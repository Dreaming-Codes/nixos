#include "nntm.h"

#include <immintrin.h>
#include <math.h>
#include <stdlib.h>

/* Values live in float lanes but are always half-representable: every operation is done in
 * single precision and rounded to half, which equals a half-precision operation for add,
 * subtract, multiply and divide. Nothing here may be contracted or reordered.
 *
 * A rounded operation takes about 16 cycles and each pixel needs some 50 of them in a row, so
 * the kernels advance LANES vectors of 8 pixels through every operation together. */
enum { LANES = NNTM_STEP / 8 };

typedef struct { __m256 l[LANES]; } vf;
typedef struct { __m256i l[LANES]; } vi;
typedef struct { __m128i l[LANES]; } vbytes;

#define VF(expr) ({ vf r_; for (int n = 0; n < LANES; n++) r_.l[n] = (expr); r_; })
#define VI(expr) ({ vi r_; for (int n = 0; n < LANES; n++) r_.l[n] = (expr); r_; })
#define VBYTES(expr) ({ vbytes r_; for (int n = 0; n < LANES; n++) r_.l[n] = (expr); r_; })
#define INLINE static inline __attribute__((always_inline))

#define RN (_MM_FROUND_TO_NEAREST_INT | _MM_FROUND_NO_EXC)
#define K_Y 1.1640625f
#define K_Y0 -18.625f
#define K_C 1.142578125f
#define K_C0 -18.28125f
#define INV255 0x1.01p-8f
#define THIRD 0x1.554p-2f
#define FILTER_STRENGTH 0.3
#define LUMA_ONE 0x3c00

const NntmParams nntm_samsung_params = {
  .restricted = true,
  .offset = {0, 128, 128},
  .yuv2rgb = {8192, -2, 11218, 8192, -1334, -3336, 8192, 13220, -2},
  .rgb2yuv = {3484, 11716, 1183, -2158, -7262, 9420, 9420, -8557, -863},
  .gtm_a = 2, .gtm_b = 512, .gtm_c = 0,
  .guide_weight = 27955, .guide_bias = -12919,
  .strength = 500.f / 1023.f, .radial = 540.f / 1023.f,
};

typedef struct {
  int *i0, *i1;
  float *w0, *w1;
} CornerAlignedLerp;

typedef struct {
  int taps;
  int *index;
  float *coeff;
} Reduce;

struct Nntm {
  int width, height;
  bool restricted;
  int gtm_a;
  float offset[3], yuv2rgb[9], rgb2yuv[9], bp1, c, c1;
  float *depth;
  CornerAlignedLerp rows, cols;
  uint8_t *uniform;
  uint16_t *blend;
  Reduce reduce_x, reduce_y;
};

static inline float r1(float x) { return _cvtsh_ss(_cvtss_sh(x, RN)); }
static inline int clamp1(int x, int lo, int hi) { return x < lo ? lo : x > hi ? hi : x; }

INLINE __m256 rnd(__m256 x) { return _mm256_cvtph_ps(_mm256_cvtps_ph(x, RN)); }
INLINE vf set(float x) { return VF(_mm256_set1_ps(x)); }
INLINE vf mul(vf a, vf b) { return VF(rnd(a.l[n] * b.l[n])); }
INLINE vf add(vf a, vf b) { return VF(rnd(a.l[n] + b.l[n])); }
INLINE vf sub(vf a, vf b) { return VF(rnd(a.l[n] - b.l[n])); }
INLINE vf dvd(vf a, vf b) { return VF(rnd(a.l[n] / b.l[n])); }
INLINE vf vmin(vf a, vf b) { return VF(_mm256_min_ps(a.l[n], b.l[n])); }
INLINE vf vmax(vf a, vf b) { return VF(_mm256_max_ps(a.l[n], b.l[n])); }
INLINE vf both(vf a, vf b) { return VF(_mm256_and_ps(a.l[n], b.l[n])); }
INLINE vf choose(vf mask, vf yes, vf no) { return VF(_mm256_blendv_ps(no.l[n], yes.l[n], mask.l[n])); }
INLINE vf clampv(vf x, float lo, float hi) { return vmin(vmax(x, set(lo)), set(hi)); }
INLINE vf loadf(const float *p) { return VF(_mm256_loadu_ps(p + 8 * n)); }
INLINE vi loadi(const int *p) { return VI(_mm256_loadu_si256((const __m256i *)(p + 8 * n))); }
INLINE vi clampi(vi x, int lo, int hi) {
  return VI(_mm256_min_epi32(_mm256_max_epi32(x.l[n], _mm256_set1_epi32(lo)), _mm256_set1_epi32(hi)));
}
#define CMP(a, b, op) VF(_mm256_cmp_ps((a).l[n], (b).l[n], op))

static float half_of_double(double x) {
  int e;
  frexp(x, &e);
  int ulp = e - 11 < -24 ? -24 : e - 11;
  return (float)ldexp(nearbyint(ldexp(x, -ulp)), ulp);
}

static CornerAlignedLerp axis_new(float scale, int n, int last) {
  CornerAlignedLerp a = {malloc(n * sizeof(int)), malloc(n * sizeof(int)), malloc(n * sizeof(float)), malloc(n * sizeof(float))};
  scale = r1(scale);
  for (int i = 0; i < n; i++) {
    float pos = r1(scale * (float)i), lo = floorf(pos);
    a.i0[i] = clamp1((int)lo, 0, last);
    a.i1[i] = clamp1((int)r1(lo + 1), 0, last);
    a.w0[i] = r1(r1(lo + 1) - pos);
    a.w1[i] = r1(pos - lo);
  }
  return a;
}

static void axis_free(CornerAlignedLerp *a) { free(a->i0); free(a->i1); free(a->w0); free(a->w1); }

static Reduce reduce_new(int in) {
  const int out = NNTM_NET_SIZE;
  float scale = (float)in / (float)out, support = scale < 1 ? 1 : scale;
  Reduce r = {.taps = (int)ceilf(support) * 2 + 1};
  r.index = calloc(r.taps * out, sizeof(int));
  r.coeff = calloc(r.taps * out, sizeof(float));
  scale = r1(scale);
  support = r1(support);
  float ss = r1(1 / support), k[r.taps];
  for (int xx = 0; xx < out; xx++) {
    float center = r1(r1((float)xx + 0.5f) * scale);
    int lo = clamp1((int)r1(r1(center - support) + 0.5f), 0, in);
    int n = clamp1((int)r1(r1(center + support) + 0.5f), 0, in) - lo;
    float total = 0;
    for (int i = 0; i < n; i++) {
      float t = fabsf(r1(r1(r1((float)(i + lo) - center) + 0.5f) * ss));
      k[i] = t < 1 ? r1(1 - t) : 0;
      total = r1(total + k[i]);
    }
    for (int i = 0; i < r.taps; i++) {
      r.index[i * out + xx] = clamp1(lo + i, 0, in - 1);
      r.coeff[i * out + xx] = i < n && total != 0 ? r1(k[i] / total) : 0;
    }
  }
  return r;
}

static uint16_t *blend_new(const NntmParams *p, int w, int h) {
  int bw = p->shading_w, bh = p->shading_h;
  float *m = malloc(bw * bh * sizeof(float)), vmin = 2;
  for (int i = 0; i < bw * bh; i++) vmin = p->shading[i] < vmin ? p->shading[i] : vmin;
  for (int i = 0; i < bw * bh; i++) {
    float b = vmin > 1e-4f ? ((1.0f / (p->shading[i] / vmin)) * p->radial + (1.0f - p->radial)) * p->strength : p->strength;
    m[i] = r1((float)(int)(b * 65536.0f) * (1.0f / 65536.0f));
  }
  CornerAlignedLerp ys = axis_new((float)(bh - 1) / (float)(h - 1), h, bh - 1), xs = axis_new((float)(bw - 1) / (float)(w - 1), w, bw - 1);
  uint16_t *blend = malloc((size_t)w * h * sizeof(uint16_t));
  for (int y = 0; y < h; y++) {
    const float *m0 = m + ys.i0[y] * bw, *m1 = m + ys.i1[y] * bw;
    for (int x = 0; x < w; x++) {
      float b = r1(xs.w0[x] * r1(ys.w0[y] * m0[xs.i0[x]]));
      b = r1(r1(xs.w1[x] * r1(ys.w0[y] * m0[xs.i1[x]])) + b);
      b = r1(r1(xs.w0[x] * r1(ys.w1[y] * m1[xs.i0[x]])) + b);
      b = r1(r1(xs.w1[x] * r1(ys.w1[y] * m1[xs.i1[x]])) + b);
      blend[(size_t)y * w + x] = _cvtss_sh(b, RN);
    }
  }
  axis_free(&ys);
  axis_free(&xs);
  free(m);
  return blend;
}

Nntm *nntm_new(const NntmParams *p, int width, int height) {
  Nntm *t = calloc(1, sizeof(*t));
  t->width = width;
  t->height = height;
  t->restricted = p->restricted;
  t->gtm_a = p->gtm_a;
  float luma_row = (float)((p->rgb2yuv[1] + p->rgb2yuv[0]) + p->rgb2yuv[2]);
  for (int i = 0; i < 9; i++) {
    t->yuv2rgb[i] = r1((float)p->yuv2rgb[i] / (float)p->yuv2rgb[0]);
    t->rgb2yuv[i] = r1((float)p->rgb2yuv[i] / luma_row);
  }
  for (int i = 0; i < 3; i++) t->offset[i] = (float)p->offset[i];
  t->bp1 = r1(r1((float)p->gtm_b / 255.0f) + 1);
  t->c = r1((float)p->gtm_c / 255.0f);
  t->c1 = r1(t->c + 1);

  float weight = r1((float)p->guide_weight * (1.0f / 8192.0f)), bias = r1((float)p->guide_bias * (1.0f / 8192.0f));
  t->depth = malloc((LUMA_ONE + 1) * sizeof(float));
  for (int bits = 0; bits <= LUMA_ONE; bits++) {
    float e = half_of_double(exp(-(double)r1(r1(_cvtsh_ss(bits) * weight) + bias)));
    t->depth[bits] = r1(7 / r1(e + 1));
  }

  t->rows = axis_new(15.0f / (float)(height - 1), height, NNTM_GRID_Y - 1);
  t->cols = axis_new(15.0f / (float)(width - 1), width, NNTM_GRID_X - 1);
  t->uniform = malloc(width / 8);
  for (int x = 0; x < width; x += 8) t->uniform[x / 8] = t->cols.i0[x] == t->cols.i0[x + 7];
  for (int y = 0; y < height; y++) { t->rows.i0[y] <<= 8; t->rows.i1[y] <<= 8; }
  for (int x = 0; x < width; x++) { t->cols.i0[x] <<= 4; t->cols.i1[x] <<= 4; }
  t->blend = blend_new(p, width, height);
  t->reduce_x = reduce_new(width);
  t->reduce_y = reduce_new(height);
  return t;
}

void nntm_free(Nntm *t) {
  if (!t) return;
  axis_free(&t->rows);
  axis_free(&t->cols);
  free(t->depth); free(t->uniform); free(t->blend);
  free(t->reduce_x.index); free(t->reduce_x.coeff);
  free(t->reduce_y.index); free(t->reduce_y.coeff);
  free(t);
}

INLINE vf normalise(const Nntm *t, vf x, int ch, float k, float k0) {
  if (t->restricted) x = clampv(add(mul(x, set(k)), set(k0)), 0, 255);
  return mul(sub(x, set(t->offset[ch])), set(INV255));
}

typedef struct { vf u_rgb[3], v_rgb[3]; } Chroma;

INLINE Chroma chroma_load(const Nntm *t, const uint8_t *uv) {
  const __m128i pairs = _mm_setr_epi8(0, 0, 2, 2, 4, 4, 6, 6, 1, 1, 3, 3, 5, 5, 7, 7);
  vi split = VI(_mm256_castsi128_si256(_mm_shuffle_epi8(_mm_loadl_epi64((const __m128i *)(uv + 8 * n)), pairs)));
  vf un = normalise(t, VF(_mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(_mm256_castsi256_si128(split.l[n])))), 1, K_C, K_C0);
  vf vn = normalise(t, VF(_mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(_mm_srli_si128(_mm256_castsi256_si128(split.l[n]), 8)))), 2, K_C, K_C0);
  Chroma c;
  for (int i = 0; i < 3; i++) {
    c.u_rgb[i] = mul(un, set(t->yuv2rgb[3 * i + 1]));
    c.v_rgb[i] = mul(vn, set(t->yuv2rgb[3 * i + 2]));
  }
  return c;
}

typedef struct { vf ch[3], luma; } Rgb;

INLINE Rgb to_rgb(const Nntm *t, const uint8_t *y, const Chroma *c) {
  vf yn = normalise(t, VF(_mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(_mm_loadl_epi64((const __m128i *)(y + 8 * n))))), 0, K_Y, K_Y0);
  Rgb p;
  for (int i = 0; i < 3; i++) p.ch[i] = clampv(add(c->v_rgb[i], add(c->u_rgb[i], mul(yn, set(t->yuv2rgb[3 * i])))), 0, 1);
  p.luma = mul(add(p.ch[2], add(p.ch[1], p.ch[0])), set(THIRD));
  return p;
}

INLINE vf pick(const Nntm *t, const float *grid, int x, vi cell, vi depth, int coeff) {
  return VF(t->uniform[x / 8 + n]
              ? _mm256_permutevar8x32_ps(_mm256_loadu_ps(grid + _mm256_cvtsi256_si32(cell.l[n]) + 8 * coeff), depth.l[n])
              : _mm256_i32gather_ps(grid + 8 * coeff, _mm256_add_epi32(cell.l[n], depth.l[n]), 4));
}

INLINE vf gain(const Nntm *t, const float *grid, int y, int x, vf luma) {
  vf z = VF(_mm256_i32gather_ps(t->depth, _mm256_cvtepu16_epi32(_mm256_cvtps_ph(luma.l[n], RN)), 4));
  vf lo = VF(_mm256_floor_ps(z.l[n]));
  vi zi = VI(_mm256_cvttps_epi32(lo.l[n]));
  vi depth[2] = {clampi(zi, 0, NNTM_GRID_Z - 1), clampi(VI(_mm256_add_epi32(zi.l[n], _mm256_set1_epi32(1))), 0, NNTM_GRID_Z - 1)};
  vf wz[2] = {sub(add(lo, set(1)), z), sub(z, lo)};
  vf wy[2] = {set(t->rows.w0[y]), set(t->rows.w1[y])};
  vf wx[2] = {loadf(t->cols.w0 + x), loadf(t->cols.w1 + x)};
  int row[2] = {t->rows.i0[y], t->rows.i1[y]};
  vi col[2] = {loadi(t->cols.i0 + x), loadi(t->cols.i1 + x)};

  /* Half addition is not associative: the eight corners accumulate in this order. */
  vf acc[2];
  for (int j = 0; j < 2; j++)
    for (int i = 0; i < 2; i++) {
      vf wxy = mul(wx[i], wy[j]);
      vi cell = VI(_mm256_add_epi32(_mm256_set1_epi32(row[j]), col[i].l[n]));
      for (int k = 0; k < 2; k++) {
        vf w = mul(wz[k], wxy);
        for (int c = 0; c < 2; c++) {
          vf term = mul(w, pick(t, grid, x, cell, depth[k], c));
          acc[c] = i + j + k ? add(term, acc[c]) : term;
        }
      }
    }
  vf mapped = clampv(add(acc[1], mul(acc[0], luma)), 0, 1);
  vf blend = VF(_mm256_cvtph_ps(_mm_loadu_si128((const __m128i *)(t->blend + (size_t)y * t->width + x + 8 * n))));
  vf out = clampv(add(luma, mul(blend, sub(mapped, luma))), 0, 1), zero = set(0);
  return both(dvd(out, luma), CMP(luma, zero, _CMP_GT_OQ));
}

INLINE void apply_gain(const Nntm *t, Rgb *p, vf g) {
  vf one = set(1), zero = set(0), bp1 = set(t->bp1), luma = p->luma, lg = mul(g, luma);
  vf d[3] = {sub(p->ch[0], luma), sub(p->ch[1], luma), sub(p->ch[2], luma)};
  vf maxd = vmax(vmax(d[0], d[2]), d[1]);
  vf smax = choose(CMP(maxd, zero, _CMP_GT_OQ), dvd(sub(one, lg), maxd), set(255));
  vf num = vmax(sub(bp1, lg), zero), inv = dvd(one, sub(bp1, luma)), power = one;
  for (int i = 0; i < t->gtm_a; i++) power = mul(mul(num, power), inv);
  vf s = vmin(smax, dvd(mul(add(set(t->c), g), power), set(t->c1)));
  vf grey = both(CMP(p->ch[0], p->ch[1], _CMP_EQ_OQ), CMP(p->ch[0], p->ch[2], _CMP_EQ_OQ));
  vf dim = CMP(g, one, _CMP_LT_OQ);
  for (int i = 0; i < 3; i++) {
    vf boosted = choose(grey, vmin(lg, one), add(lg, mul(s, d[i])));
    p->ch[i] = choose(dim, vmin(mul(g, p->ch[i]), one), boosted);
  }
}

INLINE vf to_yuv(const Nntm *t, const Rgb *p, int row) {
  const float *m = t->rgb2yuv + 3 * row;
  return mul(add(mul(set(m[2]), p->ch[2]), add(mul(set(m[1]), p->ch[1]), mul(set(m[0]), p->ch[0]))), set(255));
}

INLINE vbytes quantise(const Nntm *t, vf x, int ch) {
  const __m256 sign = _mm256_set1_ps(-0.0f);
  vi q = VI(_mm256_add_epi32(
    _mm256_cvttps_epi32(_mm256_or_ps(_mm256_floor_ps(_mm256_andnot_ps(sign, x.l[n]) + _mm256_set1_ps(0.5f)),
                                     _mm256_and_ps(sign, x.l[n]))),
    _mm256_set1_epi32((int)t->offset[ch])));
  q = clampi(q, 0, 255);
  if (t->restricted) {
    vi scaled = VI(_mm256_add_epi32(_mm256_mullo_epi32(q.l[n], _mm256_set1_epi32(ch ? 224 : 220)), _mm256_set1_epi32(128)));
    vi tie = VI(_mm256_cmpeq_epi32(_mm256_and_si256(scaled.l[n], _mm256_set1_epi32(255)), _mm256_setzero_si256()));
    vi whole = VI(_mm256_andnot_si256(_mm256_and_si256(tie.l[n], _mm256_set1_epi32(1)), _mm256_srli_epi32(scaled.l[n], 8)));
    q = clampi(VI(_mm256_add_epi32(whole.l[n], _mm256_set1_epi32(16))), 16, ch ? 240 : 235);
  }
  return VBYTES(_mm_packus_epi16(
    _mm_packus_epi32(_mm256_castsi256_si128(q.l[n]), _mm256_extracti128_si256(q.l[n], 1)), _mm_setzero_si128()));
}

INLINE vf block_mean(vf top, vf bottom) {
  const __m256i even = _mm256_setr_epi32(0, 2, 4, 6, 0, 2, 4, 6), odd = _mm256_setr_epi32(1, 3, 5, 7, 1, 3, 5, 7);
  vf sum = add(VF(_mm256_permutevar8x32_ps(top.l[n], odd)), VF(_mm256_permutevar8x32_ps(top.l[n], even)));
  sum = add(VF(_mm256_permutevar8x32_ps(bottom.l[n], even)), sum);
  sum = add(VF(_mm256_permutevar8x32_ps(bottom.l[n], odd)), sum);
  return mul(sum, set(0.25f));
}

void nntm_apply_rows(const Nntm *t, const NntmGrid grid, NntmFrame *f, int row0, int row1) {
  for (int y = row0; y < row1; y += 2) {
    uint8_t *uv = f->uv + (size_t)(y / 2) * f->uv_stride;
    for (int x = 0; x < t->width; x += NNTM_STEP) {
      Chroma c = chroma_load(t, uv + x);
      vf u[2], v[2];
      for (int k = 0; k < 2; k++) {
        uint8_t *luma = f->y + (size_t)(y + k) * f->y_stride + x;
        Rgb p = to_rgb(t, luma, &c);
        apply_gain(t, &p, gain(t, grid, y + k, x, p.luma));
        vbytes bytes = quantise(t, to_yuv(t, &p, 0), 0);
        for (int n = 0; n < LANES; n++) _mm_storel_epi64((__m128i *)(luma + 8 * n), bytes.l[n]);
        u[k] = to_yuv(t, &p, 1);
        v[k] = to_yuv(t, &p, 2);
      }
      vbytes ub = quantise(t, block_mean(u[0], u[1]), 1), vb = quantise(t, block_mean(v[0], v[1]), 2);
      for (int n = 0; n < LANES; n++)
        _mm_storel_epi64((__m128i *)(uv + x + 8 * n), _mm_unpacklo_epi8(ub.l[n], vb.l[n]));
    }
  }
}

void nntm_luma_rows(const Nntm *t, const NntmFrame *f, float *narrow, int row0, int row1) {
  const Reduce *r = &t->reduce_x;
  float line[NNTM_MAX_SIZE];
  for (int y = row0; y < row1; y++) {
    const uint8_t *luma = f->y + (size_t)y * f->y_stride, *uv = f->uv + (size_t)(y / 2) * f->uv_stride;
    for (int x = 0; x < t->width; x += NNTM_STEP) {
      Chroma c = chroma_load(t, uv + x);
      vf l = to_rgb(t, luma + x, &c).luma;
      for (int n = 0; n < LANES; n++) _mm256_storeu_ps(line + x + 8 * n, l.l[n]);
    }
    for (int xx = 0; xx < NNTM_NET_SIZE; xx += NNTM_STEP) {
      vf acc = set(0);
      for (int i = 0; i < r->taps; i++) {
        vi index = loadi(r->index + i * NNTM_NET_SIZE + xx);
        acc = add(mul(loadf(r->coeff + i * NNTM_NET_SIZE + xx), VF(_mm256_i32gather_ps(line, index.l[n], 4))), acc);
      }
      for (int n = 0; n < LANES; n++) _mm256_storeu_ps(narrow + (size_t)y * NNTM_NET_SIZE + xx + 8 * n, acc.l[n]);
    }
  }
}

void nntm_luma_finish(const Nntm *t, const float *narrow, uint16_t *net_input) {
  const Reduce *r = &t->reduce_y;
  for (int yy = 0; yy < NNTM_NET_SIZE; yy++)
    for (int x = 0; x < NNTM_NET_SIZE; x += NNTM_STEP) {
      vf acc = set(0);
      for (int i = 0; i < r->taps; i++)
        acc = add(mul(set(r->coeff[i * NNTM_NET_SIZE + yy]),
                      loadf(narrow + (size_t)r->index[i * NNTM_NET_SIZE + yy] * NNTM_NET_SIZE + x)), acc);
      for (int n = 0; n < LANES; n++)
        _mm_storeu_si128((__m128i *)(net_input + yy * NNTM_NET_SIZE + x + 8 * n), _mm256_cvtps_ph(acc.l[n], RN));
    }
}

void nntm_grid_identity(uint16_t *fresh) {
  for (int i = 0; i < NNTM_GRID_LEN; i++) fresh[i] = i & 1 ? 0 : LUMA_ONE;
}

void nntm_grid_filter(NntmGrid state, const uint16_t *fresh, bool first) {
  const float a = r1((float)FILTER_STRENGTH);
  for (int cell = 0; cell < NNTM_GRID_LEN / 2; cell++)
    for (int c = 0; c < 2; c++) {
      float value = _cvtsh_ss(fresh[2 * cell + c]);
      float *s = &state[(cell >> 3) * 16 + 8 * c + (cell & 7)];
      *s = first ? value : r1((1.0f - a) * *s + r1(value * a));
    }
}
