#!/usr/bin/env bash

# Set mode error handling
set -euo pipefail
IFS=$'\n\t'

# Validasi Akses Root
if [[ ${EUID} -ne 0 ]]; then
	echo "ERROR: Script must be run as root." >&2
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Variabel
UFW_CONF_DIR="/etc/ufw"
UFW_AFTER_INIT_FILE="${UFW_CONF_DIR}/after.init"
IPSET_DIR="/var/lib/ipset"
CONFIGURE_IPV6=0

# Fungsi untuk menangani input pengguna
process_input() {
	local prompt="$1"
	local default_choice="${2:-Y}" # Default jawaban adalah 'Y' jika tidak diberikan
	local response=""
	read -r -p "${prompt} [${default_choice}]: " response || response="${default_choice}"
	response="${response:-${default_choice}}" # Gunakan default jika tidak ada input
	case "${response}" in
	[yY][eE][sS] | [yY]) return 0 ;;
	*) return 1 ;;
	esac
}

# Konfirmasi konfigurasi UFW dengan blocklist
process_input "Configure UFW to block IPs listed in blocklist ipsets?" || exit 0

# Konfirmasi apakah ingin mengaktifkan IPv6
if process_input "Would you like to enable IPv6 support?"; then
	CONFIGURE_IPV6=1
fi

# Pastikan direktori IPSET dan UFW tersedia
mkdir -p "${IPSET_DIR}" "${UFW_CONF_DIR}"

# Periksa apakah IPv6 diaktifkan dalam konfigurasi UFW
if [[ ${CONFIGURE_IPV6} -eq 1 ]]; then
	if [[ -f /etc/default/ufw ]]; then
		if ! grep -qE "^IPV6=(yes|YES)$" /etc/default/ufw; then
			echo "IPv6 belum aktif di /etc/default/ufw. Memperbarui konfigurasi..."
			sed -i.bak 's/^#*IPV6=.*/IPV6=yes/' /etc/default/ufw 2>/dev/null || sed -i 's/^#*IPV6=.*/IPV6=yes/' /etc/default/ufw
			rm -f /etc/default/ufw.bak
			echo "Konfigurasi IPv6 telah diperbarui ke 'yes'."
		fi
	fi
fi

# Periksa apakah file after.init sudah ada
if [[ -f ${UFW_AFTER_INIT_FILE} ]]; then
	if ! process_input "The file ${UFW_AFTER_INIT_FILE} already exists. Overwrite?" "N"; then
		echo "Setup dibatalkan oleh pengguna."
		exit 0
	fi
fi

# Tentukan file sumber
SRC_INIT="${SCRIPT_DIR}/ufw/after$([[ ${CONFIGURE_IPV6} -eq 1 ]] && echo "6").init"
if [[ ! -f "${SRC_INIT}" ]]; then
	echo "ERROR: Source file ${SRC_INIT} tidak ditemukan." >&2
	exit 1
fi

# Salin konfigurasi after.init
cp "${SRC_INIT}" "${UFW_AFTER_INIT_FILE}"
chmod 755 "${UFW_AFTER_INIT_FILE}"
echo "Deployed ${UFW_AFTER_INIT_FILE}"

# Reload UFW jika diminta dan binary tersedia
if command -v ufw >/dev/null 2>&1; then
	if process_input "Reload UFW to apply changes?"; then
		ufw reload
		echo "UFW berhasil di-reload."
	fi
else
	echo "WARNING: ufw binary tidak ditemukan in PATH. Pastikan UFW terpasang."
fi
