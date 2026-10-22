#ifndef MMSHIMS_H
#define MMSHIMS_H

#include <stdint.h>
#include <sys/types.h>

typedef struct {
    uint64_t user;
    uint64_t system;
    uint64_t idle;
    uint64_t nice;
} mm_cpu_ticks;

int mm_cpu_read(mm_cpu_ticks *out, int max_cores);

typedef struct {
    uint64_t total;
    uint64_t used;
    uint64_t wired;
    uint64_t compressed;
    uint64_t cached;
    uint64_t free_bytes;
    uint64_t swap_used;
    uint64_t swap_total;
    int pressure;
} mm_mem_stats;

int mm_mem_read(mm_mem_stats *out);

typedef struct {
    double device;
    double renderer;
    uint64_t in_use_sys_mem;
    int valid;
} mm_gpu_stats;

int mm_gpu_read(mm_gpu_stats *out);

typedef struct {
    char name[24];
    uint64_t rx;
    uint64_t tx;
} mm_if_stats;

int mm_net_read(mm_if_stats *out, int max);

typedef struct {
    char name[96];
    double celsius;
} mm_temp_sensor;

int mm_temp_read(mm_temp_sensor *out, int max);
int mm_temp_supported(void);

void mm_load_avg(double *a, double *b, double *c);

#endif

typedef struct {
    pid_t pid;
    char name[64];
    char path[1024];
    char cwd[1024];
    char argv[2048];
    char tty[64];
    int tty_valid;
} mm_proc_session;

int mm_session_procs(mm_proc_session *out, int max);

typedef struct {
    char id[64];
    char dir[1024];
    char title[512];
    int found;
} mm_db_session;

int mm_db_sessions(const char *path, const char *const *ids, int nkeys,
                   mm_db_session *out, int max, char *errbuf, int errsize);
void mm_db_close(void);
