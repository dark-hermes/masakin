# Flowchart Sistem Ringkas - MasakIn

Diagram berikut menampilkan alur utama aplikasi yang berfokus pada deteksi bahan makanan dan rekomendasi resep.

```mermaid
flowchart TD
  Start((Start)) --> Capture[Ambil atau pilih gambar]
  Capture --> Preprocess[Preprocessing gambar]
  Preprocess --> Detect[Deteksi bahan YOLO - TFLite]
  Detect --> NoDetect{Bahan terdeteksi?}
  NoDetect -->|Tidak| Capture
  NoDetect -->|Ya| Extract[Ekstrak daftar bahan]
  Extract --> Gemini[Prompt ke Gemini API]
  Gemini --> Recipes[Generative AI: Rekomendasi resep]
  Recipes --> Display[Tampilkan resep & info nutrisi]
  Display --> Save[Simpan resep opsional]
  Save --> End((Selesai))

  classDef mono fill:#ffffff,stroke:#000000,color:#000000;
  class Start,Capture,Preprocess,Detect,NoDetect,Retry,Extract,Gemini,Recipes,Display,Save,End mono;
```

Ringkasan:
- Ambil gambar → preprocessing → jalankan model YOLO untuk mendeteksi bahan.
- Jika tidak ada bahan, user dapat mengambil ulang gambar.
- Jika ada bahan, ekstrak daftar bahan lalu kirim ke Gemini untuk menghasilkan rekomendasi resep.
- Tampilkan hasil dan beri opsi menyimpan resep.

File ini mengabaikan splash screen dan onboarding, hanya menampilkan fitur utama sesuai permintaan.