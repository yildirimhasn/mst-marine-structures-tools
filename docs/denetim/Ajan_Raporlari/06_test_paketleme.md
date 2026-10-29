# 06 mst-test-paketleme raporu
Değişiklik yok (src/dist/tools/depo/RBZ/pkg/kurulu klasör); çıktılar out\tests\. Ana oturum `git status --short` boş olduğunu teyit etti.

## Statik (hepsi çıkış 0, hata 0)
SHA-256 aynı; unzip -t "No errors detected"; 201 kayıt (yükleyici + klasörde 200 dosya; ön kontroldeki "klasörde 201" 1 fazla); yol sorunu 0; pkg↔zip↔kurulu 201/201; ruby -c 66; Ruby 2.5 dilbilgisi 0 hata; node --check 13; JSON 7/7 (BOM yok); gömülü <script> 27 blok (html 21, Ruby 6) node --check hata 0; Chromium 64 JS kalıpları 0. Manifest out\tests\manifest_0514.txt.

## Kurulu runner 1.1.0 uyumlu
EXPECTED_VERSION 0.51.4 / BUILD 'v0.51.4 TB1 RUBY25' eşleşiyor; expected_sources.json 201/201; özellik işaretleri var; giriş noktaları tanımlı. Kapsam: yükleme, sürüm, SHA, RubyVM derlemesi, saf hesap; B1/H1/Undo/geometri/arayüz kapsamında değil. Gerçek Ruby 2.5 derlemesi yalnız runner menü 1 ile (kullanıcı çalıştırır).

## Sahte nesne testleri
- H1 t_h1_snapshot.rb → çıkış 1, "3 geçti, 3 kaldı": 21. kayıtta Rev.01 silinir; 22. kayıt da "Rev.21" (yinelenen ad); 20'de boq eklenmez; her snapshot 3 ayrı set_attribute. Doğrulanmış hata (sahte nesne düzeyi).
- .then kaldırımı t_qs_then.rb → çıkış 0, 16 aynı/0 farklı; Ruby 2.5 benzetiminde eski kod 3 durumda invalid, yeni doğru; dal tam pakette normalde etkisiz. Sorun yok.
- filter_map→map.compact t_filter_map.rb → çıkış 0, 3/3; false çıktısı yok. Sorun yok.
- Depo testleri (0.52.0-dev1 içindir): 09-test.rb çıkış 1 (TypeError), 10-test.rb çıkış 1, 10-form-test.js "5 geçti, 2 kaldı" → G1.

## Doğrulanmış hatalar
- H1 (Yüksek) yukarıda.
- G1 (Orta, sahte DOM): ui.html updateDrivingAuto — deniz tabanı kotu silinince otomatik çakım boyu (20,50) alanda kalır, uyarı yok; bayat değer kaydedilirse çakım boyu metrajına geçebilir. SketchUp testi.

## Olası riskler
- quantity_service.rb:78 :steel_t kazık dışı elemanda donatıyı döndürür; main.rb:3305,3321, ui.html:2038 "Çelik Tonajı" toplamı boru çeliği + beton donatısını birleştirebilir (0.51.3'te de var) → metraj-kontrol.
- Plugins'te ayrı kronman_duvari_olusturucu eklentisi kurulu; etkileşim incelenmedi.
- Performans: her işlem kaydında (MST dışı dahil) dependency_rebuild.rb:149 tam collect_elements + grafik; dependency_graph prekast×döşeme döngüsü, children[a].include? → O(n²) eğilim; değişiklik varsa ikinci transparent kayıt + çalışma alanı tam yenileme (project_workspace.rb:170, 80 ms, pencere görünürken); ProjectWorkspace.entries MST olmayan grupların içine iner; collect_elements main.rb'de 70 çağrı; döngüde JSON.parse main.rb:5536.

## Eksik
Golden-master betiği/CSV yok; 0.51.3/0.51.4 sürüm notu yok.

## Performans ölçüm planı
3 model kopyası (~0, 200, 1000+ MST öğe); Ruby Konsolu'nda dependency_changes, ProjectWorkspace.entries, collect_elements süreleri 5 tekrar medyan; çalışma alanı açık/kapalı tek çizgi gecikmesi.

## SketchUp kabul listesi taslağı (24 madde)
1 yükleme/Ruby 2.5 konsol; 2 runner menü 1 (fail 0); 3 runner menü 2; 4 kontrollü BK düzenleme + tek Ctrl+Z; 5 health_history karşılaştırma; 6 golden-master BOQ CSV + Excel (referans 0.51.3 Integrated, olmazsa 0.51.2 TB1); 7 B1; 8 H1/H9 21-22 snapshot + Ctrl+Z sayısı; 9 H2/H7 Element Library öncesi/sonrası attribute dökümü; 10 R1 kronman + Alt-01 autosave; 11 H3/H8 Ctrl+Move döşeme+tretuvar; 12 H5/S1 çok örnekli Component BK menfez; 13 U1 kalıp aracı Ctrl+Z; 14 U2 DXF aks ızgarası hatası; 15 G1 kot silme + driving_length_m; 16 H4 kaplama taşınma + ikinci kaplama; 17 K1 30° döndürülmüş prekast; 18 Scale ölçek; 19 S5 bozuk dolgu kütüphanesi (yedekle); 20 A3 eski menü BOQ; 21 Chromium 64 görünüm (ui.html:325, gap); 22 R2 araç çubuğu; 23 progress_*/R4/S4 hakediş; 24 performans.
