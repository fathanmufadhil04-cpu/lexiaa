# Lexiaa v8 — Runner + Character Shop

Update ini mengganti game Tap Rush menjadi endless runner.

## Fitur
- Karakter berbentuk unik dengan animasi.
- 1 karakter gratis + karakter lain dibeli memakai koin.
- Lari otomatis, lompat dengan tap layar/tombol.
- Rintangan makin cepat dan makin sulit seiring waktu.
- Koin muncul sepanjang perjalanan.
- Rekor berdasarkan waktu bertahan.
- Leaderboard 20 pemain teratas.
- Koin, karakter, dan rekor tersimpan per akun.
- AI Tools tidak lagi ditampilkan di APK.

## Setup Supabase
Jalankan `GAME-UPDATE.sql` sekali di Supabase SQL Editor. Script ini membuat/memperbarui RPC untuk koin, rekor runner, dan leaderboard.

Tidak perlu API key OpenAI untuk versi ini.


## v10
Fixed service-worker caching so the browser cannot keep serving the old v8 runner. Start button now only starts the run; jump is handled separately. Runner physics is additionally clamped for stability.


## v12 notes
- If avatar purchase previously showed `column "avatar_id" does not exist`, run `GAME-SHOP-FIX.sql` once in Supabase SQL Editor.
- Runner includes a lightweight procedural synth backsound using Web Audio, with an ON/OFF toggle. No external audio file is required.
<!-- Cloudflare deployment trigger -->
