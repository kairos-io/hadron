package hadron_test

import (
	"errors"
	"os"
	"os/exec"
	"slices"
	"testing"
)

func TestFIPSEnabled(t *testing.T) {
	t.Setenv("FIPS", "fips")
	if !fipsEnabled() {
		t.Fatal("expected FIPS=fips to enable FIPS mode")
	}

	t.Setenv("FIPS", "true")
	if !fipsEnabled() {
		t.Fatal("expected FIPS=true to enable FIPS mode")
	}

	t.Setenv("FIPS", "no-fips")
	if fipsEnabled() {
		t.Fatal("expected FIPS=no-fips to disable FIPS mode")
	}

	_ = os.Unsetenv("FIPS")
	if fipsEnabled() {
		t.Fatal("expected unset FIPS to disable FIPS mode")
	}
}

// TestShellQuoteRoundTrip runs the quoting through a real /bin/sh, because the
// only property that matters is that sh -c sees exactly one word, byte for
// byte, including the redirections and globs the gathering commands use.
func TestShellQuoteRoundTrip(t *testing.T) {
	for _, cmd := range []string{
		"cat /oem/* > /run/oem.yaml",
		"k3s kubectl get pods -A -o json > /run/pods.json",
		`dmesg|grep -i secure| grep -i enabled`,
		"journalctl -u edgevpn@kairos -o short-iso >> /run/edgevpn@kairos.log",
		"echo it's quoted",
		"echo $HOME `id` \"x\"",
		". /etc/kairos-release; [ ! -z \"$KAIROS_VERSION\" ] && echo $KAIROS_VERSION",
	} {
		// printf %s of the quoted word reproduces the original only if the
		// outer shell treated it as a single, fully literal argument.
		out, err := exec.Command("/bin/sh", "-c", "printf %s "+shellQuote(cmd)).Output()
		if err != nil {
			t.Fatalf("shellQuote(%q): %v", cmd, err)
		}
		if string(out) != cmd {
			t.Errorf("shellQuote(%q) round-tripped to %q", cmd, out)
		}
	}
}

// TestGatherAllLogsIsBestEffort pins the behaviour the e2e suite depends on:
// a VM that answers nothing must still cost only the files, never the run.
func TestGatherAllLogsIsBestEffort(t *testing.T) {
	var ran, fetched []string

	s := logSink{
		run: func(cmd string) (string, error) {
			ran = append(ran, cmd)
			return "", errors.New("connection lost")
		},
		fetch: func(remotePath, localPath string) error {
			fetched = append(fetched, remotePath)
			return errors.New("connection lost")
		},
	}

	gatherAllLogs(s, t.TempDir(), []string{"edgevpn@kairos"}, []string{"/var/log/edgevpn.log"})

	// Every chmod failed, so no fetch should have been attempted, and the
	// call must have returned rather than raised.
	if len(fetched) != 0 {
		t.Errorf("fetched %v after every chmod failed", fetched)
	}
	if len(ran) == 0 {
		t.Fatal("gatherAllLogs ran no commands at all")
	}
}

// TestGatherAllLogsCollectsThePegSet asserts the replacement still gathers
// what peg's GatherAllLogs did, so swapping it out loses no evidence.
func TestGatherAllLogsCollectsThePegSet(t *testing.T) {
	var fetched []string

	s := logSink{
		run:   func(string) (string, error) { return "", nil },
		fetch: func(remotePath, localPath string) error { fetched = append(fetched, remotePath); return nil },
	}

	gatherAllLogs(s, t.TempDir(), []string{"edgevpn@kairos"}, []string{"/var/log/edgevpn.log"})

	for _, want := range []string{
		"/run/edgevpn@kairos.log",
		"/var/log/edgevpn.log",
		"/run/dmesg",
		"/run/journal.log",
		"/run/uname.log",
		"/run/disks.log",
		"/etc/passwd",
		"/etc/os-release",
	} {
		if !slices.Contains(fetched, want) {
			t.Errorf("gatherAllLogs did not collect %s, got %v", want, fetched)
		}
	}
}
