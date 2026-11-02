# 21 Arayüz tekrar envanteri ve son revizyon incelemesi — mst-kaynak-analiz (02.11.2026; kaynak d5fcfca; salt okuma, komut çalıştırılmadı)

## Görev 1 — Arayüz tekrarları
Menü (mst_workflow.js:62-110 buildNav): İŞ AKIŞI 1-10 + alt adımlar; ARAÇLAR: Aksesuarlar, Model Bakımı, Ayarlar, Kılavuz. "Çalışma Alanı" (ui.html:374) ve "Eleman Düzenle" (ui.html:379) seçilmiyor (pick.editor "T('editor'" arıyor; ikisi de T('project_workspace')) → "rest" olarak Kılavuz'dan sonra bölüm başlığı olmadan menü sonuna ekleniyor. add(pick.editor,TOOLS[0]) boş; NAVMAP.editor null. Uzantılar menüsü ve araç çubuğunda "Eleman Düzenle" yok.
Çalışma Alanı (ui.html:393-415, project_workspace.js/.rb, controlled_editor.rb): Modeli Yenile; arama/filtre; ağaç tıklaması ve Modelde Göster (seç+yakınlaştır); Elemanı Düzenle (kazık → Kazık sayfası + pile_load_selected_for_edit; BK/PD/kanal → Kontrollü Düzenleme paneli Önizle/Uygula); Bağlı Kot Uyumu; Bağlı Beton Sınıfı; Kapsam Kontrolü; Metrajı Aç; Model Sağlığı; Mesnet ve Bağlantı Kontrolü; özellik/uyarı panelleri.

| Giriş | Konum | Çalışma Alanı karşılığı | Gerekli mi | Öneri | Kaldırma etkisi |
|---|---|---|---|---|---|
| Sol menü "Eleman Düzenle" | ui.html:379 | Birebir aynı (ui.html:374 ile aynı çağrı) | Hayır | KALDIR | Başvuru yok; workspaceNav kalmalı |
| Kazık sayfası "✎ Eleman Düzenle" | ui.html:702 | Birebir aynı | Hayır (kazık sayfasında Oku/Güncelle var; Çalışma Alanı kazıkta bu sayfaya döner — döngü) | KALDIR | DUPS "T('editor'" (mst_workflow.js:168) eski |
| Eski "Eleman Düzenleyici" sayfası | ui.html:1079-1089 | Kısmen (önizleme onayı Çalışma Alanı'nı açar; bağımlılık ağacı listesi edDepList Çalışma Alanı'nda birebir yok; dependency_stamp = Bakım "dependency") | Erişim yalnız kılavuz g-t1 "Bu sayfayı aç" (mst_guide.js:105,193) | KALDIR (gizle) veya bağımlılık listesini BİRLEŞTİR | Ruby setEditorSelection/setDependencyAnalysis/showEditorChangePreview çağırıyor; JS işlevleri kalırsa test etkilenmez |
| TOOLS[0] editor | mst_workflow.js:24 | — | Yalnız kılavuz bağlantısı | Sayfayla birlikte KALDIR | Kılavuz g-t1 işlevsiz; kılavuz metni eski sayfayı anlatıyor; FLOW/TOOLS'ta project_workspace yok |
| pick.editor/NAVMAP.editor/addIcon/DUPS | mst_workflow.js:74,87,107,168 | — | Etkisiz | Ölü başvuru | Etkisiz |
| Seçili Eleman Bilgisi | ui.html:702,745,1082,1170 | Farklı yol | "Diğer" içinde sayfa başına tek | KORU | — |
| Eleman Kütüphanesi | ui.html:1082,1170; Bakım; eski menü | Yok | Evet (Bakım) | KORU | — |
| Model Kontrolü | adım 8, Metraj, menü, araç çubuğu, Bakım | Yok (model_health farklı) | Evet | KORU | — |
| BK sayfası Oku/Güncelle | ui.html:713,722 | Çalışma Alanı BK için AYRI Kontrollü Düzenleme formu (project_workspace.rb:160) | Evet (NCR-003 BK aynı form) | KORU; Çalışma Alanı BK düzenlemesi için BİRLEŞTİR değerlendir | BK'nın iki düzenleme formu var (NCR-003 çelişkisi) |
| Kazık sayfası Oku/Güncelle | ui.html:435,592,622 | Çalışma Alanı aynı yola gider | Evet | KORU | — |
Diğer: project_workspace.js:162 #pile_inline_edit src'de yok (kaydırma işlevsiz).

## Görev 2 — Son revizyon (D1–D5, Q1, Q2) bulguları
1. ORTA-YÜKSEK: Keşif iki kez hesaplanıyor — ui.html:381 `T('boq',this);refreshBOQ()` + ui.html:1178 T içinde `if(id==='boq')refreshBOQ()`; show_boq_engine (main.rb:10299) aynı. boq_refresh iki ayrı batch'te iki send_boq.
2. ORTA: Her işlemde tam yenileme — project_workspace.rb:172,177-186 onTransactionCommit'te sayfa bakılmadan project_workspace_refresh (yalnız dialog.visible?); DependencyModelObserver her commit'te batch dışı dependency_graph; controlled_editor_apply açık yenileme + gözlemci yenilemesi (iki tam yenileme). Önceden de vardı.
3. ORTA: Kontrollü Düzenleme parmak izi (controlled_editor.rb:70-80, 149, 186) Önizle/Uygula'da tüm Çalışma Alanı elemanları için revision_geometry_signature (önbelleksiz); ProjectWorkspace.entries işlem başına 3-5 kez.
4. DÜŞÜK-ORTA: Ağaç tıklamasında entries iki kez (project_workspace.rb:151,155).
5. ORTA: Revizyon kaydı batch dışında; boq2_boq_digest iki kez; revision_snapshots 3 kez ayrıştırılıyor (boq_pro.rb:904-931, 950-953, main.rb:10066).
6. DÜŞÜK: revisionMarkStale metni — kayıttan sonra "Son anlık kayıt" bilgisini siliyor; ilk açılışta 0 iken "son hesaplama" diyor; Keşif Farkı tablosu bayat işaretlenmiyor; kılavuz g-10a "her açılışta karşılaştırılır" diyor (mst_guide.js:97).
7. ORTA (veri kuralı): send_boq → boq_trace_payload → ensure_uid okuma yolunda işlem dışı element_uid/uid_owner_pid yazımı (main.rb:3909, 6461-6469); önbelleği bayatlatmıyor; model_audit 3 model attribute'unu koşulsuz işlem dışı yazıyor (main.rb:8722). SketchUp'ta Geri Al adımı / gözlemci tetiklenmesi belirsiz.
8. D1 + 1,5 s TTL: yeni bayatlama yok.
9. DÜŞÜK-ORTA: workflow_status her T(), her pencere odağı ve her Bakım işleminden sonra tam tarama (mst_workflow.js:293,303,317).
10. Bilgi: syncBar yalnız DOM.
11. Haberleşme bütünlüğü: callback'ler kayıtlı, execute_script hedefleri tanımlı; T sarmalayıcı zinciri çift sarmalamaya karşı korumalı.
12. DÜŞÜK: Q1 hashchange/:target kullanımı yok; kırılan kod yok.
Belirsiz: işlem dışı set_attribute'un SketchUp 2020'de Geri Al/onTransactionCommit etkisi; menü görsel sırası; revision_create_snapshot iki tanım (main.rb:10081 / boq_pro.rb:904) yükleme sırası.
