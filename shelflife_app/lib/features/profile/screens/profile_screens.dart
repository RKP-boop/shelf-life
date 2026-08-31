// Screens 42–47 — profile, impact and settings.
//
// 42 Profile · 43 Impact · 44 Reminders · 45 Account · 46 About · 47 Sign out.
//
// Principle 3 governs screen 43 completely: it counts what was rescued and
// never what was wasted. `consumption_events` records `removed` as well as
// `used` because the "% used in time" figure needs a denominator — but no
// screen ever renders a waste count. The money figure is always labelled an
// estimate, because it is derived from seeded market rates, not receipts.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/models.dart';

// ------------------------------------------------------------------ 42

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.displayName,
    required this.email,
    required this.stats,
    this.isGuest = false,
    this.syncState = SyncState.synced,
    this.pendingCount = 0,
    this.onTabChanged,
    this.onImpact,
    this.onReminders,
    this.onAccount,
    this.onAbout,
    this.onSignOut,
    this.onSignIn,
  });

  final String displayName;
  final String? email;
  final KitchenStats stats;
  final bool isGuest;
  final SyncState syncState;
  final int pendingCount;
  final ValueChanged<NavTab>? onTabChanged;
  final VoidCallback? onImpact;
  final VoidCallback? onReminders;
  final VoidCallback? onAccount;
  final VoidCallback? onAbout;
  final VoidCallback? onSignOut;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => AppScreen(
        bottomBar: BottomNav(active: NavTab.profile, onTap: onTabChanged),
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: const BoxDecoration(
                      color: T.tintMint,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.isEmpty
                          ? '?'
                          : displayName.substring(0, 1).toUpperCase(),
                      style: T.displayBold26.copyWith(color: T.accentPrimary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, style: T.titleSemiBold18),
                        const SizedBox(height: 2),
                        Text(
                          isGuest ? 'No account yet' : email ?? '',
                          style: T.secondaryRegular13
                              .copyWith(color: T.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SyncIndicator(state: syncState, pending: pendingCount),
              const SizedBox(height: 20),
              _ImpactSummary(stats: stats, onTap: onImpact),
              const SizedBox(height: 22),
              const SectionHeader('Settings'),
              const SizedBox(height: 12),
              _SettingRow(
                icon: Icons.notifications_none,
                label: 'Reminders',
                detail: 'When we nudge you about what needs using',
                onTap: onReminders,
              ),
              const SizedBox(height: 10),
              _SettingRow(
                icon: Icons.person_outline,
                label: isGuest ? 'Sign in' : 'Account',
                detail: isGuest
                    ? 'Keep your kitchen across devices'
                    // No password to mention: Google is the only way in.
                    : 'Your account and your data',
                onTap: isGuest ? onSignIn : onAccount,
              ),
              const SizedBox(height: 10),
              _SettingRow(
                icon: Icons.info_outline,
                label: 'About ShelfLife',
                detail: 'Version, licences, how the estimates work',
                onTap: onAbout,
              ),
              if (!isGuest) ...[
                const SizedBox(height: 24),
                AppButton.secondary(label: 'Sign out', onPressed: onSignOut),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _ImpactSummary extends StatelessWidget {
  const _ImpactSummary({required this.stats, this.onTap});

  final KitchenStats stats;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        radius: 26,
        colour: T.tintMint,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('What you have rescued',
                      style: T.cardSemiBold15
                          .copyWith(color: T.accentPrimary)),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: T.accentPrimary),
              ],
            ),
            const SizedBox(height: 14),
            // HUG columns with space-between, not three equal FILL columns:
            // the v1 Figma build clipped "₹1,240" that way.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stat(value: '${stats.mealsRescued}', label: 'meals'),
                // "est. saved", not "about". The qualifier belongs in the
                // label; on its own under a number it reads as a stray word,
                // and the figure has to be marked an estimate wherever it
                // appears because it comes from seeded market rates.
                _Stat(
                    value: '₹${_money(stats.valueRescuedInr)}',
                    label: 'est. saved'),
                _Stat(value: '${stats.currentStreak}', label: 'day streak'),
              ],
            ),
          ],
        ),
      );

  static String _money(double v) {
    final s = v.round().toString();
    // Indian grouping: last three, then pairs. 1240 -> 1,240; 123456 -> 1,23,456
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    return '${groups.join(',')},$last3';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: T.numeralBold34.copyWith(color: T.accentPrimary)),
          Text(label,
              style: T.chipSemiBold11.copyWith(color: T.accentPrimary)),
        ],
      );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        radius: 20,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: T.cardSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: T.accentPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: T.cardSemiBold15),
                  const SizedBox(height: 2),
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.chipSemiBold11
                          .copyWith(color: T.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: T.textSecondary),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 43

class ImpactScreen extends StatelessWidget {
  const ImpactScreen({
    super.key,
    required this.stats,
    required this.monthLabel,
    this.recentRescues = const [],
    this.onBack,
  });

  final KitchenStats stats;
  final String monthLabel;

  /// A few named things, because "18 meals" is abstract and "your spinach, on
  /// Tuesday" is not.
  final List<({String name, String when, String? glyphKey})> recentRescues;

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack),
              const SizedBox(height: 12),
              ScreenTitle(
                ['What you have', 'rescued'],
                subtitle: monthLabel,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _BigStat(
                      value: '${stats.mealsRescued}',
                      label: 'meals rescued',
                      colour: T.tintMint,
                      fg: T.accentPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BigStat(
                      value: '${stats.currentStreak}',
                      label: 'days in a row',
                      colour: T.tintPeach,
                      fg: T.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                radius: 24,
                colour: T.tintLemon,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('₹${_ImpactSummary._money(stats.valueRescuedInr)}',
                        style: T.numeralBold34),
                    const SizedBox(height: 2),
                    // Always labelled an estimate. It is derived from seeded
                    // market rates, and presenting it as measured would be a
                    // straightforward misrepresentation.
                    Text(
                      'roughly what you did not throw away — an estimate from '
                      'typical prices, not your receipts',
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary),
                    ),
                  ],
                ),
              ),
              if (stats.pctUsedInTime != null) ...[
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Used in time',
                                style: T.cardSemiBold15),
                          ),
                          Text('${stats.pctUsedInTime}%',
                              style: T.titleSemiBold18
                                  .copyWith(color: T.accentPrimary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: stats.pctUsedInTime! / 100,
                          minHeight: 8,
                          backgroundColor: T.cardSoft,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              T.accentPrimary),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Of everything that left your kitchen, this much got '
                        'eaten while it was still good.',
                        style: T.secondaryRegular13
                            .copyWith(color: T.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
              if (recentRescues.isNotEmpty) ...[
                const SizedBox(height: 24),
                const SectionHeader('Recently rescued'),
                const SizedBox(height: 12),
                AppCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      for (final r in recentRescues)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              if (r.glyphKey != null) ...[
                                ProduceImage(glyphKey: r.glyphKey!, size: 32),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                  child: Text(r.name,
                                      style: T.bodyRegular14)),
                              Text(r.when,
                                  style: T.chipSemiBold11
                                      .copyWith(color: T.textSecondary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.value,
    required this.label,
    required this.colour,
    required this.fg,
  });

  final String value;
  final String label;
  final Color colour;
  final Color fg;

  @override
  Widget build(BuildContext context) => AppCard(
        radius: 24,
        colour: colour,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: T.numeralBold34.copyWith(color: fg)),
            const SizedBox(height: 2),
            Text(label,
                style: T.secondaryRegular13.copyWith(color: fg)),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 44

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.enabled,
    required this.threeDay,
    required this.oneDay,
    required this.sameDay,
    required this.quietHours,
    this.permissionGranted = true,
    this.onBack,
    this.onChanged,
    this.onRequestPermission,
  });

  final bool enabled;
  final bool threeDay;
  final bool oneDay;
  final bool sameDay;

  /// Rendered window, e.g. "9 pm to 8 am".
  final String quietHours;

  final bool permissionGranted;
  final VoidCallback? onBack;
  final void Function(String key, bool value)? onChanged;
  final VoidCallback? onRequestPermission;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: widget.onBack, title: 'Reminders'),
              const SizedBox(height: 18),
              if (!widget.permissionGranted) ...[
                AppCard(
                  colour: T.stateAmberBg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notifications are switched off',
                          style: T.cardSemiBold15
                              .copyWith(color: T.stateAmberText)),
                      const SizedBox(height: 6),
                      Text(
                        'ShelfLife cannot nudge you without permission from '
                        'the phone. Everything else keeps working.',
                        style: T.secondaryRegular13
                            .copyWith(color: T.stateAmberText),
                      ),
                      const SizedBox(height: 14),
                      AppButton(
                        label: 'Turn them on',
                        expand: false,
                        onPressed: widget.onRequestPermission,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              AppCard(
                child: Column(
                  children: [
                    _Toggle(
                      label: 'Remind me at all',
                      detail: 'One switch for everything below.',
                      value: widget.enabled,
                      onChanged: (v) =>
                          widget.onChanged?.call('enabled', v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('When to nudge me',
                  style: T.labelMedium12.copyWith(color: T.textSecondary)),
              const SizedBox(height: 10),
              AppCard(
                child: Column(
                  children: [
                    _Toggle(
                      label: 'Three days ahead',
                      detail: 'Enough notice to plan a meal around it.',
                      value: widget.threeDay,
                      enabled: widget.enabled,
                      onChanged: (v) =>
                          widget.onChanged?.call('threeDay', v),
                    ),
                    const _Divider(),
                    _Toggle(
                      label: 'The day before',
                      detail: 'A last chance to use it at its best.',
                      value: widget.oneDay,
                      enabled: widget.enabled,
                      onChanged: (v) => widget.onChanged?.call('oneDay', v),
                    ),
                    const _Divider(),
                    _Toggle(
                      label: 'On the day',
                      detail: 'Best used today.',
                      value: widget.sameDay,
                      enabled: widget.enabled,
                      onChanged: (v) => widget.onChanged?.call('sameDay', v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quiet hours', style: T.cardSemiBold15),
                          const SizedBox(height: 2),
                          Text('No nudges while you are asleep.',
                              style: T.secondaryRegular13
                                  .copyWith(color: T.textSecondary)),
                        ],
                      ),
                    ),
                    Pill(widget.quietHours, icon: Icons.bedtime_outlined),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const InfoStrip(
                'You get at most one nudge per item per stage, so a slow week '
                'does not turn into a stream of reminders.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        thickness: 1,
        color: T.structureDivider,
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: enabled
                        ? T.cardSemiBold15
                        : T.cardSemiBold15.copyWith(color: T.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary)),
                ],
              ),
            ),
            Switch.adaptive(
              value: value && enabled,
              onChanged: enabled ? onChanged : null,
              activeTrackColor: T.accentPrimary,
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 45

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.email,
    required this.memberSince,
    this.onBack,
    this.onChangePassword,
    this.onExportData,
    this.onDeleteAccount,
  });

  final String email;
  final String memberSince;
  final VoidCallback? onBack;
  final VoidCallback? onChangePassword;
  final VoidCallback? onExportData;
  final VoidCallback? onDeleteAccount;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack, title: 'Account'),
              const SizedBox(height: 18),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Field(label: 'Email', value: email),
                    const _Divider(),
                    _Field(label: 'With us since', value: memberSince),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SettingRow(
                icon: Icons.lock_outline,
                label: 'Change your password',
                detail: 'We will email you a link',
                onTap: onChangePassword,
              ),
              const SizedBox(height: 10),
              _SettingRow(
                icon: Icons.download_outlined,
                label: 'Export your kitchen',
                detail: 'Everything you have added, as a file',
                onTap: onExportData,
              ),
              const SizedBox(height: 26),
              const InfoStrip(
                'Your kitchen is only ever visible to you — every row is '
                'scoped to your account at the database level.',
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Close my account',
                danger: true,
                onPressed: onDeleteAccount,
              ),
              const SizedBox(height: 8),
              Text(
                'This takes everything with it and cannot be undone.',
                style: T.chipSemiBold11.copyWith(color: T.textSecondary),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      T.secondaryRegular13.copyWith(color: T.textSecondary)),
            ),
            Text(value, style: T.cardSemiBold15),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 46

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.version,
    this.onBack,
    this.onLicences,
  });

  final String version;
  final VoidCallback? onBack;
  final VoidCallback? onLicences;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack, title: 'About'),
              const SizedBox(height: 22),
              Center(
                child: ArtHalo(
                  size: 170,
                  child: ProduceImage(glyphKey: 'broccoli', size: 118),
                ),
              ),
              const SizedBox(height: 20),
              const ScreenTitle(['ShelfLife']),
              const SizedBox(height: 4),
              Text('Version $version',
                  style:
                      T.secondaryRegular13.copyWith(color: T.textSecondary)),
              const SizedBox(height: 24),
              const SectionHeader('How the dates work'),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in const [
                      'A date you set yourself always wins.',
                      'Otherwise we use the date printed on the pack.',
                      'Otherwise we estimate from the item and where you keep '
                          'it.',
                      'Failing all that, we fall back to what is typical for '
                          'that kind of food.',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.arrow_right,
                                size: 20, color: T.accentPrimary),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(line, style: T.bodyRegular14)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Every date in the app carries its reason, so you can '
                      'always see which of these applied.',
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SettingRow(
                icon: Icons.description_outlined,
                label: 'Open source licences',
                detail: 'The libraries this app is built on',
                onTap: onLicences,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------------ 47

class SignOutSheet extends StatelessWidget {
  const SignOutSheet({
    super.key,
    required this.pendingCount,
    this.onSignOut,
    this.onCancel,
  });

  /// Unsynced changes. Signing out with a non-empty outbox loses them, so the
  /// sheet says the number rather than a vague caution.
  final int pendingCount;

  final VoidCallback? onSignOut;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: T.cardBase,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: T.structureBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text('Sign out?', style: T.titleSemiBold18),
            const SizedBox(height: 10),
            Text(
              pendingCount == 0
                  ? 'Everything is saved. Your kitchen will be here when you '
                      'sign back in.'
                  : '$pendingCount ${pendingCount == 1 ? 'change has' : 'changes have'} '
                      'not reached the server yet. Signing out now loses '
                      '${pendingCount == 1 ? 'it' : 'them'}.',
              style: T.bodyRegular14.copyWith(color: T.textSecondary),
            ),
            const SizedBox(height: 22),
            if (pendingCount == 0)
              AppButton(label: 'Sign out', onPressed: onSignOut)
            else
              AppButton(
                label: 'Sign out anyway',
                danger: true,
                onPressed: onSignOut,
              ),
            const SizedBox(height: 12),
            AppButton.secondary(label: 'Stay signed in', onPressed: onCancel),
          ],
        ),
      );
}

// ------------------------------------------------------------------ shared

enum SyncState { synced, pending, offline, syncing }

/// Sync status as a quiet strip, never a blocking spinner (Principle 6). The
/// app is usable offline, so this reports rather than interrupts.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.state, this.pending = 0});

  final SyncState state;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final (icon, text, fg, bg) = switch (state) {
      SyncState.synced => (
          Icons.cloud_done_outlined,
          'Everything is saved',
          T.accentPrimary,
          T.tintMint,
        ),
      SyncState.syncing => (
          Icons.cloud_sync_outlined,
          'Catching up…',
          T.infoText,
          T.infoBg,
        ),
      SyncState.pending => (
          Icons.cloud_upload_outlined,
          '$pending ${pending == 1 ? 'change' : 'changes'} waiting to save',
          T.infoText,
          T.infoBg,
        ),
      SyncState.offline => (
          Icons.cloud_off_outlined,
          pending == 0
              ? 'Offline — everything still works'
              : 'Offline — $pending ${pending == 1 ? 'change' : 'changes'} '
                  'will save when you are back',
          T.stateAmberText,
          T.stateAmberBg,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: T.labelMedium12.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}
