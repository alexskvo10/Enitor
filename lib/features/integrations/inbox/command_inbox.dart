import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../core/integration_command.dart';

/// Что ждёт показа пользователю: анкета «Добавить?», переход на экран или
/// тост «ссылка не распознана».
sealed class InboxItem {
  const InboxItem();
}

class InboxCommand extends InboxItem {
  const InboxCommand(this.command);
  final IntegrationCommand command;
}

class InboxError extends InboxItem {
  const InboxError(this.error, this.source);
  final CommandError error;
  final CommandSource source;
}

/// Очередь недоверенных входов (ссылки, «Поделиться»). Анкеты открываются по
/// одной: если пока открыта анкета, пришло ещё три ссылки — они ждут, а
/// несохранённое в открытой не теряется.
class CommandInbox extends Notifier<List<InboxItem>> {
  @override
  List<InboxItem> build() => const [];

  void push(InboxItem item) => state = [...state, item];

  /// Снимает первый элемент — его уже показали.
  InboxItem? pop() {
    if (state.isEmpty) return null;
    final first = state.first;
    state = state.sublist(1);
    return first;
  }
}

final commandInboxProvider =
    NotifierProvider<CommandInbox, List<InboxItem>>(CommandInbox.new);

/// Текст из «Поделиться» → команда добавления. Первая строка — название,
/// остальное (и ссылка в тексте) — описание. Слишком длинная первая строка
/// режется по [kMaxTitle], хвост уходит в начало описания — ничего не
/// теряется, а пользователь всё видит в анкете до сохранения.
ParseResult parseSharedText(String? text, {required DateTime now}) {
  final t = (text ?? '').replaceAll('\r\n', '\n').trim();
  if (t.isEmpty) {
    return (
      command: null,
      error: const CommandError(
        CommandErrorCode.invalidArgs,
        field: 'text',
        problem: FieldProblem.missing,
      ),
    );
  }
  final nl = t.indexOf('\n');
  var title = (nl == -1 ? t : t.substring(0, nl)).trim();
  var rest = nl == -1 ? '' : t.substring(nl + 1).trim();
  final titleRunes = title.runes.toList();
  if (titleRunes.length > kMaxTitle) {
    final tail = String.fromCharCodes(titleRunes.sublist(kMaxTitle)).trim();
    title = String.fromCharCodes(titleRunes.sublist(0, kMaxTitle)).trim();
    rest = rest.isEmpty ? tail : '$tail\n$rest';
  }
  final restRunes = rest.runes.toList();
  final warnings = <String>[];
  if (restRunes.length > kMaxLongText) {
    rest = String.fromCharCodes(restRunes.sublist(0, kMaxLongText));
    warnings.add('description');
  }
  return (
    command: AddTask(
      source: CommandSource.share,
      title: title,
      description: rest.isEmpty ? null : rest,
      date: effectiveDay(now),
      warnings: warnings,
    ),
    error: null,
  );
}
