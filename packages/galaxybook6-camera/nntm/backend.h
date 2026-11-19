#ifndef NNTM_BACKEND_H
#define NNTM_BACKEND_H

#include "nntm.h"

/* Where the pixel stages run. The element owns the network and the temporal filter; a back end turns
 * a frame into the network input and applies a filtered grid to the same frame, in place. */
typedef struct NntmBackend NntmBackend;

typedef struct {
  const char *name;
  /* OpenVINO device for the network and one compile property. */
  const char *net_device, *net_key, *net_value;
  /* Called before the first frame and after every change of frame size. */
  bool (*configure)(NntmBackend *b, int width, int height);
  /* Called before every frame's prepare. */
  bool (*set_params)(NntmBackend *b, const NntmParams *params);
  /* `persistent`: the frame's memory comes back in later frames and stays mapped until the next
   * configure or free. `net_input` is NULL when no network runs on this frame. */
  bool (*prepare)(NntmBackend *b, NntmFrame *f, bool persistent, uint16_t *net_input);
  bool (*apply)(NntmBackend *b, const NntmGrid grid, NntmFrame *f);
  void (*free)(NntmBackend *b);
} NntmBackendClass;

struct NntmBackend {
  const NntmBackendClass *klass;
};

NntmBackend *nntm_cpu_new(unsigned threads);
/* NULL and a message in `error` (free with free()) when no usable GPU runtime is found. */
NntmBackend *nntm_gpu_new(const char *data_dir, char **error);

#endif
