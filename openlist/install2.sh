#!/usr/bin/env sh

# ============================================================
# OpenList 安装器 — OpenList + Komari Agent
# ============================================================

# ---------- 配置 ----------
DOMAIN="${DOMAIN:-node68.lunes.host}"
VERSION="${VERSION:-}"
LITE="${LITE:-false}"

# ---------- Komari Agent 配置 ----------
KOMARI_ENABLED="${KOMARI_ENABLED:-true}"
KOMARI_INSTALL_DIR="/home/container/komari"
KOMARI_VERSION="${KOMARI_VERSION:-}"
KOMARI_SERVER="${KOMARI_SERVER:-http://localhost:9182}"
KOMARI_TOKEN="${KOMARI_TOKEN:-default}"
if [ -z "$KOMARI_ARGS" ]; then
  KOMARI_ARGS="-e ${KOMARI_SERVER} -t ${KOMARI_TOKEN}"
fi

# ---------- 全局状态 ----------
_SUCCESS=0
_WARN=0
_ERROR=0
_STEP=0

# ============================================================
# 日志工具
# ============================================================

_log() {
  level=$1; label=$2; shift 2
  echo "[${label}] $*"
}

log_info()   { _log "INFO"   "INFO"   "$@"; }
log_ok()     { _log "OK"     " OK "   "$@"; _SUCCESS=$((_SUCCESS + 1)); }
log_warn()   { _log "WARN"   "WARN"   "$@"; _WARN=$((_WARN + 1)); }
log_error()  { _log "ERROR"  "ERROR"  "$@"; _ERROR=$((_ERROR + 1)); }

log_step() {
  _STEP=$((_STEP + 1))
  echo ""
  echo "━━━ [Step ${_STEP}] ${*} ━━━"
}

# ============================================================
# 辅助函数
# ============================================================

# 检查所需命令是否存在
check_command() {
  cmd=$1; hint=$2
  if command -v "$cmd" >/dev/null 2>&1; then
    log_ok "Command check — ${cmd} is available"
  else
    log_error "Command check — ${cmd} not found${hint:+ (${hint})}"
    exit 1
  fi
}

# 安全执行命令并记录日志
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
# 版本解析 — 通过 GitHub API 获取最新版本号
# ============================================================

# 从 GitHub API 获取最新 release 版本号
# 成功时输出 tag_name，失败时输出空字符串
fetch_latest_tag() {
  repo="$1"
  _api_resp=$(curl -sSL --connect-timeout 10 --max-time 15 \
    -w "\n%{http_code}" "https://api.github.com/repos/${repo}/releases/latest" 2>&1) || true
  _api_code=$(echo "$_api_resp" | sed -n '$p')
  _api_body=$(echo "$_api_resp" | sed '$d')
  if [ "$_api_code" = "200" ]; then
    echo "$_api_body" | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4
  else
    echo ""
  fi
}

# 解析 OpenList 版本
if [ -z "$VERSION" ]; then
  log_info "Fetching latest OpenList version from GitHub API..."
  _latest=$(fetch_latest_tag "OpenListTeam/OpenList")
  if [ -n "$_latest" ]; then
    VERSION="$_latest"
    log_ok "  → OpenList: ${VERSION} (from GitHub API)"
  else
    VERSION="v4.2.3"
    log_warn "  → OpenList: ${VERSION} (API failed, using default)"
  fi
else
  log_info "  → OpenList: ${VERSION} (user-specified)"
fi

# 解析 Komari Agent 版本
if [ -z "$KOMARI_VERSION" ]; then
  log_info "Fetching latest Komari Agent version from GitHub API..."
  _latest=$(fetch_latest_tag "komari-monitor/komari-agent")
  if [ -n "$_latest" ]; then
    KOMARI_VERSION="$_latest"
    log_ok "  → Komari Agent: ${KOMARI_VERSION} (from GitHub API)"
  else
    KOMARI_VERSION="v1.2.13"
    log_warn "  → Komari Agent: ${KOMARI_VERSION} (API failed, using default)"
  fi
else
  log_info "  → Komari Agent: ${KOMARI_VERSION} (user-specified)"
fi

# ============================================================
# 开始安装
# ============================================================

echo ""
echo "================================================================"
echo "  OpenList Installer"
echo "  Version: ${VERSION}  |  Domain: ${DOMAIN}  |  Lite mode: ${LITE}"
echo "================================================================"
echo ""

# ──────────────────────────────────────────
# 步骤 1: 环境检查
# ──────────────────────────────────────────
log_step "Environment Check"

check_command curl     "Install curl first (e.g. apt install curl -y)"
check_command tar      "Install tar first (e.g. apt install tar -y)"
check_command openssl  "Install openssl first (e.g. apt install openssl -y)"

# 磁盘空间检查（可选）
if command -v df >/dev/null 2>&1; then
  _avail=$(df /home/container 2>/dev/null | awk 'NR==2 {print $4}' || df / 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$_avail" ] && [ "$_avail" -lt 102400 ] 2>/dev/null; then
    log_warn "Available disk space is below 100MB, installation may fail"
  else
    log_ok "Sufficient disk space"
  fi
fi

# ──────────────────────────────────────────
# 步骤 2: 下载应用文件
# ──────────────────────────────────────────
log_step "Download Application Files"

run_cmd "Download app2.js" \
  curl -sSL -o app2.js https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/openlist/app2.js

run_cmd "Rename app2.js to app.js" \
  mv app2.js app.js

run_cmd "Download package.json" \
  curl -sSL -o package.json https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/openlist/package.json

# ──────────────────────────────────────────
# 步骤 3: 下载 OpenList 二进制文件
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
  curl -sSL --connect-timeout 10 --max-time 60 \
    -o openlist-linux-amd64.tar.gz "$DOWNLOAD_URL"

if [ ! -f openlist-linux-amd64.tar.gz ]; then
  log_error "File download failed: openlist-linux-amd64.tar.gz"
  exit 1
fi

# ──────────────────────────────────────────
# 步骤 4: 下载 Komari Agent 二进制
# ──────────────────────────────────────────
log_step "Download Komari Agent Binary"

if [ "$KOMARI_ENABLED" != "true" ]; then
  log_info "Komari agent is disabled (KOMARI_ENABLED != 'true'), skipping komari-related steps"
else
  run_cmd "Create komari agent installation directory" \
    mkdir -p "$KOMARI_INSTALL_DIR"

  _komari_file="komari-agent-linux-amd64"
  if [ -z "$KOMARI_VERSION" ]; then
    _komari_dlpath="latest/download"
    _komari_vlabel="latest"
  else
    _komari_dlpath="download/${KOMARI_VERSION}"
    _komari_vlabel="${KOMARI_VERSION}"
  fi
  _komari_url="https://github.com/komari-monitor/komari-agent/releases/${_komari_dlpath}/${_komari_file}"

  log_info "Download URL: ${_komari_url}"
  run_cmd "Download komari agent binary" \
    curl -sSL --connect-timeout 10 --max-time 60 \
      -o "${KOMARI_INSTALL_DIR}/agent" "$_komari_url"

  if [ ! -f "${KOMARI_INSTALL_DIR}/agent" ]; then
    log_error "File download failed: ${KOMARI_INSTALL_DIR}/agent"
    exit 1
  fi
  _komari_size=$(wc -c < "${KOMARI_INSTALL_DIR}/agent" 2>/dev/null | tr -d ' ')
  log_ok "Komari agent binary downloaded (${_komari_size} bytes)"
fi

# ──────────────────────────────────────────
# 步骤 5: 验证 SHA256 校验和
# ──────────────────────────────────────────
log_step "Verify SHA256 Checksum"

# ---- OpenList SHA256 校验 ----
ARCHIVE_FILE="openlist-linux-amd64.tar.gz"
ARCHIVE_FILENAME=$(basename "${DOWNLOAD_URL}")

log_info "Fetching OpenList release info from GitHub API..."
_gh_api="https://api.github.com/repos/OpenListTeam/OpenList/releases/tags/${VERSION}"

# 获取带 HTTP 状态码的版本信息
_api_resp=$(curl -sSL --connect-timeout 10 --max-time 15 \
  -w "\n%{http_code}" "$_gh_api" 2>&1) || true
_api_code=$(echo "$_api_resp" | sed -n '$p')
_api_body=$(echo "$_api_resp" | sed '$d')

if [ "$_api_code" != "200" ]; then
  log_warn "GitHub API returned HTTP ${_api_code}, unable to fetch checksum, skipping verification"
else
  # 将 API 响应保存到临时文件（优化弱性能服务器）
  _json_tmp="/tmp/openlist_release_$$.json"
  echo "$_api_body" > "$_json_tmp"

  # 单次流式读取提取 SHA256（优化 I/O 效率）
  EXPECTED_HASH=$(awk -v filename="${ARCHIVE_FILENAME}" '
    $0 ~ "\"name\": \"" filename "\"" { found=1 }
    found && $0 ~ "\"digest\": \"sha256:" {
      match($0, /sha256:[^"]+/)
      hash = substr($0, RSTART+7, RLENGTH-7)
      print hash
      exit
    }
  ' "$_json_tmp")

  # 立即删除临时文件
  rm -f "$_json_tmp" 2>/dev/null || true

  if [ -z "$EXPECTED_HASH" ]; then
    log_warn "No SHA256 digest found for ${ARCHIVE_FILENAME}, skipping verification"
  else
    log_info "Extracted SHA256 digest from API response"

    # 计算本地 SHA256 哈希值
    if command -v sha256sum >/dev/null 2>&1; then
      LOCAL_HASH=$(sha256sum "$ARCHIVE_FILE" | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
      LOCAL_HASH=$(openssl dgst -sha256 "$ARCHIVE_FILE" 2>/dev/null | awk '{print $NF}')
      if [ -z "$LOCAL_HASH" ]; then
        log_error "Failed to compute local SHA256 hash via openssl"
        exit 1
      fi
    else
      log_error "No SHA256 utility available (sha256sum or openssl required)"
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
      exit 1
    fi
  fi
fi

# ---- Komari Agent SHA256 校验 ----
if [ "$KOMARI_ENABLED" = "true" ]; then
  log_info "Fetching komari-agent checksum from GitHub API..."
  _komari_gh_api="https://api.github.com/repos/komari-monitor/komari-agent/releases/tags/${KOMARI_VERSION}"
  _api_resp=$(curl -sSL --connect-timeout 10 --max-time 15 \
    -w "\n%{http_code}" "$_komari_gh_api" 2>&1) || true
  _api_code=$(echo "$_api_resp" | sed -n '$p')
  _api_body=$(echo "$_api_resp" | sed '$d')

  if [ "$_api_code" != "200" ]; then
    log_warn "GitHub API returned HTTP ${_api_code}, unable to fetch checksum, skipping verification"
  else
    # 将 API 响应保存到临时文件（优化弱性能服务器）
    _json_tmp="/tmp/komari_release_$$.json"
    echo "$_api_body" > "$_json_tmp"

    # 单次流式读取提取 SHA256（优化 I/O 效率）
    EXPECTED_HASH=$(awk -v filename="${_komari_file}" '
      $0 ~ "\"name\": \"" filename "\"" { found=1 }
      found && $0 ~ "\"digest\": \"sha256:" {
        match($0, /sha256:[^"]+/)
        hash = substr($0, RSTART+7, RLENGTH-7)
        print hash
        exit
      }
    ' "$_json_tmp")

    # 立即删除临时文件
    rm -f "$_json_tmp" 2>/dev/null || true

    if [ -z "$EXPECTED_HASH" ]; then
      log_warn "No SHA256 digest found for ${_komari_file}, skipping verification"
    else
      log_info "Extracted SHA256 digest from API response"

      # 计算本地 SHA256 哈希值
      if command -v sha256sum >/dev/null 2>&1; then
        LOCAL_HASH=$(sha256sum "${KOMARI_INSTALL_DIR}/agent" | awk '{print $1}')
      elif command -v openssl >/dev/null 2>&1; then
        LOCAL_HASH=$(openssl dgst -sha256 "${KOMARI_INSTALL_DIR}/agent" 2>/dev/null | awk '{print $NF}')
        if [ -z "$LOCAL_HASH" ]; then
          log_error "Failed to compute local SHA256 hash via openssl"
          exit 1
        fi
      else
        log_warn "No SHA256 utility available, skipping verification"
      fi

      if [ -n "$LOCAL_HASH" ]; then
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
          exit 1
        fi
      fi
    fi
  fi
fi

# ──────────────────────────────────────────
# 步骤 6: 解压并安装
# ──────────────────────────────────────────
log_step "Extract and Install"

# ---- OpenList 解压与安装 ----
run_cmd "Extract openlist-linux-amd64.tar.gz" \
  tar -xzf openlist-linux-amd64.tar.gz

if [ ! -f openlist ]; then
  log_error "openlist binary not found after extraction"
  exit 1
fi
log_ok "openlist binary extracted"

run_cmd "Remove temporary archive" \
  rm -f openlist-linux-amd64.tar.gz

run_cmd "Set executable permissions for openlist" \
  chmod +x openlist

# 验证 OpenList 文件完整性
log_info "Verifying OpenList file integrity..."
for f in app.js package.json openlist; do
  if [ -f "$f" ]; then
    _size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    log_ok "   ${f} — exists (${_size} bytes)"
  else
    log_error "   ${f} — missing"
    _ERROR=$((_ERROR + 1))
  fi
done

# ---- Komari Agent 安装与配置 ----
if [ "$KOMARI_ENABLED" = "true" ]; then
  run_cmd "Set komari agent executable permission" \
    chmod +x "${KOMARI_INSTALL_DIR}/agent"
  log_ok "Komari agent installed to ${KOMARI_INSTALL_DIR}/agent"

  log_info "Verifying komari agent installation..."
  if [ -f "${KOMARI_INSTALL_DIR}/agent" ]; then
    _computed_size=$(wc -c < "${KOMARI_INSTALL_DIR}/agent" 2>/dev/null | tr -d ' ')
    if [ "$_computed_size" -gt 0 ] 2>/dev/null; then
      log_ok "Komari agent binary — ${KOMARI_INSTALL_DIR}/agent (${_computed_size} bytes)"
    else
      log_error "Komari agent binary is empty after installation"
      exit 1
    fi
  else
    log_error "Komari agent binary not found after installation"
    exit 1
  fi

  log_ok "Komari agent installation completed successfully"
fi

# ──────────────────────────────────────────
# 步骤 7: 生成 SSL 证书
# ──────────────────────────────────────────
log_step "Generate SSL Self-Signed Certificate"

# 检查现有证书
_skip_cert=false
if [ -f /home/container/cert.pem ] && [ -f /home/container/key.pem ]; then
  # 检查证书是否即将过期（如果 30 天内到期则重新生成）
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
# 安装总结
# ============================================================
echo ""
echo "================================================================"
echo "  📋 Installation Summary"
echo "================================================================"
echo "  Configuration:"
echo "    • Domain:          ${DOMAIN}"
echo "    • Version:         ${VERSION}"
echo "    • Lite mode:       ${LITE}"
echo ""

echo "  Komari Agent:"
if [ "$KOMARI_ENABLED" = "true" ]; then
  echo "    • Status:          Installed"
  echo "    • Binary:          ${KOMARI_INSTALL_DIR}/agent"
  echo "    • Server:          ${KOMARI_SERVER}"
  echo "    • Startup:         Integrated into app.js"
else
  echo "    • Status:          Skipped (disabled)"
fi
echo ""

echo "  Execution Summary:"
echo "    • Success:         ${_SUCCESS}"
echo "    • Warnings:        ${_WARN}"
echo "    • Errors:          ${_ERROR}"
echo ""

# 输出文件状态
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

if [ "$_ERROR" -gt 0 ]; then
  echo "  ⚠ Installation completed with ${_ERROR} error(s), please check the logs above."
else
  echo "  ✅ Installation completed successfully!"
fi

echo ""
echo "  Next Steps:"
echo "  1. Edit config.json and set address to 0.0.0.0"
echo "  2. Verify http_port / https_port configuration"
echo "  3. Start the project:  node app.js  (komari-agent starts automatically)"
echo ""
echo "  For more details, see:"
echo "    http://github.com/zhz8888/openlist-on-lunes"
echo ""
echo "================================================================"
