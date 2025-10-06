// nolint
package hadron_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	. "github.com/spectrocloud/peg/matcher"
	"github.com/spectrocloud/peg/pkg/machine"
	"github.com/spectrocloud/peg/pkg/machine/types"
)

var _ = Describe("kairos custom partitioning install", Label("custom-partitioning"), func() {
	var vm VM
	var datasource string

	BeforeEach(func() {
		stateDir, err := os.MkdirTemp("", "")
		Expect(err).ToNot(HaveOccurred())
		fmt.Printf("State dir: %s\n", stateDir)

		datasource = CreateDatasource("assets/custom-partition.yaml")
		Expect(os.Setenv("DATASOURCE", datasource)).ToNot(HaveOccurred())

		opts := defaultVMOptsNoDrives(stateDir)
		opts = append(opts, types.WithDriveSize("40000"))
		opts = append(opts, types.WithDriveSize("30000"))

		m, err := machine.New(opts...)
		Expect(err).ToNot(HaveOccurred())
		vm = NewVM(m, stateDir)
		_, err = vm.Start(context.Background())
		Expect(err).ToNot(HaveOccurred())

		By("waiting for VM to be up for the first time")
		vm.EventuallyConnects(1200)
		expectDefaultService(vm)
		expectStartedInstallation(vm)
		expectRebootedToActive(vm)
	})

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

	It("installs on the pre-configured disks", func() {
		// In qemu it's tricky to boot the second disk. In multiple disk scenarios,
		// setting "-boot=cd" will make qemu try to boot from the first disk and
		// then from the cdrom.
		// We want to make sure that kairos-agent selected the second disk so we
		// simply let it boot from the cdrom again. Hopefully if the installation
		// failed, we would see the error from the manual-install command.
		vm.Reboot()
		vm.EventuallyConnects(1200)

		By("Checking the partition")
		out, err := vm.Sudo("blkid")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(MatchRegexp("/dev/vdb2.*LABEL=\"COS_OEM\""), out)
		Expect(out).To(MatchRegexp("/dev/vdb3.*LABEL=\"COS_RECOVERY\""), out)
		Expect(out).To(MatchRegexp("/dev/vdb4.*LABEL=\"COS_STATE\""), out)
		Expect(out).To(MatchRegexp("/dev/vdb5.*LABEL=\"COS_PERSISTENT\""), out)

		// Sanity check that the default disk is not touched
		Expect(out).ToNot(MatchRegexp("/dev/vda.*LABEL=\"COS_PERSISTENT\""), out)
	})
})
