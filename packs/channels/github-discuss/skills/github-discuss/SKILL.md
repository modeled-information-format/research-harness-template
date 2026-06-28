---
name: github-discuss
description: "Publish a research topic to GitHub Discussions — an announcement of completed research, a Q&A thread about methodology, or a non-canonical observation. Grounded in the SOURCES (the findings corpus and their primary-source citations) — NEVER a rendered report. Optional channel; depends on the `gh` CLI. Use when the user says 'post to discussions', 'announce the research', 'create a discussion', or 'share the findings'."
version: 0.4.1
argument-hint: "<findings-dir> [--type announce|question|anecdotal] [--title \"...\"] [--repo owner/repo] [--dry-run] [--update]"
allowed-tools: Read, Bash, Grep, Glob
---

# GitHub Discussions Channel — source-grounded

**Non-negotiable: this deliverable is produced from the SOURCES alone.** Input is the
topic's surviving findings corpus (`reports/<topic>/findings/*.json`) and the primary
materials its citations point to — **never a rendered report** (that would be a
copy-of-a-copy). The discussion body is composed from the findings and their primary
sources; it may link to a public report URL for readers, but its content derives from
the sources alone. It must read as if written from public primary sources. No internal
references belong in the body.

This is an **optional** channel. It depends on the external `gh` CLI being installed and authenticated. If `gh` is unavailable, degrade gracefully (see below).

| Type | Purpose |
| --- | --- |
| **announce** | Summary of completed research, or a delta update on a prior announcement |
| **question** | A methodology or interpretation question routed to the Q&A category |
| **anecdotal** | Non-canonical context — supplementary signal, explicitly marked as unverified |

## Dependency Check (run first)

```bash
command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed — this channel is unavailable. Install gh and run 'gh auth login', then retry."; exit 0; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated. Run 'gh auth login' and retry."; exit 0; }
```

If either fails, report the step and stop — do not error.

## Phase 0: Load the sources

1. Resolve `<findings-dir>`. Load **every surviving finding** (verdict ≠ `falsified`):

   ```bash
   jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "<findings-dir>"/*.json
   ```

   For `announce`, the findings supply the summary. For `question`/`anecdotal`, the user supplies the body and the findings (if given) are referenced only for a public cross-link. `--title` is required for `question` and `anecdotal`; for `announce` it defaults to the topic name.
2. Resolve `--repo`: the `--repo` flag, else `gh repo view --json nameWithOwner -q .nameWithOwner`.

## Phase 1: Resolve Category

```bash
gh api graphql -f query='{ repository(owner:"<owner>", name:"<repo>") { id discussionCategories(first:25){ nodes{ id name slug } } } }'
```

Capture `repositoryId` and the matched `categoryId`. Match the topic title against category names by normalized substring. For `question`, use the `q-a` category. If nothing matches, fall back to "General" and warn.

## Phase 2: Compose Body (from the findings + their primary sources)

### announce

Summarize the research from the findings: a 2–3 sentence lead over the surviving findings, a short status line, the top conclusions (the findings' verified claims), and the cited primary sources. Close with a public link to the published report if one exists. Do not enumerate internal data files; carry no finding `@id`s, `urn:mif:` ids, corpus paths, or `f_<dim>_<n>` handles.

```markdown
## {topic title}

{2-3 sentence lead synthesized from the surviving findings}

> **Status**: {status} | **Updated**: {date}

### Highlights
- {a key finding's verified claim, with its primary source linked}
- ...

Full report: {public URL to the published report, if any}
```

For `--update`, compose a `## Delta Update — {date}` comment summarizing what changed in the findings since the prior announcement.

### question / anecdotal

Use the user's text as the body. Append a single cross-reference line linking the public report (if any). For `anecdotal`, prepend the marker: *"Non-canonical observation — supplementary context, not verified through the research methodology."*

## Phase 3: Duplicate Check (announce only)

```bash
gh api graphql -f query='{ search(query:"repo:<owner>/<repo> type:discussion in:title \"{title}\"", type:DISCUSSION, first:5){ nodes{ ... on Discussion { id number url } } } }'
```

If one exists: without `--update`, warn with its URL and stop; with `--update`, append the delta as a comment.

## Phase 4: Publish

- `--dry-run`: print the composed body, target category, and title; stop.
- Escape the body with `jq -Rs '.'`, then create:

```bash
gh api graphql -f query='mutation { createDiscussion(input:{ repositoryId:"<id>", categoryId:"<cat>", title:"<title>", body:<escaped> }){ discussion{ number url } } }'
```

- For `--update` on an existing thread, use `addDiscussionComment`.

## Phase 5: Report

Report the discussion URL, category, and type. For `announce`, note the highlights count.

## Error Handling

- No category match: fall back to General; suggest creating a dedicated category.
- No findings for `announce`: error — "No surviving findings to announce."
- GraphQL failure: show the error; suggest `gh auth status`.
- `--title` missing for `question`/`anecdotal`: prompt for one.
