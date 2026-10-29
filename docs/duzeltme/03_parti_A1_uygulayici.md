# 03 Parti A1 — mst-uygulayici (commit 25da577)
Ana oturum doğrulaması: a1_r1_revision 27/0, a1_r2_identity 28/0, a1_r4_json 24/0, a1_r5_uid 24/0; 66 rb ruby -c OK; Ruby 2.5 dilbilgisi 0 hata.

| Bulgu | Kök neden | Değişiklik | Doğrulama | Durum |
|---|---|---|---|---|
| K02 | last(20) kırpma, length+1 numara, 21.+ kayıtta keşif eklenmiyor | main.rb revision_save_snapshots kırpma yok; revision_create_snapshot saf kurucu (max Rev.NN+1); boq_pro sarmalayıcısı (fark yoksa kayıt yok; >20/5 MB uyarı) | a1_r1_revision 27/0 (0.51.4: 8/19) | düzeltildi ve doğrulandı (mantık) |
| K03 | 3 işlem dışı yazma | boq_pro revision_create_snapshot tek start/commit | [:start,:commit] | düzeltildi, SketchUp testi bekliyor |
| K26 | sarmalayıcıda rescue yok | bozuk arşivde Türkçe ileti, işlem yok; hata→abort+ileti | bozuk arşiv baytı değişmiyor | düzeltildi ve doğrulandı (mantık) |
| Donatı geçmişi last(10) | kırpma | mst_rebar_tools.rb:484 kırpma kaldırıldı | 12/12 | düzeltildi ve doğrulandı (mantık) |
| K04 | standardize her açılışta yazıyor | mst_standardize_changes (yalnız eksik); standardize_model_metadata(own_op) değişiklik yoksa 0; element_library yazmaz; mst_dependency_payload UID üretmez | a1_r2_identity 28/0 (0.51.4: 6/22) | düzeltildi ve doğrulandı (mantık) |
| K05 | stamp dolu alanları eziyor | yalnız boş alan; elle dependency/revision yazımları kaldırıldı; değişiklik yoksa ileti | aynı | düzeltildi ve doğrulandı (mantık) |
| K28 | iki işlem | tek işlem | [:start,:commit] | düzeltildi, SketchUp testi bekliyor |
| K19 | bozuk progress_items_json ezilir | prog2_items_for_write; prog2_apply bozukta abort+ileti | a1_r4_json 24/0 (0.51.4: 8/16) | düzeltildi ve doğrulandı (mantık) |
| K20 | bozuk kayıt varsayılana dönüp eziliyor | mst_json_attr_bad?/mst_json_attr_guard!; rockfill kütüphane kaydet/autosave, yapı/bölge ekle-kopyala-sil, aks ızgarası, sistem yapıları, aks yöneticisi kaydı | aynı | düzeltildi ve doğrulandı (mantık) |
| K27 | bozuk dosya [] sayılıyor, atomik değil | user_accessory_items_for_write; atomik yazım; kayıt/silme öncesi kontrol | baytlar değişmiyor, .tmp kalmıyor | düzeltildi ve doğrulandı (mantık) |
| K06 | kopya UID yeniden atanmıyor | uid_owner_pid (ensure_uid, finalize_bim_identity, mst_copy_dicts!); revision_diff PID eşleşmesi; repair_bim_identity (mst_uid_owner, ilk 10 asıl→kopya, yeni UID+copied_from_uid, ilerleme devri, kopya tretuvar→kopya döşeme, kalanlar "Doğrulanmalı"); model_audit "kopya olası"; dependency_rebuild mst_uid_owner + tretuvar asıl öğe tercihi; boq_pro mst_dup_uid_continue? (revizyon ve progress_save öncesi) | a1_r5_uid 24/0 (0.51.4: 9/13) | düzeltildi, SketchUp testi bekliyor |

ADR'den sapma (ana oturum kabul etti): repair_bim_identity kopyada progress_items_json'ı progress_inherited_json'a taşıyıp eski anahtarı siler (aksi hâlde kopya onaylı görünmeye devam eder); işlem kullanıcı onaylı onarımdır, veri yeni anahtarda aynen durur, tek Ctrl+Z ile geri alınır.
Yeni anahtarlar: uid_owner_pid (Integer), copied_from_uid, progress_inherited_json, progress_inherited_status.
Bilinen sınır: 0.51.4'te önceden ezilmiş revision/type_id geri getirilemez. Bozuk kayıtta kaydetme reddedilir (kullanıcı kaydı düzeltene kadar).
Metraj: K06 onarımı kopyanın onaylı ilerlemesini düşürür (hakediş); R-1, R-2, R-4 hayır.
Ayrı öneriler (A2'ye aktarıldı): prog2_manual/manual_progress_json ve mst_rt_history bozuk JSON; bim_data_core_report ileti metni; rockfill_autosave_library reddi yalnız puts; id_groups asıl öğe tercihi.
diff: main.rb, boq_pro.rb, accessories.rb, dependency_rebuild.rb, mst_rebar_tools.rb (243+/86−) + tools/test/a1_*.rb.
