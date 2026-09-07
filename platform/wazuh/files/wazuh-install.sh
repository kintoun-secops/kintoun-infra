#!/bin/bash

# 명령어 실행 중 오류 발생하면 전체실패 처리 후 즉시 스크립트 종료
set -Eeuo pipefail

# 새로 생성되는 파일은 root 만 읽을 수 있게 제한
umask 077

# Wazuh 설치 상태와 로그를 저장할 경로 설정
BOOTSTRAP_STATE_DIR="/var/lib/wazuh-bootstrap"
BOOTSTRAP_LOG="/var/log/wazuh-bootstrap.log"
INSTALL_DIR="/opt/wazuh-install"

# Wazuh 공식 설치 스크립트 버전 경로
WAZUH_INSTALL_SERIES="4.14"

# 상태 파일을 보관할 디렉터리 생성
install -d -m 700 "${BOOTSTRAP_STATE_DIR}"

# 이미 설치 성공 기록 있으면 중복 설치 X
if [[ -f "${BOOTSTRAP_STATE_DIR}/complete" ]]; then
    exit 0
fi

# 설치 로그 파일 생성 root 만 읽기/쓰기 설정
install -m 600 /dev/null "${BOOTSTRAP_LOG}"

# 표준 출력과 오류 출력을 모두 로그 파일에 기록(관리자 비밀번호 노출 방지)
exec >>"${BOOTSTRAP_LOG}" 2>&1

# 스크립트 실행 중 오류 발생 시 실패한 줄 번호 로그에 기록
trap 'echo "[ERROR] Wazuh bootstrap failed at line ${LINENO}"' ERR
echo "[INFO] Wazuh bootstrap started at $(date --iso-8601=seconds)"

# amazon linux 패키지 업데이트 및 최신 버전 설치
dnf upgrade --refresh -y

# Wazuh 설치에 필요한 도구 설치
dnf install -y tar gzip

# Amazon SSM Agent 실행설정
systemctl enable --now amazon-ssm-agent

# Wazuh 공식 설치 파일 보관할 디렉터리 생성
install -d -m 700 "${INSTALL_DIR}"

# 설치 디렉 이동
cd "${INSTALL_DIR}"

# 공식 사이트에서 Wazuh All-in-one 설치 스크립트 다운로드
curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --tlsv1.2 \
    --output wazuh-install.sh \
    "https://packages.wazuh.com/${WAZUH_INSTALL_SERIES}/wazuh-install.sh"

# 다운로드 파일이 존재하고 크기가 0보다 큰지 확인(정상 설치 확인)
test -s wazuh-install.sh

# 설치 스크립트 root만 rwx
chmod 700 wazuh-install.sh

# Wazuh All-in-one 설치 스크립트 실행
# -a 옵션 : 서버에 모든 구성요소 설치(Indexer, Server, Dashboard, filebeat)
bash ./wazuh-install.sh -a

# Wazuh 서비스가 실제로 실행 됐는지 확인
for service in \
    wazuh-indexer \
    wazuh-manager \
    wazuh-dashboard \
    filebeat
do
    if ! systemctl is-active --quiet "${service}"; then
        echo "[ERROR] ${service} is not running"
        systemctl status "${service}" --no-pager || true
        exit 1
    fi
done

# 모든 설치와 서비스 검증이 끝났음을 기록
touch "${BOOTSTRAP_STATE_DIR}/complete"

echo "[INFO] Wazuh install completed at $(date --iso-8601=seconds)"