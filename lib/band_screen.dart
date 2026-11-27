import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart' show Pressable, kSerif, kSerifFallback;
import 'stats_page.dart' show StatsColors;

// ---------------------------------------------------------------- band screen

enum _BandStatus { disconnected, scanning, connected }

class BandScreen extends StatefulWidget {
  final bool connected;
  final ValueChanged<bool>? onConnectedChanged;

  const BandScreen({
    super.key,
    this.connected = false,
    this.onConnectedChanged,
  });

  @override
  State<BandScreen> createState() => _BandScreenState();
}

class _BandScreenState extends State<BandScreen> {
  late _BandStatus _status =
      widget.connected ? _BandStatus.connected : _BandStatus.disconnected;

  Future<void> _connect() async {
    HapticFeedback.selectionClick();
    setState(() => _status = _BandStatus.scanning);

    // TODO: replace with real Bluetooth scan + pairing (e.g. flutter_blue_plus)
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() => _status = _BandStatus.connected);
    widget.onConnectedChanged?.call(true);
  }

  void _disconnect() {
    HapticFeedback.selectionClick();
    setState(() => _status = _BandStatus.disconnected);
    widget.onConnectedChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status == _BandStatus.connected;
    final scanning = _status == _BandStatus.scanning;

    final title = connected
        ? 'Band connected'
        : scanning
            ? 'Looking for your band…'
            : 'Connect your band';
    final subtitle = connected
        ? 'Battery 78% · Synced just now'
        : scanning
            ? 'Keep it close and switched on.'
            : 'Turn on your band and hold it near your phone.';

    return Scaffold(
      backgroundColor: const Color(0xFF0E2A24),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: StatsColors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: StatsColors.card,
                  border: Border.all(
                    color: connected
                        ? StatsColors.mint
                        : StatsColors.cardBorder,
                    width: 2,
                  ),
                ),
                child: scanning
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(StatsColors.mint),
                        ),
                      )
                    : Icon(
                        connected
                            ? Icons.watch_rounded
                            : Icons.bluetooth_searching_rounded,
                        size: 48,
                        color:
                            connected ? StatsColors.mint : StatsColors.white,
                      ),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Lato',
                  fontFamilyFallback: const ['sans-serif'],
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: StatsColors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8FD0BE), fontSize: 14),
              ),
              const Spacer(),
              Pressable(
                onTap: scanning ? () {} : (connected ? _disconnect : _connect),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: scanning ? 0.45 : 1,
                  child: Container(
                    height: 50,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: connected ? Colors.transparent : StatsColors.mint,
                      borderRadius: BorderRadius.circular(26),
                      border: connected
                          ? Border.all(
                              color: StatsColors.cardBorder, width: 1.3)
                          : null,
                    ),
                    child: Text(
                      connected ? 'Disconnect' : 'Connect',
                      style: TextStyle(
                        color: connected
                            ? StatsColors.white
                            : const Color(0xFF0E2A24),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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
}

// ---------------------------------------------------------------- data

TextStyle serif(double size, {FontWeight weight = FontWeight.w700, Color? color}) =>
   TextStyle(
 fontFamily: 'Lato',
  fontSize: size,
  fontWeight: weight,
  color: color,
);

class Technique {
  final String name, detail;
  final int kind;
  final bool dim;
  const Technique(this.name, this.detail, this.kind, [this.dim = false]);
}

class World {
  final bool celestial;
  final Color bgTop, bgBottom, card, panel, line, text, muted, accent, ink, navBg;
  final List<String> tabs;
  final List<Technique> techniques;
  const World({
    required this.celestial,
    required this.bgTop,
    required this.bgBottom,
    required this.card,
    required this.panel,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.ink,
    required this.navBg,
    required this.tabs,
    required this.techniques,
  });
}

const plantsWorld = World(
  celestial: false,
  bgTop: Color(0xFF12301F),
  bgBottom: Color(0xFF091510),
  card: Color(0xFF1B4332),
  panel: Color(0x8C1B4332),
  line: Color(0x408CE6A0),
  text: Color(0xFFF2FFF6),
  muted: Color(0xFFA9DCB9),
  accent: Color(0xFF8FE3A6),
  ink: Color(0xFF0B1F14),
  navBg: Color(0xFF1B4332),
  tabs: ['Home', 'Garden', 'Stats', 'Profile'],
  techniques: [
    Technique('Box Breathing', '4-4-4-4 · 5 min · Collected · 6/10 to grow', 0),
    Technique('4-7-8 Calm', '4-7-8 · 4 min · Collected · 2/10 to grow', 1),
    Technique('Coherent Breathing', '5-5 · 6 min · Grown · 0/10 to next', 2),
    Technique('Belly Breathing', '4-6 · 5 min · Not collected yet', 0, true),
    Technique('Pursed-Lip', '2-4 · 3 min · Collected · 3/10 to grow', 2),
  ],
);

const celestialWorld = World(
  celestial: true,
  bgTop: Color(0xFF0C1A3D),      // Orbit Navy
  bgBottom: Color(0xFF050B1F),   // Deep Space
  card: Color(0xFF0C1A3D),       // Orbit Navy
  panel: Color(0x66152B5C),      // Translucent Nebula Blue
  line: Color(0xAA2F5AA8),       // Border Blue
  text: Color(0xFFFFFFFF),       // White
  muted: Color(0xFFA8C8F0),      // Soft Ice Blue (harmonized with Nebula Cyan)
  accent: Color(0xFF5CB8FF),     // Nebula Cyan
  ink: Color(0xFF050B1F),        // Deep Space
  navBg: Color(0xFF0C1A3D),      // Orbit Navy
  tabs: ['Home', 'Collection', 'Stats', 'Profile'],
  techniques: [
    Technique('Box Breathing', '4-4-4-4 · 5 min · Collected · 6/10 to grow', 0),
    Technique('4-7-8 Calm', '4-7-8 · 4 min · Collected · 2/10 to grow', 1),
    Technique('Coherent Breathing', '5-5 · 6 min · Grown · 0/10 to next', 2),
    Technique('Belly Breathing', '4-6 · 5 min · Not collected yet', 3),
    Technique('Pursed-Lip', '2-4 · 3 min · Collected · 3/10 to grow', 4),
  ],
);

const gold = Color(0xFFF2C27A);

// ------------------------------------------------------------- shared UI

/// Keeps the app phone-sized and centered when running in Chrome.
class PhoneFrame extends StatelessWidget {
  final Widget child;
  final Color outside;
  const PhoneFrame({super.key, required this.child, required this.outside});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: outside,
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: child,
      ),
    );
  }
}

class GlyphIcon extends StatelessWidget {
  final bool celestial;
  final int kind;
  final double size;
  const GlyphIcon({super.key, required this.celestial, required this.kind, required this.size});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: GlyphPainter(celestial, kind));
}

/// Draws all plant and celestial icons on a 110 x 110 grid.
class GlyphPainter extends CustomPainter {
  final bool celestial;
  final int kind;
  GlyphPainter(this.celestial, this.kind);

  Paint _fill(Color c) => Paint()..color = c;

  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 110, s.height / 110);
    celestial ? _sky(c) : _plant(c);
  }

  void _pot(Canvas c) {
    final clay = _fill(const Color(0xFFC4875A));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 66, 48, 8), const Radius.circular(2)), clay);
    final p = Path()..moveTo(36, 74)..lineTo(74, 74)..lineTo(70, 98)..lineTo(40, 98)..close();
    c.drawPath(p, clay);
  }

  void _plant(Canvas c) {
    if (kind == 1) {
      final stroke = Paint()
        ..color = const Color(0xFFA77BE0)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      for (final o in const [Offset(20, 40), Offset(35, 28), Offset(55, 22), Offset(75, 28), Offset(90, 40)]) {
        c.drawLine(const Offset(55, 68), o, stroke);
      }
    } else if (kind == 2) {
      c.drawCircle(const Offset(40, 50), 18, _fill(const Color(0xFF2F9E5F)));
      c.drawCircle(const Offset(70, 50), 18, _fill(const Color(0xFF2F9E5F)));
      c.drawCircle(const Offset(55, 38), 20, _fill(const Color(0xFF3BB26D)));
    } else {
      final leaves = Path()
        ..moveTo(55, 70)
        ..cubicTo(30, 70, 14, 52, 18, 38)
        ..relativeCubicTo(10, -6, 22, 0, 28, 10)
        ..relativeCubicTo(0, -14, 6, -28, 9, -34)
        ..relativeCubicTo(3, 6, 9, 20, 9, 34)
        ..relativeCubicTo(6, -10, 18, -16, 28, -10)
        ..relativeCubicTo(4, 14, -12, 32, -37, 32)
        ..close();
      c.drawPath(leaves, _fill(const Color(0xFF5CC47E)));
    }
    _pot(c);
  }

  void _star(Canvas c, double cx, double cy, double r, Paint p) {
    final k = r * 0.3;
    final path = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + k, cy - k)
      ..lineTo(cx + r, cy)
      ..lineTo(cx + k, cy + k)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - k, cy + k)
      ..lineTo(cx - r, cy)
      ..lineTo(cx - k, cy - k)
      ..close();
    c.drawPath(path, p);
  }

  void _sky(Canvas c) {
    switch (kind) {
      case 0: // moon
        final crater = _fill(const Color(0xFFE0C277));
        c.drawCircle(const Offset(55, 55), 36, _fill(const Color(0xFFF6DD9A)));
        c.drawCircle(const Offset(44, 46), 7, crater);
        c.drawCircle(const Offset(66, 68), 6, crater);
        c.drawCircle(const Offset(68, 42), 4, crater);
        break;
      case 1: // comet, falling down-right at 40°
        c.save();
        c.translate(55, 55);
        c.rotate(40 * math.pi / 180);

        // soft tapered tail (white fading to transparent)
        final tail = Path()
          ..moveTo(20, -9)
          ..quadraticBezierTo(-10, -6, -52, 0)
          ..quadraticBezierTo(-10, 6, 20, 9)
          ..close();
        c.drawPath(
          tail,
          Paint()
            ..shader = const LinearGradient(
              colors: [Color(0x00FFFFFF), Color(0x66F2F2F2), Color(0xFFFFFFFF)],
              stops: [0.0, 0.55, 1.0],
            ).createShader(const Rect.fromLTRB(-52, -9, 20, 9)),
        );

        // thin streaks
        c.drawLine(
          const Offset(14, -5),
          const Offset(-38, -4),
          Paint()
            ..color = const Color(0x99FFFFFF)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        c.drawLine(
          const Offset(14, 5),
          const Offset(-30, 4.5),
          Paint()
            ..color = const Color(0x66E8E8E8)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );

        // glow + head
        c.drawCircle(const Offset(20, 0), 17, _fill(const Color(0x33FFFFFF)));
        c.drawCircle(
          const Offset(20, 0),
          10,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFE6E6E6)],
            ).createShader(
                Rect.fromCircle(center: const Offset(20, 0), radius: 10)),
        );
        c.drawCircle(const Offset(17, -3), 3, _fill(Colors.white));

        c.restore();
        break;
      case 2: // orbs
        c.drawCircle(const Offset(42, 58), 24, _fill(const Color(0xE65B8DEF)));
        c.drawCircle(const Offset(68, 58), 24, _fill(const Color(0xCCD86FC0)));
        c.drawCircle(const Offset(55, 40), 22, _fill(const Color(0xD98F7CF0)));
        break;
      case 3: // wand
        c.drawLine(
          const Offset(24, 90),
          const Offset(68, 46),
          Paint()
            ..color = const Color(0xFF6C82C9)
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round,
        );
        c.drawCircle(const Offset(78, 34), 11, _fill(Colors.white));
        break;
      default: // sparkles
        final y = _fill(const Color(0xFFF6DD9A));
        _star(c, 45, 44, 26, y);
        _star(c, 82, 72, 14, y);
        _star(c, 24, 82, 10, y);
    }
  }

  @override
  bool shouldRepaint(GlyphPainter old) => old.kind != kind || old.celestial != celestial;
}

// ------------------------------------------------------ choose your world

class ChooseWorldScreen extends StatelessWidget {
  const ChooseWorldScreen({super.key});

  void _open(BuildContext context, World w) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorldShell(world: w)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08130F),
      body: PhoneFrame(
        outside: const Color(0xFF08130F),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF12301F), Color(0xFF0D1F1A), Color(0xFF091510)],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 8),
                Text('Choose your world', style: serif(28, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Same breathing techniques, two ways to grow.',
                    style: TextStyle(color: Color(0xFFA9DCB9), fontSize: 14)),
                const SizedBox(height: 18),
                _WorldCard(
                  world: plantsWorld,
                  title: 'Plants',
                  subtitle: 'Grow a garden, one breath at a time.',
                  button: 'Choose Plants',
                  glyphKind: 0,
                  gradient: const [Color(0xFF1B3D2A), Color(0xFF0F2216)],
                  border: const Color(0x408CE6A0),
                  onTap: () => _open(context, plantsWorld),
                ),
                const SizedBox(height: 18),
               _WorldCard(
                  world: celestialWorld,
                  title: 'Celestial',
                  subtitle: 'Light up the night sky with every breath.',
                  button: 'Choose Celestial',
                  glyphKind: 1,
                  gradient: const [Color(0xFF0C1A3D), Color(0xFF050B1F)],
                  border: const Color(0xAA2F5AA8),
                  onTap: () => _open(context, celestialWorld),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small static background stars for the Celestial card.
class CardStarsPainter extends CustomPainter {
  // x, y (fractions of the card), radius, opacity
  static const _stars = <List<double>>[
    [0.08, 0.07, 1.4, 0.90],
    [0.22, 0.20, 1.0, 0.60],
    [0.38, 0.06, 1.2, 0.75],
    [0.55, 0.15, 0.9, 0.55],
    [0.72, 0.07, 1.6, 0.95],
    [0.90, 0.18, 1.1, 0.70],
    [0.12, 0.42, 0.9, 0.50],
    [0.86, 0.40, 1.3, 0.80],
    [0.94, 0.58, 0.9, 0.55],
    [0.06, 0.62, 1.1, 0.65],
    [0.80, 0.30, 0.8, 0.45],
    [0.30, 0.34, 0.8, 0.45],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _stars) {
      canvas.drawCircle(
        Offset(s[0] * size.width, s[1] * size.height),
        s[2],
        Paint()..color = Color.fromRGBO(255, 255, 255, s[3]),
      );
    }
  }

  @override
  bool shouldRepaint(CardStarsPainter old) => false;
}

class _WorldCard extends StatelessWidget {
  final World world;
  final String title, subtitle, button;
  final int glyphKind;
  final List<Color> gradient;
  final Color border;
  final VoidCallback onTap;

  const _WorldCard({
    required this.world,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.glyphKind,
    required this.gradient,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: gradient),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            if (world.celestial)
              Positioned.fill(child: CustomPaint(painter: CardStarsPainter())),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 150,
                    child: Center(child: GlyphIcon(celestial: world.celestial, kind: glyphKind, size: 110)),
                  ),
                  Text(title, style: serif(24, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: world.muted, fontSize: 14)),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: world.accent,
                        foregroundColor: world.ink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      child: Text(button),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ world shell

class WorldShell extends StatefulWidget {
  final World world;
  const WorldShell({super.key, required this.world});

  @override
  State<WorldShell> createState() => _WorldShellState();
}

class _WorldShellState extends State<WorldShell> {
  int _index = 0;

  static const _icons = [
    Icons.home_outlined,
    Icons.eco_outlined,
    Icons.bar_chart_rounded,
    Icons.person_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final w = widget.world;
    final pages = <Widget>[
      HomePage(world: w),
      for (final t in w.tabs.skip(1))
        t == 'Profile'
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t, style: serif(26, color: w.text)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BandScreen()),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: w.accent,
                        foregroundColor: w.ink,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Your band'),
                    ),
                  ],
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t, style: serif(26, color: w.text)),
                    const SizedBox(height: 8),
                    Text('Coming soon.', style: TextStyle(color: w.muted)),
                  ],
                ),
              ),
    ];

    return Scaffold(
      backgroundColor: w.bgBottom,
      body: PhoneFrame(
        outside: w.bgBottom,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [w.bgTop, w.bgBottom],
            ),
          ),
          child: Column(
            children: [
              Expanded(child: SafeArea(bottom: false, child: IndexedStack(index: _index, children: pages))),
              Container(
                decoration: BoxDecoration(color: w.navBg, border: Border(top: BorderSide(color: w.line))),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      for (var i = 0; i < w.tabs.length; i++)
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _index = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_icons[i], size: 26, color: i == _index ? w.accent : w.muted),
                                  const SizedBox(height: 4),
                                  Text(
                                    w.tabs[i],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: i == _index ? w.accent : w.muted,
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
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- home page

class HomePage extends StatelessWidget {
  final World world;
  const HomePage({super.key, required this.world});

  Widget _panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: world.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: world.line),
        ),
        child: child,
      );

  Widget _vital(String value, String label) => Column(
        children: [
          Text(value, style: serif(22, color: world.text)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: world.muted)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final w = world;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good evening', style: TextStyle(color: w.muted, fontSize: 13)),
                  Text('Breathe', style: serif(30, color: w.text)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: gold),
              ),
              child: const Text('7-day streak',
                  style: TextStyle(color: gold, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _panel(
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _vital('14 /min', 'Breath rate'),
              _vital('98%', 'Oxygen'),
              _vital('72 bpm', 'Heart rate'),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        ),
        const SizedBox(height: 16),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Continue last session', style: TextStyle(fontSize: 12, color: w.muted)),
              const SizedBox(height: 12),
              Row(
                children: [
                  GlyphIcon(celestial: w.celestial, kind: 0, size: 46),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Box Breathing', style: serif(20, color: w.text)),
                        const SizedBox(height: 2),
                        Text('4-4-4-4 · 5 min · 78% accuracy',
                            style: TextStyle(fontSize: 12, color: w.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        backgroundColor: w.accent,
                        foregroundColor: w.ink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      child: const Text('Continue'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: w.text,
                        side: BorderSide(color: w.line),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      child: const Text('Redo'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('Techniques', style: serif(16, color: w.text)),
        const SizedBox(height: 10),
        for (final t in w.techniques)
          Opacity(
            opacity: t.dim ? 0.4 : 1,
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(color: w.card, borderRadius: BorderRadius.circular(14)),
                      child: Center(child: GlyphIcon(celestial: w.celestial, kind: t.kind, size: 34)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: w.text)),
                          const SizedBox(height: 2),
                          Text(t.detail, style: TextStyle(fontSize: 12, color: w.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
