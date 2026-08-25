#!/usr/bin/env bash
# /root/update-blocklist.sh or ./blocklist-updater.sh
# Versi final: perbaikan swap/type, compatibility CentOS 7/8/9 & Debian/Ubuntu, counting robust,
# DEFAULT_HASHSIZE=16384, DEFAULT_MAXELEM=1048576

set -euo pipefail
IFS=$'\n\t'

##### CONFIG #####
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-${SCRIPT_DIR}}"
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

IPSET_PREFIX="bl-" # prefix ipset untuk diproses
VARIANTS=("-inet" "-inet6" "-inet-T")

DESTROY_ALL=false       # true -> create ulang set jika dihancurkan
PARALLEL=4              # paralelisasi terbatas (cek URL & create ipset)
DEFAULT_HASHSIZE=16384  # hashsize default
DEFAULT_MAXELEM=1048576 # maxelem default

LOGFILE="/var/log/ufw-blocklist-update.log"
##### END CONFIG #####

# Colors
if [[ -t 1 ]]; then
	RED="\033[1;31m"
	GREEN="\033[1;32m"
	YELLOW="\033[1;33m"
	BLUE="\033[1;34m"
	MAGENTA="\033[1;35m"
	CYAN="\033[1;36m"
	RESET="\033[0m"
else
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	MAGENTA=""
	CYAN=""
	RESET=""
fi

if [[ ${EUID} -ne 0 ]]; then
	printf 'Script must be run as root.\n' >&2
	exit 1
fi

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
info() { printf '%s %b%s%b\n' "$(timestamp)" "${CYAN}" "$1" "${RESET}"; }
start() { printf '%s %b%s%b\n' "$(timestamp)" "${BLUE}" "$1" "${RESET}"; }
ok() { printf '%s %b%s%b\n' "$(timestamp)" "${GREEN}" "$1" "${RESET}"; }
warn() { printf '%s %b%s%b\n' "$(timestamp)" "${YELLOW}" "$1" "${RESET}"; }
err() { printf '%s %b%s%b\n' "$(timestamp)" "${RED}" "$1" "${RESET}"; }
dbg() { printf '%s %b%s%b\n' "$(timestamp)" "${MAGENTA}" "$1" "${RESET}"; }

# Log to file and screen safely
mkdir -p "$(dirname "${LOGFILE}")"
touch "${LOGFILE}"
exec > >(tee -a "${LOGFILE}") 2>&1

start "==== START update-blocklist (safe, compatibility fixes) ===="

# safe-run wrapper
run_cmd() {
	local desc="$1"
	shift
	start ">> START: ${desc}"
	if "$@"; then
		ok "<< OK: ${desc}"
		return 0
	else
		local rc=$?
		warn "<< FAILED: ${desc} (rc=${rc})"
		return "${rc}"
	fi
}

# Check ipset binary and versions
IPSET_BIN="$(command -v ipset || true)"
if [[ -z ${IPSET_BIN} || ! -x ${IPSET_BIN} ]]; then
	err "ipset binary tidak ditemukan in PATH. Install package 'ipset' terlebih dahulu."
	exit 1
fi

USRVERS="$("${IPSET_BIN}" --version 2>/dev/null || true)"
info "ipset userspace: ${USRVERS:-(unknown)}"

if command -v modinfo >/dev/null 2>&1; then
	KVER="$(modinfo ip_set 2>/dev/null | awk -F: '/version:/{gsub(/^[ \t]+/,"",$2); print $2; exit}' || true)"
	dbg "ip_set kernel module version: ${KVER:-(unknown)}"
fi

TMPTEST="__ipset_test_tmp_$$"
run_cmd "Create temporary test set ${TMPTEST}" "${IPSET_BIN}" create "${TMPTEST}" hash:ip family inet hashsize 64 maxelem 1024 >/dev/null 2>&1 || true
ADD_OUTPUT="$("${IPSET_BIN}" add "${TMPTEST}" 127.0.0.1 2>&1 >/dev/null || true)"
if printf '%s\n' "${ADD_OUTPUT}" | grep -q -i "Kernel support protocol"; then
	warn "Terdeteksi kernel<->userspace ipset mismatch: $(printf '%s' "${ADD_OUTPUT}" | sed -n '1,3p')"
fi
"${IPSET_BIN}" destroy "${TMPTEST}" >/dev/null 2>&1 || true

CURSETS="$("${IPSET_BIN}" list -n 2>/dev/null | wc -l | tr -d ' ' || true)"
info "Current ipset sets count: ${CURSETS}"

wait_for_jobs() {
	local limit="$1"
	while true; do
		local cnt
		cnt=$(jobs -rp 2>/dev/null | wc -l | tr -d ' ')
		if [[ ${cnt} -lt ${limit} ]]; then break; fi
		sleep 0.05
	done
}

if [[ ${DESTROY_ALL} == true ]]; then
	warn "DESTROY_ALL=true -> Menghapus semua ipset (flush -> destroy)."
	ALL_SETS="$("${IPSET_BIN}" list -n 2>/dev/null || true)"
	if [[ -z ${ALL_SETS} ]]; then
		info "Tidak ada ipset ditemukan."
	else
		info "Menemukan $(printf '%s\n' "${ALL_SETS}" | wc -l | tr -d ' ') set; mulai flush/destroy (paralel=${PARALLEL})."
		while IFS= read -r s; do
			[[ -z ${s} ]] && continue
			wait_for_jobs "${PARALLEL}"
			(
				if "${IPSET_BIN}" list "${s}" >/dev/null 2>&1; then
					"${IPSET_BIN}" flush "${s}" >/dev/null 2>&1 || true
				fi
				"${IPSET_BIN}" destroy "${s}" >/dev/null 2>&1 || true
			) &
		done <<<"${ALL_SETS}"
		wait
		info "Destroy-all selesai."
	fi
fi

# PRE-CREATE sets with consistent types
info "Memeriksa dan menyiapkan set dengan hashsize=${DEFAULT_HASHSIZE} maxelem=${DEFAULT_MAXELEM}"
for entry in "${BLOCKLISTS[@]}"; do
	name="${entry%% *}"
	for v in "${VARIANTS[@]}"; do
		setname="${IPSET_PREFIX}${name}${v}"
		if printf '%s' "${v}" | grep -q -E "6|inet6|ipv6"; then
			FAMILY="inet6"
		else
			FAMILY="inet"
		fi
		if ! "${IPSET_BIN}" list "${setname}" >/dev/null 2>&1; then
			"${IPSET_BIN}" create -! "${setname}" hash:net family "${FAMILY}" hashsize "${DEFAULT_HASHSIZE}" maxelem "${DEFAULT_MAXELEM}" >/dev/null 2>&1 || true
		fi
	done
done

# Ensure WORKDIR exists
if [[ ! -d ${WORKDIR} ]]; then
	err "WORKDIR ${WORKDIR} tidak ditemukan. Tidak dapat menjalankan ${SCRIPT}."
	exit 1
fi

pushd "${WORKDIR}" >/dev/null || {
	err "Gagal masuk ke ${WORKDIR}"
	exit 1
}

ARGS=()
for bl in "${BLOCKLISTS[@]}"; do
	ARGS+=(-l "${bl}")
done

if [[ -f "${SCRIPT}" ]]; then
	run_cmd "Menjalankan ${SCRIPT} (update blocklists)" bash "${SCRIPT}" "${ARGS[@]}" || true
else
	err "${SCRIPT} tidak ditemukan di ${WORKDIR}"
fi

popd >/dev/null || true

# reload UFW
if command -v ufw >/dev/null 2>&1; then
	run_cmd "ufw reload" ufw reload || true
fi

# Summary using robust counting
count_entries() {
	local setname="$1"
	local n
	n="$("${IPSET_BIN}" list "${setname}" 2>/dev/null | awk -F: '/Number of entries/{gsub(/^[ \t]+/,"",$2); print $2; exit}' || true)"
	if [[ -n ${n} ]]; then
		printf '%s\n' "${n}"
	else
		printf '0\n'
	fi
}

info "Ringkasan jumlah entries per set:"
for entry in "${BLOCKLISTS[@]}"; do
	name="${entry%% *}"
	for v in "${VARIANTS[@]}"; do
		setname="${IPSET_PREFIX}${name}${v}"
		if "${IPSET_BIN}" list "${setname}" >/dev/null 2>&1; then
			num=$(count_entries "${setname}") || num="unknown"
			ok " - ${setname} : ${num}"
		fi
	done
done

TOTAL_LINES="$("${IPSET_BIN}" list -n 2>/dev/null | wc -l | tr -d ' ' || true)"
info "Total active ipsets: ${TOTAL_LINES}"
ok "Selesai. Log tersimpan di ${LOGFILE}."
start "==== END update-blocklist ===="
