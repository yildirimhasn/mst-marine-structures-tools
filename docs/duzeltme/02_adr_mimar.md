# 02 ADR-0515 — mst-mimar karar kaydı (0.51.5 düzeltmeleri; satır numaraları 0.51.4'e göre)

## 1) R-5 / K06 kopyada UID — Karar B (gözlemci UID yazmaz)
- Yeni anahtar `uid_owner_pid` (Integer): ensure_uid (6198-6205) UID ürettiğinde ve finalize_bim_identity (6322-6326) çalıştığında eksikse yazılır; mst_copy_dicts! (11343) öğeyi başka varlıkla değiştirirse kaynak asıl sahipse/anahtar yoksa yeni varlığın pid'i yazılır.
- Asıl öğe sırası: (1) uid_owner_pid==persistent_id olan tek öğe; (2) UID `^MST-(\d+)-` içindeki pid'e sahip tek öğe; (3) en küçük persistent_id. Salt okuma yardımcısı `mst_uid_owner(candidates)` dependency_rebuild.rb'ye; karar yolunu ("kayıtlı sahip / UID içindeki PID / en eski PID") da döner.
- Kopyaya: yeni UID (`MST-<pid>-<t>-R`), `copied_from_uid` (String), `uid_owner_pid` (kendi pid). İlerleme: progress_items_json → `progress_inherited_json` (aynen taşı), progress_status → `progress_inherited_status`, sonra 'Planlandı'. Silme yok.
- Tretuvar (dependency_rebuild.rb:60-62): matches>1 ise mst_uid_owner kayıtlı sahip veya UID-PID ile tek aday döndürürse o bağlanır; "en eski PID" burada kullanılmaz (bağ kurulmaz).
- Onarımda tretuvar parent_uid yalnız tretuvar kopyaysa ve model uzayında XY merkezi tam bir kopya döşemenin sınır kutusu içindeyse kopya döşemeye çevrilir; diğerleri önizlemede "doğrulanmalı".
- Undo: repair_bim_identity mevcut işlemi (7470, 7504/7508).
- Uygulama: (a) repair_bim_identity — 7468 iletisine ilk 10 "asıl → kopya" + karar yolu; 7477-7482 mst_uid_owner ile; ilerleme taşıma + tretuvar adımları. (b) revision_diff (9256): tekrarlanan UID'de pid'i önceki kayıttaki pid'e eşit olan öğe UID'ye; öbürleri `"#{uid}~PID-#{pid}"` ile "eklendi". (c) revision_create_snapshot (boq_pro sarmalayıcısı) ve progress_save (boq_pro.rb:614) başında mükerrer UID varsa MB_YESNO: "Modelde N mükerrer UID var (kopyalanmış eleman). Revizyon/hakediş farkı yanıltıcı olabilir. Önce Model Kontrolü → BIM Identity Repair önerilir. Yine de devam edilsin mi?" (d) Model Kontrolü 7940 mesajına "kopya olası: <id>".
- Metraj: evet (kopyanın onaylı miktarı düşer; previous_* değişmez). SketchUp testi: Ctrl+Move döşeme+tretuvar.

## 2) R-3 / K09 + K58 paylaşılan tanım
- K58 (soru yok): mst_precast_def_params (11294) içinde öğede pc_rebar_json doluysa `h['rebar']='pc-v1:'+pc_rebar_json`; donatısız parçaların anahtarı değişmez.
- K09: main.rb'de mst_hb_ents yanına `mst_shared_def_prompt(e, islem)` → :not_shared/:unique/:cancel (yazmaz; yalnız ComponentInstance ve count_instances>1). İleti: "#{id}: bu eleman Component; tanımı #{n} yerde kullanılıyor. #{islem} yalnız bu parçaya uygulanacaksa parça ayrılır (Make Unique), diğer #{n-1} parça değişmez.\n\nEvet: yalnız bu parçayı ayır ve devam et\nHayır: iptal". `mst_make_unique_keep_data!(e)` (çağıranın işlemi içinde): eski tanımın DICT sözlüğünü sakla → e.make_unique → yeni tanımda eksik anahtarları açıkça kopyala; mst_def_kind/mst_def_key/mst_def_params_json yeni tanıma yazılmaz/silinir; `mst_def_unique_of` (String, eski anahtar) yazılır. Örnek öznitelikleri ve element_uid örnekte kalır.
- Çağrı: mst_cv_ui EKLE ve TEMİZLE (soru start_operation'dan önce, ayırma işlem içinde). mst_pc_ui onay metnine "seçilmemiş N parça aynı tanımı paylaşıyor; donatı onlara da uygulanır".
- Otomatik yollar (mst_cv_redraw!, mst_pc_after_rebuild!): paylaşılan Component'te çizim yok; `culvert_error` veya pc_rebar_error yazılır (Model Kontrolü, karar 11).
- Metraj: evet. SketchUp testi gerekli.

## 3) K22 döndürülmüş prekast — aşama 1
- `mst_bk_span_frame_error(b)`: ex = b.bounds.width(m) − width_m; width_m<=0 veya ex>0.005 ise Türkçe hata. Açı = transformation.xaxis ile model Y arasındaki açı. İleti: "#{id}: başlık kirişi model eksenine göre #{açı}° döndürülmüş. Prekast boyu yalnız model Y eksenine paralel BK'lar arasında ölçülebiliyor; bu yapıda boy yanlış çıkar. Prekast oluşturulmadı."
- Çağrı: 4281 ve 4421 messagebox+return (işlem açılmadan); 11130 öncesi `[nil, mesaj]`; 11681 warns; mevcut prekastlar için Model Kontrolü UYARI.
- Metraj: hayır. Aşama 2 (yerel eksende hesap) açık kaldı.

## 4) R-6 / K35 — Karar B (NN etikete kalıcı bağlanır, anahtar biçimi değişmez)
- Model DICT `pile_boq_group_codes_json` (String JSON) `{kaynak:{grup_anahtarı:NN}}`; grup_anahtarı `d=%.3f|t=%.3f`, PILE_INFILL için beton sınıfı. Bilinmeyen gruba max NN+1; silinen numara yeniden kullanılmaz.
- Kayıt yoksa bellekte: (1) hakediş geçmişindeki son dönem satırlarında name sonundaki `(…)` etiketi ↔ code sonundaki NN; (2) kalanlar bugünkü sırayla. Etiket iki gruba uyuyorsa tohumlanmaz.
- pile_boq_expand_rows (3583) NN'yi bu eşlemeden alır, yazmaz. Kalıcı yazım yalnız açık işlemlerde ve değişiklik varsa: progress_save, boq_set_prices, boq2_save_items, boq_set_pile_modes.
- Eski previous_* ve fiyat anahtarları silinmez. Bilinen sınır: geçiş öncesi kaymış dönemler geri hesaplanmaz; grup silinince numara boşluğu.

## 5) K50 gömülme
- `mst_hb_zone_segments(h,len)` (zone_info'nun süzmesiz listesi; zone_info bunu kullanır, çıktısı aynı). `mst_hb_bottom_depth(h,len,a)`: bölgeler üzerinde en büyük: f0≤a≤f1 → dz; a0≤a<f0 → dz·(a−a0)/(f0−a0); f1<a≤a1 → dz·(a1−a)/(a1−f1); diğer 0. (Uygulayıcı: uç dişler recess_profile_points/start_end_tooth_* ile de temsil ediliyorsa aynı derinlik mantığına dahil edilmeli — profil kaynağını doğrula.)
- Kazık a konumu: p.parent==b.parent ise T=p.transformation.origin, a=T.transform(b.transformation.inverse).x (m); değilse veya BK Component ise depth=0.
- emb=[pt,top].min−(bot−depth(a)). Ayak izi derinlik değişimini kesiyorsa Model Kontrolü UYARI "gömülme kazık eksenindeki taban kotundan hesaplandı". Kazık orijininin başlık merkezi olduğu sahte testle doğrulanır.
- Metraj: evet; golden-master.

## 6) Donatı
- K57: süzgeç (mst_dwg_rebar.rb:553,555) element_type=='head_beam' ∧ rebar_mode∈[drawing_detail,auto_detail] ∧ rebar_kind!='PAFTA'. İletiye: "Paftadan metrajı olan N BK ve prekast donatısı bu işlemle silinmez (Paftadan Donatı / Prekast Donatısı → SİL)."
- K63: mst_dr_clear! (382-397) rebar_prev_json yalnız yeniden kurma başarılıysa silinir; hatada mst_hb_rebar_clear!, rebar_prev_json korunur, `rebar_restore_error` yazılır; ComponentInstance ise kurmaya girilmez, aynı hata.
- K59 (main.rb:12029-12034, 12125-12127): hata durumunda pile_rebar_error yazılır, pile_cage_rebar_kg silinir, infill kafes hiç tanımlanmamış duruma (rebar_mode silinir, rebar_t pursantaj kuralının değeri — infill oluşturma yolundaki yazımdan birebir). Parametreler korunur; başarılı hesapta bayrak silinir. Okuma noktaları `mst_pile_rebar_effective?(p)` (12007, quantity_service.rb:36). mst_pile_rebar_active değişmez. Kabul: hata durumundaki tonaj = pile_rebar_mode boş olduğundaki tonaj.
- K60 (mst_pc_rebar.rb:244-249): hatada 3B set silinir; MST_PC_ATTRS'tan pc_rebar_json dışındakiler bu öğede silinir; pc_rebar_error yazılır. main.rb:3382 ve quantity_service.rb:43 pc_rebar_error doluysa atlanır. Başarılı mst_pc_draw! öğe ve eşlerindeki bayrağı siler.
- Undo: hepsi çağıranın işlemi içinde. Metraj: evet.

## 7) R-2 / K04, K05, K28
- Saf `mst_standardize_changes(model)` → [[e,k,v]]: eksik element_uid (+uid_owner_pid), eksik type_signature, type_id/library_type_id (biri boşsa diğerinden; ikisi boşsa registry — öğeler persistent_id sıralı, `registry[sig] ||= tid`), eksik schema_version, model düzeyinde eksik bim_schema_version/bim_core_revision. Boş yer tutucular (project/ano/axis/zone/parent_uid) yazılmaz; öğe 'revision' yazılmaz.
- standardize_model_metadata(own_op=true): değişiklik yoksa işlem açmaz, 0 döner. element_library(changed=nil): yazmaz; KPI `changed.nil? ? '—' : changed`; boş tid grubu "(Type ID yok)". bim_data_core_report: standardize kendi işlemiyle, sonra element_library(changed).
- stamp_dependency_metadata: tek işlem 'MST Dependency Engine 2.0'; standardize değişiklikleri işlem içinde; parent_uid ve support_left/right_uid yalnız boşsa; 8259-8262, 8269, 8271 elle dependency/revision yazımları kaldırılır (commit_with_dependencies yazıyor); değişiklik yoksa işlem açılmaz, "Değişiklik gerekmedi".
- 8243-8245: ensure_uid yerine salt okuma get_attribute.
- Metraj: hayır (BOQ CSV aynı kalmalı).

## 8) R-1 / K02, K03, K26
- boq_pro sarmalayıcısı: (1) revision_snapshots bozuksa Türkçe ileti, işlem açılmaz; (2) curr, boq2_boq_digest; (3) fark yok = revision_diff added/deleted/changed boş VE (önceki kayıtta boq yok veya boq2_boq_diff boş) → "Son revizyondan (#{ad}) bu yana modelde ve keşif miktarlarında değişiklik yok; yeni revizyon oluşturulmadı."; yalnız fiyat değişikliği revizyon üretmez; (4) numara = tüm Rev.(\d+) max + 1; (5) start_operation('MST Revizyon Kaydı',true) → snapshot+boq+currency → kırpmadan yaz → last_revision → commit; rescue'da abort + "Revizyon kaydedilemedi: …"; (6) revision_send işlem dışında.
- main.rb revision_create_snapshot → saf kurucu (ad korunur); revision_save_snapshots'tan last(20) kaldırılır; mst_rebar_tools.rb:484 h.last(MST_RT_HISTORY_MAX) kırpması kaldırılır (görüntüleme son N gösterebilir).
- Boyut uyarısı: >20 kayıt veya JSON >5 MB → "Revizyon arşivi büyüdü (N kayıt, X MB); eski kayıtlar otomatik silinmez."

## 9) K07, K53 kaplama
- collect_elements ve MST_COLLECTED_TYPES değişmez. Yeni `mst_collect_toppings(entities)` (Group, iç içe dahil): (a) 5919; (b) dependency_graph: kaplamalar all'a; bağ parent_uid ile döşemeye (karar 1 sahip tercihi), yoksa parent_deck_id ile tek eşleşme şartıyla; mst_bk_dependents kaplamayı döşemeyle aynı öteleme vektörüyle taşır (1939-1943, 12217-12222) — yalnız öteleme. children[/mst_direct_dependencies/dependency_graph kullanan yerler taranır; 'deck_topping' hiçbir yeniden kurma dağıtımına girmez.
- K53: mst_deck_regenerate! (5558 sonrası) döşemenin güncel topping_enabled, topping_thickness_m, topping_concrete_class değerlerini (varsa) data'ya yazar; 5089 deck_input_json'a yansıtır. Bilinen sınır: eğim genişliği yeniden hesaplanmaz. Fiziksel kaplama yeniden kurulmaz; yeni `parent_deck_revision_no` (Integer) oluşturmada yazılır; döşemenin deck_revision_no'su büyükse Model Kontrolü UYARI (anahtarsız eski kaplamada uyarı yok).
- Metraj: K07 hayır; K53 evet.

## 10) K51 kalıp yüz anahtarı
- `bk_formwork_face_keys(group)` → {face=>[konumlu, eski]}; konumlu `"#{eski}@#{i}/#{n}"` (aynı eski anahtarlı yüzlerin yerel bounds.min [x,z,y] mm sırası). Uygulama: önce konumlu, yoksa eski. Araç (2329) ve yüz yakalama (2228) yalnız konumlu yazar. n değişirse eski anahtara düşer.

## 11) G3 uyarı mekanizması
- Tek yer `mst_audit_v0515(elems)` → [[sev,e,check,msg,fix,pids]]; model_audit içinde 8069'dan sonra kendi begin/rescue ile; kategori 'Hesap Hatası', health_groups['QTO'] (8103). İçerik: pile_rebar_error (HATA), pc_rebar_error, rebar_restore_error, culvert_error; K22 döndürülmüş destek; K50 sınır uyarısı; K53 kaplama revizyonu; K23 ölçekli öğe. Sabit `MST_AUDIT_ERROR_FLAGS = {anahtar => [seviye, mesaj, öneri]}`. model_health.rb'ye dokunulmaz.

## Sınırlar
Dokunulmaz: collect_elements, MST_COLLECTED_TYPES, mst_pile_rebar_active, DependencyModelObserver, model_health.rb, runner'ın aradığı yöntem adları, mevcut anahtar adları/tipleri/UID'ler.
Yeni anahtarlar: uid_owner_pid (Int), copied_from_uid, progress_inherited_json, progress_inherited_status, rebar_restore_error, culvert_error, mst_def_unique_of (String), parent_deck_revision_no (Int), model DICT pile_boq_group_codes_json (String).
Golden-master: kararlar 2, 4, 5, 6, 9 (K53), 10.
Açık varsayımlar: make_unique tanım özniteliklerini kopyalıyor mu; kazık grup orijini başlık merkezi mi — sahte test/SketchUp ile doğrulanmalı.
