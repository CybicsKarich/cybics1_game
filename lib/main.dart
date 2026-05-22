import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Фиксируем ориентацию экрана горизонтально, как в оригинале
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

// Перечисления для экранов
enum GameState { mainMenu, levelsMenu, settingsMenu, gameplay }

// Модели объектов игры
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
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  GameState _state = GameState.mainMenu;
  
  // Хранилище настроек и рекордов
  late SharedPreferences _prefs;
  int _maxProgress = 0, _maxProgress2 = 0, _maxProgress3 = 0;
  int _attempts1 = 0, _attempts2 = 0, _attempts3 = 0;
  List<bool> _savedMedals1 = [false];
  List<bool> _savedMedals2 = [false, false];
  List<bool> _savedMedals3 = [false, false, false];

  // Аудио-плееры под каждый трек
  final AudioPlayer _menuPlayer = AudioPlayer();
  final AudioPlayer _level1Player = AudioPlayer();
  final AudioPlayer _level2Player = AudioPlayer();
  final AudioPlayer _level3Player = AudioPlayer();
  final AudioPlayer _deathPlayer = AudioPlayer();

  double _volume = 50.0;
  bool _showPercent = true;

  // Игровые переменные
  int _currentLevel = 1;
  int _currentRunAttempts = 1;
  bool _isGodMode = false;
  int _titleClicks = 0;
  bool _isPlaying = false;
  bool _isPaused = false;
  
  // Физические константы
  final double _levelLength = 20000;
  final double _gameHeight = 600;
  final double _floorY = 500;
  
  Player _player = Player();
  double _cameraX = 0;
  List<Obstacle> _obstacles = [];
  List<Medal> _medals = [];
  List<Offset> _trailParticles = [];
  List<BgItem> _bgItems = [];
  List<int> _collectedThisRun = [];
  int _currentProgress = 0;
  bool _isPressing = false;

  // Оверлеи
  bool _showNewRecord = false;
  bool _showVictory = false;

  // Игровой таймер (60 кадров в секунду)
  Timer? _gameTimer;
  late AnimationController _pulseController;

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
      _attempts1 = _prefs.getInt('cybics_attempts_1') ?? 0;
      _attempts2 = _prefs.getInt('cybics_attempts_2') ?? 0;
      _attempts3 = _prefs.getInt('cybics_attempts_3') ?? 0;
      _volume = _prefs.getDouble('cybics_volume') ?? 50.0;
      _showPercent = _prefs.getBool('cybics_show_percent') ?? true;

      String? m1 = _prefs.getString('cybics_medals_1');
      if (m1 != null) _savedMedals1 = List<bool>.from(jsonDecode(m1));
      String? m2 = _prefs.getString('cybics_medals_2');
      if (m2 != null) _savedMedals2 = List<bool>.from(jsonDecode(m2));
      String? m3 = _prefs.getString('cybics_medals_3');
      if (m3 != null) _savedMedals3 = List<bool>.from(jsonDecode(m3));
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
    _deathPlayer.setVolume(vol * 0.5);
  }

  // --- МУЗЫКАЛЬНЫЙ СЕКВЕНСОР MP3 ---
    // --- МУЗЫКАЛЬНЫЙ СЕКВЕНСОР MP3 (ИСПРАВЛЕННЫЙ) ---
  void _startMusicSequencer() async {
    try {
      // Настраиваем зацикливание треков
      await _menuPlayer.setReleaseMode(ReleaseMode.loop);
      await _level1Player.setReleaseMode(ReleaseMode.loop);
      await _level2Player.setReleaseMode(ReleaseMode.loop);
      await _level3Player.setReleaseMode(ReleaseMode.loop);

      if (_state == GameState.gameplay) {
        await _menuPlayer.stop();
        await _stopAllLevelTracks();

        if (!_isPaused) {
          if (_currentLevel == 1) {
            await _level1Player.play(AssetSource('level1.mp3'));
          } else if (_currentLevel == 2) {
            await _level2Player.play(AssetSource('level2.mp3'));
          } else if (_currentLevel == 3) {
            await _level3Player.play(AssetSource('level3.mp3'));
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
    } catch (e) {
      debugPrint("Ошибка остановки треков: $e");
    }
  }


  void _playDeathSound() async {
    // Воспроизведение короткого звука смерти
    await _deathPlayer.play(AssetSource('death.mp3'));
  }

  double _seededRandom(int seed) {
    double x = math.sin(seed.toDouble()) * 10000;
    return x - x.floorToDouble();
  }

  // --- ПРОЦЕДУРНАЯ ГЕНЕРАЦИЯ УРОВНЕЙ ---
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
          // ЗОНА КУБИКА (УРОВЕНЬ 3)
          
          // Выход из самолетика (71% - 77.5% прогресса)
          if (progressPct >= 71 && progressPct < 77.5) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 30, w: 120, h: 30));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 260, y: _floorY));
            nextX += 450;
          } 
          // Подвесной коридор строго от 30% до 36% прогресса
          else if (progressPct >= 30 && progressPct < 36) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 60, w: 220, h: 20));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 20, y: 0, w: 180, h: _floorY - 150));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 260, y: _floorY - 110));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 260, y: 0, w: 30, h: _floorY - 110));
            nextX += 580;
          } 
          // Предпортальный каскад ступеней (между 36% и 40%)
          else if (progressPct >= 36 && progressPct < 40) {
            _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 40, w: 80, h: 40));
            _obstacles.add(Obstacle(type: 'spike', x: nextX + 110, y: _floorY));
            _obstacles.add(Obstacle(type: 'platform', x: nextX + 170, y: _floorY - 80, w: 80, h: 80));
            nextX += 450;
          } 
          // Секретная цепочка финальных платформ на 77.5%
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
          // Начальная ловушка-лестница строго 1 раз (от 6% до 15%)
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
            _medals.add(Medal(id: 0, x: nextX + (2 * 180) - 10, y: _floorY - 30));
            nextX += (6 * 180) + 40 + 350;
            spawnedTrap = true;
          } 
          // Обычные случайные паттерны для кубика
          else {
            double r = _seededRandom(seed++);
            if (r < 0.25) {
              _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 30, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 60, y: _floorY));
              nextX += 500;
            } else if (r < 0.50) {
              _obstacles.add(Obstacle(type: 'platform', x: nextX, y: _floorY - 40, w: 100, h: 40));
              _obstacles.add(Obstacle(type: 'platform', x: nextX + 180, y: _floorY - 100, w: 120, h: 100));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 260, y: _floorY - 100));
              nextX += 550;
            } else if (r < 0.75) {
              _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
              _obstacles.add(Obstacle(type: 'platform', x: nextX + 40, y: _floorY - 60, w: 200, h: 60));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 280, y: _floorY));
              nextX += 520;
            } else {
              _obstacles.add(Obstacle(type: 'spike', x: nextX, y: _floorY));
              _obstacles.add(Obstacle(type: 'spike', x: nextX + 30, y: _floorY));
              _obstacles.add(Obstacle(type: 'platform', x: nextX + 180, y: _floorY - 80, w: 80, h: 80));
              nextX += 480;
            }
          }
        }
      }
      _medals.add(Medal(id: 0, x: _levelLength * 0.15, y: _floorY - 120));
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
    });

    _startMusicSequencer();
    _startLevel();
  }

  void _startLevel() {
    _gameTimer?.cancel();
    setState(() {
      _cameraX = 0;
      _currentProgress = 0;
      _trailParticles.clear();
      _collectedThisRun.clear();
      _showVictory = false;
      _showNewRecord = false;
      
      _player = Player()..y = _floorY - 40;

      // Инициализация плавного фона (15 предметов)
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

    // Запуск цикла 60 FPS (примерно каждые 16 мс)
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_isPlaying && !_isPaused) {
        _updatePhysics();
      }
    });
  }

  void _updatePhysics() {
    setState(() {
      _player.x += 7.5;
      _cameraX = _player.x - 200;

      _trailParticles.add(Offset(_player.x + _player.size / 2, _player.y + _player.size / 2));
      if (_trailParticles.length > 15) _trailParticles.removeAt(0);

      double progressPct = (_player.x / _levelLength) * 100;
      _player.isShip = ((_currentLevel == 2 || _currentLevel == 3) && progressPct >= 40 && progressPct <= 75);

      if (_player.isShip) {
        if (_isPressing) _player.vy -= 0.9; else _player.vy += 0.7;
        _player.vy = _player.vy.clamp(-8, 8);
        _player.y += _player.vy;
        _player.isGrounded = false;
        if (_player.y <= 100) { _player.y = 100; _player.vy = 0; }
        _player.rotation = _player.vy * 0.04;
      } else {
        _player.vy += _player.gravity;
        _player.y += _player.vy;
        _player.isGrounded = false;
      }

      if (_player.y >= _floorY - _player.size) {
        _player.y = _floorY - _player.size;
        _player.vy = 0;
        _player.isGrounded = true;
      }

      _currentProgress = (progressPct.clamp(0, 100)).floor();

      // Сбор медалек
      for (var m in _medals) {
        if (!m.collected) {
          double distX = ((_player.x + _player.size / 2) - m.x).abs();
          double distY = ((_player.y + _player.size / 2) - m.y).abs();
          if (distX < 35 && distY < 35) {
            m.collected = true;
            if (!_collectedThisRun.contains(m.id)) _collectedThisRun.add(m.id);
          }
        }
      }

      // Проверка столкновений
      for (var obs in _obstacles) {
        if (obs.type == 'spike') {
          if (_player.x + _player.size > obs.x + 8 && _player.x < obs.x + 22 &&
              ((obs.y == _floorY && _player.y + _player.size > obs.y - 30 && _player.y < obs.y) ||
               (obs.y != _floorY && _player.y < obs.y && _player.y + _player.size > obs.y - 30))) {
            if (!_isGodMode) {
              _gameOver();
              return;
            }
          }
        } else if (obs.type == 'platform') {
          if (_player.x + _player.size > obs.x + 4 && _player.x < obs.x + obs.w - 4 &&
              _player.y + _player.size >= obs.y &&
              _player.y + _player.size <= obs.y + 20 &&
              _player.vy >= 0) {
            _player.y = obs.y - _player.size;
            _player.vy = 0;
            _player.isGrounded = true;
          } 
          else if (_player.x + _player.size > obs.x &&
                   _player.x < obs.x + obs.w &&
                   _player.y + _player.size > obs.y + 15 &&
                   _player.y < obs.y + obs.h) {
            if (!_isGodMode) {
              _gameOver();
              return;
            }
          }
        }
      }

      if (!_player.isShip && _isPressing && _player.isGrounded) {
        _player.vy = _player.jumpForce;
        _player.isGrounded = false;
      }

      if (!_player.isShip) {
        if (!_player.isGrounded) {
          _player.rotation += 0.08;
        } else {
          _player.rotation = (_player.rotation / (math.pi / 2)).round() * (math.pi / 2);
        }
      }

      // Достижение финиша
      if (_player.x >= _levelLength) {
        _gameTimer?.cancel();
        _isPlaying = false;
        _showVictory = true;
        
        if (_currentLevel == 1) {
          _maxProgress = 100; _prefs.setInt('cybics_max_progress', 100);
          for (var id in _collectedThisRun) _savedMedals1[id] = true;
          _prefs.setString('cybics_medals_1', jsonEncode(_savedMedals1));
        } else if (_currentLevel == 2) {
          _maxProgress2 = 100; _prefs.setInt('cybics_max_progress_2', 100);
          for (var id in _collectedThisRun) _savedMedals2[id] = true;
          _prefs.setString('cybics_medals_2', jsonEncode(_savedMedals2));
        } else {
          _maxProgress3 = 100; _prefs.setInt('cybics_max_progress_3', 100);
          for (var id in _collectedThisRun) _savedMedals3[id] = true;
          _prefs.setString('cybics_medals_3', jsonEncode(_savedMedals3));
        }
        _stopAllLevelTracks();
      }
    });
  }

  void _gameOver() {
    _gameTimer?.cancel();
    _playDeathSound();
    bool isNewRecord = false;

    if (_currentLevel == 1 && _currentProgress > _maxProgress && _currentProgress < 100) {
      _maxProgress = _currentProgress; _prefs.setInt('cybics_max_progress', _maxProgress); isNewRecord = true;
    } else if (_currentLevel == 2 && _currentProgress > _maxProgress2 && _currentProgress < 100) {
      _maxProgress2 = _currentProgress; _prefs.setInt('cybics_max_progress_2', _maxProgress2); isNewRecord = true;
    } else if (_currentLevel == 3 && _currentProgress > _maxProgress3 && _currentProgress < 100) {
      _maxProgress3 = _currentProgress; _prefs.setInt('cybics_max_progress_3', _maxProgress3); isNewRecord = true;
    }

    if (isNewRecord) {
      setState(() { _showNewRecord = true; });
      Timer(const Duration(milliseconds: 1200), () {
        _registerNewAttempt();
        _startLevel();
      });
    } else {
      _registerNewAttempt();
      _startLevel();
    }
  }

  void _registerNewAttempt() {
    setState(() {
      _currentRunAttempts++;
      if (!_isGodMode) {
        if (_currentLevel == 1 && _maxProgress < 100) { _attempts1++; _prefs.setInt('cybics_attempts_1', _attempts1); }
        if (_currentLevel == 2 && _maxProgress2 < 100) { _attempts2++; _prefs.setInt('cybics_attempts_2', _attempts2); }
        if (_currentLevel == 3 && _maxProgress3 < 100) { _attempts3++; _prefs.setInt('cybics_attempts_3', _attempts3); }
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
        width: 230,
        padding: const EdgeInsets.all(16),
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
                  child: Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: borderColor)),
                ),
                Text('Попыток: $attempts', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: medals.map((collected) => Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: Opacity(opacity: collected ? 1.0 : 0.2, child: const Text('🥇', style: TextStyle(fontSize: 16))),
              )).toList(),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(height: 16, color: const Color(0xFF334155)),
                  FractionallySizedBox(
                    widthFactor: progress / 100.0,
                    child: Container(height: 16, color: borderColor),
                  ),
                  Center(child: Text('$progress%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
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
                )
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
      onPointerDown: (_) => setState(() { _isPressing = true; }),
      onPointerUp: (_) => setState(() { _isPressing = false; }),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GamePainter(
                player: _player,
                cameraX: _cameraX,
                obstacles: _obstacles,
                medals: _medals,
                trailParticles: _trailParticles,
                bgItems: _bgItems,
                currentLevel: _currentLevel,
                levelLength: _levelLength,
                floorY: _floorY,
                gameHeight: _gameHeight,
                currentProgress: _currentProgress,
                showPercent: _showPercent,
              ),
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
    int currentRecord = _currentLevel == 1 ? _maxProgress : (_currentLevel == 2 ? _maxProgress2 : _maxProgress3);
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
            const Text('УРОВЕНЬ ПРОЙДЕН!', style: TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: Color(0xFF22C55E), letterSpacing: 4)),
            const SizedBox(height: 10),
            const Text('Новый рекорд: 100%', style: TextStyle(fontSize: 24, color: Colors.white70)),
            const SizedBox(height: 40),
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
    _pulseController.dispose();
    _menuPlayer.dispose();
    _level1Player.dispose();
    _level2Player.dispose();
    _level3Player.dispose();
    _deathPlayer.dispose();
    super.dispose();
  }
}

// --- ОТРИСОВКА ИГРЫ (CUSTOM PAINTER) ---
class GamePainter extends CustomPainter {
  final Player player;
  final double cameraX;
  final List<Obstacle> obstacles;
  final List<Medal> medals;
  final List<Offset> trailParticles;
  final List<BgItem> bgItems;
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
    required this.currentLevel,
    required this.levelLength,
    required this.floorY,
    required this.gameHeight,
    required this.currentProgress,
    required this.showPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Рассчитываем глобальное масштабирование под текущую высоту экрана
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

    // 4. Препятствия (Чёрные шипы и блоки с восклицательными знаками)
    for (var obs in obstacles) {
      double renderX = obs.x - cameraX;
      if (renderX > -200 && renderX < (size.width / scale) + 200) {
        if (obs.type == 'spike') {
          // Угольно-чёрное тело шипа
          paint.color = const Color(0xFF0F172A);
          Path spikePath = Path()
            ..moveTo(renderX, obs.y)
            ..lineTo(renderX + 30, obs.y)
            ..lineTo(renderX + 15, obs.y - 30)
            ..close();
          canvas.drawPath(spikePath, paint);

          // Светлая рамка
          paint.style = PaintingStyle.stroke;
          paint.color = const Color(0xFFF1F5F9);
          paint.strokeWidth = 2.5;
          canvas.drawPath(spikePath, paint);
          paint.style = PaintingStyle.fill;

          // Восклицательный знак НАД шипом с пульсацией
          canvas.save();
          double time = DateTime.now().millisecondsSinceEpoch * 0.005;
          double pulse = 1.0 + math.sin(time) * 0.15;
          
          canvas.translate(renderX + 15, obs.y - 45);
          canvas.scale(pulse, pulse);
          
          TextPainter textPainter = TextPainter(
            text: const TextSpan(
              text: '!',
              style: TextStyle(color: Color(0xFFFACC15), fontSize: 20, fontWeight: FontWeight.bold),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
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
        paint.style = PaintingStyle.fill;

        TextPainter textPainter = TextPainter(
          text: const TextSpan(text: 'C', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(renderX - textPainter.width / 2, m.y - textPainter.height / 2));
      }
    }

    // 6. Неоновый широкий прозрачный шлейф
    if (trailParticles.isNotEmpty) {
      canvas.save();
      for (int i = 0; i < trailParticles.length; i++) {
        double alpha = (i / trailParticles.length) * 0.25;
        paint.color = player.isShip ? const Color(0xFFA855F7).withOpacity(alpha) : const Color(0xFF00F2FE).withOpacity(alpha);
        double trailSize = player.isShip ? 24 : 30;

        canvas.drawRect(
          Rect.fromLTWH(trailParticles[i].dx - cameraX - trailSize / 2, trailParticles[i].dy - trailSize / 2, trailSize, trailSize),
          paint,
        );
      }
      canvas.restore();
    }

    // 7. Отрисовка игрока (Кубик или Корабль)
    canvas.save();
    canvas.translate(player.x - cameraX + player.size / 2, player.y + player.size / 2);
    canvas.rotate(player.rotation);

    if (player.isShip) {
      paint.color = const Color(0xFFC084FC);
      Path shipPath = Path()
        ..moveTo(-player.size / 2, 0)
        ..lineTo(player.size / 2, -player.size / 4)
        ..lineTo(player.size / 4, player.size / 2)
        ..close();
      canvas.drawPath(shipPath, paint);

      paint.style = PaintingStyle.stroke;
      paint.color = Colors.white;
      paint.strokeWidth = 2;
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

    // 8. Фиолетовые порталы смены режима
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

    // 9. Портал финиша (Зелёный)
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

    // 10. Шкала процентов
    if (showPercent) {
      double barW = 250;
      double barH = 22;
      double barX = (size.width / scale) / 2 - barW / 2;
      double barY = 25;

      paint.color = const Color(0xFF0F172A).withOpacity(0.6);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), paint);

      paint.color = const Color(0xFF00F2FE);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW * (currentProgress / 100.0), barH), paint);

      TextPainter textPainter = TextPainter(
        text: TextSpan(text: '$currentProgress%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(barX + barW / 2 - textPainter.width / 2, barY + barH / 2 - textPainter.height / 2));
    }

    canvas.restore(); // Сбрасываем глобальный scale, перед выходом из drawGame
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
