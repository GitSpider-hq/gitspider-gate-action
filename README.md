# GitSpider CI Config Gate

Fail your build when GitHub Actions config waste creeps back — missing dependency caches, absent `timeout-minutes`, no concurrency groups, runaway matrices. The same ratchet pattern you use for test coverage, applied to CI hygiene.

Config waste returns silently: someone copies a workflow without a timeout, a cache line disappears in a refactor, a matrix grows an axis. Nothing fails, so nobody notices. This gate makes it fail.

## Quick start

```yaml
name: CI config gate
on:
  schedule:
    - cron: "0 9 * * MON"
  workflow_dispatch:
jobs:
  gate:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: GitSpider-hq/gitspider-gate-action@v1
        with:
          max-findings: 3   # your ratchet — set to your current count, tighten as you fix
```

Start **without** `max-findings` for report-only mode: the job summary shows your findings (grouped by kind, with the workflows they apply to) and never fails. Then set the ratchet.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `max-findings` | *(unset — report-only)* | Fail when scorecard findings exceed this count |
| `max-recoverable-minutes` | *(unset)* | Fail when estimated recoverable runner-min/month exceed this |
| `repository` | current repo | Any public `owner/repo` |

## Outputs

`findings`, `recoverable-minutes`, `scorecard-url` — use them in later steps if you want custom behavior.

## How it works, honestly

- Reads the repository's **public scorecard** as JSON from [gitspider.com](https://gitspider.com) — public repos only, no token, no code access, nothing leaves your runner.
- Data is the scanner's cache (up to 24h old). Right for a weekly ratchet; not a per-commit check.
- **Never scanned?** The gate warns and passes; visit your scorecard once (free, ~30 seconds, no signup) and the scheduled gate keeps it warm from then on.
- **Infra never fails your build.** Rate limits or API hiccups warn and pass — only a genuine threshold breach fails.
- Detector improvements can move your count without your config changing; the scorecard's history strip marks those transitions. Treat a surprise jump as "look", not "revert".

## What this gate is not

It checks **config health on public repos**. It does not watch runtime behavior. For continuous monitoring on every push — slowdown and failure-spike alerts in Slack, flaky-run detection, and a PR comment naming the exact commit that caused a regression, on **private repos** too — that's the [GitSpider GitHub App](https://gitspider.com).

## License

MIT
