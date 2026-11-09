#!/bin/bash
set -e
echo "=== Building Kasir Django for Vercel ==="

export UV_LINK_MODE=copy

# 1. Pastikan direktori staticfiles dan output build ada
mkdir -p staticfiles
mkdir -p staticfiles_build/static

# 2. Gunakan virtual environment dengan python3 sistem
if command -v uv >/dev/null 2>&1; then
    echo "[Vercel Build] Menggunakan uv virtual environment..."
    uv venv --python python3 .venv
    echo "[Vercel Build] Menginstall dependensi via uv..."
    uv pip install -r requirements.txt
    echo "[Vercel Build] Menjalankan collectstatic via .venv..."
    .venv/bin/python manage.py collectstatic --noinput --clear
elif python3 -m venv .venv 2>/dev/null; then
    echo "[Vercel Build] Menggunakan python3 venv..."
    .venv/bin/pip install -r requirements.txt
    echo "[Vercel Build] Menjalankan collectstatic..."
    .venv/bin/python manage.py collectstatic --noinput --clear
else
    echo "[Vercel Build] Fallback pip install..."
    python3 -m pip install -r requirements.txt --break-system-packages
    python3 manage.py collectstatic --noinput --clear
fi

# 3. Salin static files ke direktori distDir Vercel
echo "[Vercel Build] Menyalin staticfiles ke staticfiles_build/static..."
cp -r staticfiles/. staticfiles_build/static/

echo "=== Build Finished Successfully ==="
