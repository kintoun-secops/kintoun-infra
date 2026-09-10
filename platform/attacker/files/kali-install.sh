#!/bin/bash

set -Eeuo pipefail

exec > >(tee -a /var/log/kali-bootstrap.log \
    | logger -t kali-bootstrap -s 2>/dev/console) 2>&1

trap 'echo "[ERROR] 설치 실패: line=$LINENO"' ERR

echo "[INFO] Kali Linux GUI 및 SSM 설치 시작"

export DEBIAN_FRONTEND=noninteractive

# Kali apt 패키지 저장소 기본 주소를 https://로 변경
KALI_APT_SOURCE="/etc/apt/sources.list.d/kali.sources"

if [[ ! -f "${KALI_APT_SOURCE}" ]]; then
    echo "[ERROR] Kali APT 저장소 파일이 없습니다: ${KALI_APT_SOURCE}"
    exit 1
fi

# 현재 AMI가 어떤 저장소를 사용하는지 변경 전에 로그로 남김
echo "[INFO] 변경 전 Kali APT 저장소:"
grep -E '^(Types|URIs|Suites|Components|Signed-By):' \
    "${KALI_APT_SOURCE}" || true

# 기존 URI의 주소 무시, URIs 행 전체를 공식 HTTPS 주소로 교체
sed -i -E \
    's#^[[:space:]]*URIs:[[:space:]].*$#URIs: https://http.kali.org/kali/#' \
    "${KALI_APT_SOURCE}"

# 변경 결과를 bootstrap 로그에 출력
echo "[INFO] 변경 후 Kali APT 저장소:"
grep -E '^(Types|URIs|Suites|Components|Signed-By):' \
    "${KALI_APT_SOURCE}"

# 공식 HTTPS 주소가 정확하게 설정됐는지 검증
if ! grep -Eq \
    '^URIs:[[:space:]]+https://http\.kali\.org/kali/?[[:space:]]*$' \
    "${KALI_APT_SOURCE}"; then

    echo "[ERROR] Kali 공식 HTTPS 저장소 설정에 실패했습니다."
    exit 1
fi


apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    wget

install -d -m 0755 /tmp/amazon-ssm-agent

# Debian x86_64용 SSM Agent 다운로드
wget --https-only --secure-protocol=TLSv1_2 \
    "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb" \
    -O /tmp/amazon-ssm-agent/amazon-ssm-agent.deb

apt-get install -y /tmp/amazon-ssm-agent/amazon-ssm-agent.deb

systemctl enable --now amazon-ssm-agent

echo "[INFO] SSM Agent 설치 완료"

# Kali Xfce GUI와 브라우저 원격 접속에 필요한 프로그램 설치
apt-get install -y \
    kali-desktop-xfce \
    dbus-x11 \
    tigervnc-standalone-server \
    tigervnc-tools \
    novnc \
    websockify

# TigerVNC 설정 및 비밀번호 파일을 저장할 디렉터리 생성
install -d \
    -m 0700 \
    -o kali \
    -g kali \
    /home/kali/.config/tigervnc

# TigerVNC는 모니터가 없는 서버에 가상 화면을 만들어 줌
# 가상화면 :1은 내부적으로 TCP 5901 포트 사용
cat > /etc/systemd/system/kali-vnc.service <<'EOF'
[Unit]
Description=Kali TigerVNC virtual desktop
After=network-online.target
Wants=network-online.target

# VNC 암호 파일이 없으면 서비스 실행하지 않도록 설정
ConditionPathExists=/home/kali/.config/tigervnc/passwd

[Service]
Type=simple

# GUI와 VNC 서버를 root가 아닌 kali 사용자로 실행
User=kali
Group=kali
WorkingDirectory=/home/kali
Environment=HOME=/home/kali
Environment=USER=kali

# localhost yes: EC2 외부에 공개하지 않고 로컬 접속만 허용
# SecurityTypes VncAuth: 비밀번호 인증을 반드시 사용하도록 설정
# xstartup: 접속 시 Kali Xfce 데스크톱 실행

ExecStart=/usr/bin/tigervncserver :1 \
    -fg \
    -localhost yes \
    -SecurityTypes VncAuth \
    -PasswordFile /home/kali/.config/tigervnc/passwd \
    -geometry 1920x1080 \
    -depth 24 \
    -xstartup /usr/bin/startxfce4

# 서비스 종료 시 가상화면 :1(tcp 5901)도 종료
ExecStop=-/usr/bin/tigervncserver -kill :1

# 정상/비정상 종료 시 5초 후 다시 시작
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# noVNC 관리할 systemd 서비스 생성
# noVNC는 VNC 화면을 웹 브라우저가 이해할 수 있는 형태로 변환
cat > /etc/systemd/system/kali-novnc.service <<'EOF'
[Unit]
Description=Kali noVNC browser gateway

# TigerVNC 가상 화면이 시작된 뒤 noVNC 실행
After=network-online.target kali-vnc.service
Wants=network-online.target
Requires=kali-vnc.service

ConditionPathExists=/home/kali/.config/tigervnc/passwd

[Service]
Type=simple
User=kali
Group=kali
WorkingDirectory=/home/kali
Environment=HOME=/home/kali
Environment=USER=kali

# noVNC는 EC2의 127.0.0.1:6080 에서만 접속
ExecStart=/usr/share/novnc/utils/novnc_proxy \
    --listen 127.0.0.1:6080 \
    --vnc 127.0.0.1:5901

# 정상/비정상 종료 시 5초 후 다시 시작
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 새로 만든 서비스 설정을 systemd에 반영
systemctl daemon-reload

systemctl enable kali-vnc.service
systemctl enable kali-novnc.service

rm -f /tmp/amazon-ssm-agent/amazon-ssm-agent.deb

echo "[INFO] SSM + noVNC 패키지 설치 완료"

echo "[INFO] Kali 한글 설치 및 Timezone 설정"

timedatectl set-timezone Asia/Seoul

apt install -y fonts-nanum
fc-cache -f

echo "[INFO] Kali 한글 설치 및 Timezone 설정 완료"

touch /var/lib/kali-bootstrap-complete

echo "[SUCCESS] 전체 설치 완료"