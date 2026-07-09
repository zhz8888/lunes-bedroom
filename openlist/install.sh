#!/usr/bin/env sh

# ============================================================
# OpenList Installer — Detailed Logging Installer
# ============================================================

# ---------- Configuration ----------
DOMAIN="${DOMAIN:-node68.lunes.host}"
VERSION="${VERSION:-v4.2.3}"
LITE="${LITE:-false}"

# ---------- Global State ----------
_SUCCESS=0
_WARN=0
_ERROR=0
_STEP=0

# ============================================================
# Logging Utilities
# ============================================================

# Detect terminal color support
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  _C_INFO="\033[1;34m"    # Blue
  _C_OK="\033[1;32m"      # Green
  _C_WARN="\033[1;33m"    # Yellow
  _C_ERROR="\033[1;31m"   # Red
  _C_BOLD="\033[1m"
  _C_RESET="\033[0m"
else
  _C_INFO=""; _C_OK=""; _C_WARN=""; _C_ERROR=""; _C_BOLD=""; _C_RESET=""
fi

_timestamp() {
  date +'%Y-%m-%d %H:%M:%S'
}

_log() {
  level=$1; color=$2; label=$3; shift 3
  echo "${color}[$(_timestamp)] [${label}] $*${_C_RESET}"
}

log_info()   { _log "INFO"   "${_C_INFO}"   "INFO"   "$@"; }
log_ok()     { _log "OK"     "${_C_OK}"     " OK "   "$@"; _SUCCESS=$((_SUCCESS + 1)); }
log_warn()   { _log "WARN"   "${_C_WARN}"   "WARN"   "$@"; _WARN=$((_WARN + 1)); }
log_error()  { _log "ERROR"  "${_C_ERROR}"  "ERROR"  "$@"; _ERROR=$((_ERROR + 1)); }

log_step() {
  _STEP=$((_STEP + 1))
  echo ""
  echo "${_C_BOLD}━━━ [Step ${_STEP}] ${*} ━━━${_C_RESET}"
}

log_separator() {
  echo "${_C_BOLD}------------------------------------------------------------${_C_RESET}"
}

# ============================================================
# Helper Functions
# ============================================================

# Check if required command exists
check_command() {
  cmd=$1; hint=$2
  if command -v "$cmd" >/dev/null 2>&1; then
    log_ok "Command check — ${cmd} is available"
  else
    log_error "Command check — ${cmd} not found${hint:+ (${hint})}"
    exit 1
  fi
}

# Safely execute command with logging
run_cmd() {
  desc=$1; shift
  log_info "${desc}..."
  if "$@" 2>&1; then
    log_ok "${desc} — done"
    return 0
  else
    _code=$?
    log_error "${desc} — failed (exit code: ${_code})"
    return $_code
  fi
}

# ============================================================
# Installation Start
# ============================================================

echo ""
echo "${_C_BOLD}================================================================${_C_RESET}"
echo "${_C_BOLD}  OpenList Installer${_C_RESET}"
echo "${_C_BOLD}  Version: ${VERSION}  |  Domain: ${DOMAIN}  |  Lite mode: ${LITE}${_C_RESET}"
echo "${_C_BOLD}  Start time: $(_timestamp)${_C_RESET}"
echo "${_C_BOLD}================================================================${_C_RESET}"
echo ""

# ──────────────────────────────────────────
# Step 1: Environment Check
# ──────────────────────────────────────────
log_step "Environment Check"

check_command curl     "Install curl first (e.g. apt install curl -y)"
check_command tar      "Install tar first (e.g. apt install tar -y)"
check_command openssl  "Install openssl first (e.g. apt install openssl -y)"

# Disk space check (optional)
if command -v df >/dev/null 2>&1; then
  _avail=$(df /home/container 2>/dev/null | awk 'NR==2 {print $4}' || df / 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$_avail" ] && [ "$_avail" -lt 102400 ] 2>/dev/null; then
    log_warn "Available disk space is below 100MB, installation may fail"
  else
    log_ok "Sufficient disk space"
  fi
fi

# ──────────────────────────────────────────
# Step 2: Download Application Files
# ──────────────────────────────────────────
log_step "Download Application Files"

run_cmd "Download app.js" \
  curl -sSL -o app.js https://raw.githubusercontent.com/zhz8888/openlist-on-lunes/refs/heads/main/app.js

run_cmd "Download package.json" \
  curl -sSL -o package.json https://raw.githubusercontent.com/zhz8888/openlist-on-lunes/refs/heads/main/package.json

# ──────────────────────────────────────────
# Step 3: Download OpenList Binary
# ──────────────────────────────────────────
log_step "Download OpenList Binary"

if [ "$LITE" = "true" ]; then
  DOWNLOAD_URL="https://github.com/OpenListTeam/OpenList/releases/download/$VERSION/openlist-linux-amd64-lite.tar.gz"
  log_info "Version type: lite"
else
  DOWNLOAD_URL="https://github.com/OpenListTeam/OpenList/releases/download/$VERSION/openlist-linux-amd64.tar.gz"
  log_info "Version type: full"
fi

log_info "Download URL: ${DOWNLOAD_URL}"

run_cmd "Download OpenList archive" \
  curl -sSL -o openlist-linux-amd64.tar.gz "$DOWNLOAD_URL"

if [ ! -f openlist-linux-amd64.tar.gz ]; then
  log_error "File download failed: openlist-linux-amd64.tar.gz"
  exit 1
fi

# ──────────────────────────────────────────
# Step 4: Extract and Install
# ──────────────────────────────────────────
log_step "Extract and Install"

run_cmd "Extract openlist-linux-amd64.tar.gz" \
  tar -xzf openlist-linux-amd64.tar.gz

if [ ! -f openlist ]; then
  log_error "openlist binary not found after extraction"
  exit 1
fi
log_ok "openlist binary extracted"

run_cmd "Remove temporary archive" \
  rm -f openlist-linux-amd64.tar.gz

run_cmd "Set executable permissions" \
  chmod +x openlist

# Verify file integrity
log_info "Verifying file integrity..."
for f in app.js package.json openlist; do
  if [ -f "$f" ]; then
    _size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    log_ok "   ${f} — exists (${_size} bytes)"
  else
    log_error "   ${f} — missing"
    _ERROR=$((_ERROR + 1))
  fi
done

# ──────────────────────────────────────────
# Step 5: Generate SSL Certificate
# ──────────────────────────────────────────
log_step "Generate SSL Self-Signed Certificate"

# Check for existing certificate
_skip_cert=false
if [ -f /home/container/cert.pem ] && [ -f /home/container/key.pem ]; then
  # Check if certificate is about to expire (regenerate if within 30 days)
  if command -v openssl >/dev/null 2>&1; then
    _expires=$(openssl x509 -in /home/container/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2)
    log_info "Existing certificate expiry: ${_expires:-unknown}"
  fi
  log_info "Certificate files exist, skipping generation"
  _skip_cert=true
fi

if [ "$_skip_cert" = false ]; then
  log_info "Certificate domain: ${DOMAIN}"
  log_info "Certificate validity: 3650 days"
  if openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout /home/container/key.pem \
    -out /home/container/cert.pem \
    -subj "/CN=$DOMAIN" 2>&1; then
    log_ok "SSL certificate generation — done"
  else
    _cert_code=$?
    log_warn "SSL certificate generation — failed (exit code: ${_cert_code}), you can generate it manually later"
    log_warn "Manual command: openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout /home/container/key.pem -out /home/container/cert.pem -subj \"/CN=${DOMAIN}\""
  fi
fi

# ============================================================
# Installation Summary
# ============================================================
echo ""
echo "${_C_BOLD}================================================================${_C_RESET}"
echo "${_C_BOLD}  📋 Installation Summary${_C_RESET}"
echo "${_C_BOLD}  Finish time: $(_timestamp)${_C_RESET}"
echo "${_C_BOLD}================================================================${_C_RESET}"

log_separator
echo "  Configuration:"
echo "    • Domain:          ${DOMAIN}"
echo "    • Version:         ${VERSION}"
echo "    • Lite mode:       ${LITE}"
echo ""
echo "  Execution Summary:"
echo "    • Success:         ${_SUCCESS}"
echo "    • Warnings:        ${_WARN}"
echo "    • Errors:          ${_ERROR}"
echo ""

# Output file status
echo "  Files:"
for f in app.js package.json openlist; do
  if [ -f "$f" ]; then
    _size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    echo "    ✅ ${f} (${_size} bytes)"
  else
    echo "    ❌ ${f} (missing)"
  fi
done

_cert_exists="no"
[ -f /home/container/cert.pem ] && _cert_exists="yes"
echo "    ✅ SSL certificate: ${_cert_exists}"

log_separator

if [ "$_ERROR" -gt 0 ]; then
  echo "  ${_C_ERROR}⚠ Installation completed with ${_ERROR} error(s), please check the logs above.${_C_RESET}"
else
  echo "  ${_C_OK}✅ Installation completed successfully!${_C_RESET}"
fi

echo ""
echo "  ${_C_BOLD}Next Steps:${_C_RESET}"
echo "  1. Edit config.json and set address to 0.0.0.0"
echo "  2. Verify http_port / https_port configuration"
echo "  3. Start OpenList:  ./openlist"
echo ""
echo "  For more details, see:"
echo "    http://github.com/zhz8888/openlist-on-lunes"
echo ""
echo "${_C_BOLD}================================================================${_C_RESET}"
