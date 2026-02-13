import React from 'react';
import Head from '@docusaurus/Head';
import { initLandingEffects } from '../lib/landingEffects';
import '../css/landing.css';

const softwareApplicationLdJson = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: 'Hadron Linux',
  description:
    'A minimal, upstream-aligned Linux distribution built from scratch using musl, systemd, and vanilla Linux kernels - engineered for secure, predictable cloud and edge deployments.',
  url: 'https://hadron-linux.io',
  applicationCategory: 'OperatingSystem',
  operatingSystem: 'Linux',
  offers: {
    '@type': 'Offer',
    price: '0',
    priceCurrency: 'USD',
  },
  codeRepository: 'https://github.com/kairos-io/hadron',
  keywords: [
    'Linux',
    'operating system',
    'minimal',
    'musl',
    'systemd',
    'cloud',
    'edge computing',
    'secure boot',
    'UKI',
    'USI',
  ],
  featureList: [
    'Core Components - musl, systemd, vanilla kernels',
    'Upstream First - Minimal changes. Maximum compatibility',
    'Independent - Built from scratch. No package manager',
    'Seamless Updates (with Kairos) - A/B upgrade capabilities for zero-downtime operations',
    'Edge & Cloud Ready (with Kairos) - Optimized for both cloud workloads and edge deployments',
  ],
};

export default function Home() {
  React.useEffect(() => initLandingEffects(), []);

  return (
    <>
      <Head>
        <title>Hadron Linux</title>
        <meta name="description" content="The foundation for image-based systems." />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;800&display=swap"
          rel="stylesheet"
        />
        <script type="application/ld+json">{JSON.stringify(softwareApplicationLdJson)}</script>
      </Head>

      <div id="landing-container">
        <div className="blob one" aria-hidden="true" />
        <div className="blob two" aria-hidden="true" />

        <canvas id="particle-canvas" aria-hidden="true" />

        <main id="main" className="snap-container">
          <section id="page-hero" className="snap-page hero" role="banner" aria-label="Hadron hero">
            <div className="hero-inner">
              <div className="hero-left">
                <div className="eyebrow">
                  <img src="/images/hadron-logo.svg" alt="Hadron logo" width="24" height="24" />
                </div>
                <h1>The foundation for image-based systems.</h1>
                <p className="lead">
                  Hadron is a minimal, upstream-aligned Linux distribution built from scratch with musl,
                  systemd, vanilla kernels and no package manager - designed for predictable cloud and edge
                  environments.
                </p>
                <p className="lead">
                  Topped with{' '}
                  <a href="https://kairos.io" target="_blank" rel="noopener noreferrer">
                    Kairos
                  </a>
                  , it becomes immutable and has powerful lifecycle management. It's the foundation for
                  image-based systems.
                </p>
                <p>
                  Engineered by the Kairos team at{' '}
                  <a href="https://spectrocloud.com" target="_blank" rel="noopener noreferrer">
                    Spectro Cloud
                  </a>
                  .
                </p>

                <div className="ctas" role="navigation" aria-label="Primary">
                  <a
                    href="https://kairos.io/quickstart/"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn primary"
                    id="btn-start"
                  >
                    Quick Start
                  </a>
                  <a
                    href="https://github.com/kairos-io/hadron"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn secondary"
                    id="btn-github"
                  >
                    Source Code
                  </a>
                </div>
              </div>

              <aside className="showcase" aria-label="Hadron features">
                <div className="showcase-inner">
                  <ul className="feature-list">
                    <li className="feature">
                      <div className="dot" aria-hidden="true">
                        <svg
                          viewBox="0 0 24 24"
                          width="20"
                          height="20"
                          fill="none"
                          stroke="white"
                          strokeWidth="1.8"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M16.5 9.4l-9-5.19M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z" />
                          <polyline points="3.27 6.96 12 12.01 20.73 6.96" />
                          <line x1="12" y1="22.08" x2="12" y2="12" />
                        </svg>
                      </div>
                      <div>
                        <strong>Core Components</strong>
                        <div className="muted">musl, systemd, vanilla kernels.</div>
                      </div>
                    </li>

                    <li className="feature">
                      <div className="dot" aria-hidden="true">
                        <svg
                          viewBox="0 0 24 24"
                          width="20"
                          height="20"
                          fill="none"
                          stroke="white"
                          strokeWidth="1.8"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M12 19V5M5 12l7-7 7 7" />
                        </svg>
                      </div>
                      <div>
                        <strong>Upstream First</strong>
                        <div className="muted">Minimal changes. Maximum compatibility.</div>
                      </div>
                    </li>

                    <li className="feature">
                      <div className="dot" aria-hidden="true">
                        <svg
                          viewBox="0 0 24 24"
                          width="20"
                          height="20"
                          fill="none"
                          stroke="white"
                          strokeWidth="1.8"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
                        </svg>
                      </div>
                      <div>
                        <strong>Independent</strong>
                        <div className="muted">Built from scratch. No package manager.</div>
                      </div>
                    </li>

                    <li className="feature feature-kairos">
                      <div className="dot dot-kairos" aria-hidden="true">
                        <svg
                          viewBox="0 0 24 24"
                          width="20"
                          height="20"
                          fill="none"
                          stroke="white"
                          strokeWidth="1.8"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <polyline points="3 4 9 4 9 10" />
                          <polyline points="21 20 15 20 15 14" />
                          <path d="M21 4l-3.5 3.5A8 8 0 0 0 4 12" />
                          <path d="M3 20l3.5-3.5A8 8 0 0 0 20 12" />
                        </svg>
                      </div>
                      <div>
                        <div className="feature-title-row">
                          <strong>Seamless Updates</strong>
                          <span className="badge-kairos">with Kairos</span>
                        </div>
                        <div className="muted">A/B upgrade capabilities for zero-downtime operations</div>
                      </div>
                    </li>

                    <li className="feature feature-kairos">
                      <div className="dot dot-kairos" aria-hidden="true">
                        <svg
                          viewBox="0 0 24 24"
                          width="20"
                          height="20"
                          fill="none"
                          stroke="white"
                          strokeWidth="1.8"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M7 18h9a4 4 0 0 0 0-8 5 5 0 0 0-9.7-1.6A3.5 3.5 0 0 0 7 18z" />
                          <rect x="3" y="14.5" width="4" height="4" rx="1" />
                          <rect x="17" y="6" width="4" height="4" rx="1" />
                        </svg>
                      </div>
                      <div>
                        <div className="feature-title-row">
                          <strong>Edge &amp; Cloud Ready</strong>
                          <span className="badge-kairos">with Kairos</span>
                        </div>
                        <div className="muted">Optimized for both cloud workloads and edge deployments</div>
                      </div>
                    </li>
                  </ul>
                </div>
              </aside>
            </div>
          </section>
        </main>
      </div>
    </>
  );
}
