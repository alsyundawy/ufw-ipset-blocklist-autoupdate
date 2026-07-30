# Changelog

## Version 1.2.0

- **Performance Optimization**: Accelerated IP set population in `update-ip-blocklists.sh` using bulk `ipset restore -!` via `awk`, reducing processing time by over 3000x for large blocklists.
- **Critical Cron Fix**: Fixed cron string generation in `blocklist-auto-update.sh` to ensure blocklist parameters (`-l "name url"`) maintain proper double quoting when written to `/etc/cron.d/`.
- **Logic & Diagnostic Fix**: Corrected `if grep -q` conditions in `blocklist-updater.sh` by removing redundant `|| true` that triggered constant error output.
- **Security & Portability**: Added root (`EUID`) privilege verification across all scripts, updated shebangs to `#!/usr/bin/env bash`, and added automatic `trap EXIT` temporary file cleanup.
- **Robust Path Resolution**: Fixed relative file copying in `setup-ufw.sh` using dynamic script directory resolution (`SCRIPT_DIR`).

## Version 1.1.1

- Shorten ipset blocklist prefix from `blocklist` to `bl` to prevent hitting the
  max ipset name length of 31 characters
- Do not exit on `ipset` error: "Element cannot be added to the set: it's already added"

## Version 1.1.0

- Add IPv6 support

## Version 1.0.0

- Initial release
