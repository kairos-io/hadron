# 📦 Image size history

Uncompressed size (`docker image inspect .Size`, amd64) of each shipped
`:main` image, recorded once per merge. The CSV (`size-history.csv`) is the
source of truth; this page and the chart are regenerated from it by
`.github/scripts/size-history.sh`.

![image size history](./size-history.svg)

## Most recent 20 merges

| date | sha | hadron | hadron-cloud | hadron-trusted | hadron-cloud-trusted |
|---|---|--:|--:|--:|--:|
| 2026-09-04 | [`cabb59ce6cb0`](https://github.com/kairos-io/hadron/commit/cabb59ce6cb02d1e2412cbedf8caedf307e92184) | 213MB (+19KB) | 110MB (+27KB) | 186MB (+24KB) | 83MB (+27KB) |
| 2026-09-04 | [`eeae2207803b`](https://github.com/kairos-io/hadron/commit/eeae2207803b49a21847bf02d31a99ed77dcf5b8) | 213MB (+0B) | 110MB (+0B) | 186MB (+0B) | 83MB (+0B) |
| 2026-09-03 | [`d0447b6f9a9b`](https://github.com/kairos-io/hadron/commit/d0447b6f9a9b036b6fe7b603b61153275b1e0c64) | 213MB (+0B) | 110MB (+0B) | 186MB (+0B) | 83MB (+0B) |
| 2026-08-24 | [`0981227e3452`](https://github.com/kairos-io/hadron/commit/0981227e3452347b6935f479995c1b8eb40a1433) | 213MB (+2.4KB) | 110MB (+225B) | 186MB (+3.6KB) | 83MB (+40B) |
| 2026-08-21 | [`06c642f497d8`](https://github.com/kairos-io/hadron/commit/06c642f497d8198c7dfa07b162535e5dfde69ba4) | 213MB (+0B) | 110MB (+0B) | 186MB (+0B) | 83MB (+0B) |
| 2026-08-21 | [`7ae28576559a`](https://github.com/kairos-io/hadron/commit/7ae28576559adda7dc2d50f8568a2dda10a8d8a1) | 213MB (+0B) | 110MB (+0B) | 186MB (+0B) | 83MB (+0B) |
| 2026-08-20 | [`3221b95fcd55`](https://github.com/kairos-io/hadron/commit/3221b95fcd55d78671da7dedf967f8774789f476) | 213MB (+1.2KB) | 110MB (+1.2KB) | 186MB (+1.2KB) | 83MB (+1.2KB) |
| 2026-08-19 | [`9111c9f4af57`](https://github.com/kairos-io/hadron/commit/9111c9f4af575deed4a9c731b341acbbc555950c) | 213MB (+0B) | 110MB (+0B) | 186MB (+0B) | 83MB (+0B) |
| 2026-08-19 | [`98e1dc290a6d`](https://github.com/kairos-io/hadron/commit/98e1dc290a6d100933bf973236e8b4cc33fedd7d) | 213MB (+0B) | 110MB (+0B) | 186MB (+0B) | 83MB (+0B) |
| 2026-08-19 | [`b26934d8ce51`](https://github.com/kairos-io/hadron/commit/b26934d8ce51f48669226c17a60ee7c44b980b51) | 213MB (+21KB) | 110MB (+3.7KB) | 186MB (+17KB) | 83MB (+3.0KB) |
| 2026-08-18 | [`8f2f317c9ed3`](https://github.com/kairos-io/hadron/commit/8f2f317c9ed3622a7e19071a740dfdd292699a35) | 213MB (+0B) | 110MB (+0B) | 186MB (-1B) | 83MB (+0B) |
| 2026-08-10 | [`dc4d3ef7c5f9`](https://github.com/kairos-io/hadron/commit/dc4d3ef7c5f931c4d76c7381c376f846568c4561) | 213MB (-39KB) | 110MB (-41KB) | 186MB (-59KB) | 83MB (-61KB) |
| 2026-07-30 | [`d0bdc4051bac`](https://github.com/kairos-io/hadron/commit/d0bdc4051bac564e2e1a2f569823cedb81673822) | 213MB (-4.1KB) | 110MB (-1.2KB) | 186MB (-4.0KB) | 83MB (-1.4KB) |
| 2026-07-28 | [`7b242bb2e1e3`](https://github.com/kairos-io/hadron/commit/7b242bb2e1e399a84cf75a626b99dc1398794dac) | 213MB (+0B) | 110MB (+0B) | 186MB (+0B) | 83MB (+0B) |
| 2026-07-27 | [`b0fa897cf64f`](https://github.com/kairos-io/hadron/commit/b0fa897cf64fd2184e74b915b14ff86ab76a0d50) | 213MB (+28KB) | 110MB (+6.5KB) | 186MB (+29KB) | 83MB (+6.5KB) |
| 2026-07-25 | [`ab7c5a12e3ed`](https://github.com/kairos-io/hadron/commit/ab7c5a12e3ed9f07507336a432a7c737b562885f) | 213MB (-2.6KB) | 110MB (+236B) | 186MB (+633B) | 83MB (+185B) |
| 2026-07-24 | [`0f37336a7788`](https://github.com/kairos-io/hadron/commit/0f37336a77884747dc59380ff4aaf0a94df24f08) | 213MB (+22KB) | 110MB (+21KB) | 186MB (+22KB) | 83MB (+21KB) |
| 2026-07-21 | [`66b222796d14`](https://github.com/kairos-io/hadron/commit/66b222796d14e424f61319077af6a31f5a64a78c) | 213MB (+1.8KB) | 110MB (+49B) | 186MB (-3.0KB) | 83MB (-6B) |
| 2026-07-20 | [`2dc527eec060`](https://github.com/kairos-io/hadron/commit/2dc527eec060daa073c76186559ab9de3142054d) | 213MB (+1.8MB) | 110MB (+1.2MB) | 186MB (+1.8MB) | 83MB (+1.2MB) |
| 2026-07-19 | [`f6e9abe31308`](https://github.com/kairos-io/hadron/commit/f6e9abe31308ca6fd08efcfa0888d80abb6d6f08) | 211MB (-3.3KB) | 109MB (+425B) | 184MB (+5.0KB) | 82MB (+318B) |

