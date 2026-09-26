#!/bin/bash

# 명령어 실행 중 오류 발생하면 전체실패 처리 후 즉시 스크립트 종료
set -Eeuo pipefail

# 새로 생성되는 파일은 root 만 읽을 수 있게 제한
umask 077

BOOTSTRAP_STATE_DIR="/var/lib/service-bootstrap"
BOOTSTRAP_LOG="/var/log/service-bootstrap.log"
APP_ROOT="/usr/share/nginx/app"

install -d -m 700 "$${BOOTSTRAP_STATE_DIR}"

if [[ -f "$${BOOTSTRAP_STATE_DIR}/complete" ]]; then
    exit 0
fi

install -m 600 /dev/null "$${BOOTSTRAP_LOG}"
exec >>"$${BOOTSTRAP_LOG}" 2>&1

dnf upgrade --refresh -y
dnf install -y nginx

# AL2023 이미지에 AWS CLI 가 없을 수 있다. 없을 때만 설치한다.
if ! command -v aws >/dev/null 2>&1; then
    dnf install -y awscli-2
fi

install -d -m 755 "$${APP_ROOT}/releases"
install -d -m 755 /opt/deploy

# =======================================================
# 릴리스 내려받기 스크립트
# SSM Run Command 가 커밋 SHA 를 인자로 넘겨 실행한다.
# =======================================================
cat >/opt/deploy/pull.sh <<'SCRIPT'
#!/bin/bash
set -Eeuo pipefail

SHA="$${1:?사용법: pull.sh <커밋 SHA>}"
BUCKET="__ARTIFACT_BUCKET__"
REGION="__REGION__"
KEEP="__KEEP_RELEASES__"
APP_ROOT="/usr/share/nginx/app"
RELEASE="$${APP_ROOT}/releases/$${SHA}"

if [[ ! -d "$${RELEASE}" ]]; then
    install -d -m 755 "$${RELEASE}"
    aws s3 cp --region "$${REGION}" \
        "s3://$${BUCKET}/releases/frontend/$${SHA}/site.tar.gz" /tmp/site.tar.gz
    tar -xzf /tmp/site.tar.gz -C "$${RELEASE}"
    rm -f /tmp/site.tar.gz
fi

ln -sfn "$${RELEASE}" "$${APP_ROOT}/current"
nginx -t
systemctl reload nginx

# 오래된 릴리스 정리. 루트 볼륨이 작아 계속 쌓아둘 수 없다.
CURRENT_PATH="$(readlink -f "$${APP_ROOT}/current")"
ls -1dt "$${APP_ROOT}/releases"/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
    if [[ "$(readlink -f "$${old}")" != "$${CURRENT_PATH}" ]]; then
        rm -rf -- "$${old}"
    fi
done
SCRIPT

sed -i "s|__ARTIFACT_BUCKET__|${artifact_bucket}|; s|__REGION__|${region}|; s|__KEEP_RELEASES__|${keep_releases}|" /opt/deploy/pull.sh
chmod 755 /opt/deploy/pull.sh

# =======================================================
# nginx 설정
# 정적 파일만 서빙한다. TLS 는 ALB 가 끝내고 /api/* 도 ALB 가 백엔드로 보낸다.
# =======================================================
cat >/etc/nginx/conf.d/service.conf <<'CONF'
server {
    listen __LISTEN_PORT__ default_server;
    server_name _;

    root __APP_ROOT__/current;
    index index.html;

    location __HEALTH_PATH__ {
        access_log off;
        return 200 "ok\n";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
CONF

sed -i \
    -e "s|__LISTEN_PORT__|${listen_port}|" \
    -e "s|__APP_ROOT__|$${APP_ROOT}|" \
    -e "s|__HEALTH_PATH__|${health_path}|" \
    /etc/nginx/conf.d/service.conf

# AL2023 기본 nginx.conf 에는 default_server 가 있는 server 블록이 들어 있다.
# 같은 포트에 default_server 가 둘이면 nginx 가 뜨지 않으므로 최소 설정으로 덮어쓴다.
cat >/etc/nginx/nginx.conf <<'NGINXCONF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log main;

    sendfile           on;
    tcp_nopush         on;
    keepalive_timeout  65;
    types_hash_max_size 4096;

    include /etc/nginx/conf.d/*.conf;
}
NGINXCONF

chmod 644 /etc/nginx/nginx.conf

# 릴리스가 아직 없어도 nginx 가 뜨고 헬스체크가 통과하도록 빈 릴리스를 가리켜 둔다.
install -d -m 755 "$${APP_ROOT}/releases/bootstrap"
echo "service bootstrap" >"$${APP_ROOT}/releases/bootstrap/index.html"
ln -sfn "$${APP_ROOT}/releases/bootstrap" "$${APP_ROOT}/current"

nginx -t
systemctl enable --now nginx

# =======================================================
# 현재 릴리스가 기록되어 있으면 받아서 적용한다.
# =======================================================
CURRENT="$(aws ssm get-parameter --region "${region}" \
    --name "${release_parameter}" --query 'Parameter.Value' --output text 2>/dev/null || echo "bootstrap")"

if [[ "$${CURRENT}" != "bootstrap" ]]; then
    /opt/deploy/pull.sh "$${CURRENT}"
fi

touch "$${BOOTSTRAP_STATE_DIR}/complete"
