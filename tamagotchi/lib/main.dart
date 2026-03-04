import 'dart:async';
import 'dart:ui';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tamagotchi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5AD1C7),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7FAFB),
        appBarTheme: const AppBarTheme(centerTitle: true),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: const TamagotchiHome(),
    );
  }
}

enum PetStage { egg, baby, adult }

extension PetStageX on PetStage {
  String get label {
    switch (this) {
      case PetStage.egg:
        return '蛋';
      case PetStage.baby:
        return '寶寶';
      case PetStage.adult:
        return '成年';
    }
  }
}

class PetState {
  String name;
  PetStage stage;

  /// 0~100
  int hunger;

  /// 0~100
  int mood;

  int coins;

  /// 餅乾庫存（餵食會消耗）
  int cookies;

  /// 籃子等級：0=小籃子(預設), 1=中籃子(100), 2=大籃子(300)
  int basketLevel;

  /// 經驗值，用來長大
  int xp;

  DateTime lastOnline;

  PetState({
    required this.name,
    required this.stage,
    required this.hunger,
    required this.mood,
    required this.coins,
    required this.cookies,
    required this.basketLevel,
    required this.xp,
    required this.lastOnline,
  });
}

class TamagotchiHome extends StatefulWidget {
  const TamagotchiHome({super.key});

  @override
  State<TamagotchiHome> createState() => _TamagotchiHomeState();
}

class _TamagotchiHomeState extends State<TamagotchiHome>
    with TickerProviderStateMixin {
  Widget _prettyBackground({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withOpacity(0.10),
            cs.tertiary.withOpacity(0.08),
            cs.surface,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // subtle blobs
          Positioned(
            top: -90,
            left: -60,
            child: _Blob(color: cs.primary.withOpacity(0.18), size: 220),
          ),
          Positioned(
            bottom: -110,
            right: -80,
            child: _Blob(color: cs.tertiary.withOpacity(0.16), size: 260),
          ),
          child,
        ],
      ),
    );
  }

  Widget _stageBadge() {
    final cs = Theme.of(context).colorScheme;
    final label = pet.stage.label;
    final icon = switch (pet.stage) {
      PetStage.egg => '🥚',
      PetStage.baby => '🐣',
      PetStage.adult => '🐥',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(0.22)),
      ),
      child: Text(
        '$icon  $label',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }

  late PetState pet;
  Timer? _timer;

  late final AnimationController _petAnim;
  late final Animation<double> _handProgress;
  late final AnimationController _idleAnim;
  bool _showHand = false;

  static const int _maxStat = 100;

  // ====== 可調參數 ======
  // 每幾秒進行一次衰減/成長計算
  static const Duration _tick = Duration(seconds: 5);

  // 長時間沒陪伴：每分鐘心情下降多少(用「離線分鐘」計算)
  static const int _moodLossPerOfflineMin = 1;

  // 飽食度自然下降：每分鐘下降多少
  static const int _hungerLossPerMin = 1;

  // 每次撫摸增加的心情
  static const int _petMoodGain = 8;

  // 每次餵餅乾增加的飽食度
  static const int _cookieHungerGain = 18;

  // 餅乾價格
  static const int _cookiePrice = 10;

  // 成長門檻
  static const int _xpToBaby = 30;
  static const int _xpToAdult = 120;

  @override
  void initState() {
    super.initState();
    pet = PetState(
      name: '未命名',
      stage: PetStage.egg,
      hunger: 80,
      mood: 80,
      coins: 0,
      cookies: 0,
      basketLevel: 0,
      xp: 0,
      lastOnline: DateTime.now(),
    );

    // 進入 app 時，先把「離線時間」套用一次
    _applyOfflineDecay();

    // 之後用定時器做自然衰減
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      setState(() {
        _naturalDecay();
        _updateStage();
      });
    });

    _petAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _idleAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _handProgress = CurvedAnimation(
      parent: _petAnim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _petAnim.addStatusListener((status) {
      if (!mounted) return;
      if (status == AnimationStatus.completed) {
        _petAnim.reverse();
      } else if (status == AnimationStatus.dismissed) {
        setState(() => _showHand = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _petAnim.dispose();
    _idleAnim.dispose();
    super.dispose();
  }

  void _applyOfflineDecay() {
    final now = DateTime.now();
    final diff = now.difference(pet.lastOnline);
    final offlineMins = diff.inMinutes;

    if (offlineMins <= 0) {
      pet.lastOnline = now;
      return;
    }

    // 離線衰減：心情、飽食度
    final moodLoss = offlineMins * _moodLossPerOfflineMin;
    final hungerLoss = offlineMins * _hungerLossPerMin;

    pet.mood = _clamp(pet.mood - moodLoss);
    pet.hunger = _clamp(pet.hunger - hungerLoss);

    // 離線太久還會扣更多心情（簡單加重一點）
    if (offlineMins >= 60) {
      pet.mood = _clamp(pet.mood - 10);
    }

    pet.lastOnline = now;
    _updateStage();
  }

  void _naturalDecay() {
    // 每個 tick 當作 1 分鐘概念（方便 demo）
    pet.hunger = _clamp(pet.hunger - _hungerLossPerMin);

    // 如果很餓，心情掉更快
    final extraMoodLoss = pet.hunger <= 20 ? 2 : 0;
    pet.mood = _clamp(pet.mood - (_moodLossPerOfflineMin + extraMoodLoss));

    pet.lastOnline = DateTime.now();
  }

  void _updateStage() {
    if (pet.xp >= _xpToAdult) {
      pet.stage = PetStage.adult;
    } else if (pet.xp >= _xpToBaby) {
      pet.stage = PetStage.baby;
    } else {
      pet.stage = PetStage.egg;
    }
  }

  int _clamp(int v) => v.clamp(0, _maxStat);

  Color _statColor(int v) {
    if (v >= 70) return Colors.green;
    if (v >= 40) return Colors.orange;
    return Colors.red;
  }

  String _petEmoji() {
    switch (pet.stage) {
      case PetStage.egg:
        return '🥚';
      case PetStage.baby:
        return '🐣';
      case PetStage.adult:
        return '🐥';
    }
  }

  void _playPetAnimation() {
    setState(() => _showHand = true);
    _petAnim.forward(from: 0);
  }

  void _petAction() {
    if (pet.mood >= _maxStat) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('心情已滿（100），不需要再撫摸啦～')));
      return;
    }

    _playPetAnimation();
    HapticFeedback.lightImpact();
    setState(() {
      pet.mood = _clamp(pet.mood + _petMoodGain);
      pet.xp += 2;
      _updateStage();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('撫摸成功：心情上升！')));
  }

  void _feedCookie() {
    if (pet.hunger >= _maxStat) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('飽食度已滿（100），先別餵太飽～')));
      return;
    }

    if (pet.cookies <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('沒有餅乾了，去商店買一些吧！')));
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      pet.cookies -= 1;
      pet.hunger = _clamp(pet.hunger + _cookieHungerGain);
      pet.xp += 3;
      _updateStage();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('餵食成功：消耗 1 餅乾，飽食度上升！')));
  }

  Future<void> _openShop() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopPage(
          getCoins: () => pet.coins,
          getCookies: () => pet.cookies,
          getBasketLevel: () => pet.basketLevel,
          cookiePrice: _cookiePrice,
          onBuyCookie: () {
            if (pet.coins < _cookiePrice) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('金幣不夠，先去玩小遊戲賺錢吧！')));
              return false;
            }

            HapticFeedback.selectionClick();

            setState(() {
              pet.coins -= _cookiePrice;
              pet.cookies += 1;
            });

            return true;
          },
          onBuyBasket: (level, price) {
            if (pet.basketLevel >= level) return;

            // 先買中籃子(1) 才能買大籃子(2)
            if (level == 2 && pet.basketLevel < 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('要先買中籃子（100🪙）才能買大籃子喔！')),
              );
              return;
            }

            if (pet.coins < price) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('金幣不夠，先去玩小遊戲賺錢吧！')));
              return;
            }
            HapticFeedback.lightImpact();
            setState(() {
              pet.coins -= price;
              pet.basketLevel = level;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  level == 1 ? '已購買中籃子！接金幣更容易了～' : '已購買大籃子！接金幣大幅提升～',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _renamePet() async {
    final controller = TextEditingController(
      text: pet.name == '未命名' ? '' : pet.name,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('幫寵物取名字'),
          content: TextField(
            controller: controller,
            maxLength: 12,
            decoration: const InputDecoration(hintText: '輸入名字（最多 12 字）'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, name);
              },
              child: const Text('確定'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    setState(() {
      pet.name = result;
    });
  }

  Future<void> _openMinigame() async {
    final earned = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => CoinCatchGame(basketLevel: pet.basketLevel),
      ),
    );

    if (earned == null) return;

    setState(() {
      pet.coins += earned;
      pet.xp += max(1, earned ~/ 5);
      _updateStage();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('小遊戲結束：獲得 $earned 金幣！')));
  }

  @override
  Widget build(BuildContext context) {
    final hunger = pet.hunger;
    final mood = pet.mood;
    final bool canPet = mood < _maxStat;
    final bool canFeed = hunger < _maxStat;

    return Scaffold(
      appBar: AppBar(
        title: Text('${pet.name} · ${pet.stage.label}'),
        actions: [
          IconButton(
            tooltip: '商店',
            onPressed: _openShop,
            icon: const Icon(Icons.storefront),
          ),
          IconButton(
            tooltip: '改名',
            onPressed: _renamePet,
            icon: const Icon(Icons.edit),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _prettyBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ====== 中央：寵物置中（含撫摸動畫） ======
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.70),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withOpacity(0.35),
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 14,
                              right: 14,
                              child: _stageBadge(),
                            ),
                            Center(
                              child: GestureDetector(
                                onTap: canPet ? _petAction : null,
                                child: SizedBox(
                                  width: 240,
                                  height: 240,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // 寵物 (idle animation)
                                      AnimatedBuilder(
                                        animation: _idleAnim,
                                        builder: (context, child) {
                                          final sway =
                                              sin(_idleAnim.value * pi * 2) * 6;
                                          return Transform.translate(
                                            offset: Offset(sway, 0),
                                            child: AnimatedScale(
                                              duration: const Duration(
                                                milliseconds: 140,
                                              ),
                                              scale: _showHand ? 1.02 : 1.0,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Text(
                                          _petEmoji(),
                                          style: const TextStyle(fontSize: 120),
                                        ),
                                      ),

                                      // 撫摸手（動畫）
                                      if (_showHand)
                                        AnimatedBuilder(
                                          animation: _handProgress,
                                          builder: (_, __) {
                                            final t = _handProgress.value;
                                            final dx = lerpDouble(120, 12, t)!;
                                            final dy = lerpDouble(-40, 8, t)!;
                                            return Positioned(
                                              right: dx,
                                              top: dy,
                                              child: Transform.rotate(
                                                angle: lerpDouble(0.8, 0.2, t)!,
                                                child: const Text(
                                                  '🫳',
                                                  style: TextStyle(
                                                    fontSize: 68,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                      // 小提示
                                      Positioned(
                                        bottom: 6,
                                        child: Opacity(
                                          opacity: canPet ? 1 : 0.55,
                                          child: Text(
                                            canPet ? '點我也可以撫摸' : '心情已滿（100）',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ====== 狀態區（在底部按鈕上方） ======
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '🪙 ${pet.coins}   ·   🍪 ${pet.cookies}   ·   🧠 XP ${pet.xp}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _stageBadge(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _StatBar(
                          emoji: '🍪',
                          label: '飽食度',
                          value: hunger,
                          color: _statColor(hunger),
                        ),
                        const SizedBox(height: 10),
                        _StatBar(
                          emoji: '💛',
                          label: '心情',
                          value: mood,
                          color: _statColor(mood),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _statusHint(hunger, mood),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ====== 底部：三個一排（像 iPhone 底部那排） ======
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.70),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withOpacity(0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: _BottomAction(
                              icon: Icons.favorite,
                              label: '撫摸',
                              onTap: canPet ? _petAction : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _BottomAction(
                              icon: Icons.cookie,
                              label: '餵食',
                              onTap: canFeed ? _feedCookie : null,
                              subtitle: '${pet.cookies}🍪',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _BottomAction(
                              icon: Icons.videogame_asset,
                              label: '小遊戲',
                              onTap: _openMinigame,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusHint(int hunger, int mood) {
    if (hunger <= 15 && mood <= 25) return '牠又餓又不開心…快撫摸或餵食吧！';
    if (hunger <= 15) return '好餓…需要餵食！';
    if (mood <= 25) return '心情低落…多陪陪牠！';
    if (hunger >= 80 && mood >= 80) return '狀態超棒！繼續保持～';
    return '還不錯～偶爾互動一下吧。';
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 固定高度，讓三個按鈕一樣大（即使有/沒有 subtitle）
    return SizedBox(
      height: 96,
      child: FilledButton(
        onPressed: onTap,
        style:
            FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size.fromHeight(96),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ).copyWith(
              elevation: WidgetStateProperty.resolveWith<double>((states) {
                if (states.contains(WidgetState.disabled)) return 0;
                return 1.5;
              }),
              backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                final cs = Theme.of(context).colorScheme;
                if (states.contains(WidgetState.disabled)) {
                  return cs.surfaceContainerHighest.withOpacity(0.65);
                }
                return null; // default
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                states,
              ) {
                final cs = Theme.of(context).colorScheme;
                if (states.contains(WidgetState.disabled)) {
                  return cs.onSurface.withOpacity(0.45);
                }
                return null;
              }),
            ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
  });

  final String emoji;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            '$emoji $label',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value / 100.0,
              minHeight: 12,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            '$value%',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(width: size, height: size, color: color),
      ),
    );
  }
}

/// 小遊戲：接金幣
/// - 每次接到 +1 金幣
/// - 30 秒結束（或按返回）
class CoinCatchGame extends StatefulWidget {
  const CoinCatchGame({super.key, required this.basketLevel});

  final int basketLevel;

  @override
  State<CoinCatchGame> createState() => _CoinCatchGameState();
}

class _CoinCatchGameState extends State<CoinCatchGame> {
  final Random _rng = Random();

  Timer? _timer;
  Timer? _spawnTimer;

  // 玩家位置 0~1
  double _playerX = 0.5;

  // 金幣座標：x(0~1), y(0~1)
  final List<Offset> _coins = [];

  int _score = 0;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();

    // 物理更新：60ms 一次
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      setState(() {
        _step();
      });
    });

    // 生金幣：每 500ms 生成一顆
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() {
        _coins.add(Offset(_rng.nextDouble(), 0));
      });
    });

    // 倒數
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
      });
      if (_secondsLeft <= 0) {
        t.cancel();
        _endGame();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _spawnTimer?.cancel();
    super.dispose();
  }

  void _endGame() {
    _timer?.cancel();
    _spawnTimer?.cancel();
    if (!mounted) return;
    Navigator.pop(context, _score);
  }

  double get _catchHalfWidth {
    return switch (widget.basketLevel) {
      0 => 0.10,
      1 => 0.14,
      _ => 0.22,
    };
  }

  double get _minPlayerX => _catchHalfWidth;
  double get _maxPlayerX => 1.0 - _catchHalfWidth;

  void _step() {
    // coin 下落速度
    const double v = 0.018;

    // 玩家接取範圍
    const double catchY = 0.90;
    final double catchHalfWidth = _catchHalfWidth;

    for (int i = _coins.length - 1; i >= 0; i--) {
      final c = _coins[i];
      final next = Offset(c.dx, c.dy + v);

      // 到底了
      if (next.dy >= 1.05) {
        _coins.removeAt(i);
        continue;
      }

      // 判定接到
      if ((next.dy >= catchY) && (next.dy <= catchY + 0.06)) {
        final dx = (next.dx - _playerX).abs();
        if (dx <= catchHalfWidth) {
          _coins.removeAt(i);
          _score += 1;

          // SFX: 接到金幣音效（使用系統點擊音，不需額外套件）
          SystemSound.play(SystemSoundType.click);

          continue;
        }
      }

      _coins[i] = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('接金幣 · 分數 $_score · 剩 $_secondsLeft 秒'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _endGame),
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;

          // 將 0~1 座標轉像素
          Offset toPx(Offset p) => Offset(p.dx * w, p.dy * h);

          return GestureDetector(
            onHorizontalDragUpdate: (d) {
              setState(() {
                _playerX = (_playerX + d.delta.dx / w).clamp(
                  _minPlayerX,
                  _maxPlayerX,
                );
              });
            },
            onTapDown: (d) {
              // 點擊直接移動到點擊位置
              setState(() {
                _playerX = (d.localPosition.dx / w).clamp(
                  _minPlayerX,
                  _maxPlayerX,
                );
              });
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                ),

                // coins
                for (final coin in _coins)
                  Positioned(
                    left: toPx(coin).dx - 10,
                    top: toPx(coin).dy - 10,
                    child: const Text('🪙', style: TextStyle(fontSize: 22)),
                  ),

                // player
                Builder(
                  builder: (_) {
                    final double basketFontSize = switch (widget.basketLevel) {
                      0 => 40,
                      1 => 50,
                      _ => 72,
                    };

                    // Measure the emoji width so centering stays correct for different sizes.
                    final tp = TextPainter(
                      text: TextSpan(
                        text: '🧺',
                        style: TextStyle(fontSize: basketFontSize),
                      ),
                      textDirection: TextDirection.ltr,
                    )..layout();

                    final double halfW = tp.width / 2;

                    return Positioned(
                      left: _playerX * w - halfW,
                      top: h * 0.90,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.8, end: 1.0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) {
                          return Transform.scale(
                            scale: scale,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  if (widget.basketLevel > 0)
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.6),
                                      blurRadius: 18,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          '🧺',
                          style: TextStyle(fontSize: basketFontSize),
                        ),
                      ),
                    );
                  },
                ),

                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 28),
                    child: Text(
                      '操作：滑動左右或點擊移動，接到金幣 +1。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ShopPage extends StatelessWidget {
  const ShopPage({
    super.key,
    required this.getCoins,
    required this.getCookies,
    required this.getBasketLevel,
    required this.cookiePrice,
    required this.onBuyCookie,
    required this.onBuyBasket,
  });

  final int Function() getCoins;
  final int Function() getCookies;
  final int Function() getBasketLevel;

  final int cookiePrice;

  final bool Function() onBuyCookie;
  final void Function(int level, int price) onBuyBasket;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 使用 StatefulBuilder 讓 StatelessWidget 也可以局部刷新
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final coins = getCoins();
        final cookies = getCookies();
        final basketLevel = getBasketLevel();

        return Scaffold(
          appBar: AppBar(title: const Text('商店')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    '🪙 $coins   ·   🍪 $cookies   ·   籃子：${ShopPage._basketLabel(basketLevel)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),

                const SizedBox(height: 14),

                Text('道具', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),

                _ShopItemCard(
                  title: '餅乾',
                  subtitle: '餵食會消耗 1 餅乾，飽食度 +18',
                  price: '$cookiePrice🪙',
                  icon: '🍪',
                  onBuy: () {
                    final ok = onBuyCookie();
                    if (ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('購買成功！獲得 1 個餅乾 🍪')),
                      );
                      setLocalState(() {});
                    }
                  },
                ),

                const SizedBox(height: 14),

                Text(
                  '籃子升級（接金幣更容易）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),

                const SizedBox(height: 8),

                _ShopItemCard(
                  title: '中籃子',
                  subtitle: '接取範圍變大，籃子變大',
                  price: '100🪙',
                  icon: '🧺',
                  disabled: basketLevel >= 1,
                  onBuy: () {
                    onBuyBasket(1, 100);
                    setLocalState(() {});
                  },
                ),

                const SizedBox(height: 10),

                _ShopItemCard(
                  title: '大籃子',
                  subtitle: basketLevel < 1 ? '🔒 需先購買中籃子' : '接取範圍大幅提升，籃子更大',
                  price: '300🪙',
                  icon: '🧺',
                  disabled: basketLevel < 1 || basketLevel >= 2,
                  disabledLabel: basketLevel < 1 ? '請先解鎖中籃子' : '已擁有',
                  onBuy: () {
                    if (basketLevel < 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('要先買中籃子（100🪙）才能買大籃子喔！')),
                      );
                      return;
                    }
                    onBuyBasket(2, 300);
                    setLocalState(() {});
                  },
                ),

                const Spacer(),

                Text(
                  '提示：籃子升級會直接影響小遊戲的接取範圍。',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _basketLabel(int level) {
    return switch (level) {
      0 => '小籃子',
      1 => '中籃子',
      _ => '大籃子',
    };
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.icon,
    required this.onBuy,
    this.disabled = false,
    this.disabledLabel,
  });

  final String title;
  final String subtitle;
  final String price;
  final String icon;
  final VoidCallback onBuy;
  final bool disabled;
  final String? disabledLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: disabled ? null : onBuy,
              child: Text(disabled ? (disabledLabel ?? '已擁有') : '購買 $price'),
            ),
          ],
        ),
      ),
    );
  }
}
