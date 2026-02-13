export function initLandingEffects() {
  const canvas = document.getElementById('particle-canvas');
  const ctx = canvas && canvas.getContext ? canvas.getContext('2d') : null;
  if (!canvas || !ctx) {
    return () => {};
  }
  canvas.style.position = 'fixed';
  canvas.style.inset = '0';
  canvas.style.zIndex = '1';
  canvas.style.pointerEvents = 'none';

  let w = 0;
  let h = 0;
  const particles = [];
  let rafId = null;

  function resizeCanvas() {
    w = canvas.width = window.innerWidth;
    h = canvas.height = window.innerHeight;
  }

  resizeCanvas();
  window.addEventListener('resize', resizeCanvas);

  const numParticles = Math.max(28, Math.round((w * h) / 20000));
  for (let i = 0; i < numParticles; i += 1) {
    particles.push({
      x: Math.random() * w,
      y: Math.random() * h,
      vx: Math.random() * 1.2 - 0.6,
      vy: Math.random() * 1.0 - 0.5,
      r: Math.random() * 1.6 + 0.8,
    });
  }

  function step() {
    ctx.clearRect(0, 0, w, h);

    for (const p of particles) {
      p.x += p.vx;
      p.y += p.vy;

      if (p.x < -20 || p.x > w + 20) p.vx *= -1;
      if (p.y < -20 || p.y > h + 20) p.vy *= -1;

      ctx.beginPath();
      const g = ctx.createRadialGradient(p.x, p.y, p.r * 0.2, p.x, p.y, p.r * 4);
      g.addColorStop(0, 'rgba(0,200,255,0.9)');
      g.addColorStop(0.4, 'rgba(107,92,255,0.45)');
      g.addColorStop(1, 'rgba(10,20,40,0)');
      ctx.fillStyle = g;
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fill();
    }

    rafId = window.requestAnimationFrame(step);
  }

  rafId = window.requestAnimationFrame(step);

  function onMouseMove(e) {
    for (const p of particles) {
      const dx = p.x - e.clientX;
      const dy = p.y - e.clientY;
      const d = Math.sqrt(dx * dx + dy * dy);

      if (d > 0 && d < 220) {
        const force = (1 - d / 220) * 0.6;
        p.vx += (dx / d) * force * 0.2;
        p.vy += (dy / d) * force * 0.2;
      }
    }
  }

  window.addEventListener('mousemove', onMouseMove);

  return () => {
    if (rafId) {
      window.cancelAnimationFrame(rafId);
    }
    window.removeEventListener('resize', resizeCanvas);
    window.removeEventListener('mousemove', onMouseMove);
  };
}
