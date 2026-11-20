#!/bin/bash
set -e
echo "=== Preparing Kasir Django Static Assets for Vercel ==="

# 1. Pastikan direktori output selalu ada
mkdir -p staticfiles
mkdir -p staticfiles_build/static

# 2. Coba jalankan collectstatic jika Django terpasang di runtime
if python3 -c "import django" >/dev/null 2>&1; then
    echo "[Vercel Build] Menjalankan collectstatic..."
    python3 manage.py collectstatic --noinput --clear || true
fi

# 3. Salin staticfiles dari repository ke staticfiles_build/static
echo "[Vercel Build] Menyalin asset ke staticfiles_build/static..."
if [ -d "staticfiles" ] && [ "$(ls -A staticfiles 2>/dev/null)" ]; then
    cp -r staticfiles/. staticfiles_build/static/
fi

if [ -d "static" ] && [ "$(ls -A static 2>/dev/null)" ]; then
    cp -r static/. staticfiles_build/static/
fi

if [ -f "staticfiles/favicon.ico" ]; then
    cp staticfiles/favicon.ico staticfiles_build/favicon.ico
fi

# 4. Marker file agar folder staticfiles_build dijamin TIDAK PERNAH kosong
touch staticfiles_build/.keep
touch staticfiles_build/static/.keep

echo "=== Static Assets Ready for Vercel ==="
