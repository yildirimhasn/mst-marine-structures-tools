# 05 mst-arayuz-tr raporu (salt okuma)
215 execute_script çağrısı (28 rb), ~150 benzersiz JS adı tarandı: 3 tanımsız.

## Doğrulanmış hatalar
- B1 arayüz etkisi: onay metni "UID korunacak ve işlem tek Ctrl+Z ile geri alınabilecektir. Uygulansın mı?" → Tamam → NameError yalnız Ruby Console'da; arayüzde mesaj yok, model değişmez; her denemede sessiz başarısızlık. Çalışan alternatif: Kontrollü Eleman Düzenleme paneli (controlled_editor.js).
- A1 (Düşük, gizli): main.rb:9970 loadSelectedBimPile, pile_drilling.rb:74 setDrillingEditor, :76 drillingEditError JS'de tanımsız; yalnız çağrılmayan callback'lerden (pile_load_selected_bim, drilling_edit) tetiklenir.
- A3 (Düşük): main.rb:9571 show_boq_engine sekmeyi 'Keşif / BOQ' metniyle arıyor; mst_workflow.js:59 metni "BOQ / Hakediş" yaptığından sekme bulunmaz; eski menü "Keşif / BOQ Engine" BOQ sayfasına geçmez, mesaj yok.

## R1 (skp:) ayrıntı
- Gerçek skp: yönlendirmesi 20'si de ui.html'de: 9 onclick (702, 745, 1082×2, 1168, 1169×4) + 11 işlev (2180-2238). 02'ye düzeltme: mst_workflow.js:148-161'deki 'skp:' dizgeleri yönlendirme değil, onclick eşleştirme parçası.
- Başka yoldan da erişilenler: model_audit (mst_workflow.js:83), element_library / export_professional_excel / export_boq_csv (Model Bakımı maint_action main.rb:9741-9748).
- YALNIZ skp: ile erişilenler: element_info, kronman (crown_axis_info, create/load/update_crown_wall), eski Alternatif-01 dolgu sayfası (rockfill_load/save/autosave_*, rockfill_axis_info).
- skp: çalışmazsa: kronman "Aks okunuyor..." metni kalır, oluştur/güncelle geri bildirimsiz; Alt-01 her açılışta varsayılanla başlar, otomatik kayıt kaybolur. URL çözülmezse JSON.parse hatası (kronman messagebox; autosave yalnız puts).
- autoSaveRockfillLibrary ve autoSaveRockfillProject aynı 250 ms'de art arda window.location atıyor (ui.html:2185,2188,2189) → ikincisi birincisini iptal edebilir.

## Chromium 64 (SU2020) CSS
- gap: flex ~105, grid ~73 satır (mst_workflow.css 17, ui.html ~59, engineering_ui.css 7, project_workspace.css 4, gömülü html, main.rb 7). Ön ekli olmayan gap grid'de Chromium 66+, flex'te 84+ → Chromium 64'te boşluklar 0; işlev bozulmaz. Olası risk, SketchUp testi.
- ui.html:325 .pile-ov-backdrop inset:0 (87+) + width:min(720px,96vw) (79+) → kazık özel ayar penceresi ortada açılmayabilir/görünmeyebilir. Olası risk (işlevsel), SketchUp testi.
- :focus-visible engineering_ui.css:13, accent-color :9, CSS max() main.rb:4172 — Düşük.
- JS: Chromium 64 sonrası özellik bulunmadı.
- Gömülü srcdoc sayfalarda göreli src/href çözümü — SketchUp testi.
- ui.html:2071 display:block ↔ qto_workspace.js:61 hidden → boş hata kutusu kalabilir (Düşük).

## Türkçe / terim
İngilizce menü öğeleri main.rb:10241, Model Bakımı 9680-9689 ("Project / Ano / Axis Manager", "BIM Data Core / Element Library", "Dependency Engine", "Metraj / QTO Engine 3.0", "Model Audit 4.1d / Engineering QA", ...); ui.html:373 "DESIGN • MODEL • TAKEOFF"; 1082/1169 "Element Library", "Professional QTO / Excel"; "Average End Area" (1053-1054,1162,2197; mst_pageflow.js:40); "Model Kontrolü (Audit)". quantity_service.rb:72 "Kazik kesiti veya boyu gecersiz." kullanıcıya görünür. Bordür/Tretuvar (ui.html:952/958/1954, quantity_source.js:6); Kaplama/Topping (969,1099); "çakma" mst_schedule.rb:14. Terim seçimi dokümantasyonla.
Sürüm gösterimi: pencere başlığı/şerit v0.51.4; Excel/keşif "v0.51.4 TB1 RUBY25"; README 0.36.7. Eleman revision alanına bazı araçlar VERSION, bazıları 'v0.20.0' yazıyor.

## Veri kaynağı
Model Kontrolü MSTQuantitySource ile durum/yöntem/kaynak gösteriyor (sorun yok). Metraj ana sayfa/kazık tablosunda satır bazında kaynak/tahmin işareti yok (Eksik özellik). BOQ: donatı Kaynak sütunu (BIM ↔ pursantaj) var; elle poz ayrımı var; beton/kalıpta tahmin işareti yok.

## Eksik
QTO/BOQ satırında kaynak/tahmin etiketi; foraj düzenleme arayüzü; 7 TB1 aracı ayrı pencere.
