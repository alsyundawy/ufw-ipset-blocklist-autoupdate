# [1.2.1] Changelog

## Overview

Release 1.2.1 introduces repository-wide security hardening, Netfilter prefix truncation fixes, performance optimizations, and full cross-distribution compatibility.

## Changes in 1.2.1

- **Security**: Implemented `set -euo pipefail` and safe `IFS=$'\n\t'` across all shell scripts.
- **Security**: Added strict root (`EUID`) privilege enforcement on all script entry points.
- **Security**: Fixed Netfilter `--log-prefix` length by clamping prefixes to the Linux kernel limit of 29 characters (`XT_LOG_MAXPREFIX`).
- **Resilience**: Added IPv6 detection with fallback for systems without `ip6tables` or with IPv6 disabled.
- **Performance**: Replaced subshell `cut` calls with native Bash string manipulation (`${list%% *}`, `${list#* }`).
- **Performance**: Added default `maxelem 1048576` and `hashsize 16384` to prevent `Hash is full` on large blocklists (FireHOL, Abuse.ch, Spamhaus).
- **Performance**: Added duplicate IP elimination via `sort -u` prior to batch ipset restoration.
- **Performance**: Replaced full `ipset list` in `status` subcommand with concise header and entry counts.
- **Fixed**: Implemented single atomic temporary directory handling (`TMP_DIR`) with centralized trap cleanup (`EXIT INT TERM HUP`).
- **Fixed**: Added `curl` download fallback when `wget` is not installed.
- **Fixed**: Fixed `BLOCKLISTS` array to use indexed array storage to preserve CLI flag order.
- **Fixed**: Replaced `iptables-save | grep` with direct kernel checks (`iptables -C`).
- **Fixed**: Implemented looping teardown (`while iptables -D ...`) to prevent `Set cannot be destroyed` errors on stop.
- **Fixed**: Resolved script path resolution via `SCRIPT_DIR` and added POSIX line-ending normalization in `setup-ufw.sh` and `blocklist-auto-update.sh`.

## Previous Releases

### [1.2.0] - 2026-08-20

- **Performance**: Accelerated IP set population in `update-ip-blocklists.sh` using bulk `ipset restore -!` via `awk`.
- **Fixed**: Fixed cron string generation in `blocklist-auto-update.sh` to ensure blocklist parameters maintain proper double quoting in `/etc/cron.d/`.
- **Fixed**: Corrected `if grep -q` conditions in `blocklist-updater.sh` by removing redundant `|| true`.
- **Security**: Added root (`EUID`) privilege checks, updated shebangs to `#!/usr/bin/env bash`, and added automatic `trap EXIT` cleanup.
- **Fixed**: Fixed relative file copying in `setup-ufw.sh` using script directory resolution (`SCRIPT_DIR`).

### [1.1.1] - 2023-11-15

- **Changed**: Shortened ipset blocklist prefix to `bl-` to prevent exceeding the maximum ipset name limit of 31 characters.
- **Fixed**: Prevented exit on `ipset` error: "Element cannot be added to the set: it's already added".

### [1.1.0] - 2023-11-10

- **Added**: Added IPv6 blocklist support.

### [1.0.0] - 2023-10-01

- **Added**: Initial release.
