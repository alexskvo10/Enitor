#!/usr/bin/env bash
# Выкладка веб-версии (build/web, собрать: powershell -File scripts/build_web.ps1)
# на enitor.alexskvo.com. Только файлы: сервер их раздаёт и ничего не
# принимает (Caddyfile — в репо server). Ничего не перезапускает.
set -euo pipefail
cd "$(dirname "$0")/.."

HOST=${SERVER_HOST:-root@151.241.227.125}
SITE=enitor.alexskvo.com
# На Windows ключ лежит в ssh-agent Windows, а ssh из Git Bash его не видит.
SSH=ssh
[ -x /c/Windows/System32/OpenSSH/ssh.exe ] && SSH=/c/Windows/System32/OpenSSH/ssh.exe

[ -f build/web/index.html ] || { echo "нет build/web — сначала build_web.ps1" >&2; exit 1; }
if grep -q 'uncommitted' build/web/version.txt; then
  echo "сборка из незакоммиченного кода — сначала коммит и пересборка" >&2; exit 1
fi

# Папка подменяется целиком: новая рядом, потом переименование.
tar -C build -cf - web | "$SSH" "$HOST" "set -e
  rm -rf /var/www/site/.new-$SITE && mkdir -p /var/www/site/.new-$SITE
  tar -C /var/www/site/.new-$SITE -xf - && chmod -R a+rX /var/www/site/.new-$SITE
  rm -rf /var/www/site/.old-$SITE
  [ -d /var/www/site/$SITE ] && mv /var/www/site/$SITE /var/www/site/.old-$SITE
  mv /var/www/site/.new-$SITE/web /var/www/site/$SITE
  rm -rf /var/www/site/.new-$SITE /var/www/site/.old-$SITE"
echo "выложено: https://$SITE/ ($(sed -n 2p build/web/version.txt))"
