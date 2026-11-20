# Dokumentasi Bug, Celah Logika, dan Error Sistem Aplikasi Kasir (Non-Vercel)

Dokumen ini berisi hasil audit komprehensif terhadap logika bisnis, arsitektur database, keamanan, dan alur kerja aplikasi **Kasir Django** (terlepas dari infrastruktur deployment Vercel). 

Terdapat **18 temuan bug dan celah teknis** yang teridentifikasi dalam kode sumber, dikelompokkan berdasarkan kategori dampaknya:

---

## Daftar Isi
1. [Kategori 1: Transaksi Kasir & Logika Bisnis (Kritis)](#kategori-1-transaksi-kasir--logika-bisnis-kritis)
2. [Kategori 2: Perhitungan Keuangan & Laporan Toko](#kategori-2-perhitungan-keuangan--laporan-toko)
3. [Kategori 3: Manajemen Akun, Profil, & Relasi Data](#kategori-3-manajemen-akun-profil--relasi-data)
4. [Kategori 4: Keamanan Sistem & Celah Endpoint](#kategori-4-keamanan-sistem--celah-endpoint)
5. [Tabel Rekomendasi Prioritas Perbaikan](#tabel-rekomendasi-prioritas-perbaikan)

---

## Kategori 1: Transaksi Kasir & Logika Bisnis (Kritis)

### 1. Pemusnahan Data Barang saat Stok 0 (`produk.delete()`)
* **File:** [`cashier/forms.py`](cashier/forms.py) (Baris 65–66)
* **Kode Sumber Bermasalah:**
  ```python
  if produk.jumlah_produk >= int(quantity):
      produk.jumlah_produk = produk.jumlah_produk - int(quantity)
      if produk.jumlah_produk == 0:
          produk.delete()  # <-- BUG FATAL: Data terhapus permanen dari DB!
  ```
* **Dampak:** 
  Ketika suatu produk terjual hingga stoknya habis (0), sistem **menghapus baris produk tersebut secara permanen** dari database `DaftarBarang`.
  - Riwayat harga modal (harga beli), persentase laba, dan data master barang hilang seketika.
  - Barang hilang dari tabel stok, sehingga pemilik toko tidak bisa melihat histori barang yang habis untuk restock.
* **Solusi yang Benar:** 
  Jangan gunakan `.delete()`. Biarkan `jumlah_produk = 0` dan gunakan flag status seperti `is_active = False` atau tampilkan badge "Stok Habis".

---

### 2. Tidak Ada Atomic Transaction pada Checkout (`transaction.atomic`)
* **File:** [`cashier/views.py`](cashier/views.py) (Baris 96–117)
* **Kode Sumber Bermasalah:**
  ```python
  transaksi = DaftarTransaksi.objects.create(user_id=request.user.id)
  transaksi.save()
  for form in formset_post:
      if form.cleaned_data['quantity'] < 1:
          return redirect('/cart/')
      output = form.save(transaksi)
      if(output == False):
          return redirect('/cart/')
  ```
* **Dampak:**
  Objek `DaftarTransaksi` dibuat **sebelum** loop validasi barang selesai.
  Jika kasir memasukkan 3 barang, dan barang ke-3 gagal (misal stok kurang):
  1. Barang ke-1 dan ke-2 **sudah terlanjur dipotong stoknya**.
  2. Sebuah transaksi kosong (ghost transaction) dengan total Rp 0 tetap tersimpan di database.
  3. Terjadi inkonsistensi data antara stok fisik dan catatan database.
* **Solusi yang Benar:**
  Bungkus proses checkout dalam blok `with transaction.atomic():` sehingga jika salah satu item gagal, seluruh perubahan di-rollback otomatis.

---

### 3. Race Condition Pengurangan Stok Bersamaan (Multi-Kasir)
* **File:** [`cashier/forms.py`](cashier/forms.py) (Baris 62–71)
* **Kode Sumber Bermasalah:**
  ```python
  produk = DaftarBarang.objects.get(nomor=self.cleaned_data['nama_barang'])
  if produk.jumlah_produk >= int(quantity):
      produk.jumlah_produk = produk.jumlah_produk - int(quantity)
      produk.save()
  ```
* **Dampak:**
  Tidak adanya penguncian baris (*row-level locking* / `select_for_update()`) atau operasi atomik database (`F('jumlah_produk') - quantity`).
  Jika dua kasir melayani pembeli berbeda untuk barang sisa 1 pada detik yang sama, keduanya akan membaca `jumlah_produk = 1`, keduanya berhasil menjual, dan stok fisik menjadi minus.
* **Solusi yang Benar:**
  Gunakan `DaftarBarang.objects.select_for_update().get(...)` di dalam transaksi atau gunakan `F()` expression:
  ```python
  DaftarBarang.objects.filter(nomor=produk.nomor, jumlah_produk__gte=quantity).update(
      jumlah_produk=F('jumlah_produk') - quantity
  )
  ```

---

### 4. Crash `DaftarBarang.DoesNotExist` pada Form Transaksi
* **File:** [`cashier/forms.py`](cashier/forms.py) (Baris 60)
* **Kode Sumber Bermasalah:**
  ```python
  produk = DaftarBarang.objects.get(nomor=self.cleaned_data['nama_barang'])
  ```
* **Dampak:**
  Jika produk yang dipilih di dropdown telah dihapus/habis oleh kasir lain sebelum form disubmit, pemanggilan `.get()` akan melempar unhandled exception `DaftarBarang.DoesNotExist` dan memicu **HTTP 500 Internal Server Error**.
* **Solusi yang Benar:**
  Gunakan `try ... except DaftarBarang.DoesNotExist:` atau validasi di level form clean method.

---

### 5. Batas Maksimal Transaksi Hanya Rp 9,9 Juta (`max_digits=9`)
* **File:** [`cashier/models.py`](cashier/models.py) (Baris 38)
* **Kode Sumber Bermasalah:**
  ```python
  total = models.DecimalField(max_digits=9, decimal_places=2, blank=True, default=0)
  ```
* **Dampak:**
  Dalam mata uang Rupiah (IDR), `max_digits=9` dengan 2 desimal artinya hanya menyisakan 7 digit sebelum koma (`9.999.999,99` atau **maksimal Rp 9,9 Juta**). 
  Jika sebuah toko grosir melakukan transaksi senilai Rp 10.000.000 ke atas, database akan menolak dan melempar error:
  `django.db.utils.DataError: numeric field overflow`.
* **Solusi yang Benar:**
  Ubah `max_digits` minimal ke `14` atau `16` (contoh: `max_digits=16, decimal_places=2`).

---

### 6. Inkonsistensi Tipe Data Subtotal Barang
* **File:** [`cashier/models.py`](cashier/models.py) (Baris 55) & [`cashier/forms.py`](cashier/forms.py) (Baris 77–82)
* **Kode Sumber Bermasalah:**
  ```python
  # Di models.py:
  subtotal = models.PositiveIntegerField(blank=True, null=True)

  # Di forms.py:
  subtotal_produk = produk.harga_jual_satuan * int(quantity)  # Decimal dikali Int
  ```
* **Dampak:**
  Kolom harga jual di `DaftarBarang` bertipe `DecimalField`, sedangkan `subtotal` pada `ListProductTransaksi` bertipe `PositiveIntegerField`. Konversi implisit membuang nilai presisi sen atau memicu inkonsistensi saat menghitung total keseluruhan.
* **Solusi yang Benar:**
  Gunakan `DecimalField` pada kedua model secara seragam.

---

## Kategori 2: Perhitungan Keuangan & Laporan Toko

### 7. Filter Pendapatan Hari Ini Salah Tanggal (`HomeIndex`)
* **File:** [`cashier/views.py`](cashier/views.py) (Baris 34)
* **Kode Sumber Bermasalah:**
  ```python
  today = datetime.today()
  data_pendapatan = DaftarTransaksi.objects.filter(
      created__day=today.day,  # <-- BUG: Hanya memfilter nomor tanggal!
      user_id=request.user.id
  )
  ```
* **Dampak:**
  Filter ini hanya mencocokkan `day` (misal tanggal `20`), **tanpa mengecek bulan dan tahun**.
  Akibatnya, seluruh transaksi tanggal 20 di bulan Januari, Februari, dan bahkan tahun-tahun sebelumnya akan ikut terjumlah ke kartu "Pendapatan Hari Ini" di Dashboard.
* **Solusi yang Benar:**
  Gunakan filter tanggal utuh:
  ```python
  from django.utils import timezone
  today = timezone.localdate()
  data_pendapatan = DaftarTransaksi.objects.filter(
      created__date=today,
      user_id=request.user.id
  )
  ```

---

### 8. Crash AJAX Laporan Penjualan (`TemplateDoesNotExist`)
* **File:** [`cashier/views.py`](cashier/views.py) (Baris 168)
* **Kode Sumber Bermasalah:**
  ```python
  if request.is_ajax():
      ...
      return render(request, 'report_details.html', ...) # <-- Path salah!
  ```
* **Dampak:**
  File template tersebut tersimpan di `templates/cashier/report_details.html`, bukan di root template `templates/report_details.html`.
  Saat kasir menekan tombol "Cari" pada filter tanggal di menu Laporan, AJAX melempar crash `TemplateDoesNotExist: report_details.html`.
* **Solusi yang Benar:**
  Ubah path template menjadi `'cashier/report_details.html'`.

---

### 9. Penggunaan `render_to_response` yang Telah Dihapus
* **File:** [`cashier/views.py`](cashier/views.py) (Baris 82)
* **Kode Sumber Bermasalah:**
  ```python
  @login_required()
  def TotalStock(request):
      data = DaftarBarang.objects.filter(user_id=request.user.id)
      context = {'data': data}
      return render_to_response('cashier/stock.html', context)
  ```
* **Dampak:**
  `render_to_response` telah deprecated di Django 2.x dan **dihapus total di Django 3.0+**. Selain itu, fungsi ini tidak meneruskan `request` secara otomatis, sehingga variabel context processor (seperti informasi user, pesan notifikasi, dan token CSRF) tidak terinjeksi ke template.
* **Solusi yang Benar:**
  Gunakan `render(request, 'cashier/stock.html', context)`.

---

### 10. Timestamp `updated` Tidak Pernah Berubah
* **File:** [`cashier/models.py`](cashier/models.py) (Baris 41)
* **Kode Sumber Bermasalah:**
  ```python
  created = models.DateTimeField(default=now, editable=False)
  updated = models.DateTimeField(default=now, editable=False)  # <-- Tanpa auto_now=True
  ```
* **Dampak:**
  Kolom `updated` pada `DaftarTransaksi` tidak memiliki atribut `auto_now=True`. Ketika transaksi diupdate, nilai `updated` tetap sama dengan nilai `created`.
* **Solusi yang Benar:**
  Gunakan `updated = models.DateTimeField(auto_now=True)`.

---

## Kategori 3: Manajemen Akun, Profil, & Relasi Data

### 11. Crash `UnboundLocalError` pada Update Profil
* **File:** [`accounts/views.py`](accounts/views.py) (Baris 47–52)
* **Kode Sumber Bermasalah:**
  ```python
  if request.method == 'POST':
      ...
      if user_form.is_valid() and profile_form.is_valid():
          return redirect('Account')
  else:
      ...
      data_user = Profile.objects.filter(user_id=request.user.id)

  context = {
      ...
      'data_user': data_user  # <-- Crash jika POST tidak valid!
  }
  ```
* **Dampak:**
  Variabel `data_user` hanya dideklarasikan di blok `else` (GET). Jika user mengirim form POST namun terdapat kesalahan input (form tidak valid), eksekusi melompat langsung ke pembuatan dictionary `context` dan memicu crash:
  `UnboundLocalError: local variable 'data_user' referenced before assignment`.
* **Solusi yang Benar:**
  Inisialisasi `data_user = Profile.objects.filter(user_id=request.user.id)` di luar blok `if/else`.

---

### 12. Seluruh Field Biodata Kasir Tidak Bisa Disimpan
* **File:** [`accounts/forms.py`](accounts/forms.py) (Baris 31–34)
* **Kode Sumber Bermasalah:**
  ```python
  class ProfileUpdateForm(forms.ModelForm):
      class Meta:
          model = Profile
          fields = ['picture']  # <-- Hanya foto profil!
  ```
* **Dampak:**
  Model `Profile` memiliki field lengkap: `nama_depan`, `nama_belakang`, `nomor_telephone`, `provinsi`, `kota`, `kecamatan`, `kelurahan`, `alamat`, `kode_pos`.
  Namun form hanya menyertakan `['picture']`. Akibatnya, kasir atau admin tidak dapat mengubah biodata mereka melalui aplikasi web.
* **Solusi yang Benar:**
  Tambahkan field biodata ke dalam `fields` form:
  ```python
  fields = ['picture', 'nama_depan', 'nama_belakang', 'nomor_telephone', 'provinsi', 'kota', 'kecamatan', 'kelurahan', 'alamat', 'kode_pos']
  ```

---

### 13. Inkonsistensi Relasi User ID vs Profile ID
* **File:** [`cashier/models.py`](cashier/models.py) (Baris 10 & 35) vs [`cashier/views.py`](cashier/views.py) (Baris 33, 96, 136)
* **Kode Sumber Bermasalah:**
  ```python
  # Di models.py:
  user = models.ForeignKey(Profile, on_delete=models.CASCADE)

  # Di views.py:
  DaftarBarang.objects.filter(user_id=request.user.id)
  DaftarTransaksi.objects.create(user_id=request.user.id)
  dataUser = Profile.objects.get(id=dataStruck.user_id)
  ```
* **Dampak:**
  Field `user` pada `DaftarBarang` dan `DaftarTransaksi` berelasi ForeignKey ke model **`Profile`**, tetapi views mengisinya dengan **`request.user.id`** (ID dari tabel `User`/`auth_user`).
  Meskipun pada database baru ID `User` dan `Profile` sama-sama dimulai dari 1, jika ada akun yang dihapus atau dibuat manual, ID `Profile` dan `User` tidak akan sinkron. Hal ini menyebabkan data kasir tertukar dengan kasir lain atau memicu `Profile.DoesNotExist`.
* **Solusi yang Benar:**
  Ubah relasi Foreign Key langsung ke `settings.AUTH_USER_MODEL` atau isi dengan `request.user.profile.id`.

---

### 14. Crash `Profile.save()` saat Resize Foto Profil
* **File:** [`accounts/models.py`](accounts/models.py) (Baris 29–34)
* **Kode Sumber Bermasalah:**
  ```python
  def save(self, *args, **kwargs):
      super().save(*args, **kwargs)
      img = Image.open(self.picture.path)
      if img.height > 300 or img.width > 300:
          output_size = (300, 300)
          img.thumbnail(output_size)
          img.save(self.picture.path)
  ```
* **Dampak:**
  1. `self.picture.path` mengasumsikan file ada di harddisk lokal. Pada cloud storage (AWS S3, Supabase Storage, dll.), atribut `.path` akan memicu `NotImplementedError`.
  2. Jika file `profile_picture.png` default belum disalin ke folder media, server langsung melempar `FileNotFoundError`.
  3. Menyimpan ulang ke `self.picture.path` saat menggunakan default image akan menimpa file default bersama untuk seluruh akun.
* **Solusi yang Benar:**
  Periksa keberadaan file dan pastikan gambar bukan file gambar default sebelum melakukan resize.

---

## Kategori 4: Keamanan Sistem & Celah Endpoint

### 15. API Endpoint Terbuka Tanpa Autentikasi (IDOR & Data Leak)
* **File:** [`api/views.py`](api/views.py) (Baris 10 & 18)
* **Kode Sumber Bermasalah:**
  ```python
  class ApiList(generics.ListCreateAPIView):
      queryset = Profile.objects.all()
      serializer_class = ApiSerializer
      # permission_classes = (permissions.IsAuthenticatedOrReadOnly)  # <-- DIKOMENTARI!

  class ApiDetail(generics.RetrieveUpdateDestroyAPIView):
      queryset = Profile.objects.all()
      serializer_class = ApiSerializer
      # permission_classes = (permissions.IsAuthenticatedOrReadOnly, IsOwnerReadOnly) # <-- DIKOMENTARI!
  ```
* **Dampak:**
  Karena permission dikomentari, endpoint `/auth/api/` dan `/auth/api/<id>/` dapat diakses oleh **siapa saja di internet tanpa login**.
  Penyerang dapat membaca nomor telepon, alamat, nama, dan email seluruh kasir/user, bahkan dapat mengirim request `DELETE` untuk menghapus akun.
* **Solusi yang Benar:**
  Aktifkan `permission_classes = [permissions.IsAuthenticated, IsOwnerReadOnly]`.

---

### 16. Endpoint Crash Publik `/debug/`
* **File:** [`core/urls.py`](core/urls.py) (Baris 11–13, 27)
* **Kode Sumber Bermasalah:**
  ```python
  def trigger_error(request):
      division_by_zero = 1 / 0

  urlpatterns = [
      ...
      path('debug/', trigger_error),
  ]
  ```
* **Dampak:**
  Endpoint `/debug/` mengeksekusi pembagian nol secara sengaja tanpa login. Jika diakses di production saat `DEBUG = True`, penyerang dapat melihat struktur direktori, variabel environment, versi Django, dan konfigurasi rahasia.
* **Solusi yang Benar:**
  Hapus endpoint `/debug/` dari routing aplikasi.

---

### 17. Fungsi Upload Stok Tanpa Login & Memanggil Method yang Tidak Ada
* **File:** [`data/views.py`](data/views.py) (Baris 5–19)
* **Kode Sumber Bermasalah:**
  ```python
  def StockUpload(request):  # <-- Tanpa @login_required
      if request.method == 'POST':
          ...
          new_stock = request.FILES['file'] # <-- Crash KeyError jika file tidak ada
          new_stock.seek(0)
          imported_data = dataset.load(new_stock.read())
          imported_data.save()  # <-- BUG: Dataset tidak punya method .save()!
  ```
* **Dampak:**
  1. Siapapun tanpa login dapat mengakses `/stock/upload/`.
  2. Pemanggilan `imported_data.save()` langsung melempar error `AttributeError: 'Dataset' object has no attribute 'save'`.
  3. `request.FILES['file']` tanpa verifikasi melempar `MultiValueDictKeyError` (500).
* **Solusi yang Benar:**
  Tambahkan `@login_required`, hapus baris `imported_data.save()`, dan validasi file menggunakan Django Form.

---

### 18. URL Pattern Duplikat pada Routing Auth
* **File:** [`core/urls.py`](core/urls.py) (Baris 24–25)
* **Kode Sumber Bermasalah:**
  ```python
  path('auth/', include('api.urls')),
  path('auth/', RedirectView.as_view(url='/auth/api'), name='/auth/api/'),
  ```
* **Dampak:**
  Pola URL `auth/` didaftarkan dua kali berturut-turut. Django hanya akan mencocokkan baris pertama (`include('api.urls')`), sehingga baris kedua tidak akan pernah dieksekusi.
* **Solusi yang Benar:**
  Hapus baris redirect duplikat atau bedakan endpoint URL-nya.

---

## Tabel Rekomendasi Prioritas Perbaikan

| No | Nama Bug / Isu | Tingkat Keparahan | Dampak Utama |
| :---: | :--- | :---: | :--- |
| 1 | `produk.delete()` saat stok habis | **Critical** | Data master barang dan modal terhapus permanen |
| 2 | Ketiadaan `transaction.atomic` pada Cart | **Critical** | Stok berkurang padahal transaksi gagal (Ghost Transaction) |
| 3 | API `/auth/api/` terbuka tanpa login | **Critical** | Kebocoran data pribadi (IDOR) & risiko penghapusan akun |
| 4 | Filter pendapatan `created__day` salah | **High** | Nominal pendapatan di dashboard salah total |
| 5 | Batas `max_digits=9` (Maks Rp 9,9 Juta) | **High** | Transaksi di atas Rp 10 Juta crash |
| 6 | Crash AJAX Laporan Penjualan | **High** | Tombol cari tanggal melempar `TemplateDoesNotExist` |
| 7 | Crash `UnboundLocalError` di Akun | **High** | Error 500 saat validasi form profil gagal |
| 8 | Biodata profil kasir tidak bisa disimpan | **Medium** | Form edit profil hanya mengupdate foto |
| 9 | Inkonsistensi ForeignKey User vs Profile | **Medium** | Potensi salah relasi kasir pada transaksi |
| 10 | Race condition stok multi-kasir | **Medium** | Stok minus jika 2 kasir transaksi di detik yang sama |
| 11 | Endpoint publik `/debug/` (1 / 0) | **Medium** | Risiko kebocoran stack trace sistem |
| 12 | Crash `StockUpload` (`imported_data.save()`) | **Medium** | Fitur import data Excel/CSV rusak |
| 13 | Deprecated `render_to_response` | **Low** | Inkonsistensi context rendering di Django |
| 14 | Timestamp `updated` tidak otomatis | **Low** | Riwayat waktu modifikasi transaksi tidak akurat |
