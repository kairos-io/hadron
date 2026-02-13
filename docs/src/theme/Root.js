import React, { useEffect } from 'react';

function PlausibleAnalytics() {
  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    const hostname = window.location.hostname;
    const isProdDomain = hostname === 'hadron-linux.io' || hostname === 'www.hadron-linux.io';
    if (!isProdDomain) {
      return;
    }

    if (window.plausible) {
      return;
    }

    const script = document.createElement('script');
    script.async = true;
    script.src = 'https://plausible.io/js/pa-XDOpr2NFR66mVfuk7yLdI.js';
    script.setAttribute('data-hadron-plausible', 'true');

    window.plausible =
      window.plausible ||
      function plausibleProxy() {
        (window.plausible.q = window.plausible.q || []).push(arguments);
      };

    window.plausible.init =
      window.plausible.init ||
      function init(options) {
        window.plausible.o = options || {};
      };

    document.head.appendChild(script);
    window.plausible.init();
  }, []);

  return null;
}

export default function Root({ children }) {
  return (
    <>
      <PlausibleAnalytics />
      {children}
    </>
  );
}
