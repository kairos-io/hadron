// @ts-check

const config = {
  title: 'Hadron Linux',
  tagline: 'The foundation for image-based systems.',
  favicon: 'favicons/favicon.svg',

  url: 'https://hadron-linux.io',
  baseUrl: '/',

  organizationName: 'kairos-io',
  projectName: 'hadron',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: false,
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      },
    ],
  ],

  themeConfig: {
    image: 'images/hadron-logo.svg',
    navbar: {
      title: 'Hadron Linux',
      items: [
        // `pathname://` prefix keeps Docusaurus's broken-link checker away from these
        // static-file routes and forces a real navigation (the target is a
        // hand-authored index.html, not a Docusaurus route).
        { href: 'pathname:///components/#components', label: 'Components', position: 'left', target: '_self' },
        { href: 'pathname:///components/#firmware',   label: 'Firmware',   position: 'left', target: '_self' },
        { href: 'pathname:///components/#layers',     label: 'Layers',     position: 'left', target: '_self' },
      ],
    },
    footer: {
      style: 'dark',
      links: [],
      copyright: 'Kairos authors',
    },
    metadata: [
      {
        name: 'description',
        content:
          "Kairos is an open-source Linux-based operating system designed for securely running Kubernetes at the edge. It provides immutable, declarative infrastructure with features like P2P clustering, trusted boot, and A/B upgrades.",
      },
    ],
  },

  headTags: [
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/svg+xml',
        href: '/favicons/favicon.svg',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/favicon.png',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'apple-touch-icon',
        href: '/favicons/favicon.png',
      },
    },
  ],
};

module.exports = config;
