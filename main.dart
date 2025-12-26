import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black, // 전체 배경 검은색
      cardColor: const Color(0xFF121212),   // 카드 디자인 배경색
    ),
    home: MCServerDashboard(),
  ));
}

class MCServerDashboard extends StatefulWidget {
  @override
  _MCServerDashboardState createState() => _MCServerDashboardState();
}

class _MCServerDashboardState extends State<MCServerDashboard> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver { 
  
  // 서버 연결 설정 (URL 및 API 인증 키) (사용하실거면 우분투나 리눅스 사용해야합니다)
  final String serverUrl = ""; 
  final String apiPassword = ""; 
  
  // 로컬 알림 플러그인 초기화
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // 서버 상태 및 데이터 변수
  List<dynamic> _players = [];        // 접속 중인 플레이어 목록
  String _fullLog = "";               // 전체 콘솔 로그
  String _chatLog = "";               // 채팅 로그
  bool _isOnline = false;             // 서버 온라인 여부
  bool? _lastOnlineStatus;            // 이전 온라인 상태 (상태 변경 감지용)
  Map _res = {"cpu": 0, "ram": 0, "disk": 0, "ram_gb": "0/0GB", "tps": 20.0, "mspt": 0.0}; // 리소스 수치 데이터
  
  // 로그 처리 및 이벤트 감지 변수
  String _lastProcessedLogLine = ""; 
  final Map<String, DateTime> _processedEvents = {};

  // 경고 알림 중복 전송 방지 플래그
  bool _hasRamWarningSent = false;
  bool _hasCpuWarningSent = false;
  bool _hasDiskWarningSent = false;
  bool _hasTpsWarningSent = false;
  
  // UI 컨트롤러
  late TabController _tabController;
  final TextEditingController _inputController = TextEditingController();    // 명령어/채팅 입력
  final TextEditingController _playerEditController = TextEditingController(); // 플레이어 조작 대상 선택
  final ScrollController _scroll1 = ScrollController(); // 콘솔 스크롤
  final ScrollController _scroll2 = ScrollController(); // 채팅 스크롤
  
  Timer? _timer;            // 데이터 갱신용 타이머
  bool _isRefreshing = false; // 새로고침 중복 방지

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 앱 생명주기 감지 추가
    _tabController = TabController(length: 3, vsync: this); 
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {}); // 탭 변경 시 UI 갱신
    });
    _initializeApp();  // 앱 초기 설정 (알림 등)
    _startSmartTimer(); // 5초 주기 갱신 타이머 시작
  }

  // 앱 생명주기 변화 감지 (백그라운드에서 복귀 시 즉시 새로고침)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isRefreshing = false; 
      _refresh(); 
      _startSmartTimer(); 
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel(); // 앱이 보이지 않으면 타이머 정지
    }
  }

  // 데이터 주기적 갱신 타이머
  void _startSmartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (!_isRefreshing) _refresh();
    });
  }

  // 로그 가독성을 위해 ANSI 색상 코드 제거
  String _cleanLog(String log) {
    if (log.isEmpty) return log;
    final ansiPattern = RegExp(r'\x1B\[[0-9;]*[a-zA-Z]');
    return log.replaceAll(ansiPattern, '');
  }

  // 초기 알림 설정 및 권한 요청
  Future<void> _initializeApp() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      final initSettings = InitializationSettings(
        android: androidSettings,
        linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
      );
      await _notifications.initialize(initSettings);

      if (Platform.isAndroid) {
        final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.requestNotificationsPermission();
        }
      }
      _refresh();
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  // 푸시 알림 전송 함수
  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'server_event_channel', '서버 이벤트 알림',
      importance: Importance.max, priority: Priority.high,
    );
    await _notifications.show(DateTime.now().millisecond, title, body, const NotificationDetails(android: androidDetails));
  }

  // 서버 자원 사용량 감시 및 경고 로직
  void _checkResourceWarnings() {
    // 1. RAM 경고 (90% 이상)
    if (_res['ram'] >= 90 && !_hasRamWarningSent) {
      _showNotification("🚨 서버 메모리 위험", "메모리 사용량이 ${_res['ram']}%에 도달했습니다!");
      _hasRamWarningSent = true;
    } else if (_res['ram'] < 80) {
      _hasRamWarningSent = false; 
    }

    // 2. CPU 경고 (90% 이상)
    if (_res['cpu'] >= 90 && !_hasCpuWarningSent) {
      _showNotification("🚨 서버 CPU 과부하", "CPU 사용량이 ${_res['cpu']}%로 매우 높습니다.");
      _hasCpuWarningSent = true;
    } else if (_res['cpu'] < 70) {
      _hasCpuWarningSent = false;
    }

    // 3. 디스크 경고 (95% 이상)
    if (_res['disk'] >= 95 && !_hasDiskWarningSent) {
      _showNotification("🚨 저장 공간 부족", "디스크 사용량이 ${_res['disk']}%입니다. 백업 공간을 확인하세요!");
      _hasDiskWarningSent = true;
    } else if (_res['disk'] < 90) {
      _hasDiskWarningSent = false;
    }

    // 4. TPS 경고 (15.0 미만 시 성능 하락 알림)
    if (_res['tps'] < 15.0 && !_hasTpsWarningSent && _isOnline) {
      _showNotification("🐌 서버 렉 발생", "TPS가 ${_res['tps']}로 하락했습니다. 성능을 점검하세요.");
      _hasTpsWarningSent = true;
    } else if (_res['tps'] >= 18.0) {
      _hasTpsWarningSent = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _tabController.dispose();
    _inputController.dispose();
    _playerEditController.dispose();
    _scroll1.dispose();
    _scroll2.dispose();
    super.dispose();
  }

  // API 요청 공통 헤더 (API KEY 포함)
  Map<String, String> get _headers => {
    "x-api-key": apiPassword, 
    "Content-Type": "application/json",
    "Accept": "application/json"
  };

  // 새 로그를 분석하여 플레이어 입/퇴장 이벤트 감지
  void _checkLogEvents(String newLog) {
    if (newLog.isEmpty) return;
    List<String> lines = newLog.trim().split('\n');
    if (lines.isEmpty) return;
    
    final now = DateTime.now();
    int checkCount = lines.length > 5 ? 5 : lines.length; // 마지막 5줄 위주로 검사

    for (int i = lines.length - checkCount; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty || line == _lastProcessedLogLine) continue;

      String? playerName;
      String? eventType;

      // 입장 로그 패턴 검사
      if (line.contains("joined the game")) {
        try {
          playerName = line.split("] ").last.split(" joined").first.trim();
          eventType = "JOIN";
        } catch(e) {}
      } 
      // 퇴장 로그 패턴 검사
      else if (line.contains("left the game")) {
        try {
          playerName = line.split("] ").last.split(" left").first.trim();
          eventType = "LEFT";
        } catch(e) {}
      }

      if (playerName != null && eventType != null) {
        String eventKey = "${playerName}_$eventType";
        // 동일 이벤트 중복 알림 방지 (60초 이내 중복 전송 차단)
        if (!_processedEvents.containsKey(eventKey) || 
            now.difference(_processedEvents[eventKey]!).inSeconds > 60) {
          
          _processedEvents[eventKey] = now; 
          _lastProcessedLogLine = line; 

          if (eventType == "JOIN") {
            _showNotification("👤 플레이어 접속", "${playerName}님이 서버에 입장했습니다!");
          } else {
            _showNotification("🏃 플레이어 퇴장", "${playerName}님이 서버를 떠났습니다.");
          }
        }
      }
    }
    // 오래된 이벤트 캐시 삭제 (메모리 관리)
    _processedEvents.removeWhere((key, time) => now.difference(time).inMinutes > 5);
  }

  // 서버 연결 실패 시 상태 처리
  void _handleServerOffline() {
    if (!mounted) return;
    setState(() {
      _isOnline = false;
      _players = [];
      if (!_fullLog.contains("서버 연결 대기 중")) {
        _fullLog += "\n> [SYSTEM] 서버 연결 대기 중...";
      }
      _res = {"cpu": 0, "ram": 0, "disk": 0, "ram_gb": "0/0GB", "tps": 0.0, "mspt": 0.0};
    });
    
    if (_lastOnlineStatus != false) {
      _showMsg("🚨 서버 연결 끊김", Colors.redAccent);
      _showNotification("MC CORE SERVER", "🚨 서버가 오프라인입니다.");
      _lastOnlineStatus = false;
    }
  }

  // 서버의 모든 데이터(상태, 자원, 로그, 플레이어) 새로고침
  Future<void> _refresh({bool refreshPlayers = false}) async {
    if (!mounted || _isRefreshing) return;
    _isRefreshing = true;

    try {
      final timeoutLimit = const Duration(seconds: 4);
      // 1. 서버 온라인 상태 체크
      final resS = await http.get(Uri.parse('$serverUrl/status'), headers: _headers).timeout(timeoutLimit);
      
      if (resS.statusCode != 200) {
        _handleServerOffline();
        return;
      }
      
      final statusData = jsonDecode(resS.body);
      bool currentOnline = statusData['online'] ?? false;

      if (!currentOnline) {
        _handleServerOffline();
        return;
      }

      // 상태 변화 알림 (오프라인 -> 온라인)
      if (_lastOnlineStatus == false && currentOnline) {
        _showMsg("✅ 서버 가동됨", Colors.greenAccent);
        _showNotification("MC CORE SERVER", "✅ 서버가 가동되었습니다!");
      }
      _lastOnlineStatus = currentOnline;

      // 2. 자원, 로그, 플레이어 정보 병렬 요청
      final futures = [
        http.get(Uri.parse('$serverUrl/system/resources'), headers: _headers).timeout(timeoutLimit),
        http.get(Uri.parse('$serverUrl/logs'), headers: _headers).timeout(timeoutLimit),
        http.get(Uri.parse('$serverUrl/players?refresh=$refreshPlayers'), headers: _headers).timeout(timeoutLimit),
      ];

      final results = await Future.wait(futures);

      if (mounted) {
        setState(() {
          _isOnline = currentOnline;
          // 자원 정보 파싱
          final resData = jsonDecode(results[0].body);
          _res = {
            "cpu": (resData['cpu'] ?? 0).toInt(),
            "ram": (resData['ram'] ?? 0).toInt(),
            "disk": (resData['disk'] ?? 0).toInt(),
            "ram_gb": resData['ram_gb'] ?? "0/0GB",
            "tps": (resData['tps'] ?? 20.0).toDouble(),
            "mspt": (resData['mspt'] ?? 0.0).toDouble()
          };

          // 로그 정보 파싱
          final logData = jsonDecode(results[1].body);
          var rawFull = logData['full_log'] ?? logData['logs'] ?? "";
          String newFullLog = _cleanLog(rawFull is List ? rawFull.join('\n') : rawFull.toString());
          
          if (newFullLog.isNotEmpty) {
            _fullLog = newFullLog;
            _checkLogEvents(_fullLog); // 로그 기반 이벤트 체크
          }

          var rawChat = logData['chat_log'] ?? logData['chats'] ?? "";
          String newChatLog = _cleanLog(rawChat is List ? rawChat.join('\n') : rawChat.toString());
          if (newChatLog.isNotEmpty) _chatLog = newChatLog;

          // 플레이어 정보 파싱
          final playerData = jsonDecode(results[2].body);
          _players = (playerData != null && playerData['players'] is List) ? playerData['players'] : [];
        });

        _checkResourceWarnings(); // 자원 임계치 체크

        // 로그창 하단으로 자동 스크롤
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll1.hasClients) _scroll1.animateTo(_scroll1.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          if (_scroll2.hasClients) _scroll2.animateTo(_scroll2.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        });
      }
    } catch (e) {
      _handleServerOffline();
    } finally {
      _isRefreshing = false;
    }
  }

  // 범용 API 요청 전송 함수 (POST)
  Future<void> _api(String ep, [Map? body]) async {
    try { 
      await http.post(
        Uri.parse('$serverUrl$ep'), 
        headers: _headers, 
        body: body != null ? jsonEncode(body) : null
      ).timeout(const Duration(seconds: 3)); 
      _refresh(); 
    } catch (e) {
      _showMsg("명령 전송 실패", Colors.redAccent);
    }
  }

  // 플레이어의 상세 데이터(좌표, 인벤토리 등) 요청
  Future<void> _fetchPlayerData(String name) async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/player/detail/$name'), 
        headers: _headers
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        await _refresh(refreshPlayers: true);
        _showMsg("$name 데이터 업데이트", Colors.blueAccent);
      }
    } catch (e) {
      _showMsg("상세정보 요청 실패", Colors.redAccent);
    }
  }

  // 플레이어 상세 정보 대화상자 표시
  void _showPlayerDetailDialog(Map p) {
    String name = p['name'] ?? "Unknown";
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            var currentP = _players.firstWhere((element) => element['name'] == name, orElse: () => p);
            String pos = currentP['pos']?.toString() ?? "좌표 정보 없음";
            List<dynamic> items = currentP['items'] ?? [];

            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F0F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25), side: const BorderSide(color: Colors.white10)),
              title: Row(
                children: [
                  CircleAvatar(backgroundImage: NetworkImage("https://minotar.net/helm/$name/40")),
                  const SizedBox(width: 15),
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(Icons.location_on, "위치", pos, Colors.redAccent),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("인벤토리 정보", style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () async {
                              await _fetchPlayerData(name);
                              setDialogState(() {}); // 데이터 수신 후 팝업 내부 갱신
                            }, 
                            icon: const Icon(Icons.refresh, size: 14), 
                            label: const Text("좌표/템 갱신", style: TextStyle(fontSize: 11))
                          )
                        ],
                      ),
                      const Divider(color: Colors.white10),
                      // 인벤토리 아이템 목록 렌더링
                      items.isEmpty 
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: Text("인벤토리가 비었거나 데이터가 없습니다.", style: TextStyle(color: Colors.white24, fontSize: 11))),
                          )
                        : Wrap(
                            spacing: 8, runSpacing: 8,
                            children: items.map((item) {
                              String itemName = item.toString().toLowerCase().replaceAll(' ', '_');
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.network(
                                      "https://minecraft.wiki/images/Item_$itemName.png",
                                      width: 18, height: 18,
                                      errorBuilder: (c, e, s) => const Icon(Icons.inventory_2, size: 14, color: Colors.white30),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(item.toString(), style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기", style: TextStyle(color: Colors.white38))),
                ElevatedButton(
                  onPressed: () { _playerEditController.text = name; Navigator.pop(ctx); },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: const Text("선택"),
                )
              ],
            );
          }
        );
      }
    );
  }

  // 정보 한 줄 표시용 위젯 (아이콘 + 라벨 + 값)
  Widget _infoRow(IconData icon, String label, String val, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text("$label: ", style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Expanded(child: Text(val, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
      ],
    ),
  );

  // 하단 스낵바 알림 표시
  void _showMsg(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: color.withOpacity(0.8),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // 작업 확인 대화상자 (서버 시작/중지 등 민감한 동작 확인)
  void _confirmDialog(String title, String msg, Color color, Function onYes) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white10)),
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () { onYes(); Navigator.pop(ctx); }, 
            style: ElevatedButton.styleFrom(backgroundColor: color), 
            child: const Text("확인")
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MC CORE SERVER", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
        centerTitle: true, 
        backgroundColor: Colors.black, 
        elevation: 0,
        leading: Icon(Icons.dns, color: _isOnline ? Colors.greenAccent : Colors.redAccent), // 서버 온라인 표시등
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.blueAccent), onPressed: () => _refresh()),
        ],
      ),
      body: Column(
        children: [
          _buildTopResources(),    // CPU, RAM, DISK 요약 정보
          _buildPerformanceBar(), // TPS, MSPT 성능 정보
          _buildLiveGraph(),      // 미니 프로그레스 바 그래프
          _buildTabBar(),         // 탭 버튼 영역
          Expanded(
            child: TabBarView(    // 탭별 콘텐츠
              controller: _tabController,
              children: [
                _logBox(_fullLog, _scroll1, Colors.greenAccent), // 콘솔 로그 탭
                _logBox(_chatLog, _scroll2, Colors.cyanAccent),  // 채팅 로그 탭
                _playerManageTab(),                              // 플레이어 관리 탭
              ],
            ),
          ),
          _modernInputArea(),         // 입력창 영역
          _buildBottomSliceButtons(), // 하단 횡스크롤 기능 버튼들
        ],
      ),
    );
  }

  // 상단 리소스 요약 카드 섹션
  Widget _buildTopResources() => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _resCard("CPU", "${_res['cpu']}%", Colors.cyanAccent),
        _resCard("RAM", "${_res['ram']}%", const Color(0xFFFF00FF)),
        _resCard("DISK", "${_res['disk']}%", Colors.greenAccent),
      ],
    ),
  );

  // 성능 지표 표시 바 (TPS, MSPT)
  Widget _buildPerformanceBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _perfItem("TPS", "${_res['tps'].toStringAsFixed(1)}", _res['tps'] > 18 ? Colors.greenAccent : Colors.orangeAccent),
        Container(width: 1, height: 10, color: Colors.white10),
        _perfItem("MSPT", "${_res['mspt'].toStringAsFixed(1)}ms", _res['mspt'] < 40 ? Colors.cyanAccent : Colors.redAccent),
      ],
    ),
  );

  Widget _perfItem(String label, String val, Color col) => Row(children: [
    Text("$label: ", style: const TextStyle(fontSize: 10, color: Colors.white38)),
    Text(val, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
  ]);

  // 탭바 위젯
  Widget _buildTabBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(15)),
    child: TabBar(
      controller: _tabController,
      indicator: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.blueAccent.withOpacity(0.2)),
      labelColor: Colors.blueAccent, unselectedLabelColor: Colors.white30,
      tabs: const [Tab(text: "CONSOLE"), Tab(text: "CHAT"), Tab(text: "PLAYERS")],
    ),
  );

  // 하단 횡스크롤 기능 버튼 리스트
  Widget _buildBottomSliceButtons() => Container(
    height: 85, 
    margin: const EdgeInsets.only(bottom: 20),
    child: ListView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _sliceBtn("서버 시작", Icons.play_arrow_rounded, Colors.blueAccent, () {
          _confirmDialog("서버 시작", "마인크래프트 서버를 가동하시겠습니까?", Colors.blueAccent, () => _api("/start"));
        }),
        _sliceBtn("백업 실행", Icons.cloud_done_rounded, Colors.cyanAccent, () {
          _confirmDialog("실시간 백업", "현재 데이터를 백업하시겠습니까?", Colors.cyanAccent, () => _api("/backup-only"));
        }),
        _sliceBtn("백업 후 종료", Icons.save_alt_rounded, Colors.white, () {
          _confirmDialog("안전 종료", "백업 후 서버를 종료하시겠습니까?", Colors.white, () => _api("/backup-stop"));
        }),
        _sliceBtn("즉시 중단", Icons.stop_rounded, Colors.orangeAccent, () {
          _confirmDialog("서버 중단", "서버 프로세스를 즉시 중단하시겠습니까?", Colors.orangeAccent, () => _api("/stop-only"));
        }),
        _sliceBtn("시스템 종료", Icons.power_settings_new_rounded, Colors.redAccent, () {
          _confirmDialog("시스템 종료", "호스트 본체의 전원을 완전히 종료하시겠습니까?", Colors.redAccent, () => _api("/system-shutdown"));
        }),
        _sliceBtn("새로고침", Icons.refresh_rounded, Colors.greenAccent, () {
          _refresh(refreshPlayers: true);
          _showMsg("데이터 동기화 완료", Colors.greenAccent);
        }),
      ],
    ),
  );

  // 개별 기능 버튼 디자인 위젯
  Widget _sliceBtn(String t, IconData i, Color c, Function f) => Container(
    width: 120, 
    margin: const EdgeInsets.only(right: 12), 
    child: InkWell(
      onTap: () => f(),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.withOpacity(0.15), width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(i, color: c, size: 28), 
            const SizedBox(height: 6),
            Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ],
        ),
      ),
    ),
  );

  // CPU/RAM 점유율 그래프 바
  Widget _buildLiveGraph() {
    return Container(
      height: 35,
      margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
      child: Row(
        children: [
          Expanded(child: _miniProgressBar("CPU", _res['cpu'] ?? 0, Colors.cyanAccent)),
          const SizedBox(width: 25),
          Expanded(child: _miniProgressBar("RAM", _res['ram'] ?? 0, const Color(0xFFFF00FF))),
        ],
      ),
    );
  }

  // 미니 프로그레스 바 위젯
  Widget _miniProgressBar(String label, dynamic val, Color col) {
    double progress = (val is num) ? val / 100.0 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white38, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(col),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  // 3번째 탭: 플레이어 관리 섹션
  Widget _playerManageTab() {
    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.all(15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("PLAYER CONTROL", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton.icon(
                  onPressed: () => _refresh(refreshPlayers: true),
                  icon: const Icon(Icons.sync, size: 14, color: Colors.greenAccent),
                  label: const Text("SYNC", style: TextStyle(color: Colors.greenAccent, fontSize: 10)),
                )
              ],
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _playerEditController,
              decoration: InputDecoration(
                hintText: "플레이어 이름 선택/입력",
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: ElevatedButton.icon(onPressed: () => _api("/op", {"player_name": _playerEditController.text}), icon: const Icon(Icons.star), label: const Text("OP"), style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black))),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(onPressed: () => _api("/kick", {"player_name": _playerEditController.text}), icon: const Icon(Icons.gavel), label: const Text("KICK"), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent))),
              ],
            ),
            const Divider(height: 40, color: Colors.white10),
            _players.isEmpty 
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("접속 중인 플레이어가 없습니다.", style: TextStyle(color: Colors.white24))))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _players.length,
                  itemBuilder: (ctx, i) {
                    var p = _players[i];
                    String name = (p is Map) ? p['name'] : p.toString();
                    String pos = (p is Map && p['pos'] != null) ? "📍 ${p['pos']}" : "좌표 확인 중...";

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.white10,
                        backgroundImage: NetworkImage("https://minotar.net/helm/$name/30"),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(pos, style: const TextStyle(fontSize: 10, color: Colors.cyanAccent)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white24),
                      onTap: () {
                        if (p is Map) {
                          _showPlayerDetailDialog(p); // 상세 보기 팝업 출력
                        } else {
                          _playerEditController.text = name;
                        }
                      },
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }

  // 상단 요약 카드 디자인
  Widget _resCard(String lab, String val, Color col) => Container(
    width: 110, padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
    child: Column(children: [Text(lab, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
  );

  // 로그 박스 위젯 (콘솔/채팅 공용)
  Widget _logBox(String log, ScrollController sc, Color txtCol) => Container(
    margin: const EdgeInsets.all(15), padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.03))),
    child: SizedBox(
      height: 300,
      child: SingleChildScrollView(controller: sc, child: Text(log, style: TextStyle(color: txtCol, fontSize: 10, fontFamily: 'monospace', height: 1.5))),
    ),
  );

  // 하단 텍스트 입력 영역
  Widget _modernInputArea() => Padding(
    padding: const EdgeInsets.all(15),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white10)),
      child: Row(children: [
        Expanded(child: TextField(controller: _inputController, decoration: const InputDecoration(hintText: "명령어 또는 채팅 입력...", border: InputBorder.none, hintStyle: TextStyle(color: Colors.white24)))),
        IconButton(
          icon: Icon(_tabController.index == 1 ? Icons.chat_bubble_outline : Icons.send_rounded, color: Colors.blueAccent, size: 20), 
          onPressed: () { 
            String cmd = _inputController.text;
            if (cmd.isEmpty) return;
            // 채팅 탭인 경우 /say 명령어로 자동 변환 전송
            if (_tabController.index == 1) {
              _api("/command", {"command": "say $cmd"});
            } else {
              _api("/command", {"command": cmd});
            }
            _inputController.clear(); 
          }
        ),
      ]),
    ),
  );
}