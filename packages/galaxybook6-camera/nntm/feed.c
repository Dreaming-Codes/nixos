/* usage: feed <width> <height> <in.nv12> <out.nv12> <records|-> [nntm property=value...]
 * Runs every frame of in.nv12 through nntm. With a records file (nntm_1_0 PAL records back to back), frame i
 * carries record i the way the camera source attaches it. */
#include <gst/app/gstappsink.h>
#include <gst/app/gstappsrc.h>
#include <gst/gst.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NNTM_PARAMS_META "GstNntmParamsMeta"

static void attach(GstBuffer *buffer, const gchar *record, gsize size) {
  GstCustomMeta *meta = gst_buffer_add_custom_meta(buffer, NNTM_PARAMS_META);
  GBytes *bytes = g_bytes_new(record, size);
  gst_structure_set(gst_custom_meta_get_structure(meta), "record", G_TYPE_BYTES, bytes, NULL);
  g_bytes_unref(bytes);
}

int main(int argc, char **argv) {
  gst_init(&argc, &argv);
  if (argc < 6) {
    fprintf(stderr, "usage: feed <width> <height> <in.nv12> <out.nv12> <records|-> [nntm property=value...]\n");
    return 2;
  }
  int width = atoi(argv[1]), height = atoi(argv[2]);
  gsize frame = (gsize)width * height * 3 / 2, len, records_len = 0;
  gchar *frames, *records = NULL;
  if (!g_file_get_contents(argv[3], &frames, &len, NULL) ||
      (strcmp(argv[5], "-") != 0 && !g_file_get_contents(argv[5], &records, &records_len, NULL))) {
    fprintf(stderr, "cannot read the input\n");
    return 1;
  }
  const gchar *tags[] = {NULL};
  gst_meta_register_custom(NNTM_PARAMS_META, tags, NULL, NULL, NULL);

  GString *desc = g_string_new(NULL);
  g_string_printf(desc, "appsrc name=src format=time caps=video/x-raw,format=NV12,width=%d,height=%d,framerate=30/1 ! nntm",
                  width, height);
  for (int i = 6; i < argc; i++) g_string_append_printf(desc, " %s", argv[i]);
  g_string_append(desc, " ! appsink name=sink sync=false");
  GError *error = NULL;
  GstElement *pipeline = gst_parse_launch(desc->str, &error);
  if (!pipeline) {
    fprintf(stderr, "%s\n", error->message);
    return 1;
  }
  GstElement *src = gst_bin_get_by_name(GST_BIN(pipeline), "src"), *sink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
  FILE *out = fopen(argv[4], "wb");
  int status = out && gst_element_set_state(pipeline, GST_STATE_PLAYING) != GST_STATE_CHANGE_FAILURE ? 0 : 1;

  gsize at = 0;
  for (gsize i = 0; status == 0 && (i + 1) * frame <= len; i++) {
    GstBuffer *buffer = gst_buffer_new_memdup(frames + i * frame, frame);
    GST_BUFFER_PTS(buffer) = gst_util_uint64_scale(i, GST_SECOND, 30);
    if (records && at + 8 <= records_len) {
      gint32 size;
      memcpy(&size, records + at + 4, sizeof size);
      attach(buffer, records + at, MIN((gsize)size, records_len - at));
      at += size;
    }
    GstSample *sample = NULL;
    if (gst_app_src_push_buffer(GST_APP_SRC(src), buffer) != GST_FLOW_OK ||
        !(sample = gst_app_sink_try_pull_sample(GST_APP_SINK(sink), 60 * GST_SECOND))) {
      fprintf(stderr, "frame %zu did not come out\n", (size_t)i);
      status = 1;
      break;
    }
    GstMapInfo map;
    gst_buffer_map(gst_sample_get_buffer(sample), &map, GST_MAP_READ);
    if (fwrite(map.data, 1, map.size, out) != map.size) status = 1;
    gst_buffer_unmap(gst_sample_get_buffer(sample), &map);
    gst_sample_unref(sample);
  }
  gst_app_src_end_of_stream(GST_APP_SRC(src));
  gst_element_set_state(pipeline, GST_STATE_NULL);
  if (out && fclose(out) != 0) status = 1;
  gst_object_unref(src);
  gst_object_unref(sink);
  gst_object_unref(pipeline);
  return status;
}
