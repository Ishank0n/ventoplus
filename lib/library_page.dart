import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';
import 'audio_state.dart';
import 'audio_widgets.dart';

/// Library-page accent colors.
///
/// Keep the existing navy backgrounds, but use a consistent green accent
/// throughout this page instead of mixing AppColors' cyan/blue accent values.
class _LibraryColors {
  static const accent = Color(0xFF72D6A0);
  static const accentText = Color(0xFFB4E8C9);
  static const border = Color(0x665CBF8A);
}

/// LIBRARY tab: now playing, scrollable plant sounds, import / choose.
class LibraryPage extends StatelessWidget {
  /// Called when the user taps "View" after importing files.
  final VoidCallback onOpenMyMusic;

  const LibraryPage({super.key, required this.onOpenMyMusic});

  Future<void> _chooseSongs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xAA000000),
      builder: (_) => const _ChooseSongsSheet(),
    );
    if (n != null) {
      audioSnack(
        messenger,
        n == 0
            ? 'No songs chosen'
            : '$n ${n == 1 ? 'song' : 'songs'} chosen for your sessions',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: audio,
      builder: (context, _) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: NowPlayingCard(),
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AudioHeading('Plant sounds'),
              ),
            ),
            const SizedBox(height: 4),

            // Scrollable plant sounds
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: audio.library.length,
                itemBuilder: (context, i) {
                  final t = audio.library[i];
                  final isCurrent = audio.current?.id == t.id;
                  return TrackTile(
                    track: t,
                    isCurrent: isCurrent,
                    isPlaying: audio.isPlaying,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      audio.toggle(t);
                    },
                    trailing: audio.chosen.contains(t.id)
                        ? const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: _LibraryColors.accent,
                          )
                        : null,
                  );
                },
              ),
            ),

            // Import / choose
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AudioPillButton(
                          label: 'Import audio',
                          filled: false,
                          loading: audio.importing,
                          onTap: () =>
                              runImport(context, onView: onOpenMyMusic),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AudioPillButton(
                          label: 'Choose songs',
                          onTap: () => _chooseSongs(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom sheet: pick which songs to use in sessions.
class _ChooseSongsSheet extends StatefulWidget {
  const _ChooseSongsSheet();

  @override
  State<_ChooseSongsSheet> createState() => _ChooseSongsSheetState();
}

class _ChooseSongsSheetState extends State<_ChooseSongsSheet> {
  late final Set<String> _sel = Set<String>.of(audio.chosen);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.45;
    final tracks = audio.allTracks;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgTop,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: _LibraryColors.border, width: 1.2),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _LibraryColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Choose songs',
            style: TextStyle(
              fontFamily: 'Lato',
              fontFamilyFallback: const ['sans-serif'],
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_sel.length} selected',
            style: const TextStyle(
              color: _LibraryColors.accentText,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ListView(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              children: tracks.map((t) {
                final on = _sel.contains(t.id);
                return Pressable(
                  pressedScale: 0.98,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => on ? _sel.remove(t.id) : _sel.add(t.id));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
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
                                t.subtitle,
                                style: const TextStyle(
                                  color: _LibraryColors.accentText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on
                                ? _LibraryColors.accent
                                : Colors.transparent,
                            border: Border.all(
                              color: on
                                  ? _LibraryColors.accent
                                  : _LibraryColors.border,
                              width: 2,
                            ),
                          ),
                          child: AnimatedScale(
                            scale: on ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutBack,
                            child: const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: AppColors.dark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AudioPillButton(
                  label: 'Cancel',
                  filled: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AudioPillButton(
                  label: 'Save',
                  onTap: () {
                    audio.setChosen(_sel);
                    Navigator.of(context).pop(_sel.length);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
