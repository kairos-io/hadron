Some comments about dev here.


# Size reduction in OS components

- Try to compile everything with `-Os` for make or in the case of meson builds `--buildtype=minsize`
- We strip at the end, but if you build with meson, there is a switch to do it automatically which works nicely `-Dstrip=true` and valid for all meson builds
- If you have a single dep only used by a single program, build it static. If its not used by any other thing in the final system, its much nicer to encrust whatever is needed in the final app rather than have the full shared lib which is only used by a single program.
- Try to reduce build options to what we need, for example TPM2 lib builds a lot of libraries by default but we dont need but a small subset to support luks encryption via TPM, so try to check the configure options and be selective

# golang size reduction

- Do not compress with upx. It used to head this list, and it is now off the table for every Kairos Go binary, for two reasons. A packed binary unpacks itself at run time through a `memfd:upx` mapping, and on riscv64 under `qemu-system-riscv64 -accel tcg` that mapping faults: a packed `immucore` died with `unhandled signal 11` before the live root overlay was set up, and the same ISO booted once the binary was left unpacked (kairos-io/kairos#4089). A packed binary also hides its Go module metadata, so a scanner reads zero packages out of it, and `kairos-io/kairos/.github/workflows/release-scan.yml` is a release gate that fails on exactly that, because zero extracted packages is a broken scan rather than a clean one. Use the flags below instead
- use the cflags `-w -s` to drop uneeded debug and trace stuff. Sucks for debugging but reduces the size a lot
- use the gcflags `-l` which disables function inlining
- if you are starved for size, you can use the gcflags `-B` which disables bounds checks. This reduces the size a lot (relative) but its a bit unsafe as out of bound errors no longer panic...
- use gsa https://github.com/Zxilly/go-size-analyzer to analyze go binaries and understand where the sizes are coming from
