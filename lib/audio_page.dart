import 'package:flutter/material.dart';

import 'main.dart';
import 'library_page.dart';
import 'my_music_page.dart';

/// Audio-page accent colors: green accents on the existing green surfaces.
class _AudioPageColors {
  static const accent = Color(0xFF72D6A0);
  static const accentText = Color(0xFFB4E8C9);
  static const border = Color(0x665CBF8A);
}

/// AUDIO page: title + segmented tabs that switch between two separate pages.
class AudioPage extends StatefulWidget {
  const AudioPage({super.key});

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage>
    with SingleTickerProviderStateMixin {
  static const _labels = ['Library', 'My music'];

  int _tab = 0;
  int _dir = 1;

  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _tab) return;
    setState(() {
      _dir = i > _tab ? 1 : -1;
      _tab = i;
    });
  }

  Widget _stagger(int index, Widget child) {
    final begin = (index * 0.15).clamp(0.0, 0.6).toDouble();
    final end = (begin + 0.5).clamp(0.0, 1.0).toDouble();
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

  Widget _tabPage() {
    switch (_tab) {
      case 0:
        return LibraryPage(
          key: const ValueKey('library'),
          onOpenMyMusic: () => _select(1),
        );
      default:
        return const MyMusicPage(key: ValueKey('mymusic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stagger(
            0,
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                'Audio',
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontFamilyFallback: const ['sans-serif'],
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _stagger(
            1,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Segmented(
                labels: _labels,
                selected: _tab,
                onChanged: _select,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0.06 * _dir, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: _tabPage(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const _Segmented({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // Match the app's green card surface instead of the old navy-blue tint.
        color: AppColors.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _AudioPageColors.border, width: 1.2),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment(-1 + 2 * selected / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: _AudioPageColors.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: List.generate(n, (i) {
                final sel = i == selected;
                return Expanded(
                  child: Pressable(
                    pressedScale: 0.95,
                    onTap: () => onChanged(i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: sel
                              ? AppColors.dark
                              : _AudioPageColors.accentText,
                        ),
                        child: Text(labels[i]),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
