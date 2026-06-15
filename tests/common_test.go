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
// FIPS remains a runtime env flag (CI sets FIPS=true on the tests-bios-fips job),
// so detection stays centralized here rather than scattered across specs.
func fipsEnabled() bool {
	return os.Getenv("FIPS") == "fips"
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
