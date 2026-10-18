#!/bin/bash
# usage: cars_submit.sh <script.py> "<JOB_ARGS>"   - drops a job file straight into the shared editor server inbox (no waiting)
cd "$(dirname "$0")/../.." || exit 1
name="$(date +%H%M%S)_$(printf '%03d' $((RANDOM % 1000)))_$(basename "$1")"
{ printf "JOB_ARGS = r'''%s'''\n" "$2"; cat "$1"; } > "Saved/MatJobs/inbox/${name}.tmp" && mv "Saved/MatJobs/inbox/${name}.tmp" "Saved/MatJobs/inbox/${name}" && echo "queued ${name}"
