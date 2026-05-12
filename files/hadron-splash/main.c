/* hadron — animated HADRON splash. C99, libc only. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <unistd.h>

#define DURATION_SEC 5
#define FRAME_USEC   33333
#define MIN_COLS     54
#define MIN_ROWS     12
#define N_ATOMS      5
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Hadron palette: 256-color indices for #3578e5, #00c2ff, #8b5cf6, #6b5cff,
   #54c7ec, #fa383e, #ffba00 */
static const uint8_t PAL[7] = {68, 39, 98, 99, 74, 203, 214};
#define AMBER 214

static char g_ver[64] = "";

static void load_version(void) {
    FILE *f = fopen("/etc/os-release", "r");
    if (!f) return;
    char b[256];
    while (fgets(b, sizeof(b), f)) {
        if (strncmp(b, "VERSION_ID=", 11)) continue;
        char *v = b + 11; if (*v == '"') v++;
        size_t L = strlen(v);
        while (L && (v[L-1] == '\n' || v[L-1] == '\r' || v[L-1] == '"')) v[--L] = 0;
        snprintf(g_ver, sizeof(g_ver), "version: %.40s", v);
        break;
    }
    fclose(f);
}

typedef struct { char g[4]; uint8_t color; uint8_t intensity; } cell_t;
typedef struct { int rows, cols; cell_t *cells; } grid_t;

static int  g_alloc(grid_t *g, int r, int c) {
    g->rows = r; g->cols = c;
    g->cells = calloc((size_t)r * c, sizeof *g->cells);
    if (!g->cells) return -1;
    for (int i = 0; i < r * c; i++) g->cells[i].g[0] = ' ';
    return 0;
}
static void g_set(grid_t *g, int r, int c, const char *s, uint8_t col, uint8_t in) {
    if (r < 0 || r >= g->rows || c < 0 || c >= g->cols) return;
    cell_t *x = &g->cells[r * g->cols + c];
    int i = 0; while (i < 3 && s[i]) { x->g[i] = s[i]; i++; } x->g[i] = 0;
    x->color = col; x->intensity = in;
}
static void g_decay(grid_t *g) {
    for (int i = 0; i < g->rows * g->cols; i++)
        if (g->cells[i].intensity) g->cells[i].intensity--;
}

static int utf8_next(const char *s, char o[4]) {
    unsigned c = (unsigned char)s[0];
    if (!c) { o[0] = 0; return 0; }
    int n = c < 0x80 ? 1 : (c & 0xE0) == 0xC0 ? 2 : (c & 0xF0) == 0xE0 ? 3 : 4;
    for (int i = 0; i < n; i++) o[i] = s[i];
    o[n < 4 ? n : 3] = 0;
    return n;
}
static int utf8_cols(const char *s) {
    int n = 0; char t[4];
    while (*s) { int a = utf8_next(s, t); if (!a) break; s += a; n++; }
    return n;
}

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
static const char *TAG = "the foundation for image-based systems";

static void paint_text(grid_t *g, int top, int left, uint8_t col) {
    for (int r = 0; r < ART_ROWS; r++) {
        const char *p = ART[r]; int c = 0; char gl[4];
        while (*p) { int a = utf8_next(p, gl); if (!a) break;
            if (!(a == 1 && gl[0] == ' ')) g_set(g, top + r, left + c, gl, col, 0);
            p += a; c++; }
    }
}
static void paint_str(grid_t *g, int row, const char *s, uint8_t col) {
    if (!s || !*s) return;
    int left = (g->cols - utf8_cols(s)) / 2; if (left < 0) left = 0;
    int c = 0; char gl[4];
    while (*s) { int a = utf8_next(s, gl); if (!a) break;
        g_set(g, row, left + c, gl, col, 0); s += a; c++; }
}

typedef struct { double cx, cy, rx, ry, theta, omega; uint8_t phase; } atom_t;
static uint32_t xs(uint32_t *s) { uint32_t x = *s; x ^= x<<13; x ^= x>>17; x ^= x<<5; *s = x?x:0xdeadbeef; return *s; }
static double xu(uint32_t *s) { return (xs(s) & 0xFFFFFF) / (double)0x1000000; }

static void atoms_init(atom_t *a, int cols, int rows, uint32_t seed) {
    uint32_t s = seed ? seed : 1;
    double cx = cols / 2.0, cy = rows / 2.0;
    double brx = ART_COLS / 2.0 + 4, bry = ART_ROWS / 2.0 + 3;
    for (int i = 0; i < N_ATOMS; i++) {
        a[i] = (atom_t){ cx, cy, brx + xu(&s) * 4, bry + xu(&s) * 2,
            xu(&s) * 2 * M_PI, 0.8 + xu(&s) * 1.4, (uint8_t)(xs(&s) % 7) };
    }
}

static const char *TRACE[6] = {" ", ".", "'", ":", "*", "o"};
static void paint_trace(grid_t *g) {
    for (int i = 0; i < g->rows * g->cols; i++) {
        cell_t *x = &g->cells[i];
        if (x->intensity > 0 && x->intensity < 5) {
            const char *t = TRACE[x->intensity];
            int j = 0; while (j < 3 && t[j]) { x->g[j] = t[j]; j++; } x->g[j] = 0;
        } else if (!x->intensity) { x->g[0] = ' '; x->g[1] = 0; x->color = 0; }
    }
}

static double now_sec(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec + t.tv_usec/1e6; }

static int cell_eq(const cell_t *a, const cell_t *b) {
    return a->color == b->color && a->intensity == b->intensity && !strcmp(a->g, b->g);
}

static void flush_grid(const grid_t *cur, grid_t *prev, int use_color) {
    int sgr = -1;
    for (int r = 0; r < cur->rows; r++) for (int c = 0; c < cur->cols; c++) {
        int i = r * cur->cols + c;
        cell_t a = cur->cells[i], b = prev->cells[i];
        if (cell_eq(&a, &b)) continue;
        printf("\033[%d;%dH", r+1, c+1);
        if (use_color) {
            int w = !a.color ? 0 : (a.intensity > 0 && a.intensity < 5 ? 1000+a.color : 2000+a.color);
            if (w != sgr) {
                if (!w) fputs("\033[0m", stdout);
                else if (w >= 2000) printf("\033[0;1;38;5;%dm", w-2000);
                else                printf("\033[0;2;38;5;%dm", w-1000);
                sgr = w;
            }
        }
        fputs(a.g[0] ? a.g : " ", stdout);
        prev->cells[i] = a;
    }
    fflush(stdout);
}

static volatile sig_atomic_t g_exit = 0;
static void on_sig(int s) { (void)s; g_exit = 1; }

int main(void) {
    load_version();

    struct winsize ws; int rows = 24, cols = 80;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row && ws.ws_col) {
        rows = ws.ws_row; cols = ws.ws_col;
    }
    if (!isatty(STDOUT_FILENO) || rows < MIN_ROWS || cols < MIN_COLS) {
        if (g_ver[0]) printf("HADRON  %s\n", g_ver); else puts("HADRON");
        return 0;
    }

    int use_color = 1;
    if (!isatty(STDOUT_FILENO) || getenv("NO_COLOR")) use_color = 0;
    const char *t = getenv("TERM"); if (t && !strcmp(t, "dumb")) use_color = 0;

    atom_t atoms[N_ATOMS];
    atoms_init(atoms, cols, rows, (uint32_t)now_sec());

    grid_t cur, prev;
    if (g_alloc(&cur, rows, cols) || g_alloc(&prev, rows, cols)) return 1;

    struct sigaction sa; memset(&sa, 0, sizeof sa); sigemptyset(&sa.sa_mask);
    sa.sa_handler = on_sig;
    sigaction(SIGINT, &sa, NULL); sigaction(SIGTERM, &sa, NULL);

    fputs("\033[?1049h\033[?25l\033[2J\033[H", stdout); fflush(stdout);

    int block_h = ART_ROWS + 3;
    int top = (rows - block_h) / 2;
    int left = (cols - ART_COLS) / 2;
    int tag_row = top + ART_ROWS + 1;
    int ver_row = top + ART_ROWS + 2;

    double t0 = now_sec(), tp = t0;
    while (!g_exit) {
        double tn = now_sec(), dt = tn - tp; tp = tn;
        if (tn - t0 >= DURATION_SEC) break;

        g_decay(&cur);
        paint_trace(&cur);
        int phase = (int)(tn * 0.7);
        paint_text(&cur, top, left, PAL[phase % 7]);
        paint_str(&cur, tag_row, TAG, PAL[(phase + 2) % 7]);
        if (g_ver[0]) paint_str(&cur, ver_row, g_ver, AMBER);
        for (int i = 0; i < N_ATOMS; i++) {
            atoms[i].theta += atoms[i].omega * dt;
            int x = (int)(atoms[i].cx + atoms[i].rx * cos(atoms[i].theta) + 0.5);
            int y = (int)(atoms[i].cy - atoms[i].ry * sin(atoms[i].theta) + 0.5);
            g_set(&cur, y, x, "o", PAL[(atoms[i].phase + (int)(tn * 1.5)) % 7], 5);
        }
        flush_grid(&cur, &prev, use_color);
        usleep(FRAME_USEC);
    }

    fputs("\033[0m\033[?25h\033[?1049l", stdout); fflush(stdout);
    free(cur.cells); free(prev.cells);
    return 0;
}
