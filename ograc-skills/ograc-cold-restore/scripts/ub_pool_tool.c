/* Copyright (c) 2026 Huawei Technologies Co., Ltd. All rights reserved.
 * Licensed under Mulan PSL v2. */
/* Offline test cleanup. Run as the database OS user. No mapping, region
 * destruction, or live-DB cleanup; the controller checks both DB identities. */
#include "cm_ubs_mem.h"
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int pool_name_valid(const char *name, const char *prefix)
{
    size_t n = strlen(prefix);
    if (!strcmp(name, prefix)) return 1; /* Legacy allocation, offline only. */
    if (strncmp(name, prefix, n) || name[n] != '_' || name[n + 1] != 'g' || strlen(name + n + 2) != 16) return 0;
    return strspn(name + n + 2, "0123456789abcdef") == 16;
}

static int sdk_initialize(void)
{
    unsigned char options[256] = {0}; /* Installed SDK's options ABI. */
    int ret = ubsmem_init_attributes((ubsmem_options_t *)options);
    if (!ret) ret = ubsmem_initialize((ubsmem_options_t *)options);
    return ret;
}

#define MAX_CLEAN_OBJECTS 300

static int is_user_gbp_name(const char *name, const char *user_prefix, const char *node)
{
    size_t n = strlen(user_prefix);
    if (strncmp(name, user_prefix, n) != 0) return 0;
    if (strstr(name, "data_buf_part_") == NULL) return 0;
    if (node == NULL) return 1;
    char tag[64];
    int len = snprintf(tag, sizeof(tag), "data_buf_part_%s", node);
    if (len < 0 || (size_t)len >= sizeof(tag)) return 0;
    const char *p = strstr(name, tag);
    if (p == NULL) return 0;
    char c = p[len];
    return c == '\0' || c == '_';
}

/* List/deallocate every GBP data-buffer allocation owned by this OS user,
 * regardless of the namespace generation (any vN generation, legacy).  Names
 * start with "<user>_"; objects of other users never match.  With NODE, only
 * allocations for that node index are touched (the SDK list is cluster-wide,
 * but remote objects cannot be deallocated from this host). */
static int clean_all_gbp(int list_only, const char *node)
{
    /* UB_POOL_USER overrides the name prefix.  Needed after a UID migration:
     * allocations created under the old numeric uid must be removed by a
     * process running as that old uid, but the passwd name is now gone/changed. */
    const char *user_name = getenv("UB_POOL_USER");
    char prefix[MAX_SHM_NAME_LENGTH + 1];
    if (user_name == NULL || user_name[0] == '\0') {
        struct passwd *user = getpwuid(getuid());
        if (user == NULL) return 2;
        user_name = user->pw_name;
    }
    int length = snprintf(prefix, sizeof(prefix), "%s_", user_name);
    if (length < 0 || (size_t)length >= sizeof(prefix)) return 2;

    int ret = sdk_initialize();
    if (ret) { fprintf(stderr, "initialize ret=%d\n", ret); return 1; }

    ubsmem_shmem_desc_t objects[MAX_CLEAN_OBJECTS] = {0};
    unsigned count = MAX_CLEAN_OBJECTS;
    ret = ubsmem_shmem_list_lookup(prefix, objects, &count);
    printf("lookup prefix=%s ret=%d count=%u\n", prefix, ret, count);
    if (ret || count > MAX_CLEAN_OBJECTS) goto fail;

    unsigned matched = 0;
    for (unsigned i = 0; i < count; i++) {
        if (memchr(objects[i].name, 0, sizeof(objects[i].name)) == NULL ||
            !is_user_gbp_name(objects[i].name, prefix, node)) continue;
        matched++;
        printf("object name=%s bytes=%llu\n", objects[i].name, (unsigned long long)objects[i].size);
        if (list_only) continue;
        int dret = ubsmem_shmem_deallocate(objects[i].name);
        printf("deallocate %s ret=%d\n", objects[i].name, dret);
    }
    if (list_only) {
        printf("gbp-list prefix=%s node=%s matched=%u\n", prefix, node == NULL ? "*" : node, matched);
        (void)ubsmem_finalize();
        return 0;
    }

    memset(objects, 0, sizeof(objects));
    count = MAX_CLEAN_OBJECTS;
    ret = ubsmem_shmem_list_lookup(prefix, objects, &count);
    unsigned remaining = 0;
    if (ret == 0) {
        for (unsigned i = 0; i < count; i++) {
            if (memchr(objects[i].name, 0, sizeof(objects[i].name)) == NULL ||
                !is_user_gbp_name(objects[i].name, prefix, node)) continue;
            remaining++;
            printf("remaining name=%s bytes=%llu\n", objects[i].name, (unsigned long long)objects[i].size);
        }
    }
    int success = ret == 0 && remaining == 0;
    if (success) printf("all-pools-empty prefix=%s node=%s\n", prefix, node == NULL ? "*" : node);
    (void)ubsmem_finalize();
    return !success;

fail:
    (void)ubsmem_finalize();
    return 1;
}

static int memory_statistics(void)
{
    if (sdk_initialize()) return 1;
    ubsmem_cluster_info_t info = {0};
    int ret = ubsmem_lookup_cluster_statistic(&info);
    printf("pool-memory-lookup ret=%d hosts=%d\n", ret, info.host_num);
    int success = ret == 0 && info.host_num > 0 && info.host_num <= MAX_HOST_NUM;
    if (success) {
        for (int i = 0; i < info.host_num; i++) {
            ubsmem_host_info_t *host = &info.host[i];
            if (host->numa_num < 0 || host->numa_num > MAX_NUMA_NUM) { success = 0; break; }
            for (int j = 0; j < host->numa_num; j++) {
                ubsmem_numa_mem_t *n = &host->numa[j];
                printf("pool-memory host=%.*s numa=%u total=%llu free=%llu borrow=%llu lend=%llu\n",
                    MAX_HOST_NAME_DESC_LENGTH, host->host_name, n->numa_id, (unsigned long long)n->mem_total,
                    (unsigned long long)n->mem_free, (unsigned long long)n->mem_borrow, (unsigned long long)n->mem_lend);
            }
        }
    }
    ret = ubsmem_finalize();
    return !success || ret != 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version")) {
        puts("ub_pool_tool generation-v1");
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "--stats")) return memory_statistics();
    if (argc == 2 && !strcmp(argv[1], "all-list")) return clean_all_gbp(1, NULL);
    if (argc == 4 && !strcmp(argv[1], "clean-all") &&
        (!strcmp(argv[2], "0") || !strcmp(argv[2], "1")) &&
        !strcmp(argv[3], "--both-databases-stopped")) return clean_all_gbp(0, argv[2]);
    if ((argc != 3 && argc != 4) || (strcmp(argv[1], "0") && strcmp(argv[1], "1")) ||
        (strcmp(argv[2], "list") && strcmp(argv[2], "release")) ||
        (!strcmp(argv[2], "release") && (argc != 4 || strcmp(argv[3], "--both-databases-stopped")))) {
        fprintf(stderr, "usage: %s NODE list | NODE release --both-databases-stopped\n"
                        "       %s clean-all NODE --both-databases-stopped | all-list\n", argv[0], argv[0]);
        return 2;
    }
    struct passwd *user = getpwuid(getuid());
    char prefix[MAX_SHM_NAME_LENGTH + 1];
    if (user == NULL) return 2;
    /* Exact-generation release path.  Keep UB_POOL_GENERATION in sync with
     * dtc_ub_object_name()'s namespace version (for example "v12"). */
    const char *generation = getenv("UB_POOL_GENERATION");
    if (generation == NULL || generation[0] == '\0') generation = "v12";
    int length = snprintf(prefix, sizeof(prefix), "%s_%s_data_buf_part_%s",
                          user->pw_name, generation, argv[1]);
    if (length < 0 || (size_t)length >= sizeof(prefix)) return 2;
    int ret = sdk_initialize();
    if (ret) { fprintf(stderr, "initialize ret=%d\n", ret); return 1; }
    ubsmem_shmem_desc_t objects[2] = {0};
    unsigned count = 2;
    ret = ubsmem_shmem_list_lookup(prefix, objects, &count);
    printf("lookup prefix=%s ret=%d count=%u\n", prefix, ret, count);
    int success = 0;
    if (ret || count > 1) goto done; /* Ambiguous generations require inspection. */
    if (count && (memchr(objects[0].name, 0, sizeof(objects[0].name)) == NULL ||
                  !pool_name_valid(objects[0].name, prefix))) goto done;
    if (count) printf("object name=%s bytes=%llu\n", objects[0].name, (unsigned long long)objects[0].size);
    if (strcmp(argv[2], "release")) { success = 1; goto done; }
    if (count) {
        ret = ubsmem_shmem_deallocate(objects[0].name);
        printf("deallocate %s ret=%d\n", objects[0].name, ret);
        if (ret) goto done;
    }
    count = 2;
    ret = ubsmem_shmem_list_lookup(prefix, objects, &count);
    if (!ret && count == 0) {
        printf("pool-prefix-empty %s protocol=generation-v1\n", prefix);
        success = 1;
    }
done:
    ret = ubsmem_finalize();
    return !success || ret != 0;
}
