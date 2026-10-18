#!/usr/bin/env bash
# Unity batch-mode runner with a project-wide mutex and filtered output (compile loop / editor scripts / tests).
#   Tools/ub.sh <logname> <Namespace.Class.Method | -> [extra Unity args...]
# Env: GFX=1   -> run WITH graphics (no -nographics) so rendering/screenshots work
#      NOQUIT=1 -> do not pass -quit (e.g. when -runTests quits by itself)
#      MAXLINES -> max "[MudRunner" log lines printed (default 80)
# Only one Unity process can open the project, so every run takes Logs/cli/.unity.lock (mkdir mutex, stale-safe).
# Prints: exit code, compile errors (error CS...), exceptions, and any "[MudRunner" lines.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PROJ="$(cygpath -w "$ROOT")"
UNITY="/c/Program Files/Unity/Hub/Editor/6000.6.0f1/Editor/Unity.exe"
NAME="${1:?logname}"; METHOD="${2:--}"; shift 2 || true
mkdir -p "$ROOT/Logs/cli"
LOCK="$ROOT/Logs/cli/.unity.lock"

# ---- acquire mutex (wait up to 60 min). Owner = WINDOWS pid of this bash (MSYS pids are not comparable across sessions);
#      a lock is stale only if its owner process no longer exists AND it is older than 20 s, or if it is older than 40 min.
alive() { [ -n "$1" ] && tasklist //FI "PID eq $1" //NH 2>/dev/null | grep -q " $1 "; }
MYPID="$(cat /proc/$$/winpid 2>/dev/null || echo $$)"
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  owner="$(cat "$LOCK/owner" 2>/dev/null || true)"
  age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  if [ -n "$owner" ] && ! alive "$owner" && [ "$age" -gt 20 ]; then echo "== stale lock (owner $owner gone) - taking over"; rm -rf "$LOCK"; continue; fi
  if [ "$age" -gt 2400 ]; then rm -rf "$LOCK"; continue; fi
  [ $((waited % 60)) -eq 0 ] && echo "== waiting for Unity lock (held by win-pid ${owner:-?}, age ${age}s)..."
  sleep 3; waited=$((waited+3))
  [ "$waited" -gt 3600 ] && { echo "== gave up waiting for the Unity lock"; exit 99; }
done
echo "$MYPID" > "$LOCK/owner"
trap 'rm -rf "$LOCK"' EXIT

# ---- also wait while some other editor process (started outside this script) still has the project open
busy() { powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='Unity.exe'\" | Where-Object { \$_.CommandLine -like '*UnitySonnet5.5MudRunner*' -and \$_.CommandLine -notlike '*-adb2*' }).Count" 2>/dev/null | tr -d '
' | grep -qE '^[1-9]'; }
w2=0
while busy; do
  [ $((w2 % 60)) -eq 0 ] && echo "== another Unity editor has the project open; waiting..."
  sleep 5; w2=$((w2+5)); [ "$w2" -gt 3600 ] && { echo "== gave up waiting for the other Unity editor"; exit 98; }
done

LOG="$PROJ\\Logs\\cli\\$NAME.log"
ARGS=(-batchmode -projectPath "$PROJ" -logFile "$LOG")
[ "${GFX:-0}" = "1" ] || ARGS+=(-nographics)
[ "$METHOD" = "-" ] || ARGS+=(-executeMethod "$METHOD")
[ "${NOQUIT:-0}" = "1" ] || ARGS+=(-quit)
[ "${NOBURST:-0}" = "1" ] && ARGS+=(-burst-disable-compilation)
# run Unity under a watchdog: no single run may hold the shared project longer than UB_TIMEOUT seconds (default 1500)
"$UNITY" "${ARGS[@]}" "$@" &
UPID=$!
UWIN="$(cat /proc/$UPID/winpid 2>/dev/null || echo $UPID)"
START=$(date +%s)
while kill -0 "$UPID" 2>/dev/null; do
  if [ $(( $(date +%s) - START )) -gt "${UB_TIMEOUT:-1500}" ]; then
    echo "== WATCHDOG: Unity run exceeded ${UB_TIMEOUT:-1500}s - killing it (win-pid $UWIN)"
    taskkill //F //T //PID "$UWIN" >/dev/null 2>&1; sleep 2; break
  fi
  sleep 3
done
wait "$UPID" 2>/dev/null
CODE=$?
echo "== unity exit code: $CODE  (log: Logs/cli/$NAME.log)"
LOGF="$ROOT/Logs/cli/$NAME.log"
if [ -f "$LOGF" ]; then
  echo "== compile errors:"
  grep -aE "error CS[0-9]+|: error |Compilation failed|Scripts have compiler errors|Shader error|error: " "$LOGF" | sort -u | head -60
  echo "== exceptions / asserts:"
  grep -aE "^[A-Za-z.]*Exception|NullReferenceException|Assertion failed|Unhandled exception" "$LOGF" | sort -u | head -30
  echo "== MudRunner lines:"
  grep -a "\[MudRunner" "$LOGF" | head -${MAXLINES:-80}
fi
exit $CODE
