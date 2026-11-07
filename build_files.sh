#!/bin/bash
echo "=== Building Kasir Django for Vercel ==="

# 1. Pastikan direktori staticfiles selalu ada agar tidak memicu error STATIC_BUILD_NO_OUT_DIR
mkdir -p staticfiles

# 2. Install dependencies (support uv / pip break-system-packages / venv)
if command -v uv >/dev/null 2>&1; then
    echo "[Vercel Build] Menggunakan uv untuk instalasi dependensi..."
    uv pip install --system -r requirements.txt || python3 -m pip install -r requirements.txt --break-system-packages
elif python3 -m pip --version >/dev/null 2>&1; then
    echo "[Vercel Build] Menggunakan pip (--break-system-packages)..."
    python3 -m pip install -r requirements.txt --break-system-packages
else
    echo "[Vercel Build] Membuat virtual environment fallback..."
    python3 -m venv .build_env
    source .build_env/bin/activate
    pip install -r requirements.txt
fi

# 3. Kumpulkan asset static ke folder staticfiles
echo "[Vercel Build] Menjalankan collectstatic..."
python3 manage.py collectstatic --noinput --clear || python manage.py collectstatic --noinput --clear

echo "=== Build Finished Successfully ==="
