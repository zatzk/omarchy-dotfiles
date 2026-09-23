#!/usr/bin/env bash
# ==============================================================================
# Omarchy Quattro Dotfiles Installer & System Restorer
# ==============================================================================
# Restores configurations, shell plugins, custom themes, user scripts,
# and optional extra packages to an Omarchy Linux system.
#
# Usage:
#   ./install.sh                Interactive guided installation
#   ./install.sh --all          Restore configs, plugins, themes, and packages
#   ./install.sh --config-only  Restore configs, plugins, and scripts only
#   ./install.sh --packages     Install extra native & AUR packages
#   ./install.sh --themes       Install upstream git themes
#   ./install.sh --symlink      Symlink configs instead of copying
#   ./install.sh --dry-run      Show what would be done without making changes
# ==============================================================================

set -euo pipefail

# Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_BLUE="\033[34m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_CYAN="\033[36m"

info()    { echo -e "${C_BLUE}${C_BOLD}[INFO]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}${C_BOLD}[OK]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}${C_BOLD}[WARN]${C_RESET} $*"; }
error()   { echo -e "${C_RED}${C_BOLD}[ERROR]${C_RESET} $*" >&2; }
heading() { echo -e "\n${C_CYAN}${C_BOLD}=== $* ===${C_RESET}"; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BACKUP_DIR="$HOME/.config/dotfiles-backup-$(date +%Y%m%d%H%M%S)"

MODE_ALL=false
MODE_CONFIG=false
MODE_PACKAGES=false
MODE_THEMES=false
MODE_SYMLINK=false
DRY_RUN=false

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        MODE_ALL=true
        shift
        ;;
      --config-only)
        MODE_CONFIG=true
        shift
        ;;
      --packages)
        MODE_PACKAGES=true
        shift
        ;;
      --themes)
        MODE_THEMES=true
        shift
        ;;
      --symlink)
        MODE_SYMLINK=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        error "Unknown argument: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

show_help() {
  cat << EOF
Omarchy Quattro Dotfiles Installer

Usage:
  ./install.sh [OPTIONS]

Options:
  --all          Install configs, plugins, scripts, themes, and packages
  --config-only  Restore only configuration files, plugins, and scripts (default in non-interactive)
  --packages     Install extra native & AUR packages (requires yay/pacman)
  --themes       Install extra upstream git themes via omarchy theme install
  --symlink      Create symlinks to dotfiles instead of copying files
  --dry-run      Print actions without modifying the filesystem
  -h, --help     Show this help message
EOF
}

check_environment() {
  heading "Environment Check"
  if ! command -v omarchy >/dev/null 2>&1; then
    warn "Omarchy CLI was not detected. This system might not be running Omarchy Linux."
    warn "Configs will still be placed in standard XDG paths."
  else
    success "Omarchy Linux detected ($(omarchy version 2>/dev/null || echo 'Quattro'))"
  fi
}

backup_target() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "  [dry-run] Would backup $target to $BACKUP_DIR"
      return
    fi
    mkdir -p "$BACKUP_DIR"
    local rel="${target#"$HOME"/}"
    local dest_dir="$BACKUP_DIR/$(dirname "$rel")"
    mkdir -p "$dest_dir"
    cp -a "$target" "$dest_dir/"
  fi
}

sync_item() {
  local src="$1"
  local dest="$2"

  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] $src -> $dest"
    return
  fi

  backup_target "$dest"
  mkdir -p "$(dirname "$dest")"

  if [[ "$MODE_SYMLINK" == true ]]; then
    rm -rf "$dest"
    ln -s "$src" "$dest"
  else
    rm -rf "$dest"
    cp -a "$src" "$dest"
  fi
}

restore_configs() {
  heading "Restoring Configurations & Plugins"

  # 1. ~/.config entries
  for item in "$SCRIPT_DIR"/config/*; do
    local base="$(basename "$item")"
    info "Installing config: $base"
    sync_item "$item" "$HOME/.config/$base"
  done

  # 2. Shell files in home
  if [[ -d "$SCRIPT_DIR/home" ]]; then
    for item in "$SCRIPT_DIR"/home/.*; do
      local base="$(basename "$item")"
      [[ "$base" == "." || "$base" == ".." ]] && continue
      info "Installing home file: $base"
      sync_item "$item" "$HOME/$base"
    done
  fi

  # 3. User scripts in ~/.local/bin
  if [[ -d "$SCRIPT_DIR/bin" ]]; then
    mkdir -p "$HOME/.local/bin"
    for item in "$SCRIPT_DIR"/bin/*; do
      local base="$(basename "$item")"
      info "Installing script: ~/.local/bin/$base"
      sync_item "$item" "$HOME/.local/bin/$base"
      [[ "$DRY_RUN" == false ]] && chmod +x "$HOME/.local/bin/$base"
    done
  fi

  # 4. Make plugin executable scripts runnable
  if [[ "$DRY_RUN" == false && -d "$HOME/.config/omarchy/plugins" ]]; then
    find "$HOME/.config/omarchy/plugins" -type f \( -name "*.sh" -o -name "*-ctl" -o -name "*-lyrics" -o -path "*/scripts/*" -o -path "*/bin/*" \) -exec chmod +x {} + 2>/dev/null || true
    # Quickshell spotify backend binary
    if [[ -f "$HOME/.config/omarchy/plugins/quickshell.spotify/backend/dist/x86_64/omarchy-spotify-backend" ]]; then
      chmod +x "$HOME/.config/omarchy/plugins/quickshell.spotify/backend/dist/x86_64/omarchy-spotify-backend"
      mkdir -p "$HOME/.local/lib/omarchy-spotify"
      cp -a "$HOME/.config/omarchy/plugins/quickshell.spotify/backend/dist/x86_64/omarchy-spotify-backend" "$HOME/.local/lib/omarchy-spotify/"
    fi
  fi

  # 5. Make hooks executable
  if [[ "$DRY_RUN" == false && -d "$HOME/.config/omarchy/hooks" ]]; then
    find "$HOME/.config/omarchy/hooks" -type f -exec chmod +x {} + 2>/dev/null || true
  fi

  if [[ -d "$BACKUP_DIR" ]]; then
    success "Backup of replaced configurations saved to: $BACKUP_DIR"
  fi
  success "Configurations, plugins, and scripts installed successfully."
}

restore_themes() {
  heading "Restoring Upstream Themes"
  local themes_file="$SCRIPT_DIR/config/omarchy/themes-list.txt"

  if [[ ! -f "$themes_file" ]]; then
    warn "No themes-list.txt found, skipping extra themes."
    return
  fi

  while IFS= read -r url || [[ -n "$url" ]]; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue
    local name=$(basename -- "$url" .git | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]')
    local dest="$HOME/.config/omarchy/themes/$name"

    if [[ -d "$dest" ]]; then
      info "Theme $name already installed."
      continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
      echo "  [dry-run] Would install theme $name from $url"
      continue
    fi

    if command -v omarchy >/dev/null 2>&1; then
      info "Installing theme via omarchy: $url"
      omarchy theme install "$url" || warn "Could not install theme $url"
    else
      info "Cloning theme $name from $url"
      git clone --depth=1 "$url" "$dest" || warn "Could not clone theme $url"
    fi
  done < "$themes_file"

  success "Themes check complete."
}

restore_packages() {
  heading "Installing Extra Packages"

  local aur_helper=""
  if command -v yay >/dev/null 2>&1; then
    aur_helper="yay"
  elif command -v paru >/dev/null 2>&1; then
    aur_helper="paru"
  fi

  local native_list="$SCRIPT_DIR/packages/extra-native-packages.txt"
  local aur_list="$SCRIPT_DIR/packages/aur-packages.txt"

  # Native packages
  if [[ -f "$native_list" ]]; then
    info "Checking extra native repository packages..."
    local to_install=()
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
      [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
      if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
        to_install+=("$pkg")
      fi
    done < "$native_list"

    if [[ ${#to_install[@]} -gt 0 ]]; then
      info "Installing ${#to_install[@]} missing native packages: ${to_install[*]}"
      if [[ "$DRY_RUN" == false ]]; then
        sudo pacman -S --needed --noconfirm "${to_install[@]}" || warn "Some native packages failed to install."
      fi
    else
      success "All extra native packages are already installed."
    fi
  fi

  # AUR packages
  if [[ -f "$aur_list" ]]; then
    if [[ -z "$aur_helper" ]]; then
      warn "No AUR helper (yay/paru) found. Skipping AUR package installation."
      warn "Packages to install manually: $(cat "$aur_list" | tr '\n' ' ')"
      return
    fi

    info "Checking AUR packages with $aur_helper..."
    local aur_to_install=()
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
      [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
      if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
        aur_to_install+=("$pkg")
      fi
    done < "$aur_list"

    if [[ ${#aur_to_install[@]} -gt 0 ]]; then
      info "Installing ${#aur_to_install[@]} missing AUR packages: ${aur_to_install[*]}"
      if [[ "$DRY_RUN" == false ]]; then
        "$aur_helper" -S --needed --noconfirm "${aur_to_install[@]}" || warn "Some AUR packages failed to install."
      fi
    else
      success "All extra AUR packages are already installed."
    fi
  fi
}

reload_system() {
  heading "Reloading System Components"

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] Would reload systemd, Hyprland, and Omarchy shell."
    return
  fi

  # Systemd user daemon reload
  if command -v systemctl >/dev/null 2>&1; then
    info "Reloading systemd user daemon..."
    systemctl --user daemon-reload || true
  fi

  # Rescan shell plugins
  if command -v omarchy-shell >/dev/null 2>&1; then
    info "Rescanning Omarchy shell plugins..."
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi

  # Hyprland reload
  if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    info "Reloading Hyprland..."
    hyprctl reload >/dev/null 2>&1 || true
  fi

  # Restart omarchy shell if running
  if command -v omarchy-restart-shell >/dev/null 2>&1; then
    info "Restarting Omarchy shell..."
    omarchy-restart-shell >/dev/null 2>&1 || true
  fi

  success "System components reloaded."
}

interactive_menu() {
  echo -e "${C_CYAN}${C_BOLD}"
  echo "  ██████╗  ██████╗ ████████╗███████╗██╗██╗     ███████╗███████╗"
  echo "  ██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██║██║     ██╔════╝██╔════╝"
  echo "  ██║  ██║██║   ██║   ██║   █████╗  ██║██║     █████╗  ███████╗"
  echo "  ██║  ██║██║   ██║   ██║   ██╔══╝  ██║██║     ██╔══╝  ╚════██║"
  echo "  ██████╔╝╚██████╔╝   ██║   ██║     ██║███████╗███████╗███████║"
  echo "  ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝╚══════╝╚══════╝╚══════╝"
  echo -e "${C_RESET}"
  echo -e "Omarchy Quattro Dotfiles Installer\n"

  echo "Select installation mode:"
  echo "  1) Complete Restore (Configs, Plugins, Themes, and Packages) [Recommended]"
  echo "  2) Configs & Plugins Only (No package installs)"
  echo "  3) Extra Packages Only (Install pacman/AUR software)"
  echo "  4) Upstream Themes Only"
  echo "  5) Exit"
  echo ""
  read -rp "Enter choice [1-5]: " choice

  case "$choice" in
    1)
      MODE_ALL=true
      ;;
    2)
      MODE_CONFIG=true
      ;;
    3)
      MODE_PACKAGES=true
      ;;
    4)
      MODE_THEMES=true
      ;;
    *)
      info "Aborted by user."
      exit 0
      ;;
  esac

  read -rp "Use symlinks instead of copying files? [y/N]: " symlink_choice
  if [[ "$symlink_choice" =~ ^[Yy]$ ]]; then
    MODE_SYMLINK=true
  fi
}

main() {
  parse_args "$@"

  # If dry-run without a specific mode, default to all modes
  if [[ "$DRY_RUN" == true && "$MODE_ALL" == false && "$MODE_CONFIG" == false && "$MODE_PACKAGES" == false && "$MODE_THEMES" == false ]]; then
    MODE_ALL=true
  fi

  # If no flags passed, enter interactive mode
  if [[ "$MODE_ALL" == false && "$MODE_CONFIG" == false && "$MODE_PACKAGES" == false && "$MODE_THEMES" == false ]]; then
    if [[ -t 0 ]]; then
      interactive_menu
    else
      MODE_CONFIG=true
    fi
  fi

  check_environment

  if [[ "$MODE_ALL" == true || "$MODE_CONFIG" == true ]]; then
    restore_configs
  fi

  if [[ "$MODE_ALL" == true || "$MODE_THEMES" == true ]]; then
    restore_themes
  fi

  if [[ "$MODE_ALL" == true || "$MODE_PACKAGES" == true ]]; then
    restore_packages
  fi

  reload_system

  heading "Done!"
  success "All selected dotfiles and configurations have been restored."
}

main "$@"
