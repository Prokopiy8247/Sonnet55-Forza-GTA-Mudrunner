#!/usr/bin/env bash
# Re-run a Unity wrapper command while the ONLY problem is compile errors (other workers editing the shared tree mid-way).
#   Tools/retry.sh [-n attempts] [-s seconds] <command...>     e.g.  Tools/retry.sh -n 10 Tools/rt.sh name Filter
N=8; S=60
while [ "${1:-}" = "-n" ] || [ "${1:-}" = "-s" ]; do
  [ "$1" = "-n" ] && N="$2"; [ "$1" = "-s" ] && S="$2"; shift 2
done
TMP="$(mktemp)"
for i in $(seq 1 "$N"); do
  "$@" 2>&1 | tee "$TMP"
  CODE=${PIPESTATUS[0]}
  if grep -qE "Scripts have compiler errors|Failed to acquire global mutex|another Unity instance|Another instance of Unity|Aborting batchmode due to fatal error" "$TMP"; then
    echo "== transient failure (compile errors from another worker mid-edit, or a Unity instance/licence-client clash) (attempt $i/$N) - retrying in ${S}s"
    sleep "$S"; continue
  fi
  rm -f "$TMP"; exit $CODE
done
rm -f "$TMP"; echo "== gave up after $N attempts"; exit 97
