# 📦 Image size history

Uncompressed size (`docker image inspect .Size`, amd64) of each shipped
`:main` image, recorded once per merge. The CSV (`size-history.csv`) is the
source of truth; this page and the chart are regenerated from it by
`.github/scripts/size-history.sh`.

![image size history](./size-history.svg)

## Most recent 20 merges

| date | sha | hadron | hadron-cloud | hadron-trusted | hadron-cloud-trusted |
|---|---|--:|--:|--:|--:|
| 2026-06-28 | `d48f407110c3` | 210MB (+23KB) | 108MB (+26KB) | 183MB (+21KB) | 81MB (+26KB) |
| 2026-06-26 | `ae12f001fb5c` | 210MB (+11KB) | 108MB (+12KB) | 183MB (+12KB) | 81MB (+12KB) |
| 2026-06-25 | `239f9887abc3` | 210MB (+0B) | 108MB (+0B) | 183MB (+0B) | 81MB (+0B) |
| 2026-06-25 | `5d2e300cfb47` | 210MB (+0B) | 108MB (+1B) | 183MB (-2.0KB) | 81MB (+1B) |
| 2026-06-24 | `ba5a4a5d6c73` | 210MB (+0B) | 108MB (-323B) | 183MB (+622B) | 81MB (+343B) |
| 2026-06-22 | `ce3ccbbb354a` | 210MB | 108MB | 183MB | 81MB |

