# Omarchy Quattro Dotfiles

Complete dotfiles, shell plugins, custom themes, and system configurations for **Omarchy Quattro** (Arch Linux + Hyprland).

Designed to quickly restore an existing Omarchy installation or set up a fresh machine with the exact same configuration level, shortcuts, plugins, and appearance.

---

## ⚡ Quick Start

To restore configurations on a new Omarchy installation:

```bash
# 1. Clone this repository
git clone https://github.com/zatzk/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Run the guided installer
./install.sh
```

Or run directly in one line:
```bash
git clone https://github.com/zatzk/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh --all
```

---

## 📦 What's Included

### 1. Omarchy Shell & Plugins (`config/omarchy/`)
All shell settings and 13 bar/overlay plugins are tracked directly with all custom edits preserved:

| Plugin ID | Name | Highlights / Customizations |
| :--- | :--- | :--- |
| `mykcib.obsidian-quickedit` | **Obsidian Quick Note** | Enhanced with tag switcher (`quicknotes`, `mnemosyne/inbox`), note moving, vault path normalization, smooth auto-scrolling textarea (`ensureCursorVisible`), mouse wheel handling, and Quick Note creation (`Super+N`). |
| `community.cn-input` | **Chinese Input** | Customized trigger hotkey `Ctrl+Alt+Space` with Fcitx5 and Rime Ice pinyin. |
| `ozymandias.menu` | **My Omarchy Menu** | Custom categorized Quickshell application launcher and system menu. |
| `quickshell.spotify` | **Omarchy Spotify** | Lightweight Spotify client (mini-player, artist search, playback backend). |
| `jkoestinger.vpn` | **VPN** | Multi-backend VPN switcher (WireGuard, Proton, Mullvad, NetworkManager, OpenConnect). |
| `robzolkos.github` | **GitHub Notifications** | Real-time GitHub notification watcher and quick-access panel. |
| `fred.sysinfo` | **System Information** | Hardware monitor panel (CPU, thermals, RAM, disks, I/O). |
| `luotao.adhd-kit` | **ADHD Kit** | Time Timer visual countdown widget + quick-capture overlay. |
| `io.github.rohan-patnaik.window-switcher` | **Orbit** | Multi-mode visual window switcher for Hyprland. |
| `stappmus.lyrics` | **Omasing** | Fast, cross-checked synced lyrics popup for the active track. |
| `danglenoir.hanzi` | **Daily Hanzi** | Daily Chinese character flashcard bar widget. |
| `xp.tasklist` | **XP Tasklist** | Classic Windows XP taskbar window buttons. |
| Built-in bar widgets | **Bar Layout** | Configured in `shell.json` (Clock, Indicators, Tray, Audio, Power, Workspaces, Bluetooth, Network, Display, System Update). |

### 2. Custom Themes (`config/omarchy/themes/`)
- **`windows-xp`**: Custom nostalgic Windows XP theme complete with startup audio sound (`xp-startup.mp3`), Bliss background, and an automatic theme hook (`windows-xp-theme-hook`) that shifts the taskbar to the bottom with `ozymandias.menu` as the Start button.
- **`themes-list.txt`**: Upstream git theme URLs (`brutalism`, `green-garden`, `latchdark`, `manga`, `mechanoonna`, `type17`, `venice-from-above`) automatically installable via `omarchy theme install`.

### 3. Hyprland Window Manager (`config/hypr/`)
- `bindings.lua`: Personal keybindings including `Super + N` (New Quick Note), `Super + Alt + N` (Search Notes), and launcher shortcuts.
- `monitors.lua`: Dual-display setup and scaling configurations.
- `looknfeel.lua`: Gaps, borders, animations, and window decoration profiles.
- `input.lua`: Keyboard repeat rates, touchpad natural scrolling, gestures, and layout switching.
- `hyprland.lua`: Personal rules including floating Dusklight (`dev.twilitrealm.dusk`) scratchpad bridge.
- `autostart.lua` & `shaders/`: Custom startup services and screen shaders.

### 4. Terminal Emulators (`config/`)
Configured with JetBrainsMono Nerd Font (size 9), CSI-u keybindings, and Omarchy theme integration:
- **Alacritty** (`config/alacritty/alacritty.toml`)
- **Ghostty** (`config/ghostty/config`)
- **Kitty** (`config/kitty/kitty.conf`)
- **Foot** (`config/foot/foot.ini`)

### 5. CLI, Agents & Productivity Tools (`config/` & `home/`)
- **Fcitx5**: `config/fcitx5/` with `Control+Alt+Space` trigger and Rime input group.
- **Git**: `config/git/config` with user configuration (`Jean Luiz`), custom aliases (`co`, `br`, `ci`, `st`), histogram diff, and branch sorting.
- **Neovim**: `config/nvim/` with LazyVim, remote clipboard synchronization (`remote_clipboard.lua`), tmux OSC 52 integration, and theme auto-reload.
- **Starship Prompt**: `config/starship.toml` custom prompt styling.
- **Tmux**: `config/tmux/tmux.conf`.
- **Btop**: `config/btop/btop.conf`.
- **Mise**: `config/mise/config.toml` managing Node.js (22.22.2), GitHub CLI, Codex, Claude Code, and Opencode.
- **Omarchy Default Agent**: `config/omarchy/defaults/agent` configured for `opencode`.
- **Zed Editor**: `config/zed/settings.json` with Vim mode and font preferences.
- **Default Applications**: `config/mimeapps.list` with Zen Browser, Vesktop, MongoDB Compass associations.
- **Shell**: `home/.bashrc` and `home/.zshrc` with custom aliases (VPN controls `vpn-up`/`vpn-down`/`vpn-status`, SD Forge, Opencode PATH).

### 6. VPN & Network Provisioning (`config/vpn/`)
- **WireGuard (`wg0`)**:
  - Sample configurations provided in `config/vpn/wg0.conf.sample` and `config/vpn/wg0.nmconnection.sample` with exact peer endpoint, allowed IPs, listen port (21841), and IP settings.
  - Non-destructive automated provisioning script `config/vpn/setup-vpn.sh` (or `./install.sh --vpn`) to quickly import the connection into NetworkManager with a single command.
- **Tailscale**: Automated verification and enablement of `tailscaled.service`.
- **Omarchy VPN Bar Plugin**: `jkoestinger.vpn` multi-backend controller with OpenConnect authentication helper (`bin/omarchy-openconnect-auth`).
- **Quick Shell Aliases**:
  ```bash
  alias vpn-up='sudo wg-quick up wg0'
  alias vpn-down='sudo wg-quick down wg0'
  alias vpn-status='sudo wg show'
  ```

### 7. Hardware & Audio Configurations (`config/wireplumber/`)
- `wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf`: Automatic Bluetooth A2DP profile connection.
- `wireplumber.conf.d/kef-lsx-no-suspend.conf`: Prevents KEF LSX II LT USB sink suspension (`session.suspend-timeout-seconds = 0`) to eliminate firmware lockups on idle timeouts.

### 8. User Scripts (`bin/`)
- `pinote-quicknote`: Instant quick note capture script.
- `pinote-history`: Quick note history viewer.
- `salinha`: Wayland Intel Mesa / iHD VA-API wrapper avoiding NVIDIA conflicts.
- `the-classic-games`: Game launcher runner script.

### 9. User Systemd Units (`config/systemd/user/`)
- `rclone-bisync.service` & `rclone-bisync.timer`: Google Drive 2-way sync for Obsidian vault every 15 minutes.
- `omarchy-spotify.service`: Background daemon for Quickshell Spotify playback.

### 10. Package Lists (`packages/`)
- `all-explicit-packages.txt`: Complete snapshot of 281 explicitly installed native and AUR packages.
- `extra-native-packages.txt`: 79 extra native repository packages beyond base Omarchy.
- `aur-packages.txt`: 29 foreign/AUR packages installed on the system (Doppler, Dusklight, RustDesk, Zen Browser, Antigravity, Spicetify, etc.).

---

## 🛠️ Installer Options

The `install.sh` script is modular, non-destructive, and creates automatic backups of replaced configs:

```bash
# Guided interactive menu
./install.sh

# Complete restore without prompts (configs + plugins + themes + packages + VPN helper)
./install.sh --all

# Restore configurations and plugins only (skips package installs)
./install.sh --config-only

# Install extra native and AUR packages (uses pacman and yay/paru)
./install.sh --packages

# Install upstream git themes
./install.sh --themes

# Run VPN and WireGuard setup helper
./install.sh --vpn

# Symlink configurations to dotfiles instead of copying
./install.sh --symlink

# Preview actions without touching the filesystem
./install.sh --dry-run
```

---

## 🔒 Security & Privacy

This repository uses a strict `.gitignore` to prevent committing private credentials:
- Secrets such as `rclone.conf` (Google Drive OAuth tokens), WireGuard private keys (`wg0.conf`, `*.nmconnection`), and session tokens are strictly excluded.
- Templates are provided at `config/rclone/rclone.conf.sample`, `config/vpn/wg0.conf.sample`, and `config/vpn/wg0.nmconnection.sample`. Run `./install.sh --vpn` or `rclone config` on a new machine to authenticate.
