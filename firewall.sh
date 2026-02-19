#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# firewall.sh — Complete firewall setup for the homeserver.
#
# Manages both:
#   1. INPUT chain  — host-level services (SSH, Samba on host)
#   2. DOCKER-USER  — Docker-published ports (Jenkins, Samba container)
#
# Usage:  sudo ./firewall.sh [apply|reset|status]
#
# Reads LAN_SUBNET from .env in the same directory (e.g. 192.168.1.0/24)
# Requires: iptables-persistent (for boot persistence)
# -------------------------------------------------------------------

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${BASE_DIR}/.env"
ACTION="${1:-apply}"

# --- Load config ---
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: ${ENV_FILE} not found. Create it with LAN_SUBNET=192.168.1.0/24"
    exit 1
fi

source "$ENV_FILE"

if [[ -z "${LAN_SUBNET:-}" ]]; then
    echo "ERROR: LAN_SUBNET not set in ${ENV_FILE}"
    exit 1
fi

# ===================================================================
# Port configuration
# ===================================================================

# Host INPUT: ports open to everyone
INPUT_OPEN_PORTS=(
    22      # SSH
)

# Host INPUT: ports open to LAN only
INPUT_LAN_PORTS_TCP=(
    # Currently empty — all LAN-only services run in Docker (see DOCKER_LAN_PORTS)
)

# Docker DOCKER-USER: container ports restricted to LAN only
DOCKER_LAN_PORTS=(
    8080    # Jenkins web UI
    50000   # Jenkins agent
    445     # Samba (container)
)

# ===================================================================
# Functions
# ===================================================================

flush_docker_user() {
    echo "  Flushing DOCKER-USER managed rules..."
    while iptables -L DOCKER-USER -n --line-numbers 2>/dev/null \
          | grep "homeserver-managed" | head -1 | awk '{print $1}' | grep -q .; do
        local line
        line=$(iptables -L DOCKER-USER -n --line-numbers \
               | grep "homeserver-managed" | head -1 | awk '{print $1}')
        iptables -D DOCKER-USER "$line"
    done
}

apply_input_rules() {
    echo "Setting up INPUT chain..."

    # Flush existing INPUT rules
    iptables -F INPUT

    # Allow established/related connections (critical — keeps current SSH alive)
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo "  ✓ ACCEPT established/related connections"

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    echo "  ✓ ACCEPT loopback"

    # Ports open to everyone
    for port in "${INPUT_OPEN_PORTS[@]}"; do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        echo "  ✓ ACCEPT * → port ${port}"
    done

    # TCP ports open to LAN only
    for port in "${INPUT_LAN_PORTS_TCP[@]}"; do
        iptables -A INPUT -p tcp --dport "$port" -s "$LAN_SUBNET" -j ACCEPT
        echo "  ✓ ACCEPT ${LAN_SUBNET} → port ${port}"
    done

    # Default policy: drop everything else
    iptables -P INPUT DROP
    echo "  ✓ Default policy: DROP"
    echo ""
}

apply_docker_rules() {
    echo "Setting up DOCKER-USER chain..."

    flush_docker_user

    # ACCEPT from LAN for each protected port
    for port in "${DOCKER_LAN_PORTS[@]}"; do
        iptables -A DOCKER-USER -p tcp --dport "$port" \
            -s "$LAN_SUBNET" -j ACCEPT \
            -m comment --comment "homeserver-managed"
        echo "  ✓ ACCEPT ${LAN_SUBNET} → port ${port}"
    done

    # DROP from everywhere else for each protected port
    for port in "${DOCKER_LAN_PORTS[@]}"; do
        iptables -A DOCKER-USER -p tcp --dport "$port" \
            -j DROP \
            -m comment --comment "homeserver-managed"
        echo "  ✓ DROP   * → port ${port}"
    done
    echo ""
}

apply_rules() {
    echo "Applying homeserver firewall rules..."
    echo "  LAN_SUBNET: ${LAN_SUBNET}"
    echo ""

    apply_input_rules
    apply_docker_rules

    echo "All firewall rules applied."
}

show_status() {
    echo "=== INPUT chain ==="
    echo ""
    iptables -L INPUT -n --line-numbers -v 2>/dev/null
    echo ""
    echo "=== DOCKER-USER chain ==="
    echo ""
    iptables -L DOCKER-USER -n --line-numbers -v 2>/dev/null || echo "(chain not found)"
}

reset_rules() {
    echo "Resetting all homeserver-managed rules..."

    # Reset INPUT to accept-all
    iptables -F INPUT
    iptables -P INPUT ACCEPT
    echo "  ✓ INPUT chain flushed, policy set to ACCEPT"

    # Remove DOCKER-USER managed rules
    flush_docker_user
    echo "  ✓ DOCKER-USER managed rules removed"
}

persist_rules() {
    if command -v netfilter-persistent &>/dev/null; then
        echo ""
        echo "Persisting rules with netfilter-persistent..."
        netfilter-persistent save
        echo "Rules saved to /etc/iptables/rules.v4"
    else
        echo ""
        echo "WARNING: iptables-persistent is not installed."
        echo "  Rules will be lost on reboot. Install it with:"
        echo "  sudo apt install -y iptables-persistent"
        echo "  Then re-run: sudo $0 apply"
    fi
}

# ===================================================================
# Main
# ===================================================================

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo)."
    exit 1
fi

case "$ACTION" in
    apply)
        apply_rules
        persist_rules
        ;;
    reset)
        reset_rules
        persist_rules
        echo "All homeserver-managed rules removed."
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: sudo $0 [apply|reset|status]"
        exit 1
        ;;
esac
