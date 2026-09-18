---
name: bump-version-minor
description: >
  Cut a yahoo-finance minor release: bump version-minor in the ASDF
  system, date CHANGELOG, annotated git tag, push to GitHub. Use when
  the user asks to tag, cut, or bump the minor version, "tag it as
  v0.N.0 as previous", or runs /bump-version-minor.
---

# Bump minor version

Cut `vMAJOR.(MINOR+1).0` for this library only when the user explicitly
asked to cut/tag/bump. Mirror the limbic.fi ritual: dated changelog,
annotated tag, push. `v0.1.0` was a lightweight tag (`git cat-file -t`
is `commit`); later tags must be annotated so `git describe` sees them.

## Version number

Read `version-major`, `version-minor`, `version-revision` from
`yahoo-finance.asd` (package `yahoo-finance/system`).

- New version: `MAJOR` unchanged, `MINOR+1`, revision `0`.
- Tag name: `vMAJOR.MINOR.0` (example: asd `0.1.0` → cut `v0.2.0`).

Working tree must be clean except the files this skill edits. Do not
mix other changes into the version commit. If the tree is dirty with
unrelated files, stop.

If `git rev-parse vMAJOR.MINOR.0` already exists, stop.

## Date

Use the session's current date as `Month D AD YYYY` with a full English
month name and no leading zero on the day, e.g. `September 18 AD 2026`.

Message for the commit and the annotated tag:

```
Yahoo Finance vMAJOR.MINOR.0 - Month D AD YYYY
```

## Files

1. `yahoo-finance.asd` — set `version-minor` / `version-revision`. The
   `:version` form already uses `(version-string)`.
2. `documentation/yahoo-finance-package.latex` — the sentence
   `This is version \texttt{X.Y.Z}.` under **Version**.
3. `CHANGELOG.md` — under the current `AD YYYY` heading, the unreleased
   `## vMAJOR.MINOR.0` line becomes `## vMAJOR.MINOR.0 - Month D AD YYYY`.
   If that heading is missing, insert it at the top of the year section
   (keep existing bullets; do not invent changelog text). If the file
   does not exist, create `# AD YYYY` plus that dated heading only.
4. `AGENTS.md` — if it exists and names an unreleased `vX.Y.Z`, advance
   that pair to `vMAJOR.(MINOR+1).0`. Skip if the file is absent.

There is no separate sigma version test today. If a
`behavior 'version-string` (or equivalent) appears later, update it to
`(MAJOR MINOR 0)` and `"MAJOR.MINOR.0"`.

## Verify, commit, tag, push

Do **not** set `YAHOO_FINANCE_LIVE_TESTS`. Offline specs only:

```bash
sbcl --non-interactive --eval '(pushnew #P"/ABS/PATH/TO/yahoo-finance/" asdf:*central-registry*)' --eval '(asdf:test-system :yahoo-finance)'
```

Must exit 0. Then commit only the files this skill changed, create an
**annotated** tag, and push the branch and tag:

```bash
git tag -a vMAJOR.MINOR.0 -m "Yahoo Finance vMAJOR.MINOR.0 - Month D AD YYYY"
git push origin HEAD
git push origin vMAJOR.MINOR.0
```

Report the version, tag, commit, and that it was pushed.
