# 16 Kabul denetimi — mst-kabul-denetim (02.11.2026; kaynak eaaa858, paket 454daf8e…167bbe; salt okuma)
Ajan incelemesidir, kullanıcı onayı değildir. SketchUp içi kabul ve görsel kanıt yok.

## Hedef sonuçları
| # | Hedef | Sonuç | Gerekçe |
|---|---|---|---|
| H1a | Doğrulanan bütün hataları gider (29.10) | kısmen | 63 K bulgusunun tamamının izi var; Undo/Component/observer/skp: davranışları SketchUp kabulü ister; K22 aşama 2 açık |
| H1b | Eksikleri tamamla | kısmen | K33/K39/K40 poz eşlemesi, tapa/derz tarifi belge bekliyor; K44 belge yok |
| H1c | Uygulanabilir iyileştirmeler | kısmen | B'nin 6 ayrı önerisi, A2'nin 2 maddesi, K32 açık |
| H1d | Kuruluma hazır RBZ | kısmen | Paket bütünlüğü statik kanıtlı; SketchUp 2020 kurulumu yapılmadı; runner sürüm/SHA kontrolleri beklenen şekilde başarısız |
| H2a | 0.51.5 çekilsin | karşılandı | MST_BUILD, VERSION, rozetler |
| H2b | Her şey Türkçe | kısmen | Bilinçli istisnalar (araç çubuğu adları, creator, saklanan grup adları, katalog/aksesuar değerleri, SketchUp terimleri) kullanıcı onayı bekliyor; README arşiv başlığı İngilizce |
| H3a/b | Excel çift satır / tanımsız JS | kısmen | Sahte nesne kanıtı; SketchUp'ta doğrulanmadı |
| H4a | Kod inceleme bulguları | kısmen | 14'ten 13'ü işlendi; #3 K59 gerekçeli uygulanmadı, ADR 02 §6 kaydı eksik |
| H4b | Kopya hakediş | kısmen | g1 testi; SketchUp adımı yok |
| H4c | Metraj A–D | kısmen | Fikstür kanıtı (g4/g5/g6, golden beklenmeyen 0) |
| H4d | Kazık İçi Beton yazımı | karşılandı (kaynak metni) | src içinde "Kazık İçi Betonu" 0 |
| H4e | Tüm kazıklar kapsamı | kısmen | g_all testi; sayı ve tek Ctrl+Z SketchUp ister |
| H4f | Tüm önerileri yap | kısmen | Önceki partilerin ayrı önerilerinin bir kısmı açık |
Genel: kısmen karşılandı.

## Boşluklar
- DÜZELT olup izi olmayan K bulgusu yok. Raporu eksik: K47 (D), G arayüz partisi c39c52c. K40/K23 ara çözüm olarak sınıflanmalı.
- K43 terim sorunu değil: aks organizasyonu / elle aks işlevlerine (main.rb:9199, 9278) erişim sorunu; hiçbir partide açılmadı — açık.
- K30 ölü kod (gizli pile_mfg_edit paneli, kullanılmayan callback'ler, drillingEditorToken): "tüm önerileri yap" silme onayı sayılmaz (CLAUDE.md üç koşulu) — açık, kullanıcı kararı.
- K32 (ui.html:325 inset/min()) açık. K49 yalnız bağımlılık grafiği kısmı yapıldı. Menfez–gömülme kesişimi uyarısı yapılmadı. DXF birimi tanımsızken iki varsayılan (m/cm) açık. 08 R7, sarmalayıcı Component ×N, v034 tretuvar köşe bindirmesi triage'a girmedi.
- B ayrı önerileri açık: VK temas BK formwork rescue nil, boq_pro.rb:376 send_boq hatası yalnız puts, mst_schedule.rb:274 ve mst_v50_piles.rb:459 işlem dışı yazım, U6 okuma işlevlerinin yazması, element_visible_id kaplama. A2: K35 performansı, kafes yönelimi değişince açıklık. C: mstLoadCommonPileForm boş değer.
- Golden: uçtan uca 0.51.4 ↔ son karşılaştırma yok (CSV/Excel/hakediş bölümlerinin 0.51.4 karşılığı yok); fark CSV'sinde eski_0514 sütun adı yanıltıcı.
- Belgeler: 07 §1/§4/§6 eskimiş; 08'de E/F/G-a/G-b ve bazı A2/B adımları eksik.

## SketchUp kabul önceliği
1 kurulum + runner; 2 golden (0.51.4 ↔ 0.51.5 CSV, Ayrıntılı Metraj, Özet); 3 kritik metraj (K36, K50, K22, K58, K57, K59, K35, K33); 4 veri/kimlik (revizyon, G1, K04/K05, bozuk JSON, pid'siz revizyon); 5 paylaşılan tanım (K09, G3-#11); 6 Undo; 7 Model Kontrolü; 8 arayüz; 9 DXF birimi ve performans.

## Kullanıcı kararları
1 ölü kod silme; 2 K43 aks işlevleri; 3 K32 yedek CSS; 4 Türkçe istisnaları; 5 K59 mevcut davranış + ADR düzeltmesi; 6 B/A2 açık öneriler; 7 belgeler (poz eşlemesi, fiyat farkı, tapa, derz, R4, REBAR_DEFAULTS, bordür oranı, DXF varsayılanı, K22 aşama 2, K10); 8 davranış değişiklikleri (CSV 9. sütun, Excel sayfa adları, G4 hakediş etkisi); 9 0.51.5 runner.
