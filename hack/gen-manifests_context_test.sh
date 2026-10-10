#!/bin/sh
# The Dockerfile's components-manifest stage generates the in-image component
# manifests from a hand-written list of COPYd files. If hack/gen-components.sh
# grows a dependency on a file that stage does not copy in, the build keeps
# succeeding and silently ships a different manifest than `make gen-components`
# writes. This test catches that: it stages exactly the paths the Dockerfile
# copies, runs the generator there, and diffs against a run over the full tree.
#
# No network, no docker. The COPY list is parsed out of the Dockerfile so the
# test cannot drift from the stage it is checking.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
STAGE="components-manifest"

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Extract the stage's COPY sources (context copies only, no --from=) ---
COPIES="$(awk -v st="$STAGE" '
  $0 ~ "^FROM .* AS "st"$" { inb=1; next }
  inb && /^FROM / { inb=0 }
  inb && /^COPY / && $0 !~ /--from=/ {
    # drop the COPY keyword and the destination (last field)
    for (i = 2; i < NF; i++) printf "%s\n", $i
  }' "$ROOT/Dockerfile")"

[ -n "$COPIES" ] || fail "no context COPY lines found in the $STAGE stage; did it get renamed?"

# --- Extract the RUN command the stage executes ---
RUNLINE="$(awk -v st="$STAGE" '
  $0 ~ "^FROM .* AS "st"$" { inb=1; next }
  inb && /^FROM / { inb=0 }
  inb && /^RUN / { sub(/^RUN /, ""); print; exit }' "$ROOT/Dockerfile")"

[ -n "$RUNLINE" ] || fail "no RUN line found in the $STAGE stage"

WORK="$(mktemp -d)"
REF_OUT="$(mktemp -d)"
trap 'rm -rf "$WORK" "$REF_OUT"' EXIT

# --- Stage only what the Dockerfile copies ---
for src in $COPIES; do
  case "$src" in
    ./*|/*) fail "unexpected COPY source '$src' in the $STAGE stage" ;;
  esac
  [ -e "$ROOT/$src" ] || fail "the $STAGE stage copies '$src', which does not exist"
  mkdir -p "$WORK/$(dirname "$src")"
  cp -R "$ROOT/$src" "$WORK/$src"
done

# --- Reference: the same generator over the full tree ---
sh "$ROOT/hack/gen-manifests.sh" --format flat --out-dir "$REF_OUT" --quiet 2>/dev/null

# --- Run the stage's own command, in the staged tree, with nothing else ---
STAGE_OUT="$WORK/out"
( cd "$WORK" && eval "${RUNLINE%% --out-dir *} --out-dir '$STAGE_OUT' --quiet" ) 2>/dev/null \
  || fail "the $STAGE stage command failed against its own COPY set"

[ -n "$(ls -A "$STAGE_OUT" 2>/dev/null)" ] || fail "the $STAGE stage produced no manifests"

diff -r "$REF_OUT" "$STAGE_OUT" \
  || fail "manifests generated inside the $STAGE stage differ from the full-tree run;
the stage is missing an input the generator reads (add it to the stage's COPY)"

echo "PASS: gen-manifests context test ($(ls "$STAGE_OUT" | wc -l | tr -d ' ') manifests, byte-identical)"
