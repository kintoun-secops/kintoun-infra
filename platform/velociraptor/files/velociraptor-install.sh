#!/bin/bash
set -Eeuo pipefail

# 서버 설정과 로그에는 운영 정보가 담길 수 있으므로 소유자만 읽게 합니다.
umask 077
LOG_FILE="/var/log/velociraptor-bootstrap.log"
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"

# 화면 출력과 오류 출력을 설치 로그 및 cloud-init 로그에 함께 남깁니다.
exec > >(tee -a "$LOG_FILE") 2>&1

# 각 설치 단계에 실행 시간을 표시합니다.
log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

# 실패한 단계와 종료 코드를 로그에 남기되 비밀번호는 출력하지 않습니다.
STAGE="초기화"
trap 'rc=$?; log "설치 실패: 단계=$STAGE, 종료 코드=$rc"; exit "$rc"' ERR

VERSION="0.77.2"
EXPECTED_SHA256="6c4c23c466d892788ff56ddcd3a31f844e4c0d797ade454c5e2625eb9e427077"
DOWNLOAD_URL="https://github.com/Velocidex/velociraptor/releases/download/v${VERSION}/velociraptor-v${VERSION}-linux-amd64"

log "Velociraptor ${VERSION} 설치 시작"

# 이 실행 파일은 x86_64용입니다.
test "$(uname -m)" = "x86_64"

STAGE="필요 패키지 설치"
log "$STAGE"
dnf install -y curl-minimal openssl

# 임시 디렉터리는 설정과 비밀키를 포함하므로 종료 시 삭제합니다.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

STAGE="Velociraptor 다운로드 및 검사"
log "$STAGE"
curl --fail --location --retry 3 \
  --output "$WORK_DIR/velociraptor" "$DOWNLOAD_URL"
echo "$EXPECTED_SHA256  $WORK_DIR/velociraptor" | sha256sum -c -
chmod 0755 "$WORK_DIR/velociraptor"

# velociraptor 서비스 계정이 검증된 실행 파일을 실행할 수 있게 합니다.
# 설정 파일과 RPM은 umask 077에 따라 계속 소유자만 읽을 수 있습니다.
chmod 0711 "$WORK_DIR"

if test -f /etc/velociraptor/server.config.yaml; then
  # 앞선 실행에서 RPM 설치까지 성공했으므로 기존 인증서를 재사용합니다.
  STAGE="기존 서버 설정 확인"
  log "기존 서버 설정 확인: 설정과 인증서를 재사용합니다."
  systemctl cat velociraptor_server.service >/dev/null
else
  STAGE="EC2 사설 IP 확인"
  log "$STAGE"

  # 에이전트가 접속할 고정 DNS
  SERVER_HOSTNAME="velo.internal.kintoun.work"

  # 에이전트는 사설 IP:8000으로, 관리 GUI는 로컬:8889로 접속합니다.
  MERGE_JSON="$(printf \
    '{"Frontend":{"hostname":"%s","bind_address":"0.0.0.0"},"Client":{"server_urls":["https://%s:8000/"]},"GUI":{"bind_address":"127.0.0.1"}}' \
    "$SERVER_HOSTNAME" "$SERVER_HOSTNAME")"

  STAGE="서버 설정 생성"
  log "$STAGE"
  "$WORK_DIR/velociraptor" config generate \
    --merge "$MERGE_JSON" > "$WORK_DIR/server.config.yaml"

  STAGE="서버 RPM 생성 및 설치"
  log "$STAGE"

  # --output에는 RPM 파일명이 아니라 출력 디렉터리를 지정합니다.
  "$WORK_DIR/velociraptor" rpm server \
    --config "$WORK_DIR/server.config.yaml" \
    --output "$WORK_DIR"

  # Velociraptor가 자동 생성한 RPM 파일을 찾아 설치합니다.
  RPM_FILE="$(find "$WORK_DIR" -maxdepth 1 -type f \
    -name 'velociraptor-server-*.rpm' -print -quit)"
  test -n "$RPM_FILE"
  test -f "$RPM_FILE"
  rpm -Uvh "$RPM_FILE"
fi

# 새 설치와 기존 부분 설치 모두에서 서비스를 실행 상태로 만듭니다.
systemctl enable --now velociraptor_server.service

STAGE="관리자 계정 생성"
log "$STAGE"

# 설치된 실행 파일의 경로를 추측하지 않고 검증된 다운로드 파일을 사용합니다.
if runuser -u velociraptor -- \
  "$WORK_DIR/velociraptor" \
  --config /etc/velociraptor/server.config.yaml \
  user show admin >/dev/null 2>&1; then
  log "관리자 계정이 이미 있어 비밀번호를 변경하지 않습니다."
else
  # 최초 비밀번호는 로그가 아닌 root 전용 파일에만 저장합니다.
  ADMIN_PASSWORD="$(openssl rand -hex 24)"
  printf 'username=admin\npassword=%s\n' "$ADMIN_PASSWORD" \
    > /root/velociraptor-initial-admin.txt
  chmod 0600 /root/velociraptor-initial-admin.txt

  # 서비스 계정으로 관리자 사용자를 추가합니다.
  runuser -u velociraptor -- \
    "$WORK_DIR/velociraptor" \
    --config /etc/velociraptor/server.config.yaml \
    user add --role administrator admin "$ADMIN_PASSWORD"
fi

STAGE="서비스 재시작 및 상태 확인"
log "$STAGE"
systemctl restart velociraptor_server.service
systemctl is-active --quiet velociraptor_server.service

log "설치 성공: Velociraptor 서버가 실행 중입니다."

STAGE="클라이언트 설정 파일 생성"
log "$STAGE"

# 서버 설정에서 에이전트용 설정을 추출합니다.
# DNS 접속 주소와 CA 인증서(서버를 신뢰하는 기준)가 포함됩니다.
# CA 비밀키는 포함 X
"$WORK_DIR/velociraptor" \
  --config /etc/velociraptor/server.config.yaml \
  config client > "$WORK_DIR/client.config.yaml"

# 빈 파일이면 실패 처리하고, 정상 파일은 root만 읽고 쓰도록 저장합니다.
test -s "$WORK_DIR/client.config.yaml"
install -o root -g root -m 0600 \
  "$WORK_DIR/client.config.yaml" \
  /root/velociraptor-client.config.yaml