#!/usr/bin/env bash
# ==============================================================================
# Omarchy VPN Setup & Provisioning Helper
# ==============================================================================
# Configures WireGuard (wg0), Tailscale, and checks jkoestinger.vpn prerequisites.
# ==============================================================================

set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_BLUE="\033[34m"
C_YELLOW="\033[33m"
C_RED="\033[31m"

info()    { echo -e "${C_BLUE}${C_BOLD}[VPN INFO]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}${C_BOLD}[VPN OK]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}${C_BOLD}[VPN WARN]${C_RESET} $*"; }
error()   { echo -e "${C_RED}${C_BOLD}[VPN ERROR]${C_RESET} $*" >&2; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

setup_wireguard() {
  info "Checking WireGuard connection 'wg0'..."

  if nmcli connection show wg0 >/dev/null 2>&1; then
    success "NetworkManager connection 'wg0' is already configured."
    return
  fi

  local sample_conf="$SCRIPT_DIR/wg0.conf.sample"
  local target_conf="$SCRIPT_DIR/wg0.conf"

  if [[ ! -f "$target_conf" ]]; then
    warn "No customized 'wg0.conf' found in $SCRIPT_DIR."
    echo "To configure WireGuard for NetworkManager:"
    echo "  1. Copy $sample_conf to $target_conf"
    echo "  2. Replace <INSERT_PRIVATE_KEY_HERE> with your private key"
    echo "  3. Re-run this script, or run: nmcli connection import type wireguard file $target_conf"
    
    if [[ -t 0 ]]; then
      read -rp "Do you want to enter your WireGuard private key now? [y/N]: " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        read -rsp "Enter WireGuard Private Key: " privkey
        echo ""
        if [[ -n "$privkey" ]]; then
          sed "s|<INSERT_PRIVATE_KEY_HERE>|$privkey|" "$sample_conf" > "$target_conf"
          chmod 600 "$target_conf"
          info "Importing connection into NetworkManager..."
          nmcli connection import type wireguard file "$target_conf"
          success "WireGuard connection 'wg0' created in NetworkManager."
          rm -f "$target_conf"
          return
        fi
      fi
    fi
    return
  fi

  info "Importing existing $target_conf into NetworkManager..."
  nmcli connection import type wireguard file "$target_conf"
  success "WireGuard connection 'wg0' imported successfully."
}

setup_tailscale() {
  info "Checking Tailscale..."
  if command -v tailscale >/dev/null 2>&1; then
    if systemctl is-enabled tailscaled >/dev/null 2>&1; then
      success "Tailscale service (tailscaled) is enabled."
    else
      warn "Enabling and starting tailscaled daemon..."
      sudo systemctl enable --now tailscaled || warn "Failed to enable tailscaled with sudo"
    fi

    if tailscale status >/dev/null 2>&1; then
      success "Tailscale is logged in and active."
    else
      warn "Tailscale is not authenticated. Run: sudo tailscale up"
    fi
  else
    warn "Tailscale is not installed. Install via: omarchy pkg add tailscale (or pacman -S tailscale)"
  fi
}

setup_omarchy_vpn_plugin() {
  info "Checking Omarchy VPN plugin (jkoestinger.vpn)..."
  local auth_script="$HOME/.config/omarchy/plugins/jkoestinger.vpn/bin/omarchy-openconnect-auth"
  if [[ -f "$auth_script" ]]; then
    chmod +x "$auth_script"
    success "OpenConnect auth helper is executable ($auth_script)."
  fi
}

main() {
  echo -e "\n${C_BOLD}=== Omarchy VPN Provisioning ===${C_RESET}\n"
  setup_wireguard
  setup_tailscale
  setup_omarchy_vpn_plugin
  echo ""
  success "VPN setup check complete."
}

main "$@"
