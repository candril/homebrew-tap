---
name: fleet-deps
description: Update dependencies across the five candril terminal tools — lane, monq, presto, riff, topiq — as one fleet rather than five repos. Trigger on "update the deps", "what's outdated", "bump <package>", "is the fleet aligned", an OpenTUI or TypeScript upgrade, or /fleet-deps from any of the checkouts.
user-invocable: true
---

# Dependencies across the five tools

There is no Renovate on these repos. This skill is the only thing that moves a version in
them, so a bump nobody makes here does not get made.

It works the **fleet**, not the repo the session happens to be sitting in. The five share a
stack — OpenTUI, React, TypeScript, oxlint, oxfmt, and the Astro docs site — and they are
only cheap to maintain while they carry the same versions of it. A bump is therefore one
package moving in up to five repos, with its changelog read **once** and five verifications
run. riff is the standing proof of what the other shape costs: it sat on `@opentui/core`
0.1.81 while its four siblings ran 0.5.11.

## The fleet

`homebrew-tap/tools.json` is the registry; each tool is a sibling checkout next to it
(`../lane`, `../monq`, …). Both scripts here find that directory by walking up from the
working directory, or take it from `FLEET_ROOT`. They ship beside this file, so reach them
through the plugin root — everything below assumes:

```sh
fleet="$CLAUDE_PLUGIN_ROOT/skills/fleet-deps/scripts"
```
 A tool with no checkout is skipped and
said out loud — never silently.

## Iron rules

- **Never push and never open a PR.** Land described jj changes in each repo and stop. The
  push is a separate thing the user asks for, every time.
- **One package across five repos, not five packages in one repo.** The reading is the
  expensive part and it is per package; the verification is per repo.
- **Nothing lands unverified.** Every repo that gets a bump runs the gate below. A repo
  whose gate fails is reverted with `jj abandon`, not left half-bumped while the others go
  green.
- **`bun.lock` is written by `bun install`.** Never edit it, never copy one between repos.
- **The range style is the repo's.** `~0.67.0` in lane and `^0.67.0` in monq is a finding
  to report, not something to quietly normalise inside an unrelated bump.
- **A 0.x minor is a migration, not a bump.** Pre-1.0 packages break on minors, and all
  five apps are built on one of them. Read the release notes before editing a version.
- **Skip a repo whose working copy holds unrelated changes.** Say which and why; do not
  fold a dependency bump into somebody's in-flight work.

## Pass A — survey

```sh
"$fleet/survey.sh"                # all five, plus each site/
"$fleet/survey.sh" presto riff
```

Two sections. The first is `bun outdated` per checkout. The second lists every declared
range side by side and marks with `!` the packages where the five disagree — the thing
`bun outdated` structurally cannot see, because a repo pinned to an old line is perfectly
current against npm on its own terms.

Read the second section first. A `-` is not automatically a gap: riff has no React because
it has no React, and only monq has `mongodb`. A gap worth reporting is a *shared* tool
missing from a repo that should have it — today presto and riff carry no oxlint or oxfmt
while the other three do.

## Pass B — classify

Sort what the survey found into three, and say which bucket each package landed in before
touching anything:

- **Routine** — patch and minor on 1.x-and-up packages, `@types/*`, lint and format
  tooling. Bump across the fleet in one group.
- **Migration** — any major, any 0.x minor, and anything in the OpenTUI / React / Astro
  stack regardless of how small the number looks. Read the upstream release notes, name
  the breaking changes, then decide. `typescript` 5 → 7 is this, and so is the docs site's
  Astro 5 → 7.
- **Catch-up** — a tool behind its siblings on a shared package. Bring it to where they
  are, not to latest, unless the fleet is moving too.

## Pass C — apply

Per group, never per repo:

1. **Read once.** `gh release view` on the package's repo, or its CHANGELOG. For a
   migration, write down what actually breaks before editing a `package.json`.
2. **Pilot.** Run the group in the repo where the package is least load-bearing first.
   What breaks there is what will break in the other four, and it is cheaper to learn it
   once.
3. **Land.** In each repo: `jj st` (dirty with unrelated work → skip and report),
   `jj new -m "deps: <package> <from> → <to>"`, edit the range, `bun install`, run the
   gate.
4. **Gate fails** → fix it if the fix is in the migration's scope, otherwise `jj abandon`
   that repo's change and report the group as blocked. A migration half-applied across the
   fleet is worse than one not started.
5. **Describe honestly.** The change message says what moved and the reason it mattered —
   the changelog line, the API that changed. Not "bump deps".

## The gate

Every repo that takes a bump, in order:

```sh
just typecheck
just test
just build
```

then, from anywhere in the fleet:

```sh
"$fleet/smoke.sh" <tool>           # source entry
"$fleet/smoke.sh" --built <tool>   # the dist/ binary, after just build
```

`smoke.sh` checks that the tool reports its version and, where the tool has a demo mode,
that it paints a real frame in a detached tmux pane instead of dying on launch — the
failure a typecheck cannot see, because a broken OpenTUI render is type-correct.

All five have a demo mode, so all five get a frame: `--demo` in monq, presto, riff and
topiq, and `--mock`/`--demo` in lane. A tool `smoke.sh` cannot launch that way falls back
to a version check, and the report says so rather than implying a frame was seen. lane,
monq and topiq also have `just lint` and `just fmt`; run them where they exist.

## Pass D — report

What moved, in which repos, with the reason. Then, separately and without softening:
what was skipped and why — a blocked migration, a dirty working copy, a tool whose frame
could not be checked. End with the fleet-alignment table from Pass A as it stands *after*
the run, and stop. The push is the user's call.
