#!/usr/bin/env bash
# Pull the latest release of each tool from GitHub and regenerate releases/<tool>.json
# and Formula/<tool>.rb. Tools without a release yet are skipped. Idempotent: run it
# any time; only a new release changes a file.
#
#   scripts/update.sh            all tools in tools.json
#   scripts/update.sh presto     one tool
set -euo pipefail
cd "$(dirname "$0")/.."

tools=("$@")
[ ${#tools[@]} -gt 0 ] || tools=($(jq -r 'keys[]' tools.json))

targets=(darwin-arm64 darwin-x64 linux-arm64 linux-x64)

for tool in "${tools[@]}"; do
  tag=$(gh release view --repo "candril/${tool}" --json tagName --jq .tagName 2>/dev/null || true)
  if [ -z "$tag" ]; then
    echo "${tool}: no release yet, skipped"
    continue
  fi
  version="${tag#v}"
  sums=$(curl -fsSL "https://github.com/candril/${tool}/releases/download/${tag}/SHA256SUMS")

  json="{\"version\":\"${version}\",\"sha256\":{"
  sep=""
  for t in "${targets[@]}"; do
    sha=$(awk -v f="${tool}-${t}.gz" '$2 == f { print $1 }' <<<"$sums")
    if [ -z "$sha" ]; then
      echo "${tool} ${tag}: SHA256SUMS has no entry for ${tool}-${t}.gz" >&2
      exit 1
    fi
    json+="${sep}\"${t}\":\"${sha}\""
    sep=","
  done
  json+="}}"

  jq . <<<"$json" > "releases/${tool}.json"
  bash scripts/render-formula.sh "$tool"
done
