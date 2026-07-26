import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/achievement.dart';
import '../../data/repositories/achievements_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';

String _categoryLabel(AppLocalizations l10n, AchievementCategory c) =>
    switch (c) {
      AchievementCategory.volume => l10n.categoryVolume,
      AchievementCategory.streak => l10n.categoryStreak,
      AchievementCategory.quality => l10n.categoryQuality,
      AchievementCategory.milestone => l10n.categoryMilestone,
    };

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final all = ref.watch(achievementsProvider);

    final unlockedCount = all.where((a) => a.unlocked).length;
    final total = all.length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.achievementsTitle)),
      body: all.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Сводка прогресса
                _SummaryCard(unlocked: unlockedCount, total: total),
                const SizedBox(height: 8),
                for (final cat in AchievementCategory.values) ...[
                  _SectionHeader(
                    title: _categoryLabel(l10n, cat),
                    unlocked:
                        all.where((a) => a.def.category == cat && a.unlocked).length,
                    total: all.where((a) => a.def.category == cat).length,
                  ),
                  for (final a in all.where((a) => a.def.category == cat))
                    _AchievementTile(item: a),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.unlocked, required this.total});
  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total == 0 ? 0.0 : unlocked / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🏅', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Text(
                  context.l10n.achievementsUnlockedCount(unlocked, total),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.unlocked,
    required this.total,
  });
  final String title;
  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          Text(
            '$unlocked/$total',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.item});
  final EvaluatedAchievement item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = item.def;
    final unlocked = item.unlocked;
    // Скрытая (топовая) ачивка, ещё не полученная — прячем детали.
    final hidden = def.secret && !unlocked;

    final l10n = context.l10n;
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    final emoji = hidden ? '❓' : def.emoji;
    final title =
        hidden ? l10n.hiddenAchievementTitle : def.localizedTitle(ru);
    final description = hidden
        ? l10n.hiddenAchievementDescription
        : def.localizedDescription(ru);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: unlocked
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Эмодзи (приглушено, если не получено)
            Opacity(
              opacity: unlocked ? 1.0 : 0.4,
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: unlocked
                          ? null
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  // Прогресс — только для НЕскрытых и ещё не полученных.
                  if (!unlocked && !hidden) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: item.fraction,
                              minHeight: 6,
                              backgroundColor: theme
                                  .colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.displayProgress}/${def.target}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (unlocked)
              Icon(Icons.check_circle,
                  color: theme.colorScheme.primary, size: 24)
            else if (hidden)
              Icon(Icons.lock_outline,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  size: 20),
          ],
        ),
      ),
    );
  }
}
