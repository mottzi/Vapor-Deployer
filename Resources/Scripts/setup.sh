#!/usr/bin/env bash

# Exit on errors, undefined variables, and failed pipeline parts.
set -Eeuo pipefail

# ────────────────────────────────────────────────────────────
#  Terminal styling
# ────────────────────────────────────────────────────────────

# Only emit ANSI escapes when stdout is a TTY and the operator has not opted out via NO_COLOR.
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

# Detect a sensible terminal width, capped at 100 for readability.
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

# Print a horizontal rule of the given character across the terminal width.
_rule() {
  local char="${1:-━}"
  local color="${2:-${_C_DIM}}"
  local w; w="$(_term_width)"
  local i
  printf '%s' "$color"
  for (( i=0; i<w; i++ )); do printf '%s' "$char"; done
  printf '%s\n' "${_C_RESET}"
}

# Print a rule with a title embedded at the start, e.g. "━━━ Title ━━━━━━".
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
TOTAL_STEPS=21
CURRENT_STEP_NAME="startup"

# Small progress message with a dim chevron prefix.
info() { printf '  %s›%s %s\n' "${_C_DIM}" "${_C_RESET}" "$*"; }

# Success affirmation with a green check.
ok() { printf '  %s✓%s %s\n' "${_C_GREEN}" "${_C_RESET}" "$*"; }

# Non-fatal warning with a yellow bang.
warn() { printf '  %s!%s %s\n' "${_C_YELLOW}" "${_C_RESET}" "$*" >&2; }

# Dim descriptive text, used to explain prompt fields.
hint() { printf '  %s%s%s\n' "${_C_DIM}" "$*" "${_C_RESET}"; }

# Fatal error: styled red cross, then exit.
die() {
  printf '\n  %s✗%s %s\n\n' "${_C_RED}${_C_BOLD}" "${_C_RESET}" "$*" >&2
  exit 1
}

# Numbered step header with title and a rule underneath.
step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  CURRENT_STEP_NAME="$1"
  echo
  printf '%s[%d/%d]%s %s%s%s\n' \
    "${_C_DIM}" "$CURRENT_STEP" "$TOTAL_STEPS" "${_C_RESET}" \
    "${_C_BOLD}${_C_CYAN}" "$1" "${_C_RESET}"
  _rule '━' "${_C_CYAN}"
}

# Sub-section label used inside a step to group related prompts or output.
section() {
  echo
  printf '  %s%s%s\n' "${_C_BOLD}" "$1" "${_C_RESET}"
}

# Indent every line of piped output by four spaces so noisy subprocesses
# stay visually subordinate to step headers.
indent_stream() {
  sed 's/^/    /'
}

# Run a command as the service user while only showing a rolling tail of output.
# On failure, print the full captured log to aid debugging.
run_compact_as_user() {
  local command="$1"
  local tail_lines="${2:-6}"
  local stdout_log
  local stderr_log
  local cmd_pid
  local status=0
  local rendered_lines=0
  local i
  local line
  local -a recent_lines=()

  stdout_log="$(mktemp)"
  stderr_log="$(mktemp)"
  as_user "$command" >"$stdout_log" 2>"$stderr_log" &
  cmd_pid=$!

  if [[ -t 1 ]]; then
    while kill -0 "$cmd_pid" 2>/dev/null; do
      mapfile -t recent_lines < <(tail -n "$tail_lines" "$stdout_log" 2>/dev/null || true)

      if (( rendered_lines > 0 )); then
        for (( i=0; i<rendered_lines; i++ )); do
          printf '\r\033[1A\033[2K'
        done
      fi

      rendered_lines=0
      for line in "${recent_lines[@]}"; do
        printf '    %s\n' "$line"
        rendered_lines=$((rendered_lines + 1))
      done

      sleep 0.2
    done

    wait "$cmd_pid" || status=$?

    mapfile -t recent_lines < <(tail -n "$tail_lines" "$stdout_log" 2>/dev/null || true)
    if (( rendered_lines > 0 )); then
      for (( i=0; i<rendered_lines; i++ )); do
        printf '\r\033[1A\033[2K'
      done
    fi
    for line in "${recent_lines[@]}"; do
      printf '    %s\n' "$line"
    done
  else
    wait "$cmd_pid" || status=$?
    tail -n "$tail_lines" "$stdout_log" | indent_stream
  fi

  if (( status != 0 )); then
    printf '    Build failed. Full error output:\n' >&2
    if [[ -s "$stderr_log" ]]; then
      cat "$stderr_log" | indent_stream >&2
    else
      printf '    (No stderr output was captured.)\n' >&2
    fi
    rm -f "$stdout_log" "$stderr_log"
    return "$status"
  fi

  rm -f "$stdout_log" "$stderr_log"
}

# Open a card-style block with a title embedded in the top rule.
card_open() {
  echo
  _titled_rule "$1" "${_C_DIM}"
  echo
}

# Aligned key/value row inside a card.
card_kv() {
  printf '  %s%-22s%s %s\n' "${_C_BOLD}" "$1" "${_C_RESET}" "$2"
}

# Freeform indented line inside a card.
card_line() {
  printf '  %s\n' "$*"
}

# Close a card with a bottom rule and spacing.
card_close() {
  echo
  _rule '━' "${_C_DIM}"
  echo
}

# ────────────────────────────────────────────────────────────
#  Trap handlers
# ────────────────────────────────────────────────────────────

# Clean exit on Ctrl-C; suppress the default "^C" noise.
_abort() {
  echo
  printf '\n  %s!%s Aborted by user.\n\n' "${_C_YELLOW}" "${_C_RESET}" >&2
  exit 130
}
trap '_abort' INT

# Print the failing line, step, and command when the script aborts unexpectedly.
_on_err() {
  local exit_code=$?
  local line="$1"
  printf '\n  %s✗ Setup failed%s at line %s (exit %d)\n' \
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
${_C_BOLD}Vapor-Mottzi-Deployer · Installer${_C_RESET}

Installs the deployer service alongside a target Vapor app, configures
systemd or supervisor to run both, provisions managed Nginx + TLS
(Let's Encrypt), and registers a GitHub push webhook.

${_C_BOLD}Usage${_C_RESET}
  sudo ./setup.sh [options]

${_C_BOLD}Options${_C_RESET}
  -h, --help       Show this help and exit.

${_C_BOLD}Environment${_C_RESET}
  NO_COLOR         Disable ANSI colors when set.

The installer is interactive and prompts for the values it needs.
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
  _rule '━' "${_C_CYAN}"
  printf '  %sVapor-Mottzi-Deployer%s %s· Installer%s\n' \
    "${_C_BOLD}" "${_C_RESET}" "${_C_DIM}" "${_C_RESET}"
  _rule '━' "${_C_CYAN}"
  echo
  printf '  %sInstalls the deployer + target app, configures services,%s\n' "${_C_DIM}" "${_C_RESET}"
  printf '  %sprovisions Nginx + TLS, and wires the GitHub webhook.%s\n' "${_C_DIM}" "${_C_RESET}"
  echo
}

_banner

# ────────────────────────────────────────────────────────────
#  Interactive input helpers
# ────────────────────────────────────────────────────────────

# Ask for yes/no confirmation.
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
# If a default is provided, pressing enter accepts it.
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

# Ask for a secret without echoing it to the terminal.
prompt_secret() {
  local var_name="$1"
  local label="$2"
  local value styled

  while true; do
    styled="$(printf '  %s%s%s: ' "${_C_BOLD}" "$label" "${_C_RESET}")"
    read -r -s -p "$styled" value
    echo

    if [[ -n "$value" ]]; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi

    warn "$label is required. Please try again."
  done
}

# Ask for a secret twice so typos do not lock the operator out immediately.
prompt_secret_confirm() {
  local var_name="$1"
  local label="$2"
  local first second styled_first styled_second

  while true; do
    styled_first="$(printf '  %s%s%s: ' "${_C_BOLD}" "$label" "${_C_RESET}")"
    read -r -s -p "$styled_first" first
    echo
    [[ -n "$first" ]] || {
      warn "$label is required. Please try again."
      continue
    }

    styled_second="$(printf '  %sConfirm %s%s: ' "${_C_BOLD}" "$label" "${_C_RESET}")"
    read -r -s -p "$styled_second" second
    echo

    if [[ "$first" == "$second" ]]; then
      printf -v "$var_name" '%s' "$first"
      return 0
    fi

    warn "Values did not match. Please try again."
  done
}

# Ask for a username value and reject root.
prompt_non_root_user() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local value

  while true; do
    prompt value "$label" "$default"
    if [[ "$value" == "root" ]]; then
      warn "$label may not be root. Please choose a dedicated user."
      continue
    fi
    printf -v "$var_name" '%s' "$value"
    return 0
  done
}

# Ask for a name that is safe for paths, service names, and webhook paths.
prompt_safe_name() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local value

  while true; do
    prompt value "$label" "$default"
    if [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    warn "$label may contain only letters, numbers, dots, dashes, and underscores."
  done
}

# Ask for a TCP port value.
prompt_port() {
  local var_name="$1"
  local label="$2"
  local default="$3"
  local value

  while true; do
    prompt value "$label" "$default"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 )); then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    warn "$label must be a number between 1 and 65535."
  done
}

# Ask for a GitHub SSH repo URL and extract owner/repo.
prompt_github_repo_url() {
  local var_name="$1"
  local label="$2"
  local value

  while true; do
    prompt value "$label"
    if [[ "$value" =~ ^git@github\.com:([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)(\.git)?$ ]]; then
      printf -v "$var_name" '%s' "$value"
      GITHUB_OWNER="${BASH_REMATCH[1]}"
      GITHUB_REPO="${BASH_REMATCH[2]}"
      GITHUB_REPO="${GITHUB_REPO%.git}"
      return 0
    fi
    warn "Use a GitHub SSH URL like git@github.com:owner/repo.git"
  done
}

# Ask for the service manager kind.
prompt_service_manager() {
  local var_name="$1"
  local label="$2"
  local default="$3"
  local value

  while true; do
    prompt value "$label" "$default"
    if [[ "$value" == "systemd" || "$value" == "supervisor" ]]; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    warn "$label must be 'systemd' or 'supervisor'."
  done
}

# Ask for a public base URL and normalize it.
prompt_base_url() {
  local var_name="$1"
  local label="$2"
  local value
  local normalized

  while true; do
    prompt value "$label"
    normalized="${value%/}"
    normalized="${normalized,,}"
    if is_valid_public_base_url "$normalized"; then
      printf -v "$var_name" '%s' "$normalized"
      return 0
    fi
    warn "Public base URL must look like https://example.com (HTTPS + domain only, no path, no port)."
  done
}

# Ask for an email address used for TLS registration/renewal notices.
prompt_email() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local value

  while true; do
    prompt value "$label" "$default"
    value="${value,,}"
    if is_valid_email "$value"; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    warn "$label must be a valid email address (e.g. admin@example.com)."
  done
}

# Run a command as the dedicated service user.
as_user() {
  local command="$1"
  su - "$SERVICE_USER" -s /bin/bash -c "$command"
}

# Restrict names used in paths, service names, and webhook paths to safe characters.
require_safe_name() {
  local value="$1"
  local label="$2"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || die "$label may contain only letters, numbers, dots, dashes, and underscores."
}

# Validate a TCP port number.
require_port() {
  local value="$1"
  local label="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$label must be a number."
  (( value >= 1 && value <= 65535 )) || die "$label must be between 1 and 65535."
}

# Normalize the panel route so it always has a leading slash and no trailing slash.
normalize_panel_route() {
  local value="$1"
  value="/${value#/}"
  if [[ "$value" != "/" ]]; then
    value="${value%/}"
  fi
  printf '%s' "$value"
}

# Validate a public base URL like https://example.com.
# The installer expects only the origin here, not a path.
is_valid_public_base_url() {
  local value="$1"
  value="${value%/}"
  [[ "$value" =~ ^https://([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+)$ ]]
}

# Validate an operator email used by Certbot.
is_valid_email() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Normalize and enforce an HTTPS + FQDN-only public origin.
normalize_base_url() {
  local value="$1"
  value="${value%/}"
  value="${value,,}"
  is_valid_public_base_url "$value" \
    || die "Public base URL must look like https://example.com (HTTPS + domain only, no path, no port)."
  printf '%s' "$value"
}

# Extract the hostname from a normalized public base URL.
extract_base_url_host() {
  local value
  value="$(normalize_base_url "$1")"
  printf '%s' "${value#https://}"
}

# Derive the non-canonical counterpart host (www ↔ apex).
derive_alias_domain() {
  local host="$1"
  if [[ "$host" == www.* ]]; then
    printf '%s' "${host#www.}"
  else
    printf 'www.%s' "$host"
  fi
}

# Return success when DNS resolution succeeds for a hostname.
hostname_resolves() {
  local host="$1"
  getent ahosts "$host" >/dev/null 2>&1
}

# Fail fast if DNS for a required hostname cannot be resolved.
require_resolvable_hostname() {
  local host="$1"
  local label="$2"
  hostname_resolves "$host" || die "$label '$host' does not resolve in DNS. Point it to this server before continuing."
}

# Write a root-owned file atomically from stdin.
write_root_file() {
  local destination="$1"
  local mode="${2:-0644}"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  install -m "$mode" -o root -g root "$tmp" "$destination"
  rm -f "$tmp"
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

# Capture previous managed proxy metadata so reruns can clean old files.
load_previous_proxy_metadata() {
  PREVIOUS_NGINX_SITE_NAME="$(read_deployerctl_value "NGINX_SITE_NAME")"
  PREVIOUS_NGINX_SITE_AVAILABLE="$(read_deployerctl_value "NGINX_SITE_AVAILABLE")"
  PREVIOUS_NGINX_SITE_ENABLED="$(read_deployerctl_value "NGINX_SITE_ENABLED")"
  PREVIOUS_CERTBOT_RENEW_HOOK="$(read_deployerctl_value "CERTBOT_RENEW_HOOK")"
}

# Create a random hex secret without requiring extra tools beyond the base system.
generate_hex_secret() {
  od -An -tx1 -N 32 /dev/urandom | tr -d ' \n'
}

# Escape values embedded inside generated service-manager config files.
escaped_config_value() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

# Build a systemd KEY=value assignment that is safe inside Environment="...".
systemd_environment_assignment() {
  local key="$1"
  local value="$2"
  printf '%s=%s' "$key" "$(escaped_config_value "$value")"
}

# Build a safe value for Supervisor's quoted environment= assignments.
supervisor_environment_value() {
  escaped_config_value "$1"
}

# Run systemctl against the dedicated user's systemd user manager.
as_user_systemctl() {
  local command="$1"
  local uid
  uid="$(id -u "$SERVICE_USER")"
  as_user "XDG_RUNTIME_DIR=/run/user/$uid systemctl --user $command"
}

# Return the current runtime status for a managed service.
service_status() {
  local service_name="$1"

  case "$SERVICE_MANAGER" in
    systemd)
      as_user_systemctl "is-active ${service_name}.service" 2>/dev/null || true
      ;;
    supervisor)
      supervisorctl status "$service_name" 2>/dev/null | awk '{print $2}' || true
      ;;
  esac
}

# Report whether a managed service is currently running.
service_is_running() {
  local service_name="$1"
  local status
  status="$(service_status "$service_name")"

  case "$SERVICE_MANAGER" in
    systemd) [[ "$status" == "active" ]] ;;
    supervisor) [[ "$status" == "RUNNING" ]] ;;
  esac
}

# Wait for a service to report healthy/running status.
wait_for_service() {
  local service_name="$1"
  local retries="${2:-30}"
  local i

  for ((i = 1; i <= retries; i++)); do
    if service_is_running "$service_name"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# Wait for a TCP port to begin accepting connections.
wait_for_tcp() {
  local host="$1"
  local port="$2"
  local retries="${3:-30}"
  local i

  for ((i = 1; i <= retries; i++)); do
    if bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# Make an authenticated GitHub API request using the operator-provided token.
github_api() {
  curl --silent --show-error --fail \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "$@"
}

# Normalize a GitHub repository remote URL into owner/repo form for reliable comparisons.
normalize_github_remote() {
  local remote="$1"
  remote="${remote%.git}"
  remote="${remote#https://github.com/}"
  remote="${remote#http://github.com/}"
  remote="${remote#ssh://git@github.com/}"
  remote="${remote#git@github.com:}"
  printf '%s' "${remote,,}"
}

# Return success when two GitHub remotes point to the same repository.
github_remote_matches() {
  local left="$1"
  local right="$2"
  [[ "$(normalize_github_remote "$left")" == "$(normalize_github_remote "$right")" ]]
}

# Verify that the persistent deploy key can access the target app repository.
verify_repo_access() {
  as_user "export GIT_SSH_COMMAND='ssh -i $DEPLOY_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes'; git ls-remote '$APP_REPO_URL' '$APP_BRANCH' >/dev/null 2>&1"
}

# Detect executable product names declared by the target app Package.swift manifest.
infer_executable_products() {
  local manifest_file="$APP_DIR/Package.swift"
  [[ -f "$manifest_file" ]] || return 0

  # Parse Package.swift without requiring Swift toolchain; handles multiline executable declarations.
  awk '
    function emit_name(line,    value) {
      if (!match(line, /name[[:space:]]*:[[:space:]]*"[^"]+"/)) {
        return 0
      }
      value = substr(line, RSTART, RLENGTH)
      sub(/^.*name[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/"$/, "", value)
      print value
      return 1
    }

    {
      line = $0

      if (!in_executable_product && line ~ /\.executable[[:space:]]*\(/) {
        in_executable_product = 1
      }

      if (!in_executable_target && line ~ /\.executableTarget[[:space:]]*\(/) {
        in_executable_target = 1
      }

      if (in_executable_product) {
        if (emit_name(line)) {
          in_executable_product = 0
        } else if (line ~ /\)/) {
          in_executable_product = 0
        }
      }

      if (in_executable_target) {
        if (emit_name(line)) {
          in_executable_target = 0
        } else if (line ~ /\)/) {
          in_executable_target = 0
        }
      }
    }
  ' "$manifest_file" | awk 'NF' | sort -u
}

# Write deployer.json beside the repo-root deployer binary.
write_deployer_json() {
  local socket_path

  if [[ "$PANEL_ROUTE" == "/" ]]; then
    socket_path="/ws"
  else
    socket_path="$PANEL_ROUTE/ws"
  fi

  jq -n \
    --arg product_name "$PRODUCT_NAME" \
    --arg target_directory "$APP_DIR_REL" \
    --arg build_mode "$APP_BUILD_MODE" \
    --arg service_manager "$SERVICE_MANAGER" \
    --arg panel_route "$PANEL_ROUTE" \
    --arg socket_path "$socket_path" \
    --arg push_event_path "$WEBHOOK_PATH" \
    --arg deployment_mode "$DEPLOYMENT_MODE" \
    --argjson port "$DEPLOYER_PORT" \
    '{
      port: $port,
      dbFile: "deployer.db",
      panelRoute: $panel_route,
      socketPath: $socket_path,
      serviceManager: $service_manager,
      target: {
        name: $product_name,
        directory: $target_directory,
        buildMode: $build_mode,
        deploymentMode: $deployment_mode,
        pusheventPath: $push_event_path
      }
    }' > "$INSTALL_DIR/deployer.json"

  chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/deployer.json"
  chmod 0644 "$INSTALL_DIR/deployer.json"
}

# Download the deployer binary from the latest GitHub release.
# Prefers an arch-specific asset (deployer-linux-<arch>) then falls back to "deployer".
_download_deployer_binary() {
  local arch releases_json asset_name download_url tmp_bin
  arch="$(uname -m)"

  info "Fetching latest release metadata..."
  releases_json="$(curl --silent --show-error --fail \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/mottzi/Vapor-Deployer/releases/latest")"

  asset_name="deployer-linux-${arch}"
  download_url="$(printf '%s' "$releases_json" \
    | jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' \
    | head -n1)"

  if [[ -z "$download_url" ]]; then
    download_url="$(printf '%s' "$releases_json" \
      | jq -r '.assets[] | select(.name == "deployer") | .browser_download_url' \
      | head -n1)"
  fi

  [[ -n "$download_url" ]] \
    || die "No deployer binary found in the latest GitHub release. Choose 'Build deployer from source?' next time to compile on-box."

  info "Downloading $download_url"
  tmp_bin="$(mktemp)"
  curl --silent --show-error --fail --location -o "$tmp_bin" "$download_url"
  install -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" "$tmp_bin" "$INSTALL_DIR/deployer"
  rm -f "$tmp_bin"
}

# Remove stale managed proxy artifacts from a previous install metadata set.
cleanup_previous_managed_proxy_files() {
  if [[ -n "${PREVIOUS_NGINX_SITE_AVAILABLE:-}" && "$PREVIOUS_NGINX_SITE_AVAILABLE" != "$NGINX_SITE_AVAILABLE" ]]; then
    if [[ -n "${PREVIOUS_NGINX_SITE_ENABLED:-}" && "$PREVIOUS_NGINX_SITE_ENABLED" == /etc/nginx/sites-enabled/* ]]; then
      rm -f "$PREVIOUS_NGINX_SITE_ENABLED"
    fi
    if [[ "$PREVIOUS_NGINX_SITE_AVAILABLE" == /etc/nginx/sites-available/* ]]; then
      rm -f "$PREVIOUS_NGINX_SITE_AVAILABLE"
      info "Removed previous managed Nginx site '$PREVIOUS_NGINX_SITE_AVAILABLE'"
    fi
  fi

  if [[ -n "${PREVIOUS_CERTBOT_RENEW_HOOK:-}" && "$PREVIOUS_CERTBOT_RENEW_HOOK" != "$CERTBOT_RENEW_HOOK" ]]; then
    if [[ "$PREVIOUS_CERTBOT_RENEW_HOOK" == /etc/letsencrypt/renewal-hooks/deploy/* ]]; then
      rm -f "$PREVIOUS_CERTBOT_RENEW_HOOK"
      info "Removed previous Certbot renewal hook '$PREVIOUS_CERTBOT_RENEW_HOOK'"
    fi
  fi
}

# Symlink the generated site file into nginx's enabled set.
enable_managed_nginx_site() {
  install -d -m 0755 -o root -g root /etc/nginx/sites-available /etc/nginx/sites-enabled
  ln -sfn "$NGINX_SITE_AVAILABLE" "$NGINX_SITE_ENABLED"
}

# Validate nginx configuration and apply it.
validate_and_reload_nginx() {
  nginx -t 2>&1 | indent_stream
  systemctl reload nginx >/dev/null
}

# Write bootstrap HTTP-only nginx config for ACME challenges and HTTPS redirect.
write_nginx_bootstrap_config() {
  write_root_file "$NGINX_SITE_AVAILABLE" 0644 <<EOF
# Auto-generated by setup.sh — managed reverse proxy bootstrap config.
# Rerun setup.sh to regenerate.

server {
    listen 80;
    listen [::]:80;
    server_name $PRIMARY_DOMAIN $ALIAS_DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_WEBROOT;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 301 https://$PRIMARY_DOMAIN\$request_uri;
    }
}
EOF
}

# Issue or renew the managed certificate lineage for canonical + alias domains.
issue_tls_certificate() {
  local email_args=()
  if [[ -n "$TLS_CONTACT_EMAIL" ]]; then
    email_args=(--email "$TLS_CONTACT_EMAIL")
  else
    # No email collected because a valid cert already existed. The ACME account
    # is already registered on this host; --register-unsafely-without-email
    # satisfies certbot's non-interactive requirement without re-registering.
    email_args=(--register-unsafely-without-email)
  fi

  certbot certonly \
    --webroot \
    --agree-tos \
    --non-interactive \
    "${email_args[@]}" \
    --cert-name "$CERT_NAME" \
    --expand \
    --keep-until-expiring \
    -w "$ACME_WEBROOT" \
    -d "$PRIMARY_DOMAIN" \
    -d "$ALIAS_DOMAIN" \
    2>&1 | indent_stream
}

# Install a renewal deploy hook that validates and reloads nginx after renewal.
write_certbot_renew_hook() {
  install -d -m 0755 -o root -g root /etc/letsencrypt/renewal-hooks/deploy
  write_root_file "$CERTBOT_RENEW_HOOK" 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
nginx -t
systemctl reload nginx
EOF
}

# Write the final TLS nginx config with canonical host routing.
write_nginx_tls_config() {
  write_root_file "$NGINX_SITE_AVAILABLE" 0644 <<EOF
# Auto-generated by setup.sh — managed reverse proxy config.
# Rerun setup.sh to regenerate.

server {
    listen 80;
    listen [::]:80;
    server_name $PRIMARY_DOMAIN $ALIAS_DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_WEBROOT;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 301 https://$PRIMARY_DOMAIN\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $ALIAS_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$CERT_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$CERT_NAME/privkey.pem;
    return 301 https://$PRIMARY_DOMAIN\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $PRIMARY_DOMAIN;

    root $APP_PUBLIC_DIR;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$CERT_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$CERT_NAME/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:deployer_tls:10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location = $DEPLOYER_SOCKET_PATH {
        proxy_pass http://127.0.0.1:$DEPLOYER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }

    location = $PANEL_ROUTE {
        proxy_pass http://127.0.0.1:$DEPLOYER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ^~ ${PANEL_ROUTE}/ {
        proxy_pass http://127.0.0.1:$DEPLOYER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = $WEBHOOK_PATH {
        proxy_pass http://127.0.0.1:$DEPLOYER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri \$uri/ @app_upstream;
    }

    location @app_upstream {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
    }
}
EOF
}

# Bootstrap nginx on HTTP so Certbot can solve HTTP-01 challenges.
configure_nginx_bootstrap() {
  cleanup_previous_managed_proxy_files
  install -d -m 0755 -o root -g root "$ACME_WEBROOT"
  write_nginx_bootstrap_config
  enable_managed_nginx_site
  systemctl enable --now nginx >/dev/null 2>&1
  validate_and_reload_nginx
}

# Resolve the actual certbot lineage name after issuance.
# When a lineage named $CERT_NAME already exists and certbot cannot reuse it
# in place (e.g. prior install with different SANs), certbot appends a numeric
# suffix like -0002. Detect that and update CERT_NAME so nginx config paths
# point at the real certificate files.
resolve_cert_name_after_issue() {
  # Returns 0 if the named lineage has readable cert and key files on disk.
  _lineage_files_ok() {
    local live="/etc/letsencrypt/live/$1"
    [[ -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]]
  }

  # Returns 0 if the named lineage's cert covers both required domains.
  _lineage_covers_domains() {
    local cert="/etc/letsencrypt/live/$1/fullchain.pem"
    local san
    san="$(openssl x509 -noout -text -in "$cert" 2>/dev/null \
           | grep -A1 'Subject Alternative Name' | tail -1 || true)"
    [[ "$san" == *"DNS:$PRIMARY_DOMAIN"* && "$san" == *"DNS:$ALIAS_DOMAIN"* ]]
  }

  # Check the expected name first.
  if [[ -d "/etc/letsencrypt/live/$CERT_NAME" ]]; then
    if ! _lineage_files_ok "$CERT_NAME"; then
      warn "Lineage '$CERT_NAME' exists but cert files are missing or incomplete; scanning for alternatives."
    elif ! _lineage_covers_domains "$CERT_NAME"; then
      warn "Lineage '$CERT_NAME' does not cover $PRIMARY_DOMAIN + $ALIAS_DOMAIN; scanning for alternatives."
    else
      return 0
    fi
  fi

  # Scan suffix lineages produced by certbot (e.g. -0001, -0002).
  # Glob expansion is lexicographically sorted, so iterating to the end
  # selects the highest-numbered candidate — the most recently created one.
  local best_name=""
  local candidate name
  for candidate in "/etc/letsencrypt/live/${CERT_NAME}-"[0-9]*/; do
    [[ -d "$candidate" ]] || continue
    name="$(basename "$candidate")"
    _lineage_files_ok     "$name" || continue
    _lineage_covers_domains "$name" || continue
    best_name="$name"
  done

  if [[ -n "$best_name" ]]; then
    CERT_NAME="$best_name"
    warn "Using certificate lineage '$CERT_NAME' (pre-existing lineage conflict)."
    return 0
  fi

  die "Cannot locate a valid TLS certificate lineage for $PRIMARY_DOMAIN + $ALIAS_DOMAIN under /etc/letsencrypt/live/"
}

# Scan all existing lineages under /etc/letsencrypt/live/ for one that already
# covers both required domains, and pre-set CERT_NAME to it.  This lets
# certbot's --keep-until-expiring actually short-circuit on reruns instead of
# issuing a brand-new lineage every time because the canonical name
# ($PRIMARY_DOMAIN) doesn't match the suffixed path certbot created previously.
resolve_existing_cert_name() {
  local candidate name cert san
  for candidate in /etc/letsencrypt/live/*/; do
    [[ -d "$candidate" ]] || continue
    name="$(basename "$candidate")"
    cert="$candidate/fullchain.pem"
    [[ -f "$cert" ]] || continue
    san="$(openssl x509 -noout -text -in "$cert" 2>/dev/null \
           | grep -A1 'Subject Alternative Name' | tail -1 || true)"
    [[ "$san" == *"DNS:$PRIMARY_DOMAIN"* && "$san" == *"DNS:$ALIAS_DOMAIN"* ]] || continue
    CERT_NAME="$name"
    CERT_LINEAGE_FOUND=true
    info "Reusing existing certificate lineage '$CERT_NAME'"
    return 0
  done
  # No usable lineage found; certbot will issue a fresh one under $PRIMARY_DOMAIN.
}

# Issue/renew certificates and activate the final HTTPS reverse-proxy config.
activate_nginx_tls_proxy() {
  resolve_existing_cert_name
  issue_tls_certificate
  resolve_cert_name_after_issue
  write_nginx_tls_config
  write_certbot_renew_hook
  enable_managed_nginx_site
  validate_and_reload_nginx
}

# Remove generated systemd unit files for the current install if we switch to Supervisor.
remove_systemd_files() {
  local unit_dir="$SERVICE_HOME/.config/systemd/user"
  as_user_systemctl "disable --now deployer.service ${PRODUCT_NAME}.service" >/dev/null 2>&1 || true
  as_user "rm -f '$unit_dir/deployer.service' '$unit_dir/${PRODUCT_NAME}.service'"
  as_user_systemctl "daemon-reload" >/dev/null 2>&1 || true
}

# Remove generated Supervisor config files for the current install if we switch to systemd.
remove_supervisor_files() {
  rm -f "/etc/supervisor/conf.d/deployer.conf" "/etc/supervisor/conf.d/${PRODUCT_NAME}.conf"
}

# Generate systemd unit files with the required environment values inlined.
write_systemd_files() {
  remove_supervisor_files
  local unit_dir="$SERVICE_HOME/.config/systemd/user"
  install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" "$unit_dir"

  cat > "$unit_dir/deployer.service" <<EOF
[Unit]
Description=Deployer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/deployer serve
Environment="$(systemd_environment_assignment "PATH" "$SWIFT_PATH")"
Environment="$(systemd_environment_assignment "HOME" "$SERVICE_HOME")"
Environment="$(systemd_environment_assignment "USER" "$SERVICE_USER")"
Environment="$(systemd_environment_assignment "GITHUB_WEBHOOK_SECRET" "$WEBHOOK_SECRET")"
Environment="$(systemd_environment_assignment "PANEL_PASSWORD" "$PANEL_PASSWORD")"
Restart=always
RestartSec=2
StandardOutput=append:$INSTALL_DIR/deployer.log
StandardError=append:$INSTALL_DIR/deployer.log

[Install]
WantedBy=default.target
EOF

  cat > "$unit_dir/${PRODUCT_NAME}.service" <<EOF
[Unit]
Description=$PRODUCT_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/deploy/$PRODUCT_NAME serve --port $APP_PORT
Environment="$(systemd_environment_assignment "PATH" "$SWIFT_PATH")"
Environment="$(systemd_environment_assignment "HOME" "$SERVICE_HOME")"
Environment="$(systemd_environment_assignment "USER" "$SERVICE_USER")"
Restart=always
RestartSec=2
StandardOutput=append:$APP_DIR/deploy/$PRODUCT_NAME.log
StandardError=append:$APP_DIR/deploy/$PRODUCT_NAME.log

[Install]
WantedBy=default.target
EOF

  chown "$SERVICE_USER:$SERVICE_USER" "$unit_dir/deployer.service" "$unit_dir/${PRODUCT_NAME}.service"
  chmod 0644 "$unit_dir/deployer.service" "$unit_dir/${PRODUCT_NAME}.service"
}

# Generate Supervisor program files with the required environment values inlined.
write_supervisor_files() {
  remove_systemd_files

  cat > /etc/supervisor/conf.d/deployer.conf <<EOF
[program:deployer]
directory=$INSTALL_DIR
command=$INSTALL_DIR/deployer serve
user=$SERVICE_USER
environment=PATH="$(supervisor_environment_value "$SWIFT_PATH")",HOME="$(supervisor_environment_value "$SERVICE_HOME")",USER="$(supervisor_environment_value "$SERVICE_USER")",GITHUB_WEBHOOK_SECRET="$(supervisor_environment_value "$WEBHOOK_SECRET")",PANEL_PASSWORD="$(supervisor_environment_value "$PANEL_PASSWORD")"
autorestart=true
redirect_stderr=true
stdout_logfile=$INSTALL_DIR/deployer.log
EOF

  cat > "/etc/supervisor/conf.d/${PRODUCT_NAME}.conf" <<EOF
[program:$PRODUCT_NAME]
directory=$APP_DIR
command=$APP_DIR/deploy/$PRODUCT_NAME serve --port $APP_PORT
user=$SERVICE_USER
environment=PATH="$(supervisor_environment_value "$SWIFT_PATH")",HOME="$(supervisor_environment_value "$SERVICE_HOME")",USER="$(supervisor_environment_value "$SERVICE_USER")"
autorestart=true
redirect_stderr=true
stdout_logfile=$APP_DIR/deploy/$PRODUCT_NAME.log
EOF
}

# Enable and start the generated services.
start_services() {
  case "$SERVICE_MANAGER" in
    systemd)
      local uid
      uid="$(id -u "$SERVICE_USER")"
      loginctl enable-linger "$SERVICE_USER"
      systemctl start "user@${uid}.service" >/dev/null 2>&1 || true
      as_user_systemctl "daemon-reload"
      as_user_systemctl "enable --now deployer.service ${PRODUCT_NAME}.service"
      ;;
    supervisor)
      systemctl enable --now supervisor
      supervisorctl reread >/dev/null
      supervisorctl update >/dev/null
      supervisorctl restart deployer >/dev/null 2>&1 || supervisorctl start deployer >/dev/null
      supervisorctl restart "$PRODUCT_NAME" >/dev/null 2>&1 || supervisorctl start "$PRODUCT_NAME" >/dev/null
      ;;
  esac
}

# Write the root-owned operator control wrapper and its config file.
# The wrapper gives admins a single command (`sudo deployerctl ...`) for
# manual service actions, hiding the XDG/D-Bus session plumbing required
# to talk to a systemd --user manager under a dedicated service account.
install_deployerctl() {
  install -d -m 0755 -o root -g root "$DEPLOYERCTL_CONFIG_DIR"

  # Persist install-specific values so the static wrapper stays reusable.
  # Values are emitted via %q so paths/names are re-parseable on source.
  local tmp_conf
  tmp_conf="$(mktemp)"
  {
    printf '# %s\n' "Auto-generated by Vapor-Mottzi-Deployer setup.sh"
    printf '# %s\n' "Consumed by $DEPLOYERCTL_BIN. Rerun setup.sh to regenerate."
    printf 'SERVICE_USER=%q\n'    "$SERVICE_USER"
    printf 'SERVICE_MANAGER=%q\n' "$SERVICE_MANAGER"
    printf 'PRODUCT_NAME=%q\n'    "$PRODUCT_NAME"
    printf 'INSTALL_DIR=%q\n'     "$INSTALL_DIR"
    printf 'APP_DIR=%q\n'         "$APP_DIR"
    printf 'DEPLOYER_LOG=%q\n'    "$INSTALL_DIR/deployer.log"
    printf 'APP_LOG=%q\n'         "$APP_DIR/deploy/$PRODUCT_NAME.log"
    printf 'PRIMARY_DOMAIN=%q\n'  "$PRIMARY_DOMAIN"
    printf 'ALIAS_DOMAIN=%q\n'    "$ALIAS_DOMAIN"
    printf 'CERT_NAME=%q\n'       "$CERT_NAME"
    printf 'NGINX_SITE_NAME=%q\n' "$NGINX_SITE_NAME"
    printf 'NGINX_SITE_AVAILABLE=%q\n' "$NGINX_SITE_AVAILABLE"
    printf 'NGINX_SITE_ENABLED=%q\n'   "$NGINX_SITE_ENABLED"
    printf 'ACME_WEBROOT=%q\n'    "$ACME_WEBROOT"
    printf 'CERTBOT_RENEW_HOOK=%q\n' "$CERTBOT_RENEW_HOOK"
    printf 'WEBHOOK_PATH=%q\n'   "$WEBHOOK_PATH"
    printf 'GITHUB_WEBHOOK_SETTINGS_URL=%q\n' "https://github.com/$GITHUB_OWNER/$GITHUB_REPO/settings/hooks"
  } > "$tmp_conf"
  install -m 0644 -o root -g root "$tmp_conf" "$DEPLOYERCTL_CONFIG"
  rm -f "$tmp_conf"

  # The wrapper itself is a static script — no per-install values are
  # inlined. Single-quoted heredoc keeps this file free of shell
  # expansion by the installer.
  local tmp_bin
  tmp_bin="$(mktemp)"
  cat > "$tmp_bin" <<'DEPLOYERCTL_EOF'
#!/usr/bin/env bash
# deployerctl — operator control surface for the Vapor-Mottzi-Deployer install.
#
# Auto-generated by setup.sh. Do not edit by hand; rerun setup.sh to update.
#
# Provides a single `sudo deployerctl <action> [target]` command that hides
# the XDG_RUNTIME_DIR / DBUS_SESSION_BUS_ADDRESS plumbing required to drive
# a systemd --user manager under a dedicated service account.

set -Eeuo pipefail

CONFIG_FILE="/etc/deployer/deployerctl.conf"
PROG="$(basename -- "$0")"

die()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
warn() { printf '%s: %s\n'        "$PROG" "$*" >&2; }

usage() {
  cat <<USAGE
$PROG — control the deployer and its managed app

Usage:
  sudo $PROG <action> [target]
  sudo $PROG help

Actions:
  status        Show service status
  start         Start services
  stop          Stop services
  restart       Restart services
  reload        Reload services where supported
  enable        Enable services at boot
  disable       Disable services at boot
  logs          Follow on-disk service log file(s) (Ctrl-C to exit)
  journal       Show recent systemd journal entries (systemd only)

Targets:
  deployer      Just the deployer service
  app           Just the managed app service (${PRODUCT_NAME:-configured app})
  all           Both services (default)

Environment:
  NO_COLOR      Disable ANSI colors when set.

Config file:   $CONFIG_FILE
USAGE
}

# Parse flags/action early so --help works without root.
case "${1:-}" in
  ""|-h|--help|help) usage; [[ -n "${1:-}" ]] || exit 2; exit 0 ;;
esac

[[ $EUID -eq 0 ]] || die "must be run as root (try: sudo $PROG $*)"
[[ -r "$CONFIG_FILE" ]] || die "config not found: $CONFIG_FILE (reinstall with setup.sh)"

# shellcheck disable=SC1090
. "$CONFIG_FILE"

for _var in SERVICE_USER SERVICE_MANAGER PRODUCT_NAME INSTALL_DIR APP_DIR DEPLOYER_LOG APP_LOG; do
  [[ -n "${!_var:-}" ]] || die "missing $_var in $CONFIG_FILE"
done

id -u "$SERVICE_USER" >/dev/null 2>&1 || die "service user '$SERVICE_USER' does not exist"
SERVICE_UID="$(id -u "$SERVICE_USER")"
BUS_PATH="/run/user/$SERVICE_UID/bus"

action="$1"; shift
target="${1:-all}"
case "$target" in
  deployer|app|all) ;;
  *) warn "unknown target: $target"; usage >&2; exit 2 ;;
esac

# Resolve units/log files for the chosen target.
declare -a units supervisor_progs logs_files
case "$target" in
  deployer)
    units=("deployer.service")
    supervisor_progs=("deployer")
    logs_files=("$DEPLOYER_LOG")
    ;;
  app)
    units=("${PRODUCT_NAME}.service")
    supervisor_progs=("$PRODUCT_NAME")
    logs_files=("$APP_LOG")
    ;;
  all)
    units=("deployer.service" "${PRODUCT_NAME}.service")
    supervisor_progs=("deployer" "$PRODUCT_NAME")
    logs_files=("$DEPLOYER_LOG" "$APP_LOG")
    ;;
esac

# systemd --user requires the per-user manager to be running so a session
# bus is available. setup.sh enables linger + starts user@<uid>.service,
# but this keeps the wrapper rerun-safe after reboots or manual stops.
ensure_user_manager() {
  loginctl enable-linger "$SERVICE_USER" >/dev/null 2>&1 || true
  systemctl start "user@${SERVICE_UID}.service" >/dev/null 2>&1 || true

  local i
  for ((i = 0; i < 50; i++)); do
    [[ -S "$BUS_PATH" ]] && return 0
    sleep 0.1
  done
  die "user bus $BUS_PATH is unavailable; check 'systemctl status user@${SERVICE_UID}.service'"
}

# Drop to the service user to invoke `systemctl --user` / `journalctl --user`
# with the right session env. `runuser` (util-linux) is the correct tool for
# root→user transitions on systemd hosts: unlike `sudo`, it bypasses PAM auth
# stacks and sudoers policy, so it works on any host where systemd is already
# running. `env VAR=val` is used rather than relying on `runuser -s`/profile
# loading so the session variables survive regardless of the target user's
# shell or login files.
as_service_user() {
  runuser -u "$SERVICE_USER" -- env \
    "XDG_RUNTIME_DIR=/run/user/$SERVICE_UID" \
    "DBUS_SESSION_BUS_ADDRESS=unix:path=$BUS_PATH" \
    "$@"
}

user_systemctl()  { as_service_user systemctl  --user "$@"; }
user_journalctl() { as_service_user journalctl --user "$@"; }

# Forward Ctrl-C cleanly when following logs.
trap 'exit 130' INT

case "$SERVICE_MANAGER" in
  systemd)
    # ensure_user_manager is only required for actions that actually talk to
    # the per-user bus. `logs` tails root-readable on-disk files and must
    # stay functional precisely when the user manager is broken — that's
    # when admins reach for it.
    case "$action" in
      status)
        ensure_user_manager
        user_systemctl --no-pager status "${units[@]}"
        ;;
      start|stop|restart|reload|enable|disable)
        ensure_user_manager
        user_systemctl "$action" "${units[@]}"
        ;;
      logs)
        # Prefer on-disk log files since the generated units use
        # StandardOutput=append: rather than journal.
        _missing=0
        for _f in "${logs_files[@]}"; do
          [[ -f "$_f" ]] || { warn "log file not found yet: $_f"; _missing=1; }
        done
        (( _missing == 0 )) || warn "run '$PROG journal $target' to see systemd lifecycle events instead"
        exec tail -n 100 -F -- "${logs_files[@]}"
        ;;
      journal)
        ensure_user_manager
        _jargs=()
        for _u in "${units[@]}"; do
          _jargs+=(--unit "$_u")
        done
        user_journalctl --no-pager --lines=200 "${_jargs[@]}"
        ;;
      *) warn "unknown action: $action"; usage >&2; exit 2 ;;
    esac
    ;;
  supervisor)
    command -v supervisorctl >/dev/null 2>&1 || die "supervisorctl not found on PATH"
    case "$action" in
      status)  supervisorctl status "${supervisor_progs[@]}" ;;
      start)   supervisorctl start  "${supervisor_progs[@]}" ;;
      stop)    supervisorctl stop   "${supervisor_progs[@]}" ;;
      restart|reload) supervisorctl restart "${supervisor_progs[@]}" ;;
      enable|disable)
        die "'$action' is not supported with service manager 'supervisor'"
        ;;
      logs)
        if (( ${#supervisor_progs[@]} == 1 )); then
          exec supervisorctl tail -f "${supervisor_progs[0]}"
        else
          exec tail -n 100 -F -- "${logs_files[@]}"
        fi
        ;;
      journal)
        die "'journal' is only available with service manager 'systemd'"
        ;;
      *) warn "unknown action: $action"; usage >&2; exit 2 ;;
    esac
    ;;
  *) die "unknown SERVICE_MANAGER in $CONFIG_FILE: $SERVICE_MANAGER" ;;
esac
DEPLOYERCTL_EOF

  install -m 0755 -o root -g root "$tmp_bin" "$DEPLOYERCTL_BIN"
  rm -f "$tmp_bin"
}

# Create or update a single push webhook for this deployer endpoint.
ensure_github_webhook() {
  local hooks_api="https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/hooks"
  local hooks_json
  local existing_id
  local create_payload
  local update_payload

  hooks_json="$(github_api "${hooks_api}?per_page=100")"
  existing_id="$(printf '%s' "$hooks_json" | jq -r --arg url "$WEBHOOK_URL" '.[] | select(.config.url == $url) | .id' | head -n 1)"

  update_payload="$(jq -nc \
    --arg url "$WEBHOOK_URL" \
    --arg secret "$WEBHOOK_SECRET" \
    '{
      active: true,
      events: ["push"],
      config: {
        url: $url,
        content_type: "json",
        secret: $secret,
        insecure_ssl: "0"
      }
    }')"

  if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
    info "Updating existing GitHub webhook"
    github_api -X PATCH -d "$update_payload" "${hooks_api}/${existing_id}" >/dev/null
  else
    create_payload="$(jq -nc \
      --arg url "$WEBHOOK_URL" \
      --arg secret "$WEBHOOK_SECRET" \
      '{
        name: "web",
        active: true,
        events: ["push"],
        config: {
          url: $url,
          content_type: "json",
          secret: $secret,
          insecure_ssl: "0"
        }
      }')"

    info "Creating GitHub webhook"
    github_api -X POST -d "$create_payload" "$hooks_api" >/dev/null
  fi
}

# Validate local state for conflicts that would otherwise abort mid-install.
# Runs before anything destructive so the operator gets fast feedback.
preflight_local_state() {
  if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    local existing_home
    existing_home="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
    if [[ "$existing_home" != "$SERVICE_HOME" ]]; then
      die "User '$SERVICE_USER' already exists with home '$existing_home', not '$SERVICE_HOME'. Resolve this before rerunning setup."
    fi
    info "Reusing user '$SERVICE_USER' (home: $existing_home)"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
      if [[ "$BUILD_FROM_SOURCE" == "true" ]]; then
        local origin dirty
        origin="$(as_user "git -C '$INSTALL_DIR' remote get-url origin" 2>/dev/null || true)"
        if [[ -n "$origin" ]] && ! github_remote_matches "$origin" "$DEPLOYER_REPO_URL"; then
          die "Existing deployer checkout at '$INSTALL_DIR' points at '$origin', not '$DEPLOYER_REPO_URL'."
        fi
        dirty="$(as_user "git -C '$INSTALL_DIR' status --porcelain --untracked-files=no" 2>/dev/null || true)"
        if [[ -n "$dirty" ]]; then
          die "Existing deployer checkout at '$INSTALL_DIR' has uncommitted changes. Clean them before rerunning setup."
        fi
        info "Deployer checkout at '$INSTALL_DIR' is clean"
      else
        info "Found source checkout at '$INSTALL_DIR'; pre-built binary will be installed there"
      fi
    elif [[ -d "$INSTALL_DIR" ]]; then
      if [[ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        if [[ "$BUILD_FROM_SOURCE" == "true" ]]; then
          die "'$INSTALL_DIR' exists but is not a deployer git checkout and is not empty."
        else
          info "Reusing existing install directory '$INSTALL_DIR'"
        fi
      fi
    fi

    if [[ -d "$APP_DIR/.git" ]]; then
      local app_origin app_dirty
      app_origin="$(as_user "git -C '$APP_DIR' remote get-url origin" 2>/dev/null || true)"
      if [[ -n "$app_origin" ]] && ! github_remote_matches "$app_origin" "$APP_REPO_URL"; then
        die "Existing app checkout at '$APP_DIR' points at '$app_origin', not '$APP_REPO_URL'."
      fi
      app_dirty="$(as_user "git -C '$APP_DIR' status --porcelain --untracked-files=no" 2>/dev/null || true)"
      if [[ -n "$app_dirty" ]]; then
        die "Existing app checkout at '$APP_DIR' has uncommitted changes. Clean them before rerunning setup."
      fi
      info "App checkout at '$APP_DIR' is clean"
    fi
  else
    info "Service user '$SERVICE_USER' will be created"
  fi
}

# ────────────────────────────────────────────────────────────
#  Preflight
# ────────────────────────────────────────────────────────────

# The installer must run with root privileges because it creates users,
# installs packages, and writes service files under /etc.
[[ $EUID -eq 0 ]] || die "This command requires privileges. Run as root or with sudo."

# Keep the first version Ubuntu-only so package names and service paths stay predictable.
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer currently supports Ubuntu only."

# Fixed installer defaults.
DEPLOYER_REPO_URL="https://github.com/mottzi/Vapor-Deployer.git"
DEPLOYER_REPO_BRANCH="main"
APP_BRANCH="main"
DEPLOYER_BUILD_MODE="release"
APP_BUILD_MODE="release"
DEPLOYMENT_MODE="manual"

step "Collecting setup values"

section "Service identity"
hint "The dedicated Linux account that will own the deployer and app processes."
prompt_non_root_user SERVICE_USER "Dedicated service user" "vapor"

section "Source repository"
hint "SSH URL of the app repository to deploy (e.g. git@github.com:owner/repo.git)."
prompt_github_repo_url APP_REPO_URL "Private app repo SSH URL"
hint "Short name used for the systemd unit, SSH key filename, and webhook path."
prompt_safe_name APP_NAME "Target app name" "$GITHUB_REPO"
#if [[ "$APP_NAME" == "$GITHUB_REPO" ]]; then
#  info "Using app name '$APP_NAME' inferred from repository slug '$GITHUB_REPO'"
#else
#  info "Using overridden app name '$APP_NAME' (repo slug is '$GITHUB_REPO')"
#fi

section "Network configuration"
hint "TCP port where the deployer's web panel listens."
prompt_port DEPLOYER_PORT "Deployer port" "8081"
hint "TCP port your app binds to when the deployer starts it."
prompt_port APP_PORT "Target app port" "8080"
hint "URL path prefix the deployer web UI is served under (e.g. /deployer)."
prompt PANEL_ROUTE "Panel route" "/deployer"
PANEL_ROUTE="$(normalize_panel_route "$PANEL_ROUTE")"
[[ "$PANEL_ROUTE" != "/" ]] || die "Panel route '/' is not supported with managed Nginx setup. Use a prefixed route like /deployer."

section "Runtime"
hint "Which process manager supervises the deployer and app: 'systemd' or 'supervisor'."
prompt_service_manager SERVICE_MANAGER "Service manager" "systemd"

section "Deployer binary"
hint "Download a pre-built binary from the latest GitHub release (fast),"
hint "or clone and compile the deployer on-box (takes significantly longer)."
BUILD_FROM_SOURCE=false
if confirm "Build deployer from source?" n; then
  BUILD_FROM_SOURCE=true
fi

# Derive fixed runtime paths from the dedicated service user.
SERVICE_HOME="/home/$SERVICE_USER"
INSTALL_DIR="$SERVICE_HOME/deployer"
APPS_ROOT_DIR="$SERVICE_HOME/apps"
APP_DIR_REL="../apps/$APP_NAME"
APP_DIR="$APPS_ROOT_DIR/$APP_NAME"
DEPLOY_KEY_PATH="$SERVICE_HOME/.ssh/${APP_NAME}_deploy_key"
SWIFTLY_HOME_DIR="$SERVICE_HOME/.local/share/swiftly"
SWIFTLY_BIN_DIR="$SWIFTLY_HOME_DIR/bin"
SWIFT_PATH="$SWIFTLY_BIN_DIR:/usr/local/bin:/usr/bin:/bin"
WEBHOOK_PATH="/pushevent/$APP_NAME"
DEPLOYER_SOCKET_PATH="$PANEL_ROUTE/ws"
NGINX_SITE_NAME="deployer-${APP_NAME}"
NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/${NGINX_SITE_NAME}.conf"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/${NGINX_SITE_NAME}.conf"
ACME_WEBROOT="/var/www/certbot/${APP_NAME}"
CERTBOT_RENEW_HOOK="/etc/letsencrypt/renewal-hooks/deploy/${NGINX_SITE_NAME}-reload-nginx.sh"
APP_PUBLIC_DIR="$APP_DIR/Public"

# Operator control wrapper paths. The wrapper is system-wide (not owned by
# the service user) so admins can invoke it via `sudo deployerctl ...`
# without having to know the dedicated account's name.
DEPLOYERCTL_BIN="/usr/local/sbin/deployerctl"
DEPLOYERCTL_CONFIG_DIR="/etc/deployer"
DEPLOYERCTL_CONFIG="$DEPLOYERCTL_CONFIG_DIR/deployerctl.conf"

# Keep previous managed proxy metadata so reruns can clean stale artifacts
# even after deployerctl.conf is regenerated with new values.
load_previous_proxy_metadata

step "Preflight checks"

preflight_local_state
ok "Preflight checks passed"

step "Installing base packages"

# Detect the GCC major version that this Ubuntu release ships so the
# version-pinned Swift deps (libgcc-X-dev, libstdc++-X-dev) resolve correctly
# without hardcoding a release-specific number (e.g. 12 on 22.04, 13 on 24.04).
_gcc_major="$(apt-cache show gcc 2>/dev/null \
  | awk '/^Version:/ { v=$2; sub(/^[0-9]+:/, "", v); split(v, a, "."); print a[1]; exit }')"
_gcc_major="${_gcc_major:-13}"   # fall back to 13 (Ubuntu 24.04) if detection fails

APT_PACKAGES=(
  # Swift system dependencies (swift.org/install/linux).
  # Swiftly only prints the install command when deps are missing — it does not
  # install them itself when running as an unprivileged user. We satisfy them
  # here as root so swift build works after swiftly init completes.
  binutils
  gnupg2
  libc6-dev
  libcurl4-openssl-dev
  libedit2
  "libgcc-${_gcc_major}-dev"
  libncurses-dev
  libpython3-dev
  libsqlite3-0
  "libstdc++-${_gcc_major}-dev"
  libxml2-dev
  libz3-dev
  pkg-config
  tzdata
  unzip
  zip
  zlib1g-dev
  # Deployer infrastructure
  ca-certificates
  certbot
  curl
  git
  jq
  nginx
  openssl
  openssh-client
)

if [[ "$SERVICE_MANAGER" == "supervisor" ]]; then
  APT_PACKAGES+=(supervisor)
fi

_missing_packages=()
for _pkg in "${APT_PACKAGES[@]}"; do
  dpkg -s "$_pkg" >/dev/null 2>&1 || _missing_packages+=("$_pkg")
done

if (( ${#_missing_packages[@]} > 0 )); then
  info "Refreshing apt package index..."
  apt-get -qq update
  ok "Apt package index refreshed"
  info "Installing missing packages: ${_missing_packages[*]}"
  apt-get -y -qq install "${_missing_packages[@]}"
  ok "Base packages installed"
else
  info "All required packages already installed"
fi

step "Preparing service user"

# Create the dedicated runtime user on first install, or reuse it on rerun.
if id -u "$SERVICE_USER" >/dev/null 2>&1; then
  EXISTING_HOME="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
  [[ "$EXISTING_HOME" == "$SERVICE_HOME" ]] || die "Existing user '$SERVICE_USER' does not use $SERVICE_HOME as its home directory."
  info "Reusing existing user '$SERVICE_USER' (home: $EXISTING_HOME)"
else
  info "Creating service user '$SERVICE_USER'"
  useradd --system --create-home --home-dir "$SERVICE_HOME" --shell /bin/bash "$SERVICE_USER"
  ok "Created user '$SERVICE_USER'"
fi

# Ensure stable sibling directories under the service account home.
install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" "$SERVICE_HOME" "$APPS_ROOT_DIR"
if [[ -d "$INSTALL_DIR" ]]; then
  chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
fi

step "Preparing deployer checkout"

if [[ "$BUILD_FROM_SOURCE" == "true" ]]; then
  # Clone deployer on first install, or update it safely on rerun.
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Reusing existing deployer checkout at $INSTALL_DIR"

    CURRENT_DEPLOYER_ORIGIN="$(as_user "git -C '$INSTALL_DIR' remote get-url origin")"
    github_remote_matches "$CURRENT_DEPLOYER_ORIGIN" "$DEPLOYER_REPO_URL" \
      || die "Existing deployer checkout uses origin '$CURRENT_DEPLOYER_ORIGIN', not '$DEPLOYER_REPO_URL'."

    DEPLOYER_STATUS="$(as_user "git -C '$INSTALL_DIR' status --porcelain --untracked-files=no")"
    [[ -z "$DEPLOYER_STATUS" ]] || die "Existing deployer checkout has uncommitted changes at '$INSTALL_DIR'. Clean them before rerunning setup."

    as_user "
    set -Eeuo pipefail
    git -C '$INSTALL_DIR' fetch origin '$DEPLOYER_REPO_BRANCH' --prune
    git -C '$INSTALL_DIR' checkout '$DEPLOYER_REPO_BRANCH'
    git -C '$INSTALL_DIR' pull --ff-only origin '$DEPLOYER_REPO_BRANCH'
    " 2>&1 | indent_stream
  else
    if [[ -d "$INSTALL_DIR" ]]; then
      if [[ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        die "Expected '$INSTALL_DIR' to be a deployer git checkout, but found a non-empty directory."
      fi
      rmdir "$INSTALL_DIR" || true
    fi

    info "Cloning deployer into $INSTALL_DIR"
    as_user "
    set -Eeuo pipefail
    git clone --branch '$DEPLOYER_REPO_BRANCH' '$DEPLOYER_REPO_URL' '$INSTALL_DIR'
    " 2>&1 | indent_stream
  fi
  ok "Deployer checkout ready"
else
  install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" "$INSTALL_DIR"
  ok "Install directory ready at $INSTALL_DIR"
fi

step "Preparing GitHub clone access"

# Generate a persistent deploy key for the runtime user.
install -d -m 0700 -o "$SERVICE_USER" -g "$SERVICE_USER" "$SERVICE_HOME/.ssh"
as_user "touch ~/.ssh/known_hosts && chmod 600 ~/.ssh/known_hosts"
as_user "ssh-keyscan -H github.com >> ~/.ssh/known_hosts" 2>&1 | indent_stream

if [[ ! -f "$DEPLOY_KEY_PATH" ]]; then
  info "Generating deploy key at $DEPLOY_KEY_PATH"
  as_user "ssh-keygen -t ed25519 -N '' -f '$DEPLOY_KEY_PATH' -C '$SERVICE_USER@$HOSTNAME-$APP_NAME'" 2>&1 | indent_stream
else
  info "Reusing existing deploy key at $DEPLOY_KEY_PATH"
fi

# Verify access immediately. If it fails, show the public key and let the operator add it.
if ! verify_repo_access; then
  DEPLOY_KEYS_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/settings/keys"
  card_open "Action required · Add deploy key to GitHub"
  card_line "The deploy key below needs to be registered on GitHub before"
  card_line "the installer can clone the target app repository."
  echo
  card_kv "Open"   "$DEPLOY_KEYS_URL"
  card_kv "Title"  "${APP_NAME}-deployer  (or similar)"
  card_kv "Access" "leave write access disabled (read-only key)"
  echo
  card_line "${_C_BOLD}Public key to paste:${_C_RESET}"
  echo
  while IFS= read -r _pubkey_line; do
    printf '    %s%s%s\n' "${_C_CYAN}" "$_pubkey_line" "${_C_RESET}"
  done < "$DEPLOY_KEY_PATH.pub"
  card_close
  confirm "Continue after adding the deploy key on GitHub?" y || die "GitHub deploy key setup was not confirmed."
  verify_repo_access || die "GitHub access check failed. Verify the deploy key and repository permissions."
fi
ok "GitHub clone access verified"

step "Preparing target app checkout"

# Clone the target app on first install, or update it safely on rerun.
if [[ -d "$APP_DIR/.git" ]]; then
  info "Reusing existing app checkout at $APP_DIR"

  CURRENT_ORIGIN="$(as_user "git -C '$APP_DIR' remote get-url origin")"
  github_remote_matches "$CURRENT_ORIGIN" "$APP_REPO_URL" \
    || die "Existing app checkout uses origin '$CURRENT_ORIGIN', not '$APP_REPO_URL'."

  as_user "git -C '$APP_DIR' config core.sshCommand 'ssh -i $DEPLOY_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes'"

  APP_STATUS="$(as_user "git -C '$APP_DIR' status --porcelain --untracked-files=no")"
  [[ -z "$APP_STATUS" ]] || die "Existing app checkout has uncommitted changes at '$APP_DIR'. Clean them before rerunning setup."

  as_user "
  set -Eeuo pipefail
  git -C '$APP_DIR' fetch origin '$APP_BRANCH' --prune
  git -C '$APP_DIR' checkout '$APP_BRANCH'
  git -C '$APP_DIR' pull --ff-only origin '$APP_BRANCH'
  " 2>&1 | indent_stream
else
  info "Cloning target app into $APP_DIR"
  install -d -m 0755 -o "$SERVICE_USER" -g "$SERVICE_USER" "$(dirname "$APP_DIR")"

  as_user "
  set -Eeuo pipefail
  export GIT_SSH_COMMAND='ssh -i $DEPLOY_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes'
  git clone '$APP_REPO_URL' '$APP_DIR'
  git -C '$APP_DIR' config core.sshCommand 'ssh -i $DEPLOY_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes'
  git -C '$APP_DIR' checkout '$APP_BRANCH'
  " 2>&1 | indent_stream
fi
ok "App checkout ready"

step "Resolving executable product"

mapfile -t EXECUTABLE_PRODUCTS < <(infer_executable_products)
if (( ${#EXECUTABLE_PRODUCTS[@]} == 0 )); then
  warn "Could not infer an executable product from Package.swift."
  prompt_safe_name PRODUCT_NAME "Executable product name"
elif (( ${#EXECUTABLE_PRODUCTS[@]} == 1 )); then
  PRODUCT_NAME="${EXECUTABLE_PRODUCTS[0]}"
  info "Using executable product '$PRODUCT_NAME' inferred from Package.swift"
else
  info "Detected multiple executable products in Package.swift:"
  for executable_product in "${EXECUTABLE_PRODUCTS[@]}"; do
    printf '    %s•%s %s\n' "${_C_DIM}" "${_C_RESET}" "$executable_product"
  done
  echo
  prompt_safe_name PRODUCT_NAME "Executable product name" "${EXECUTABLE_PRODUCTS[0]}"
fi

# Collect all remaining interactive values before Swift install/build steps begin.
step "Collecting final runtime configuration"

section "Panel credentials"
hint "Password used to sign in to the deployer web panel."
prompt_secret_confirm PANEL_PASSWORD "Panel password"

# Generate the webhook secret automatically so the finished system is functional immediately.
WEBHOOK_SECRET="$(generate_hex_secret)"

section "Public URL"
hint "The canonical externally reachable origin, e.g. https://example.com (HTTPS + domain only)."
prompt_base_url PUBLIC_BASE_URL "Public base URL"
PUBLIC_BASE_URL="$(normalize_base_url "$PUBLIC_BASE_URL")"
PRIMARY_DOMAIN="$(extract_base_url_host "$PUBLIC_BASE_URL")"
ALIAS_DOMAIN="$(derive_alias_domain "$PRIMARY_DOMAIN")"
CERT_NAME="$PRIMARY_DOMAIN"

# Resolve now so we can skip the email prompt when a valid cert already exists.
# openssl is available at this point (installed in step 3).
CERT_LINEAGE_FOUND=false
resolve_existing_cert_name

TLS_CONTACT_EMAIL=""
if [[ "$CERT_LINEAGE_FOUND" == "false" ]]; then
  section "TLS"
  hint "Email address used by Let's Encrypt for expiration and account notices."
  prompt_email TLS_CONTACT_EMAIL "TLS contact email"
else
  info "Reusing existing certificate '$CERT_NAME'; skipping TLS email prompt"
fi

require_resolvable_hostname "$PRIMARY_DOMAIN" "Canonical domain"
require_resolvable_hostname "$ALIAS_DOMAIN" "Alias domain"
WEBHOOK_URL="${PUBLIC_BASE_URL}${WEBHOOK_PATH}"

section "GitHub access token"
card_open "How to create the GitHub token"
card_kv "Browser"    "https://github.com/settings/tokens"
card_kv "Click"    "Generate new token > Generate new token (classic)"
card_kv "Select"  "'admin:repo_hook'"
card_close
prompt_secret GITHUB_TOKEN "GitHub token"

step "Verifying GitHub API access"

# Verify that the provided token can manage repository webhooks before we proceed.
if ! github_api "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/hooks?per_page=1" >/dev/null; then
  die "GitHub token check failed. Use a classic token with 'admin:repo_hook' (or 'write:repo_hook') and webhook admin permission on '$GITHUB_OWNER/$GITHUB_REPO'."
fi
ok "GitHub API access verified"

step "Installation summary"

card_open "Planned configuration"
card_kv "Install directory"    "$INSTALL_DIR"
card_kv "Deployer repo"        "$DEPLOYER_REPO_URL"
card_kv "Deployer branch"      "$DEPLOYER_REPO_BRANCH"
card_kv "Service user"         "$SERVICE_USER"
card_kv "Service manager"      "$SERVICE_MANAGER"
card_kv "App name"             "$APP_NAME"
card_kv "Executable product"   "$PRODUCT_NAME"
card_kv "App repo"             "$APP_REPO_URL"
card_kv "App branch"           "$APP_BRANCH"
card_kv "App directory"        "$APP_DIR"
card_kv "Config target path"   "$APP_DIR_REL"
card_kv "Deployer build mode"  "$DEPLOYER_BUILD_MODE"
card_kv "App build mode"       "$APP_BUILD_MODE"
card_kv "Deployment mode"      "$DEPLOYMENT_MODE"
card_kv "Deployer port"        "$DEPLOYER_PORT"
card_kv "App port"             "$APP_PORT"
card_kv "Panel route"          "$PANEL_ROUTE"
card_kv "Canonical domain"     "$PRIMARY_DOMAIN"
card_kv "Alias domain"         "$ALIAS_DOMAIN"
card_kv "TLS contact"          "${TLS_CONTACT_EMAIL:-"(reusing existing certificate)"}"
card_kv "Nginx site file"      "$NGINX_SITE_AVAILABLE"
card_kv "ACME webroot"         "$ACME_WEBROOT"
card_kv "Webhook URL"          "$WEBHOOK_URL"
card_close

step "Installing Swift via Swiftly"

# Install Swift under the runtime user so later deploy-time builds use the same toolchain.
if ! swift_install_output="$(as_user "
set -Eeuo pipefail

if [[ ! -x '$SWIFTLY_BIN_DIR/swift' ]]; then
  workdir=\$(mktemp -d)
  cd \"\$workdir\"

  archive=\"swiftly-\$(uname -m).tar.gz\"
  curl -fL -o \"\$archive\" \"https://download.swift.org/swiftly/linux/\$archive\"
  tar zxf \"\$archive\"

  ./swiftly init --quiet-shell-followup --assume-yes

  cd \"\$HOME\"
  rm -rf \"\$workdir\"
fi

source '$SWIFTLY_HOME_DIR/env.sh'
hash -r
swift --version
" 2>&1)"; then
  printf '    Swift installation failed. Full output:\n' >&2
  printf '%s\n' "$swift_install_output" | indent_stream >&2
  die "Failed to install Swift via Swiftly."
fi

if grep -q "Swift .* is installed successfully!" <<<"$swift_install_output"; then
  grep -m1 "Swift .* is installed successfully!" <<<"$swift_install_output" | indent_stream
else
  info "Swift was already installed; confirming active toolchain:"
fi
grep -m1 "^Swift version" <<<"$swift_install_output" | indent_stream || true
grep -m1 "^Target:" <<<"$swift_install_output" | indent_stream || true

step "Building deployer"

if [[ "$BUILD_FROM_SOURCE" == "true" ]]; then
  run_compact_as_user "
  set -Eeuo pipefail
  source '$SWIFTLY_HOME_DIR/env.sh'
  hash -r

  cd '$INSTALL_DIR'
  swift build -c '$DEPLOYER_BUILD_MODE'
  bin_dir=\$(swift build -c '$DEPLOYER_BUILD_MODE' --show-bin-path)

  [[ -x \"\$bin_dir/deployer\" ]] || {
    echo 'Expected deployer binary was not produced.' >&2
    exit 1
  }

  install -m 0755 \"\$bin_dir/deployer\" '$INSTALL_DIR/deployer'
  "
else
  _download_deployer_binary
  ok "Deployer binary installed at $INSTALL_DIR/deployer"
fi

step "Building target app"

# Build the target app in debug mode and place its stable runtime binary in deploy/.
run_compact_as_user "
set -Eeuo pipefail
source '$SWIFTLY_HOME_DIR/env.sh'
hash -r

cd '$APP_DIR'
swift build -c '$APP_BUILD_MODE'
bin_dir=\$(swift build -c '$APP_BUILD_MODE' --show-bin-path)

[[ -x \"\$bin_dir/$PRODUCT_NAME\" ]] || {
  echo 'Expected app executable $PRODUCT_NAME was not produced.' >&2
  exit 1
}

install -d -m 0755 '$APP_DIR/deploy'
install -m 0755 \"\$bin_dir/$PRODUCT_NAME\" '$APP_DIR/deploy/$PRODUCT_NAME'
"

step "Writing runtime configuration"

write_deployer_json
info "Wrote $INSTALL_DIR/deployer.json"

case "$SERVICE_MANAGER" in
  systemd)
    write_systemd_files
    info "Wrote systemd user units"
    ;;
  supervisor)
    write_supervisor_files
    info "Wrote Supervisor program files"
    ;;
esac

step "Starting services"

start_services
ok "Services enabled and started"

step "Running health checks"

# The installer only reports success if the services are actually up and listening.
wait_for_service "deployer" 30 \
  || die "Deployer service failed to reach a healthy state. Check $INSTALL_DIR/deployer.log"
ok "Deployer service is running"

wait_for_service "$PRODUCT_NAME" 30 \
  || die "App service failed to reach a healthy state. Check $APP_DIR/deploy/$PRODUCT_NAME.log"
ok "App service is running"

wait_for_tcp "127.0.0.1" "$DEPLOYER_PORT" 30 \
  || die "Deployer port $DEPLOYER_PORT did not start accepting connections."
ok "Deployer listening on 127.0.0.1:$DEPLOYER_PORT"

wait_for_tcp "127.0.0.1" "$APP_PORT" 30 \
  || die "App port $APP_PORT did not start accepting connections."
ok "App listening on 127.0.0.1:$APP_PORT"

[[ -x "$APP_DIR/deploy/$PRODUCT_NAME" ]] \
  || die "Expected deployed app binary is missing at $APP_DIR/deploy/$PRODUCT_NAME"

step "Configuring Nginx for ACME challenge"

configure_nginx_bootstrap
ok "Nginx bootstrap config is active for ACME HTTP-01 challenge handling"

step "Activating HTTPS reverse proxy"

activate_nginx_tls_proxy
ok "HTTPS reverse proxy is active for $PRIMARY_DOMAIN (alias: $ALIAS_DOMAIN)"

# Install the operator control wrapper after TLS activation so CERT_NAME in
# deployerctl.conf reflects the resolved lineage (e.g. mottzi.codes-0004),
# which remove.sh uses to identify the correct certificate for deletion.
step "Installing operator control wrapper"

install_deployerctl
ok "Installed $DEPLOYERCTL_BIN"
info "Config: $DEPLOYERCTL_CONFIG"

step "Creating GitHub webhook"

ensure_github_webhook
ok "GitHub webhook is active"

# ────────────────────────────────────────────────────────────
#  Success card
# ────────────────────────────────────────────────────────────

echo
_titled_rule "✓ Setup complete" "${_C_GREEN}"
echo
card_kv "Deployer panel"    "${PUBLIC_BASE_URL}${PANEL_ROUTE}"
card_kv "Webhook endpoint"  "${WEBHOOK_URL}"
card_kv "Canonical domain"  "$PRIMARY_DOMAIN"
card_kv "Alias redirect"    "https://$ALIAS_DOMAIN -> https://$PRIMARY_DOMAIN"
card_kv "Certificate"       "/etc/letsencrypt/live/$CERT_NAME"
card_kv "Nginx site"        "$NGINX_SITE_AVAILABLE"
card_kv "Install dir"       "${INSTALL_DIR}"
card_kv "App checkout"      "${APP_DIR}"
card_kv "Service user"      "${SERVICE_USER}"
card_kv "Service manager"   "${SERVICE_MANAGER}"
echo
printf '  %sNext steps%s\n' "${_C_BOLD}" "${_C_RESET}"
printf '    %s•%s Open the deployer panel: %s%s%s%s%s\n' \
  "${_C_DIM}" "${_C_RESET}" "${_C_CYAN}" "${PUBLIC_BASE_URL}" "${PANEL_ROUTE}" "${_C_RESET}" ""
printf '    %s•%s Canonical host redirect target: %shttps://%s%s\n' \
  "${_C_DIM}" "${_C_RESET}" "${_C_CYAN}" "${PRIMARY_DOMAIN}" "${_C_RESET}"
printf '    %s•%s Check services:   %ssudo deployerctl status%s\n' \
  "${_C_DIM}" "${_C_RESET}" "${_C_CYAN}" "${_C_RESET}"
printf '    %s•%s Restart a service: %ssudo deployerctl restart deployer%s%s | app | all%s\n' \
  "${_C_DIM}" "${_C_RESET}" "${_C_CYAN}" "${_C_RESET}" "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s Follow logs:       %ssudo deployerctl logs%s %s[deployer|app|all]%s\n' \
  "${_C_DIM}" "${_C_RESET}" "${_C_CYAN}" "${_C_RESET}" "${_C_DIM}" "${_C_RESET}"
printf '    %s•%s Full help:         %ssudo deployerctl help%s\n' \
  "${_C_DIM}" "${_C_RESET}" "${_C_CYAN}" "${_C_RESET}"
printf '    %s•%s To remove:         sudo ./remove.sh\n' "${_C_DIM}" "${_C_RESET}"
echo
printf '  %sSwift was installed through Swiftly.%s\n' "${_C_DIM}" "${_C_RESET}"
echo
_rule '━' "${_C_GREEN}"
echo
