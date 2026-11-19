import 'package:enitor/core/utils/format_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compactCount округляет до следующей единицы', () {
    expect(compactCount(999), '999');
    expect(compactCount(1500), '1.5k');
    expect(compactCount(9999), '10k');
    expect(compactCount(999950), '1M');
    expect(compactCount(-2500000), '-2.5M');
    expect(compactCount(3000000000), '3B');
  });
}
