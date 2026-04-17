#!/usr/bin/env bash

# Exit on errors, undefined variables, and failed pipeline parts.
set -Eeuo pipefail

# ────────────────────────────────────────────────────────────
#  Terminal styling
# ────────────────────────────────────────────────────────────

# Only emit ANSI escapes when stdout is a TTY and NO_COLOR is not set.
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  _C_RESET=$'\033[0m'
  _C_BOLD=$'\033[1m'
  _C_DIM=$'\033[2m'
  _C_RED=$'\033[31m'
  _C_GREEN=$'\033[32m'
  _C_YELLOW=$'\033[33m'
  _C_BLUE=$'\033[34m'
  _C_CYAN=$'\033[36m'
else
  _C_RESET=""; _C_BOLD=""; _C_DIM=""
  _C_RED=""; _C_GREEN=""; _C_YELLOW=""; _C_BLUE=""; _C_CYAN=""
fi

# Detect terminal width, capped at 100 for readability.
_term_width() {
  local w="${COLUMNS:-}"
  if [[ -z "$w" ]] && command -v tput >/dev/null 2>&1; then
    w="$(tput cols 2>/dev/null || true)"
  fi
  [[ -n "$w" && "$w" =~ ^[0-9]+$ ]] || w=80
  (( w > 100 )) && w=100
  (( w < 40 )) && w=40
  printf '%s' "$w"
}

# Print a horizontal rule.
_rule() {
  local char="${1:-━}"
  local color="${2:-${_C_DIM}}"
  local w; w="$(_term_width)"
  local i
  printf '%s' "$color"
  for (( i=0; i<w; i++ )); do printf '%s' "$char"; done
  printf '%s\n' "${_C_RESET}"
}

# Rule with a title embedded at the start.
_titled_rule() {
  local title="$1"
  local color="${2:-${_C_DIM}}"
  local char="${3:-━}"
  local w; w="$(_term_width)"
  local prefix="${char}${char}${char} "
  local used=$(( ${#prefix} + ${#title} + 1 ))
  local fill=$(( w - used ))
  (( fill < 0 )) && fill=0
  printf '%s%s%s%s%s%s ' "$color" "$prefix" "${_C_BOLD}" "$title" "${_C_RESET}" "$color"
  local i
  for (( i=0; i<fill; i++ )); do printf '%s' "$char"; done
  printf '%s\n' "${_C_RESET}"
}

# ────────────────────────────────────────────────────────────
#  Step tracking + output helpers
# ────────────────────────────────────────────────────────────

CURRENT_STEP=0
TOTAL_STEPS=9
CURRENT_STEP_NAME="startup"

# Operator control wrapper paths (match setup.sh).
DEPLOYERCTL_BIN="/usr/local/sbin/deployerctl"
DEPLOYERCTL_CONFIG_DIR="/etc/deployer"
DEPLOYERCTL_CONFIG="$DEPLOYERCTL_CONFIG_DIR/deployerctl.conf"

info() { printf '  %s›%s %s\n' "${_C_DIM}" "${_C_RESET}" "$*"; }
ok()   { printf '  %s✓%s %s\n' "${_C_GREEN}" "${_C_RESET}" "$*"; }
warn() { printf '  %s!%s %s\n' "${_C_YELLOW}" "${_C_RESET}" "$*" >&2; }
hint() { printf '  %s%s%s\n' "${_C_DIM}" "$*" "${_C_RESET}"; }

die() {
  printf '\n  %s✗%s %s\n\n' "${_C_RED}${_C_BOLD}" "${_C_RESET}" "$*" >&2
  exit 1
}

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  CURRENT_STEP_NAME="$1"
  echo
  printf '%s[%d/%d]%s %s%s%s\n' \
    "${_C_DIM}" "$CURRENT_STEP" "$TOTAL_STEPS" "${_C_RESET}" \
    "${_C_BOLD}${_C_CYAN}" "$1" "${_C_RESET}"
  _rule '━' "${_C_CYAN}"
}

section() {
  echo
  printf '  %s%s%s\n' "${_C_BOLD}" "$1" "${_C_RESET}"
}

# Indent every line of piped output by four spaces.
indent_stream() {
  sed 's/^/    /'
}

card_open() {
  echo
  _titled_rule "$1" "${_C_DIM}"
  echo
}

card_kv() {
  printf '  %s%-22s%s %s\n' "${_C_BOLD}" "$1" "${_C_RESET}" "$2"
}

card_line() {
  printf '  %s\n' "$*"
}

card_close() {
  echo
  _rule '━' "${_C_DIM}"
  echo
}

# ────────────────────────────────────────────────────────────
#  Trap handlers
# ────────────────────────────────────────────────────────────

_abort() {
  echo
  printf '\n  %s!%s Aborted by user.\n\n' "${_C_YELLOW}" "${_C_RESET}" >&2
  exit 130
}
trap '_abort' INT

_on_err() {
  local exit_code=$?
  local line="$1"
  printf '\n  %s✗ Remove failed%s at line %s (exit %d)\n' \
    "${_C_RED}${_C_BOLD}" "${_C_RESET}" "$line" "$exit_code" >&2
  printf '  %sstep:%s    %s\n' "${_C_DIM}" "${_C_RESET}" "${CURRENT_STEP_NAME:-unknown}" >&2
  printf '  %scommand:%s %s\n\n' "${_C_DIM}" "${_C_RESET}" "${BASH_COMMAND:-unknown}" >&2
}
trap '_on_err $LINENO' ERR

# ────────────────────────────────────────────────────────────
#  Argument parsing
# ────────────────────────────────────────────────────────────

_usage() {
  cat <<EOF
${_C_BOLD}Vapor-Mottzi-Deployer · Remover${_C_RESET}

Tears down a deployer installation created by setup.sh: stops services,
removes generated unit/config files, deletes the app/deployer checkouts,
removes managed reverse-proxy artifacts, and removes the dedicated Linux
service user.

${_C_BOLD}Usage${_C_RESET}
  sudo ./remove.sh [options]

${_C_BOLD}Options${_C_RESET}
  -h, --help       Show this help and exit.

${_C_BOLD}Environment${_C_RESET}
  NO_COLOR         Disable ANSI colors when set.

The remover is interactive and prompts for the values it needs.
Ubuntu hosts are supported. Run as root or with sudo.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    -h|--help) _usage; exit 0 ;;
    --) shift; break ;;
    -*) printf 'Unknown option: %s\n\n' "$1" >&2; _usage >&2; exit 2 ;;
    *)  printf 'Unexpected argument: %s\n\n' "$1" >&2; _usage >&2; exit 2 ;;
  esac
  shift
done

# ────────────────────────────────────────────────────────────
#  Banner
# ────────────────────────────────────────────────────────────

_banner() {
  echo
  _rule '━' "${_C_RED}"
  printf '  %sVapor-Mottzi-Deployer%s %s· Remover%s\n' \
    "${_C_BOLD}" "${_C_RESET}" "${_C_DIM}" "${_C_RESET}"
  _rule '━' "${_C_RED}"
  echo
  printf '  %sStops services, removes managed proxy files, and deletes%s\n' "${_C_DIM}" "${_C_RESET}"
  printf '  %sthe service user created by setup.sh. This is destructive.%s\n' "${_C_DIM}" "${_C_RESET}"
  echo
}

_banner

# ────────────────────────────────────────────────────────────
#  Interactive input helpers
# ────────────────────────────────────────────────────────────

# Ask the operator to confirm a yes/no decision.
#   confirm "prompt"         → no default (must answer)
#   confirm "prompt" y       → default yes; display [Y/n]
#   confirm "prompt" n       → default no;  display [y/N]
confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-}"
  local reply label styled
  case "$default" in
    y|yes|Y) label="[Y/n]" ;;
    n|no|N)  label="[y/N]" ;;
    *)       label="[y/n]" ;;
  esac

  while true; do
    styled="$(printf '  %s%s%s %s%s%s: ' \
      "${_C_BOLD}" "$prompt" "${_C_RESET}" \
      "${_C_DIM}" "$label" "${_C_RESET}")"
    read -r -p "$styled" reply
    reply="${reply:-$default}"
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     warn "Please answer y or n." ;;
    esac
  done
}

# Ask for a value, re-prompting until a non-empty answer is available.
prompt() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local response styled

  while true; do
    if [[ -n "$default" ]]; then
      styled="$(printf '  %s%s%s %s[%s]%s: ' \
        "${_C_BOLD}" "$label" "${_C_RESET}" \
        "${_C_DIM}" "$default" "${_C_RESET}")"
      read -r -p "$styled" response
      response="${response:-$default}"
    else
      styled="$(printf '  %s%s%s: ' "${_C_BOLD}" "$label" "${_C_RESET}")"
      read -r -p "$styled" response
    fi

    if [[ -n "$response" ]]; then
      printf -v "$var_name" '%s' "$response"
      return 0
    fi

    warn "$label cannot be empty. Please try again."
  done
}

# Ask for a yes/no value and normalize it.
prompt_yes_no() {
  local var_name="$1"
  local label="$2"
  local default="${3:-n}"
  local response styled suffix

  case "$default" in
    y|yes|Y) suffix="[Y/n]" ;;
    *)       suffix="[y/N]" ;;
  esac

  while true; do
    styled="$(printf '  %s%s%s %s%s%s: ' \
      "${_C_BOLD}" "$label" "${_C_RESET}" \
      "${_C_DIM}" "$suffix" "${_C_RESET}")"
    read -r -p "$styled" response
    if [[ -z "$response" ]]; then
      case "$default" in
        y|yes|Y) response="y" ;;
        *)       response="n" ;;
      esac
    fi

    case "${response,,}" in
      y|yes)
        printf -v "$var_name" '%s' "yes"
        return 0
        ;;
      n|no)
        printf -v "$var_name" '%s' "no"
        return 0
        ;;
      *)
        warn "Enter y or n."
        ;;
    esac
  done
}

# Resolve a configured path to an absolute path using INSTALL_DIR when needed.
resolve_install_relative_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s' "$path"
  else
    printf '%s/%s' "$INSTALL_DIR" "$path"
  fi
}

# Resolve a path for safe deletion guards, even if it does not exist yet.
canonicalize_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$path"
  else
    readlink -f "$path" 2>/dev/null || printf '%s' "$path"
  fi
}

# Try to discover the most likely deployer.json for a given service home.
discover_deployer_config() {
  local service_home="$1"
  local default_config="$service_home/deployer/deployer.json"
  local candidates
  local candidate

  if [[ -f "$default_config" ]]; then
    printf '%s' "$default_config"
    return 0
  fi

  [[ -d "$service_home" ]] || return 1

  candidates="$(find "$service_home" -maxdepth 4 -type f -name deployer.json 2>/dev/null || true)"
  [[ -n "$candidates" ]] || return 1

  # Prefer candidates that look like a deployer checkout root.
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$(dirname "$candidate")/Package.swift" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done <<< "$candidates"

  # Fall back to the first discovered config file.
  printf '%s' "$candidates" | head -n 1
}

# Read a single value from deployerctl config when present.
read_deployerctl_value() {
  local key="$1"
  [[ -r "$DEPLOYERCTL_CONFIG" ]] || return 0
  DEPLOYERCTL_FILE="$DEPLOYERCTL_CONFIG" DEPLOYERCTL_KEY="$key" \
    bash -c '
      set -Eeuo pipefail
      # shellcheck disable=SC1090
      source "$DEPLOYERCTL_FILE"
      printf "%s" "${!DEPLOYERCTL_KEY:-}"
    ' 2>/dev/null || true
}

# Run a command as the dedicated service user.
as_user() {
  local command="$1"
  su - "$SERVICE_USER" -s /bin/bash -c "$command"
}

# Run systemctl against the dedicated user's systemd user manager.
as_user_systemctl() {
  local command="$1"
  local uid
  uid="$(id -u "$SERVICE_USER")"
  as_user "XDG_RUNTIME_DIR=/run/user/$uid systemctl --user $command"
}

# Remove the operator control wrapper (`deployerctl`) and its config.
# Leaves /etc/deployer in place only if it still contains unrelated files.
remove_deployerctl() {
  local removed_any=0

  if [[ -e "$DEPLOYERCTL_BIN" || -L "$DEPLOYERCTL_BIN" ]]; then
    rm -f "$DEPLOYERCTL_BIN"
    info "Removed $DEPLOYERCTL_BIN"
    removed_any=1
  fi

  if [[ -f "$DEPLOYERCTL_CONFIG" ]]; then
    rm -f "$DEPLOYERCTL_CONFIG"
    info "Removed $DEPLOYERCTL_CONFIG"
    removed_any=1
  fi

  if [[ -d "$DEPLOYERCTL_CONFIG_DIR" ]]; then
    # rmdir only if empty; leave in place if operators added other files.
    if rmdir "$DEPLOYERCTL_CONFIG_DIR" 2>/dev/null; then
      info "Removed $DEPLOYERCTL_CONFIG_DIR"
    fi
  fi

  (( removed_any == 0 )) && info "Operator control wrapper was not present"
  return 0
}

# Remove generated Supervisor config files for deployer and the managed app.
remove_supervisor_files() {
  rm -f /etc/supervisor/conf.d/deployer.conf
  rm -f "/etc/supervisor/conf.d/${PRODUCT_NAME}.conf"
}

# Remove managed reverse-proxy files generated by setup.sh.
remove_reverse_proxy_artifacts() {
  local removed_any=0

  if [[ -n "${NGINX_SITE_ENABLED:-}" ]]; then
    if [[ "$NGINX_SITE_ENABLED" == /etc/nginx/sites-enabled/* ]]; then
      if [[ -L "$NGINX_SITE_ENABLED" || -e "$NGINX_SITE_ENABLED" ]]; then
        rm -f "$NGINX_SITE_ENABLED"
        info "Removed Nginx site entry: $NGINX_SITE_ENABLED"
        removed_any=1
      fi
    else
      warn "Skipping Nginx site entry outside /etc/nginx/sites-enabled: $NGINX_SITE_ENABLED"
    fi
  fi

  if [[ -n "${NGINX_SITE_AVAILABLE:-}" ]]; then
    if [[ "$NGINX_SITE_AVAILABLE" == /etc/nginx/sites-available/* ]]; then
      if [[ -f "$NGINX_SITE_AVAILABLE" ]]; then
        rm -f "$NGINX_SITE_AVAILABLE"
        info "Removed Nginx site file: $NGINX_SITE_AVAILABLE"
        removed_any=1
      fi
    else
      warn "Skipping Nginx site file outside /etc/nginx/sites-available: $NGINX_SITE_AVAILABLE"
    fi
  fi

  if [[ -n "${CERTBOT_RENEW_HOOK:-}" ]]; then
    if [[ "$CERTBOT_RENEW_HOOK" == /etc/letsencrypt/renewal-hooks/deploy/* ]]; then
      if [[ -f "$CERTBOT_RENEW_HOOK" ]]; then
        rm -f "$CERTBOT_RENEW_HOOK"
        info "Removed Certbot renewal hook: $CERTBOT_RENEW_HOOK"
        removed_any=1
      fi
    else
      warn "Skipping renewal hook outside /etc/letsencrypt/renewal-hooks/deploy: $CERTBOT_RENEW_HOOK"
    fi
  fi

  if [[ -n "${ACME_WEBROOT:-}" && -d "$ACME_WEBROOT" ]]; then
    if [[ "$ACME_WEBROOT" == /var/www/certbot/* ]]; then
      rm -rf "$ACME_WEBROOT"
      info "Removed ACME webroot: $ACME_WEBROOT"
      removed_any=1
    else
      warn "Skipping ACME webroot cleanup because path is outside /var/www/certbot: $ACME_WEBROOT"
    fi
  fi

  if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
      systemctl reload nginx >/dev/null 2>&1 || true
      info "Reloaded nginx"
    else
      warn "Nginx config test failed after cleanup; run 'nginx -t' manually."
    fi
  fi

  if (( removed_any == 0 )); then info "Managed reverse-proxy artifacts were not present"; fi
}

# Optionally remove the managed Let's Encrypt certificate lineage.
remove_tls_certificate_if_requested() {
  [[ -n "${CERT_NAME:-}" ]] || {
    info "No managed certificate name configured; skipping cert deletion prompt"
    return 0
  }

  confirm "Delete Let's Encrypt certificate '$CERT_NAME' as well?" n || {
    info "Keeping certificate lineage '$CERT_NAME'"
    return 0
  }

  if ! command -v certbot >/dev/null 2>&1; then
    warn "certbot is not installed; cannot remove certificate '$CERT_NAME'."
    return 0
  fi

  if certbot delete --non-interactive --cert-name "$CERT_NAME" >/dev/null 2>&1; then
    ok "Deleted certificate lineage '$CERT_NAME'"
  else
    warn "Could not delete certificate lineage '$CERT_NAME'. It may not exist."
  fi
}

# Stop/disable user-level systemd units and remove generated unit files.
remove_user_units() {
  local unit_dir="$SERVICE_HOME/.config/systemd/user"
  if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    as_user_systemctl "disable --now deployer.service ${PRODUCT_NAME}.service" >/dev/null 2>&1 || true
    as_user "rm -f '$unit_dir/deployer.service' '$unit_dir/${PRODUCT_NAME}.service'" || true
    as_user_systemctl "daemon-reload" >/dev/null 2>&1 || true
    loginctl disable-linger "$SERVICE_USER" >/dev/null 2>&1 || true
  else
    rm -f "$unit_dir/deployer.service" "$unit_dir/${PRODUCT_NAME}.service" >/dev/null 2>&1 || true
  fi
}

# Remove the generated app deploy key and prune the SSH config reference.
remove_ssh_material() {
  local key_base="$SERVICE_HOME/.ssh/${APP_NAME}_deploy_key"
  local ssh_config="$SERVICE_HOME/.ssh/config"

  if [[ -f "$key_base" || -f "${key_base}.pub" ]]; then
    info "Removing deploy key files for app '$APP_NAME'"
  fi

  rm -f "$key_base" "${key_base}.pub" >/dev/null 2>&1 || true

  if [[ -f "$ssh_config" ]]; then
    sed -i.bak "\|IdentityFile $key_base|d" "$ssh_config" || true
    sed -i "\|deployer-managed-$APP_NAME|d" "$ssh_config" || true
    rm -f "${ssh_config}.bak" >/dev/null 2>&1 || true
  fi
}

# Remove a directory with basic safety guards.
remove_directory() {
  local path="$1"
  local label="$2"
  local resolved_path

  [[ -n "$path" ]] || die "Refusing to delete an empty path for $label."
  resolved_path="$(canonicalize_path "$path")"
  [[ "$resolved_path" != "/" ]] || die "Refusing to delete '/'."
  [[ "$resolved_path" != "/home" ]] || die "Refusing to delete '/home'."
  [[ "$resolved_path" != "/root" ]] || die "Refusing to delete '/root'."
  [[ "$resolved_path" != "$SERVICE_HOME" ]] || die "Refusing to delete service home directly: $SERVICE_HOME"

  if [[ -d "$resolved_path" ]]; then
    info "Removing $label: $resolved_path"
    rm -rf "$resolved_path"
  fi
}

# Remove the dedicated service user and its home directory.
remove_user() {
  if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    local attempt
    local active_pids

    info "Removing user '$SERVICE_USER'"
    loginctl terminate-user "$SERVICE_USER" >/dev/null 2>&1 || true
    loginctl disable-linger "$SERVICE_USER" >/dev/null 2>&1 || true

    for attempt in {1..10}; do
      active_pids="$(pgrep -u "$SERVICE_USER" || true)"
      [[ -z "$active_pids" ]] && break
      pkill -TERM -u "$SERVICE_USER" >/dev/null 2>&1 || true
      sleep 1
    done

    pkill -KILL -u "$SERVICE_USER" >/dev/null 2>&1 || true

    for attempt in {1..10}; do
      if userdel -r "$SERVICE_USER" >/dev/null 2>&1; then
        ok "Removed user '$SERVICE_USER'"
        return 0
      fi

      id -u "$SERVICE_USER" >/dev/null 2>&1 || return 0
      loginctl terminate-user "$SERVICE_USER" >/dev/null 2>&1 || true
      pkill -KILL -u "$SERVICE_USER" >/dev/null 2>&1 || true
      sleep 1
    done

    active_pids="$(pgrep -u "$SERVICE_USER" || true)"
    if [[ -n "$active_pids" ]]; then
      die "Unable to remove user '$SERVICE_USER'. Active PIDs remain: $active_pids"
    fi

    userdel -r "$SERVICE_USER" || die "Unable to remove user '$SERVICE_USER'."
  else
    info "User '$SERVICE_USER' already absent"
  fi
}

# ────────────────────────────────────────────────────────────
#  Preflight
# ────────────────────────────────────────────────────────────

# The remover needs root privileges to stop services and delete users/files.
[[ $EUID -eq 0 ]] || die "Run as root or with sudo."

# Keep the first version Ubuntu-only so service paths/behavior stay predictable.
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This remover currently supports Ubuntu only."

step "Collecting removal values"

# Ask for service user first so defaults can be inferred around that identity.
section "Service identity"
hint "The dedicated Linux account that owns the deployer installation."
prompt SERVICE_USER "Dedicated service user" "vapor"
SERVICE_HOME="/home/$SERVICE_USER"

if id -u "$SERVICE_USER" >/dev/null 2>&1; then
  EXISTING_HOME_DISCOVERED="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
  info "Found user '$SERVICE_USER' (home: $EXISTING_HOME_DISCOVERED)"
else
  warn "User '$SERVICE_USER' does not exist — some cleanup steps will be no-ops"
fi

# Infer install directory from the selected service user and auto-discovered config.
section "Installation paths"
INSTALL_DIR_DEFAULT="$SERVICE_HOME/deployer"
DISCOVERED_CONFIG_FILE="$(discover_deployer_config "$SERVICE_HOME" || true)"
if [[ -n "$DISCOVERED_CONFIG_FILE" ]]; then
  INSTALL_DIR_DEFAULT="$(dirname "$DISCOVERED_CONFIG_FILE")"
  info "Discovered deployer config: $DISCOVERED_CONFIG_FILE"
fi

hint "Absolute path to the deployer checkout directory."
prompt INSTALL_DIR "Deployer install directory" "$INSTALL_DIR_DEFAULT"
if [[ -r "$DEPLOYERCTL_CONFIG" ]]; then
  info "Discovered deployerctl metadata: $DEPLOYERCTL_CONFIG"
fi

# Derive best-effort defaults from the install/config so prompts stay minimal.
CONFIG_FILE="$INSTALL_DIR/deployer.json"
PRODUCT_DEFAULT="deployer-app"
APP_DIR_REL_DEFAULT="../apps/app"
APP_NAME_DEFAULT="app"
WEBHOOK_PATH_DEFAULT="/pushevent/app"
SERVICE_MANAGER_DEFAULT="systemd"
PRIMARY_DOMAIN_FROM_CTL="$(read_deployerctl_value "PRIMARY_DOMAIN")"
ALIAS_DOMAIN_FROM_CTL="$(read_deployerctl_value "ALIAS_DOMAIN")"
CERT_NAME_FROM_CTL="$(read_deployerctl_value "CERT_NAME")"
NGINX_SITE_NAME_FROM_CTL="$(read_deployerctl_value "NGINX_SITE_NAME")"
NGINX_SITE_AVAILABLE_FROM_CTL="$(read_deployerctl_value "NGINX_SITE_AVAILABLE")"
NGINX_SITE_ENABLED_FROM_CTL="$(read_deployerctl_value "NGINX_SITE_ENABLED")"
ACME_WEBROOT_FROM_CTL="$(read_deployerctl_value "ACME_WEBROOT")"
CERTBOT_RENEW_HOOK_FROM_CTL="$(read_deployerctl_value "CERTBOT_RENEW_HOOK")"
WEBHOOK_PATH_FROM_CTL="$(read_deployerctl_value "WEBHOOK_PATH")"
GITHUB_WEBHOOK_SETTINGS_URL_FROM_CTL="$(read_deployerctl_value "GITHUB_WEBHOOK_SETTINGS_URL")"

if [[ -f "$CONFIG_FILE" && -x "$(command -v jq)" ]]; then
  PRODUCT_DEFAULT="$(jq -r '.target.name // empty' "$CONFIG_FILE")"
  APP_DIR_REL_DEFAULT="$(jq -r '.target.directory // empty' "$CONFIG_FILE")"
  WEBHOOK_PATH_DEFAULT="$(jq -r '.target.pusheventPath // empty' "$CONFIG_FILE")"
  SERVICE_MANAGER_DEFAULT="$(jq -r '.serviceManager // empty' "$CONFIG_FILE")"
fi

[[ -n "$PRODUCT_DEFAULT" ]] || PRODUCT_DEFAULT="mottzi"
[[ -n "$APP_DIR_REL_DEFAULT" ]] || APP_DIR_REL_DEFAULT="../apps/$PRODUCT_DEFAULT"
[[ -n "$WEBHOOK_PATH_FROM_CTL" ]] && WEBHOOK_PATH_DEFAULT="$WEBHOOK_PATH_FROM_CTL"
[[ -n "$WEBHOOK_PATH_DEFAULT" ]] || WEBHOOK_PATH_DEFAULT="/pushevent/$PRODUCT_DEFAULT"
[[ -n "$SERVICE_MANAGER_DEFAULT" ]] || SERVICE_MANAGER_DEFAULT="systemd"
APP_DIR_DEFAULT="$(resolve_install_relative_path "$APP_DIR_REL_DEFAULT")"
APP_NAME_DEFAULT="$(basename "$APP_DIR_DEFAULT")"
PRIMARY_DOMAIN_DEFAULT="${PRIMARY_DOMAIN_FROM_CTL:-example.com}"
ALIAS_DOMAIN_DEFAULT="${ALIAS_DOMAIN_FROM_CTL:-www.${PRIMARY_DOMAIN_DEFAULT#www.}}"
CERT_NAME_DEFAULT="${CERT_NAME_FROM_CTL:-$PRIMARY_DOMAIN_DEFAULT}"
NGINX_SITE_NAME_DEFAULT="${NGINX_SITE_NAME_FROM_CTL:-deployer-${APP_NAME_DEFAULT}}"
NGINX_SITE_AVAILABLE_DEFAULT="${NGINX_SITE_AVAILABLE_FROM_CTL:-/etc/nginx/sites-available/${NGINX_SITE_NAME_DEFAULT}.conf}"
NGINX_SITE_ENABLED_DEFAULT="${NGINX_SITE_ENABLED_FROM_CTL:-/etc/nginx/sites-enabled/${NGINX_SITE_NAME_DEFAULT}.conf}"
ACME_WEBROOT_DEFAULT="${ACME_WEBROOT_FROM_CTL:-/var/www/certbot/${APP_NAME_DEFAULT}}"
CERTBOT_RENEW_HOOK_DEFAULT="${CERTBOT_RENEW_HOOK_FROM_CTL:-/etc/letsencrypt/renewal-hooks/deploy/${NGINX_SITE_NAME_DEFAULT}-reload-nginx.sh}"

# Collect the core identifiers we need for teardown.
section "Target app"
hint "The executable product / service name (as configured in deployer.json)."
prompt PRODUCT_NAME "Target product/service name" "$PRODUCT_DEFAULT"
hint "Absolute path to the app checkout directory."
prompt APP_DIR "Target app checkout directory" "$APP_DIR_DEFAULT"
if [[ "$APP_DIR" != /* ]]; then
  APP_DIR="$(resolve_install_relative_path "$APP_DIR")"
fi
hint "Short app name used to derive the SSH deploy key filename."
prompt APP_NAME "App name (used for SSH deploy key filename)" "$APP_NAME_DEFAULT"

GITHUB_WEBHOOK_SETTINGS_URL="${GITHUB_WEBHOOK_SETTINGS_URL_FROM_CTL:-}"

section "Runtime"
hint "Which process manager was used: 'systemd' or 'supervisor'."
prompt SERVICE_MANAGER "Service manager" "$SERVICE_MANAGER_DEFAULT"

# Reverse-proxy metadata defaults come from deployerctl config when available.
PRIMARY_DOMAIN="${PRIMARY_DOMAIN_FROM_CTL:-$PRIMARY_DOMAIN_DEFAULT}"
ALIAS_DOMAIN="${ALIAS_DOMAIN_FROM_CTL:-$ALIAS_DOMAIN_DEFAULT}"
CERT_NAME="${CERT_NAME_FROM_CTL:-$CERT_NAME_DEFAULT}"
NGINX_SITE_NAME="${NGINX_SITE_NAME_FROM_CTL:-deployer-${APP_NAME}}"
NGINX_SITE_AVAILABLE="${NGINX_SITE_AVAILABLE_FROM_CTL:-/etc/nginx/sites-available/${NGINX_SITE_NAME}.conf}"
NGINX_SITE_ENABLED="${NGINX_SITE_ENABLED_FROM_CTL:-/etc/nginx/sites-enabled/${NGINX_SITE_NAME}.conf}"
ACME_WEBROOT="${ACME_WEBROOT_FROM_CTL:-/var/www/certbot/${APP_NAME}}"
CERTBOT_RENEW_HOOK="${CERTBOT_RENEW_HOOK_FROM_CTL:-/etc/letsencrypt/renewal-hooks/deploy/${NGINX_SITE_NAME}-reload-nginx.sh}"

step "Removal summary"

card_open "Removal summary"
card_kv "Install dir"      "$INSTALL_DIR"
card_kv "App dir"          "$APP_DIR"
card_kv "Service user"     "$SERVICE_USER"
card_kv "Service manager"  "$SERVICE_MANAGER"
card_kv "Product name"     "$PRODUCT_NAME"
card_kv "App name"         "$APP_NAME"
card_kv "Canonical domain" "$PRIMARY_DOMAIN"
card_kv "Alias domain"     "$ALIAS_DOMAIN"
card_kv "Nginx site file"  "$NGINX_SITE_AVAILABLE"
card_kv "ACME webroot"     "$ACME_WEBROOT"
card_kv "Cert lineage"     "$CERT_NAME"
echo
printf '  %s%sThis will (destructive):%s\n' "${_C_BOLD}" "${_C_YELLOW}" "${_C_RESET}"
printf '    %s•%s stop/disable deployer and app services (user-systemd + supervisor cleanup)\n' "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s reload user systemd manager\n' "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s remove generated unit/config files\n' "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s remove managed Nginx site files, ACME webroot, and renewal hook\n' "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s remove operator control wrapper (%s and %s)\n' "${_C_DIM}" "${_C_RESET}" "$DEPLOYERCTL_BIN" "$DEPLOYERCTL_CONFIG"
printf '    %s•%s remove deploy SSH key files for this app\n' "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s remove deployer and app checkout directories\n' "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s remove Linux user and home directory\n' "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s optionally delete certificate lineage: %s\n' "${_C_DIM}" "${_C_RESET}" "$CERT_NAME"
card_close

confirm "Proceed with teardown?" n || die "Cancelled."

# Stop running services and remove generated service definitions first.
step "Stopping and removing services"
remove_user_units
remove_supervisor_files
if command -v supervisorctl >/dev/null 2>&1; then
  supervisorctl stop deployer >/dev/null 2>&1 || true
  supervisorctl stop "$PRODUCT_NAME" >/dev/null 2>&1 || true
  supervisorctl reread >/dev/null 2>&1 || true
  supervisorctl update >/dev/null 2>&1 || true
fi
ok "Services stopped and unit/config files removed"

step "Cleaning reverse proxy artifacts"
remove_reverse_proxy_artifacts
remove_tls_certificate_if_requested
ok "Managed reverse-proxy artifacts cleaned up"

# Remove the root-owned operator control wrapper and its config so
# `sudo deployerctl ...` does not linger after teardown.
step "Removing operator control wrapper"
remove_deployerctl
ok "Operator control wrapper cleaned up"

# Remove generated runtime artifacts from the deployer install tree.
step "Removing deployer-generated files"
rm -f "$INSTALL_DIR/deployer" \
      "$INSTALL_DIR/deployer.json" \
      "$INSTALL_DIR/deployer.db" \
      "$INSTALL_DIR/deployer.log" >/dev/null 2>&1 || true
info "Removed deployer binary, config, database, and log files"

if [[ -d "$APP_DIR/deploy" ]]; then
  rm -rf "$APP_DIR/deploy"
  info "Removed app deploy directory"
fi

# Remove deploy SSH materials so no lingering app access keys remain.
step "Removing SSH deploy keys"
remove_ssh_material

# Remove checkout directories before deleting the user account.
step "Removing checkout directories"
remove_directory "$APP_DIR" "app checkout"
remove_directory "$INSTALL_DIR" "deployer checkout"

# Remove the dedicated service user and lingering home-directory data.
step "Removing service user"
remove_user

# ────────────────────────────────────────────────────────────
#  Success card
# ────────────────────────────────────────────────────────────

echo
_titled_rule "✓ Removal complete" "${_C_GREEN}"
echo
card_kv "Service user"     "$SERVICE_USER (removed)"
card_kv "Install dir"      "$INSTALL_DIR (removed)"
card_kv "App dir"          "$APP_DIR (removed)"
card_kv "Nginx site"       "$NGINX_SITE_AVAILABLE (removed if present)"
card_kv "ACME webroot"     "$ACME_WEBROOT (removed if present)"
echo
printf '  %sManual follow-up%s\n' "${_C_BOLD}" "${_C_RESET}"
printf '    %s•%s Delete the GitHub webhook pointing at:\n' "${_C_DIM}" "${_C_RESET}"
printf '      %s%s%s\n' "${_C_CYAN}" "$WEBHOOK_PATH_DEFAULT" "${_C_RESET}"
if [[ -n "$GITHUB_WEBHOOK_SETTINGS_URL" ]]; then
  printf '      %s%s%s\n' "${_C_CYAN}" "$GITHUB_WEBHOOK_SETTINGS_URL" "${_C_RESET}"
else
  printf '      %s(GitHub repo → Settings → Webhooks)%s\n' "${_C_DIM}" "${_C_RESET}"
fi
echo
_rule '━' "${_C_GREEN}"
echo
