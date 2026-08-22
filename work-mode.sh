#!/bin/bash

# omarchy:summary=Toggle work mode (GlobalProtect VPN, Tds theme, Firefox browser)
# omarchy:group=plugin
# omarchy:args=[toggle|on|off|status|auth] [--json]
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

mkdir -p "$STATE_DIR"

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
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    omarchy-launch-floating-terminal-with-presentation "globalprotect connect"
  elif command -v globalprotect >/dev/null 2>&1; then
    globalprotect connect
  else
    echo "globalprotect binary not found in PATH" >&2
    exit 1
  fi
}

enable_work_mode() {
  # If not currently active, remember the previous theme and browser
  if ! is_active; then
    local current_theme
    current_theme=$(get_current_theme)
    if [[ -n "$current_theme" && "${current_theme,,}" != "${WORK_THEME,,}" ]]; then
      echo "$current_theme" > "$PREV_THEME_FILE"
    fi

    local current_browser
    current_browser=$(get_current_browser)
    if [[ -n "$current_browser" && "$current_browser" != "$WORK_BROWSER" ]]; then
      echo "$current_browser" > "$PREV_BROWSER_FILE"
    fi
  fi

  # 1. Switch default browser to Firefox FIRST (so SAML SSO opens in Firefox)
  set_browser "$WORK_BROWSER"

  # 2. Change Omarchy Theme to Tds
  set_theme "$WORK_THEME"

  # 3. Connect GlobalProtect VPN
  if command -v globalprotect >/dev/null 2>&1; then
    globalprotect connect >/dev/null 2>&1 &
  fi

  # Mark active
  touch "$ACTIVE_FILE"

  # Desktop notification
  notify "Work Mode" "Enabled (VPN connecting • Tds theme • Firefox active)" "󰢏"

  # Signal Omarchy Shell to refresh widget
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell -q oma-work refresh 2>/dev/null || true
  fi

  echo "Work Mode enabled: VPN connecting, theme '$WORK_THEME' applied, default browser set to $WORK_BROWSER"
}

disable_work_mode() {
  # 1. Disconnect GlobalProtect VPN
  if command -v globalprotect >/dev/null 2>&1; then
    globalprotect disconnect >/dev/null 2>&1 &
  fi

  # 2. Restore previous theme
  local restore_theme=""
  if [[ -f "$PREV_THEME_FILE" ]]; then
    restore_theme=$(<"$PREV_THEME_FILE")
    rm -f "$PREV_THEME_FILE"
  fi
  if [[ -z "$restore_theme" || "${restore_theme,,}" == "${WORK_THEME,,}" ]]; then
    restore_theme="$DEFAULT_FALLBACK_THEME"
  fi
  set_theme "$restore_theme"

  # 3. Restore previous browser
  local restore_browser=""
  if [[ -f "$PREV_BROWSER_FILE" ]]; then
    restore_browser=$(<"$PREV_BROWSER_FILE")
    rm -f "$PREV_BROWSER_FILE"
  fi
  if [[ -z "$restore_browser" || "$restore_browser" == "$WORK_BROWSER" ]]; then
    restore_browser="$DEFAULT_FALLBACK_BROWSER"
  fi
  set_browser "$restore_browser"

  # Remove active marker
  rm -f "$ACTIVE_FILE"

  # Desktop notification
  notify "Work Mode" "Disabled (VPN disconnected • restored theme: $restore_theme • browser: $restore_browser)" "󰢓"

  # Signal Omarchy Shell to refresh widget
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell -q oma-work refresh 2>/dev/null || true
  fi

  echo "Work Mode disabled: VPN disconnected, restored theme '$restore_theme', default browser set to $restore_browser"
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

  if [[ "${1:-}" == "--json" ]]; then
    printf '{"active":%s,"vpn":"%s","theme":"%s","browser":"%s"}\n' \
      "$active" "$vpn" "$theme" "$browser"
  else
    echo "Work Mode Status:"
    echo "  Active:  $active"
    echo "  VPN:     $vpn"
    echo "  Theme:   $theme"
    echo "  Browser: $browser"
  fi
}

action="${1:-toggle}"

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
  status)
    shift || true
    print_status "${1:-}"
    ;;
  -h|--help|help)
    echo "Usage: work-mode [toggle|on|off|status|auth] [--json]"
    echo ""
    echo "Commands:"
    echo "  toggle      Toggle work mode between ON and OFF (default)"
    echo "  on          Enable work mode (Connect VPN, set Tds theme, set Firefox browser)"
    echo "  off         Disable work mode (Disconnect VPN, restore theme and browser)"
    echo "  auth        Launch interactive GlobalProtect connect session in floating terminal"
    echo "  status      Show current work mode, VPN, theme, and browser status"
    ;;
  *)
    echo "Unknown command: $action" >&2
    echo "Usage: work-mode [toggle|on|off|status|auth] [--json]" >&2
    exit 1
    ;;
esac
