# 07 mst-kod-inceleme raporu (bağımsız, salt okuma)
İncelenmeyen: donatı modülleri, rockfill_* (rockfill_live hariç), quantity_service ayrıntısı, CSS, metraj formülleri.

## A. Bağımsız doğrulama
- B1 Teyit; öncelik Yüksek (04'ün "Kritik"ine katılmıyor: veri bozulmuyor, Kontrollü Düzenleme çalışıyor).
- R1 Kısmen: skp:'nin çalıştığına dair not/test kaydı yok; aynı sayfadaki diğer çağrılar sketchup.X; embed köprüsü (embed.rb:153-161) skp:'yi iletmez; Ruby URL çözmüyor (main.rb:9054 `%7B…` JSON.parse) → skp: çalışsa bile kırık olabilir. API belgesi bu oturumda görülmedi. SketchUp testi.
- H1 Teyit. H7 Teyit.
- H2 Teyit, ayrıntılı: her model açılışında değil; Element Library (10122, 9741, eski menü), BIM Core (6433), Dependency stamp (8255) yollarında değişiklik bakmadan tüm elemanlara yazar (6382-6400); `changed` eleman sayısıdır, "Standardize Edilen" olarak gösterilir (6428); aynı imzada son okunan library_type_id kazanır (6377-6380); 6363-6366 2.1/v0.23.4 yazar, standardize 2.0/v0.20.0'a geri çeker.
- H3 Kısmen: kopya anında tespit yok, ama Audit (main.rb:7940), relationship_audit.rb:20, project_workspace.rb:102 çift UID'yi raporluyor; elle onarım main.rb:7460. Tretuvar bağı kopması teyit (dep.:60-62 matches.length==1).
- H4 Teyit (mst_collect_elements_raw 2098, mst_all_elements 8211; kaplama kök entities'e 5954).
- H5 Teyit; ayrıca mst_cv_redraw! definition içindeki menfezleri siler, yalnız bu örneğin culverts_json'undan yeniden çizer (125-126) → diğer örneklere sızar.
- U1 Teyit (kural), etki büyük olasılıkla düşük: 2344-2345 arayüzden erişilemez (bk_formwork_face_tool JS çağıranı yok); erişilebilen 2432 Evrensel Kalıp; observer işlemi UI.start_timer(0) ile sonra açıldığından ikinci commit açık işlem yokken çalışır. Öncelik Düşük, SketchUp testi.
- U2 Teyit, Orta; yalnız mst_kd_apply_grid! hata verdiğinde; ayrıca 459 set_attribute işlem dışında.
- S1 Kısmen → Orta (Kritik değil): çizim gerçekçi olarak yalnız menfez BK dışında kalınca (87) başarısız; o durumda düşüm yapmamak geometrik olarak doğru. Kusur: geçersiz kayıt culverts_json'da kalır, uyarı yok.
- S2 Teyit, olasılık düşük (değer hep JSON.generate ile yazılıyor) → Düşük.
- S4 Teyit, kapsam daha geniş: 753/755'te elemanın TÜM pozlarının kaydı silinir; clear yolunda öznitelik silinir; dış bozulmaya bağlı → Orta.
- S5 Kısmen: tamamen skp: yoluna bağlı (2181).
- G1 Kısmen: ui.html:1185 deniz tabanı boşsa alan düzenlenebilir olur, eski değer kalır; bilinçli elle giriş tasarımı olabilir → niyet sorusu.
- K1 Teyit (kod): 90°'de clear<=0 mesajı; ara açılarda boy uyarısız yanlış. SketchUp testi.
- A3 Teyit.

## B. Yeni bulgular
- N1 Doğrulanmış hata: main.rb:9046 çift tırnaklı Ruby'de `\'` → `'`; JS'e `crownAxisError('Önce SketchUp'ta …')` gider → JS sözdizimi hatası, "Aks okunuyor..." kalır (kenar seçili değilken; R1 yolu çalışıyorsa). Ana oturum satırı okuyup teyit etti.
- N2 Doğrulanmış hata: boq_pro.rb:836 revizyon arşivi bozuksa sarmalayıcı önce okuyup hata verir; callback main.rb:10115 rescue yok → kullanıcı hiçbir şey görmez.
- N3 Doğrulanmış hata (kayıtlı veri kuralı): accessories.rb:228-238 bozuk library.json → `rescue []`; ekleme (265) / silme (302) yalnız yeni listeyle File.write (atomik değil) → kullanıcının bütün aksesuar kütüphanesi kaybolur. (boq_library.rb:99-121, safe_report_file.rb atomik.) Ana oturum teyit etti.
- N4 Doğrulanmış hata (Undo): main.rb:6433-6435, 8255-8256 BIM Core / Dependency komutu iki ayrı start_operation → 2 Ctrl+Z.
- N5 Olası: main.rb:2318 MSTBKFormworkFaceTool Component BK'da hb.entities → NoMethodError (arayüzden erişilemiyor).
- N6 Olası: main.rb:9821, 9827 axis_name HTML'e kaçışsız; JSON.generate `</script>` kaçırmaz → aks adında `<`/`</script>` pencereyi bozar (yapı adı 10034 regex ile korunuyor).
- N7 Olası: main.rb:10136, 10151-10157, 10016-10017 rescue'suz JSON.parse callback'leri.
- N8 Olası: main.rb:9886 pile_batch_inline_apply JS tipinde yazar; 6456 Float/Integer → aynı anahtar String/sayı karışık olabilir (doğrulanamadı).

## Sorun bulunmadı
Callback yeniden kaydı (@d her açılışta yeni, 9782-9783); boq2 callback adları çakışmıyor (boq_pro.rb:1056-1074); embed.rb:132 ana adları ezmiyor; menü/toolbar/observer file_loaded? içinde; observer model başına tek; alias zinciri `unless method_defined?` korumalı, load'da sonsuz özyineleme yok (yalnız main.rb tek başına load edilirse boq_pro sarmalayıcıları kaybolur); transparent işlem kuralı uygun.

## Doğrulanamayan
Açık işlem yokken commit/abort SU2020 davranışı (U1, 6018, 6407, 8276, 9968); R1 API davranışı; N8.
