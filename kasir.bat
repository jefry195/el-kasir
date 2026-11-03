@echo off
setlocal enabledelayedexpansion
title Aplikasi Kasir - Localhost:7971
cd /d "%~dp0"

set "PORT=7971"
set "HOST=127.0.0.1"
set "URL=http://localhost:%PORT%"

echo =======================================================
echo          SISTEM KASIR - AUTO LAUNCHER
echo =======================================================
echo.

:: 1. Deteksi Python Environment
set "PYTHON_BIN="
if exist "venv\Scripts\python.exe" (
    set "PYTHON_BIN=venv\Scripts\python.exe"
) else if exist ".venv\Scripts\python.exe" (
    set "PYTHON_BIN=.venv\Scripts\python.exe"
) else (
    where python >nul 2>&1
    if !errorlevel! equ 0 (
        set "PYTHON_BIN=python"
    ) else (
        echo [ERROR] Python tidak ditemukan! Pastikan Python atau virtual environment terpasang.
        pause
        exit /b 1
    )
)
echo [OK] Menggunakan Python: !PYTHON_BIN!

:: 2. Cek Konektivitas IP Localhost
echo [INFO] Memeriksa konektivitas IP Localhost...
ping -n 1 127.0.0.1 >nul 2>&1
if !errorlevel! neq 0 (
    echo [PERINGATAN] Loopback 127.0.0.1 tidak merespon ping, melanjutkan dengan localhost.
) else (
    echo [OK] IP Localhost (127.0.0.1) normal dan tidak ada konflik.
)

:: 3. Cek Konflik Port 7971
echo [INFO] Memeriksa ketersediaan Port %PORT%...
set "OCCUPIED_PID="
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /R /C:":%PORT% "') do (
    set "OCCUPIED_PID=%%a"
)

if defined OCCUPIED_PID (
    echo [PERINGATAN] Port %PORT% sedang dipakai oleh PID !OCCUPIED_PID!.
    echo [INFO] Mencoba menghentikan proses lama untuk menghindari konflik...
    taskkill /F /PID !OCCUPIED_PID! >nul 2>&1
    timeout /t 1 /nobreak >nul
    
    :: Cek ulang setelah kill
    set "RECHECK_PID="
    for /f "tokens=5" %%b in ('netstat -ano -p tcp ^| findstr /R /C:":%PORT% "') do (
        set "RECHECK_PID=%%b"
    )
    if defined RECHECK_PID (
        echo [ERROR] Gagal membebaskan Port %PORT%. Silakan tutup aplikasi yang memakai port tersebut.
        pause
        exit /b 1
    ) else (
        echo [OK] Port %PORT% berhasil dibebaskan!
    )
) else (
    echo [OK] Port %PORT% aman, tidak ada konflik port.
)

:: 4. Cek dan Konfigurasi Firewall
echo [INFO] Memeriksa status Windows Firewall untuk Port %PORT%...
netsh advfirewall firewall show rule name="Kasir_Port_%PORT%" >nul 2>&1
if !errorlevel! neq 0 (
    netsh advfirewall firewall add rule name="Kasir_Port_%PORT%" dir=in action=allow protocol=TCP localport=%PORT% >nul 2>&1
    if !errorlevel! equ 0 (
        echo [OK] Rule Firewall baru berhasil ditambahkan untuk Port %PORT%.
    ) else (
        echo [INFO] Firewall aktif, akses localhost/loopback diizinkan secara default.
    )
) else (
    echo [OK] Rule Firewall untuk Port %PORT% sudah terdaftar.
)

:: 5. Otomatis Buka Browser
echo.
echo [INFO] Membuka web browser ke %URL% dalam 2 detik...
start "" cmd /c "timeout /t 2 /nobreak >nul & start %URL%"

:: 6. Jalankan Server Django
echo [INFO] Menjalankan server kasir di %URL% ...
echo Tekan CTRL+C untuk menghentikan server.
echo =======================================================
echo.

"%PYTHON_BIN%" manage.py runserver %HOST%:%PORT%

if !errorlevel! neq 0 (
    echo.
    echo [ERROR] Server berhenti dengan kode error: !errorlevel!
    pause
)
