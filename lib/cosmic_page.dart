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
import 'selection.dart';
import 'vitals_service.dart';
import 'auth_service.dart';


final AuthService auth = AuthService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0C1A3D), // Orbit Navy
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
      // After login the user chooses a world: Plants or Space (Cosmos).
      return modeSelection();
    }

    return _GoogleLoginScreen(
      busy: _signingIn,
      error: _error,
      onSignIn: _signIn,
      onRetry: _initializeAndRestore,
    );
  }
}

/// The "Choose your world" screen.
///  - Space opens this project's Cosmos app ([RootShell]).
///  - Plants opens the teammate's Plants world ([PlantsWorldPlaceholder] for now).
/// The Builder gives onSpace a context that is still mounted when it runs.
Widget modeSelection() => Builder(
      builder: (ctx) => ModeSelectionScreen(
        plantsBuilder: (_) => const PlantsWorldPlaceholder(),
        onSpace: () => Navigator.of(ctx).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const RootShell()),
        ),
      ),
    );

/// Stand-in until the teammate's Plants app is plugged in. Replace the
/// PlantsWorldPlaceholder() call in [modeSelection] with their root widget.
class PlantsWorldPlaceholder extends StatelessWidget {
  const PlantsWorldPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0E2217),
      body: Center(
        child: Text(
          'Plants world coming soon',
          style: TextStyle(color: Color(0xFFA6DDB8), fontSize: 16),
        ),
      ),
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF050B1F), // Deep Space
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF5CB8FF)), // Nebula Cyan
            SizedBox(height: 18),
            Text(
              'Checking your session…',
              style: TextStyle(color: Color(0xFF9FD4FF), fontSize: 14),
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
      backgroundColor: const Color(0xFF050B1F), // Deep Space
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0C1A3D), Color(0xFF050B1F)], // Orbit Navy → Deep Space
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
                        color: const Color(0x33152B5C),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFF2F5AA8),
                          width: 1.4,
                        ),
                      ),
                      child: const Center(
                        child: GalaxyIcon(
                          size: 50,
                          color: Color(0xFF5CB8FF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    const Text(
                      'Welcome to Breathe',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Sign in to continue your breathing journey.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF9FD4FF),
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
                          backgroundColor: const Color(0xFF5CB8FF),
                          foregroundColor: const Color(0xFF050B1F),
                          disabledBackgroundColor:
                              const Color(0xFF3B5F8F),
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
                                  color: Color(0xFF050B1F),
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
                            style: TextStyle(color: Color(0xFF9FD4FF)),
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
  static const bgTop = Color(0xFF0C1A3D);       // Orbit Navy
  static const bgBottom = Color(0xFF050B1F);    // Deep Space
  static const card = Color(0xFF152B5C);
  static const cardBorder = Color(0xFF2F5AA8);
  static const tile = Color(0xFF152B5C);
  static const mint = Color(0xFF5CB8FF);        // Nebula Cyan (accent)
  static const mintText = Color(0xFF9FD4FF);    // light tint of Nebula Cyan
  static const white = Color(0xFFFFFFFF);
  static const dark = Color(0xFF050B1F);        // Deep Space (text on accent)
  static const amber = Color(0xFFF2C47E);
  static const navBg = Color(0xFF0C1A3D);       // Orbit Navy
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
      title: 'Breathe',
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

/// The ten constellations that replace the old plants.
enum ConstellationType {
  cassiopeia,
  orion,
  ursaMajor,
  cygnus,
  scorpius,
  canisMajor,
  pegasus,
  leo,
  taurus,
  draco,
}

int _minutesFromSeconds(int seconds) => math.max(1, (seconds / 60).round());

/// Picks the constellation for a technique from its id:
/// 1 → Cassiopeia, 2 → Orion, ... 10 → Draco, then it repeats.
ConstellationType _constellationFor(int? id) {
  final n = ConstellationType.values.length;
  return ConstellationType.values[((id ?? 1) - 1) % n];
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
  final ConstellationType constellation;

  // Filled in when the data comes from the API.
  final int? id;
  final String? slug;
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
    required this.constellation,
    this.progress = 0,
    this.goal = 10,
    this.id,
    this.slug,
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
      name: t.name,
      description: t.description,
      pattern: t.pattern,
      minutes: _minutesFromSeconds(t.defaultDurationSec),
      status: _statusForStage(p?.stage),
      constellation: _constellationFor(t.id),
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
        name: s.techniqueName,
        pattern: s.pattern,
        minutes: _minutesFromSeconds(s.targetDurationSec),
        status: TechniqueStatus.collected,
        constellation: _constellationFor(s.techniqueId),
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
        constellation: constellation,
        progress: progress,
        goal: goal,
        id: id ?? s.techniqueId,
        slug: slug ?? s.techniqueSlug,
        description: description,
        phases: s.phases,
        isFinalStage: isFinalStage,
        targetDurationSec: s.targetDurationSec,
        sessionId: s.id,
        elapsedSec: s.elapsedSec,
      );

  /// Kept so older code that reads `technique.plant` still compiles.
  ConstellationType get plant => constellation;

  String get subtitle {
    final base = '$pattern · $minutes min';
    switch (status) {
      case TechniqueStatus.notCollected:
        return '$base · Not collected yet';
      case TechniqueStatus.collected:
        return '$base · Collected · $progress/$goal to grow';
      case TechniqueStatus.grown:
        return isFinalStage
            ? '$base · Flourishing'
            : '$base · Grown · $progress/$goal to next';
    }
  }
}

/// ---------------------------------------------------------------------------
/// TECHNIQUE CATALOG
/// ---------------------------------------------------------------------------
/// The ten techniques the app offers, in display order. Item N gets the Nth
/// constellation (1 = Cassiopeia ... 10 = Draco). The API supplies each
/// technique's progress, status, id and phases; matching is by [slug] first,
/// then by name. A technique the server doesn't know yet is shown as not
/// collected, and starting it sends [slug] to the server.
class TechniqueSpec {
  final String slug;
  final String name;
  final String pattern;
  final int minutes;

  const TechniqueSpec({
    required this.slug,
    required this.name,
    required this.pattern,
    required this.minutes,
  });
}

const List<TechniqueSpec> kTechniqueCatalog = [
  TechniqueSpec(
    slug: 'box-breathing',
    name: 'Box Breathing',
    pattern: '4-4-4-4',
    minutes: 5,
  ),
  TechniqueSpec(
    slug: '4-6-breathing',
    name: '4-6 Breathing',
    pattern: '4-6',
    minutes: 4,
  ),
  TechniqueSpec(
    slug: '5-5-coherent-breathing',
    name: '5-5 Coherent Breathing',
    pattern: '5-5',
    minutes: 5,
  ),
  TechniqueSpec(
    slug: 'pursed-lip-breathing',
    name: 'Pursed Lip Breathing',
    pattern: '2-4',
    minutes: 3,
  ),
  TechniqueSpec(
    slug: 'extended-exhale',
    name: 'Extended Exhale (1:2)',
    pattern: '4-8',
    minutes: 4,
  ),
  TechniqueSpec(
    slug: 'physiological-sigh',
    name: 'Physiological Sigh',
    pattern: '2-1-6',
    minutes: 1,
  ),
  TechniqueSpec(
    slug: '4-2-6-breathing',
    name: '4-2-6 Breathing',
    pattern: '4-2-6',
    minutes: 4,
  ),
  TechniqueSpec(
    slug: 'alternate-nostril-breathing',
    name: 'Alternate Nostril Breathing',
    pattern: '4-4-4-4',
    minutes: 5,
  ),
  TechniqueSpec(
    slug: 'humming-bee-breath',
    name: 'Humming Bee Breath',
    pattern: '4-6',
    minutes: 3,
  ),
  TechniqueSpec(
    slug: '5-4-3-2-1-breathing',
    name: '5-4-3-2-1 Breathing',
    pattern: '5-4-3-2-1',
    minutes: 3,
  ),
];

String _normName(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Finds the API technique that matches a catalog entry (slug, then name).
ApiTechnique? _findApiTechnique(List<ApiTechnique> api, TechniqueSpec spec) {
  for (final t in api) {
    if (t.slug == spec.slug) return t;
  }
  final wanted = _normName(spec.name);
  for (final t in api) {
    if (_normName(t.name) == wanted) return t;
  }
  return null;
}

/// Builds a technique from the catalog, filling in progress from the API
/// when the server knows it. The name, pattern and length shown always come
/// from the catalog.
Technique _techniqueFromSpec(TechniqueSpec spec, int index, ApiTechnique? api) {
  final base = api == null ? null : Technique.fromApi(api);
  return Technique(
    id: base?.id,
    slug: base?.slug ?? spec.slug,
    name: spec.name,
    description: base?.description,
    pattern: spec.pattern,
    minutes: spec.minutes,
    status: base?.status ?? TechniqueStatus.notCollected,
    constellation:
        ConstellationType.values[index % ConstellationType.values.length],
    progress: base?.progress ?? 0,
    goal: base?.goal ?? 10,
    isFinalStage: base?.isFinalStage ?? false,
    phases: base?.phases ?? const [],
    targetDurationSec: spec.minutes * 60,
  );
}

/// The ten catalog techniques, in order, merged with the API's data.
List<Technique> _buildCatalog(List<ApiTechnique> api) => [
      for (var i = 0; i < kTechniqueCatalog.length; i++)
        _techniqueFromSpec(
            kTechniqueCatalog[i], i, _findApiTechnique(api, kTechniqueCatalog[i])),
    ];

/// Placeholder data. The home screen now loads techniques, streak and the
/// last session from the API, and the vitals from the ESP32 band
/// (see VitalsService). Kept because other pages may still reference it.
class HomeData {
  static const String greeting = 'Good evening';
  static const String title = 'Breathe';
  static const String streakLabel = '7-day streak';
  static const String breathRate = '14 /min';
  static const String oxygen = '98%';
  static const String heartRate = '72 bpm';

  static const Technique lastSession = Technique(
    name: 'Box Breathing',
    pattern: '4-4-4-4',
    minutes: 5,
    status: TechniqueStatus.collected,
    constellation: ConstellationType.cassiopeia,
    progress: 6,
  );
  static const int lastAccuracy = 78;

  /// The ten catalog techniques (not yet merged with any API data).
  static final List<Technique> techniques = [
    for (var i = 0; i < kTechniqueCatalog.length; i++)
      _techniqueFromSpec(kTechniqueCatalog[i], i, null),
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
/// REUSABLE: CONSTELLATION ICON (drawn with CustomPainter)
/// ---------------------------------------------------------------------------
class ConstellationIcon extends StatelessWidget {
  final ConstellationType type;
  final double size;
  final bool faded;

  const ConstellationIcon({
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
      child: CustomPaint(painter: _ConstellationPainter(type, faded)),
    );
  }
}

/// Old name, kept so existing pages that use PlantIcon keep compiling.
typedef PlantIcon = ConstellationIcon;

class _ConstellationData {
  /// Each star is [x, y, size] with x and y in 0..1 and size as a multiplier.
  final List<List<double>> stars;

  /// Each edge joins two star indexes.
  final List<List<int>> edges;

  const _ConstellationData({required this.stars, required this.edges});
}

const _constellations = <ConstellationType, _ConstellationData>{
  ConstellationType.cassiopeia: _ConstellationData(
    stars: [[0.06, 0.32, 1.0], [0.27, 0.7, 1.0], [0.5, 0.4, 1.2], [0.73, 0.72, 1.0], [0.94, 0.3, 1.0]],
    edges: [[0, 1], [1, 2], [2, 3], [3, 4]],
  ),
  ConstellationType.orion: _ConstellationData(
    stars: [[0.28, 0.12, 1.5], [0.72, 0.15, 1.1], [0.4, 0.48, 1.0], [0.5, 0.5, 1.1], [0.6, 0.52, 1.0], [0.7, 0.88, 1.0], [0.3, 0.86, 1.5], [0.5, 0.68, 0.7]],
    edges: [[0, 1], [0, 2], [1, 4], [2, 3], [3, 4], [2, 6], [4, 5], [5, 6], [3, 7]],
  ),
  ConstellationType.ursaMajor: _ConstellationData(
    stars: [[0.12, 0.3, 1.0], [0.15, 0.62, 1.0], [0.4, 0.68, 1.0], [0.4, 0.4, 1.0], [0.6, 0.36, 1.0], [0.76, 0.44, 1.0], [0.94, 0.62, 1.0]],
    edges: [[0, 1], [1, 2], [2, 3], [3, 0], [3, 4], [4, 5], [5, 6]],
  ),
  ConstellationType.cygnus: _ConstellationData(
    stars: [[0.5, 0.06, 1.4], [0.5, 0.46, 1.1], [0.5, 0.94, 1.1], [0.14, 0.3, 1.0], [0.86, 0.62, 1.0]],
    edges: [[0, 1], [1, 2], [3, 1], [1, 4]],
  ),
  ConstellationType.scorpius: _ConstellationData(
    stars: [[0.78, 0.1, 1.0], [0.62, 0.18, 1.0], [0.42, 0.34, 1.6], [0.34, 0.5, 1.0], [0.36, 0.66, 1.0], [0.48, 0.8, 1.0], [0.66, 0.86, 1.0], [0.82, 0.74, 1.0], [0.78, 0.58, 1.1], [0.9, 0.24, 1.0]],
    edges: [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [1, 9]],
  ),
  ConstellationType.canisMajor: _ConstellationData(
    stars: [[0.3, 0.3, 1.6], [0.16, 0.14, 1.0], [0.42, 0.1, 1.0], [0.5, 0.5, 1.2], [0.38, 0.72, 1.2], [0.72, 0.8, 1.0]],
    edges: [[1, 0], [2, 0], [0, 3], [3, 4], [3, 5]],
  ),
  ConstellationType.pegasus: _ConstellationData(
    stars: [[0.38, 0.3, 1.0], [0.7, 0.28, 1.0], [0.72, 0.62, 1.0], [0.4, 0.64, 1.0], [0.22, 0.2, 1.0], [0.08, 0.1, 1.0], [0.22, 0.8, 1.0], [0.1, 0.94, 1.0], [0.92, 0.14, 1.0]],
    edges: [[0, 1], [1, 2], [2, 3], [3, 0], [0, 4], [4, 5], [3, 6], [6, 7], [1, 8]],
  ),
  ConstellationType.leo: _ConstellationData(
    stars: [[0.22, 0.82, 1.5], [0.26, 0.62, 1.0], [0.33, 0.44, 1.1], [0.27, 0.26, 1.0], [0.34, 0.1, 1.0], [0.46, 0.2, 1.0], [0.64, 0.36, 1.0], [0.66, 0.6, 1.0], [0.92, 0.5, 1.2]],
    edges: [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [2, 6], [6, 7], [7, 0], [6, 8], [7, 8]],
  ),
  ConstellationType.taurus: _ConstellationData(
    stars: [[0.3, 0.58, 1.6], [0.14, 0.42, 1.0], [0.16, 0.78, 1.0], [0.5, 0.46, 1.0], [0.9, 0.1, 1.2], [0.88, 0.46, 1.0], [0.66, 0.76, 0.6], [0.72, 0.7, 0.6], [0.7, 0.82, 0.6]],
    edges: [[1, 0], [0, 2], [0, 3], [3, 4], [3, 5]],
  ),
  ConstellationType.draco: _ConstellationData(
    stars: [[0.16, 0.24, 1.0], [0.28, 0.1, 1.0], [0.42, 0.16, 1.0], [0.34, 0.3, 1.0], [0.5, 0.42, 1.0], [0.66, 0.34, 1.0], [0.8, 0.46, 1.0], [0.7, 0.62, 1.0], [0.5, 0.66, 1.0], [0.36, 0.78, 1.0], [0.5, 0.9, 1.0], [0.78, 0.93, 1.0]],
    edges: [[0, 1], [1, 2], [2, 3], [3, 0], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [9, 10], [10, 11]],
  ),
};

class _ConstellationPainter extends CustomPainter {
  final ConstellationType type;
  final bool faded;

  _ConstellationPainter(this.type, this.faded);

  @override
  void paint(Canvas canvas, Size s) {
    final data = _constellations[type]!;
    final w = s.width;
    final h = s.height;
    const pad = 0.1;

    Offset at(List<double> p) =>
        Offset((pad + p[0] * (1 - 2 * pad)) * w, (pad + p[1] * (1 - 2 * pad)) * h);

    // Locked (not collected) constellations are dim and have no glow.
    final lineColor =
        faded ? const Color(0x663A5A9A) : AppColors.mint.withAlpha(170);
    final starColor = faded ? const Color(0xFF4F6FA8) : const Color(0xFFFFFFFF);
    final glowColor = AppColors.mint.withAlpha(70);

    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, w * 0.032);

    for (final e in data.edges) {
      canvas.drawLine(at(data.stars[e[0]]), at(data.stars[e[1]]), line);
    }

    for (final st in data.stars) {
      final c = at(st);
      final r = math.max(1.1, w * 0.04 * st[2]);
      if (!faded) canvas.drawCircle(c, r * 2.3, Paint()..color = glowColor);
      canvas.drawCircle(c, r, Paint()..color = starColor);
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) =>
      old.type != type || old.faded != faded;
}

/// ---------------------------------------------------------------------------
/// REUSABLE: GALAXY ICON (spiral galaxy drawn with CustomPainter)
/// ---------------------------------------------------------------------------
class GalaxyIcon extends StatelessWidget {
  final double size;
  final Color color;

  const GalaxyIcon({super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GalaxyPainter(color)),
    );
  }
}

class _GalaxyPainter extends CustomPainter {
  final Color color;

  _GalaxyPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final c = Offset(w / 2, h / 2);

    const turns = 1.15; // how far each arm winds around the core
    const steps = 28;

    // Two spiral arms, thick and bright near the core, thin and faint outside.
    for (int arm = 0; arm < 2; arm++) {
      final base = arm * math.pi;
      Offset? prev;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final ang = base + t * turns * 2 * math.pi;
        final r = w * (0.08 + 0.38 * t);
        final p = c + Offset(math.cos(ang), math.sin(ang)) * r;
        if (prev != null) {
          canvas.drawLine(
            prev,
            p,
            Paint()
              ..color = color.withAlpha((235 - 155 * t).round())
              ..strokeWidth = w * (0.085 - 0.05 * t)
              ..strokeCap = StrokeCap.round,
          );
        }
        prev = p;
      }
    }

    // Glowing core.
    canvas.drawCircle(c, w * 0.15, Paint()..color = color.withAlpha(60));
    canvas.drawCircle(c, w * 0.085, Paint()..color = color);

    // A few background stars.
    final star = Paint()..color = color.withAlpha(200);
    canvas.drawCircle(Offset(w * 0.13, h * 0.2), w * 0.03, star);
    canvas.drawCircle(Offset(w * 0.88, h * 0.14), w * 0.025, star);
    canvas.drawCircle(Offset(w * 0.9, h * 0.82), w * 0.03, star);
    canvas.drawCircle(Offset(w * 0.1, h * 0.86), w * 0.022, star);
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter old) => old.color != color;
}

/// ---------------------------------------------------------------------------
/// ROOT SHELL (bottom navigation + page switching)
/// ---------------------------------------------------------------------------
/// Watches the Home tab's nested navigator. Anything pushed on top of the
/// first route (i.e. a breathing session) counts as "session in progress".
class _SessionObserver extends NavigatorObserver {
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  int _depth = 0;

  void _update() {
    // Notify after the frame so we never trigger a rebuild mid-navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = _depth > 0;
      if (active.value != next) active.value = next;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _depth++;
      _update();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_depth > 0) {
      _depth--;
      _update();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_depth > 0) {
      _depth--;
      _update();
    }
  }

  void dispose() => active.dispose();
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // Each tab is built the first time it is opened, then kept alive.
  final Set<int> _visited = {0};

  // Nested navigator for the Home tab: the breathing session is pushed here,
  // so the bottom nav stays visible and the session survives tab changes.
  final GlobalKey<NavigatorState> _homeNavKey = GlobalKey<NavigatorState>();
  final _SessionObserver _sessionObserver = _SessionObserver();

  // Stats (3) and Profile (4) use the teal palette
  bool get _teal => _index == 3 || _index == 4;

  static final _items = <_NavItem>[
    _NavItem.icon('Home', Icons.home_outlined),
    _NavItem('Cosmos', (c, s) => GalaxyIcon(color: c, size: s)),
    _NavItem.icon('Audio', Icons.headphones_outlined),
    _NavItem.icon('Stats', Icons.bar_chart_rounded),
    _NavItem.icon('Profile', Icons.person_outline_rounded),
  ];

  @override
  void dispose() {
    _sessionObserver.dispose();
    super.dispose();
  }

  Widget _page(int i) {
    switch (i) {
      case 0:
        // TickerMode(enabled: true) makes sure the session's animations keep
        // running while another tab is on screen.
        return TickerMode(
          enabled: true,
          child: Navigator(
            key: _homeNavKey,
            observers: [_sessionObserver],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const HomePage(key: ValueKey('home')),
            ),
          ),
        );
      case 1:
        return const PlaceholderPage(key: ValueKey('cosmos'), title: 'Cosmos');
      case 2:
        return const AudioPage(key: ValueKey('audio'));
      case 3:
        return const StatsPage(key: ValueKey('stats'));
      default:
        return const ProfilePage(key: ValueKey('profile'));
    }
  }

  void _onBack() {
    final homeNav = _homeNavKey.currentState;
    if (_index == 0 && homeNav != null && homeNav.canPop()) {
      homeNav.maybePop(); // let SessionPage handle its own back/exit logic
    } else if (_index != 0) {
      setState(() => _index = 0); // back from another tab returns to Home
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
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
          child: Stack(
            children: [
              // IndexedStack keeps every opened tab (and the running session)
              // alive while another tab is showing.
              Positioned.fill(
                child: IndexedStack(
                  index: _index,
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
                  ],
                ),
              ),

              // "Session in progress" banner on the other tabs.
              Positioned(
                left: 16,
                right: 16,
                bottom: 10,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _sessionObserver.active,
                  builder: (context, active, _) {
                    if (!active || _index == 0) return const SizedBox.shrink();
                    return _SessionBanner(
                      onTap: () => setState(() => _index = 0),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomNav(
          items: _items,
          currentIndex: _index,
          onTap: (i) => setState(() {
            _index = i;
            _visited.add(i);
          }),
          bg: _teal ? StatsColors.navBg : AppColors.navBg,
          borderColor:
              _teal ? StatsColors.navBorder : const Color(0x662F5AA8),
          accent: _teal ? StatsColors.mint : AppColors.mint,
        ),
      ),
    );
  }
}

class _SessionBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _SessionBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      pressedScale: 0.97,
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xEE152B5C),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.mint, width: 1.2),
        ),
        child: const Row(
          children: [
            Icon(Icons.air_rounded, size: 18, color: AppColors.mint),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Breathing session in progress',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'Return',
              style: TextStyle(
                color: AppColors.mintText,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.mintText),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final Widget Function(Color color, double size) iconBuilder;

  const _NavItem(this.label, this.iconBuilder);

  factory _NavItem.icon(String label, IconData icon) =>
      _NavItem(label, (c, s) => Icon(icon, color: c, size: s));
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
    this.borderColor = const Color(0x662F5AA8),
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
                      child: items[i].iconBuilder(
                        selected ? accent : accent.withAlpha(150),
                        24,
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
      ]);
      final techniques = _buildCatalog(results[0] as List<ApiTechnique>);
      final summary = results[1] as ApiSummary;
      final last = results[2] as ApiSession?;

      if (!mounted) return;
      setState(() {
        _techniques = techniques;
        _summary = summary;
        _lastSession = last;
        _lastTechnique =
            last == null ? null : _techniqueForSession(last, techniques);
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
      final sameId = t.id != null && t.id == s.techniqueId;
      final sameSlug = t.slug != null && t.slug == s.techniqueSlug;
      if (sameId || sameSlug) return t.withSession(s);
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
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
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

    // This context sits inside the Home tab's nested Navigator, so the session
    // opens inside the tab and the bottom navigation stays reachable.
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
                    // Home lives in a nested Navigator, so the world switch
                    // must use the ROOT navigator to replace the whole shell.
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true)
                            .pushReplacement(
                      MaterialPageRoute(builder: (_) => modeSelection()),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x33152B5C),
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
              ConstellationIcon(type: t.constellation, size: 52),
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
                  color: const Color(0x33152B5C),
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
        color: const Color(0x66152B5C),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xAA2F5AA8), width: 1.2),
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
            color: band.isConnected ? const Color(0x33152B5C) : AppColors.mint,
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
            color: const Color(0x332F5AA8),
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
              color: locked ? const Color(0x33081433) : AppColors.tile,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ConstellationIcon(
                type: technique.constellation, size: 44, faded: locked),
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
/// PLACEHOLDER PAGE (Cosmos)
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
