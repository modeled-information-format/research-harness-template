---
name: github-discuss
description: "Publish a synthesized deliverable to GitHub Discussions — an announcement of completed research, a Q&A thread about methodology, or a non-canonical observation. A channel adapter behind the findings→artifact contract: input is the report-synthesizer artifact, output is a GitHub Discussion. Optional channel; depends on the `gh` CLI. Use when the user says 'post to discussions', 'announce the research', 'create a discussion', or 'share the findings'."
version: 1.0.0
argument-hint: "<artifact-path> [--type announce|question|anecdotal] [--title \"...\"] [--repo owner/repo] [--dry-run] [--update]"
allowed-tools: Read, Bash, Grep, Glob
---

# GitHub Discussions Channel Adapter

Publish a synthesized deliverable to GitHub Discussions. Input is the **rendered
artifact** from `report-synthesizer` (a clean, already-cited document), not the
findings corpus. The discussion body is composed from the artifact and from
public links to the published report — it must read as if written from public
primary sources alone. No internal references belong in the body.

This is an **optional** channel. It depends on the external `gh` CLI being installed and authenticated. If `gh` is unavailable, degrade gracefully (see below).

| Type | Purpose |
| --- | --- |
| **announce** | Summary of a completed report, or a delta update on a prior announcement |
| **question** | A methodology or interpretation question routed to the Q&A category |
| **anecdotal** | Non-canonical context — supplementary signal, explicitly marked as unverified |

## Dependency Check (run first)

```bash
command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed — this channel is unavailable. Install gh and run 'gh auth login', then retry."; exit 0; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated. Run 'gh auth login' and retry."; exit 0; }
```

If either fails, report the step and stop — do not error.

## Phase 0: Resolve Inputs

1. Resolve `<artifact-path>` to the synthesized deliverable. For `announce`, this is required and supplies the summary. For `question`/`anecdotal`, the user supplies the body and the artifact (if given) is referenced only for a public cross-link. `--title` is required for `question` and `anecdotal`; for `announce` it defaults to the artifact's leading heading.
2. Resolve `--repo`: the `--repo` flag, else `gh repo view --json nameWithOwner -q .nameWithOwner`.

## Phase 1: Resolve Category

```bash
gh api graphql -f query='{ repository(owner:"<owner>", name:"<repo>") { id discussionCategories(first:25){ nodes{ id name slug } } } }'
```

Capture `repositoryId` and the matched `categoryId`. Match the artifact's title against category names by normalized substring. For `question`, use the `q-a` category. If nothing matches, fall back to "General" and warn.

## Phase 2: Compose Body (from the artifact only)

### announce

Summarize the artifact: a 2–3 sentence lead from its executive summary, a short status line, the top signals named in its own conclusions, and its tags. Close with a public link to the published report. Do not enumerate internal data files.

```markdown
## {artifact_title}

{2-3 sentence lead from the artifact's summary}

> **Status**: {status} | **Updated**: {date}

### Highlights
- {key conclusion drawn from the artifact}
- ...

Full report: {public URL to the published report}
```

For `--update`, compose a `## Delta Update — {date}` comment summarizing what changed, linking the public delta.

### question / anecdotal

Use the user's text as the body. Append a single cross-reference line linking the public report. For `anecdotal`, prepend the marker: *"Non-canonical observation — supplementary context, not verified through the research methodology."*

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
- Missing artifact for `announce`: error — "No artifact to announce. Render the report first."
- GraphQL failure: show the error; suggest `gh auth status`.
- `--title` missing for `question`/`anecdotal`: prompt for one.
