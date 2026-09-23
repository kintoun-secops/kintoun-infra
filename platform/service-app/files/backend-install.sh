#!/bin/bash

# 명령어 실행 중 오류 발생하면 전체실패 처리 후 즉시 스크립트 종료
set -Eeuo pipefail

# 새로 생성되는 파일은 root 만 읽을 수 있게 제한
umask 077

BOOTSTRAP_STATE_DIR="/var/lib/service-bootstrap"
BOOTSTRAP_LOG="/var/log/service-bootstrap.log"
APP_ROOT="/opt/app"

install -d -m 700 "$${BOOTSTRAP_STATE_DIR}"

if [[ -f "$${BOOTSTRAP_STATE_DIR}/complete" ]]; then
    exit 0
fi

install -m 600 /dev/null "$${BOOTSTRAP_LOG}"
exec >>"$${BOOTSTRAP_LOG}" 2>&1

dnf upgrade --refresh -y
dnf install -y python3.11 python3.11-pip

# 메모리 1GB 인스턴스에서 pip install 이 OOM 으로 죽지 않게 스왑을 만든다.
if [[ ! -f /swapfile ]]; then
    dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >>/etc/fstab
fi

if ! command -v aws >/dev/null 2>&1; then
    dnf install -y awscli-2
fi

# 애플리케이션은 전용 계정으로 돌린다. 로그인 셸을 주지 않는다.
if ! id appuser >/dev/null 2>&1; then
    useradd --system --home-dir "$${APP_ROOT}" --shell /sbin/nologin appuser
fi

install -d -m 755 -o appuser -g appuser "$${APP_ROOT}"
install -d -m 755 -o appuser -g appuser "$${APP_ROOT}/releases"
install -d -m 755 /opt/deploy

# =======================================================
# 애플리케이션 환경 변수
# 비밀번호가 없다. 애플리케이션이 인스턴스 롤로 IAM 인증 토큰을 만들어 접속한다.
# =======================================================
cat >"$${APP_ROOT}/env" <<ENV
AWS_REGION=${region}
APP_PORT=${app_port}
APP_MODULE=app.main:app
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USER=${db_iam_user}
DB_SSLMODE=require
ENV

chmod 644 "$${APP_ROOT}/env"

# =======================================================
# 릴리스 내려받기 스크립트
# 릴리스마다 독립된 venv 를 만든다. 롤백이 심볼릭 링크 교체로 끝난다.
# =======================================================
cat >/opt/deploy/pull.sh <<'SCRIPT'
#!/bin/bash
set -Eeuo pipefail

SHA="$${1:?사용법: pull.sh <커밋 SHA>}"
BUCKET="__ARTIFACT_BUCKET__"
REGION="__REGION__"
KEEP="__KEEP_RELEASES__"
APP_ROOT="/opt/app"
RELEASE="$${APP_ROOT}/releases/$${SHA}"

if [[ ! -d "$${RELEASE}" ]]; then
    install -d -m 755 -o appuser -g appuser "$${RELEASE}"
    aws s3 cp --region "$${REGION}" \
        "s3://$${BUCKET}/releases/backend/$${SHA}/app.tar.gz" /tmp/app.tar.gz
    tar -xzf /tmp/app.tar.gz -C "$${RELEASE}"
    rm -f /tmp/app.tar.gz

    python3.11 -m venv "$${RELEASE}/venv"
    "$${RELEASE}/venv/bin/pip" install --quiet --upgrade pip
    "$${RELEASE}/venv/bin/pip" install --quiet -r "$${RELEASE}/requirements.txt"
    chown -R appuser:appuser "$${RELEASE}"
fi

ln -sfn "$${RELEASE}" "$${APP_ROOT}/current"
systemctl restart service-api

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
# systemd 유닛
# =======================================================
cat >/etc/systemd/system/service-api.service <<'UNIT'
[Unit]
Description=FastAPI service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=appuser
Group=appuser
EnvironmentFile=/opt/app/env
WorkingDirectory=/opt/app/current
ExecStart=/opt/app/current/venv/bin/uvicorn $${APP_MODULE} --host 0.0.0.0 --port $${APP_PORT}
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/app

[Install]
WantedBy=multi-user.target
UNIT

chmod 644 /etc/systemd/system/service-api.service
systemctl daemon-reload
systemctl enable service-api

# =======================================================
# 현재 릴리스가 기록되어 있으면 받아서 띄운다.
# 없으면 유닛만 등록해 두고 첫 배포를 기다린다.
# =======================================================
CURRENT="$(aws ssm get-parameter --region "${region}" \
    --name "${release_parameter}" --query 'Parameter.Value' --output text 2>/dev/null || echo "bootstrap")"

if [[ "$${CURRENT}" != "bootstrap" ]]; then
    /opt/deploy/pull.sh "$${CURRENT}"
fi

touch "$${BOOTSTRAP_STATE_DIR}/complete"
