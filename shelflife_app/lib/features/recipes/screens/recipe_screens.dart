// Screens 33–38 — recipes.
//
// 33 List · 34 Detail · 35 Method · 36 Cooked it · 37 Empty · 38 Missing
// ingredients.
//
// The hard constraint from spec §5.2, repeated here because it is the thing
// most likely to be broken by a well-meaning edit: the match score is never
// rendered. What the user sees is "6 of 7 ingredients" and the names of the
// items that are pressing. A percentage invites arguing with the algorithm;
// a list of ingredients invites cooking.

import 'package:flutter/material.dart';

import '../../../core/engines/recipe_scorer.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/produce_image.dart';

// ------------------------------------------------------------------ 33

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({
    super.key,
    required this.matches,
    this.filter = RecipeFilter.useSoonest,
    this.onFilterChanged,
    this.onTabChanged,
    this.onRecipeTap,
    this.onAddItems,
  });

  final List<RecipeMatch> matches;
  final RecipeFilter filter;
  final ValueChanged<RecipeFilter>? onFilterChanged;
  final ValueChanged<NavTab>? onTabChanged;
  final ValueChanged<RecipeMatch>? onRecipeTap;
  final VoidCallback? onAddItems;

  List<RecipeMatch> get _visible => switch (filter) {
        RecipeFilter.useSoonest =>
          matches.where((m) => m.urgentNames.isNotEmpty).toList(),
        RecipeFilter.canCookNow =>
          matches.where((m) => m.missingNames.isEmpty).toList(),
        RecipeFilter.quick =>
          matches.where((m) => m.prepMinutes <= 20).toList(),
        RecipeFilter.everything => matches,
      };

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return AppScreen(
      bottomBar: BottomNav(active: NavTab.recipes, onTap: onTabChanged),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Gutter(
            child: ScreenTitle(
              ['What you can', 'cook tonight'],
              subtitle: 'Ranked by what you already have and what needs using '
                  'first.',
            ),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Gutter.width),
            child: Row(
              children: [
                for (final f in RecipeFilter.values) ...[
                  if (f != RecipeFilter.values.first)
                    const SizedBox(width: 8),
                  FilterPill(
                    label: f.label,
                    selected: f == filter,
                    onTap: () => onFilterChanged?.call(f),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (visible.isEmpty)
            Gutter(child: _empty())
          else
            for (final match in visible) ...[
              Gutter(
                child: RecipeCard(
                  match: match,
                  onTap: () => onRecipeTap?.call(match),
                ),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 37

  Widget _empty() => EmptyState(
        title: switch (filter) {
          RecipeFilter.useSoonest => 'Nothing pressing',
          RecipeFilter.canCookNow => 'Nothing complete yet',
          RecipeFilter.quick => 'Nothing quick right now',
          RecipeFilter.everything => 'No recipes yet',
        },
        body: switch (filter) {
          RecipeFilter.useSoonest =>
            'Nothing in your kitchen is in a hurry. Have a look at everything '
                'instead.',
          RecipeFilter.canCookNow =>
            'Every recipe is missing something. Tap one to see what, and add '
                'it to your shopping list.',
          RecipeFilter.quick =>
            'Nothing under twenty minutes with what you have in. Worth a look '
                'at the rest.',
          RecipeFilter.everything =>
            'Add a few things to your kitchen and recipes will start showing '
                'up here.',
        },
        artwork: const DishImage(imageKey: 'vegetable-pulao', size: 108),
        action: filter == RecipeFilter.everything
            ? 'Add to my kitchen'
            : 'Show everything',
        onAction: filter == RecipeFilter.everything
            ? onAddItems
            : () => onFilterChanged?.call(RecipeFilter.everything),
      );
}

enum RecipeFilter { useSoonest, canCookNow, quick, everything }

extension RecipeFilterLabel on RecipeFilter {
  String get label => switch (this) {
        RecipeFilter.useSoonest => 'Use these first',
        RecipeFilter.canCookNow => 'Can cook now',
        RecipeFilter.quick => 'Under 20 min',
        RecipeFilter.everything => 'Everything',
      };
}

/// The recipe card. Shared by screens 10, 33 and 29.
class RecipeCard extends StatelessWidget {
  const RecipeCard({super.key, required this.match, this.onTap});

  final RecipeMatch match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        radius: 24,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: T.tintMint,
                borderRadius: BorderRadius.circular(22),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: DishImage(imageKey: match.imageKey, size: 76),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.name, style: T.cardSemiBold15),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // The count, never the score.
                      Pill(match.matchLabel,
                          fg: match.missingNames.isEmpty
                              ? T.accentPrimary
                              : T.textSecondary,
                          bg: match.missingNames.isEmpty
                              ? T.tintMint
                              : T.cardSoft),
                      const SizedBox(width: 8),
                      Pill('${match.prepMinutes} min',
                          icon: Icons.schedule),
                    ],
                  ),
                  if (match.urgencyLine != null) ...[
                    const SizedBox(height: 8),
                    Text(match.urgencyLine!,
                        style: T.chipSemiBold11
                            .copyWith(color: T.stateRedText)),
                  ] else if (match.missingNames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Needs ${_join(match.missingNames)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.chipSemiBold11
                          .copyWith(color: T.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  static String _join(List<String> names) => names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

// ------------------------------------------------------------------ 34, 38

class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({
    super.key,
    required this.match,
    required this.servings,
    required this.ingredients,
    this.onBack,
    this.onCook,
    this.onAddMissingToList,
    this.onSeeMethod,
    this.saved = false,
    this.onToggleSaved,
  });

  final RecipeMatch match;
  final int servings;

  /// Every ingredient with its state, so screen 38's "what am I missing" is the
  /// same screen rather than a separate one.
  final List<IngredientLine> ingredients;

  final VoidCallback? onBack;
  final VoidCallback? onCook;
  final VoidCallback? onAddMissingToList;
  final VoidCallback? onSeeMethod;
  final bool saved;
  final VoidCallback? onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final missing = ingredients.where((i) => !i.have && !i.optional).toList();
    return AppScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gutter(
            child: TopBar(
              onBack: onBack,
              trailingIcon: saved ? Icons.favorite : Icons.favorite_border,
              onTrailing: onToggleSaved,
            ),
          ),
          Center(
            child: ArtHalo(
              size: 250,
              child: DishImage(imageKey: match.imageKey, size: 186),
            ),
          ),
          const SizedBox(height: 8),
          Gutter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.name, style: T.displayBold26),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Pill('${match.prepMinutes} min', icon: Icons.schedule),
                    const SizedBox(width: 8),
                    Pill('$servings servings', icon: Icons.people_outline),
                    const SizedBox(width: 8),
                    Pill(match.matchLabel,
                        fg: missing.isEmpty ? T.accentPrimary : T.textSecondary,
                        bg: missing.isEmpty ? T.tintMint : T.cardSoft),
                  ],
                ),
                if (match.urgencyLine != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: T.stateRedBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.priority_high,
                            size: 19, color: T.stateRedText),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(match.urgencyLine!,
                              style: T.secondaryRegular13
                                  .copyWith(color: T.stateRedText)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                const SectionHeader('What goes in'),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      for (final ing in ingredients) _IngredientRow(row: ing),
                    ],
                  ),
                ),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  AppButton.secondary(
                    label: missing.length == 1
                        ? 'Add ${missing.single.name} to my list'
                        : 'Add ${missing.length} missing things to my list',
                    onPressed: onAddMissingToList,
                  ),
                ],
                const SizedBox(height: 24),
                AppButton(
                  label: missing.isEmpty
                      ? 'Cook this'
                      : 'Cook it anyway',
                  onPressed: onCook,
                ),
                const SizedBox(height: 12),
                AppButton.secondary(
                    label: 'See how to make it', onPressed: onSeeMethod),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One ingredient line, as the detail screen needs it.
///
/// Distinct from the persisted `RecipeIngredientRow`: `have` and `urgent` are
/// facts about *this user's kitchen right now*, produced by joining the recipe
/// against inventory. Putting them on the stored row would imply the recipe
/// knows something it cannot.
///
/// `have` drives everything visually: a tick and full contrast when it is in
/// the kitchen, a plain circle and secondary text when it is not.
class IngredientLine {
  const IngredientLine({
    required this.name,
    required this.amount,
    required this.have,
    this.optional = false,
    this.urgent = false,
    this.glyphKey,
  });

  final String name;
  final String amount;
  final bool have;
  final bool optional;

  /// In the kitchen and due today or overdue — the reason this recipe ranked.
  final bool urgent;

  final String? glyphKey;
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.row});

  final IngredientLine row;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(
              row.have ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: row.have ? T.accentPrimary : T.structureBorder,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    row.name,
                    style: row.have
                        ? T.bodyRegular14
                        : T.bodyRegular14.copyWith(color: T.textSecondary),
                  ),
                  if (row.optional) ...[
                    const SizedBox(width: 8),
                    Text('optional',
                        style: T.chipSemiBold11
                            .copyWith(color: T.textSecondary)),
                  ],
                  if (row.urgent) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: T.stateRedText, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
            ),
            Text(row.amount,
                style:
                    T.secondaryRegular13.copyWith(color: T.textSecondary)),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 35

class RecipeMethodScreen extends StatelessWidget {
  const RecipeMethodScreen({
    super.key,
    required this.name,
    required this.steps,
    required this.currentStep,
    this.onBack,
    this.onStepTap,
    this.onDone,
  });

  final String name;
  final List<String> steps;

  /// Which step the user is on. Progress is kept because a recipe read on a
  /// phone in a kitchen gets interrupted.
  final int currentStep;

  final VoidCallback? onBack;
  final ValueChanged<int>? onStepTap;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: onBack, title: 'How to make it'),
              const SizedBox(height: 14),
              Text(name, style: T.displayBold26),
              const SizedBox(height: 6),
              Text('Step ${currentStep + 1} of ${steps.length}',
                  style:
                      T.secondaryRegular13.copyWith(color: T.textSecondary)),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (currentStep + 1) / steps.length,
                  minHeight: 6,
                  backgroundColor: T.cardSoft,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(T.accentPrimary),
                ),
              ),
              const SizedBox(height: 22),
              for (var i = 0; i < steps.length; i++) ...[
                _Step(
                  index: i,
                  text: steps[i],
                  done: i < currentStep,
                  active: i == currentStep,
                  onTap: () => onStepTap?.call(i),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 16),
              AppButton(label: 'I have made it', onPressed: onDone),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.text,
    required this.done,
    required this.active,
    this.onTap,
  });

  final int index;
  final String text;
  final bool done;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        radius: 20,
        colour: active ? T.tintMint : null,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: done || active ? T.accentPrimary : T.cardSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: done
                  ? const Icon(Icons.check, size: 16, color: T.textOnAccent)
                  : Text(
                      '${index + 1}',
                      style: T.chipSemiBold11.copyWith(
                        color: active ? T.textOnAccent : T.textSecondary,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: done
                    ? T.bodyRegular14.copyWith(color: T.textSecondary)
                    : T.bodyRegular14,
              ),
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------------ 36

/// Cooked it. This is the screen that writes consumption events, so it is also
/// where the impact figures come from — which is why it asks which ingredients
/// were actually used rather than assuming all of them.
class CookedItScreen extends StatefulWidget {
  const CookedItScreen({
    super.key,
    required this.recipeName,
    required this.used,
    this.onBack,
    this.onConfirm,
  });

  final String recipeName;

  /// Candidate items, pre-ticked. The user unticks anything they did not use.
  final List<CookedItem> used;

  final VoidCallback? onBack;
  final void Function(Set<String> usedIds)? onConfirm;

  @override
  State<CookedItScreen> createState() => _CookedItScreenState();
}

class CookedItem {
  const CookedItem({
    required this.id,
    required this.name,
    required this.amount,
    this.glyphKey,
    this.urgent = false,
  });

  final String id;
  final String name;
  final String amount;
  final String? glyphKey;
  final bool urgent;
}

class _CookedItScreenState extends State<CookedItScreen> {
  late final Set<String> _ticked = widget.used.map((u) => u.id).toSet();

  @override
  Widget build(BuildContext context) => AppScreen(
        child: Gutter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(onBack: widget.onBack),
              const SizedBox(height: 14),
              ScreenTitle(
                ['You made', widget.recipeName],
                subtitle: 'Untick anything you did not actually use, and we '
                    'will take the rest off your list.',
              ),
              const SizedBox(height: 22),
              AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  children: [
                    for (final u in widget.used)
                      _TickRow(
                        item: u,
                        ticked: _ticked.contains(u.id),
                        onToggle: () => setState(() {
                          _ticked.contains(u.id)
                              ? _ticked.remove(u.id)
                              : _ticked.add(u.id);
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const InfoStrip(
                'This is what counts towards your rescued total, so it is worth '
                'getting roughly right.',
                icon: Icons.insights_outlined,
              ),
              const SizedBox(height: 26),
              AppButton(
                label: _ticked.isEmpty
                    ? 'Nothing used'
                    : 'That is ${_ticked.length} used',
                onPressed: () => widget.onConfirm?.call(_ticked),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
}

class _TickRow extends StatelessWidget {
  const _TickRow({
    required this.item,
    required this.ticked,
    required this.onToggle,
  });

  final CookedItem item;
  final bool ticked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                ticked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 22,
                color: ticked ? T.accentPrimary : T.structureBorder,
              ),
              const SizedBox(width: 12),
              if (item.glyphKey != null) ...[
                ProduceImage(glyphKey: item.glyphKey!, size: 32),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Row(
                  children: [
                    Text(item.name, style: T.bodyRegular14),
                    if (item.urgent) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: T.stateRedText, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ),
              Text(item.amount,
                  style:
                      T.secondaryRegular13.copyWith(color: T.textSecondary)),
            ],
          ),
        ),
      );
}
