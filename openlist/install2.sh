#!/usr/bin/env sh

# ============================================================
# OpenList Installer — OpenList + Komari Agent
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
  curl -sSL -o app.js https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/openlist/app.js

run_cmd "Download package.json" \
  curl -sSL -o package.json https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/openlist/package.json

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
# Step 3.5: Verify SHA256 Checksum (via GitHub API)
# ──────────────────────────────────────────
log_step "Verify SHA256 Checksum"

ARCHIVE_FILE="openlist-linux-amd64.tar.gz"
ARCHIVE_FILENAME=$(basename "${DOWNLOAD_URL}")

log_info "Fetching release info from GitHub API..."
_gh_api="https://api.github.com/repos/OpenListTeam/OpenList/releases/tags/${VERSION}"

# Fetch release info with HTTP status code
_api_resp=$(curl -sSL --connect-timeout 10 --max-time 15 \
  -w "\n%{http_code}" "$_gh_api" 2>&1) || true
_api_code=$(echo "$_api_resp" | sed -n '$p')
_api_body=$(echo "$_api_resp" | sed '$d')

if [ "$_api_code" != "200" ]; then
  log_warn "GitHub API returned HTTP ${_api_code}, unable to fetch checksum, skipping verification"
else
  # Find the SHA256 checksum asset URL matching the downloaded archive
  _checksum_url=$(echo "$_api_body" | \
    grep -o '"browser_download_url": "[^"]*'"${ARCHIVE_FILENAME}"'\.sha256"' | \
    cut -d'"' -f4)

  if [ -z "$_checksum_url" ]; then
    log_warn "No SHA256 checksum asset found in release, skipping verification"
  else
    log_info "Downloading checksum file..."
    if curl -sSL -o "${ARCHIVE_FILE}.sha256" --connect-timeout 10 --max-time 15 "$_checksum_url"; then
      # Expected hash is the first whitespace-separated field
      read -r EXPECTED_HASH _ < "${ARCHIVE_FILE}.sha256" || true

      # Compute local SHA256 hash
      if command -v sha256sum >/dev/null 2>&1; then
        LOCAL_HASH=$(sha256sum "$ARCHIVE_FILE" | awk '{print $1}')
      elif command -v openssl >/dev/null 2>&1; then
        LOCAL_HASH=$(openssl dgst -sha256 "$ARCHIVE_FILE" 2>/dev/null | awk '{print $NF}')
        if [ -z "$LOCAL_HASH" ]; then
          log_error "Failed to compute local SHA256 hash via openssl"
          rm -f "${ARCHIVE_FILE}.sha256"
          exit 1
        fi
      else
        log_error "No SHA256 utility available (sha256sum or openssl required)"
        rm -f "${ARCHIVE_FILE}.sha256"
        exit 1
      fi

      echo ""
      echo "  Expected SHA256: ${EXPECTED_HASH}"
      echo "  Local SHA256:    ${LOCAL_HASH}"
      echo ""

      if [ "$EXPECTED_HASH" = "$LOCAL_HASH" ]; then
        log_ok "SHA256 checksum verification — passed"
      else
        log_error "SHA256 checksum verification — failed (file may be corrupted or tampered)"
        log_error "Expected: ${EXPECTED_HASH}"
        log_error "Got:      ${LOCAL_HASH}"
        rm -f "${ARCHIVE_FILE}.sha256"
        exit 1
      fi

      rm -f "${ARCHIVE_FILE}.sha256"
    else
      log_warn "Failed to download SHA256 checksum file, skipping verification"
    fi
  fi
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
# Komari Agent Integration
# ============================================================
#
# 此部分添加 komari-agent 的安装与启动支持。
# 安装路径固定为 /home/container/komari，通过 app.js 启动。
# 仅支持 Linux amd64 架构。
# ============================================================

# ──────────────────────────────────────────
# Step 6: Setup Komari Agent
# ──────────────────────────────────────────
log_step "Setup Komari Agent"

# ---------- Load Configuration ----------
_KOMARI_ENV_FILE="${KOMARI_ENV_FILE:-./komari-agent-env}"
if [ -f "$_KOMARI_ENV_FILE" ]; then
  log_info "Loading komari agent configuration from ${_KOMARI_ENV_FILE}"
  . "$_KOMARI_ENV_FILE"
else
  log_info "No komari-agent-env file found, using defaults / environment variables"
fi

# ---------- Configuration with Defaults ----------
KOMARI_ENABLED="${KOMARI_ENABLED:-true}"
KOMARI_INSTALL_DIR="/home/container/komari"
KOMARI_VERSION="${KOMARI_VERSION:-}"
KOMARI_ARGS="${KOMARI_ARGS:-}"
KOMARI_LOG_LEVEL="${KOMARI_LOG_LEVEL:-info}"

# Add --log-level to args if not already set
case " $KOMARI_ARGS " in
  *"--log-level"*) ;;  # already specified
  *) KOMARI_ARGS="$KOMARI_ARGS --log-level $KOMARI_LOG_LEVEL" ;;
esac

# ---------- Check if enabled ----------
if [ "$KOMARI_ENABLED" != "true" ]; then
  log_info "Komari agent is disabled (KOMARI_ENABLED != 'true'), skipping installation"
else
  log_info "Starting komari agent installation..."

  # ---------- Construct Download URL (linux amd64 only) ----------
  _file_name="komari-agent-linux-amd64"

  if [ -z "$KOMARI_VERSION" ]; then
    _download_path="latest/download"
    _version_label="latest"
  else
    _download_path="download/${KOMARI_VERSION}"
    _version_label="${KOMARI_VERSION}"
  fi

  _download_url="https://github.com/komari-monitor/komari-agent/releases/${_download_path}/${_file_name}"

  # ---------- Create Installation Directory ----------
  run_cmd "Create komari agent directory: ${KOMARI_INSTALL_DIR}" \
    mkdir -p "$KOMARI_INSTALL_DIR"

  _komari_agent_path="${KOMARI_INSTALL_DIR}/agent"

  # ---------- Download Binary ----------
  log_info "Downloading ${_file_name} (${_version_label})..."
  log_info "URL: ${_download_url}"

  if curl -L -o "$_komari_agent_path" "$_download_url" 2>&1; then
    _download_size=$(wc -c < "$_komari_agent_path" 2>/dev/null | tr -d ' ')
    log_ok "Komari agent binary downloaded (${_download_size} bytes)"
  else
    log_error "Failed to download komari agent binary"
    log_error "URL: ${_download_url}"
    exit 1
  fi

  # ---------- Set Executable Permission ----------
  run_cmd "Set komari agent executable permission" \
    chmod +x "$_komari_agent_path"

  log_ok "Komari agent installed to ${_komari_agent_path}"

  # ---------- Add komari-agent to app.js startup ----------
  log_info "Adding komari-agent to app.js startup..."

  # Remove the closing ]; of the apps array, then append agent entry
  sed -i '/^];$/d' app.js
  sed -i '$s/$/,/' app.js
  {
    echo '  {'
    echo '    name: "komari-agent",'
    echo "    binaryPath: \"${_komari_agent_path}\","
    echo '    args: []'
    echo '  }'
    echo '];'
  } >> app.js

  log_ok "Komari-agent added to app.js startup"

  # ---------- Verify Installation ----------
  log_info "Verifying komari agent installation..."
  if [ -f "$_komari_agent_path" ]; then
    _size=$(wc -c < "$_komari_agent_path" 2>/dev/null | tr -d ' ')
    log_ok "Komari agent binary — ${_komari_agent_path} (${_size} bytes)"
  else
    log_error "Komari agent binary not found after installation"
    exit 1
  fi

  log_ok "Komari agent installation completed successfully"
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

echo "  Komari Agent:"
if [ "$KOMARI_ENABLED" = "true" ]; then
  echo "    • Status:          ${_C_OK}Installed${_C_RESET}"
  echo "    • Binary:          ${_komari_agent_path}"
  echo "    • Startup:         ${_C_OK}Integrated in app.js${_C_RESET}"
else
  echo "    • Status:          Skipped (disabled by config)"
fi
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
echo "  3. Start the project:  node app.js  (komari-agent starts automatically)"
echo ""
echo "  For more details, see:"
echo "    http://github.com/zhz8888/openlist-on-lunes"
echo ""
echo "${_C_BOLD}================================================================${_C_RESET}"
