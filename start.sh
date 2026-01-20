#!/bin/bash

# =================================================================
# 서버 설정 
# =================================================================
# 1. 서버 디렉토리 설정 
SERVER_DIR="${MINECRAFT_PATH:-""}" 

if [ -z "$SERVER_DIR" ]; then
    echo "Error: SERVER_DIR is not set. Please set MINECRAFT_PATH or edit the script."
    exit 1
fi

cd "$SERVER_DIR" || { echo "Error: Directory not found"; exit 1; }

# 스크린 세션 이름 및 로그 설정
SCREEN_NAME="minecraft_server"
LOG_FILE="$SCREEN_NAME.log"

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

# 3. 메모리 및 JVM 옵션 
MEM_ARGS="-Xms8G -Xmx10G -XX:+UseG1GC -XX:+AlwaysPreTouch"

# 절대 경로 대신 서버 디렉토리($SERVER_DIR) 기준 상대 경로로 변경하여 공용화
FORGE_UNIX_ARGS="$SERVER_DIR/libraries/net/minecraftforge/forge/1.20.1-47.4.3/unix_args.txt"
NEO_UNIX_ARGS="$SERVER_DIR/libraries/net/neoforged/neoforge/1.20.1/unix_args.txt"

if [ -f "$FORGE_UNIX_ARGS" ]; then
    LAUNCH_ARGS="@$FORGE_UNIX_ARGS"
    LOADER_TYPE="Forge 47.4.3"
elif [ -f "$NEO_UNIX_ARGS" ]; then
    LAUNCH_ARGS="@$NEO_UNIX_ARGS"
    LOADER_TYPE="NeoForge"
elif [ -f "fabric-server-launch.jar" ]; then
    LAUNCH_ARGS="-jar fabric-server-launch.jar"
    LOADER_TYPE="Fabric"
else
    JAR_FILE=$(ls *.jar | grep -E "forge|neoforge|fabric|server" | head -n 1)
    LAUNCH_ARGS="-jar $JAR_FILE"
    LOADER_TYPE="Generic JAR ($JAR_FILE)"
fi
# -----------------------------------------------------------------------

# 4. 실행 
echo "Starting $LOADER_TYPE server with high CPU priority (nice -10)..."
sudo screen -L -Logfile "$LOG_FILE" -dmS "$SCREEN_NAME" nice -n -10 java $MEM_ARGS $LAUNCH_ARGS nogui

# 5. 확인 절차
sleep 2
if sudo screen -list | grep -q "\.$SCREEN_NAME"; then
    echo "SUCCESS: Minecraft $LOADER_TYPE server started."
    echo "Memory: $MEM_ARGS | Screen: $SCREEN_NAME"
    sudo chmod 666 "$LOG_FILE"
else
    echo "FAILURE: Server failed to start. Check java arguments."
    exit 1
fi
