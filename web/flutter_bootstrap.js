{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: {
    // Запасные шрифты — только свои. По умолчанию движок берёт Roboto (и
    // шрифты для эмодзи и редких алфавитов) с fonts.gstatic.com, то есть
    // показывает Google IP посетителя. Roboto — из Flutter SDK (Apache 2.0),
    // под именем, которое ждёт движок; остальное просто не найдётся.
    fontFallbackBaseUrl: "fallback_fonts/",
  },
});
