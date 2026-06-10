import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const CybicsApp());
}

class CybicsApp extends StatelessWidget {
  const CybicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cybics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const GameScreen(),
    );
  }
}

enum GameState { mainMenu, levelsMenu, settingsMenu, gameplay, customLevelsMenu, downloadedLevelsMenu, searchMenu, searchResultsMenu, createdLevelsMenu, newLevelMenu, editor, editorConsole, editorTracksMenu }

class Obstacle {
  final String type;
  final double x;
  final double y;
  final double w;
  final double h;
  Obstacle({required this.type, required this.x, required this.y, this.w = 0, this.h = 0});
}

class Medal {
  final int id;
  final double x;
  final double y;
  bool collected;
  Medal({required this.id, required this.x, required this.y, this.collected = false});
}

class BgItem {
  double x;
  double y;
  final double size;
  final double speed;
  double angle;
  final double rotSpeed;
  BgItem({required this.x, required this.y, required this.size, required this.speed, required this.angle, required this.rotSpeed});
}

class DeathParticle {
  double x;
  double y;
  final double vx;
  double vy;
  final double size;
  double alpha;
  DeathParticle({required this.x, required this.y, required this.vx, required this.vy, required this.size, required this.alpha});
}

class GameOrb {
  final double x;
  final double y;
  bool collected;
  GameOrb({required this.x, required this.y, this.collected = false});

  GameOrb clone() => GameOrb(x: this.x, y: this.y, collected: false);
}

class Player {
  double x = 100;
  double y = 0;
  double size = 40;
  double vy = 0;
  double gravity = 1.5;
  double jumpForce = -20;
  bool isGrounded = true;
  bool isShip = false;
  double rotation = 0;
  bool isUpsideDown = false;
}

class CustomLevel {
  final String id;
  final String name;
  final int difficultyIndex;
  int progress;
  String selectedMusic; 
  List<Obstacle> obstacles;
  List<GameOrb> orbs;
  List<Medal> medals;

  CustomLevel({
    required this.id,
    required this.name,
    required this.difficultyIndex,
    this.progress = 0,
    this.selectedMusic = 'none',
    List<Obstacle>? obstacles,
    List<GameOrb>? orbs,
    List<Medal>? medals,
  }) : this.obstacles = obstacles ?? [],
       this.orbs = orbs ?? [],
       this.medals = medals ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'difficultyIndex': difficultyIndex,
    'progress': progress,
    'selectedMusic': selectedMusic,
    'obstacles': obstacles.map((e) => {'type': e.type, 'x': e.x, 'y': e.y, 'w': e.w, 'h': e.h}).toList(),
    'orbs': orbs.map((e) => {'x': e.x, 'y': e.y}).toList(),
    'medals': medals.map((e) => {'id': e.id, 'x': e.x, 'y': e.y}).toList(),
  };

  factory CustomLevel.fromJson(Map<String, dynamic> json) {
    var lvl = CustomLevel(
      id: json['id'],
      name: json['name'],
      difficultyIndex: json['difficultyIndex'],
      progress: json['progress'] ?? 0,
      selectedMusic: json['selectedMusic'] ?? 'level1.mp3',
    );
    if (json['obstacles'] != null) {
      lvl.obstacles = (json['obstacles'] as List).map((e) => Obstacle(
        type: e['type'] ?? 'platform', 
        x: (e['x'] as num).toDouble(), 
        y: (e['y'] as num).toDouble(), 
        w: (e['w'] as num?)?.toDouble() ?? 0, 
        h: (e['h'] as num?)?.toDouble() ?? 0
      )).toList();
    }
    if (json['orbs'] != null) {
      lvl.orbs = (json['orbs'] as List).map((e) => GameOrb(
        x: (e['x'] as num).toDouble(), 
        y: (e['y'] as num).toDouble()
      )).toList();
    }
    if (json['medals'] != null) {
      lvl.medals = (json['medals'] as List).map((e) => Medal(
        id: e['id'] as int, 
        x: (e['x'] as num).toDouble(), 
        y: (e['y'] as num).toDouble()
      )).toList();
    }
    return lvl;
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  GameState _state = GameState.mainMenu;
  
  final ValueNotifier<int> _gameTickNotifier = ValueNotifier<int>(0);

   void _saveCustomLevelsToPrefs() {
    String encoded = jsonEncode(_myCreatedLevels.map((e) => e.toJson()).toList());
    _prefs.setString('cybics_custom_levels', encoded);
  }

  late SharedPreferences _prefs;
  int _maxProgress = 0, _maxProgress2 = 0, _maxProgress3 = 0, _maxProgress4 = 0;
  int _attempts1 = 0, _attempts2 = 0, _attempts3 = 0, _attempts4 = 0;
  List<bool> _savedMedals1 = [false];
  List<bool> _savedMedals2 = [false, false];
  List<bool> _savedMedals3 = [false, false, false];
  List<bool> _savedMedals4 = [false, false, false];

  final AudioPlayer _menuPlayer = AudioPlayer();
  final AudioPlayer _level1Player = AudioPlayer();
  final AudioPlayer _level2Player = AudioPlayer();
  final AudioPlayer _level3Player = AudioPlayer();
  final AudioPlayer _level4Player = AudioPlayer();
  final AudioPlayer _deathPlayer = AudioPlayer();

  double _volume = 50.0;
  bool _showPercent = true;
  bool _showFps = false;
  int _fpsCount = 0;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();

  int _currentLevel = 1;
  int _currentRunAttempts = 1;
  bool _isGodMode = false;
  int _titleClicks = 0;
  bool _isPlaying = false;
  bool _isPaused = false;
  
  double _levelLength = 20000;
  final double _gameHeight = 600;
  final double _floorY = 500;
  
  Player _player = Player();
  double _cameraX = 0;
  List<Obstacle> _obstacles = [];
  List<Medal> _medals = [];
  List<Offset> _trailParticles = [];
  List<BgItem> _bgItems = [];
  List<DeathParticle> _deathParticles = [];
  List<GameOrb> _orbs = [];
  final List<DeathParticle> _portalParticles = [];
  double _orbSpinAngle = 0;
  bool _isGravityInverted = false;
  List<int> _collectedThisRun = [];
  int _currentProgress = 0;
  int _spaceTimeCounter = 0; // Счетчик кадров для 3-секундного таймера в космосе
  final TextEditingController _searchController = TextEditingController(); // Контроллер для поля поиска
  final TextEditingController _levelNameController = TextEditingController(); // Контроллер названия уровня
  int _selectedDifficultyIndex = 0; // Выбранная сложность (0 - легко, 5 - кошмар)
  List<CustomLevel> _myCreatedLevels = []; // Список всех созданных уровней игрока
  GameState _customLevelLaunchSource = GameState.createdLevelsMenu; // Запоминает, откуда запустили кастомную карту
  CustomLevel? _currentEditingLevel; // Какой уровень мы сейчас редактируем
  final TextEditingController _consoleController = TextEditingController(); // Для командной строки
  bool _areSecretTracksUnlocked = false; // Разблокированы ли новые треки чит-кодом
  
  // Переменные для режима работы редактора
  String _editorSelectedTool = 'platform_1'; // Какая постройка выбрана в доке
  bool _isEraserMode = false; // Включена ли стёрка
  bool _isBuildDockOpen = false; // Открыта ли панель построек
  double _editorCameraX = 0; // Сдвиг экрана пальцами в редакторе
  double _editorCameraY = 0; // Сдвиг камеры редактора по вертикали (вверх/вниз)

  // Истории действий для Undo/Redo (храним снимки списков)
  final List<String> _undoHistory = [];
  final List<String> _redoHistory = [];

  bool _isPressing = false;

  bool _showNewRecord = false;
  bool _showVictory = false;

  Timer? _gameTimer;
  late AnimationController _pulseController;

  Timer? _deathVolumeTimer;
  Timer? _retryTimer;

    @override
  void initState() {
    super.initState();
    
    // ИСПРАВЛЕНИЕ: Включаем режим полного погружения (Immersive Sticky)
    // Это намертво прячет верхнюю панель времени и 3 боковые кнопки навигации приложения
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    _initData();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  Future<void> _initData() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _maxProgress = _prefs.getInt('cybics_max_progress') ?? 0;
      _maxProgress2 = _prefs.getInt('cybics_max_progress_2') ?? 0;
      _maxProgress3 = _prefs.getInt('cybics_max_progress_3') ?? 0;
      _maxProgress4 = _prefs.getInt('cybics_max_progress_4') ?? 0;
      _attempts1 = _prefs.getInt('cybics_attempts_1') ?? 0;
      _attempts2 = _prefs.getInt('cybics_attempts_2') ?? 0;
      _attempts3 = _prefs.getInt('cybics_attempts_3') ?? 0;
      _attempts4 = _prefs.getInt('cybics_attempts_4') ?? 0;
      _volume = _prefs.getDouble('cybics_volume') ?? 50.0;
      _showPercent = _prefs.getBool('cybics_show_percent') ?? true;
      _showFps = _prefs.getBool('cybics_show_fps') ?? false;

      String? m1 = _prefs.getString('cybics_medals_1');
      if (m1 != null) _savedMedals1 = List<bool>.from(jsonDecode(m1));
      String? m2 = _prefs.getString('cybics_medals_2');
      if (m2 != null) _savedMedals2 = List<bool>.from(jsonDecode(m2));
      String? m3 = _prefs.getString('cybics_medals_3');
      if (m3 != null) _savedMedals3 = List<bool>.from(jsonDecode(m3));
      String? m4 = _prefs.getString('cybics_medals_4');
      if (m4 != null) _savedMedals4 = List<bool>.from(jsonDecode(m4));
      String? savedLevelsJson = _prefs.getString('cybics_custom_levels');
      if (savedLevelsJson != null) {
        List<dynamic> decoded = jsonDecode(savedLevelsJson);
        _myCreatedLevels = decoded.map((item) => CustomLevel.fromJson(item)).toList();
      }
    });
    _updatePlayersVolume();
    _startMusicSequencer();
  }

  void _updatePlayersVolume() {
    double vol = _volume / 100.0;
    _menuPlayer.setVolume(vol * 0.5);
    _level1Player.setVolume(vol);
    _level2Player.setVolume(vol);
    _level3Player.setVolume(vol);
    _level4Player.setVolume(vol);
    _deathPlayer.setVolume(vol * 0.5);
  }

    void _startMusicSequencer() async {
    try {
      await _menuPlayer.setReleaseMode(ReleaseMode.loop);
      await _level1Player.setReleaseMode(ReleaseMode.loop);
      await _level2Player.setReleaseMode(ReleaseMode.loop);
      await _level3Player.setReleaseMode(ReleaseMode.loop);
      await _level4Player.setReleaseMode(ReleaseMode.loop);

      if (_state == GameState.gameplay) {
        await _menuPlayer.stop();
        await _stopAllLevelTracks();

        if (!_isPaused) {
                    if (_currentEditingLevel != null) {
            // ИСПРАВЛЕНИЕ: Если трек равен 'none' — глушим музыку до тех пор, пока игрок не выберет её в консоли!
            if (_currentEditingLevel!.selectedMusic == 'none') {
              await _level1Player.stop();
            } else {
              await _level1Player.play(AssetSource(_currentEditingLevel!.selectedMusic));
            }
          } else {
            // Обычные стандартные уровни игры
            if (_currentLevel == 1) await _level1Player.play(AssetSource('level1.mp3'));
            if (_currentLevel == 2) await _level2Player.play(AssetSource('level2.mp3'));
            if (_currentLevel == 3) await _level3Player.play(AssetSource('level3.mp3'));
            if (_currentLevel == 4) await _level4Player.play(AssetSource('level4.mp3'));
          }
        }
      } else {
        await _stopAllLevelTracks();
        await _menuPlayer.play(AssetSource('menu.mp3'));
      }
    } catch (e) {
      debugPrint("Ошибка аудиосеквенсора: $e");
    }
  }


  Future<void> _stopAllLevelTracks() async {
    try {
      await _level1Player.stop();
      await _level2Player.stop();
      await _level3Player.stop();
      await _level4Player.stop();
    } catch (e) {
      debugPrint("Ошибка остановки треков: $e");
    }
  }

    void _playDeathSound() async {
    try {
      // ИСПРАВЛЕНИЕ: Отменяем старый таймер громкости, если игрок умер слишком быстро
      _deathVolumeTimer?.cancel(); 

      await _deathPlayer.stop();
      await _deathPlayer.setVolume((_volume / 100.0) * 0.2);
      await _deathPlayer.play(AssetSource('death.mp3'));

      AudioPlayer activePlayer;
      if (_currentLevel == 1) activePlayer = _level1Player;
      else if (_currentLevel == 2) activePlayer = _level2Player;
      else if (_currentLevel == 3) activePlayer = _level3Player;
      else activePlayer = _level4Player;

      double normalVol = _volume / 100.0;
      
      // ИСПРАВЛЕНИЕ: Убираем await с фоновых операций, чтобы UI не зависал в момент смерти
      activePlayer.setVolume(normalVol * 0.2);
      activePlayer.seek(Duration.zero);
      await activePlayer.play(
        _currentLevel == 1 ? AssetSource('level1.mp3') : 
        (_currentLevel == 2 ? AssetSource('level2.mp3') : 
        (_currentLevel == 3 ? AssetSource('level3.mp3') : AssetSource('level4.mp3')))
      );

      // ИСПРАВЛЕНИЕ: Сохраняем таймер в переменную класса
      _deathVolumeTimer = Timer(const Duration(milliseconds: 300), () async {
        await activePlayer.setVolume(normalVol);
      });
    } catch (e) {
      debugPrint("Ошибка перезапуска музыки при смерти: $e");
    }
  }


  double _seededRandom(int seed) {
    double x = math.sin(seed.toDouble()) * 10000;
    return x - x.floorToDouble();
  }

  void _generateFixedLevel() {
    _obstacles.clear();
    _medals.clear();
    _orbs.clear();
    _collectedThisRun.clear();
    double nextX = 700;

    if (_currentLevel == 1) {
      _orbs.clear();
      int seed = 42;
      while (nextX < _levelLength - 1000) {
        double r = _seededRandom(seed++);
        if (r < 0.35) {
          _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
          nextX += 400 + _seededRandom(seed++) * 200;
        } else if (r < 0.6) {
          _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
          _obstacles.add(Obstacle(type: 'spike', x: nextX + 30, y: _floorY));
          nextX += 500 + _seededRandom(seed++) * 200;
        } else {
          double pWidth = 200 + (_seededRandom(seed++) * 3).floor() * 60;
          double pHeight = 80;
          _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - pHeight, w: pWidth, h: pHeight));
          if (_seededRandom(seed++) > 0.4) {
            _obstacles.add(Obstacle(type: 'spike', x: nextX + pWidth / 2 - 15, y: _floorY - pHeight));
          }
          nextX += pWidth + 400 + _seededRandom(seed++) * 200;
        }
      }
      _medals.add(Medal(id: 0, x: _levelLength * 0.52, y: _floorY - 140));
    } 
    else if (_currentLevel == 2) {
      _orbs.clear();
      int seed = 999;
      while (nextX < _levelLength - 1000) {
        double progressPct = (nextX / _levelLength) * 100;
        bool isShipZone = progressPct >= 40 && progressPct <= 71;

                if (isShipZone) {
          double r = _seededRandom(seed++);
          if (r < 0.5) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 0, w: 60, h: 180));
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 180, w: 60, h: 180));
          } else {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 100, w: 80, h: 100));
          }
          nextX += 600 + _seededRandom(seed++) * 200;
        } else {
          double r = _seededRandom(seed++);
          if (r < 0.4) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 60, w: 160, h: 60));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 220, y: _floorY - 120, w: 160, h: 120));
            nextX += 600;
          } else if (r < 0.7) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 70, w: 300, h: 70));
            nextX += 650;
          } else {
            _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
            nextX += 450;
          }
        }
      }
      _medals.add(Medal(id: 0, x: _levelLength * 0.22, y: _floorY - 150));
      _medals.add(Medal(id: 1, x: _levelLength * 0.435, y: _floorY - 30));
    } 
    else if (_currentLevel == 3) {
      _orbs.clear();
      int seed = 888;
      bool spawnedTrap = false;
      bool spawnedShipTrap = false;
      bool spawnedSecretChain = false;

      while (nextX < _levelLength - 1000) {
        double progressPct = (nextX / _levelLength) * 100;
        bool isShipZone = progressPct >= 40 && progressPct <= 71;

        if (isShipZone) {
          if (!spawnedShipTrap && progressPct > 52) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 0, w: 280, h: 40));
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 190, w: 280, h: 40));
            _medals.add(Medal(id: 1, x: nextX + 140, y: 115));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 10, y: 230));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 90, y: 230));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 170, y: 230));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 250, y: 230));
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 100, w: 280, h: 100));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 40, y: _floorY - 100));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 120, y: _floorY - 100));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 200, y: _floorY - 100));
            nextX += 600;
            spawnedShipTrap = true;
          } else {
            double r = _seededRandom(seed++);
            if (r < 0.4) {
              _obstacles.add(Obstacle(type: 'spike', x: nextX - 80, y: _floorY));
              _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 240, w: 60, h: 120));
              _obstacles.add(Obstacle(type: 'spike', x: nextX - 15, y: 300));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 15, y: 240));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 40, y: 300));
              nextX += 450;
            } else if (r < 0.7) {
              _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 0, w: 200, h: 140));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 20, y: 170));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 90, y: 170));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 160, y: 170));
              _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 80, w: 200, h: 80));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 10, y: _floorY - 80));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 80, y: _floorY - 80));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 150, y: _floorY - 80));
              nextX += 500;
            } else {
              _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 30, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 60, y: _floorY));
              nextX += 400;
            }
          }
        } else {
          if (progressPct >= 71 && progressPct < 77.5) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 30, w: 120, h: 30));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 260, y: _floorY));
            nextX += 450;
          } 
          else if (progressPct >= 30 && progressPct < 36) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 60, w: 220, h: 20));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 20, y: 0, w: 180, h: _floorY - 150));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 260, y: _floorY - 110));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 260, y: 0, w: 30, h: _floorY - 110));
            nextX += 580;
          } 
          else if (progressPct >= 36 && progressPct < 40) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 40, w: 80, h: 40));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 110, y: _floorY));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 170, y: _floorY - 80, w: 80, h: 80));
            nextX += 450;
          } 
          else if (!spawnedSecretChain && progressPct >= 77.5) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 70, w: 200, h: 70));
            double p1X = nextX + 240;
            double p1Y = _floorY - 140;
            _obstacles.add(Obstacle(type: 'platform', x: p1X, y: p1Y, w: 80, h: 25));
            double p2X = p1X + 160;
            double p2Y = _floorY - 210;
            _obstacles.add(Obstacle(type: 'platform', x: p2X, y: p2Y, w: 80, h: 25));
            _medals.add(Medal(id: 2, x: p2X + 40, y: p2Y - 25));
            nextX = p2X + 250;
            spawnedSecretChain = true;
          } 
          else if (!spawnedTrap && progressPct > 6 && progressPct < 15) {
            double currentY = _floorY;
            for (int i = 0; i < 5; i++) {
              currentY -= 50;
              double gapShift = (i >= 2) ? 40 : 0;
              _obstacles.add(Obstacle(type: 'platform', x: nextX + (i * 180) + gapShift, y: currentY, w: 120, h: 50));
            }
            double platform6X = nextX + (5 * 180) + 40;
            _obstacles.add(Obstacle(type: 'platform', x: platform6X, y: currentY - 50, w: 120, h: 50));
            _obstacles.add(Obstacle(type: 'spike', x: platform6X + 90, y: currentY - 50));
            _medals.add(Medal(id: 0, x: nextX + (2 * 180) + 80, y: _floorY - 40));
            nextX += (6 * 180) + 40 + 350;
            spawnedTrap = true;
          } 
                    else {
            double r = _seededRandom(seed++);
            // ИСПРАВЛЕНИЕ: Локальная переменная для шага по умолчанию
            double stepX = 500; 

            if (r < 0.25) {
              _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 30, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 60, y: _floorY));
              stepX = 500;
            } else if (r < 0.50) {
              _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 40, w: 100, h: 40));
              _obstacles.add(Obstacle(type: 'platform', x: nextX + 180, y: _floorY - 100, w: 120, h: 100));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 260, y: _floorY - 100));
              stepX = 550;
            } else if (r < 0.75) {
              _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
              _obstacles.add(Obstacle(type: 'platform', x: nextX + 40, y: _floorY - 60, w: 200, h: 60));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 280, y: _floorY));
              stepX = 520;
            } else {
              _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 30, y: _floorY));
              _obstacles.add(Obstacle(type: 'platform', x: nextX + 180, y: _floorY - 80, w: 80, h: 80));
              stepX = 480;
            }
            // Гарантированный сдвиг вперед, исключающий зависание цикла
            nextX += stepX; 
          }
        }
      }
    }
        else if (_currentLevel == 4) {
      int seed = 4444; 
      int invertedSeed = 8585;
      _orbs.clear();
      _medals.clear(); 
      double portalInX = _levelLength * 0.35;
      double portalOutX = _levelLength * 0.70; 
      bool safeGapSpawned = false;

      bool spawnedMedal1Obstacle = false;
      bool spawnedMedal2Obstacle = false;
      bool spawnedMedal3Obstacle = false;

      while (nextX < _levelLength - 1000) {
        double progressPct = (nextX / _levelLength) * 100;
        bool isGravityZone = progressPct >= 35 && progressPct <= 70;

        // --- ЗОНА ИНВЕРСИИ ГРАВИТАЦИИ (35% - 70%) ---
        if (isGravityZone) {
          if (nextX < portalInX + 500) {
            _obstacles.add(Obstacle(type: 'platform', x: portalInX, y: 130, w: 350, h: 30));
            nextX = portalInX + 650;
            continue;
          }

          // МЕДАЛЬ №2 (50%): НАСТРОЙКА СФЕРЫ ВЫШЕ, МОНЕТКА ТАМ ЖЕ
          if (progressPct >= 50.0 && !spawnedMedal2Obstacle) {
            double platX = nextX;
            double platY = 100;
            double platW = 500; 
            
            _obstacles.add(Obstacle(type: 'platform', x: platX, y: platY, w: platW, h: 60));
            
            // 3 нормальных шипа
            _obstacles.add(Obstacle(type: 'spike', x: platX + 220, y: 160));
            _obstacles.add(Obstacle(type: 'spike', x: platX + 250, y: 160)); 
            _obstacles.add(Obstacle(type: 'spike', x: platX + 280, y: 160));

            // ИСПРАВЛЕНИЕ: Подняли сферу чуть повыше (ближе к центру экрана: Y = platY + 140 вместо 110)
            _orbs.add(GameOrb(x: platX + 250, y: platY + 140, collected: false));
            
            // Монетка осталась на своей высоте (Y = platY + 210)
            _medals.add(Medal(id: 1, x: platX + 340, y: platY + 210));

            nextX += platW + 150; 
            spawnedMedal2Obstacle = true;
            continue;
          }

                    // МЕДАЛЬ №3 (67%): СКРЫТАЯ МОНЕТА В ИНВЕРТИРОВАННОЙ ПРОПАСТИ НАВЕРХУ
          if (progressPct >= 66.5 && progressPct <= 68.5 && !spawnedMedal3Obstacle) {
            double m3X = nextX;
            
            // Стартовая платформа-потолок
            _obstacles.add(Obstacle(type: 'platform', x: m3X, y: 100, w: 150, h: 40));
            
            // Монетка скрыта наполовину
            _medals.add(Medal(id: 2, x: m3X + 265, y: -10)); 

            // Орб для прыжка обратно в коридор
            _orbs.add(GameOrb(x: m3X + 265, y: 160, collected: false));
            
            // ИСПРАВЛЕНИЕ: Отодвинули вторую платформу дальше (X = m3X + 520 вместо +380) 
            // и уменьшили ширину до 80, чтобы у кубика было огромное безопасное окно 
            // для падения вниз сквозь портал без удара о торец блока!
            _obstacles.add(Obstacle(type: 'platform', x: m3X + 520, y: 100, w: 80, h: 40));
            
            nextX += 680; 
            spawnedMedal3Obstacle = true;
            continue;
          }




          // Обычный рандом внутри инверсии (УДАЛЕНЫ любые скрытые/случайные спавны медалей!)
          double rMode = _seededRandom(invertedSeed++);
          if (rMode < 0.33) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 80, w: 180, h: 60));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 240, y: 120, w: 180, h: 60)); 
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 480, y: 160, w: 180, h: 60)); 
            nextX += 720;
          } else if (rMode < 0.66) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 100, w: 300, h: 60));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 95, y: 160));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 125, y: 160)); 
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 155, y: 160));
            nextX += 500;
          } else {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: 100, w: 150, h: 60));
            _orbs.add(GameOrb(x: nextX + 265, y: 220, collected: false));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 380, y: 100, w: 150, h: 60));
            nextX += 650;
          }
        } 
                // --- НАЗЕМНАЯ ЗОНА ОБЫЧНОЙ ГРАВИТАЦИИ ---
        else {
          if (progressPct > 70 && !safeGapSpawned) {
            nextX = portalOutX + 600;
            safeGapSpawned = true;
            continue;
          }

          // ======================================================================
          // ИСПРАВЛЕНИЕ: Препятствие генерируется динамически по ходу движения X,
          // как только мы пересекаем отметку 25% прогресса (примерно начало уровня)
          // ======================================================================
          if (progressPct >= 25.0 && !spawnedMedal1Obstacle) {
            double startX = nextX;
            
            // Основание (удлиняем платформу под тремя сферами)
            _obstacles.add(Obstacle(type: 'platform', x: startX, y: _floorY - 40, w: 380, h: 40));
            
            // 12 шипов подряд
            for (int i = 0; i < 12; i++) {
              _obstacles.add(Obstacle(type: 'spike', x: startX + (i * 30), y: _floorY - 40));
            }
            
            // НАША ЗАДУМКА: Лесенка из ТРЁХ сфер вместо двух
            _orbs.add(GameOrb(x: startX + 60, y: _floorY - 120, collected: false));
            _orbs.add(GameOrb(x: startX + 170, y: _floorY - 190, collected: false));
            _orbs.add(GameOrb(x: startX + 280, y: _floorY - 260, collected: false)); // Третья сфера выше и правее!
            
            // Платформа после шипов, куда приземляется игрок
            _obstacles.add(Obstacle(type: 'platform', x: startX + 380, y: _floorY - 60, w: 110, h: 60));
            
            // ИСПРАВЛЕНИЕ: Монетка находится на уровне и прям чуть выше третьей сферы (на 20px выше)
            _medals.add(Medal(id: 0, x: startX + 310, y: _floorY - 280));  
            
            // Безопасный отступ в 900 пикселей, чтобы игрок не умер сразу после забора
            nextX = startX + 380 + 110 + 900; 
            spawnedMedal1Obstacle = true;
            continue;
          }

          // Стандартный рандом (срабатывает на остальных участках пола)
          double r = _seededRandom(seed++);
          if (r < 0.35) {
            _orbs.add(GameOrb(x: nextX + 110, y: _floorY - 110, collected: false));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 30, y: _floorY));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 60, y: _floorY));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 90, y: _floorY));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 120, y: _floorY));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 150, y: _floorY)); 
            nextX += 510;
          } else if (r < 0.70) {
            _orbs.add(GameOrb(x: nextX + 50, y: _floorY - 90, collected: false));
            _orbs.add(GameOrb(x: nextX + 200, y: _floorY - 170, collected: false));
            for (int i = 0; i < 9; i++) {
              _obstacles.add(Obstacle(type: 'spike', x: nextX + (i * 30), y: _floorY));
            }
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 280, y: _floorY - 80, w: 120, h: 80));
            nextX += 560; 
          } else {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 50, w: 100, h: 50));
            _orbs.add(GameOrb(x: nextX + 200, y: _floorY - 140, collected: false));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 130, y: _floorY));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 160, y: _floorY));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 190, y: _floorY));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 220, y: _floorY)); 
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 250, y: _floorY)); 
            nextX += 540;
          }
        }
      }
    }
    }
  

  void _launchGameplay() {
    setState(() {
      _state = GameState.gameplay;
      _isPlaying = true;
      _isPaused = false;
      _currentRunAttempts = 1;

      // ТВОЯ ЛОГИКА: Попытки растут ТОЛЬКО если уровень ещё не пройден на 100%
      if (_currentLevel == 1 && _maxProgress < 100) { _attempts1++; _prefs.setInt('cybics_attempts_1', _attempts1); }
      if (_currentLevel == 2 && _maxProgress2 < 100) { _attempts2++; _prefs.setInt('cybics_attempts_2', _attempts2); }
      if (_currentLevel == 3 && _maxProgress3 < 100) { _attempts3++; _prefs.setInt('cybics_attempts_3', _attempts3); } // Исправлено на _maxProgress3
      if (_currentLevel == 4 && _maxProgress4 < 100) { _attempts4++; _prefs.setInt('cybics_attempts_4', _attempts4); }
    });

    _startMusicSequencer();
    _startLevel();
  }

    void _startLevel() {
    _gameTimer?.cancel();
    setState(() {
      _isPlaying = true;
      _cameraX = 0;
      _currentProgress = 0;
      _trailParticles.clear();
      _collectedThisRun.clear();
      _showVictory = false;
      _showNewRecord = false; 
      _spaceTimeCounter = 0;
      _isGravityInverted = false;
      _portalParticles.clear();

      _player = Player()
        ..y = _floorY - 40
        ..isUpsideDown = false;
      
      // ИСПРАВЛЕНИЕ 2: Сбрасываем режим самолётика у нового игрока, чтобы раунд всегда начинался кубиком
      _player.isShip = false; 

      _bgItems.clear();
      var rand = math.Random();
      for (int i = 0; i < 15; i++) {
        _bgItems.add(BgItem(
          x: rand.nextDouble() * 800,
          y: rand.nextDouble() * (_floorY - 100),
          size: 8 + rand.nextDouble() * 12,
          speed: 0.5 + rand.nextDouble() * 0.8,
          angle: rand.nextDouble() * math.pi * 2,
          rotSpeed: 0.01 + rand.nextDouble() * 0.02
        ));
      }

      _generateFixedLevel();

            if (_currentLevel == 5 && _currentEditingLevel != null) {
        _obstacles = List.from(_currentEditingLevel!.obstacles);
        
        // ИСПРАВЛЕНИЕ: Глубокое клонирование сфер! 
        // Теперь каждая попытка создает новые физические сферы в игре, а оригиналы в редакторе не портятся!
        _orbs = _currentEditingLevel!.orbs.map((orb) => orb.clone()).toList();
        
        _medals = List.from(_currentEditingLevel!.medals);


        double farthestX = 2000.0;
        for (var obs in _obstacles) { if (obs.x > farthestX) farthestX = obs.x; }
        for (var orb in _orbs) { if (orb.x > farthestX) farthestX = orb.x; }
        for (var m in _medals) { if (m.x > farthestX) farthestX = m.x; }
        
        _levelLength = farthestX + 800.0; 
        
        // Перезапускаем трек, выбранный игроком, с самого начала
        _level1Player.stop();
        _level1Player.seek(Duration.zero);
        // Защита: если музыка 'none', то плеер просто молчит, иначе — играет выбранный трек
        if (_currentEditingLevel!.selectedMusic != 'none') {
          _level1Player.play(AssetSource(_currentEditingLevel!.selectedMusic));
        }
      } else {
        _levelLength = 20000.0; 
        // ИСПРАВЛЕНИЕ 4: Для обычных уровней сбрасываем статус собранных медалей
        for (var m in _medals) {
          m.collected = false;
        }
        for (var orb in _orbs) {
          orb.collected = false;
        }
      }
    });

    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_isPlaying && !_isPaused) {
        _updatePhysics(); 
        _gameTickNotifier.value++; 
      }
    });
  }


      void _checkOrbActivation() {
    if (!_isPlaying || _isPaused || _currentLevel != 4) return;

    final double playerCenterX = _player.x + _player.size / 2;
    final double playerCenterY = _player.y + _player.size / 2;

    for (var orb in _orbs) {
      if (orb.collected) continue;
      if (orb.x < _player.x - 60 || orb.x > _player.x + 150) continue;

      double distX = (playerCenterX - orb.x).abs();
      double distY = (playerCenterY - orb.y).abs();
      
      if (distX < 70 && distY < 70) {
        orb.collected = true;
        
        // ИСПРАВЛЕНИЕ: В инверсии сфера должна толкать куб ВНИЗ (vy = 14.5), а на полу — ВВЕРХ (vy = -14.5)
        if (_isGravityInverted) {
          _player.vy = 14.5;
        } else {
          _player.vy = -14.5;
        }
        _player.isGrounded = false;
        break;
      }
    }
  }

  void _updatePhysics() {
    _player.x += 7.5;
    _cameraX = _player.x - 200;

        double progressPct = (_player.x / _levelLength) * 100;
    // ИСПРАВЛЕНИЕ: Автоматический сброс по % работает ТОЛЬКО на стандартных уровнях. 
    // На 5-м кастомном уровне режим переключается исключительно порталами!
    if (_currentLevel != 5) {
      _player.isShip = (progressPct >= 40 && progressPct <= 75 && (_currentLevel == 2 || _currentLevel == 3));
    }


    _trailParticles.add(Offset(_player.x, _player.y + _player.size / 2));
    if (_trailParticles.length > 15) _trailParticles.removeAt(0);

    // ОПТИМИЗАЦИЯ: Считаем тики вместо создания тяжелых объектов DateTime.now() каждую миллисекунду
    _frameCount++;
    if (_frameCount >= 60) {
      _fpsCount = _frameCount;
      _frameCount = 0;
    }

        // --- ЭТАП 1: ОБРАБОТКА ВВОДА (ПРЫЖКИ КУБИКА И СДВИГ ВЕКТОРОВ СКОРОСТИ) ---
    if (_currentLevel == 4) {
      _player.isShip = false;
      _isGravityInverted = (progressPct >= 35 && progressPct <= 70);
      
      double portalInX = _levelLength * 0.35;
      bool isAutoFlying = _isGravityInverted && (_player.x < portalInX + 600);

      if (_isPressing && _player.isGrounded && !isAutoFlying) {
        _player.vy = _isGravityInverted ? 17.0 : _player.jumpForce;
        _player.isGrounded = false;
      }
    } 
    else if (_currentLevel == 5) {
      // Для кастомного уровня: если кубик на потолке, прыжок толкает его ВНИЗ (+17.0)
      if (!_player.isShip && _isPressing && _player.isGrounded) {
        _player.vy = _isGravityInverted ? 17.0 : _player.jumpForce;
        _player.isGrounded = false;
      }
    } 
    else {
      // Стандартные уровни 1, 2, 3
      if (!_player.isShip && _isPressing && _player.isGrounded) {
        _player.vy = _player.jumpForce;
        _player.isGrounded = false;
      }
    }

     // --- ЭТАП 2: ФИЗИКА ДВИЖЕНИЯ (ГРАВИТАЦИЯ, ИНВЕРСИЯ И ОБСЧЁТ ТАЙМЕРА КОСМОСА) ---
    bool wasGrounded = _player.isGrounded;
    _player.isGrounded = false;

    // ======================================================================
    // ГЛОБАЛЬНАЯ ЛОГИКА ТАЙМЕРА КОСМОСА ДЛЯ ВСЕХ РЕЖИМОВ И УРОВНЕЙ (4 и 5)
    // ======================================================================
    // ИСПРАВЛЕНИЕ: Теперь условие работает СИНХРОННО для кубика и самолетика на 4 и 5 уровнях!
    if (_isGravityInverted && _player.y < 0) {
      _spaceTimeCounter++;
      
      if (_spaceTimeCounter > 180 && !_isGodMode) { // 180 кадров движка = 3 секунды
        _spaceTimeCounter = 0;
        _gameOver(); 
        return;
      }
    } else {
      if (_player.y >= 0) {
        _spaceTimeCounter = 0; // Сброс таймера в безопасной зоне
      }
    }

    // РАСЧЁТ ДВИЖЕНИЯ ДЛЯ 4-ГО УРОВНЯ
    if (_currentLevel == 4) {
      double portalInX = _levelLength * 0.35;
      bool isAutoFlying = _isGravityInverted && (_player.x < portalInX + 600);

      if (isAutoFlying) {
        double targetPlatformY = 160;
        _player.y += (targetPlatformY - _player.y) * 0.12;
        _player.vy = 0;
        if ((_player.y - targetPlatformY).abs() < 5) {
          _player.y = targetPlatformY;
          _player.isGrounded = true;
        }
      } 
      else if (_isGravityInverted) {
        _player.vy -= 1.3;
        if (_player.vy < -14) _player.vy = -14;
        
        // ИСПРАВЛЕНИЕ: Позволяем кубику на 4 уровне беспрепятственно улетать в Y < 0, чтобы включить таймер
        _player.y += _player.vy;

        if (progressPct >= 64.0 && progressPct <= 69.0) {
          if (_player.y >= 350) {
            _isGravityInverted = false;
            _player.vy = 0;
          }
        } else {
          // Убираем здесь жесткую смерть при y <= 5, чтобы она не конфликтовала с 3-секундным таймером!
          if (_player.y < -1500 && !_isGodMode) { 
            _gameOver(); 
            return; 
          }
        } 
      } 
      else {
        _player.vy += _player.gravity;
        if (_player.vy > 15) _player.vy = 15;
        _player.y += _player.vy;
        if (_player.y >= _floorY - _player.size) {
          _player.y = _floorY - _player.size;
          _player.vy = 0;
          _player.isGrounded = true;
        }
      } 
    } 
    // РАСЧЁТ ДВИЖЕНИЯ ДЛЯ КАСТОМНОГО 5-ГО УРОВНЯ
    else if (_currentLevel == 5) {
      if (_player.isShip) {
        if (_isGravityInverted) {
          // Инвертированный самолётик: зажали — летит вниз, отпустили — падает вверх (в космос)
          if (_isPressing) _player.vy += 0.9; else _player.vy -= 0.7;
        } else {
          // Обычный самолётик
          if (_isPressing) _player.vy -= 0.9; else _player.vy += 0.7;
        }
        _player.vy = _player.vy.clamp(-8, 8);
        _player.y += _player.vy;

        // ИСПРАВЛЕНИЕ: Убрали жесткий ограничитель у самолетика (y <= 60), если включена инверсия!
        // Теперь самолётик в инверсии может свободно пересекать границу Y < 0 и улетать вверх.
        if (!_isGravityInverted && _player.y <= 60) { 
          _player.y = 60; 
          _player.vy = 0; 
        }
        
        if (_player.y >= _floorY - _player.size) { 
          _player.y = _floorY - _player.size; 
          _player.vy = 0; 
        }
      } 
      else {
        if (_isGravityInverted) {
          _player.vy -= 1.3; 
          if (_player.vy < -14) _player.vy = -14;
          _player.y += _player.vy;
          
          // Потолок y = 100 полностью убран, кубик свободно летит вверх за экран.
        } else {
          _player.vy += _player.gravity;
          if (_player.vy > 15) _player.vy = 15;
          _player.y += _player.vy;

          if (_player.y >= _floorY - _player.size) {
            _player.y = _floorY - _player.size;
            _player.vy = 0;
            _player.isGrounded = true;
          }
        }
      }
    }
    // СТАНДАРТНЫЕ УРОВНИ 1, 2, 3
    else {
      if (_player.isShip) {
        if (_isPressing) _player.vy -= 0.9; else _player.vy += 0.7;
        _player.vy = _player.vy.clamp(-8, 8);
        _player.y += _player.vy;
        if (_player.y <= 100) { _player.y = 100; _player.vy = 0; }
      } else {
        _player.vy += _player.gravity;
        _player.y += _player.vy;
      }

      if (_player.y >= _floorY - _player.size) {
        _player.y = _floorY - _player.size;
        _player.vy = 0;
        _player.isGrounded = true;
      }
    }


        // --- ЭТАП 3: РАСЧЕТ КОЛЛИЗИЙ И ДИНАМИЧЕСКИЙ ПРОГРЕСС ---
    _currentProgress = (progressPct.clamp(0, 100)).floor();

    if (_currentLevel == 5 && _currentEditingLevel != null) {
      if (_currentProgress > _currentEditingLevel!.progress) {
        _currentEditingLevel!.progress = _currentProgress;
        String encoded = jsonEncode(_myCreatedLevels.map((e) => e.toJson()).toList());
        _prefs.setString('cybics_custom_levels', encoded);
      }
    }

    // Сбор монет
    for (var m in _medals) {
      if (m.collected) continue;
      if (m.x < _player.x - 100 || m.x > _player.x + 200) continue;
      double playerCenterX = _player.x + _player.size / 2;
      double playerCenterY = _player.y + _player.size / 2;
      if ((playerCenterX - m.x).abs() < 50 && (playerCenterY - m.y).abs() < 50) {
        m.collected = true;
        if (!_collectedThisRun.contains(m.id)) _collectedThisRun.add(m.id);
      }
    }

        // ======================================================================
    // ИСПРАВЛЕНИЕ ОШИБКИ №2: ЧЕСТНЫЕ ХИТБОКСЫ СФЕР И ЗАЩИТА ОТ ДВОЙНОГО КЛИКА
    // ======================================================================
    if (_isPressing && !_player.isGrounded) {
      final double playerCenterX = _player.x + _player.size / 2;
      final double playerCenterY = _player.y + _player.size / 2;
      
      for (var orb in _orbs) {
        if (orb.collected) continue;
        // Ограничиваем зону проверки по X для оптимизации
        if (orb.x < _player.x - 50 || orb.x > _player.x + 100) continue;

        double distX = (playerCenterX - orb.x).abs();
        double distY = (playerCenterY - orb.y).abs();
        
        // ИСПРАВЛЕНИЕ: Сузили радиус с 70 до 45 пикселей. 
        // Теперь кубик не активирует верхнюю сферу раньше времени!
        if (distX < 45 && distY < 45) {
          orb.collected = true;
          
          // Проверяем инверсию гравитации строго в момент тапа
          if (_isGravityInverted) {
            _player.vy = 14.5; // Толкаем вниз, если куб на потолке
          } else {
            _player.vy = -14.5; // Толкаем вверх, если куб на полу
          }
          
          _player.isGrounded = false;
          _isPressing = false; // ИСПРАВЛЕНИЕ: Гарантированно сбрасываем нажатие, блокируя ложный двойной прыжок!
          break; // Выходим из цикла, обрабатывая строго ОДИН орб за один тап
        }
      }
    }

    // ИСПРАВЛЕНИЕ: Физика шипов (Возвращены оригинальные размеры и честная смерть)
    for (var obs in _obstacles) {
      if (obs.type != 'spike' && obs.type != 'spike_mark' && obs.type != 'spike_upside') continue;
      if (obs.x < _player.x - 50 || obs.x > _player.x + 800) continue;

      bool isSpikeUpsideDown = (obs.type == 'spike_upside' || (_currentLevel == 4 && _isGravityInverted && obs.y < 200));
      
      // Оригинальный размер хитбокса Geometry Dash
      if (_player.x + _player.size > obs.x + 8 && _player.x < obs.x + 22) {
        if (!isSpikeUpsideDown) {
          if (_player.y + _player.size > obs.y - 30 && _player.y < obs.y) {
            if (!_isGodMode) { _gameOver(); return; }
          }
        } else {
          if (_player.y < obs.y + 30 && _player.y + _player.size > obs.y) {
            if (!_isGodMode) { _gameOver(); return; }
          }
        }
      }
    }

    // ИСПРАВЛЕНИЕ: Железобетонная физика платформ (Считывает реальную высоту obs.h кастомного уровня)
    for (var obs in _obstacles) {
      if (obs.type != 'platform' && obs.type != 'portal_ship' && obs.type != 'portal_grav') continue;
      double width = obs.w > 0 ? obs.w : 30.0;
      double height = obs.h > 0 ? obs.h : 30.0; // Считываем высоту блока динамически!
      if (obs.x + width < _player.x - 100 || obs.x > _player.x + 800) continue;

            // ИСПРАВЛЕНИЕ: Портал Самолётика работает на всю высоту 400px и инвертирует режим при повторном входе
      if (obs.type == 'portal_ship') {
        if (_player.x + _player.size > obs.x && _player.x < obs.x + 40) {
          if (_player.y + _player.size > obs.y && _player.y < obs.y + 400) {
            // Чтобы режим не мигал каждый кадр, пока куб внутри портала, переключаем только при входе
            if (_player.x >= obs.x && _player.x <= obs.x + 8) {
              _player.isShip = !_player.isShip; // Первый портал включит самолёт, второй — выключит!
              _player.vy = 0;
            }
          }
        }
        continue; 
      }
      
           // ИСПРАВЛЕНИЕ НЕДОЧЁТА: Портал гравитации на 4 уровне теперь вытянут на 400px, 
      // чтобы кубик на 67% прогресса гарантированно падал вниз к монетке!
      if (obs.type == 'portal_grav') {
        double portalHeight = (_currentLevel == 4) ? 400.0 : (obs.h > 0 ? obs.h : 120.0);
        if (_player.x + _player.size > obs.x && _player.x < obs.x + 40) {
          if (_player.y + _player.size > obs.y && _player.y < obs.y + portalHeight) {
            if (_currentLevel == 5) {
              // Кастомный уровень: инвертирует режим при повторном входе
              if (_player.x >= obs.x && _player.x <= obs.x + 8) {
                _isGravityInverted = !_isGravityInverted;
                _player.vy = 0;
              }
            } else {
              // Стандартный 4 уровень: активирует триггеры по ходу прохождения
              if (_player.x >= obs.x && _player.x <= obs.x + 8) {
                _isGravityInverted = false; // Возвращаем кубик на обычную гравитацию пола!
              }
            }
          }
        }
        continue; 
      }

      bool stoodOnPlatform = false;

      // Приземление/Прилипание к платформе
      if (_player.x + _player.size > obs.x + 4 && _player.x < obs.x + width - 4) {
        if (_isGravityInverted) {
          // Инверсия: цепляемся за нижнюю грань платформы (obs.y + height)
          if (_player.vy <= 0 && _player.y <= obs.y + height && _player.y >= obs.y + height - 25) {
            _player.y = obs.y + height;
            _player.vy = 0;
            _player.isGrounded = true;
            stoodOnPlatform = true;
          }
        } else {
          // Обычный режим: приземляемся сверху на блок
          if (_player.vy >= 0 && _player.y + _player.size >= obs.y && _player.y + _player.size <= obs.y + 25) {
            _player.y = obs.y - _player.size;
            _player.vy = 0;
            _player.isGrounded = true;
            stoodOnPlatform = true;
          }
        }
      }

      if (stoodOnPlatform) continue;

      // Жесткий удар в торец (бок) платформы — МГНОВЕННАЯ СМЕРТЬ И ОТКАТ ПРОВАЛИВАНИЙ!
      if (!_isGodMode) {
        if (_player.x + _player.size > obs.x && _player.x < obs.x + width) {
          if (_player.y + _player.size > obs.y + 6 && _player.y < obs.y + height - 6) {
            _gameOver();
            return;
          }
        }
      }
    }


    // Вращение куба в воздухе...
    if (_currentLevel == 4) {
      if (!_player.isGrounded) {
        _player.rotation += _isGravityInverted ? -0.08 : 0.08;
      } else {
        _player.rotation = (_player.rotation / (math.pi / 2)).round() * (math.pi / 2);
      }
    } else {
      if (!_player.isShip) {
        if (!_player.isGrounded) _player.rotation += 0.08;
        else _player.rotation = (_player.rotation / (math.pi / 2)).round() * (math.pi / 2);
      }
    }
    // ==========================================
    // ЭТАП 4: ЛОГИКА ФИНАЛЬНОГО ПОРТАЛА И ИСКР
    // ==========================================
    double portalTargetY = _floorY - 150; 

    // Генерируем зеленые искры из портала, если игрок приблизился к финишу
    if (_player.x >= _levelLength - 1000 && _player.x < _levelLength + 300) {
      var rand = math.Random();
      if (rand.nextDouble() < 0.4) {
        double pAngle = rand.nextDouble() * math.pi * 2;
        double pSpeed = 1 + rand.nextDouble() * 3;
        _portalParticles.add(DeathParticle(
          x: _levelLength + (rand.nextDouble() * 40 - 20),
          y: portalTargetY + (rand.nextDouble() * 160 - 80),
          vx: -math.cos(pAngle).abs() * pSpeed - 2, 
          vy: math.sin(pAngle) * pSpeed,
          size: 4 + rand.nextDouble() * 4,
          alpha: 1.0,
        ));
      }
    }

    // Физика движения искр финиша
    for (int i = _portalParticles.length - 1; i >= 0; i--) {
      var p = _portalParticles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.alpha -= 0.02;
      if (p.alpha <= 0) _portalParticles.removeAt(i);
    }

    // АВТОЗАТЯГИВАНИЕ: Если игрок подлетает к порталу ближе чем на 250px
    if (_player.x >= _levelLength - 250 && _isPlaying) {
      _player.vy = 0;
      _player.isGrounded = false;
      _player.y += (portalTargetY - (_player.y + _player.size / 2)) * 0.12; 
    }

            // ==========================================
    // ЭТАП 5: ПРОВЕРКА ФИНАЛА И СОХРАНЕНИЕ
    // ==========================================
    if (_player.x >= _levelLength) {
      _gameTimer?.cancel();
      _isPlaying = false;
      _portalParticles.clear(); 
      
      if (_currentLevel == 1) {
        _maxProgress = 100; 
        _prefs.setInt('cybics_max_progress', 100);
        // Сохраняем медаль 1 уровня на финише
        for (var id in _collectedThisRun) {
          if (id < _savedMedals1.length) _savedMedals1[id] = true;
        }
        _prefs.setString('cybics_medals_1', jsonEncode(_savedMedals1));
      } else if (_currentLevel == 2) {
        _maxProgress2 = 100; 
        _prefs.setInt('cybics_max_progress_2', 100);
        for (var id in _collectedThisRun) {
          if (id < _savedMedals2.length) _savedMedals2[id] = true;
        }
        _prefs.setString('cybics_medals_2', jsonEncode(_savedMedals2));
      } else if (_currentLevel == 3) {
        _maxProgress3 = 100; 
        _prefs.setInt('cybics_max_progress_3', 100);
        for (var id in _collectedThisRun) {
          if (id < _savedMedals3.length) _savedMedals3[id] = true;
        }
        _prefs.setString('cybics_medals_3', jsonEncode(_savedMedals3));
      } else if (_currentLevel == 4) {
        _maxProgress4 = 100; 
        _prefs.setInt('cybics_max_progress_4', 100);
        for (var id in _collectedThisRun) {
          if (id < _savedMedals4.length) _savedMedals4[id] = true;
        }
        _prefs.setString('cybics_medals_4', jsonEncode(_savedMedals4));
      }
      _stopAllLevelTracks();

      if (mounted) {
        setState(() { 
          _showVictory = true; 
        });
      }
    }
  if (_player.y > _gameHeight) {
      if (!_isGodMode) { _gameOver(); return; }
    }
  } // <--- Это закрывающая фигурная скобка самого метода _updatePhysics()



 
      void _gameOver() {
    _gameTimer?.cancel();
    _retryTimer?.cancel(); 
    _playDeathSound();
    bool isNewRecord = false;

    // 1. Сначала рассчитываем текстовый рекорд % прохождения для плашек
    if (_currentLevel == 1 && _currentProgress > _maxProgress && _currentProgress < 100) {
      _maxProgress = _currentProgress; _prefs.setInt('cybics_max_progress', _maxProgress); isNewRecord = true;
    } else if (_currentLevel == 2 && _currentProgress > _maxProgress2 && _currentProgress < 100) {
      _maxProgress2 = _currentProgress; _prefs.setInt('cybics_max_progress_2', _maxProgress2); isNewRecord = true;
    } else if (_currentLevel == 3 && _currentProgress > _maxProgress3 && _currentProgress < 100) {
      _maxProgress3 = _currentProgress; _prefs.setInt('cybics_max_progress_3', _maxProgress3); isNewRecord = true;
    } else if (_currentLevel == 4 && _currentProgress > _maxProgress4 && _currentProgress < 100) {
      _maxProgress4 = _currentProgress; _prefs.setInt('cybics_max_progress_4', _maxProgress4); isNewRecord = true;
    } else if (_currentLevel == 5 && _currentEditingLevel != null) {
      if (_currentProgress > _currentEditingLevel!.progress) {
        _currentEditingLevel!.progress = _currentProgress;
        _saveCustomLevelsToPrefs();
        isNewRecord = true;
      }
    }

    // 2. ИСПРАВЛЕНИЕ ОШИБКИ №1: Монеты сгорают! Полностью очищаем список раунда.
    // Больше никаких проверок индексов _savedMedals, которые ломали и замораживали таймер смерти!
    _collectedThisRun.clear();

    if (!mounted) return; 
    // Дальше идет твой стандартный блок setState(() { _isPlaying = false; ... }) с добавлением частиц взрыва... 
    setState(() {
      _isPlaying = false;
      _trailParticles.clear();
      _deathParticles.clear();

      var rand = math.Random();
      for (int i = 0; i < 16; i++) {
        double angle = rand.nextDouble() * math.pi * 2;
        double speed = 2 + rand.nextDouble() * 5;
        _deathParticles.add(DeathParticle(
          x: _player.x + _player.size / 2,
          y: _player.y + _player.size / 2,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
          size: 5 + rand.nextDouble() * 6,
          alpha: 1.0,
        ));
      }
    });

    // ИСПРАВЛЕНИЕ: Анимация частиц обновляет холст через Нотификатор. Глобальный setState() больше не вызывается!
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) { timer.cancel(); return; }
      
      for (var p in _deathParticles) {
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.15;
        p.alpha -= 0.03;
        if (p.alpha < 0) p.alpha = 0;
      }
      _gameTickNotifier.value++; // Даем команду холсту перерисовать частицы смерти
    });

    _retryTimer = Timer(const Duration(milliseconds: 350), () {
      _gameTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _deathParticles.clear();
      });
      _continueGameOverLogic(isNewRecord);
    });
  }


    void _continueGameOverLogic(bool isNewRecord) {
    if (isNewRecord) {
      if (!mounted) return; 
      setState(() { _showNewRecord = true; });
      
      // Задержка 1200мс для рекорда, чтобы рассмотреть плашку
      _retryTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        _registerNewAttempt();
        _startLevel();
      });
    } else {
      // ИСПРАВЛЕНИЕ ОШИБКИ №1: Добавлена микро-пауза в 300мс для обычных смертей.
      // Теперь кубик не телепортируется мгновенно, звук взрыва успевает доиграть,
      // а переменная _retryTimer контролируется движком и не вызывает скрытых сбоев!
      _retryTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _registerNewAttempt();
        _startLevel();
      });
    }
  }

  void _registerNewAttempt() {
    if (!mounted) return; 
    setState(() {
      _currentRunAttempts++; // Внутри текущего забега счётчик растёт всегда
      
      if (!_isGodMode) {
        // ТВОЯ ЛОГИКА + ИСПРАВЛЕНИЕ ОПЕЧАТКИ: Теперь 3-й уровень сохраняется строго в cybics_attempts_3
        if (_currentLevel == 1 && _maxProgress < 100) { _attempts1++; _prefs.setInt('cybics_attempts_1', _attempts1); }
        if (_currentLevel == 2 && _maxProgress2 < 100) { _attempts2++; _prefs.setInt('cybics_attempts_2', _attempts2); }
        if (_currentLevel == 3 && _maxProgress3 < 100) { _attempts3++; _prefs.setInt('cybics_attempts_3', _attempts3); } // ИСПРАВЛЕНО (было attempts_4)
        if (_currentLevel == 4 && _maxProgress4 < 100) { _attempts4++; _prefs.setInt('cybics_attempts_4', _attempts4); }
      }
    });
  }


  // --- ИНТЕРФЕЙС ЭКРАНОВ (ВЕРСТКА FLUTTER) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _buildCurrentScreen(),
      ),
    );
  }

      Widget _buildCurrentScreen() {
    switch (_state) {
      case GameState.mainMenu:
        return _buildMainMenu();
      case GameState.levelsMenu:
        return _buildLevelsMenu();
      case GameState.settingsMenu:
        return _buildSettingsMenu();
      case GameState.gameplay:
        return _buildGameplay();
      case GameState.customLevelsMenu:
        return _buildCustomLevelsMenu();
      // Перенаправляем на новое меню скачанных карт
      case GameState.downloadedLevelsMenu:
        return _buildDownloadedLevelsMenu();
      case GameState.searchMenu:
        return _buildSearchMenu();
      case GameState.searchResultsMenu:
        return _buildSearchResultsMenu();
      case GameState.createdLevelsMenu:
        return _buildCreatedLevelsMenu();
      case GameState.newLevelMenu:
        return _buildNewLevelMenu();
        // НАШИ НОВЫЕ ЭКРАНЫ РЕДАКТОРА (ШАГ 1):
      case GameState.editor:
        return _buildLevelEditor();
      case GameState.editorConsole:
        return _buildEditorConsole();
      case GameState.editorTracksMenu:
        return _buildEditorTracksMenu();
    }
  }



    Widget _buildMainMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              if (_isGodMode) return;
              _titleClicks++;
              if (_titleClicks >= 10) {
                setState(() { _isGodMode = true; });
                _menuPlayer.play(AssetSource('god.mp3')); 
              }
            },
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.03).animate(_pulseController),
              child: Text(
                _isGodMode ? 'GOD MODE' : 'CYBICS',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  color: _isGodMode ? const Color(0xFFE11D48) : const Color(0xFF00F2FE),
                  shadows: [
                    Shadow(
                      color: _isGodMode ? const Color(0xFFF43F5E).withOpacity(0.8) : const Color(0xFF00F2FE).withOpacity(0.6),
                      blurRadius: 20,
                    )
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          _buildBtn('Играть', () {
            setState(() { _state = GameState.levelsMenu; });
          }),
          // НАША НОВАЯ КНОПКА: Переводит в меню кастомных уровней
          _buildBtn('Другие уровни', () {
            setState(() { _state = GameState.customLevelsMenu; });
          }),
          _buildBtn('Настройки', () {
            setState(() { _state = GameState.settingsMenu; });
          }, isSecondary: true),
        ],
      ),
    );
  }


      Widget _buildLevelsMenu() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 20.0),
          child: Text('Выбор уровня', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLevelCard(1, 'Start Level', _maxProgress, _attempts1, _savedMedals1, const Color(0xFF3B82F6)),
            const SizedBox(width: 15),
            _buildLevelCard(2, 'NOT BAD', _maxProgress2, _attempts2, _savedMedals2, const Color(0xFFA855F7)),
            const SizedBox(width: 15),
            _buildLevelCard(3, 'TRY AND CRY', _maxProgress3, _attempts3, _savedMedals3, const Color(0xFFEF4444)),
            const SizedBox(width: 15),
            _buildLevelCard(4, 'SPACE SHIFT', _maxProgress4, _attempts4, _savedMedals4, const Color(0xFFFACC15)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: _buildBtn('Назад', () {
            setState(() { _state = GameState.mainMenu; });
          }, isSecondary: true, minWidth: 200),
        )
      ],
    );
  }

  Widget _buildLevelCard(int lvl, String name, int progress, int attempts, List<bool> medals, Color borderColor) {
    return GestureDetector(
      onTap: () {
        _currentLevel = lvl;
        _launchGameplay();
      },
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: borderColor)),
                ),
                Text('П: $attempts', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: medals.map((collected) => Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: Opacity(opacity: collected ? 1.0 : 0.2, child: const Text('🥇', style: TextStyle(fontSize: 14))),
              )).toList(),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(height: 14, color: const Color(0xFF334155)),
                  FractionallySizedBox(
                    widthFactor: progress / 100.0,
                    child: Container(height: 14, color: borderColor),
                  ),
                  Center(child: Text('$progress%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

    Widget _buildDownloadedLevelsMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 15),
          const Text(
            'Скачанные уровни', 
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
          const SizedBox(height: 15),
          
          // Твой большой квадрат в центре экрана
          Container(
            width: 450,
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B), // Темный фон в стиле карточек
              border: Border.all(color: const Color(0xFF06B6D4), width: 2), // Бирюзовая неоновая рамка
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Нет скачанных уровней', 
                style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500)
              ),
            ),
          ),
          
          const SizedBox(height: 15),
          
          // Кнопка возврата в предыдущее меню "Другие уровни"
          _buildBtn('Назад', () {
            setState(() { _state = GameState.customLevelsMenu; });
          }, minWidth: 180),
        ],
      ),
    );
  }

   Widget _buildSearchMenu() {
    return Center(
      // ИСПРАВЛЕНИЕ: Обернули в SingleChildScrollView. Ошибка "bottom overflowed" полностью исчезнет!
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Поиск уровней', 
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5)
            ),
            const SizedBox(height: 25),
            
            SizedBox(
              width: 400,
              child: TextField(
                controller: _searchController,
                autofocus: false, 
                maxLength: 50, // ИСПРАВЛЕНИЕ: Максимально можно набрать 50 символов
                style: const TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: "", // Скрываем некрасивый стандартный счетчик под полем ввода
                  hintText: 'название или номер уровня',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16), 
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFF334155), width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 2), 
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            _buildBtn('Найти', () {
              FocusScope.of(context).unfocus();
              setState(() { _state = GameState.searchResultsMenu; });
            }),
            
            const SizedBox(height: 10),
            
            _buildBtn('Назад', () {
              FocusScope.of(context).unfocus();
              setState(() { _state = GameState.customLevelsMenu; });
            }, isSecondary: true, minWidth: 180),
          ],
        ),
      ),
    );
  }

    Widget _buildSearchResultsMenu() {
    final List<Color> diffColors = [
      const Color(0xFF38BDF8), const Color(0xFF4ADE80), const Color(0xFFFACC15),
      const Color(0xFFEA580C), const Color(0xFFEF4444), const Color(0xFF8B5CF6)
    ];

    String query = _searchController.text.trim().toLowerCase();
    
    List<CustomLevel> foundLevels = _myCreatedLevels.where((lvl) {
      return lvl.name.toLowerCase().contains(query) || lvl.id.toLowerCase() == query;
    }).toList();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 15),
          Text(
            'Результаты для: "${_searchController.text}"', 
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey)
          ),
          const SizedBox(height: 15),
          
          Container(
            width: 450,
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              border: Border.all(color: const Color(0xFF06B6D4), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: foundLevels.isEmpty
                ? const Center(
                    child: Text(
                      'Уровней не найдено', 
                      style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500)
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: foundLevels.length,
                    itemBuilder: (context, index) {
                      final lvl = foundLevels[index];
                      
                      // ИСПРАВЛЕНИЕ: Тап по найденной плашке запускает игру со всеми постройками!
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentEditingLevel = lvl;
                            _currentLevel = 5;
                            _customLevelLaunchSource = GameState.searchResultsMenu; // Источник — Поиск!
                            
                            _obstacles = List.from(lvl.obstacles);
                            _orbs = List.from(lvl.orbs);
                            _medals = List.from(lvl.medals);
                            
                            _launchGameplay();
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lvl.name, 
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    Text('Номер: ${lvl.id}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Stack(
                                        children: [
                                          Container(height: 6, color: const Color(0xFF334155)),
                                          FractionallySizedBox(
                                            widthFactor: lvl.progress / 100.0,
                                            child: Container(height: 6, color: diffColors[lvl.difficultyIndex]),
                                          ),
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: CustomPaint(
                                  painter: DifficultyShapePainter(
                                    difficultyIndex: lvl.difficultyIndex, 
                                    color: diffColors[lvl.difficultyIndex]
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          const SizedBox(height: 15),
          
          _buildBtn('Назад', () {
            setState(() { _state = GameState.searchMenu; });
          }, minWidth: 180),
        ],
      ),
    );
  }


    Widget _buildCreatedLevelsMenu() {
    final List<Color> diffColors = [
      const Color(0xFF38BDF8), const Color(0xFF4ADE80), const Color(0xFFFACC15),
      const Color(0xFFEA580C), const Color(0xFFEF4444), const Color(0xFF8B5CF6)
    ];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          const Text(
            'Созданные уровни', 
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
          const SizedBox(height: 15),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 420, 
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  border: Border.all(color: const Color(0xFF06B6D4), width: 2), 
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _myCreatedLevels.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет созданных уровней', 
                          style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500)
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _myCreatedLevels.length,
                        itemBuilder: (context, index) {
                          final lvl = _myCreatedLevels[index];
                          
                          // ИСПРАВЛЕНИЕ: Обернули плашку уровня в GestureDetector для фичи "Нажми и Играй"
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _currentEditingLevel = lvl;
                                _currentLevel = 5; // Условный ID, обозначающий кастомную карту в движке
                                _customLevelLaunchSource = GameState.createdLevelsMenu; // ИСПРАВЛЕНИЕ: Источник — Созданные!
                                
                                // Мгновенно копируем объекты из файла уровня в глобальные списки физики игры
                                _obstacles = List.from(lvl.obstacles);
                                _orbs = List.from(lvl.orbs);
                                _medals = List.from(lvl.medals);
                                
                                _launchGameplay(); // Запускаем кубик в игру!
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: Row(
                                children: [
                                  // Левый блок кнопок управления
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildBtn('Редактировать', () {
                                        setState(() {
                                          _currentEditingLevel = lvl;
                                          _editorCameraX = 0;
                                          _undoHistory.clear();
                                          _redoHistory.clear();
                                          _state = GameState.editor;
                                        });
                                      }, isSecondary: true, minWidth: 125),
                                      const SizedBox(height: 4),
                                      _buildBtn('Удалить', () {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              backgroundColor: const Color(0xFF1E293B),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              title: const Text('Удаление', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                                              content: const Text('Вы точно хотите удалить этот уровень?', style: TextStyle(color: Colors.white)),
                                              actions: [
                                                TextButton(
                                                  child: const Text('ОТМЕНА', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                                  onPressed: () => Navigator.of(context).pop(),
                                                ),
                                                TextButton(
                                                  child: const Text('ДА, УДАЛИТЬ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                                                  onPressed: () {
                                                    setState(() {
                                                      _myCreatedLevels.removeAt(index);
                                                      _saveCustomLevelsToPrefs();
                                                    });
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      }, isSecondary: true, minWidth: 125),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  
                                  // Центральный блок текста (Имя, Номер, Прогресс-бар)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lvl.name, 
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Номер: ${lvl.id}', 
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 4),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Stack(
                                            children: [
                                              Container(height: 10, color: const Color(0xFF334155)),
                                              FractionallySizedBox(
                                                widthFactor: lvl.progress / 100.0,
                                                child: Container(height: 10, color: diffColors[lvl.difficultyIndex]),
                                              ),
                                            ],
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  
                                  // Правый блок: иконка-круг сложности
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CustomPaint(
                                      painter: DifficultyShapePainter(
                                        difficultyIndex: lvl.difficultyIndex, 
                                        color: diffColors[lvl.difficultyIndex]
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              
              const SizedBox(width: 20), 
              
                            _buildBtn('Добавить\nуровень', () {
                _levelNameController.clear(); 
                setState(() { 
                  _selectedDifficultyIndex = 0; 
                  _state = GameState.newLevelMenu; 
                });
              }, isSecondary: true, minWidth: 140),
            ],
          ),
          
          const SizedBox(height: 15),
          
          _buildBtn('Назад', () {
            setState(() { _state = GameState.customLevelsMenu; });
          }, minWidth: 180),
        ],
      ),
    );
  }

          


    // ======================================================================
  // ИСПРАВЛЕННЫЙ И ПОДРОБНЫЙ ШАГ 5: ИНТЕРФЕЙС РЕДАКТОРА
  // ======================================================================

  void _takeSnapshot() {
    if (_currentEditingLevel == null) return;
    _undoHistory.add(jsonEncode(_currentEditingLevel!.toJson()));
    _redoHistory.clear();
  }

      Widget _buildLevelEditor() {
    bool canUndo = _undoHistory.isNotEmpty;
    bool canRedo = _redoHistory.isNotEmpty;

    return Stack(
      children: [
                // ИСПРАВЛЕНИЕ: Свободный скролл пальцами по двум осям (onPanUpdate) и учет Y при тапе
        Positioned.fill(
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                // Двигаем экран влево-вправо
                _editorCameraX = (_editorCameraX - details.delta.dx).clamp(0, _levelLength - 800);
                // Двигаем экран вверх-вниз
                _editorCameraY = (_editorCameraY - details.delta.dy).clamp(-300.0, 300.0);
              });
            },
                        onTapDown: (details) {
              if (_currentEditingLevel == null || _isPaused) return;

              RenderBox renderBox = context.findRenderObject() as RenderBox;
              double currentScreenHeight = renderBox.size.height;
              double scale = currentScreenHeight / _gameHeight;

              double rawX = details.localPosition.dx / scale;
              double rawY = details.localPosition.dy / scale;

              if (rawY >= _floorY || rawY < 60) return;

              double step = 30.0;
              
              // Координата X остается прежней (с учетом горизонтального скролла)
              double worldX = (((rawX + _editorCameraX) / step).floor() * step);
              
              // ======================================================================
              // ИСПРАВЛЕНИЕ: МАТЕМАТИКА МАГНИТНОЙ СЕТКИ ОТТАЛКИВАЕТСЯ СТРОГО ОТ ПОЛА!
              // ======================================================================
              // Мы берем абсолютную координату клика с учетом вертикальной камеры,
              // вычитаем её из линии пола (500) и округляем по шагу 30 вверх.
              // Это гарантирует, что первый ряд над платформой будет целым (ровно 30px),
              // а постройки встанут строго НА синюю линию горизонта без проваливаний!
              double relativeYFromFloor = (_floorY - (rawY + _editorCameraY));
              double snappedRelativeY = (relativeYFromFloor / step).floor() * step;
              double worldY = _floorY - snappedRelativeY;

              _takeSnapshot();

              setState(() {
                if (_isEraserMode) {
                  bool removed = false;
                  for (int i = _currentEditingLevel!.obstacles.length - 1; i >= 0; i--) {
                    var obs = _currentEditingLevel!.obstacles[i];
                    double width = obs.w > 0 ? obs.w : 30.0;
                    double height = obs.h > 0 ? obs.h : 30.0;
                    if (worldX >= obs.x && worldX < obs.x + width && worldY >= obs.y && worldY < obs.y + height) {
                      _currentEditingLevel!.obstacles.removeAt(i);
                      removed = true;
                      break;
                    }
                  }
                  if (!removed) {
                    for (int i = _currentEditingLevel!.orbs.length - 1; i >= 0; i--) {
                      var orb = _currentEditingLevel!.orbs[i];
                      if ((worldX - orb.x).abs() < 30 && (worldY - orb.y).abs() < 30) {
                        _currentEditingLevel!.orbs.removeAt(i);
                        removed = true;
                        break;
                      }
                    }
                  }
                  if (!removed) {
                    for (int i = _currentEditingLevel!.medals.length - 1; i >= 0; i--) {
                      var m = _currentEditingLevel!.medals[i];
                      if ((worldX - m.x).abs() < 30 && (worldY - m.y).abs() < 30) {
                        _currentEditingLevel!.medals.removeAt(i);
                        removed = true;
                        break;
                      }
                    }
                  }
                  if (!removed && _undoHistory.isNotEmpty) _undoHistory.removeLast();
                } 
                else {
                  if (_editorSelectedTool.startsWith('platform')) {
                    double width = 60;
                    if (_editorSelectedTool == 'platform_1') width = 30;
                    if (_editorSelectedTool == 'platform_2') width = 60;
                    if (_editorSelectedTool == 'platform_3') width = 120;
                    if (_editorSelectedTool == 'platform_4') width = 210;
                    if (_editorSelectedTool == 'platform_5') width = 360;

                    _currentEditingLevel!.obstacles.add(Obstacle(type: 'platform', x: worldX, y: worldY, w: width, h: 30));
                  } 
                  else if (_editorSelectedTool == 'spike_normal') {
                    _currentEditingLevel!.obstacles.add(Obstacle(type: 'spike', x: worldX, y: worldY + 30));
                  } 
                  else if (_editorSelectedTool == 'spike_mark') {
                    _currentEditingLevel!.obstacles.add(Obstacle(type: 'spike_mark', x: worldX, y: worldY + 30));
                  } 
                  else if (_editorSelectedTool == 'spike_upside') {
                    _currentEditingLevel!.obstacles.add(Obstacle(type: 'spike_upside', x: worldX, y: worldY));
                  } 
                  else if (_editorSelectedTool == 'orb_1') {
                    _currentEditingLevel!.orbs.add(GameOrb(x: worldX + 15, y: worldY + 15));
                  } 
                  else if (_editorSelectedTool == 'portal_ship') {
                    // ИСПРАВЛЕНИЕ: Портал теперь стоит от Y=100 до пола и имеет высоту 400px
                    _currentEditingLevel!.obstacles.add(Obstacle(type: 'portal_ship', x: worldX, y: 100, w: 40, h: 400));
                  } 
                  else if (_editorSelectedTool == 'portal_grav') {
                    // ИСПРАВЛЕНИЕ: Портал инверсии тоже вытянут на 400px
                    _currentEditingLevel!.obstacles.add(Obstacle(type: 'portal_grav', x: worldX, y: 100, w: 40, h: 400));
                  }  
                  else if (_editorSelectedTool == 'medal') {
                    if (_currentEditingLevel!.medals.length < 3) {
                      int nextId = _currentEditingLevel!.medals.length;
                      _currentEditingLevel!.medals.add(Medal(id: nextId, x: worldX + 15, y: worldY + 15));
                    } else {
                      if (_undoHistory.isNotEmpty) _undoHistory.removeLast();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Достигнут лимит: Максимум 3 медали на уровень!'))
                      );
                    }
                  }
                }
              });
            },
            child: CustomPaint(
              // ИСПРАВЛЕНИЕ: Передаем _editorCameraY в отрисовщик холста, чтобы сетка сдвигалась по вертикали!
              painter: EditorBackgroundPainter(
                cameraX: _editorCameraX, 
                cameraY: _editorCameraY, // Добавили параметр
                floorY: _floorY, 
                gameHeight: _gameHeight, 
                levelLength: _levelLength,
                currentLevelData: _currentEditingLevel,
              ),
            ),
          ),
        ),

        Positioned(
          top: 15,
          left: 15,
          child: Column(
            children: [
              // ИСПРАВЛЕНИЕ: backgroundColor перенесен в style: IconButton.styleFrom
              IconButton(
                icon: Icon(Icons.undo, size: 36, color: canUndo ? const Color(0xFF22C55E) : Colors.grey),
                style: IconButton.styleFrom(backgroundColor: canUndo ? Colors.black45 : Colors.black12),
                onPressed: !canUndo ? null : () {
                  setState(() {
                    _redoHistory.add(jsonEncode(_currentEditingLevel!.toJson()));
                    String snapshot = _undoHistory.removeLast();
                    _currentEditingLevel = CustomLevel.fromJson(jsonDecode(snapshot));
                  });
                },
              ),
              const SizedBox(height: 10),
              IconButton(
                icon: Icon(Icons.redo, size: 36, color: canRedo ? const Color(0xFF22C55E) : Colors.grey),
                style: IconButton.styleFrom(backgroundColor: canRedo ? Colors.black45 : Colors.black12),
                onPressed: !canRedo ? null : () {
                  setState(() {
                    _undoHistory.add(jsonEncode(_currentEditingLevel!.toJson()));
                    String snapshot = _redoHistory.removeLast();
                    _currentEditingLevel = CustomLevel.fromJson(jsonDecode(snapshot));
                  });
                },
              ),
            ],
          ),
        ),

        Positioned(
          top: 15,
          right: 15,
          child: Column(
            children: [
              IconButton(
                icon: const Icon(Icons.pause, size: 34, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () { setState(() { _isPaused = true; }); },
              ),
              const SizedBox(height: 10),
              IconButton(
                icon: Icon(Icons.architecture, size: 34, color: _isBuildDockOpen ? const Color(0xFF00F2FE) : Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () {
                  setState(() { 
                    _isBuildDockOpen = !_isBuildDockOpen;
                    if (_isBuildDockOpen) _isEraserMode = false;
                  });
                },
              ),
              const SizedBox(height: 10),
              IconButton(
                icon: const Icon(Icons.terminal, size: 32, color: Colors.amber),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () {
                  _consoleController.clear();
                  setState(() { _state = GameState.editorConsole; });
                },
              ),
              const SizedBox(height: 10),
              IconButton(
                icon: Icon(Icons.auto_fix_normal, size: 32, color: _isEraserMode ? Colors.red : Colors.white),
                style: IconButton.styleFrom(backgroundColor: _isEraserMode ? Colors.red.withOpacity(0.3) : Colors.black54),
                onPressed: () {
                  setState(() { 
                    _isEraserMode = !_isEraserMode; 
                    if (_isEraserMode) _isBuildDockOpen = false;
                  });
                },
              ),
            ],
          ),
        ),

        if (_isEraserMode)
          Positioned(
            top: 20,
            left: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.red.withOpacity(0.8),
              child: const Text('РЕЖИМ СТЁРКИ: Нажмите на объект для удаления', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
            ),
          ),

        if (_isBuildDockOpen) _buildEditorBuildDock(),
        if (_isPaused) _buildEditorPauseOverlay(),
      ],
    );
  }

  Widget _buildEditorBuildDock() {
    final List<Map<String, String>> tools = [
      {'id': 'platform_1', 'name': 'Платформа XS'},
      {'id': 'platform_2', 'name': 'Платформа S'},
      {'id': 'platform_3', 'name': 'Платформа M'},
      {'id': 'platform_4', 'name': 'Платформа L'},
      {'id': 'platform_5', 'name': 'Платформа XL'},
      {'id': 'spike_normal', 'name': 'Шип обычный'},
      {'id': 'spike_mark', 'name': 'Шип с [!]'},
      {'id': 'spike_upside', 'name': 'Шип перевёрнутый'},
      {'id': 'orb_1', 'name': 'Сфера прыжка'},
      {'id': 'portal_ship', 'name': 'Портал Корабля'},
      {'id': 'portal_grav', 'name': 'Портал Инверсии'},
      {'id': 'medal', 'name': 'Медаль (Макс 3)'},
    ];

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.95),
          border: const Border(top: BorderSide(color: Color(0xFF06B6D4), width: 2)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: tools.map((tool) {
              bool isSelected = _editorSelectedTool == tool['id'];
              return GestureDetector(
                onTap: () { setState(() { _editorSelectedTool = tool['id']!; }); },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.all(8),
                  width: 120,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF1E1B4B),
                    border: Border.all(color: isSelected ? const Color(0xFF00F2FE) : Colors.transparent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      tool['name']!, 
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF00F2FE) : Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }


  Widget _buildEditorPauseOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ПАУЗА РЕДАКТОРА', style: TextStyle(fontSize: 36, color: Color(0xFF00F2FE), fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 20),
            
            _buildBtn('Продолжить', () { setState(() { _isPaused = false; }); }, minWidth: 280),
            
                        // 2. Сохранить изменения и сразу запустить тест уровня
            _buildBtn('Сохранить и Играть', () {
              _saveCustomLevelsToPrefs(); // Сохраняем на диск
              setState(() {
                _isPaused = false;
                _customLevelLaunchSource = GameState.editor; // После выхода вернемся в редактор
                _currentLevel = 5;
                
                // Переносим постройки в игровой движок
                _obstacles = List.from(_currentEditingLevel!.obstacles);
                _orbs = List.from(_currentEditingLevel!.orbs);
                _medals = List.from(_currentEditingLevel!.medals);
                
                _launchGameplay();
              });
            }, minWidth: 280),

            
            _buildBtn('Сохранить и Выйти', () {
              _saveCustomLevelsToPrefs();
              setState(() {
                _isPaused = false;
                _state = GameState.createdLevelsMenu;
              });
            }, minWidth: 280),
            
            _buildBtn('Сохранить изменения', () {
              _saveCustomLevelsToPrefs();
              setState(() { _isPaused = false; });
            }, minWidth: 280),
            
            _buildBtn('Выйти без сохранения', () {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Выход', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                    content: const Text('Вы точно хотите выйти без сохранения? Все последние изменения будут безвозвратно потеряны.', style: TextStyle(color: Colors.white)),
                    actions: [
                      TextButton(
                        child: const Text('ОТМЕНА', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      TextButton(
                        child: const Text('ДА, ВЫЙТИ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                        onPressed: () {
                          String? saved = _prefs.getString('cybics_custom_levels');
                          if (saved != null) {
                            List<dynamic> decoded = jsonDecode(saved);
                            _myCreatedLevels = decoded.map((item) => CustomLevel.fromJson(item)).toList();
                          }
                          Navigator.of(context).pop(); 
                          setState(() {
                            _isPaused = false;
                            _state = GameState.createdLevelsMenu; 
                          });
                        },
                      ),
                    ],
                  );
                },
              );
            }, isSecondary: true, minWidth: 280),
          ],
        ),
      ),
    );
  }

      Widget _buildEditorConsole() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Командная строка', 
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 1.5)
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 400,
              child: TextField(
                controller: _consoleController,
                style: const TextStyle(color: Colors.green, fontFamily: 'monospace', fontSize: 16),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Введите чит-код...',
                  hintStyle: TextStyle(color: Colors.green.withOpacity(0.3)),
                  filled: true,
                  fillColor: Colors.black,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), 
                    borderSide: const BorderSide(color: Colors.green)
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), 
                    borderSide: const BorderSide(color: Colors.amber, width: 2)
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildBtn('Активировать', () {
              String code = _consoleController.text.trim();
              if (code == "musicforlevelsunlock") {
                setState(() {
                  _areSecretTracksUnlocked = true; 
                  _state = GameState.editorTracksMenu; 
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный чит-код')));
              }
              FocusScope.of(context).unfocus();
            }),
            const SizedBox(height: 10),
            _buildBtn('Назад', () {
              FocusScope.of(context).unfocus();
              setState(() { _state = GameState.editor; }); 
            }, isSecondary: true, minWidth: 180),
          ],
        ),
      ),
    );
  }



  Widget _buildEditorTracksMenu() {
    final List<String> secretTracks = [
      'level5.mp3',
      'level6.mp3',
      'level7.mp3',
      'level8.mp3',
      'level9.mp3'
    ];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Выбор музыки уровня', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE))),
          const SizedBox(height: 15),
          Container(
            width: 400,
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B), 
              borderRadius: BorderRadius.circular(12), 
              border: Border.all(color: Colors.amber, width: 1.5)
            ),
            child: ListView.builder(
              itemCount: secretTracks.length,
              itemBuilder: (context, index) {
                bool isSelected = _currentEditingLevel?.selectedMusic == secretTracks[index];
                return ListTile(
                  title: Text(
                    'Аркадный трек №${index + 5} (${secretTracks[index]})', 
                    style: TextStyle(color: isSelected ? Colors.amber : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)
                  ),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.amber) : null,
                  onTap: () {
                    setState(() {
                      _currentEditingLevel?.selectedMusic = secretTracks[index];
                      _takeSnapshot(); 
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _buildBtn('Назад', () {
            setState(() { _state = GameState.editor; });
          }, minWidth: 180),
        ],
      ),
    );
  }

  Widget _buildNewLevelMenu() {
    // Список данных для наших сложностей
    final List<Map<String, dynamic>> difficulties = [
      {'name': 'Легко', 'color': const Color(0xFF38BDF8)},       // Голубой
      {'name': 'Средне', 'color': const Color(0xFF4ADE80)},      // Зелёный
      {'name': 'Затруднено', 'color': const Color(0xFFFACC15)},  // Жёлтый
      {'name': 'Сложно', 'color': const Color(0xFFEA580C)},
      {'name': 'Невозможно', 'color': const Color(0xFFEF4444)},  // Красный
      {'name': 'Кошмар', 'color': const Color(0xFF8B5CF6)},      // Фиолетовый
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Новый уровень', 
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5)
            ),
            const SizedBox(height: 15),
            
            // Строка ввода названия уровня
            SizedBox(
              width: 420,
              child: TextField(
                controller: _levelNameController,
                maxLength: 20, // Лимит 20 символов
                style: const TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: "", 
                  hintText: 'Введите название уровня...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFF334155), width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 2),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 15),
            const Text(
              'Выберите сложность уровня', 
              style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 15),
            
            // Горизонтальный ряд выбора сложностей
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                bool isSelected = _selectedDifficultyIndex == index;
                return GestureDetector(
                  onTap: () {
                    setState(() { _selectedDifficultyIndex = index; });
                  },
                  child: Container(
                    width: 105,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                      border: Border.all(
                        color: isSelected ? difficulties[index]['color'] : Colors.transparent, 
                        width: 2
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          difficulties[index]['name'], 
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold, 
                            color: isSelected ? difficulties[index]['color'] : Colors.grey
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Векторная отрисовка уникального смайлика-фигуры
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CustomPaint(
                            painter: DifficultyShapePainter(
                              difficultyIndex: index, 
                              color: difficulties[index]['color']
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            
                        const SizedBox(height: 25),
            
            // Ряд из трех кнопок
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. Кнопка Создать (пока null)
                _buildBtn('Создать', null, minWidth: 140), 
                
                const SizedBox(width: 15),
                
                // 2. ИСПРАВЛЕНИЕ: Кнопка Сохранить обёрнута в зелёный неон со свечением
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22C55E).withOpacity(0.4), // Зелёное свечение
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: _buildBtn('Сохранить', () {
                    String enteredName = _levelNameController.text.trim();
                    if (enteredName.isEmpty) enteredName = "Без названия";

                    var rand = math.Random();
                    String generatedId = "#${1000 + rand.nextInt(9000)}";

                    setState(() {
                      _myCreatedLevels.add(CustomLevel(
                        id: generatedId,
                        name: enteredName,
                        difficultyIndex: _selectedDifficultyIndex,
                      ));
                      _saveCustomLevelsToPrefs(); 
                      _state = GameState.createdLevelsMenu; 
                    });
                    FocusScope.of(context).unfocus(); 
                  }, minWidth: 140),
                ),
                
                const SizedBox(width: 15),
                
                // 3. Кнопка Отмена
                _buildBtn('Отмена', () {
                  FocusScope.of(context).unfocus();
                  setState(() { _state = GameState.createdLevelsMenu; });
                }, isSecondary: true, minWidth: 140),
              ],
            )
          ],
        ),
      ),
    );
  }


   Widget _buildCustomLevelsMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Другие уровни', 
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 2)
          ),
          const SizedBox(height: 25),
          
          // ИСПРАВЛЕНИЕ: Обернули кнопку в ФИОЛЕТОВОЕ неоновое свечение (0xFF9333EA)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFA855F7).withOpacity(0.4), // Фиолетовый неон
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: _buildBtn('Созданные уровни', () {
              setState(() { _state = GameState.createdLevelsMenu; });
            }, minWidth: 250),
          ),
          
          const SizedBox(height: 12),
          
          // Зелёная кнопка скачанных
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: _buildBtn('Скачанные уровни', () {
              setState(() { _state = GameState.downloadedLevelsMenu; });
            }, minWidth: 250),
          ),
          
          const SizedBox(height: 12),
          
          // Жёлтая кнопка поиска
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFACC15).withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: _buildBtn('Поиск уровней', () {
              _searchController.clear();
              setState(() { _state = GameState.searchMenu; });
            }, minWidth: 250),
          ),
          
          const SizedBox(height: 25),
          
          _buildBtn('Назад', () {
            setState(() { _state = GameState.mainMenu; });
          }, minWidth: 200),
        ],
      ),
    );
  }


  Widget _buildSettingsMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Настройки', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          SizedBox(
            width: 300,
            child: Column(
              children: [
                Text('Громкость музыки: ${_volume.round()}%'),
                Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  activeColor: const Color(0xFF00F2FE),
                  onChanged: (val) {
                    setState(() { _volume = val; });
                    _prefs.setDouble('cybics_volume', val);
                    _updatePlayersVolume();
                  },
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  title: const Text('Показывать проценты в игре', style: TextStyle(fontSize: 14)),
                  value: _showPercent,
                  activeColor: const Color(0xFF00F2FE),
                  onChanged: (val) {
                    setState(() { _showPercent = val ?? true; });
                    _prefs.setBool('cybics_show_percent', _showPercent);
                  },
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  title: const Text('Показывать FPS в игре', style: TextStyle(fontSize: 14)),
                  value: _showFps,
                  activeColor: const Color(0xFF00F2FE),
                  onChanged: (val) {
                    setState(() { _showFps = val ?? false; });
                    _prefs.setBool('cybics_show_fps', _showFps);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          _buildBtn('Назад', () {
            setState(() { _state = GameState.mainMenu; });
          }, isSecondary: true),
        ],
      ),
    );
  }

    Widget _buildGameplay() {
    return Listener(
      // ИСПРАВЛЕНИЕ: Убран setState(). Переменная меняется в памяти мгновенно, не тормозя отрисовку!
      onPointerDown: (_) {
        if (_isPaused || !_isPlaying) return; // Блокировка нажатия во время паузы
        if (!_isPressing) _checkOrbActivation();
        _isPressing = true;
      },
      onPointerUp: (_) {
        _isPressing = false;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: _gameTickNotifier,
              builder: (context, tick, child) {
                return CustomPaint(
                  painter: GamePainter(
                    player: _player,
                    cameraX: _cameraX,
                    obstacles: _obstacles,
                    medals: _medals,
                    trailParticles: _trailParticles,
                    bgItems: _bgItems,
                    deathParticles: _deathParticles,
                    portalParticles: _portalParticles,
                    orbs: _orbs,
                    isPlaying: _isPlaying,
                    currentLevel: _currentLevel,
                    levelLength: _levelLength,
                    floorY: _floorY,
                    gameHeight: _gameHeight,
                    currentProgress: _currentProgress,
                    showPercent: _showPercent,
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Text(
              _isGodMode ? 'БЕССМЕРТИЕ' : 'ПОПЫТКА $_currentRunAttempts',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: const [Shadow(blurRadius: 5, color: Colors.black)],
                fontStyle: _isGodMode ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (_showFps)
            Positioned(
              top: 28,
              right: 80,
              child: Text(
                'FPS: $_fpsCount',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF22C55E),
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.pause_circle_filled, size: 40, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isPaused = true;
                  _isPressing = false; // ИСПРАВЛЕНИЕ: Сбрасываем флаг, убирая "призрачный прыжок"
                  _stopAllLevelTracks();
                });
              },
            ),
          ),
          if (_isPaused) _buildPauseOverlay(),
          if (_showNewRecord) _buildNewRecordOverlay(),
          if (_showVictory) _buildVictoryOverlay(),
        ],
      ),
    );
  }


  Widget _buildPauseOverlay() {
    int currentRecord = _currentLevel == 1 
        ? _maxProgress 
        : (_currentLevel == 2 
            ? _maxProgress2 
            : (_currentLevel == 3 ? _maxProgress3 : _maxProgress4));
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ПАУЗА', style: TextStyle(fontSize: 44, color: Color(0xFF00F2FE), fontWeight: FontWeight.bold)),
            Text('Рекорд уровня: $currentRecord%', style: const TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 30),
            _buildBtn('Продолжить', () {
              setState(() { _isPaused = false; });
              _startMusicSequencer();
            }),
                        _buildBtn('В меню', () {
              setState(() {
                _isPlaying = false;
                _isPaused = false;
                // ИСПРАВЛЕНИЕ: Возвращает туда, откуда зашли (в Поиск, Созданные или Редактор)
                _state = _currentLevel == 5 ? _customLevelLaunchSource : GameState.levelsMenu;
              });
              _startMusicSequencer();
            }, isSecondary: true),
          ],
        ),
      ),
    );
  }

  Widget _buildNewRecordOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('НОВЫЙ РЕКОРД!', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Color(0xFFE11D48), letterSpacing: 3)),
            const SizedBox(height: 10),
            Text('$_currentProgress%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

    Widget _buildVictoryOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'УРОВЕНЬ ПРОЙДЕН!', 
              style: TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: Color(0xFF22C55E), letterSpacing: 4)
            ),
            const SizedBox(height: 10),
            const Text(
              'Новый рекорд: 100%', 
              style: TextStyle(fontSize: 24, color: Colors.white70)
            ),
            const SizedBox(height: 40),
               _buildBtn('ОК', () {
              setState(() {
                _state = _currentLevel == 5 ? _customLevelLaunchSource : GameState.levelsMenu;
                _showVictory = false;
              });
              _startMusicSequencer();
            }),
          ],
        ),
      ),
    );
  }


      // ИСПРАВЛЕНИЕ: Добавили знак вопроса к VoidCallback?, чтобы кнопка могла принимать null
  Widget _buildBtn(String text, VoidCallback? onPressed, {bool isSecondary = false, double minWidth = 250}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: minWidth,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        // ИСПРАВЛЕНИЕ: Добавлен жёлтый градиент для кнопки поиска (0xFFFACC15 и 0xFFEAB308)
        gradient: isSecondary 
            ? null 
            : (text.contains('Скачанные') 
                ? const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF10B981)]) 
                : (text.contains('Поиск') 
                    ? const LinearGradient(colors: [Color(0xFFFACC15), Color(0xFFEAB308)])
                    : const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)]))),
        color: onPressed == null ? const Color(0xFF1E293B) : (isSecondary ? const Color(0xFF334155) : null),
        boxShadow: [
          BoxShadow(
            color: onPressed == null 
                ? Colors.transparent 
                : (isSecondary 
                    ? Colors.black.withOpacity(0.25) 
                    : (text.contains('Скачанные') 
                        ? const Color(0xFF10B981).withOpacity(0.4) 
                        : (text.contains('Поиск')
                            ? const Color(0xFFEAB308).withOpacity(0.4)
                            : const Color(0xFF06B6D4).withOpacity(0.3)))),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
            child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          // ИСПРАВЛЕНИЕ: Уменьшаем внутренние отступы по бокам для узких кнопок, чтобы текст не сжимался
          padding: EdgeInsets.symmetric(horizontal: minWidth < 135 ? 4 : 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          disabledForegroundColor: Colors.white38, 
        ),
        onPressed: onPressed, 
        child: Text(
          text, 
          style: TextStyle(
            // ИСПРАВЛЕНИЕ: Ставим размер шрифта 10 для кнопки "Редактировать"
            fontSize: minWidth < 135 ? 10 : 18, 
            fontWeight: FontWeight.bold, 
            color: Colors.white,
          ),
          maxLines: 1,
          // Убираем жесткое усечение, давая тексту занять всё свободное пространство кнопки
          softWrap: false,
        ),
      ),
    );
  }


  @override
  void dispose() {
    _gameTimer?.cancel();
    _deathVolumeTimer?.cancel(); 
    _retryTimer?.cancel();  
    _pulseController.dispose();
    _gameTickNotifier.dispose();
    _menuPlayer.dispose();
    _level1Player.dispose();
    _level2Player.dispose();
    _level3Player.dispose();
    _level4Player.dispose();
    _deathPlayer.dispose();
    super.dispose();
  }
}

class GamePainter extends CustomPainter {
  final Player player;
  final double cameraX;
  final List<Obstacle> obstacles;
  final List<Medal> medals;
  final List<Offset> trailParticles;
  final List<BgItem> bgItems;
  final List<DeathParticle> deathParticles;
  final List<DeathParticle> portalParticles;
  final List<GameOrb> orbs;
  final bool isPlaying;
  final int currentLevel;
  final double levelLength;
  final double floorY;
  final double gameHeight;
  final int currentProgress;
  final bool showPercent;

  GamePainter({
    required this.player,
    required this.cameraX,
    required this.obstacles,
    required this.medals,
    required this.trailParticles,
    required this.bgItems,
    required this.deathParticles,
    required this.portalParticles,
    required this.orbs,
    required this.isPlaying,
    required this.currentLevel,
    required this.levelLength,
    required this.floorY,
    required this.gameHeight,
    required this.currentProgress,
    required this.showPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double scale = size.height / gameHeight;
    canvas.save();
    canvas.scale(scale, scale);

    final Paint paint = Paint();

    // 1. Задний фон (Небо)
    final Rect bgRect = Rect.fromLTWH(0, 0, size.width / scale, gameHeight);
    paint.shader = const LinearGradient(
      colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(bgRect);
    canvas.drawRect(bgRect, paint);
    paint.shader = null;

    // 2. Анимированный тематический фон частиц
    for (var item in bgItems) {
      canvas.save();
      canvas.translate(item.x, item.y);
      canvas.rotate(item.angle);

      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      if (currentLevel == 1) {
        paint.color = const Color(0xFF00F2FE).withOpacity(0.15);
        Path path = Path()
          ..moveTo(0, -item.size)
          ..lineTo(item.size, 0)
          ..lineTo(0, item.size)
          ..lineTo(-item.size, 0)
          ..close();
        canvas.drawPath(path, paint);
      } 
      else if (currentLevel == 2) {
        paint.color = const Color(0xFFA855F7).withOpacity(0.15);
        canvas.drawCircle(Offset.zero, item.size, paint);
        canvas.drawCircle(Offset.zero, item.size * 0.4, paint);
      } 
      else if (currentLevel == 3) {
        paint.color = const Color(0xFFEF4444).withOpacity(0.15);
        canvas.drawLine(Offset(-item.size / 2, 0), Offset(item.size / 2, 0), paint);
        canvas.drawLine(Offset(0, -item.size / 2), Offset(0, item.size / 2), paint);
      }
      else if (currentLevel == 4) {
        paint.color = const Color(0xFFFACC15).withOpacity(0.15);
        Path path = Path()
          ..moveTo(0, -item.size)
          ..lineTo(item.size, item.size)
          ..lineTo(-item.size, item.size)
          ..close();
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
    paint.style = PaintingStyle.fill;

    // 3. Пол
    double maxFloorW = (levelLength - cameraX).clamp(0, size.width / scale);
    if (maxFloorW > 0) {
      paint.color = const Color(0xFF1E293B);
      canvas.drawRect(Rect.fromLTWH(0, floorY, maxFloorW, gameHeight - floorY), paint);
      
      paint.color = const Color(0xFF3B82F6);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 4;
      canvas.drawLine(Offset(0, floorY), Offset(maxFloorW, floorY), paint);
      paint.style = PaintingStyle.fill;
    }

            // 4. Препятствия кастомных и обычных уровней (Отрисовка в прохождении)
    for (var obs in obstacles) {
      double renderX = obs.x - cameraX;
      if (renderX > -200 && renderX < (size.width / scale) + 200) {
        
        // ОБЫЧНЫЙ ШИП ИЛИ ШИП С ПОМЕТКОЙ
        if (obs.type == 'spike' || obs.type == 'spike_mark' || obs.type == 'spike_upside') {
          // ИСПРАВЛЕНИЕ: Используем currentLevel без подчеркивания. 
          // Если Y меньше 200 или тип spike_upside — шип автоматически переворачивается!
          bool isSpikeUpsideDown = (obs.type == 'spike_upside' || obs.y < 200 || (currentLevel == 4 && obs.y < 250));
          
          paint.color = const Color(0xFF0F172A);
          Path spikePath = Path();
          
          if (isSpikeUpsideDown) {
            spikePath.moveTo(renderX, obs.y);
            spikePath.lineTo(renderX + 30, obs.y);
            spikePath.lineTo(renderX + 15, obs.y + 30); // Острие вниз
          } else {
            spikePath.moveTo(renderX, obs.y);
            spikePath.lineTo(renderX + 30, obs.y);
            spikePath.lineTo(renderX + 15, obs.y - 30); // Острие вверх
          }
          spikePath.close();
          canvas.drawPath(spikePath, paint);

          paint.style = PaintingStyle.stroke;
          paint.color = const Color(0xFFF1F5F9); 
          paint.strokeWidth = 2.5;
          canvas.drawPath(spikePath, paint);
          paint.style = PaintingStyle.fill;

          // ИСПРАВЛЕНИЕ: Рисуем анимированный знак [!] строго для уровней 1-4 или для spike_mark
          if (currentLevel <= 4 || obs.type == 'spike_mark') {
            canvas.save();
            double pulse = 1.0 + math.sin(player.x * 0.05) * 0.15;
            double markOffsetY = isSpikeUpsideDown ? 45 : -45;
            
            canvas.translate(renderX + 15, obs.y + markOffsetY);
            canvas.scale(pulse, pulse);
            
            paint.color = isSpikeUpsideDown ? const Color(0xFFEF4444) : const Color(0xFFFACC15);
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-2, -9, 4, 11), const Radius.circular(1.5)), paint);
            canvas.drawCircle(const Offset(0, 5), 2, paint);
            canvas.restore();
          }
        } 
        // ТВЕРДАЯ ПЛАТФОРМА
        else if (obs.type == 'platform') {
          paint.color = const Color(0xFF334155); 
          canvas.drawRect(Rect.fromLTWH(renderX, obs.y, obs.w, obs.h > 0 ? obs.h : 30), paint);
          
          paint.style = PaintingStyle.stroke; 
          paint.color = const Color(0xFF475569); 
          paint.strokeWidth = 3; 
          canvas.drawRect(Rect.fromLTWH(renderX, obs.y, obs.w, obs.h > 0 ? obs.h : 30), paint); 
          paint.style = PaintingStyle.fill;
        }
                else if (obs.type == 'portal_ship' || obs.type == 'portal_grav') {
          paint.style = PaintingStyle.fill;
          paint.color = obs.type == 'portal_ship' ? const Color(0x66A855F7) : const Color(0x59EAB308);
          
          // ИСПРАВЛЕНИЕ: Если это 4 уровень — вытягиваем луч на 400 пикселей до самого пола!
          double renderHeight = (currentLevel == 4) ? 400.0 : (obs.h > 0 ? obs.h : 120.0);
          canvas.drawRect(Rect.fromLTWH(renderX, obs.y, 40, renderHeight), paint);
          
          paint.style = PaintingStyle.stroke;
          paint.color = obs.type == 'portal_ship' ? const Color(0xFFC084FC) : const Color(0xFFFACC15);
          paint.strokeWidth = 5;
          canvas.drawLine(Offset(renderX + 20, obs.y), Offset(renderX + 20, obs.y + renderHeight), paint);
          paint.style = PaintingStyle.fill;
        }
      }
    }


    // 5. Медали
    for (var m in medals) {
      double renderX = m.x - cameraX;
      if (!m.collected && renderX > -50 && renderX < (size.width / scale) + 50) {
        paint.color = const Color(0xFFF59E0B);
        canvas.drawCircle(Offset(renderX, m.y), 18, paint);

        paint.style = PaintingStyle.stroke;
        paint.color = Colors.white;
        paint.strokeWidth = 3;
        canvas.drawCircle(Offset(renderX, m.y), 18, paint);
        
        paint.style = PaintingStyle.fill;
        paint.color = Colors.white;
        Path coinSymbol = Path()
          ..moveTo(renderX, m.y - 7)
          ..lineTo(renderX + 7, m.y)
          ..lineTo(renderX, m.y + 7)
          ..lineTo(renderX - 7, m.y)
          ..close();
        canvas.drawPath(coinSymbol, paint);
      }
    }

        // 5.1 Сферы (Орбы) — ИСПРАВЛЕНИЕ: Насыщенно-жёлтый аркадный цвет для всех режимов
    final double orbTime = DateTime.now().millisecondsSinceEpoch * 0.003;
    final double rotationAngle = orbTime % (math.pi * 2);

    for (var orb in orbs) {
      double renderX = orb.x - cameraX;
      if (!orb.collected && renderX > -50 && renderX < (size.width / scale) + 50) {
        canvas.save();
        canvas.translate(renderX, orb.y);
        canvas.rotate(rotationAngle);
        
        paint.color = const Color(0xFFFACC15); // Настоящий жёлтый цвет Geometry Сферы!
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 3.5;
        canvas.drawCircle(Offset.zero, 22, paint);
        
        paint.strokeWidth = 2.5;
        canvas.drawLine(const Offset(-15, 0), const Offset(15, 0), paint);
        canvas.drawLine(const Offset(0, -15), const Offset(0, 15), paint);
        
        paint.color = Colors.white;
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(Offset.zero, 9, paint);
        canvas.restore();
      }
    }


    // ==========================================
    // ИСПРАВЛЕННЫЙ БЛОК 6: ШЛЕЙФ ДЛЯ ВСЕХ РЕЖИМОВ
    // ==========================================
    if (trailParticles.isNotEmpty) {
      canvas.save();
      for (int i = 0; i < trailParticles.length; i++) {
        double alpha = (i / trailParticles.length) * 0.25;
        double sizeFactor = (i / trailParticles.length); 

        if (player.isShip) {
          paint.color = const Color(0xFFA855F7).withOpacity(alpha); 
          double trailSize = 24 * sizeFactor; 
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(trailParticles[i].dx - cameraX, trailParticles[i].dy),
              width: trailSize,
              height: trailSize,
            ),
            paint,
          );
        } else {
          paint.color = const Color(0xFF00F2FE).withOpacity(alpha); 
          double trailSize = 30 * sizeFactor; 
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(trailParticles[i].dx - cameraX, trailParticles[i].dy),
              width: trailSize,
              height: trailSize,
            ),
            paint,
          );
        }
      }
      canvas.restore();
    }

        // ==========================================
    // ИСПРАВЛЕННЫЙ БЛОК 7: ОТРИСОВКА ПЕРСОНАЖА
    // ==========================================
    if (isPlaying) {
      canvas.save();
      canvas.translate(player.x - cameraX + player.size / 2, player.y + player.size / 2);
      canvas.rotate(player.rotation);

      if (player.isShip) {
        paint.color = const Color(0xFFC084FC);
        double currentSize = player.size * 0.85; 
        double halfW = currentSize / 2; 
        double halfH = currentSize / 2.6; 

        Path shipPath = Path()
          ..moveTo(-halfW, -halfH) 
          ..lineTo(-halfW, halfH)  
          ..lineTo(halfW * 1.3, 0) 
          ..close();
        canvas.drawPath(shipPath, paint);

        paint.style = PaintingStyle.stroke;
        paint.color = Colors.white;
        paint.strokeWidth = 2.0;
        canvas.drawPath(shipPath, paint);
        paint.style = PaintingStyle.fill;
      } else {
        paint.color = const Color(0xFF00F2FE);
        canvas.drawRect(Rect.fromCircle(center: Offset.zero, radius: player.size / 2), paint);

        paint.style = PaintingStyle.stroke;
        paint.color = const Color(0xFF0F172A);
        paint.strokeWidth = 4;
        canvas.drawRect(Rect.fromCircle(center: Offset.zero, radius: player.size * 0.33), paint);
        paint.style = PaintingStyle.fill;
      }
      canvas.restore();
    }

    // ==========================================
    // ОПТИМИЗИРОВАННЫЙ БЛОК 8: ФИОЛЕТОВЫЕ ПОРТАЛЫ
    // ==========================================
    if (currentLevel == 2 || currentLevel == 3) {
      double shipInX = (levelLength * 0.4) - cameraX;
      double shipOutX = (levelLength * 0.75) - cameraX;

      void drawModePortal(double x) {
        if (x > -100 && x < (size.width / scale) + 100) {
          paint.shader = const LinearGradient(
            colors: [Colors.transparent, Color(0x66A855F7), Colors.transparent],
          ).createShader(Rect.fromLTWH(x - 20, 100, 40, floorY - 100));
          canvas.drawRect(Rect.fromLTWH(x - 20, 100, 40, floorY - 100), paint);
          paint.shader = null;

          paint.style = PaintingStyle.stroke;
          paint.color = const Color(0xFFC084FC);
          paint.strokeWidth = 6;
          canvas.drawLine(Offset(x, 100), Offset(x, floorY), paint);
          paint.style = PaintingStyle.fill;
        }
      }
      drawModePortal(shipInX);
      drawModePortal(shipOutX);
    }

    // ==========================================
    // ОПТИМИЗИРОВАННЫЙ БЛОК 8.1: ЖЁЛТЫЕ ПОРТАЛЫ ГРАВИТАЦИИ
    // ==========================================
    if (currentLevel == 4) {
      double gravInX = (levelLength * 0.35) - cameraX;
      double gravOutX = (levelLength * 0.70) - cameraX;

      void drawGravityPortal(double x, bool isEntering) {
        if (x > -100 && x < (size.width / scale) + 100) {
          canvas.save();

          final Rect portalRect = Rect.fromLTWH(x - 25, 100, 50, floorY - 100);
          paint.shader = const LinearGradient(
            colors: [Colors.transparent, Color(0x59EAB308), Colors.transparent],
          ).createShader(portalRect);
          paint.style = PaintingStyle.fill;
          canvas.drawRect(portalRect, paint);
          paint.shader = null;

          paint.style = PaintingStyle.stroke;
          paint.color = const Color(0xFFFACC15);
          paint.strokeWidth = 5;
          canvas.drawLine(Offset(x, 100), Offset(x, floorY), paint);

          paint.style = PaintingStyle.fill;
          paint.color = Colors.white;
          canvas.translate(x, 80); 

          Path arrowPath = Path();
          if (isEntering) {
            arrowPath.moveTo(-8, -5);
            arrowPath.lineTo(8, -5);
            arrowPath.lineTo(0, 7);
          } else {
            arrowPath.moveTo(-8, 5);
            arrowPath.lineTo(8, 5);
            arrowPath.lineTo(0, -7);
          }
          arrowPath.close();
          canvas.drawPath(arrowPath, paint);

          canvas.restore();
        }
      }
      drawGravityPortal(gravInX, true);
      drawGravityPortal(gravOutX, false);
    }

    // ==========================================
    // БЛОК 9: ПОРТАЛ ФИНИША
    // ==========================================
    double portalX = levelLength - cameraX;
    if (portalX > -200 && portalX < (size.width / scale) + 200) {
      paint.shader = const RadialGradient(
        colors: [Color(0xFFFFFFFF), Color(0xCC4ADE80), Color(0x4D22C55E), Colors.transparent],
        stops: [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(portalX, floorY - 150), radius: 90));
      
      canvas.save();
      canvas.translate(portalX, floorY - 150);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 180, height: 300), paint);
      paint.shader = null;

      paint.style = PaintingStyle.stroke;
      paint.color = const Color(0xFF4ADE80);
      paint.strokeWidth = 6;
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 80, height: 280), paint);
      canvas.restore();
      paint.style = PaintingStyle.fill;
    }

    for (var p in portalParticles) {
      if (p.alpha > 0) {
        canvas.save();
        paint.color = const Color(0xFF4ADE80).withOpacity(p.alpha); 
        paint.style = PaintingStyle.fill;
        
        final Rect pRect = Rect.fromLTWH(p.x - cameraX - p.size / 2, p.y - p.size / 2, p.size, p.size);
        canvas.drawOval(pRect, paint); 
        canvas.restore();
      }
    }
   
    // ==========================================
    // БЛОК: ОСКОЛКИ СМЕРТИ
    // ==========================================
    for (var p in deathParticles) {
      if (p.alpha > 0) {
        canvas.save();
        paint.color = player.isShip 
            ? const Color(0xFFC084FC).withOpacity(p.alpha) 
            : const Color(0xFF00F2FE).withOpacity(p.alpha);
        paint.style = PaintingStyle.fill;
        
        final Rect pRect = Rect.fromLTWH(p.x - cameraX - p.size / 2, p.y - p.size / 2, p.size, p.size);
        canvas.drawRect(pRect, paint);
        
        paint.color = Colors.white.withOpacity(p.alpha);
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 1;
        canvas.drawRect(pRect, paint);
        canvas.restore();
      }
    }

    // ==========================================
    // ОПТИМИЗИРОВАННЫЙ БЛОК 10: ВЕРХНИЙ ПРОГРЕСС-БАР
    // ==========================================
    if (showPercent && isPlaying) {
      double barW = 250;
      double barH = 22;
      double barX = (size.width / scale) / 2 - barW / 2;
      double barY = 25;

      paint.color = const Color(0xFF0F172A).withOpacity(0.6);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), paint);

      paint.color = const Color(0xFF00F2FE);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW * (currentProgress / 100.0), barH), paint);

      TextPainter progressTextPainter = TextPainter(
        text: TextSpan(
          text: '$currentProgress%', 
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      progressTextPainter.paint(
        canvas, 
        Offset(barX + barW / 2 - progressTextPainter.width / 2, barY + barH / 2 - progressTextPainter.height / 2)
      );
    }

    canvas.restore(); 
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DifficultyShapePainter extends CustomPainter {
  final int difficultyIndex;
  final Color color;

  DifficultyShapePainter({required this.difficultyIndex, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color..style = PaintingStyle.fill;
    
    final Paint facePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
      
    double cx = size.width / 2;
    double cy = size.height / 2;
    double baseRadius = 16.0; 

    // ======================================================================
    // ЭТАП 1: ДОПОЛНИТЕЛЬНЫЕ ЭФФЕКТЫ (СВЕЧЕНИЕ И ШИПЫ)
    // ======================================================================
    if (difficultyIndex >= 3) {
      final Paint glowPaint = Paint()
        ..color = color.withOpacity(0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), baseRadius + 8, glowPaint);
    }

    if (difficultyIndex == 4 || difficultyIndex == 5) {
      final Paint spikePaint = Paint()
        ..color = difficultyIndex == 5 ? const Color(0xFF1E1B4B) : color 
        ..style = PaintingStyle.fill;
        
      final Paint spikeOutline = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      int spikeCount = difficultyIndex == 5 ? 12 : 8; 
      double spikeLength = difficultyIndex == 5 ? 8.0 : 6.0; 
      double spikeWidth = 5.0; 

      for (int i = 0; i < spikeCount; i++) {
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate((math.pi * 2 / spikeCount) * i);

        Path spikePath = Path()
          ..moveTo(-spikeWidth / 2, -baseRadius + 1) 
          ..lineTo(spikeWidth / 2, -baseRadius + 1)  
          ..lineTo(0, -baseRadius - spikeLength)     
          ..close();

        canvas.drawPath(spikePath, spikePaint);
        canvas.drawPath(spikePath, spikeOutline); 
        canvas.restore();
      }
    }

    // ======================================================================
    // ЭТАП 2: ОТРИСОВКА ЕДИНОЙ КРУГЛОЙ ОСНОВЫ
    // ======================================================================
    canvas.drawCircle(Offset(cx, cy), baseRadius, paint);

    if (difficultyIndex == 5) {
      final Paint nightmareOverlay = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), baseRadius, nightmareOverlay);
    }

    // ======================================================================
    // ЭТАП 3: ОТРИСОВКА МИМИКИ ЛИЦА
    // ======================================================================
    if (difficultyIndex == 0) {
      canvas.drawCircle(Offset(cx - 5, cy - 3), 2, Paint()..color = const Color(0xFF0F172A));
      canvas.drawCircle(Offset(cx + 5, cy - 3), 2, Paint()..color = const Color(0xFF0F172A));
      canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy + 1), width: 14, height: 10), 0, math.pi, false, facePaint);
    } 
    else if (difficultyIndex == 1) {
      canvas.drawCircle(Offset(cx - 5, cy - 3), 2, Paint()..color = const Color(0xFF0F172A));
      canvas.drawCircle(Offset(cx + 5, cy - 3), 2, Paint()..color = const Color(0xFF0F172A));
      canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy + 2), width: 8, height: 3), 0, math.pi, false, facePaint);
    } 
    else if (difficultyIndex == 2) {
      canvas.drawCircle(Offset(cx - 5, cy - 3), 2, Paint()..color = const Color(0xFF0F172A));
      canvas.drawCircle(Offset(cx + 5, cy - 3), 2, Paint()..color = const Color(0xFF0F172A));
      canvas.drawLine(Offset(cx - 5, cy + 4), Offset(cx + 5, cy + 4), facePaint);
    } 
    else if (difficultyIndex == 3) {
      canvas.drawLine(Offset(cx - 7, cy - 5), Offset(cx - 2, cy - 3), facePaint);
      canvas.drawLine(Offset(cx + 7, cy - 5), Offset(cx + 2, cy - 3), facePaint);
      canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy + 4), width: 10, height: 6), math.pi, math.pi, false, facePaint);
    } 
    else if (difficultyIndex == 4) {
      canvas.drawLine(Offset(cx - 7, cy - 5), Offset(cx - 2, cy - 2), facePaint);
      canvas.drawLine(Offset(cx + 7, cy - 5), Offset(cx + 2, cy - 2), facePaint);
      canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy + 4), width: 12, height: 8), math.pi, math.pi, false, facePaint);
      canvas.drawLine(Offset(cx - 6, cy + 4), Offset(cx + 6, cy + 4), facePaint); 
    } 
    else if (difficultyIndex == 5) {
      facePaint.strokeWidth = 3.0; 
      canvas.drawLine(Offset(cx - 7, cy - 5), Offset(cx - 2, cy - 2), facePaint);
      canvas.drawLine(Offset(cx + 7, cy - 5), Offset(cx + 2, cy - 2), facePaint);
      
      Path madMouth = Path()
        ..moveTo(cx - 6, cy + 4)
        ..lineTo(cx - 3, cy + 7)
        ..lineTo(cx, cy + 3)
        ..lineTo(cx + 3, cy + 7)
        ..lineTo(cx + 6, cy + 4);
      canvas.drawPath(madMouth, facePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class EditorBackgroundPainter extends CustomPainter {
  final double cameraX;
  final double cameraY; // ИСПРАВЛЕНИЕ: Добавили поле
  final double floorY;
  final double gameHeight;
  final double levelLength;
  final CustomLevel? currentLevelData; 

  EditorBackgroundPainter({
    required this.cameraX, 
    required this.cameraY, // Передаем в конструктор
    required this.floorY, 
    required this.gameHeight, 
    required this.levelLength,
    required this.currentLevelData,
  });

    @override
  void paint(Canvas canvas, Size size) {
    double scale = size.height / gameHeight;
    canvas.save();
    canvas.scale(scale, scale);

    final Paint paint = Paint();

    // 1. Тёмный фон конструктора
    final Rect bgRect = Rect.fromLTWH(0, 0, size.width / scale, gameHeight);
    paint.shader = const LinearGradient(
      colors: [Color(0xFF1E1E2E), Color(0xFF11111B)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(bgRect);
    canvas.drawRect(bgRect, paint);
    paint.shader = null;

    // ======================================================================
    // ИСПРАВЛЕНИЕ: ДИНАМИЧЕСКИЙ ПОЛ ДЛЯ СИНХРОНИЗАЦИИ СЕТКИ
    // ======================================================================
    double dynamicFloorY = floorY - cameraY; // Вычисляем положение пола на экране

    // 2. Отрисовка тонкой сетки 30x30px
    paint.color = Colors.white.withOpacity(0.04); 
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.0;
    
    double step = 30.0; 
    double startGridX = -(cameraX % step);
    
    // Вертикальные линии сетки (привязаны к скроллу X)
    for (double x = startGridX; x < size.width / scale; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, gameHeight), paint);
    }
    
    // ИСПРАВЛЕНИЕ: Горизонтальные линии теперь отсчитываются от DYNAMICFLOORY!
    // Благодаря этому при движении вверх/вниз сетка намертво прикреплена к линии земли.
    // Сетка идет вверх до самого неба конструктора
    for (double y = dynamicFloorY; y >= 0; y -= step) {
      canvas.drawLine(Offset(0, y), Offset(size.width / scale, y), paint);
    }
    // Сетка идет вниз под пол (для плавности при скролле)
    for (double y = dynamicFloorY + step; y < gameHeight; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width / scale, y), paint);
    }

    // Красный флажок спавна
    double flagRenderX = 100.0 - cameraX;
    if (flagRenderX > -50 && flagRenderX < (size.width / scale) + 50) {
      paint.style = PaintingStyle.stroke; paint.color = Colors.grey; paint.strokeWidth = 3;
      canvas.drawLine(Offset(flagRenderX, dynamicFloorY), Offset(flagRenderX, dynamicFloorY - 50), paint);
      paint.style = PaintingStyle.fill; paint.color = const Color(0xFFEF4444);
      Path flagCloth = Path()..moveTo(flagRenderX, dynamicFloorY - 50)..lineTo(flagRenderX + 20, dynamicFloorY - 40)..lineTo(flagRenderX, dynamicFloorY - 30)..close();
      canvas.drawPath(flagCloth, paint);
    }

    // 3. ОТРИСОВКА ПОСТРОЕК НА СЕТКЕ
    if (currentLevelData != null) {
      for (var obs in currentLevelData!.obstacles) {
        double renderX = obs.x - cameraX;
        double renderY = obs.y - cameraY; 
        
        if (renderX > -200 && renderX < (size.width / scale) + 200) {
          if (obs.type == 'platform') {
            paint.style = PaintingStyle.fill; paint.color = const Color(0xFF334155);
            canvas.drawRect(Rect.fromLTWH(renderX, renderY, obs.w > 0 ? obs.w : 30, obs.h > 0 ? obs.h : 30), paint);
            paint.style = PaintingStyle.stroke; paint.color = const Color(0xFF475569); paint.strokeWidth = 3;
            canvas.drawRect(Rect.fromLTWH(renderX, renderY, obs.w > 0 ? obs.w : 30, obs.h > 0 ? obs.h : 30), paint);
          } 
          else if (obs.type == 'spike') {
            paint.style = PaintingStyle.fill; paint.color = const Color(0xFF0F172A);
            Path spikePath = Path()..moveTo(renderX, renderY)..lineTo(renderX + 30, renderY)..lineTo(renderX + 15, renderY - 30)..close();
            canvas.drawPath(spikePath, paint);
            paint.style = PaintingStyle.stroke; paint.color = const Color(0xFFF1F5F9); paint.strokeWidth = 2.5; canvas.drawPath(spikePath, paint);
          }
          else if (obs.type == 'spike_mark') {
            paint.style = PaintingStyle.fill; paint.color = const Color(0xFF0F172A);
            Path spikePath = Path()..moveTo(renderX, renderY)..lineTo(renderX + 30, renderY)..lineTo(renderX + 15, renderY - 30)..close();
            canvas.drawPath(spikePath, paint);
            paint.style = PaintingStyle.stroke; paint.color = const Color(0xFFFACC15); paint.strokeWidth = 2.5; canvas.drawPath(spikePath, paint);
            paint.style = PaintingStyle.fill; paint.color = const Color(0xFFEA580C); canvas.drawRect(Rect.fromLTWH(renderX + 13, renderY - 22, 4, 8), paint); canvas.drawCircle(Offset(renderX + 15, renderY - 8), 2, paint);
          }
          else if (obs.type == 'spike_upside') {
            paint.style = PaintingStyle.fill; paint.color = const Color(0xFF0F172A);
            Path spikePath = Path()..moveTo(renderX, renderY)..lineTo(renderX + 30, renderY)..lineTo(renderX + 15, renderY + 30)..close();
            canvas.drawPath(spikePath, paint);
            paint.style = PaintingStyle.stroke; paint.color = const Color(0xFFEF4444); paint.strokeWidth = 2.5; canvas.drawPath(spikePath, paint);
          }
          else if (obs.type == 'portal_ship' || obs.type == 'portal_grav') {
            paint.style = PaintingStyle.fill; paint.color = obs.type == 'portal_ship' ? const Color(0x66A855F7) : const Color(0x59EAB308);
            canvas.drawRect(Rect.fromLTWH(renderX, renderY, 40, 400), paint);
            paint.style = PaintingStyle.stroke; paint.color = obs.type == 'portal_ship' ? const Color(0xFFC084FC) : const Color(0xFFFACC15); paint.strokeWidth = 5;
            canvas.drawLine(Offset(renderX + 20, renderY), Offset(renderX + 20, renderY + 400), paint);
            paint.style = PaintingStyle.fill;
          }
        }
      }

      // Сферы прыжка
      for (var orb in currentLevelData!.orbs) {
        double renderX = orb.x - cameraX;
        double renderY = orb.y - cameraY; 
        if (renderX > -50 && renderX < (size.width / scale) + 50) {
          canvas.save(); canvas.translate(renderX, renderY);
          paint.style = PaintingStyle.stroke; paint.color = const Color(0xFFFACC15); paint.strokeWidth = 3.5; canvas.drawCircle(Offset.zero, 22, paint);
          paint.strokeWidth = 2.5; canvas.drawLine(const Offset(-15, 0), const Offset(15, 0), paint); canvas.drawLine(const Offset(0, -15), const Offset(0, 15), paint);
          paint.color = Colors.white; paint.style = PaintingStyle.fill; canvas.drawCircle(Offset.zero, 9, paint);
          canvas.restore();
        }
      }

      // Медали
      for (var m in currentLevelData!.medals) {
        double renderX = m.x - cameraX;
        double renderY = m.y - cameraY; 
        if (renderX > -50 && renderX < (size.width / scale) + 50) {
          paint.style = PaintingStyle.fill; paint.color = const Color(0xFFF59E0B); canvas.drawCircle(Offset(renderX, renderY), 16, paint);
          paint.style = PaintingStyle.stroke; paint.color = Colors.white; paint.strokeWidth = 2.5; canvas.drawCircle(Offset(renderX, renderY), 16, paint);
          paint.style = PaintingStyle.fill; paint.color = Colors.white;
          Path coinSymbol = Path()..moveTo(renderX, renderY - 6)..lineTo(renderX + 6, renderY)..lineTo(renderX, renderY + 6)..lineTo(renderX - 6, renderY)..close();
          canvas.drawPath(coinSymbol, paint);
        }
      }
    }

    // 4. Линия пола (Нижняя платформа)
    double maxFloorW = (levelLength - cameraX).clamp(0, size.width / scale);
    if (maxFloorW > 0) {
      paint.style = PaintingStyle.fill; paint.color = const Color(0xFF181825);
      canvas.drawRect(Rect.fromLTWH(0, dynamicFloorY, maxFloorW, gameHeight - dynamicFloorY), paint);
      paint.color = const Color(0xFF89B4FA); paint.style = PaintingStyle.stroke; paint.strokeWidth = 3;
      canvas.drawLine(Offset(0, dynamicFloorY), Offset(maxFloorW, dynamicFloorY), paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EditorBackgroundPainter oldDelegate) => true;
}
