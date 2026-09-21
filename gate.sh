#!/usr/bin/env bash
# GitSpider CI config gate. Reads the repository's PUBLIC scorecard (cached JSON —
# this endpoint never triggers a scan) and optionally fails the build when config
# waste exceeds the configured ratchet.
#
# Gate philosophy: only a genuine threshold breach fails the build. Infra conditions
# (repo not scanned yet, rate limit, API hiccup) WARN and pass — a hygiene gate must
# never be the flaky check in someone's CI.
set -uo pipefail

API="https://gitspider.com/api/v1/scorecard/${REPO}"
SCORECARD="https://gitspider.com/scan/${REPO}"

summary() { echo "$1" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; }
out() { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/null}"; }

body=$(curl -s --max-time 15 -w "\n%{http_code}" "$API")
status=$(echo "$body" | tail -1)
json=$(echo "$body" | sed '$d')

out scorecard_url "$SCORECARD"

if [ "$status" = "404" ]; then
  echo "::warning::No cached scorecard for ${REPO} yet. Visit ${SCORECARD} once to scan it (free, ~30s); the scheduled gate keeps it warm afterwards."
  summary "### GitSpider config gate: not scanned yet"
  summary "Visit [the scorecard](${SCORECARD}) once to run the first scan — this gate keeps it warm from then on."
  out findings ""
  out recoverable_min ""
  exit 0
fi
if [ "$status" != "200" ]; then
  echo "::warning::GitSpider API returned ${status} — skipping the gate this run (a hygiene gate should never be your flaky check)."
  out findings ""
  out recoverable_min ""
  exit 0
fi

# The RATCHET counts only findings that carry measurable recoverable minutes.
# Advisory findings (est 0 — style/hygiene/risk flags) are reported in the summary
# but never fail the gate: detector releases add advisory kinds over time, and a
# pinned max-findings must not start failing builds because the scanner learned
# a new advisory check.
findings=$(echo "$json" | jq '[.findings[] | select((.est_wasted_min_per_month // 0) > 0)] | length')
advisory=$(echo "$json" | jq '[.findings[] | select((.est_wasted_min_per_month // 0) == 0)] | length')
recoverable=$(echo "$json" | jq '.est_recoverable_min_capped // 0')
fetched=$(echo "$json" | jq -r '.fetched_at')
out findings "$findings"
out recoverable_min "$recoverable"

summary "### GitSpider config gate — \`${REPO}\`"
summary ""
summary "| Metric | Value |"
summary "|---|---|"
summary "| Config findings (gated) | **${findings}** |"
summary "| Advisory findings (never gate) | ${advisory} |"
summary "| Est. recoverable runner-min / month | **${recoverable}** |"
summary "| Scorecard data as of | ${fetched} |"
summary ""
if [ "$findings" != "0" ] || [ "$advisory" != "0" ]; then
  summary "**Findings by kind:**"
  echo "$json" | jq -r '.findings | group_by(.kind) | .[] | "- \(.[0].kind) × \(length) (\([.[].workflow] | join(", ")))"' >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  summary ""
fi
summary "[Full scorecard with the exact YAML fixes →](${SCORECARD})"
summary ""
summary "<sub>This gate checks public-repo config health (data up to 24h old). For continuous monitoring, Slack alerts, and PR comments that blame the exact commit — on private repos too — see [GitSpider](https://gitspider.com).</sub>"

fail=0
if [ -n "${MAX_FINDINGS}" ] && [ "$findings" -gt "${MAX_FINDINGS}" ]; then
  echo "::error::Config findings ${findings} > max-findings ${MAX_FINDINGS}. Fixes: ${SCORECARD}"
  fail=1
fi
if [ -n "${MAX_MINUTES}" ] && [ "$recoverable" -gt "${MAX_MINUTES}" ]; then
  echo "::error::Recoverable minutes ${recoverable} > max-recoverable-minutes ${MAX_MINUTES}. Fixes: ${SCORECARD}"
  fail=1
fi
if [ "$fail" = "1" ]; then exit 1; fi

if [ -z "${MAX_FINDINGS}" ] && [ -z "${MAX_MINUTES}" ]; then
  echo "Report-only mode: ${findings} findings, ~${recoverable} recoverable min/mo. Set max-findings to arm the gate."
else
  echo "Gate passed: ${findings} findings, ~${recoverable} recoverable min/mo."
fi
