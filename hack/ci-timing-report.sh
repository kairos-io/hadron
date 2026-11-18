#!/usr/bin/env bash
# ci-timing-report.sh [timings.json]
#
# Writes how long each job of the current workflow run waited for a runner and
# how long it ran, as JSON (default timings.json) and as markdown on the step
# summary. Needs GH_TOKEN with `actions: read`, and GITHUB_REPOSITORY,
# GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT from the runner. Jobs that have not
# finished (this one, for a start) are left out. Always exits 0: it reports,
# it does not gate.

set -euo pipefail

out=${1:-timings.json}
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}

gh api --paginate \
  "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}/jobs?per_page=100" \
  --jq '.jobs[]' \
| jq -s '
    def secs(a; b): ((b | fromdateiso8601) - (a | fromdateiso8601));
    [ .[]
      | select(.started_at != null and .completed_at != null and .conclusion != "skipped")
      | select(.name != "timing-report")
      | { name, label: (.labels | join("+")), conclusion,
          created: .created_at, started: .started_at, ended: .completed_at,
          wait: secs(.created_at; .started_at),
          run: secs(.started_at; .completed_at) } ]' > "${out}" || { echo "ci-timing-report: could not read the jobs, skipping"; exit 0; }

[ "$(jq 'length' "${out}")" -gt 0 ] || { echo "ci-timing-report: no finished jobs"; exit 0; }

# The run is created before its first job when it sits behind another run of
# the same concurrency group, which is how main runs queue up.
run_created=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}" --jq '.created_at' 2>/dev/null || true)

{
  echo "## Job timing"
  echo
  jq -r --arg rc "${run_created}" '
    def m: (. / 60 | floor | tostring) + " min";
    ( (map(.ended | fromdateiso8601) | max) - (map(.created | fromdateiso8601) | min) ) as $wall
    | (if $rc == "" then 0 else ((map(.created | fromdateiso8601) | min) - ($rc | fromdateiso8601)) end) as $held
    | "Wall time of the jobs: **\($wall | m)**. Held back before the first job (waiting for an earlier run of the same concurrency group): **\($held | m)**.",
      "",
      "Waiting for runners, summed over jobs: **\(map(.wait) | add | m)**. Time running, summed: **\(map(.run) | add | m)**.",
      "",
      "### Waiting for a runner, by pool",
      "",
      "| Runner label | Jobs | Median wait | Worst wait | Median run |",
      "|---|---:|---:|---:|---:|",
      ( group_by(.label)
        | map({label: .[0].label, n: length,
               w: (map(.wait) | sort), r: (map(.run) | sort)})
        | sort_by(-(.w[-1]))
        | .[]
        | "| `\(.label)` | \(.n) | \(.w[(.n / 2 | floor)] | m) | \(.w[-1] | m) | \(.r[(.n / 2 | floor)] | m) |" ),
      "",
      "### Longest jobs (wait + run)",
      "",
      "| Job | Pool | Wait | Run |",
      "|---|---|---:|---:|",
      ( sort_by(-(.wait + .run)) | .[:15][]
        | "| \(.name) | `\(.label)` | \(.wait | m) | \(.run | m) |" )
  ' "${out}"
} >> "${summary}"
