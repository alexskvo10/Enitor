import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_matrix.dart';

// Самопроверка помощника UI-матрицы. Каждый тест подсовывает виджет с известной
// поломкой и требует, чтобы помощник её нашёл. Если помощник перестанет
// ловить проблемы, сломается именно этот файл, а не чей-то экран.

void main() {
  testWidgets('нормальный виджет проходит все проверки', (tester) async {
    final violations = await collectUiMatrixViolations(
      tester,
      () => Column(
        children: [
          const Text('Заголовок'),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    expect(violations, isEmpty);
  });

  testWidgets('переполнение Row ловится как нарушение', (tester) async {
    final violations = await collectUiMatrixViolations(
      tester,
      () => const Row(
        children: [
          SizedBox(width: 600, height: 20),
          SizedBox(width: 600, height: 20),
        ],
      ),
    );

    expect(violations, isNotEmpty);
  });

  testWidgets('кнопка 20×20 ловится как мелкая цель касания', (tester) async {
    final violations = await collectUiMatrixViolations(
      tester,
      () => Semantics(
        button: true,
        label: 'x',
        child: InkWell(
          onTap: () {},
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    );

    expect(violations, isNotEmpty);
    expect(
      violations.any((v) => v.contains('цель касания')),
      isTrue,
      reason: 'Нарушение должно быть про цель касания: $violations',
    );
  });

  testWidgets('текст с многоточием ловится, пока не разрешён', (tester) async {
    Widget build() => const SizedBox(
          width: 50,
          child: Text(
            'очень длинный текст',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );

    final violations = await collectUiMatrixViolations(tester, build);
    expect(violations, isNotEmpty);
    expect(
      violations.any((v) => v.contains('многоточием')),
      isTrue,
      reason: 'Нарушение должно быть про многоточие: $violations',
    );

    final allowed = await collectUiMatrixViolations(
      tester,
      build,
      allowedEllipsis: {'очень длинный текст'},
    );
    expect(allowed.where((v) => v.contains('многоточием')), isEmpty);
  });

  testWidgets('широкое содержимое ловится при checkPageWidth', (tester) async {
    final violations = await collectUiMatrixViolations(
      tester,
      () => const SizedBox(width: 800, height: 100),
      checkPageWidth: true,
    );

    expect(violations, isNotEmpty);
    expect(
      violations.every((v) => v.contains('ширина содержимого')),
      isTrue,
      reason: 'Нарушение должно быть про ширину: $violations',
    );
  });
}
