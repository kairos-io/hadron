package hadron_test

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/disk"
	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/diskfs/go-diskfs/filesystem/iso9660"
	"github.com/google/uuid"
	process "github.com/mudler/go-processmanager"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	. "github.com/spectrocloud/peg/matcher"
	"github.com/spectrocloud/peg/pkg/controller"
	"github.com/spectrocloud/peg/pkg/machine"
	"github.com/spectrocloud/peg/pkg/machine/types"
)

func TestSuite(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "kairos Test Suite")
}

var getVersionCmd = ". /etc/kairos-release; [ ! -z \"$KAIROS_VERSION\" ] && echo $KAIROS_VERSION"

// CreateDatasource creates a datasource iso from a given user-data file
// And returns the path to the datasource iso
// Its the caller's responsibility to remove the datasource iso afterwards
func CreateDatasource(userDataFile string) string {
	ds, err := os.MkdirTemp("", "datasource-*")
	Expect(err).ToNot(HaveOccurred())
	diskImg := path.Join(ds, "datasource.iso")
	var diskSize int64 = 1 * 1024 * 1024 // 1 MB
	mydisk, err := diskfs.Create(diskImg, diskSize, diskfs.SectorSizeDefault)
	Expect(err).ToNot(HaveOccurred())
	mydisk.LogicalBlocksize = 2048
	fspec := disk.FilesystemSpec{Partition: 0, FSType: filesystem.TypeISO9660, VolumeLabel: "cidata"}
	fs, err := mydisk.CreateFilesystem(fspec)
	Expect(err).ToNot(HaveOccurred())
	rw, err := fs.OpenFile("user-data", os.O_CREATE|os.O_RDWR)
	Expect(err).ToNot(HaveOccurred())
	content, err := os.ReadFile(userDataFile)
	_, err = rw.Write(content)
	Expect(rw.Close()).ToNot(HaveOccurred())
	Expect(err).ToNot(HaveOccurred())
	rw, err = fs.OpenFile("meta-data", os.O_CREATE|os.O_RDWR)
	Expect(err).ToNot(HaveOccurred())
	_, err = rw.Write([]byte(""))
	Expect(rw.Close()).ToNot(HaveOccurred())
	Expect(err).ToNot(HaveOccurred())
	iso, ok := fs.(*iso9660.FileSystem)
	Expect(ok).To(BeTrue())
	err = iso.Finalize(iso9660.FinalizeOptions{RockRidge: true, VolumeIdentifier: "cidata"})
	Expect(err).ToNot(HaveOccurred())
	return diskImg
}

// https://gist.github.com/sevkin/96bdae9274465b2d09191384f86ef39d
// GetFreePort asks the kernel for a free open port that is ready to use.
func getFreePort() (port int, err error) {
	var a *net.TCPAddr
	if a, err = net.ResolveTCPAddr("tcp", "localhost:0"); err == nil {
		var l *net.TCPListener
		if l, err = net.ListenTCP("tcp", a); err == nil {
			defer l.Close()
			return l.Addr().(*net.TCPAddr).Port, nil
		}
	}
	return
}

func user() string {
	u := os.Getenv("SSH_USER")
	if u == "" {
		u = "kairos"
	}
	return u
}

func pass() string {
	p := os.Getenv("SSH_PASS")
	if p == "" {
		p = "kairos"
	}

	return p
}

// saveSerialLog copies the qemu serial console into logs/ and prints it.
//
// qemu writes that file on the host, so it is readable even when the VM is
// gone, and it is the only log that is. Everything else has to be fetched over
// SSH, so this one comes first.
func saveSerialLog(vm testVM) {
	serial, _ := os.ReadFile(filepath.Join(vm.StateDir, "serial.log"))
	_ = os.MkdirAll("logs", os.ModePerm|os.ModeDir)
	_ = os.WriteFile(filepath.Join("logs", "serial.log"), serial, os.ModePerm)
	fmt.Println(string(serial))
}

// gatherLogs collects what a failed spec left on the VM.
//
// It runs on a machine that has just failed, so an unreachable or rebooting VM
// is the normal case here and not an edge case. Every command goes through
// RootCommand for that reason: a vm.Sudo here would take the whole suite down
// with a panic, and it would do so from inside the handler whose only job is to
// preserve the evidence.
func gatherLogs(vm testVM) {
	// Use kairos-agent logs command to collect logs
	vm.RootCommand("kairos-agent logs --output /run/kairos-logs.tar.gz")

	// Collect additional system information not covered by kairos-agent logs
	vm.RootCommand("cat /oem/* > /run/oem.yaml")
	vm.RootCommand("cat /etc/resolv.conf > /run/resolv.conf")
	vm.RootCommand("k3s kubectl get pods -A -o json > /run/pods.json")
	vm.RootCommand("k3s kubectl get events -A -o json > /run/events.json")
	vm.RootCommand("cat /proc/cmdline > /run/cmdline")
	vm.RootCommand("chmod 777 /run/events.json")

	vm.RootCommand("df -h > /run/disk")
	vm.RootCommand("mount > /run/mounts")
	vm.RootCommand("blkid > /run/blkid")
	vm.RootCommand("dmesg > /run/dmesg.log")

	// Collect Kubernetes logs
	vm.Scp("assets/kubernetes_logs.sh", "/tmp/logs.sh", "0770")
	vm.RootCommand("sh /tmp/logs.sh > /run/kube_logs")

	gatherAllLogs(vmLogSink(vm), "logs",
		[]string{
			"edgevpn@kairos",
		},
		[]string{
			"/var/log/edgevpn.log",
			"/run/pods.json",
			"/run/disk",
			"/run/mounts",
			"/run/blkid",
			"/run/events.json",
			"/run/kube_logs",
			"/run/cmdline",
			"/run/oem.yaml",
			"/run/resolv.conf",
			"/run/dmesg.log",
			"/tmp/ovmf_debug.log",
			"/run/kairos-logs.tar.gz",
		})
}

// logSink is everything gatherAllLogs needs from a VM: run a command as root,
// and copy one file off the machine. Both report failure as an error, which is
// the whole point of the type, and it lets the plan be tested without a VM.
type logSink struct {
	run   func(cmd string) (string, error)
	fetch func(remotePath, localPath string) error
}

// vmLogSink binds a logSink to a running machine.
//
// peg's own vm.GatherAllLogs cannot be used here. Both it and the
// vm.GatherLog it calls about twenty times route through machineSudo, which
// panics from its own goroutine once the SSH session has died (see testVM). A
// failed spec is precisely when the VM is gone or rebooting, so that is the
// common case rather than the edge case, and the panic ends the test binary on
// the spot: the files the steps above just wrote on the VM are never copied off
// it, and no later spec runs. machine.Command and the SCP client both return
// errors instead.
func vmLogSink(vm testVM) logSink {
	return logSink{
		run: vm.RootCommand,
		fetch: func(remotePath, localPath string) error {
			f, err := os.Create(localPath)
			if err != nil {
				return err
			}
			defer f.Close()

			client := controller.NewSCPClient(vm.machine)
			if err := client.Connect(); err != nil {
				return err
			}
			defer client.Close()

			// A VM that answered the chmod can still stall mid-transfer, and
			// this runs inside AfterEach: without a deadline one wedged file
			// would hold the whole suite until the job timeout.
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			defer cancel()

			return client.CopyFromRemote(ctx, f, remotePath)
		},
	}
}

// gatherAllLogs collects the services and files peg's GatherAllLogs collects,
// into outDir, without ever taking the process down with it. Every step is
// best effort: a VM that cannot answer costs that one file, not the run.
func gatherAllLogs(s logSink, outDir string, services, logFiles []string) {
	for _, service := range services {
		path := fmt.Sprintf("/run/%s.log", service)
		runForLog(s, fmt.Sprintf("journalctl -u %s -o short-iso >> %s", service, path))
		gatherLog(s, outDir, path)
	}

	for _, file := range logFiles {
		gatherLog(s, outDir, file)
	}

	for _, extra := range []struct {
		cmds []string
		path string
	}{
		{[]string{"dmesg > /run/dmesg"}, "/run/dmesg"},
		{[]string{"journalctl -o short-iso > /run/journal.log"}, "/run/journal.log"},
		{[]string{"uname -a > /run/uname.log"}, "/run/uname.log"},
		{[]string{"lsblk -a >> /run/disks.log", "blkid >> /run/disks.log"}, "/run/disks.log"},
	} {
		for _, cmd := range extra.cmds {
			runForLog(s, cmd)
		}
		gatherLog(s, outDir, extra.path)
	}

	gatherLog(s, outDir, "/etc/passwd")
	gatherLog(s, outDir, "/etc/os-release")
}

// runForLog runs one gathering command and reports a failure without raising.
func runForLog(s logSink, cmd string) {
	if out, err := s.run(cmd); err != nil {
		fmt.Printf("Error running %q: %s\nOutput: %s\n", cmd, err, out)
	}
}

// gatherLog copies one file from the VM into outDir, world readable so the
// CI artifact upload can read it.
func gatherLog(s logSink, outDir, remotePath string) {
	if out, err := s.run("chmod 777 " + remotePath); err != nil {
		fmt.Printf("Couldn't change permissions on %s: %s\nOutput: %s\n", remotePath, err, out)
		return
	}

	if err := os.MkdirAll(outDir, 0755); err != nil {
		fmt.Printf("Couldn't create %s: %s\n", outDir, err)
		return
	}

	localPath := filepath.Join(outDir, filepath.Base(remotePath))
	if err := s.fetch(remotePath, localPath); err != nil {
		fmt.Printf("Error while copying %s: %s\n", remotePath, err)
		return
	}

	_ = os.Chmod(localPath, 0666)
	fmt.Printf("File %s copied!\n", remotePath)
}

// return the PID of the swtpm (to be killed later) and the state directory
func emulateTPM(stateDir string) {
	t := path.Join(stateDir, "tpm")
	err := os.MkdirAll(t, os.ModePerm)
	Expect(err).ToNot(HaveOccurred())

	cmd := exec.Command("swtpm",
		"socket",
		"--tpmstate", fmt.Sprintf("dir=%s", t),
		"--ctrl", fmt.Sprintf("type=unixio,path=%s/swtpm-sock", t),
		"--tpm2", "--log", "level=20")
	err = cmd.Start()
	Expect(err).ToNot(HaveOccurred())

	err = os.WriteFile(path.Join(t, "pid"), []byte(strconv.Itoa(cmd.Process.Pid)), 0744)
	Expect(err).ToNot(HaveOccurred())
}

// testVM is peg's VM plus the machine it was built from.
//
// peg keeps the machine unexported and reaches it through vm.Sudo, which runs
// `sudo /bin/sh` and feeds the command into the session's stdin from a
// goroutine of its own. If the SSH session dies while that write is in flight,
// io.Copy returns an error and the goroutine panics (peg
// matcher/helpers.go:226). A panic on a goroutine Ginkgo does not own takes the
// whole test binary down: no spec failure, no AfterEach, so no gatherLogs and
// no serial console either. Keeping the machine lets the suite call Command
// instead, which is session.CombinedOutput and returns an error.
type testVM struct {
	VM
	machine types.Machine
}

// RootCommand runs cmd as root over a fresh SSH session and returns an error,
// never a panic, when the VM is rebooting or already gone.
//
// cmd still runs under /bin/sh as root, so redirections inside it are performed
// by the root shell exactly as they are with vm.Sudo.
func (v testVM) RootCommand(cmd string) (string, error) {
	return v.machine.Command("sudo /bin/sh -c " + shellQuote(cmd))
}

// shellQuote wraps s in single quotes so /bin/sh sees it as one word.
//
// RootCommand passes the caller's command as an argument to `sh -c`, which
// means it travels through one more shell than vm.Sudo's stdin did, and the
// gathering commands are full of redirections and globs that must survive it.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func startVM() (context.Context, testVM) {
	stateDir, err := os.MkdirTemp("", "")
	Expect(err).ToNot(HaveOccurred())
	fmt.Printf("State dir: %s\n", stateDir)

	opts := defaultVMOpts(stateDir)

	m, err := machine.New(opts...)
	Expect(err).ToNot(HaveOccurred())

	vm := testVM{VM: NewVM(m, stateDir), machine: m}

	ctx, err := vm.Start(context.Background())
	Expect(err).ToNot(HaveOccurred())

	return ctx, vm
}

func isFlavor(vm testVM, flavor string) bool {
	out, err := vm.Sudo(fmt.Sprintf("cat /etc/os-release | grep ID=%s", flavor))
	return err == nil && out != ""
}

func expectDefaultService(vm testVM) {
	By("checking if default service is active in live cd mode", func() {
		if isFlavor(vm, "alpine") {
			out, err := vm.Sudo("rc-status")
			Expect(err).ToNot(HaveOccurred(), out)
			Expect(out).Should(ContainSubstring("kairos-agent"))
		} else {
			// This is also run in the upgrade latest, so we need to check for both kairos-installer and kairos in case the service name changed.
			// kairos-interactive is the third name: AuroraBoot collapsed the three GRUB
			// install entries into one that boots with install-mode-interactive, and
			// 52_installer.yaml writes kairos-interactive.service for that keyword
			// instead of kairos-installer.service. It is the same dispatcher, it runs
			// AutoInstall first, so an auto config still installs unattended.
			Eventually(func() string {
				out, _ := vm.Sudo("systemctl status kairos-installer || systemctl status kairos-interactive || systemctl status kairos")
				return out
			}, 3*time.Minute, 2*time.Second).Should(
				Or(
					ContainSubstring("loaded (/etc/systemd/system/kairos-installer.service; enabled;"),
					ContainSubstring("loaded (/etc/systemd/system/kairos-interactive.service; enabled;"),
					ContainSubstring("loaded (/etc/systemd/system/kairos.service; enabled;"),
				))
		}
	})
}

func expectStartedInstallation(vm testVM) {
	By("checking that installation has started (via journald logs)", func() {
		Eventually(func() string {
			out, _ := vm.RootCommand("journalctl -t kairos-agent --no-pager")
			return out
		}, 30*time.Minute, 1*time.Second).Should(ContainSubstring("kairos-install.after"))
	})
}

func expectRebootedToActive(vm testVM) {
	By("checking that vm has rebooted to 'active'", func() {
		Eventually(func() string {
			out, _ := vm.RootCommand("kairos-agent state get boot")
			return out
		}, 40*time.Minute, 10*time.Second).Should(
			Or(
				ContainSubstring("active_boot"),
			))
	})
}

func defaultVMOpts(stateDir string) []types.MachineOption {
	opts := defaultVMOptsNoDrives(stateDir)

	driveSize := os.Getenv("DRIVE_SIZE")
	if driveSize == "" {
		driveSize = "25000"
	}

	opts = append(opts, types.WithDriveSize(driveSize))

	return opts
}

func defaultVMOptsNoDrives(stateDir string) []types.MachineOption {
	var err error

	if os.Getenv("ISO") == "" && os.Getenv("CREATE_VM") == "true" {
		fmt.Println("ISO missing")
		os.Exit(1)
	}

	var sshPort, spicePort int

	vmName := uuid.New().String()

	// Always setup a tpm emulator
	emulateTPM(stateDir)

	sshPort, err = getFreePort()
	Expect(err).ToNot(HaveOccurred())
	fmt.Printf("Using ssh port: %d\n", sshPort)

	memory := os.Getenv("MEMORY")
	if memory == "" {
		memory = "2096"
	}
	cpus := os.Getenv("CPUS")
	if cpus == "" {
		cpus = "2"
	}

	opts := []types.MachineOption{
		types.QEMUEngine,
		types.WithISO(os.Getenv("ISO")),
		types.WithMemory(memory),
		types.WithCPU(cpus),
		types.WithSSHPort(strconv.Itoa(sshPort)),
		types.WithID(vmName),
		types.WithSSHUser(user()),
		types.WithSSHPass(pass()),
		types.OnFailure(func(p *process.Process) {
			// peg calls this from the goroutine it starts in
			// machine.monitor, not from a Ginkgo node, so the Fail below
			// needs a GinkgoRecover to be turned into a spec failure
			// instead of an unrecovered panic.
			defer GinkgoRecover()

			var serial string

			out, _ := os.ReadFile(p.StdoutPath())
			err, _ := os.ReadFile(p.StderrPath())
			status, _ := p.ExitCode()

			if serialBytes, err := os.ReadFile(path.Join(p.StateDir(), "serial.log")); err != nil {
				serial = fmt.Sprintf("Error reading serial log file: %s\n", err)
			} else {
				serial = string(serialBytes)
			}

			// We are explicitly killing the qemu process. We don't treat that as an error,
			// but we just print the output just in case.
			fmt.Printf("\nVM Aborted.\nstdout: %s\nstderr: %s\nserial: %s\nExit status: %s\n", out, err, serial, status)
			Fail(fmt.Sprintf("\nVM Aborted.\nstdout: %s\nstderr: %s\nserial: %s\nExit status: %s\n",
				out, err, serial, status))
		}),
		types.WithStateDir(stateDir),
		// Serial output to file: https://superuser.com/a/1412150
		func(m *types.MachineConfig) error {
			m.Args = append(m.Args,
				"-chardev", fmt.Sprintf("stdio,mux=on,id=char0,logfile=%s,signal=off", path.Join(stateDir, "serial.log")),
				"-serial", "chardev:char0",
				"-mon", "chardev=char0",
			)
			if os.Getenv("EMULATE_TPM") != "" {
				m.Args = append(m.Args,
					"-chardev", fmt.Sprintf("socket,id=chrtpm,path=%s/swtpm-sock", path.Join(stateDir, "tpm")),
					"-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-tis,tpmdev=tpm0",
				)
			}
			return nil
		},
		// Firmware
		func(m *types.MachineConfig) error {
			FW := os.Getenv("FIRMWARE")
			if FW != "" {
				getwd, err := os.Getwd()
				if err != nil {
					return err
				}
				m.Args = append(m.Args, "-drive",
					fmt.Sprintf("file=%s,if=pflash,format=raw,readonly=on", FW),
				)

				// Set custom vars file for efi config so we boot first from disk then from DVD with secureboot on
				UKI := os.Getenv("UKI_TEST")
				if UKI != "" {
					// On uki use an empty efivars.fd so we can test the autoenrollment
					m.Args = append(m.Args, "-drive",
						fmt.Sprintf("file=%s,if=pflash,format=raw", filepath.Join(getwd, "assets/efivars.empty.fd")),
					)
				} else {
					m.Args = append(m.Args, "-drive",
						fmt.Sprintf("file=%s,if=pflash,format=raw", filepath.Join(getwd, "assets/efivars.fd")),
					)
				}
				// Needed to be set for secureboot!
				m.Args = append(m.Args, "-machine", "q35,smm=on")
			}

			return nil
		},
		types.WithDataSource(os.Getenv("DATASOURCE")),
	}
	if os.Getenv("KVM") != "" {
		opts = append(opts, func(m *types.MachineConfig) error {
			m.Args = append(m.Args,
				"-enable-kvm",
			)
			return nil
		})
	}

	if os.Getenv("USE_QEMU") == "true" {
		opts = append(opts, types.QEMUEngine)

		// You can connect to it with "spicy" or other tool.
		// DISPLAY is already taken on Linux X sessions
		if os.Getenv("MACHINE_SPICY") != "" {
			spicePort, _ = getFreePort()
			for spicePort == sshPort { // avoid collision
				spicePort, _ = getFreePort()
			}
			display := fmt.Sprintf("-spice port=%d,addr=127.0.0.1,disable-ticketing=yes", spicePort)
			opts = append(opts, types.WithDisplay(display))

			cmd := exec.Command("spicy",
				"-h", "127.0.0.1",
				"-p", strconv.Itoa(spicePort))
			err = cmd.Start()
			Expect(err).ToNot(HaveOccurred())
		}
	} else {
		opts = append(opts, types.VBoxEngine)
	}

	return opts
}

var stateAssertVM = func(vm testVM, query, expected string) {
	out, err := vm.Sudo(fmt.Sprintf("kairos-agent state get %s", query))
	ExpectWithOffset(1, err).ToNot(HaveOccurred(), out)
	ExpectWithOffset(1, out).To(ContainSubstring(expected))
}
