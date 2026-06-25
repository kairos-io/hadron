package hadron_test

import (
	"os"
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
