---
title: "How to instantiate the harness"
diataxis_type: how-to
---

# How to instantiate the harness

The harness is distributed as a **living, update-propagating template** (design
spec §7). There are three ways to stand up your own instance from
`research-harness-template`; they differ in one decisive way — whether you can
later pull template improvements with `bash scripts/update.sh` (the provenance-verified
wrapper around `copier update`).

| Path | Gets the files | `scripts/update.sh` works after? |
| --- | --- | --- |
| `copier copy` (recommended) | yes | **yes** — records `.copier-answers.yml` |
| GitHub "Use this template" | yes | no (until you adopt copier — see below) |
| `git clone` | yes | no |

## Option A — Copier (recommended: living template)

`copier copy` renders the template, asks the instantiation questions, and writes
a `.copier-answers.yml` that records the template version and your answers. That
answers file is what makes the instance *updatable* — **commit it** (it is not
gitignored): `copier update` reads its `_commit` as the merge base, so an
uncommitted or lost answers file breaks future updates.

```bash
pipx install copier            # or: pipx install copier && pipx ensurepath
copier copy gh:modeled-information-format/research-harness-template my-harness
cd my-harness
```

Copier strips template-only files at generation (`copier.yml`'s `_exclude`:
`copier.yml`, `COMPLETION-CRITERIA.md`, `IMPLEMENTATION-PLAN.md`, `PROGRESS.md`,
the template's CI). Only `*.jinja` files are rendered (suffix dropped); every
other file is copied verbatim, so the contracts, scripts, agents, and gates
travel unchanged.

### Pull later template improvements

This is the differentiator over snapshot engines. When the template ships a fix
or addition (for example a new channel pack or an engine fix), re-apply it to your instance:

```bash
cd my-harness
bash scripts/update.sh   # verifies release provenance, then runs copier update
```

`scripts/update.sh` is the only supported update path: it verifies the target release's
build-provenance attestation (fail-closed — nothing is applied on a miss), then runs
`copier update` pinned to the verified commit. `copier update` uses the recorded
`.copier-answers.yml` to merge template changes into your instance without clobbering your
edits (it conflict-marks the one file you hand-edit, `harness.config.json`). See
[update your harness safely](update-your-harness.md). Do not run `copier update` directly
— that bypasses the provenance gate.

## Option B — GitHub "Create repo from template"

GitHub's **Use this template → Create a new repository** copies the template
contents into a fresh repo you own. This is the quickest start and gives you a
clean git history, but the copy is a **snapshot**: there is no
`.copier-answers.yml`, so `copier update` cannot run and later template
improvements will not propagate automatically.

After creating from template:

1. Remove the template-only scaffolding that GitHub's copy carries over (these
   are excluded by `copier copy` but not by GitHub's template feature):

   ```bash
   git rm copier.yml COMPLETION-CRITERIA.md IMPLEMENTATION-PLAN.md PROGRESS.md
   git rm .copier-answers.yml.jinja docs/harness-instance.md.jinja
   ```

2. Edit `harness.config.json` to declare your topics, dimensions, outputs, and
   packs.
3. Run `bash scripts/verify.sh` — it must exit `0`.

### Adopt copier later (to regain update propagation)

If you started from a GitHub template copy (or a plain clone) and want update
propagation, adopt copier retroactively:

```bash
copier copy --answers-file .copier-answers.yml \
  gh:modeled-information-format/research-harness-template .
```

This writes the `.copier-answers.yml` your instance was missing; subsequent
`bash scripts/update.sh` runs then propagate template changes (provenance-verified).

## Option C — Plain git clone

`git clone` gives you the template files verbatim, including the template-only
scaffolding and with no `.copier-answers.yml`. Treat it like Option B: strip the
template-only files and, if you want update propagation, adopt copier as above.

## Add instance-specific guidance in `CLAUDE.local.md`

The template ships a `CLAUDE.md` that orients Claude Code to the harness *itself* —
its quality gates, contracts, and conventions. That file is **template-managed**:
it is copied verbatim and re-applied by `bash scripts/update.sh`, so edits you make
to it will conflict on the next update.

Put **your instance's** guidance — active research topics, house style, local
paths, team conventions — in a separate `CLAUDE.local.md` at the repo root. Claude
Code loads it automatically alongside `CLAUDE.md`, and the template never ships or
manages it, so `copier update` will never touch or clobber it.

```bash
cat > CLAUDE.local.md <<'EOF'
# Instance guidance

- Active topics: <your topic ids>
- House style: <conventions Claude should follow in this harness>
- Local paths / services: <anything specific to this clone>
EOF
```

Optional but recommended: keep `CLAUDE.local.md` out of version control so the
local guidance stays personal and never collides with template updates. Skip this
step if you instead want to commit it as shared, team-wide instance guidance.

```bash
echo 'CLAUDE.local.md' >> .gitignore
```

## Next

- [Declare and verify your harness](../tutorials/getting-started.md)
- [Import an existing corpus](import-a-corpus.md)
- [Update your harness safely](update-your-harness.md) — why `CLAUDE.md` and other
  template-managed files are re-applied on update (and `CLAUDE.local.md` is not)
