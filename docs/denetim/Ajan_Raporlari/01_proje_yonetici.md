# 01 mst-proje-yonetici raporu (salt okuma)

## Modül haritası
Menü: main.rb:10235-10241 (ana menü, "Proje Paftaları (v0.50)", "Tüm araçlar (eski menü)"). Araç çubukları main.rb:10243-10289 (Marine Structures / MST Kazık / MST Donatı / MST Proje).
- Proje/sistem/aktif yapı/aks: project_workspace.rb/.js, axis_chain.rb, main.rb:10019-10062, 12315-12632. Sistemler DOLFEN/İSKELE/RIHTIM (main.rb:1146).
- Çelik boru kazık: main.rb, mst_v50_piles.rb, pile_manufacturing.rb, pile_drilling.rb, pile_visual_geometry.rb, mst_labels.rb, accessories.rb; toplu detay main.rb:10182.
- Fore kazık bored_pile.rb/.html (+ main.rb:3649 bored_pile_boq_rebar_rate). Jet grout jet_grout.rb/.html.
- BK, diş/konsol/kanal: main.rb, headbeam_editor.rb, mst_v50_beams.rb (menfez, taban bölgesi, kademeli döküm), controlled_editor.rb.
- Prekast: main.rb create_channel_precast / create_crane_precast (10151-10152), mst_pc_rebar.rb.
- Boyuna/vinç kirişi: mst_v50_beams.rb (VK/BBK).
- Döşeme/kaplama/tretuvar/kronman: main.rb create_deck_slab (10153), create_deck_curbs (4457), crown_* (8826-9066), mst_v50_misc.rb.
- Kazı-dolgu Alt-1/2: rockfill_*.rb (17), special_solids.rb.
- Batimetri/deniz tabanı/kesit: rockfill_tin.rb, rockfill_geometry_engine.rb:60 seabed_profile, rockfill_templates.rb, data/akdeniz_reference_sections.json.
- Dalgakıran: pakette karşılığı bulunamadı (doğrulanacak). Tek iz main.rb:9015 "mendirek".
- BIM/donatı/pursantaj: mst_auto_rebar, mst_dwg_rebar, mst_dr_auto, mst_dx_rebar, mst_dxf, mst_rebar_tools, data/rebar_drawings.
- Metraj/BOQ/hakediş/ilerleme: quantity_service, qto_workspace, takeoff_excel, boq_library, boq_mapping, boq_pro (hakediş boq_pro.rb:948), source_tariffs.json, unified_catalog.json. İş programı mst_schedule.rb.
- Diğer: model_health*, health_*, record_repair, batch_record_repair, relationship_audit, revision_signatures, elevation_sync, material_change, dependency_rebuild, system_exports, embed.

## Bulgular
- Doğrulanan hata: yok.
- Olası risk (Orta): progress_* main.rb'de tanımlı, boq_pro.rb'de yeniden tanımlanıyor (imzalar farklı row → row,date=nil); main.rb:12638 notuna göre bilinçli; metraj etkisi doğrulanmadı.
- Olası risk (Düşük): tb.show koşulsuz (main.rb:10288) — kapatılan araç çubuğu geri gelebilir. SketchUp testi gerekli.
- Olası risk (Düşük): install_dependency_observers file_loaded? içinde (main.rb:10234); model değişiminde yeniden bağlanma dependency_rebuild.rb:174-190 AppObserver'a bağlı; tekrar ekleme doğrulanmadı.
- Eksik: Dalgakıran modülü bulunamadı (tanım belgesi gerekli).
- SketchUp testi: araç çubuğu kapat/aç; eski menü öğeleri; hakediş/ilerleme hangi progress_* sürümünü kullanıyor.
- Açık sorular: dalgakıran tanımı; golden-master BOQ CSV var mı.
