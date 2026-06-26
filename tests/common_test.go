package hadron_test

import (
	"fmt"
	"os"
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

// assertPamPasswordPolicy verifies the STIG password-complexity hardening
// (kairos-io/kairos#4058 finding 6): pam_pwquality + pam_pwhistory are present,
// the hardened /etc/security/pwquality.conf ships, the modules are wired into
// the password stack (with nullok removed), and the policy functionally rejects
// weak passwords while accepting a strong one (which also proves the cracklib
// dictionary loaded). pwquality only gates interactive password changes; yip
// provisions by writing /etc/shadow directly, so this does not affect login.
func assertPamPasswordPolicy(vm VM) {
	By("checking the STIG PAM password-complexity stack is present", func() {
		out, err := vm.Sudo("ls /usr/lib/security/pam_pwquality.so /usr/lib/security/pam_pwhistory.so")
		Expect(err).ToNot(HaveOccurred(), out)
		out, err = vm.Sudo("command -v pwscore")
		Expect(err).ToNot(HaveOccurred(), out)
	})
	By("checking the hardened pwquality.conf values", func() {
		out, err := vm.Sudo("cat /etc/security/pwquality.conf")
		Expect(err).ToNot(HaveOccurred(), out)
		for _, want := range []string{"minlen = 15", "minclass = 4", "dictcheck = 1", "enforce_for_root"} {
			Expect(out).To(ContainSubstring(want), "pwquality.conf missing %q", want)
		}
	})
	By("checking pwquality/pwhistory are wired into the password stack (no nullok)", func() {
		out, err := vm.Sudo("cat /etc/pam.d/system-auth")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(MatchRegexp(`(?m)^password\s+requisite\s+pam_pwquality\.so`))
		Expect(out).To(MatchRegexp(`(?m)^password\s+requisite\s+pam_pwhistory\.so`))
		Expect(out).ToNot(MatchRegexp(`(?m)^password\s+.*pam_unix\.so.*\bnullok\b`),
			"nullok must be removed from the password stack")
	})
	By("checking pwquality rejects a weak password and accepts a strong one", func() {
		// weak -> non-zero exit (also exercises the cracklib dictcheck)
		_, err := vm.Sudo("echo 'weak' | pwscore")
		Expect(err).To(HaveOccurred(), "pwscore should reject a weak password")
		// strong -> score printed, exit 0 (proves pw_dict loaded and the policy passes)
		out, err := vm.Sudo("echo 'Zr7#kPq2!mNv4@Lx' | pwscore")
		Expect(err).ToNot(HaveOccurred(), out)
	})
}

// assertLastlog2 verifies the pam_lastlog2 last-login hardening
// (kairos-io/kairos#4058 finding 6; pam_lastlog was removed upstream in PAM 1.6).
// The module + CLI ship, and the current SSH session - which logs in through
// sshd -> system-login -> pam_lastlog2 - is recorded in the sqlite db.
func assertLastlog2(vm VM) {
	By("checking pam_lastlog2 module and CLI are present", func() {
		out, err := vm.Sudo("ls /usr/lib/security/pam_lastlog2.so")
		Expect(err).ToNot(HaveOccurred(), out)
		out, err = vm.Sudo("command -v lastlog2")
		Expect(err).ToNot(HaveOccurred(), out)
	})
	By("checking the SSH login was recorded by pam_lastlog2", func() {
		out, err := vm.Sudo("test -f /var/lib/lastlog/lastlog2.db && echo OK")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("OK"))
		records, err := vm.Sudo("lastlog2")
		Expect(err).ToNot(HaveOccurred(), records)
		Expect(records).To(ContainSubstring(user()))
	})
}
