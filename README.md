# Work Mode Plugin for Omarchy (`oma-work`)

A toggleable **Work Mode** plugin for Omarchy.

When activated, Work Mode puts your desktop into a work-ready state:
1. **Switches your Default Browser**: Sets default web browser to **Firefox** (`firefox.desktop`)
2. **Switches your Theme**: Sets your Omarchy theme to **`Tds`**
3. **Connects your VPN**: Runs `globalprotect connect`

When deactivated, it cleanly reverses the changes:
- Disconnects VPN (`globalprotect disconnect`)
- Restores your previous personal theme (e.g. `Miasma`, `Tokyo Night`, etc.)
- Restores your previous default browser (e.g. `chromium.desktop`)

---

## Features

- **Bar Widget**: Shows a briefcase icon (`󰢏`) in the Omarchy bar.
  - **Highlighted/Active**: Work Mode is ON (VPN connected, Tds theme, Firefox browser).
  - **Dimmed/Standard**: Work Mode is OFF.
  - **Left-Click**: Toggle Work Mode ON / OFF.
  - **Right-Click / Middle-Click**: Launch interactive floating terminal for VPN re-authentication.
  - **Hover Tooltip**: Displays current VPN status, theme, and default browser.
- **Seamless Re-Authentication**:
  - **SAML / Browser SSO**: Since default browser is switched to Firefox before connecting, GlobalProtect's SSO login page opens automatically in Firefox.
  - **Interactive Terminal Prompts**: Right-click or middle-click the bar widget, or run `./work-mode.sh auth` to immediately open an Omarchy floating terminal with `globalprotect connect`.
- **State Preservation**: Automatically remembers what theme and browser you were using before turning Work Mode on so they are faithfully restored when turning it off.
- **Desktop Notifications**: Sends native Omarchy notifications on state changes.
- **CLI & IPC Control**: Easily trigger via terminal scripts, keybindings, or `omarchy-shell`.

---

## Installation & Setup

### Local Development / Manual Installation
Link or copy this folder into your Omarchy plugins directory:
```bash
mkdir -p ~/.config/omarchy/plugins
ln -sfn /home/hclark/git/oma-work ~/.config/omarchy/plugins/oma-work
```

Rescan plugins and enable the widget:
```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable oma-work
```

### Git Installation (Once Published)
```bash
omarchy plugin add https://github.com/<your-username>/oma-work.git --enable
```

---

## Usage

### 1. Omarchy Bar
- **Left-Click**: Toggle between Work Mode and Personal Mode.
- **Right-Click / Middle-Click**: Open interactive floating terminal for GlobalProtect authentication / MFA prompt.
- **Hover**: View live status of VPN, theme, and browser.

### 2. Command Line
```bash
# Toggle between ON and OFF
./work-mode.sh toggle

# Explicitly enable work mode
./work-mode.sh on

# Explicitly disable work mode
./work-mode.sh off

# Re-authenticate to VPN interactively
./work-mode.sh auth

# Check current status
./work-mode.sh status
./work-mode.sh status --json
```

### 3. Omarchy Shell IPC
```bash
omarchy-shell oma-work toggle
omarchy-shell oma-work enable
omarchy-shell oma-work disable
omarchy-shell oma-work status
omarchy-shell oma-work refresh
```

### 4. Hyprland Keybinding
Add shortcuts to `~/.config/hypr/hyprland.conf`:
```ini
bind = $mainMod ALT, W, exec, omarchy-shell oma-work toggle
bind = $mainMod ALT, A, exec, ./work-mode.sh auth
```

---

## File Structure

```text
oma-work/
├── manifest.json   # Omarchy plugin manifest
├── BarWidget.qml   # Omarchy bar widget & IPC handler
├── work-mode.sh    # Core shell script managing VPN, theme, and browser state
├── bin/
│   └── oma-work    # Executable CLI wrapper
└── README.md       # Documentation
```

## License

MIT
