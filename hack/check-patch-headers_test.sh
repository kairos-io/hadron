#!/bin/sh
#
# Exercises hack/check-patch-headers.sh against patch files written for this
# test, plus the repository's own patches/ directory.
#
# Every fixture is a real patch body taken from the shapes this tree already
# carries, so a pass here means the checker accepted a file `patch -p1` would
# accept, not a file invented to match the regex. The negative cases are the
# three ways a header can be missing: nothing above the diff at all, only
# blank lines, and mail fields with no reason under them.
#
# See hack/refresh-source-checksums_test.sh for the other script-under-test
# style test.

set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/hack/check-patch-headers.sh"

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

# A unified diff with no header at all. This is the shape
# patches/0001-make-getopt-gcc15.patch had.
diff_body() {
	cat <<'EOF'
--- a/src/getopt.c
+++ b/src/getopt.c
@@ -202,7 +202,7 @@
    whose names are inconsistent.  */

 #ifndef getenv
-extern char *getenv ();
+extern char *getenv (const char *);
 #endif

 static char *
EOF
}

# Asserts the checker's exit status and that its output names the file.
expect() {
	label=$1
	dir=$2
	want=$3
	needle=$4

	set +e
	out=$(sh "$checker" "$dir" 2>&1)
	got=$?
	set -e

	if [ "$got" -ne "$want" ]; then
		fail "$label: expected exit $want, got $got"
		printf '%s\n' "$out" | sed 's/^/    /' >&2
		return
	fi

	case "$out" in
	*"$needle"*) pass "$label" ;;
	*)
		fail "$label: output does not mention '$needle'"
		printf '%s\n' "$out" | sed 's/^/    /' >&2
		;;
	esac
}

# 1. A patch with prose above the diff is accepted.
mkdir -p "$tmpdir/good"
{
	echo "Build gnu-efi's two archives with a grouped target."
	echo
	echo "Under 'make -j' the two rules are eligible at the same time, so"
	echo "make runs the sub-make twice in the same directory."
	echo
	diff_body
} >"$tmpdir/good/0001-with-header.patch"
expect "a patch with prose above the diff passes" "$tmpdir/good" 0 "0001-with-header.patch"

# 2. The headerless shape this check exists for.
mkdir -p "$tmpdir/bare"
diff_body >"$tmpdir/bare/0001-no-header.patch"
expect "a patch that opens on its diff fails" "$tmpdir/bare" 1 "0001-no-header.patch has no header"

# 3. Blank lines are not a header.
mkdir -p "$tmpdir/blank"
{
	echo
	echo
	diff_body
} >"$tmpdir/blank/0001-blank-header.patch"
expect "blank lines above the diff do not count as a header" "$tmpdir/blank" 1 "0001-blank-header.patch has no header"

# 4. Mail fields alone are a title, not a reason.
mkdir -p "$tmpdir/meta"
{
	echo "From: Someone <someone@example.com>"
	echo "Subject: tools/resolve_btfids: copy BTF names before mutating BTF"
	echo
	diff_body
} >"$tmpdir/meta/0002-mail-fields-only.patch"
expect "mail fields with no body do not count as a header" "$tmpdir/meta" 1 "0002-mail-fields-only.patch has no header"

# 5. Mail fields followed by a reason are a header. This is the shape
#    patches/kernel-patches/0002-resolve_btfids-... carries.
mkdir -p "$tmpdir/mail"
{
	echo "From: Someone <someone@example.com>"
	echo "Subject: tools/resolve_btfids: copy BTF names before mutating BTF"
	echo
	echo "glibc's mremap usually extends the buffer in place, so this stays"
	echo "hidden upstream. musl's mallocng always moves it."
	echo
	diff_body
} >"$tmpdir/mail/0002-mail-fields-and-body.patch"
expect "mail fields followed by a reason pass" "$tmpdir/mail" 0 "0002-mail-fields-and-body.patch"

# 6. One good patch does not excuse a bad one in the same directory.
mkdir -p "$tmpdir/mixed"
cp "$tmpdir/good/0001-with-header.patch" "$tmpdir/mixed/"
cp "$tmpdir/bare/0001-no-header.patch" "$tmpdir/mixed/"
expect "a headerless patch next to a good one still fails" "$tmpdir/mixed" 1 "0001-no-header.patch has no header"

# 7. Patches in a subdirectory are checked too. kernel-patches/ is one.
mkdir -p "$tmpdir/nested/kernel-patches"
cp "$tmpdir/bare/0001-no-header.patch" "$tmpdir/nested/kernel-patches/"
expect "a headerless patch in a subdirectory fails" "$tmpdir/nested" 1 "kernel-patches/0001-no-header.patch has no header"

# 8. An empty directory is a red, not a green. A check that inspected nothing
#    has not said no.
mkdir -p "$tmpdir/empty"
expect "a patch directory with no patches fails" "$tmpdir/empty" 1 "no *.patch files found"

# 9. A directory that does not exist is a red for the same reason.
expect "a missing patch directory fails" "$tmpdir/absent" 1 "is not a directory"

# 10. The repository's own patches. This is the assertion that keeps the
#     tree honest; everything above only proves the checker can tell the
#     difference.
set +e
out=$(sh "$checker" 2>&1)
got=$?
set -e
if [ "$got" -eq 0 ]; then
	pass "every patch in patches/ carries a header"
else
	fail "patches/ has a patch with no header"
	printf '%s\n' "$out" | sed 's/^/    /' >&2
fi

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi

echo "All patch header checker tests passed"
