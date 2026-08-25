#!/usr/bin/env bash

# ##################################################
# ufw-ipset-blocklist-autoupdate
#
# Blocking lists of IPs from public blocklists / blacklists (e.g. blocklist.de, spamhaus.org)
#
# Version: 1.2.1
#
# MIT License
#
# Copyright (c) 2023 Niels Gandraß <niels@gandrass.de>
# Modifications (c) 2026 Harry DS Alsyundawy
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ##################################################

set -euo pipefail
IFS=$'\n\t'

# === Defaults and Configuration ===
IPSET_BIN="" # Detected dynamically
IPSET_DIR="/var/lib/ipset"
IPSET_PREFIX="bl"
IPSET_TYPE="hash:net"
DEFAULT_HASHSIZE=16384
DEFAULT_MAXELEM=1048576
IPV4=1
IPV6=1
QUIET=0
VERBOSE=0
declare -a BLOCKLISTS=()
TMP_DIR=""

# Regex definitions for IP matching
IPV4_REGEX="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(/[1-3]?[0-9])?"
IPV6_REGEX="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(/[1-6]?[0-9])?"

##
# Prints the help/usage message
##
print_usage() {
	cat <<EOF
Usage: $0 [-h] [-4] [-6] [-q] [-v] -l "name url" [-l ...]
Blocking lists of IPs from public blocklists / blacklists (e.g. blocklist.de, spamhaus.org)

Options:
  -l     : Blocklist to use. Can be specified multiple times.
           Format: "\$name \$url" (space-separated). See examples below.
  -4     : Run in IPv4 only mode. Ignore IPv6 addresses.
  -6     : Run in IPv6 only mode. Ignore IPv4 addresses.
  -q     : Quiet mode. Outputs are suppressed if flag is present.
  -v     : Verbose mode. Prints additional information during execution.
  -h     : Print this help message.

Example usage:
  $0 -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
  $0 -l "blocklist https://lists.blocklist.de/lists/all.txt" -l "spamhaus https://www.spamhaus.org/drop/drop.txt"
  $0 -l "spamhaus https://www.spamhaus.org/drop/drop.txt" -l "spamhaus6 https://www.spamhaus.org/drop/dropv6.txt"
EOF
}

##
# Logging functions
##
log() {
	if [[ ${QUIET} -eq 0 ]]; then
		printf '%s\n' "$1"
	fi
}

log_verbose() {
	if [[ ${VERBOSE} -eq 1 && ${QUIET} -eq 0 ]]; then
		printf '%s\n' "$1"
	fi
}

log_error() {
	printf '[ERROR]: %s\n' "$1" >&2
}

##
# Detects ipset binary
##
detect_ipset() {
	local bin
	bin="$(command -v ipset || true)"
	if [[ -z "${bin}" || ! -x "${bin}" ]]; then
		log_error "ipset binary not found in PATH or not executable."
		exit 1
	fi
	printf '%s' "${bin}"
}

##
# Validates the correctness of the BLOCKLISTS array
##
validate_blocklists() {
	if [[ ${#BLOCKLISTS[@]} -eq 0 ]]; then
		log_error "No blocklists given. Exiting..."
		print_usage
		exit 1
	fi

	for list in "${BLOCKLISTS[@]}"; do
		local list_name="${list%% *}"
		local list_url="${list#* }"

		if [[ -z "${list_name}" || "${list_name}" == "${list}" ]]; then
			log_error "Invalid name for list: ${list}"
			exit 1
		fi

		if [[ -z "${list_url}" ]]; then
			log_error "Invalid url for list: ${list}"
			exit 1
		fi

		# Check name length for ipset compatibility (max 31 characters total with prefix and suffix)
		# Prefix: bl- (3), suffix: -inet6-T (9) -> list name max 19 chars
		if ((${#list_name} > 19)); then
			log_error "List name '${list_name}' is too long (${#list_name} chars). Max 19 characters allowed."
			exit 1
		fi

		log_verbose "Found valid blocklist: name=${list_name}, url=${list_url}"
	done
}

##
# Downloads a file with wget or curl
##
download_file() {
	local url="$1"
	local destination="$2"

	if command -v wget >/dev/null 2>&1; then
		wget -q --timeout=30 --tries=3 -O "${destination}" "${url}"
	elif command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 30 --retry 3 -o "${destination}" "${url}"
	else
		log_error "Neither 'wget' nor 'curl' binary found for downloading."
		exit 1
	fi
}

##
# Updates an ipset based on a list of IP addresses
##
update_ipset() {
	local setname="$1"
	local ipfile="$2"
	local family="$3"

	local livelist="${setname}-${family}"
	local templist="${setname}-${family}-T"

	# Create sets if they do not exist
	"${IPSET_BIN}" create -! "${livelist}" "${IPSET_TYPE}" family "${family}" hashsize "${DEFAULT_HASHSIZE}" maxelem "${DEFAULT_MAXELEM}" 2>/dev/null || true
	"${IPSET_BIN}" create -! "${templist}" "${IPSET_TYPE}" family "${family}" hashsize "${DEFAULT_HASHSIZE}" maxelem "${DEFAULT_MAXELEM}" 2>/dev/null || true

	# Ensure temp set is flushed
	"${IPSET_BIN}" flush "${templist}" 2>/dev/null || true
	log_verbose "Prepared ipset lists: livelist='${livelist}', templist='${templist}'"

	local entry_count=0
	if [[ -s "${ipfile}" ]]; then
		awk -v setn="${templist}" '{print "add " setn " " $1}' "${ipfile}" | "${IPSET_BIN}" restore -! 2>/dev/null || true
		entry_count=$(wc -l <"${ipfile}" | tr -d ' ')
	fi

	"${IPSET_BIN}" swap "${templist}" "${livelist}" 2>/dev/null || true
	log_verbose "Swapped ipset: ${livelist}"
	"${IPSET_BIN}" destroy "${templist}" 2>/dev/null || true
	log_verbose "Destroyed temporary ipset: ${templist}"

	# Write ipset savefile
	"${IPSET_BIN}" save "${livelist}" >"${IPSET_DIR}/${livelist}.save"
	log_verbose "Wrote savefile for '${livelist}' to: ${IPSET_DIR}/${livelist}.save"
	log "Added ${entry_count} entries to ipset '${livelist}'"
}

##
# Updates the given blocklist from a URL
##
update_blocklist() {
	local name="$1"
	local url="$2"

	log "Updating blacklist '${name}' ..."
	log_verbose "Downloading blocklist '${name}' from: ${url} ..."

	local raw_file="${TMP_DIR}/blocklist.${name}.raw"
	download_file "${url}" "${raw_file}"

	if [[ ! -s "${raw_file}" ]]; then
		log_error "Blacklist '${name}' is empty or failed to download from ${url}."
		return 1
	fi

	local linecount
	linecount=$(wc -l <"${raw_file}" | tr -d ' ')
	if ((linecount < 1)); then
		log_error "Blacklist '${name}' contains 0 lines. Skipping..."
		return 1
	fi

	# Extract IPv4 addresses
	if [[ ${IPV4} -eq 1 ]]; then
		local filtered_ipv4="${TMP_DIR}/blocklist.${name}.ipv4"
		grep -v '^[#;]' "${raw_file}" | grep -E -o "${IPV4_REGEX}" | cut -d ' ' -f 1 | sort -u >"${filtered_ipv4}" || true
		local numips_v4
		numips_v4=$(wc -l <"${filtered_ipv4}" | tr -d ' ')
		log_verbose "Got ${numips_v4} IPv4 entries from blocklist '${name}'"

		if ((numips_v4 > 0)); then
			update_ipset "${IPSET_PREFIX}-${name}" "${filtered_ipv4}" "inet"
		else
			log_verbose "No IPv4 addresses found in blocklist '${name}'. Skipping IPv4."
		fi
	fi

	# Extract IPv6 addresses
	if [[ ${IPV6} -eq 1 ]]; then
		local filtered_ipv6="${TMP_DIR}/blocklist.${name}.ipv6"
		grep -v '^[#;]' "${raw_file}" | grep -E -o "${IPV6_REGEX}" | cut -d ' ' -f 1 | sort -u >"${filtered_ipv6}" || true
		local numips_v6
		numips_v6=$(wc -l <"${filtered_ipv6}" | tr -d ' ')
		log_verbose "Got ${numips_v6} IPv6 entries from blocklist '${name}'"

		if ((numips_v6 > 0)); then
			update_ipset "${IPSET_PREFIX}-${name}" "${filtered_ipv6}" "inet6"
		else
			log_verbose "No IPv6 addresses found in blocklist '${name}'. Skipping IPv6."
		fi
	fi
}

##
# Main function
##
main() {
	if [[ ${EUID} -ne 0 ]]; then
		log_error "Script must be run as root."
		exit 1
	fi

	validate_blocklists
	IPSET_BIN="$(detect_ipset)"
	mkdir -p "${IPSET_DIR}"

	# Setup atomic temporary directory with cleanup trap
	TMP_DIR="$(mktemp -d "/tmp/ufw-blocklist.XXXXXXXX")"
	trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM HUP

	for list in "${BLOCKLISTS[@]}"; do
		local list_name="${list%% *}"
		local list_url="${list#* }"
		update_blocklist "${list_name}" "${list_url}" || true
	done

	log "All blocklists processed successfully."
}

# === Argument Parsing ===
while getopts ":hqv46l:" opt; do
	case "${opt}" in
	l)
		BLOCKLISTS+=("${OPTARG}")
		;;
	4)
		IPV4=1
		IPV6=0
		log "Using IPv4 only mode. Skipping IPv6 addresses."
		;;
	6)
		IPV4=0
		IPV6=1
		log "Using IPv6 only mode. Skipping IPv4 addresses."
		;;
	q)
		QUIET=1
		;;
	v)
		VERBOSE=1
		;;
	h)
		print_usage
		exit 0
		;;
	:)
		log_error "Option -${OPTARG} requires an argument."
		print_usage
		exit 1
		;;
	\? | *)
		log_error "Invalid option -${OPTARG}."
		print_usage
		exit 1
		;;
	esac
done

# Execute main
main
