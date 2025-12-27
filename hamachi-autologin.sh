#!/bin/bash

# ============================================================
# Hamachi 자동 로그인 및 설정 스크립트 
# ============================================================


HAMACHI_EMAIL="your_email@example.com"     
HAMACHI_NICKNAME="Your_Nickname"            
HAMACHI_PATH="/usr/bin/hamachi"

# ============================================================
# 메인 로직 시작 
# ============================================================

# 1. Hamachi 데몬 시작
# 시스템 서비스를 통해 하마치 엔진을 백그라운드에서 실행합니다.
echo "[$(date)] [INFO] Hamachi 데몬 서비스를 시작합니다..."
sudo systemctl start logmein-hamachi

# 2. 프로세스 준비 대기
# 데몬이 완전히 실행되어 명령을 받을 수 있을 때까지 5초간 대기합니다.
echo "[$(date)] [INFO] 서비스 안정화를 위해 5초간 대기 중..."
sleep 5

# 3. CLI 로그인
# 하마치 네트워크에 접속을 시도합니다.
echo "[$(date)] [INFO] Hamachi 로그인을 시도합니다..."
sudo $HAMACHI_PATH login

# 4. 계정 연결 (Attach)
# 지정된 이메일 계정에 현재 클라이언트를 귀속시킵니다.
echo "[$(date)] [INFO] 계정 연결 중: $HAMACHI_EMAIL"
sudo $HAMACHI_PATH attach "$HAMACHI_EMAIL"

# 5. 닉네임 설정
# 네트워크상에서 표시될 이름을 설정합니다. (데몬이 명령을 처리할 시간을 위해 2초 대기)
sleep 2
echo "[$(date)] [INFO] 닉네임을 설정합니다: $HAMACHI_NICKNAME"
sudo $HAMACHI_PATH set-nick "$HAMACHI_NICKNAME"

# 6. 상태 및 네트워크 목록 확인
# 로그인이 완료된 후 현재 연결된 네트워크와 상태를 화면에 출력합니다.
echo "[$(date)] [SUCCESS] 현재 Hamachi 네트워크 목록:"
sudo $HAMACHI_PATH list

echo "[$(date)] [INFO] 모든 작업이 완료되었습니다."