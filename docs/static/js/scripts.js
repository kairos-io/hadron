/* Light-weight particle background + UI wiring
   - shows a fixed "up" arrow when the details page is visible
   - down arrow scrolls to details
   - buttons open links / scroll
*/

(function () {
    // Particles
    const canvas = document.getElementById('particle-canvas');
    const ctx = canvas && canvas.getContext ? canvas.getContext('2d') : null;
    let w = 0, h = 0, particles = [];

    function resizeCanvas() {
        if (!canvas || !ctx) return;
        w = canvas.width = window.innerWidth;
        h = canvas.height = window.innerHeight;
    }
    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();

    // create particles
    const NUM = Math.max(28, Math.round((w * h) / 20000));
    for (let i = 0; i < NUM; i++) {
        particles.push({
            x: Math.random() * w,
            y: Math.random() * h,
            vx: (Math.random() * 1.2 - 0.6),
            vy: (Math.random() * 1.0 - 0.5),
            r: Math.random() * 1.6 + 0.8
        });
    }

    function step() {
        if (!ctx) return;
        ctx.clearRect(0, 0, w, h);

        // particles
        for (let p of particles) {
            p.x += p.vx; p.y += p.vy;
            if (p.x < -20 || p.x > w + 20) p.vx *= -1;
            if (p.y < -20 || p.y > h + 20) p.vy *= -1;

            ctx.beginPath();
            const g = ctx.createRadialGradient(p.x, p.y, p.r * 0.2, p.x, p.y, p.r * 4);
            g.addColorStop(0, "rgba(0,200,255,0.9)");
            g.addColorStop(0.4, "rgba(107,92,255,0.45)");
            g.addColorStop(1, "rgba(10,20,40,0)");
            ctx.fillStyle = g;
            ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
            ctx.fill();
        }

        requestAnimationFrame(step);
    }
    requestAnimationFrame(step);

    // small mouse attraction
    window.addEventListener('mousemove', (e) => {
        for (let p of particles) {
            const dx = p.x - e.clientX, dy = p.y - e.clientY;
            const d = Math.sqrt(dx * dx + dy * dy);
            if (d < 220) {
                const force = (1 - d / 220) * 0.6;
                p.vx += (dx / d) * force * 0.2;
                p.vy += (dy / d) * force * 0.2;
            }
        }
    });

    // UI wiring
    document.addEventListener('DOMContentLoaded', () => {
        const scrollDown = document.getElementById('scroll-down');
        const scrollUp = document.getElementById('scroll-up-fixed');
        const pageDetails = document.getElementById('page-details');
        const pageHero = document.getElementById('page-hero');
        const btnStart = document.getElementById('btn-start');
        const btnGithub = document.getElementById('btn-github');

        if (scrollDown && pageDetails) {
            scrollDown.addEventListener('click', () => pageDetails.scrollIntoView({ behavior: 'smooth' }));
        }
        if (btnStart && pageDetails) {
            btnStart.addEventListener('click', () => pageDetails.scrollIntoView({ behavior: 'smooth' }));
        }
        if (btnGithub) {
            btnGithub.addEventListener('click', () => window.open('https://github.com/kairos-io/hadron', '_blank'));
        }

        // Arrow toggling - show down on hero, up on details
        const downBtn = scrollDown;
        const upBtn = scrollUp;
        const main = document.getElementById('main');

        if (downBtn && upBtn && main) {
            // Listen to scroll on the main container
            main.addEventListener('scroll', () => {
                const scrolled = main.scrollTop;

                // Toggle arrows based on scroll position with smooth transitions
                if (scrolled > window.innerHeight * 0.5) {
                    downBtn.style.opacity = '0';
                    downBtn.style.pointerEvents = 'none';
                    downBtn.style.transform = 'translateY(10px) scale(0.9)';
                    upBtn.classList.add('show');
                } else {
                    downBtn.style.opacity = '1';
                    downBtn.style.pointerEvents = 'auto';
                    downBtn.style.transform = 'translateY(0) scale(1)';
                    upBtn.classList.remove('show');
                }
            }, { passive: true });
        } else {
        }

        // Arrow click handlers
        if (downBtn && pageDetails) {
            downBtn.addEventListener('click', () => {
                pageDetails.scrollIntoView({ behavior: 'smooth' });
            });
        }

        if (upBtn && pageHero) {
            upBtn.addEventListener('click', () => {
                pageHero.scrollIntoView({ behavior: 'smooth' });
            });
        }
    });
})();
