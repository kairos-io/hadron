#!/bin/sh
# ci-rebuild-guard.sh <plain-progress-log> <stage-regex>
#
# Prints a GitHub ::warning for every Dockerfile stage matching <stage-regex>
# (an awk extended regex anchored by the caller, e.g. '^kernel-') that ran
# steps in this build instead of taking them from the cache. The main
# workflow passes the stages an earlier job already built and cached, so a
# job that silently rebuilds the kernel shows up in the run summary instead
# of only as a slow job.
#
# A step counts as run when its vertex never printed CACHED and either printed
# command output or never pulled a layer. BuildKit sometimes shows a parent's
# layers being pulled under a vertex that did not run, without CACHED.
#
# Always exits 0: this is a signal, not a gate.

set -eu

log=$1
pattern=$2

[ -s "$log" ] || { echo "ci-rebuild-guard: no build log at $log, skipping"; exit 0; }

awk -v pat="$pattern" '
# "#12 [kernel-base  3/30] COPY ..." names a vertex; "#12 CACHED" marks it reused.
match($0, /^#[0-9]+ \[[^]]+\]/) {
    id = $1
    hdr = substr($0, RSTART, RLENGTH)
    sub(/^#[0-9]+ \[/, "", hdr); sub(/\]$/, "", hdr)
    split(hdr, f, " ")
    stage = f[1]
    # FROM lines are image pulls, not build steps.
    if (stage != "internal" && stage != "auth" && substr($0, RSTART + RLENGTH, 6) != " FROM " && !(id in name)) { name[id] = stage; step[id] = hdr }
    next
}
$1 ~ /^#[0-9]+$/ && $2 == "CACHED" { cached[$1] = 1; next }
$1 ~ /^#[0-9]+$/ && $2 ~ /^[0-9]+\.[0-9]+$/ { output[$1] = 1; next }
$1 ~ /^#[0-9]+$/ && ($2 == "extracting" || $2 ~ /^sha256:/) { pulled[$1] = 1; next }
$1 ~ /^#[0-9]+$/ && ($2 == "DONE" || $2 == "ERROR") { ended[$1] = 1 }
END {
    for (id in name) {
        if (!(id in ended) || (id in cached)) continue
        if ((id in pulled) && !(id in output)) continue
        if (name[id] !~ pat) continue
        n[name[id]]++
        if (!(name[id] in first)) first[name[id]] = step[id]
    }
    for (s in n) {
        printf "::warning title=Rebuilt a cached stage::%s ran %d step(s) (first seen: [%s]); an upstream job should have cached it\n", s, n[s], first[s]
        total += n[s]
    }
    printf "ci-rebuild-guard: %d step(s) ran in stages matching %s\n", total + 0, pat
}
' "$log"
