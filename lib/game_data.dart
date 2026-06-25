import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Definition of a single purchasable upgrade.
class UpgradeDef {
  final String id;
  final String title;
  final String description;
  final int maxLevel;
  final int baseCost;
  final int costStep;

  const UpgradeDef({
    required this.id,
    required this.title,
    required this.description,
    required this.maxLevel,
    required this.baseCost,
    required this.costStep,
  });

  /// Cost to go from [currentLevel] to the next one.
  int costFor(int currentLevel) => baseCost + costStep * currentLevel;
}

/// All upgrades available in the shop.
const List<UpgradeDef> kUpgrades = [
  UpgradeDef(
    id: 'balls',
    title: 'Extra Balls',
    description: '+1 ball per round',
    maxLevel: 10,
    baseCost: 50,
    costStep: 40,
  ),
  UpgradeDef(
    id: 'split',
    title: 'Split Power',
    description: '+1 split per ball',
    maxLevel: 4,
    baseCost: 120,
    costStep: 150,
  ),
  UpgradeDef(
    id: 'mult',
    title: 'Score Boost',
    description: '+15% score multiplier',
    maxLevel: 10,
    baseCost: 80,
    costStep: 60,
  ),
  UpgradeDef(
    id: 'coins',
    title: 'Coin Magnet',
    description: '+1 coin per match',
    maxLevel: 10,
    baseCost: 70,
    costStep: 55,
  ),
  UpgradeDef(
    id: 'magnet',
    title: 'Zone Pull',
    description: 'Balls drift to matching zones',
    maxLevel: 5,
    baseCost: 150,
    costStep: 120,
  ),
];

/// Persistent player progression: coins, unlocked level, high score, upgrades.
class GameData extends ChangeNotifier {
  static const _kCoins = 'dz_coins';
  static const _kUnlocked = 'dz_unlocked';
  static const _kHighScore = 'dz_highscore';
  static const _kSound = 'dz_sound';
  static const _kUpgradePrefix = 'dz_up_';

  late SharedPreferences _prefs;
  bool _ready = false;
  bool get ready => _ready;

  int coins = 0;
  int unlockedLevel = 1;
  int highScore = 0;
  bool soundOn = true;
  final Map<String, int> _upgrades = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    coins = _prefs.getInt(_kCoins) ?? 0;
    unlockedLevel = _prefs.getInt(_kUnlocked) ?? 1;
    highScore = _prefs.getInt(_kHighScore) ?? 0;
    soundOn = _prefs.getBool(_kSound) ?? true;
    for (final u in kUpgrades) {
      _upgrades[u.id] = _prefs.getInt('$_kUpgradePrefix${u.id}') ?? 0;
    }
    _ready = true;
    notifyListeners();
  }

  int upgradeLevel(String id) => _upgrades[id] ?? 0;

  // --- Derived gameplay values from upgrades ---
  int get ballsPerRound => 8 + upgradeLevel('balls');
  int get splitBudget => 2 + upgradeLevel('split');
  double get scoreMultiplier => 1.0 + 0.15 * upgradeLevel('mult');
  int get coinsPerMatch => 1 + upgradeLevel('coins');
  double get magnetStrength => upgradeLevel('magnet') * 70.0;

  bool canUpgrade(UpgradeDef def) {
    final lvl = upgradeLevel(def.id);
    if (lvl >= def.maxLevel) return false;
    return coins >= def.costFor(lvl);
  }

  bool buyUpgrade(UpgradeDef def) {
    final lvl = upgradeLevel(def.id);
    if (lvl >= def.maxLevel) return false;
    final cost = def.costFor(lvl);
    if (coins < cost) return false;
    coins -= cost;
    _upgrades[def.id] = lvl + 1;
    _prefs.setInt(_kCoins, coins);
    _prefs.setInt('$_kUpgradePrefix${def.id}', lvl + 1);
    notifyListeners();
    return true;
  }

  void addCoins(int amount) {
    coins += amount;
    _prefs.setInt(_kCoins, coins);
    notifyListeners();
  }

  /// Called when a level is completed. Awards coins and unlocks the next level.
  void completeLevel(int level, int score, int coinsEarned) {
    coins += coinsEarned;
    _prefs.setInt(_kCoins, coins);
    if (level + 1 > unlockedLevel) {
      unlockedLevel = level + 1;
      _prefs.setInt(_kUnlocked, unlockedLevel);
    }
    if (score > highScore) {
      highScore = score;
      _prefs.setInt(_kHighScore, highScore);
    }
    notifyListeners();
  }

  void registerScore(int score) {
    if (score > highScore) {
      highScore = score;
      _prefs.setInt(_kHighScore, highScore);
      notifyListeners();
    }
  }

  void toggleSound() {
    soundOn = !soundOn;
    _prefs.setBool(_kSound, soundOn);
    notifyListeners();
  }
}

/// Per-level configuration derived deterministically from the level index.
class LevelConfig {
  final int level;
  final int targetScore;
  final int balls;
  final int zoneCount;
  final int splitterCount;
  final int mirrorCount;

  LevelConfig({
    required this.level,
    required this.targetScore,
    required this.balls,
    required this.zoneCount,
    required this.splitterCount,
    required this.mirrorCount,
  });

  factory LevelConfig.forLevel(int level, int ballsPerRound) {
    final zones = (3 + level ~/ 2).clamp(3, 6);
    final splitters = (2 + level).clamp(2, 9);
    final mirrors = (level ~/ 2).clamp(0, 6);
    // Tuned to be comfortably beatable once the player controls ball colors.
    final target = 450 + level * 230 + level * level * 35;
    return LevelConfig(
      level: level,
      targetScore: target,
      balls: ballsPerRound,
      zoneCount: zones,
      splitterCount: splitters,
      mirrorCount: mirrors,
    );
  }
}
