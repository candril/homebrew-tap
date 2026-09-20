#!/usr/bin/env bash
# What is outdated across the five tool checkouts, and where they disagree with each
# other. Two sections: `bun outdated` per checkout, then the declared version of every
# shared dependency side by side — the second is the one that catches a tool drifting
# away from its siblings, which `bun outdated` cannot see because each repo is current
# against npm on its own terms.
#
#   survey.sh                  every tool in tools.json
#   survey.sh presto riff      some of them
#
# FLEET_ROOT overrides the search for the directory that holds the checkouts.
set -euo pipefail

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

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# `bun outdated` draws an ASCII table; the package cell carries a (dev)/(peer) suffix.
parse() {
  awk -F'|' -v tool="$1" -v loc="$2" '
    NF < 5 { next }
    {
      for (i = 2; i <= 5; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == "Package" || $2 ~ /^-+$/ || $2 == "") next
      kind = "prod"
      if (match($2, /\((dev|peer)\)$/)) { kind = substr($2, RSTART + 1, RLENGTH - 2); sub(/ *\((dev|peer)\)$/, "", $2) }
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", tool, loc, $2, kind, $3, $4, $5
    }'
}

echo "# outdated"
printf '%-8s %-6s %-34s %-6s %-12s %-12s %s\n' tool where package kind current update latest
for tool in "${tools[@]}"; do
  for loc in . site; do
    dir="$root/$tool/$loc"
    [ -f "$dir/package.json" ] || continue
    if [ ! -d "$dir/node_modules" ]; then
      printf '%-8s %-6s %s\n' "$tool" "$loc" "(no node_modules — run bun install there first)"
      continue
    fi
    (cd "$dir" && bun outdated 2>/dev/null) | parse "$tool" "$loc" >>"$scratch/outdated"
  done
done
if [ -s "$scratch/outdated" ]; then
  while IFS=$'\t' read -r tool loc pkg kind cur upd lat; do
    printf '%-8s %-6s %-34s %-6s %-12s %-12s %s\n' "$tool" "$loc" "$pkg" "$kind" "$cur" "$upd" "$lat"
  done <"$scratch/outdated"
else
  echo "(everything current against npm)"
fi

# Declared ranges, so a tool pinned to an older line than its siblings shows up even
# when npm has nothing newer to offer it.
for tool in "${tools[@]}"; do
  for loc in . site; do
    f="$root/$tool/$loc/package.json"
    [ -f "$f" ] || continue
    key=$([ "$loc" = "." ] && echo "" || echo "site:")
    jq -r --arg tool "$tool" --arg key "$key" '
      [.dependencies // {}, .devDependencies // {}, .peerDependencies // {}]
      | add // {} | to_entries[] | "\($tool)\t\($key)\(.key)\t\(.value)"' "$f"
  done
done >"$scratch/declared"

echo
echo "# declared, side by side (! = the five disagree)"
printf '%-2s %-34s' "" "package"
for tool in "${tools[@]}"; do printf '%-14s' "$tool"; done
echo
awk -F'\t' -v list="$(IFS=' '; echo "${tools[*]}")" '
  BEGIN { n = split(list, T, " ") }
  { v[$2 SUBSEP $1] = $3; pkg[$2] = 1 }
  END {
    for (p in pkg) {
      line = ""; distinct = 0; delete seen
      for (i = 1; i <= n; i++) {
        val = ((p SUBSEP T[i]) in v) ? v[p SUBSEP T[i]] : "-"
        line = line sprintf("%-14s", val)
        if (val != "-" && !(val in seen)) { seen[val] = 1; distinct++ }
      }
      printf "%s\t%-2s %-34s%s\n", (distinct > 1 ? 0 : 1), (distinct > 1 ? "!" : ""), p, line
    }
  }' "$scratch/declared" | sort -k1,1 -k2,2 | cut -f2-
