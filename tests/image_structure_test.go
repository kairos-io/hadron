package hadron_test

// image_structure_test.go contains fast, VM-free structural checks that
// introspect an already-built Hadron CONTAINER OCI image. Unlike the rest of
// the suite, these specs do NOT use peg/QEMU. They run the image with the
// local container runtime (docker by default) and assert on the contents of
// the rootfs.
//
// The image reference is taken from the CONTAINER_IMAGE env var. If it is
// unset, the whole Describe is skipped. The container runtime can be
// overridden with CONTAINER_RUNTIME (defaults to "docker").
//
// Prerequisites:
//   - A built (or pulled) Hadron container image, e.g. via `make build-hadron`
//     or `docker pull ghcr.io/kairos-io/hadron:main`.
//   - A working `docker` (or other CONTAINER_RUNTIME) on the host.
//
// Run locally with:
//
//	CONTAINER_IMAGE=ghcr.io/kairos-io/hadron:main \
//	  go run github.com/onsi/ginkgo/v2/ginkgo --label-filter image-structure ./tests/
//
// Or with a custom runtime:
//
//	CONTAINER_IMAGE=hadron:dev CONTAINER_RUNTIME=podman \
//	  go run github.com/onsi/ginkgo/v2/ginkgo --label-filter image-structure ./tests/

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// crashSignalExitCodes mirrors the crash-signal logic in
// files/verify_binaries.sh. A binary that exits with one of these codes
// (128 + signal) was killed by a crash signal rather than exiting cleanly.
//
//	139 = SIGSEGV (Segmentation fault)
//	132 = SIGILL  (Illegal instruction)
//	134 = SIGABRT (Abort)
//	133 = SIGTRAP (Trace/breakpoint trap)
//	136 = SIGFPE  (Floating point exception)
//	138 = SIGBUS  (Bus error)
var crashSignalExitCodes = map[int]string{
	139: "SIGSEGV",
	132: "SIGILL",
	134: "SIGABRT",
	133: "SIGTRAP",
	136: "SIGFPE",
	138: "SIGBUS",
}

var _ = Describe("hadron container image structure", Label("image-structure"), func() {
	var (
		image   string
		runtime string
		arch    string
	)

	// runInImage executes `<runtime> run --rm --entrypoint <bin> <image> <args...>`
	// and returns combined stdout+stderr, the process exit code, and any error
	// starting the process. Note: a non-zero exit code from the in-container
	// program is NOT returned as err (err is reserved for failures to launch
	// the runtime itself).
	runInImage := func(bin string, args ...string) (string, int, error) {
		runArgs := []string{"run", "--rm", "--entrypoint", bin, image}
		runArgs = append(runArgs, args...)
		cmd := exec.Command(runtime, runArgs...)
		out, err := cmd.CombinedOutput()
		exitCode := 0
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				exitCode = exitErr.ExitCode()
				// The runtime ran fine; the in-container command exited
				// non-zero. That is not a launch failure.
				err = nil
			}
		}
		return string(out), exitCode, err
	}

	// shInImage runs an arbitrary shell snippet inside the image via
	// `sh -c '<script>'`. Returns trimmed combined output and exit code.
	shInImage := func(script string) (string, int) {
		out, code, err := runInImage("sh", "-c", script)
		Expect(err).ToNot(HaveOccurred(), "failed to invoke %q: %s", runtime, out)
		return strings.TrimSpace(out), code
	}

	// skipUnlessFullImage skips specs that assert on bootable-OS hardening files
	// (sshd config, sysctl, modprobe, login.defs). Those ship only in the full
	// image (the `default`/full-image-final target); the minimal `container`
	// target — which CI structure-tests — deliberately omits them. systemd is
	// present only in the full image, so it is a reliable discriminator.
	skipUnlessFullImage := func() {
		out, code := shInImage("test -x /usr/lib/systemd/systemd && echo full")
		if code != 0 || !strings.Contains(out, "full") {
			Skip("minimal container base ships no bootable-OS hardening files " +
				"(sshd/sysctl/modprobe/login.defs); these specs apply to the full image only")
		}
	}

	BeforeEach(func() {
		image = os.Getenv("CONTAINER_IMAGE")
		if image == "" {
			Skip("CONTAINER_IMAGE is not set; skipping VM-free container image " +
				"structure checks. Set CONTAINER_IMAGE to a built/pulled Hadron " +
				"image (e.g. ghcr.io/kairos-io/hadron:main) to run these specs.")
		}

		runtime = os.Getenv("CONTAINER_RUNTIME")
		if runtime == "" {
			runtime = "docker"
		}

		// Detect the architecture inside the container so the rest of the
		// checks can tolerate x86_64/aarch64/riscv64 differences.
		out, _, err := runInImage("uname", "-m")
		Expect(err).ToNot(HaveOccurred(),
			"could not run %q against image %q: %s", runtime, image, out)
		arch = strings.TrimSpace(out)
		Expect(arch).ToNot(BeEmpty(), "uname -m returned empty output")
	})

	It("reports ID=hadron in /etc/os-release", func() {
		out, code := shInImage("cat /etc/os-release")
		Expect(code).To(Equal(0), out)
		Expect(out).To(ContainSubstring("ID=hadron"))
	})

	It("ships a parseable per-image component manifest", func() {
		// Every shipped image carries /usr/lib/hadron/components.json: a flat
		// { "name": "version" } map generated at build time from the
		// Dockerfile's ARG *_VERSION defaults, filtered to what the image
		// actually ships. See the `components` stage in the Dockerfile and
		// hack/gen-components.sh.
		out, code := shInImage("cat /usr/lib/hadron/components.json")
		Expect(code).To(Equal(0),
			"expected /usr/lib/hadron/components.json to exist; output: %s", out)

		manifest := map[string]string{}
		Expect(json.Unmarshal([]byte(out), &manifest)).To(Succeed(),
			"components.json is not a flat string map:\n%s", out)
		Expect(manifest).ToNot(BeEmpty(), "component manifest is empty")

		// curl + openssl ship in both the minimal container and the full image.
		Expect(manifest).To(HaveKey("curl"))
		Expect(manifest).To(HaveKey("openssl"))
		Expect(manifest["curl"]).ToNot(BeEmpty(), "curl version is empty")
	})

	It("ships the musl dynamic loader for the current arch", func() {
		loader := fmt.Sprintf("/lib/ld-musl-%s.so.1", arch)
		out, code := shInImage(fmt.Sprintf("test -e %s && echo OK", loader))
		Expect(code).To(Equal(0),
			"expected musl loader %s to exist; output: %s", loader, out)
		Expect(out).To(ContainSubstring("OK"))
	})

	It("does NOT ship glibc (no ld-linux*.so* or libc.so.6)", func() {
		// find prints nothing when there are no matches; we assert the
		// output is empty so any glibc artifact fails the spec loudly.
		out, code := shInImage(
			"find /lib /usr/lib \\( -name 'ld-linux*.so*' -o -name 'libc.so.6' \\) 2>/dev/null")
		Expect(code).To(Equal(0), out)
		Expect(out).To(BeEmpty(),
			"found glibc artifacts that should not be present:\n%s", out)
	})

	DescribeTable("core binaries run without crashing",
		func(bin string, args ...string) {
			out, code, err := runInImage(bin, args...)
			Expect(err).ToNot(HaveOccurred(),
				"failed to invoke %q: %s", runtime, out)
			if sig, crashed := crashSignalExitCodes[code]; crashed {
				Fail(fmt.Sprintf("%s crashed with %s (exit code %d):\n%s",
					bin, sig, code, out))
			}
		},
		Entry("bash", "bash", "--version"),
		Entry("busybox", "busybox", "--help"),
		Entry("openssl", "openssl", "version"),
		Entry("curl", "curl", "--version"),
		Entry("systemctl", "systemctl", "--version"),
		Entry("sshd", "sshd", "-V"),
		Entry("rsync", "rsync", "--version"),
		Entry("grep", "grep", "--version"),
		Entry("find", "find", "--version"),
	)

	It("resolves /bin/sh to bash", func() {
		out, code := shInImage("readlink -f /bin/sh")
		Expect(code).To(Equal(0), out)
		Expect(out).To(HaveSuffix("bash"),
			"expected /bin/sh to resolve to bash, got %q", out)
	})

	It("ships no static archives (*.a)", func() {
		out, code := shInImage("find / -name '*.a' 2>/dev/null")
		Expect(code).To(Equal(0), out)
		Expect(out).To(BeEmpty(),
			"found static archives that should be stripped:\n%s", out)
	})

	It("ships no python bytecode (*.pyc / __pycache__)", func() {
		out, code := shInImage(
			"find / \\( -name '*.pyc' -o -name '__pycache__' \\) 2>/dev/null")
		Expect(code).To(Equal(0), out)
		Expect(out).To(BeEmpty(),
			"found python bytecode artifacts that should be removed:\n%s", out)
	})

	DescribeTable("top-level dirs are symlinks into usr",
		func(dir, wantTarget string) {
			// -L: path is a symlink. Then compare the readlink target.
			out, code := shInImage(fmt.Sprintf(
				"test -L %s && readlink %s", dir, dir))
			Expect(code).To(Equal(0),
				"expected %s to be a symlink; output: %s", dir, out)
			Expect(out).To(ContainSubstring(wantTarget),
				"expected %s to point into usr (got %q)", dir, out)
		},
		Entry("/sbin -> usr/bin", "/sbin", "usr"),
		Entry("/lib -> usr/lib", "/lib", "usr"),
		Entry("/bin -> usr/bin", "/bin", "usr"),
	)

	It("ships a valid, STIG-hardened sshd config (sshd -G parses cleanly)", func() {
		skipUnlessFullImage()
		out, code, err := runInImage("sshd", "-G")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(code).To(Equal(0), "sshd -G failed to parse the sshd config:\n%s", out)
		lc := strings.ToLower(out)
		for _, want := range []string{
			"permitrootlogin prohibit-password",
			"x11forwarding no",
			"maxauthtries 4",
		} {
			Expect(lc).To(ContainSubstring(want), "effective sshd config missing %q", want)
		}
	})

	It("STIG sshd drop-in carries no crypto keywords (FIPS-safety invariant)", func() {
		skipUnlessFullImage()
		// The STIG drop-in sorts before the 100-* crypto file and sshd is
		// first-value-wins for these keywords, so crypto here would silently
		// override FIPS crypto in FIPS images. Guard against a regression.
		out, code := shInImage("cat /etc/ssh/sshd_config.d/99-hadron-stig.conf")
		Expect(code).To(Equal(0), out)
		lc := strings.ToLower(out)
		for _, k := range []string{"ciphers", "macs", "kexalgorithms", "hostkeyalgorithms"} {
			Expect(lc).ToNot(MatchRegexp(`(?m)^[[:space:]]*`+k+`[[:space:]]`),
				"STIG drop-in must not set crypto keyword %q (breaks FIPS ordering)", k)
		}
	})

	It("ships the STIG sysctl hardening drop-in", func() {
		skipUnlessFullImage()
		out, code := shInImage("cat /etc/sysctl.d/60-hadron-hardening.conf")
		Expect(code).To(Equal(0), out)
		for _, want := range []string{
			"kernel.kptr_restrict = 1",
			"kernel.dmesg_restrict = 1",
			"fs.protected_symlinks = 1",
			"net.ipv4.tcp_syncookies = 1",
		} {
			Expect(out).To(ContainSubstring(want),
				"sysctl hardening drop-in missing %q", want)
		}
	})

	It("sysctl hardening drop-in omits keys that break Kubernetes", func() {
		skipUnlessFullImage()
		// Forwarding, rp_filter, bridge-nf and user namespaces are owned by the
		// CNI/kubelet; shipping STIG's restrictive values for them breaks a k8s
		// node. Guard against a regression — checked against ACTIVE lines only so
		// the documented "DELIBERATELY OMITTED" comments don't trip the match.
		out, code := shInImage("cat /etc/sysctl.d/60-hadron-hardening.conf")
		Expect(code).To(Equal(0), out)
		var active strings.Builder
		for _, line := range strings.Split(out, "\n") {
			t := strings.TrimSpace(line)
			if t == "" || strings.HasPrefix(t, "#") {
				continue
			}
			active.WriteString(t + "\n")
		}
		for _, forbidden := range []string{
			"ip_forward", ".forwarding", "rp_filter",
			"bridge-nf-call", "max_user_namespaces",
		} {
			Expect(active.String()).ToNot(ContainSubstring(forbidden),
				"drop-in must not set Kubernetes/CNI-owned key %q", forbidden)
		}
	})

	It("ships the legacy-network-protocol blacklist", func() {
		skipUnlessFullImage()
		out, code := shInImage("cat /etc/modprobe.d/disable-legacy-net-protocols.conf")
		Expect(code).To(Equal(0), out)
		for _, mod := range []string{"dccp", "rds", "tipc", "atm", "ax25", "netrom"} {
			Expect(out).To(MatchRegexp(`(?m)^install\s+`+mod+`\s+/bin/false`),
				"blacklist must disable %q via install /bin/false", mod)
		}
	})

	It("ships STIG-hardened login.defs", func() {
		skipUnlessFullImage()
		out, code := shInImage("cat /etc/login.defs")
		Expect(code).To(Equal(0), out)
		Expect(out).To(MatchRegexp(`(?m)^PASS_MAX_DAYS\s+60\b`), "PASS_MAX_DAYS should be 60")
		Expect(out).To(MatchRegexp(`(?m)^LOG_OK_LOGINS\s+yes\b`), "LOG_OK_LOGINS should be yes")
		Expect(out).To(MatchRegexp(`(?m)^UMASK\s+077\b`), "UMASK should be 077")
	})
})
