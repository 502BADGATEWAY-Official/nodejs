#!/usr/bin/env bash

# 设置各变量
WEB_USERNAME=${WEB_USERNAME:-'admin'}
WEB_PASSWORD=${WEB_PASSWORD:-'password'}

# 哪吒4个参数，ssl/tls 看是否需要，不需要的话可以留空，删除或在这4行最前面加 # 以注释
NEZHA_SERVER="$NEZHA_SERVER"
NEZHA_PORT="$NEZHA_PORT"
NEZHA_KEY="$NEZHA_KEY"
NEZHA_TLS="$NEZHA_TLS"

# Argo 固定域名隧道的两个参数,这个可以填 Json 内容或 Token 内容，不需要的话可以留空，删除或在这三行最前面加 # 以注释
ARGO_AUTH=''
ARGO_DOMAIN="$ARGO_DOMAIN"

# ttyd / filebrowser argo 域名
SSH_DOMAIN="$SSH_AUTH"
FTP_DOMAIN="$FTP_AUTH"

# 安装系统依赖
check_dependencies() {
  DEPS_CHECK=("wget" "unzip" "ss" "tar")
  DEPS_INSTALL=(" wget" " unzip" " iproute2" "tar")
  for ((i=0;i<${#DEPS_CHECK[@]};i++)); do [[ ! $(type -p ${DEPS_CHECK[i]}) ]] && DEPS+=${DEPS_INSTALL[i]}; done
  [ -n "$DEPS" ] && { apt-get update >/dev/null 2>&1; apt-get install -y $DEPS >/dev/null 2>&1; }
}

generate_alist() {
  cat > alist.sh << EOF
#!/usr/bin/env bash

# 下载最新版本 alist
download_alist() {
  if [ ! -e alist ]; then
    URL=\$(wget -qO- -4 "https://api.github.com/repos/alist-org/alist/releases/latest" | grep -o "https.*alist-linux-musl-amd64.tar.gz")
    URL=\${URL:-https://github.com/alist-org/alist/releases/download/v3.30.0/alist-linux-musl-amd64.tar.gz}
    wget -t 2 -T 10 -N \${URL}
    tar -zxvf alist-linux-musl-amd64.tar.gz && rm -f alist-linux-musl-amd64.tar.gz
  fi
}

# 运行客户端
run() {
  [[ ! \$PROCESS =~ alist && -e alist ]] && ./alist server 2>&1 &
}

download_alist
run
EOF
}

generate_aria2() {
  cat > aria2.sh << EOF
#!/usr/bin/env bash

# 下载最新版本 aria2
download_aria2() {
  if [ ! -e alist ]; then
    URL=\$(wget -qO- -4 "https://api.github.com/repos/P3TERX/Aria2-Pro-Core/releases/latest" | grep -o "https.*static-linux-amd64.tar.gz")
    URL=\${URL:-https://github.com/P3TERX/Aria2-Pro-Core/releases/download/1.36.0_2021.08.22/aria2-1.36.0-static-linux-amd64.tar.gz}
    wget -t 2 -T 10 -N \${URL}
    tar -zxvf aria2-1.36.0-static-linux-amd64.tar.gz -C /usr/bin && rm -f aria2-1.36.0-static-linux-amd64.tar.gz
  fi
}

# 配置文件处理
aria2_config() {
sh /tracker.sh /aria2.conf
EXEC=$(head /dev/urandom | md5sum | cut -c 1-8)
ln -sf /aria2.conf /tmp/${EXEC}.conf
ln -sf /usr/bin/aria2c /usr/bin/${EXEC}
touch /aria2.session
}

# 运行客户端
run() {
  exec ${EXEC} --conf-path="/tmp/${EXEC}.conf"
}

download_aria2
aria2_config
run
EOF
}

generate_argo() {
  cat > argo.sh << ABC
#!/usr/bin/env bash

ARGO_AUTH=${ARGO_AUTH}
ARGO_DOMAIN=${ARGO_DOMAIN}
SSH_DOMAIN=${SSH_DOMAIN}
FTP_DOMAIN=${FTP_DOMAIN}

# 下载并运行 Argo
check_file() {
  [ ! -e cloudflared ] && wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared
}

run() {
  if [[ -n "\${ARGO_AUTH}" && -n "\${ARGO_DOMAIN}" ]]; then
    if [[ "\$ARGO_AUTH" =~ TunnelSecret ]]; then
      echo "\$ARGO_AUTH" | sed 's@{@{"@g;s@[,:]@"\0"@g;s@}@"}@g' > tunnel.json
      cat > tunnel.yml << EOF
tunnel: \$(sed "s@.*TunnelID:\(.*\)}@\1@g" <<< "\$ARGO_AUTH")
credentials-file: $(pwd)/tunnel.json
protocol: http2

ingress:
  - hostname: \$ARGO_DOMAIN
    service: http://localhost:5244
EOF
      [ -n "\${SSH_DOMAIN}" ] && cat >> tunnel.yml << EOF
  - hostname: \$SSH_DOMAIN
    service: http://localhost:2222
EOF
      [ -n "\${FTP_DOMAIN}" ] && cat >> tunnel.yml << EOF
  - hostname: \$FTP_DOMAIN
    service: http://localhost:3333
EOF
      cat >> tunnel.yml << EOF
  - service: http_status:404
EOF
      nohup ./cloudflared tunnel --edge-ip-version auto --config tunnel.yml run 2>/dev/null 2>&1 &
    elif [[ \$ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
      nohup ./cloudflared tunnel --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH} 2>/dev/null 2>&1 &
    fi
  else
    nohup ./cloudflared tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url http://localhost:5244 2>/dev/null 2>&1 &
    sleep 5
    local LOCALHOST=\$(ss -nltp | grep '"cloudflared"' | awk '{print \$4}')
    ARGO_DOMAIN=\$(wget -qO- http://\$LOCALHOST/quicktunnel | cut -d\" -f4)
  fi
}

check_file
run
ABC
}

generate_nezha() {
  cat > nezha.sh << EOF
#!/usr/bin/env bash

# 哪吒的4个参数
NEZHA_SERVER="$NEZHA_SERVER"
NEZHA_PORT="$NEZHA_PORT"
NEZHA_KEY="$NEZHA_KEY"
NEZHA_TLS="$NEZHA_TLS"

# 检测是否已运行
check_run() {
  [[ \$(pgrep -laf nezha-agent) ]] && echo "哪吒客户端正在运行中!" && exit
}

# 三个变量不全则不安装哪吒客户端
check_variable() {
  [[ -z "\${NEZHA_SERVER}" || -z "\${NEZHA_PORT}" || -z "\${NEZHA_KEY}" ]] && exit
}

# 下载最新版本 Nezha Agent
download_agent() {
  if [ ! -e nezha-agent ]; then
    URL=\$(wget -qO- -4 "https://api.github.com/repos/nezhahq/agent/releases/latest" | grep -o "https.*linux_amd64.zip")
    URL=\${URL:-https://github.com/nezhahq/agent/releases/download/v0.15.6/nezha-agent_linux_amd64.zip}
    wget -t 2 -T 10 -N \${URL}
    unzip -qod ./ nezha-agent_linux_amd64.zip && rm -f nezha-agent_linux_amd64.zip
  fi
}

# 运行客户端
run() {
  TLS=\${NEZHA_TLS:+'--tls'}
  [[ ! \$PROCESS =~ nezha-agent && -e nezha-agent ]] && ./nezha-agent -s \${NEZHA_SERVER}:\${NEZHA_PORT} -p \${NEZHA_KEY} \${TLS} 2>&1 &
}

check_run
check_variable
download_agent
run
EOF
}

generate_ttyd() {
  cat > ttyd.sh << EOF
#!/usr/bin/env bash

# ttyd 三个参数
WEB_USERNAME=${WEB_USERNAME}
WEB_PASSWORD=${WEB_PASSWORD}
SSH_DOMAIN=${SSH_DOMAIN}

# 检测是否已运行
check_run() {
  [[ \$(pgrep -lafx ttyd) ]] && echo "ttyd 正在运行中" && exit
}

# ssh argo 域名不设置，则不安装 ttyd 服务端
check_variable() {
  [ -z "\${SSH_DOMAIN}" ] && exit
}

# 下载最新版本 ttyd
download_ttyd() {
  if [ ! -e ttyd ]; then
    URL=\$(wget -qO- "https://api.github.com/repos/tsl0922/ttyd/releases/latest" | grep -o "https.*x86_64")
    URL=\${URL:-https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64}
    wget -O ttyd \${URL}
    chmod +x ttyd
  fi
}

# 运行 ttyd 服务端
run() {
  [ -e ttyd ] && nohup ./ttyd -c \${WEB_USERNAME}:\${WEB_PASSWORD} -p 2222 bash >/dev/null 2>&1 &
}

check_run
check_variable
download_ttyd
run
EOF
}

generate_filebrowser () {
  cat > filebrowser.sh << EOF
#!/usr/bin/env bash

# filebrowser 三个参数
WEB_USERNAME=${WEB_USERNAME}
WEB_PASSWORD=${WEB_PASSWORD}
FTP_DOMAIN=${FTP_DOMAIN}

# 检测是否已运行
check_run() {
  [[ \$(pgrep -lafx filebrowser) ]] && echo "filebrowser 正在运行中" && exit
}

# 若 ftp argo 域名不设置，则不安装 filebrowser
check_variable() {
  [ -z "\${FTP_DOMAIN}" ] && exit
}

# 下载最新版本 filebrowser
download_filebrowser() {
  if [ ! -e filebrowser ]; then
    URL=\$(wget -qO- "https://api.github.com/repos/filebrowser/filebrowser/releases/latest" | grep -o "https.*linux-amd64.*gz")
    URL=\${URL:-https://github.com/filebrowser/filebrowser/releases/download/v2.23.0/linux-amd64-filebrowser.tar.gz}
    wget -O filebrowser.tar.gz \${URL}
    tar xzvf filebrowser.tar.gz filebrowser
    rm -f filebrowser.tar.gz
    chmod +x filebrowser
  fi
}

# 运行 filebrowser 服务端
run() {
  PASSWORD_HASH=\$(./filebrowser hash \$WEB_PASSWORD)
  [ -e filebrowser ] && nohup ./filebrowser --port 3333 --username \${WEB_USERNAME} --password "\${PASSWORD_HASH}" >/dev/null 2>&1 &
}

check_run
check_variable
download_filebrowser
run
EOF
}

generate_alist
generate_aria2
generate_argo
generate_nezha
generate_ttyd
generate_filebrowser

[ -e alist.sh ] && bash alist.sh
[ -e aria2.sh ] && bash aria2.sh
[ -e nezha.sh ] && bash nezha.sh
[ -e argo.sh ] && bash argo.sh
[ -e ttyd.sh ] && bash ttyd.sh
[ -e filebrowser.sh ] && bash filebrowser.sh
