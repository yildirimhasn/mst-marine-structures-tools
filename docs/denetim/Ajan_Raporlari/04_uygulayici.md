# 04 mst-uygulayici raporu (salt okuma; dosya değiştirilmedi)
Ara liste: review_v0514\noop_mods.txt (işlem açmadan model değiştiren 153 işlev, sezgisel).

## Undo
Sayım main.rb 68 start / 69 commit(+cwd) / 69 abort; boq_pro 9/9/9.
- U1 Doğrulanmış hata: main.rb:2344-2345 ve 2433 commit_with_dependencies (dependency_rebuild.rb:99-101 zaten commit eder) + @model.commit_operation → çift commit (BK Kalıp Yüzeyi ve Evrensel Kalıp aracı tıklaması). Ana oturum teyit etti. SketchUp etkisi testi gerekli.
- U2 Doğrulanmış hata: mst_v50_piles.rb:468-473 transparent işlemde abort_operation (DXF kazık dispozisyonu, aks ızgarası kurulamazsa) → önceki kazık oluşturma işlemi geri alınabilir, mesaj "Kazıklar oluşturuldu".
- U3: main.rb:2258-2280 set_selected_faces_formwork, 6143 unregister_selected_element, mst_schedule.rb:297-299 — start/commit arasında rescue yok, istisnada işlem açık kalır.
- U4: main.rb:9096-9150 rockfill kaydet/yükle/autosave işlem dışı set_attribute (autosave 250 ms, ui.html:2180-2181; load_project okurken yazıyor 9147).
- U5: snapshot 3 ayrı işlem dışı yazma (main.rb:9350-9356, boq_pro.rb:835-850) (H9 teyidi).
- U6 Olası: main.rb:10325-10331, 10388-10393 okuma işlevleri set_attribute yapıyor.
- U7 Olası: main.rb:7293,7443; mst_schedule.rb:365,375 açık işlem yokken abort rescue nil.
- U8 Düşük: main.rb:4270-4274 toplu prekast her aralık ayrı işlem.
- İç içe start_operation bulunmadı. dependency_rebuild, boq_pro, rockfill_live, pile_manufacturing işlemleri sorunsuz.

## Sessiz başarısızlık
- S1 (metrajı değiştirir): mst_v50_beams.rb:126 `mst_cv_draw!(hb,s) rescue nil` — BK yeniden kurulurken menfez çizilemezse grup oluşmaz, culverts_json kalır; düşüm gruplardan okunduğu için (77-79; main.rb:2459,2526 rescue 0.0) BK betonu düşümsüz, menfez sacı 0, uyarı yok. (Ana oturum: yutma teyit; çizimin başarısız olma koşulu SketchUp'a bağlı → koşullu hata.)
- S2: mst_v50_beams.rb:122+157 bozuk culverts_json → [] → EKLE eski menfez kayıtlarını siler.
- S3: mst_v50_beams.rb:173-174 formwork_net_area_m2 yazımı rescue nil.
- S4: boq_pro.rb:397+750-753 prog2_items bozuk JSON'da {} → ilerleme kaydında elemanın onay geçmişi (ok dizisi) üzerine yazılır; hakediş geçmişi kaybı.
- S5: main.rb:9093+9130-9135 bozuk dolgu kütüphanesi → varsayılan; ilk autosave kullanıcı kütüphanesini ezer.
- S6 Olası: main.rb:10377,10447,10829,10893 aks/yapı/sistem/yerleşim JSON bozuksa {} → sonraki kayıtta ezilir.
- S7: boq_pro.rb:358 kazık iç betonu ilerleme miktarı hata→0.0. S8: mst_v50_misc.rb:84 aksesuar ankraj donatısı 0 kg. S9: hatalar yalnız puts (9134,9142; boq_pro.rb:847).

## Ruby 2.5 / SU2020 API: sorun bulunmadı
Ruby 2.6+ yöntem yok; find_entity_by_persistent_id (2020.0) korumasız ama SU2020'de var (main.rb:9067, rockfill_live.rb:42,163); active_path= korumalı; LayerFolder/weld/build/Overlay yok. Çalışma zamanı (ör. Date#strftime) SketchUp'ta doğrulanır.

## Birim / kot
- K1 Olası: prekast açıklığı/boyu bounds.min.x/max.x ile (main.rb:4270,4281,4295,4419-4431,11130) → model X'e paralel olmayan (döndürülmüş) yapıda prekast boyu ve beton metrajı hatalı; uyarı yok. SketchUp testi.
- K2: main.rb:4374,4386 length_m yoksa bounds.width.
- K3 sorun yok: inç→m (0.0254) doğru, mm/m karışması yok, yuvarlama toplamdan sonra (8555-8566).
- K4 Bilgi: rockfill model Z (m) = kot varsayımı.

## En küçük düzeltme yaklaşımları (yazılmadı)
B1: callback'te Türkçe uyarı + arayüzü controlled_editor akışına yönlendir (metraj değişmez). R1: skp: → sketchup.X(p) (Ruby değişmez). H1: numarayı en büyük Rev.NN+1'den, boq tespiti ad farkıyla, last(20) silmesini kullanıcı kararına bırak, tek işlem. H2: yalnız eksik anahtarı yaz, registry ilk gelen kazanır, element_library yazmasın. H4: ayrı kaplama toplayıcı (collect_elements değişirse metraj değişir → golden-master).
Öncelik önerisi: Kritik B1,S1,S4; Yüksek H1,H2,S2,S5,U2,R1; Orta U1,U4/U5,K1,S3,S6,H4; Düşük U3,U6-U8,S7-S9,K2.
Ek: Evrensel Kalıp aracı (main.rb:2400-2412) yüzeyin sahibe ait olduğunu denetlemiyor (2308'deki BK aracı denetliyor).
