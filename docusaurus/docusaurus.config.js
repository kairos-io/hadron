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
      items: [],
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
        rel: 'alternate icon',
        href: '/favicons/favicon.ico',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'apple-touch-icon',
        href: '/favicons/apple-touch-icon-180x180.png',
        sizes: '180x180',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/favicon-16x16.png',
        sizes: '16x16',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/favicon-32x32.png',
        sizes: '32x32',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/android-36x36.png',
        sizes: '36x36',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/android-48x48.png',
        sizes: '48x48',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/android-72x72.png',
        sizes: '72x72',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/android-96x96.png',
        sizes: '96x96',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/android-144x144.png',
        sizes: '144x144',
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'icon',
        type: 'image/png',
        href: '/favicons/android-192x192.png',
        sizes: '192x192',
      },
    },
  ],
};

module.exports = config;
