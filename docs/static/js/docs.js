// Docs page JavaScript for collapsible sections

document.addEventListener('DOMContentLoaded', function() {
    const sectionTitles = document.querySelectorAll('.docs-section-title');
    
    // Initialize sections - expand section if it contains the active page
    sectionTitles.forEach(btn => {
        const sectionId = btn.getAttribute('data-section');
        const entries = document.getElementById(`section-${sectionId}`);
        const hasActive = entries && entries.querySelector('.docs-entry.active');
        
        if (hasActive) {
            entries.classList.add('show');
            btn.classList.add('active');
        }
    });
    
    // Toggle sections on click
    sectionTitles.forEach(btn => {
        btn.addEventListener('click', function() {
            const sectionId = this.getAttribute('data-section');
            const entries = document.getElementById(`section-${sectionId}`);
            
            if (entries) {
                const isExpanded = entries.classList.contains('show');
                
                if (isExpanded) {
                    entries.classList.remove('show');
                    this.classList.remove('active');
                } else {
                    entries.classList.add('show');
                    this.classList.add('active');
                }
            }
        });
    });
    
    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const href = this.getAttribute('href');
            if (href !== '#') {
                e.preventDefault();
                const target = document.querySelector(href);
                if (target) {
                    target.scrollIntoView({
                        behavior: 'smooth',
                        block: 'start'
                    });
                }
            }
        });
    });
});

