import 'package:flutter/material.dart';

// Re-uses AppColors, Pressable, kSerif and kSerifFallback from main.dart.
import 'main.dart';
import 'audio_state.dart';

/// Shared green accent palette for all audio widgets.
class _AudioWidgetColors {
  static const accent = Color(0xFF72D6A0);
  static const accentText = Color(0xFFB4E8C9);
  static const border = Color(0x665CBF8A);
  static const faintTrack = Color(0x553D805F);
  static const divider = Color(0x665CBF8A);
  static const tile = Color(0xFF173B2D);
  static const surface = Color(0xFF1F4A3A);
}

/// Translucent card used across the audio pages.
class AudioCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  const AudioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _AudioWidgetColors.border, width: 1.2),
      ),
      child: child,
    );
  }
}

/// Section heading (serif, bold).
class AudioHeading extends StatelessWidget {
  final String text;

  const AudioHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Lato',
        fontFamilyFallback: const ['sans-serif'],
        fontSize: 15.5,
        fontWeight: FontWeight.w800,
        color: AppColors.white,
      ),
    );
  }
}

class SeekBar extends StatefulWidget {
  final double value; // 0..1
  final ValueChanged<double> onChanged;

  const SeekBar({super.key, required this.value, required this.onChanged});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  void _commit() {
    final v = _drag;
    setState(() => _drag = null);
    if (v != null) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const box = 22.0;
        final usable = (c.maxWidth - box).clamp(0.0, double.infinity);
        final active = _drag != null;
        final v = (_drag ?? widget.value).clamp(0.0, 1.0).toDouble();

        double toValue(double dx) => usable == 0
            ? 0
            : ((dx - box / 2) / usable).clamp(0.0, 1.0).toDouble();
        void hold(double dx) => setState(() => _drag = toValue(dx));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => hold(d.localPosition.dx),
          onTapUp: (_) => _commit(),
          onTapCancel: () => setState(() => _drag = null),
          onHorizontalDragStart: (d) => hold(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => hold(d.localPosition.dx),
          onHorizontalDragEnd: (_) => _commit(),
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: box / 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: usable,
                    height: active ? 6 : 4,
                    decoration: BoxDecoration(
                      color: _AudioWidgetColors.faintTrack,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: box / 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: v * usable,
                    height: active ? 6 : 4,
                    decoration: BoxDecoration(
                      color: _AudioWidgetColors.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: v * usable,
                  child: SizedBox(
                    width: box,
                    height: box,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        width: active ? 20 : 13,
                        height: active ? 20 : 13,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _AudioWidgetColors.accent,
                          boxShadow: [
                            BoxShadow(
                              color: _AudioWidgetColors.accent.withValues(
                                alpha: active ? 0.35 : 0.15,
                              ),
                              blurRadius: active ? 12 : 6,
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
        );
      },
    );
  }
}

/// "Now playing" card with the current track and a seek bar.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: audio,
      builder: (context, _) {
        final t = audio.current;
        return AudioCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Now playing',
                style: TextStyle(
                  color: _AudioWidgetColors.accentText,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Text(
                  t?.title ?? 'Nothing playing',
                  key: ValueKey(t?.id ?? 'none'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontFamilyFallback: const ['sans-serif'],
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SeekBar(value: audio.progress, onChanged: audio.seek),
            ],
          ),
        );
      },
    );
  }
}

/// One row in a track list: round play / pause button, title, subtitle.
class TrackTile extends StatelessWidget {
  final AudioTrack track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final showPause = isCurrent && isPlaying;
    return Column(
      children: [
        Pressable(
          pressedScale: 0.98,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent
                        ? _AudioWidgetColors.accent
                        : _AudioWidgetColors.tile,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      showPause
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      key: ValueKey(showPause),
                      size: 24,
                      color: isCurrent ? AppColors.dark : AppColors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _AudioWidgetColors.accentText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
        Container(height: 1, color: _AudioWidgetColors.divider),
      ],
    );
  }
}

/// Pill button (filled accent or outlined).
class AudioPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool loading;
  final double height;

  const AudioPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.loading = false,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: loading ? () {} : onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? _AudioWidgetColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(height),
          border: filled
              ? null
              : Border.all(color: _AudioWidgetColors.border, width: 1.5),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    filled ? AppColors.dark : _AudioWidgetColors.accent,
                  ),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: filled ? AppColors.dark : AppColors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// Floating snackbar in the app's style.
void audioSnack(
  ScaffoldMessengerState messenger,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: _AudioWidgetColors.surface,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _AudioWidgetColors.border),
      ),
      content: Text(message, style: const TextStyle(color: AppColors.white)),
      duration: const Duration(seconds: 3),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: _AudioWidgetColors.accent,
              onPressed: onAction,
            )
          : null,
    ),
  );
}

/// Opens the file picker and imports audio. Shared by Library and My music.
Future<void> runImport(BuildContext context, {VoidCallback? onView}) async {
  final messenger = ScaffoldMessenger.of(context);
  final r = await audio.importAudio();
  if (r.cancelled) return;

  String msg;
  if (r.error != null) {
    msg = r.error!;
  } else if (r.added == 0) {
    msg = r.skipped > 0
        ? 'Those files are already in My music'
        : 'No audio files were selected';
  } else {
    msg = 'Imported ${r.added} ${r.added == 1 ? 'file' : 'files'}';
    if (r.skipped > 0) msg += ' · ${r.skipped} skipped';
  }

  audioSnack(
    messenger,
    msg,
    actionLabel: (r.added > 0 && onView != null) ? 'View' : null,
    onAction: onView,
  );
}
