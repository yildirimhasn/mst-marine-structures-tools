# 03 mst-mimar raporu (salt okuma)

Not: dependency_rebuild "Auto Rebuild" geometri kurmaz; yalnız dependency_* meta verisini yazar (67-92). Geometri yalnız açık komutlarla aktarılır; QTO attribute'lardan rapor anında okunur.
01'in observer tekrar ekleme riskine katılmıyor: model başına hash + tek AppObserver (dependency_rebuild.rb:181-182,189).

## Zincir
Kazık→BK bağlı (connected_pile_ids; piles_follow main.rb:1916-1931) · BK→prekast bağlı (support_left/right_pid = persistent_id; kot Δ taşıma 1938-1948, aks BK3 11113-11224, genişlik yalnız uyarı 1951-1954) · BK/prekast→döşeme yalnız taşıma (support_pids 5057,5835; ölçü yeniden kurulmaz) · döşeme→tretuvar bağlı (kopyada kopar) · döşeme→kaplama KOPUK · BK↔VK/BBK KOPUK · →metraj attribute tabanlı.

## Doğrulanmış hatalar (statik)
- H1 Yüksek: main.rb:9252 `arr.last(20)`, 9352 `n=snaps.length+1`, boq_pro.rb:840 `snaps.length>n0`. 21.+ snapshot: en eski kayıt sessizce silinir, her yeni kayıt "Rev.21" adını alır, keşif özeti (boq) yeni kayda eklenmez. Revizyon yalnız ileri yazılır kuralı ihlali. (Ana oturum satırları okuyup teyit etti.)
- H2 Yüksek: main.rb:6377-6403 standardize_model_metadata, element_library (6411; callback 10122) açılınca çağrılır → elemanlarda revision='v0.20.0', schema_version='2.0', model bim_schema_version='2.0' yazar (geri); aynı imzalı elemanların library_type_id'si tek ID'ye zorlanır, type_id üzerine yazılır. (Ana oturum teyit etti.)
- H3 Yüksek: kopyalamada UID çakışma tespiti/yeniden atama yok. Ctrl+Move döşeme+tretuvar → iki döşeme aynı element_uid; dependency_rebuild.rb:57-62 belirsiz eşleşmede asıl döşemenin tretuvar bağı da kopar; kopya pid ile asıl BK'yı gösterdiğinden BK kot değişikliği kopyayı da taşır.
- H4 Orta-Yüksek: main.rb:2098/2117 collect_elements kaplamayı (deck_topping) toplamaz → mükerrer kaplama kontrolü (5919) çalışmaz; 6007 dependency_child_uids observer tarafından silinir (dep.:71-78); BK kot/aks değişikliğinde kaplama taşınmaz; 7462/7920/9237 filtreleri ölü. Metraj döşeme attribute'undan (3469-3487) okunduğu için ikinci kaplama metrajı ikiye katlamaz; geometri ile metraj ayrışır.
- H5 Orta: mst_v50_beams.rb:131-165 mst_cv_ui çok örnekli Component BK'da menfezi paylaşılan tanıma çizer (main.rb:2784 mst_hb_ents) → boşluk/sac/kalıp düşümü tüm örneklerde; culverts_json yalnız seçili örnekte; "unique yap" sorulmaz (mst_bz_ui:210 Group şartı koyuyor).
- H6 Orta: dependency_rebuild.rb:31-36 VK/BBK BK'yı takip etmez; link_contact_json kopyada eski BK'yı gösterir.
- H7 Orta: main.rb:8263,8269 stamp_dependency_metadata tüm elemanlara revision='v0.20.0' yazar; tek ebeveynli elemanda parent_uid üzerine yazar (BK'ya kazık UID'si).
- H8 Orta: main.rb:9256 revision_diff UID ile hash → çakışan UID'de kopya görünmez/yerine geçer.
- H9 Düşük-Orta: snapshot yazımı start_operation dışında (9252, 9355; boq_pro.rb:843) → çoklu Undo adımı.

## Olası riskler
- Metraj transformation ölçeğini dikkate almıyor (quantity_service.rb); Scale ile geometri/metraj ayrışır; model denetimi işaretlemiyor. SketchUp testi.
- repair_bim_identity mükerrer UID'de ilk bulunanı asıl sayar; pile_id yeniden numaralamada BK connected_pile_ids güncellenmez (7477-7493).
- Eski döşemede topping_enabled yoksa kaplama metraja dahil (3473-3474).
- repair_deck_bim_relationships bounds ile mesnet tespiti, iç içe grupta uzay karışması (7522-7543); VK planı b1.bounds + transformation (mst_v50_beams.rb:306-317).
- İşlem açılmadan hata → abort_operation (6017-6018, 6406-6407; 5946 korumasız JSON.parse).
- Performans: her commit'te tüm bağımlılık grafiği + çalışma alanı tam yenileme (dep.:149; project_workspace.rb:170).

## Sorun bulunmadı
Transparent işlem kuralı (dep.:143-171), diğer observer'lar, kazık Component (853-905), prekast Component (11213-11214), BK form revizyonu (1773-1779, 1825-1827), relationship_audit (VK/BBK ve kaplama kapsam dışı).

## Kayıtlı veri
RevisionLog H1; MarineStructures H2/H7; MAG_MST_HealthHistory sözlüğü CLAUDE.md listesinde yok; eski döşeme stale (9602-9604) otomatik geçiş yok.

## Eksik
UID çakışma yeniden atama; kaplama ve VK/BBK grafikte yok; döşeme ölçüsü yeniden kurulmuyor.
