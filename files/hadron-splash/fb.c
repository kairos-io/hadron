/* hadron-splash-fb — framebuffer HADRON splash. C99, libc only.
 * Plymouth-style: takes over /dev/fb0 + tty1 in KD_GRAPHICS mode,
 * runs animation until SIGTERM, restores VT and exits. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/kd.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>

#define N_ATOMS    5
#define FRAME_USEC 33333
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* HADRON palette as 0x00RRGGBB */
static const uint32_t PAL[7] = {
    0x3578e5, 0x00c2ff, 0x8b5cf6, 0x6b5cff, 0x54c7ec, 0xfa383e, 0xffba00
};

#define ART_ROWS 6
#define ART_COLS 51
static const char *ART[ART_ROWS] = {
"██╗  ██╗ █████╗ ██████╗ ██████╗  ██████╗ ███╗   ██╗",
"██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔═══██╗████╗  ██║",
"███████║███████║██║  ██║██████╔╝██║   ██║██╔██╗ ██║",
"██╔══██║██╔══██║██║  ██║██╔══██╗██║   ██║██║╚██╗██║",
"██║  ██║██║  ██║██████╔╝██║  ██║╚██████╔╝██║ ╚████║",
"╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝",
};

/* Pre-decoded logo: each cell encoded as a 3x3 sub-pixel mask.
 * Bit layout (row-major):
 *   bit0 bit1 bit2     top-left   top    top-right
 *   bit3 bit4 bit5  =  left       center right
 *   bit6 bit7 bit8     bot-left   bot    bot-right
 */
static uint16_t LOGO[ART_ROWS][ART_COLS];

#define M_FULL 0x1FF  /* all 9 cells */
#define M_VERT (1<<1 | 1<<4 | 1<<7)              /* top, center, bot */
#define M_HORZ (1<<3 | 1<<4 | 1<<5)              /* left, center, right */
/* corners: where lines go out from center cell */
#define M_TL   (1<<4 | 1<<5 | 1<<7)              /* center + right + bot  (top-left of box) */
#define M_TR   (1<<3 | 1<<4 | 1<<7)              /* center + left  + bot  (top-right) */
#define M_BL   (1<<1 | 1<<4 | 1<<5)              /* center + top   + right (bot-left) */
#define M_BR   (1<<1 | 1<<3 | 1<<4)              /* center + top   + left  (bot-right) */

static int utf8_next(const char *s, char o[4]) {
    unsigned c = (unsigned char)s[0];
    if (!c) { o[0] = 0; return 0; }
    int n = c < 0x80 ? 1 : (c & 0xE0) == 0xC0 ? 2 : (c & 0xF0) == 0xE0 ? 3 : 4;
    for (int i = 0; i < n; i++) o[i] = s[i];
    o[n < 4 ? n : 3] = 0;
    return n;
}

/* Map UTF-8 box-drawing glyph (or full block) to a 3x3 sub-pixel mask. */
static uint16_t glyph_mask(const char *gl) {
    unsigned a = (unsigned char)gl[0];
    unsigned b = (unsigned char)gl[1];
    unsigned c = (unsigned char)gl[2];
    if (a == ' ' || a == 0) return 0;
    if (a == 0xE2 && b == 0x96 && c == 0x88) return M_FULL; /* █ U+2588 */
    if (a == 0xE2 && b == 0x95) {
        switch (c) {
            case 0x90: return M_HORZ; /* ═ U+2550 */
            case 0x91: return M_VERT; /* ║ U+2551 */
            case 0x94: return M_TL;   /* ╔ U+2554 */
            case 0x97: return M_TR;   /* ╗ U+2557 */
            case 0x9A: return M_BL;   /* ╚ U+255A */
            case 0x9D: return M_BR;   /* ╝ U+255D */
        }
    }
    return M_FULL; /* unknown printable → safe fallback */
}

static void logo_build(void) {
    for (int r = 0; r < ART_ROWS; r++) {
        const char *s = ART[r]; int c = 0; char gl[4];
        while (*s && c < ART_COLS) {
            int n = utf8_next(s, gl);
            if (!n) break;
            LOGO[r][c++] = glyph_mask(gl);
            s += n;
        }
        while (c < ART_COLS) LOGO[r][c++] = 0;
    }
}

typedef struct {
    int fd, vt_fd;
    uint8_t *map;
    size_t map_len;
    int w, h, pitch;     /* pitch in bytes */
    int bpp;
    uint32_t *back;      /* W*H scratch buffer in 0x00RRGGBB */
} fb_t;

static int fb_open(fb_t *f, const char *path) {
    f->fd = open(path, O_RDWR);
    if (f->fd < 0) { perror("open fb"); return -1; }
    struct fb_var_screeninfo v;
    struct fb_fix_screeninfo x;
    if (ioctl(f->fd, FBIOGET_VSCREENINFO, &v) < 0) { perror("FBIOGET_VSCREENINFO"); return -1; }
    if (ioctl(f->fd, FBIOGET_FSCREENINFO, &x) < 0) { perror("FBIOGET_FSCREENINFO"); return -1; }
    f->w = v.xres; f->h = v.yres; f->bpp = v.bits_per_pixel; f->pitch = x.line_length;
    if (f->bpp != 32 && f->bpp != 16) {
        fprintf(stderr, "unsupported bpp %d\n", f->bpp);
        return -1;
    }
    f->map_len = (size_t)x.smem_len;
    f->map = mmap(NULL, f->map_len, PROT_READ | PROT_WRITE, MAP_SHARED, f->fd, 0);
    if (f->map == MAP_FAILED) { perror("mmap"); return -1; }
    f->back = calloc((size_t)f->w * f->h, sizeof(uint32_t));
    if (!f->back) return -1;
    return 0;
}

static void fb_close(fb_t *f) {
    if (f->back) free(f->back);
    if (f->map && f->map != MAP_FAILED) munmap(f->map, f->map_len);
    if (f->fd >= 0) close(f->fd);
}

static int vt_grab(fb_t *f, const char *tty_path) {
    f->vt_fd = open(tty_path, O_RDWR);
    if (f->vt_fd < 0) { perror("open tty"); return -1; }
    if (ioctl(f->vt_fd, KDSETMODE, KD_GRAPHICS) < 0) {
        perror("KDSETMODE KD_GRAPHICS");
        close(f->vt_fd); f->vt_fd = -1;
        return -1;
    }
    return 0;
}

static void vt_release(fb_t *f) {
    if (f->vt_fd >= 0) {
        ioctl(f->vt_fd, KDSETMODE, KD_TEXT);
        close(f->vt_fd);
        f->vt_fd = -1;
    }
}

/* Composite back buffer to framebuffer, converting if needed. */
static void fb_present(fb_t *f) {
    if (f->bpp == 32) {
        int row_bytes = f->w * 4;
        for (int y = 0; y < f->h; y++) {
            memcpy(f->map + (size_t)y * f->pitch,
                   f->back + (size_t)y * f->w,
                   (size_t)row_bytes);
        }
    } else { /* 16bpp RGB565 */
        for (int y = 0; y < f->h; y++) {
            uint16_t *dst = (uint16_t *)(f->map + (size_t)y * f->pitch);
            uint32_t *src = f->back + (size_t)y * f->w;
            for (int xp = 0; xp < f->w; xp++) {
                uint32_t p = src[xp];
                uint16_t r = ((p >> 16) & 0xff) >> 3;
                uint16_t g = ((p >>  8) & 0xff) >> 2;
                uint16_t b = ( p        & 0xff) >> 3;
                dst[xp] = (uint16_t)((r << 11) | (g << 5) | b);
            }
        }
    }
}

/* Fade back buffer toward black by factor 220/256. */
static void back_fade(fb_t *f) {
    uint32_t *p = f->back;
    int n = f->w * f->h;
    for (int i = 0; i < n; i++) {
        uint32_t v = p[i];
        uint32_t r = (((v >> 16) & 0xff) * 220) >> 8;
        uint32_t g = (((v >>  8) & 0xff) * 220) >> 8;
        uint32_t b = (( v        & 0xff) * 220) >> 8;
        p[i] = (r << 16) | (g << 8) | b;
    }
}

static void fill_rect(fb_t *f, int x, int y, int w, int h, uint32_t col) {
    int x0 = x < 0 ? 0 : x;
    int y0 = y < 0 ? 0 : y;
    int x1 = x + w > f->w ? f->w : x + w;
    int y1 = y + h > f->h ? f->h : y + h;
    for (int yy = y0; yy < y1; yy++) {
        uint32_t *row = f->back + (size_t)yy * f->w;
        for (int xx = x0; xx < x1; xx++) row[xx] = col;
    }
}

static void fill_circle(fb_t *f, int cx, int cy, int rad, uint32_t col) {
    int r2 = rad * rad;
    int y0 = cy - rad < 0 ? -cy : -rad;
    int y1 = cy + rad >= f->h ? f->h - cy - 1 : rad;
    for (int dy = y0; dy <= y1; dy++) {
        int dx_max = (int)sqrt((double)(r2 - dy * dy));
        int x0 = cx - dx_max; if (x0 < 0) x0 = 0;
        int x1 = cx + dx_max; if (x1 >= f->w) x1 = f->w - 1;
        uint32_t *row = f->back + (size_t)(cy + dy) * f->w;
        for (int xx = x0; xx <= x1; xx++) row[xx] = col;
    }
}

static void draw_logo(fb_t *f, int lx, int ly, int cw, int ch, uint32_t col) {
    /* Sub-pixel size; integer division so cells tile without gaps. */
    int sw0 = cw / 3, sw1 = (cw * 2) / 3 - sw0, sw2 = cw - sw0 - sw1;
    int sh0 = ch / 3, sh1 = (ch * 2) / 3 - sh0, sh2 = ch - sh0 - sh1;
    int sw[3] = { sw0, sw1, sw2 };
    int sh[3] = { sh0, sh1, sh2 };
    for (int r = 0; r < ART_ROWS; r++) {
        for (int c = 0; c < ART_COLS; c++) {
            uint16_t m = LOGO[r][c];
            if (!m) continue;
            int cx = lx + c * cw;
            int cy = ly + r * ch;
            int py = cy;
            for (int sr = 0; sr < 3; sr++) {
                int px = cx;
                for (int sc = 0; sc < 3; sc++) {
                    if (m & (1 << (sr * 3 + sc)))
                        fill_rect(f, px, py, sw[sc], sh[sr], col);
                    px += sw[sc];
                }
                py += sh[sr];
            }
        }
    }
}

typedef struct {
    double cx, cy;       /* orbit center, pixels */
    double rx, ry;       /* orbit radii, pixels */
    double theta, omega; /* angle, angular velocity (rad/s) */
    uint8_t phase;       /* color phase offset */
    int radius;          /* atom visual radius, pixels */
} atom_t;

static uint32_t xs(uint32_t *s) {
    uint32_t x = *s; x ^= x<<13; x ^= x>>17; x ^= x<<5;
    *s = x ? x : 0xdeadbeef; return *s;
}
static double xu(uint32_t *s) { return (xs(s) & 0xFFFFFF) / (double)0x1000000; }

static double now_sec(void) {
    struct timeval t; gettimeofday(&t, NULL);
    return t.tv_sec + t.tv_usec / 1e6;
}

static volatile sig_atomic_t g_exit = 0;
static void on_sig(int s) { (void)s; g_exit = 1; }

int main(int argc, char **argv) {
    const char *tty_path = "/dev/tty1";
    const char *fb_path  = "/dev/fb0";
    double duration = 0.0; /* 0 = run until signal */
    int no_vt = 0;
    int stdout_mode = 0;
    int sw = 800, sh = 600;
    for (int i = 1; i < argc; i++) {
        if (!strncmp(argv[i], "--tty=", 6))      tty_path = argv[i] + 6;
        else if (!strncmp(argv[i], "--fb=", 5))  fb_path  = argv[i] + 5;
        else if (!strncmp(argv[i], "--duration=", 11)) duration = atof(argv[i] + 11);
        else if (!strcmp(argv[i], "--no-vt"))    no_vt = 1;
        else if (!strcmp(argv[i], "--stdout"))   stdout_mode = 1;
        else if (!strncmp(argv[i], "--w=", 4))   sw = atoi(argv[i] + 4);
        else if (!strncmp(argv[i], "--h=", 4))   sh = atoi(argv[i] + 4);
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            fprintf(stderr,
                "usage: %s [--tty=/dev/ttyN] [--fb=/dev/fbN] "
                "[--duration=SEC] [--no-vt] [--stdout --w=W --h=H]\n", argv[0]);
            return 0;
        }
    }

    logo_build();

    fb_t fb = { .fd = -1, .vt_fd = -1 };
    if (stdout_mode) {
        fb.w = sw; fb.h = sh; fb.bpp = 32;
        fb.back = calloc((size_t)fb.w * fb.h, sizeof(uint32_t));
        if (!fb.back) return 1;
    } else {
        if (fb_open(&fb, fb_path) < 0) return 1;
        if (!no_vt && vt_grab(&fb, tty_path) < 0) { fb_close(&fb); return 1; }
    }

    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sigemptyset(&sa.sa_mask);
    sa.sa_handler = on_sig;
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP,  &sa, NULL);

    /* Layout: fit logo to ~70% width, keep block aspect 1w:2h. */
    int cw = (fb.w * 70 / 100) / ART_COLS;
    if (cw < 2) cw = 2;
    int ch = cw * 2;
    int max_h = fb.h / 3;
    while (ch * ART_ROWS > max_h && cw > 2) { cw--; ch = cw * 2; }
    int logo_w = cw * ART_COLS;
    int logo_h = ch * ART_ROWS;
    int lx = (fb.w - logo_w) / 2;
    int ly = (fb.h - logo_h) / 2;
    int ccx = fb.w / 2;
    int ccy = fb.h / 2;

    /* Atom orbits sized to enclose logo with margin. */
    double base_rx = (double)logo_w / 2.0 + cw * 4;
    double base_ry = (double)logo_h / 2.0 + ch * 2;
    int atom_r = cw < 8 ? cw : (cw / 2 + 4);
    if (atom_r < 3) atom_r = 3;

    uint32_t seed = (uint32_t)(now_sec() * 1e6);
    atom_t a[N_ATOMS];
    uint32_t s = seed ? seed : 1;
    for (int i = 0; i < N_ATOMS; i++) {
        a[i].cx = ccx;
        a[i].cy = ccy;
        a[i].rx = base_rx + xu(&s) * cw * 4;
        a[i].ry = base_ry + xu(&s) * ch * 2;
        a[i].theta = xu(&s) * 2 * M_PI;
        a[i].omega = 0.8 + xu(&s) * 1.4;
        a[i].phase = (uint8_t)(xs(&s) % 7);
        a[i].radius = atom_r;
    }

    /* Clear screen once. */
    memset(fb.back, 0, (size_t)fb.w * fb.h * sizeof(uint32_t));
    if (!stdout_mode) fb_present(&fb);

    double t0 = now_sec(), tp = t0;
    while (!g_exit) {
        double tn = now_sec();
        double dt = tn - tp; tp = tn;
        if (duration > 0 && tn - t0 >= duration) break;

        back_fade(&fb);

        int phase = (int)(tn * 0.7);
        draw_logo(&fb, lx, ly, cw, ch, PAL[phase % 7]);

        for (int i = 0; i < N_ATOMS; i++) {
            a[i].theta += a[i].omega * dt;
            int x = (int)(a[i].cx + a[i].rx * cos(a[i].theta) + 0.5);
            int y = (int)(a[i].cy - a[i].ry * sin(a[i].theta) + 0.5);
            uint32_t col = PAL[(a[i].phase + (int)(tn * 1.5)) % 7];
            fill_circle(&fb, x, y, a[i].radius, col);
        }

        if (stdout_mode) {
            size_t n = (size_t)fb.w * fb.h * 4;
            if (fwrite(fb.back, 1, n, stdout) != n) break;
            fflush(stdout);
        } else {
            fb_present(&fb);
        }
        usleep(FRAME_USEC);
    }

    if (stdout_mode) {
        free(fb.back);
    } else {
        memset(fb.back, 0, (size_t)fb.w * fb.h * sizeof(uint32_t));
        fb_present(&fb);
        vt_release(&fb);
        fb_close(&fb);
    }
    return 0;
}
