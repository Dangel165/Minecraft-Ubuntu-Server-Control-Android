#!/bin/bash

# ============================================================
# 마인크래프트 AFK(잠수) 플레이어 보호 스크립트 
# ============================================================

# [설정 - 개인정보 보호를 위해 변수 처리]
# 깃허브에 올릴 때는 IP와 비밀번호를 가짜 정보로 수정하세요.
SERVER_ROOT="$HOME/minecraft"
LOG_FILE="$SERVER_ROOT/logs/latest.log"      # 서버 로그 파일 경로
STATE_FILE="$SERVER_ROOT/afk_state.txt"     # AFK 상태 저장용 임시 파일
LOG_OUT="$SERVER_ROOT/afk_protect.log"       # 이 스크립트의 활동 로그

RCON_ENABLED=true
RCON_HOST="127.0.0.1"                        # 서버 IP 
RCON_PORT=25575
RCON_PASSWORD="your_password_here"           # RCON 비밀번호 

SCREEN_KEYWORD="minecraft_server"            # screen 세션 이름 키워드

# 상태 저장 파일이 없으면 생성합니다.
touch "$STATE_FILE"

# ============================================================
# 1. Screen 세션 탐색 함수 
# ============================================================
get_sessions() {
    sudo screen -ls | grep "\.${SCREEN_KEYWORD}" | awk '{print $1}'
}

# 초기 구동 시 세션 확인
CHECK_SESSIONS=$(get_sessions)
if [[ -z "$CHECK_SESSIONS" ]]; then
    echo "[$(date)] [WARN] 세션을 찾을 수 없습니다. 키워드 확인 필요: $SCREEN_KEYWORD" | tee -a "$LOG_OUT"
else
    echo "[$(date)] [INFO] 감지된 세션: $CHECK_SESSIONS" | tee -a "$LOG_OUT"
fi

echo "[$(date)] [INFO] AFK 보호 스크립트가 시작되었습니다." | tee -a "$LOG_OUT"

# ============================================================
# 2. 기능 함수 (명령어 전송 및 보호 적용/해제)
# ============================================================

# 서버 콘솔에 명령어를 전송하는 함수 (RCON 우선, 실패 시 Screen Stuff 방식 사용)
send_cmd() {
    local cmd="$1"
    local SUCCESS=false

    # RCON이 활성화된 경우 RCON으로 먼저 시도
    if [[ "$RCON_ENABLED" == true ]]; then
        if mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "$cmd" >/dev/null 2>&1; then
            SUCCESS=true
        fi
    fi

    # RCON 실패 시 또는 비활성 시 Screen 세션에 직접 전달
    if [[ "$SUCCESS" == false ]]; then
        local SESSIONS=$(get_sessions)
        if [[ -n "$SESSIONS" ]]; then
            for SESSION in $SESSIONS; do
                sudo screen -S "$SESSION" -p 0 -X stuff "$cmd$(printf '\r')"
            done
        fi
    fi
}

# AFK 보호 적용: 플레이어를 크리에이티브 모드로 변경
apply_protection() {
    local player="$1"
    if grep -q "^$player$" "$STATE_FILE"; then return; fi # 이미 보호 중이면 무시
    
    echo "$player" >> "$STATE_FILE"
    send_cmd "say [AFK Protect] $player 님이 잠수 상태입니다. 보호 모드(크리에이티브)로 전환합니다."
    send_cmd "gamemode creative $player"
    echo "[$(date)] AFK 보호 적용: $player" >> "$LOG_OUT"
}

# AFK 보호 해제: 플레이어를 서바이벌 모드로 변경
remove_protection() {
    local player="$1"
    if grep -q "^$player$" "$STATE_FILE"; then
        sed -i "/^$player$/d" "$STATE_FILE"
        send_cmd "say [AFK Protect] $player 님이 복귀했습니다. 서바이벌 모드로 전환합니다."
        send_cmd "gamemode survival $player"
        echo "[$(date)] AFK 보호 해제: $player" >> "$LOG_OUT"
    fi
}

# ============================================================
# 3. 메인 루프 (로그 실시간 모니터링)
# ============================================================
# 서버 로그를 실시간으로 읽어 특정 키워드(EssentialX 등의 AFK 메시지)를 감지합니다.
tail -Fn0 "$LOG_FILE" | while read -r line; do
    
    # [무한 루프 방지] 이 스크립트가 보낸 메시지는 무시합니다.
    if [[ "$line" == *"[AFK Protect]"* ]]; then
        continue
    fi
    
    # "is now AFK" 문구 감지 시 플레이어 이름 추출 및 보호 적용
    if [[ "$line" =~ "is now AFK" ]]; then
        player=$(echo "$line" | sed -n 's/.*: \(.*\) is now AFK.*/\1/p')
        [[ -z "$player" ]] && player=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="is" && $(i+1)=="now" && $(i+2)=="AFK") print $(i-1)}')
        
        # 이름이 비어있지 않고, 시스템 메시지 기호가 없는 경우 실행
        if [[ -n "$player" ]] && [[ "$player" != *"]"* ]]; then
            apply_protection "$player"
        fi
    fi

    # "is no longer AFK" 문구 감지 시 플레이어 이름 추출 및 보호 해제
    if [[ "$line" =~ "is no longer AFK" ]]; then
        player=$(echo "$line" | sed -n 's/.*: \(.*\) is no longer AFK.*/\1/p')
        [[ -z "$player" ]] && player=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="is" && $(i+1)=="no" && $(i+2)=="longer" && $(i+3)=="AFK") print $(i-1)}')
        
        if [[ -n "$player" ]] && [[ "$player" != *"]"* ]]; then
            remove_protection "$player"
        fi
    fi
done