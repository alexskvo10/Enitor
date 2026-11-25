// Вызывать только под `kIsWeb`: в нативных сборках — заглушки.
export 'web_bits_stub.dart' if (dart.library.js_interop) 'web_bits_web.dart';
