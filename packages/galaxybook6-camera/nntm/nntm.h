#ifndef NNTM_H
#define NNTM_H

#include <stdbool.h>
#include <stdint.h>

enum {
  NNTM_GRID_Y = 16,
  NNTM_GRID_X = 16,
  NNTM_GRID_Z = 8,
  NNTM_GRID_LEN = NNTM_GRID_Y * NNTM_GRID_X * NNTM_GRID_Z * 2,
  NNTM_NET_SIZE = 256,
  NNTM_MAX_SIZE = 2048,
  NNTM_STEP = 64,
};

/* Filtered bilateral grid of affine luma coefficients as nntm_apply_rows reads it:
 * half-representable floats, [row][column][coefficient][depth]. */
typedef float NntmGrid[NNTM_GRID_LEN];

/* Parameter set in the units of Samsung's nntm_control tuning record. */
typedef struct {
  bool restricted;
  int offset[3];
  int yuv2rgb[9];
  int rgb2yuv[9];
  int gtm_a, gtm_b, gtm_c;
  int guide_weight, guide_bias;
  float strength, radial;
  int shading_w, shading_h;
  const float *shading;
} NntmParams;

/* NV12 planes. Width must be a multiple of NNTM_STEP and height even, both at most NNTM_MAX_SIZE. */
typedef struct {
  uint8_t *y, *uv;
  int y_stride, uv_stride;
  int width, height;
} NntmFrame;

/* Tables derived from one parameter set and one frame size. */
typedef struct Nntm Nntm;

extern const NntmParams nntm_samsung_params;

Nntm *nntm_new(const NntmParams *params, int width, int height);
void nntm_free(Nntm *t);

/* Network input: luma of rows [row0, row1) reduced horizontally into rows of NNTM_NET_SIZE floats. */
void nntm_luma_rows(const Nntm *t, const NntmFrame *f, float *narrow, int row0, int row1);
/* Vertical reduction of all narrow rows into NNTM_NET_SIZE * NNTM_NET_SIZE halves. */
void nntm_luma_finish(const Nntm *t, const float *narrow, uint16_t *net_input);

/* Blend map at the shading grid's size, as the Windows parameter kernel stores it: blend * 65536. */
void nntm_blend_q16(const NntmParams *params, int32_t *q16);

/* `fresh` is a network output: NNTM_GRID_LEN halves, [row][column][depth][coefficient]. */
void nntm_grid_identity(uint16_t *fresh);
void nntm_grid_filter(NntmGrid state, const uint16_t *fresh, bool first);
/* The filtered grid as halves in the network's order, which is how Samsung's ltm_gain kernel reads it. */
void nntm_grid_halves(const NntmGrid state, uint16_t *halves);

/* Tone-map rows [row0, row1) in place; row0 and row1 are even. */
void nntm_apply_rows(const Nntm *t, const NntmGrid grid, NntmFrame *f, int row0, int row1);

#endif
