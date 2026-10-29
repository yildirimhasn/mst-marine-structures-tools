# 02 mst-kaynak-analiz raporu (salt okuma)

Kontroller: menü + 4 toolbar (31 komut) → işlev → tanım: hepsi tanımlı; 31 ikon çifti mevcut. JS literal çağrı → Ruby kaydı: eksik yok. ~120 callback hedef işlev örneklemi. nav_*.png 18/18 kullanılıyor (mst_workflow.js:82-87, ui.html:377-383) — ön kontroldeki "başvuru yok" notu yanlış.

## Doğrulanmış hata
- B1 (Yüksek): main.rb:10133 `add_action_callback('universal_edit'){|_,j|update_selected_element(j)}` — `update_selected_element` hiçbir yerde tanımlı değil (ana oturum grep ile teyit etti; method_missing yok). Yol: Eleman Düzenle (ui.html:1079/1087, mst_workflow.js:159) → applyEditor (ui.html:1958) → editor_preview (main.rb:10129) → preview_editor_change (8635-8645) → confirm → sketchup.universal_edit (ui.html:1959) → NameError, rescue yok; güncelleme uygulanmaz. Aynı satır yerel depoda da var (incelenmedi).

## Olası riskler
- R1 (Yüksek, SketchUp testi): HtmlDialog içinde `window.location='skp:<ad>@'+encodeURIComponent(JSON)` (ui.html 16 yer, mst_workflow.js 4): kronman oluştur/yükle/revize/aks oku (ui.html:2233,2236-2238), dolgu kütüphanesi/proje kaydet/yükle/otomatik kaydet (2180-2213), element_info, element_library, export_professional_excel, export_boq_csv, model_audit (702,745,1082,1168-1169; mst_workflow.js:148-161). HtmlDialog'un skp: yönlendirmesi ve URL çözme statik doğrulanamaz; Ruby JSON.parse öncesi URL çözmüyor (main.rb:9054,9068,9097,9122,9131,9138). Otomatik kayıt hataları yalnız puts (9134,9142). Kronmanın tek arayüz yolu bu.
- R2 (Düşük): tb.show koşulsuz (main.rb:10288).
- R3 (Düşük): gömülü sayfalarda `sketchup` Proxy (ui.html:2468) → JS `if(sketchup.X)` korumaları etkisiz; kayıtsız ad yalnız Ruby konsoluna yazılır (embed.rb:116).
- R4 (doğrulanamadı): progress_approved_quantity(row,date=nil) main.rb:8083'ten tarihsiz çağrılıyor; prog2_frac(e,src,nil) davranışı okunmadı.
- respond_to?(:mst_…) korumaları (main.rb:1818,2459,2526,3432,3644): bir require başarısız olursa ilgili metraj kalemi (mst_v50_boq_rows, mst_hb_culvert_void) sessizce düşer.
- Dinamik: public_send controlled_editor.rb:158; define_singleton_method(:add_action_callback) embed.rb:156 (mst_embed_forward 126-141); JS sketchup[name] boq_pro.js:9, mst_workflow.js:43.

## Yeniden tanımlar (17/17 doğrulandı) — imzalar uyumlu
progress_approved_quantity (8083,9466,9502), progress_live_rows, progress_save (eski progressSave → boq_pro.js:167 ile prog2_save'e yönlenir), progress_delete_period, project_ano_axis_manager (tüm yollar 12464 sürümüne gider).

## Eksik / erişilemeyen
- E1 (Orta): main.rb:8797 eski aks yöneticisi geçersiz kılındığından auto_organize_project (8689) ve assign_manual_axis_to_selection (8768) arayüzden erişilemiyor (project_organize/project_manual_axis callback 8810/8815). Silme önerisi değil.
- E2: Dalgakıran modülü yok (yalnız "mendirek" metni main.rb:9015, ui.html:1072).
- BK diş/konsol için ayrı işlev bulunamadı (doğrulanamadı).
- Foraj düzenleme: drilling_edit callback'inin JS çağıranı yok; yalnız eski menüdeki toplu güncelleme.
- Tablo C (kayıtlı, çağrılmayan): audit_repair_* 4 adet (8172-8175), pile_batch_details_from_page, pile_load_selected_bim, pile_update_selected_bim (9969-9971), drilling_edit 10084, boq_select_sources 10090, boq_element_detail 10091, select_pile_qto_id 10107, pile_edit_v2 10124, bk_formwork_face_tool 10146, formwork_yes/no 10148-10149, prog2_view_date boq_pro.rb:1074.

## Kapsam (kaynakta / erişim; canlı test hepsinde yok)
Proje/aks main.rb:12464 · çelik kazık 1133/541, A-çerçeve mst_v50_piles.rb:140 · çember 6593/6676 · tapa 10195 · iç beton 687, pile_manufacturing.rb:195 · foraj pile_drilling.rb:63 · PE mst_labels.rb:231 · fore bored_pile.rb:99 · jet grout jet_grout.rb:121 · BK cep/kanal 1393,1542,2042,11517,11897 · menfez/taban/kademeli mst_v50_beams.rb:131/208/258 · prekast 4266/4379/4414 · boyuna/vinç kirişi mst_v50_beams.rb:345/406 · döşeme/kaplama/tretuvar 5139/5900/4457, mst_v50_misc.rb:44 · kronman 9053 (yalnız skp:) · iskele/rıhtım/dolfen sistem etiketi (12468) · Alt-1/2 rockfill_alternatives.rb:6, main.rb:9113 · batimetri rockfill_geometry_engine.rb:60, rockfill_cut_mesh.rb:27 · BIM/donatı 3230, 5502 + donatı modülleri · BOQ boq_pro.rb:315/365/1064, main.rb:3441 · iş programı mst_schedule.rb:306 · hakediş boq_pro.rb:1068/614.
