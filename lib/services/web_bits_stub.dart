// Нативные сборки: веб-функций нет (см. web_bits_web.dart).
void downloadText(String name, String text, String mime) =>
    throw UnsupportedError('web only');

Future<bool> anotherTabOpen() async => false;

void requestPersistentStorage() {}

bool get isInstalledApp => false;
