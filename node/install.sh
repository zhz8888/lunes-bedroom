#!/usr/bin/env sh

# ============================================================
# Node Installer — Xray + Hysteria2 One-click Node Setup
# ============================================================

# ---------- Configuration ----------
DOMAIN="${DOMAIN:-node68.lunes.host}"
PORT="${PORT:-10008}"
UUID="${UUID:-2584b733-9095-4bec-a7d5-62b473540f7a}"
HY2_PASSWORD="${HY2_PASSWORD:-vevc.HY2.Password}"
VERSION_XRAY="${VERSION_XRAY:-v25.8.3}"
VERSION_HY2="${VERSION_HY2:-v2.6.2}"

# ---------- Paths ----------
XRAY_DIR="/home/container/xy"
HY2_DIR="/home/container/h2"
NODE_INFO_FILE="/home/container/node.txt"

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
echo "${_C_BOLD}  Node Installer${_C_RESET}"
echo "${_C_BOLD}  Xray: ${VERSION_XRAY}  |  Hysteria2: ${VERSION_HY2}${_C_RESET}"
echo "${_C_BOLD}  Domain: ${DOMAIN}  |  Port: ${PORT}${_C_RESET}"
echo "${_C_BOLD}  Start time: $(_timestamp)${_C_RESET}"
echo "${_C_BOLD}================================================================${_C_RESET}"
echo ""

# ──────────────────────────────────────────
# Step 1: Environment Check
# ──────────────────────────────────────────
log_step "Environment Check"

check_command curl     "Install curl first (e.g. apt install curl -y)"
check_command tar      "Install tar first (e.g. apt install tar -y)"
check_command unzip    "Install unzip first (e.g. apt install unzip -y)"
check_command openssl  "Install openssl first (e.g. apt install openssl -y)"
check_command node     "Install Node.js first (e.g. apt install nodejs -y)"

# Disk space check
if command -v df >/dev/null 2>&1; then
  _avail=$(df /home/container 2>/dev/null | awk 'NR==2 {print $4}' || df / 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$_avail" ] && [ "$_avail" -lt 512000 ] 2>/dev/null; then
    log_warn "Available disk space is below 500MB, installation may fail"
  else
    log_ok "Sufficient disk space"
  fi
fi

# ──────────────────────────────────────────
# Step 2: Download Application Files
# ──────────────────────────────────────────
log_step "Download Application Files"

run_cmd "Download app.js" \
  curl -sSL -o app.js https://raw.githubusercontent.com/vevc/one-node/refs/heads/main/lunes-host/app.js

run_cmd "Download package.json" \
  curl -sSL -o package.json https://raw.githubusercontent.com/vevc/one-node/refs/heads/main/lunes-host/package.json

# ──────────────────────────────────────────
# Step 3: Setup Xray Core
# ──────────────────────────────────────────
log_step "Setup Xray Core"

# Create directory
run_cmd "Create xray directory" \
  mkdir -p "$XRAY_DIR"

# Download Xray archive
run_cmd "Download Xray-core (${VERSION_XRAY})" \
  curl -sSL --connect-timeout 10 --max-time 60 \
    -o "${XRAY_DIR}/Xray-linux-64.zip" \
    "https://github.com/XTLS/Xray-core/releases/download/${VERSION_XRAY}/Xray-linux-64.zip"

if [ ! -f "${XRAY_DIR}/Xray-linux-64.zip" ]; then
  log_error "File download failed: Xray-linux-64.zip"
  exit 1
fi

# Extract archive
run_cmd "Extract Xray archive" \
  unzip -o "${XRAY_DIR}/Xray-linux-64.zip" -d "$XRAY_DIR"

# Remove temporary archive
run_cmd "Remove temporary archive" \
  rm -f "${XRAY_DIR}/Xray-linux-64.zip"

# Rename binary xray -> xy
if [ -f "${XRAY_DIR}/xray" ]; then
  run_cmd "Rename xray binary to xy" \
    mv "${XRAY_DIR}/xray" "${XRAY_DIR}/xy"
  log_ok "xray binary extracted and renamed to xy"
else
  log_error "xray binary not found after extraction"
  exit 1
fi

# Download xray config
run_cmd "Download xray config.json" \
  curl -sSL -o "${XRAY_DIR}/config.json" \
    https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/node/xray-config.json

# Configure port and UUID
run_cmd "Configure PORT in xray config" \
  sed -i "s/10008/$PORT/g" "${XRAY_DIR}/config.json"

run_cmd "Configure UUID in xray config" \
  sed -i "s/YOUR_UUID/$UUID/g" "${XRAY_DIR}/config.json"

# Generate x25519 key pair
log_info "Generating x25519 key pair..."
_keyPair=$("${XRAY_DIR}/xy" x25519 2>&1) || true

if [ -z "$_keyPair" ]; then
  log_error "Failed to generate x25519 key pair"
  exit 1
fi

_privateKey=$(echo "$_keyPair" | grep "Private key" | awk '{print $3}')
_publicKey=$(echo "$_keyPair" | grep "Public key" | awk '{print $3}')

if [ -z "$_privateKey" ] || [ -z "$_publicKey" ]; then
  log_error "Failed to parse x25519 key pair from output"
  exit 1
fi

log_ok "x25519 key pair generated"
log_info "Private key: ${_privateKey}"
log_info "Public key:  ${_publicKey}"

run_cmd "Configure private key in xray config" \
  sed -i "s/YOUR_PRIVATE_KEY/$_privateKey/g" "${XRAY_DIR}/config.json"

# Generate and configure short ID
_shortId=$(openssl rand -hex 4)
log_info "Short ID: ${_shortId}"

run_cmd "Configure short ID in xray config" \
  sed -i "s/YOUR_SHORT_ID/$_shortId/g" "${XRAY_DIR}/config.json"

# Create VLESS URL
_vlessUrl="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=$_publicKey&sid=$_shortId&spx=%2F&type=tcp&headerType=none#lunes-reality"

log_ok "VLESS Reality URL generated"

# Verify xray files
log_info "Verifying xray files..."
for _f in xy config.json geoip.dat geosite.dat; do
  if [ -f "${XRAY_DIR}/${_f}" ]; then
    log_ok "   ${_f} — exists"
  else
    log_warn "   ${_f} — not found (optional file)"
  fi
done

# ──────────────────────────────────────────
# Step 4: Setup Hysteria2
# ──────────────────────────────────────────
log_step "Setup Hysteria2"

# Create directory
run_cmd "Create hysteria directory" \
  mkdir -p "$HY2_DIR"

# Download hysteria binary
run_cmd "Download Hysteria2 binary (${VERSION_HY2})" \
  curl -sSL --connect-timeout 10 --max-time 60 \
    -o "${HY2_DIR}/h2" \
    "https://github.com/apernet/hysteria/releases/download/app%2F${VERSION_HY2}/hysteria-linux-amd64"

if [ ! -f "${HY2_DIR}/h2" ]; then
  log_error "File download failed: hysteria binary"
  exit 1
fi

# Set executable permissions
run_cmd "Set h2 executable permissions" \
  chmod +x "${HY2_DIR}/h2"

# Download hysteria config
run_cmd "Download hysteria config.yaml" \
  curl -sSL -o "${HY2_DIR}/config.yaml" \
    https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/node/hysteria-config.yaml

# Generate SSL certificate
log_info "Generating SSL certificate for domain: ${DOMAIN}"
log_info "Certificate validity: 3650 days"

if openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "${HY2_DIR}/key.pem" \
  -out "${HY2_DIR}/cert.pem" \
  -subj "/CN=$DOMAIN" 2>&1; then
  log_ok "SSL certificate generation — done"
else
  _cert_code=$?
  log_warn "SSL certificate generation — failed (exit code: ${_cert_code}), you can generate it manually later"
fi

# Configure port and password
run_cmd "Configure PORT in hysteria config" \
  sed -i "s/10008/$PORT/g" "${HY2_DIR}/config.yaml"

run_cmd "Configure password in hysteria config" \
  sed -i "s/HY2_PASSWORD/$HY2_PASSWORD/g" "${HY2_DIR}/config.yaml"

# Create HY2 URL with URI-encoded password
log_info "Encoding HY2 password for connection URL..."
_encodedHy2Pwd=$(node -e "console.log(encodeURIComponent(process.argv[1]))" "$HY2_PASSWORD" 2>&1) || true

if [ -z "$_encodedHy2Pwd" ]; then
  log_error "Failed to encode HY2 password"
  exit 1
fi

_hy2Url="hysteria2://$_encodedHy2Pwd@$DOMAIN:$PORT?insecure=1#lunes-hy2"
log_ok "Hysteria2 URL generated"

# Verify hysteria files
log_info "Verifying hysteria files..."
for _f in h2 config.yaml cert.pem key.pem; do
  if [ -f "${HY2_DIR}/${_f}" ]; then
    log_ok "   ${_f} — exists"
  else
    log_warn "   ${_f} — not found (optional file)"
  fi
done

# ──────────────────────────────────────────
# Step 5: Save Connection Info
# ──────────────────────────────────────────
log_step "Save Connection Info"

log_info "Saving connection info to ${NODE_INFO_FILE}..."
echo "$_vlessUrl" > "$NODE_INFO_FILE"
echo "$_hy2Url" >> "$NODE_INFO_FILE"

if [ -f "$NODE_INFO_FILE" ]; then
  log_ok "Connection info saved to ${NODE_INFO_FILE}"
else
  log_error "Failed to save connection info"
  exit 1
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
echo "    • Port:            ${PORT}"
echo "    • UUID:            ${UUID}"
echo "    • Xray Version:    ${VERSION_XRAY}"
echo "    • Hysteria2:       ${VERSION_HY2}"
echo ""
echo "  Execution Summary:"
echo "    • Success:         ${_SUCCESS}"
echo "    • Warnings:        ${_WARN}"
echo "    • Errors:          ${_ERROR}"
echo ""

echo "  Connection Info:"
echo "    ✅ VLESS Reality URL"
echo "    ✅ Hysteria2 URL"
echo "    📄 Saved to: ${NODE_INFO_FILE}"
echo ""

log_separator

if [ "$_ERROR" -gt 0 ]; then
  echo "  ${_C_ERROR}⚠ Installation completed with ${_ERROR} error(s), please check the logs above.${_C_RESET}"
else
  echo "  ${_C_OK}✅ Installation completed successfully!${_C_RESET}"
fi

echo ""
echo "  ${_C_BOLD}Connection URLs:${_C_RESET}"
echo "------------------------------------------------------------"
echo "${_vlessUrl}"
echo "${_hy2Url}"
echo "------------------------------------------------------------"
echo ""
echo "  ${_C_BOLD}Next Steps:${_C_RESET}"
echo "  1. Verify the connection info in ${NODE_INFO_FILE}"
echo "  2. Configure your client with the VLESS or Hysteria2 URL"
echo ""
echo "${_C_BOLD}================================================================${_C_RESET}"
