# 12 Bağımsız kod incelemesi — mst-kod-inceleme (02.11.2026, kaynak 98222c5, salt okuma; komut çalıştırılmadı)
KRİTİK yok. Undo/operasyon: iç içe start_operation, kapanmayan işlem, çift commit, transparent işlemde koşulsuz abort bulunmadı.

| # | Önem | Yer | Bulgu |
|---|---|---|---|
| 1 | ORTA | main.rb:9579, 9549-9552, 9566-9568; ui.html:2182/2198/2218 | Bozuk rockfill_section_chain_json sessizce boş sayılıyor, ilk otomatik kayıtta guard'sız eziliyor (R-4 kapsam boşluğu) |
| 2 | ORTA | main.rb:7701-7708 | Kimlik Onarımı'ndan geçmiş kopya yeniden kopyalanınca progress_items_json taşınmıyor, durum 'Planlandı'ya çekilmiyor → hakedişte çift sayım (yeni anahtar/biçim: mimar kararı) |
| 3 | DÜŞÜK | main.rb:12496 | K59 iç beton rebar_t siliniyor; ADR "pursantaj değeri yazılır" diyor (metraj doğru; revizyon imzası değişir) |
| 4 | DÜŞÜK | dependency_rebuild.rb:57-62, 133-144 | Kaplama bağımlılık ağında; eski modelde ilk işlemde toplu dependency_* yazımı (uyumluluk notu) |
| 5 | DÜŞÜK | main.rb:11797-11798 | Sahiplik kaydı olmayan kopya Group→Component dönüşümünde kayıtlı sahip olabiliyor (mimar sorusu) |
| 6 | DÜŞÜK | main.rb:10706, mst_dwg_rebar.rb:568-589 | Araç çubuğu "donatıyı sil" yolunda R-4 reddi Türkçe ileti vermiyor |
| 7 | DÜŞÜK | main.rb:3685 | Bozuk pile_boq_group_codes_json, ayrı poz modu kullanılmasa da hakediş/keşif/fiyat kaydını engelliyor |
| 8 | DÜŞÜK, doğrulanamadı | main.rb:8482-8490 | Bazı kontrol adları sağlık kutularına bağlı değil |
| 9 | DÜŞÜK | main.rb:8649, 7728-7732 | stamp/repair her öğe için dependency_graph kuruyor (O(n²)); ölçülmedi |
| 10 | DÜŞÜK | main.rb:4430-4442 | K15 toplu yerleşimde begin öncesi istisnada Türkçe ileti yok (abort doğru) |
| 11 | DÜŞÜK, doğrulanamadı | mst_dwg_rebar.rb:384 | Paylaşılan Component BK'da çizimden donatı silme diğer örnekleri etkileyebilir |
| 12 | DÜŞÜK, doğrulanamadı | main.rb:9692-9694 | PID'siz eski revizyon kayıtlarında mükerrer UID anahtar çakışması |
| 13 | DÜŞÜK, doğrulanamadı | main.rb:2580 | K50 gömülmede sessiz rescue → 0; kazık/BK orijin varsayımı açık |
| 14 | Not | main.rb:10573 | universal_edit iletisi Kontrollü Düzenleme diyor; Parti C raporu metni düzeltilmeli |

İncelendi, sorun yok: R-1 revizyon, donatı geçmişi kırpması kaldırıldı, R-2 standardize, stamp_dependency_metadata tek işlem, K09 soru/işlem sırası, K63, K60, K11/K12 transparent işlem, R-5 (asıl UID yeniden üretilmiyor), G3, K24 (Ruby'de URI decode kalmadı), Parti E karşılaştırılan metinler ve VERSION kapsamı, Parti F.
