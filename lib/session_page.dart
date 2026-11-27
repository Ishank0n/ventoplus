  import 'dart:async';
  import 'dart:math' as math;

  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

  // Re-uses AppColors, kSerif, Technique, PlantIcon and Pressable from main.dart
  import 'main.dart';
  import 'breathe_api.dart';
  import 'audio_state.dart';
  import 'audio_widgets.dart' show TrackTile, audioSnack;
  import 'vitals_service.dart';
  import 'vitals_reading.dart';

  class _Phase {
    final String label; // Inhale
    final String action; // Inhaling
    final String hint;
    final int seconds;
    final String phaseKey; // inhale | hold_in | exhale | hold_out

    const _Phase(this.label, this.action, this.hint, this.seconds, this.phaseKey);
  }

  /// A flower available to use as the visual companion during a session.
  class SessionFlower {
    final String id;
    final String name;
    final String emoji;

    const SessionFlower({
      required this.id,
      required this.name,
      required this.emoji,
    });
  }

  /// Builds the phases from a pattern string, e.g. "4-4-4-4", "4-7-8", "5-5".
  List<_Phase> _phasesFor(String pattern) {
    final n = pattern.split('-').map((e) => int.tryParse(e) ?? 4).toList();

    _Phase inhale(int s) =>
        _Phase('Inhale', 'Inhaling', 'Breathe in slowly through your nose', s, 'inhale');
    _Phase hold(int s) =>
        _Phase('Hold', 'Holding', 'Hold your breath gently', s, 'hold');
    _Phase exhale(int s) =>
        _Phase('Exhale', 'Exhaling', 'Breathe out slowly through your mouth', s, 'exhale');

    if (n.length >= 4) return [inhale(n[0]), hold(n[1]), exhale(n[2]), hold(n[3])];
    if (n.length == 3) return [inhale(n[0]), hold(n[1]), exhale(n[2])];
    if (n.length == 2) return [inhale(n[0]), exhale(n[1])];
    return [inhale(4), exhale(4)];
  }

  /// ---------------------------------------------------------------------------
  /// SESSION PAGE
  /// ---------------------------------------------------------------------------
  class SessionPage extends StatefulWidget {
    final Technique technique;
    final bool restart;

    const SessionPage({super.key, required this.technique, this.restart = false});

    @override
    State<SessionPage> createState() => _SessionPageState();
  }

  class _SessionPageState extends State<SessionPage>
      with SingleTickerProviderStateMixin {
    late final List<_Phase> _phases;
    late final int _cycleSeconds;
    late final AnimationController _cycle;
    late final Duration _startOffset;
    final Stopwatch _sw = Stopwatch()..start();

    // Band readings are retained for background session logging only.
    late final VitalsService _band;
    Timer? _uploadTimer;
    final Stopwatch _sessionStopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> _pendingReadings = [];
    DateTime? _lastReadingAt;
    int _lastElapsedMs = -1;
    bool _uploading = false;

    // Live breathing phase from the ESP32 band controls the flower/circle.
    String? _liveBreathingPhase;
    double _userBreathScale = _minScale;

    AudioTrack? _sessionTrack;
    bool _done = false;

    // Each MP4 grows from its first frame to its final frame over the full
    // duration of the breathing exercise.
    VideoPlayerController? _flowerVideoController;
    bool _flowerVideoReady = false;
    bool _flowerVideoFailed = false;

    String get _flowerVideoAsset {
      // Prefer the visible technique name. API slugs are not guaranteed to
      // match the local MP4 filenames (e.g. slug "box" vs "box_breathing").
      String normalize(String value) => value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '');

      final nameKey = normalize(widget.technique.name);
      final slugKey = normalize(widget.technique.slug ?? '');

      // Explicit mapping for the techniques shown in the app. Both the
      // technique name and common slug variants are supported.
      const assetsByKey = <String, String>{
        'boxbreathing': 'box_breathing.mp4',
        'box': 'box_breathing.mp4',

        '46breathing': '46_breathing.mp4',
        '46': '46_breathing.mp4',

        '55coherentbreathing': '55_coherent_breathing.mp4',
        '55coherent': '55_coherent_breathing.mp4',

        'coherentbreathing': 'coherent_breathing.mp4',
        'pursedlipbreathing': 'pursed_lip_breathing.mp4',
        'pursedlip': 'pursed_lip_breathing.mp4',
        'pursedlipbreath': 'pursed_lip_breathing.mp4',

        'extendedexhale12': 'extended_exhale_1_2.mp4',
        'extendedexhale': 'extended_exhale_1_2.mp4',

        'physiologicalsigh': 'physiological_sigh.mp4',
        '426breathing': '426_breathing.mp4',
        'alternatenostrilbreathing': 'alternate_nostril_breathing.mp4',
        'alternatenostril': 'alternate_nostril_breathing.mp4',
        'hummingbeebreath': 'humming_bee_breath.mp4',
        'hummingbee': 'humming_bee_breath.mp4',
        '54321grounding': '5_4_3_2_1_grounding.mp4',
        '54321': '5_4_3_2_1_grounding.mp4',

        // Other names present in the local fallback catalogue.
        '478calm': '4_7_8_calm.mp4',
        '478breathing': '4_7_8_calm.mp4',
        'bellybreathing': 'belly_breathing.mp4',
      };

      final fileName = assetsByKey[nameKey] ??
          assetsByKey[slugKey] ??
          '${(widget.technique.slug?.trim().isNotEmpty == true ? widget.technique.slug! : widget.technique.name).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '')}.mp4';

      return 'assets/flower/$fileName';
    }

    Future<void> _setupFlowerVideo() async {
      debugPrint('Loading session flower video: $_flowerVideoAsset');
      final controller = VideoPlayerController.asset(_flowerVideoAsset);
      _flowerVideoController = controller;

      try {
        await controller.initialize();
        await controller.setLooping(false);
        await controller.setVolume(0);

        // Match the complete plant-growth animation to the exercise duration.
        // Example: a 12-second source video in a 3-minute session plays at
        // 12 / 180 = 0.0667x, reaching the final plant at the session end.
        final exerciseDuration = Duration(
          seconds: math.max(1, widget.technique.minutes * 60).toInt(),
        );
        final sourceDuration = controller.value.duration;
        if (sourceDuration.inMilliseconds > 0) {
          final playbackSpeed = sourceDuration.inMilliseconds /
              exerciseDuration.inMilliseconds;
          await controller.setPlaybackSpeed(playbackSpeed);
        }
        await controller.seekTo(Duration.zero);

        if (!mounted) {
          await controller.dispose();
          return;
        }

        setState(() {
          _flowerVideoReady = true;
          _flowerVideoFailed = false;
        });
        await controller.play();
        debugPrint(
          'Flower growth duration: ${controller.value.duration.inSeconds}s source, '
          '${widget.technique.minutes} minute exercise',
        );
      } catch (error) {
        debugPrint('Could not load flower animation "$_flowerVideoAsset": $error');
        await controller.dispose();
        if (!mounted) return;
        setState(() {
          _flowerVideoController = null;
          _flowerVideoReady = false;
          _flowerVideoFailed = true;
        });
      }
    }

    // Each exercise gets a consistent flower companion. The mapping can be
    // made explicit by slug/name here as the exercise catalogue is finalized.
    static const List<SessionFlower> _allFlowers = [
      SessionFlower(id: 'rose', name: 'Rose', emoji: '🌹'),
      SessionFlower(id: 'sunflower', name: 'Sunflower', emoji: '🌻'),
      SessionFlower(id: 'tulip', name: 'Tulip', emoji: '🌷'),
      SessionFlower(id: 'daisy', name: 'Daisy', emoji: '🌼'),
      SessionFlower(id: 'cherry', name: 'Cherry Blossom', emoji: '🌸'),
      SessionFlower(id: 'lavender', name: 'Lavender', emoji: '🪻'),
      SessionFlower(id: 'hibiscus', name: 'Hibiscus', emoji: '🌺'),
      SessionFlower(id: 'blossom', name: 'Blossom', emoji: '💮'),
      SessionFlower(id: 'lotus', name: 'Lotus', emoji: '🪷'),
    ];

    late final SessionFlower _selectedFlower;

    String get _exerciseKey =>
        (widget.technique.slug ?? widget.technique.id?.toString() ?? widget.technique.name)
            .trim()
            .toLowerCase();

    SessionFlower _defaultFlower() {
      // Stable assignment: the same exercise always displays the same flower.
      // Replace/add entries here to assign a specific flower to an exercise.
      const fixedAssignments = <String, String>{
        // 'box-breathing': 'lotus',
        // '4-7-8-breathing': 'lavender',
      };
      final assignedId = fixedAssignments[_exerciseKey];
      if (assignedId != null) {
        return _allFlowers.firstWhere((flower) => flower.id == assignedId);
      }
      var hash = 0;
      for (final code in _exerciseKey.codeUnits) {
        hash = (hash * 31 + code) & 0x7fffffff;
      }
      return _allFlowers[hash % _allFlowers.length];
    }

    static const double _minScale = 0.82;

    @override
    void initState() {
      super.initState();
      _selectedFlower = _defaultFlower();

      // Start each breathing session with a randomly selected preset sound.
      // Avoid repeating the currently playing track when alternatives exist.
      final availableTracks = audio.library;
      if (availableTracks.isNotEmpty) {
        final alternatives = availableTracks.length > 1
            ? availableTracks
                .where((track) => track.id != audio.current?.id)
                .toList()
            : availableTracks;
        final randomTrack = alternatives[
            math.Random().nextInt(alternatives.length)];
        _sessionTrack = randomTrack;
        if (audio.current?.id != randomTrack.id || !audio.isPlaying) {
          unawaited(audio.toggle(randomTrack));
        }
      }

      _setupFlowerVideo();
      _phases = widget.technique.phases.isNotEmpty
          ? widget.technique.phases.map((p) {
              final key = p.phase;
              final label = key == 'inhale'
                  ? 'Inhale'
                  : key == 'exhale'
                      ? 'Exhale'
                      : 'Hold';
              final action = key == 'inhale'
                  ? 'Inhaling'
                  : key == 'exhale'
                      ? 'Exhaling'
                      : 'Holding';
              final hint = key == 'inhale'
                  ? 'Breathe in slowly through your nose'
                  : key == 'exhale'
                      ? 'Breathe out slowly through your mouth'
                      : 'Hold your breath gently';
              return _Phase(label, action, hint, p.durationSec.round().clamp(1, 60).toInt(), key);
            }).toList()
          : _phasesFor(widget.technique.pattern);
      _cycleSeconds = _phases.fold(0, (a, p) => a + p.seconds);
      // Every newly opened exercise starts at its full default duration.
      // Do not carry elapsed time over from a previous session.
      _startOffset = Duration(seconds: widget.technique.elapsedSec);
      final cycleMs = math.max(1, _cycleSeconds * 1000);
      final initialCycleValue =
          (_startOffset.inMilliseconds % cycleMs) / cycleMs;
      _cycle = AnimationController(
        vsync: this,
        duration: Duration(seconds: _cycleSeconds),
        value: initialCycleValue,
      )..repeat();

      _band = context.read<VitalsService>();
      _band.addListener(_onBand);
      // Send BLE samples in small batches instead of making one HTTP request
      // for every 500 ms notification.
      _uploadTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _flushReadings(),
      );
    }

    @override
    void dispose() {
      _uploadTimer?.cancel();
      _band.removeListener(_onBand);
      _cycle.dispose();
      _flowerVideoController?.dispose();
      super.dispose();
    }

    /// Called for each BLE notification and connection-state change.
    /// The live phase drives the breathing circle while sensor uploads continue
    /// quietly in the background.
    void _onBand() {
      final reading = _band.latest;

      // Connection changes can notify listeners before the first sensor
      // reading arrives. Rebuild so the live-state label updates immediately.
      if (reading == null) {
        if (mounted) {
          setState(() => _liveBreathingPhase = null);
        }
        return;
      }

      final phase = reading.phase.trim().toLowerCase();
      double? target;
      if (phase == 'inhale') {
        target = 1.0;
      } else if (phase == 'exhale') {
        target = _minScale;
      }

      if (_lastReadingAt == null || reading.at.isAfter(_lastReadingAt!)) {
        _lastReadingAt = reading.at;
        _queueReading(reading);
      }

      if (!mounted) return;
      setState(() {
        if (const {
          'inhale',
          'exhale',
          'hold',
          'hold_in',
          'hold_out',
          'none',
          'unknown',
        }.contains(phase)) {
          _liveBreathingPhase = phase;
        }
        // During a hold or when the sensor has no phase, keep the last
        // measured expansion level.
        if (target != null) _userBreathScale = target;
      });
    }

    void _queueReading(VitalsReading reading) {
      final sessionId = widget.technique.sessionId;
      if (sessionId == null || !_band.isConnected) return;

      var elapsedMs = _startOffset.inMilliseconds +
          _sessionStopwatch.elapsedMilliseconds;
      if (elapsedMs <= _lastElapsedMs) elapsedMs = _lastElapsedMs + 1;
      _lastElapsedMs = elapsedMs;

      // Firmware currently sends phase from the two physical buttons. `hold`
      // has no inhale/exhale subtype, so send null and let the backend exclude
      // that sample from the accuracy denominator.
      final detected = (reading.phase == 'inhale' || reading.phase == 'exhale')
          ? reading.phase
          : null;

      final sensors = <String, dynamic>{};
      // The supplied firmware sets demo=true and generates mock vitals. Do not
      // persist those values as real health measurements.
      if (!reading.demo) {
        sensors.addAll({
          'spo2_pct': reading.spo2,
          'heart_rate_bpm': reading.heartRate,
          'hrv_ms': reading.hrv,
          'stress': reading.stress,
          'steps': reading.steps.toDouble(),
          'wrist_tilt_deg': reading.wristTiltDeg,
        });
      }

      _pendingReadings.add({
        'elapsed_ms': elapsedMs,
        'detected_phase': detected,
        'sensors': sensors,
      });
      if (_pendingReadings.length >= 10) _flushReadings();
    }

    Future<void> _flushReadings() async {
      final sessionId = widget.technique.sessionId;
      if (sessionId == null || _pendingReadings.isEmpty || _uploading) return;
      _uploading = true;
      final batch = _pendingReadings.take(40).toList();
      _pendingReadings.removeRange(0, batch.length);
      try {
        await BreatheApi.instance.uploadBandReadings(sessionId, batch);
      } catch (e) {
        // Keep failed readings for the next retry, preserving timestamp order.
        _pendingReadings.insertAll(0, batch);
        if (_pendingReadings.length > 200) {
          _pendingReadings.removeRange(0, _pendingReadings.length - 200);
        }
        debugPrint('Could not upload band readings: $e');
      } finally {
        _uploading = false;
      }
    }

    Future<void> _finishSession({required bool completed}) async {
      if (_done) return;
      _done = true;
      _uploadTimer?.cancel();
      // Give any in-flight upload a chance to finish, then send the final batch.
      while (_uploading) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      await _flushReadings();
      if (!mounted) return;
      final elapsed = _startOffset.inSeconds + _sessionStopwatch.elapsed.inSeconds;
      Navigator.of(context).pop(BreatheSessionResult(
        elapsedSec: elapsed,
        cyclesCompleted: _cycleSeconds <= 0 ? 0 : elapsed ~/ _cycleSeconds,
        accuracyPct: null,
        completed: completed,
        abandoned: !completed,
      ));
    }

    String _fmt(int totalSeconds) {
      final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
      final s = (totalSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }


    Future<void> _openMusicPicker() async {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final height = MediaQuery.of(sheetContext).size.height * 0.78;
          return SafeArea(
            top: false,
            child: Container(
              height: height,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              decoration: const BoxDecoration(
                color: AppColors.bgTop,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1.2)),
              ),
              child: AnimatedBuilder(
                animation: audio,
                builder: (context, _) {
                  final presets = audio.library;
                  final imported = audio.imported;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.cardBorder,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Choose your music',
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontFamilyFallback: const ['sans-serif'],
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pick a preset sound or use audio from your device.',
                        style: TextStyle(color: AppColors.mintText, fontSize: 12.5),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Preset sounds',
                              style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${presets.length} available',
                            style: const TextStyle(color: AppColors.mintText, fontSize: 11.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                            for (final track in presets)
                              TrackTile(
                                key: ValueKey('session-${track.id}'),
                                track: track,
                                isCurrent: _sessionTrack?.id == track.id,
                                isPlaying: _sessionTrack?.id == track.id && audio.isPlaying,
                                onTap: () {
                                  setState(() => _sessionTrack = track);
                                  if (audio.current?.id != track.id || !audio.isPlaying) {
                                    audio.toggle(track);
                                  }
                                  Navigator.of(sheetContext).pop();
                                },
                              ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Your imported music',
                                    style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Pressable(
                                  onTap: audio.importing
                                      ? () {}
                                      : () async {
                                          final result = await audio.importAudio();
                                          if (!mounted) return;
                                          String message;
                                          if (result.error != null) {
                                            message = result.error!;
                                          } else if (result.cancelled) {
                                            return;
                                          } else if (result.added == 0) {
                                            message = 'Those tracks are already imported';
                                          } else {
                                            message = 'Imported ${result.added} ${result.added == 1 ? 'track' : 'tracks'}. Select one below.';
                                          }
                                          audioSnack(ScaffoldMessenger.of(context), message);
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: AppColors.cardBorder),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (audio.importing)
                                          const SizedBox(
                                            width: 13,
                                            height: 13,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint),
                                          )
                                        else
                                          const Icon(Icons.add_rounded, size: 16, color: AppColors.mint),
                                        const SizedBox(width: 5),
                                        Text(
                                          audio.importing ? 'Importing' : 'Import',
                                          style: const TextStyle(color: AppColors.mint, fontSize: 12, fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (imported.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Text(
                                  'Your imported tracks will appear here.',
                                  style: TextStyle(color: AppColors.mintText, fontSize: 12),
                                ),
                              )
                            else
                              for (final track in imported)
                                TrackTile(
                                  key: ValueKey('session-${track.id}'),
                                  track: track,
                                  isCurrent: _sessionTrack?.id == track.id,
                                  isPlaying: _sessionTrack?.id == track.id && audio.isPlaying,
                                  onTap: () {
                                    setState(() => _sessionTrack = track);
                                    if (audio.current?.id != track.id || !audio.isPlaying) {
                                      audio.toggle(track);
                                    }
                                    Navigator.of(sheetContext).pop();
                                  },
                                ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );
    }

    Widget _buildMusicCard() {
      return AnimatedBuilder(
        animation: audio,
        builder: (context, _) {
          final track = _sessionTrack;
          final playing = track != null && audio.current?.id == track.id && audio.isPlaying;
          return _SessionCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: Color(0xFF23503F), shape: BoxShape.circle),
                  child: const Icon(Icons.music_note_rounded, color: AppColors.mint, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Session music', style: TextStyle(color: AppColors.mintText, fontSize: 11.5)),
                      const SizedBox(height: 3),
                      Text(
                        track?.title ?? 'Choose a sound for your session',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      if (track != null)
                        Text(playing ? 'Playing' : 'Paused', style: const TextStyle(color: AppColors.mintText, fontSize: 11)),
                    ],
                  ),
                ),
                if (track != null)
                  Pressable(
                    onTap: () => audio.toggle(track),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.mint, size: 23),
                    ),
                  ),
                Pressable(
                  onTap: _openMusicPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      track == null ? 'Choose' : 'Change',
                      style: const TextStyle(color: AppColors.dark, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    @override
    Widget build(BuildContext context) {
      final t = widget.technique;

      return Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.bgTop, AppColors.bgBottom],
            ),
          ),
          child: SafeArea(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - v)),
                  child: child,
                ),
              ),
              child: AnimatedBuilder(
                animation: _cycle,
                builder: (context, _) => _buildContent(t),
              ),
            ),
          ),
        ),
      );
    }

    // Fine-tune each source video independently. Values are fractions of the
    // video viewport width; positive moves the plant right, negative left.
    // These offsets center the POT (the visual anchor), not necessarily the
    // widest part of the foliage.
    double get _flowerVideoOffsetX {
      String normalize(String value) =>
          value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

      final nameKey = normalize(widget.technique.name);
      final slugKey = normalize(widget.technique.slug ?? '');
      const offsets = <String, double>{
        'boxbreathing': -0.025,
        'box': -0.025,
        '46breathing': 0.0,
        '46': 0.0,
        '55coherentbreathing': 0.008,
        '55coherent': 0.008,
        'pursedlipbreathing': 0.008,
        'pursedlip': 0.008,
        'extendedexhale12': 0.030,
        'extendedexhale': 0.030,
        'physiologicalsigh': 0.035,
        '426breathing': 0.008,
        'alternatenostrilbreathing': 0.025,
        'alternatenostril': 0.025,
        'hummingbeebreath': 0.015,
        'hummingbee': 0.015,
      };

      return offsets[nameKey] ?? offsets[slugKey] ?? 0.0;
    }

    Widget _circle(double s, double diameter) {
      return Transform.scale(
        scale: s,
        child: Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1F4A3A),
            border: Border.all(
              color: const Color(0xFF7FD69A),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.mint.withAlpha(
                    (20 + 50 * (s - _minScale) / (1 - _minScale))
                        .round()
                        .clamp(0, 255)
                        .toInt()),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: _flowerVideoReady &&
                    _flowerVideoController != null &&
                    _flowerVideoController!.value.isInitialized
                ? ClipOval(
                    key: const ValueKey('flower-video'),
                    child: SizedBox(
                      width: diameter * 0.88,
                      height: diameter * 0.88,
                      child: Transform.translate(
                        offset: Offset(diameter * _flowerVideoOffsetX, 0),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: _flowerVideoController!.value.size.width,
                            height: _flowerVideoController!.value.size.height,
                            child: VideoPlayer(_flowerVideoController!),
                          ),
                        ),
                      ),
                    ),
                  )
                : _flowerVideoFailed
                    ? const Icon(
                        Icons.local_florist_rounded,
                        key: ValueKey('flower-video-fallback'),
                        color: AppColors.mint,
                        size: 64,
                      )
                    : const SizedBox(
                        key: ValueKey('flower-video-loading'),
                        width: 1,
                        height: 1,
                      ),
          ),
        ),
      );
    }

    Widget _buildContent(Technique t) {
      final totalSession = t.minutes * 60;
      final elapsedSession = (_sw.elapsed + _startOffset).inSeconds;
      final remaining = math.max(0, totalSession - elapsedSession);

      if (remaining <= 0 && !_done) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _finishSession(completed: true);
        });
      }

      final cycleT = _cycle.value * _cycleSeconds;
      double acc = 0;
      int idx = 0;
      for (int i = 0; i < _phases.length; i++) {
        if (cycleT < acc + _phases[i].seconds || i == _phases.length - 1) {
          idx = i;
          break;
        }
        acc += _phases[i].seconds;
      }

      final phase = _phases[idx];
      final inPhase = (cycleT - acc).clamp(0.0, phase.seconds.toDouble());
      final phaseProgress = inPhase / phase.seconds;
      final secondsLeft = (phase.seconds - inPhase).ceil().clamp(0, phase.seconds);

      // The flower follows the guided exercise, not the band's detected
      // phase. This keeps the instruction and measured performance distinct.
      final eased = Curves.easeInOut.transform(phaseProgress);
      double guideScale;
      if (phase.label == 'Inhale') {
        guideScale = _minScale + (1 - _minScale) * eased;
      } else if (phase.label == 'Exhale') {
        guideScale = 1 - (1 - _minScale) * eased;
      } else {
        final prev = _phases[(idx - 1 + _phases.length) % _phases.length];
        guideScale = prev.label == 'Inhale' ? 1.0 : _minScale;
      }
      final breathLevel = ((guideScale - _minScale) / (1 - _minScale))
          .clamp(0.0, 1.0)
          .toDouble();

      final reading = _band.latest;
      final bandConnected = _band.isConnected;
      final bandLive = _band.isLive && reading != null;
      final actualPhase = !bandConnected
          ? 'Band disconnected'
          : !bandLive
              ? 'Waiting for band data'
              : switch (reading.phase.trim().toLowerCase()) {
                  'inhale' => 'Inhaling',
                  'exhale' => 'Exhaling',
                  'hold' || 'hold_in' || 'hold_out' => 'Holding',
                  'none' => 'No skin contact',
                  _ => 'Detecting breathing',
                };

      String metric(double value, String suffix) =>
          value > 0 ? '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}$suffix' : '--';
            return Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        child: Column(
          children: [
            // Compact top bar leaves the majority of the screen for the flower.
            Row(
              children: [
                Pressable(
                  onTap: () => _finishSession(completed: false),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x661F4A3A),
                      border: Border.all(color: AppColors.cardBorder, width: 1.3),
                    ),
                    child: const Text(
                      'X',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      t.name,
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
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF23503F),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_fmt(remaining)} left',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            // The flower expands into all remaining available screen space.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final diameter = (math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ) * 0.96).toDouble();
                  return Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: _minScale,
                        end: guideScale,
                      ),
                      duration: const Duration(milliseconds: 850),
                      curve: Curves.easeInOut,
                      builder: (context, scale, _) => _circle(scale, diameter),
                    ),
                  );
                },
              ),
            ),

            // What the user should be doing: this meter follows the
            // breathing pattern and the flower above.
            _SessionCard(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'YOUR GUIDE',
                        style: TextStyle(
                          color: AppColors.mintText,
                          fontSize: 9.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${secondsLeft}s',
                        style: const TextStyle(
                          color: AppColors.mintText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${phase.label} · ${phase.hint}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: breathLevel,
                      minHeight: 7,
                      backgroundColor: const Color(0xFF2E6B52),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.mint),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),

            // What the band actually detects: never drives the guide meter.
            _SessionCard(
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'FROM YOUR BAND',
                        style: TextStyle(
                          color: AppColors.mintText,
                          fontSize: 9.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: bandLive ? AppColors.mint : Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        bandLive ? 'LIVE' : bandConnected ? 'CONNECTED' : 'OFFLINE',
                        style: const TextStyle(
                          color: AppColors.mintText,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          actualPhase,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (reading != null && bandLive) ...[
                        _BandMetric(label: 'BPM', value: metric(reading.heartRate, '')),
                        const SizedBox(width: 12),
                        _BandMetric(label: 'SpO₂', value: metric(reading.spo2, '%')),
                        const SizedBox(width: 12),
                        _BandMetric(label: 'HRV', value: metric(reading.hrv, '')),
                      ],
                    ],
                  ),
                  if (reading?.demo == true && bandLive)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Text(
                        'Demo sensor readings',
                        style: TextStyle(color: AppColors.mintText, fontSize: 9),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),

            // Music selector is the final control at the bottom of the page.
            _buildMusicCard(),
          ],
        ),
      );
    }
  }

  /// ---------------------------------------------------------------------------
  /// WIDGETS
  /// ---------------------------------------------------------------------------
  class _BandMetric extends StatelessWidget {
    final String label;
    final String value;

    const _BandMetric({required this.label, required this.value});

    @override
    Widget build(BuildContext context) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.mintText,
              fontSize: 8.5,
            ),
          ),
        ],
      );
    }
  }

  class _SessionCard extends StatelessWidget {
    final Widget child;
    final EdgeInsets padding;

    const _SessionCard({required this.child, required this.padding});

    @override
    Widget build(BuildContext context) {
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0x661F4A3A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xAA2E6B52), width: 1.2),
        ),
        child: child,
      );
    }
  }
