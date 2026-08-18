const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const template = fs.readFileSync(`${__dirname}/components-template.html`, 'utf8');
const match = template.match(/function layerCard\(layer\)\{[\s\S]*?\n  \}\n  function layersRender/);
assert(match, 'layerCard function not found in components template');

const context = {
  esc: value => String(value),
  fmtDate: value => value,
  lyOpen: {},
};
vm.createContext(context);
vm.runInContext(`${match[0].replace(/\n  function layersRender$/, '')}; this.layerCard = layerCard;`, context);

const html = context.layerCard({
  name: 'git',
  title: 'Git',
  image: 'ghcr.io/kairos-io/hadron-layers/git',
  latest: '2.55.0',
  tags: [{
    tag: '2.55.0',
    created: '2026-08-18',
    sysext: {
      amd64: {oci: 'ghcr.io/kairos-io/hadron-layers/sysext/git@sha256:amd64'},
      arm64: {oci: 'ghcr.io/kairos-io/hadron-layers/sysext/git@sha256:arm64'},
    },
  }],
});

assert.match(html, /amd64 sysext/);
assert.match(html, /arm64 sysext/);
assert.match(html, /data-copy="ghcr\.io\/kairos-io\/hadron-layers\/sysext\/git@sha256:amd64"/);
assert.match(html, /data-copy="ghcr\.io\/kairos-io\/hadron-layers\/sysext\/git@sha256:arm64"/);

console.log('components template sysext tests passed');
