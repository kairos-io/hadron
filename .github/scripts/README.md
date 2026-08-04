# CI helper scripts

Small scripts used by the GitHub Actions workflows in `.github/workflows/`.

## Image size tooling

Two complementary tools track the uncompressed size (`docker image inspect
.Size`, amd64) of the shipped images. They share the canonical list of tracked
variants and the `human()` byte formatter via `size-history-lib.sh`, so the list
of images only lives in one place.

### `image-size-report.sh` — per-PR report

Used by the `image-size-report` job in `PR_multiarch.yml`. Compares the images built
for a PR against the published `:main` baseline and emits a Markdown report
(top-line per-variant delta plus a per-directory / per-file breakdown) to
stdout. The job writes it to the step summary and posts a sticky PR comment.
This is **ephemeral**: it lives only on that PR / run.

```
image-size-report.sh <pr-sha> <repo-slug>
```

### `size-history.sh` — per-merge history

Used by the `size-history` job in `build-multiarch-images.yml`, which runs once
per merge to `main`. It records the size of each shipped `:main` image, appends
a row to a **durable** time series, and regenerates a Markdown table and an SVG
chart with one independently scaled panel per image (so small KB/MB changes stay
visible instead of flattening against a shared, GiB-dominated scale). The data
lives on the dedicated, orphan `size-history` branch
(`size-history.csv` is the source of truth, with `SIZE_HISTORY.md` and
`size-history.svg` regenerated from it), so the history survives the log / step
summary purging that the per-PR report is subject to. Deltas are computed
against the previous recorded merge — there is no need to rebuild `HEAD^1`.

```
# Append one data point for the current merge and print a per-merge summary:
size-history.sh record <csv> <sha> <repo-slug>

# Regenerate SIZE_HISTORY.md + size-history.svg from the CSV (no network).
# With a repo-slug each sha links to its commit; with a tags file (lines
# "<full-sha> <tag>") a release merge is annotated with its release version,
# linked to the release page, to the right of the sha:
size-history.sh render <csv> <out-dir> [repo-slug] [tags-file]

# record then render in one go (what the workflow uses):
size-history.sh all <csv> <sha> <repo-slug> <out-dir> [tags-file]
```

Releases are shown alongside the sha of the merge they point at (never as a
separate row), since a release and its merge share the same commit.

Both tools measure amd64 sizes only, matching the existing PR report. A variant
that is not yet published to `:main` is recorded as blank / `n/a` rather than
failing.
