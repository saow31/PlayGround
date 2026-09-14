#!/usr/bin/env bash
# startup.sh — запуск приложения на свежем Actions-раннере.
# - переходит в собственный каталог (корень проекта)
# - проверяет playable entrypoint (./index.html или ./dist/index.html)
# - устанавливает зависимости (если есть package.json), сборка при необходимости
# - стартует сервер на ${PORT:-3000} на переднем плане
# Повторные запуски безопасно переиспользуют уже установленные зависимости.
set -euo pipefail

# --- per-command timing helper ---
_time() {
  local label="$1"; shift
  local start end code
  start=$(date +%s)
  echo "==> [startup] ${label} ..."
  set +e
  "$@"
  code=$?
  set -e
  end=$(date +%s)
  echo "==> [startup] ${label} done in $((end - start))s (exit=${code})"
  return "${code}"
}

# 1. Собственный каталог проекта
_time "change to project directory" cd "$(dirname "$0")"
echo "==> [startup] project dir: $(pwd)"

# 2. Entrypoint: ./index.html или ./dist/index.html
SERVE_DIR="."
if [ -f "./index.html" ]; then
  echo "==> [startup] entrypoint found: ./index.html"
elif [ -f "./dist/index.html" ]; then
  echo "==> [startup] entrypoint found: ./dist/index.html"
  SERVE_DIR="./dist"
else
  echo "==> [startup] ERROR: neither ./index.html nor ./dist/index.html exists" >&2
  exit 1
fi

PORT="${PORT:-3000}"
echo "==> [startup] port: ${PORT}"

# 3. Зависимости (только если проект их требует)
if [ -f package.json ]; then
  if command -v npm >/dev/null 2>&1; then
    if [ ! -d node_modules ]; then
      if [ -f package-lock.json ]; then
        _time "npm ci" npm ci --no-audit --no-fund
      else
        _time "npm install" npm install --no-audit --no-fund
      fi
    else
      echo "==> [startup] node_modules exists, reusing dependencies"
    fi
    # 4. Сборка при необходимости (только если есть build-скрипт и нет готового dist)
    if npm run | grep -q " build" 2>/dev/null; then
      if [ ! -f "./dist/index.html" ]; then
        _time "npm run build" npm run build
      else
        echo "==> [startup] dist/index.html exists, skipping build"
      fi
      if [ -f "./dist/index.html" ]; then
        SERVE_DIR="./dist"
      fi
    fi
  else
    echo "==> [startup] WARNING: package.json found but npm is missing, skipping install" >&2
  fi
else
  echo "==> [startup] no package.json — static site, nothing to install or build"
fi

# 5. Сервер на переднем плане
echo "==> [startup] serving '${SERVE_DIR}' on port ${PORT} (foreground)"
if command -v python3 >/dev/null 2>&1; then
  _time "serve (python3 http.server)" python3 -m http.server "${PORT}" --directory "${SERVE_DIR}"
else
  _time "serve (npx serve)" npx --yes serve -l "${PORT}" "${SERVE_DIR}"
fi
