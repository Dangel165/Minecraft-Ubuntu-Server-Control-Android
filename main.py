# -*- coding: utf-8 -*-
import asyncio
import os
import psutil
import subprocess
import re
from fastapi import FastAPI, BackgroundTasks, HTTPException, Depends, Request
from pydantic import BaseModel

app = FastAPI()

# --- 설정 및 경로  ---
API_PASSWORD = ""  # 앱에서 사용할 API 인증 키 (x-api-key)
SCREEN_NAME = "minecraft_server"  # 실행 중인 리눅스 screen 세션 이름
BASE_DIR = ""      # 마인크래프트 서버 루트 경로 
SCRIPTS_DIR = f"{BASE_DIR}/scripts" # 실행 스크립트들이 위치한 디렉토리
LOG_FILE = f"{BASE_DIR}/{SCREEN_NAME}.log" # 마인크래프트 실행 로그 파일 경로

# 실행에 필요한 쉘 스크립트 경로들
START_SCRIPT = f"{SCRIPTS_DIR}/start.sh"
BACKUP_STOP_SCRIPT = f"{SCRIPTS_DIR}/backup_and_shutdown.sh"
BACKUP_ONLY_SCRIPT = f"{SCRIPTS_DIR}/backup_world.sh"

# 로그 최적화 및 캐싱을 위한 전역 변수
last_processed_log_line = ""
last_cached_chat_log = "" 

# --- 데이터 모델 정의 (Pydantic) ---
class CommandModel(BaseModel):
    command: str

class PlayerActionModel(BaseModel):
    player_name: str

# --- 유틸리티 및 보안 함수 ---

# 헤더의 x-api-key를 검증하는 의존성 주입 함수
async def verify_token(request: Request):
    token = request.headers.get("x-api-key")
    if token != API_PASSWORD:
        raise HTTPException(status_code=403, detail="Forbidden")
    return token

# 리눅스 Screen 세션에 명령어를 전달하는 함수
async def send_screen_cmd_async(cmd: str):
    try:
        process = await asyncio.create_subprocess_exec(
            'sudo', '/usr/bin/screen', '-S', SCREEN_NAME, '-p', '0', '-X', 'stuff', f"{cmd}\n"
        )
        await process.wait()
    except Exception as e:
        print(f"Screen Command Error: {e}")

# 외부 쉘 스크립트를 비동기로 실행하는 함수 (시스템 부하 방지용 nice 적용)
async def run_script_async(path):
    if os.path.exists(path):
        try:
            # ionice -c 3(유휴 상태) 및 nice -n 19(가장 낮은 우선순위)로 시스템 프리징 방지
            subprocess.Popen(
                ['sudo', '/usr/bin/ionice', '-c', '3', '/usr/bin/nice', '-n', '19', '/usr/bin/bash', path],
                cwd=os.path.dirname(path),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=os.setpgrp
            )
        except Exception as e:
            print(f"Script Run Error: {e}")

# --- API 엔드포인트 ---

# 서버 온라인 여부 확인 (Screen 세션 리스트 확인)
@app.get("/status", dependencies=[Depends(verify_token)])
async def get_status():
    try:
        process = await asyncio.create_subprocess_exec(
            'sudo', '/usr/bin/screen', '-ls', SCREEN_NAME, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        stdout, _ = await process.communicate()
        return {"online": f".{SCREEN_NAME}" in stdout.decode()}
    except:
        return {"online": False}

# 호스트 시스템 자원 사용량 조회
@app.get("/system/resources", dependencies=[Depends(verify_token)])
async def get_resources():
    try:
        vm = psutil.virtual_memory()
        return {
            "cpu": psutil.cpu_percent(interval=None),
            "ram": vm.percent,
            "disk": psutil.disk_usage('/').percent,
            "ram_gb": f"{round(vm.used / 1073741824, 1)}/{round(vm.total / 1073741824, 1)}GB",
            "tps": 20.0, # 마인크래프트 내부 TPS (기본값)
            "mspt": 0.0  # 마인크래프트 내부 MSPT (기본값)
        }
    except:
        return {"cpu": 0, "ram": 0, "disk": 0, "ram_gb": "0/0GB", "tps": 0.0, "mspt": 0.0}

# 현재 접속 중인 플레이어 목록 및 데이터(위치, 아이템) 파싱
@app.get("/players", dependencies=[Depends(verify_token)])
async def get_players(refresh: bool = False):
    try:
        if refresh:
            # 서버에 최신 데이터를 로그로 남기도록 명령 전송
            await send_screen_cmd_async("list")
            await send_screen_cmd_async("execute as @a run data get entity @s Pos")
            await asyncio.sleep(0.8)

        if not os.path.exists(LOG_FILE):
            return {"players": []}
        
        # 로그 파일 마지막 300줄 읽기
        proc = await asyncio.create_subprocess_exec(
            'sudo', '/usr/bin/tail', '-n', '300', LOG_FILE, stdout=subprocess.PIPE
        )
        stdout, _ = await proc.communicate()
        lines = stdout.decode('utf-8', 'ignore').splitlines()
        
        player_list = []
        for line in reversed(lines):
            # 플레이어 목록 로그 패턴 매칭
            if "players online:" in line.lower() or "there are" in line.lower():
                parts = re.split(r"players online:|there are \d+/\d+ players online:", line, flags=re.IGNORECASE)
                if len(parts) > 1 and parts[1].strip():
                    names = [n.strip().split(' ')[0] for n in parts[1].strip().split(",")]
                    for name in names:
                        pos = "Unknown"
                        items = []
                        # 해당 플레이어의 위치 및 인벤토리 데이터 파싱
                        for l in reversed(lines):
                            if f"{name} has the following entity data: [" in l and "id:" not in l:
                                m_pos = re.search(r"data: \[([^\]]+)\]", l)
                                if m_pos: 
                                    pos = m_pos.group(1).replace('d', '').replace('f', '')
                                    break
                            if f"{name} has the following entity data: " in l and "id:" in l:
                                raw_items = re.findall(r'id:\s*"([^"]+)"', l)
                                items = [i.split(':')[-1].replace('_', ' ').title() for i in raw_items]
                        
                        player_list.append({
                            "name": name,
                            "pos": pos,
                            "position": pos,
                            "items": list(set(items))[:8] # 중복 제거 후 최대 8개
                        })
                    return {"players": player_list}
                break
    except Exception as e:
        print(f"Error parsing players: {e}")
    return {"players": []}

# 전체 콘솔 로그 및 채팅 로그 분리 조회
@app.get("/logs", dependencies=[Depends(verify_token)])
async def get_logs():
    global last_processed_log_line, last_cached_chat_log
    if not os.path.exists(LOG_FILE):
        return {"full_log": "No log file found.", "chat_log": ""}
    try:
        proc = await asyncio.create_subprocess_exec(
            'sudo', '/usr/bin/tail', '-n', '300', LOG_FILE, stdout=subprocess.PIPE
        )
        stdout, _ = await proc.communicate()
        full_log = stdout.decode('utf-8', 'ignore')
        lines = full_log.splitlines()
        if not lines:
            return {"full_log": "", "chat_log": ""}

        current_last_line = lines[-1]
        # 채팅 관련 키워드가 포함된 줄만 필터링
        chat_lines = [l for l in lines if any(x in l for x in ["<", ">", "[Server]", "joined the game", "left the game"])]
        current_chat_log = "\n".join(chat_lines)
        if not current_chat_log.strip():
            current_chat_log = "> No chat records..."

        # 이전과 로그가 동일하면 캐시된 데이터 반환 (부하 절감)
        if current_last_line == last_processed_log_line:
            return {"full_log": full_log, "chat_log": last_cached_chat_log if last_cached_chat_log else current_chat_log}
        
        last_processed_log_line = current_last_line
        last_cached_chat_log = current_chat_log 
        return {"full_log": full_log, "chat_log": current_chat_log}
    except Exception as e:
        return {"full_log": str(e), "chat_log": "Error loading chat."}

# 특정 플레이어의 상세 위치/인벤토리 조회
@app.get("/player/detail/{name}", dependencies=[Depends(verify_token)])
async def get_player_info(name: str):
    try:
        await send_screen_cmd_async(f"data get entity {name} Pos")
        await send_screen_cmd_async(f"data get entity {name} Inventory")
        await asyncio.sleep(0.8)
        proc = await asyncio.create_subprocess_exec(
            'sudo', '/usr/bin/tail', '-n', '300', LOG_FILE, stdout=subprocess.PIPE
        )
        stdout, _ = await proc.communicate()
        log_slice = stdout.decode('utf-8', 'ignore')
        pos_data, items = "Offline/No Data", []
        for line in reversed(log_slice.splitlines()):
            if f"{name} has the following entity data: [" in line and "id:" not in line:
                m = re.search(r"data: \[([^\]]+)\]", line)
                if m:
                    pos_data = m.group(1).replace('d', '').replace('f', '')
                    break
        for line in reversed(log_slice.splitlines()):
            if f"{name} has the following entity data: " in line and "id:" in line:
                raw_items = re.findall(r'id:\s*"([^"]+)"', line)
                items = [i.split(':')[-1].replace('_', ' ').title() for i in raw_items]
                break
        return {"name": name, "pos": pos_data, "position": pos_data, "items": items}
    except:
        return {"name": name, "pos": "Error", "position": "Error", "items": []}

# --- 서버 제어 명령(저기에 맞는 스크립트 파일이 있어야합니다) ---

# 서버 시작
@app.post("/start", dependencies=[Depends(verify_token)])
async def start_server(background_tasks: BackgroundTasks):
    background_tasks.add_task(run_script_async, START_SCRIPT)
    return {"message": "success"}

# 서버 중단 없이 월드 데이터만 백업
@app.post("/backup-only", dependencies=[Depends(verify_token)])
async def backup_only(background_tasks: BackgroundTasks):
    await send_screen_cmd_async("say [System] World backup starting...")
    await send_screen_cmd_async("save-off") # 백업 중 쓰기 방지
    await send_screen_cmd_async("save-all")
    await asyncio.sleep(2)
    background_tasks.add_task(run_script_async, BACKUP_ONLY_SCRIPT)
    await send_screen_cmd_async("save-on") # 백업 완료 후 다시 켜기 
    return {"status": "success"}

# 안전 종료 (백업 후 종료)
@app.post("/backup-stop", dependencies=[Depends(verify_token)])
async def backup_stop(background_tasks: BackgroundTasks):
    await send_screen_cmd_async("say [System] Backup and Shutdown sequence started.")
    background_tasks.add_task(run_script_async, BACKUP_STOP_SCRIPT)
    return {"status": "success"}

# 즉시 종료 (백업 없이 종료)
@app.post("/stop-only", dependencies=[Depends(verify_token)])
async def stop_only():
    await send_screen_cmd_async("say [System] Server stopping...")
    await send_screen_cmd_async("save-all")
    await asyncio.sleep(1)
    await send_screen_cmd_async("stop")
    return {"status": "success"}

# 시스템 종료 (본체 전원 끄기)
@app.post("/system-shutdown", dependencies=[Depends(verify_token)])
async def system_shutdown():
    os.system("sudo /sbin/shutdown now")
    return {"status": "success"}

# 플레이어 관리 (OP 권한 부여)
@app.post("/op", dependencies=[Depends(verify_token)])
async def op_player(data: PlayerActionModel):
    await send_screen_cmd_async(f"op {data.player_name}")
    return {"status": "success"}

# 플레이어 관리 (추방)
@app.post("/kick", dependencies=[Depends(verify_token)])
async def kick_player(data: PlayerActionModel):
    await send_screen_cmd_async(f"kick {data.player_name}")
    return {"status": "success"}

# 사용자 지정 명령어 전송
@app.post("/command", dependencies=[Depends(verify_token)])
async def send_custom_command(data: CommandModel):
    await send_screen_cmd_async(data.command)
    return {"status": "success"}

if __name__ == "__main__":
    import uvicorn
    # 외부 접속 허용 (0.0.0.0), 포트 8050

    uvicorn.run(app, host="0.0.0.0", port=8050, access_log=False)
