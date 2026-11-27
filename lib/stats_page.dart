import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Re-uses Pressable, kSerif, kSerifFallback and AppColors from main.dart
import 'main.dart';
import 'stats_repository.dart';

/// ---------------------------------------------------------------------------
/// THEME (consistent green accent palette)
/// ---------------------------------------------------------------------------
/// Keep the page's accents green so chart bars, labels and indicators do not
/// mix the green accent with the previous blue accent shades.
class StatsColors {
  static const bgTop = AppColors.bgTop;
  static const bgBottom = AppColors.bgBottom;
  static const card = AppColors.card;
  static const cardBorder = Color(0x6648A982);

  static const mint = Color(0xFF63D6A5);
  static const bar = Color(0xFF286B55);
  static const white = AppColors.white;
  static const muted = Color(0xFF9BE7C5);
  static const label = Color(0xFF83CFA9);

  static const navBg = AppColors.navBg;
  static const navBorder = Color(0x6648A982);
}

/// ---------------------------------------------------------------------------
/// CHART SERIES (normalised 0..1, NaN = no data)
/// ---------------------------------------------------------------------------
List<double> _normLine(List<double?> v, double minSpan) {
  final vals = v.whereType<double>();
  if (vals.isEmpty) return List.filled(v.length, double.nan);
  var lo = vals.reduce(math.min);
  var hi = vals.reduce(math.max);
  if (hi - lo < minSpan) {
    final mid = (hi + lo) / 2;
    lo = mid - minSpan / 2;
    hi = mid + minSpan / 2;
  }
  final pad = (hi - lo) * 0.1;
  lo -= pad;
  hi += pad;
  return v
      .map((e) => e == null ? double.nan : ((e - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble())
      .toList();
}

List<double> _normBars(List<double?> v) {
  final vals = v.whereType<double>();
  final m = vals.isEmpty ? 0.0 : vals.reduce(math.max);
  return v.map((e) => (e == null || m <= 0) ? 0.0 : (e / m).clamp(0.0, 1.0).toDouble()).toList();
}

/// Chart values currently on screen (lets us animate between data sets).
class _Series {
  final List<double> heart;
  final List<double> oxygen;
  final List<double> steps;
  final List<double> calories;

  const _Series(this.heart, this.oxygen, this.steps, this.calories);

  factory _Series.empty() => const _Series([], [], [], []);

  factory _Series.fromSnapshot(StatsSnapshot s) => _Series(
        _normLine(s.heart, 20),
        _normLine(s.spo2, 4),
        _normBars(s.steps),
        _normBars(s.calories),
      );

  /// Works when the two series have different lengths (e.g. 24 hours -> 7 days).
  static List<double> _l(List<double> a, List<double> b, double t) {
    return List.generate(b.length, (i) {
      final target = b[i];
      if (target.isNaN) return double.nan;
      var start = 0.0;
      if (a.isNotEmpty) {
        final idx = ((i + 0.5) * a.length / b.length).floor().clamp(0, a.length - 1);
        if (!a[idx].isNaN) start = a[idx];
      }
      return start + (target - start) * t;
    });
  }

  static _Series lerp(_Series a, _Series b, double t) => _Series(
        _l(a.heart, b.heart, t),
        _l(a.oxygen, b.oxygen, t),
        _l(a.steps, b.steps, t),
        _l(a.calories, b.calories, t),
      );
}

/// ---------------------------------------------------------------------------
/// FORMATTING
/// ---------------------------------------------------------------------------
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _rangeLabel(StatsSnapshot s) {
  String md(DateTime d) => '${_months[d.month - 1]} ${d.day}';
  switch (s.period) {
    case StatsPeriod.day:
      return 'Today, ${md(s.rangeEnd)}';
    case StatsPeriod.week:
    case StatsPeriod.month:
      return '${md(s.rangeStart)} – ${md(s.rangeEnd)}';
    case StatsPeriod.year:
      return '${_months[s.rangeStart.month - 1]} ${s.rangeStart.year} – '
          '${_months[s.rangeEnd.month - 1]} ${s.rangeEnd.year}';
  }
}

/// ---------------------------------------------------------------------------
/// STATS PAGE
/// ---------------------------------------------------------------------------
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with TickerProviderStateMixin {
  StatsPeriod _period = StatsPeriod.week;

  late final AnimationController _intro;
  late final AnimationController _morph;
  late final StatsRepository _repo;
  bool _bound = false;

  _Series _from = _Series.empty();
  _Series _to = _Series.empty();
  StatsSnapshot? _lastSnap;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _repo = context.read<StatsRepository>();
    _repo.addListener(_onRepo);
    _retarget();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _repo.setActivePeriod(_period);
    });
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepo);
    _intro.dispose();
    _morph.dispose();
    super.dispose();
  }

  _Series get _shown => _Series.lerp(
        _from,
        _to,
        Curves.easeOutCubic.transform(_morph.value),
      );

  void _onRepo() {
    if (mounted) _retarget();
  }

  /// Animate the charts only when genuinely new data (or a new period) arrives.
  void _retarget() {
    final snap = _repo.snapshot(_period);
    if (snap != null && identical(snap, _lastSnap)) return;
    _lastSnap = snap;
    final next = snap == null ? _Series.empty() : _Series.fromSnapshot(snap);
    setState(() {
      _from = _shown; // snapshot so interrupted animations stay smooth
      _to = next;
    });
    _morph.forward(from: 0);
  }

  void _select(StatsPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _repo.setActivePeriod(p);
    _retarget();
  }

  Widget _stagger(int index, Widget child) {
    final begin = (index * 0.09).clamp(0.0, 0.6).toDouble();
    final end = (begin + 0.4).clamp(0.0, 1.0).toDouble();
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StatsRepository>();
    final snap = repo.snapshot(_period);

    // Status line under the period selector
    IconData statusIcon = Icons.sensors_rounded;
    String? status;
    if (repo.error != null) {
      statusIcon = Icons.cloud_off_rounded;
      status = snap == null
          ? "Can't reach the server"
          : "Can't refresh · showing saved data from ${_clock(snap.fetchedAt)}";
    } else if (snap != null) {
      status = 'Updated ${_clock(snap.fetchedAt)}'
          '${snap.includesDemo ? '' : ''}';
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: StatsColors.mint,
        backgroundColor: StatsColors.card,
        onRefresh: repo.syncNow,
        child: AnimatedBuilder(
          animation: _morph,
          builder: (context, _) {
            final s = _shown;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stagger(
                    0,
                    const Text(
                      'Statistics',
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontFamilyFallback: const ['sans-serif'],
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: StatsColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _stagger(
                    1,
                    _PeriodSelector(selected: _period, onChanged: _select),
                  ),
                  const SizedBox(height: 10),
                  _stagger(
                    1,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (snap != null)
                          Text(
                            _rangeLabel(snap),
                            style: const TextStyle(
                              color: StatsColors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (status != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(statusIcon, size: 14, color: StatsColors.mint),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  status,
                                  style: const TextStyle(
                                    color: StatsColors.muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (snap != null && !snap.hasData) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'No band readings in this period yet. Connect your band '
                            'and your data will sync here every minute.',
                            style: TextStyle(color: StatsColors.muted, fontSize: 12),
                          ),
                        ],
                        if (repo.loading) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(
                            minHeight: 2,
                            color: StatsColors.mint,
                            backgroundColor: StatsColors.card,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _stagger(
                    2,
                    _StatCard(
                      title: 'Heart rate · avg',
                      value: snap?.heartText ?? '--',
                      caption: snap?.heartCaption,
                      child: SizedBox(
                        height: 46,
                        width: double.infinity,
                        child: CustomPaint(painter: _LinePainter(s.heart)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _stagger(
                    3,
                    _StatCard(
                      title: 'Blood oxygen · avg',
                      value: snap?.spo2Text ?? '--',
                      caption: snap?.spo2Caption,
                      child: SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: CustomPaint(painter: _LinePainter(s.oxygen)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _stagger(
                    4,
                    _StatCard(
                      title: snap?.isDay == false ? 'Steps · daily avg' : 'Steps',
                      value: snap?.stepsText ?? '--',
                      child: SizedBox(
                        height: 62,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _BarsPainter(
                            s.steps,
                            highlight: _period == StatsPeriod.day ? DateTime.now().hour : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _stagger(
                    5,
                    _StatCard(
                      title: snap?.isDay == false
                          ? 'Active calories (est.) · daily avg'
                          : 'Active calories (est.)',
                      value: snap?.caloriesText ?? '--',
                      child: SizedBox(
                        height: 62,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _BarsPainter(
                            s.calories,
                            highlight: _period == StatsPeriod.day ? DateTime.now().hour : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _stagger(
                    6,
                    const Text(
                      'Breathing',
                      style: TextStyle(color: StatsColors.muted, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _stagger(
                    7,
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _MiniTile(
                              value: snap == null ? '--' : '${snap.collectibles}',
                              label: 'Collectibles',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniTile(
                              value: snap == null ? '--' : '${snap.exercises}',
                              label: 'Exercises done',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniTile(
                              value: snap?.practiceText ?? '--',
                              label: 'Total time',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// WIDGETS
/// ---------------------------------------------------------------------------
class _PeriodSelector extends StatelessWidget {
  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final count = StatsPeriod.values.length;
    final idx = selected.index;

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: StatsColors.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: StatsColors.cardBorder, width: 1.2),
      ),
      child: Stack(
        children: [
          // Sliding accent pill
          AnimatedAlign(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment(-1 + 2 * idx / (count - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: StatsColors.mint,
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
          ),
          // Labels
          Positioned.fill(
            child: Row(
              children: StatsPeriod.values.map((p) {
                final isSel = p == selected;
                return Expanded(
                  child: Pressable(
                    pressedScale: 0.94,
                    onTap: () => onChanged(p),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSel ? AppColors.dark : StatsColors.mint,
                        ),
                        child: Text(p.label),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? caption;
  final Widget child;

  const _StatCard({
    required this.title,
    required this.value,
    required this.child,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: StatsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StatsColors.cardBorder, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: StatsColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _FadeText(
                text: value,
                alignment: Alignment.centerRight,
                style: const TextStyle(
                  fontFamily: 'Lato',
                  fontFamilyFallback: const ['sans-serif'],
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: StatsColors.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                caption!,
                style: const TextStyle(color: StatsColors.label, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final String value;
  final String label;

  const _MiniTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: StatsColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StatsColors.cardBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FadeText(
            text: value,
            alignment: Alignment.centerLeft,
            style: const TextStyle(
              fontFamily: 'Lato',
              fontFamilyFallback: const ['sans-serif'],
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: StatsColors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: StatsColors.label, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Text that cross-fades when its value changes.
class _FadeText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Alignment alignment;

  const _FadeText({
    required this.text,
    required this.style,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}

/// ---------------------------------------------------------------------------
/// PAINTERS
/// ---------------------------------------------------------------------------
/// Line chart that leaves gaps where there is no data (NaN) instead of
/// drawing made-up values. Isolated points are drawn as dots.
class _LinePainter extends CustomPainter {
  final List<double> v; // 0..1, NaN = missing

  _LinePainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    const pad = 3.0;
    final dx = v.length == 1 ? 0.0 : (size.width - pad * 2) / (v.length - 1);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = StatsColors.mint;
    final dot = Paint()..color = StatsColors.mint;

    final path = Path();
    var pen = false;
    for (int i = 0; i < v.length; i++) {
      if (v[i].isNaN) {
        pen = false;
        continue;
      }
      final x = pad + dx * i;
      final y = pad + (1 - v[i]) * (size.height - pad * 2);

      final prevOk = i > 0 && !v[i - 1].isNaN;
      final nextOk = i < v.length - 1 && !v[i + 1].isNaN;
      if (!prevOk && !nextOk) canvas.drawCircle(Offset(x, y), 2.6, dot);

      if (!pen) {
        path.moveTo(x, y);
        pen = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

class _BarsPainter extends CustomPainter {
  final List<double> v; // 0..1
  final int? highlight; // bar drawn in accent colour (default: the last one)

  _BarsPainter(this.v, {this.highlight});

  @override
  void paint(Canvas canvas, Size size) {
    final n = v.length;
    if (n == 0) return;
    final slot = size.width / n;
    final barW = slot * 0.72;
    final radius = math.min(6.0, barW / 2);
    final hi = highlight ?? n - 1;

    for (int i = 0; i < n; i++) {
      final value = v[i].isNaN ? 0.0 : v[i];
      final h = math.max(size.height * 0.08, value * size.height);
      final left = i * slot + (slot - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - h, barW, h),
          Radius.circular(radius),
        ),
        Paint()..color = i == hi ? StatsColors.mint : StatsColors.bar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}
