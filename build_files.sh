#!/bin/bash
echo "=== Building Kasir Django for Vercel ==="

# Install all project dependencies
python3 -m pip install -r requirements.txt

# Collect static assets into staticfiles directory
python3 manage.py collectstatic --noinput --clear

echo "=== Build Finished ==="
