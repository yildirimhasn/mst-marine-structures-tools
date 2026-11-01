# 10 Parti F — mst-uygulayici (02.11.2026; kullanıcı talimatı "ikisini de düzelt")
Ana oturum doğrulaması: 22 sahte nesne testi 0 kalan (a1/a2/b/c/f); ruby -c 66/66; r25check failures=0. SketchUp'ta denenmedi.

F1 — Ayrıntılı Metraj (Excel) iç beton çift satırı: main.rb export_professional_excel type_names adı 'Kazık İçi Beton'; reject koşulu `row[0]==type_names['pile_infill_concrete']`. Test f1_infill_excel: yeni 6/0, f7046b5 1/5 (2 satır, 35,377 m³). Golden f7046b5 ↔ yeni 321/321 aynı (golden Excel Ayrıntılı Metraj sayfasını kapsamaz). Metrajı değiştirir: yalnız bu sayfa. Eleman Kütüphanesi sayfasındaki ad da "Kazık İçi Beton" olur.

F2 — Tanımsız JS işlevleri (loadSelectedBimPile, setDrillingEditor, drillingEditError): mevcut Kazık sayfası iki işi karşılıyor (ui.html:431/435 "Modelden Seçili Kazığı Yükle" → pile_load_selected_for_edit; foraj alanları + "✓ Mevcut Kazığı Güncelle" → pile_target_apply, tek işlem). main.rb:10406 ve pile_drilling.rb:74/76 çağrıları `typeof` korumalı; işlev yoksa dialog içinde Türkçe yönlendirme (alert — Ruby, execute_script sonucunu okuyamadığı için). Callback'ler ve Ruby yöntemleri silinmedi. Test f2_guarded_js yeni 9/0, f7046b5 4/5; c_callbacks 23/0.

Açık (kullanıcı kararı): eski foraj düzenleyicisinin "Projedeki tüm kazıklar" kapsamı; gizli pile_mfg_edit paneli ve kullanılmayan callback'ler için ölü kod değerlendirmesi; main.rb:4192 ve unified_catalog.json'daki "Kazık İçi Betonu" yazımı.
SketchUp kabul: Excel Ayrıntılı Metraj'da tek "Kazık İçi Beton" satırı = Keşif ÖBF-010; Kazık sayfasında seçili kazık yükle → foraj değiştir → güncelle → tek Ctrl+Z.
