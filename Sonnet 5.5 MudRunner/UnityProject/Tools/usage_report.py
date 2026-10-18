"""Token + API-equivalent cost accounting for THIS Claude Code session (python -I Tools/usage_report.py [--json]).

Sources (only usage metadata is read; no message text is printed or copied):
  <projects>/<sanitised cwd>/<session id>.jsonl                       main conversation
  <projects>/<sanitised cwd>/<session id>/subagents/**/agent-*.jsonl  Agent-tool and Workflow subagents (their own model)
Events are de-duplicated by (message id, request id) - streaming writes the same message several times, we keep the LAST record
(final usage). Categories are mutually exclusive as reported by the API:
  input_tokens (uncached) | cache_read_input_tokens | cache_creation_input_tokens (split 5m / 1h when reported) | output_tokens
  thinking tokens are reported inside output_tokens (output_tokens_details.thinking_tokens) - shown separately, NOT added again.
A missing counter is 'unknown', never zero. Cost = token-only, standard API pricing of the model each record names.
"""
import glob
import json
import os
import sys
from collections import defaultdict

SESSION = "3bbf66bb-50d0-4331-97ea-9e4f6f39f0b8"
PROJ_DIR = os.path.expanduser(r"~\.claude\projects\W--YouTube-Claude-Sonnet-5-5-MudRunner-UnitySonnet5-5MudRunner")

# USD per million tokens (https://platform.claude.com/docs/en/about-claude/pricing, verified 2026-10-16)
PRICES = {
    "claude-sonnet-5-5": dict(inp=2.0, cw5=2.5, cw1h=4.0, cr=0.10, out=10.0),
    "claude-sonnet-5": dict(inp=2.0, cw5=2.5, cw1h=4.0, cr=0.20, out=10.0),
    "claude-opus-5-5": None,   # filled below if encountered
    "claude-haiku-5-5": None,
    "claude-fable-5-1": dict(inp=10.0, cw5=12.5, cw1h=20.0, cr=0.25, out=50.0),
}


def load(path):
    recs = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"usage"' not in line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            m = o.get("message") if isinstance(o, dict) else None
            if not isinstance(m, dict) or "usage" not in m:
                continue
            key = (m.get("id"), o.get("requestId"))
            if key[0] is None:
                key = (o.get("uuid"), None)
            recs[key] = (m.get("model", "unknown"), m["usage"], o.get("timestamp"))
    return recs


def main():
    files = [os.path.join(PROJ_DIR, SESSION + ".jsonl")]
    files += glob.glob(os.path.join(PROJ_DIR, SESSION, "**", "*.jsonl"), recursive=True)
    groups = defaultdict(lambda: defaultdict(float))
    seen = set()
    first_ts = last_ts = None
    unknown = defaultdict(int)
    for fp in files:
        part = "main" if fp.endswith(SESSION + ".jsonl") else "subagent"
        for key, (model, u, ts) in load(fp).items():
            gk = (part, key)
            if gk in seen:
                continue
            seen.add(gk)
            if ts:
                first_ts = ts if first_ts is None or ts < first_ts else first_ts
                last_ts = ts if last_ts is None or ts > last_ts else last_ts
            g = groups[(part, model)]
            g["requests"] += 1
            for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"):
                if k in u and u[k] is not None:
                    g[k] += u[k]
                else:
                    unknown[k] += 1
            cc = u.get("cache_creation") or {}
            if cc:
                g["cw5"] += cc.get("ephemeral_5m_input_tokens", 0) or 0
                g["cw1h"] += cc.get("ephemeral_1h_input_tokens", 0) or 0
            else:
                g["cw_unsplit"] += u.get("cache_creation_input_tokens", 0) or 0
            det = u.get("output_tokens_details") or {}
            if "thinking_tokens" in det:
                g["thinking"] += det["thinking_tokens"] or 0
                g["thinking_known"] += 1

    out = {"first_event": first_ts, "last_event": last_ts, "groups": [], "unknown_counters": dict(unknown)}
    tot = defaultdict(float)
    total_cost = 0.0
    cost_known = True
    for (part, model), g in sorted(groups.items()):
        pr = PRICES.get(model)
        cost = None
        if pr:
            cw5 = g.get("cw5", 0); cw1h = g.get("cw1h", 0); unsplit = g.get("cw_unsplit", 0)
            cost = (g["input_tokens"] * pr["inp"] + g["cache_read_input_tokens"] * pr["cr"] + g["output_tokens"] * pr["out"]
                    + cw5 * pr["cw5"] + cw1h * pr["cw1h"] + unsplit * pr["cw5"]) / 1e6
            total_cost += cost
        else:
            cost_known = False
        for k, v in g.items():
            tot[k] += v
        out["groups"].append({"part": part, "model": model, "requests": int(g["requests"]), "uncached_input": int(g["input_tokens"]),
                              "cache_read": int(g["cache_read_input_tokens"]), "cache_write_total": int(g["cache_creation_input_tokens"]),
                              "cache_write_5m": int(g.get("cw5", 0)), "cache_write_1h": int(g.get("cw1h", 0)), "cache_write_unsplit": int(g.get("cw_unsplit", 0)),
                              "output": int(g["output_tokens"]), "thinking_included_in_output": int(g.get("thinking", 0)), "cost_usd": cost})
    out["total"] = {"requests": int(tot["requests"]), "uncached_input": int(tot["input_tokens"]), "cache_read": int(tot["cache_read_input_tokens"]),
                    "cache_write": int(tot["cache_creation_input_tokens"]), "output": int(tot["output_tokens"]),
                    "thinking_included_in_output": int(tot.get("thinking", 0)),
                    "dedup_total_tokens": int(tot["input_tokens"] + tot["cache_read_input_tokens"] + tot["cache_creation_input_tokens"] + tot["output_tokens"]),
                    "cost_usd": total_cost if cost_known else None}
    if "--json" in sys.argv:
        print(json.dumps(out, indent=2))
        return
    print("events: %s .. %s" % (first_ts, last_ts))
    for g in out["groups"]:
        print("%-9s %-20s req=%-6d in=%-10d cacheR=%-12d cacheW=%-10d (5m %d / 1h %d / unsplit %d) out=%-9d (thinking %d) cost=$%s" % (
            g["part"], g["model"], g["requests"], g["uncached_input"], g["cache_read"], g["cache_write_total"], g["cache_write_5m"], g["cache_write_1h"],
            g["cache_write_unsplit"], g["output"], g["thinking_included_in_output"], "%.2f" % g["cost_usd"] if g["cost_usd"] is not None else "unknown"))
    t = out["total"]
    print("TOTAL req=%d uncached_in=%d cache_read=%d cache_write=%d output=%d (thinking %d inside output) all=%d cost=$%s" % (
        t["requests"], t["uncached_input"], t["cache_read"], t["cache_write"], t["output"], t["thinking_included_in_output"], t["dedup_total_tokens"],
        "%.2f" % t["cost_usd"] if t["cost_usd"] is not None else "unknown"))
    if unknown:
        print("counters missing in some records (unknown, not zero):", dict(unknown))


main()
