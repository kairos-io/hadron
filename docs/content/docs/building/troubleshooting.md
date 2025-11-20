---
title: "Troubleshooting"
weight: 15
---

# Troubleshooting

### Build Fails with "Out of Memory"

By default we set the number of jobs for building to the number of processors availabel in the machine.
In some environments like CI or K8s pods this can lead to the processes being killed due too much CPU usage.
You can try to reduce the parallel jobs by setting the `JOBS` variable when building:

```bash
make build JOBS=4
```

### ISO Not Found After Build

Check the build directory:

```bash
ls -lh build/
```

The Makefile should print the exact path, but if not:

```bash
find build -name "*.iso" -type f
```

### Keys Not Found

Ensure your `KEYS_DIR` contains all required files:

```bash
ls -la ${KEYS_DIR}/
```

Required files:
- `tpm2-pcr-private.pem`
- `db.key`
- `db.pem`
- `db.auth`
- `KEK.auth`
- `PK.auth`

### Docker Build Context Issues

Ensure you're running commands from the repository root:

```bash
cd /path/to/hadron
make build
```
