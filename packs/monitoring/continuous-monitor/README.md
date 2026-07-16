# continuous-monitor

This `monitoring` pack is documented in the MIF research-harness reference:

- **[continuous-monitor — pack reference](https://modeled-information-format.github.io/research-harness-template/reference/packs/monitoring/#continuous-monitor)** — its purpose, constraints, goals,
  and how to enable it.

**Dependencies:** jq, python3, curl, timeout, ajv-cli + ajv-formats, git

The pack source lives in this directory. It ships disabled; enable it with
`scripts/pack-toggle.sh continuous-monitor on`, and opt a topic in via its own
`continuousMonitoring` block in `harness.config.json` (both are required --
research-harness-template#483). The pack's GitHub Actions workflows
(`workflows/monitor.yml`, `workflows/monitor-gate.yml`) are the canonical
sources for the unattended path -- copier excludes `.github/workflows/*`, so an
instantiated clone materializes them with
`bash scripts/install-monitoring-workflows.sh` (research-harness-template#517).
See the
[MIF research-harness docs](https://modeled-information-format.github.io/research-harness-template/) for the full pack catalog.
