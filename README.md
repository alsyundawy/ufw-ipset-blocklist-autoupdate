# UFW IPSet Blocklist AutoUpdate

[![Versi Terbaru](https://img.shields.io/github/v/release/alsyundawy/ufw-ipset-blocklist-autoupdate)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/releases)
[![Status Pemeliharaan](https://img.shields.io/maintenance/yes/9999)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/)
[![Lisensi](https://img.shields.io/github/license/alsyundawy/ufw-ipset-blocklist-autoupdate)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/blob/master/LICENSE)
[![Masalah GitHub](https://img.shields.io/github/issues/alsyundawy/ufw-ipset-blocklist-autoupdate)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/issues)
[![Pull Requests GitHub](https://img.shields.io/github/issues-pr/alsyundawy/ufw-ipset-blocklist-autoupdate)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/pulls)
[![Donasi dengan PayPal](https://img.shields.io/badge/PayPal-donate-orange)](https://www.paypal.me/alsyundawy)
[![Sponsor dengan GitHub](https://img.shields.io/badge/GitHub-sponsor-orange)](https://github.com/sponsors/alsyundawy)
[![Bintang GitHub](https://img.shields.io/github/stars/alsyundawy/ufw-ipset-blocklist-autoupdate?style=social)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/stargazers)
[![Fork GitHub](https://img.shields.io/github/forks/alsyundawy/ufw-ipset-blocklist-autoupdate?style=social)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/network/members)
[![Kontributor GitHub](https://img.shields.io/github/contributors/alsyundawy/ufw-ipset-blocklist-autoupdate?style=social)](https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate/graphs/contributors)

## Overview

Koleksi skrip ini secara otomatis mengambil daftar blokir IP (misalnya Spamhaus, Blocklist, dll.) dan menolak paket dari alamat IP yang terdaftar. Skrip ini terintegrasi dengan firewall sederhana (`ufw`) dan menggunakan `ipset` untuk menyimpan alamat IP serta rentang jaringan. Mendukung daftar blokir IPv4 dan IPv6.

Sangat ideal untuk memproteksi server email (**Zimbra Collaboration Suite**, Postfix, Dovecot) dan server aplikasi web dari serangan brute-force, botnet C2, dan spam di tingkat kernel Netfilter $O(1)$.

## Dependencies

Pastikan sistem Anda memiliki paket dependensi berikut terpasang:

- `bash` (versi 4.0 atau lebih baru)
- `ufw`
- `ipset`
- `iptables` / `ip6tables`
- `wget` atau `curl`

Pada Debian / Ubuntu:

```sh
apt-get update && apt-get install -y ufw ipset iptables wget git
```

Pada RHEL / CentOS / Rocky Linux / AlmaLinux:

```sh
yum install -y epel-release && yum install -y ufw ipset iptables-services wget git
```

## Quickstart

1. Clone repositori:

   ```sh
   git clone https://github.com/alsyundawy/ufw-ipset-blocklist-autoupdate.git /root/ufw-ipset-blocklist-autoupdate
   cd /root/ufw-ipset-blocklist-autoupdate
   ```

2. Jalankan skrip setup UFW:

   ```sh
   ./setup-ufw.sh
   ```

3. Unduh dan inisialisasi daftar blokir awal:

   ```sh
   ./update-ip-blocklists.sh -l "blocklist https://lists.blocklist.de/lists/all.txt" -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
   ```

4. Tambahkan pembaruan otomatis ke Cron:

   ```sh
   ./blocklist-auto-update.sh
   ```

## Configuration

### Penggunaan CLI `update-ip-blocklists.sh`

```sh
Usage: ./update-ip-blocklists.sh [-h] [-4] [-6] [-q] [-v] -l "name url" [-l ...]

Options:
  -l     : Daftar blokir yang digunakan (format: "$name $url").
  -4     : Hanya untuk IPv4. Mengabaikan alamat IPv6.
  -6     : Hanya untuk IPv6. Mengabaikan alamat IPv4.
  -q     : Mode senyap (suppress standard output).
  -v     : Mode verbose (tampilkan informasi rinci).
  -h     : Tampilkan bantuan.
```

### Contoh Konfigurasi Sumber Blocklist

```sh
./update-ip-blocklists.sh -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
./update-ip-blocklists.sh -l "blocklist https://lists.blocklist.de/lists/all.txt" -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
./update-ip-blocklists.sh -l "spamhaus https://www.spamhaus.org/drop/drop.txt" -l "spamhaus6 https://www.spamhaus.org/drop/dropv6.txt"
```

## Running Tests

Untuk memvalidasi sintaksis dan kepatuhan ShellCheck:

```sh
shellcheck --norc *.sh ufw/*
for f in *.sh ufw/*; do bash -n "$f"; done
```

## Daftar Blokir yang Didukung

- [Binary Defense Systems Artillery Threat Intelligence Banlist](https://www.binarydefense.com):
  `-l "bdsatib https://www.binarydefense.com/banlist.txt"`
- [Blocklist.de Fail2Ban Reporting (all)](https://www.blocklist.de/en/export.html):
  `-l "blocklist https://lists.blocklist.de/lists/all.txt"`
- [BruteForceBlocker](https://danger.rulez.sk/index.php/bruteforceblocker/):
  `-l "bfblocker https://danger.rulez.sk/projects/bruteforceblocker/blist.php"`
- [CINS Army List](http://www.ciarmy.com/#list):
  `-l "cnisarmy http://cinsscore.com/list/ci-badguys.txt"`
- [FEODO Tracker: Botnet C2 (Recommended)](https://feodotracker.abuse.ch/blocklist/):
  `-l "feodoc2 https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt"`
- [FireHOL IP List Level 1](https://iplists.firehol.org/):
  `-l "firehol1 https://iplists.firehol.org/files/firehol_level1.netset"`
- [GreenSnow](https://greensnow.co/):
  `-l "greensnow https://blocklist.greensnow.co/greensnow.txt"`
- [IPsum](https://github.com/stamparm/ipsum):
  `-l "ipsum https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"`
- [Spamhaus Don't Route Or Peer List (DROP)](https://www.spamhaus.org/drop/):
  `-l "spamhaus https://www.spamhaus.org/drop/drop.txt"`
- [Spamhaus IPv6 DROP List (DROPv6)](https://www.spamhaus.org/drop/):
  `-l "spamhaus6 https://www.spamhaus.org/drop/dropv6.txt"`

## Contributing

Kontribusi selalu terbuka! Silakan kirimkan Pull Request atau laporkan bug melalui GitHub Issues.

## License

Proyek ini dilisensikan di bawah [MIT License](file:///Users/alsyundawy/Downloads/GitHub/ufw-ipset-blocklist-autoupdate/LICENSE).

---

## Penghargaan

Proyek ini terinspirasi dari [blog Xela's Linux](https://spielwiese.la-evento.com/xelasblog/archives/74-Ipset-aus-der-Spamhaus-DROP-gemeinsam-mit-ufw-nutzen.html).
