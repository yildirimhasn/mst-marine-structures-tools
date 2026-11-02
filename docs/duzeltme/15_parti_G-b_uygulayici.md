# 15 Parti G-b — mst-uygulayici (02.11.2026; ADR 13 G4, G5, G6, G7 + 'ALL' kazık kapsamı)
Ana oturum doğrulaması: 34 test dosyası 0 kalan; ruby -c 66/66; r25check failures=0; check_inline_js 20/20; check_chromium64 hits=0; golden 7e2e9c7 ↔ yeni: eski=425 yeni=432 aynı=400 farklı=45 beklenmeyen=0. Ajan: yeni g4/g5/g6/g7/g_all testleri 7e2e9c7'de kalıyor. SketchUp'ta denenmedi.

G4: bordür donatısı Keşif REBAR'da (hacim × rebar_rate('deck')); K34 notu; DS2 döşeme + ayrı bordür Model Kontrolü UYARISI. Fikstür: REBAR +0,315 t; hakediş önceden onaylı bordür +0,18 t (previous_* değişmez).
G5: mst_qto_detail_rows (Excel ile ortak; Ayrıntılı Metraj farkı 0) + mst_boq_csv_rows; CSV 8 sütun + Donati_t; Celik_t = boru çeliği; 'Keşif ek kalemi' satırları; Kategori sütunu tür anahtarı (uyumluluk); fore kazık satırları eklendi. g5: ΣDonati_t=REBAR, ΣCelik_t=PILE_STEEL, BK net, iç beton=PILE_INFILL.
G6: pano/Excel Toplam Beton + kaplama (fikstür 126,8193 → 134,6693), KAPLAMA kırılımı, Excel "Beton Kaplama (sınıf)"; qto3_snapshot değişmedi. Sınırı: sınıfı '-' olan öğe varsa sınıf satırları + kaplama ≠ toplam.
'ALL': mst_resolve_pile_targets 'ALL' → tüm BIM kazıkları; ui.html seçenek "Projedeki tüm kazıklar" (varsayılan ACTIVE); diğer değerler değişmedi.
G7: grafik bir kez — stamp n=200: 201 → 2 çağrı (0,537 → 0,026 s); repair n=209: 417 → 2 (1,140 → 0,013 s); son durum imzaları birebir. Ara '2.1' yazımı kaldırıldı; işlem sonu öznitelikleri aynı.
Golden fikstürü genişletildi (eski tip döşeme + bordür, DS2 + bordür, kopyanın kopyası, hakediş kayıtları; CSV, Excel Özet/Ayrıntılı Metraj, REBAR izlemesi, hakediş bölümleri).
Açık: 0514 kural seti genişletilmiş fikstürle çalıştırılmadı (golden_872d3a3.csv üzerine yazılır); CSV "Kazık içi donatı" ek satırı testsiz.
SketchUp kabul: ÖBF-004 artışı = bordür hacmi × 150/1000; K34 metni; DS2 + bordür uyarısı; CSV 9 sütun ve toplamlar; Toplam Beton kaplama dahil; "Projedeki tüm kazıklar" sayı = model kazık sayısı, tek Ctrl+Z; Kimlik Onarımı / Bağımlılık Motoru hızı.
