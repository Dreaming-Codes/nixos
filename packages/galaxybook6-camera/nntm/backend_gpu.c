#define CL_TARGET_OPENCL_VERSION 300
#define _GNU_SOURCE
#include <CL/cl.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "backend.h"

enum { WRAP_SLOTS = 16 };

typedef struct { int64_t v; } SyclRange;
typedef struct { int v[3]; } Int3;
typedef struct { float v[9]; } Float9;

typedef struct {
  const void *host;
  cl_mem mem;
} Wrap;

typedef struct {
  NntmBackend base;
  cl_device_id device;
  cl_context context;
  cl_command_queue queue;
  cl_program pixels, resize;
  cl_kernel preprocess, ltm_gain, postprocess, coeffs, resample_w, resample_h;
  int width, height;
  cl_mem luma, gain, narrow, small, coeff_w, bounds_w, coeff_h, bounds_h, grid, blend;
  uint16_t grid_halves[NNTM_GRID_LEN];
  Wrap wraps[WRAP_SLOTS];
  int next_wrap;
  uint8_t *staging;
  cl_mem frame;
  bool frame_owned;
} Gpu;

#define TRY(call) do { if ((call) != CL_SUCCESS) return false; } while (0)
#define ARG(k, i, v) TRY(clSetKernelArg((k), (i), sizeof(v), &(v)))

static size_t frame_bytes(const Gpu *g) { return (size_t)g->width * g->height * 3 / 2; }

static void release_mem(cl_mem *m) {
  if (*m) clReleaseMemObject(*m);
  *m = NULL;
}

static void forget_frames(Gpu *g) {
  for (int i = 0; i < WRAP_SLOTS; i++) {
    release_mem(&g->wraps[i].mem);
    g->wraps[i].host = NULL;
  }
  g->next_wrap = 0;
}

static void release_sized(Gpu *g) {
  forget_frames(g);
  cl_mem *all[] = {&g->luma, &g->gain, &g->narrow, &g->small, &g->coeff_w, &g->bounds_w, &g->coeff_h, &g->bounds_h, &g->grid, &g->blend};
  for (size_t i = 0; i < sizeof all / sizeof *all; i++) release_mem(all[i]);
  free(g->staging);
  g->staging = NULL;
}

static bool buffer(Gpu *g, cl_mem *m, cl_mem_flags flags, size_t size, void *host) {
  cl_int e;
  *m = clCreateBuffer(g->context, flags, size, host, &e);
  return e == CL_SUCCESS;
}

static bool run(Gpu *g, cl_kernel k, int dims, size_t x, size_t y) {
  size_t global[2] = {x, y};
  return clEnqueueNDRangeKernel(g->queue, k, dims, NULL, global, NULL, 0, NULL, NULL) == CL_SUCCESS;
}

/* Samsung's kernels index the chroma plane as y + width * height with both strides equal to width. */
static bool contiguous(const Gpu *g, const NntmFrame *f) {
  return f->y_stride == g->width && f->uv_stride == g->width && f->uv == f->y + (size_t)g->width * g->height;
}

static float support(int in) {
  float scale = (float)in / (float)NNTM_NET_SIZE;
  return scale < 1 ? 1 : scale;
}

static int taps(int in) { return (int)ceilf(support(in)) * 2 + 1; }

static bool coefficients(Gpu *g, cl_mem coeff, cl_mem bounds, int in) {
  const SyclRange zero = {0};
  float scale = (float)in / (float)NNTM_NET_SIZE, reach = support(in);
  int n = taps(in);
  ARG(g->coeffs, 0, coeff); ARG(g->coeffs, 1, zero); ARG(g->coeffs, 2, bounds); ARG(g->coeffs, 3, zero);
  ARG(g->coeffs, 4, in); ARG(g->coeffs, 5, scale); ARG(g->coeffs, 6, reach); ARG(g->coeffs, 7, n);
  return run(g, g->coeffs, 1, NNTM_NET_SIZE, 1);
}

static bool configure(Gpu *g, int width, int height) {
  release_sized(g);
  g->width = width;
  g->height = height;
  const int net = NNTM_NET_SIZE, taps_w = taps(width), taps_h = taps(height);
  const size_t px = (size_t)width * height;
  bool made = buffer(g, &g->luma, CL_MEM_READ_WRITE, px * 2, NULL) && buffer(g, &g->gain, CL_MEM_READ_WRITE, px * 2, NULL) &&
              buffer(g, &g->narrow, CL_MEM_READ_WRITE, (size_t)height * net * 2, NULL) &&
              buffer(g, &g->small, CL_MEM_READ_WRITE | CL_MEM_ALLOC_HOST_PTR, (size_t)net * net * 2, NULL) &&
              buffer(g, &g->coeff_w, CL_MEM_READ_WRITE, (size_t)net * taps_w * 2, NULL) &&
              buffer(g, &g->bounds_w, CL_MEM_READ_WRITE, (size_t)net * 2 * 4, NULL) &&
              buffer(g, &g->coeff_h, CL_MEM_READ_WRITE, (size_t)net * taps_h * 2, NULL) &&
              buffer(g, &g->bounds_h, CL_MEM_READ_WRITE, (size_t)net * 2 * 4, NULL) &&
              buffer(g, &g->grid, CL_MEM_READ_ONLY | CL_MEM_ALLOC_HOST_PTR, NNTM_GRID_LEN * 2, NULL) &&
              buffer(g, &g->blend, CL_MEM_READ_ONLY, NNTM_BLEND_MAX * sizeof(int32_t), NULL);
  if (!made || posix_memalign((void **)&g->staging, 4096, frame_bytes(g))) return false;
  if (!coefficients(g, g->coeff_w, g->bounds_w, width) || !coefficients(g, g->coeff_h, g->bounds_h, height)) return false;

  const SyclRange zero = {0}, whole = {(int64_t)frame_bytes(g)}, plane = {(int64_t)px};
  float row_scale = 15.0f / (float)(height - 1), col_scale = 15.0f / (float)(width - 1);

  cl_kernel k = g->preprocess;
  ARG(k, 1, zero); ARG(k, 2, g->luma); ARG(k, 3, zero); ARG(k, 7, width); ARG(k, 8, height);
  k = g->resample_w;
  ARG(k, 0, g->luma); ARG(k, 1, zero); ARG(k, 2, g->narrow); ARG(k, 3, zero); ARG(k, 4, g->bounds_w); ARG(k, 5, zero);
  ARG(k, 6, g->coeff_w); ARG(k, 7, zero); ARG(k, 8, width); ARG(k, 9, net); ARG(k, 10, taps_w);
  k = g->resample_h;
  ARG(k, 0, g->narrow); ARG(k, 1, zero); ARG(k, 2, g->small); ARG(k, 3, zero); ARG(k, 4, g->bounds_h); ARG(k, 5, zero);
  ARG(k, 6, g->coeff_h); ARG(k, 7, zero); ARG(k, 8, net); ARG(k, 9, net); ARG(k, 10, taps_h);
  k = g->ltm_gain;
  ARG(k, 0, g->luma); ARG(k, 1, zero); ARG(k, 2, g->grid); ARG(k, 3, zero); ARG(k, 4, g->blend); ARG(k, 5, zero);
  ARG(k, 6, g->gain); ARG(k, 7, zero); ARG(k, 10, row_scale); ARG(k, 11, col_scale); ARG(k, 16, width);
  k = g->postprocess;
  ARG(k, 1, whole); ARG(k, 2, whole); ARG(k, 3, zero); ARG(k, 4, g->gain); ARG(k, 5, plane); ARG(k, 6, plane); ARG(k, 7, zero);
  ARG(k, 9, whole); ARG(k, 10, whole); ARG(k, 11, zero); ARG(k, 21, width); ARG(k, 22, height);
  return clFinish(g->queue) == CL_SUCCESS;
}

static bool set_params(Gpu *g, const NntmParams *p) {
  Int3 offset = {{p->offset[0], p->offset[1], p->offset[2]}};
  Float9 yuv2rgb, rgb2yuv;
  float luma_row = (float)((p->rgb2yuv[1] + p->rgb2yuv[0]) + p->rgb2yuv[2]);
  for (int i = 0; i < 9; i++) {
    yuv2rgb.v[i] = (float)p->yuv2rgb[i] / (float)p->yuv2rgb[0];
    rgb2yuv.v[i] = (float)p->rgb2yuv[i] / luma_row;
  }
  const int input_restricted = p->input_restricted, output_restricted = p->output_restricted;
  float weight = (float)p->guide_weight * (1.0f / 8192.0f), bias = (float)p->guide_bias * (1.0f / 8192.0f);
  float blend_rows = (float)(p->blend_h - 1) / (float)(g->height - 1), blend_cols = (float)(p->blend_w - 1) / (float)(g->width - 1);
  float gtm_b = (float)p->gtm_b / 255.0f, gtm_c = (float)p->gtm_c / 255.0f;
  TRY(clEnqueueWriteBuffer(g->queue, g->blend, CL_TRUE, 0, (size_t)p->blend_w * p->blend_h * sizeof(int32_t), p->blend, 0, NULL, NULL));

  cl_kernel k = g->preprocess;
  ARG(k, 4, offset); ARG(k, 5, yuv2rgb); ARG(k, 6, input_restricted);
  k = g->ltm_gain;
  ARG(k, 8, weight); ARG(k, 9, bias); ARG(k, 12, blend_rows); ARG(k, 13, blend_cols); ARG(k, 14, p->blend_h); ARG(k, 15, p->blend_w);
  k = g->postprocess;
  ARG(k, 12, offset); ARG(k, 13, yuv2rgb); ARG(k, 14, offset); ARG(k, 15, rgb2yuv); ARG(k, 16, input_restricted);
  ARG(k, 17, output_restricted); ARG(k, 18, p->gtm_a); ARG(k, 19, gtm_b); ARG(k, 20, gtm_c);
  return true;
}

static cl_mem wrap(Gpu *g, const void *host) {
  cl_int e;
  cl_mem m = clCreateBuffer(g->context, CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR, frame_bytes(g), (void *)host, &e);
  return e == CL_SUCCESS ? m : NULL;
}

static cl_mem wrap_cached(Gpu *g, const void *host) {
  for (int i = 0; i < WRAP_SLOTS; i++)
    if (g->wraps[i].mem && g->wraps[i].host == host) return g->wraps[i].mem;
  Wrap *slot = &g->wraps[g->next_wrap];
  g->next_wrap = (g->next_wrap + 1) % WRAP_SLOTS;
  release_mem(&slot->mem);
  slot->host = host;
  slot->mem = wrap(g, host);
  return slot->mem;
}

static bool prepare(Gpu *g, NntmFrame *f, bool persistent, uint16_t *net_input) {
  const void *host = f->y;
  if (!contiguous(g, f)) {
    for (int y = 0; y < g->height; y++) memcpy(g->staging + (size_t)y * g->width, f->y + (size_t)y * f->y_stride, g->width);
    uint8_t *uv = g->staging + (size_t)g->width * g->height;
    for (int y = 0; y < g->height / 2; y++) memcpy(uv + (size_t)y * g->width, f->uv + (size_t)y * f->uv_stride, g->width);
    host = g->staging;
    persistent = true;
  }
  g->frame_owned = !persistent;
  g->frame = persistent ? wrap_cached(g, host) : wrap(g, host);
  if (!g->frame) return false;
  if (persistent) {
    /* The host rewrote the frame since its last use. The runtime may keep its own copy of host memory
     * and only picks up host writes through a map; invalidating keeps the map from copying the old
     * output back over the new frame. */
    cl_int e;
    void *p = clEnqueueMapBuffer(g->queue, g->frame, CL_FALSE, CL_MAP_WRITE_INVALIDATE_REGION, 0, frame_bytes(g), 0, NULL, NULL, &e);
    TRY(e);
    TRY(clEnqueueUnmapMemObject(g->queue, g->frame, p, 0, NULL, NULL));
  }
  ARG(g->preprocess, 0, g->frame);
  ARG(g->postprocess, 0, g->frame);
  ARG(g->postprocess, 8, g->frame);
  if (!run(g, g->preprocess, 2, g->width / 2, g->height / 2)) return false;
  if (!net_input) return true;
  if (!run(g, g->resample_w, 2, NNTM_NET_SIZE, g->height) || !run(g, g->resample_h, 2, NNTM_NET_SIZE, NNTM_NET_SIZE)) return false;
  return clEnqueueReadBuffer(g->queue, g->small, CL_TRUE, 0, NNTM_NET_SIZE * NNTM_NET_SIZE * 2, net_input, 0, NULL, NULL) == CL_SUCCESS;
}

static bool apply(Gpu *g, const NntmGrid grid, NntmFrame *f) {
  cl_int e;
  nntm_grid_halves(grid, g->grid_halves);
  TRY(clEnqueueWriteBuffer(g->queue, g->grid, CL_FALSE, 0, sizeof g->grid_halves, g->grid_halves, 0, NULL, NULL));
  if (!run(g, g->ltm_gain, 2, g->width / 2, g->height / 2) || !run(g, g->postprocess, 2, g->width / 2, g->height / 2)) return false;
  void *out = clEnqueueMapBuffer(g->queue, g->frame, CL_TRUE, CL_MAP_READ, 0, frame_bytes(g), 0, NULL, NULL, &e);
  if (e != CL_SUCCESS) return false;
  TRY(clEnqueueUnmapMemObject(g->queue, g->frame, out, 0, NULL, NULL));
  if (g->frame_owned) {
    release_mem(&g->frame);
    TRY(clFinish(g->queue));
  } else {
    TRY(clFlush(g->queue));
  }
  if (!contiguous(g, f)) {
    for (int y = 0; y < g->height; y++) memcpy(f->y + (size_t)y * f->y_stride, g->staging + (size_t)y * g->width, g->width);
    const uint8_t *uv = g->staging + (size_t)g->width * g->height;
    for (int y = 0; y < g->height / 2; y++) memcpy(f->uv + (size_t)y * f->uv_stride, uv + (size_t)y * g->width, g->width);
  }
  return true;
}

static void gpu_free(NntmBackend *b) {
  Gpu *g = (Gpu *)b;
  if (g->queue) clFinish(g->queue);
  release_sized(g);
  cl_kernel kernels[] = {g->preprocess, g->ltm_gain, g->postprocess, g->coeffs, g->resample_w, g->resample_h};
  for (size_t i = 0; i < sizeof kernels / sizeof *kernels; i++)
    if (kernels[i]) clReleaseKernel(kernels[i]);
  if (g->pixels) clReleaseProgram(g->pixels);
  if (g->resize) clReleaseProgram(g->resize);
  if (g->queue) clReleaseCommandQueue(g->queue);
  if (g->context) clReleaseContext(g->context);
  free(g);
}

static bool gpu_configure(NntmBackend *b, int width, int height) { return configure((Gpu *)b, width, height); }
static bool gpu_set_params(NntmBackend *b, const NntmParams *p) { return set_params((Gpu *)b, p); }
static bool gpu_prepare(NntmBackend *b, NntmFrame *f, bool persistent, uint16_t *net_input) { return prepare((Gpu *)b, f, persistent, net_input); }
static bool gpu_apply(NntmBackend *b, const NntmGrid grid, NntmFrame *f) { return apply((Gpu *)b, grid, f); }

static const NntmBackendClass gpu_class = {
  .name = "gpu",
  .net_device = "GPU",
  .net_property = "INFERENCE_PRECISION_HINT",
  .net_property_value = "f16",
  .configure = gpu_configure,
  .set_params = gpu_set_params,
  .prepare = gpu_prepare,
  .apply = gpu_apply,
  .free = gpu_free,
};

static char *message(const char *format, ...) {
  va_list ap;
  char *s = NULL;
  va_start(ap, format);
  if (vasprintf(&s, format, ap) < 0) s = NULL;
  va_end(ap);
  return s;
}

static bool find_gpu(cl_device_id *device) {
  cl_platform_id platforms[8];
  cl_uint n = 0;
  if (clGetPlatformIDs(8, platforms, &n) != CL_SUCCESS) return false;
  for (cl_uint i = 0; i < n && i < 8; i++)
    if (clGetDeviceIDs(platforms[i], CL_DEVICE_TYPE_GPU, 1, device, NULL) == CL_SUCCESS) return true;
  return false;
}

static cl_program program(Gpu *g, const char *data_dir, const char *file, char **error) {
  char *path = message("%s/%s", data_dir, file);
  FILE *in = path ? fopen(path, "rb") : NULL;
  cl_program p = NULL;
  if (!in) {
    *error = message("cannot read %s", path);
    free(path);
    return NULL;
  }
  fseek(in, 0, SEEK_END);
  long len = ftell(in);
  rewind(in);
  void *il = malloc(len);
  cl_int e = fread(il, 1, len, in) == (size_t)len ? CL_SUCCESS : CL_INVALID_VALUE;
  fclose(in);
  if (e == CL_SUCCESS) p = clCreateProgramWithIL(g->context, il, len, &e);
  if (e == CL_SUCCESS) e = clBuildProgram(p, 1, &g->device, "", NULL, NULL);
  if (e != CL_SUCCESS) {
    *error = message("cannot build %s: OpenCL error %d", path, e);
    if (p) clReleaseProgram(p);
    p = NULL;
  }
  free(il);
  free(path);
  return p;
}

static bool kernel(Gpu *g, cl_kernel *k, cl_program p, const char *name, char **error) {
  cl_int e;
  *k = clCreateKernel(p, name, &e);
  if (e != CL_SUCCESS) *error = message("no kernel %s: OpenCL error %d", name, e);
  return e == CL_SUCCESS;
}

NntmBackend *nntm_gpu_new(const char *data_dir, char **error) {
  Gpu *g = calloc(1, sizeof *g);
  cl_int e = CL_SUCCESS;
  g->base.klass = &gpu_class;
  *error = NULL;
  if (!find_gpu(&g->device)) {
    *error = message("no OpenCL GPU device");
    goto failed;
  }
  g->context = clCreateContext(NULL, 1, &g->device, NULL, NULL, &e);
  if (e == CL_SUCCESS) g->queue = clCreateCommandQueueWithProperties(g->context, g->device, NULL, &e);
  if (e != CL_SUCCESS) {
    *error = message("cannot open the GPU: OpenCL error %d", e);
    goto failed;
  }
  if (!(g->pixels = program(g, data_dir, "nntm.spv", error)) || !(g->resize = program(g, data_dir, "resize.spv", error)))
    goto failed;
  if (kernel(g, &g->preprocess, g->pixels, "_ZTS10preprocess", error) && kernel(g, &g->ltm_gain, g->pixels, "_ZTS8ltm_gain", error) &&
      kernel(g, &g->postprocess, g->pixels, "_ZTS11postprocess", error) &&
      kernel(g, &g->coeffs, g->resize, "_ZTS16precomputeCoeffs", error) &&
      kernel(g, &g->resample_w, g->resize, "_ZTS10resample_w", error) && kernel(g, &g->resample_h, g->resize, "_ZTS10resample_h", error))
    return &g->base;
failed:
  gpu_free(&g->base);
  return NULL;
}
