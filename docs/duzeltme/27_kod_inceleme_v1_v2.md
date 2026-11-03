# 27 Kod incelemesi — b0a2592 + 0983966 (mst-kod-inceleme, 03.11.2026; salt okuma, test çalıştırmadı)
Kapsam: rapor 25/26 bulgu düzeltmeleri (b0a2592) ve prekast NCR-003 + Kontrollü Düzenleme tip adı (0983966).
İncelenmeyen: show_boq_engine, Model Kontrolü iletileri, mstBKAddProjectStructure, mst_pageflow.js topSections (ajan beyanı).

| # | Önem | Yer | Bulgu | Ana oturum sonucu |
|---|---|---|---|---|
| K1 | ENGELLEYİCİ (ajan) | main.rb mst_axis_manager_names_plan | `removed` ham sistem listesinden; sızmış eski kod (DOLFEN'de ANO-01) onaylanamaz silme hatası verir | Senaryo bu yolda oluşmuyor: Aks Yöneticisi açılışı listeyi süzüp yeniden yazıyor (sahte nesne denemesi). Savunma düzeltmesi yapıldı: `removed` yalnız `mst_structures_for_system` ile görünen kodlardan. Test 27/K1 |
| K2 | ORTA | controlled_editor.rb precast_type_after | tip adı yokken `precast_id` (fiziksel kimlik) üzerinden ad üretiliyor | Düzeltildi: yalnız kayıtlı `precast_type_id` varsa ad güncellenir. Test T5. BK boyutlandırma yolunda aynı geri düşüş bugün de var — değiştirilmedi (ayrı karar) |
| K3 | ORTA | controlled_editor.rb | mm altı değişiklik (ölçü anahtarı aynı) yeni tip adı açabiliyor | Düzeltildi: yeni ölçü anahtarı eskisiyle aynıysa ad değişmez. Test T6. Tek örnekli tipin eski ölçüye geri dönüşünde eski ada dönmeme davranışı BK yolu kuralıyla aynı, değiştirilmedi |
| K4 | ORTA | main.rb mst_code_usage_extra | Aks Yöneticisi her açılışta element_type'sız grup / bileşenlerin içine iner | Ölçüm yok; sonsuz özyineleme riski yok (tanım bir kez). Kabul listesine büyük modelde açılış süresi ölçümü eklenecek |
| K5 | NOT | main.rb hedef kod denetimi | sunucu birebir, JS harf farksız | Düzeltildi: sunucu da `mst_name_key` ile karşılaştırır. Test 27/K5 |
| K6 | NOT | JS checkCode ↔ MST_CODE_CHAR | büyük/küçük harfi olmayan harf, birleşik işaret, 0-9 dışı rakamda JS reddeder Ruby kabul eder | Değiştirilmedi: son denetim sunucuda, veri bozulmaz; yalnız ileti farkı (bilinen sınır) |

Sorun bulunmayan (ajan): Undo (plan yazmaz; apply yazımları start_operation sonrası, hatada abort), fingerprint kapsamı, BK boyutlandırma yolunda `dims=nil` ile eski anahtar, Prekast sayfası alt sekme görünürlüğü, ağaç anahtarı build/reveal tutarlılığı, Ruby 2.5 / Chromium 64.
Ek (rapor 28): tip adı kaydı artık `collect_elements` kapsamından (BK yoluyla aynı, iç içe prekast dahil).
