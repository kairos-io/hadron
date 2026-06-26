package hadron_test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/types"
	. "github.com/spectrocloud/peg/matcher"
)

var stateContains = func(vm VM, query string, expected ...string) {
	var or []types.GomegaMatcher
	for _, e := range expected {
		or = append(or, ContainSubstring(e))
	}
	out, err := vm.Sudo(fmt.Sprintf("kairos-agent state get %s", query))
	ExpectWithOffset(1, err).ToNot(HaveOccurred())
	ExpectWithOffset(1, strings.ToLower(out)).To(Or(or...))
}

var _ = Describe("kairos basic test", func() {
	var vm VM
	var datasource string

	// BeforeEach only brings the live-CD VM up so that an install/reboot failure
	// is reported against the test that exercises it, not as a setup failure.
	// The actual install + reboot-to-active is an explicit step in each It below
	// (see installAndBootToActive).
	BeforeEach(func() {
		datafile := "assets/acceptance.yaml"
		if fipsEnabled() {
			datafile = "assets/acceptance-fips.yaml"
		}
		datasource = CreateDatasource(datafile)
		Expect(os.Setenv("DATASOURCE", datasource)).ToNot(HaveOccurred())
		_, vm = startVM()
		vm.EventuallyConnects(600)
		expectDefaultService(vm)
	})

	// installAndBootToActive performs the install assertion and the reboot into
	// the installed system. It used to live in the BeforeEach, which meant an
	// install failure looked like a setup failure; it is now an explicit,
	// clearly-labeled part of each spec's flow.
	installAndBootToActive := func() {
		By("Installing and booting to active", func() {
			expectStartedInstallation(vm)
			By("Rebooting into installed system")
			vm.Reboot()
			expectRebootedToActive(vm)
		})
	}

	AfterEach(func() {
		if CurrentSpecReport().Failed() {
			gatherLogs(vm)
			serial, _ := os.ReadFile(filepath.Join(vm.StateDir, "serial.log"))
			_ = os.MkdirAll("logs", os.ModePerm|os.ModeDir)
			_ = os.WriteFile(filepath.Join("logs", "serial.log"), serial, os.ModePerm)
			fmt.Println(string(serial))
		}

		err := vm.Destroy(nil)
		Expect(err).ToNot(HaveOccurred())

		Expect(os.Unsetenv("DATASOURCE")).ToNot(HaveOccurred())
		Expect(os.Remove(datasource)).ToNot(HaveOccurred())
	})

	It("passes checks", Label("acceptance", "fips"), func() {
		installAndBootToActive()

		if fipsEnabled() {
			assertFIPSEnabled(vm)
		}
		By("checking grubenv file", func() {
			out, err := vm.Sudo("cat /oem/grubenv")
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(out).To(ContainSubstring("foobarzz"))
		})

		By("checking custom cmdline", func() {
			out, err := vm.Sudo("cat /proc/cmdline")
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("foobarzz"))
		})

		By("checking the use of dracut immutable module", func() {
			out, err := vm.Sudo("cat /proc/cmdline")
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("cos-img/filename="))
		})

		By("checking Auto assessment", func() {
			// Auto assessment was installed
			out, _ := vm.Sudo("cat /run/initramfs/cos-state/grubcustom")
			Expect(out).To(ContainSubstring("bootfile_loc"))

			out, _ = vm.Sudo("cat /run/initramfs/cos-state/grub_boot_assessment")
			Expect(out).To(ContainSubstring("boot_assessment_blk"))

			cmdline, _ := vm.Sudo("cat /proc/cmdline")
			Expect(cmdline).To(ContainSubstring("rd.emergency=reboot rd.shell=0"))
			Expect(cmdline).To(ContainSubstring("panic=5"))
			Expect(cmdline).To(ContainSubstring("rd.shell=0"))
		})

		assertWriteableTmp(vm)

		assertBpfMounted(vm)

		By("checking correct permissions", func() {
			out, err := vm.Sudo(`stat -c "%a" /oem`)
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("770"))

			out, err = vm.Sudo(`stat -c "%a" /usr/local/cloud-config`)
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("770"))
		})

		By("checking grubmenu", func() {
			// Statereset is now part of the default grub.cfg
			out, err := vm.Sudo("cat /etc/cos/grub.cfg")
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("--id cos"))
			Expect(out).To(ContainSubstring("--id fallback"))
			Expect(out).To(ContainSubstring("--id recovery"))
			Expect(out).To(ContainSubstring("--id statereset"))
			// Now this one you can override with a custom grubmenu but by default we ship the remote recovery on it
			out, err = vm.Sudo("cat /run/initramfs/cos-state/grubmenu")
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("remoterecovery"))
		})

		By("checking additional mount specified, with no dir in rootfs", func() {
			out, err := vm.Sudo("mount")
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("/var/lib/longhorn"))
		})

		assertRootfsShared(vm)

		By("checking that it doesn't has grub data into the cloud config", func() {
			out, err := vm.Sudo(`cat /oem/90_custom.yaml`)
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(out).ToNot(ContainSubstring("vga_text"))
			Expect(out).ToNot(ContainSubstring("videotest"))
		})

		assertNetworking(vm)

		assertSSHHardening(vm)
		assertSSHCrypto(vm)
		assertSysctlHardening(vm)
		assertLegacyNetDisabled(vm)
		assertLoginDefsHardening(vm)

		By("checking custom CA installation", func() {
			out, err := vm.Sudo(`set -eu
# On a booted Kairos node the persistent partition mounts over /usr/local,
# shadowing the image's dir, so recreate it before writing the cert.
mkdir -p /usr/local/share/ca-certificates
openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
  -subj "/CN=hadron-custom-ca" \
  -keyout /tmp/hadron-custom-ca.key \
  -out /usr/local/share/ca-certificates/hadron-custom-ca.crt \
  >/tmp/hadron-custom-ca.openssl.log 2>&1
update-ca-certificates
# Alpine's update-ca-certificates names per-cert symlinks ca-cert-<name>.pem
test -L /etc/ssl/certs/ca-cert-hadron-custom-ca.pem
openssl x509 -in /etc/ssl/certs/ca-cert-hadron-custom-ca.pem -noout -subject`)
			Expect(err).ToNot(HaveOccurred(), out)
			// openssl prints "CN = ..." or "CN=..." depending on version; match both.
			Expect(out).To(MatchRegexp(`CN\s*=\s*hadron-custom-ca`))
		})

		By("checking the sysctl(8) CLI is present and functional", func() {
			// procps-ng sysctl ships in the final image (not the container
			// base) so consumers like Stylus can run `sysctl --system`.
			// systemd-sysctl is not a substitute for the CLI.
			out, err := vm.Sudo("command -v sysctl")
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(out).To(ContainSubstring("/sysctl"))

			out, err = vm.Sudo("sysctl --version")
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(out).To(ContainSubstring("procps-ng"))

			// Reading a key and applying drop-in config must both succeed.
			out, err = vm.Sudo("sysctl -n kernel.ostype")
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(out).To(ContainSubstring("Linux"))

			out, err = vm.Sudo("sysctl --system")
			Expect(err).ToNot(HaveOccurred(), out)
		})

		By("checking SYN cookies are available (CONFIG_SYN_COOKIES)", func() {
			// CONFIG_SYN_COOKIES is now enabled on every kernel variant (it was
			// absent on cloud/riscv64), so net.ipv4.tcp_syncookies exists and
			// defaults to 1. This is what lets the sysctl hardening baseline
			// actually enforce SYN-flood protection on the cloud kernel.
			out, err := vm.Sudo("sysctl -n net.ipv4.tcp_syncookies")
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(strings.TrimSpace(out)).To(Equal("1"))
		})

		assertPamPasswordPolicy(vm)
		assertLastlog2(vm)

		By("checking corresponding state", func() {
			out, err := vm.Sudo("kairos-agent state")
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("boot: active_boot"))

			stateAssertVM(vm, "oem.mounted", "true")
			stateAssertVM(vm, "oem.found", "true")
			stateAssertVM(vm, "persistent.mounted", "true")
			stateAssertVM(vm, "state.mounted", "true")
			stateAssertVM(vm, "oem.type", "ext4")
			stateAssertVM(vm, "persistent.type", "ext4")
			stateAssertVM(vm, "state.type", "ext4")
			stateAssertVM(vm, "oem.mount_point", "/oem")
			stateAssertVM(vm, "persistent.mount_point", "/usr/local")
			stateAssertVM(vm, "persistent.name", "/dev/vda")
			stateAssertVM(vm, "state.mount_point", "/run/initramfs/cos-state")
			stateAssertVM(vm, "oem.read_only", "false")
			stateAssertVM(vm, "persistent.read_only", "false")
			stateAssertVM(vm, "state.read_only", "true")

			assertKairosState(vm)
		})

		assertInstallRecoveryServicesAbsent(vm)

		By("Checking that k9s bundle is present", func() {
			k9s, err := vm.Sudo("k9s version")
			Expect(err).ToNot(HaveOccurred(), k9s)
			Expect(k9s).To(ContainSubstring("v0.50.9"))
		})
	})
	It("resets", Label("reset", "fips"), func() {
		installAndBootToActive()

		if fipsEnabled() {
			assertFIPSEnabled(vm)
		}

		Eventually(func() string {
			out, _ := vm.Sudo("cat /oem/grubenv")
			return out
		}, 10*time.Minute, 1*time.Second).Should(
			Or(
				ContainSubstring("foobarzz"),
			))

		By("Creating files on persistent and oem")
		_, err := vm.Sudo("touch /usr/local/test")
		Expect(err).ToNot(HaveOccurred())

		_, err = vm.Sudo("touch /oem/test")
		Expect(err).ToNot(HaveOccurred())

		vm.HasFile("/oem/test")
		vm.HasFile("/usr/local/test")
		By("Setting the next entry to statereset")
		_, err = vm.Sudo("grub2-editenv /oem/grubenv set next_entry=statereset")
		Expect(err).ToNot(HaveOccurred())
		By("Rebooting")
		vm.Reboot()

		expectRebootedToActive(vm)

		By("Checking that persistent file is gone")
		Eventually(func() string {
			out, _ := vm.Sudo("if [ -f /usr/local/test ]; then echo ok; else echo wrong; fi")
			return out
		}, 3*time.Minute, 1*time.Second).Should(
			Or(
				ContainSubstring("wrong"),
			))
		By("Checking that oem file is still there")
		Eventually(func() string {
			out, _ := vm.Sudo("if [ -f /oem/test ]; then echo ok; else echo wrong; fi")
			return out
		}, 3*time.Minute, 1*time.Second).Should(
			Or(
				ContainSubstring("ok"),
			))
	})
})
