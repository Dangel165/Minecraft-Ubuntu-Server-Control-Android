#!/bin/bash

# ============================================================
# 마인크래프트 서버 메모리 모니터링 및 알림 스크립트
# ============================================================

# 1. 메모리 확인 함수
# 시스템의 전체 메모리와 사용 중인 메모리를 계산하여 사용률(%)을 산출합니다.
check_memory() {
    # [기존 로직 유지] free 명령어를 통해 메가바이트 단위로 정보를 가져와 GB로 환산합니다.
    total_memory=$(free -m | awk '/Mem:/ {printf "%.1f", $2/1024}')
    used_memory=$(free -m | awk '/Mem:/ {printf "%.1f", $3/1024}')
    
    # 사용률을 퍼센트(%) 단위로 계산합니다.
    usage_percent=$(awk "BEGIN {printf \"%.1f\", ($used_memory/$total_memory)*100}")
    
    # 결과를 문자열로 반환합니다.
    echo "${used_memory}GB / ${total_memory}GB (사용률: ${usage_percent}%)"
}

# 2. 콘솔 메시지 전송 함수
# 실행 중인 마인크래프트 screen 세션을 찾아 게임 내 채팅으로 메시지를 보냅니다.
send_to_console() {
    message="$1"
    
    # [수정] sudo를 사용하여 root 권한으로 실행된 세션까지 모두 탐색합니다.
    # 키워드(.minecraft_server)가 포함된 세션 아이디만 추출합니다.
    SESSIONS=$(sudo screen -ls | grep ".minecraft_server" | awk '{print $1}')

    if [ -n "$SESSIONS" ]; then
        # 찾은 모든 세션에 대해 루프를 돌며 메시지를 전송합니다.
        for SESSION in $SESSIONS; do
            # [기존 기능 유지] stuff 명령어를 통해 screen 세션 내부에 타이핑 명령을 전달합니다.
            # printf '\r'는 엔터 키 입력을 의미합니다.
            sudo screen -S "${SESSION}" -X stuff "say ${message}$(printf '\r')"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 전송 완료 [세션: ${SESSION}]: ${message}"
        done
    else
        # 세션을 찾지 못했을 경우 출력할 경고 메시지입니다.
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: 실행 중인 minecraft_server 세션을 찾을 수 없습니다."
        echo "참고: 서버가 sudo로 실행되었다면 이 스크립트도 sudo 권한이 필요합니다."
    fi
}

# ============================================================
# 메인 실행부 
# ============================================================

# 메모리 사용량 정보를 변수에 담습니다.
memory_usage=$(check_memory)

# 계산된 정보를 마인크래프트 서버 콘솔로 전송합니다.
send_to_console "[시스템 알림] 현재 서버 메모리 사용량: ${memory_usage}"