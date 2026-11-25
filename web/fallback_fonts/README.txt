Запасные шрифты движка Flutter web — отдаются со своего адреса, а не с
fonts.gstatic.com (см. web/flutter_bootstrap.js). Имена файлов — те, что ждёт движок.

roboto/          Roboto Regular из Flutter SDK (material_fonts). Apache License 2.0.
notocoloremoji/  Noto Color Emoji, Google Fonts (скачано 24.11.2026 для Flutter 3.44).
                 SIL Open Font License 1.1: https://openfontlicense.org
При обновлении Flutter сверить имена: grep "notocoloremoji/v" в flutter_web_sdk/lib/_engine.
