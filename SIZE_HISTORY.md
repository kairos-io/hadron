# 📦 Image size history

Uncompressed rootfs size (sum of regular files, amd64) of each shipped
`:main` image, recorded once per merge. The CSV (`size-history.csv`) is the
source of truth; this page and the chart are regenerated from it by
`.github/scripts/size-history.sh`.

![image size history](./size-history.svg)

## Most recent 20 merges

| date | sha | hadron | hadron-cloud | hadron-trusted | hadron-cloud-trusted |
|---|---|--:|--:|--:|--:|
| 2026-11-20 | [`2be1352ed636`](https://github.com/kairos-io/hadron/commit/2be1352ed6364bedde3b98e60a1f2ca9a859d2d2) | 221MB (+0B) | 117MB (+0B) | 191MB (+0B) | 87MB (+0B) |
| 2026-11-20 | [`b677b9c3dfdd`](https://github.com/kairos-io/hadron/commit/b677b9c3dfddbb4143de91d171515daa2d76d7ec) | 221MB (+0B) | 117MB (+0B) | 191MB (+0B) | 87MB (+0B) |
| 2026-11-20 | [`54d2681faf1a`](https://github.com/kairos-io/hadron/commit/54d2681faf1a150f442cefee65e826570f3e3391) | 221MB (-1.9KB) | 117MB (+47B) | 191MB (+1.3KB) | 87MB (+48B) |
| 2026-11-19 | [`05da905cd35e`](https://github.com/kairos-io/hadron/commit/05da905cd35ef8958f9536e8c9824ac8d8667b27) | 221MB (+36KB) | 117MB (+77KB) | 191MB (+29KB) | 87MB (+72KB) |
| 2026-11-19 | [`16f775e95d6d`](https://github.com/kairos-io/hadron/commit/16f775e95d6d741f893a9f3d86885e399f00ee7b) | 221MB (+0B) | 117MB (-374B) | 191MB (-1.4KB) | 87MB (+0B) |
| 2026-11-19 | [`61d16290e4eb`](https://github.com/kairos-io/hadron/commit/61d16290e4eb10dad4aa16b0fcf48453667b9a9e) | 221MB (-861B) | 117MB (+0B) | 191MB (+4.8KB) | 87MB (+0B) |
| 2026-11-19 | [`f5361bfb41da`](https://github.com/kairos-io/hadron/commit/f5361bfb41daa9f0012ca0d2a9b786f4c9bb26ec) [`v0.6.6`](https://github.com/kairos-io/hadron/releases/tag/v0.6.6) | 221MB (+1.2KB) | 117MB (+263B) | 191MB (-2.1KB) | 87MB (+0B) |
| 2026-11-18 | [`cd779deaa986`](https://github.com/kairos-io/hadron/commit/cd779deaa98647209a7bcd0bc82af796df437a7e) | 221MB (-3.2KB) | 117MB (+0B) | 191MB (-3.8KB) | 87MB (-280B) |
| 2026-11-17 | [`4600bc82989b`](https://github.com/kairos-io/hadron/commit/4600bc82989b79b9dfae946c3bcb34946a0dd707) | 221MB (+3.7KB) | 117MB (-301B) | 191MB (+3.4KB) | 87MB (+406B) |
| 2026-11-17 | [`d68d2ff28153`](https://github.com/kairos-io/hadron/commit/d68d2ff28153fa20a14e42575e788555725a2b6d) | 221MB (-1.7KB) | 117MB (+568B) | 191MB (+141B) | 87MB (-308B) |
| 2026-11-16 | [`de78cc12d41f`](https://github.com/kairos-io/hadron/commit/de78cc12d41f88b5a4035bfa09ef3776b737995d) | 221MB (+218B) | 117MB (-109B) | 191MB (+2.4KB) | 87MB (+173B) |
| 2026-11-16 | [`a3a7843fe79c`](https://github.com/kairos-io/hadron/commit/a3a7843fe79c026b29b3a2eb40e2b4831f3d62b3) | 221MB (+1.5KB) | 117MB (+195B) | 191MB (-3.3KB) | 87MB (+0B) |
| 2026-11-12 | [`7b3a3c728989`](https://github.com/kairos-io/hadron/commit/7b3a3c7289898306f524615ad4120caeaa8813ad) [`v0.6.5`](https://github.com/kairos-io/hadron/releases/tag/v0.6.5) | 221MB (+12B) | 117MB (+0B) | 191MB (+1.1KB) | 87MB (-279B) |
| 2026-11-12 | [`146a7793afe9`](https://github.com/kairos-io/hadron/commit/146a7793afe9086236e249cae285ef658fffa2b4) | 221MB (-889B) | 117MB (-145B) | 191MB (-3.2KB) | 87MB (+531B) |
| 2026-11-12 | [`a22c2c4165c3`](https://github.com/kairos-io/hadron/commit/a22c2c4165c3a37c0be5c54c4ec5ac6679ff40e6) | 221MB (+25KB) | 117MB (+5.2KB) | 191MB (+23KB) | 87MB (+3.8KB) |
| 2026-11-10 | [`e66f94a4840d`](https://github.com/kairos-io/hadron/commit/e66f94a4840d17fd4a5cfaf876abdb7a27540539) | 221MB (+19KB) | 117MB (+6.4KB) | 191MB (+20KB) | 87MB (+6.6KB) |
| 2026-11-06 | [`890189205368`](https://github.com/kairos-io/hadron/commit/8901892053687bd7b67a4e068af42558d7a8ce13) | 221MB (+3.3KB) | 117MB (-186B) | 191MB (+3.5KB) | 87MB (-202B) |
| 2026-11-06 | [`1bb6889d70b1`](https://github.com/kairos-io/hadron/commit/1bb6889d70b117d356b483345dc559d826d3425d) | 221MB (+13KB) | 117MB (+15KB) | 191MB (+15KB) | 87MB (+15KB) |
| 2026-11-05 | [`7393288ff1a9`](https://github.com/kairos-io/hadron/commit/7393288ff1a94c323fc134470826a1bfabe15818) [`v0.6.4`](https://github.com/kairos-io/hadron/releases/tag/v0.6.4) | 221MB (+389KB) | 117MB (+384KB) | 191MB (+387KB) | 87MB (+384KB) |
| 2026-10-28 | [`b0e9e989016e`](https://github.com/kairos-io/hadron/commit/b0e9e989016e51c550b977905c5ce1612dc51617) | 220MB (+70MB) | 116MB (+68MB) | 191MB (+51MB) | 87MB (+50MB) |

