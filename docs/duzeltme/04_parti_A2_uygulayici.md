# 04 Parti A2 — mst-uygulayici (commit 7244973)
Ana oturum doğrulaması: A1 4 test + A2 9 test hepsi "N geçti, 0 kaldı"; ruby -c 0 hata; Ruby 2.5 dilbilgisi 0 hata.

| Test | Yeni | 0.51.4 |
|---|---|---|
| a2_k50_embed | 16/0 | 10/6 |
| a2_k36_k59_pile | 15/0 | 8/7 |
| a2_r6_opening | 9/0 | 3/4 |
| a2_k57_k63_dwg | 11/0 | 4/7 |
| a2_k58_k60_k09_pc | 28/0 | 3/10 |
| a2_k35_codes | 12/0 | 1/3 |
| a2_k55_r4 | 8/0 | 4/4 |
| a2_boq_progress | 12/0 | 5/4 |
| a2_info_g3 | 13/0 | — |

| Bulgu | Kök neden | Değişiklik | Durum |
|---|---|---|---|
| K36 | pile_qto_concrete önce çocuğu sayıyordu; Component paylaşılan çocuğu silinmiyor | qto_workspace pile_qto_concrete önce infill_enabled=0; pile_manufacturing pile_infill_enabled?/set_pile_infill | düzeltildi, SketchUp testi bekliyor |
| K50 | gömülme ana gövde tabanından | mst_v50_beams mst_hb_zone_segments, mst_hb_bottom_depth; main mst_bk_pile_embed kazık eksenindeki derinlik (Component BK, çok akslı BK, farklı kap: eski kural) | düzeltildi, SketchUp testi bekliyor |
| K57 | süzgeç yalnız rebar_mode | mst_dr_remove_ui yalnız head_beam ve PAFTA dışı; kapsam dışı sayısı iletide | düzeltildi ve doğrulandı (mantık) |
| K63 | rebar_prev_json önce siliniyordu | mst_dr_clear! yalnız başarılı kurulumda siler; aksi rebar_restore_error | düzeltildi ve doğrulandı (mantık) |
| K58 (G1 üretildi) | donatılı parça donatısız tanıma geçiyordu | mst_precast_def_params 'rebar'=>'pc-v1:'+json | düzeltildi, SketchUp testi bekliyor |
| K60 | çizim hatasında eski tonaj | mst_pc_after_rebuild! hatada kayıtları siler (pc_rebar_json hariç), pc_rebar_error; okuma yerleri atlar | düzeltildi ve doğrulandı (mantık) |
| K09 | paylaşılan tanımda soru yok | mst_shared_def_prompt, mst_make_unique_keep_data!; mst_cv_ui EKLE/TEMİZLE; mst_cv_redraw! paylaşılanda çizmez → culvert_error; mst_pc_ui onay iletisi | düzeltildi, SketchUp testi bekliyor |
| K59 | hata durumunda sessiz 0 | mst_pile_rebar_effective?; hata→pile_rebar_error, tonaj pursantaja döner | düzeltildi ve doğrulandı (mantık) |
| K35 | NN sıra numarası | pile_boq_group_key, pile_boq_codes_stored/for/persist!; 4 işlemde kalıcı yazım; bozuk kayıt ezilmez | düzeltildi, SketchUp testi bekliyor |
| K55 | bilinmeyen kod yoğunluk 0 | rockfill_qto_alt1_data hata (Alt-2 gibi) | düzeltildi ve doğrulandı (mantık) |
| K33/K39/K40 | pozsuz miktar görünmüyor | mst_boq_info_rows; send_boq toplamdan sonra info satırları (boq_rows'a girmez; hakediş/iş programı/Excel/CSV değişmez) | kısmen (poz eşlemesi belge gerekli); SketchUp görünümü bekliyor |
| K34 | görünürlük yok | progress_live_rows REBAR warning notu | kısmen (kural belge/kullanıcı kararı) |
| K38 | iki kural ayrışıyor | prog2_icmal_cetvel_warning; payload icmal_warning; Excel icmal notu | kısmen (kural sözleşme gerekli) |
| 08-R6 | alt kalıp kapalıyken açıklık düşülüyor | head_beam_pile_opening_area: alt yüzlerin hiçbiri kalıpta değilse 0 | düzeltildi ve doğrulandı (mantık); kısmi kapalı alt yüzde eski kural |
| Eğik kazık elips | daire | mst_pile_opening_m2/ratio; BK oluşturma ve mst_bk_follow_plan | düzeltildi ve doğrulandı (mantık) |
| 08-R3 | yedek yol adet oranı | prog2_quantities miktar ağırlıklı | düzeltildi ve doğrulandı (mantık) |
| R-4 kalan | bozuk JSON eziliyordu | prog2_manual_set, mst_rt_history_push! | düzeltildi ve doğrulandı (mantık) |
| K46 | — | tarihsiz çağrı tüm onayları sayar; etkin tek çağrı model_audit'te; hata yok | gerekçesiyle uygulanmadı |
| G3 | bayraklar okunmuyordu | MST_AUDIT_ERROR_FLAGS, mst_audit_v0515, model_audit 'Hesap Hatası' | düzeltildi ve doğrulandı (mantık) |

Metraj önce/sonra (sahte örnek, elle beklenen): K50 0,1621 → 0,5675 m³ (π/4·1,016²·0,7); eğimli geçiş 0,1621 → 0,3648; K36 9,126 m³/2,281 t → 0/0; K59 0 t → 2,2814 t; K58 0,42 t sızma → yok; K60 0,5 t eski → 172,8 kg; 08-R6 19,968 → 22,4 m²; elips 0,810732 → 0,821915 m²; 08-R3 7,6 t → 0; K55 0 t sessiz → hata.
ADR'den sapmalar: K09 otomatik yolda paylaşan parçaların hepsi aynı pc_rebar_json ise çizilir; K60 paylaşılan tanımda 3B set silinmez, yalnız hatalı parça kaydı; K63 desteklenmeyen/bozuk kayıt da "kurulamadı"; elips mst_bk_follow_plan'a da uygulandı; R-4 donatı geçmişi bozuksa işlem durur.
Yeni anahtarlar: rebar_restore_error, culvert_error (öğe), mst_def_unique_of (tanım), pile_boq_group_codes_json (model). Donatılı prekast tanım anahtarına rebar parametresi.
Undo: yeni normal işlem yok; yardımcılar çağıranın işlemi içinde; K09 sorusu işlemden önce.
Ayrı öneriler (B'ye aktarıldı): quantity_service pile_owned_concrete K36 sırası; mst_pc_ui işlem dışı set_attribute (K62); bilgi satırları stili (arayüz); K35 performansı ölçülmedi; kafes donatısı yönelim değişince açıklık güncellemesi.
diff: 9 dosya +359/−40 + tools/test/a2_*.rb.
