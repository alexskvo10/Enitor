# Веб-версия Enitor -> build/web (выкладка: bash scripts/deploy_web.sh).
# Запуск из корня репо: powershell -File scripts/build_web.ps1 [-BaseHref /]
# --no-web-resources-cdn: CanvasKit со своего адреса, не с gstatic.com (Google).
# Запасные шрифты (Roboto, эмодзи) тоже свои: см. web/flutter_bootstrap.js.
param([string]$BaseHref = '/')
$ErrorActionPreference = 'Stop'

flutter build web --release --no-web-resources-cdn --no-source-maps --base-href $BaseHref
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = 'build/web'
Remove-Item -Force -ErrorAction SilentlyContinue "$out/.last_build_id"

# Сборка dart2js рисует только через CanvasKit: остальные движки и символы
# отладки не грузятся, а весят ~25 МБ.
Get-ChildItem "$out/canvaskit" -Recurse -Include 'skwasm*', 'wimp*', '*.symbols' | Remove-Item -Force
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$out/canvaskit/experimental_webparagraph"

# Из какого коммита собрано — открыто всем: enitor.alexskvo.com/version.txt.
$commit = git rev-parse HEAD
$dirty = if (git status --porcelain -- lib web pubspec.yaml pubspec.lock) { ' (+ uncommitted changes)' } else { '' }
Set-Content -Encoding ascii "$out/version.txt" "Enitor web`ncommit $commit$dirty`nbuilt $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC"

Write-Host "OK: $out"
