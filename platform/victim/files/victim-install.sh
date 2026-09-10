#!/bin/bash

set -Eeuo pipefail

umask 022

BOOTSTRAP_STATE_DIR="/var/lib/victim-bootstrap"
BOOTSTRAP_LOG="/var/log/victim-bootstrap.log"

install -d -m 755 "$${BOOTSTRAP_STATE_DIR}"

if [[ -f "$${BOOTSTRAP_STATE_DIR}/complete" ]]; then
    exit 0
fi

exec > >(tee -a "$${BOOTSTRAP_LOG}") 2>&1

trap 'echo "[ERROR] Victim bootstrap failed at line $${LINENO}"' ERR
echo "[INFO] Victim bootstrap started at $(date --iso-8601=seconds)"

# amazon linux 패키지 업데이트 및 최신 버전 설치
dnf upgrade --refresh -y

# =======================================================
# Nginx 웹 서버 설치 및 설정
# =======================================================

dnf install -y nginx

# Terraform이 포트를 채운 뒤, 아래 내용을 Nginx 설정 파일로 저장
cat > /etc/nginx/nginx.conf << 'NGINX'
user nginx;
worker_processes auto;

# 오류 로그와 실행 중인 PID 저장
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # ALB 뒤에서도 클라이언트 IP를 남기도록 X-Forwarded-For 헤더 값을 로그에 기록
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    # 위에서 정의한 main 형식으로 요청 로그 저장                
    access_log /var/log/nginx/access.log main;

    server {
        # Terraform에서 전달 받은 포트로 IPv4 IPv6 요청을 받아 헬스체크 처리
        listen ${victim_app_port} default_server;
        listen [::]:${victim_app_port} default_server;
        server_name _;

        # 기존 스크립트가 생성하는 index.html과 health 파일의 위치
        root /usr/share/nginx/html;
        index index.html;

        location / {
            # 요청 경로에 해당하는 파일을 제공하고 없으면 404 반환
            try_files $uri $uri/ =404;
        }
    }
}
NGINX

# Nginx가 웹 파일을 제공할 기본 디렉터리를 확인 및 생성
install -d -m 755 /usr/share/nginx/html

# 기본 페이지 생성
cat > /usr/share/nginx/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kintoun Project</title>
</head>
<body>
    <h1>Kintoun Project</h1>
</body>
</html>
EOF

# root만 수정할 수 있도록 권한 설정(read는 all)
chmod 644 /usr/share/nginx/html/index.html

# =======================================================
# ALB Health Check 경로 생성
# =======================================================

# ALB가 Get /health 요청을 보냈을 때 HTTP 200 응답을 받을 수 있도록 정적 파일 생성
printf '%s\n' 'healthy' > /usr/share/nginx/html/health

chmod 644 /usr/share/nginx/html/health

# Nginx 설정 문법 오류 확인
nginx -t

systemctl enable --now nginx
systemctl is-active --quiet nginx

# 로컬에서 /health 요청을 보내 HTTP 오류가 있는지 확인
curl \
    --fail \
    --silent \
    --show-error \
    --max-time 10 \
    http://127.0.0.1:${victim_app_port}/health

# SSM Agent 실행
systemctl enable --now amazon-ssm-agent
systemctl is-active --quiet amazon-ssm-agent

# 모든 설치와 서비스 검증이 끝났음을 기록
touch "$${BOOTSTRAP_STATE_DIR}/complete"

echo "[INFO] Victim bootstrap completed at $(date --iso-8601=seconds)"