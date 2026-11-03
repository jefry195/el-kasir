import os
import socket
import django

# 1. Setup Django settings
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'core.settings')
django.setup()

# 2. Verify login endpoint
from django.test import Client
client = Client()
response = client.get('/login/')
assert response.status_code == 200, f"Expected 200 from /login/, got {response.status_code}"

# 3. Check port 7971 bindability
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind(('127.0.0.1', 7971))
sock.close()

# 4. Check kasir.bat existence
assert os.path.isfile('kasir.bat'), "kasir.bat does not exist"

print("Setup check passed: Django configuration, database, port 7971, and kasir.bat are verified.")
