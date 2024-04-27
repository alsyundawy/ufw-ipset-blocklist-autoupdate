#!/bin/bash

# Variables
UFW_CONF_DIR="/etc/ufw"
UFW_AFTER_INIT_FILE="$UFW_CONF_DIR/after.init"
IPSET_DIR="/var/lib/ipset"
CONFIGURE_IPV6=0

# Function to process user input
process_input() {
    read -r -p "$1" response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Let user abort
process_input "Configure UFW to block IPs listed in blocklist ipsets? [Y/n] " || exit

# Enable IPv6 support if requested
process_input "Would you like to enable IPv6 support? [Y/n] " && CONFIGURE_IPV6=1

# Ensure that IPSET_DIR exists
mkdir -p "$IPSET_DIR" || exit

# Check if ufw has IPv6 enabled
if [[ "$CONFIGURE_IPV6" == 1 && ! $(grep -q -E "IPV6=(yes|YES)" /etc/default/ufw) ]]; then
    echo "ERROR: IPv6 rules requested but UFW is not configured to use IPv6. Set IPV6=yes in /etc/default/ufw and rerun this script."
    exit 1
fi

# Check if file already exists
if [[ -f "$UFW_AFTER_INIT_FILE" ]]; then
    process_input "The file $UFW_UFW_AFTER_INIT_FILE already exists. Are you sure that you want to overwrite it? [y/N] " || exit
fi

# Deploy after.init based on IPv6 support
cp "ufw/after${CONFIGURE_IPV6:+6}.init" "$UFW_AFTER_INIT_FILE" || exit
chmod 755 "$UFW_AFTER_INIT_FILE"
echo "Deployed $UFW_UFW_AFTER_INIT_FILE"

# Restart ufw if needed
process_input "Reload ufw to apply changes? [Y/n] " && ufw reload
