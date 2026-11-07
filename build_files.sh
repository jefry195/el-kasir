#!/bin/bash
set -e
echo "=== Building Kasir Django for Vercel ==="

# Install dependencies into system with --break-system-packages, fallback to venv if needed
if python3 -m pip install -r requirements.txt --break-system-packages; then
    echo "Dependencies installed via pip with --break-system-packages"
    mkdir -p staticfiles
    python3 manage.py collectstatic --noinput --clear
else
    echo "Falling back to virtual environment..."
    python3 -m venv .build_env
    source .build_env/bin/activate
    pip install -r requirements.txt
    mkdir -p staticfiles
    python manage.py collectstatic --noinput --clear
fi

echo "=== Build Finished Successfully ==="
