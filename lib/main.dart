import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'auth_stats_api.dart';
import 'stats_repository.dart';
import 'breathe_api.dart';
import 'session_page.dart';
import 'stats_page.dart';
import 'profile_page.dart';
import 'audio_page.dart';
import 'garden_page.dart';
import 'selection.dart';
import 'vitals_service.dart';
import 'auth_service.dart';


final AuthService auth = AuthService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF1A3F30),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(
    MultiProvider(
      providers: [
        // One shared BLE connection for every page (home, breathing session...).
        ChangeNotifierProvider(create: (_) => VitalsService()),
        // Collects band data in the background and syncs it every minute.
        // lazy: false so it starts with the app, not when the Stats tab opens.
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) => StatsRepository(
            vitals: ctx.read<VitalsService>(),
            api: AuthStatsApi(),
          ),
        ),
      ],
      child: const BreatheApp(),
    ),
  );
}

/// ---------------------------------------------------------------------------
/// AUTHENTICATION GATE
/// ---------------------------------------------------------------------------
/// On launch, initialize Google Sign-In and validate any saved refresh token.
/// A valid session goes straight to the existing app. Otherwise show login.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _signedIn = false;
  bool _signingIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeAndRestore();
  }

  Future<void> _initializeAndRestore() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await auth.init();
      final restored = await auth.restoreSession();
      if (!mounted) return;
      setState(() {
        _signedIn = restored;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _error = null;
    });

    try {
      await auth.signInWithGoogle();

      // Verify that the newly issued app session can access the protected API.
      final response = await auth.authedGet('/api/me');
      if (response.statusCode != 200) {
        throw AuthException(
          'Login succeeded, but account verification failed '
          '(${response.statusCode}): ${response.body}',
        );
      }

      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _signingIn = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _AuthLoadingScreen();
    }

    if (_signedIn) {
      return Builder(
        builder: (context) => ModeSelectionScreen(
          plantsBuilder: (_) => const RootShell(),
          onSpace: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const RootShell(),
              ),
            );
          },
        ),
      );
    }

    return _GoogleLoginScreen(
      busy: _signingIn,
      error: _error,
      onSignIn: _signIn,
      onRetry: _initializeAndRestore,
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0E2217),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF8FE3A5)),
            SizedBox(height: 18),
            Text(
              'Checking your session…',
              style: TextStyle(color: Color(0xFFA6DDB8), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleLoginScreen extends StatelessWidget {
  final bool busy;
  final String? error;
  final VoidCallback onSignIn;
  final VoidCallback onRetry;

  const _GoogleLoginScreen({
    required this.busy,
    required this.error,
    required this.onSignIn,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E2217),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C4636), Color(0xFF0E2217)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: const Color(0x331F4A3A),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFF2E6B52),
                          width: 1.4,
                        ),
                      ),
                      child: const Icon(
                        Icons.spa_rounded,
                        size: 46,
                        color: Color(0xFF8FE3A5),
                      ),
                    ),
                    const SizedBox(height: 25),
                    const Text(
                      'Welcome to Vento+',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFF3F7F2),
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Sign in to continue your breathing journey.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFA6DDB8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: busy ? null : onSignIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8FE3A5),
                          foregroundColor: const Color(0xFF0F2A1C),
                          disabledBackgroundColor:
                              const Color(0xFF638B70),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.3,
                                  color: Color(0xFF0F2A1C),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'G',
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF4285F4),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Continue with Google',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0x33D98B5F),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0x99D98B5F),
                          ),
                        ),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFFD5BC),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      if (error!.contains('API_BASE') ||
                          error!.contains('GOOGLE_WEB_CLIENT_ID')) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: onRetry,
                          child: const Text(
                            'Retry configuration',
                            style: TextStyle(color: Color(0xFFA6DDB8)),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// THEME
/// ---------------------------------------------------------------------------
class AppColors {
  static const bgTop = Color(0xFF1C4636);
  static const bgBottom = Color(0xFF0E2217);
  static const card = Color(0xFF1F4A3A);
  static const cardBorder = Color(0xFF2E6B52);
  static const tile = Color(0xFF1F4A3A);
  static const mint = Color(0xFF8FE3A5);
  static const mintText = Color(0xFFA6DDB8);
  static const white = Color(0xFFF3F7F2);
  static const dark = Color(0xFF0F2A1C);
  static const amber = Color(0xFFF2C47E);
  static const navBg = Color(0xFF1A3F30);
  static const terracotta = Color(0xFFD98B5F);
}

const String kSerif = 'Lato';
const List<String> kSerifFallback = ['sans-serif'];

class BreatheApp extends StatelessWidget {
  const BreatheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vento+',
      theme: ThemeData(
        fontFamily: 'Lato',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bgBottom,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      // Authentication is checked before showing the existing app flow.
      home: const AuthGate(),
    );
  }
}

/// ---------------------------------------------------------------------------
/// MODEL
/// ---------------------------------------------------------------------------
enum TechniqueStatus { notCollected, collected, grown }

enum PlantType { spiky, purple, bush, mushroom }

// Use the same plant assets as the Garden page. The API's plant_key is
// carried on Technique so every breathing exercise displays its own plant.
const Map<String, String> _techniquePlantImages = {
  'sunflower': 'assets/images/plants/sunflower.png',
  'periwinkle': 'assets/images/plants/periwinkle.png',
  'bhrama': 'assets/images/plants/bhrama.png',
  'rose': 'assets/images/plants/rose.png',
  'tulips': 'assets/images/plants/tulips.png',
  'dhalia': 'assets/images/plants/dhalia.png',
  'orchids': 'assets/images/plants/orchids.png',
  'daisy': 'assets/images/plants/daisy.png',
  'forget_me_not': 'assets/images/plants/forget_me_not.png',
};

String? _plantAssetForKey(String? plantKey) {
  final key = (plantKey ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_');
  return _techniquePlantImages[key];
}

Widget _techniquePlantImage(String? plantKey, {double size = 44}) {
  final assetPath = _plantAssetForKey(plantKey);
  if (assetPath == null) {
    return Icon(Icons.local_florist, size: size * 0.7, color: AppColors.mint);
  }
  return Image.asset(
    assetPath,
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) => Icon(
      Icons.broken_image_outlined,
      size: size * 0.7,
      color: AppColors.mintText,
    ),
  );
}

int _minutesFromSeconds(int seconds) => math.max(1, (seconds / 60).round());

/// Maps the API's plant_key to the plant drawn by PlantIcon.
PlantType _plantTypeForKey(String? key) {
  switch (key) {
    case 'lavender':
      return PlantType.purple;
    case 'shrub':
      return PlantType.bush;
    case 'clover':
      return PlantType.mushroom;
    case 'succulent':
    case 'fern':
    default:
      return PlantType.spiky;
  }
}

/// Maps the API's plant stage. "flourishing" is shown as grown + isFinalStage.
TechniqueStatus _statusForStage(String? stage) {
  switch (stage) {
    case 'collected':
      return TechniqueStatus.collected;
    case 'grown':
    case 'flourishing':
      return TechniqueStatus.grown;
    case 'not_collected':
    default:
      return TechniqueStatus.notCollected;
  }
}

class Technique {
  final String name;
  final String pattern;
  final int minutes;
  final TechniqueStatus status;
  final int progress;
  final int goal;
  final PlantType plant;

  // Filled in when the data comes from the API.
  final int? id;
  final String? slug;
  final String? plantKey;
  final String? description;
  final List<ApiPhase> phases;
  final bool isFinalStage; // "flourishing": the plant can't grow further
  final int? targetDurationSec;

  // Set when this technique is opened for a specific server session.
  // SessionPage can read these (e.g. resume the timer from elapsedSec).
  final String? sessionId;
  final int elapsedSec;

  const Technique({
    required this.name,
    required this.pattern,
    required this.minutes,
    required this.status,
    required this.plant,
    this.progress = 0,
    this.goal = 10,
    this.id,
    this.slug,
    this.plantKey,
    this.description,
    this.phases = const [],
    this.isFinalStage = false,
    this.targetDurationSec,
    this.sessionId,
    this.elapsedSec = 0,
  });

  factory Technique.fromApi(ApiTechnique t) {
    final p = t.progress;
    return Technique(
      id: t.id,
      slug: t.slug,
      plantKey: t.plantKey,
      name: t.name,
      description: t.description,
      pattern: t.pattern,
      minutes: _minutesFromSeconds(t.defaultDurationSec),
      status: _statusForStage(p?.stage),
      plant: _plantTypeForKey(t.plantKey),
      progress: p?.progressToNext ?? 0,
      goal: p?.sessionsPerStage ?? 10,
      isFinalStage: p?.stage == 'flourishing',
      phases: t.phases,
      targetDurationSec: t.defaultDurationSec,
    );
  }

  /// Fallback when a session's technique isn't in the active list.
  factory Technique.fromSession(ApiSession s) => Technique(
        id: s.techniqueId,
        slug: s.techniqueSlug,
        plantKey: s.techniquePlantKey,
        name: s.techniqueName,
        pattern: s.pattern,
        minutes: _minutesFromSeconds(s.targetDurationSec),
        status: TechniqueStatus.collected,
        plant: _plantTypeForKey(s.techniquePlantKey),
        phases: s.phases,
        targetDurationSec: s.targetDurationSec,
        sessionId: s.id,
        elapsedSec: s.elapsedSec,
      );

  /// Same technique, tied to a server session (uses the session's snapshot).
  Technique withSession(ApiSession s) => Technique(
        name: name,
        pattern: s.pattern,
        minutes: _minutesFromSeconds(s.targetDurationSec),
        status: status,
        plant: plant,
        progress: progress,
        goal: goal,
        id: id ?? s.techniqueId,
        slug: slug ?? s.techniqueSlug,
        plantKey: plantKey ?? s.techniquePlantKey,
        description: description,
        phases: s.phases,
        isFinalStage: isFinalStage,
        targetDurationSec: s.targetDurationSec,
        sessionId: s.id,
        elapsedSec: s.elapsedSec,
      );

  String get subtitle {
    final base = '$pattern · $minutes min';
    switch (status) {
      case TechniqueStatus.notCollected:
        return '$base · Not collected yet';
      case TechniqueStatus.collected:
        return '$base · Collected';
      case TechniqueStatus.grown:
        return isFinalStage ? '$base · Flourishing' : '$base · Grown';
    }
  }
}

/// Placeholder data. The home screen now loads techniques, streak and the
/// last session from the API, and the vitals from the ESP32 band
/// (see VitalsService). Kept because other pages may still reference it.
class HomeData {
  static const String greeting = 'Good evening';
  static const String title = 'Vento+';
  static const String streakLabel = '7-day streak';
  static const String breathRate = '14 /min';
  static const String oxygen = '98%';
  static const String heartRate = '72 bpm';

  static const Technique lastSession = Technique(
    name: 'Box Breathing',
    pattern: '4-4-4-4',
    minutes: 5,
    status: TechniqueStatus.collected,
    plant: PlantType.spiky,
    progress: 6,
  );
  static const int lastAccuracy = 78;

  static const List<Technique> techniques = [
    Technique(
      name: 'Box Breathing',
      pattern: '4-4-4-4',
      minutes: 5,
      status: TechniqueStatus.collected,
      plant: PlantType.spiky,
      progress: 6,
    ),
    Technique(
      name: '4-7-8 Calm',
      pattern: '4-7-8',
      minutes: 4,
      status: TechniqueStatus.collected,
      plant: PlantType.purple,
      progress: 2,
    ),
    Technique(
      name: 'Coherent Breathing',
      pattern: '5-5',
      minutes: 6,
      status: TechniqueStatus.grown,
      plant: PlantType.bush,
      progress: 0,
    ),
    Technique(
      name: 'Belly Breathing',
      pattern: '4-6',
      minutes: 5,
      status: TechniqueStatus.notCollected,
      plant: PlantType.spiky,
    ),
    Technique(
      name: 'Pursed-Lip',
      pattern: '2-4',
      minutes: 3,
      status: TechniqueStatus.collected,
      plant: PlantType.mushroom,
      progress: 3,
    ),
  ];
}

/// ---------------------------------------------------------------------------
/// REUSABLE: PRESSABLE (tap + scale animation)
/// ---------------------------------------------------------------------------
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double pressedScale;

  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.95,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// REUSABLE: PLANT ICON (drawn with CustomPainter)
/// ---------------------------------------------------------------------------
class PlantIcon extends StatelessWidget {
  final PlantType type;
  final double size;
  final bool faded;

  const PlantIcon({
    super.key,
    required this.type,
    this.size = 40,
    this.faded = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PlantPainter(type, faded)),
    );
  }
}

class _PlantPainter extends CustomPainter {
  final PlantType type;
  final bool faded;

  _PlantPainter(this.type, this.faded);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;

    final potColor = faded ? const Color(0xFF2B4A3B) : AppColors.terracotta;
    final rimColor =
        faded ? const Color(0xFF335746) : const Color(0xFFE59A6E);

    // Pot
    final pot = Path()
      ..moveTo(w * 0.27, h * 0.68)
      ..lineTo(w * 0.73, h * 0.68)
      ..lineTo(w * 0.66, h * 0.93)
      ..lineTo(w * 0.34, h * 0.93)
      ..close();
    canvas.drawPath(pot, Paint()..color = potColor);

    // Rim
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.22, h * 0.60, w * 0.56, h * 0.12),
        Radius.circular(w * 0.04),
      ),
      Paint()..color = rimColor,
    );

    final base = Offset(w * 0.5, h * 0.64);

    switch (type) {
      case PlantType.spiky:
        _fan(canvas, base, h, const [-62, -32, 0, 32, 62],
            faded ? const Color(0xFF244536) : const Color(0xFF4CAF6E),
            faded ? const Color(0xFF1E3B2E) : const Color(0xFF2E8B57));
        break;
      case PlantType.purple:
        _fan(canvas, base, h, const [-58, -28, 0, 28, 58],
            const Color(0xFF8E7CC3), const Color(0xFF5B4B9A));
        break;
      case PlantType.bush:
        final dark = Paint()..color = const Color(0xFF2E8B57);
        final light = Paint()..color = const Color(0xFF3FA66B);
        canvas.drawCircle(Offset(w * 0.34, h * 0.52), w * 0.15, dark);
        canvas.drawCircle(Offset(w * 0.66, h * 0.52), w * 0.15, dark);
        canvas.drawCircle(Offset(w * 0.5, h * 0.42), w * 0.2, light);
        canvas.drawCircle(Offset(w * 0.5, h * 0.53), w * 0.16, dark);
        break;
      case PlantType.mushroom:
        final a = Paint()..color = const Color(0xFFA6DDB8);
        final b = Paint()..color = const Color(0xFF6CC48E);
        canvas.drawCircle(Offset(w * 0.34, h * 0.5), w * 0.13, b);
        canvas.drawCircle(Offset(w * 0.66, h * 0.5), w * 0.13, b);
        canvas.drawCircle(Offset(w * 0.5, h * 0.4), w * 0.17, a);
        canvas.drawCircle(Offset(w * 0.5, h * 0.53), w * 0.13, b);
        break;
    }
  }

  void _fan(Canvas canvas, Offset base, double h, List<double> angles,
      Color light, Color dark) {
    for (int i = 0; i < angles.length; i++) {
      final isCenter = angles[i] == 0;
      _leaf(
        canvas,
        base,
        angles[i],
        h * (isCenter ? 0.46 : 0.38),
        h * 0.11,
        i.isEven ? light : dark,
      );
    }
  }

  void _leaf(Canvas canvas, Offset base, double deg, double len, double wd,
      Color color) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(deg * 3.1415926535 / 180);
    final p = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-wd, -len * 0.5, 0, -len)
      ..quadraticBezierTo(wd, -len * 0.5, 0, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlantPainter old) =>
      old.type != type || old.faded != faded;
}

/// ---------------------------------------------------------------------------
/// ROOT SHELL (bottom navigation + page switching)
/// ---------------------------------------------------------------------------
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // Stats (3) and Profile (4) use the teal palette
  bool get _teal => _index == 3 || _index == 4;

  static const _items = <_NavItem>[
    _NavItem('Home', Icons.home_outlined),
    _NavItem('Garden', Icons.eco_outlined),
    _NavItem('Audio', Icons.headphones_outlined),
    _NavItem('Stats', Icons.bar_chart_rounded),
    _NavItem('Profile', Icons.person_outline_rounded),
  ];

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const HomePage(key: ValueKey('home'));
      case 1:
        return const GardenPage(key: ValueKey('garden'));
      case 2:
        return const AudioPage(key: ValueKey('audio'));
      case 3:
        return const StatsPage(key: ValueKey('stats'));
      default:
        return const ProfilePage(key: ValueKey('profile'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _teal
                ? const [StatsColors.bgTop, StatsColors.bgBottom]
                : const [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: _page(_index),
        ),
      ),
      bottomNavigationBar: _BottomNav(
        items: _items,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        bg: _teal ? StatsColors.navBg : AppColors.navBg,
        borderColor:
            _teal ? StatsColors.navBorder : const Color(0x662E6B52),
        accent: _teal ? StatsColors.mint : AppColors.mint,
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

class _BottomNav extends StatelessWidget {
  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  final Color bg;
  final Color borderColor;
  final Color accent;

  const _BottomNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.bg = AppColors.navBg,
    this.borderColor = const Color(0x662E6B52),
    this.accent = AppColors.mint,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: SizedBox(
        height: 68,
        child: Row(
          children: List.generate(items.length, (i) {
            final selected = i == currentIndex;
            return Expanded(
              child: Pressable(
                pressedScale: 0.9,
                onTap: () => onTap(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      height: 3,
                      width: selected ? 22 : 0,
                      margin: const EdgeInsets.only(bottom: 5),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    AnimatedScale(
                      scale: selected ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        items[i].icon,
                        size: 24,
                        color: selected
                            ? accent
                            : accent.withAlpha(150),
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? accent
                            : accent.withAlpha(150),
                      ),
                      child: Text(items[i].label),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// HOME PAGE
/// ---------------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final BreatheApi _api = BreatheApi.instance;
  late final AnimationController _intro;

  bool _loading = true;
  bool _busy = false; // a session is being started
  String? _error;
  String? _firstName;

  List<Technique> _techniques = const [];
  ApiSummary? _summary;
  ApiSession? _lastSession;
  Technique? _lastTechnique;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _load(showSpinner: false); // _loading already starts as true
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  // ---- Data ---------------------------------------------------------------
  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _api.ensureUser();
      final results = await Future.wait<Object?>([
        _api.listUserTechniques(),
        _api.getSummary(),
        _api.getLastSession(),
        auth.firstName,
      ]);
      final techniques = (results[0] as List<ApiTechnique>)
          .map((t) => Technique.fromApi(t))
          .toList();
      final summary = results[1] as ApiSummary;
      final last = results[2] as ApiSession?;
      final firstName = results[3] as String?;

      if (!mounted) return;
      setState(() {
        _techniques = techniques;
        _summary = summary;
        _lastSession = last;
        _lastTechnique =
            last == null ? null : _techniqueForSession(last, techniques);
        _firstName = firstName;
        _loading = false;
        _error = null;
      });
      if (_intro.status == AnimationStatus.dismissed) _intro.forward();
    } catch (e) {
      if (!mounted) return;
      final message = _messageFor(e);
      setState(() {
        _loading = false;
        if (_summary == null) _error = message;
      });
      // Data is already on screen: keep it and just report the problem.
      if (_summary != null) _showSnack(message);
    }
  }

  Technique _techniqueForSession(ApiSession s, List<Technique> list) {
    for (final t in list) {
      if (t.id == s.techniqueId) return t.withSession(s);
    }
    return Technique.fromSession(s);
  }

  String _messageFor(Object e) {
    if (e is ApiException) return e.message;
    debugPrint('Breathe API error: $e');
    return 'Something went wrong. Pull down to try again.';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ));
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return _firstName == null ? timeGreeting : '$timeGreeting, $_firstName';
  }

  // ---- Actions ------------------------------------------------------------
  /// [resume]: continue the technique's existing in-progress session.
  /// Otherwise a new session is started on the server first.
  Future<void> _openSession(Technique t,
      {bool restart = false, bool resume = false}) async {
    if (_busy) return;
    setState(() => _busy = true);

    Technique active;
    try {
      if (resume && t.sessionId != null) {
        active = t;
      } else {
        final ref = t.slug ?? t.id?.toString();
        if (ref == null) {
          throw const ApiException(-1, 'This technique has no id.');
        }
        active = t.withSession(await _api.startSession(ref));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack(_messageFor(e));
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);

    final result = await Navigator.of(context).push<Object?>(
      PageRouteBuilder<Object?>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) =>
            SessionPage(technique: active, restart: restart),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );

    final sessionId = active.sessionId;
    if (result is BreatheSessionResult && sessionId != null) {
      try {
        await _api.saveSessionResult(sessionId, result,
            previousElapsedSec: active.elapsedSec);
      } on ApiException catch (e) {
        // 409 = SessionPage already finished it itself; nothing to save.
        if (e.statusCode != 409 && mounted) {
          _showSnack('Your session was not saved. ${e.message}');
        }
      } catch (e) {
        if (mounted) _showSnack(_messageFor(e));
      }
    }
    if (mounted) await _load(showSpinner: false);
  }

  Future<void> _hideLastSession() async {
    final previousSession = _lastSession;
    final previousTechnique = _lastTechnique;
    setState(() {
      _lastSession = null;
      _lastTechnique = null;
    });
    try {
      await _api.hideLastSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastSession = previousSession;
        _lastTechnique = previousTechnique;
      });
      _showSnack(_messageFor(e));
    }
  }

  // ---- UI -----------------------------------------------------------------
  Widget _stagger(int index, Widget child) {
    final begin = (index * 0.08).clamp(0.0, 0.6);
    final end = (begin + 0.4).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_summary == null) {
      return SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.mint),
              )
            : _ErrorView(
                message: _error ?? 'Could not load your data.',
                onRetry: () => _load(),
              ),
      );
    }

    final last = _lastSession;
    final lastTechnique = _lastTechnique;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _stagger(
            0,
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting,
                          style: const TextStyle(
                            color: AppColors.mintText,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          HomeData.title,
                          style: TextStyle(
                            fontFamily: 'Lato',
                            fontFamilyFallback: const ['sans-serif'],
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ModeSelectionScreen(
                          plantsBuilder: (_) => const RootShell(),
                        ),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x331F4A3A),
                        border: Border.all(
                          color: AppColors.cardBorder,
                          width: 1.2,
                        ),
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        size: 20,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Vitals card: live data from the ESP32 band
          _stagger(
            1,
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _VitalsCard(),
            ),
          ),
          const SizedBox(height: 14),

          // Last session card (hidden when there is none)
          if (last != null && lastTechnique != null) ...[
            _stagger(
              2,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildLastSessionCard(last, lastTechnique),
              ),
            ),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 6),

          // Techniques title
          _stagger(
            3,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Techniques',
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontFamilyFallback: const ['sans-serif'],
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white,
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Scrollable techniques list (pull down to refresh)
          Expanded(
            child: RefreshIndicator(
              color: AppColors.dark,
              backgroundColor: AppColors.mint,
              onRefresh: () => _load(showSpinner: false),
              child: _techniques.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: const [
                        Text(
                          'No techniques are available yet. Pull down to refresh.',
                          style: TextStyle(
                            color: AppColors.mintText,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: _techniques.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, i) {
                        final tech = _techniques[i];
                        return _stagger(
                          4 + i,
                          _TechniqueTile(
                            technique: tech,
                            onTap: () => _openSession(tech),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastSessionCard(ApiSession s, Technique t) {
    final canContinue = s.canContinue;
    final details = <String>[t.pattern, '${t.minutes} min'];
    final accuracy = s.accuracyPct;
    if (accuracy != null) details.add('${accuracy.round()}% accuracy');
    if (canContinue && s.elapsedSec > 0) {
      details.add('${s.progressPct.round()}% done');
    }

    return _CardShell(
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Last session',
                  style: TextStyle(
                    color: AppColors.mintText,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Pressable(
                pressedScale: 0.85,
                onTap: _hideLastSession,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.mintText,
                    semanticLabel: 'Hide last session',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _techniquePlantImage(t.plantKey, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: const TextStyle(
                        fontFamily: 'Lato',
                        fontFamilyFallback: const ['sans-serif'],
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details.join(' · '),
                      style: const TextStyle(
                        color: AppColors.mintText,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Pressable(
              onTap: () => _openSession(t, restart: true),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x331F4A3A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.cardBorder,
                    width: 1.3,
                  ),
                ),
                child: const Text(
                  'Redo',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 40, color: AppColors.mintText),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.white, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Server: $kApiBaseUrl',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.mintText, fontSize: 11.5),
            ),
            const SizedBox(height: 18),
            Pressable(
              onTap: onRetry,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    color: AppColors.dark,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  const _CardShell({
    required this.child,
    required this.padding,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0x661F4A3A),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xAA2E6B52), width: 1.2),
      ),
      child: child,
    );
  }
}

/// ---------------------------------------------------------------------------
/// VITALS CARD (live from the ESP32 band)
/// ---------------------------------------------------------------------------
class _VitalsCard extends StatelessWidget {
  const _VitalsCard();

  @override
  Widget build(BuildContext context) {
    final band = context.watch<VitalsService>();
    final r = band.latest;
    final live = band.isLive && r != null;
    final breath = band.breathsPerMinute;

    final breathText = live && breath != null ? '${breath.round()} /min' : '--';
    final oxygenText = live ? '${r.spo2.round()}%' : '--';
    final heartText = live ? '${r.heartRate.round()} bpm' : '--';

    String statusText;
    if (band.status == BandStatus.scanning) {
      statusText = 'Searching for band…';
    } else if (band.status == BandStatus.connecting) {
      statusText = 'Connecting to band…';
    } else if (live) {
      statusText = r.demo ? 'Band connected · simulated data' : 'Band connected';
    } else if (band.isConnected) {
      statusText = 'Waiting for data…';
    } else {
      statusText = band.error ?? 'Band not connected';
    }

    Widget action;
    if (band.isBusy) {
      action = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint),
      );
    } else {
      action = Pressable(
        pressedScale: 0.92,
        onTap: band.isConnected ? band.disconnect : band.connectToBand,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: band.isConnected ? const Color(0x331F4A3A) : AppColors.mint,
            border: Border.all(
              color: band.isConnected ? AppColors.cardBorder : AppColors.mint,
              width: 1.2,
            ),
          ),
          child: Text(
            band.isConnected ? 'Disconnect' : 'Connect',
            style: TextStyle(
              color: band.isConnected ? AppColors.white : AppColors.dark,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return _CardShell(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      radius: 18,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(value: breathText, label: 'Breath rate'),
              _Stat(value: oxygenText, label: 'Oxygen'),
              _Stat(value: heartText, label: 'Heart rate'),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0x332E6B52),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live ? AppColors.mint : AppColors.amber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mintText,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Lato',
            fontFamilyFallback: const ['sans-serif'],
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.mintText, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _TechniqueTile extends StatelessWidget {
  final Technique technique;
  final VoidCallback onTap;

  const _TechniqueTile({required this.technique, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final locked = technique.status == TechniqueStatus.notCollected;
    return Pressable(
      pressedScale: 0.97,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: locked ? const Color(0x33143225) : AppColors.tile,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Opacity(
              opacity: locked ? 0.4 : 1,
              child: _techniquePlantImage(technique.plantKey, size: 46),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  technique.name,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  technique.subtitle,
                  style: const TextStyle(
                    color: AppColors.mintText,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// PLACEHOLDER PAGE (Garden)
/// ---------------------------------------------------------------------------
class PlaceholderPage extends StatelessWidget {
  final String title;

  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Lato',
            fontFamilyFallback: const ['sans-serif'],
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}