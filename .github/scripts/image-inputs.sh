#!/bin/sh
# image-inputs.sh
#
# Reads changed file names, one per line, on stdin. Prints "true" when at least
# one of them can change what the pull request pipeline builds or boot-tests,
# and "false" when every one of them is on the skip list below.
#
# The list is deny by default: a path that is not named here counts as an
# image input. A new top-level directory, a new COPY source or a new script
# wired into PR_multiarch.yml therefore builds until someone decides it is safe
# to skip. tests/image-inputs_test.sh keeps the list honest against the
# Dockerfile and PR_multiarch.yml.
#
# First match wins, so the "never skip" arms stay above the skip arms.

set -eu

needs=false
while IFS= read -r f; do
	[ -n "$f" ] || continue
	# A markdown file in the repository root: .dockerignore drops it from the
	# build context. Markdown elsewhere is judged by its directory below.
	case "$f" in
	*/*) ;;
	*.md) continue ;;
	esac
	case "$f" in
	# ---- Read only by variants that main builds and a pull request does not:
	# arm64, riscv64, the cloud kernel and FIPS. PR_multiarch.yml builds amd64,
	# default kernel, no FIPS, so no job of a pull request reads these. The
	# quick checks still verify the kernel configs. If the pull request pipeline
	# ever builds one of those variants, delete its arm here
	# (tests/image-inputs_test.sh fails until you do).
	files/kernel/cloud.config | files/kernel/*-arm64.config | files/kernel/*-riscv64.config) ;;
	files/openssl/openssl.cnf.fips | files/ssh/sshd_config.d/02-hadron-fips.conf) ;;
	# ---- Read by the image build or by a job of the pull request pipeline.
	Dockerfile | sources.yaml | .dockerignore) needs=true ;;
	files/* | patches/*) needs=true ;;                             # COPY and bind mount sources
	tests/gcc/*) needs=true ;;                                     # COPY source (.dockerignore lets it through)
	hack/gen-components.sh | hack/gen-manifests.sh) needs=true ;;  # COPY in components-manifest
	hack/render.sh | hack/list-missing-sources.sh) needs=true ;;   # render-dockerfile action
	hack/ci-timing-report.sh) needs=true ;;                        # timing-report job
	.github/workflows/PR_multiarch.yml) needs=true ;;
	.github/workflows/populate-sources.yml) needs=true ;;
	.github/actions/*) needs=true ;;
	.github/scripts/image-size-report.sh | .github/scripts/size-history-lib.sh) needs=true ;;
	.github/scripts/image-inputs.sh) needs=true ;;                 # the gate itself: a change to it builds
	tests/assets/*) needs=true ;;                                  # ISO fixtures and Secure Boot keys
	tests/*.go | tests/go.mod | tests/go.sum) needs=true ;;        # boot and structure specs
	# ---- Cannot reach the image or the pipeline. The quick checks cover them.
	docs/* | examples/* | updatecli.d/*) ;;
	.github/workflows/* | .github/scripts/*) ;;
	.github/CODEOWNERS | .github/dependabot.yml | .github/*.md) ;;
	hack/*) ;;
	tests/*.sh | tests/*.rb) ;;
	Makefile | renovate.json | LICENSE | .gitignore) ;;
	# ---- Everything else, including anything new.
	*) needs=true ;;
	esac
	if [ "$needs" = true ]; then
		break
	fi
done

echo "$needs"
