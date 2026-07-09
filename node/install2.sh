#!/usr/bin/env sh

# ============================================================
# 节点安装器 — Xray + Hysteria2 + Komari Agent
# ============================================================

# ---------- 配置 ----------
DOMAIN="${DOMAIN:-node68.lunes.host}"
PORT="${PORT:-10008}"
UUID="${UUID:-2584b733-9095-4bec-a7d5-62b473540f7a}"
HY2_PASSWORD="${HY2_PASSWORD:-vevc.HY2.Password}"
VERSION_XRAY="${VERSION_XRAY:-}"
VERSION_HY2="${VERSION_HY2:-}"

# ---------- Komari Agent 配置 ----------
KOMARI_ENABLED="${KOMARI_ENABLED:-true}"
KOMARI_INSTALL_DIR="/home/container/komari"
KOMARI_VERSION="${KOMARI_VERSION:-}"
KOMARI_SERVER="${KOMARI_SERVER:-http://localhost:9182}"
KOMARI_TOKEN="${KOMARI_TOKEN:-default}"
if [ -z "$KOMARI_ARGS" ]; then
  KOMARI_ARGS="-e ${KOMARI_SERVER} -t ${KOMARI_TOKEN}"
fi

# ---------- 路径 ----------
XRAY_DIR="/home/container/xy"
HY2_DIR="/home/container/h2"
NODE_INFO_FILE="/home/container/node.txt"

# ---------- 全局状态 ----------
_SUCCESS=0
_WARN=0
_ERROR=0
_STEP=0

# ============================================================
# 日志工具
# ============================================================

# 检测终端颜色支持
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  _C_INFO="\033[1;34m"    # 蓝色
  _C_OK="\033[1;32m"      # 绿色
  _C_WARN="\033[1;33m"    # 黄色
  _C_ERROR="\033[1;31m"   # 红色
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

# 解析 Xray 版本
if [ -z "$VERSION_XRAY" ]; then
  log_info "Fetching latest Xray-core version from GitHub API..."
  _latest=$(fetch_latest_tag "XTLS/Xray-core")
  if [ -n "$_latest" ]; then
    VERSION_XRAY="$_latest"
    log_ok "  → Xray-core: ${VERSION_XRAY} (from GitHub API)"
  else
    VERSION_XRAY="v26.3.27"
    log_warn "  → Xray-core: ${VERSION_XRAY} (API failed, using default)"
  fi
else
  log_info "  → Xray-core: ${VERSION_XRAY} (user-specified)"
fi

# 解析 Hysteria2 版本
if [ -z "$VERSION_HY2" ]; then
  log_info "Fetching latest Hysteria2 version from GitHub API..."
  _latest=$(fetch_latest_tag "apernet/hysteria")
  if [ -n "$_latest" ]; then
    VERSION_HY2="$_latest"
    log_ok "  → Hysteria2: ${VERSION_HY2} (from GitHub API)"
  else
    VERSION_HY2="v2.9.3"
    log_warn "  → Hysteria2: ${VERSION_HY2} (API failed, using default)"
  fi
else
  log_info "  → Hysteria2: ${VERSION_HY2} (user-specified)"
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
echo "${_C_BOLD}================================================================${_C_RESET}"
echo "${_C_BOLD}  Node Installer${_C_RESET}"
echo "${_C_BOLD}  Xray: ${VERSION_XRAY}  |  Hysteria2: ${VERSION_HY2}${_C_RESET}"
echo "${_C_BOLD}  Domain: ${DOMAIN}  |  Port: ${PORT}${_C_RESET}"
echo "${_C_BOLD}  Start time: $(_timestamp)${_C_RESET}"
echo "${_C_BOLD}================================================================${_C_RESET}"
echo ""

# ──────────────────────────────────────────
# 步骤 1: 环境检查
# ──────────────────────────────────────────
log_step "Environment Check"

check_command curl     "Install curl first (e.g. apt install curl -y)"
check_command tar      "Install tar first (e.g. apt install tar -y)"
check_command unzip    "Install unzip first (e.g. apt install unzip -y)"
check_command openssl  "Install openssl first (e.g. apt install openssl -y)"
check_command node     "Install Node.js first (e.g. apt install nodejs -y)"

# 磁盘空间检查
if command -v df >/dev/null 2>&1; then
  _avail=$(df /home/container 2>/dev/null | awk 'NR==2 {print $4}' || df / 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$_avail" ] && [ "$_avail" -lt 512000 ] 2>/dev/null; then
    log_warn "Available disk space is below 500MB, installation may fail"
  else
    log_ok "Sufficient disk space"
  fi
fi

# ──────────────────────────────────────────
# 步骤 2: 下载应用文件
# ──────────────────────────────────────────
log_step "Download Application Files"

run_cmd "Download app2.js" \
  curl -sSL -o app2.js https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/node/app2.js

run_cmd "Rename app2.js to app.js" \
  mv app2.js app.js

run_cmd "Download package.json" \
  curl -sSL -o package.json https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/node/package.json

# ──────────────────────────────────────────
# 步骤 3: 安装 Xray 核心
# ──────────────────────────────────────────
log_step "Setup Xray Core"

# 创建目录
run_cmd "Create xray directory" \
  mkdir -p "$XRAY_DIR"

# 下载 Xray 压缩包
run_cmd "Download Xray-core (${VERSION_XRAY})" \
  curl -sSL --connect-timeout 10 --max-time 60 \
    -o "${XRAY_DIR}/Xray-linux-64.zip" \
    "https://github.com/XTLS/Xray-core/releases/download/${VERSION_XRAY}/Xray-linux-64.zip"

if [ ! -f "${XRAY_DIR}/Xray-linux-64.zip" ]; then
  log_error "File download failed: Xray-linux-64.zip"
  exit 1
fi

# 解压压缩包
run_cmd "Extract Xray archive" \
  unzip -o "${XRAY_DIR}/Xray-linux-64.zip" -d "$XRAY_DIR"

# 删除临时压缩包
run_cmd "Remove temporary archive" \
  rm -f "${XRAY_DIR}/Xray-linux-64.zip"

# 重命名 xray 二进制文件为 xy
if [ -f "${XRAY_DIR}/xray" ]; then
  run_cmd "Rename xray binary to xy" \
    mv "${XRAY_DIR}/xray" "${XRAY_DIR}/xy"
  run_cmd "Set executable permission on xy" \
    chmod +x "${XRAY_DIR}/xy"
  log_ok "xray binary extracted and renamed to xy"
else
  log_error "xray binary not found after extraction"
  exit 1
fi

# 下载 xray 配置文件
run_cmd "Download xray config.json" \
  curl -sSL -o "${XRAY_DIR}/config.json" \
    https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/node/xray-config.json

# 配置端口和 UUID
run_cmd "Configure PORT in xray config" \
  sed -i "s/10008/$PORT/g" "${XRAY_DIR}/config.json"

run_cmd "Configure UUID in xray config" \
  sed -i "s/YOUR_UUID/$UUID/g" "${XRAY_DIR}/config.json"

# 生成 x25519 密钥对
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
  log_error "Raw output from 'xy x25519': ${_keyPair}"
  exit 1
fi

log_ok "x25519 key pair generated"
log_info "Private key: ${_privateKey}"
log_info "Public key:  ${_publicKey}"

run_cmd "Configure private key in xray config" \
  sed -i "s/YOUR_PRIVATE_KEY/$_privateKey/g" "${XRAY_DIR}/config.json"

# 生成并配置短 ID
_shortId=$(openssl rand -hex 4)
log_info "Short ID: ${_shortId}"

run_cmd "Configure short ID in xray config" \
  sed -i "s/YOUR_SHORT_ID/$_shortId/g" "${XRAY_DIR}/config.json"

# 创建 VLESS 链接
_vlessUrl="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=$_publicKey&sid=$_shortId&spx=%2F&type=tcp&headerType=none#lunes-reality"

log_ok "VLESS Reality URL generated"

# 验证 xray 文件
log_info "Verifying xray files..."
for _f in xy config.json geoip.dat geosite.dat; do
  if [ -f "${XRAY_DIR}/${_f}" ]; then
    log_ok "   ${_f} — exists"
  else
    log_warn "   ${_f} — not found (optional file)"
  fi
done

# ──────────────────────────────────────────
# 步骤 4: 安装 Hysteria2
# ──────────────────────────────────────────
log_step "Setup Hysteria2"

# 创建目录
run_cmd "Create hysteria directory" \
  mkdir -p "$HY2_DIR"

# 下载 hysteria 二进制文件
run_cmd "Download Hysteria2 binary (${VERSION_HY2})" \
  curl -sSL --connect-timeout 10 --max-time 60 \
    -o "${HY2_DIR}/h2" \
    "https://github.com/apernet/hysteria/releases/download/app%2F${VERSION_HY2}/hysteria-linux-amd64"

if [ ! -f "${HY2_DIR}/h2" ]; then
  log_error "File download failed: hysteria binary"
  exit 1
fi

# 设置可执行权限
run_cmd "Set h2 executable permissions" \
  chmod +x "${HY2_DIR}/h2"

# 下载 hysteria 配置文件
run_cmd "Download hysteria config.yaml" \
  curl -sSL -o "${HY2_DIR}/config.yaml" \
    https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/node/hysteria-config.yaml

# 生成 SSL 证书
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

# 配置端口和密码
run_cmd "Configure PORT in hysteria config" \
  sed -i "s/10008/$PORT/g" "${HY2_DIR}/config.yaml"

run_cmd "Configure password in hysteria config" \
  sed -i "s/HY2_PASSWORD/$HY2_PASSWORD/g" "${HY2_DIR}/config.yaml"

# 创建 URI 编码后的 HY2 链接
log_info "Encoding HY2 password for connection URL..."
_encodedHy2Pwd=$(node -e "console.log(encodeURIComponent(process.argv[1]))" "$HY2_PASSWORD" 2>&1) || true

if [ -z "$_encodedHy2Pwd" ]; then
  log_error "Failed to encode HY2 password"
  exit 1
fi

_hy2Url="hysteria2://$_encodedHy2Pwd@$DOMAIN:$PORT?insecure=1#lunes-hy2"
log_ok "Hysteria2 URL generated"

# 验证 hysteria 文件
log_info "Verifying hysteria files..."
for _f in h2 config.yaml cert.pem key.pem; do
  if [ -f "${HY2_DIR}/${_f}" ]; then
    log_ok "   ${_f} — exists"
  else
    log_warn "   ${_f} — not found (optional file)"
  fi
done

# ──────────────────────────────────────────
# 步骤 5: 安装 Komari Agent
# ──────────────────────────────────────────
log_step "Setup Komari Agent"

if [ "$KOMARI_ENABLED" != "true" ]; then
  log_info "Komari agent is disabled (KOMARI_ENABLED != 'true'), skipping installation"
else
  # 创建安装目录
  run_cmd "Create komari agent installation directory" \
    mkdir -p "$KOMARI_INSTALL_DIR"

  # 下载二进制文件
  _komari_file="komari-agent-linux-amd64"
  if [ -z "$KOMARI_VERSION" ]; then
    _komari_dlpath="latest/download"
    _komari_vlabel="latest"
  else
    _komari_dlpath="download/${KOMARI_VERSION}"
    _komari_vlabel="${KOMARI_VERSION}"
  fi
  _komari_url="https://github.com/komari-monitor/komari-agent/releases/${_komari_dlpath}/${_komari_file}"

  log_info "Downloading komari-agent (${_komari_vlabel})..."
  run_cmd "Download komari agent binary" \
    curl -L -o "${KOMARI_INSTALL_DIR}/agent" "$_komari_url"

  if [ ! -f "${KOMARI_INSTALL_DIR}/agent" ]; then
    log_error "File download failed: ${KOMARI_INSTALL_DIR}/agent"
    exit 1
  fi
  _komari_size=$(wc -c < "${KOMARI_INSTALL_DIR}/agent" 2>/dev/null | tr -d ' ')
  log_ok "Komari agent binary downloaded (${_komari_size} bytes)"

  # 设置可执行权限
  run_cmd "Set komari agent executable permission" \
    chmod +x "${KOMARI_INSTALL_DIR}/agent"
  log_ok "Komari agent installed to ${KOMARI_INSTALL_DIR}/agent"

  # 验证安装
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
# 步骤 6: 保存连接信息
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
# 安装总结
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

echo "  Komari Agent:"
if [ "$KOMARI_ENABLED" = "true" ]; then
  echo "    • Status:          ${_C_OK}Installed${_C_RESET}"
  echo "    • Binary:          ${KOMARI_INSTALL_DIR}/agent"
  echo "    • Server:          ${KOMARI_SERVER}"
  echo "    • Startup:         ${_C_OK}Integrated into app.js${_C_RESET}"
else
  echo "    • Status:          Skipped (disabled)"
fi
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
echo "  3. Start the project:  node app.js  (komari-agent starts automatically)"
echo ""
echo "${_C_BOLD}================================================================${_C_RESET}"
