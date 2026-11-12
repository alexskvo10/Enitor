/// Разбор CSV по RFC 4180: разделитель — запятая, поля в кавычках, "" внутри
/// кавычек, переводы строк внутри кавычек, CRLF и LF. BOM в начале срезается,
/// пустые строки пропускаются. Незакрытая кавычка не даёт исключения: поле
/// читается до конца текста.
List<List<String>> parseCsv(String text) {
  final src = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endRow() {
    row.add(field.toString());
    field.clear();
    if (row.length > 1 || row[0].isNotEmpty) {
      rows.add(row);
    }
    row = <String>[];
  }

  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (inQuotes) {
      if (c != '"') {
        field.write(c);
      } else if (i + 1 < src.length && src[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        inQuotes = false;
      }
    } else if (c == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < src.length && src[i + 1] == '\n') {
        i++;
      }
      endRow();
    } else {
      field.write(c);
    }
  }
  if (row.isNotEmpty || field.isNotEmpty) {
    endRow();
  }
  return rows;
}
