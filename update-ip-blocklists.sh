#!/bin/bash

# Variables
IPSET_BIN="/usr/bin/ipset"
IPSET_DIR="/var/lib/ipset"
IPSET_PREFIX="bl"
IPSET_TYPE="hash:net"
IPV4=1
IPV6=1
QUIET=0
VERBOSE=0
declare -A BLOCKLISTS

# Function to print usage message
print_usage() {
    cat << EOF
Usage: $0 [-h]
Blocking lists of IPs from public blocklists / blacklists (e.g. blocklist.de, spamhaus.org)

Options:
  -l     : Blocklist to use. Can be specified multiple times. Format: "\$name \$url"
  -4     : Run in IPv4 only mode. Ignore IPv6 addresses.
  -6     : Run in IPv6 only mode. Ignore IPv4 addresses.
  -q     : Quiet mode. Outputs are suppressed if flag is present.
  -v     : Verbose mode. Prints additional information during execution.
  -h     : Print this help message.
EOF
}

# Function to log messages
log() {
    [[ $QUIET -eq 0 ]] && echo "$1"
}

# Function to log verbose messages
log_verbose() {
    [[ $VERBOSE -eq 1 && $QUIET -eq 0 ]] && echo "$1"
}

# Function to log errors
log_error() {
    >&2 echo "[ERROR]: $1"
}

# Function to detect ipset binary
detect_ipset() {
    local IPSET_BIN=$(which ipset)
    [[ ! -x "${IPSET_BIN}" ]] && { log_error "ipset binary not found."; exit 1; }
    echo "${IPSET_BIN}"
}

# Function to validate blocklists
validate_blocklists() {
    [[ ${#BLOCKLISTS[@]} -eq 0 ]] && { log_error "No blocklists given. Exiting..."; print_usage; exit 1; }

    for list in "${BLOCKLISTS[@]}"; do
        local list_name=$(echo "$list" | cut -d ' ' -f 1)
        local list_url=$(echo "$list" | cut -d ' ' -f 2)

        [[ -z "$list_name" || -z "$list_url" ]] && { log_error "Invalid name or URL for list: $list"; exit 1; }

        log_verbose "Found valid blocklist: name=${list_name}, url=${list_url}"
    done
}

# Function to update an ipset based on a list of IP addresses
update_ipset() {
    local setname=$1
    local ipfile=$2
    local family=$3

    local livelist="$setname-$family"
    local templist="$setname-$family-T"

    $IPSET_BIN create -q "$livelist" "$IPSET_TYPE" family $family
    $IPSET_BIN create -q "$templist" "$IPSET_TYPE" family $family

    log_verbose "Prepared ipset lists: livelist='$livelist', templist='$templist'"

    while read -r ip; do
        if $IPSET_BIN add "$templist" "$ip"; then
            log_verbose "Added '$ip' to '$templist'"
        else
            log "Failed to add '$ip' to '$templist'"
        fi
    done < "$ipfile"

    $IPSET_BIN swap "$templist" "$livelist"
    log_verbose "Swapped ipset: $livelist"
    $IPSET_BIN destroy "$templist"
    log_verbose "Destroyed ipset: $templist"

    $IPSET_BIN save "$livelist" > "$IPSET_DIR/$livelist.save"
    log_verbose "Wrote savefile for '$livelist' to: $IPSET_DIR/$livelist.save"
    log "Added $(cat "$ipfile" | wc -l) to ipset '$livelist'"
}

# Function to update a blocklist from a URL
update_blocklist() {
    local list_name=$1
    local list_url=$2

    log "Updating blacklist '$list_name' ..."
    log_verbose "Downloading blocklist '$list_name' from: $list_url ..."
    local tempfile=$(mktemp "/tmp/blocklist.$list_name.XXXXXXXX")
    wget -q -O "$tempfile" "$list_url"

    linecount=$(cat "$tempfile" | wc -l)
    [[ $linecount -lt 10 ]] && { log_error "Blacklist '$list_name' contains only $linecount lines. Exiting..."; exit 1; }

    if [[ $IPV4 -eq 1 ]]; then
        grep -v '^[#;]' "$tempfile" | grep -E -o "$IPV4_REGEX" | cut -d ' ' -f 1 > "$tempfile.filtered"
        local numips=$(cat "$tempfile.filtered" | wc -l)

        log_verbose "Got $numips IPv4 entries from blocklist '$list_name'"

        [[ $numips -gt 0 ]] && update_ipset "${IPSET_PREFIX}-$list_name" "$tempfile.filtered" "inet"
    fi

    if [[ $IPV6 -eq 1 ]]; then
        grep -v '^[#;]' "$tempfile" | grep -E -o "$IPV6_REGEX" | cut -d ' ' -f 1 > "$tempfile.filtered6"
        local numips=$(cat "$tempfile.filtered6" | wc -l)

        log_verbose "Got $numips IPv6 entries from blocklist '$list_name'"

        [[ $numips -gt 0 ]] && update_ipset "${IPSET_PREFIX}-$list_name" "$tempfile.filtered6" "inet6"
    fi

    rm "$tempfile"*
}

# Main program loop
main() {
    validate_blocklists
    IPSET_BIN=$(detect_ipset)
    mkdir -p "${IPSET_DIR}"

    for list in "${BLOCKLISTS[@]}"; do
        local list_name=$(echo "$list" | cut -d ' ' -f 1)
        local list_url=$(echo "$list" | cut -d ' ' -f 2)

        update_blocklist "$list_name" "$list_url"
    done
}

# Parse arguments
while getopts ":hqv46l:" opt; do
    case ${opt} in
        l) BLOCKLISTS[${#BLOCKLISTS[@]}]=${OPTARG}
            ;;
        4) IPV4=1; IPV6=0; log "Using IPv4 only mode. Skipping IPv6 addresses."
            ;;
        6) IPV4=0; IPV6=1; log "Using IPv6 only mode. Skipping IPv4 addresses."
            ;;
        q) QUIET=1
            ;;
        v) VERBOSE=1
            ;;
        h) print_usage; exit
            ;;
        :) print_usage; exit
            ;;
        \? ) print_usage; exit
            ;;
    esac
done

# Entry point
main

