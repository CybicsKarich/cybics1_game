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

enum GameState { mainMenu, levelsMenu, settingsMenu, gameplay }

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

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  GameState _state = GameState.mainMenu;
  
  final ValueNotifier<int> _gameTickNotifier = ValueNotifier<int>(0);

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
  
  final double _levelLength = 20000;
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
          if (_currentLevel == 1) await _level1Player.play(AssetSource('level1.mp3'));
          if (_currentLevel == 2) await _level2Player.play(AssetSource('level2.mp3'));
          if (_currentLevel == 3) await _level3Player.play(AssetSource('level3.mp3'));
          if (_currentLevel == 4) await _level4Player.play(AssetSource('level4.mp3'));
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
    _collectedThisRun.clear();
    double nextX = 700;

    if (_currentLevel == 1) {
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

          // МЕДАЛЬ №2 (50%): НОРМАЛЬНЫЕ 3 ШИПА И ПОДНЯТАЯ МОНЕТКА
          if (progressPct >= 50.0 && !spawnedMedal2Obstacle) {
            double platX = nextX;
            double platY = 100;
            double platW = 500; // Большая устойчивая платформа
            
            _obstacles.add(Obstacle(type: 'platform', x: platX, y: platY, w: platW, h: 60));
            
            // ЧЕСТНЫЕ 3 ШИПА (расстояние между ними ровно 30 пикселей)
            _obstacles.add(Obstacle(type: 'spike', x: platX + 220, y: 160));
            _obstacles.add(Obstacle(type: 'spike', x: platX + 250, y: 160)); 
            _obstacles.add(Obstacle(type: 'spike', x: platX + 280, y: 160));

            // Сфера висит строго в середине над центральным шипом
            _orbs.add(GameOrb(x: platX + 250, y: platY + 110, collected: false));
            
            // ИСПРАВЛЕНИЕ: Подняли медаль повыше (сместили Y ближе к полу: 210 вместо 150)
            _medals.add(Medal(id: 1, x: platX + 340, y: platY + 210));

            // Корректный сдвиг камеры (длина платформы + короткий зазор в 150px)
            nextX += platW + 150; 
            spawnedMedal2Obstacle = true;
            continue;
          }

          // МЕДАЛЬ №3 (67%): Скрытая медаль в пропасти
          if (progressPct >= 66.5 && progressPct <= 68.5 && !spawnedMedal3Obstacle) {
            double m3X = nextX;
            _obstacles.add(Obstacle(type: 'platform', x: m3X, y: 100, w: 150, h: 60));
            
            _medals.add(Medal(id: 2, x: m3X + 265, y: 320)); 
            _obstacles.add(Obstacle(type: 'platform', x: m3X + 130, y: 380, w: 270, h: 20));
            _obstacles.add(Obstacle(type: 'platform', x: m3X + 350, y: 380, w: 50, h: 200));

            _orbs.add(GameOrb(x: m3X + 265, y: 220, collected: false));
            _obstacles.add(Obstacle(type: 'platform', x: m3X + 380, y: 100, w: 150, h: 60));
            
            nextX += 150 + 380 + 150; 
            spawnedMedal3Obstacle = true;
            continue;
          }

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

          // МЕДАЛЬ №1 (28%): ГАРАНТИРОВАННАЯ ПЕРВАЯ МОНЕТКА УРОВНЯ
          if (progressPct >= 27.5 && progressPct <= 29.5 && !spawnedMedal1Obstacle) {
            double startX = nextX;
            double platW = 210;
            
            _obstacles.add(Obstacle(type: 'platform', x: startX, y: _floorY - 80, w: platW, h: 80));
            for (int i = 0; i < 7; i++) {
              _obstacles.add(Obstacle(type: 'spike', x: startX + (i * 30), y: _floorY - 80));
            }
            
            _orbs.add(GameOrb(x: startX + 105, y: _floorY - 170, collected: false));
            _medals.add(Medal(id: 0, x: startX + 240, y: _floorY - 230)); // ID: 0 — честная первая медаль!
            
            nextX += platW + 150; 
            spawnedMedal1Obstacle = true;
            continue;
          }

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
  

  // --- ИГРОВОЙ ДВИЖОК И ФИЗИКА ---
  void _launchGameplay() {
    setState(() {
      _state = GameState.gameplay;
      _isPlaying = true;
      _isPaused = false;
      _currentRunAttempts = 1;

      if (_currentLevel == 1 && _maxProgress < 100) { _attempts1++; _prefs.setInt('cybics_attempts_1', _attempts1); }
      if (_currentLevel == 2 && _maxProgress2 < 100) { _attempts2++; _prefs.setInt('cybics_attempts_2', _attempts2); }
      if (_currentLevel == 3 && _maxProgress3 < 100) { _attempts3++; _prefs.setInt('cybics_attempts_3', _attempts3); }
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
      
      _orbs.clear();
      _orbSpinAngle = 0;
      _isGravityInverted = false;
      _portalParticles.clear();

      _player = Player()
        ..y = _floorY - 40
        ..isUpsideDown = false;

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
    });

        _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
  if (_isPlaying && !_isPaused) {
    _updatePhysics(); // Считаем физику в фоне
    _gameTickNotifier.value++; // Даем холсту сигнал: "пора рисовать"
  }
});
  }

      void _checkOrbActivation() {
    if (!_isPlaying || _isPaused || _currentLevel != 4) return;

    final double playerCenterX = _player.x + _player.size / 2;
    final double playerCenterY = _player.y + _player.size / 2;

    for (var orb in _orbs) {
      if (orb.collected) continue;

      // НАСТРОЙКА: Расширяем окно предварительного поиска сферы по X (с 120 до 150)
      if (orb.x < _player.x - 60 || orb.x > _player.x + 150) continue;

      double distX = (playerCenterX - orb.x).abs();
      double distY = (playerCenterY - orb.y).abs();
      
      // НАСТРОЙКА: Увеличиваем радиус активации сферы с 55 до 70 пикселей для большего пространства
      if (distX < 70 && distY < 70) {
        orb.collected = true;
        
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
    // ОПТИМИЗИРОВАННЫЙ СДВИГ: Расчеты идут напрямую в переменные
    _player.x += 7.5;
    _cameraX = _player.x - 200;

    double progressPct = (_player.x / _levelLength) * 100;

    // Определяем режим корабля (для уровней 2 и 3 в диапазоне 40%-75%)
    _player.isShip = (progressPct >= 40 && progressPct <= 75 && (_currentLevel == 2 || _currentLevel == 3));

    // ОБНОВЛЕНИЕ: Шлейф теперь работает и для кубика, и для самолётика
    // Точка генерации смещена строго на заднюю (левую) грань персонажа
    _trailParticles.add(Offset(_player.x, _player.y + _player.size / 2));
    if (_trailParticles.length > 15) _trailParticles.removeAt(0);

    _frameCount++;
    DateTime now = DateTime.now();
    if (now.difference(_lastFpsTime).inSeconds >= 1) {
      _fpsCount = _frameCount;
      _frameCount = 0;
      _lastFpsTime = now;
    }

    // ==========================================
    // ЭТАП 1: ОБРАБОТКА ВВОДА (ПРЫЖКИ) ДО ДВИЖЕНИЯ
    // ==========================================
    if (_currentLevel == 4) {
      _player.isShip = false;
      if (progressPct >= 35 && progressPct <= 70) {
        _isGravityInverted = true;
      } else {
        _isGravityInverted = false;
      }
      
      double portalInX = _levelLength * 0.35;
      bool isAutoFlying = _isGravityInverted && (_player.x < portalInX + 600);

      if (_isPressing && _player.isGrounded && !isAutoFlying) {
        // НАСТРОЙКА: Прыжок в инверсии равен 17.0
        _player.vy = _isGravityInverted ? 17.0 : _player.jumpForce;
        _player.isGrounded = false;
      }
    } else {
      if (!_player.isShip && _isPressing && _player.isGrounded) {
        _player.vy = _player.jumpForce;
        _player.isGrounded = false;
      }
    }

    // ==========================================
    // ЭТАП 2: ПРИМЕНЕНИЕ ФИЗИКИ И СДВИГ ТЕЛА
    // ==========================================
    bool wasGrounded = _player.isGrounded;
    _player.isGrounded = false;

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
        // НАСТРОЙКА: Притяжение к потолку равно 1.3
        _player.vy -= 1.3;
        if (_player.vy < -14) _player.vy = -14;
        _player.y += _player.vy;

        // ИСПРАВЛЕНИЕ: Защита и отключение смерти на потолке на 64%-69%
        if (progressPct >= 64.0 && progressPct <= 69.0) {
          if (_player.y >= 350) {
            _isGravityInverted = false;
            _player.vy = 0;
          }
        } 
        else {
          if (_player.y <= 10 && !wasGrounded && !_isGodMode) { 
            _gameOver(); 
            return; 
          }
        } 
      } 
      else {
        // ОБЫЧНЫЙ НАЗЕМНЫЙ РЕЖИМ 4 УРОВНЯ
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
    else {
      // ЛОГИКА ДЛЯ 1, 2 И 3 УРОВНЕЙ (Обычный куб / Корабль)
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

    if (_player.y < 0 || _player.y > _gameHeight) {
      if (!_isGodMode) { _gameOver(); return; }
    }

        // ==========================================
    // ЭТАП 3: РАСЧЕТ КОЛЛИЗИЙ (РАЗДЕЛЬНЫЕ ЦИКЛЫ)
    // ==========================================
    _currentProgress = (progressPct.clamp(0, 100)).floor();

    // ИСПРАВЛЕНИЕ: Убрали ограничение "_currentLevel != 4". Теперь монеты работают везде!
    for (var m in _medals) {
      if (m.x < _player.x - 100 || m.x > _player.x + 200) continue;
      if (!m.collected) {
        // Рассчитываем центры игрока и монеты
        double playerCenterX = _player.x + _player.size / 2;
        double playerCenterY = _player.y + _player.size / 2;
        
        double distX = (playerCenterX - m.x).abs();
        double distY = (playerCenterY - m.y).abs();
        
        // ИСПРАВЛЕНИЕ: Расширили радиус сбора до 50 пикселей, чтобы монета 100% забиралась в инверсии и в полете
        if (distX < 50 && distY < 50) {
          m.collected = true;
          if (!_collectedThisRun.contains(m.id)) _collectedThisRun.add(m.id);
        }
      }
    }
  

    // ЦИКЛ А: ОБРАБОТКА ТОЛЬКО ШИПОВ
    for (var obs in _obstacles) {
      if (obs.type != 'spike') continue; 
      if (obs.x < _player.x - 150 || obs.x > _player.x + 900) continue;

      bool isUpsideDown = (obs.y < 200);
      if (_player.x + _player.size > obs.x + 8 && _player.x < obs.x + 22 &&
          ((!isUpsideDown && _player.y + _player.size > obs.y - 30 && _player.y < obs.y) ||
           (isUpsideDown && _player.y < obs.y + 30 && _player.y + _player.size > obs.y))) {
        if (!_isGodMode) { _gameOver(); return; }
      }
    }

    // ЦИКЛ Б: ОБРАБОТКА ТОЛЬКО ПЛАТФОРМ (С ЗАЩИТОЙ ДЛИННЫХ БЛОКОВ)
    for (var obs in _obstacles) {
      if (obs.type != 'platform') continue; 
      if (obs.x + obs.w < _player.x - 150 || obs.x > _player.x + 900) continue;

      bool stoodOnPlatform = false;

      // Железобетонный захват поверхности блока
      if (_player.x + _player.size > obs.x + 2 && _player.x < obs.x + obs.w - 2) {
        if (_currentLevel == 4 && _isGravityInverted) {
          if (_player.vy <= 0 && _player.y <= obs.y + obs.h && _player.y >= obs.y + obs.h - 32) {
            _player.y = obs.y + obs.h;
            _player.vy = 0;
            _player.isGrounded = true;
            stoodOnPlatform = true;
          }
        } else {
          if (_player.vy >= 0 && _player.y + _player.size >= obs.y && _player.y + _player.size <= obs.y + 32) {
            _player.y = obs.y - _player.size;
            _player.vy = 0;
            _player.isGrounded = true;
            stoodOnPlatform = true;
          }
        }
      }

      if (stoodOnPlatform) continue;

      // Честная смерть от удара в торец
      if (!_isGodMode) {
        if (_player.x + _player.size > obs.x && _player.x < obs.x + obs.w) {
          if (_player.y + _player.size > obs.y + 10 && _player.y < obs.y + obs.h - 10) {
            _gameOver();
            return;
          }
        }
      }
    }

    // Вращение куба в воздухе
    if (_currentLevel == 4) {
      double portalInX = _levelLength * 0.35;
      bool isAutoFlying = _isGravityInverted && (_player.x < portalInX + 600);
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
  }



 
  void _gameOver() {
    _gameTimer?.cancel();
    _retryTimer?.cancel(); // ИСПРАВЛЕНИЕ: Сбрасываем старый таймер ретрая
    _collectedThisRun.clear();
    _playDeathSound();
    bool isNewRecord = false;

    if (_currentLevel == 1 && _currentProgress > _maxProgress && _currentProgress < 100) {
      _maxProgress = _currentProgress; _prefs.setInt('cybics_max_progress', _maxProgress); isNewRecord = true;
    } else if (_currentLevel == 2 && _currentProgress > _maxProgress2 && _currentProgress < 100) {
      _maxProgress2 = _currentProgress; _prefs.setInt('cybics_max_progress_2', _maxProgress2); isNewRecord = true;
    } else if (_currentLevel == 3 && _currentProgress > _maxProgress3 && _currentProgress < 100) {
      _maxProgress3 = _currentProgress; _prefs.setInt('cybics_max_progress_3', _maxProgress3); isNewRecord = true;
    } else if (_currentLevel == 4 && _currentProgress > _maxProgress4 && _currentProgress < 100) {
      _maxProgress4 = _currentProgress; _prefs.setInt('cybics_max_progress_4', _maxProgress4); isNewRecord = true;
    }

    // ИСПРАВЛЕНИЕ: Проверяем, жив ли еще виджет на экране перед вызовом setState
    if (!mounted) return; 
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

    Timer? deathAnimTimer;
    deathAnimTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
          // Перед вызовом setState в _gameOver добавь этот блок сохранения:
    for (var id in _collectedThisRun) {
      if (_currentLevel == 1) _savedMedals1[id] = true;
      if (_currentLevel == 2) _savedMedals2[id] = true;
      if (_currentLevel == 3) _savedMedals3[id] = true;
      if (_currentLevel == 4) _savedMedals4[id] = true;
    }
    _prefs.setString('cybics_medals_1', jsonEncode(_savedMedals1));
    _prefs.setString('cybics_medals_2', jsonEncode(_savedMedals2));
    _prefs.setString('cybics_medals_3', jsonEncode(_savedMedals3));
    _prefs.setString('cybics_medals_4', jsonEncode(_savedMedals4));

      setState(() {
        for (var p in _deathParticles) {
          p.x += p.vx;
          p.y += p.vy;
          p.vy += 0.15;
          p.alpha -= 0.03;
          if (p.alpha < 0) p.alpha = 0;
        }
      });
    });

    _retryTimer = Timer(const Duration(milliseconds: 350), () {
      deathAnimTimer?.cancel();
      if (!mounted) return; // ИСПРАВЛЕНИЕ: Защита от вылета при выходе в меню
      setState(() {
        _deathParticles.clear();
      });
      _continueGameOverLogic(isNewRecord);
    });
  }

  void _continueGameOverLogic(bool isNewRecord) {
    if (isNewRecord) {
      if (!mounted) return; // ИСПРАВЛЕНИЕ
      setState(() { _showNewRecord = true; });
      _retryTimer = Timer(const Duration(milliseconds: 1200), () {
        _registerNewAttempt();
        _startLevel();
      });
    } else {
      _registerNewAttempt();
      _startLevel();
    }
  }

  void _registerNewAttempt() {
    if (!mounted) return; // ИСПРАВЛЕНИЕ
    setState(() {
      _currentRunAttempts++;
      if (!_isGodMode) {
        if (_currentLevel == 1 && _maxProgress < 100) { _attempts1++; _prefs.setInt('cybics_attempts_1', _attempts1); }
        if (_currentLevel == 2 && _maxProgress2 < 100) { _attempts2++; _prefs.setInt('cybics_attempts_2', _attempts2); }
        if (_currentLevel == 3 && _maxProgress3 < 100) { _attempts3++; _prefs.setInt('cybics_attempts_4', _attempts3); } // Исправлен твой баг с сохранением 3 уровня в cybics_attempts_4
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
      onPointerDown: (_) {
        setState(() {
          if (!_isPressing) _checkOrbActivation();
          _isPressing = true;
        });
      },
      onPointerUp: (_) => setState(() { _isPressing = false; }),
      child: Stack(
        children: [
                    Positioned.fill(
            // ИСПРАВЛЕНИЕ: Перерисовывается СТРОГО холст, не затрагивая оверлеи интерфейса
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
                _state = GameState.levelsMenu;
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
            // ИСПРАВЛЕНИЕ: Кнопка ручного закрытия экрана победы
            _buildBtn('ОК', () {
              setState(() {
                _state = GameState.levelsMenu;
                _showVictory = false;
              });
              _startMusicSequencer();
            }),
          ],
        ),
      ),
    );
  }


    Widget _buildBtn(String text, VoidCallback onPressed, {bool isSecondary = false, double minWidth = 250}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: minWidth,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: isSecondary ? null : const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)]),
        color: isSecondary ? const Color(0xFF334155) : null,
        boxShadow: [
          BoxShadow(
            color: isSecondary ? Colors.black.withOpacity(0.25) : const Color(0xFF06B6D4).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        ),
        onPressed: onPressed,
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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

    // 4. Препятствия (Чёрные шипы и блоки)
    for (var obs in obstacles) {
      double renderX = obs.x - cameraX;
      if (renderX > -200 && renderX < (size.width / scale) + 200) {
        if (obs.type == 'spike') {
          bool isSpikeUpsideDown = (obs.y < 200);
          paint.color = const Color(0xFF0F172A);
          Path spikePath = Path();
          
          if (isSpikeUpsideDown) {
            spikePath.moveTo(renderX, obs.y);
            spikePath.lineTo(renderX + 30, obs.y);
            spikePath.lineTo(renderX + 15, obs.y + 30);
          } else {
            spikePath.moveTo(renderX, obs.y);
            spikePath.lineTo(renderX + 30, obs.y);
            spikePath.lineTo(renderX + 15, obs.y - 30);
          }
          spikePath.close();
          canvas.drawPath(spikePath, paint);

          paint.style = PaintingStyle.stroke;
          paint.color = const Color(0xFFF1F5F9);
          paint.strokeWidth = 2.5;
          canvas.drawPath(spikePath, paint);
          paint.style = PaintingStyle.fill;

          // ИСПРАВЛЕНИЕ: Заменяем тяжелый TextPainter знака (!) на быстрый векторный рисунок
          canvas.save();
          double time = DateTime.now().millisecondsSinceEpoch * 0.005;
          double pulse = 1.0 + math.sin(time) * 0.15;
          double markOffsetY = isSpikeUpsideDown ? 45 : -45;
          canvas.translate(renderX + 15, obs.y + markOffsetY);
          canvas.scale(pulse, pulse);
          
          paint.color = const Color(0xFFFACC15);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-2, -9, 4, 11), const Radius.circular(1.5)), paint);
          canvas.drawCircle(const Offset(0, 5), 2, paint);
          
          canvas.restore();
        } 
        else if (obs.type == 'platform') {
          paint.color = const Color(0xFF334155);
          canvas.drawRect(Rect.fromLTWH(renderX, obs.y, obs.w, obs.h), paint);
          
          paint.style = PaintingStyle.stroke;
          paint.color = const Color(0xFF475569);
          paint.strokeWidth = 3;
          canvas.drawRect(Rect.fromLTWH(renderX, obs.y, obs.w, obs.h), paint);
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
        
        // ИСПРАВЛЕНИЕ: Рисуем внутренний кристалл монеты геометрией холста
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

    // 5.1 Сферы (Орбы) 4 уровня
    if (currentLevel == 4) {
      for (var orb in orbs) {
        double renderX = orb.x - cameraX;
        if (!orb.collected && renderX > -50 && renderX < (size.width / scale) + 50) {
          canvas.save();
          canvas.translate(renderX, orb.y);
          
          double time = DateTime.now().millisecondsSinceEpoch * 0.003;
          double rotationAngle = time % (math.pi * 2);
          canvas.rotate(rotationAngle);
          
          paint.color = const Color(0xFFFACC15);
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
    }

        // ==========================================
    // ИСПРАВЛЕННЫЙ БЛОК 6: ШЛЕЙФ ДЛЯ ВСЕХ РЕЖИМОВ
    // ==========================================
    if (trailParticles.isNotEmpty) {
      canvas.save();
      for (int i = 0; i < trailParticles.length; i++) {
        // Рассчитываем плавное затухание от старых частиц к новым
        double alpha = (i / trailParticles.length) * 0.25;
        
        // Разделяем дизайн шлейфа под текущий режим игрока
        if (player.isShip) {
          paint.color = const Color(0xFFA855F7).withOpacity(alpha); // Фиолетовый для корабля
          double trailSize = 24;
          canvas.drawRect(
            Rect.fromLTWH(trailParticles[i].dx - cameraX - trailSize / 2, trailParticles[i].dy - trailSize / 2, trailSize, trailSize),
            paint,
          );
        } else {
          paint.color = const Color(0xFF00F2FE).withOpacity(alpha); // Неоново-бирюзовый для кубика
          double trailSize = 30;
          canvas.drawRect(
            Rect.fromLTWH(trailParticles[i].dx - cameraX - trailSize / 2, trailParticles[i].dy - trailSize / 2, trailSize, trailSize),
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
        
        // НАСТРОЙКА: Немного уменьшаем общий размер самолётика для маневренности
        double currentSize = player.size * 0.85; 
        double halfW = currentSize / 2; // Половина ширины (высоты треугольника)
        double halfH = currentSize / 2.6; // Уменьшаем высоту основания, чтобы сделать его уже

        // Равнобедренный треугольник, вытянутый вперед строго параллельно линии пола
        Path shipPath = Path()
          ..moveTo(-halfW, -halfH) // Верхний хвост (корма)
          ..lineTo(-halfW, halfH)  // Нижний хвост (корма)
          ..lineTo(halfW * 1.3, 0) // Вытянутый нос корабля (смотрит строго вправо по оси X)
          ..close();
        canvas.drawPath(shipPath, paint);

        paint.style = PaintingStyle.stroke;
        paint.color = Colors.white;
        paint.strokeWidth = 2.0;
        canvas.drawPath(shipPath, paint);
        paint.style = PaintingStyle.fill;
      } else {
        // Отрисовка кубика
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

          // ВЕКТОРНЫЕ СТРЕЛКИ ВМЕСТО ТЕКСТА (РАБОТАЮТ В 100 РАЗ БЫСТРЕЕ)
          paint.style = PaintingStyle.fill;
          paint.color = Colors.white;
          canvas.translate(x, 80); // Сдвиг к вершине портала

          Path arrowPath = Path();
          if (isEntering) {
            // Рисуем стрелку вниз ▼
            arrowPath.moveTo(-8, -5);
            arrowPath.lineTo(8, -5);
            arrowPath.lineTo(0, 7);
          } else {
            // Рисуем стрелку вверх ▲
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
        paint.color = const Color(0xFF4ADE80).withOpacity(p.alpha); // Неоново-зелёный цвет
        paint.style = PaintingStyle.fill;
        
        // Рисуем искры в виде аккуратных овалов, летящих из портала
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
    if (showPercent) {
      double barW = 250;
      double barH = 22;
      double barX = (size.width / scale) / 2 - barW / 2;
      double barY = 25;

      paint.color = const Color(0xFF0F172A).withOpacity(0.6);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), paint);

      paint.color = const Color(0xFF00F2FE);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW * (currentProgress / 100.0), barH), paint);

      // Кэшируем TextPainter локально внутри кадра (он один, это не бьет по FPS)
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

    canvas.restore(); // Сбрасываем глобальный масштаб
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
