#!/bin/bash
set +e
failures=0

echo "Starting binary verification..."

# List of directories to check
DIRS="/bin /sbin /usr/bin /usr/sbin"


for dir in $DIRS; do
    # check if the dir is a symlink
    if [ -L "$dir" ]; then
        echo "Skipping symlink: $dir"
        continue
    fi
    if [ -d "$dir" ]; then
        echo "Checking directory: $dir"
        for bin in "$dir"/*; do
            # Check if file exists and is executable
            if [ -f "$bin" ] && [ -x "$bin" ]; then
                # Run with timeout
                # We redirect stdout/stderr to null to reduce noise
                echo "Checking binary: $bin"
                timeout 1s "$bin" --help >/dev/null 2>&1
                rc=$?

                # Check for crash signals
                # 139 = SIGSEGV (Segmentation fault)
                # 132 = SIGILL (Illegal instruction)
                # 134 = SIGABRT (Abort)
                # 133 = SIGTRAP (Trace/breakpoint trap)
                # 136 = SIGFPE (Floating point exception)
                # 138 = SIGBUS (Bus error)
                if [ $rc -eq 139 ] || [ $rc -eq 132 ] || [ $rc -eq 134 ] || [ $rc -eq 133 ] || [ $rc -eq 136 ] || [ $rc -eq 138 ]; then
                    echo "❌ FAILED: $bin crashed with exit code $rc"
                    failures=$((failures+1))
                #else
                #    echo "✅ OK: $bin"
                fi
            fi
        done
    else
        echo "Directory $dir not found, skipping."
    fi
done

if [ $failures -gt 0 ]; then
    echo "❌ Verification FAILED: $failures binaries crashed."
    exit 1
else
    echo "✅ Verification PASSED: All binaries executed without crashing."
    exit 0
fi
