#include "CShims.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/processor_info.h>
#include <mach/vm_statistics.h>
#include <math.h>
#include <net/if.h>
#include <net/if_var.h>
#include <ifaddrs.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <sys/syslimits.h>
#include <sys/types.h>
#include <sys/unistd.h>

static int mm_debug_enabled(void) {
    return getenv("MM_DEBUG") != NULL;
}

int mm_cpu_read(mm_cpu_ticks *out, int max_cores) {
    natural_t count = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t info_count = 0;

    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                            &count, &info, &info_count) != KERN_SUCCESS) {
        return 0;
    }

    int total = (int)count;
    int n = total < max_cores ? total : max_cores;
    processor_cpu_load_info_t loads = (processor_cpu_load_info_t)info;

    mm_cpu_ticks agg = {0, 0, 0, 0};
    for (int i = 0; i < n; i++) {
        mm_cpu_ticks t;
        t.user = loads[i].cpu_ticks[CPU_STATE_USER];
        t.system = loads[i].cpu_ticks[CPU_STATE_SYSTEM];
        t.idle = loads[i].cpu_ticks[CPU_STATE_IDLE];
        t.nice = loads[i].cpu_ticks[CPU_STATE_NICE];
        out[i + 1] = t;
        agg.user += t.user;
        agg.system += t.system;
        agg.idle += t.idle;
        agg.nice += t.nice;
    }
    out[0] = agg;

    vm_deallocate(mach_task_self(), (vm_address_t)info,
                  (vm_size_t)(info_count * sizeof(integer_t)));
    return n;
}

int mm_mem_read(mm_mem_stats *out) {
    memset(out, 0, sizeof(*out));

    uint64_t total = 0;
    size_t len = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &len, NULL, 0) != 0) {
        return 0;
    }

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          (host_info64_t)&vm, &count) != KERN_SUCCESS) {
        return 0;
    }

    uint64_t page = (uint64_t)vm_kernel_page_size;
    uint64_t active = (uint64_t)vm.active_count * page;
    uint64_t inactive = (uint64_t)vm.inactive_count * page;
    uint64_t wired = (uint64_t)vm.wire_count * page;
    uint64_t compressed = (uint64_t)vm.compressor_page_count * page;
    uint64_t speculative = (uint64_t)vm.speculative_count * page;
    uint64_t free_pages = (uint64_t)vm.free_count * page;

    out->total = total;
    out->wired = wired;
    out->compressed = compressed;
    out->cached = inactive + speculative;
    out->free_bytes = free_pages;
    uint64_t used = active + wired + compressed;
    out->used = used > total ? total : used;

    struct xsw_usage swap;
    memset(&swap, 0, sizeof(swap));
    size_t swap_len = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &swap_len, NULL, 0) == 0) {
        out->swap_used = swap.xsu_used;
        out->swap_total = swap.xsu_total;
    }

    int level = 0;
    size_t level_len = sizeof(level);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &level_len,
                     NULL, 0) != 0) {
        level = 0;
    }
    out->pressure = level;
    return 1;
}

static uint64_t dict_u64(CFDictionaryRef d, const char *key) {
    CFStringRef k = CFStringCreateWithCString(kCFAllocatorDefault, key,
                                              kCFStringEncodingUTF8);
    if (!k) return 0;
    CFTypeRef v = CFDictionaryGetValue(d, k);
    uint64_t result = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) {
        int64_t n = 0;
        if (CFNumberGetValue((CFNumberRef)v, kCFNumberSInt64Type, &n)) {
            result = (uint64_t)(n > 0 ? n : 0);
        }
    }
    CFRelease(k);
    return result;
}

int mm_gpu_read(mm_gpu_stats *out) {
    memset(out, 0, sizeof(*out));

    static io_service_t service = 0;
    if (service == 0) {
        io_iterator_t iter = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                         IOServiceMatching("IOAccelerator"),
                                         &iter) != KERN_SUCCESS) {
            return 0;
        }
        service = IOIteratorNext(iter);
        IOObjectRelease(iter);
        if (service == 0) return 0;
    }

    CFTypeRef perf = IORegistryEntryCreateCFProperty(
        service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
    if (!perf || CFGetTypeID(perf) != CFDictionaryGetTypeID()) {
        if (perf) CFRelease(perf);
        return 0;
    }

    CFDictionaryRef d = (CFDictionaryRef)perf;
    out->device = (double)dict_u64(d, "Device Utilization %");
    out->renderer = (double)dict_u64(d, "Renderer Utilization %");
    out->in_use_sys_mem = dict_u64(d, "In use system memory");
    out->valid = 1;
    CFRelease(perf);
    return 1;
}

int mm_net_read(mm_if_stats *out, int max) {
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) {
        return 0;
    }

    int n = 0;
    for (struct ifaddrs *ifa = list; ifa && n < max; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK) continue;
        if (!(ifa->ifa_flags & IFF_UP) || (ifa->ifa_flags & IFF_LOOPBACK)) continue;
        if (strncmp(ifa->ifa_name, "en", 2) != 0) continue;
        struct if_data *data = (struct if_data *)ifa->ifa_data;
        if (!data) continue;

        mm_if_stats *s = &out[n++];
        memset(s, 0, sizeof(*s));
        strncpy(s->name, ifa->ifa_name, sizeof(s->name) - 1);
        s->rx = data->ifi_ibytes;
        s->tx = data->ifi_obytes;
    }

    freeifaddrs(list);
    return n;
}

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} mm_smc_vers;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_limit;
    uint32_t gpu_limit;
    uint32_t mem_limit;
} mm_smc_plimit;

typedef struct {
    uint32_t data_size;
    uint32_t data_type;
    char attributes;
} mm_smc_key_info;

typedef struct {
    uint32_t key;
    mm_smc_vers vers;
    mm_smc_plimit plimit;
    mm_smc_key_info key_info;
    char result;
    char status;
    char data8;
    uint32_t data32;
    uint8_t bytes[32];
} mm_smc_key_data;

#define MM_SMC_READ_BYTES 5
#define MM_SMC_READ_INDEX 8
#define MM_SMC_READ_KEYINFO 9
#define MM_SMC_KERNEL_INDEX 2
#define MM_SMC_CMD_READ_KEYINFO 9
#define MM_SMC_MAX_KEYS 64

static io_connect_t g_smc = 0;
static int g_smc_ready = 0;
static int g_discovered = 0;
static uint32_t g_keys[MM_SMC_MAX_KEYS];
static char g_key_names[MM_SMC_MAX_KEYS][5];
static int g_key_count = 0;

static uint32_t mm_smc_fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static int mm_smc_open(void) {
    if (g_smc_ready) return g_smc != 0;
    g_smc_ready = 1;
    io_service_t device = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (device == 0) {
        if (mm_debug_enabled()) fprintf(stderr, "smc: no AppleSMC service\n");
        return 0;
    }
    kern_return_t kr = IOServiceOpen(device, mach_task_self(), 0, &g_smc);
    IOObjectRelease(device);
    if (kr != KERN_SUCCESS) {
        if (mm_debug_enabled()) fprintf(stderr, "smc: open failed 0x%x\n", kr);
        g_smc = 0;
        return 0;
    }
    if (mm_debug_enabled()) fprintf(stderr, "smc: opened struct=%zu\n", sizeof(mm_smc_key_data));
    return 1;
}

static kern_return_t mm_smc_call(int index, mm_smc_key_data *in,
                                 mm_smc_key_data *out) {
    size_t in_size = sizeof(*in);
    size_t out_size = sizeof(*out);
    return IOConnectCallStructMethod(g_smc, index, in, in_size, out, &out_size);
}

static int mm_smc_read(uint32_t key, mm_smc_key_data *value) {
    mm_smc_key_data in;
    memset(&in, 0, sizeof(in));
    in.key = key;
    in.data8 = MM_SMC_CMD_READ_KEYINFO;

    mm_smc_key_data info;
    memset(&info, 0, sizeof(info));
    if (mm_smc_call(MM_SMC_KERNEL_INDEX, &in, &info) != KERN_SUCCESS) return 0;

    in.key_info = info.key_info;
    in.data8 = MM_SMC_READ_BYTES;

    mm_smc_key_data bytes;
    memset(&bytes, 0, sizeof(bytes));
    if (mm_smc_call(MM_SMC_KERNEL_INDEX, &in, &bytes) != KERN_SUCCESS) return 0;

    *value = bytes;
    value->key_info = info.key_info;
    return 1;
}

static int mm_smc_decode(mm_smc_key_data *value, double *out) {
    uint32_t type = value->key_info.data_type;
    uint32_t size = value->key_info.data_size;
    if (size == 0 || size > 32) return 0;

    if (type == mm_smc_fourcc("sp78") && size == 2) {
        int16_t raw = (int16_t)(((uint16_t)value->bytes[0] << 8) |
                                (uint16_t)value->bytes[1]);
        *out = (double)raw / 256.0;
        return 1;
    }
    if (type == mm_smc_fourcc("flt ") && size == 4) {
        uint32_t raw = ((uint32_t)value->bytes[3] << 24) |
                       ((uint32_t)value->bytes[2] << 16) |
                       ((uint32_t)value->bytes[1] << 8) |
                       (uint32_t)value->bytes[0];
        float f;
        memcpy(&f, &raw, sizeof(f));
        *out = (double)f;
        return 1;
    }
    if (type == mm_smc_fourcc("ui16") && size == 2) {
        *out = (double)(((uint16_t)value->bytes[0] << 8) |
                        (uint16_t)value->bytes[1]);
        return 1;
    }
    return 0;
}

static void mm_smc_discover(void) {
    g_discovered = 1;
    if (!mm_smc_open()) return;

    mm_smc_key_data key_value;
    if (!mm_smc_read(mm_smc_fourcc("#KEY"), &key_value)) {
        if (mm_debug_enabled()) fprintf(stderr, "smc: #KEY read failed\n");
        return;
    }
    if (key_value.key_info.data_size != 4) {
        if (mm_debug_enabled()) fprintf(stderr, "smc: #KEY size=%u type=%08x\n",
                                        key_value.key_info.data_size,
                                        key_value.key_info.data_type);
        return;
    }
    uint32_t count = ((uint32_t)key_value.bytes[0] << 24) |
                     ((uint32_t)key_value.bytes[1] << 16) |
                     ((uint32_t)key_value.bytes[2] << 8) |
                     (uint32_t)key_value.bytes[3];
    if (mm_debug_enabled()) fprintf(stderr, "smc: key count=%u\n", count);

    int t_seen = 0;
    for (uint32_t i = 0; i < count && g_key_count < MM_SMC_MAX_KEYS; i++) {
        mm_smc_key_data in;
        memset(&in, 0, sizeof(in));
        in.data8 = MM_SMC_READ_INDEX;
        in.data32 = i;

        mm_smc_key_data indexed;
        memset(&indexed, 0, sizeof(indexed));
        if (mm_smc_call(MM_SMC_KERNEL_INDEX, &in, &indexed) != KERN_SUCCESS) {
            continue;
        }
        uint32_t key = indexed.key;
        char name[5];
        name[0] = (char)((key >> 24) & 0xff);
        name[1] = (char)((key >> 16) & 0xff);
        name[2] = (char)((key >> 8) & 0xff);
        name[3] = (char)(key & 0xff);
        name[4] = 0;

        if (name[0] != 'T') continue;
        if (name[1] != 'p' && name[1] != 'g' && name[1] != 'a') continue;
        t_seen++;

        mm_smc_key_data info;
        if (!mm_smc_read(key, &info)) continue;
        uint32_t type = info.key_info.data_type;
        if (mm_debug_enabled()) {
            fprintf(stderr, "smc: candidate %s type=%08x size=%u\n", name, type,
                    info.key_info.data_size);
        }
        if (type != mm_smc_fourcc("sp78") && type != mm_smc_fourcc("flt ") &&
            type != mm_smc_fourcc("ui16")) {
            continue;
        }
        g_keys[g_key_count] = key;
        memcpy(g_key_names[g_key_count], name, 5);
        g_key_count++;
    }
    if (mm_debug_enabled()) fprintf(stderr, "smc: T candidates=%d kept=%d\n",
                                    t_seen, g_key_count);
}

int mm_temp_supported(void) {
    return mm_smc_open() ? 1 : 0;
}

int mm_temp_read(mm_temp_sensor *out, int max) {
    if (!g_discovered) mm_smc_discover();
    if (g_key_count == 0) return 0;

    int n = 0;
    for (int i = 0; i < g_key_count && n < max; i++) {
        mm_smc_key_data value;
        if (!mm_smc_read(g_keys[i], &value)) continue;
        double celsius = 0;
        if (!mm_smc_decode(&value, &celsius)) continue;
        if (mm_debug_enabled()) {
            fprintf(stderr, "smc: %s type=%08x raw=%02x%02x%02x%02x val=%.3f\n",
                    g_key_names[i], value.key_info.data_type, value.bytes[0],
                    value.bytes[1], value.bytes[2], value.bytes[3], celsius);
        }
        if (!(celsius > 1.0 && celsius < 130.0)) continue;

        memset(&out[n], 0, sizeof(out[n]));
        strncpy(out[n].name, g_key_names[i], sizeof(out[n].name) - 1);
        out[n].celsius = celsius;
        n++;
    }
    return n;
}

void mm_load_avg(double *a, double *b, double *c) {
    double load[3] = {0, 0, 0};
    if (getloadavg(load, 3) != 3) {
        *a = *b = *c = 0;
        return;
    }
    *a = load[0];
    *b = load[1];
    *c = load[2];
}

static void mm_session_copy_argc_args(const char *buffer, size_t size,
                                      char *exec_path, size_t exec_size,
                                      char *argv, size_t argv_size) {
    exec_path[0] = 0;
    argv[0] = 0;
    if (size < 5) return;

    int32_t argc = 0;
    memcpy(&argc, buffer, sizeof(argc));
    if (argc <= 0 || argc > 4096) return;

    const char *p = buffer + sizeof(int32_t);
    const char *end = buffer + size;

    size_t len = strnlen(p, (size_t)(end - p)) + 1;
    if (p + len > end) return;
    strncpy(exec_path, p, exec_size - 1);
    exec_path[exec_size - 1] = 0;
    p += len;

    while (p < end && *p == 0) p++;

    size_t used = 0;
    int consumed = 0;
    while (p < end && consumed < argc) {
        size_t s = strnlen(p, (size_t)(end - p));
        if (p + s + 1 > end) break;
        if (s == 0) break;
        if (consumed > 0 && used + 1 < argv_size) {
            argv[used++] = ' ';
        }
        if (used + s >= argv_size) break;
        memcpy(argv + used, p, s);
        used += s;
        argv[used] = 0;
        p += s + 1;
        consumed++;
    }
}

int mm_session_procs(mm_proc_session *out, int max) {
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return 0;

    size_t pids_size = (size_t)(count + 64) * sizeof(pid_t);
    pid_t *pids = malloc(pids_size);
    if (!pids) return 0;

    int total = proc_listallpids(pids, (int)pids_size);
    if (total <= 0) {
        free(pids);
        return 0;
    }

    size_t args_size = 65536;
    char *args = malloc(args_size);
    if (!args) {
        free(pids);
        return 0;
    }

    int n = 0;
    for (int i = 0; i < total && n < max; i++) {
        char path[1024];
        if (proc_pidpath(pids[i], path, sizeof(path)) <= 0) continue;
        const char *kind_name = NULL;
        if (strstr(path, "/claude") != NULL || strstr(path, "/.claude") != NULL) {
            kind_name = "claude";
        } else if (strstr(path, "/opencode") != NULL) {
            kind_name = "opencode";
        } else {
            char name[64];
            if (proc_name(pids[i], name, sizeof(name)) <= 0) continue;
            if (strstr(name, "claude") == NULL &&
                strstr(name, "opencode") == NULL) {
                continue;
            }
            kind_name = strstr(name, "claude") != NULL ? "claude" : "opencode";
        }

        mm_proc_session *entry = &out[n];
        memset(entry, 0, sizeof(*entry));
        entry->pid = pids[i];
        strncpy(entry->name, kind_name, sizeof(entry->name) - 1);
        strncpy(entry->path, path, sizeof(entry->path) - 1);

        int mib[3] = {CTL_KERN, KERN_PROCARGS2, pids[i]};
        size_t wanted = args_size;
        if (sysctl(mib, 3, args, &wanted, NULL, 0) == 0) {
            mm_session_copy_argc_args(args, wanted, entry->path,
                                      sizeof(entry->path), entry->argv,
                                      sizeof(entry->argv));
        }

        struct proc_vnodepathinfo vpi;
        int r = proc_pidinfo(pids[i], PROC_PIDVNODEPATHINFO, 0, &vpi,
                             (int)sizeof(vpi));
        if (r > 0) {
            strncpy(entry->cwd, vpi.pvi_cdir.vip_path, sizeof(entry->cwd) - 1);
        }

        struct kinfo_proc kp;
        memset(&kp, 0, sizeof(kp));
        int mib2[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pids[i]};
        size_t kp_size = sizeof(kp);
        if (sysctl(mib2, 4, &kp, &kp_size, NULL, 0) == 0 && kp_size > 0) {
            dev_t tdev = kp.kp_eproc.e_tdev;
            if (tdev != NODEV && tdev != 0) {
                char devbuf[64];
                if (devname_r(tdev, S_IFCHR, devbuf, (int)sizeof(devbuf)) != NULL) {
                    strncpy(entry->tty, devbuf, sizeof(entry->tty) - 1);
                    entry->tty_valid = 1;
                }
            }
        }

        n++;
    }

    free(args);
    free(pids);
    return n;
}

#include <dlfcn.h>

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

typedef int (*sqlite3_open_v2_fn)(const char *, sqlite3 **, int, const char *);
typedef int (*sqlite3_prepare_v2_fn)(sqlite3 *, const char *, int,
                                     sqlite3_stmt **, const char **);
typedef int (*sqlite3_bind_text_fn)(sqlite3_stmt *, int, const char *, int,
                                    void (*)(void *));
typedef int (*sqlite3_step_fn)(sqlite3_stmt *);
typedef const unsigned char *(*sqlite3_column_text_fn)(sqlite3_stmt *, int);
typedef int (*sqlite3_finalize_fn)(sqlite3_stmt *);
typedef int (*sqlite3_close_fn)(sqlite3 *);
typedef const char *(*sqlite3_errmsg_fn)(sqlite3 *);

static void *mm_sqlite_lib = NULL;
static sqlite3 *mm_sqlite_handle = NULL;
static char mm_sqlite_path[1024] = {0};

#define MM_SQLITE_OPEN_READONLY 0x00000001
#define MM_SQLITE_OPEN_URI 0x00000040
#define MM_SQLITE_ROW 100
#define MM_SQLITE_OK 0

static int mm_sqlite_lookup(void) {
    if (mm_sqlite_lib) return 1;
    mm_sqlite_lib = dlopen("libsqlite3.dylib", RTLD_LAZY);
    if (!mm_sqlite_lib) return 0;
    if (!dlsym(mm_sqlite_lib, "sqlite3_open_v2") ||
        !dlsym(mm_sqlite_lib, "sqlite3_prepare_v2") ||
        !dlsym(mm_sqlite_lib, "sqlite3_bind_text") ||
        !dlsym(mm_sqlite_lib, "sqlite3_step") ||
        !dlsym(mm_sqlite_lib, "sqlite3_column_text") ||
        !dlsym(mm_sqlite_lib, "sqlite3_finalize") ||
        !dlsym(mm_sqlite_lib, "sqlite3_close") ||
        !dlsym(mm_sqlite_lib, "sqlite3_errmsg")) {
        dlclose(mm_sqlite_lib);
        mm_sqlite_lib = NULL;
        return 0;
    }
    return 1;
}

static void mm_sqlite_seterr(sqlite3 *db, char *errbuf, int errsize) {
    if (!errbuf || errsize <= 0) return;
    errbuf[0] = 0;
    if (!mm_sqlite_lib || !db) return;
    sqlite3_errmsg_fn errmsg = (sqlite3_errmsg_fn)dlsym(mm_sqlite_lib, "sqlite3_errmsg");
    if (!errmsg) return;
    const char *msg = errmsg(db);
    if (msg) {
        strncpy(errbuf, msg, (size_t)errsize - 1);
        errbuf[errsize - 1] = 0;
    }
}

static void mm_sqlite_copy_col(sqlite3_stmt *stmt, int col, char *dst, size_t size,
                               sqlite3_column_text_fn coltext) {
    const unsigned char *text = coltext(stmt, col);
    if (!text) {
        dst[0] = 0;
        return;
    }
    strncpy(dst, (const char *)text, size - 1);
    dst[size - 1] = 0;
}

int mm_db_sessions(const char *path, const char *const *ids, int nkeys,
                   mm_db_session *out, int max, char *errbuf, int errsize) {
    if (errbuf && errsize > 0) errbuf[0] = 0;
    if (!path || nkeys > max || nkeys <= 0) return -1;
    if (!mm_sqlite_lookup()) {
        if (errbuf && errsize > 0) {
            strncpy(errbuf, "sqlite unavailable", (size_t)errsize - 1);
            errbuf[errsize - 1] = 0;
        }
        return -1;
    }

    if (mm_sqlite_handle && strcmp(path, mm_sqlite_path) != 0) {
        sqlite3_close_fn closefn = (sqlite3_close_fn)dlsym(mm_sqlite_lib, "sqlite3_close");
        if (closefn) closefn(mm_sqlite_handle);
        mm_sqlite_handle = NULL;
    }

    if (!mm_sqlite_handle) {
        char uri[1152];
        snprintf(uri, sizeof(uri), "file:%s?mode=ro", path);
        sqlite3_open_v2_fn openfn = (sqlite3_open_v2_fn)dlsym(mm_sqlite_lib, "sqlite3_open_v2");
        if (!openfn) return -1;
        int rc = openfn(uri, &mm_sqlite_handle,
                        MM_SQLITE_OPEN_READONLY | MM_SQLITE_OPEN_URI, NULL);
        if (rc != MM_SQLITE_OK) {
            mm_sqlite_seterr(mm_sqlite_handle, errbuf, errsize);
            if (mm_sqlite_handle) {
                sqlite3_close_fn closefn = (sqlite3_close_fn)dlsym(mm_sqlite_lib, "sqlite3_close");
                if (closefn) closefn(mm_sqlite_handle);
                mm_sqlite_handle = NULL;
            }
            return -1;
        }
        strncpy(mm_sqlite_path, path, sizeof(mm_sqlite_path) - 1);
    }

    const char *sql = "SELECT directory, title FROM session WHERE id = ?";
    sqlite3_prepare_v2_fn prepare = (sqlite3_prepare_v2_fn)dlsym(mm_sqlite_lib, "sqlite3_prepare_v2");
    sqlite3_bind_text_fn bindtext = (sqlite3_bind_text_fn)dlsym(mm_sqlite_lib, "sqlite3_bind_text");
    sqlite3_step_fn stepfn = (sqlite3_step_fn)dlsym(mm_sqlite_lib, "sqlite3_step");
    sqlite3_column_text_fn coltext = (sqlite3_column_text_fn)dlsym(mm_sqlite_lib, "sqlite3_column_text");
    sqlite3_finalize_fn finalize = (sqlite3_finalize_fn)dlsym(mm_sqlite_lib, "sqlite3_finalize");
    if (!prepare || !bindtext || !stepfn || !coltext || !finalize) return -1;

    sqlite3_stmt *stmt = NULL;
    if (prepare(mm_sqlite_handle, sql, -1, &stmt, NULL) != MM_SQLITE_OK) {
        mm_sqlite_seterr(mm_sqlite_handle, errbuf, errsize);
        return -1;
    }

    int n = 0;
    for (int i = 0; i < nkeys; i++) {
        mm_db_session *entry = &out[i];
        memset(entry, 0, sizeof(*entry));
        if (!ids[i]) continue;
        strncpy(entry->id, ids[i], sizeof(entry->id) - 1);
        if (ids[i][0] == 0) continue;

        bindtext(stmt, 1, ids[i], -1, NULL);
        int rc = stepfn(stmt);
        if (rc == MM_SQLITE_ROW) {
            mm_sqlite_copy_col(stmt, 0, entry->dir, sizeof(entry->dir), coltext);
            mm_sqlite_copy_col(stmt, 1, entry->title, sizeof(entry->title), coltext);
            entry->found = 1;
        }
        n++;
    }
    bindtext(stmt, 1, "", -1, NULL);
    finalize(stmt);
    return n;
}

void mm_db_close(void) {
    if (mm_sqlite_lib && mm_sqlite_handle) {
        sqlite3_close_fn closefn = (sqlite3_close_fn)dlsym(mm_sqlite_lib, "sqlite3_close");
        if (closefn) closefn(mm_sqlite_handle);
    }
    mm_sqlite_handle = NULL;
    if (mm_sqlite_lib) {
        dlclose(mm_sqlite_lib);
        mm_sqlite_lib = NULL;
    }
}
