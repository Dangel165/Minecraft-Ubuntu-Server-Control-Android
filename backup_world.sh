#!/bin/bash

# ============================================================
# 마인크래프트 서버 백업 스크립트 
# ============================================================

# [설정] 서버 환경에 맞게 이 부분만 수정하세요.
USER_HOME=$(eval echo "~$USER")
WORLD_PATH="$USER_HOME/minecraft"      # 마인크래프트 서버 실행 경로
BACKUP_PATH="$WORLD_PATH/backups"       # 백업 파일이 저장될 경로
LOG_FILE="$BACKUP_PATH/backup_log.txt"  # 백업 활동 로그 파일
SCREEN_KEYWORD="minecraft_server"       # 실행 중인 screen 세션의 이름 키워드
DATE=$(date +'%Y-%m-%d_%H-%M-%S')       # 백업 파일명에 사용할 날짜 형식

# ==============================
# 1. 경로 확인 및 준비
# ==============================
# 서버 경로가 존재하는지 확인합니다.
if [[ ! -d "$WORLD_PATH" ]]; then
    echo "[$(date)] ERROR: 서버 경로를 찾을 수 없습니다: $WORLD_PATH" | tee -a "$LOG_FILE"
    exit 1
fi

# 백업 폴더가 없으면 생성합니다.
mkdir -p "$BACKUP_PATH"
echo "[$(date)] 백업 프로세스를 시작합니다..." | tee -a "$LOG_FILE"

# 실행 중인 마인크래프트 screen 세션을 찾습니다. (sudo 권한 필요)
SESSIONS=$(sudo screen -ls | grep ".$SCREEN_KEYWORD" | awk '{print $1}')

# ==============================
# 2. 서버 데이터 안전 모드 (World Save 중지)
# ==============================
# 세션이 확인되면 서버 내부에 명령어를 전달하여 데이터를 안전하게 저장합니다.
if [ -z "$SESSIONS" ]; then
    echo "[$(date)] WARNING: $SCREEN_KEYWORD 세션을 찾을 수 없습니다. 파일 백업만 진행합니다." | tee -a "$LOG_FILE"
else
    for SESSION in $SESSIONS; do
        # 서버에 공지 및 자동 저장 기능 일시 중지 (백업 시 데이터 오염 방지)
        sudo screen -S "$SESSION" -p 0 -X stuff "say [Server] 월드 백업을 시작합니다...$(printf '\r')"
        sudo screen -S "$SESSION" -p 0 -X stuff "save-off$(printf '\r')"
        sudo screen -S "$SESSION" -p 0 -X stuff "save-all$(printf '\r')"
    done
fi

# 데이터가 디스크에 완전히 기록될 때까지 5초간 대기합니다.
sleep 5

# ==============================
# 3. 대상 월드 파일 리스트 구성
# ==============================
# 기본 월드와 지옥(nether), 엔더(the_end) 월드가 있다면 목록에 추가합니다.
WORLD_FILES=("world")
[[ -d "$WORLD_PATH/world_nether" ]] && WORLD_FILES+=("world_nether")
[[ -d "$WORLD_PATH/world_the_end" ]] && WORLD_FILES+=("world_the_end")

BACKUP_FILE="$BACKUP_PATH/minecraft_all_worlds_$DATE.tar.gz"
echo "[$(date)] 다음 월드들을 압축합니다: ${WORLD_FILES[*]}" | tee -a "$LOG_FILE"

# ==============================
# 4. 압축 및 백업 실행
# ==============================
# -C 옵션으로 경로를 이동하여 압축 파일 내부에 불필요한 전체 경로가 포함되지 않게 합니다.
tar -czf "$BACKUP_FILE" -C "$WORLD_PATH" "${WORLD_FILES[@]}"
echo "[$(date)] 백업 파일 생성 완료: $BACKUP_FILE" | tee -a "$LOG_FILE"

# ==============================
# 5. 서버 데이터 저장 기능 재활성화
# ==============================
# 백업이 끝났으므로 다시 서버의 자동 저장 기능을 켭니다.
if [ -n "$SESSIONS" ]; then
    for SESSION in $SESSIONS; do
        sudo screen -S "$SESSION" -p 0 -X stuff "save-on$(printf '\r')"
        sudo screen -S "$SESSION" -p 0 -X stuff "say [Server] 월드 백업이 성공적으로 완료되었습니다!$(printf '\r')"
    done
fi

# ==============================
# 6. 오래된 백업 삭제 (보관 주기 관리)
# ==============================
# 2일(+2)이 지난 오래된 .tar.gz 백업 파일을 삭제하여 용량을 확보합니다.
find "$BACKUP_PATH" -type f -name "*.tar.gz" -mtime +2 -exec rm -f {} \;
echo "[$(date)] 2일 이상 된 오래된 백업 파일을 정리했습니다." | tee -a "$LOG_FILE"

echo "[$(date)] 모든 백업 공정이 정상적으로 종료되었습니다." | tee -a "$LOG_FILE"