import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'vitals_service.dart';
import 'vitals_reading.dart';

/// ---------------------------------------------------------------------------
/// MODELS
/// ---------------------------------------------------------------------------
enum StatsPeriod { day, week, month, year }

extension StatsPeriodX on StatsPeriod {
  String get label {
    switch (this) {
      case StatsPeriod.day:
        return 'Day';
      case StatsPeriod.week:
        return 'Week';
      case StatsPeriod.month:
        return 'Month';
      case StatsPeriod.year:
        return 'Year';
    }
  }
}

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();
List<double?> _list(dynamic v) => (v as List).map(_d).toList();

String _group(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// One period of statistics exactly as stored on the server. No placeholders:
/// anything without data is null and the UI shows "--" / a gap.
class StatsSnapshot {
  final StatsPeriod period;
  final DateTime fetchedAt;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final bool hasData;
  final bool includesDemo;

  final double? hrAvg, hrMin, hrMax, spo2Avg, spo2Min;
  final int stepsTotal, stepsDailyAvg;
  final double caloriesTotal, caloriesDailyAvg;
  final int exercises, collectibles, practiceSec;

  /// Bucket series. null = no data in that bucket (hour/day/month).
  final List<double?> heart, spo2, steps, calories;

  StatsSnapshot._({
    required this.period,
    required this.fetchedAt,
    required this.rangeStart,
    required this.rangeEnd,
    required this.hasData,
    required this.includesDemo,
    required this.hrAvg,
    required this.hrMin,
    required this.hrMax,
    required this.spo2Avg,
    required this.spo2Min,
    required this.stepsTotal,
    required this.stepsDailyAvg,
    required this.caloriesTotal,
    required this.caloriesDailyAvg,
    required this.exercises,
    required this.collectibles,
    required this.practiceSec,
    required this.heart,
    required this.spo2,
    required this.steps,
    required this.calories,
  });

  factory StatsSnapshot.fromJson(StatsPeriod period, Map<String, dynamic> j) {
    final sum = j['summary'] as Map<String, dynamic>;
    final hr = sum['heart_rate'] as Map<String, dynamic>;
    final ox = sum['spo2'] as Map<String, dynamic>;
    final st = sum['steps'] as Map<String, dynamic>;
    final cal = sum['calories'] as Map<String, dynamic>;
    final br = j['breathing'] as Map<String, dynamic>;
    final se = j['series'] as Map<String, dynamic>;
    return StatsSnapshot._(
      period: period,
      fetchedAt: DateTime.now(),
      rangeStart: DateTime.parse(j['range_start'] as String),
      rangeEnd: DateTime.parse(j['range_end'] as String),
      hasData: j['has_data'] as bool,
      includesDemo: j['includes_demo'] as bool,
      hrAvg: _d(hr['avg']),
      hrMin: _d(hr['min']),
      hrMax: _d(hr['max']),
      spo2Avg: _d(ox['avg']),
      spo2Min: _d(ox['min']),
      stepsTotal: (st['total'] as num).toInt(),
      stepsDailyAvg: (st['daily_avg'] as num).toInt(),
      caloriesTotal: (cal['total'] as num).toDouble(),
      caloriesDailyAvg: (cal['daily_avg'] as num).toDouble(),
      exercises: (br['exercises'] as num).toInt(),
      collectibles: (br['collectibles'] as num).toInt(),
      practiceSec: (br['total_sec'] as num).toInt(),
      heart: _list(se['heart_rate']),
      spo2: _list(se['spo2']),
      steps: _list(se['steps']),
      calories: _list(se['calories']),
    );
  }

  // ---- display strings ----
  bool get isDay => period == StatsPeriod.day;

  String get heartText => hrAvg == null ? '--' : '${hrAvg!.round()} bpm';
  String get spo2Text => spo2Avg == null ? '--' : '${spo2Avg!.toStringAsFixed(1)}%';
  String get stepsText => hasData ? _group(isDay ? stepsTotal : stepsDailyAvg) : '--';
  String get caloriesText => hasData
      ? '${_group((isDay ? caloriesTotal : caloriesDailyAvg).round())} kcal'
      : '--';
  String get heartCaption => hrMin == null
      ? ''
      : 'Range ${hrMin!.round()}–${hrMax!.round()} bpm';
  String get spo2Caption => spo2Min == null
      ? ''
      : 'Lowest ${spo2Min!.toStringAsFixed(1)}%';

  String get practiceText {
    final h = practiceSec ~/ 3600;
    final m = (practiceSec % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

/// ---------------------------------------------------------------------------
/// API  (swap HttpStatsApi for your existing authenticated client if you have one)
/// ---------------------------------------------------------------------------
abstract class StatsApi {
  Future<void> postVitals(List<Map<String, dynamic>> buckets);
  Future<Map<String, dynamic>> getStats(StatsPeriod period, int tzOffsetMin);
}

class StatsApiException implements Exception {
  final int status;
  StatsApiException(this.status);
  @override
  String toString() => 'StatsApiException($status)';
}

class HttpStatsApi implements StatsApi {
  HttpStatsApi({
    required this.baseUrl,
    required this.accessToken,
    required this.userId,
  });

  final String baseUrl;
  final Future<String?> Function() accessToken;
  final Future<String?> Function() userId;

  Future<(Uri, Map<String, String>)> _target(String path) async {
    final id = await userId();
    final token = await accessToken();
    if (id == null || token == null) throw StatsApiException(401);
    return (
      Uri.parse('$baseUrl/api/users/$id/$path'),
      {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    );
  }

  @override
  Future<void> postVitals(List<Map<String, dynamic>> buckets) async {
    final (uri, headers) = await _target('vitals');
    final res = await http
        .post(uri, headers: headers, body: jsonEncode({'buckets': buckets}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw StatsApiException(res.statusCode);
  }

  @override
  Future<Map<String, dynamic>> getStats(StatsPeriod period, int tzOffsetMin) async {
    final (uri, headers) = await _target('stats');
    final res = await http
        .get(
          uri.replace(queryParameters: {
            'period': period.name,
            'tz_offset_min': '$tzOffsetMin',
          }),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 300) throw StatsApiException(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

/// ---------------------------------------------------------------------------
/// MINUTE BUCKET
/// ---------------------------------------------------------------------------
class _Bucket {
  _Bucket(this.minute);

  final DateTime minute; // UTC, floored to the minute
  int n = 0;
  double hrSum = 0, hrMin = double.infinity, hrMax = 0;
  double spo2Sum = 0, spo2Min = double.infinity;
  int steps = 0;
  bool demo = false;

  void add(double hr, double spo2, bool isDemo) {
    n++;
    hrSum += hr;
    spo2Sum += spo2;
    if (hr < hrMin) hrMin = hr;
    if (hr > hrMax) hrMax = hr;
    if (spo2 < spo2Min) spo2Min = spo2;
    demo = demo || isDemo;
  }

  double _r1(double v) => double.parse(v.toStringAsFixed(1));

  Map<String, dynamic> toJson() => {
        'minute': minute.toIso8601String(),
        'samples': n,
        'hr_avg': _r1(hrSum / n),
        'hr_min': _r1(hrMin),
        'hr_max': _r1(hrMax),
        'spo2_avg': _r1(spo2Sum / n),
        'spo2_min': _r1(spo2Min),
        'steps_delta': steps,
        'demo': demo,
      };
}

/// ---------------------------------------------------------------------------
/// REPOSITORY
///
/// Lives for the whole app session (not just while the Stats tab is open), so
/// data keeps being collected from the band in the background:
///   band reading (every 500 ms) -> current 1-minute bucket (in memory)
///   every minute: send closed buckets to the server -> re-fetch active period
/// The UI only ever changes once a minute.
/// ---------------------------------------------------------------------------
class StatsRepository extends ChangeNotifier with WidgetsBindingObserver {
  StatsRepository({
    required this.vitals,
    required this.api,
    this.syncInterval = const Duration(minutes: 1),
  }) {
    vitals.addListener(_onVitals);
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(syncInterval, (_) => _tick());
  }

  final VitalsService vitals;
  final StatsApi api;
  final Duration syncInterval;

  static const _maxPending = 2880; // 2 days of minutes if the server is unreachable
  static const _batchSize = 200; // matches the server limit

  Timer? _timer;
  _Bucket? _current;
  final List<_Bucket> _pending = [];
  VitalsReading? _lastReading;
  int? _lastSteps; // kept across disconnects so steps taken offline are credited

  final Map<StatsPeriod, StatsSnapshot> _cache = {};
  StatsPeriod _active = StatsPeriod.week;
  bool _loading = false;
  bool _flushing = false;
  String? _error;

  bool get loading => _loading;
  String? get error => _error;
  StatsSnapshot? snapshot(StatsPeriod p) => _cache[p];

  // ---- collecting ----------------------------------------------------------
  DateTime _floorMinute(DateTime t) =>
      DateTime.utc(t.year, t.month, t.day, t.hour, t.minute);

  void _onVitals() {
    if (!vitals.isLive) return;
    final r = vitals.latest;
    if (r == null || identical(r, _lastReading)) return;
    _lastReading = r;

    // Ignore sensor glitches (zeros, dropouts) rather than storing them.
    if (r.heartRate < 30 || r.heartRate > 220) return;
    if (r.spo2 < 70 || r.spo2 > 100) return;

    final now = DateTime.now().toUtc();
    final minute = _floorMinute(now);
    if (_current != null && _current!.minute != minute) {
      _pending.add(_current!);
      _current = null;
    }
    final b = _current ??= _Bucket(minute);
    b.add(r.heartRate, r.spo2, r.demo);

    // Steps arrive as a running counter. Store the difference, and treat a
    // drop as a band reboot/wrap (new counter value = steps since reset).
    final cur = r.steps;
    final last = _lastSteps;
    if (last != null) {
      final delta = cur >= last ? cur - last : cur;
      if (delta <= 5000) b.steps += delta; // sanity cap against corrupt values
    }
    _lastSteps = cur;
  }

  void _closeFinishedBuckets() {
    final cur = _current;
    if (cur != null && cur.minute.isBefore(_floorMinute(DateTime.now().toUtc()))) {
      _pending.add(cur);
      _current = null;
    }
  }

  // ---- syncing -------------------------------------------------------------
  Future<void> _tick() async {
    _closeFinishedBuckets();
    await _flush();
    await refresh();
  }

  Future<void> _flush() async {
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        final batch = _pending.take(_batchSize).toList();
        await api.postVitals(batch.map((b) => b.toJson()).toList());
        _pending.removeRange(0, batch.length);
      }
    } catch (e) {
      debugPrint('Vitals sync failed, will retry: $e');
      if (_pending.length > _maxPending) {
        _pending.removeRange(0, _pending.length - _maxPending);
      }
    } finally {
      _flushing = false;
    }
  }

  /// Pull-to-refresh: push what we have, then re-read the stats.
  Future<void> syncNow() async {
    _closeFinishedBuckets();
    await _flush();
    await refresh();
  }

  // ---- reading -------------------------------------------------------------
  void setActivePeriod(StatsPeriod p) {
    _active = p;
    refresh(p);
  }

  Future<void> refresh([StatsPeriod? period]) async {
    final p = period ?? _active;
    _loading = true;
    notifyListeners();
    try {
      final json = await api.getStats(p, DateTime.now().timeZoneOffset.inMinutes);
      _cache[p] = StatsSnapshot.fromJson(p, json);
      _error = null;
    } catch (e) {
      debugPrint('Stats refresh failed: $e');
      _error = 'refresh_failed';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---- lifecycle -----------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flush(); // best effort before the OS suspends us
    } else if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    vitals.removeListener(_onVitals);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}