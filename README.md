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

## Jumlah Bintang Seiring Waktu
[![Stargazers over time](https://starchart.cc/alsyundawy/ufw-ipset-blocklist-autoupdate.svg?variant=adaptive)](https://starchart.cc/alsyundawy/ufw-ipset-blocklist-autoupdate)

**Jika proyek ini bermanfaat bagi Anda, silakan pertimbangkan untuk berdonasi melalui [PayPal](https://www.paypal.me/alsyundawy). Terima kasih atas dukungan Anda!**

## Tentang Proyek

Koleksi skrip ini secara otomatis mengambil daftar blokir IP (misalnya Spamhaus, Blocklist, dll.) dan menolak paket dari alamat IP yang terdaftar. Skrip ini terintegrasi dengan firewall sederhana (`ufw`) dan menggunakan `ipset` untuk menyimpan alamat IP serta rentang jaringan. Mendukung daftar blokir IPv4 dan IPv6.

## Instalasi

1. Instal `ufw` dan `ipset`.
2. Jalankan skrip `setup-ufw.sh`:  
   ```sh
   ./setup-ufw.sh
   ```
3. Tentukan daftar blokir yang ingin digunakan.
4. Unduh daftar blokir awal:
   ```sh
   ./update-ip-blocklists.sh -l "blocklist https://lists.blocklist.de/lists/all.txt" -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
   ```
5. Tambahkan `update-ip-blocklists.sh` ke `crontab` untuk pembaruan otomatis:
   ```sh
   @daily /path/to/update-ip-blocklists.sh -l "blocklist https://lists.blocklist.de/lists/all.txt" -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
   ```

## Penggunaan

```sh
Usage: ./update-ip-blocklists.sh [-h]
Memblokir daftar IP dari sumber blocklist/blacklist publik (misalnya blocklist.de, spamhaus.org)

Opsi:
  -l     : Daftar blokir yang digunakan. Bisa ditentukan lebih dari sekali.
           Format: "$name $url" (dipisahkan oleh spasi). Lihat contoh di bawah.
  -4     : Hanya untuk IPv4. Mengabaikan alamat IPv6.
  -6     : Hanya untuk IPv6. Mengabaikan alamat IPv4.
  -q     : Mode senyap. Tidak menampilkan output jika opsi ini digunakan.
  -v     : Mode verbose. Menampilkan informasi tambahan selama eksekusi.
  -h     : Menampilkan pesan bantuan.

Contoh penggunaan:
./update-ip-blocklists.sh -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
./update-ip-blocklists.sh -l "blocklist https://lists.blocklist.de/lists/all.txt" -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
./update-ip-blocklists.sh -l "spamhaus https://www.spamhaus.org/drop/drop.txt" -l "spamhaus6 https://www.spamhaus.org/drop/dropv6.txt"
```

## Komponen

- `update-ip-blocklist.sh`: Mengunduh versi terbaru dari daftar blokir, memperbarui ipset, dan mengekspor ipset ke `$IPSET_DIR` (default: `/var/lib/ipset`).
- `ufw/after.init`: Menyisipkan dan menghapus aturan `iptables` yang diperlukan saat `ufw` dimuat ulang.
- `setup-ufw.sh`: Skrip bantu untuk menerapkan `ufw/after.init`.

## Daftar Blokir yang Didukung

Skrip ini dapat membaca semua daftar blokir yang mencantumkan alamat IPv4 atau IPv6 dengan format teks biasa per baris. Beberapa daftar blokir yang dapat digunakan:

- **Spamhaus DROP List**  
  ```sh
  -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
  ```
- **Blocklist.de (Semua Laporan Fail2Ban)**  
  ```sh
  -l "blocklist https://lists.blocklist.de/lists/all.txt"
  ```
- **FireHOL Level 1**  
  ```sh
  -l "firehol1 https://iplists.firehol.org/files/firehol_level1.netset"
  ```
- **Binary Defense Systems Banlist**  
  ```sh
  -l "bdsatib https://www.binarydefense.com/banlist.txt"
  ```

## Penghargaan

Proyek ini terinspirasi dari [blog Xela's Linux](https://spielwiese.la-evento.com/xelasblog/archives/74-Ipset-aus-der-Spamhaus-DROP-gemeinsam-mit-ufw-nutzen.html).

---

## **Anda Luar Biasa | ༺ Harry DS Alsyundawy ༻**
## **"Hanya Saya, Diri Saya, dan Saya Sendiri. Tidak Ada yang Sempurna."**

---

## Statistik GitHub

![Alt](https://repobeats.axiom.co/api/embed/96c0ae9c24279dc7c5da425f07426f78c35a3cc9.svg "Repobeats analytics image")
