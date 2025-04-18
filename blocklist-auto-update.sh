#!/bin/bash
# Script: blocklist-auto-update.sh
# Deskripsi: Instalasi dan konfigurasi otomatis blocklist, penjadwalan cron,
#            serta memastikan UFW mendukung IPv6 dengan benar.

set -euo pipefail  # Aktifkan strict mode

# Fungsi untuk logging yang konsisten
log() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1"
}

# 1. Pastikan script dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    log "Harap jalankan sebagai root: sudo $0" >&2
    exit 1
fi

# 2. Tentukan direktori instalasi repository
DIR="/root/ufw-ipset-blocklist-autoupdate"

# 3. Deteksi distribusi dan instal dependensi
log "Mendeteksi sistem operasi..."
if [ -f /etc/debian_version ]; then
    OS="debian"
    INSTALL_CMD="apt-get update -qq && apt-get install -y -qq"
elif [ -f /etc/redhat-release ]; then
    OS="rhel"
    INSTALL_CMD="yum install -y -q"
else
    log "Distribusi tidak didukung!" >&2
    exit 1
fi

log "Menginstal dependensi..."
if [ "$OS" = "debian" ]; then
    $INSTALL_CMD git iptables ufw ipset dos2unix
elif [ "$OS" = "rhel" ]; then
    $INSTALL_CMD epel-release
    $INSTALL_CMD git iptables-services ufw ipset dos2unix
    systemctl enable --now iptables
fi

# 4. Konfigurasi repository blocklist
log "Mengkonfigurasi repository..."
if [ ! -d "$DIR" ]; then
    git clone --depth 1 https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate.git "$DIR"
else
    (cd "$DIR" && git pull --quiet origin master)
fi

# 5. Pastikan konfigurasi IPv6 benar
log "Memastikan konfigurasi IPv6 di /etc/default/ufw..."
if [ -f /etc/default/ufw ]; then
    # Ubah format file ke Unix dan konfigurasikan IPv6
    dos2unix -q /etc/default/ufw 2>/dev/null || true
    sed -i 's/^[[:space:]]*IPV6=no.*$/IPV6=yes/' /etc/default/ufw
    
    # Tambahkan IPV6=yes jika tidak ada
    if ! grep -q "^IPV6=yes" /etc/default/ufw; then
        echo "IPV6=yes" >> /etc/default/ufw
    fi
fi

# 6. Restart UFW agar konfigurasi baru diterapkan
log "Melakukan restart UFW..."
ufw --force disable
ufw --force enable

# 7. Verifikasi konfigurasi IPv6
if grep -q "^IPV6=yes" /etc/default/ufw; then
    log "Konfigurasi IPv6 sudah aktif."
else
    log "Error: IPv6 belum dikonfigurasi dengan benar di /etc/default/ufw." >&2
    exit 1
fi

# 8. Jalankan setup awal UFW dari repository
log "Menjalankan setup awal UFW..."
(cd "$DIR" && bash setup-ufw.sh)

# 9. Daftar sumber blocklist
BLOCKLISTS=(
    "blocklist https://lists.blocklist.de/lists/all.txt"
    "spamhaus https://www.spamhaus.org/drop/drop.txt"
    "bdsatib https://www.binarydefense.com/banlist.txt"
    "ipsum https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"
    "greensnow https://blocklist.greensnow.co/greensnow.txt"
    "cnisarmy http://cinsscore.com/list/ci-badguys.txt"
    "feodoc2ioc https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
    "sefinek https://raw.githubusercontent.com/sefinek/Malicious-IP-Addresses/main/lists/main.txt"
)

# Membuat parameter command line
BLOCKLIST_ARGS=""
for list in "${BLOCKLISTS[@]}"; do
    BLOCKLIST_ARGS+=" -l \"$list\""
done

# 10. Update blocklist pertama kali
log "Memperbarui blocklist..."
(cd "$DIR" && bash update-ip-blocklists.sh $BLOCKLIST_ARGS)

# 11. Atur cron job harian untuk update blocklist
log "Mengatur cron job harian..."
CRON_FILE="/etc/cron.d/blocklist-update"
echo "0 2 * * * root cd $DIR && bash update-ip-blocklists.sh $BLOCKLIST_ARGS >/dev/null 2>&1" > "$CRON_FILE"
chmod 644 "$CRON_FILE"

log "Instalasi selesai! Blocklist akan diperbarui setiap hari pukul 02:00."
