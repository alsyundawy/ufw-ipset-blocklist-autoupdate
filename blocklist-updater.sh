#!/usr/bin/env bash
# /root/update-blocklist.sh
# Versi diperbaiki: robust, berwarna, paralel, menghapus semua ipset, pre-create set,
# menulis ke logfile & menampilkan layar, dan TETAP LANJUT meski ada error.
#
# WARNING: script ini akan HAPUS SEMUA ipset (DESTROY_ALL=true).
#
# Ubah variabel CONFIG di bawah jika perlu.

##### ========== CONFIG ========== #####
WORKDIR="/root/ufw-ipset-blocklist-autoupdate"
SCRIPT="update-ip-blocklists.sh"

BLOCKLISTS=(
  "blocklist https://lists.blocklist.de/lists/all.txt"
  "spamhaus https://www.spamhaus.org/drop/drop.txt"
  "bdsatib https://www.binarydefense.com/banlist.txt"
  "ipsum https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"
  "greensnow https://blocklist.greensnow.co/greensnow.txt"
  "cnisarmy http://cinsscore.com/list/ci-badguys.txt"
  "bfblocker https://danger.rulez.sk/projects/bruteforceblocker/blist.php"
  "firehol https://raw.githubusercontent.com/firehol/blocklist-ipsets/refs/heads/master/firehol_abusers_1d.netset"
  "feodoc2ioc https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
  "sefinek https://raw.githubusercontent.com/sefinek/Malicious-IP-Addresses/main/lists/main.txt"
  "daygle https://daygle.net/blocklist.txt"
  "threathive https://threathive.net/hiveblocklist.txt"
)

IPSET_PREFIX="bl-"
VARIANTS=( "-inet" "-inet6" "-inet-T" )

DESTROY_ALL=true
PARALLEL=6                # paralel destroy jobs (sesuaikan dengan CPU/RAM)
DEFAULT_HASHSIZE=8192
DEFAULT_MAXELEM=524288    # ubah jika ingin lebih besar (butuh lebih RAM)

LOGFILE="/var/log/ufw-blocklist-update.log"
##### ========== END CONFIG ========== #####

# Colors if terminal supports it
if [ -t 1 ]; then
  RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"
  BLUE="\033[1;34m"; MAGENTA="\033[1;35m"; CYAN="\033[1;36m"; RESET="\033[0m"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; RESET=""
fi

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
logf() { printf '%s %s\n' "$(timestamp)" "$*"; }
info()  { printf '%s %b%s%b\n' "$(timestamp)" "${CYAN}" "$1" "${RESET}"; }
start() { printf '%s %b%s%b\n' "$(timestamp)" "${BLUE}" "$1" "${RESET}"; }
ok()    { printf '%s %b%s%b\n' "$(timestamp)" "${GREEN}" "$1" "${RESET}"; }
warn()  { printf '%s %b%s%b\n' "$(timestamp)" "${YELLOW}" "$1" "${RESET}"; }
err()   { printf '%s %b%s%b\n' "$(timestamp)" "${RED}" "$1" "${RESET}"; }
dbg()   { printf '%s %b%s%b\n' "$(timestamp)" "${MAGENTA}" "$1" "${RESET}"; }

# tee all output to logfile and screen
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

start "==== START update-blocklist (DESTROY_ALL=${DESTROY_ALL}) ===="

# helper: run but do not exit on failure; record rc
run_cmd() {
  local desc="$1"; shift
  start ">> START: $desc"
  if "$@"; then
    ok "<< OK: $desc"
    return 0
  else
    local rc=$?
    warn "<< FAILED: $desc (rc=$rc)"
    return $rc
  fi
}

# Check ipset availability and versions
if command -v ipset >/dev/null 2>&1; then
  run_cmd "Cek versi ipset (userspace)" ipset --version || true
else
  err "ipset tidak ditemukan di PATH. Pasang paket 'ipset' dulu."
fi

# Try kernel module info (non-fatal)
if command -v modinfo >/dev/null 2>&1; then
  run_cmd "modinfo ip_set (kernel module info)" modinfo ip_set || true
else
  dbg "modinfo tidak tersedia. Lewati pemeriksaan modul."
fi

# Show current sets count
if command -v ipset >/dev/null 2>&1; then
  CURSETS=$(ipset list -n 2>/dev/null | wc -l || true)
  info "Current ipset sets: $CURSETS"
fi

# Function to limit background jobs (simple job control)
# call wait_for_jobs N to block until background jobs < N
wait_for_jobs() {
  local limit="$1"
  while true; do
    # count background jobs of this shell
    local cnt
    cnt=$(jobs -rp 2>/dev/null | wc -l)
    if [ "$cnt" -lt "$limit" ]; then
      break
    fi
    sleep 0.05
  done
}

# 1) Destroy all ipset (if requested)
if [ "$DESTROY_ALL" = true ]; then
  warn "Menghapus SEMUA ipset pada host (DESTROY_ALL=true)."
  ALL_SETS="$(ipset list -n 2>/dev/null || true)"
  if [ -z "$ALL_SETS" ]; then
    info "Tidak ada ipset ditemukan. Lanjut."
  else
    info "Menemukan $(printf '%s\n' "$ALL_SETS" | wc -l) set. Melakukan flush -> destroy (paralel=$PARALLEL)."
    # iterate and spawn background jobs with limited concurrency
    while IFS= read -r setname; do
      [ -z "$setname" ] && continue
      wait_for_jobs "$PARALLEL"
      (
        # child subshell: try flush then destroy; log minimal to stdout
        timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
        if ipset list "$setname" >/dev/null 2>&1; then
          if ipset flush "$setname" >/dev/null 2>&1; then
            printf '%s %s\n' "$(timestamp)" "Flushed $setname"
          else
            printf '%s %s\n' "$(timestamp)" "Flush failed $setname; trying destroy"
          fi
        fi
        if ipset destroy "$setname" >/dev/null 2>&1; then
          printf '%s %s\n' "$(timestamp)" "Destroyed $setname"
        else
          printf '%s %s\n' "$(timestamp)" "Destroy failed $setname"
        fi
      ) &
    done <<< "$ALL_SETS"
    # wait all children done
    wait
    info "Destroy-all selesai."
  fi
fi

# Recheck if any sets left
REMAIN="$(ipset list -n 2>/dev/null || true)"
if [ -z "$REMAIN" ]; then
  ok "Semua ipset kosong sekarang."
else
  warn "Masih ada ipset tersisa ($(printf '%s\n' "$REMAIN" | wc -l)). Lanjutkan dengan pre-create."
fi

# 2) Pre-create expected sets to avoid 'Hash is full'
info "Pre-create set target dengan hashsize=$DEFAULT_HASHSIZE maxelem=$DEFAULT_MAXELEM"
for entry in "${BLOCKLISTS[@]}"; do
  name=${entry%% *}
  for v in "${VARIANTS[@]}"; do
    setname="${IPSET_PREFIX}${name}${v}"
    # decide family by variant name
    if printf '%s' "$v" | grep -q -E '6|inet6|ipv6'; then
      FAMILY="inet6"
    else
      FAMILY="inet"
    fi
    if ipset list "$setname" >/dev/null 2>&1; then
      dbg "Set exists: $setname (skip create)"
    else
      run_cmd "Create set $setname (family=$FAMILY)" \
        ipset create "$setname" hash:ip family "$FAMILY" hashsize "$DEFAULT_HASHSIZE" maxelem "$DEFAULT_MAXELEM" || true
    fi
  done
done

# 3) Run update script (assemble args)
if [ ! -d "$WORKDIR" ]; then
  err "WORKDIR $WORKDIR tidak ditemukan. Tidak dapat menjalankan $SCRIPT."
  err "Selesai."
  exit 1
fi

pushd "$WORKDIR" >/dev/null || { err "Gagal masuk ke $WORKDIR"; exit 1; }

ARGS=()
for bl in "${BLOCKLISTS[@]}"; do
  ARGS+=( -l "$bl" )
done

# run update script; don't exit on failure
run_cmd "Menjalankan $SCRIPT" bash "$SCRIPT" "${ARGS[@]}" || true

popd >/dev/null || true

# 4) reload ufw
run_cmd "ufw reload" ufw reload || true

# 5) Summary: try to parse number of entries; more robust parsing
info "Ringkasan jumlah entries per set (mencari 'Number of entries' atau digit pada header):"
for entry in "${BLOCKLISTS[@]}"; do
  name=${entry%% *}
  for v in "${VARIANTS[@]}"; do
    setname="${IPSET_PREFIX}${name}${v}"
    if ipset list "$setname" >/dev/null 2>&1; then
      # try several patterns
      num="$(ipset list "$setname" 2>/dev/null | awk -F: '/Number of entries/{gsub(/^[ \t]+/,"",$2); print $2; exit}')"
      if [ -z "$num" ]; then
        # fallback: look for "Size:" or a line containing a single number
        num="$(ipset list "$setname" 2>/dev/null | sed -n '1,20p' | awk '/^[[:space:]]*[0-9]+$/{print $1; exit}')"
      fi
      if [ -z "$num" ]; then num="unknown"; fi
      ok " - $setname : $num"
    else
      warn " - $setname : (tidak ada)"
    fi
  done
done

# Extra diagnostics: check for common errors in logfile and give clear, actionable advice
info "Analisa otomatis pesan error di $LOGFILE (mencari 'Kernel support protocol' dan 'Hash is full')"
if grep -q "Kernel support protocol" "$LOGFILE" 2>/dev/null || true; then
  err "Terdeteksi mismatch Kernel<->userspace ipset (pesan 'Kernel support protocol versions ...')."
  echo -e "${YELLOW}Saran:${RESET} Upgrade paket ipset yang cocok dengan kernel, atau rebuild/upgrade kernel module."
  echo -e "Contoh (Debian/Ubuntu): apt update && apt install --only-upgrade ipset"
fi

if grep -q "Hash is full" "$LOGFILE" 2>/dev/null || true; then
  warn "Terdeteksi 'Hash is full' selama proses. Anda mungkin perlu tingkatkan DEFAULT_MAXELEM/hasSize atau pecah set besar."
  echo -e "${YELLOW}Saran:${RESET} Tingkatkan DEFAULT_MAXELEM di awal skrip (butuh RAM), mis: 1048576"
fi

TOTAL_LINES=$(ipset -l 2>/dev/null | wc -l || true)
info "Total raw lines dari 'ipset -l': $TOTAL_LINES"

ok "Selesai. Periksa $LOGFILE untuk detail lebih lengkap."
start "==== END update-blocklist ===="
