#!/bin/bash

# Set mode error handling
set -euo pipefail

# Variabel
UFW_CONF_DIR="/etc/ufw"
UFW_AFTER_INIT_FILE="$UFW_CONF_DIR/after.init"
IPSET_DIR="/var/lib/ipset"
CONFIGURE_IPV6=0

# Fungsi untuk menangani input pengguna
process_input() {
    local prompt="$1"
    local default_choice="${2:-Y}"  # Default jawaban adalah 'Y' jika tidak diberikan
    read -r -p "$prompt [$default_choice]: " response
    response="${response:-$default_choice}"  # Gunakan default jika tidak ada input
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Konfirmasi konfigurasi UFW dengan blocklist
process_input "Configure UFW to block IPs listed in blocklist ipsets?" || exit 0

# Konfirmasi apakah ingin mengaktifkan IPv6
if process_input "Would you like to enable IPv6 support?" ; then
    CONFIGURE_IPV6=1
fi

# Pastikan direktori IPSET tersedia
mkdir -p "$IPSET_DIR"

# Periksa apakah IPv6 diaktifkan dalam konfigurasi UFW
if [[ "$CONFIGURE_IPV6" == 1 ]]; then
    if ! grep -qE "^IPV6=(yes|YES)$" /etc/default/ufw; then
        echo "IPv6 belum dikonfigurasi di UFW. Memperbaiki konfigurasi..."
        sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
        echo "Konfigurasi IPv6 telah diperbarui ke 'yes'."
    fi
fi

# Periksa apakah file after.init sudah ada
if [[ -f "$UFW_AFTER_INIT_FILE" ]]; then
    if ! process_input "The file $UFW_AFTER_INIT_FILE already exists. Overwrite?" "N"; then
        exit 0
    fi
fi

# Salin konfigurasi after.init yang sesuai dengan IPv6
cp "ufw/after${CONFIGURE_IPV6:+6}.init" "$UFW_AFTER_INIT_FILE"
chmod 755 "$UFW_AFTER_INIT_FILE"
echo "Deployed $UFW_AFTER_INIT_FILE"

# Reload UFW jika diminta
if process_input "Reload UFW to apply changes?"; then
    ufw reload
    echo "UFW berhasil di-reload."
fi
