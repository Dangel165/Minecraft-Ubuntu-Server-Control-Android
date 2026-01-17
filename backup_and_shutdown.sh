#!/bin/bash

# ============================================================
# 마인크래프트 서버 RCON 제어 및 백업 스크립트 (GitHub용)
# ============================================================

SERVER_DIR="$HOME/minecraft"          # 마인크래프트 서버가 위치한 경로
BACKUP_DIR="$SERVER_DIR/backups"      # 백업 파일이 저장될 경로
DATE=$(date +"%Y%m%d_%H%M%S")         # 파일명용 날짜 데이터
BACKUP_FILE="$BACKUP_DIR/minecraft_backup_$DATE.tar.gz"

# [RCON 및 세션 설정]
RCON_HOST="127.0.0.1"                 # 서버 IP (기존: 192.168.219.100)
RCON_PORT="25575"                     # RCON 포트
RCON_PASSWORD="your_password_here"    # RCON 비밀번호 (실제 사용 시 수정)
SCREEN_NAME="minecraft_server"        # 실행 중인 screen 세션 이름

# 백업 디렉토리가 없으면 생성합니다.
mkdir -p "$BACKUP_DIR"

# ============================================================
# 메인 로직 시작 (기존 로직 유지)
# ============================================================

# [보완] sudo를 사용하여 root 권한 세션까지 감지
if sudo screen -list | grep -q "\.$SCREEN_NAME"; then
    echo "[$(date)] [INFO] 서버가 작동 중입니다. 안전 종료 시퀀스를 시작합니다..."

    # 1. 유저 공지 (10초 대기)
    # 서버 내부 플레이어들에게 백업 및 종료 예고를 전달합니다.
    mcrcon -H $RCON_HOST -P $RCON_PORT -p $RCON_PASSWORD "say §c[System] 서버 백업 및 종료를 시작합니다!"
    mcrcon -H $RCON_HOST -P $RCON_PORT -p $RCON_PASSWORD "say §e[System] 10초 후 데이터 저장을 시작합니다."
    sleep 10

    # 2. 데이터 강제 저장
    # 현재 메모리에 있는 월드 데이터를 디스크에 물리적으로 저장합니다.
    echo "[$(date)] [INFO] 월드 데이터를 저장 중입니다..."
    mcrcon -H $RCON_HOST -P $RCON_PORT -p $RCON_PASSWORD "save-all"
    sleep 2

    # 3. 서버 종료 명령어 전송
    # 안전하게 서버를 종료하여 데이터 무결성을 확보합니다.
    echo "[$(date)] [INFO] 마인크래프트 서버를 종료합니다..."
    mcrcon -H $RCON_HOST -P $RCON_PORT -p $RCON_PASSWORD "stop"

    # 4. 서버가 완전히 꺼질 때까지 대기 (최대 60초)
    # screen 세션이 사라질 때까지 반복해서 확인합니다.
    echo "[$(date)] [INFO] 서버 종료 대기 중..."
    for i in {1..60}; do
        if ! sudo screen -list | grep -q "\.$SCREEN_NAME"; then
            echo "[$(date)] [SUCCESS] 서버가 안전하게 종료되었습니다."
            break
        fi
        sleep 1
    done

    # 5. 백업 실행 (전체 월드, 설정, 모드 포함)
    # world, world_nether, world_the_end, config, mods 폴더를 압축합니다.
    echo "[$(date)] [INFO] 압축 및 백업 시작 (전체 데이터 포함): $BACKUP_FILE"
    tar -czf "$BACKUP_FILE" -C "$SERVER_DIR" world world_nether world_the_end config mods

    # 백업 결과 확인
    if [ $? -eq 0 ]; then
        echo "[$(date)] [SUCCESS] 백업 완료: $BACKUP_FILE"
        
        # [기존 로직 유지] 2일이 지난 오래된 백업 파일 자동 삭제
        echo "[$(date)] [INFO] 2일 이상 된 오래된 백업 파일을 정리합니다..."
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +1 -delete
        echo "[$(date)] [INFO] 오래된 파일 정리 완료."
    else
        echo "[$(date)] [ERROR] 백업 도중 압축 오류가 발생했습니다!"
    fi

else
    # 서버 세션이 발견되지 않았을 경우
    echo "[$(date)] [WARN] 서버가 작동 중이지 않습니다. 백업 시퀀스를 중단합니다."
fi

echo "[$(date)] [INFO] 모든 작업이 종료되었습니다."
