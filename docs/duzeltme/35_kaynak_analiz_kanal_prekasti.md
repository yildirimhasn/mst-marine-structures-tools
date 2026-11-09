# 35 Kaynak analizi — kanal prekastı (PK) (mst-kaynak-analiz, 09.11.2026; salt okuma, komut çalıştırmadı; ana oturum kaydetti; kaynak HEAD d7bb45d, çağıranın beyanı)
Hedef: kullanıcı talimatı 09.11.2026 (PK-U / PK-UU / PK-L / PK-K tipleri, Prekast Yerleşimi PK seçimi + BK kanal boşluğu uyumu, 3 kot yöntemi, döşeme boşluğu, uyumluluk). Satırlar main.rb, aksi belirtilmedikçe.

## A) Oluşturma / düzenleme — üç ayrı yol
1. **Tek kanal formu:** ui.html:902 → createChannelPrecast (ui.html:1953) → callback create_channel_precast (:10949) → create_channel_precast (:4652). Seçili BK gerekir; alt kot = BK üst kotu (:4664); gövde 3 iç grup (taban + 2 duvar, :4671-4676); kalıp boyama çağrılmaz. Yazılan (:4678): element_type, precast_type='KANAL_PREKASTI_U', inner_width_m, inner_depth_m, base_thickness_m, wall_thickness_m, outer_width_m, length_m, seat_left_m, seat_right_m, concrete_class, bottom_elevation_m, top_elevation_m, concrete_volume_m3, formwork_area_m2, formwork_inner_m2, formwork_wall_top_m2, formwork_bottom/sides/inner/ends/top. Yazılmayan: precast_type_id, precast_family, support_*_pid. Sonra finalize_bim_identity (:6618). Kesit önizlemesi statik CSS (ui.html:890-893), yalnız etiketler güncellenir (ui.html:1949); "Referans" tek seçenek (ui.html:882).
2. **Prekast Yerleşimi PK satırı:** createPD (ui.html:1439) → create_flat_precast (:10937) → `when 'PK'` (:4588-4592): U profil itme; üst kot = BK üstü + yerleşimdeki en kalın PD/PV (:4591); kalıp paint_channel_precast_formwork (:291). Ek anahtarlar: precast_family='PK', precast_id, precast_type_id, library_type_id, precast_type, type_signature, width_m, layout_width_m, joint_m, seat_each_side_m, support_left_pid, support_right_pid. Varsayılan gövde Component (:4598-4601).
3. **Ceplere yerleştirme (KN1):** kn_place (:10943) → mst_kn_place (:13010) → mst_kn_create_pk! (:12964); ek anahtar kn_from_pocket (:12981); Component.
- finalize_bim_identity type_signature / library_type_id / type_id'yi kanonik "önek-T##" ile üzerine yazar (:6652-6656); precast_id çakışırsa değiştirilir (:6645); mst_sync_precast_type_library aynı üçünü yeniden yazar (:8033-8048); tip adı precast_type_id'de; mst_precast_type_id precast_id'ye geri düşer (:12291).
- Kontrollü Düzenleme: controlled_editor.rb:10 FIELDS, :196-200 (rebuild_channel_parametric'e public_send) → :8905. Ret: Component (:55), paylaşılan tanım (:58), iç grup (:65), standart U dışı (:29), bağımlısı olan (:129), mesnede bağlı (:132) → yerleşim / KN PK'sı ve form PK'sı bu akışla değiştirilemez (koddan çıkarım; canlı test yok).
- Boy yeniden kurma: mst_precast_resize_plan (:13473) → mst_apply_precast_resize! (:12437); Group → mst_rebuild_channel_precast_length (:12389), Component → tanım değiştirme (:12441); kesit ve kot korunur.

## B) Prekast Yerleşimi
- PK tipleri model attribute `precast_type_library_json` (yazma :4604, okuma :10938, JS varsayılanı ui.html:1404); alanlar inner_width, inner_depth, base, wall, concrete. unified_catalog kullanımı görülmedi.
- Satırda sınıf, tip adı, okunur genişlik, adet (ui.html:1436); kesit önizleme / uyum işareti / kot seçimi yok.
- mst_kn_find_pk_type (:12828) tek çağıran mst_kn_place_plan (:12911); eşleşme dış genişlik + toplam yükseklik ±5 mm; önce kütüphane, sonra modeldeki PK'lar.
- KN düğmeleri yalnız PD alt sekmesindeki yan panelde (ui.html:849-850, mst_workflow.js:238).

## C) BK kanal cebi
- Anahtarlar start_/end_seat_enabled, _offset_m, _length_m, _depth_m; geometri recess_profile_points (:417-452), BK tam genişliğinde.
- Dünya cep kutusu / eksen / taban kotu: mst_bk_pockets (:12751; floor_z :12757); çok akslı BK'da cep yok (:12736).
- Denetim mst_kn_audit (:12766): boş cep, cep uzunluğu, ortalılık, taban kotu, üst kot; Model Sağlığı'ndan (:8583).
- Bağımlılık: PK support_*_pid varsa BK'nın çocuğu (dependency_rebuild.rb:44-53); BK kot değişiminde mst_bk_dependents ile taşınır (:1991); BK düzenlenince mst_kn_after_edit yalnız boş cebe yerleştirir (:13003) — mevcut PK cep kotuna yeniden oturtulmaz.
- Kot eşitleme "PD üstü": sync_precast_to_head_beams (:4622-4629), elevation_sync.rb:126-134 (yalnız Group, :116).

## D) Döşeme boşlukları
- mst_deck_plan (:4845): kanal açıklığı = iç genişlik, kutu merkezine simetrik varsayım; yükseklik taban üstünden döşeme üstüne (:4886-4891).
- Hücre bazlı aralık çıkarma (:4920-4923): her hücre bir kez → aynı aralık iki kez düşülmez (yapısal gözlem, test yok).
- Kayıt channel_opening_volume_m3, channel_opening_count (:5336); kalıpta kanal açıklığı yan yüzleri dahil (:5341).
- Yeniden üretim mst_deck_after_edit yalnız BK düzenlemesi ve KN yerleşimi sonrası (:13007, :13022); PK silme / düzenleme sonrası otomatik tetik yok (observer yok); elle deck_refresh (:10954).
- Eski kurucu create_deck_slab_legacy_v034 (:5931, "not called"). Döşeme ↔ prekast bağı dependency_rebuild.rb:53.

## E) Metraj
- quantity_service.rb:65, :84 kayıtlı concrete_volume_m3 / formwork_area_m2.
- U kesit formülü tekrarları: :4591, :4677, :8917, :12400, :12510, :12975, controlled_editor.rb:25, :141.
- Donatı: hacim × oran (:3516) ya da tanım donatısı (quantity_service.rb:44); PK donatı alanları duvar + taban varsayar (mst_pc_rebar.rb:25-31, :53-55).
- Rapor gruplama :4306; tanım anahtarı :12500-12505.

## F) Testler (incelendi, çalıştırılmadı)
- PK yalnız sabit attribute'lu sahte nesne: tools/golden/fixture.rb:112, v4_tapa_prekast_poz.rb:57, k1_structure_copy.rb:601. Metin kontrolleri b_audit_k22_k23_k10_k54.rb:49-50, b_misc.rb:118. mst_deck_plan testte stub (b_k07_k53_topping.rb:65). a2_r6_opening BK kazık açıklığı (döşeme değil).
- Kesit geometrisi, KN, döşeme kanal açıklığı için test yok.

Durum: kaynakta var (üç yol); arayüzden erişilebilir (form, yerleşim, KN düğmeleri bağlı); canlı test kanıtı yok.
Belirsiz: rebuild_channel_parametric için başka dinamik çağıran taraması tam değil; okunmayanlar: BK formu "3. Kanal Prekastı" (ui.html:738, :974), boq_pro.rb tamamı, model_health.rb, relationship_audit.rb, structure_copy.rb, project_workspace.*, mst_labels.rb, mst_schedule.rb, mst_dx_rebar.rb.
