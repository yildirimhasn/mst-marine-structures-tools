# 07 Sürüm notu — MST 0.51.5 TB1 FIX1 (mst-dokumantasyon, 02.11.2026)

Kaynaklar: `01_plan_proje_yonetici.md`, `02_adr_mimar.md`, `03`–`06` parti raporları, `docs\denetim\00_BIRLESIK_DENETIM_RAPORU.md`, `docs\denetim\Ajan_Raporlari\10_dokumantasyon.md`. Bu notta yazan her madde bu raporlardan alınmıştır; raporda olmayan sayı veya sonuç eklenmemiştir.

## 1. Sürüm kaydı

| Sürüm | Kaynak | Tarih | Kurulu mu |
|---|---|---|---|
| 0.51.4 TB1 RUBY25 (temel) | Kullanıcı paketi `MST_v0.51.4_TB1_Ruby25_TEST.rbz`, SHA-256 `5684bec3375e57403c13b4c0476d8daa3547659a6b376a40274b53a303f2ac42` (02.11.2026 çalışma kopyasındaki kaynak RBZ'den). Çalışma kopyasında `docs\kaynak_MST_v0.51.4_TB1_Ruby25_TEST.rbz` | 28.10.2026 | 29.10.2026 denetiminde SketchUp 2020'de kurulu, 201/201 dosya aynı. Bugün yeniden doğrulanmadı |
| 0.51.5 TB1 FIX1 | Çalışma kopyası `mst_tb1` (git), parti commit'leri: A1 `25da577`, A2 `7244973`, B `38a7946`, C `6e48ee8`, D `8da4ec1`, E `f7046b5`, F `a31e168`, satır sonu `98222c5` | 02.11.2026 | Hayır. RBZ `distMST_v0.51.5_TB1_FIX1_TEST.rbz`, 201 dosya, 1.172.753 bayt, SHA-256 `e1ad035fc2c1e730f384fbe0be8a0b1c7969053095101fe7427a2d4bdea28d87`; src ile 201/201 aynı; iki üretimde aynı SHA |
| mst_tb1_integration_runner 1.1.0 | Kullanıcı test eklentisi (ayrı paket) | — | 29.10.2026'da kurulu; 0.51.4'ü bekler |

Yerel `mst` deposu (0.52.0-dev1) ayrı sürüm hattıdır; bu düzeltmeler orada yoktur, oradaki değişiklikler burada var sayılmaz.

Sürüm adları: `VERSION = '0.51.5'` (`qto_workspace.rb:4`), `MST_BUILD = 'v0.51.5 TB1 FIX1'` (`main.rb:27`). Durum: bu not yazılırken iki satır hâlâ 0.51.4 değerindeydi; değişiklik ana oturum/uygulayıcı tarafından yapılacak (Parti D raporu).

## 2. Değişiklik notu

### 2.1 Metraj sonucunu değiştirenler
Değerler sahte örneklerdir (elle beklenen = test sonucu, SketchUp dışı). Sahte fikstür golden-master (SketchUp dışı, 02.11.2026, `ruby tools/golden/run_golden.rb 872d3a3`, kaynak HEAD `8da4ec1`): 44 farklı anahtarın tamamı K36, K50, 08-R6 (§2.1), K08 gösterimi (§2.4) ve K33/K39 bilgi satırlarıyla (§2.2) eşlendi; sayısal farklar beklenen değere eşit; beklenmeyen 0 (`docs\duzeltme\golden\`). Fikstürün kapsamadığı (eylem sonucu oluşan) kalemler: K57, K58, K60, K63, K09, K53, K56, K17, DXF birim, K55, 08-R3, K35 geçmişli eşleme, K06, eğik kazık elipsi (oluşturma). SketchUp içi golden-master (08 satır 0.3) yapılmadı.

| Bulgu | Etkilenen kalem | Değişiklik | Örnek fark (0.51.4 → 0.51.5) | Kaynak |
|---|---|---|---|---|
| K50 | BK betonu (kazık gömülmesi düşümü) | Gömülme kazık eksenindeki taban kotundan (diş/alçak bölge); Component BK, çok akslı BK, farklı üst grup: eski kural | 0,1621 → 0,5675 m³ (π/4·1,016²·0,7); eğimli geçiş 0,1621 → 0,3648 m³ | A2 |
| K36 | Kazık iç betonu ve donatısı (Component kazık) | "İç beton YOK" önce denetlenir | 9,126 m³ / 2,281 t → 0 / 0 | A2; B (`pile_owned_concrete` sırası) |
| K59 | Kazık kafes donatısı | Hata durumunda pursantaja döner, `pile_rebar_error` + Model Kontrolü HATA | 0 t → 2,2814 t | A2 |
| K58 | Prekast donatısı (Component) | Donatılı parçanın tanım anahtarına donatı parametresi | 0,42 t sızma → yok | A2 |
| K60 | Prekast donatısı | Çizim hatasında eski kayıt silinir (`pc_rebar_json` hariç), `pc_rebar_error` | 0,5 t → 172,8 kg | A2 |
| K57 | BK / prekast / pafta donatısı | "Donatıyı Sil" yalnız BK ve PAFTA dışı kayıtlar | sayısal örnek raporda yok | A2, ADR §6 |
| K63 | BK donatısı geri yükleme | Önceki kayıt yalnız başarılı kurulumda silinir; aksi `rebar_restore_error` | sayısal örnek raporda yok | A2 |
| K09 | Menfez / prekast donatısı (paylaşılan tanım) | "Yalnız bunu ayır / iptal" sorusu; otomatik yolda paylaşılan tanıma çizim yok (`culvert_error`) | sayısal örnek raporda yok | A2, ADR §2 |
| 08-R6 | BK net kalıbı | Alt yüzlerin hiçbiri kalıpta değilse kazık açıklığı düşülmez (kısmi kapalıda eski kural) | 19,968 → 22,4 m² | A2 |
| Eğik kazık açıklığı | BK kalıp açıklığı | Daire yerine elips; BK oluşturma ve plan izleme | 0,810732 → 0,821915 m² | A2 |
| K51 | BK kalıbı | Yüz anahtarı konumlu; önce konumlu, yoksa eski anahtar | sayısal örnek raporda yok; ADR golden-master listesinde | B, ADR §10 |
| K53 | Kaplama alanı/hacmi | Döşeme yenilenince güncel kaplama değerleri korunur | 0 → 50 m² / 6,0 m³ | B |
| K56 | Dolgu Alt-1 hacmi | Aynı istasyonda kesit sırası istasyon + özgün sıra | sayısal örnek raporda yok | B |
| K17 | Menfez düşümü | Bozuk menfez kaydında yeniden çizim menfezi silmez, `culvert_error` | sayısal örnek raporda yok | B |
| DXF birim | Paftadan donatı tonajı | "L=" birimi `$INSUNITS`; yoksa sorulur, varsayılan m; regex mm/cm/m; otomatik pafta toleransı 0,006/birim (cm = eski 0,6) | sayısal örnek raporda yok | B |
| K55 | Dolgu Alt-1 tonajı | Bilinmeyen malzeme kodunda sessiz 0 yerine hata | 0 t (sessiz) → hata | A2 |
| 08-R3 | Hakediş (yedek yol) | Miktar ağırlıklı | 7,6 t → 0 | A2 |
| K35 | Kazık ayrı poz hakedişi | NN kesit etiketine kalıcı bağlanır (`pile_boq_group_codes_json`) | sayısal örnek raporda yok; geçiş öncesi kaymış dönemler geri hesaplanmaz | A2, ADR §4 |
| K06 | Hakediş ilerlemesi (kopya öğe) | BIM kimlik onarımı kopyanın ilerlemesini `progress_inherited_json`'a taşır (onaysız) | kopyanın onaylı miktarı düşer; `previous_*` değişmez | A1 |
| G1 (kod inceleme #2) | Hakediş ilerlemesi (kopyanın kopyası) | Önceki devralma kaydı olan kopya yeniden onarılınca `progress_items_json` silinir, durum 'Planlandı' olur; olay `progress_inherited_history_json`'a tek kayıt olarak eklenir, eski devralma alanları değişmez | ikinci kuşak kopyanın onaylı miktarı düşer (sahte nesne testinde onaylı oran 1 → 0); `previous_*` değişmez | G-a, g1_inherited_history |
| F1 | Ayrıntılı Metraj (Excel) sayfası — kazık içi beton | ad uyuşmazlığı ("Kazık İçi Betonu" ↔ "Kazık İçi Beton") yüzünden fiziksel iç beton satırı silinmiyor, yedek satır aynı hacmi tekrar ekliyordu (0.51.4'ten beri); ad tek yerden alınır | fikstür: 35,377 → 26,251 m³, donatı 8,344 → 6,063 t; yalnız bu Excel sayfası, Keşif/Özet değişmez (golden 321/321 aynı) | F, f1_infill_excel |
| G3-#13 | BK gömülme düşümü (özel durumlar) | kazık başına derinlik hatasında düşüm 0 yerine düz taban kuralıyla hesaplanır (depth_error UYARI); `registered_external` (Mevcut Elemanı Tanıt) kazıkta diş/bölge derinliği 0 alınır | yalnız hata durumu ve tanıtılmış kazık; golden fikstür değişmedi | G-a, g3_embed_errors |
| G4 (metraj kontrolü A) | Keşif ÖBF-004 donatı (REBAR), hakediş REBAR | Ayrı bordür / tretuvar öğesinin donatısı (beton hacmi × `rebar_rate('deck')`, varsayılan 150 kg/m³; ayrı oran yok) Keşif dökümüne "Bordür / Tretuvar" satırı olarak girer; REBAR izlemesi (hakediş eleman kümesi) bordürü içerir; K34 notu: bordür donatısı eleman ilerlemesiyle ödenir. Gövdesinde bordür betonu olan (DS2) döşemede ayrı bordür satırı yoktur. Yeni Model Kontrolü UYARISI: `curb_volume_m3` > 0 olan döşemeye ayrıca ayrı bordür öğesi bağlıysa (beton ve donatı çift sayılabilir). **Hakediş:** önceki dönemlerde onaylanmış bordürlerin donatısı bu dönem artışı olarak görünür; `previous_*` değişmez | fikstür (C1 1,2 + C2 0,6 + C3 0,3 m³): REBAR 19,674058 → 19,989058 t (+0,315 t); hakediş REBAR onaylı 0 → 0,18 t (önceden onaylı C1) | G-b, g4_curb_rebar |
| G5 (metraj kontrolü C) | Keşif / Metraj CSV | CSV, Excel Ayrıntılı Metraj ile aynı satırlardan (`mst_qto_detail_rows`) üretilir: BK betonu net, kazık iç betonu tek satır (tüm kaynaklar), Celik_t = boru çeliği, yeni `Donati_t` sütunu = Keşif ÖBF-004 dökümü (sehpa düşümü dahil); "Keşif ek kalemi" satırları: Kaplama Betonu (sınıf bazında), Sehpa, Aksesuar ankrajı. Malzeme/Sinif = `qto_material_class`. Fore kazık satırları da yazılır. Keşif değişmez | fikstür: ΣDonati_t = REBAR, ΣCelik_t = PILE_STEEL (0 → 54,808 t), BK 23,7 → 22,968 m³, iç beton 9,126 → 26,251 m³ (1e-6) | G-b, g5_csv_boq |
| G6 (metraj kontrolü B) | Pano ve Excel Özet "Toplam Beton" | Toplam Beton kaplama betonunu içerir (pano KAPLAMA kırılımı; Excel Özet'te "Beton Kaplama (sınıf)" satırları, sınıfsız kaplama C35/45); `qto3_snapshot`, Keşif ve Ayrıntılı Metraj sayfası değişmez | fikstür: 126,819 → 134,669 m³ (+7,85 m³ kaplama) | G-b, g6_total_concrete |

Plan G2'de metraj etkili sayılıp parti raporunda metraj etkisi yazılmayan: K42 (kazık formunda kot silinince çakım alanı temizlenir; C). K22 ADR'de "metraj: hayır" (prekast oluşturulmaz, aşama 1). Doğrulanmalı.

### 2.2 Yeni uyarılar (metraj değişmez)
- Model Kontrolü "Hesap Hatası" grubu (`mst_audit_v0515`): `pile_rebar_error`, `pc_rebar_error`, `rebar_restore_error`, `culvert_error`, `formwork_net_error`; K21 S7/S8 HATA (A2 G3, B).
- K22 aşama 1: döndürülmüş BK'da prekast oluşturulmaz, Türkçe ileti; mevcut prekastta UYARI (B).
- K23 ölçekli/aynalı öğe, K10 BK'sı değişen VK/BBK, K52 eski döşeme kaplaması, K54 PV diş/oturma, K53 kaplama revizyonu, K50 sınır uyarısı (B, ADR §11).
- K33/K39/K40 BOQ "BİLGİ" satırları: fiyatsız, toplam ve hakediş/Excel/CSV dışı (A2, C). K38 icmal ↔ cetvel uyarısı; K34 eşlenmemiş donatı notu.
- Mükerrer UID varsa revizyon ve hakediş kaydı öncesi soru (A1).
- Revizyon arşivi >20 kayıt veya >5 MB uyarısı (A1).

### 2.3 Düzeltmeler
- Revizyon (K02, K03, K26): kırpma yok; numara max Rev.NN+1; fark yoksa kayıt yok; tek işlem; hata → geri alma + Türkçe ileti. Donatı geçmişi kırpılmaz.
- Kimlik (K04, K05, K28): yalnız eksik alan yazılır; Eleman Kütüphanesi yazmaz; değişiklik yoksa işlem açılmaz.
- Bozuk kayıt (K19, K20, K27, R-4): bozuk JSON ezilmez, kaydetme reddedilir; aksesuar dosyası atomik yazılır.
- Kopya UID (K06): `uid_owner_pid`, `copied_from_uid`; revizyon farkında PID eşleşmesi; tretuvar asıl öğe tercihi.
- Undo (B): K11 ikinci commit kaldırıldı; K12 transparent işlemde commit + ileti; K13 rescue'da abort; K15 toplu prekast tek işlem (yarıda kalırsa tümü geri alınır); K14 dolgu yazımı; K62 Malzeme Ata / Canlı QTO tek işlem.
- K07 kaplama bağımlılık ağında (yalnız öteleme), K16, K18, K29 (Component BK yüz aracı, aks adı kaçışı, 9 callback), K61 tam dönüşüm zinciri.

### 2.4 Arayüz (C)
K24 `skp:` → `sketchup.<ad>()` (20 yer); K25 kronman hata metni; K01 Eleman Düzenle yalnız önizleme; K31 eski menü Keşif/BOQ; K45 kapatılan araç çubuğu geri gelmez; K42/08-R1 kot silinince çakım; K37 kazık önizleme = Kazık QTO; K08 Pano Kaplama satırı; K41 boru çeliği/donatı/dolgu ayrı sütun; K48 Türkçe iletiler.

## 3. Yeni attribute anahtarları ve eski modellerle uyumluluk
Hepsi yalnız eklenir; mevcut anahtar adı/tipi değişmez (G4). Eski modelde anahtar yoksa eski davranış veya "uyarı yok" geçerlidir.

| Anahtar | Tip | Yer | Eski modelde yoksa |
|---|---|---|---|
| `uid_owner_pid` | Integer | öğe | Asıl öğe UID içindeki PID'den, o da yoksa en eski PID'den seçilir (tretuvar bağında en eski PID kullanılmaz) |
| `copied_from_uid` | String | öğe (kopya) | Yalnız onarımda yazılır |
| `progress_inherited_json`, `progress_inherited_status` | String | öğe (kopya) | Yalnız onarımda; eski `progress_items_json` buraya taşınır (A1 sapması, ana oturum kabul etti) |
| `rebar_restore_error`, `culvert_error` | String | öğe | Uyarı yok |
| `mst_def_unique_of` | String | tanım | Yalnız "ayır" sonrası |
| `parent_deck_revision_no` | Integer | kaplama | Anahtarsız eski kaplamada uyarı yok |
| `link_support_state_json` | String | VK/BBK | K10 uyarısı yalnız kayıt varsa |
| `formwork_net_error` | String | öğe | Uyarı yok |
| `pile_boq_group_codes_json` | String | model | İlk açık kayıt işleminde (hakediş, fiyat, BOQ kalem, kazık poz modu) hakediş geçmişinden tohumlanır |
| `progress_inherited_history_json` | String (JSON dizisi) | öğe (kopya) | Yok = boş geçmiş. Yalnız BIM Kimlik Onarımı'nda, önceki devralma kaydı (`progress_inherited_json` / `progress_inherited_status`) dolu kopyaya yazılır; kayıt: `v, at, source, from_uid, new_uid, items_json, status, prev_copied_from_uid, prev_uid_owner_pid`. Bozuksa onarım yapılmaz (G1) |

Kaplama bağımlılık ağı (G8, kod inceleme #4): 0.51.5'te kaplama grupları (deck_topping) bağımlılık ağına girer. Kaplaması olan eski modelde, ilk MST işleminden veya modeldeki ilk değişiklikten sonra kaplama gruplarına dependency_parent_uids/ids ve dependency_schema='2.2', döşemelere dependency_child_uids/ids yazılır. Geometri ve metraj değişmez. Yazım o MST işleminin içinde ya da kullanıcının işlemine birleşen otomatik yenilemede (dependency_rebuild.rb:217-226) yapılır; Ctrl+Z ile o işlemle birlikte geri alınır. Model değişmiş görünür. Bu anahtarlar türetilmiş veridir; kimlik veya metraj kaynağı değildir. 0.51.4 ile açılınca davranış doğrulanmadı.
Ayrıca donatılı prekast tanım anahtarına `rebar` parametresi (`pc-v1:` + `pc_rebar_json`) eklenir; donatısız parçaların anahtarı değişmez. Konumlu kalıp yüz anahtarı (`eski@i/n`) eski anahtarın yanında kullanılır.

Keşif / Metraj CSV (G5): ilk 8 sütun (Kategori, Tip, Malzeme/Sinif, Adet, Boy_m, Beton_m3, Kalip_m2, Celik_t) yerinde kalır, sona `Donati_t` (t) eklenir. CSV'yi dışarıdan okuyan araçlar (tablo, makro, içe aktarma) 9. sütunu tanımalı veya yok saymalıdır; sütun sayısını 8 kabul eden araç hata verebilir. Ayrıca değerlerin anlamı değişir: Beton_m3 BK için net (gömülme ve açıklık düşülmüş), iç beton tek satır (tüm kaynaklar, Kategori `pile_infill_concrete`, Tip "Tüm kaynaklar"), Celik_t boru çeliği (önceden ham `weight_kg`, çoğu modelde 0), Malzeme/Sinif `qto_material_class`; yeni satırlar Kategori "Keşif ek kalemi" (Kaplama Betonu, Sehpa, Aksesuar ankrajı) ve `bored_pile`. Model özniteliği eklenmez.

## 4. Bilinen sınırlar / açık kalanlar
- Uygulanmadı (plan): K30 (ölü kod silinmez), K32, K43 (kullanıcı kararı), K44 (dalgakıran tanım belgesi yok), K49 ve TIN/boq_mapping O(n²) (ölçüm yok), derz harcı ve 08-R4 (belge gerekli), menfez–gömülme kesişimi (ertelendi). K46: hata bulunmadı, değişiklik yok (A2).
- Ara/kısmi çözüm: K33 (poz eşlemesi belge gerekli), K34, K38 (sözleşme kuralı gerekli), K39, K10 (yeniden kurma kuralı belgesi yok), K52, K54, K23 (yalnız uyarı), K22 aşama 2 (yerel eksende boy) açık.
- Açık belgeler: poz listesi/sınıf eşlemesi (K33), fiyat farkı kuralı (K38), tapa ve derz harcı tarifi (K39), dalgakıran tanımı (K44), paftada ankraj (R4), prekast pursantajı; `mst_dr_clear!` pursantaj oranı belge gerekli. K43 ve K48 terim listesi kullanıcı kararı (denetim §7 önerileri onaylanmadı).
- Geri getirilemez: 0.51.4'te önceden ezilmiş `revision` / `type_id` değerleri; K35 geçiş öncesi kaymış dönemler; silinen grubun numara boşluğu.
- K51 konumsuz eski kayıt eski anahtara düşer; K07 `parent_uid` dolu ama eşleşmiyorsa `parent_deck_id`'ye düşülmez; kaplama önizlemede "PID-n"; K23 çok örnekli tanımda zincir durur; otomatik paftada L= metre kabulü; K53 eğim genişliği yeniden hesaplanmaz; 08-R6 kısmi kapalı alt yüzde eski kural.
- Doğrulanmamış varsayımlar (ADR): `make_unique` tanım özniteliklerini kopyalıyor mu; kazık grup orijini başlık merkezi mi.
- C kapsam dışı notları: `main.rb` ~8941/8964 'Kazık İçi Betonu' ↔ 'Kazık İçi Beton' (Detailed QTO'da çift satır olasılığı, doğrulanmadı); `ui.html` ~1707 boş değer forma yazılmıyor (önceki kazığın kotu kalabilir); `ui.html` ~1965 kullanılmayan `drillingEditorToken`. B ayrı önerileri: VK temas BK formwork rescue nil, `boq_pro.rb:376` hata yalnız puts, `mst_schedule.rb:274` ve `mst_v50_piles.rb:459` işlem dışı yazım, U6 okuma işlevleri yazma, `element_visible_id` kaplama. K35 performansı ölçülmedi.
- Davranış değişikliği: K15 toplu yerleşim yarıda kalırsa tümü geri alınır; K62 Canlı QTO hatasında son sonuç kaydedilmez; bozuk kayıtta kaydetme reddedilir.
- `ui.html` satır içi betiklerden 1'i `node --check`'te FAIL (HEAD'de de aynı; çıkarma yöntemi kaynaklı, C raporu).

## 5. Runner uyarısı
Kurulu `mst_tb1_integration_runner` 1.1.0, 0.51.4 sürüm adını ve 0.51.4 dosya SHA-256 manifestini bekler. 0.51.5'te bu kontroller **beklenen şekilde başarısız** olur; paket hatası sayılmaz. Yöntem adı kontrolleri korunmuştur (G4). Runner için ayrı RBZ üretilmedi (ana oturum kararı, seçenek b).

## 6. Kanıt durumu
| Düzey | Durum |
|---|---|
| Statik | Parti C sonrası ana oturum çıktısı (02.11.2026): ruby -c hatasız, Ruby 2.5 dilbilgisi 66 dosya 0 hata, `node --check` OK, `src` içinde `skp:` = 0. Sürüm adı değişikliği ve paketleme sonrası yeniden çalıştırılmalı. Bu belge yazılırken çalıştırılmadı |
| Sahte nesne | A1 4, A2 9, B 4 test; tümü "0 kaldı" (parti raporları). Yalnız mantığı sınar |
| Golden-master BOQ/QTO (0.51.4 ↔ 0.51.5) | Sahte fikstür (SketchUp dışı, 872d3a3 ↔ 8da4ec1): 44 fark, beklenmeyen 0 (§2.1 notu). SketchUp içi CSV karşılaştırması yapılmadı; metrajı değiştiren işler "kabul bekliyor". Metin değişikliğinden sonra yeniden çalıştırılmalı |
| SketchUp 2020 kabulü | Denenmedi. Liste: `08_sketchup_kabul_listesi_0.51.5.md` |
| Görsel | Yok |
