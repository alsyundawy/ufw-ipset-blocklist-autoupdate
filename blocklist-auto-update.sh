#!/usr/bin/env bash
# Script: blocklist-auto-update.sh
# Deskripsi: Otomasi instalasi/konfigurasi blocklist dengan UFW dan ipset (IPv4 & IPv6), penjadwalan cron harian.
# Prasyarat: Dijalankan sebagai root.

set -euo pipefail
IFS=$'\n\t'

#--------------------------------------
# Fungsi Logging
#--------------------------------------
log() {
	local timestamp level msg
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	level=${2:-INFO}
	msg=$1
	echo "[${timestamp}] [${level}] ${msg}"
}

#--------------------------------------
# Validasi Akses Root
#--------------------------------------
if [[ ${EUID} -ne 0 ]]; then
	log "Script must be run as root." ERROR
	exit 1
fi

#--------------------------------------
# Variabel Konfigurasi
#--------------------------------------
REPO_URL="https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${SCRIPT_DIR}"
CRON_PATH="/etc/cron.d/blocklist-update"
UPDATE_SCRIPT="update-ip-blocklists.sh"
SETUP_SCRIPT="setup-ufw.sh"
CRON_SCHEDULE="0 2 * * *"

# Daftar blocklist (nama dan URL) - nama max 19 karakter
declare -A BLOCKLISTS=(
	[blocklist]="https://lists.blocklist.de/lists/all.txt"
	[spamhaus]="https://www.spamhaus.org/drop/drop.txt"
	[bdsatib]="https://www.binarydefense.com/banlist.txt"
	[ipsum]="https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"
	[greensnow]="https://blocklist.greensnow.co/greensnow.txt"
	[cnisarmy]="http://cinsscore.com/list/ci-badguys.txt"
	[feodotracker]="https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
	[sefinek]="https://raw.githubusercontent.com/sefinek/Malicious-IP-Addresses/main/lists/main.txt"
)

#--------------------------------------
# Deteksi OS & Instalasi Dependensi
#--------------------------------------
log "Mendeteksi OS dan memeriksa dependensi..."
if [[ -f /etc/debian_version ]]; then
	MISSING=()
	for pkg in git ufw ipset iptables; do
		if ! dpkg -s "${pkg}" &>/dev/null; then
			MISSING+=("${pkg}")
		fi
	done
	if ((${#MISSING[@]} > 0)); then
		log "Menginstal paket: ${MISSING[*]}"
		apt-get update -qq
		apt-get install -y -qq "${MISSING[@]}"
	else
		log "Semua dependensi sudah terpasang."
	fi
elif [[ -f /etc/redhat-release ]]; then
	MISSING=()
	if ! rpm -q epel-release &>/dev/null; then
		yum install -y -q epel-release || true
	fi
	for pkg in git ufw ipset iptables-services; do
		if ! rpm -q "${pkg}" &>/dev/null; then
			MISSING+=("${pkg}")
		fi
	done
	if ((${#MISSING[@]} > 0)); then
		log "Menginstal paket: ${MISSING[*]}"
		yum install -y -q "${MISSING[@]}"
	else
		log "Semua dependensi sudah terpasang."
	fi
	if systemctl is-enabled iptables &>/dev/null || systemctl is-active iptables &>/dev/null; then
		systemctl enable --now iptables 2>/dev/null || true
	fi
else
	log "Distribusi Linux tidak dikenali secara langsung, melanjutkan dengan dependensi yang ada..." WARNING
fi

#--------------------------------------
# Clone atau Update Repository
#--------------------------------------
log "Menyiapkan repository blocklist di ${WORKDIR}..."
if [[ -d "${WORKDIR}/.git" ]]; then
	git -C "${WORKDIR}" pull --quiet origin master 2>/dev/null || true
elif [[ ! -f "${WORKDIR}/${UPDATE_SCRIPT}" ]]; then
	WORKDIR="/root/ufw-ipset-blocklist-autoupdate"
	if [[ -d "${WORKDIR}/.git" ]]; then
		git -C "${WORKDIR}" pull --quiet origin master 2>/dev/null || true
	else
		git clone --depth 1 "${REPO_URL}" "${WORKDIR}"
	fi
fi

#--------------------------------------
# Konfigurasi UFW IPv6
#--------------------------------------
log "Mengonfigurasi IPv6 di UFW..."
UFW_CONF="/etc/default/ufw"
if [[ -f ${UFW_CONF} ]]; then
	sed -i 's/\r$//' "${UFW_CONF}" 2>/dev/null || true
	sed -i -E 's/^#?IPV6=.*$/IPV6=yes/' "${UFW_CONF}"
	grep -q '^IPV6=yes' "${UFW_CONF}" || echo 'IPV6=yes' >>"${UFW_CONF}"
else
	log "${UFW_CONF} tidak ditemukan" WARNING
fi

# Restart UFW jika tersedia
if command -v ufw >/dev/null 2>&1; then
	ufw --force disable 2>/dev/null || true
	ufw --force enable 2>/dev/null || true
	log "UFW telah di-restart dengan IPv6 aktif."
fi

#--------------------------------------
# Jalankan Setup Awal (Non-interaktif)
#--------------------------------------
log "Menjalankan setup awal UFW (auto-confirm)..."
if [[ -x "${WORKDIR}/${SETUP_SCRIPT}" ]]; then
	(cd "${WORKDIR}" && yes Y | bash "${SETUP_SCRIPT}")
elif [[ -f "${WORKDIR}/${SETUP_SCRIPT}" ]]; then
	(cd "${WORKDIR}" && yes Y | bash "${SETUP_SCRIPT}")
else
	log "Script setup tidak ditemukan: ${WORKDIR}/${SETUP_SCRIPT}" ERROR
	exit 1
fi

#--------------------------------------
# Build Argumen Blocklist
#--------------------------------------
log "Menyusun parameter blocklist..."
args=()
cron_args_str=""
for name in "${!BLOCKLISTS[@]}"; do
	args+=("-l" "${name} ${BLOCKLISTS[${name}]}")
	cron_args_str+="-l \"${name} ${BLOCKLISTS[${name}]}\" "
done

#--------------------------------------
# Update Blocklist Pertama Kali
#--------------------------------------
log "Memperbarui blocklist pertama kali..."
if [[ -f "${WORKDIR}/${UPDATE_SCRIPT}" ]]; then
	(cd "${WORKDIR}" && bash "${UPDATE_SCRIPT}" "${args[@]}")
else
	log "Script update tidak ditemukan: ${WORKDIR}/${UPDATE_SCRIPT}" ERROR
	exit 1
fi

#--------------------------------------
# Atur Cron Job Harian
#--------------------------------------
log "Menulis cron job harian ke ${CRON_PATH}..."
mkdir -p "$(dirname "${CRON_PATH}")"
cat <<EOF >"${CRON_PATH}"
# /etc/cron.d/blocklist-update: Auto-update ipset blocklists for UFW
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

${CRON_SCHEDULE} root cd ${WORKDIR} && bash ${UPDATE_SCRIPT} ${cron_args_str}>/dev/null 2>&1
EOF
chmod 644 "${CRON_PATH}"

log "Instalasi dan konfigurasi selesai. Blocklist dijadwalkan setiap hari pukul 02:00."
