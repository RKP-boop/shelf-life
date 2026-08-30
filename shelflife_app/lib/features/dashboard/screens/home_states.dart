// Screens 09, 11, 12 — the other three home states.
//
// 09 Home empty (first run) · 11 Home in guest mode · 12 Search.
//
// 09 is the screen that decides whether the product gets used at all: an empty
// kitchen has nothing to show, so the screen has to be an invitation rather
// than a blank. It offers all three add paths, because the fastest one depends
// on what the user happens to have to hand.

import 'package:flutter/material.dart';

import '../../../core/engines/expiry_estimator.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/item_row.dart';
import '../../../core/widgets/produce_image.dart';
import '../../../models/inventory_item.dart';

// ------------------------------------------------------------------ 09

class HomeEmptyScreen extends StatelessWidget {
  const HomeEmptyScreen({
    super.key,
    required this.greeting,
    this.onTabChanged,
    this.onScanReceipt,
    this.onScanBarcode,
    this.onAddByHand,
  });

  /// Rendered greeting. Guest mode has no name, so this is "Welcome" rather
  /// than "Welcome, you".
  final String greeting;
  final ValueChanged<NavTab>? onTabChanged;
  final VoidCallback? onScanReceipt;
  final VoidCallback? onScanBarcode;
  final VoidCallback? onAddByHand;

  @override
  Widget build(BuildContext context) => AppScreen(
        bottomBar: BottomNav(active: NavTab.home, onTap: onTabChanged),
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(greeting, style: T.titleSemiBold18),
              const SizedBox(height: 24),
              const ScreenTitle(
                ['Nothing in your', 'kitchen yet'],
                subtitle: 'Add a few things and ShelfLife starts keeping track '
                    'of what needs using.',
              ),
              const SizedBox(height: 26),
              Center(
                child: ArtHalo(
                  size: 200,
                  child: ProduceImage(glyphKey: 'carrot', size: 140),
                ),
              ),
              const SizedBox(height: 26),
              // Three routes in, ranked by how much they save. The receipt path
              // is first because it adds a whole shop at once.
              _AddRoute(
                icon: Icons.receipt_long_outlined,
                title: 'Photograph a receipt',
                body: 'A whole shop in one go. Best value for the effort.',
                onTap: onScanReceipt,
                emphasised: true,
              ),
              const SizedBox(height: 12),
              _AddRoute(
                icon: Icons.qr_code_scanner,
                title: 'Scan a barcode',
                body: 'Good for packaged things with a printed date.',
                onTap: onScanBarcode,
              ),
              const SizedBox(height: 12),
              _AddRoute(
                icon: Icons.edit_outlined,
                title: 'Add by hand',
                body: 'Loose vegetables, or anything without a label.',
                onTap: onAddByHand,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
}

class _AddRoute extends StatelessWidget {
  const _AddRoute({
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        radius: 22,
        colour: emphasised ? T.tintMint : null,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: emphasised ? T.accentPrimary : T.cardSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  size: 22,
                  color: emphasised ? T.textOnAccent : T.accentPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: T.cardSemiBold15),
                  const SizedBox(height: 2),
                  Text(body,
                      style: T.secondaryRegular13
                          .copyWith(color: T.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: T.textSecondary),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 11

/// The guest banner, shown above any screen while there is no account.
///
/// Dismissible and stated as a fact rather than a warning: the app works fully
/// in guest mode, so a persistent nag would be dishonest about the trade-off
/// the user already accepted on screen 08.
class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key, this.onCreateAccount, this.onDismiss});

  final VoidCallback? onCreateAccount;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: T.infoBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.phone_iphone, size: 19, color: T.infoText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stored on this phone only',
                      style: T.labelMedium12.copyWith(color: T.infoText)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onCreateAccount,
                    child: Text(
                      'Create an account to keep it',
                      style: T.chipSemiBold11.copyWith(
                        color: T.infoText,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, color: T.infoText),
              ),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 12

class SearchScreen extends StatelessWidget {
  const SearchScreen({
    super.key,
    required this.query,
    required this.results,
    this.onBack,
    this.onQueryChanged,
    this.onItemTap,
    this.onAddByHand,
    this.recentSearches = const [],
    this.today,
  });

  final String query;
  final List<InventoryItem> results;
  final VoidCallback? onBack;
  final ValueChanged<String>? onQueryChanged;
  final ValueChanged<InventoryItem>? onItemTap;
  final VoidCallback? onAddByHand;
  final List<String> recentSearches;
  final DateTime? today;

  static const _estimator = ExpiryEstimator();

  @override
  Widget build(BuildContext context) {
    final now = today ?? DateTime.now();
    return AppScreen(
      child: Gutter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(onBack: onBack),
            const SizedBox(height: 10),
            SearchField(
              hint: 'Search your kitchen',
              autofocus: true,
              controller: TextEditingController(text: query),
              onChanged: onQueryChanged,
            ),
            const SizedBox(height: 20),
            if (query.isEmpty)
              _recent()
            else if (results.isEmpty)
              _noMatch()
            else ...[
              Text(
                '${results.length} ${results.length == 1 ? 'match' : 'matches'}',
                style: T.labelMedium12.copyWith(color: T.textSecondary),
              ),
              const SizedBox(height: 12),
              for (final item in results) ...[
                ItemRow(
                  item: item,
                  freshness: _estimator.freshness(item.expiryDate, today: now),
                  badgeLabel: _estimator.badgeLabel(
                      _estimator.freshness(item.expiryDate, today: now),
                      item.expiryDate,
                      today: now),
                  onTap: () => onItemTap?.call(item),
                ),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _recent() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recentSearches.isNotEmpty) ...[
            const SectionHeader('Recent'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final term in recentSearches)
                  Pill(term, icon: Icons.history),
              ],
            ),
          ] else
            const InfoStrip(
              'Search by name, or by what it is — "greens" finds spinach and '
              'coriander.',
              icon: Icons.search,
            ),
        ],
      );

  Widget _noMatch() => EmptyState(
        title: 'Nothing called "$query"',
        body: 'It might not be in your kitchen yet. Add it and ShelfLife will '
            'start tracking it.',
        artwork: const ProduceImage(glyphKey: 'cat-pantry', size: 96),
        action: 'Add it by hand',
        onAction: onAddByHand,
      );
}
