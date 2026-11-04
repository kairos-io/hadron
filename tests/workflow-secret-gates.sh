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
env_gate="env.PR_CACHE_WRITE == 'true'"

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

# Write one `name|needs|disabled|reads_credential|schedule_only|gate|where`
# record per job. Job keys are the 2-space indented mapping keys under the top
# level `jobs:`, and everything indented further belongs to the job above it.
#
# `schedule_only` is deliberately a single literal rather than an expression
# evaluator: the only way this tree says "not on a pull request" is
# `github.event_name == 'schedule'`. Anything subtler is not recognised, so a
# job gets held to the rule rather than waved through, which is the safe
# direction to be wrong in.
#
# `gate` is the weakest guard in front of any credential the job reads, and
# `where` names the step it was found in (or `job` for a credential outside
# any step). A credential is guarded by the job `if:` or by the `if:` of the
# step that reads it, whichever is stronger:
#
#   inline  the `if:` carries both $head_check and $bot_check itself
#   env     the `if:` is `env.PR_CACHE_WRITE == 'true'`, so it is only as good
#           as the workflow level PR_CACHE_WRITE, which is checked on its own
#   nobot   the `if:` checks the head repository but not the actor
#   none    nothing in front of the credential at all
#
# Every job is judged on its own `if:` lines rather than on the workflow text
# as a whole, so one remaining gate cannot vouch for a login that lost its own.
# An `if: >-` folded over several lines is joined back into one before it is
# matched.
job_records() {
	awk -v head="$head_check" -v bot="$bot_check" -v envgate="$env_gate" '
		function indent(s) {
			match(s, /^ */)
			return RLENGTH
		}
		function kind(g) {
			gsub(/[[:space:]]+/, " ", g)
			if (index(g, head) && index(g, bot)) return 0
			if (index(g, envgate)) return 1
			if (index(g, head)) return 2
			return 3
		}
		function close_step() {
			if (in_step && step_cred) {
				n++
				cred_kind[n] = kind(step_if)
				cred_where[n] = step_name == "" ? "unnamed step" : step_name
			}
			in_step = 0; step_cred = 0; step_if = ""; step_name = ""
		}
		function close_job(   jk, k, worst, where, i) {
			close_step()
			if (job == "") return
			jk = kind(job_if)
			worst = 0; where = ""
			if (job_cred) {
				worst = jk; where = "job"
			}
			for (i = 1; i <= n; i++) {
				k = cred_kind[i] < jk ? cred_kind[i] : jk
				if (where == "" || k > worst) {
					worst = k; where = cred_where[i]
				}
			}
			split("inline env nobot none", names, " ")
			print job "|" needs "|" disabled "|" cred "|" sched "|" names[worst + 1] "|" where
		}
		/^[[:space:]]*$/ { next }
		/^jobs:[[:space:]]*$/ { in_jobs = 1; next }
		/^[^[:space:]#]/      { close_job(); job = ""; in_jobs = 0 }
		in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
			close_job()
			job = $1; sub(/:$/, "", job)
			needs = ""; disabled = 0; cred = 0; sched = 0
			job_if = ""; job_cred = 0; n = 0; in_steps = 0; cap = ""
			next
		}
		in_jobs && job != "" {
			line = $0
			if (cap != "" && indent(line) > cap_indent) {
				if (cap == "job") job_if = job_if " " line
				else step_if = step_if " " line
				next
			}
			cap = ""

			if (line ~ /^    [^[:space:]#]/) {
				close_step()
				in_steps = (line ~ /^    steps:/)
			}
			if (in_steps && line ~ /^      - /) {
				close_step()
				in_step = 1
				sub(/^      - /, "        ", line)
			}

			if (line ~ /^    if:[[:space:]]*\$\{\{[[:space:]]*false[[:space:]]*\}\}[[:space:]]*$/)
				disabled = 1
			if (line ~ /QUAY_IO_(USERNAME|PASSWORD)/) {
				cred = 1
				if (in_step) step_cred = 1
				else job_cred = 1
			}
			if (line ~ /^    if:.*github\.event_name == .schedule./)
				sched = 1
			if (line ~ /^    if:/) {
				job_if = line; cap = "job"; cap_indent = 4
			}
			if (in_step && line ~ /^        if:/) {
				step_if = line; cap = "step"; cap_indent = 8
			}
			if (in_step && line ~ /^        name:/) {
				step_name = line
				sub(/^        name:[[:space:]]*/, "", step_name)
				gsub(/\|/, "/", step_name)
			}
			if (line ~ /^    needs:/) {
				sub(/^    needs:[[:space:]]*/, "", line)
				gsub(/[][,]/, " ", line)
				needs = needs " " line
			}
		}
		END { close_job() }
	' "$1" >"$2"
}

# The workflow level `PR_CACHE_WRITE:` entry under the top level `env:`, folded
# to one line, or nothing when the workflow does not define it.
pr_cache_write_env() {
	awk '
		/^env:[[:space:]]*$/ { in_env = 1; next }
		/^[^[:space:]#]/     { in_env = 0; grab = 0 }
		in_env && grab && /^   / { printf " %s", $0; next }
		{ grab = 0 }
		in_env && /^  PR_CACHE_WRITE:/ { printf "%s", $0; grab = 1 }
	' "$1" | tr '\t' ' ' | tr -s ' '
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

	# A workflow that defines PR_CACHE_WRITE is checked on that line whether or
	# not a job uses it yet, so the gate is right before anything leans on it.
	env_ok=0
	env_line=$(pr_cache_write_env "$file")
	if [ -n "$env_line" ]; then
		case "$env_line" in
		*"$head_check"*"$bot_check"* | *"$bot_check"*"$head_check"*)
			env_ok=1
			pass "$1 PR_CACHE_WRITE excludes both forks and dependabot"
			;;
		*"$head_check"*)
			fail "$1 PR_CACHE_WRITE gates on the head repository but not on the
	actor, so a dependabot PR reaches the registry login with no secrets and
	fails the job. Add: && $bot_check"
			;;
		*)
			fail "$1 PR_CACHE_WRITE has no fork check. Expected: $head_check
	&& $bot_check"
			;;
		esac
	fi

	unreachable=$(unreachable_jobs "$recfile")

	while IFS='|' read -r job _needs _disabled cred sched gate where; do
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

		case "$gate" in
		inline)
			pass "$1 / $job excludes both forks and dependabot"
			;;
		env)
			if [ "$env_ok" -eq 1 ]; then
				pass "$1 / $job excludes both forks and dependabot through PR_CACHE_WRITE"
			else
				fail "$1 / $job ($where) gates on $env_gate, but the
	workflow level PR_CACHE_WRITE is missing or does not exclude both forks and
	dependabot"
			fi
			;;
		nobot)
			fail "$1 / $job ($where) gates on the head repository but not on the
	actor, so a dependabot PR reaches the registry login with no secrets and
	fails the job. Add: && $bot_check"
			;;
		*)
			fail "$1 / $job ($where) reads a quay credential on a pull_request with
	no fork and dependabot gate on the job or on that step. Expected: if:
	\${{ $env_gate }}, or $head_check && $bot_check"
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
