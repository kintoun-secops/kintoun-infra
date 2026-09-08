#!/bin/bash

set -Eeuo pipefail

umask 022

BOOTSTRAP_STATE_DIR="/var/lib/victim-bootstrap"
BOOTSTRAP_LOG="/var/log/victim-bootstrap.log"

install -d -m 755 "${BOOTSTRAP_STATE_DIR}"

if [[ -f "${BOOTSTRAP_STATE_DIR}/complete" ]]; then
    exit 0
fi

exec > >(tee -a "${BOOTSTRAP_LOG}") 2>&1

trap 'echo "[ERROR] Victim bootstrap failed at line ${LINENO}"' ERR
echo "[INFO] Victim bootstrap started at $(date --iso-8601=seconds)"

# amazon linux 패키지 업데이트 및 최신 버전 설치
dnf upgrade --refresh -y

# =======================================================
# Nginx 웹 서버 설치 및 설정
# =======================================================

dnf install -y nginx

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
    http://127.0.0.1/health

# SSM Agent 실행
systemctl enable --now amazon-ssm-agent
systemctl is-active --quiet amazon-ssm-agent

# 모든 설치와 서비스 검증이 끝났음을 기록
touch "${BOOTSTRAP_STATE_DIR}/complete"

echo "[INFO] Victim bootstrap completed at $(date --iso-8601=seconds)"