# Dokumentasi Akun Login, Bug, dan Solusi Deploy Vercel

Dokumen ini berisi informasi kredensial akun login serta rincian seluruh kendala teknis (bug & error) yang ditemukan saat melakukan *deployment* proyek **Kasir Django** ke platform serverless **Vercel**, beserta solusi teknis yang telah diterapkan.

---

## 1. Informasi Akun Login (Default Credentials)

Berdasarkan data yang tersimpan pada database default (`cashier.db`), akun yang dapat langsung digunakan adalah:

| Role | Username | Password | Akses URL |
| :--- | :--- | :--- | :--- |
| **Superuser / Admin** | `admin` | `admin` | `/login/` atau `/admin/` (Jet Admin Dashboard) |
| **Pendaftaran Baru** | *(Daftar Mandiri)* | *(Sesuai Registrasi)* | `/register/` |

> **Catatan Penggunaan di Vercel:**
> - Jika menggunakan database bawaan SQLite (`cashier.db`), aplikasi telah dikonfigurasi untuk menyalin file database ke `/tmp/cashier.db` saat runtime Vercel agar sesi login dapat disimpan tanpa crash.
> - Jika ingin data tersimpan permanen di cloud (tidak hilang saat serverless restart/cold start), hubungkan database cloud PostgreSQL (seperti **Neon**, **Supabase**, atau **ElephantSQL**) dengan mengisi Environment Variable `DATABASE_URL` di Vercel Dashboard.

---

## 2. Rincian Bug & Error Deployment Vercel Beserta Solusinya

Berikut adalah daftar lengkap 8 kendala yang menyebabkan kegagalan build/runtime di Vercel beserta perbaikan yang telah diterapkan:

---

### Bug 1: Runtime Python 3.9 Dihentikan Vercel (Deprecated)
* **Pesan Error:**  
  `Error: Unable to find any supported Python versions` atau `Invalid runtime python3.9`
* **Penyebab:**  
  Vercel telah menghentikan dukungan (*end-of-life*) untuk runtime Python 3.9 pada container build modernnya. Vercel kini hanya mendukung **Python 3.12, 3.13, dan 3.14**. Konfigurasi sebelumnya yang memasang versi `3.9` pada `.python-version` dan `vercel.json` langsung ditolak oleh runner Vercel.
* **Solusi:**  
  - Memperbarui [`.python-version`](.python-version) menjadi `3.12`.
  - Memperbarui parameter `runtime` pada [`vercel.json`](vercel.json) menjadi `python3.12`.

---

### Bug 2: Penghapusan Modul `distutils` pada Python 3.12 (PEP 632)
* **Pesan Error:**  
  ```text
  ModuleNotFoundError: No module named 'distutils'
  ImportError: Couldn't import Django. Are you sure it's installed and available on your PYTHONPATH...
  ```
* **Penyebab:**  
  Pada Python 3.12, modul `distutils` resmi dihapus dari Python Standard Library. Django 2.2 masih memanggil `from distutils.version import LooseVersion` di dalam `django.utils.version`.
* **Solusi:**  
  Membuat modul kompatibilitas ringan [`core/compat.py`](core/compat.py) yang menyediakan implementasi native `LooseVersion` dan mendaftarkan modul virtual `distutils` & `distutils.version` ke dalam `sys.modules`. Modul ini di-import pada baris paling awal di [`manage.py`](manage.py), [`core/wsgi.py`](core/wsgi.py), dan [`core/settings.py`](core/settings.py).

---

### Bug 3: Meta Path Importer Incompatibility pada `six.moves` (PEP 451)
* **Pesan Error:**  
  ```text
  ModuleNotFoundError: No module named 'django.utils.six.moves'
  ```
* **Penyebab:**  
  Python 3.12 sepenuhnya menghapus metode lawas `find_module` pada *meta path importers* dan mewajibkan implementasi `find_spec` (PEP 451). Modul `django.utils.six` bawaan Django 2.2 belum mengimplementasikan `find_spec`, sehingga pemanggilan modul seperti `django.utils.six.moves.http_client` pada Django REST Framework gagal.
* **Solusi:**  
  Menambahkan patch fungsi `find_spec`, `create_module`, dan `exec_module` pada kelas `_SixMetaPathImporter` di dalam [`core/compat.py`](core/compat.py) sehingga submodul `six.moves` dapat diakses secara normal di Python 3.12.

---

### Bug 4: `ModuleNotFoundError: No module named 'django'` pada `@vercel/static-build`
* **Pesan Error:**  
  ```text
  Traceback (most recent call last):
    File "/vercel/path0/manage.py", line 10, in main
      from django.core.management import execute_from_command_line
  ModuleNotFoundError: No module named 'django'
  ```
* **Penyebab:**  
  Container `@vercel/static-build` pada Vercel adalah environment terpisah yang tidak memiliki Django di path sistemnya. Menjalankan `pip install -r requirements.txt` di dalam script static build memakan waktu lama, berisiko terkena proteksi PEP 668 (*externally-managed-environment*), dan sering gagal mengekspos library ke `python3`.
* **Solusi:**  
  Mengubah arsitektur build: Asset statis di-*collect* secara lokal terlebih dahulu (`staticfiles/`) dan disimpan langsung ke repositori git. Script [`build_files.sh`](build_files.sh) kini cukup menyalin asset yang sudah jadi ke `distDir` tanpa perlu menjalankan instalasi pip berulang-ulang yang rentan gagal.

---

### Bug 5: Error `STATIC_BUILD_EMPTY_OUT_DIR`
* **Pesan Error:**  
  ```text
  Error: [STATIC_BUILD_EMPTY_OUT_DIR] The Output Directory "staticfiles" is empty.
  Learn More: https://vercel.link/missing-public-directory
  ```
* **Penyebab:**  
  Folder `staticfiles/` sebelumnya dimasukkan ke dalam `.gitignore`, sehingga folder tersebut tidak ada di GitHub. Saat `build_files.sh` gagal mengumpulkan static files di Vercel, direktori output menjadi kosong. Vercel secara ketat menolak deployment jika output build kosong.
* **Solusi:**  
  - Menghapus aturan `staticfiles/` dari [`.gitignore`](.gitignore) dan melakukan commit seluruh 2.185 file asset ke repositori.
  - Memperbarui [`build_files.sh`](build_files.sh) agar menyalin asset ke `staticfiles_build/static/` dan menambahkan file `.keep` untuk menjamin direktori output tidak akan pernah kosong dalam kondisi apapun.
  - Menyesuaikan `distDir` pada [`vercel.json`](vercel.json) ke `staticfiles_build`.

---

### Bug 6: Crash Read-Only Filesystem pada `server.log`
* **Pesan Error:**  
  ```text
  OSError: [Errno 30] Read-only file system: 'server.log'
  ```
* **Penyebab:**  
  Pada Vercel Serverless Functions (AWS Lambda), filesystem direktori aplikasi bersifat *strictly read-only*. Penggunaan `logging.FileHandler` yang mencoba menulis file `server.log` ke root proyek memicu crash saat aplikasi pertama kali menerima request HTTP.
* **Solusi:**  
  Mengubah handler logging pada [`core/settings.py`](core/settings.py) dari `logging.FileHandler` menjadi `logging.StreamHandler`. Dengan demikian seluruh log Django dialirkan langsung ke konsol Vercel Logs tanpa menulis ke disk.

---

### Bug 7: Error SQLite Read-Only saat Transaksi/Login
* **Pesan Error:**  
  ```text
  sqlite3.OperationalError: attempt to write a readonly database
  ```
* **Penyebab:**  
  File `cashier.db` di `/var/task/cashier.db` berada di partisi read-only. Ketika user login, Django mencoba menulis data session ke tabel `django_session`, yang menyebabkan crash.
* **Solusi:**  
  Di [`core/settings.py`](core/settings.py), ditambahkan logika proteksi: jika dijalankan di environment Vercel (`VERCEL=1`) tanpa `DATABASE_URL`, aplikasi secara otomatis menyalin `cashier.db` ke direktori `/tmp/cashier.db` (partisi writable sementara pada serverless instance) sebelum membuka koneksi database.

---

### Bug 8: Potensi Upload File Berlebih & Konflik Binary Windows
* **Penyebab:**  
  Sebelumnya proyek tidak memiliki file `.vercelignore`. Hal ini dapat menyebabkan folder virtual environment Windows (`venv/` berukuran ratusan MB), file batch (`.bat`), file log, dan cache Python ikut terunggah, melebihi batas ukuran fungsi Vercel (maksimal zip 50MB / unzipped 250MB).
* **Solusi:**  
  Membuat file [`.vercelignore`](.vercelignore) yang mengecualikan:
  - `venv/`, `.venv/`, `env/`
  - `*.bat`
  - `*.log`, `server.log`
  - `__pycache__/`, `*.pyc`
  - `.git/`

---

## 3. Ringkasan File yang Diubah

1. **[`core/compat.py`](core/compat.py)**: Layer kompatibilitas Python 3.12 (`distutils`, `collections.abc`, `six.moves`).
2. **[`manage.py`](manage.py)**: Import `core.compat` di baris paling awal.
3. **[`core/wsgi.py`](core/wsgi.py)**: Import `core.compat` sebelum memanggil `get_wsgi_application()`.
4. **[`core/settings.py`](core/settings.py)**: Import `core.compat`, logging `StreamHandler`, dan fallback SQLite ke `/tmp/`.
5. **[`.python-version`](.python-version)**: Diset ke `3.12`.
6. **[`vercel.json`](vercel.json)**: Runtime diset ke `python3.12` dan `distDir` ke `staticfiles_build`.
7. **[`build_files.sh`](build_files.sh)**: Script penyalinan asset statis yang cepat, aman, dan kebal error.
8. **[`.gitignore`](.gitignore)**: Mengizinkan tracking folder `staticfiles/`.
9. **[`.vercelignore`](.vercelignore)**: Mencegah upload file sampah dan binary Windows.
10. **[`staticfiles/`](staticfiles/)**: 2.185 file asset statis siap saji via Edge CDN.
