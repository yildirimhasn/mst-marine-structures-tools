# 07 Sürüm notu — MST 0.51.5 TB1 FIX1 (mst-dokumantasyon, 02.11.2026)

Kaynaklar: `01_plan_proje_yonetici.md`, `02_adr_mimar.md`, `03`–`06` parti raporları, `docs\denetim\00_BIRLESIK_DENETIM_RAPORU.md`, `docs\denetim\Ajan_Raporlari\10_dokumantasyon.md`. Bu notta yazan her madde bu raporlardan alınmıştır; raporda olmayan sayı veya sonuç eklenmemiştir.

## 1. Sürüm kaydı

| Sürüm | Kaynak | Tarih | Kurulu mu |
|---|---|---|---|
| 0.51.4 TB1 RUBY25 (temel) | Kullanıcı paketi `MST_v0.51.4_TB1_Ruby25_TEST.rbz`, SHA-256 `5684BEC3…2AC42` (denetim raporu §0; tam değer burada kayıtlı değil). Çalışma kopyasında `docs\kaynak_MST_v0.51.4_TB1_Ruby25_TEST.rbz` | 28.10.2026 | 29.10.2026 denetiminde SketchUp 2020'de kurulu, 201/201 dosya aynı. Bugün yeniden doğrulanmadı |
| 0.51.5 TB1 FIX1 | Çalışma kopyası `mst_tb1` (git), parti commit'leri: A1 `25da577`, A2 `7244973`, B `38a7946`, C ve D: ana oturum kaydı (son commit `6e48ee8` C sonrası) | 02.11.2026 | Hayır. RBZ `MST_v0.51.5_TB1_FIX1_TEST.rbz` henüz üretilmedi; SHA-256 paketleme sonrası yazılacak |
| mst_tb1_integration_runner 1.1.0 | Kullanıcı test eklentisi (ayrı paket) | — | 29.10.2026'da kurulu; 0.51.4'ü bekler |

Yerel `mst` deposu (0.52.0-dev1) ayrı sürüm hattıdır; bu düzeltmeler orada yoktur, oradaki değişiklikler burada var sayılmaz.

Sürüm adları: `VERSION = '0.51.5'` (`qto_workspace.rb:4`), `MST_BUILD = 'v0.51.5 TB1 FIX1'` (`main.rb:27`). Durum: bu not yazılırken iki satır hâlâ 0.51.4 değerindeydi; değişiklik ana oturum/uygulayıcı tarafından yapılacak (Parti D raporu).

## 2. Değişiklik notu

### 2.1 Metraj sonucunu değiştirenler
Değerler sahte örneklerdir (elle beklenen = test sonucu, SketchUp dışı). Golden-master yapılmadı.

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
Ayrıca donatılı prekast tanım anahtarına `rebar` parametresi (`pc-v1:` + `pc_rebar_json`) eklenir; donatısız parçaların anahtarı değişmez. Konumlu kalıp yüz anahtarı (`eski@i/n`) eski anahtarın yanında kullanılır.

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
| Golden-master BOQ/QTO (0.51.4 ↔ 0.51.5) | Yapılmadı. Metrajı değiştiren işler "kabul bekliyor" |
| SketchUp 2020 kabulü | Denenmedi. Liste: `08_sketchup_kabul_listesi_0.51.5.md` |
| Görsel | Yok |
