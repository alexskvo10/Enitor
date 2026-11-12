import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/features/integrations/import/csv.dart';

void main() {
  test('простые поля через запятую', () {
    expect(parseCsv('a,b,c\n1,2,3'), [
      ['a', 'b', 'c'],
      ['1', '2', '3'],
    ]);
  });

  test('поле в кавычках с запятой внутри', () {
    expect(parseCsv('"x, y",z'), [
      ['x, y', 'z'],
    ]);
  });

  test('"" внутри кавычек превращается в одну кавычку', () {
    expect(parseCsv('"say ""hi""",2'), [
      ['say "hi"', '2'],
    ]);
  });

  test('перевод строки внутри кавычек сохраняется', () {
    expect(parseCsv('"line1\nline2",x\ny,z'), [
      ['line1\nline2', 'x'],
      ['y', 'z'],
    ]);
  });

  test('CRLF разделяет строки так же, как LF', () {
    expect(parseCsv('a,b\r\nc,d\r\n'), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });

  test('CRLF внутри кавычек остаётся как есть', () {
    expect(parseCsv('"a\r\nb",c'), [
      ['a\r\nb', 'c'],
    ]);
  });

  test('BOM в начале срезается', () {
    expect(parseCsv('﻿TYPE,CONTENT\ntask,x'), [
      ['TYPE', 'CONTENT'],
      ['task', 'x'],
    ]);
  });

  test('пустые строки пропускаются', () {
    expect(parseCsv('a,b\n\n\nc,d\n'), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });

  test('пустые поля сохраняются по позиции', () {
    expect(parseCsv(',,\na,,c'), [
      ['', '', ''],
      ['a', '', 'c'],
    ]);
  });

  test('пустой текст даёт пустой результат', () {
    expect(parseCsv(''), isEmpty);
    expect(parseCsv('﻿'), isEmpty);
  });

  test('незакрытая кавычка не бросает исключение', () {
    expect(parseCsv('a,"незакрыто\nb,c'), [
      ['a', 'незакрыто\nb,c'],
    ]);
  });

  test('кавычка внутри невыделенного поля — обычный символ', () {
    expect(parseCsv('ab"c,d'), [
      ['ab"c', 'd'],
    ]);
  });

  test('точка с запятой не разделитель', () {
    expect(parseCsv('a;b,c'), [
      ['a;b', 'c'],
    ]);
  });
}
