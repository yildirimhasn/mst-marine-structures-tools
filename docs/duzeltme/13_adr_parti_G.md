# 13 ADR-0515 ek — Parti G karar kaydı (mst-mimar, 02.11.2026)
Durum: Önerildi; kullanıcı kararı "Mimar karar versin, düzelt", "tüm önerileri yap". Satır numaraları c39c52c öncesi çalışma kopyasından.

## G1 — Kod inceleme #2: kopyanın kopyasında ilerleme (ORTA)
Sorun: main.rb:7701-7708 taşıma yalnız progress_inherited_json/_status boşsa; ikinci kuşak kopyada progress_items_json ve durum kalır → hakedişte çift sayım (hakediş yalnız progress_items_json/progress_status okur). copied_from_uid de üzerine yazılıyor.
Seçilen B: yeni anahtar `progress_inherited_history_json` (String, JSON dizisi); eski tekil alanlar değişmez (A: tip değiştirme, C: silme reddedildi).
Algoritma (repair_bim_identity, kopya e, UID u): pj=progress_items_json (boş değilse), ps=progress_status (boş değil ve ≠'Planlandı'). Eski alanlar boşsa bugünkü davranış. Doluysa olayın tamamı tek kayıt olarak geçmişe eklenir: {"v":1,"at","source":"repair_bim_identity","from_uid","new_uid","items_json","status","prev_copied_from_uid","prev_uid_owner_pid"}. Sonra progress_items_json silinir, progress_status='Planlandı'. Eski kayıtlar değişmez. Ön doğrulama (işlem açılmadan): geçmiş dolu ama dizi değilse "#{id}: devralınmış ilerleme geçmişi (progress_inherited_history_json) okunamadı; üzerine yazılmadı, onarım yapılmadı." ve dönülür. Önizleme iletisine (7684): "Önceki devralma kaydı olan kopyada yeni devralma geçmişe eklenir; eski kayıt değişmez."
Eski model: anahtar yoksa geçmiş boş. Undo: mevcut 'MST BIM Kimlik Onarımı' işlemi (7690/7734/7738); yeni start/commit yok. Metraj: hakediş değişir (kopyanın kopyası onaysız).
Test g1_inherited_history: ilk onarım; ikinci kuşak (geçmiş 1, eski alan bayt bayt aynı, prog2_frac=0); üçüncü kuşak (geçmiş 2); yalnız durum; bozuk geçmiş (işlem yok); asıl öğe değişmez; start=1 commit=1 abort=0.
SketchUp: D1 Onaylandı → Ctrl+Move → onarım → ilerleme gir → Ctrl+Move → onarım → son kopya onaysız → tek Ctrl+Z.

## G2 — #5 mst_copy_dicts! sahiplik devri (DÜŞÜK)
Seçilen B: own doluysa yalnız own.to_i==from.persistent_id ise devredilir; own nil ise UID `^MST-(\d+)-` değeri from.persistent_id ise devredilir; değilse/ayrıştırılamıyorsa yazılmaz. Yeni anahtar yok; çağıranın işlemi; metraj değişmez. Bilinen sınır: ayrıştırılamayan eski biçimli mükerrer UID'de "en eski PID" kararı kayabilir. Testler: X/Y çevirme senaryoları, E-biçimli UID. Kazık Group↔Component dönüşümü incelenmedi.

## G3 — #11, #12, #13
#11 doğrulandı: mst_dr_clear! (mst_dwg_rebar.rb:384) paylaşılan Component'te seti tanımdan (tüm örneklerden) siler, öznitelikleri yalnız seçili örnekte. Karar: mst_dr_remove_ui'de işlem öncesi count_instances>1 ve tanımın tüm örnekleri seçimde değilse mst_shared_def_prompt(e,'Çizimden donatı silme'); :cancel → iptal; :unique → işlem içinde mst_make_unique_keep_data!, sonra temizle. 383 geçmiş koşulu: `mst_dr_set_of(e).any? || %w[drawing_detail auto_detail].include?(rebar_mode)`. Metraj değişmez. Ayrı öneri: mst_rt_upgrade! (mst_rebar_tools.rb:184-202) paylaşım korumasız mst_dr_draw! çağırıyor.
#12 kısmen doğrulandı (0.51.5 ve 0.51.1 pid yazıyor; diğer sürümler incelenmedi). Karar (revision_diff, saf): ortak pid yoksa ve önceki tarafta tek kayıt → u'ya eşlenir; güncelde UID-PID'e eşit tek kayıt, yoksa en küçük pid. Önceki tarafta çok kayıt → "u~PID-#{pid}" ya da "u~REC-#{sıra}". Metraj değişmez.
#13 doğrulandı: 2580 rescue tüm BK düşümünü 0 yapıyor. Karar: derinlik hesabı kazık başına begin/rescue (hatada dep=0 + depth_error); dış rescue {volume_m3:0.0,items:[],error:}; registered_external kazıkta dep=0; mst_audit_v0515: :error → ERROR "BK gömülme düşümü hesaplanamadı (…); BK betonu brüt alındı.", depth_error → UYARI, orijin denetimi (BK yerel y∉[0,width_m] veya |origin.z − top_elevation_m|>0,01) → UYARI "kazık orijini kazık başı merkezi olmayabilir; gömülme derinliği doğrulanmalı". Metraj yalnız hata durumunda değişir.

## G4 — Metraj A: bordür donatısı Keşif'e (ÖBF-004 REBAR)
Kırılıma Döşeme'den sonra ['curb','Bordür / Tretuvar']; boq_trace_entities (3814) ve quantity_service.rb:107 curb dışlaması kaldırılır (deck_topping kalır), 106 açıklaması güncellenir; K34 notu yeni kapsama göre. Kaynak: hacim × rebar_rate('deck') (MST_REBAR_RATE_KEYS['curb']='deck'; ayrı oran için belge gerekli, rebar_rate_curb uydurulmaz). DS2 döşemede bordür gövdede → yeni satır 0; ayrı curb yalnız legacy yolda. Yeni Model Kontrolü UYARISI: ayrı curb öğesinin döşemesinde curb_volume_m3>0 (beton bugün de çift sayılıyor). Metraj değişir (+bordür donatısı); hakediş: geçmiş onaylı bordür donatısı bu dönem artışı görünür (kullanıcı bilgisine). Test: legacy döşeme+bordür → REBAR farkı = hacim×150/1000; DS2 → 0; izleme toplamı = REBAR.

## G5 — Metraj C: CSV = Keşif
Ortak salt okuma yardımcısı mst_qto_detail_rows(all,snapshot) (export_professional_excel 8943-8966 mantığı); Excel ve CSV kullanır. CSV 8 sütun yerinde, sonuna Donati_t. Celik_t = boru çeliği; Donati_t = mst_rebar_sum (sehpa düşümü kuralıyla), iç beton satırı mst_boq_rebar_breakdown 'pile'. Ek satırlar Kategori='Keşif ek kalemi': Kaplama Betonu, Sehpa, Aksesuar ankrajı. Malzeme/Sinif = qto_material_class. Kabul: ΣDonati_t=REBAR, ΣCelik_t=PILE_STEEL, BK Beton net, iç beton=PILE_INFILL (1e-6); sağlanmazsa fark satırıyla gizlenmez, iş durur. Keşif değişmez.

## G6 — Metraj B: Toplam Beton kaplamayı içerir
Toplam Beton = qto3_snapshot[:totals][:concrete_m3] + topping_quantities(all)[1] (qto3_snapshot değişmez). qto_summary: concrete_summary += topping_vol; concrete_breakdown['KAPLAMA']; DİĞER değişmez; 4019 "(Toplam Beton'a dahil; keşifte ayrı kalem ÖBF-072)", 4030 açıklaması; ui.html:1136 alt yazısına KAPLAMA; Excel Özet Toplam Beton + kaplama ve "Beton Kaplama (sınıf)" satırı. Fikstür 95,919 → 101,919 m³; Keşif değişmez.

## G7 — #9 bağımlılık grafiği (performans)
Grafik işlemde bir kez kurulur (stamp: döngü öncesi; repair: yazımlardan sonra). Önce ölçüm: tools/test/g7_dep_perf.rb n=50/200; çağrı sayısı + süre; ch listesi ve yazılan öznitelikler birebir aynı. Ölçüm yoksa uygulanmaz. Ayrı öneri: 7728-7732 döngüsü '2.1' yazıp commit_with_dependencies '2.2' ile eziyor (davranış değişikliği).

## G8 — #4 uyumluluk notu (07 §3)
"0.51.5'te kaplama grupları (deck_topping) bağımlılık ağına girer. Kaplaması olan eski modelde, ilk MST işleminden veya modeldeki ilk değişiklikten sonra kaplama gruplarına dependency_parent_uids/ids ve dependency_schema='2.2', döşemelere dependency_child_uids/ids yazılır. Geometri ve metraj değişmez. Yazım o MST işleminin içinde ya da kullanıcının işlemine birleşen otomatik yenilemede (dependency_rebuild.rb:217-226) yapılır; Ctrl+Z ile o işlemle birlikte geri alınır. Model değişmiş görünür. Bu anahtarlar türetilmiş veridir; kimlik veya metraj kaynağı değildir. 0.51.4 ile açılınca davranış doğrulanmadı."

## Sınırlar
Dokunulacak: main.rb repair_bim_identity, mst_copy_dicts!, revision_diff, mst_bk_pile_embed, mst_audit_v0515, mst_boq_rebar_breakdown, boq_trace_entities, export_boq_csv + mst_qto_detail_rows, export_professional_excel, qto_summary, stamp_dependency_metadata; quantity_service.rb:106-107; mst_dwg_rebar.rb mst_dr_remove_ui, mst_dr_clear!; ui.html:1136.
Dokunulmaz: collect_elements, MST_COLLECTED_TYPES, qto3_snapshot, dependency_graph kuralları, DependencyModelObserver, mst_uid_owner, model_health.rb, mevcut anahtar adları/tipleri/UID'ler, REBAR_DEFAULTS.
Golden-master: G1, G3-#13 (hata durumu), G4, G5, G6; fikstüre eski tip döşeme + bordür ve kopyanın kopyası eklenir.
