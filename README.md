# candril/homebrew-tap

Distribution for five terminal tools — [lane](https://candril.github.io/lane/) (Jira),
[monq](https://candril.github.io/monq/) (MongoDB), [presto](https://candril.github.io/presto/)
(pull requests), [riff](https://candril.github.io/riff/) (code review) and
[topiq](https://candril.github.io/topiq/) (Kafka) — plus the templates that keep their five
repositories identical where they should be.

Every route installs the same binary: the one attached to the tool's GitHub release, verified
against that release's `SHA256SUMS`.

## Install

```sh
brew install candril/tap/presto            # Homebrew, macOS and Linux
nix run github:candril/presto              # Nix — `nix profile install` to keep it
nix run github:candril/homebrew-tap#presto # …or straight from here
curl -fsSL https://raw.githubusercontent.com/candril/presto/main/scripts/install.sh | bash
```

Swap `presto` for `lane`, `monq`, `riff` or `topiq`.

## How a release gets here

1. A tool's `just release 0.2.0` checks `package.json` and `CHANGELOG.md` against the version
   and tags `v0.2.0`; pushing the tag runs the tool's release workflow, which builds one binary
   per platform *on* that platform, checks that it reports the tag, and publishes the release
   with `SHA256SUMS`.
2. [`update.yml`](.github/workflows/update.yml) here runs hourly (or at once, when the tool's
   workflow has a `TAP_TOKEN` to nudge it with) and runs [`scripts/update.sh`](scripts/update.sh):
   for each tool it reads the latest release, writes `releases/<tool>.json` (version + four
   checksums) and renders `Formula/<tool>.rb` from it.
3. [`flake.nix`](flake.nix) reads the same JSON at evaluation time, so Nix needs no edit at all.
   Each tool repo carries a thin `flake.nix` that re-exports its package from here, with no lock
   file, so `nix run github:candril/<tool>` always resolves the latest release.

## Templates

[`templates/`](templates/) holds the files that are the same in every tool repo except for the
tool's name: the installer, the build script, the release and site workflows, the docs-site
footer that links the siblings, the thin flake, and the version module. `scripts/sync.sh`
stamps the name in and copies them into `../<tool>`; a diff in a tool repo after running it is
drift.

```sh
scripts/sync.sh              # all five (expects them as sibling checkouts)
scripts/sync.sh presto riff
scripts/update.sh            # refresh releases/ and Formula/ from GitHub, locally
```

`tools.json` is the registry: description, homepage, entry file, Homebrew dependencies and the
runtime tools Nix wraps onto the binary's `PATH`.
