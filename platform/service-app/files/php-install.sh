#!/bin/bash

# 명령어 실행 중 오류 발생하면 전체실패 처리 후 즉시 스크립트 종료
set -Eeuo pipefail

# Ubuntu 24.04 (noble) 기준. apt 비대화형.
export DEBIAN_FRONTEND=noninteractive

# 새로 생성되는 파일은 root 만 읽을 수 있게 제한
umask 077

BOOTSTRAP_STATE_DIR="/var/lib/service-bootstrap"
BOOTSTRAP_LOG="/var/log/service-bootstrap.log"
APP_ROOT="/opt/app"
PHP_VER="8.3"

install -d -m 700 "$${BOOTSTRAP_STATE_DIR}"

if [[ -f "$${BOOTSTRAP_STATE_DIR}/complete" ]]; then
    exit 0
fi

install -m 600 /dev/null "$${BOOTSTRAP_LOG}"
exec >>"$${BOOTSTRAP_LOG}" 2>&1

apt-get update -y
apt-get upgrade -y

# 메모리 1GB 인스턴스에서 설치가 OOM 으로 죽지 않게 스왑을 만든다.
if [[ ! -f /swapfile ]]; then
    dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >>/etc/fstab
fi

# AWS CLI v2 는 배포판 패키지 버전에 흔들리지 않게 공식 번들로 설치한다.
if ! command -v aws >/dev/null 2>&1; then
    apt-get install -y curl unzip
    TMP="$(mktemp -d)"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$${TMP}/awscliv2.zip"
    (cd "$${TMP}" && unzip -q awscliv2.zip && ./aws/install)
    rm -rf -- "$${TMP}"
fi

# nginx 가 요청을 받고 php-fpm 이 PHP 를 실행한다. php-fpm 풀은 표준대로 www-data 로 돈다.
# php-pgsql 은 PostgreSQL 접속(pdo_pgsql)용.
apt-get install -y nginx php-fpm php-pgsql

# 릴리스 파일 소유용 계정. 로그인 셸을 주지 않는다.
if ! id appuser >/dev/null 2>&1; then
    useradd --system --home-dir "$${APP_ROOT}" --shell /usr/sbin/nologin appuser
fi

install -d -m 755 -o appuser -g appuser "$${APP_ROOT}"
install -d -m 755 -o appuser -g appuser "$${APP_ROOT}/releases"
install -d -m 755 /opt/deploy

# =======================================================
# 애플리케이션 환경 변수 (비밀 아님)
# DB_PASSWORD 는 여기 없다. 배포가 릴리스 .env 에서 읽어 secret.env 에 넣는다.
# =======================================================
cat >"$${APP_ROOT}/env" <<ENV
AWS_REGION=${region}
APP_PORT=${app_port}
ENV

chmod 644 "$${APP_ROOT}/env"
: >"$${APP_ROOT}/secret.env"
chmod 600 "$${APP_ROOT}/secret.env"

# =======================================================
# php-fpm 풀 — 표준 www-data 로 실행. open_basedir 로 웹 루트 제한, 액세스 로그 기록.
# =======================================================
cat >"/etc/php/$${PHP_VER}/fpm/pool.d/www.conf" <<'FPM'
[www]
user = www-data
group = www-data
listen = /run/php/app.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
; 워커가 systemd 로 받은 환경변수(DB_*)를 그대로 물려받게 둔다.
clear_env = no
catch_workers_output = yes
access.log = /var/log/php-fpm/app.access.log
access.format = "%R - %t \"%m %r\" %s %f"
php_admin_value[open_basedir] = /opt/app/current/src:/tmp
php_admin_value[session.save_path] = /tmp
php_admin_value[upload_tmp_dir] = /tmp
php_admin_flag[allow_url_include] = off
php_admin_flag[allow_url_fopen] = off
FPM

install -d -m 755 /var/log/php-fpm

# php-fpm 이 /opt/app/env 와 secret.env 의 DB 접속 정보를 환경변수로 받게 한다.
install -d -m 755 "/etc/systemd/system/php$${PHP_VER}-fpm.service.d"
cat >"/etc/systemd/system/php$${PHP_VER}-fpm.service.d/env.conf" <<'DROPIN'
[Service]
EnvironmentFile=-/opt/app/env
EnvironmentFile=-/opt/app/secret.env
DROPIN

# =======================================================
# nginx — ${app_port} 에서 받아 .php 는 php-fpm 으로, 나머지는 정적 제공
# real_ip 로 ALB 뒤 실제 클라이언트 IP 를 로그에 남긴다.
# =======================================================
cat >/etc/nginx/conf.d/app.conf <<NGINX
server {
    listen ${app_port};
    server_name _;
    root /opt/app/current/src;
    index index.php;
    client_max_body_size 10m;

    set_real_ip_from 10.60.0.0/16;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/app.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
NGINX

# =======================================================
# 릴리스 내려받기 스크립트
# 설치는 릴리스의 install.sh 가 appuser 로 한다. 롤백이 심볼릭 링크 교체로 끝난다.
# =======================================================
cat >/opt/deploy/pull.sh <<'SCRIPT'
#!/bin/bash
set -Eeuo pipefail

SHA="$${1:?사용법: pull.sh <커밋 SHA>}"
BUCKET="__ARTIFACT_BUCKET__"
REGION="__REGION__"
KEEP="__KEEP_RELEASES__"
PHP_VER="8.3"
APP_ROOT="/opt/app"
RELEASE="$${APP_ROOT}/releases/$${SHA}"

# 설치가 끝난 릴리스에만 표시가 남는다. 중간에 실패한 릴리스는 지우고 다시 받는다.
if [[ ! -f "$${RELEASE}/.installed" ]]; then
    rm -rf -- "$${RELEASE}"
    install -d -m 755 -o appuser -g appuser "$${RELEASE}"
    aws s3 cp --region "$${REGION}" \
        "s3://$${BUCKET}/releases/${app_role}/$${SHA}/app.tar.gz" /tmp/app.tar.gz
    tar -xzf /tmp/app.tar.gz -C "$${RELEASE}" --no-same-owner
    rm -f /tmp/app.tar.gz
    chown -R appuser:appuser "$${RELEASE}"

    # 업로드 디렉터리는 php-fpm(www-data)이 써야 하므로 소유를 넘긴다.
    install -d -m 775 -o www-data -g www-data "$${RELEASE}/src/uploads"

    if [[ -f "$${RELEASE}/install.sh" ]]; then
        (cd "$${RELEASE}" && runuser -u appuser -- env HOME="$${APP_ROOT}" bash ./install.sh)
    fi
    touch "$${RELEASE}/.installed"
fi

# DB_PASSWORD 를 릴리스 .env 에서 읽어 php-fpm 이 쓸 환경파일로 옮긴다 (systemd 호환 평문).
if [[ -f "$${RELEASE}/.env" ]]; then
    set -a
    . "$${RELEASE}/.env"
    set +a
    printf 'DB_PASSWORD=%s\n' "$${DB_PASSWORD:-}" >"$${APP_ROOT}/secret.env"
    chmod 600 "$${APP_ROOT}/secret.env"
fi

ln -sfn "$${RELEASE}" "$${APP_ROOT}/current"

# 릴리스 교체 후 php-fpm 재시작(opcache 비우기), nginx reload.
systemctl restart "php$${PHP_VER}-fpm"
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
# 서비스 기동
# =======================================================
systemctl daemon-reload
systemctl enable --now "php$${PHP_VER}-fpm"
systemctl enable --now nginx

# =======================================================
# 현재 릴리스가 기록되어 있으면 받아서 띄운다.
# 없으면 nginx·php-fpm 만 올려두고 첫 배포를 기다린다.
# =======================================================
CURRENT="$(aws ssm get-parameter --region "${region}" \
    --name "${release_parameter}" --query 'Parameter.Value' --output text 2>/dev/null || echo "bootstrap")"

if [[ "$${CURRENT}" != "bootstrap" ]]; then
    /opt/deploy/pull.sh "$${CURRENT}"
fi

touch "$${BOOTSTRAP_STATE_DIR}/complete"
