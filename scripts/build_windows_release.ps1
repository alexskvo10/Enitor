# Сборка Windows-релиза: enitor.exe + enitor-cli.exe в одном zip.
#
#   powershell -File scripts/build_windows_release.ps1
#
# Версия берётся из pubspec.yaml. Результат — dist/release-vX.Y.Z/
# enitor-vX.Y.Z-windows.zip с папкой enitor-vX.Y.Z-windows/ внутри (как у
# прошлых релизов). Скрипт падает, если в архиве нет хотя бы одного из двух
# exe: консоль для интеграций без неё бесполезна, а заметить это глазами
# легко пропустить.

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$name = "enitor-v$version-windows"
$release = 'build\windows\x64\runner\Release'

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

# `dart compile exe` спотыкается о хуки сборки пакета objective_c, поэтому —
# `dart build cli`; рядом с exe он кладёт нужные библиотеки в bundle/lib.
dart build cli -t bin/enitor_cli.dart -o build\cli
if ($LASTEXITCODE -ne 0) { throw 'dart build cli failed' }
Copy-Item build\cli\bundle\bin\enitor_cli.exe "$release\enitor-cli.exe" -Force
if (Test-Path build\cli\bundle\lib) {
    Copy-Item build\cli\bundle\lib\* $release -Recurse -Force
}

# Эталонный сервер синхронизации (docs/integrations/server.md) — тем же способом.
dart build cli -t bin/enitor_server.dart -o build\server
if ($LASTEXITCODE -ne 0) { throw 'dart build cli (server) failed' }
Copy-Item build\server\bundle\bin\enitor_server.exe "$release\enitor-server.exe" -Force

# ENITOR_RELEASE_OUT — своя папка для пробной сборки, мимо dist.
$out = if ($env:ENITOR_RELEASE_OUT) { $env:ENITOR_RELEASE_OUT } else { "dist\release-v$version" }
New-Item -ItemType Directory -Force $out | Out-Null
$stage = Join-Path $env:TEMP $name
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
Copy-Item $release $stage -Recurse
$zip = Join-Path (Resolve-Path $out) "$name.zip"
# Готовый архив не перезаписываем никогда: это может быть уже выложенный
# релиз той же версии. Новая сборка — новая версия в pubspec.yaml.
if (Test-Path $zip) { throw "Already exists, bump the version: $zip" }
# Записи создаём сами: и Compress-Archive, и ZipFile.CreateFromDirectory в
# Windows PowerShell 5.1 пишут пути через «\», а другие распаковщики
# понимают только «/».
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
$base = (Resolve-Path $stage).Path.TrimEnd('\') + '\'
Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel = $name + '/' + $_.FullName.Substring($base.Length).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive, $_.FullName, $rel, 'Optimal') | Out-Null
}
$archive.Dispose()
Remove-Item $stage -Recurse -Force

$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
$entries = $archive.Entries.FullName
$archive.Dispose()
foreach ($exe in @("$name/enitor.exe", "$name/enitor-cli.exe")) {
    if (-not ($entries -contains $exe)) { throw "Missing in the archive: $exe" }
}
Write-Output "OK: $zip"
