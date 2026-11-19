import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/goal.dart';
import '../../data/models/task.dart';
import '../../l10n/app_localizations.dart';

/// Поиск по задачам (название, описание, теги). Возвращает дату задачи, по
/// которой тапнули — экран «Задачи» переключается на этот день.
class GlobalSearchDelegate extends SearchDelegate<DateTime?> {
  GlobalSearchDelegate({required this.tasks, required String searchFieldLabel})
      : super(searchFieldLabel: searchFieldLabel);

  final List<Task> tasks;

  static const _maxResults = 50;

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  bool _matches(Task t, String q) =>
      searchNorm(t.title).contains(q) ||
      searchNorm(t.description ?? '').contains(q) ||
      t.tags.any((tag) => searchNorm(tag).contains(q));

  /// Подзаголовок результата: дата · время · теги (время локализовано).
  String _subtitle(Task t, DateFormat df, AppLocalizations l10n) {
    final time =
        t.timeLabelWith(fromWord: l10n.timeFromWord, toWord: l10n.timeToWord);
    return [
      df.format(t.date),
      if (time != null) time,
      if (t.tags.isNotEmpty) t.tags.map((x) => '#$x').join(' '),
    ].join(' · ');
  }

  Widget _buildList(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = searchNorm(query.trim());
    if (q.isEmpty) {
      return Center(
        child: NotebookEmptyState(
          icon: Icons.search_outlined,
          text: l10n.searchTasksEmptyHint,
        ),
      );
    }

    // Свежие даты первыми.
    final found = tasks.where((t) => _matches(t, q)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (found.isEmpty) {
      return Center(
        child: NotebookEmptyState(
          icon: Icons.search_off_outlined,
          text: l10n.searchNothingFound,
        ),
      );
    }

    final df =
        DateFormat('d MMMM y', Localizations.localeOf(context).languageCode);
    return ListView(
      children: [
        for (final t in found.take(_maxResults))
          ListTile(
            leading: Icon(
              t.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: t.isCompleted ? AppColors.success : null,
            ),
            title: Text(t.title),
            subtitle: Text(_subtitle(t, df, l10n)),
            onTap: () => close(context, dateOnly(t.date)),
          ),
        if (found.length > _maxResults)
          _MoreHint(shown: _maxResults, total: found.length),
      ],
    );
  }
}

/// Поиск по целям (название, описание). Возвращает выбранную цель — экран
/// «Цели» переключается на её период.
class GoalSearchDelegate extends SearchDelegate<Goal?> {
  GoalSearchDelegate({required this.goals, required String searchFieldLabel})
      : super(searchFieldLabel: searchFieldLabel);

  final List<Goal> goals;

  static const _maxResults = 50;

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  bool _matches(Goal g, String q) =>
      searchNorm(g.title).contains(q) ||
      searchNorm(g.description ?? '').contains(q) ||
      g.tags.any((tag) => searchNorm(tag).contains(q));

  Widget _buildList(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = searchNorm(query.trim());
    if (q.isEmpty) {
      return Center(
        child: NotebookEmptyState(
          icon: Icons.search_outlined,
          text: l10n.searchGoalsEmptyHint,
        ),
      );
    }

    // Свежие периоды первыми, как у задач.
    final found = goals.where((g) => _matches(g, q)).toList()
      ..sort((a, b) => b.ref.start.compareTo(a.ref.start));
    if (found.isEmpty) {
      return Center(
        child: NotebookEmptyState(
          icon: Icons.search_off_outlined,
          text: l10n.searchNothingFound,
        ),
      );
    }

    return ListView(
      children: [
        for (final g in found.take(_maxResults))
          ListTile(
            leading: Icon(
              g.completed ? Icons.flag : Icons.flag_outlined,
              color: g.completed ? AppColors.success : null,
            ),
            title: Text(g.title),
            subtitle: Text(g.ref.labelFor(
                Localizations.localeOf(context).languageCode == 'ru')),
            onTap: () => close(context, g),
          ),
        if (found.length > _maxResults)
          _MoreHint(shown: _maxResults, total: found.length),
      ],
    );
  }
}

/// Под списком, когда найдено больше, чем показано.
class _MoreHint extends StatelessWidget {
  const _MoreHint({required this.shown, required this.total});

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Text(
          AppLocalizations.of(context).searchTooMany(shown, total),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}
