import 'dart:convert';

/// Максимальный размер тела кадра-запроса (как в command_pipe.cpp).
const int kMaxFrameBytes = 64 * 1024;

/// Ответ бывает больше запроса (list_today с длинными описаниями): Enitor
/// пишет его целиком, ограничение здесь — только от мусора в канале.
const int kMaxReplyBytes = 16 * 1024 * 1024;

/// Кадр: 4 байта длины little-endian + UTF-8 JSON.
List<int> encodeFrame(String json) {
  final body = utf8.encode(json);
  if (body.isEmpty || body.length > kMaxFrameBytes) {
    throw ArgumentError('Frame must be 1..$kMaxFrameBytes bytes, got ${body.length}');
  }
  final len = body.length;
  return [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF, (len >> 24) & 0xFF, ...body];
}

/// Разбирает первый кадр из [bytes]. Лишние байты после кадра не трогаем.
({String? json, String? error}) decodeFrame(
  List<int> bytes, {
  int maxBytes = kMaxFrameBytes,
}) {
  if (bytes.length < 4) {
    return (json: null, error: 'truncated header');
  }
  final len = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  if (len == 0) {
    return (json: null, error: 'empty frame');
  }
  if (len > maxBytes) {
    return (json: null, error: 'frame too large: $len bytes');
  }
  if (bytes.length - 4 < len) {
    return (json: null, error: 'truncated body');
  }
  try {
    final json = utf8.decode(bytes.sublist(4, 4 + len));
    return (json: json, error: null);
  } on FormatException {
    return (json: null, error: 'body is not UTF-8');
  }
}
