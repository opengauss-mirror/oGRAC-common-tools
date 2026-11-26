#!/usr/bin/env python3
"""Apply a reference UB + serial-flush parameter profile to an ogracd.ini.

The values below come from an oGRAC super-node performance test profile
("UB + serial flush") and are sized for a large-memory node (on the order of
1.5 TB).  Adjust the memory sizes for your hardware before production use.

UB cluster addressing is site-specific, so UBS_CLUSTER_HOSTS is NOT hardcoded:
set it in the environment (format required by your UBS SDK, e.g.
"21-204,21-205").  If it is unset, the key is left untouched.

Usage:
    UBS_CLUSTER_HOSTS='<hosts>' python3 apply_ub_params.py /path/to/ogracd.ini
The file is modified in place; keys not present are appended.
"""
import os
import re
import sys

PARAMS = {
    "_ENABLE_UBSMEM": "TRUE",
    "DATA_BUFFER_SIZE": "350G",
    "DTC_REMOTE_SGA_SIZE": "20G",
    "DTC_REMOTE_DATA_BUF_SIZE": "14G",
    "_UB_PAGE_HOT_THRESHOLD": "10",
    "_UB_PAGE_HOT_TIMEOUT": "1",
    "SHARED_POOL_SIZE": "25G",
    "TEMP_BUFFER_SIZE": "25G",
    "LOG_BUFFER_COUNT": "16",
    "LOG_BUFFER_SIZE": "110M",
    "MES_POOL_SIZE": "16384",
    "CHECKPOINT_IO_CAPACITY": "4096",
    "BUFFER_LRU_SEARCH_THRE": "40",
    "BUFFER_PAGE_CLEAN_RATIO": "0.1",
    "DBWR_PROCESSES": "8",
    "INTERCONNECT_CHANNEL_NUM": "32",
    "ENABLE_DBSTOR_BATCH_FLUSH": "TRUE",
    "_LOG_MAX_FILE_SIZE": "160M",
    "_LOG_BACKUP_FILE_COUNT": "6",
    "OGRAC_TASK_NUM": "256",
    "REACTOR_THREAD_NUM": "6",
    "OPTIMIZED_WORKER_THREADS": "2000",
    "MAX_WORKER_THREADS": "2000",
    "_ENABLE_REMOTE_DISTRIBUTE_LOCK": "TRUE",
}

ubs_hosts = os.environ.get("UBS_CLUSTER_HOSTS", "").strip()
if ubs_hosts:
    PARAMS["UBS_CLUSTER_HOSTS"] = ubs_hosts


def main():
    if len(sys.argv) != 2:
        print("usage: [UBS_CLUSTER_HOSTS=<hosts>] apply_ub_params.py <ogracd.ini>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8", errors="replace") as fp:
        lines = fp.readlines()

    seen = set()
    out = []
    for line in lines:
        match = re.match(r"^\s*([A-Za-z0-9_]+)\s*=", line)
        if match and match.group(1) in PARAMS:
            key = match.group(1)
            out.append("%s = %s\n" % (key, PARAMS[key]))
            seen.add(key)
        else:
            out.append(line)

    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"
    missing = [key for key in PARAMS if key not in seen]
    if missing:
        out.append("\n# UB + serial flush parameters (appended by apply_ub_params.py)\n")
        for key in missing:
            out.append("%s = %s\n" % (key, PARAMS[key]))

    with open(path, "w", encoding="utf-8") as fp:
        fp.writelines(out)

    print("updated %s (%d replaced, %d appended)" % (path, len(seen), len(missing)))
    if not ubs_hosts:
        print("note: UBS_CLUSTER_HOSTS not set; the key was not modified", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
