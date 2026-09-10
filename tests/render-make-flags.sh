#!/bin/sh
# Guard the three invariants that keep the load cap working in the built image
# (kairos-io/kairos#4559).
#
# 1. Every stage that expands ${MAX_LOAD} has `ARG MAX_LOAD` in scope, in
#    itself or in an ancestor it inherits from through FROM. A stage that
#    misses it drops the cap silently instead of failing the build.
# 2. Every use of the flag is written `${MAX_LOAD:+-l${MAX_LOAD}}`. Writing
#    a bare `-l${MAX_LOAD}` is the original bug: with no value in scope
#    BuildKit leaves it for /bin/sh, which expands it to a lone `-l`, and
#    GNU make reads that as *removing* any load limit.
# 3. No `make` invocation passes a literal bare `-l`, for the same reason.
#
# Checks the rendered Dockerfile by default. Pass a path to check something
# else; Dockerfile.tmpl works too, since envsubst touches neither the ARG
# lines nor the ${MAX_LOAD} expansions.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

if [ "$#" -ge 1 ]; then
    dockerfile=$1
else
    dockerfile=Dockerfile
    trap 'rm -f "$repo_root/Dockerfile"' EXIT
    ./hack/render.sh >/dev/null
fi

[ -f "$dockerfile" ] || { echo "error: $dockerfile not found" >&2; exit 1; }

awk -v file="$dockerfile" '
# Literal substring count: the needles are full of $ { } and are not regexes.
function occurrences(haystack, needle,   n, at) {
    n = 0
    while ((at = index(haystack, needle)) > 0) {
        n++
        haystack = substr(haystack, at + length(needle))
    }
    return n
}

# A stage inherits its parent ARGs through FROM, so scope is a chain walk,
# not a per-stage lookup.
/^[Ff][Rr][Oo][Mm][ \t]/ {
    id++
    base = ""
    as = 0
    name[id] = ""
    for (i = 2; i <= NF; i++) {
        if ($i ~ /^--/) continue
        if (toupper($i) == "AS") { as = 1; continue }
        if (as) { name[id] = $i; break }
        if (base == "") base = $i
    }
    parent[id] = base
    if (name[id] != "") stage_of[name[id]] = id
    next
}

id == 0 { next }   # global ARGs before the first FROM are defaults, not scope

/^[ \t]*ARG[ \t]+MAX_LOAD([ \t]|=|$)/ { declares[id] = 1 }

index($0, "${MAX_LOAD") { uses[id] = 1 }

{
    unguarded = occurrences($0, "-l${MAX_LOAD}") \
              - occurrences($0, "${MAX_LOAD:+-l${MAX_LOAD}}")
    if (unguarded > 0) raw[++nraw] = FNR ": " $0
}

# `make ... -l` with nothing after it. -lz and friends are linker flags and
# do not match; the two standalone -l in the tree (mussel, attr) are not make.
$0 ~ /(^|[^[:alnum:]_.\/-])make([ \t]|$)/ && $0 ~ /(^|[ \t])-l([ \t]|\\|$)/ {
    bare[++nbare] = FNR ": " $0
}

END {
    fail = 0
    for (s = 1; s <= id; s++) {
        if (!uses[s]) continue
        cur = s
        found = 0
        seen = ""
        while (cur != "" && cur != 0) {
            if (declares[cur]) { found = 1; break }
            if (index(seen, "|" cur "|")) break   # a FROM cycle; stop, do not spin
            seen = seen "|" cur "|"
            cur = stage_of[parent[cur]]
        }
        if (found) continue
        label = (name[s] != "" ? name[s] : "<anonymous stage " s ">")
        print "error: stage " label " expands ${MAX_LOAD} with no ARG MAX_LOAD in scope" > "/dev/stderr"
        fail = 1
    }
    if (nraw) {
        print "error: " nraw " use(s) of -l${MAX_LOAD} outside ${MAX_LOAD:+...}; an empty value leaves make a bare -l:" > "/dev/stderr"
        for (i = 1; i <= nraw; i++) print "  " raw[i] > "/dev/stderr"
        fail = 1
    }
    if (nbare) {
        print "error: " nbare " make invocation(s) pass a bare -l, which removes the load limit:" > "/dev/stderr"
        for (i = 1; i <= nbare; i++) print "  " bare[i] > "/dev/stderr"
        fail = 1
    }
    if (fail) exit 1
    print "make-flags: " id " stages checked in " file "; MAX_LOAD in scope wherever it is used, every use guarded, no bare -l"
}
' "$dockerfile"
