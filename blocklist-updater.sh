#!/usr/bin/env bash
# /root/update-blocklist.sh
# Versi final: perbaikan swap/type, compatibility CentOS6 ipset v6.11 & Debian/Ubuntu, counting robust,
# DEFAULT_HASHSIZE=16384, DEFAULT_MAXELEM=1048576
#
# WARNING: this script may DESTROY ALL existing ipset if DESTROY_ALL=true

##### CONFIG #####
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

IPSET_PREFIX="bl-"              # prefix ipset untuk diproses
# create all variants (including -T temp sets to match update script swap behavior)
VARIANTS=( "-inet" "-inet6" "-inet-T" )

DESTROY_ALL=true            # true -> create ulang set jika dihancurkan
PARALLEL=6                 # paralelisasi terbatas (cek URL & create ipset)
DEFAULT_HASHSIZE=16384		# hashsize default (naikkan jika perlu)
DEFAULT_MAXELEM=1048576    # maxelem default (naikkan jika RAM mencukupi)

LOGFILE="/var/log/ufw-blocklist-update.log"
##### END CONFIG #####

# Colors
if [ -t 1 ]; then
  RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"
  BLUE="\033[1;34m"; MAGENTA="\033[1;35m"; CYAN="\033[1;36m"; RESET="\033[0m"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; RESET=""
fi

timestamp(){ date +"%Y-%m-%d %H:%M:%S"; }
echo_log(){ printf '%s %s\n' "$(timestamp)" "$*"; }
info(){ printf '%s %b%s%b\n' "$(timestamp)" "${CYAN}" "$1" "${RESET}"; }
start(){ printf '%s %b%s%b\n' "$(timestamp)" "${BLUE}" "$1" "${RESET}"; }
ok(){ printf '%s %b%s%b\n' "$(timestamp)" "${GREEN}" "$1" "${RESET}"; }
warn(){ printf '%s %b%s%b\n' "$(timestamp)" "${YELLOW}" "$1" "${RESET}"; }
err(){ printf '%s %b%s%b\n' "$(timestamp)" "${RED}" "$1" "${RESET}"; }
dbg(){ printf '%s %b%s%b\n' "$(timestamp)" "${MAGENTA}" "$1" "${RESET}"; }

# Log to file and screen
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

start "==== START update-blocklist (safe, compatibility fixes) ===="

# safe-run wrapper (logs start/ok/fail but does NOT exit script)
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

# Check ipset binary and versions
IPSET_BIN="$(command -v ipset || true)"
if [ -z "$IPSET_BIN" ]; then
  err "ipset binary tidak ditemukan in PATH. Install package 'ipset' terlebih dahulu."
  exit 1
fi

# userspace version
USRVERS="$($IPSET_BIN --version 2>/dev/null || true)"
info "ipset userspace: ${USRVERS:-(unknown)}"

# Try kernel module info
KVER=""
if command -v modinfo >/dev/null 2>&1; then
  KVER="$(modinfo ip_set 2>/dev/null | awk -F: '/version:/{gsub(/^[ \t]+/,"",$2); print $2; exit}')"
  dbg "ip_set kernel module version: ${KVER:-(unknown)}"
fi

# Simple heuristic to detect protocol mismatch:
# try to create a temporary set and add a test IP; capture known mismatch messages
TMPTEST="__ipset_test_tmp_$$"
run_cmd "Create temporary test set $TMPTEST" $IPSET_BIN create "$TMPTEST" hash:ip family inet hashsize 64 maxelem 1024 >/dev/null 2>&1 || true
# try add an IP (127.0.0.1); capture stderr for protocol mismatch pattern
ADD_OUTPUT="$($IPSET_BIN add "$TMPTEST" 127.0.0.1 2>&1 >/dev/null || true)"
if printf '%s\n' "$ADD_OUTPUT" | grep -q -i "Kernel support protocol"; then
  warn "Terdeteksi kernel<->userspace ipset mismatch: $(printf '%s' "$ADD_OUTPUT" | sed -n '1,3p')"
  echo
  echo "  >> Penjelasan singkat:"
  echo "     - CentOS 6 (ipset v6.11) sering memiliki kernel/userspace mismatch jika userspace terlalu lama/baru."
  echo "     - Solusi: sinkronkan userspace ipset dengan modul kernel:"
  echo "         * (Debian/Ubuntu) apt update && apt install --only-upgrade ipset"
  echo "         * (CentOS) update package ipset via yum/CentOS repos or use matching ipset binary for kernel"
  echo "         * Jika instalasi paket tidak tersedia, Anda mungkin perlu recompile/install ipset userspace yang kompatibel atau reboot setelah upgrade kernel/module."
  echo
  warn "Karena mismatch, beberapa operasi ipset mungkin gagal. Lanjutkan dengan kewaspadaan."
fi
# cleanup tmp test set
$IPSET_BIN destroy "$TMPTEST" >/dev/null 2>&1 || true

# Show current ipset count (rough)
CURSETS="$(ipset list -n 2>/dev/null | wc -l || true)"
info "Current ipset sets (before destroy): $CURSETS"

# Concurrency helper
wait_for_jobs() {
  local limit="$1"
  while true; do
    local cnt
    cnt=$(jobs -rp 2>/dev/null | wc -l)
    if [ "$cnt" -lt "$limit" ]; then break; fi
    sleep 0.05
  done
}

# DESTROY ALL if requested
if [ "$DESTROY_ALL" = true ]; then
  warn "DESTROY_ALL=true -> Menghapus semua ipset (flush -> destroy)."
  ALL_SETS="$(ipset list -n 2>/dev/null || true)"
  if [ -z "$ALL_SETS" ]; then
    info "Tidak ada ipset ditemukan."
  else
    info "Menemukan $(printf '%s\n' "$ALL_SETS" | wc -l) set; mulai flush/destroy (paralel=$PARALLEL)."
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      wait_for_jobs "$PARALLEL"
      (
        # child: flush then destroy
        if ipset list "$s" >/dev/null 2>&1; then
          if ipset flush "$s" >/dev/null 2>&1; then
            printf '%s %s\n' "$(timestamp)" "Flushed $s"
          else
            printf '%s %s\n' "$(timestamp)" "Flush failed $s"
          fi
        fi
        if ipset destroy "$s" >/dev/null 2>&1; then
          printf '%s %s\n' "$(timestamp)" "Destroyed $s"
        else
          printf '%s %s\n' "$(timestamp)" "Destroy failed $s"
        fi
      ) &
    done <<< "$ALL_SETS"
    wait
    info "Destroy-all selesai."
  fi
fi

# Verify all sets removed
REMAIN="$(ipset list -n 2>/dev/null || true)"
if [ -z "$REMAIN" ]; then
  ok "Semua ipset kini kosong."
else
  warn "Masih terdapat beberapa ipset tersisa ($(printf '%s\n' "$REMAIN" | wc -l)). Lanjutkan."
fi

# PRE-CREATE sets (include -T) with consistent types to avoid swap/type mismatch
info "Pre-create sets (varians termasuk -T) dengan hashsize=$DEFAULT_HASHSIZE maxelem=$DEFAULT_MAXELEM"
for entry in "${BLOCKLISTS[@]}"; do
  name=${entry%% *}
  for v in "${VARIANTS[@]}"; do
    setname="${IPSET_PREFIX}${name}${v}"
    # determine family: -inet6 likely IPv6
    if printf '%s' "$v" | grep -q -E "6|inet6|ipv6"; then
      FAMILY="inet6"
    else
      FAMILY="inet"
    fi
    # Ensure we create same type as update script expects: use hash:ip which is most common
    if ipset list "$setname" >/dev/null 2>&1; then
      dbg "Set exists: $setname (skip create)"
    else
      # try create; capture errors but continue
      run_cmd "Create $setname (family=$FAMILY)" ipset create "$setname" hash:ip family "$FAMILY" hashsize "$DEFAULT_HASHSIZE" maxelem "$DEFAULT_MAXELEM" || true
    fi
  done
done

# Ensure WORKDIR exists
if [ ! -d "$WORKDIR" ]; then
  err "WORKDIR $WORKDIR tidak ditemukan. Tidak dapat menjalankan $SCRIPT."
  exit 1
fi

pushd "$WORKDIR" >/dev/null || { err "Gagal masuk ke $WORKDIR"; exit 1; }

# assemble args and run update script (do not fail entire script on error)
ARGS=()
for bl in "${BLOCKLISTS[@]}"; do
  ARGS+=( -l "$bl" )
done

run_cmd "Menjalankan $SCRIPT (update blocklists)" bash "$SCRIPT" "${ARGS[@]}" || true

popd >/dev/null || true

# reload UFW (best-effort)
run_cmd "ufw reload" ufw reload || true

# RELIABLE COUNT: use ipset save and count 'add ' entries inside section per set
count_entries() {
  local setname="$1"
  # ipset save prints all sets; extract section that starts with "create <setname>" until next create or EOF
  if ipset save 2>/dev/null | sed -n "/^create $setname[[:space:]]/,/^create /p" | grep -q '^add '; then
    # count add lines in that section
    local c
    c=$(ipset save 2>/dev/null | sed -n "/^create $setname[[:space:]]/,/^create /p" | grep -c '^add ' || true)
    printf '%s\n' "$c"
  else
    # Try fallback: ipset list -> parse Number of entries or Members count
    local n
    n=$(ipset list "$setname" 2>/dev/null | awk -F: '/Number of entries/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
    if [ -n "$n" ]; then
      printf '%s\n' "$n"
    else
      printf 'unknown\n'
    fi
  fi
}

# Summary using robust counting
info "Ringkasan jumlah entries per set (menggunakan 'ipset save' fallback):"
for entry in "${BLOCKLISTS[@]}"; do
  name=${entry%% *}
  for v in "${VARIANTS[@]}"; do
    setname="${IPSET_PREFIX}${name}${v}"
    if ipset list "$setname" >/dev/null 2>&1; then
      num=$(count_entries "$setname") || num="unknown"
      if [ "$num" = "unknown" ]; then
        warn " - $setname : unknown"
      else
        ok " - $setname : $num"
      fi
    else
      warn " - $setname : (tidak ada)"
    fi
  done
done

# Analyze logfile for known errors and provide clear next steps
info "Analisa otomatis pesan error (lihat $LOGFILE):"
if grep -q "Kernel support protocol" "$LOGFILE" 2>/dev/null || true; then
  err "Terdeteksi kernel/userspace protocol mismatch di logfile."
  echo "Saran tindakan:"
  echo " - CentOS 6 (ipset v6.11): pastikan package ipset userspace cocok. Jika tidak tersedia di repo, cari ipset build yang cocok untuk kernel atau upgrade kernel."
  echo " - Debian/Ubuntu: jalankan 'apt update && apt install --only-upgrade ipset' (atau gunakan backports jika perlu)."
  echo " - Setelah upgrade, reboot jika diperlukan sehingga modul kernel dan userspace sejalan."
fi

if grep -q "Hash is full" "$LOGFILE" 2>/dev/null || true; then
  warn "Ditemukan 'Hash is full' pada logfile."
  echo "Saran: tingkatkan DEFAULT_MAXELEM/DEFAULT_HASHSIZE (cermati RAM server), atau pecah blocklist menjadi beberapa set."
fi

if grep -q "The sets cannot be swapped: they type does not match" "$LOGFILE" 2>/dev/null || true; then
  warn "Terdeteksi error 'The sets cannot be swapped: they type does not match'."
  echo "Saran: pastikan pre-create set dan temp-set (-T) memiliki tipe yang sama (hash:ip/inets). Skrip ini sudah mencoba membuat -T dengan tipe hash:ip."
fi

TOTAL_LINES="$(ipset -l 2>/dev/null | wc -l || true)"
info "Total raw lines ipset -l: $TOTAL_LINES"

ok "Selesai. Periksa $LOGFILE untuk detail. Jika Anda ingin saya ubah DEFAULT_MAXELEM/hasSize atau non-aktifkan DESTROY_ALL, beri tahu nilai yang diinginkan."

start "==== END update-blocklist ===="
