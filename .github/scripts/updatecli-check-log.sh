#!/bin/sh
#
# Reads the output of `updatecli apply` and fails when any source, condition
# or target of the run went wrong.
#
#   updatecli-check-log.sh <logfile>
#
# updatecli exits 0 and counts the pipeline as succeeded when one of its
# sources errors: it prints
#
#   source: attr
#   ------------
#   ...
#   ✗ Something went wrong:
#   	shell command failed. Expected exit code 0 but got 1
#
# and moves on, so the autobumper ended green for weeks while its git sources
# could not clone the mirror (kairos-io/kairos#6138). The marker is the only
# trace of the failure.
#
# Exits 0 when the log has no marker. Otherwise prints one GitHub `::error::`
# annotation per failing source, condition or target, named after the
# `source: <name>` style header updatecli prints before the step that failed,
# and exits 1. A missing log is an error too: it means updatecli never ran.
#
# Colour codes are stripped first, so a log captured from a terminal reads
# the same as one captured from a pipe.

set -eu

if [ $# -ne 1 ]; then
	echo "usage: updatecli-check-log.sh <logfile>" >&2
	exit 2
fi

log=$1

if [ ! -r "$log" ]; then
	echo "::error::updatecli log $log is missing, updatecli did not run"
	exit 1
fi

errors=$(awk '
	{ gsub(/\033\[[0-9;]*[A-Za-z]/, ""); sub(/\r$/, "") }
	reason_for != "" {
		reason = $0
		sub(/^[ \t]+/, "", reason)
		if (reason ~ /^(source|condition|target): /) reason = ""
		report(reason_for, reason)
		reason_for = ""
	}
	/^(source|condition|target): / {
		kind = $1
		sub(/:$/, "", kind)
		name = $0
		sub(/^[a-z]+: /, "", name)
		next
	}
	/Something went wrong/ {
		key = (name == "") ? "updatecli" : kind " " name
		if (!(key in seen)) {
			seen[key] = 1
			reason_for = key
		}
	}
	function report(key, reason) {
		if (reason == "") {
			printf "::error::%s went wrong\n", key
		} else {
			printf "::error::%s went wrong: %s\n", key, reason
		}
	}
	END {
		if (reason_for != "") report(reason_for, "")
	}
' "$log")

if [ -z "$errors" ]; then
	exit 0
fi

echo "$errors"
exit 1
