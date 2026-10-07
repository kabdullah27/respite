# Skrip Quick Launcher — Respite

Aksi cepat Respite dari launcher favoritmu, lewat skema URL `respite://action/<nama>`.
Respite harus sedang berjalan (menu bar). Semua aksi hanya MEMBUKA modul terkait —
tidak ada yang dieksekusi otomatis; Maintenance Sweep tetap minta konfirmasi di app.

| Aksi | URL |
|---|---|
| Monitor Memori | `respite://action/free-memory` |
| Diagnosis Performa | `respite://action/run-diagnostic` |
| Maintenance Sweep | `respite://action/maintenance-sweep` |

## Raycast
1. Buka Raycast → Settings → Extensions → Script Commands → Add Directly, atau
   import folder `raycast/` ini (Extensions → Import).
2. Pastikan Script Commands enabled. Ketik nama command-nya di Raycast.

## Alfred
1. Buat Workflow baru → tambahkan object **Keyword** (mis. `rkdiag`).
2. Hubungkan ke object **Open URL** dengan URL dari tabel di atas.
3. Ulangi untuk aksi lain yang mau dipakai.
