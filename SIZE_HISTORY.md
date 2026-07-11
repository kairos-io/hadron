# 📦 Image size history

Uncompressed size (`docker image inspect .Size`, amd64) of each shipped
`:main` image, recorded once per merge. The CSV (`size-history.csv`) is the
source of truth; this page and the chart are regenerated from it by
`.github/scripts/size-history.sh`.

![image size history](./size-history.svg)

## Most recent 20 merges

| date | sha | hadron | hadron-cloud | hadron-trusted | hadron-cloud-trusted |
|---|---|--:|--:|--:|--:|
| 2026-07-11 | [`533490d527f0`](https://github.com/kairos-io/hadron/commit/533490d527f06dc4ffc7afcef234134bc8d91cdb) | 210MB (-9.6KB) | 109MB (-7.8KB) | 183MB (+1.8KB) | 82MB (+155B) |
| 2026-07-09 | [`2193edcd4aba`](https://github.com/kairos-io/hadron/commit/2193edcd4aba9edf26ec4dddb12629a0a616c7db) [`v0.5.1`](https://github.com/kairos-io/hadron/releases/tag/v0.5.1) | 210MB (+0B) | 109MB (+0B) | 183MB (+0B) | 82MB (+0B) |
| 2026-07-09 | [`a059a4eccc51`](https://github.com/kairos-io/hadron/commit/a059a4eccc51586bcb67322156ebcc6ad2ee3825) | 210MB (+0B) | 109MB (+0B) | 183MB (+0B) | 82MB (+0B) |
| 2026-07-08 | [`15591032ddc1`](https://github.com/kairos-io/hadron/commit/15591032ddc1eb45a46025bd34273753c2062c81) | 210MB (+0B) | 109MB (+0B) | 183MB (+0B) | 82MB (+0B) |
| 2026-07-07 | [`9770f45f5a29`](https://github.com/kairos-io/hadron/commit/9770f45f5a29785412b9e1caef41b10d0a3eb5c9) [`v0.5.0`](https://github.com/kairos-io/hadron/releases/tag/v0.5.0) | 210MB (+0B) | 109MB (+0B) | 183MB (+0B) | 82MB (+0B) |
| 2026-07-07 | [`f1a66a3beb88`](https://github.com/kairos-io/hadron/commit/f1a66a3beb885d0b9d582c666d059ee36e8405db) | 210MB (+5.4KB) | 109MB (+977KB) | 183MB (+4.7KB) | 82MB (+977KB) |
| 2026-07-06 | [`2a1d0e7e8973`](https://github.com/kairos-io/hadron/commit/2a1d0e7e8973fe9b618ca56fcd82dffa98d46c57) | 210MB (+0B) | 108MB (+0B) | 183MB (+0B) | 81MB (+0B) |
| 2026-07-05 | [`b58fec5c6be2`](https://github.com/kairos-io/hadron/commit/b58fec5c6be250854e9ffc7ea02d8f7a7870948d) | 210MB (+13KB) | 108MB (+21KB) | 183MB (+12KB) | 81MB (+20KB) |
| 2026-07-01 | [`60a9683ca5e3`](https://github.com/kairos-io/hadron/commit/60a9683ca5e348527851eeaf6f2127022f0b7d1b) | 210MB (-3.3KB) | 108MB (+164B) | 183MB (-6.4KB) | 81MB (+700B) |
| 2026-06-29 | [`5046ffc48763`](https://github.com/kairos-io/hadron/commit/5046ffc487636ed74ef6cf651813d7fdb8301039) | 210MB (+0B) | 108MB (+0B) | 183MB (+1.8KB) | 81MB (+0B) |
| 2026-06-29 | [`42283828299d`](https://github.com/kairos-io/hadron/commit/42283828299dd9bbe5e9b5ff2a8beea02ad9dbe3) | 210MB (+19KB) | 108MB (+19KB) | 183MB (+21KB) | 81MB (+19KB) |
| 2026-06-28 | [`d48f407110c3`](https://github.com/kairos-io/hadron/commit/d48f407110c3194100dd4008b9d7e26073b74e34) | 210MB (+23KB) | 108MB (+26KB) | 183MB (+21KB) | 81MB (+26KB) |
| 2026-06-26 | [`ae12f001fb5c`](https://github.com/kairos-io/hadron/commit/ae12f001fb5cdd0e919a2078ad902a76a62ef5ef) | 210MB (+11KB) | 108MB (+12KB) | 183MB (+12KB) | 81MB (+12KB) |
| 2026-06-25 | [`239f9887abc3`](https://github.com/kairos-io/hadron/commit/239f9887abc303a34d01192368928c8511a0b2c9) | 210MB (+0B) | 108MB (+0B) | 183MB (+0B) | 81MB (+0B) |
| 2026-06-25 | [`5d2e300cfb47`](https://github.com/kairos-io/hadron/commit/5d2e300cfb47247f7bcfbf50d7907458e61bd6b5) | 210MB (+0B) | 108MB (+1B) | 183MB (-2.0KB) | 81MB (+1B) |
| 2026-06-24 | [`ba5a4a5d6c73`](https://github.com/kairos-io/hadron/commit/ba5a4a5d6c737979723f52718168d4dea43fe1af) | 210MB (+0B) | 108MB (-323B) | 183MB (+622B) | 81MB (+343B) |
| 2026-06-22 | [`ce3ccbbb354a`](https://github.com/kairos-io/hadron/commit/ce3ccbbb354aeee4f2c153038a58a21f8e6e8192) | 210MB | 108MB | 183MB | 81MB |

