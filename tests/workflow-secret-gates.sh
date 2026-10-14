#!/bin/sh
#
# Locks in the one invariant that kept every dependabot PR from ever building
# an image (kairos-io/kairos#5481):
#
#   a workflow gate that decides "may this run use a registry secret" must not
#   be written as "is this branch in this repository".
#
# Those are different questions. A dependabot branch lives in the repository,
# so a head-repository check says yes, and GitHub still withholds secrets from
# a pull_request event raised by dependabot. The login step then runs with an
# empty username and password and fails, which is worse than skipping the
# push: it fails stage0 and skips every job downstream of it, so the image is
# never built and the red check says nothing about the change.
#
# Every job that can reach a QUAY_IO_USERNAME / QUAY_IO_PASSWORD login on a
# pull_request must therefore exclude dependabot as well as forks. This reads
# the workflow text, so it needs no runner and no secrets. See
# tests/make-image-tags.sh for the other no-runner style test.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

workflows=.github/workflows

head_check="github.event.pull_request.head.repo.full_name == github.repository"
bot_check="github.actor != 'dependabot[bot]'"

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok: $*"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Fold to one space separated line so an `if:` broken over several lines with
# `>-` matches the same glob as a single line one.
flatten() {
	tr '\n\t' '  ' <"$1" | tr -s ' '
}

# Write one `name|needs|disabled|reads_credential|schedule_only` record per
# job. Job keys are the 2-space indented mapping keys under the top level
# `jobs:`, and everything indented further belongs to the job above it.
#
# `schedule_only` is deliberately a single literal rather than an expression
# evaluator: the only way this tree says "not on a pull request" is
# `github.event_name == 'schedule'`. Anything subtler is not recognised, so a
# job gets held to the rule rather than waved through, which is the safe
# direction to be wrong in.
job_records() {
	awk '
		/^jobs:[[:space:]]*$/ { in_jobs = 1; next }
		/^[^[:space:]#]/      { in_jobs = 0 }
		in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
			if (job != "") print job "|" needs "|" disabled "|" cred "|" sched
			job = $1; sub(/:$/, "", job)
			needs = ""; disabled = 0; cred = 0; sched = 0
			next
		}
		in_jobs && job != "" {
			if ($0 ~ /^    if:[[:space:]]*\$\{\{[[:space:]]*false[[:space:]]*\}\}[[:space:]]*$/)
				disabled = 1
			if ($0 ~ /QUAY_IO_(USERNAME|PASSWORD)/)
				cred = 1
			if ($0 ~ /^    if:.*github\.event_name == .schedule./)
				sched = 1
			if ($0 ~ /^    needs:/) {
				line = $0
				sub(/^    needs:[[:space:]]*/, "", line)
				gsub(/[][,]/, " ", line)
				needs = needs " " line
			}
		}
		END { if (job != "") print job "|" needs "|" disabled "|" cred "|" sched }
	' "$1" >"$2"
}

# A job switched off with `if: ${{ false }}` cannot reach the login, and
# neither can anything downstream of it, because a skipped dependency skips its
# dependents. Both are exempt, and both un-exempt themselves: when the pipeline
# is switched back on the `false` goes away and every job in it is held to the
# same rule as the rest.
#
# Repeated passes rather than one, because `needs` may name a job defined later
# in the file. The loop reads from a file, not a pipe, so the set it is
# building survives each pass.
unreachable_jobs() {
	recfile=$1
	unreachable=" "
	changed=1
	while [ "$changed" -eq 1 ]; do
		changed=0
		while IFS='|' read -r job needs disabled _cred _sched; do
			case "$unreachable" in
			*" $job "*) continue ;;
			esac

			off=$disabled
			for dep in $needs; do
				case "$unreachable" in
				*" $dep "*) off=1 ;;
				esac
			done

			if [ "$off" = "1" ]; then
				unreachable="$unreachable$job "
				changed=1
			fi
		done <"$recfile"
	done
	printf '%s' "$unreachable"
}

check_workflow() {
	file=$workflows/$1

	if [ ! -f "$file" ]; then
		fail "$1 is missing: either it was renamed and this test must follow
	it, or the pipeline it guarded is gone and these checks guard nothing"
		return
	fi

	text=$(flatten "$file")

	case "$text" in
	*pull_request*) ;;
	*)
		pass "$1 reads a quay credential, but not on a pull_request event"
		return
		;;
	esac

	recfile=$tmpdir/records
	job_records "$file" "$recfile"

	if ! cut -d'|' -f4 "$recfile" | grep -q '^1$'; then
		fail "$1 no longer reads a quay credential in any job: either the
	credential moved and this test must follow it, or this gate is now
	guarding nothing"
		return
	fi

	unreachable=$(unreachable_jobs "$recfile")

	while IFS='|' read -r job _needs _disabled cred sched; do
		[ "$cred" = "1" ] || continue

		case "$unreachable" in
		*" $job "*)
			pass "$1 / $job is switched off with if: \${{ false }}, directly or through needs"
			continue
			;;
		esac

		if [ "$sched" = "1" ]; then
			pass "$1 / $job runs on the schedule event only, where secrets are present"
			continue
		fi

		case "$text" in
		*"$head_check"*) ;;
		*)
			fail "$1 / $job reads a quay credential on a pull_request and the
	workflow has no fork check. Expected: $head_check"
			continue
			;;
		esac

		case "$text" in
		*"$bot_check"*)
			pass "$1 / $job excludes both forks and dependabot"
			;;
		*)
			fail "$1 / $job gates on the head repository but not on the actor,
	so a dependabot PR reaches the registry login with no secrets and fails the
	job. Add: && $bot_check"
			;;
		esac
	done <"$recfile"
}

# Named rather than discovered, so deleting a guarded workflow fails here
# instead of silently shrinking the test to nothing.
check_workflow PR_multiarch.yml
check_workflow pr-cache-cleanup.yml

# And a sweep for the next copy of the mistake, so a new workflow is covered
# the day it is added rather than the day it breaks.
for f in "$workflows"/*.yml "$workflows"/*.yaml; do
	[ -e "$f" ] || continue
	name=$(basename "$f")
	case "$name" in
	PR_multiarch.yml | pr-cache-cleanup.yml) continue ;;
	esac
	grep -q 'QUAY_IO_USERNAME\|QUAY_IO_PASSWORD' "$f" || continue
	check_workflow "$name"
done

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi

echo "All workflow secret gate checks passed"
