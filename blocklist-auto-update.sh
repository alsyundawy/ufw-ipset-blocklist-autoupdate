#!/bin/bash
# Script: blocklist-auto-update.sh
# Deskripsi: Instalasi dan konfigurasi otomatis blocklist, penjadwalan cron,
#            serta memastikan UFW mendukung IPv6 dengan benar.
#
# Catatan:
# - Script ini memastikan file /etc/default/ufw berisi "IPV6=yes" (tanpa spasi atau CRLF).
# - UFW dinonaktifkan dan diaktifkan ulang agar konfigurasi baru diterapkan.
# - Setelah konfigurasi IPv6 diverifikasi, script akan melanjutkan setup awal UFW.

set -euo pipefail  # Aktifkan strict mode

# 1. Pastikan script dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    echo "Harap jalankan sebagai root: sudo $0" >&2
    exit 1
fi

# 2. Tentukan direktori instalasi repository
if [ "$(id -u)" -eq 0 ]; then
    DIR="/root/ufw-ipset-blocklist-autoupdate"
else
    DIR="$HOME/ufw-ipset-blocklist-autoupdate"
fi

# 3. Deteksi distribusi (Debian atau RHEL) dan instal dependensi
if [ -f /etc/debian_version ]; then
    OS="debian"
elif [ -f /etc/redhat-release ]; then
    OS="rhel"
else
    echo "Distribusi tidak didukung!" >&2
    exit 1
fi

echo "Menginstal dependensi..."
if [ "$OS" = "debian" ]; then
    apt update && apt install -y git iptables ufw ipset dos2unix
elif [ "$OS" = "rhel" ]; then
    yum install -y epel-release
    yum install -y git iptables-services ufw ipset dos2unix
    systemctl enable iptables && systemctl start iptables
fi

# 4. Konfigurasi repository blocklist
echo "Mengkonfigurasi repository..."
if [ ! -d "$DIR" ]; then
    git clone https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate.git "$DIR"
else
    (cd "$DIR" && git pull origin master)
fi

# 5. Pastikan file /etc/default/ufw mengandung "IPV6=yes" tanpa karakter ekstra
echo "Memastikan konfigurasi IPv6 di /etc/default/ufw..."
if [ -f /etc/default/ufw ]; then
    # Jika dos2unix tersedia, gunakan untuk mengubah format file ke Unix
    if command -v dos2unix >/dev/null 2>&1; then
         dos2unix /etc/default/ufw
    fi
    # Ganti baris "IPV6=no" (jika ada) dengan "IPV6=yes" dan hapus spasi ekstra
    sed -i 's/^[[:space:]]*IPV6=no[[:space:]]*$/IPV6=yes/' /etc/default/ufw
fi

# 6. Restart UFW agar konfigurasi baru diterapkan
echo "Melakukan restart UFW..."
ufw disable
ufw enable

# 7. Verifikasi konfigurasi IPv6
if grep -q "^IPV6=yes" /etc/default/ufw; then
    echo "Konfigurasi IPV6 sudah aktif."
else
    echo "Error: IPV6 belum dikonfigurasi dengan benar di /etc/default/ufw." >&2
    exit 1
fi

# 8. Jalankan setup awal UFW dari repository
echo "Menjalankan setup awal UFW..."
(cd "$DIR" && bash setup-ufw.sh)

# 9. Update blocklist pertama kali
echo "Memperbarui blocklist..."
(cd "$DIR" ;bash update-ip-blocklists.sh -l "blocklist https://lists.blocklist.de/lists/all.txt" -l "spamhaus https://www.spamhaus.org/drop/drop.txt" -l "bdsatib https://www.binarydefense.com/banlist.txt" -l "ipsum https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt" -l "greensnow https://blocklist.greensnow.co/greensnow.txt" -l "cnisarmy http://cinsscore.com/list/ci-badguys.txt" -l "feodoc2ioc https://feodotracker.abuse.ch/downloads/ipblocklist.txt" -l "spamhausex https://www.spamhaus.org/drop/edrop.txt")

# 10. Atur cron job harian untuk update blocklist
echo "Mengatur cron job harian..."
CRON_JOB="0 2 * * * root cd $DIR && bash update-ip-blocklists.sh -l ... >/dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "update-ip-blocklists.sh"; echo "$CRON_JOB") | crontab -

echo "Instalasi selesai! Blocklist akan diperbarui setiap hari pukul 02:00."
