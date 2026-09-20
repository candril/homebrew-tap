#!/usr/bin/env bash
# Prove a tool still starts after a dependency moved: it reports its version, and —
# where the tool has a demo mode — it paints a real frame in a detached tmux pane.
#
#   smoke.sh                   every tool in tools.json
#   smoke.sh presto riff
#   smoke.sh --built presto    the compiled binary in dist/ instead of the source entry
#
# A tool without a demo mode is only version-checked: launching it for real would talk
# to that tool's Jira, Mongo or Kafka, which a dependency bump has no business doing.
# FLEET_ROOT overrides the search for the directory that holds the checkouts.
set -euo pipefail

built=0
[ "${1:-}" = "--built" ] && { built=1; shift; }

root=${FLEET_ROOT:-}
if [ -z "$root" ]; then
  d=$PWD
  while [ "$d" != "/" ]; do
    [ -f "$d/homebrew-tap/tools.json" ] && { root=$d; break; }
    d=$(dirname "$d")
  done
fi
[ -n "$root" ] || { echo "no checkout dir found: run from inside one of the tools, or set FLEET_ROOT" >&2; exit 1; }

registry="$root/homebrew-tap/tools.json"
tools=("$@")
[ ${#tools[@]} -gt 0 ] || tools=($(jq -r 'keys[]' "$registry"))

scratch=${TMPDIR:-/tmp}/fleet-smoke
rm -rf "$scratch"; mkdir -p "$scratch"
failed=0

for tool in "${tools[@]}"; do
  repo="$root/$tool"
  [ -d "$repo" ] || { printf '%-8s SKIP   no checkout at %s\n' "$tool" "$repo"; continue; }
  entry=$(jq -r ".${tool}.entry" "$registry")
  upper=$(tr '[:lower:]' '[:upper:]' <<<"$tool")

  if [ "$built" = 1 ]; then
    cmd="$repo/dist/$tool"
    [ -x "$cmd" ] || { printf '%-8s FAIL   no binary at dist/%s — run `just build` there\n' "$tool" "$tool"; failed=1; continue; }
  else
    cmd="bun $entry"
  fi

  version=$( (cd "$repo" && $cmd --version 2>&1) | tail -1 | tr -d '\r')
  if [ -z "$version" ]; then
    printf '%-8s FAIL   --version printed nothing\n' "$tool"; failed=1; continue
  fi

  if ! grep -rqs -- '--demo' "$repo/src"; then
    printf '%-8s ok     %-12s no demo mode — frame not checked\n' "$tool" "$version"; continue
  fi

  session="fleet-smoke-$tool"
  tmux kill-session -t "$session" 2>/dev/null || true
  # The throwaway config dir keeps a smoke run from writing into the real one; the
  # trailing sleep holds the pane open after a crash so its output can be captured.
  tmux new-session -d -s "$session" -x 140 -y 42 \
    "cd '$repo' && ${upper}_CONFIG_DIR='$scratch/$tool' $cmd --demo 2>&1; sleep 60"
  sleep 4
  tmux capture-pane -t "$session" -N -p >"$scratch/$tool.txt" 2>/dev/null || true
  tmux kill-session -t "$session" 2>/dev/null || true

  lines=$(grep -cve '^[[:space:]]*$' "$scratch/$tool.txt" || true)
  if grep -qE 'error:|Error:|Cannot find|is not a function|Unhandled|at [a-zA-Z0-9_$]+ \(' "$scratch/$tool.txt"; then
    printf '%-8s FAIL   %-12s crashed on launch — %s\n' "$tool" "$version" "$scratch/$tool.txt"
    grep -m3 -E 'error:|Error:|Cannot find|is not a function|Unhandled' "$scratch/$tool.txt" | sed 's/^/           /'
    failed=1
  elif [ "$lines" -lt 3 ]; then
    printf '%-8s FAIL   %-12s blank frame (%s lines) — %s\n' "$tool" "$version" "$lines" "$scratch/$tool.txt"
    failed=1
  else
    printf '%-8s ok     %-12s frame %s lines\n' "$tool" "$version" "$lines"
  fi
done

exit $failed
