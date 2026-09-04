package hadron_test

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	. "github.com/spectrocloud/peg/matcher"
)

// fipsEnabled reports whether the suite is running in FIPS mode.
// FIPS remains a runtime env flag (CI currently uses both `fips` and `true`),
// so detection stays centralized here rather than scattered across specs.
func fipsEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("FIPS"))) {
	case "fips", "true", "1", "yes", "on":
		return true
	default:
		return false
	}
}

// assertFIPSEnabled verifies the kernel has FIPS mode enabled.
func assertFIPSEnabled(vm VM) {
	By("Checking that FIPS is enabled", func() {
		out, err := vm.Sudo("cat /proc/sys/crypto/fips_enabled")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("1"))
	})
}

// assertWriteableTmp verifies /tmp is writeable.
func assertWriteableTmp(vm VM) {
	By("checking writeable tmp", func() {
		_, err := vm.Sudo("echo 'foo' > /tmp/bar")
		Expect(err).ToNot(HaveOccurred())

		out, err := vm.Sudo("sudo cat /tmp/bar")
		Expect(err).ToNot(HaveOccurred())

		Expect(out).To(ContainSubstring("foo"))
	})
}

// assertBpfMounted verifies the bpf filesystem is mounted.
func assertBpfMounted(vm VM) {
	By("checking bpf mount", func() {
		Eventually(func() string {
			out, _ := vm.Sudo("mount")
			return out
		}, 5*time.Minute, 1*time.Second).Should(
			Or(
				ContainSubstring("bpf"),
			))
	})
}

// assertBTFAvailable verifies the kernel exposes vmlinux BTF at
// /sys/kernel/btf/vmlinux (CONFIG_DEBUG_INFO_BTF=y). CO-RE eBPF consumers
// (Datadog system-probe, Tetragon, Inspektor Gadget, Parca, bpftrace, BCC
// CO-RE tools) require this to relocate their pre-compiled programs at load
// time. Without it they fail with "no BTF data".
func assertBTFAvailable(vm VM) {
	By("checking kernel BTF is exposed for CO-RE eBPF", func() {
		out, err := vm.Sudo("stat -c %s /sys/kernel/btf/vmlinux 2>/dev/null || echo missing")
		Expect(err).ToNot(HaveOccurred(), out)
		s := strings.TrimSpace(out)
		Expect(s).ToNot(Equal("missing"),
			"/sys/kernel/btf/vmlinux is absent; CONFIG_DEBUG_INFO_BTF likely not enabled")
		// vmlinux BTF is typically 3-8MB. Assert a conservative lower bound
		// so a truncated or empty file trips the test.
		n, perr := strconv.Atoi(s)
		Expect(perr).ToNot(HaveOccurred(), "unparseable size %q", s)
		Expect(n).To(BeNumerically(">", 1_000_000),
			"vmlinux BTF suspiciously small: %d bytes", n)
	})
}

// assertFirmwareLayout verifies the firmware search layout on an installed
// node. See kairos-io/kairos#4290: the image blobs used to live at
// /usr/local/lib/firmware with /lib/firmware symlinked into it, so the
// COS_PERSISTENT mount at /usr/local hid every blob baked into the image.
//
// The blobs now sit in the real directory /usr/lib/firmware, on the read-only
// rootfs where the persistent mount cannot shadow them, and the persistent
// partition is reachable as the override directory /usr/lib/firmware/updates.
// The kernel searches /lib/firmware/updates before /lib/firmware (fw_path[]
// in drivers/base/firmware_loader/main.c), so an operator blob dropped on the
// persistent partition wins, as long as its compression suffix comes no later
// than the image blob's in the loader's uncompressed, .zst, .xz sequence. The
// image blobs are .zst, so an .xz override loses to them. See the comment
// above the firmware RUN in Dockerfile.tmpl for the derivation, and for why
// riscv64 reads uncompressed overrides only.
//
// What this helper covers, and what it does not: it asserts the on-disk layout
// that makes the kernel's documented search order reachable, namely that
// /usr/lib/firmware is a real directory, that it is not backed by the
// persistent partition, and that a file written under /usr/local/lib/firmware
// is readable through /lib/firmware/updates. It never asks the kernel to load
// firmware, so it does not observe the loader choosing between two same-named
// blobs. That is not reachable from this suite: /usr is read-only at runtime,
// so a colliding blob cannot be planted in /usr/lib/firmware, and
// CONFIG_TEST_FIRMWARE is unset in every files/kernel/*.config, so the
// trigger_request interface that would let userspace see which file won is not
// built. Observing it in CI means building CONFIG_TEST_FIRMWARE=m and driving
// /sys/devices/virtual/misc/test_firmware/trigger_request, which is a kernel
// config change outside this PR.
func assertFirmwareLayout(vm VM) {
	By("checking the firmware directory is a real directory", func() {
		// A symlink here makes a firmware sysext replace the baked-in blobs
		// instead of merging with them: overlayfs merges two directories, but
		// an upper directory replaces a lower symlink outright.
		out, err := vm.Sudo("test -d /usr/lib/firmware && test ! -L /usr/lib/firmware && echo ok")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("ok"))
	})

	By("checking the firmware directory is not backed by the persistent partition", func() {
		fwDev, err := vm.Sudo("stat -c %d /usr/lib/firmware")
		Expect(err).ToNot(HaveOccurred(), fwDev)
		persistentDev, err := vm.Sudo("stat -c %d /usr/local")
		Expect(err).ToNot(HaveOccurred(), persistentDev)
		Expect(strings.TrimSpace(persistentDev)).ToNot(BeEmpty())
		Expect(strings.TrimSpace(fwDev)).ToNot(Equal(strings.TrimSpace(persistentDev)),
			"/usr/lib/firmware sits on the persistent partition, so blobs baked into the image are hidden")
	})

	By("checking the override directory resolves onto the persistent partition", func() {
		out, err := vm.Sudo("readlink /usr/lib/firmware/updates")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(strings.TrimSpace(out)).To(Equal("/usr/local/lib/firmware"))

		// The kernel opens the override path through /lib/firmware/updates, so
		// walk that exact path rather than the /usr/lib one.
		out, err = vm.Sudo("mkdir -p /usr/local/lib/firmware && " +
			"echo kairos-4290 > /usr/local/lib/firmware/kairos-4290.bin && " +
			"cat /lib/firmware/updates/kairos-4290.bin")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("kairos-4290"))

		out, err = vm.Sudo("rm -f /usr/local/lib/firmware/kairos-4290.bin")
		Expect(err).ToNot(HaveOccurred(), out)
	})
}

// assertRootfsShared verifies the rootfs is mounted as a shared mount.
func assertRootfsShared(vm VM) {
	By("checking rootfs shared mount", func() {
		out, err := vm.Sudo(`cat /proc/1/mountinfo | grep ' / / '`)
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("shared"))
	})
}

// assertNetworking verifies that networking is functional.
func assertNetworking(vm VM) {
	By("checking that networking is functional", func() {
		out, err := vm.Sudo(`curl google.it`)
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("Moved"))
	})
}

// assertInstallRecoveryServicesAbsent verifies the interactive install and
// recovery services are not present on a non-alpine flavor.
func assertInstallRecoveryServicesAbsent(vm VM) {
	By("Checking install/recovery services do not exist", func() {
		if !isFlavor(vm, "alpine") {
			for _, service := range []string{"kairos-interactive", "kairos-recovery"} {
				By(fmt.Sprintf("Checking that service %s does not exist", service), func() {})
				Eventually(func() string {
					out, _ := vm.Sudo(fmt.Sprintf("systemctl status %s", service))
					return out
				}, 3*time.Minute, 2*time.Second).Should(
					And(
						ContainSubstring(fmt.Sprintf("Unit %s.service could not be found", service)),
					),
				)
			}
		}
	})
}

// assertKairosState verifies the shared kairos state assertions: the OS name,
// flavor, and that the reported version matches the on-disk version.
func assertKairosState(vm VM) {
	currentVersion, err := vm.Sudo(getVersionCmd)
	ExpectWithOffset(1, err).ToNot(HaveOccurred(), currentVersion)

	stateAssertVM(vm, "kairos.version", strings.ReplaceAll(strings.ReplaceAll(currentVersion, "\r", ""), "\n", ""))
	stateContains(vm, "system.os.name", "hadron")
	stateContains(vm, "kairos.flavor", "hadron")
}

// assertSSHHardening verifies the STIG sshd policy hardening is in effect on a
// booted node. Uses `sshd -T` (effective config dump; host keys exist at
// runtime via sshkeygen.service). Keyword names in -T output are lowercased.
func assertSSHHardening(vm VM) {
	By("checking sshd STIG policy hardening is effective", func() {
		cfg, err := vm.Sudo("sshd -T")
		Expect(err).ToNot(HaveOccurred(), cfg)
		lc := strings.ToLower(cfg)
		for _, want := range []string{
			"permitrootlogin prohibit-password",
			"permitemptypasswords no",
			"permituserenvironment no",
			"ignorerhosts yes",
			"hostbasedauthentication no",
			"x11forwarding no",
			"allowtcpforwarding no",
			"maxauthtries 4",
			"logingracetime 60",
			"clientaliveinterval 600",
			"clientalivecountmax 1",
		} {
			Expect(lc).To(ContainSubstring(want), "expected effective sshd config to contain %q", want)
		}
	})
	By("checking password auth stays enabled (Kairos provisions users with passwords)", func() {
		cfg, err := vm.Sudo("sshd -T")
		Expect(err).ToNot(HaveOccurred(), cfg)
		Expect(strings.ToLower(cfg)).To(ContainSubstring("passwordauthentication yes"))
	})
}

// assertSSHCrypto verifies the sshd crypto matches the image's FIPS posture and,
// critically, that the STIG drop-in did NOT override the FIPS crypto in FIPS
// images (it sorts before the 100-* crypto file and sshd is first-value-wins).
func assertSSHCrypto(vm VM) {
	By("checking sshd crypto matches the FIPS posture", func() {
		cfg, err := vm.Sudo("sshd -T")
		Expect(err).ToNot(HaveOccurred(), cfg)
		lc := strings.ToLower(cfg)
		Expect(lc).To(ContainSubstring("aes256-gcm@openssh.com"))
		if fipsEnabled() {
			Expect(lc).ToNot(ContainSubstring("chacha20-poly1305"), "FIPS image must not offer chacha20 (STIG drop-in must not override FIPS crypto)")
			Expect(lc).ToNot(ContainSubstring("curve25519"), "FIPS image must not offer curve25519")
			Expect(lc).To(ContainSubstring("kexalgorithms ecdh-sha2-nistp256"))
		} else {
			Expect(lc).To(ContainSubstring("chacha20-poly1305"))
			Expect(lc).To(ContainSubstring("curve25519-sha256"))
		}
	})
}

// assertSysctlHardening verifies the GPOS/STIG sysctl baseline is applied on a
// booted node and, critically, that `sysctl --system` returns success: a key
// absent from the running kernel would make it fail, so the config-dependent
// keys (yama/kexec/sysrq/perf/bpf_jit) use the "-" ignore-if-missing prefix.
// Only universally-present keys are value-asserted here; the config-dependent
// ones and the k8s-safety omissions are checked structurally in the
// image-structure suite.
func assertSysctlHardening(vm VM) {
	By("checking sysctl --system applies cleanly (no missing-key failures)", func() {
		out, err := vm.Sudo("sysctl --system")
		Expect(err).ToNot(HaveOccurred(), out)
	})
	By("checking hardened sysctl values are in effect", func() {
		want := map[string]string{
			"kernel.kptr_restrict":                  "1",
			"kernel.dmesg_restrict":                 "1",
			"kernel.randomize_va_space":             "2",
			"kernel.unprivileged_bpf_disabled":      "1",
			"fs.suid_dumpable":                      "0",
			"fs.protected_symlinks":                 "1",
			"fs.protected_hardlinks":                "1",
			"net.ipv4.conf.all.accept_redirects":    "0",
			"net.ipv4.conf.all.accept_source_route": "0",
			"net.ipv6.conf.all.accept_redirects":    "0",
		}
		for key, val := range want {
			out, err := vm.Sudo("sysctl -n " + key)
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(strings.TrimSpace(out)).To(Equal(val), "sysctl %s should be %s", key, val)
		}
	})
}

// assertLegacyNetDisabled verifies the legacy network protocol modules (DCCP,
// RDS, TIPC, ATM, AX25, NETROM) are blocked from loading via modprobe.d.
func assertLegacyNetDisabled(vm VM) {
	By("checking legacy network protocols are blocked from loading", func() {
		for _, mod := range []string{"dccp", "rds", "tipc", "atm", "ax25", "netrom"} {
			// modprobe -n -v is a config-based dry run: with `install <mod>
			// /bin/false` it resolves to /bin/false and exits 0 even when the
			// module is not compiled, so this check is kernel-variant-agnostic.
			out, err := vm.Sudo("modprobe -n -v " + mod)
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(out).To(ContainSubstring("/bin/false"),
				"module %s must be blocked by install /bin/false", mod)
			// A real load attempt must not actually load it.
			vm.Sudo("modprobe " + mod + " >/dev/null 2>&1 || true")
			lsmod, err := vm.Sudo("lsmod")
			Expect(err).ToNot(HaveOccurred(), lsmod)
			Expect(lsmod).ToNot(MatchRegexp("(?m)^"+mod+`\\b`),
				"module %s must not be loaded", mod)
		}
	})
}

// assertLoginDefsHardening verifies the STIG login.defs hardening (password max
// age, successful-login logging, restrictive default umask) on a booted node.
func assertLoginDefsHardening(vm VM) {
	By("checking login.defs STIG hardening values", func() {
		out, err := vm.Sudo("cat /etc/login.defs")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(MatchRegexp(`(?m)^PASS_MAX_DAYS\s+60\b`), "PASS_MAX_DAYS should be 60")
		Expect(out).To(MatchRegexp(`(?m)^LOG_OK_LOGINS\s+yes\b`), "LOG_OK_LOGINS should be yes")
		Expect(out).To(MatchRegexp(`(?m)^UMASK\s+077\b`), "UMASK should be 077")
	})
}
