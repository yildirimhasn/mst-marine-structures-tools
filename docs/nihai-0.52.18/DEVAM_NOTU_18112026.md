# DEVAM NOTU — 18.11.2026 (GÜNCEL: AÇIK İŞ YOK)

## Güncel durum (18.11.2026, D2 sonrası)
**Açık iş yok.** Nihai RBZ üretildi, D2 (temiz profil kurulumu) GEÇTİ (kullanıcı beyanı).
- RBZ: `ADAY_PAKETLER\MST_v0.52.18_Fore_Donati_NIHAI_ADAY17.rbz`, SHA-256 `60242F69…CFC3`, 222 dosya.
- D2 çıktısı: `KOŞU 12 PASS: manifest=222 aynı=222 eksik=0 farklı=0 sürüm=0.52.18`.
- Kaynak kod: GitHub özel depo `yildirimhasn/mst-marine-structures-tools`, `master`, commit `4eebb75` (yerel: `sketchup-deniz-eklentisi\mst_tb1`; `src/` = RBZ içeriği, 222/222 SHA-256 aynı). `dist/` ve `*.rbz` .gitignore gereği depoda yok.
- Yedek: `MST_FINAL_140_140_KABUL` klasörü Drive'a kullanıcı tarafından yüklendi (yükleme tamlığı doğrulanamadı; Drive bağlayıcısı yetki hatası veriyor).
- Kurulu SketchUp profili asıl profile geri döndürüldü (`SketchUp 2020_TEST` = temiz profil denemesi).
- "140/140 geçti" DENMEZ; kapanış grup + kullanıcı beyanıyla. Bilinen sınırlar aşağıda ve CHANGELOG_05218.md'de.
- Yeni iş ancak kullanıcı isterse başlar (ör. kalıp düşümü / U-bar kg doğrulaması pafta gerektirir).

---
# Aşağısı: önceki not (arşiv)


## Nerede kaldık
**Nihai RBZ ÜRETİLDİ, yalnız D2 (temiz profil kurulumu) kaldı, kullanıcıda.**
- RBZ: `ADAY_PAKETLER\MST_v0.52.18_Fore_Donati_NIHAI_ADAY17.rbz`, SHA-256 `60242F69…CFC3`, 1.403.004 bayt, 222 dosya (kurulu ADAY17 ile 222/222 aynı). Kayıt: `PAKET_NIHAI_ADAY17.md`.
- Kurulu kod (dosya kopyalama): ADAY17 = main.rb A8086AA0, boq_pro.js E8982745, boq_resolver.rb 61A55712, structure_copy.rb 131E9034.
- Yedek klasörleri: KURULU_YEDEK_ONCESI_ADAY15/16/17. Keşif kütüphanesi yedekleri: MST_KABUL_KANITLARI\Kesif\lib_yedek_D1 (canlı ile aynı), lib_yedek_ana22k, lib_yedek_ana23.

## Yarın: D2 (kullanıcı yapar, ben izlerim)
1. SketchUp'ı kapat. `%APPDATA%\SketchUp\SketchUp 2020` klasörünü `SketchUp 2020_YEDEK` yap.
2. SketchUp'ı aç (temiz profil), Extension Manager > Install Extension > RBZ. SketchUp'ı kapat/aç. Menü, araç çubuğu, MST'ye ait Console hatası?
3. Console: `load 'C:/Users/yildi/Documents/MST_FINAL_140_140_KABUL/ADAY_PAKETLER/NIHAI_kaynak/kosu_12_temiz_kurulum_nihai.rb'` → beklenen `KOŞU 12 PASS: manifest=222 aynı=222 eksik=0 farklı=0 sürüm=0.52.18` (betik SketchUp'ta henüz çalıştırılmadı).
4. GERİ DÖN: SketchUp'ı kapat; `SketchUp 2020` → `SketchUp 2020_TEST`, `SketchUp 2020_YEDEK` → `SketchUp 2020`. (Keşif kütüphanesi %APPDATA%\MarineStructuresTools\BOQLibrary profilden ayrı, etkilenmez.)
Sonucu "D2 GEÇTİ / KALDI + çıktı" diye bildir.

## Kapanış durumu
Geçti (kanıtlı/beyanlı): kod+testler, BOQ golden-master (ADAY14/15/16, ADAY4 kopya BOQ, ADAY7 40/40), bağımsız incelemeler (ADAY4, 7, 9, 10–14), ekran kabulleri (K1–K4, C5, ADAY10–17), G-120 onaylı.
Bilinen sınırlar (CHANGELOG_05218.md): kalıp düşümü ve U-bar kg bağımsız doğrulanamadı (pafta yok); özgün kanal aralığı kaydı yok (karar A); ADAY4 bulgu 2/3 ve doğrulamaya PID kontrolü yapılmadı; Miktar Kaynağı listesi hafif kesik; arşiv dönemi etiketi ve Onaylı Metraj ÖBF-NN doğrulanmadı; D1/D2(arayüzden kayıt) atlandı.
Kapalı: runner 22 ("yok"), Fore 150 kg/m³ ("değiştirme").
Not: "140/140 geçti" DENMEZ; madde madde 140 satırlık liste yok, kapanış grup ve kullanıcı beyanlarıyla.

## Dersler
- Runner temizleme adımı yedek alınmadan hata verirse kütüphaneyi sildi (düzeltildi: ana_runner_23.rb, ana_runner_22k.rb).
- PowerShell 5.1 CreateFromDirectory ters eğik çizgi üretir; paketleme `paketle_rbz.ps1` (ZipArchive, '/').
- Ruby File.write Windows'ta LF→CRLF; satır sonu farkı 500+ satırlık sahte diff üretir, CRLF'yi geri yükle.
- `sha256sum` Windows yolunda baştaki `\` yazar; karşılaştırma için `sha256sum < dosya`.

## D2 SONUCU (kullanıcı beyanı, 18.11.2026)
D2 GEÇTİ. Temiz profil + Extension Manager kurulumu; Console: KOŞU 12 PASS: manifest=222 aynı=222 eksik=0 farklı=0 sürüm=0.52.18
(Paket: MST_v0.52.18_Fore_Donati_NIHAI_ADAY17.rbz, SHA-256 60242F69…CFC3.) Not: "140/140 geçti" denmez; kapanış grup + kullanıcı beyanıyla.
