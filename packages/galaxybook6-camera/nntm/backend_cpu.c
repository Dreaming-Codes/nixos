#include <glib.h>

#include "backend.h"

enum { SWEEP_ROWS = 16 };

typedef struct Cpu Cpu;

typedef struct {
  Cpu *cpu;
  void (*rows)(Cpu *cpu, int row0, int row1);
  gint next, running;
  GMutex lock;
  GCond done;
} Sweep;

struct Cpu {
  NntmBackend base;
  guint threads;
  GThreadPool *pool;
  Nntm *tables;
  NntmFrame *frame;
  const float *grid;
  float *narrow;
};

static void sweep_work(gpointer data, gpointer unused) {
  Sweep *s = data;
  int height = s->cpu->frame->height;
  for (int row; (row = g_atomic_int_add(&s->next, SWEEP_ROWS)) < height;)
    s->rows(s->cpu, row, MIN(row + SWEEP_ROWS, height));
  g_mutex_lock(&s->lock);
  if (--s->running == 0) g_cond_signal(&s->done);
  g_mutex_unlock(&s->lock);
}

static void sweep(Cpu *cpu, void (*rows)(Cpu *, int, int)) {
  Sweep s = {.cpu = cpu, .rows = rows, .running = cpu->threads};
  g_mutex_init(&s.lock);
  g_cond_init(&s.done);
  for (guint i = 1; i < cpu->threads; i++) g_thread_pool_push(cpu->pool, &s, NULL);
  sweep_work(&s, NULL);
  g_mutex_lock(&s.lock);
  while (s.running) g_cond_wait(&s.done, &s.lock);
  g_mutex_unlock(&s.lock);
  g_mutex_clear(&s.lock);
  g_cond_clear(&s.done);
}

static void luma_rows(Cpu *cpu, int row0, int row1) { nntm_luma_rows(cpu->tables, cpu->frame, cpu->narrow, row0, row1); }

static void apply_rows(Cpu *cpu, int row0, int row1) { nntm_apply_rows(cpu->tables, cpu->grid, cpu->frame, row0, row1); }

static bool cpu_configure(NntmBackend *b, int width, int height) {
  Cpu *cpu = (Cpu *)b;
  nntm_free(cpu->tables);
  cpu->tables = nntm_new(width, height);
  cpu->narrow = g_realloc(cpu->narrow, (gsize)height * NNTM_NET_SIZE * sizeof(gfloat));
  return true;
}

static bool cpu_set_params(NntmBackend *b, const NntmParams *params) {
  nntm_set_params(((Cpu *)b)->tables, params);
  return true;
}

static bool cpu_prepare(NntmBackend *b, NntmFrame *f, bool persistent, uint16_t *net_input) {
  Cpu *cpu = (Cpu *)b;
  if (!net_input) return true;
  cpu->frame = f;
  sweep(cpu, luma_rows);
  nntm_luma_finish(cpu->tables, cpu->narrow, net_input);
  return true;
}

static bool cpu_apply(NntmBackend *b, const NntmGrid grid, NntmFrame *f) {
  Cpu *cpu = (Cpu *)b;
  cpu->frame = f;
  cpu->grid = grid;
  sweep(cpu, apply_rows);
  return true;
}

static void cpu_free(NntmBackend *b) {
  Cpu *cpu = (Cpu *)b;
  if (cpu->pool) g_thread_pool_free(cpu->pool, FALSE, TRUE);
  nntm_free(cpu->tables);
  g_free(cpu->narrow);
  g_free(cpu);
}

static const NntmBackendClass cpu_class = {
  .name = "cpu",
  .net_device = "CPU",
  .net_property = "INFERENCE_NUM_THREADS",
  .net_property_value = "1",
  .configure = cpu_configure,
  .set_params = cpu_set_params,
  .prepare = cpu_prepare,
  .apply = cpu_apply,
  .free = cpu_free,
};

NntmBackend *nntm_cpu_new(unsigned threads) {
  Cpu *cpu = g_new0(Cpu, 1);
  cpu->base.klass = &cpu_class;
  cpu->threads = MAX(threads, 1);
  if (cpu->threads > 1) cpu->pool = g_thread_pool_new(sweep_work, NULL, cpu->threads - 1, TRUE, NULL);
  return &cpu->base;
}
