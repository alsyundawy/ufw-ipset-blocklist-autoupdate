#!/bin/bash
# Script: blocklist-auto-update.sh
# Deskripsi: Instalasi dan konfigurasi otomatis blocklist + penjadwalan cron

set -e  # Hentikan skrip jika terjadi error

# Cek izin root
if [ "$(id -u)" != "0" ]; then
   echo "Harap jalankan sebagai root: sudo $0" >&2
   exit 1
fi

# Deteksi distribusi
if [ -f /etc/debian_version ]; then
    OS="debian"
elif [ -f /etc/redhat-release ]; then
    OS="rhel"
else
    echo "Distribusi tidak didukung!"
    exit 1
fi

# Instal dependensi
echo "Menginstal dependensi..."
if [ "$OS" = "debian" ]; then
    apt update && apt install -y git iptables ufw ipset
elif [ "$OS" = "rhel" ]; then
    yum install -y epel-release
    yum install -y git iptables-services ufw ipset
    systemctl enable iptables && systemctl start iptables
fi

# Konfigurasi repository
echo "Mengkonfigurasi repository..."
DIR="/opt/ufw-ipset-blocklist-autoupdate"
if [ ! -d "$DIR" ]; then
    git clone https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate.git $DIR
else
    cd $DIR && git pull origin main
fi

# Jalankan setup awal
echo "Menjalankan setup awal..."
cd $DIR
bash setup-ufw.sh

# Update blocklist pertama kali
echo "Memperbarui blocklist..."
bash update-ip-blocklists.sh \
  -l "blocklist https://lists.blocklist.de/lists/all.txt" \
  -l "spamhaus https://www.spamhaus.org/drop/drop.txt" \
  -l "bdsatib https://www.binarydefense.com/banlist.txt" \
  -l "ipsum https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt" \
  -l "greensnow https://blocklist.greensnow.co/greensnow.txt" \
  -l "cnisarmy http://cinsscore.com/list/ci-badguys.txt" \
  -l "bfblocker https://danger.rulez.sk/projects/bruteforceblocker/blist.php"

# Konfigurasi cron harian
echo "Mengatur cron job harian..."
CRON_JOB="0 2 * * * root cd $DIR && bash update-ip-blocklists.sh -l ... >/dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "update-ip-blocklists.sh"; echo "$CRON_JOB") | crontab -

echo "Instalasi selesai! Blocklist akan diperbarui harian pukul 02:00"
