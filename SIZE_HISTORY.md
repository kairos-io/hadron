# 📦 Image size history

Uncompressed size (`docker image inspect .Size`, amd64) of each shipped
`:main` image, recorded once per merge. The CSV (`size-history.csv`) is the
source of truth; this page and the chart are regenerated from it by
`.github/scripts/size-history.sh`.

![image size history](./size-history.svg)

## Most recent 20 merges

| date | sha | hadron | hadron-cloud | hadron-trusted | hadron-cloud-trusted |
|---|---|--:|--:|--:|--:|
| 2026-10-01 | [`b5f07fc13db7`](https://github.com/kairos-io/hadron/commit/b5f07fc13db73a38e233dc0aab0d600119825a1b) | 149MB (-4.8KB) | 47MB (-6.0KB) | 139MB (-1.1KB) | 37MB (+732B) |
| 2026-09-30 | [`82495b7bbd5c`](https://github.com/kairos-io/hadron/commit/82495b7bbd5c056e872b154e82f7c7a2830a0da7) | 149MB (-3.6KB) | 47MB (+2.8KB) | 139MB (-2.5KB) | 37MB (-133B) |
| 2026-09-29 | [`f824b1d9929f`](https://github.com/kairos-io/hadron/commit/f824b1d9929f18b32ee33824a2706d9a632d28c5) | 149MB (+191KB) | 47MB (+186KB) | 139MB (+179KB) | 37MB (+181KB) |
| 2026-09-28 | [`cb6c3010c01a`](https://github.com/kairos-io/hadron/commit/cb6c3010c01a03afd589cdc517817de36c7615b0) | 148MB (+35KB) | 47MB (+6.9KB) | 139MB (+55KB) | 37MB (-3.1KB) |
| 2026-09-25 | [`a1d66f7a64a4`](https://github.com/kairos-io/hadron/commit/a1d66f7a64a45a7287a849224b1c400e97415f30) | 148MB (+8.2KB) | 47MB (+130B) | 139MB (+984B) | 37MB (-272B) |
| 2026-09-23 | [`0f6dee5d0baf`](https://github.com/kairos-io/hadron/commit/0f6dee5d0baf4748af2c42c32beeb8fff3367ac5) | 148MB (+182KB) | 47MB (+159KB) | 139MB (+167KB) | 37MB (+177KB) |
| 2026-09-22 | [`43419ac10e74`](https://github.com/kairos-io/hadron/commit/43419ac10e743c697fcc81392f223a1a2a8cb686) | 148MB (-31KB) | 46MB (+1.5KB) | 139MB (-1.8KB) | 37MB (+11KB) |
| 2026-09-21 | [`2d1f8db6772d`](https://github.com/kairos-io/hadron/commit/2d1f8db6772d94002d31e9e1a56a25f6f0451c92) | 148MB (-67MB) | 46MB (-66MB) | 139MB (-50MB) | 37MB (-49MB) |
| 2026-09-18 | [`985b926dd8d4`](https://github.com/kairos-io/hadron/commit/985b926dd8d4af4e3a68475daaa1a814a4948059) [`v0.5.3`](https://github.com/kairos-io/hadron/releases/tag/v0.5.3) | 215MB (+914KB) | 112MB (+298KB) | 188MB (+912KB) | 85MB (+298KB) |
| 2026-09-17 | [`8d31a50a3b96`](https://github.com/kairos-io/hadron/commit/8d31a50a3b965eb309bd27c05ff7883f6d38d448) | 214MB (+606B) | 111MB (+606B) | 187MB (+606B) | 84MB (+606B) |
| 2026-09-17 | [`30f4d1a10410`](https://github.com/kairos-io/hadron/commit/30f4d1a1041061b9f5d20b8bb05f13ab6f7f1418) | 214MB (+0B) | 111MB (+0B) | 187MB (+2.8KB) | 84MB (-145B) |
| 2026-09-17 | [`8d73d38f395f`](https://github.com/kairos-io/hadron/commit/8d73d38f395fdc23c0bd06608112aa409e814b12) | 214MB (+0B) | 111MB (+0B) | 187MB (+0B) | 84MB (+0B) |
| 2026-09-16 | [`65d7eae64b1b`](https://github.com/kairos-io/hadron/commit/65d7eae64b1bc3e588e79e169ee5e7ab6aedb3a1) | 214MB (+0B) | 111MB (+0B) | 187MB (+0B) | 84MB (+0B) |
| 2026-09-16 | [`849b1157a571`](https://github.com/kairos-io/hadron/commit/849b1157a5712aa59d5574602352bb9e398fa9a3) | 214MB (+0B) | 111MB (+0B) | 187MB (+0B) | 84MB (+0B) |
| 2026-09-15 | [`4ffdf3cf6866`](https://github.com/kairos-io/hadron/commit/4ffdf3cf6866cd0e810b964d82263b91b406d9fc) | 214MB (+753KB) | 111MB (+758KB) | 187MB (+754KB) | 84MB (+758KB) |
| 2026-09-14 | [`b433696522eb`](https://github.com/kairos-io/hadron/commit/b433696522eb6141b41491b9567230f8703e5da3) | 213MB (+4.4KB) | 111MB (+228B) | 186MB (+2.1KB) | 84MB (+489B) |
| 2026-09-09 | [`b07772651fe2`](https://github.com/kairos-io/hadron/commit/b07772651fe26b2dca5b7fd11a207de193117ab6) [`v0.5.2`](https://github.com/kairos-io/hadron/releases/tag/v0.5.2) | 213MB (+34KB) | 111MB (+32KB) | 186MB (+31KB) | 84MB (+32KB) |
| 2026-09-08 | [`82b8231648b1`](https://github.com/kairos-io/hadron/commit/82b8231648b1fd2c0e3a154af55918d1f238c540) | 213MB (-8.1KB) | 111MB (-8.1KB) | 186MB (-8.1KB) | 84MB (-8.1KB) |
| 2026-09-08 | [`880a97c34706`](https://github.com/kairos-io/hadron/commit/880a97c3470674be3c9ca251e20f751d981696c3) | 213MB (+0B) | 111MB (+0B) | 186MB (+0B) | 84MB (+0B) |
| 2026-09-07 | [`b8e32575f1ad`](https://github.com/kairos-io/hadron/commit/b8e32575f1ad3821790a009eb5a403786799498d) | 213MB (+411KB) | 111MB (+419KB) | 186MB (+418KB) | 84MB (+418KB) |

