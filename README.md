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
All shell settings and 12 bar/overlay plugins are tracked directly with all custom edits preserved:

| Plugin ID | Name | Highlights / Customizations |
| :--- | :--- | :--- |
| `mykcib.obsidian-quickedit` | **Obsidian Quick Note** | Enhanced with smooth auto-scrolling textarea (`ensureCursorVisible`), mouse wheel handling, and Quick Note creation (`Super+N`). |
| `community.cn-input` | **Chinese Input** | Customized trigger hotkey `Ctrl+Alt+Space` with Fcitx5 and Rime Ice pinyin. |
| `ozymandias.menu` | **My Omarchy Menu** | Custom categorized Quickshell application launcher and system menu. |
| `quickshell.spotify` | **Omarchy Spotify** | Lightweight Spotify client (mini-player, artist search, playback backend). |
| `jkoestinger.vpn` | **VPN** | Multi-backend VPN switcher (WireGuard, Proton, Mullvad, NetworkManager). |
| `fred.sysinfo` | **System Information** | Hardware monitor panel (CPU, thermals, RAM, disks, I/O). |
| `luotao.adhd-kit` | **ADHD Kit** | Time Timer visual countdown widget + quick-capture overlay. |
| `io.github.rohan-patnaik.window-switcher` | **Orbit** | Multi-mode visual window switcher for Hyprland. |
| `stappmus.lyrics` | **Omasing** | Fast, cross-checked synced lyrics popup for the active track. |
| `danglenoir.hanzi` | **Daily Hanzi** | Daily Chinese character flashcard bar widget. |
| `xp.tasklist` | **XP Tasklist** | Classic Windows XP taskbar window buttons. |
| Built-in bar widgets | **Bar Layout** | Configured in `shell.json` (Clock, Indicators, Tray, Audio, Power, Workspaces, Bluetooth, Network, Display). |

### 2. Custom Themes (`config/omarchy/themes/`)
- **`windows-xp`**: Custom nostalgic Windows XP theme complete with startup audio sound (`xp-startup.mp3`), Bliss background, and an automatic theme hook (`windows-xp-theme-hook`) that shifts the taskbar to the bottom with `ozymandias.menu` as the Start button.
- **`themes-list.txt`**: Upstream git theme URLs (`brutalism`, `green-garden`, `latchdark`, `manga`, `mechanoonna`, `type17`, `venice-from-above`) automatically installable via `omarchy theme install`.

### 3. Hyprland Window Manager (`config/hypr/`)
- `bindings.lua`: Personal keybindings including `Super + N` (New Quick Note), `Super + Alt + N` (Search Notes), and launcher shortcuts.
- `monitors.lua`: Dual-display setup and scaling configurations.
- `looknfeel.lua`: Gaps, borders, animations, and window decoration profiles.
- `input.lua`: Keyboard repeat rates, touchpad natural scrolling, gestures, and layout switching.
- `autostart.lua` & `shaders/`: Custom startup services and screen shaders.

### 4. Terminal Emulators (`config/`)
Configured with JetBrainsMono Nerd Font (size 9), CSI-u keybindings, and Omarchy theme integration:
- **Alacritty** (`config/alacritty/alacritty.toml`)
- **Ghostty** (`config/ghostty/config`)
- **Kitty** (`config/kitty/kitty.conf`)
- **Foot** (`config/foot/foot.ini`)

### 5. CLI & Productivity Tools (`config/` & `home/`)
- **Fcitx5**: `config/fcitx5/` with `Control+Alt+Space` trigger and Rime input group.
- **Git**: `config/git/config` with custom aliases (`co`, `br`, `ci`, `st`), histogram diff, and branch sorting.
- **Neovim**: `config/nvim/` with LazyVim, remote clipboard integration, and theme auto-reload.
- **Starship Prompt**: `config/starship.toml` custom prompt styling.
- **Tmux**: `config/tmux/tmux.conf`.
- **Btop**: `config/btop/btop.conf`.
- **Mise**: `config/mise/config.toml` managing Node.js, GitHub CLI, and Codex.
- **Zed Editor**: `config/zed/settings.json` with Vim mode and font preferences.
- **Default Applications**: `config/mimeapps.list`.
- **Shell**: `home/.bashrc` and `home/.zshrc` with custom aliases (VPN controls, SD Forge, etc.).

### 6. User Scripts (`bin/`)
- `pinote-quicknote`: Instant quick note capture script.
- `pinote-history`: Quick note history viewer.
- `the-classic-games`: Game launcher runner script.

### 7. User Systemd Units (`config/systemd/user/`)
- `rclone-bisync.service` & `rclone-bisync.timer`: Google Drive 2-way sync for Obsidian vault every 15 minutes.
- `omarchy-spotify.service`: Background daemon for Quickshell Spotify playback.

### 8. Package Lists (`packages/`)
- `all-explicit-packages.txt`: Complete snapshot of explicitly installed native and AUR packages.
- `extra-native-packages.txt`: Extra native repository packages beyond base Omarchy.
- `aur-packages.txt`: Extra AUR packages installed on the system.

---

## 🛠️ Installer Options

The `install.sh` script is modular, non-destructive, and creates automatic backups of replaced configs:

```bash
# Guided interactive menu
./install.sh

# Complete restore without prompts (configs + plugins + themes + packages)
./install.sh --all

# Restore configurations and plugins only (skips package installs)
./install.sh --config-only

# Install extra native and AUR packages (uses pacman and yay/paru)
./install.sh --packages

# Install upstream git themes
./install.sh --themes

# Symlink configurations to dotfiles instead of copying
./install.sh --symlink

# Preview actions without touching the filesystem
./install.sh --dry-run
```

---

## 🔒 Security & Privacy

This repository uses a strict `.gitignore` to prevent committing private credentials:
- Secrets such as `rclone.conf` (Google Drive OAuth tokens), private keys, and session tokens are excluded.
- A template is provided at `config/rclone/rclone.conf.sample`. Run `rclone config` on a new machine to authenticate.
