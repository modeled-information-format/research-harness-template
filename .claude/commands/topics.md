---
name: topics
description: List the topic registry from harness.config.json with id, title, namespace, and lifecycle status.
argument-hint: "[--filter <status>] [--ids]"
allowed-tools:
  - Bash
  - Read
---

# Topics

Lists the research topic registry from `harness.config.json` `topics[]`. The
config is the single declarative manifest (SPEC §7) and the deploy contract — it
is where a clone declares its topics. Read-only.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--filter <status>` — show only topics with this lifecycle `status` (e.g.
  `active`, `complete`).
- `--ids` — print bare topic ids (one per line), for piping into other commands.

## Behavior

`harness.config.json` `topics` is an **array** of objects, each with `id`,
`title`, `namespace`, and `status`. Read it with jq.

### `--ids`

```bash
jq -r '.topics[].id' harness.config.json
```

Print the ids one per line and stop.

### Default (and `--filter`)

Render a table. Apply the status filter when `--filter <status>` is given.

```bash
COUNT=$(jq '.topics | length' harness.config.json)

jq -r --arg filter "<status or empty>" '
  .topics
  | (if $filter == "" then . else map(select(.status == $filter)) end)
  | (["ID", "TITLE", "NAMESPACE", "STATUS"], ["--", "-----", "---------", "------"]),
    (.[] | [.id, .title, .namespace, .status])
  | @tsv' harness.config.json | column -t -s $'\t'
```

Wrap the table in a markdown code block for monospace alignment, and prefix a
header line:

```markdown
## Topic Registry — {COUNT} topics
```

If `--filter` was applied, note the filter and the filtered count in the header.

After the table, show contextual next-step examples using actual topic ids from
the output:

```text
/start --topic <id>          # start (needs a goal — author with /goal-writer)
/status --topic <id>         # current session state
/resume --topic <id>         # continue a session
/augment <dimension> --topic <id>   # deepen one config-declared dimension
/falsify --topic <id>        # re-run the adversarial gate
```

If `topics[]` is empty, say so and point the user at `/start` (which registers a
topic) and `/goal-writer` (which authors the session goal).
