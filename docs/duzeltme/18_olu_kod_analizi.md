# 18 Ölü kod analizi (K30) — mst-kaynak-analiz (02.11.2026; kaynak eaaa858; salt okuma)
Kullanıcı kararı: "Önce analiz, sonra karar". Silme için CLAUDE.md üç koşulu: (1) başvuru araması — bu rapor; (2) kayıtlı veri/uyumluluk — bu rapor; (3) kullanıcı onayı — BEKLİYOR. Canlı test kanıtı yok.

Runner (kurulu kopya okundu): yalnız 12 yöntem adını respond_to? ile arar (main.rb:83) — aday öğelerin hiçbiri değil; expected_sources.json dosya SHA-256'larını denetler (ui.html, main.rb, pile_drilling.rb, pile_manufacturing.rb, boq_pro.rb dahil) → her değişiklik "Farklı", dosya silme "Eksik" uyarısı üretir (0.51.5'te zaten beklenen).

Yöntem: 197 literal add_action_callback + 19 boq_pro.rb wrap kaydı; sketchup.X( çağrıları (ui.html, *.js, *.html, Ruby içi HTML); dinamik çağrılar (boq_pro.js call/bq2Call literal; mst_workflow.js sketchup[it.open||it.emb] kapalı liste; eval sabit; Ruby send/public_send/method( aday öğelere ulaşmıyor); menü ve MST_MAINT_ACTIONS.

Kayıtlı ama JS/HTML'den çağrılmayan 16 callback: drilling_edit, pile_load_selected_bim, pile_update_selected_bim, pile_batch_details_from_page, boq_element_detail, select_pile_qto_id, pile_edit_v2, universal_edit, bk_formwork_face_tool, formwork_yes, formwork_no, audit_repair_pile_types, audit_repair_pipe_weights, audit_repair_bk_types, audit_repair_precast_types, prog2_view_date. pile_mfg_edit yalnız gizli panelden çağrılıyor.

## Sınıflama
| Öğe | Yer | Sınıf | Gerekçe |
|---|---|---|---|
| "Mevcut Kazık — İmalat Yönetimi" paneli | ui.html:484-509 | KOŞULLU | JS (2087-2119) ve pile_mfg_edit callback'iyle birlikte silinmeli |
| JS readPileMfg/setPileMfg/pileMfgError/savePileMfg, pileMfgToken, pileParamKeys | ui.html:2087-2119 | KOŞULLU | c_callbacks birlikte güncellenmeli |
| pile_mfg_edit → pile_mfg_edit_action ve yalnız ona ait yardımcılar | main.rb:10666; pile_manufacturing.rb:12-34, 43-64, 82-161, 212-422 | KOŞULLU | Kayıtlı veri yazıyor (saved_*_available yalnız burada okunur → eski modelde sahipsiz kalır, bozulmaz); dosyanın infill yardımcıları kalmalı (a2_k36_k59 sınıyor) |
| mstPileUnifiedEditSurface | ui.html:621-650 | SİLİNMEMELİ | Etkin yükleme yolu içindeki öğelere null kontrolsüz erişiyor |
| drilling_edit + pile_drilling.rb | main.rb:10665; pile_drilling.rb:4-79 | KOŞULLU | Veri sahipsizliği yok; f2_guarded_js, c_callbacks ve require birlikte güncellenmeli; runner "Eksik" |
| pile_load_selected_bim | main.rb:10548 | KOŞULLU | f2_guarded_js:46, c_callbacks:74/85 |
| mst_selected_bim_pile_payload | main.rb:6688 | SİLİNMEMELİ | Etkin pile_load_selected_for_edit yolunda |
| universal_edit | main.rb:10715 | KOŞULLU | Parti C adı bilinçli korudu; kullanıcı kararı |
| pile_update_selected_bim + mst_update_selected_bim_pile + selectedBimPileUpdated | main.rb:10549, 7477-7509; ui.html:1889 | GÜVENLE SİLİNEBİLİR (üçü birlikte) | Yalnız birbirini çağırıyor |
| drillingEditorToken, drillingEditorCount | ui.html:1965 | GÜVENLE SİLİNEBİLİR | Hiç okunmuyor |
| boq_element_detail zinciri | main.rb:10672, 3851-~3925; ui.html:2029-2045 | KOŞULLU | HTML/DOM parçaları incelenmedi |
| pile_edit_v2, pile_batch_details_from_page kayıtları | main.rb:10705, 10547 | GÜVENLE SİLİNEBİLİR (yalnız kayıt satırı) | İşlevler bakım listesi/menüden çalışır, kalmalı |
| formwork_yes/formwork_no kayıtları | main.rb:10730-10731 | GÜVENLE SİLİNEBİLİR (yalnız kayıt) | set_selected_faces_formwork testte, kalır |
| bk_formwork_face_tool kaydı | main.rb:10728 | GÜVENLE SİLİNEBİLİR (yalnız kayıt) | İşlev ayrıca incelenmeli |
| select_pile_qto_id kaydı | main.rb:10688 | GÜVENLE SİLİNEBİLİR (yalnız kayıt) | İşlev ayrıca incelenmeli |
| audit_repair_* dört kayıt | main.rb:8618-8621 | GÜVENLE SİLİNEBİLİR (yalnız kayıt) | Onarım işlevleri bakım listesinden çalışır |
| wrap.('prog2_view_date') | boq_pro.rb:1150 | GÜVENLE SİLİNEBİLİR (yalnız kayıt) | Aynı adlı Ruby yöntemi etkin, kalır |
| JS typeOptions | ui.html:1231 | GÜVENLE SİLİNEBİLİR | Çağıran yok |
| JS mstPileIgnoredFields | ui.html:1765 | GÜVENLE SİLİNEBİLİR | Çağıran yok |
| JS mstTechnicalReportProgress | ui.html:1647 | GÜVENLE SİLİNEBİLİR | Çağıran yok |
| JS updateOrBatchSelectedPiles | ui.html:1888 | GÜVENLE SİLİNEBİLİR | Çağıran yok |
Özet: GÜVENLE SİLİNEBİLİR 13 kalem, KOŞULLU 7, SİLİNMEMELİ 2.

Test bağımlılıkları: c_callbacks.rb (:74, :85, 1. bölüm pile_mfg_edit), f2_guarded_js.rb (:8-38, :46), a2_k36_k59_pile.rb (pile_manufacturing.rb infill yardımcıları), b_undo.rb (:94, :103 — kayıt silinirse etkilenmez), a2_boq_progress.rb (:14 — etkilenmez).

Belirsiz: ui.html'de ~64 JS adı ve ayrı *.js dosyalarının iç işlevleri tek tek doğrulanmadı; Ruby Console/başka eklentiden elle çağrı koddan bilinemez; boq_element_detail DOM parçaları, select_pile_qto_id ve activate_bk_formwork_face_tool gövdeleri incelenmedi.
