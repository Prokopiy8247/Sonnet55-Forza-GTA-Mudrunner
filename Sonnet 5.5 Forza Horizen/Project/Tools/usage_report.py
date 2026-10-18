"""
Token accounting for THIS Claude Code session (Section 16.2 of the task): reads only usage metadata
(message id, model, token counters, timestamps) from the session's own transcripts:
  <claude projects dir>/<project>/<sessionId>.jsonl                  (main conversation)
  <claude projects dir>/<project>/<sessionId>/subagents/**/agent-*.jsonl   (all delegated subagents / workflow agents)
Events are de-duplicated by Anthropic message id (a streamed message is written as several transcript lines carrying the
same id and the same usage block: the maximum per counter is taken). Categories are mutually exclusive:
  input_uncached = usage.input_tokens, cache_read = usage.cache_read_input_tokens,
  cache_write = usage.cache_creation_input_tokens (split into 5m / 1h when present), output = usage.output_tokens.
Thinking tokens are reported only if separately exposed (output_tokens_details.thinking_tokens) and are INCLUDED in output.
Nothing is estimated; messages without usage are counted as 'unknown'.

Usage: python Tools/usage_report.py [--json out.json]
"""
import json, os, sys, glob, collections, datetime

SESSION_ID = "6e2e1651-bde1-428b-acc7-9a6c04207475"
PROJ = r"<home>\.claude\projects\W--YouTube-Claude-Sonnet-5-5-Forza-Horizen-Sonnet55Forza-UnrealSonnet55Forza"
START = "2026-10-16T16:45:48"   # run start (UTC) from .sonnet-5.5-forza-unreal-runs/run-*-sonnet55/start_time.txt


def iter_files():
    main = os.path.join(PROJ, SESSION_ID + ".jsonl")
    if os.path.exists(main):
        yield "main", main
    for f in glob.glob(os.path.join(PROJ, SESSION_ID, "subagents", "**", "*.jsonl"), recursive=True):
        base = os.path.basename(f)
        if base.startswith("agent-"):
            yield "subagent", f


def main():
    best = {}          # message id -> (usage dict, model, kind, file, ts)
    no_usage = 0
    lines_total = 0
    for kind, f in iter_files():
        with open(f, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                lines_total += 1
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("type") != "assistant":
                    continue
                m = d.get("message") or {}
                u = m.get("usage")
                mid = m.get("id") or d.get("requestId") or d.get("uuid")
                if not u or not mid:
                    no_usage += 1
                    continue
                prev = best.get(mid)
                cur = (u, m.get("model") or d.get("requestedModel") or "unknown", kind, f, d.get("timestamp"))
                if prev is None:
                    best[mid] = cur
                else:
                    # keep the record with the larger output counter (final chunk of a streamed message)
                    if (u.get("output_tokens") or 0) >= (prev[0].get("output_tokens") or 0):
                        best[mid] = cur
    agg = collections.defaultdict(lambda: collections.Counter())
    for mid, (u, model, kind, f, ts) in best.items():
        key = (model, kind)
        a = agg[key]
        a["messages"] += 1
        a["input_uncached"] += u.get("input_tokens") or 0
        a["cache_read"] += u.get("cache_read_input_tokens") or 0
        cw = u.get("cache_creation_input_tokens") or 0
        a["cache_write"] += cw
        cc = u.get("cache_creation") or {}
        a["cache_write_5m"] += cc.get("ephemeral_5m_input_tokens") or 0
        a["cache_write_1h"] += cc.get("ephemeral_1h_input_tokens") or 0
        a["output"] += u.get("output_tokens") or 0
        det = u.get("output_tokens_details") or {}
        a["thinking_included_in_output"] += det.get("thinking_tokens") or 0
    out = {"session": SESSION_ID, "generated_utc": datetime.datetime.utcnow().isoformat(timespec="seconds"),
           "transcript_lines": lines_total, "unique_messages": len(best), "messages_without_usage": no_usage, "by_model_and_kind": {}}
    tot = collections.Counter()
    for (model, kind), a in sorted(agg.items()):
        out["by_model_and_kind"][model + " | " + kind] = dict(a)
        for k, v in a.items():
            tot[(model, k)] += v
    by_model = collections.defaultdict(collections.Counter)
    for (model, k), v in tot.items():
        by_model[model][k] += v
    out["by_model"] = {m: dict(c) for m, c in by_model.items()}
    grand = collections.Counter()
    for m, c in by_model.items():
        for k, v in c.items():
            grand[k] += v
    grand["deduplicated_total_tokens"] = grand["input_uncached"] + grand["cache_read"] + grand["cache_write"] + grand["output"]
    out["grand_total"] = dict(grand)
    txt = json.dumps(out, indent=2)
    print(txt)
    if len(sys.argv) > 2 and sys.argv[1] == "--json":
        open(sys.argv[2], "w", encoding="utf-8").write(txt)


if __name__ == "__main__":
    main()
