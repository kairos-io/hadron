# Post-install scripts

Each script here holds the post-install steps for one package: file modes,
ownership and similar fixups that the upstream install does not do. They are
the equivalent of a distro package's post-install hook.

- Name the script after the package, for example `pam.sh`.
- The `full-image-final` stage of the Dockerfile runs every `*.sh` here with
  `bash -eu`, in name order, on the final root filesystem. A failing command
  fails the build.
- Scripts are bind mounted during the build and are not copied into the image.
- Add a test in `tests/` for the behaviour the script fixes.
