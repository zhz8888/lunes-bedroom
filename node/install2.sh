#!/usr/bin/env sh

# ============================================================
# 节点安装器 — Xray + Hysteria2 + Komari Agent
# ============================================================

# ---------- 配置 ----------
DOMAIN="${DOMAIN:-node68.lunes.host}"
PORT="${PORT:-10008}"
UUID="${UUID:-2584b733-9095-4bec-a7d5-62b473540f7a}"
HY2_PASSWORD="${HY2_PASSWORD:-vevc.HY2.Password}"
VERSION_XRAY="${VERSION_XRAY:-v26.3.27}"
VERSION_HY2="${VERSION_HY2:-v2.9.3}"

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

run_cmd "Download app.js" \
  curl -sSL -o app.js https://raw.githubusercontent.com/zhz8888/lunes-bedroom/refs/heads/main/node/app.js

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
# 步骤 5: 保存连接信息
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
# Komari Agent 集成
# ============================================================
#
# 此部分添加 komari-agent 的安装与启动支持。
# 安装路径固定为 /home/container/komari，通过 app.js 启动。
# -e 参数用于链接 komari 服务器地址，-t 参数用于认证令牌。
# 仅支持 Linux amd64 架构。
# ============================================================

# ──────────────────────────────────────────
# 步骤 6: 安装 Komari Agent
# ──────────────────────────────────────────
log_step "Setup Komari Agent"

# ---------- 配置参数 ----------
KOMARI_ENABLED="${KOMARI_ENABLED:-true}"
KOMARI_INSTALL_DIR="/home/container/komari"
KOMARI_VERSION="${KOMARI_VERSION:-}"
KOMARI_SERVER="${KOMARI_SERVER:-http://localhost:9182}"
KOMARI_TOKEN="${KOMARI_TOKEN:-default}"

# 构建启动参数（如果用户未自定义 KOMARI_ARGS 则使用默认值）
if [ -z "$KOMARI_ARGS" ]; then
  KOMARI_ARGS="-e ${KOMARI_SERVER} -t ${KOMARI_TOKEN}"
fi

# ---------- 检查是否启用 ----------
if [ "$KOMARI_ENABLED" != "true" ]; then
  log_info "Komari agent is disabled (KOMARI_ENABLED != 'true'), skipping installation"
else
  log_info "Starting komari agent installation..."

  # ---------- 创建安装目录 ----------
  run_cmd "Create komari agent directory: ${KOMARI_INSTALL_DIR}" \
    mkdir -p "$KOMARI_INSTALL_DIR"

  # ---------- 构建下载地址（仅 Linux amd64）----------
  _file_name="komari-agent-linux-amd64"

  if [ -z "$KOMARI_VERSION" ]; then
    _download_path="latest/download"
    _version_label="latest"
  else
    _download_path="download/${KOMARI_VERSION}"
    _version_label="${KOMARI_VERSION}"
  fi

  _download_url="https://github.com/komari-monitor/komari-agent/releases/${_download_path}/${_file_name}"

  # ---------- 下载二进制文件 ----------
  log_info "Downloading ${_file_name} (${_version_label})..."
  log_info "URL: ${_download_url}"

  if curl -L -o "${KOMARI_INSTALL_DIR}/agent" "$_download_url" 2>&1; then
    _download_size=$(wc -c < "${KOMARI_INSTALL_DIR}/agent" 2>/dev/null | tr -d ' ')
    log_ok "Komari agent binary downloaded (${_download_size} bytes)"
  else
    log_error "Failed to download komari agent binary"
    log_error "URL: ${_download_url}"
    exit 1
  fi

  # ---------- 设置可执行权限 ----------
  run_cmd "Set komari agent executable permission" \
    chmod +x "${KOMARI_INSTALL_DIR}/agent"

  log_ok "Komari agent installed to ${KOMARI_INSTALL_DIR}/agent"

  # ---------- 将 komari-agent 添加到 app.js 启动 ----------
  log_info "Adding komari-agent to app.js startup..."

  # 将 KOMARI_ARGS 字符串拆分为 JS 数组元素
  _args_str=""
  for _arg in $KOMARI_ARGS; do
    if [ -z "$_args_str" ]; then
      _args_str="\"${_arg}\""
    else
      _args_str="${_args_str}, \"${_arg}\""
    fi
  done

  # 移除 apps 数组的闭合标记 ];，然后追加 agent 条目
  sed -i '/^];$/d' app.js
  sed -i '$s/$/,/' app.js
  {
    echo '  {'
    echo '    name: "komari-agent",'
    echo "    binaryPath: \"${KOMARI_INSTALL_DIR}/agent\","
    echo "    args: [${_args_str}]"
    echo '  }'
    echo '];'
  } >> app.js

  log_ok "Komari-agent added to app.js startup (server: ${KOMARI_SERVER})"

  # ---------- 验证安装 ----------
  log_info "Verifying komari agent installation..."
  if [ -f "${KOMARI_INSTALL_DIR}/agent" ]; then
    _size=$(wc -c < "${KOMARI_INSTALL_DIR}/agent" 2>/dev/null | tr -d ' ')
    log_ok "Komari agent binary — ${KOMARI_INSTALL_DIR}/agent (${_size} bytes)"
  else
    log_error "Komari agent binary not found after installation"
    exit 1
  fi

  log_ok "Komari agent installation completed successfully"
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
