#!/usr/bin/env bash
# Stamp the templates with a tool's name and copy them into its checkout, which is
# expected as a sibling directory (../<tool>). Drift between the five repos then shows
# up as a diff here instead of having to be noticed.
#
#   scripts/sync.sh              every tool in tools.json
#   scripts/sync.sh presto riff  some of them
set -euo pipefail
cd "$(dirname "$0")/.."

tools=("$@")
[ ${#tools[@]} -gt 0 ] || tools=($(jq -r 'keys[]' tools.json))

# template path → destination inside the tool repo
files=(
  "install.sh:scripts/install.sh"
  "build.ts:scripts/build.ts"
  "release.yml:.github/workflows/release.yml"
  "deploy-site.yml:.github/workflows/deploy-site.yml"
  "site-ci.yml:.github/workflows/site-ci.yml"
  "Footer.astro:site/src/components/Footer.astro"
  "flake.nix:flake.nix"
  "renovate.json:renovate.json"
)
# written only when the tool has none yet: the file is the tool's, not the template's
seed=(
  "version.ts:src/version.ts"
)

stamp() {
  local tool="$1" src="$2" dest="$3"
  local upper entry desc runtime floor
  upper=$(tr '[:lower:]' '[:upper:]' <<<"$tool")
  entry=$(jq -r ".${tool}.entry" tools.json)
  desc=$(jq -r ".${tool}.desc" tools.json)
  floor=$(jq -r ".${tool}.bun_floor" tools.json)
  runtime=$(jq -r ".${tool}.nix_runtime | map(\"\\\"\" + . + \"\\\"\") | join(\" \")" tools.json)
  mkdir -p "$(dirname "$dest")"
  sed -e "s|{{tool}}|${tool}|g" -e "s|{{TOOL}}|${upper}|g" -e "s|{{entry}}|${entry}|g" \
    -e "s|{{desc}}|${desc}|g" -e "s|{{nix_runtime}}|${runtime}|g" \
    -e "s|{{bun_floor}}|${floor}|g" \
    "templates/${src}" > "$dest"
  [ "${src##*.}" = "sh" ] && chmod +x "$dest"
  echo "  ${dest#../}"
}

for tool in "${tools[@]}"; do
  repo="../${tool}"
  [ -d "$repo" ] || { echo "${tool}: no checkout at ${repo}, skipped"; continue; }
  echo "${tool}:"
  for f in "${files[@]}"; do
    stamp "$tool" "${f%%:*}" "${repo}/${f#*:}"
  done
  for f in "${seed[@]}"; do
    [ -f "${repo}/${f#*:}" ] || stamp "$tool" "${f%%:*}" "${repo}/${f#*:}"
  done
done
