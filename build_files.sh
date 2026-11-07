#!/bin/bash
set -e
echo "=== Building Kasir Django for Vercel ==="

export UV_LINK_MODE=copy

# 1. Pastikan direktori staticfiles ada
mkdir -p staticfiles

# 2. Gunakan virtual environment dengan python3 sistem
if command -v uv >/dev/null 2>&1; then
    echo "[Vercel Build] Membuat .venv menggunakan uv (--python python3)..."
    uv venv --python python3 .venv
    echo "[Vercel Build] Menginstall dependensi ke dalam .venv..."
    uv pip install -r requirements.txt
    echo "[Vercel Build] Menjalankan collectstatic via .venv/bin/python..."
    .venv/bin/python manage.py collectstatic --noinput --clear
elif python3 -m venv .venv 2>/dev/null; then
    echo "[Vercel Build] Membuat .venv menggunakan python3 venv..."
    .venv/bin/pip install -r requirements.txt
    echo "[Vercel Build] Menjalankan collectstatic..."
    .venv/bin/python manage.py collectstatic --noinput --clear
else
    echo "[Vercel Build] Fallback instalasi sistem..."
    python3 -m pip install -r requirements.txt --break-system-packages
    python3 manage.py collectstatic --noinput --clear
fi

echo "=== Build Finished Successfully ==="
