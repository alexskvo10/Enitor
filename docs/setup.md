# Установка окружения

## 1. Flutter SDK

1. Скачать ZIP-архив со стабильной версией: https://docs.flutter.dev/get-started/install/windows
2. Распаковать, например, в `C:\src\flutter` (важно: НЕ в `Program Files` — нужны права на запись)
3. Добавить `C:\src\flutter\bin` в переменную окружения `PATH`
4. Перезапустить PowerShell, проверить:
   ```powershell
   flutter --version
   ```

## 2. Зависимости

```powershell
flutter doctor
```

Команда покажет, чего не хватает. Скорее всего, понадобится:

### Android
- **Android Studio**: https://developer.android.com/studio
- В нём установить Android SDK + Platform Tools + эмулятор (через SDK Manager)
- Принять лицензии:
  ```powershell
  flutter doctor --android-licenses
  ```

### Windows (desktop)
- **Visual Studio 2022 Build Tools** с компонентом *Desktop development with C++*:
  https://visualstudio.microsoft.com/downloads/

## 3. Установка зависимостей проекта

Из корня репозитория:
```powershell
flutter pub get
```

## 4. Запуск

```powershell
flutter devices                 # посмотреть доступные устройства
flutter run -d windows          # Windows desktop
flutter run -d emulator-5554    # Android-эмулятор/устройство (id из flutter devices)
```

Hot reload — клавиша `r` в терминале с запущенным `flutter run`.

> В репозитории есть папка `web/` (сгенерирована `flutter create`), но веб —
> не поддерживаемая платформа проекта: не тестируется и не собирается в релизах.

## 5. Сборка релиза

```powershell
flutter build windows --release           # → build\windows\runner\Release\
flutter build apk --release               # → build\app\outputs\flutter-apk\app-release.apk
```

Для подписанного Android-релиза нужен `android/key.properties` + keystore
(в репозитории их нет — см. `.gitignore`); без них соберётся debug-подписанный APK.
