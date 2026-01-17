#!/bin/bash

# ============================================================
# 마인크래프트 서버 실행 스크립트 
# ============================================================

# 새로운 버전으로 업데이트 시 이 숫자들만 변경하면 됩니다.
MC_VER="1.20.1"
FORGE_VER="47.4.0"

#  개인정보 보호를 위해 $HOME 변수 활용
SERVER_DIR="$HOME/minecraft"
SCREEN_NAME="minecraft_server"
LOG_FILE="$SCREEN_NAME.log"

# 1. 서버 디렉토리로 이동 
cd "$SERVER_DIR" || { echo "Error: Directory not found"; exit 1; }

# [최적화] 서버 시작 전 이전 로그 백업 
if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
fi
echo "--- Server starting at $(date) ---" > "$LOG_FILE"

# 2. 기존 스크린 세션 종료 
if sudo screen -list | grep -q "\.$SCREEN_NAME"; then
    echo "Existing session found. Restarting..."
    sudo screen -S "$SCREEN_NAME" -X quit
    sleep 2
fi

# 3. 메모리 및 Forge 사양 
MEM_ARGS="-Xms4G -Xmx12G -XX:+UseG1GC -XX:+AlwaysPreTouch"

# 아래 경로는 위에서 설정한 MC_VER, FORGE_VER 변수를 자동으로 대입합니다.
FORGE_ARGS="@libraries/net/minecraftforge/forge/${MC_VER}-${FORGE_VER}/unix_args.txt"

# 4. 실행 (nice -n -10 CPU 우선순위 유지)
echo "Starting server with high CPU priority (nice -10)..."
# $FORGE_ARGS 변수를 사용하여 설정한 버전의 포지를 실행합니다.
sudo screen -L -Logfile "$LOG_FILE" -dmS "$SCREEN_NAME" nice -n -10 java $MEM_ARGS $FORGE_ARGS nogui

# 5. 확인 절차 
sleep 2
if sudo screen -list | grep -q "\.$SCREEN_NAME"; then
    echo "SUCCESS: Minecraft ${MC_VER} Forge server started."
    echo "Memory: $MEM_ARGS | Screen: $SCREEN_NAME"
    # 소유권 보장 (기존 666 권한 유지)
    sudo chmod 666 "$LOG_FILE"
else
    echo "FAILURE: Server failed to start. Check java arguments for version ${MC_VER}."
    exit 1
fi
