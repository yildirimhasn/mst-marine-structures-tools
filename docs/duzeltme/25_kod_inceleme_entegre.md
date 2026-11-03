# 25 Kod incelemesi — entegre 0.51.5 (a5ea937…10e520d; mst-kod-inceleme, 03.11.2026; salt okuma, test kanıtı yok)
Görünen ad kimlik alanlarına sızmıyor; ad/kod yolları eleman özniteliği yazmıyor; Undo yapısı doğru. 12 bulgu:
1 YÜKSEK main.rb:11837-11862, JS 13769-13793 — C seçeneğinde hedef kod (to) kullanım denetimi yok: kazıklı ANO-02 silinip aynı oturumda boş ANO-03'ün kodu "ANO-02" yapılırsa ANO-02 kazıkları ANO-03'ün ızgara/yerleşim/bölgesine bağlanır (sessiz yapı birleşmesi). Öneri: hedef kod tüm sistemlerde old_codes dışında + mst_structure_code_lock eşdeğeri denetim, işlem öncesi Türkçe hata.
2 ORTA main.rb:13469-13473 — kullanılan yapının Aks Yöneticisi'nden silinmesi sunucu tarafında denetlenmiyor (G5b yalnız yükte kalan ızgaraları geziyor); elemanlar sahipsiz, görünen ad kaydı düşer. Öneri: mst_code_usage ile sunucu denetimi, onay yoksa ret.
3 ORTA main.rb:11739-11753 — "kullanılmıyor" denetimi yalnız collect_elements (10 tür): jet grout ano taşıyor ama sayılmıyor; iç içe aks görseli sayılmıyor; prekast axis "X-01↔X-02" virgülle bölünüyor. Öneri: tüm element_type taşıyıcıları, ↔ ayırıcı.
4 ORTA main.rb:10323 show_boq_engine — mstShowPage('boq') + ayrıca refreshBOQ → çift boq_refresh (eski menü Keşif Motoru, Bakım boq_engine).
5 DÜŞÜK main.rb:13657/13817 — G5a: kayıtlı ızgarası olmayan yapıda varsayılan ızgara yazımı ilk kayıtta işlem açtırır; mst_structure_move_plans → mst_structures_for_system işlem dışı yazabilir (önceden de vardı).
6 DÜŞÜK main.rb:13451-13452 — MstAttrRecorder anahtarsız delete_attribute ve method_missing okumaları; bugünkü yolda kullanılmıyor.
7 DÜŞÜK main.rb:11707-11712 — serbest kalan eski kod yeniden önerilebiliyor; sahipsiz active_structure_zone__ ve arşiv belirsizliği.
8 DÜŞÜK controlled_editor.rb:75-91 — G2 prekast için güvenli; Ruby head_beam'i hâlâ kabul ediyor (üst kazıklar odak dışı); güvence yalnız JS. Öneri: Ruby'de BK reddi ya da üst elemanları odağa ekle.
9 DÜŞÜK main.rb:8536/8581 — Model Kontrolü iletileri erişilemeyen "Eleman Düzenleyici"yi gösteriyor; ACT.editor ve navigate('editor') ölü.
10 DÜŞÜK project_workspace.js:198-206 — pendingBeam 5 s: başka eleman sonra aynı BK seçilirse BK sayfası istenmeden açılabilir.
11 DÜŞÜK JS 13720 ↔ Ruby 11618 — JS yalnız yasak liste, Ruby izin listesi: , ; @ = % JS'ten geçer, onaydan sonra Ruby reddeder; mstBKAddProjectStructure ayrı kural.
12 DÜŞÜK mst_workflow.js:296 — emb_* sayfalar T çağırmıyor; gömülü sayfaya geçişte eski tam yenileme (performans, güvenli yön).
Sorun yok: görünen ad sızıntısı, işlem yapısı, bozuk JSON, Ruby 2.5/Chromium 64, G3 arşiv önbelleği, Bağımlılıklar yanıt eşleştirmesi, yeni anahtarlar.
Soru: Kontrollü Düzenleme paneli prekast için ikinci form — NCR-003 prekast için de geçerli mi (kullanıcı kararı).
