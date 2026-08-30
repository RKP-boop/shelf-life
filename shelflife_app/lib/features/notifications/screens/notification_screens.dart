// Screens 48–52 — notifications and the cross-cutting states.
//
// 48 Permission request · 49 Today's reminders · 50 Offline · 51 Syncing ·
// 52 Something did not work.
//
// Flow 6 on the board had no screens at all in the source doc, despite expiry
// reminders being the entire point of the product (D15). These are those
// screens.
//
// Screen 52 is deliberately not called an error screen. PRD 4.10 forbids
// `Error`, `Failed` and `Warning`, and the substitution is not cosmetic: the
// screen has to say what happened, what still works, and what to do next.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../features/profile/screens/profile_screens.dart' show SyncState, SyncIndicator;
import '../../../models/enums.dart';

// ------------------------------------------------------------------ 48

/// Asked for at the moment it makes sense — after the first item is added, not
/// on launch. A permission prompt before the user has anything to be reminded
/// about is the classic way to get it denied for good.
class NotificationPermissionScreen extends StatelessWidget {
  const NotificationPermissionScreen({
    super.key,
    required this.firstItemName,
    required this.firstItemDays,
    this.onAllow,
    this.onNotNow,
    this.glyphKey,
  });

  final String firstItemName;
  final int firstItemDays;
  final VoidCallback? onAllow;
  final VoidCallback? onNotNow;
  final String? glyphKey;

  @override
  Widget build(BuildContext context) => AppScreen(
        scrollable: false,
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Spacer(),
              Center(
                child: ArtHalo(
                  size: 210,
                  child: ProduceImage(
                      glyphKey: glyphKey ?? 'lemon', size: 146),
                ),
              ),
              const Spacer(),
              const ScreenTitle(['Want a nudge', 'before it turns?']),
              const SizedBox(height: 12),
              Text(
                firstItemDays == 0
                    ? 'Your $firstItemName is best used today. We can tell you '
                        'about things like this before it is too late.'
                    : 'Your $firstItemName has about $firstItemDays '
                        '${firstItemDays == 1 ? 'day' : 'days'} left. We can '
                        'give you a heads-up before it turns.',
                style: T.bodyRegular14.copyWith(color: T.textSecondary),
              ),
              const SizedBox(height: 20),
              const InfoStrip(
                'Three days ahead, the day before, and on the day. At most one '
                'nudge per item per stage.',
                icon: Icons.notifications_none,
              ),
              const Spacer(flex: 2),
              AppButton(label: 'Yes, nudge me', onPressed: onAllow),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: onNotNow,
                  child: Text('Not now',
                      style: T.labelMedium12
                          .copyWith(color: T.textSecondary)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------------ 49

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.entries,
    this.onBack,
    this.onEntryTap,
    this.onSeeRecipes,
    this.onSettings,
  });

  final List<NotificationEntry> entries;
  final VoidCallback? onBack;
  final ValueChanged<NotificationEntry>? onEntryTap;
  final VoidCallback? onSeeRecipes;
  final VoidCallback? onSettings;

  List<NotificationEntry> get _today =>
      entries.where((e) => e.level == NotificationLevel.sameDay).toList();

  List<NotificationEntry> get _ahead =>
      entries.where((e) => e.level != NotificationLevel.sameDay).toList();

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final ahead = _ahead;

    return AppScreen(
      child: Gutter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(
              onBack: onBack,
              title: 'Reminders',
              trailingIcon: Icons.tune,
              onTrailing: onSettings,
            ),
            const SizedBox(height: 14),
            if (entries.isEmpty)
              _empty()
            else ...[
              if (today.isNotEmpty) ...[
                const ScreenTitle(['Today']),
                const SizedBox(height: 12),
                for (final e in today) ...[
                  _Entry(entry: e, onTap: () => onEntryTap?.call(e)),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                AppButton(
                  label: 'See what to cook with these',
                  onPressed: onSeeRecipes,
                ),
                const SizedBox(height: 24),
              ],
              if (ahead.isNotEmpty) ...[
                const SectionHeader('Coming up'),
                const SizedBox(height: 12),
                for (final e in ahead) ...[
                  _Entry(entry: e, onTap: () => onEntryTap?.call(e)),
                  const SizedBox(height: 10),
                ],
              ],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _empty() => EmptyState(
        title: 'Nothing to flag',
        body: 'Everything in your kitchen has time in hand. We will let you '
            'know when something needs using.',
        artwork: const ProduceImage(glyphKey: 'apple', size: 100),
      );
}

/// One reminder. Carries the level so the row styling and the copy both derive
/// from the same value the dedup ledger stores.
class NotificationEntry {
  const NotificationEntry({
    required this.id,
    required this.itemName,
    required this.level,
    required this.detail,
    this.glyphKey,
    this.category,
  });

  final String id;
  final String itemName;
  final NotificationLevel level;

  /// The plain-English line, e.g. "Best used today — you have 250 g".
  final String detail;

  final String? glyphKey;
  final FoodCategory? category;
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, this.onTap});

  final NotificationEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sameDay = entry.level == NotificationLevel.sameDay;
    return AppCard(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ProduceTile(
            glyphKey: entry.glyphKey ?? 'cat-pantry',
            category: entry.category,
            size: 50,
            radius: 16,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.itemName, style: T.cardSemiBold15),
                const SizedBox(height: 2),
                Text(
                  entry.detail,
                  style: T.secondaryRegular13.copyWith(
                    color: sameDay ? T.stateRedText : T.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: T.textSecondary),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 50, 51

/// Offline and syncing, as a full screen for the case where the user has opened
/// the sync detail deliberately. The inline [SyncIndicator] is what appears
/// during normal use — no screen ever blocks on the network.
class SyncStatusScreen extends StatelessWidget {
  const SyncStatusScreen({
    super.key,
    required this.state,
    required this.pendingCount,
    required this.lastSyncedLabel,
    this.oldestPendingLabel,
    this.exhaustedCount = 0,
    this.onBack,
    this.onRetryNow,
  });

  final SyncState state;
  final int pendingCount;

  /// Rendered, e.g. "12 minutes ago" or "not yet".
  final String lastSyncedLabel;

  final String? oldestPendingLabel;

  /// Items the queue gave up on after six attempts. Surfaced rather than left
  /// stuck invisibly in the outbox.
  final int exhaustedCount;

  final VoidCallback? onBack;
  final VoidCallback? onRetryNow;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack, title: 'Saving'),
              const SizedBox(height: 20),
              Center(
                child: ArtHalo(
                  size: 180,
                  colour: state == SyncState.offline
                      ? T.tintPeach
                      : T.tintMint,
                  child: Icon(
                    state == SyncState.offline
                        ? Icons.cloud_off_outlined
                        : state == SyncState.synced
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_sync_outlined,
                    size: 82,
                    color: state == SyncState.offline
                        ? T.stateAmberText
                        : T.accentPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ScreenTitle(
                switch (state) {
                  SyncState.offline => const ['You are offline'],
                  SyncState.synced => const ['Everything is', 'saved'],
                  SyncState.syncing => const ['Catching up'],
                  SyncState.pending => const ['Waiting to save'],
                },
                subtitle: switch (state) {
                  SyncState.offline =>
                    'The app works exactly the same offline. Anything you '
                        'change is queued and saved as soon as you are back.',
                  SyncState.synced =>
                    'Nothing is waiting. Your kitchen matches the server.',
                  SyncState.syncing =>
                    'Sending your changes now. You can carry on using the app.',
                  SyncState.pending =>
                    'Your changes are safe on this phone and will go up on the '
                        'next connection.',
                },
              ),
              const SizedBox(height: 22),
              SyncIndicator(state: state, pending: pendingCount),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(label: 'Last saved', value: lastSyncedLabel),
                    if (pendingCount > 0) ...[
                      const Divider(
                          height: 20,
                          thickness: 1,
                          color: T.structureDivider),
                      _Line(
                        label: 'Waiting',
                        value: '$pendingCount '
                            '${pendingCount == 1 ? 'change' : 'changes'}',
                      ),
                    ],
                    if (oldestPendingLabel != null) ...[
                      const Divider(
                          height: 20,
                          thickness: 1,
                          color: T.structureDivider),
                      _Line(label: 'Oldest', value: oldestPendingLabel!),
                    ],
                  ],
                ),
              ),
              if (exhaustedCount > 0) ...[
                const SizedBox(height: 16),
                AppCard(
                  colour: T.stateAmberBg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$exhaustedCount '
                        '${exhaustedCount == 1 ? 'change has' : 'changes have'} '
                        'stopped trying',
                        style: T.cardSemiBold15
                            .copyWith(color: T.stateAmberText),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'We tried six times and gave up so it would not retry '
                        'forever. They are still on this phone — tap below to '
                        'have another go.',
                        style: T.secondaryRegular13
                            .copyWith(color: T.stateAmberText),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (state != SyncState.synced)
                AppButton(label: 'Try now', onPressed: onRetryNow),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    T.secondaryRegular13.copyWith(color: T.textSecondary)),
          ),
          Text(value, style: T.cardSemiBold15),
        ],
      );
}

// ------------------------------------------------------------------ 52

/// Something did not work.
///
/// Three things, in this order: what happened in plain words, what still works,
/// and one clear way forward. "Error 500" satisfies none of those.
class SomethingWrongScreen extends StatelessWidget {
  const SomethingWrongScreen({
    super.key,
    required this.what,
    required this.stillWorks,
    this.detail,
    this.onRetry,
    this.onBack,
    this.retryLabel = 'Try again',
  });

  /// What happened, in the user's terms: "We could not reach the server."
  final String what;

  /// What is unaffected. Almost always a lot, since the app is offline-first.
  final String stillWorks;

  /// Technical detail, collapsed. Useful when the user is reporting it, and
  /// invisible when they are not.
  final String? detail;

  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack),
              const SizedBox(height: 30),
              Center(
                child: ArtHalo(
                  size: 180,
                  colour: T.tintPeach,
                  child: Icon(Icons.cloud_off_outlined,
                      size: 80, color: T.stateAmberText),
                ),
              ),
              const SizedBox(height: 28),
              const ScreenTitle(['That did not', 'go through']),
              const SizedBox(height: 12),
              Text(what, style: T.bodyRegular14),
              const SizedBox(height: 18),
              AppCard(
                colour: T.tintMint,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 19, color: T.accentPrimary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(stillWorks,
                          style: T.secondaryRegular13
                              .copyWith(color: T.accentPrimary)),
                    ),
                  ],
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 16),
                Theme(
                  data: ThemeData(
                    dividerColor: Colors.transparent,
                    splashColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text('Technical detail',
                        style: T.labelMedium12
                            .copyWith(color: T.textSecondary)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(detail!,
                            style: T.chipSemiBold11
                                .copyWith(color: T.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 26),
              AppButton(label: retryLabel, onPressed: onRetry),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}
