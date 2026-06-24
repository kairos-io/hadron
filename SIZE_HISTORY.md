# 📦 Image size history

Uncompressed size (`docker image inspect .Size`, amd64) of each shipped
`:main` image, recorded once per merge. The CSV (`size-history.csv`) is the
source of truth; this page and the chart are regenerated from it by
`.github/scripts/size-history.sh`.

![image size history](./size-history.svg)

## Most recent 20 merges

| date | sha | hadron | hadron-cloud | hadron-trusted | hadron-cloud-trusted |
|---|---|--:|--:|--:|--:|
| 2026-06-24 | `ba5a4a5d6c73` | 210MB (+0B) | 108MB (-323B) | 183MB (+622B) | 81MB (+343B) |
| 2026-06-22 | `ce3ccbbb354a` | 210MB | 108MB | 183MB | 81MB |

