LEXIAA ADMIN PANEL

1. Buka Supabase > SQL Editor.
2. Jalankan isi ADMIN.sql.
3. Di bagian BOOTSTRAP ADMIN, ganti EMAIL_ADMIN dengan email akun Lexiaa milikmu.
4. Hilangkan tanda -- pada dua baris INSERT bootstrap, lalu Run.
5. Deploy seluruh isi folder ini seperti biasa.
6. Buka /admin.html untuk masuk ke Admin Panel.

Fitur admin:
- melihat semua akun terdaftar + email/nama/username
- klik akun untuk melihat foto dan memutar musik
- melihat saldo koin, avatar aktif, avatar terbuka, dan rekor runner
- menambahkan koin lewat RPC admin yang memeriksa role admin

Keamanan:
- Pengguna biasa tidak diberi akses baca lintas akun melalui RLS.
- Admin ditentukan lewat tabel public.admin_users.
- File foto/musik/avatar tetap private; admin mendapat signed URL hanya setelah lolos is_admin().
