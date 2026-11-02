# 06 Parti C — mst-arayuz-tr (iki oturum: 30.10 kesildi, 02.11 tamamlandı)
Ana oturum doğrulaması (02.11.2026): 7 dosya +96/−59; ruby -c main.rb, pile_manufacturing.rb, quantity_service.rb, boq_pro.rb Syntax OK; node --check mst_workflow.js, boq_pro.js OK; ui.html satır içi 11 betikten 10'u OK, 1'i HEAD'de de aynı biçimde FAIL (çıkarma yöntemi: iç içe `<script>` dizgisi); src içinde `skp:` = 0; A1/A2/B 17 sahte nesne testi 0 kalan; r25check files=66 failures=0. SketchUp'ta denenmedi.

## Bulgular
| ID | Değişiklik | Durum |
|---|---|---|
| K24 | ui.html 20 `skp:` → `sketchup.<ad>()`; mst_workflow.js eşleştirme dizgeleri; loadRockfillState açılışta alternatif göndermez (K24 sonrası istenmeyen '01' yazımı/Undo adımı önlendi) | SketchUp testi bekliyor |
| K25 | main.rb crownAxisError JSON.generate | SketchUp testi bekliyor |
| K01 | Eleman Düzenleyici 5. kart "Kontrollü Güncelleme" (ui.html:1087): "✓ Seçili Elemanın Etkisini Önizle" yalnız editor_preview çağırır, modele yazmaz; not, güncelleme için Proje Çalışma Alanı → Elemanı Düzenle düğmesini (BK / normal ve kanal prekast → Kontrollü Düzenleme paneli, kazık → kazık paneli) gösterir; "Bu Tipteki Tüm Elemanları Güncelle" pasif. universal_edit callback adı korunur (main.rb:10573), ui.html'den çağrılmaz; çağrılırsa model değişmeden "Bu düzenleme yolu bu sürümde desteklenmiyor; seçili eleman için Kontrollü Düzenleme panelini kullanın." iletisini verir (update_selected_element yok; yeni yazma yolu kapsam dışı). Metin 02.11.2026 kod inceleme #14 ile koda uyduruldu | SketchUp testi bekliyor |
| K31 | show_boq_engine `mstShowPage('boq')` | SketchUp testi bekliyor |
| K48 | BIM Data Core iletisi; quantity_service.rb Türkçe hata metni | düzeltildi |
| K42 / 08-R1 | updateDrivingAuto kot silinince alanı temizler + not; boş kot/0 m kaydında onay | SketchUp testi bekliyor |
| K37 | pile_manufacturing.rb önizleme pile_fabrication_qto_row'dan okur | SketchUp testi bekliyor |
| K08 | Pano: ayrı Kaplama satırı, DOSP'tan kaplama çıkarıldı (yalnız gösterim) | düzeltildi |
| K41 | Boru çeliği / donatı / dolgu ayrı sütun (qQTO3 8 sütun, Detailed QTO 10 sütun) | düzeltildi; BOQ değişmez |
| K33/K39/K40 | setBOQ info_only satırları "BİLGİ", fiyatsız, toplam ve eşleme sayısı dışı | düzeltildi |
| K38 | renderIcmal '!' satırı tek uyarı satırı | düzeltildi |
| K34 | Hakediş REBAR warning notu görünür; kırmızı yalnız negatif dönem | düzeltildi |
| G3 | Hesap Hatası grubu Ruby HTML'inde; JS değişikliği gerekmedi | gerek yok |
| K30 | Dokunulmadı (ölü kod silinmez, çağıran yok) | uygulanmadı |
| K32, K43, K44 | iş tanımı gereği | uygulanmadı |

## Kapsam dışı (metraj-kontrol / ayrı öneri)
- main.rb ~8941/8964: type_names 'Kazık İçi Betonu' ↔ silme koşulu 'Kazık İçi Beton' — Detailed QTO'da çift satır olasılığı; HEAD'de doğrulanmadı.
- ui.html ~1707 mstLoadCommonPileForm boş değeri forma yazmıyor; önceki kazığın kotu kalabilir.
- ui.html ~1965 drillingEditorToken kullanılmıyor; silinmedi.

## SketchUp kabul adımları
Ajan raporundaki 11 adım: BOQ bilgi satırları ve toplamın 0.51.4 ile aynılığı; Hakediş REBAR notu; icmal '!' satırı ve kayıtta hesaba girmemesi; Kronman aks oku; Dolgu Alt-02 açılışta korunur ve Undo adımı oluşmaz; Seçili Eleman Bilgisi/Element Library/Excel/CSV/Model Kontrolü düğmeleri; Eleman Düzenle önizleme; eski menü Keşif/BOQ Engine; kazık formu kot/çakım; Kaplama satırı ve sütunlar, Detailed QTO 10 sütun; VAR/YOK önizleme = Kazık QTO.
