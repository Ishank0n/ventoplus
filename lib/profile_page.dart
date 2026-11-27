import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Re-uses Pressable, kSerif, kSerifFallback, auth, AuthGate and AppColors (main.dart)
import 'main.dart';
import 'vitals_service.dart';
import 'reminder_service.dart';

/// ---------------------------------------------------------------------------
/// PLACEHOLDER DATA  (replace with real data / state management)
/// ---------------------------------------------------------------------------
class ProfileData {
  static const String bandLastSync = '2 min ago';
  static const String footnote =
      'Vento+ supports stress management and well-being. It does not '
      'diagnose or treat any condition.';
}

/// Colors for this page. They now come from the shared AppColors palette
/// (Nebula Cyan / Deep Space / Orbit Navy) instead of the old teal StatsColors.
class _C {
  static const bg = AppColors.card; // 0xFF152B5C
  static const border = AppColors.cardBorder; // 0xFF2F5AA8
  static const mint = AppColors.mint; // 0xFF5CB8FF (Nebula Cyan)
  static const white = AppColors.white; // 0xFFFFFFFF
  static const dark = AppColors.dark; // 0xFF050B1F (Deep Space)
  static const divider = Color(0xFF224282); // between card and border
  static const subtle = AppColors.mintText; // 0xFF9FD4FF
  static const avatar = Color(0xFFB9A2FF);
  static const avatarText = Color(0xFF1B1740);
  static const danger = Color(0xFFFF9C94);
}

/// ---------------------------------------------------------------------------
/// PROFILE PAGE
/// ---------------------------------------------------------------------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  // Settings state (placeholders)
  bool _lightCues = true;
  bool _dailyReminder = false; // loaded from storage in initState
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);
  bool _loggingOut = false;

  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();
    _loadReminder();
    _loadUser();
  }

  // ---- Signed-in user --------------------------------------------------------
  // Same endpoint AuthGate uses to verify the login (main.dart).
  String _userName = '';
  String _userEmail = '';
  bool _userLoaded = false;

  Future<void> _loadUser() async {
    try {
      final res = await auth.authedGet('/api/me');
      if (res.statusCode != 200) {
        throw Exception('/api/me returned ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      // Accept either { ...user fields } or { "user": { ... } }.
      final Map<String, dynamic> data =
          decoded is Map<String, dynamic> && decoded['user'] is Map
              ? Map<String, dynamic>.from(decoded['user'] as Map)
              : decoded as Map<String, dynamic>;

      String pick(List<String> keys) {
        for (final k in keys) {
          final v = data[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return '';
      }

      final email = pick(['email']);
      var name = pick([
        'name',
        'display_name',
        'displayName',
        'full_name',
        'given_name',
      ]);
      // Fall back to the part of the email before '@'.
      if (name.isEmpty && email.contains('@')) name = email.split('@').first;

      if (!mounted) return;
      setState(() {
        _userName = name;
        _userEmail = email;
        _userLoaded = true;
      });
    } catch (e) {
      debugPrint('Profile load failed: $e');
      if (!mounted) return;
      setState(() => _userLoaded = true);
    }
  }

  Future<void> _loadReminder() async {
    final s = await ReminderService.instance.load();
    if (!mounted) return;
    setState(() {
      _dailyReminder = s.enabled;
      _time = TimeOfDay(hour: s.hour, minute: s.minute);
    });
  }

  Future<void> _toggleReminder() async {
    HapticFeedback.selectionClick();
    if (!_dailyReminder) {
      final ok = await ReminderService.instance.enable(_time);
      if (!mounted) return;
      if (!ok) {
        _snack(ReminderService.instance.supported
            ? 'Allow notifications in your phone settings to get reminders'
            : 'Reminders only work in the phone app');
        return;
      }
      setState(() => _dailyReminder = true);
      _snack('Daily reminder set for ${_time.format(context)}');
    } else {
      await ReminderService.instance.disable();
      if (!mounted) return;
      setState(() => _dailyReminder = false);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _stagger(int index, Widget child) {
    final begin = (index * 0.06).clamp(0.0, 0.6).toDouble();
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

  // ---- Helpers ---------------------------------------------------------------
  void _toggle(bool current, ValueChanged<bool> set) {
    HapticFeedback.selectionClick();
    setState(() => set(!current));
  }

  void _snack(String message) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _C.bg,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _C.border),
        ),
        content: Text(message, style: const TextStyle(color: _C.white)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openSheet(WidgetBuilder builder) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: const Color(0xAA000000),
      builder: builder,
    );
  }

  // ---- Row actions -----------------------------------------------------------
  Future<void> _confirmLogout() async {
    HapticFeedback.selectionClick();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _C.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _C.border),
        ),
        title: const Text(
          'Log out?',
          style: TextStyle(color: _C.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'You will need to sign in again to access your account.',
          style: TextStyle(color: _C.subtle, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _C.subtle)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Log out',
              style: TextStyle(color: _C.danger, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || _loggingOut) return;

    setState(() => _loggingOut = true);

    // Disconnect the BLE band first. A disconnect failure must not prevent
    // the user from logging out of their account.
    try {
      await context.read<VitalsService>().disconnect();
    } catch (e) {
      debugPrint('Band disconnect during logout failed: $e');
    }

    try {
      await auth.signOut();
    } catch (e) {
      // AuthService clears the local tokens even if the remote/Google sign-out
      // step fails, so continue to the authentication gate.
      debugPrint('Sign-out cleanup warning: $e');
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  void _openBand() {
    final bandService = context.read<VitalsService>();
    _openSheet(
      (_) => _BandSheet(
        service: bandService,
        lastSync: ProfileData.bandLastSync,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _C.mint,
            onPrimary: _C.dark,
            surface: _C.bg,
            onSurface: _C.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _time = picked);
      await ReminderService.instance.updateTime(picked);
      if (!mounted) return;
      _snack('Reminder set for ${picked.format(context)}');
    }
  }

  void _openPrivacy() {
    _openSheet(
      (_) => _PrivacySheet(
        // TODO: open real links with url_launcher
        onSelect: (label) => _snack('$label: add your link here'),
      ),
    );
  }

  // ---- Build -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bandService = context.watch<VitalsService>();
    final bandStatus = bandService.isConnected
        ? 'Paired'
        : (bandService.isBusy ? 'Connecting…' : 'Not paired');

    final name = !_userLoaded
        ? 'Loading…'
        : (_userName.isEmpty ? 'Your profile' : _userName);
    final email = _userEmail;
    final initial = _userName.isEmpty ? '?' : _userName[0].toUpperCase();

    final rows = <Widget>[
      _SettingRow(
        label: 'Band',
        trailing: _ValueText(bandStatus),
        onTap: _openBand,
      ),
      _SettingRow(
        label: 'Light cues',
        trailing: _CheckBox(value: _lightCues),
        onTap: () => _toggle(_lightCues, (v) => _lightCues = v),
      ),
      _SettingRow(
        label: 'Daily reminder',
        trailing: _CheckBox(value: _dailyReminder),
        onTap: _toggleReminder,
      ),
      _SettingRow(
        label: 'Reminder time',
        dim: !_dailyReminder,
        trailing: _ValueText(_time.format(context)),
        onTap: _pickTime,
      ),
      _SettingRow(
        label: 'Privacy and help',
        trailing: const SizedBox.shrink(),
        onTap: _openPrivacy,
      ),
    ];

    // Own opaque background so the shell's gradient never shows through.
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, AppColors.bgBottom],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stagger(
                0,
                const Text(
                  'User Profile',
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontFamilyFallback: const ['sans-serif'],
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _C.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _stagger(
                1,
                Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _C.avatar,
                      ),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontFamily: 'Lato',
                          fontFamilyFallback: const ['sans-serif'],
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _C.avatarText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Lato',
                              fontFamilyFallback: const ['sans-serif'],
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _C.white,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: _C.subtle, fontSize: 12.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _stagger(
                2,
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _C.bg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _C.border, width: 1.2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(21),
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        for (int i = 0; i < rows.length; i++)
                          _stagger(3 + i, rows[i]),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              ProfileData.footnote,
                              style: TextStyle(
                                color: _C.subtle,
                                fontSize: 10.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _stagger(
                3 + rows.length,
                _PillButton(
                  label: 'Log out',
                  onTap: _confirmLogout,
                  enabled: !_loggingOut,
                  loading: _loggingOut,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// ROW WIDGETS
/// ---------------------------------------------------------------------------
class _RowTap extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _RowTap({required this.onTap, required this.child});

  @override
  State<_RowTap> createState() => _RowTapState();
}

class _RowTapState extends State<_RowTap> {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // Pressed highlight: Nebula Cyan at 10% (was a teal tint).
        color: _down ? const Color(0x1A5CB8FF) : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget trailing;
  final VoidCallback onTap;
  final bool dim;

  const _SettingRow({
    required this.label,
    required this.trailing,
    required this.onTap,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RowTap(
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: dim ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: _C.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  trailing,
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: _C.divider)),
          ),
        ),
      ],
    );
  }
}

class _ValueText extends StatelessWidget {
  final String text;

  const _ValueText(this.text);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerRight,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: Text(
        text,
        key: ValueKey(text),
        style: const TextStyle(color: _C.mint, fontSize: 13.5),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  final bool value;

  const _CheckBox({required this.value});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: value ? _C.white : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _C.white, width: 1.6),
      ),
      child: AnimatedScale(
        scale: value ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: const Icon(Icons.check_rounded, size: 18, color: _C.dark),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool value;

  const _Toggle({required this.value});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // Off state: muted navy (was a gray-teal).
        color: value ? _C.mint : const Color(0xFF2A4580),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? _C.dark : _C.white,
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// BOTTOM SHEETS
/// ---------------------------------------------------------------------------
class _SheetFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const _SheetFrame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: _C.border, width: 1.2)),
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
                color: _C.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Lato',
              fontFamilyFallback: const ['sans-serif'],
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _C.white,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.filled = true,
    this.enabled = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : () {},
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? _C.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: filled ? null : Border.all(color: _C.border, width: 1.3),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(_C.dark),
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: filled ? _C.dark : _C.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Band status is driven by the real VitalsService BLE connection.
class _BandSheet extends StatefulWidget {
  final VitalsService service;
  final String lastSync;

  const _BandSheet({
    required this.service,
    required this.lastSync,
  });

  @override
  State<_BandSheet> createState() => _BandSheetState();
}

class _BandSheetState extends State<_BandSheet> {
  late String _lastSync = widget.lastSync;
  bool _syncing = false;
  bool _connectionActionRunning = false;

  Future<void> _toggleConnection() async {
    if (_connectionActionRunning || widget.service.isBusy) return;

    setState(() => _connectionActionRunning = true);
    try {
      if (widget.service.isConnected) {
        await widget.service.disconnect();
      } else {
        await widget.service.connectToBand();
      }

      if (!mounted) return;
      final error = widget.service.error;
      if (error != null && error.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Band connection failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _connectionActionRunning = false);
    }
  }

  Future<void> _sync() async {
    if (!widget.service.isConnected || _syncing) return;
    setState(() => _syncing = true);
    // The current VitalsService has no separate sync command. A successful
    // BLE connection already streams live readings from the band.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastSync = 'Just now';
    });
  }

  Widget _info(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(k,
                  style: const TextStyle(color: _C.subtle, fontSize: 13.5)),
            ),
            Text(v,
                style: const TextStyle(
                    color: _C.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final connected = widget.service.isConnected;
        final busy = widget.service.isBusy || _connectionActionRunning;
        final status = connected
            ? 'Paired'
            : (busy ? 'Connecting…' : 'Not paired');

        return _SheetFrame(
          title: 'Band',
          child: Column(
            children: [
              _info('Status', status),
              _info('Last sync', connected ? _lastSync : '--'),
              if (widget.service.error != null &&
                  widget.service.error!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.service.error!,
                    style: const TextStyle(
                      color: _C.danger,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _PillButton(
                      label: 'Sync now',
                      loading: _syncing,
                      enabled: connected && !_syncing,
                      onTap: _sync,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PillButton(
                      label: busy
                          ? 'Connecting…'
                          : (connected ? 'Unpair' : 'Pair band'),
                      filled: false,
                      loading: busy,
                      enabled: !busy,
                      onTap: _toggleConnection,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Privacy and help links.
class _PrivacySheet extends StatelessWidget {
  final ValueChanged<String> onSelect;

  const _PrivacySheet({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const items = <String>[
      'Privacy policy',
      'Terms of use',
      'Help center',
      'Contact support',
      'Delete my data',
    ];
    return _SheetFrame(
      title: 'Privacy and help',
      child: Column(
        children: items.map((label) {
          final danger = label == 'Delete my data';
          return _RowTap(
            onTap: () {
              Navigator.of(context).pop();
              onSelect(label);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: danger ? _C.danger : _C.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: danger ? _C.danger : _C.subtle,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
