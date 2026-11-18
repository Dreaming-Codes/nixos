/* nntm: Samsung's Windows neural tone-mapping stage as an in-place NV12 video filter. */
#include <gst/gst.h>
#include <gst/video/gstvideofilter.h>
#include <gst/video/video.h>
#include <openvino/c/openvino.h>

#include "nntm.h"

#define GST_TYPE_NNTM (gst_nntm_get_type())
G_DECLARE_FINAL_TYPE(GstNntm, gst_nntm, GST, NNTM, GstVideoFilter)

GST_DEBUG_CATEGORY_STATIC(nntm_debug);
#define GST_CAT_DEFAULT nntm_debug

enum { SWEEP_ROWS = 16 };
enum { RANGE_FULL, RANGE_LIMITED };
enum { PROP_0, PROP_RANGE, PROP_STRENGTH, PROP_RADIAL, PROP_BYPASS, PROP_THREADS, PROP_IDENTITY_GRID, PROP_DATA_DIR };

/* One pass over the rows of the current frame, shared between the streaming thread and the pool. */
typedef struct {
  GstNntm *self;
  void (*rows)(GstNntm *self, int row0, int row1);
  gint next, running;
  GMutex lock;
  GCond done;
} Sweep;

struct _GstNntm {
  GstVideoFilter parent;

  gint range;
  gfloat strength, radial;
  gboolean bypass, identity_grid;
  guint threads;
  gchar *data_dir;

  NntmParams params;
  gfloat *shading;
  Nntm *tables;
  gboolean stale, first;
  NntmFrame frame;
  gfloat *grid, *narrow;
  guint16 *net_input;

  ov_core_t *core;
  ov_compiled_model_t *compiled;
  ov_infer_request_t *request;
  ov_tensor_t *input;
  GThreadPool *pool;
  guint64 frames, usec[3];
};

G_DEFINE_TYPE(GstNntm, gst_nntm, GST_TYPE_VIDEO_FILTER)

#define NNTM_CAPS \
  "video/x-raw, format=(string)NV12, width=(int)[%d, %d, %d], height=(int)[2, %d, 2], " \
  "framerate=(fraction)[0/1, 2147483647/1]"

static GType range_type(void) {
  static const GEnumValue values[] = {
    {RANGE_FULL, "Y 0..255", "full"}, {RANGE_LIMITED, "Y 16..235", "limited"}, {0, NULL, NULL}};
  static GType type;
  if (g_once_init_enter(&type)) g_once_init_leave(&type, g_enum_register_static("GstNntmRange", values));
  return type;
}

static void sweep_work(gpointer data, gpointer unused) {
  Sweep *s = data;
  int height = s->self->frame.height;
  for (int row; (row = g_atomic_int_add(&s->next, SWEEP_ROWS)) < height;)
    s->rows(s->self, row, MIN(row + SWEEP_ROWS, height));
  g_mutex_lock(&s->lock);
  if (--s->running == 0) g_cond_signal(&s->done);
  g_mutex_unlock(&s->lock);
}

static void sweep(GstNntm *self, void (*rows)(GstNntm *, int, int)) {
  Sweep s = {.self = self, .rows = rows, .running = self->threads};
  g_mutex_init(&s.lock);
  g_cond_init(&s.done);
  for (guint i = 1; i < self->threads; i++) g_thread_pool_push(self->pool, &s, NULL);
  sweep_work(&s, NULL);
  g_mutex_lock(&s.lock);
  while (s.running) g_cond_wait(&s.done, &s.lock);
  g_mutex_unlock(&s.lock);
  g_mutex_clear(&s.lock);
  g_cond_clear(&s.done);
}

static void luma_rows(GstNntm *self, int row0, int row1) {
  nntm_luma_rows(self->tables, &self->frame, self->narrow, row0, row1);
}

static void apply_rows(GstNntm *self, int row0, int row1) {
  nntm_apply_rows(self->tables, self->grid, &self->frame, row0, row1);
}

static gboolean load_shading(GstNntm *self) {
  g_autofree gchar *path = g_build_filename(self->data_dir, "shading.f32", NULL);
  g_autofree gchar *data = NULL;
  gsize len;
  if (!g_file_get_contents(path, &data, &len, NULL) || len < 8) return FALSE;
  guint32 w = GST_READ_UINT32_LE(data), h = GST_READ_UINT32_LE(data + 4);
  if (len != 8 + (gsize)w * h * sizeof(gfloat)) return FALSE;
  self->shading = g_memdup2(data + 8, len - 8);
  self->params.shading_w = w;
  self->params.shading_h = h;
  self->params.shading = self->shading;
  return TRUE;
}

static gboolean load_network(GstNntm *self) {
  g_autofree gchar *xml = g_build_filename(self->data_dir, "nntm.xml", NULL);
  g_autofree gchar *bin = g_build_filename(self->data_dir, "nntm.bin", NULL);
  int64_t dims[4] = {1, 1, NNTM_NET_SIZE, NNTM_NET_SIZE};
  self->net_input = g_new(guint16, NNTM_NET_SIZE * NNTM_NET_SIZE);
  ov_model_t *model = NULL;
  ov_shape_t shape;
  gboolean ok = ov_core_create(&self->core) == OK && ov_core_read_model(self->core, xml, bin, &model) == OK &&
                ov_core_compile_model(self->core, model, "CPU", 2, &self->compiled, "INFERENCE_NUM_THREADS", "1") == OK &&
                ov_compiled_model_create_infer_request(self->compiled, &self->request) == OK &&
                ov_shape_create(4, dims, &shape) == OK;
  if (ok) {
    ok = ov_tensor_create_from_host_ptr(F16, shape, self->net_input, &self->input) == OK &&
         ov_infer_request_set_input_tensor(self->request, self->input) == OK;
    ov_shape_free(&shape);
  }
  if (model) ov_model_free(model);
  return ok;
}

static gboolean gst_nntm_start(GstBaseTransform *trans) {
  GstNntm *self = GST_NNTM(trans);
  if (!load_shading(self) || !load_network(self)) {
    GST_ELEMENT_ERROR(self, RESOURCE, OPEN_READ, ("cannot load tone-mapping data from %s", self->data_dir), (NULL));
    return FALSE;
  }
  if (self->threads > 1) self->pool = g_thread_pool_new(sweep_work, NULL, self->threads - 1, TRUE, NULL);
  self->grid = g_new(gfloat, NNTM_GRID_LEN);
  self->first = self->stale = TRUE;
  self->frames = self->usec[0] = self->usec[1] = self->usec[2] = 0;
  return TRUE;
}

static gboolean gst_nntm_stop(GstBaseTransform *trans) {
  GstNntm *self = GST_NNTM(trans);
  if (self->frames)
    GST_INFO_OBJECT(self, "%" G_GUINT64_FORMAT " frames, mean ms: luma %.2f network %.2f apply %.2f", self->frames,
                    self->usec[0] / 1e3 / self->frames, self->usec[1] / 1e3 / self->frames,
                    self->usec[2] / 1e3 / self->frames);
  if (self->pool) g_thread_pool_free(self->pool, FALSE, TRUE);
  if (self->input) ov_tensor_free(self->input);
  if (self->request) ov_infer_request_free(self->request);
  if (self->compiled) ov_compiled_model_free(self->compiled);
  if (self->core) ov_core_free(self->core);
  nntm_free(self->tables);
  g_free(self->shading);
  g_free(self->narrow);
  g_free(self->grid);
  g_free(self->net_input);
  self->pool = NULL;
  self->input = NULL;
  self->request = NULL;
  self->compiled = NULL;
  self->core = NULL;
  self->tables = NULL;
  self->shading = self->narrow = self->grid = NULL;
  self->net_input = NULL;
  return TRUE;
}

static GstFlowReturn gst_nntm_transform_frame_ip(GstVideoFilter *filter, GstVideoFrame *frame) {
  GstNntm *self = GST_NNTM(filter);
  guint16 identity[NNTM_GRID_LEN];
  const guint16 *fresh = identity;
  ov_tensor_t *output = NULL;
  gint64 t[4];

  GST_OBJECT_LOCK(self);
  gboolean bypass = self->bypass, identity_grid = self->identity_grid;
  if (self->stale && !bypass) {
    self->params.restricted = self->range == RANGE_LIMITED;
    self->params.strength = self->strength;
    self->params.radial = self->radial;
    self->frame.width = GST_VIDEO_FRAME_WIDTH(frame);
    self->frame.height = GST_VIDEO_FRAME_HEIGHT(frame);
    nntm_free(self->tables);
    self->tables = nntm_new(&self->params, self->frame.width, self->frame.height);
    self->narrow = g_realloc(self->narrow, (gsize)self->frame.height * NNTM_NET_SIZE * sizeof(gfloat));
    self->stale = FALSE;
  }
  GST_OBJECT_UNLOCK(self);
  if (bypass) return GST_FLOW_OK;

  self->frame.y = GST_VIDEO_FRAME_PLANE_DATA(frame, 0);
  self->frame.uv = GST_VIDEO_FRAME_PLANE_DATA(frame, 1);
  self->frame.y_stride = GST_VIDEO_FRAME_PLANE_STRIDE(frame, 0);
  self->frame.uv_stride = GST_VIDEO_FRAME_PLANE_STRIDE(frame, 1);

  t[0] = g_get_monotonic_time();
  if (identity_grid) {
    nntm_grid_identity(identity);
    t[1] = t[0];
  } else {
    void *data;
    sweep(self, luma_rows);
    nntm_luma_finish(self->tables, self->narrow, self->net_input);
    t[1] = g_get_monotonic_time();
    if (ov_infer_request_infer(self->request) != OK || ov_infer_request_get_output_tensor(self->request, &output) != OK ||
        ov_tensor_data(output, &data) != OK) {
      GST_ELEMENT_ERROR(self, LIBRARY, FAILED, ("tone-mapping network failed"), (NULL));
      return GST_FLOW_ERROR;
    }
    fresh = data;
  }
  nntm_grid_filter(self->grid, fresh, self->first);
  if (output) ov_tensor_free(output);
  self->first = FALSE;
  t[2] = g_get_monotonic_time();
  sweep(self, apply_rows);
  t[3] = g_get_monotonic_time();

  self->frames++;
  for (int i = 0; i < 3; i++) self->usec[i] += t[i + 1] - t[i];
  GST_LOG_OBJECT(self, "luma %" G_GINT64_FORMAT " network %" G_GINT64_FORMAT " apply %" G_GINT64_FORMAT " us",
                 t[1] - t[0], t[2] - t[1], t[3] - t[2]);
  return GST_FLOW_OK;
}

static gboolean gst_nntm_set_info(GstVideoFilter *filter, GstCaps *in, GstVideoInfo *in_info, GstCaps *out,
                                  GstVideoInfo *out_info) {
  GST_NNTM(filter)->stale = TRUE;
  return TRUE;
}

static void gst_nntm_set_property(GObject *object, guint id, const GValue *value, GParamSpec *pspec) {
  GstNntm *self = GST_NNTM(object);
  GST_OBJECT_LOCK(self);
  switch (id) {
    case PROP_RANGE: self->range = g_value_get_enum(value); break;
    case PROP_STRENGTH: self->strength = g_value_get_float(value); break;
    case PROP_RADIAL: self->radial = g_value_get_float(value); break;
    case PROP_BYPASS: self->bypass = g_value_get_boolean(value); break;
    case PROP_THREADS: self->threads = g_value_get_uint(value); break;
    case PROP_IDENTITY_GRID: self->identity_grid = g_value_get_boolean(value); break;
    case PROP_DATA_DIR: g_free(self->data_dir); self->data_dir = g_value_dup_string(value); break;
    default: G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, pspec);
  }
  self->stale = TRUE;
  GST_OBJECT_UNLOCK(self);
  if (id == PROP_BYPASS) gst_base_transform_set_passthrough(GST_BASE_TRANSFORM(self), self->bypass);
}

static void gst_nntm_get_property(GObject *object, guint id, GValue *value, GParamSpec *pspec) {
  GstNntm *self = GST_NNTM(object);
  switch (id) {
    case PROP_RANGE: g_value_set_enum(value, self->range); break;
    case PROP_STRENGTH: g_value_set_float(value, self->strength); break;
    case PROP_RADIAL: g_value_set_float(value, self->radial); break;
    case PROP_BYPASS: g_value_set_boolean(value, self->bypass); break;
    case PROP_THREADS: g_value_set_uint(value, self->threads); break;
    case PROP_IDENTITY_GRID: g_value_set_boolean(value, self->identity_grid); break;
    case PROP_DATA_DIR: g_value_set_string(value, self->data_dir); break;
    default: G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, pspec);
  }
}

static void gst_nntm_finalize(GObject *object) {
  g_free(GST_NNTM(object)->data_dir);
  G_OBJECT_CLASS(gst_nntm_parent_class)->finalize(object);
}

static void gst_nntm_class_init(GstNntmClass *klass) {
  GObjectClass *object = G_OBJECT_CLASS(klass);
  GstElementClass *element = GST_ELEMENT_CLASS(klass);
  GstBaseTransformClass *trans = GST_BASE_TRANSFORM_CLASS(klass);
  GstVideoFilterClass *filter = GST_VIDEO_FILTER_CLASS(klass);
  const GParamFlags flags = G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS;
  g_autofree gchar *raw = g_strdup_printf(NNTM_CAPS, NNTM_STEP, NNTM_MAX_SIZE, NNTM_STEP, NNTM_MAX_SIZE);
  GstCaps *caps = gst_caps_from_string(raw);

  object->set_property = gst_nntm_set_property;
  object->get_property = gst_nntm_get_property;
  object->finalize = gst_nntm_finalize;
  g_object_class_install_property(object, PROP_RANGE,
      g_param_spec_enum("range", "Range", "Quantisation range of the NV12 stream, in and out", range_type(),
                        RANGE_LIMITED, flags));
  g_object_class_install_property(object, PROP_STRENGTH,
      g_param_spec_float("strength", "Strength",
                         "Weight of the tone-mapped luma in the image centre (Samsung: 500/1023 at sensor gain 2 and above, 350/1023 at gain 1)",
                         0, 1, nntm_samsung_params.strength, flags));
  g_object_class_install_property(object, PROP_RADIAL,
      g_param_spec_float("radial", "Radial",
                         "How far the weight follows lens shading towards the corners (Samsung: 540/1023 at sensor gain 2 to 8, 500/1023 from 16)",
                         0, 1, nntm_samsung_params.radial, flags));
  g_object_class_install_property(object, PROP_BYPASS,
      g_param_spec_boolean("bypass", "Bypass", "Pass frames through untouched", FALSE, flags));
  g_object_class_install_property(object, PROP_THREADS,
      g_param_spec_uint("threads", "Threads", "Threads sharing the per-pixel work, read when the element starts", 1, 64,
                        4, flags));
  g_object_class_install_property(object, PROP_IDENTITY_GRID,
      g_param_spec_boolean("identity-grid", "Identity grid",
                           "Test hook: skip the network and use a grid that maps luma to itself", FALSE, flags));
  g_object_class_install_property(object, PROP_DATA_DIR,
      g_param_spec_string("data-dir", "Data directory", "Directory holding nntm.xml, nntm.bin and shading.f32",
                          NNTM_DATA_DIR, flags));

  gst_element_class_set_static_metadata(element, "Neural tone mapping", "Filter/Effect/Video",
                                        "Local tone mapping of the Galaxy Book6 camera as its Windows driver does it",
                                        "galaxybook6-camera");
  gst_element_class_add_pad_template(element, gst_pad_template_new("sink", GST_PAD_SINK, GST_PAD_ALWAYS, caps));
  gst_element_class_add_pad_template(element, gst_pad_template_new("src", GST_PAD_SRC, GST_PAD_ALWAYS, caps));
  gst_caps_unref(caps);

  trans->start = gst_nntm_start;
  trans->stop = gst_nntm_stop;
  filter->set_info = gst_nntm_set_info;
  filter->transform_frame_ip = gst_nntm_transform_frame_ip;
}

static void gst_nntm_init(GstNntm *self) {
  self->params = nntm_samsung_params;
  self->range = RANGE_LIMITED;
  self->strength = self->params.strength;
  self->radial = self->params.radial;
  self->threads = 4;
  self->data_dir = g_strdup(NNTM_DATA_DIR);
}

static gboolean plugin_init(GstPlugin *plugin) {
  GST_DEBUG_CATEGORY_INIT(nntm_debug, "nntm", 0, "neural tone mapping");
  return gst_element_register(plugin, "nntm", GST_RANK_NONE, GST_TYPE_NNTM);
}

GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, nntm, "Neural tone mapping for the Galaxy Book6 camera",
                  plugin_init, "1.0", GST_LICENSE_UNKNOWN, "galaxybook6-camera", "local")
