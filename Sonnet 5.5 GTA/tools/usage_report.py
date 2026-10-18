#!/usr/bin/env python3
"""
usage_report.py - exact token accounting from Claude Code / Claude Agent SDK session transcripts (JSONL).

Usage:
  python -I tools/usage_report.py --project-dir "<~/.claude/projects/<mangled-project>>" \
      --session 9630d360-dbea-4514-865b-fe30e8b74a28 [--session 0149c506-...] [--since ISO] [--until ISO] \
      [--rates rates.json] [--json out.json]

How it counts (Section 58 of the task prompt):
  * Every assistant transcript line carries message.usage for ONE API request; a request can be written on several lines
    (one per content block), so lines are de-duplicated by message.id / requestId and the MAXIMUM of each counter is kept.
  * Categories are mutually exclusive as exposed by the Anthropic Messages API usage object:
      input_tokens                 uncached input
      cache_read_input_tokens      cache hits
      cache_creation_input_tokens  cache writes (split into ephemeral_5m / ephemeral_1h when present)
      output_tokens                output incl. thinking tokens (output_tokens_details.thinking_tokens is a SUBSET, never added again)
  * Sub-agent transcripts (<session>/subagents/**/agent-*.jsonl, incl. workflow agents) are counted once, in their own file,
    and reported separately from the parent session. A missing counter is reported as unknown (None), not zero.
  * Cost = sum(category_tokens * rate_per_million) / 1e6, with rates given via --rates (JSON), per model id.
"""
import argparse
import glob
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def iter_files(project_dir, session):
    main = os.path.join(project_dir, session + ".jsonl")
    if os.path.exists(main):
        yield main, "main"
    sub_root = os.path.join(project_dir, session, "subagents")
    for path in sorted(glob.glob(os.path.join(sub_root, "**", "*.jsonl"), recursive=True)):
        if os.path.basename(path) == "journal.jsonl":
            continue
        yield path, "subagent"


def scan(path, since, until):
    """Return dict request_id -> record (max counters) for one transcript file."""
    reqs = {}
    last_ts = None
    with open(path, "r", encoding="utf8", errors="replace") as fh:
        for line in fh:
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            msg = d.get("message") or {}
            u = msg.get("usage")
            if not u:
                continue
            ts = parse_ts(d.get("timestamp"))
            if since and ts and ts < since:
                continue
            if until and ts and ts > until:
                continue
            key = msg.get("id") or d.get("requestId") or d.get("uuid")
            r = reqs.setdefault(key, dict(model=msg.get("model") or d.get("requestedModel"), ts=ts, inp=0, cr=0, cw=0, cw5=0, cw1=0, out=0, think=0,
                                          has_cw_split=False, speed=u.get("speed"), tier=u.get("service_tier"),
                                          sidechain=bool(d.get("isSidechain"))))
            r["inp"] = max(r["inp"], u.get("input_tokens") or 0)
            r["cr"] = max(r["cr"], u.get("cache_read_input_tokens") or 0)
            r["cw"] = max(r["cw"], u.get("cache_creation_input_tokens") or 0)
            cc = u.get("cache_creation") or {}
            if cc:
                r["has_cw_split"] = True
                r["cw5"] = max(r["cw5"], cc.get("ephemeral_5m_input_tokens") or 0)
                r["cw1"] = max(r["cw1"], cc.get("ephemeral_1h_input_tokens") or 0)
            r["out"] = max(r["out"], u.get("output_tokens") or 0)
            td = u.get("output_tokens_details") or {}
            r["think"] = max(r["think"], td.get("thinking_tokens") or 0)
            if ts and (r["ts"] is None or ts > r["ts"]):
                r["ts"] = ts
            if ts and (last_ts is None or ts > last_ts):
                last_ts = ts
    return reqs, last_ts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-dir", required=True)
    ap.add_argument("--session", action="append", required=True)
    ap.add_argument("--since")
    ap.add_argument("--until")
    ap.add_argument("--rates", help="JSON: {model_id: {input, output, cache_read, cache_write_5m, cache_write_1h}} USD per million")
    ap.add_argument("--json")
    a = ap.parse_args()
    since, until = parse_ts(a.since), parse_ts(a.until)

    rates = json.load(open(a.rates, encoding="utf8")) if a.rates else {}
    totals = defaultdict(lambda: defaultdict(int))     # key: (session, kind, model)
    req_counts = defaultdict(int)
    seen = set()
    cutoff = None
    files = 0
    for session in a.session:
        for path, kind in iter_files(a.project_dir, session):
            files += 1
            reqs, last_ts = scan(path, since, until)
            if last_ts and (cutoff is None or last_ts > cutoff):
                cutoff = last_ts
            for rid, r in reqs.items():
                if rid in seen:
                    continue            # same API request seen twice (e.g. copied into a parent transcript)
                seen.add(rid)
                k = (session, kind, r["model"] or "unknown")
                t = totals[k]
                t["input"] += r["inp"]
                t["cache_read"] += r["cr"]
                t["cache_write"] += r["cw"]
                if r["has_cw_split"]:
                    t["cache_write_5m"] += r["cw5"]
                    t["cache_write_1h"] += r["cw1"]
                else:
                    t["cache_write_unsplit"] += r["cw"]
                t["output"] += r["out"]
                t["thinking_subset_of_output"] += r["think"]
                t["requests"] += 1
                req_counts[k] += 1

    grand = defaultdict(int)
    cost_by_model = defaultdict(float)
    rows = []
    for (session, kind, model), t in sorted(totals.items()):
        row = dict(session=session, kind=kind, model=model, **{k: v for k, v in t.items()})
        if model in rates:
            r = rates[model]
            c = (t["input"] * r["input"] + t["output"] * r["output"] + t["cache_read"] * r["cache_read"]
                 + t.get("cache_write_5m", 0) * r["cache_write_5m"] + t.get("cache_write_1h", 0) * r["cache_write_1h"]
                 + t.get("cache_write_unsplit", 0) * r["cache_write_5m"]) / 1e6
            row["cost_usd"] = round(c, 4)
            cost_by_model[model] += c
        rows.append(row)
        for k in ("input", "cache_read", "cache_write", "output", "thinking_subset_of_output", "requests", "cache_write_5m", "cache_write_1h", "cache_write_unsplit"):
            grand[k] += t.get(k, 0)

    result = dict(files=files, observation_cutoff=cutoff.isoformat() if cutoff else None,
                  rows=rows, grand_total=dict(grand),
                  dedup_total_tokens=grand["input"] + grand["cache_read"] + grand["cache_write"] + grand["output"],
                  cost_by_model={m: round(v, 4) for m, v in cost_by_model.items()},
                  cost_total_usd=round(sum(cost_by_model.values()), 4) if cost_by_model else None)
    print(json.dumps(result, indent=2, default=str))
    if a.json:
        with open(a.json, "w", encoding="utf8") as fh:
            json.dump(result, fh, indent=2, default=str)


if __name__ == "__main__":
    main()
