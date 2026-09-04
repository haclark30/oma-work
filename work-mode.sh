#!/bin/bash

# omarchy:summary=Toggle work mode (GlobalProtect VPN, notes mount, Tds theme, Firefox browser)
# omarchy:group=plugin
# omarchy:args=[toggle|on|off|status|auth|mount|unmount] [--headless] [--json]
# omarchy:examples=work-mode toggle

set -euo pipefail

STATE_DIR="$HOME/.local/state/omarchy/work-mode"
ACTIVE_FILE="$STATE_DIR/active"
PREV_THEME_FILE="$STATE_DIR/prev-theme"
PREV_BROWSER_FILE="$STATE_DIR/prev-browser"

WORK_THEME="Tds"
WORK_BROWSER="firefox.desktop"
DEFAULT_FALLBACK_THEME="Tokyo Night"
DEFAULT_FALLBACK_BROWSER="chromium.desktop"

NOTES_REMOTE="workpc:/home/usrwpi/git/obsidian-notes"
NOTES_MOUNT="$HOME/work-notes"

mkdir -p "$STATE_DIR"

# Parse options
HEADLESS=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --headless|--no-terminal)
      HEADLESS=1
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

if [[ ${#ARGS[@]} -gt 0 ]]; then
  set -- "${ARGS[@]}"
else
  set -- "toggle"
fi

action="${1:-toggle}"

# Auto-launch interactive presentation terminal if invoked without a TTY
case "$action" in
  status|-h|--help|help)
    # Status and help are never redirected to a terminal window
    ;;
  *)
    if [[ "$HEADLESS" -eq 0 && -z "${OMA_WORK_IN_TERMINAL:-}" && ! -t 1 ]]; then
      if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
        exec omarchy-launch-floating-terminal-with-presentation env OMA_WORK_IN_TERMINAL=1 "$0" "$@"
      elif command -v omarchy-launch-terminal >/dev/null 2>&1; then
        exec omarchy-launch-terminal env OMA_WORK_IN_TERMINAL=1 "$0" "$@"
      elif command -v xdg-terminal-exec >/dev/null 2>&1; then
        exec xdg-terminal-exec env OMA_WORK_IN_TERMINAL=1 "$0" "$@"
      fi
    fi
    ;;
esac

notify() {
  local title="$1"
  local msg="$2"
  local glyph="${3:-󰢏}"

  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send "$title" "$msg" -g "$glyph" -u low 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a "omarchy-action" "$title" "$msg" 2>/dev/null || true
  fi
}

get_current_theme() {
  if command -v omarchy-theme-current >/dev/null 2>&1; then
    omarchy-theme-current 2>/dev/null || echo ""
  elif [[ -f "$HOME/.local/state/omarchy/current/theme.name" ]]; then
    cat "$HOME/.local/state/omarchy/current/theme.name"
  else
    echo ""
  fi
}

get_current_browser() {
  local browser=""
  if command -v xdg-settings >/dev/null 2>&1; then
    browser=$(xdg-settings get default-web-browser 2>/dev/null || true)
  fi
  if [[ -z "$browser" ]] && command -v xdg-mime >/dev/null 2>&1; then
    browser=$(xdg-mime query default x-scheme-handler/http 2>/dev/null || true)
  fi
  echo "$browser"
}

get_vpn_status() {
  if command -v globalprotect >/dev/null 2>&1; then
    if timeout 3 globalprotect show --status 2>/dev/null | grep -qi "Connected"; then
      echo "connected"
      return 0
    fi
  fi
  echo "disconnected"
}

get_notes_status() {
  if mountpoint -q "$NOTES_MOUNT" 2>/dev/null; then
    echo "mounted"
  else
    echo "unmounted"
  fi
}

mount_notes() {
  mkdir -p "$NOTES_MOUNT"
  if mountpoint -q "$NOTES_MOUNT" 2>/dev/null; then
    echo "  ✓ Work notes already mounted at $NOTES_MOUNT"
    return 0
  fi

  if ! command -v sshfs >/dev/null 2>&1; then
    echo "  ✗ sshfs binary not found in PATH" >&2
    return 1
  fi

  if sshfs "$NOTES_REMOTE" "$NOTES_MOUNT" \
    -o reconnect \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o ConnectTimeout=5 \
    -o uid="$(id -u)" \
    -o gid="$(id -g)" \
    -o follow_symlinks; then
    echo "  ✓ Mounted notes at $NOTES_MOUNT"
    return 0
  else
    echo "  ✗ Failed to mount $NOTES_REMOTE at $NOTES_MOUNT" >&2
    return 1
  fi
}

mount_notes_background() {
  (
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
      # If work mode was disabled in the meantime, abort
      if ! is_active; then
        exit 0
      fi
      if mountpoint -q "$NOTES_MOUNT" 2>/dev/null; then
        exit 0
      fi
      if mount_notes >/dev/null 2>&1; then
        notify "Work Notes" "Obsidian notes mounted at $NOTES_MOUNT" "󰢏"
        if command -v omarchy-shell >/dev/null 2>&1; then
          omarchy-shell -q oma-work refresh 2>/dev/null || true
        fi
        exit 0
      fi
      attempt=$((attempt + 1))
      sleep 2
    done
  ) >/dev/null 2>&1 &
}

unmount_notes() {
  if mountpoint -q "$NOTES_MOUNT" 2>/dev/null; then
    echo "  Unmounting $NOTES_MOUNT..."
    if command -v fusermount3 >/dev/null 2>&1; then
      fusermount3 -u "$NOTES_MOUNT" 2>/dev/null || fusermount3 -u -z "$NOTES_MOUNT" 2>/dev/null || true
    elif command -v fusermount >/dev/null 2>&1; then
      fusermount -u "$NOTES_MOUNT" 2>/dev/null || fusermount -u -z "$NOTES_MOUNT" 2>/dev/null || true
    elif command -v umount >/dev/null 2>&1; then
      umount "$NOTES_MOUNT" 2>/dev/null || umount -l "$NOTES_MOUNT" 2>/dev/null || true
    fi

    if ! mountpoint -q "$NOTES_MOUNT" 2>/dev/null; then
      echo "  ✓ Successfully unmounted $NOTES_MOUNT"
    else
      echo "  ! Warning: $NOTES_MOUNT could not be unmounted cleanly" >&2
    fi
  else
    echo "  • Work notes not mounted at $NOTES_MOUNT"
  fi
}

set_browser() {
  local browser="$1"
  [[ -n "$browser" ]] || return 0

  if command -v xdg-settings >/dev/null 2>&1; then
    xdg-settings set default-web-browser "$browser" 2>/dev/null || true
  fi
  if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default "$browser" x-scheme-handler/http 2>/dev/null || true
    xdg-mime default "$browser" x-scheme-handler/https 2>/dev/null || true
    xdg-mime default "$browser" text/html 2>/dev/null || true
    xdg-mime default "$browser" text/xml 2>/dev/null || true
    xdg-mime default "$browser" application/xhtml+xml 2>/dev/null || true
    xdg-mime default "$browser" application/xml 2>/dev/null || true
  fi
}

set_theme() {
  local theme="$1"
  [[ -n "$theme" ]] || return 0

  if command -v omarchy-theme-set >/dev/null 2>&1; then
    omarchy-theme-set "$theme" >/dev/null 2>&1 || true
  elif command -v omarchy >/dev/null 2>&1; then
    omarchy theme set "$theme" >/dev/null 2>&1 || true
  fi
}

is_active() {
  [[ -f "$ACTIVE_FILE" ]]
}

interactive_auth() {
  echo "════════════════════════════════════════════════════════"
  echo "       GLOBALPROTECT VPN RE-AUTHENTICATION              "
  echo "════════════════════════════════════════════════════════"
  echo ""
  if command -v globalprotect >/dev/null 2>&1; then
    echo "Starting interactive GlobalProtect session..."
    echo "--------------------------------------------------------"
    globalprotect connect || true
    echo "--------------------------------------------------------"
    echo ""
    local vpn_state
    vpn_state=$(get_vpn_status)
    if [[ "$vpn_state" == "connected" ]]; then
      echo "✓ VPN connected successfully"
      if is_active && ! mountpoint -q "$NOTES_MOUNT" 2>/dev/null; then
        echo ""
        echo "▶ Mounting work notes ($NOTES_REMOTE -> $NOTES_MOUNT)..."
        mount_notes || true
      fi
    else
      echo "! GlobalProtect status: $vpn_state"
    fi
  else
    echo "globalprotect binary not found in PATH" >&2
    exit 1
  fi

  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell -q oma-work refresh 2>/dev/null || true
  fi
}

enable_work_mode() {
  echo "════════════════════════════════════════════════════════"
  echo "           ACTIVATING WORK MODE                         "
  echo "════════════════════════════════════════════════════════"
  echo ""

  # Save previous state if not already active
  if ! is_active; then
    local current_theme
    current_theme=$(get_current_theme)
    if [[ -n "$current_theme" && "${current_theme,,}" != "${WORK_THEME,,}" ]]; then
      echo "$current_theme" > "$PREV_THEME_FILE"
      echo "  • Preserved personal theme: $current_theme"
    fi

    local current_browser
    current_browser=$(get_current_browser)
    if [[ -n "$current_browser" && "$current_browser" != "$WORK_BROWSER" ]]; then
      echo "$current_browser" > "$PREV_BROWSER_FILE"
      echo "  • Preserved personal browser: $current_browser"
    fi
  fi

  # 1. Switch default browser to Firefox FIRST (so SAML SSO opens in Firefox)
  echo ""
  echo "▶ [1/4] Setting default browser to Firefox ($WORK_BROWSER)..."
  set_browser "$WORK_BROWSER"
  echo "  ✓ Default browser set to Firefox"

  # 2. Change Omarchy Theme to Tds
  echo ""
  echo "▶ [2/4] Switching Omarchy theme to $WORK_THEME..."
  set_theme "$WORK_THEME"
  echo "  ✓ Desktop theme set to $WORK_THEME"

  # 3. Connect GlobalProtect VPN interactively
  echo ""
  echo "▶ [3/4] Connecting GlobalProtect VPN..."
  local vpn_state
  vpn_state=$(get_vpn_status)
  if [[ "$vpn_state" == "connected" ]]; then
    echo "  ✓ GlobalProtect VPN is already connected"
  elif command -v globalprotect >/dev/null 2>&1; then
    echo "  Starting interactive GlobalProtect session..."
    echo "  (If prompted, complete authentication in terminal or browser)"
    echo "--------------------------------------------------------"
    globalprotect connect || true
    echo "--------------------------------------------------------"

    vpn_state=$(get_vpn_status)
    if [[ "$vpn_state" == "connected" ]]; then
      echo "  ✓ VPN connection established"
    else
      echo "  ! Current VPN status: $vpn_state"
      echo "    If 2FA/SSO was opened in Firefox, complete it there."
    fi
  else
    echo "  ✗ globalprotect binary not found in PATH"
  fi

  # 4. Mount work notes via SSHFS
  echo ""
  echo "▶ [4/4] Mounting Obsidian notes vault..."
  echo "  Remote: $NOTES_REMOTE"
  echo "  Target: $NOTES_MOUNT"
  if mountpoint -q "$NOTES_MOUNT" 2>/dev/null; then
    echo "  ✓ Notes already mounted at $NOTES_MOUNT"
  else
    local mounted=false
    local max_tries=3
    local try=1
    while [[ $try -le $max_tries ]]; do
      echo "  Attempting mount (try $try of $max_tries)..."
      if mount_notes; then
        mounted=true
        echo "  ✓ Notes vault successfully mounted at $NOTES_MOUNT"
        break
      fi
      if [[ $try -lt $max_tries ]]; then
        echo "  Mount attempt $try failed. Retrying in 2s..."
        sleep 2
      fi
      try=$((try + 1))
    done

    if [[ "$mounted" != "true" ]]; then
      echo "  ! Could not mount notes yet."
      echo "    Starting background mount retry watcher..."
      mount_notes_background
    fi
  fi

  # Mark work mode active
  touch "$ACTIVE_FILE"

  # Desktop notification
  notify "Work Mode" "Enabled (VPN: $(get_vpn_status) • Theme: $WORK_THEME • Firefox)" "󰢏"

  # Signal Omarchy Shell to refresh widget
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell -q oma-work refresh 2>/dev/null || true
  fi

  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "           WORK MODE ACTIVATED                          "
  echo "════════════════════════════════════════════════════════"
  echo "  • Theme:   $WORK_THEME"
  echo "  • Browser: $WORK_BROWSER"
  echo "  • VPN:     $(get_vpn_status)"
  echo "  • Notes:   $(get_notes_status) ($NOTES_MOUNT)"
  echo "════════════════════════════════════════════════════════"
}

disable_work_mode() {
  echo "════════════════════════════════════════════════════════"
  echo "           DEACTIVATING WORK MODE                       "
  echo "════════════════════════════════════════════════════════"
  echo ""

  # 1. Unmount notes vault BEFORE disconnecting VPN
  echo "▶ [1/4] Unmounting Obsidian notes vault ($NOTES_MOUNT)..."
  unmount_notes
  echo ""

  # 2. Disconnect GlobalProtect VPN
  echo "▶ [2/4] Disconnecting GlobalProtect VPN..."
  if command -v globalprotect >/dev/null 2>&1; then
    globalprotect disconnect || true
    echo "  ✓ GlobalProtect VPN disconnected"
  else
    echo "  • globalprotect command not found in PATH"
  fi
  echo ""

  # 3. Restore previous theme
  local restore_theme=""
  if [[ -f "$PREV_THEME_FILE" ]]; then
    restore_theme=$(<"$PREV_THEME_FILE")
    rm -f "$PREV_THEME_FILE"
  fi
  if [[ -z "$restore_theme" || "${restore_theme,,}" == "${WORK_THEME,,}" ]]; then
    restore_theme="$DEFAULT_FALLBACK_THEME"
  fi
  echo "▶ [3/4] Restoring personal theme ($restore_theme)..."
  set_theme "$restore_theme"
  echo "  ✓ Theme restored to $restore_theme"
  echo ""

  # 4. Restore previous browser
  local restore_browser=""
  if [[ -f "$PREV_BROWSER_FILE" ]]; then
    restore_browser=$(<"$PREV_BROWSER_FILE")
    rm -f "$PREV_BROWSER_FILE"
  fi
  if [[ -z "$restore_browser" || "$restore_browser" == "$WORK_BROWSER" ]]; then
    restore_browser="$DEFAULT_FALLBACK_BROWSER"
  fi
  echo "▶ [4/4] Restoring default browser ($restore_browser)..."
  set_browser "$restore_browser"
  echo "  ✓ Default browser restored to $restore_browser"
  echo ""

  # Remove active marker
  rm -f "$ACTIVE_FILE"

  # Desktop notification
  notify "Work Mode" "Disabled (Restored: $restore_theme • $restore_browser)" "󰢓"

  # Signal Omarchy Shell to refresh widget
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell -q oma-work refresh 2>/dev/null || true
  fi

  echo "════════════════════════════════════════════════════════"
  echo "           WORK MODE DEACTIVATED                        "
  echo "════════════════════════════════════════════════════════"
  echo "  • Restored Theme:   $restore_theme"
  echo "  • Restored Browser: $restore_browser"
  echo "  • VPN Status:       $(get_vpn_status)"
  echo "  • Notes Status:     $(get_notes_status)"
  echo "════════════════════════════════════════════════════════"
}

toggle_work_mode() {
  if is_active; then
    disable_work_mode
  else
    enable_work_mode
  fi
}

print_status() {
  local active
  if is_active; then
    active="true"
  else
    active="false"
  fi

  local vpn
  vpn=$(get_vpn_status)

  local theme
  theme=$(get_current_theme)

  local browser
  browser=$(get_current_browser)

  local notes
  notes=$(get_notes_status)

  if [[ "${1:-}" == "--json" ]]; then
    printf '{"active":%s,"vpn":"%s","theme":"%s","browser":"%s","notes":"%s"}\n' \
      "$active" "$vpn" "$theme" "$browser" "$notes"
  else
    echo "Work Mode Status:"
    echo "  Active:  $active"
    echo "  VPN:     $vpn"
    echo "  Theme:   $theme"
    echo "  Browser: $browser"
    echo "  Notes:   $notes"
  fi
}

case "$action" in
  on|enable|start)
    enable_work_mode
    ;;
  off|disable|stop)
    disable_work_mode
    ;;
  toggle)
    toggle_work_mode
    ;;
  auth|reauth|login)
    interactive_auth
    ;;
  mount)
    mount_notes
    if command -v omarchy-shell >/dev/null 2>&1; then
      omarchy-shell -q oma-work refresh 2>/dev/null || true
    fi
    ;;
  unmount|umount)
    unmount_notes
    if command -v omarchy-shell >/dev/null 2>&1; then
      omarchy-shell -q oma-work refresh 2>/dev/null || true
    fi
    ;;
  status)
    shift || true
    print_status "${1:-}"
    ;;
  -h|--help|help)
    echo "Usage: work-mode [toggle|on|off|status|auth|mount|unmount] [--headless] [--json]"
    echo ""
    echo "Commands:"
    echo "  toggle      Toggle work mode between ON and OFF in an interactive session"
    echo "  on          Enable work mode interactively (VPN, notes, Tds theme, Firefox browser)"
    echo "  off         Disable work mode interactively (unmount notes, disconnect VPN, restore theme/browser)"
    echo "  auth        Launch interactive GlobalProtect VPN authentication session"
    echo "  mount       Explicitly mount notes sshfs filesystem"
    echo "  unmount     Explicitly unmount notes sshfs filesystem"
    echo "  status      Show current work mode, VPN, theme, browser, and notes mount status"
    echo ""
    echo "Options:"
    echo "  --headless  Run directly without auto-launching a floating presentation terminal"
    echo "  --json      Output status as JSON (only with status command)"
    ;;
  *)
    echo "Unknown command: $action" >&2
    echo "Usage: work-mode [toggle|on|off|status|auth|mount|unmount] [--headless] [--json]" >&2
    exit 1
    ;;
esac
