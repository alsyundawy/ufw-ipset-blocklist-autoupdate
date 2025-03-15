#!/bin/bash

# Set mode error handling
set -euo pipefail

# Variabel
IPSET_BIN="/usr/sbin/ipset"
IPSET_DIR="/var/lib/ipset"
IPSET_PREFIX="bl"
IPSET_TYPE="hash:net"
IPV4=1
IPV6=1
QUIET=0
VERBOSE=0
declare -A BLOCKLISTS

# Fungsi untuk menampilkan bantuan
print_usage() {
    cat << EOF
Usage: $0 [-h]
Blocking lists of IPs from public blocklists (e.g., blocklist.de, spamhaus.org)

Options:
  -l     : Blocklist yang digunakan. Bisa dipanggil berkali-kali. Format: "\$name \$url"
  -4     : Mode hanya IPv4. Abaikan alamat IPv6.
  -6     : Mode hanya IPv6. Abaikan alamat IPv4.
  -q     : Mode diam. Tidak menampilkan output jika flag ini diaktifkan.
  -v     : Mode verbose. Menampilkan informasi tambahan selama eksekusi.
  -h     : Menampilkan pesan bantuan ini.
EOF
}

# Fungsi logging
log() {
    [[ $QUIET -eq 0 ]] && echo "$1"
}

log_verbose() {
    [[ $VERBOSE -eq 1 && $QUIET -eq 0 ]] && echo "$1"
}

log_error() {
    >&2 echo "[ERROR]: $1"
}

# Fungsi untuk mendeteksi ipset
detect_ipset() {
    if ! command -v ipset &>/dev/null; then
        log_error "ipset binary not found."
        exit 1
    fi
}

# Fungsi validasi blocklists
validate_blocklists() {
    if [[ ${#BLOCKLISTS[@]} -eq 0 ]]; then
        log_error "No blocklists given. Exiting..."
        print_usage
        exit 1
    fi
}

# Fungsi memperbarui ipset dari daftar IP
update_ipset() {
    local setname=$1
    local ipfile=$2
    local family=$3

    local livelist="${setname}-${family}"
    local templist="${setname}-${family}-T"

    $IPSET_BIN create -q "$livelist" "$IPSET_TYPE" family $family || true
    $IPSET_BIN create -q "$templist" "$IPSET_TYPE" family $family || true

    log_verbose "Prepared ipset lists: livelist='$livelist', templist='$templist'"

    while read -r ip; do
        $IPSET_BIN add "$templist" "$ip" 2>/dev/null && log_verbose "Added '$ip' to '$templist'"
    done < "$ipfile"

    $IPSET_BIN swap "$templist" "$livelist"
    log_verbose "Swapped ipset: $livelist"
    $IPSET_BIN destroy "$templist"
    log_verbose "Destroyed ipset: $templist"

    $IPSET_BIN save "$livelist" > "$IPSET_DIR/$livelist.save"
    log_verbose "Wrote savefile for '$livelist' to: $IPSET_DIR/$livelist.save"
    log "Added $(wc -l < "$ipfile") to ipset '$livelist'"
}

# Fungsi memperbarui daftar blocklist
update_blocklist() {
    local list_name=$1
    local list_url=$2

    log "Updating blacklist '$list_name' ..."
    log_verbose "Downloading blocklist '$list_name' from: $list_url ..."

    local tempfile
    tempfile=$(mktemp "/tmp/blocklist.${list_name}.XXXXXXXX")

    wget -q -O "$tempfile" "$list_url"

    local linecount
    linecount=$(wc -l < "$tempfile")

    if [[ $linecount -lt 10 ]]; then
        log_error "Blacklist '$list_name' contains only $linecount lines. Exiting..."
        exit 1
    fi

    # Filter IPv4
    if [[ $IPV4 -eq 1 ]]; then
        grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$tempfile" > "${tempfile}.filtered"
        local numips
        numips=$(wc -l < "${tempfile}.filtered")

        log_verbose "Got $numips IPv4 entries from blocklist '$list_name'"

        [[ $numips -gt 0 ]] && update_ipset "${IPSET_PREFIX}-${list_name}" "${tempfile}.filtered" "inet"
    fi

    # Filter IPv6
    if [[ $IPV6 -eq 1 ]]; then
        grep -Eo '([a-fA-F0-9:]+:+)+[a-fA-F0-9]+' "$tempfile" > "${tempfile}.filtered6"
        local numips6
        numips6=$(wc -l < "${tempfile}.filtered6")

        log_verbose "Got $numips6 IPv6 entries from blocklist '$list_name'"

        [[ $numips6 -gt 0 ]] && update_ipset "${IPSET_PREFIX}-${list_name}" "${tempfile}.filtered6" "inet6"
    fi

    rm -f "$tempfile"*
}

# Fungsi utama
main() {
    detect_ipset
    validate_blocklists
    mkdir -p "${IPSET_DIR}"

    for list in "${BLOCKLISTS[@]}"; do
        IFS=' ' read -r list_name list_url <<< "$list"
        update_blocklist "$list_name" "$list_url"
    done
}

# Parsing argumen
while getopts ":hqv46l:" opt; do
    case ${opt} in
        l) BLOCKLISTS[${#BLOCKLISTS[@]}]="${OPTARG}" ;;
        4) IPV4=1; IPV6=0; log "Using IPv4 only mode." ;;
        6) IPV4=0; IPV6=1; log "Using IPv6 only mode." ;;
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        h) print_usage; exit ;;
        :) print_usage; exit ;;
        \? ) print_usage; exit ;;
    esac
done

# Jalankan skrip utama
main
