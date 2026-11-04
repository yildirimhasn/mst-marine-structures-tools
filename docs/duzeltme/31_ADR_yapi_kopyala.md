# 31 ADR-0515-K1 — Aks Yöneticisi "Yapıyı Kopyala": yapının tamamını tek işlemde N kez çoğaltma (mst-mimar, 04.11.2026; salt okuma, kod yazmadı, test çalıştırmadı)
Durum: Önerildi. Kaynak: `src/marine_structures_tools` @ `2cc5c29`. Kullanıcı hedefi (04.11.2026): mevcut "Yapıyı Kopyala" düğmesi genişletilir (yeni ana arayüz düğmesi yok); seçilen yapının tüm elemanları, geometrisi, donatısı, teknik verileri ve iç bağları tek işlemde N kopya; atomik (9. kopyada hata → hepsi geri); tek Ctrl+Z; kopyalar bağımsız; ilerleme "Planlandı", hakediş/QC/revizyon geçmişi aktarılmaz; kütüphane çoğaltılmaz.

## Bağlam (doğrulanan)
- JS `addStructure(copy)` (main.rb:13934) yalnız aks ağını tarayıcıda kopyalar; modele yazım `axis_manager_v2_save` (main.rb:13970-14018: `mst_plan_readonly`, `start_operation(...,true)`, `abort_operation`, `commit_with_dependencies`).
- `mstBKAddProjectStructure` (main.rb:10820-10838) `start_operation` açmadan `system_structures_json` / `axis_grids_json` yazar — Undo kuralı ihlali (ayrı küçük düzeltme).
- `mst_copy_structure_zone` (main.rb:11204) için çağıran bulunamadı; silinmez.
- Yapının tamamını öteleyen yol zaten var: `mst_structure_move_plans` / `mst_apply_structure_move_plans` (main.rb:13729-13796); aidiyet `mst_element_in_structure?` (main.rb:13706): `system` eşleşir, `structure` doluysa o, boşsa `ano`.
- Tutarsızlık: Keşif/hakediş önce `ano` sonra `structure` okur (boq_pro.rb:1049, 1124) → kopyada `structure`, `ano`, `zone` aynı yeni koda yazılmalı.

## Bulgular
1. Group/Component: tipsiz ComponentInstance kapsayıcıda toplayıcı definition içine iner (main.rb:2159) → kapsayıcı Component olarak kopyalanırsa iç öğeler aynı nesne kalır; kapsayıcı Group olarak kopyalanmalı, iç öğelere yazmadan önce ayrıştırılmalı. Kazık gövdeleri parametre anahtarıyla bilerek paylaşılır (`mst_def_find_or_create` main.rb:779-813), korunabilir. Component BK menfez/donatı düzenlemesi zaten "ayır" sorar (main.rb:2930, 2939; mst_v50_beams.rb:178-202; controlled_editor.rb:58 paylaşımlıyı reddeder). Type imzadan türetilir (main.rb:6651-6656), kopyada korunur.
2. Kimlik: `ensure_uid` biçimi `MST-<pid>-<time>` (main.rb:6483). Fiziksel ID tür bazında model genelinde benzersiz (main.rb:6636-6648, 7821-7832). Kimlik Onarımı `copied_from_uid` = kaynak UID (main.rb:7796) — anlam aynı; onarım ilerlemeyi devralır, yapı kopyası devralmaz. Aksesuar UID `SecureRandom.uuid` (accessories.rb:74).
3. Dönüşüm: aks yönü yalnız ±X/±Y (main.rb:13680, 13736); keyfi açı temsil edilemez. `toe_x_m/toe_y_m` yerel `axis_x_m` üzerinden (main.rb:630, 695). `azimuth_deg` çerçevesi belgesiz.
4. Kayıtlı veri: ilerleme öğe üzerinde (boq_pro.rb:438-465); RevisionLog model düzeyi anlık görüntü (main.rb:9952); öğe `revision` = şema damgası (main.rb:6661); `bk_revision_no`/`deck_revision_no`/`parent_deck_revision_no` birbirine bağlı (main.rb:6280, 8413-8416).
5. Bağımlılık: `dependency_graph` PID/ID ile bağlar, `project`/`ano` farklıysa bağlamaz (dependency_rebuild.rb:20-27). `mst_bk_connected_piles` PID → ID + ano süzgeci (main.rb:2592-2617).
6. Operasyon: Dependency/Workspace observer yalnız commit/undo/abort sonrası zamanlayıcıyla (dependency_rebuild.rb:206-233, project_workspace.rb:216-235); `commit_with_dependencies` önbellekleri commit öncesi yazar.

## Kararlar
- **K1 Kapsam:** kaynak kümesi `mst_structure_move_plans` kuralı + `mst_code_usage_extra` (main.rb:11808) tipli öğeleri. İç öğeler (pile_infill_concrete, *_rebar_set, bk_culvert, deck_topping, rebar_bar) üst öğeyle gelir. Ön kontrol (işlem açılmadan): system/structure/ano üçü boş tipli öğe; bağ hedefi başka yapıda olan öğe; karışık yapılı kapsayıcı → işlem başlamaz, "yapı / eleman / neden" listesi. Aksesuar (miktar çizelgeden, accessories.rb:68) — karar gerekli. Dolgu (rockfill; model düzeyi JSON main.rb:9833, yapı anahtarı yok) — ortak proje verisi, kopyalanmaz. special_solids / embed — `ano` yok; varsa ön kontrolde belirsiz. Etiket ve aks görseli kopyalanmaz, yeniden üretilir.
- **K2 Yöntem:** Group kopyası + iç yazımdan önce `make_unique` (SketchUp 2020'de doğrulanmalı; güvenli yol attribute sözlüklerini açıkça kopyalamak). ComponentInstance: `add_instance(defn,tr)` + attribute kopyası. Component BK ayrıştırma — karar gerekli. Type anahtarları değişmez.
- **K3 Kimlik:** yeni UID `MST-<yeni pid>-<time>-C`; `uid_owner_pid` = yeni PID; `copied_from_uid` = kaynak UID; isteğe bağlı `copy_origin='structure_copy'` (yeni anahtar, uyumluluk notu). Fiziksel ID `mst_next_unique_physical_id` ile model genelinde (önerim kuralı değiştirmemek). Eşlem tablolarıyla yeniden yazılacaklar — PID: `support_left_pid`, `support_right_pid`, `support_pids`, `connected_pile_persistent_ids`, `reference_pid`; UID: `support_*_uid`, `support_uids`, `parent_uid`, `parent_deck_uid`, `root_uid`, `fill_uid`; ID: `connected_pile_ids`, `pile_ids`, `parent_deck_id`, `parent_crown_id`, `support_hb_ids`. `type_uid` değişmez (main.rb:4562 bağlamı doğrulanmalı). Eşlemde karşılığı olmayan bağ ön kontrolde hata. `dependency_*` kopyalanmaz, `commit_with_dependencies` kurar.
- **K4 Dönüşüm:** ilk sürüm yalnız ofset (X/Y, isteğe bağlı Z); `global_x_m/global_y_m`, `global_origin_*` `mst_apply_structure_move_plans` kuralıyla; yerel alanlar (`axis_x_m`, `toe_*`, `grid_*_axis`, `axis`, `axis_span`, kotlar) aynen. Dönüş reddedilir (180° = x_dir/y_dir ters; azimut çerçevesi belgesiz → karar gerekli). Aks ağı `grids["SİSTEM::yeni"]`. Yerleşim önerisi ABSOLUTE (kaynağa bağlı yerleşim kaynağın kodunu kilitler main.rb:11841 ve kaynak taşınınca kopyaları da taşır main.rb:13755-13759).
- **K5 Kayıtlar:** kopyada `progress_items_json`, `progress_inherited_*`, `progress_inherited_history_json` yazılmaz; `progress_status='Planlandı'`. PROGRESS_DICT, MAG_MST_DR, MAG_MST_View, HealthHistory, RevisionLog'a dokunulmaz (kopyalar sonraki anlık görüntüde "eklendi"). Revizyon sayaçları: A) aynen taşı (önerilen) / B) hepsini birlikte 0. Model düzeyi: `system_structures_json`, `structure_display_names_json`, `axis_grids_json`, `structure_placements_json`.
- **K6 Atomiklik:** ön kontrol `mst_plan_readonly` içinde (kod benzersizliği, JSON koruması, aidiyet, bağ eşlemi, N sınırı) → tek `start_operation('MST Yapı Kopyala ×N',true)` → N kopya → son doğrulama → `commit_with_dependencies`; istisnada `abort_operation` + yeniden fırlatma (desen main.rb:13995-14006); transparent yok. `mst_scan_batch` içinde çalıştırılmaz (önbelleğe Group#copy kopyaları eklenmez, main.rb:2184-2189). Kazık dizini önbelleği (1,5 sn, main.rb:2582) doğrulamadan önce ve abort sonrası sıfırlanmalı. Son doğrulama: tür bazında sayı (kopya = kaynak), UID/ID benzersizliği, bağ hedefi aynı kopyada, kaynak imzası değişmedi, `QuantityService` kopya metrajı = kaynak. "Geri alındı" ancak abort sonrası kaynak imzası karşılaştırması tutarsa yazılır.
- **K7 Riskler:** `mst_bk_connected_piles` ID yolu (PID yeniden yazılınca düşülmez); `dependency_graph` ano kuralı (yeni kod zorunlu); Kimlik Onarımı (yeni UID/ID ile mükerrer görünmez); hakediş "ödenen azaldı" (beklenen); Keşif yapı sütunu (üç anahtar aynı); Aks Yöneticisi kaydedilmemiş değişiklik — önerim reddet.
- **K8 Test / sınır:** sahte nesne: aidiyet, eşlem/bağ yazımı, ID, ilerleme sıfırlama, 9. kopyada abort, kaynak imzası. Yalnız SketchUp: Group#copy attribute/definition ayrışması, persistent_id, Ctrl+Z/Redo, kaydet-yeniden aç, metraj ×3 golden, observer sonrası boş transparent işlem. Yeni modül `structure_copy.rb` (`mst_structure_copy_plan`, `mst_structure_copy_apply!`, `mst_structure_copy_verify`); main.rb: düğme bağlama, callback, require.

## Seçenekler
A) ayrı modül, tam kopya, yalnız ofset (önerilen) · B) dönüşlü (aks modeli + azimut çerçevesi belgelenmeden doğrulanamaz) · C) yalnız aks ağı (mevcut; hedefi karşılamaz).

**Metraja etki:** VAR (kopya kalemleri toplamı artırır; kaynak değişmemeli) → CHANGELOG "Metraj sonucunu değiştirenler" + golden-master.

**Dokunulmayacak:** `dependency_rebuild.rb`, `finalize_bim_identity`, `repair_bim_identity`, `mst_bk_connected_piles`, `collect_elements`/`MST_COLLECTED_TYPES`, QTO formülleri, boq_pro, RevisionLog, PROGRESS_DICT, `mst_copy_structure_zone`.

## Açık kararlar (kullanıcı)
1 Component BK kopyada ayrıştırılsın mı · 2 Aksesuar ilk sürüme dahil mi · 3 Revizyon sayaçları A/B · 4 Yerleşim ABSOLUTE mi · 5 Dönüş ilk sürümde reddedilsin mi · 6 Kaydedilmemiş Aks Yöneticisi değişikliği · 7 Fiziksel ID biçimi.
Kullanıcı kararları bu bölümün altına eklenecek.

## Kullanıcı kararları (04.11.2026)
1. Component BK: **kopyada ayrılır** (`mst_make_unique_keep_data!` deseni; her yapı kendi definition'ı).
2. Aksesuar (usturmaça vb.): **ilk sürümde kopyalanmaz**; kopya sonunda "N aksesuar kopyalanmadı, çizelgeye elle ekleyin" bildirilir. Sonra ayrı iş.
3. Revizyon sayaçları: **A** (aynen taşınır) — ana oturum önerisi, kullanıcı itiraz etmedi.
4. Yerleşim: **ABSOLUTE** (kaynağa bağlanmaz) — ana oturum önerisi.
5. Dönüş: **ilk sürüm yalnız ofset**; dönüş istenirse "henüz desteklenmiyor"; azimut çerçevesi doğrulanınca ikinci aşama.
6. Kaydedilmemiş Aks Yöneticisi değişikliği varken kopya **reddedilir** — ana oturum önerisi.
7. Fiziksel ID: **model genelinde sıradaki numara** (mevcut kural).
Ek: `mstBKAddProjectStructure` operasyon düzeltmesi kullanıcının genel onayı ("gerekli teknik düzenlemeler") kapsamında bu işe dahil. Dolgu (rockfill) ortak proje verisi, kopyalanmaz.

## İnceleme sonrası kararlar (04.11.2026; rapor 32 / 33)
8. Jet grout satırında elle girilmiş ilerleme (manual_progress_json, yüzde) varken kaynak yapıda jet grout bulunursa **kopya reddedilir** (kullanıcı kararı; hakediş şişmez). Eleman bazlı jet grout ilerlemesi ayrı iş.
9. Component prekast tanımı **ortak kalır** (Type semantiği; kaynak yapı içindeki aynı tip prekastlar bugün de paylaşır); kopya sonu iletisinde ve kabul listesinde yazılır (kullanıcı kararı).
10. MAG_MST_DR ve MAG_MST_View kopyaya aktarılır (eleman tanımının teknik / görünüm verisi; saha kaydı değil). K5 "dokunulmaz" = kaynak ve model düzeyi kayda yazılmaz (ana oturum kararı, rapor 32/9).
11. Rapor 32/1–8 ve 33/2, 4, 5, 6 düzeltilir.
