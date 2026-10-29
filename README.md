# Narto Drama TV - Android TV Edition

Aplikasi Android TV khusus untuk streaming short drama dari agregator Narto Drama (56 provider termasuk DramaBox, ReelShort, ShortMax, Sereal+, Melolo, BibiShort, FlickPulse, dll).

Didesain dari awal untuk pengalaman 10-foot widescreen TV, navigasi penuh remote D-pad, dan rendering video hardware ultra-ringan.

---

## Fitur Utama

- **Navigasi Penuh Remote D-Pad (10-Foot Experience)**:
  - Antarmuka widescreen 16:9 landscape dengan respons instan tombol arah (Atas, Bawah, Kiri, Kanan, OK/Center, Back).
  - Indikator fokus interaktif: Card drama dan tombol remote membesar (scale 1.05x) dengan efek border crimson glow (`#FF2D55`).
  - Auto-scroll otomatis menjaga item yang sedang difokuskan tetap berada di area pandang utama.
- **6 Tab Navigasi Utama**:
  - **Beranda**: Banner rekomendasi dan baris horizontal section drama terpopuler per provider.
  - **Provider**: Eksplorasi 56 provider drama dengan fitur sinkronisasi daftar provider upstream otomatis & manual.
  - **Riwayat**: Lanjutkan menonton episode terakhir yang belum selesai dengan progres waktu tersimpan.
  - **Favorit**: Akses cepat daftar drama yang telah ditandai/dibookmark.
  - **Pencarian**: Pencarian drama instan menggunakan virtual keyboard TV.
  - **Pengaturan**: Konfigurasi cache gambar, ukuran subtitle TV, dan informasi sistem.
- **Pemutar Video Khusus Layar TV**:
  - **Kontrol D-Pad Intuitif**:
    - **Kiri / Kanan**: Lompat cepat mundur/maju 10 detik.
    - **Tengah (OK / Center)**: Toggle Play / Pause instan tanpa flicker.
    - **Bawah**: Buka laci cepat daftar seluruh episode (horizontal drawer) tanpa menghentikan pemutaran video.
    - **Tombol Subtitle**: Toggle aktif/nonaktif takarir WebVTT langsung dari remote.
  - **Visualisasi Cache Buffer di Timeline**:
    - Timeline multi-tier (Base Track abu-abu, Buffer Track putih semi-transparan, Play Track merah crimson).
    - Memudahkan mengetahui apakah buffering/stutter disebabkan oleh jaringan upstream atau performa pemutar.
  - **Anti-Glitch Hardware SurfaceTexture Rendering**:
    - Menggunakan backend `video_player_android: 2.7.1` murni hardware OpenGL ES SurfaceTexture.
    - Bebas green frame (0 YUV glitch) saat pause dan resume.
    - Kompatibilitas tinggi dengan GPU Mali, PowerVR, dan Amlogic pada Android TV / Google TV.
- **Sinkronisasi Provider Dinamis**:
  - Menarik pembaruan provider baru dari server upstream secara otomatis atau manual via tombol di Tab Provider & Pengaturan.

---

## Spesifikasi & Kompatibilitas

- **Target Device**: Android TV 9.0+, Android TV 10, Google TV, Android Box, Mi TV Stick, Xiaomi TV.
- **Arsitektur CPU**: `armeabi-v7a` (32-bit TV standar seperti Xiaomi Mi TV A2 55") & `arm64-v8a` (64-bit TV).
- **Launcher**: Standar Android TV Leanback Launcher (`android.intent.category.LEANBACK_LAUNCHER`) dengan banner 320x180 px (`@drawable/banner.png`).

---

## Unduh Biner Rilis (v1.0.0)

Unduh paket rilis resmi dari tab [Releases v1.0.0](https://github.com/raiwidartha/narto-drama-tv/releases/tag/v1.0.0):

- **[narto-drama-tv-v1.0.0-armv7.zip](https://github.com/raiwidartha/narto-drama-tv/releases/download/v1.0.0/narto-drama-tv-v1.0.0-armv7.zip)** (Rekomendasi Xiaomi Mi TV A2 55" / MiTV-MOOQ1 / Android TV 32-bit)
- **[narto-drama-tv-v1.0.0-arm64.zip](https://github.com/raiwidartha/narto-drama-tv/releases/download/v1.0.0/narto-drama-tv-v1.0.0-arm64.zip)** (Android TV / Google TV 64-bit)
- **[narto-drama-tv-v1.0.0-apks.zip](https://github.com/raiwidartha/narto-drama-tv/releases/download/v1.0.0/narto-drama-tv-v1.0.0-apks.zip)** (Paket lengkap seluruh ABI)
- **[Direct APK armeabi-v7a](https://github.com/raiwidartha/narto-drama-tv/releases/download/v1.0.0/narto-drama-tv-v1.0.0-armeabi-v7a.apk)**
- **[Direct APK arm64-v8a](https://github.com/raiwidartha/narto-drama-tv/releases/download/v1.0.0/narto-drama-tv-v1.0.0-arm64-v8a.apk)**

---

## Cara Instalasi via ADB Nirkabel

1. Aktifkan **Opsi Pengembang (Developer Options)** dan **USB Debugging / Wireless ADB** di menu Pengaturan Android TV Anda.
2. Hubungkan PC ke TV via ADB:
   ```bash
   adb connect <IP_TV>:5555
   ```
3. Pasang APK rilis:
   ```bash
   adb install -r app-armeabi-v7a-release.apk
   ```

