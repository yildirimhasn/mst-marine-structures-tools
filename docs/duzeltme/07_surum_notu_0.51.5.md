# 07 Sürüm notu — MST 0.51.5 TB1 FIX1 (mst-dokumantasyon, 02.11.2026; son durum güncellemesi 02.11.2026, kaynak `eaaa858`; §1 paket satırları ve §6 kanıt tablosu: mst-test-paketleme, 02.11.2026, kaynak `c8f9d70`, bu oturumun komut çıktıları)

Kaynaklar: `01_plan_proje_yonetici.md`, `02_adr_mimar.md`, `03`–`06` parti raporları, `09_parti_E_turkce.md`, `10_parti_F_uygulayici.md`, `11_metraj_kontrol.md`, `12_kod_inceleme.md`, `13_adr_parti_G.md`, `14_parti_G-a_uygulayici.md`, `15_parti_G-b_uygulayici.md`, `16_kabul_denetim.md`, `docs\denetim\00_BIRLESIK_DENETIM_RAPORU.md`, `docs\denetim\Ajan_Raporlari\10_dokumantasyon.md` ve ana oturumun 02.11.2026 son komut çıktıları (kaynak `eaaa858`). Bu notta yazan her madde bu kaynaklardan alınmıştır; kaynakta olmayan sayı veya sonuç eklenmemiştir. Bu belge yazılırken mst-dokumantasyon komut çalıştırmadı.

## 1. Sürüm kaydı

| Sürüm | Kaynak | Tarih | Kurulu mu |
|---|---|---|---|
| 0.51.4 TB1 RUBY25 (temel) | Kullanıcı paketi `MST_v0.51.4_TB1_Ruby25_TEST.rbz`, SHA-256 `5684bec3375e57403c13b4c0476d8daa3547659a6b376a40274b53a303f2ac42` (02.11.2026 çalışma kopyasındaki kaynak RBZ'den). Çalışma kopyasında `docs\kaynak_MST_v0.51.4_TB1_Ruby25_TEST.rbz` | 28.10.2026 | 29.10.2026 denetiminde SketchUp 2020'de kurulu, 201/201 dosya aynı. Bugün yeniden doğrulanmadı |
| 0.51.5 TB1 FIX1 | Çalışma kopyası `mst_tb1` (git), parti commit'leri: A1 `25da577`, A2 `7244973`, B `38a7946`, C `6e48ee8`, D `8da4ec1`, E `f7046b5`, F `a31e168`, satır sonu `98222c5`, G arayüz `c39c52c`, G-a `7e2e9c7`, G-b `eaaa858`, Parti H arayüz `8d7d431`, Parti H Ruby `c8f9d70` (son kaynak) | 02.11.2026 | Hayır (SketchUp'ta kurulmadı, denenmedi). RBZ `dist\MST_v0.51.5_TB1_FIX1_TEST.rbz`, kaynak commit `c8f9d70` (src temiz), 201 dosya, 1.181.367 bayt, SHA-256 `75c0ea66779cbe8d89fb193d07f847cfcdc9549450a272c03c5f79adf278c773`; manifest `dist\MST_v0.51.5_TB1_FIX1_TEST.manifest.txt`; paket ↔ src 201/201 aynı; geçici klasöre ikinci üretim aynı SHA; 0.51.4 paketine göre eklenen 0 / çıkan 0; `unzip -t` hatasız; geçersiz pakete göre içeriği farklı 9 dosya = `git diff eaaa858 c8f9d70 -- src` 9 dosya (mst-test-paketleme, bu oturum) |
| 0.51.5 önceki paketler (geçersiz) | `dist\gecersiz_e1ad035f\`; `dist\gecersiz_454daf8e\` (kaynak `eaaa858`, Parti H öncesi; 02.11.2026'da silinmeden taşındı) | 02.11.2026 | Hayır. İkisi de geçersiz; kurulmamalı, kabulde kullanılmamalı (yerine geçti: yukarıdaki `c8f9d70` paketi) |
| mst_tb1_integration_runner 1.1.0 | Kullanıcı test eklentisi (ayrı paket) | — | 29.10.2026'da kurulu; 0.51.4'ü bekler (§5). 0.51.5 için kullanılmaz (yerine geçti: 1.2.0) |
| mst_tb1_integration_runner 1.2.0 (0.51.5 için) | `runner\` (src dışı; `tools\package.rb` paketine girmez), temel 1.1.0. Paket `dist\MST_TB1_Integration_TestRunner_v1.2.3_for_0.51.5.rbz`, 3 dosya, 17.384 bayt, SHA-256 `a02b4383ab28514c96f3f3f96dabeae896a98d646b84b71719a0e37805cb59ea`, manifest `…manifest.txt`; `tools\package_runner.rb` ile, iki üretim aynı SHA, `unzip -t` hatasız. Beklenen sürüm `0.51.5` / `v0.51.5 TB1 FIX1`; `expected_sources.json` `c8f9d70` src'sinden (201 dosya; yeni MST paketiyle 201/201 aynı) | 02.11.2026 | Hayır (SketchUp'ta kurulmadı). Sahte nesne (SketchUp dışı) çalıştırmada çekirdek testler 31 geçti / 0 hata; 1.1.0 aynı ortamda 29 / 2 hata (sürüm, dosya SHA) |
| 0.51.5 TB1 FIX1 — 03.11.2026 kaynak devamı | Çalışma kopyası `mst_tb1` (git), commit'ler: arayüz sadeleştirme `a5ea937`, Çalışma Alanı Bağımlılıklar `7e804c9`, isimlendirme `b99ced8` + `c1e3a59`, gecikmeler G1–G6 `10e520d`, rapor 25/26 düzeltmeleri `b0a2592`, prekast NCR-003 seçenek A `0983966`, rapor 27/28 düzeltmeleri `930876a` (son kaynak). Ayrıntı §2.8 | 03.11.2026 | Hayır (SketchUp'ta kurulmadı, denenmedi). RBZ adı, dosya sayısı ve SHA-256: **paketleme sonrası yazılacak** |

Yerel `mst` deposu (0.52.0-dev1) ayrı sürüm hattıdır; bu düzeltmeler orada yoktur, oradaki değişiklikler burada var sayılmaz.

**Kurulu sürüm notu (02.11.2026, ana oturum SHA-256 kontrolü; mst-dokumantasyon bu kontrolü kendisi çalıştırmadı):** SketchUp 2020'de kurulu olan MST v0.52.6 AUDIT CANDIDATE'tir; en yakın paket `MST_v0.52.5_Audit_Candidate.rbz` (204/209 dosya aynı). Bu ayrı bir sürüm hattıdır; 0.51.5 düzeltmeleri orada var sayılmaz, oradaki değişiklikler burada var sayılmaz (`17_adr_parti_H.md` kapsam satırı). Kullanıcı kararı (02.11.2026): sürüm hattı "0.51.5 ile devam"; 0.51.5 kurulumu v0.52.6 AUDIT CANDIDATE'in yerine geçer. *(Yerine geçti: yukarıdaki tabloda 0.51.4 için "29.10.2026 denetiminde SketchUp 2020'de kurulu" bilgisi 02.11.2026 itibarıyla geçerli değil; kurulu sürüm bu nottaki gibidir.)*

Sürüm adları: `VERSION = '0.51.5'` (`qto_workspace.rb:4`), `MST_BUILD = 'v0.51.5 TB1 FIX1'` (`main.rb:27`). Durum: koddadır (Parti E `f7046b5`; 16 H2a "karşılandı", kaynak metni). *(Yerine geçti: bu notun ilk yazımındaki "iki satır hâlâ 0.51.4 değerindeydi" ifadesi artık geçerli değil.)* Rozetler ve pencere başlığının SketchUp'ta görünümü denenmedi (08, adım 0.1).

## 2. Değişiklik notu

### 2.1 Metraj sonucunu değiştirenler
Değerler sahte örneklerdir (elle beklenen = test sonucu, SketchUp dışı). Sahte fikstür golden-master (SketchUp dışı) zinciri parça parça yapıldı (§6): 872d3a3 ↔ 8da4ec1 44 farklı anahtarın tamamı K36, K50, 08-R6 (§2.1), K08 gösterimi (§2.4) ve K33/K39 bilgi satırlarıyla (§2.2) eşlendi, beklenmeyen 0; E, F ve G-a adımlarında fark 0; 7e2e9c7 ↔ eaaa858 (genişletilmiş fikstür) 45 fark, beklenmeyen 0 (`docs\duzeltme\golden\`). *(Yerine geçti, 02.11.2026: uçtan uca 0.51.4 ↔ c8f9d70 fikstür karşılaştırması yapıldı; Excel Ayrıntılı Metraj sayfası dışındaki bölümler eşlendi — §6.)* Önceki kayıt: **Uçtan uca 0.51.4 ↔ eaaa858 karşılaştırması yok**: genişletilmiş fikstürün CSV, Excel (Özet/Ayrıntılı Metraj), REBAR izlemesi ve hakediş bölümlerinin 0.51.4 karşılığı üretilmedi (0.51.4 kural seti genişletilmiş fikstürle çalıştırılmadı; fark CSV'sindeki `eski_0514` sütun adı bu karşılaştırmada yanıltıcıdır, 15 ve 16). Fikstürün kapsamadığı (eylem sonucu oluşan) kalemler: K57, K58, K60, K63, K09, K53, K56, K17, DXF birim, K55, 08-R3, K35 geçmişli eşleme, K06, eğik kazık elipsi (oluşturma). SketchUp içi golden-master (08 satır 0.3) yapılmadı.

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
| H4b | Başlık kirişi kalıbı (kazık yönelimi değişince) | Seçili Kazıklara Yönlendirme Uygula artık bağlı BK'nın kazık açıklığını (eğik kazıkta elips) ve net kalıbını aynı işlemde yeniden yazar; önceden kayıtlı açıklık güncellenmiyordu | fikstür: 1:6 eğik Ø1016'da açıklık +0,011183 m², net kalıp −0,011183 m² (FORMWORK_CAST); golden 8d7d431 ↔ yeni 12 fark, beklenmeyen 0 | H, h_h4b_orientation |
| G4 (metraj kontrolü A) | Keşif ÖBF-004 donatı (REBAR), hakediş REBAR | Ayrı bordür / tretuvar öğesinin donatısı (beton hacmi × `rebar_rate('deck')`, varsayılan 150 kg/m³; ayrı oran yok) Keşif dökümüne "Bordür / Tretuvar" satırı olarak girer; REBAR izlemesi (hakediş eleman kümesi) bordürü içerir; K34 notu: bordür donatısı eleman ilerlemesiyle ödenir. Gövdesinde bordür betonu olan (DS2) döşemede ayrı bordür satırı yoktur. Yeni Model Kontrolü UYARISI: `curb_volume_m3` > 0 olan döşemeye ayrıca ayrı bordür öğesi bağlıysa (beton ve donatı çift sayılabilir). **Hakediş:** önceki dönemlerde onaylanmış bordürlerin donatısı bu dönem artışı olarak görünür; `previous_*` değişmez | fikstür (C1 1,2 + C2 0,6 + C3 0,3 m³): REBAR 19,674058 → 19,989058 t (+0,315 t); hakediş REBAR onaylı 0 → 0,18 t (önceden onaylı C1) | G-b, g4_curb_rebar |
| G5 (metraj kontrolü C) | Keşif / Metraj CSV | CSV, Excel Ayrıntılı Metraj ile aynı satırlardan (`mst_qto_detail_rows`) üretilir: BK betonu net, kazık iç betonu tek satır (tüm kaynaklar), Celik_t = boru çeliği, yeni `Donati_t` sütunu = Keşif ÖBF-004 dökümü (sehpa düşümü dahil); "Keşif ek kalemi" satırları: Kaplama Betonu (sınıf bazında), Sehpa, Aksesuar ankrajı. Malzeme/Sinif = `qto_material_class`. Fore kazık satırları da yazılır. Keşif değişmez | fikstür: ΣDonati_t = REBAR, ΣCelik_t = PILE_STEEL (0 → 54,808 t), BK 23,7 → 22,968 m³, iç beton 9,126 → 26,251 m³ (1e-6) | G-b, g5_csv_boq |
| G6 (metraj kontrolü B) | Pano ve Excel Özet "Toplam Beton" | Toplam Beton kaplama betonunu içerir (pano KAPLAMA kırılımı; Excel Özet'te "Beton Kaplama (sınıf)" satırları, sınıfsız kaplama C35/45); `qto3_snapshot`, Keşif ve Ayrıntılı Metraj sayfası değişmez | fikstür: 126,819 → 134,669 m³ (+7,85 m³ kaplama) | G-b, g6_total_concrete |
| NCR-003 seçenek A (`0983966`, `930876a`) | Metraj sayfası prekast PD / PK tablosu (satır dağılımı) | Kontrollü Düzenleme ile geometrisi değişen prekastın `precast_type_id` / `precast_type` adı BK boyutlandırma kuralıyla güncellenir; PD satır anahtarı `precast_type` + sınıf + genişlik + yükseklik, PK anahtarı `precast_type_id` + iç ölçüler olduğundan düzenlenen parçanın satırı ayrışabilir | ör. PD-01 satırı PD-01 / PD-01-B olarak ikiye ayrılır; **toplam değişmez** (tip adı / gruplama kaynaklı fark yok; düzenlenen parçanın kendi geometri değişikliği metraja ayrıca yansır). Keşif, CSV, Excel (`library_type_id`), revizyon imzası ve hakediş anahtarları tip adı içermez. Sayısal golden kanıtı yok (fikstürde tip adı yok; golden Kontrollü Düzenleme yolunu sınamıyor) — kod okuması, rapor 28 | 28 |

Plan G2'de metraj etkili sayılıp parti raporunda metraj etkisi yazılmayan: K42 (kazık formunda kot silinince çakım alanı temizlenir; C). K22 ADR'de "metraj: hayır" (prekast oluşturulmaz, aşama 1). Doğrulanmalı.

### 2.2 Yeni uyarılar (metraj değişmez)
- Model Kontrolü "Hesap Hatası" grubu (`mst_audit_v0515`): `pile_rebar_error`, `pc_rebar_error`, `rebar_restore_error`, `culvert_error`, `formwork_net_error`; K21 S7/S8 HATA (A2 G3, B).
- K22 aşama 1: döndürülmüş BK'da prekast oluşturulmaz, Türkçe ileti; mevcut prekastta UYARI (B).
- K23 ölçekli/aynalı öğe, K10 BK'sı değişen VK/BBK, K52 eski döşeme kaplaması, K54 PV diş/oturma, K53 kaplama revizyonu, K50 sınır uyarısı (B, ADR §11).
- K33/K39/K40 BOQ "BİLGİ" satırları: fiyatsız, toplam ve hakediş/Excel/CSV dışı (A2, C). K38 icmal ↔ cetvel uyarısı; K34 eşlenmemiş donatı notu.
- Mükerrer UID varsa revizyon ve hakediş kaydı öncesi soru (A1).
- Revizyon arşivi >20 kayıt veya >5 MB uyarısı (A1).
- G3-#13 (G-a): Model Kontrolü'nde BK gömülme düşümü hesaplanamazsa HATA "BK gömülme düşümü hesaplanamadı (…); BK betonu brüt alındı."; kazık başına derinlik hatasında UYARI; kazık orijini denetimi UYARI "kazık orijini kazık başı merkezi olmayabilir; gömülme derinliği doğrulanmalı" (bilinen sınır: iç içe ötelenmiş kapta yanlış uyarı olası).
- G4 (G-b): ayrı bordür öğesi bağlı DS2 döşemede (`curb_volume_m3` > 0) çift sayım UYARISI (§2.1).
- #8 (G-a): Model Kontrolü sağlık kutularına bağlı olmayan kontrol adları gruplara bağlandı (+ 'Kanal Cebi').

### 2.3 Düzeltmeler
- Revizyon (K02, K03, K26): kırpma yok; numara max Rev.NN+1; fark yoksa kayıt yok; tek işlem; hata → geri alma + Türkçe ileti. Donatı geçmişi kırpılmaz.
- Kimlik (K04, K05, K28): yalnız eksik alan yazılır; Eleman Kütüphanesi yazmaz; değişiklik yoksa işlem açılmaz.
- Bozuk kayıt (K19, K20, K27, R-4): bozuk JSON ezilmez, kaydetme reddedilir; aksesuar dosyası atomik yazılır.
- Kopya UID (K06): `uid_owner_pid`, `copied_from_uid`; revizyon farkında PID eşleşmesi; tretuvar asıl öğe tercihi.
- Undo (B): K11 ikinci commit kaldırıldı; K12 transparent işlemde commit + ileti; K13 rescue'da abort; K15 toplu prekast tek işlem (yarıda kalırsa tümü geri alınır); K14 dolgu yazımı; K62 Malzeme Ata / Canlı QTO tek işlem.
- K07 kaplama bağımlılık ağında (yalnız öteleme), K16, K18, K29 (Component BK yüz aracı, aks adı kaçışı, 9 callback), K61 tam dönüşüm zinciri.
- F2 (F): tanımsız JS işlevleri (`loadSelectedBimPile`, `setDrillingEditor`, `drillingEditError`) çağrıları `typeof` korumalı; işlev yoksa dialog içinde Türkçe yönlendirme. Callback'ler ve Ruby yöntemleri silinmedi.
- G-a: G2 `mst_copy_dicts!` sahiplik devri yalnız kaynak PID eşleşirse; G3-#11 paylaşılan Component BK'da çizimden donatı silmeden önce "yalnız bunu ayır / iptal" sorusu (`mst_dr_remove_ui`, `mst_rt_upgrade_ui`); G3-#12 PID'siz eski revizyon kayıtlarında eşleme (`u~PID-n` / `u~REC-n`); #1 bozuk dolgu kesit zinciri (`rockfill_section_chain_json`) kaydetme/otomatik kayıtta ezilmez, yüklemede uyarı; #6 araç çubuğu "donatıyı sil" yolunda bozuk kayıt reddi Türkçe ileti; #7 bozuk `pile_boq_group_codes_json` yalnız AYRI POZ modunda kaydı engeller; #10 toplu prekast hatasında Türkçe ileti.
- G-b: G7 bağımlılık grafiği işlemde bir kez kurulur (ölçüm: stamp n=200 201 → 2 çağrı, 0,537 → 0,026 s; repair n=209 417 → 2, 1,140 → 0,013 s; son durum imzaları birebir; sahte nesne ölçümü); ara '2.1' şema yazımı kaldırıldı. 'ALL' kazık kapsamı: "Projedeki tüm kazıklar" seçeneği (varsayılan değişmedi: ACTIVE).

### 2.4 Arayüz (C)
K24 `skp:` → `sketchup.<ad>()` (20 yer); K25 kronman hata metni; K01 Eleman Düzenle yalnız önizleme; K31 eski menü Keşif/BOQ; K45 kapatılan araç çubuğu geri gelmez; K42/08-R1 kot silinince çakım; K37 kazık önizleme = Kazık QTO; K08 Pano Kaplama satırı; K41 boru çeliği/donatı/dolgu ayrı sütun; K48 Türkçe iletiler.

### 2.5 Arayüz — Türkçeleştirme ve 0.51.5 rozetleri (Parti E, `f7046b5`)
Dayanak: kullanıcı kararı 02.11.2026 "0.51.5 çekilsin, bütün açıklamalar isimler her şey türkçe olsun" (09). 33 dosya ±443 satır; golden 321 anahtar, farklı 0 (metin işi metrajı değiştirmedi; sahte fikstür).
- Terimler: Marine Structures Tools → Deniz Yapıları Araçları (MST); BOQ → Keşif; QTO → Metraj; Professional QTO/Excel → Ayrıntılı Metraj (Excel); Model Audit → Model Kontrolü; Element Library → Eleman Kütüphanesi; Identity Repair → Kimlik Onarımı; Dependency Engine → Bağımlılık Motoru; Data Core → BIM Veri Çekirdeği; Snapshot → Anlık Kayıt; Offset → Kaçıklık; Override → Özel Değer.
- Excel sayfa adları: Özet, Ayrıntılı Metraj, Eleman Kütüphanesi, Kazık Metrajı, Keşif USD, Fore Kazık, Taş Dolgu.
- CSV başlıkları ASCII Türkçe: Kategori, Tip, Malzeme/Sinif, Adet, Boy_m, Beton_m3, Kalip_m2, Celik_t (BOM'suz UTF-8 nedeniyle); G5 ile sonuna `Donati_t` eklendi (§2.1).
- Türkçeleştirilmeyen (bilinçli istisna, kullanıcı onayı bekliyor; §4.1): araç çubuğu adları, `EXTENSION.creator`, modelde saklanan grup adları, aksesuar seçenek değerleri, JSON kataloglar, SketchUp terimleri (Component/Group/Tag), teknik kısaltmalar; README arşiv başlığı İngilizce (16 H2b). *(02.11.2026: kullanıcı kararı "Kabul, böyle kalsın" — §4.1.)*
- Davranış etkisi: §2.7.

### 2.6 Arayüz — G arayüz partisi (`c39c52c`)
Bu partinin ayrı raporu yoktur (16 §Boşluklar); içerik ana oturum bildirimi ve kaynak metninden yazılmıştır.
- K34 notu (metraj kontrolü D, 11): hakediş REBAR satırındaki "Hakedişe eleman bazında girmeyen donatı" notu nedenleri arasında kazık içi beton donatısını (parametreli / BIM kafes) da yazar; G-b ile "Bordür / tretuvar donatısı eleman ilerlemesiyle ödenir" eklendi (`boq_pro.rb:523`). Metin değişikliği; REBAR tavanı değişmez.
- "Kazık İçi Beton" yazımı tek terim: `src` içinde "Kazık İçi Betonu" kalmadı (16 H4d, kaynak metni; F'de açık kalan `main.rb:4192` ve `unified_catalog.json` yazımı). SketchUp görünümü denenmedi.
- KAPLAMA anahtarı: pano Toplam Beton kırılımında `KAPLAMA` (alt yazı "BK + PD + DOSP + KAPLAMA + KRONMAN + ÇBK", `ui.html:1136`); metraj etkisi G6 altında (§2.1).

### 2.7 Davranış değişiklikleri (kullanıcıyı/dış araçları etkileyebilir)
- **Keşif / Metraj CSV (G5):** 9. sütun `Donati_t` eklendi; sütun sayısını 8 kabul eden dış araç hata verebilir. `Celik_t` anlamı değişti: boru çeliği (önceden ham `weight_kg`, çoğu modelde 0). Beton_m3 BK için net; iç beton tek satır; yeni satır türleri ("Keşif ek kalemi", `bored_pile`). Ayrıntı §3 sonu.
- **Excel sayfa adları (E):** Türkçe adlar (§2.5); sayfa adına göre okuyan makro/bağlantılar etkilenebilir.
- **Eklenti adı (E):** "Deniz Yapıları Araçları (MST)". Extension Manager'daki etkin/pasif durumu ve Extensions menü yoluna atanmış kısayollar sıfırlanabilir (doğrulanmadı).
- **G4 hakediş etkisi:** önceki dönemlerde onaylanmış ayrı bordürlerin donatısı ilk 0.51.5 hakedişinde bu dönem artışı olarak görünür; `previous_*` değişmez (fikstür +0,18 t).
- **G6:** pano ve Excel Özet "Toplam Beton" kaplamayı içerir; önceki raporlarla karşılaştırmada fark kaplama hacmidir.
- **F1:** Ayrıntılı Metraj sayfasında kazık iç betonu tek satır; önceki Excel çıktılarıyla karşılaştırmada iç beton satırı azalır.
- Önceden kayıtlı (B): K15 toplu yerleşim yarıda kalırsa tümü geri alınır; K62 Canlı QTO hatasında son sonuç kaydedilmez; bozuk kayıtta kaydetme reddedilir (§4'te de geçer).

### 2.8 İsimlendirme, gecikmeler ve prekast Kontrollü Düzenleme (mst-dokumantasyon, 03.11.2026; kaynak `930876a`)
Kaynaklar: `21`–`28` raporları ve ana oturumun commit bildirimi. Bu bölüm yazılırken mst-dokumantasyon komut çalıştırmadı. Hiçbiri SketchUp içinde denenmedi.

**Metraj sonucunu değiştirenler:** yalnız NCR-003 Kontrollü Düzenleme prekast tip adı — §2.1 son satır (toplam değişmez, Metraj sayfası PD/PK satırı ayrışabilir). Diğer maddelerde golden 433/433 aynı (23, 24, §6.1).

**Yeni uyarılar / ret iletileri (metraj değişmez):**
- Aks Yöneticisi: yapı kodu silinmiş ya da başka yerde kullanılan bir koda değiştirilirse ret; hedef kod denetimi harf farksızdır (`mst_name_key`, sunucu ve JS aynı; 27/K5) (`b0a2592`, `930876a`).
- Aks Yöneticisi: kullanılan yapı silinirken uyarı + onay; onaysız ret (`b0a2592`). Silme denetimi yalnız görünen yapı listesinden (`mst_structures_for_system`) yapılır (27/K1, `930876a`).
- Yeni yapı / aks kodu karakter kümesi: harf, rakam, boşluk, `-` `_` `.`; parantez, virgül vb. ret. Görünen ad kuralı değişmedi (23: harf, işaret, rakam, boşluk, `- _ . ( ) # + &`); eski kodlar denetlenmez (`b0a2592`).
- Kullanılan aks kodu yükten kalkarsa işlem öncesi Türkçe hata; Aks Yöneticisi önizlemesinde onaylanmışsa kaydedilir (24 G5b).
- Model Kontrolü iletileri düzenlendi (`b0a2592`; ayrıntı 25/26 raporlarında; 27 bu kısmı incelemedi).
- Kontrollü Düzenleme: mesnetli PD'de geometri değişikliği ve Component prekast reddedilir (Türkçe ileti) (`0983966`).

**Düzeltmeler:**
- İsimlendirme (`b99ced8`, `c1e3a59`; ADR 22, rapor 23): yapı ve aks için Görünen Ad ile Kod ayrı; gösterim "Ad (kod)"; kullanılan kod kilitli (arayüzde); C seçeneği — koşullar sağlanırsa yapı kodu değiştirilebilir (kendi ızgarası ve bölge listesi taşınır). Aks ekle/sil sonrası "JS HATASI" giderildi (`renderPlacementSelectors`).
- Kod kullanım taraması (`mst_code_usage`): jet grout, iç içe aks görseli ve "X-01↔X-02" durumları (`b0a2592`; ayrıntı 25/26).
- Gecikmeler G1–G6 (`10e520d`, rapor 24): Çalışma Alanı sayfa kapalıyken yenilenmez, açılınca yenilenir; Kontrollü Düzenleme parmak izi yalnız hedef + bağımlılık ağacı (bilinçli davranış farkı: ilgisiz elemanın iç geometrisi değişirse uygulama artık reddedilmez); revizyon kaydında `boq_rows` 2 → 1; Aks Yöneticisi değişikliksiz kayıtta işlem açmaz ("Değişiklik yok — Geri Al adımı oluşmadı"). Sahte ölçümler (n=600): 24 G6.
- Keşif Motoru açılışında tek yenileme (`b0a2592`).
- Çalışma Alanı: BK düzenle sonrası bekleyen BK sayfası açılışı, başka eleman seçilince uygulanmaz (`b0a2592`).
- Prekast tip adı (`0983966`, `930876a`): geometri değişince `precast_type_id` / `precast_type` BK boyutlandırma kuralıyla — aynı tür + temel tip + ölçüde tip varsa o ad, yoksa "<temel>-B…"; temel tip `precast_base_type_id` (mevcut anahtar, BK yolunda da kullanılıyor). Ad yalnız kayıtlı `precast_type_id` varsa ve mm ölçü anahtarı değişince güncellenir (27/K2, K3); tip kaydı `collect_elements` kapsamından (iç içe prekast dahil; 27 ek, 28).

**Arayüz:**
- Arayüz sadeleştirme (`a5ea937`; envanter 21).
- Çalışma Alanı "Bağımlılıklar" (`7e804c9`).
- Çalışma Alanı ağacı yapı koduyla kurulur; aynı görünen adlı iki yapı ayrı düğümdür (`b0a2592`).
- Excel: Keşif "Poz Metrajları" 4 → 5 sütun, Hakediş "Onaylı Metraj" 9 → 10 sütun ("Yapı" görünen ad + "Yapı Kodu"); CSV değişmedi (23). Dışarıdan sütun konumuna göre okuyan araçlar etkilenebilir (§2.7 ile aynı tür davranış değişikliği).
- Prekast NCR-003 seçenek A (`0983966`): Çalışma Alanı → Elemanı Düzenle, prekastta Kontrollü Düzenleme formunu Prekast sayfasında açar; alt sekme PD / PK (kanal) parçaya göre seçilir; önizlemede "Prekast tipi" satırı.

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
| `structure_display_names_json` | String (JSON `{kod: ad}`) | model | Yok veya bozuk → görünen ad yok, kod gösterilir; okumada yazım yok. Boş ya da koda eşit ad kaydedilmez; bozuksa üzerine yazılmaz (`c1e3a59`/`b99ced8`, 23) |
| `axis_display_names_json` | String (JSON `{"<ano>::<zone>": {"x":{kod:ad},"y":{kod:ad}}}`) | model | Aynı kural (23) |

Kaplama bağımlılık ağı (G8, kod inceleme #4): 0.51.5'te kaplama grupları (deck_topping) bağımlılık ağına girer. Kaplaması olan eski modelde, ilk MST işleminden veya modeldeki ilk değişiklikten sonra kaplama gruplarına dependency_parent_uids/ids ve dependency_schema='2.2', döşemelere dependency_child_uids/ids yazılır. Geometri ve metraj değişmez. Yazım o MST işleminin içinde ya da kullanıcının işlemine birleşen otomatik yenilemede (dependency_rebuild.rb:217-226) yapılır; Ctrl+Z ile o işlemle birlikte geri alınır. Model değişmiş görünür. Bu anahtarlar türetilmiş veridir; kimlik veya metraj kaynağı değildir. 0.51.4 ile açılınca davranış doğrulanmadı.
Ayrıca donatılı prekast tanım anahtarına `rebar` parametresi (`pc-v1:` + `pc_rebar_json`) eklenir; donatısız parçaların anahtarı değişmez. Konumlu kalıp yüz anahtarı (`eski@i/n`) eski anahtarın yanında kullanılır.

Keşif / Metraj CSV (G5): ilk 8 sütun (Kategori, Tip, Malzeme/Sinif, Adet, Boy_m, Beton_m3, Kalip_m2, Celik_t) yerinde kalır, sona `Donati_t` (t) eklenir. CSV'yi dışarıdan okuyan araçlar (tablo, makro, içe aktarma) 9. sütunu tanımalı veya yok saymalıdır; sütun sayısını 8 kabul eden araç hata verebilir. Ayrıca değerlerin anlamı değişir: Beton_m3 BK için net (gömülme ve açıklık düşülmüş), iç beton tek satır (tüm kaynaklar, Kategori `pile_infill_concrete`, Tip "Tüm kaynaklar"), Celik_t boru çeliği (önceden ham `weight_kg`, çoğu modelde 0), Malzeme/Sinif `qto_material_class`; yeni satırlar Kategori "Keşif ek kalemi" (Kaplama Betonu, Sehpa, Aksesuar ankrajı) ve `bored_pile`. Model özniteliği eklenmez.

## 4. Bilinen sınırlar / açık kalanlar
- Uygulanmadı (plan): K30 (ölü kod silinmez), K32, K43 (kullanıcı kararı), K44 (dalgakıran tanım belgesi yok), K49 ve TIN/boq_mapping O(n²) (ölçüm yok), derz harcı ve 08-R4 (belge gerekli), menfez–gömülme kesişimi (ertelendi). K46: hata bulunmadı, değişiklik yok (A2).
- Ara/kısmi çözüm: K33 (poz eşlemesi belge gerekli), K34, K38 (sözleşme kuralı gerekli), K39, K10 (yeniden kurma kuralı belgesi yok), K52, K54, K23 (yalnız uyarı), K22 aşama 2 (yerel eksende boy) açık.
- Açık belgeler: poz listesi/sınıf eşlemesi (K33), fiyat farkı kuralı (K38), tapa ve derz harcı tarifi (K39), dalgakıran tanımı (K44), paftada ankraj (R4), prekast pursantajı; `mst_dr_clear!` pursantaj oranı belge gerekli. K43 ve K48 terim listesi kullanıcı kararı (denetim §7 önerileri onaylanmadı). *(Düzeltme 02.11.2026, 16: K43 terim sorunu değildir, aks işlevlerine erişim sorunudur — §4.1. K48 terim listesi Parti E ile kullanıcı kararına dayanarak uygulandı — §2.5.)*
- Geri getirilemez: 0.51.4'te önceden ezilmiş `revision` / `type_id` değerleri; K35 geçiş öncesi kaymış dönemler; silinen grubun numara boşluğu.
- K51 konumsuz eski kayıt eski anahtara düşer; K07 `parent_uid` dolu ama eşleşmiyorsa `parent_deck_id`'ye düşülmez; kaplama önizlemede "PID-n"; K23 çok örnekli tanımda zincir durur; otomatik paftada L= metre kabulü; K53 eğim genişliği yeniden hesaplanmaz; 08-R6 kısmi kapalı alt yüzde eski kural.
- Doğrulanmamış varsayımlar (ADR): `make_unique` tanım özniteliklerini kopyalıyor mu; kazık grup orijini başlık merkezi mi.
- C kapsam dışı notları: `main.rb` ~8941/8964 'Kazık İçi Betonu' ↔ 'Kazık İçi Beton' (Detailed QTO'da çift satır olasılığı, doğrulanmadı) — **giderildi (0.51.5, F1 `a31e168` + G arayüz `c39c52c`)**: çift satır F1 ile düzeltildi (sahte nesne testi f1_infill_excel), yazım tek terim (src içinde "Kazık İçi Betonu" 0); SketchUp'ta denenmedi (08). `ui.html` ~1707 `mstLoadCommonPileForm` boş değer forma yazılmıyor (önceki kazığın kotu kalabilir) — açık. `ui.html` ~1965 kullanılmayan `drillingEditorToken` — açık (K30 kapsamı). B ayrı önerileri: VK temas BK formwork rescue nil, `boq_pro.rb:376` hata yalnız puts, `mst_schedule.rb:274` ve `mst_v50_piles.rb:459` işlem dışı yazım, U6 okuma işlevleri yazma, `element_visible_id` kaplama — açık. K35 performansı ölçülmedi. *(Yerine geçti, 02.11.2026: sahte nesne ölçümü yapıldı, eşik 1 s aşılmadı — §6; SketchUp içi ölçüm 08 H-9.)*
- Davranış değişikliği: K15 toplu yerleşim yarıda kalırsa tümü geri alınır; K62 Canlı QTO hatasında son sonuç kaydedilmez; bozuk kayıtta kaydetme reddedilir. (Tüm davranış değişiklikleri: §2.7.)
- `ui.html` satır içi betiklerden 1'i `node --check`'te FAIL (HEAD'de de aynı; çıkarma yöntemi kaynaklı, C raporu). *(Sonraki durum: G-a/G-b ve son kaynak eaaa858'de `check_inline_js` 20/20; eski çıkarma yöntemiyle yeniden çalıştırılmadı.)*

### 4.1 Kabul denetimi (16) boşlukları ve sonraki açık kalanlar (02.11.2026, kaynak eaaa858)
- **K43**: terim sorunu değil; aks organizasyonu / elle aks işlevlerine (`main.rb:9199`, `9278`) arayüzden erişim sorunu. Hiçbir partide açılmadı — açık, kullanıcı kararı.
  - **Karara bağlandı (kullanıcı kararı 02.11.2026): "Elle aks maddesi + metin düzelt"** (`17_adr_parti_H.md` H1, öneri B + C): eski menüye "Seçili Elemana Elle Aks Ata…" maddesi; yalnız `axis` ve `axis_assignment='manual'` yazılır; `auto_organize_project` bağlanmaz; Model Kontrolü metni bu maddeye yönlendirilir. Uygulama Parti H'de, kod henüz bitmedi; test ve SketchUp kabulü yok.
- **K30 ölü kod**: gizli `pile_mfg_edit` paneli, kullanılmayan callback'ler, `drillingEditorToken`. "Tüm önerileri yap" talimatı silme onayı sayılmaz (CLAUDE.md üç koşulu: çağrı araması, kayıtlı veri etkisi, kullanıcı onayı) — açık, kullanıcı kararı.
  - **Karara bağlandı (kullanıcı kararı 02.11.2026): "Yalnız 13 güvenli kalem"** — `18_olu_kod_analizi.md` "GÜVENLE SİLİNEBİLİR" 13 kalem silinebilir; KOŞULLU 7 kalem (ör. `pile_mfg_edit` paneli/JS/callback, `drilling_edit` + `pile_drilling.rb`, `pile_load_selected_bim`, `universal_edit`, `boq_element_detail` zinciri) ve SİLİNMEMELİ 2 kalem (`mstPileUnifiedEditSurface`, `mst_selected_bim_pile_payload`) kalır. Silmenin uygulanma durumu bu notta kayıtlı değil.
- **K32** (`ui.html:325` inset/min() yedek CSS) — açık. *(Parti H, H2 — ana oturum kararı: yalnız kazık özel ayarları kipine yedek CSS; genel flex gap yedeği eklenmez. Uygulama sürüyor.)* **K49** yalnız bağımlılık grafiği kısmı yapıldı (G7). **Menfez–gömülme kesişimi** uyarısı yapılmadı.
- **B ayrı önerileri** açık: VK temas BK formwork rescue nil; `boq_pro.rb:376` send_boq hatası yalnız puts; `mst_schedule.rb:274` ve `mst_v50_piles.rb:459` işlem dışı yazım; U6 okuma işlevlerinin yazması; `element_visible_id` kaplama.
- **A2 açık önerileri**: K35 performansı ölçülmedi *(yerine geçti: sahte nesne ölçümü §6)*; kafes donatısı yönelimi değişince açıklık güncellemesi.
- **C**: `mstLoadCommonPileForm` boş değeri forma yazmıyor (önceki kazığın kotu kalabilir) — açık.
- **DXF birimi**: birim tanımsızken iki farklı varsayılan (m / cm) var (11, 16) — açık; DXF varsayılanı için belge/kullanıcı kararı gerekli.
  - **Karara bağlandı (kullanıcı kararı 02.11.2026): "Her yerde sor, ön seçim yok"** (17 H6, öneri C): birim tanımsızken üç yolda (kazık dispozisyonu, paftadan donatı "L=", 3B pafta) ön seçimsiz "— seçin —" sorusu, seçilmezse iptal; soru işlemden önce. "L=" yazı birimi ↔ `$INSUNITS` kuralı belge gerekli, değişmez. Uygulama Parti H'de, kod henüz bitmedi.
- **Triage dışı 08 maddeleri**: 08 R7, sarmalayıcı Component ×N, v034 tretuvar köşe bindirmesi — triage'a girmedi, açık. *(Parti H, 17 H8: R7 belge gerekli, kod yok; sarmalayıcı Component ×N için Model Kontrolü UYARISI; v034 tretuvar için yalnız uyarı — ana oturum kararı, kayıtlı değer düzeltilmez. Uygulama sürüyor.)*
- **K59 #3 ADR sapması** — **karara bağlandı, ADR düzeltildi (02.11.2026)**: 17 H10 kararıyla kod değişmez, `02_adr_mimar.md` §6'ya "0.51.5 Parti H düzeltmesi (02.11.2026)" notu yazıldı; eski cümle "yerine geçti" olarak yerinde bırakıldı. H10'daki imza testi (başarı → hata → hata → başarı) çalıştırılmadı. Önceki kayıt: ADR 02 §6 "rebar_t pursantaj kuralının değeri yazılır" der; kod (`main.rb:12496`) hata yolunda `rebar_t`'yi siler. Metraj QuantityService ile doğru; revizyon imzası etkisi (`rebar_t` `REVISION_PARAMETER_KEYS` içinde, `revision_signatures.rb:5`) ele alınmadı. Kullanıcı kararı bekliyor (mevcut davranış + ADR düzeltmesi ya da kod değişikliği). Ayrıntı: `14_parti_G-a_uygulayici.md` "ADR sapması".
- **Türkçe istisnaları**: §2.5'teki bilinçli istisnalar ve README arşiv başlığı — kullanıcı onayı bekliyor. **Karara bağlandı (kullanıcı kararı 02.11.2026): "Kabul, böyle kalsın"** — istisnalar Türkçeleştirilmez.
- **Sürüm hattı** — **karara bağlandı (kullanıcı kararı 02.11.2026): "0.51.5 ile devam"**; kurulu v0.52.6 AUDIT CANDIDATE ayrı hattır, 0.51.5 kurulunca onun yerine geçer (§1).
- **0.51.5 runner** — **karara bağlandı (kullanıcı kararı 02.11.2026): 0.51.5 runner paketi üretilecek** (§5'teki "ayrı RBZ üretilmedi" ana oturum kararının yerine geçer). Paket bu not yazılırken üretilmemişti.
- **Belge gerekli (Parti H, `17_adr_parti_H.md`)**: H8 — 08 R7 tanımı (yalnız satır numarası var; iki aday: `rockfill_boq_source.rb:80` başlık ↔ tablo, `:42` sabit kesit '13'); H6 — pafta "L=" yazı birimi standardı (`$INSUNITS` ile ilişkisi; `MST_DXF_INSUNITS` değerlerinin Autodesk belgesiyle doğrulanması); H7 — menfez ile kazık gömülmesi kesişim hacmi kuralı (yalnız uyarı, hacim düzeltmesi yok); H9 — döşeme + kaplama hasırı sayım kuralı (yalnız BİLGİ satırı); H2 — tarayıcı (Chromium) sürüm tablosu (inset, min(), flex gap, grid gap desteği; 17'deki sürüm numaraları ajan belleğidir, belge değildir). Belge gelmeden bu kurallar değiştirilmez.
- **Açık riskler (Parti H sonrasında da kalır)**: (1) **U6 `active_ano` çatışması** — `mst_active_ano_context` (`main.rb:10912`) yöneticinin yazdığı yapı adını "ANO-01" ile ezebilir; ana oturum kararıyla değiştirilmez (17 H3e; Parti H yalnız "değer farklıysa yaz" düzeltmesini yapar). (2) **Sarmalayıcı Component örnek yolu kimliği** — sarmalayıcı Component ×N kopyada içteki MST öğeleri örnek yolu bazında ayrı kimlik taşımaz; Keşif N kez, iz/hakediş `.uniq` ile 1 kez sayar (17 H8). Parti H yalnız Model Kontrolü UYARISI ekler; kimlik/sayım çözümü yok.
- **Parti H ana oturum kararları (kayıt)**: H2 yalnız kazık ayarları kipi; H8 tretuvar yalnız uyarı; U6 `active_ano` çatışması değiştirilmez; H4a yalnız ölçüm, eşik 1 s. Parti H değişiklik notu kod bitince yazılacak.
- **G-a bilinen sınırları**: orijin z denetimi kap çerçevesinde (iç içe ötelenmiş kapta yanlış uyarı olası); kazık Group↔Component dönüşümü sahiplik açısından incelenmedi; bozuk kod/dolgu kaydı için onarım aracı yok.
- **G-b bilinen sınırları**: G6'da sınıfı '-' olan öğe varsa sınıf satırları + kaplama ≠ toplam; CSV "Kazık içi donatı" ek satırı testsiz.
- **F açık**: eski foraj düzenleyicisinin "Projedeki tüm kazıklar" kapsamı (10). G-b'de `mst_resolve_pile_targets` için 'ALL' seçeneği "Projedeki tüm kazıklar" eklendi (15); bunun F'deki açık noktayı kapatıp kapatmadığı raporlarda yazılmadı — doğrulanamadı. Gizli `pile_mfg_edit` paneli ölü kod değerlendirmesinde (K30).
- **Rapor eksikleri**: K47 (D) ve G arayüz partisi `c39c52c` için ayrı parti raporu yok. K40/K23 ara çözüm olarak sınıflanmalı (16).
- **Golden**: uçtan uca 0.51.4 ↔ eaaa858 karşılaştırması yok (§2.1, §6). *(Yerine geçti, 02.11.2026: 0.51.4 ↔ c8f9d70 fikstür karşılaştırması yapıldı, §6; açık kalan: Excel Ayrıntılı Metraj sayfası 0.51.4 sütun düzeni nedeniyle karşılaştırılamadı; SketchUp içi CSV karşılaştırması 08 satır 0.3.)*
- **03.11.2026 eklenen bilinen sınırlar (kaynak `930876a`, §2.8)**:
  - Component prekast ve alt gruplu kanal Kontrollü Düzenleme formunda düzenlenemez (Component için Türkçe ret iletisi).
  - Yeni kod karakter kümesinde JS (`checkCode`) ↔ Ruby (`MST_CODE_CHAR`) küçük farkı: büyük/küçük harfi olmayan harf, birleşik işaret, 0-9 dışı rakamda JS reddeder, Ruby kabul eder. Son denetim sunucuda; veri bozulmaz, yalnız ileti farkı (27/K6, değiştirilmedi).
  - `u1` test dosyasında 1 kalan: `editor_payload` hatası; 0.51.4'ten beri var, gizli sayfaya ait — açık. *(Yerine geçti, `dd952bb`: `editor_payload` tanımlandı, `u1` 89/0.)*
  - Golden-master Kontrollü Düzenleme yolunu sınamıyor (fikstürde tip adı yok); NCR-003 tip adı ve satır ayrışması yalnız kod okumasıyla (28) değerlendirildi — SketchUp kabulü 08 §10.
  - Aks Yöneticisi her açılışta `element_type`'sız grup / bileşenlerin içine iner (27/K4); süre ölçülmedi — 08 N-18.
  - BK boyutlandırma yolunda tip adı yokken `precast_id` üzerinden ad üretme geri düşüşü ve tek örnekli tipin eski ölçüye dönünce eski ada dönmemesi değiştirilmedi (27/K2, K3; ayrı karar).
  - Ruby 2.5 çalışma zamanında `unicode_normalize` / `:turkic` çalıştırılmadı (elle eşleme yedeği var; 23).
  - Ayrı öneriler (23, 24): `project_ano_axis_manager` iki tanım; `mst_add_ano` length+1; `DependencyModelObserver` her commit'te batch dışı `dependency_graph`; kazık raporu "Aks Noktası" görünen adı; `mst_code_usage` önbelleği — açık.
- **03.11.2026 kabul denetimi sonrası kapatılanlar (kaynak `dd952bb`; kullanıcı kararı "hepsi bu pakette")**:
  - 25/8: Kontrollü Düzenleme başlık kirişini Ruby tarafında da reddeder (BK yalnız Başlık Kirişi sayfasında).
  - `editor_payload` tanımlandı (salt okuma); gizli Eleman Düzenleyici "Seçimi Yenile" hata vermez.
  - 26/1a: Keşif Excel "Poz Metrajları" ara toplamında adet etikette ("Eleman toplamı · N eleman"), "Yapı" sütunu boş; yalnız miktarı > 0 olan (listelenen) elemanlar sayılır. **Excel görünümü değişir, toplam miktar değişmez.**
  - 25/5: Aks Yöneticisi kaydının işlem öncesi planlaması salt okuma (geçiş yazımları işlem içinde); yalnız kayıtsız varsayılan ızgaralar farklıysa kayıt değişiklik sayılmaz — **davranış farkı**: ilk değişikliksiz kayıt artık Geri Al adımı açmaz ve varsayılan ızgarayı yazmaz (okuma aynı varsayılanı üretir; başka değişiklikle birlikte eskisi gibi yazılır).
  - 25/6: kuru çalıştırma kaydedicisi desteklemediği çağrıda açık hata verir; kayıt "değişiklik var" sayılıp normal işlemle sürer.
  - 25/7: sahipsiz elemanlarda kullanılan kod yeni yapı kodu olarak önerilmez; elle verilirse onay istenir (yük `reattach_codes`), onaysız kayıt reddedilir. Sahipsiz `active_structure_zone__<kod>` değeri silinmez (kayıtlı veri; yeniden bağlanan yapı aynı bölgeyi kullanır).
  - 25/12: kod değişikliği gerekmedi — gömülü sayfa `mstShowPage` → `T` yoluyla sayfa kimliğini bildiriyor (test `v3`).
- **Kullanıcı kararları listesi** (16): ölü kod silme; K43; K32; Türkçe istisnaları; K59; B/A2 açık öneriler; belgeler (poz eşlemesi, fiyat farkı, tapa, derz, R4, REBAR_DEFAULTS, bordür oranı, DXF varsayılanı, K22 aşama 2, K10); davranış değişiklikleri (§2.7); 0.51.5 runner. *(02.11.2026 durumu: ölü kod, K43, Türkçe istisnaları, DXF varsayılanı, sürüm hattı ve 0.51.5 runner kullanıcı kararıyla karara bağlandı; K59 ADR düzeltmesiyle kapandı; K32 ve B/A2 önerileri Parti H'de; diğer belgeler ve §2.7 açık.)*

## 5. Runner uyarısı
Kurulu `mst_tb1_integration_runner` 1.1.0, 0.51.4 sürüm adını ve 0.51.4 dosya SHA-256 manifestini bekler. 0.51.5'te bu kontroller **beklenen şekilde başarısız** olur; paket hatası sayılmaz. Yöntem adı kontrolleri korunmuştur (G4). Runner için ayrı RBZ üretilmedi (ana oturum kararı, seçenek b). *(Yerine geçti, 02.11.2026: kullanıcı kararıyla 0.51.5 runner paketi üretilecek — §4.1; bu not yazılırken üretilmemişti.)* *(Yerine geçti, 02.11.2026 mst-test-paketleme: 1.2.0 paketi üretildi — §1; beklenen sürüm 0.51.5, dosya SHA listesi `c8f9d70` src'si; 0.51.5 ile çalıştırıldığında sürüm ve SHA kontrollerinin **geçmesi** beklenir. 1.1.0 0.51.5 kabulünde kullanılmaz.)*

## 6. Kanıt durumu (son kaynak c8f9d70; mst-test-paketleme bu oturum komut çıktıları, 02.11.2026)
| Düzey | Durum |
|---|---|
| Statik | `ruby -c` 66/66 hatasız; `tools\r25check.rb` (GEM_PATH=tools/gems) files=66 ruby25_failures=0; `check_inline_js` inline_blocks=20 ok=20 fail=0; `node --check` 13/13 .js hatasız; `check_chromium64` (CSS desenleri eklendi: `inset:`, `min(`, `max(`, `clamp(`; flex `gap` yalnız bilgi) added_lines=2109 hits=0 — CSS eşleşmeleri yalnız `ui.html:325` iki eşleşme, ikisi de "YEDEKLİ eski" (H2 yedekleri `top/right/bottom/left:0` ve `width:96vw;max-width:720px` asıl bildirimden önce; `.pile-ov-grid` `grid-gap:10px` `gap:10px`'ten önce); eklenen satırlarda yeni `gap:` 0 (taşınan: flex 9, grid 8, belirsiz 3; toplam `gap:` taban 872d3a3 = 247 = çalışma ağacı). Paket: §1 (`82bf9518…2fcfe`, 201/201, iki üretim aynı SHA, eklenen/çıkan 0/0, `unzip -t` hatasız). *(Yerine geçti: önceki eaaa858 satırı.)* |
| Sahte nesne | 41 test dosyası (a1/a2/b/c/f/g/h; yeni `h_h4a_k35_perf.rb` dahil), 705 denetim geçti, hepsi "0 kaldı", her dosya çıkış kodu 0. Yalnız mantığı sınar; SketchUp davranışını kanıtlamaz |
| Golden-master BOQ/QTO (sahte fikstür, SketchUp dışı) | Önceki zincir: 872d3a3 ↔ 8da4ec1 44 fark / 0 beklenmeyen; E, F, G-a fark 0; 7e2e9c7 ↔ eaaa858 45 fark / 0 beklenmeyen; 8d7d431 ↔ Parti H 12 fark (H4b) / 0 beklenmeyen (19). Bu oturum: `run_golden.rb c8f9d70` → eski=433 yeni=433 aynı=433 farklı=0 beklenmeyen=0 (betik doğrulaması; src değişmedi). **Uçtan uca 0.51.4 ↔ c8f9d70** (`run_golden.rb 872d3a3 --etiket uctan_uca_0514`, genişletilmiş fikstür + H4b eylemi, kural seti 0514; izlenen `golden_872d3a3.csv` korunarak `golden_872d3a3_uctan_uca_0514.csv`, `golden_HEAD-c8f9d70_uctan_uca_0514.csv`, `fark_872d3a3_HEAD-c8f9d70_uctan_uca_0514.csv`): eski=409 yeni=433 aynı=342 farklı=110; 36 fark 0514 kurallarıyla eşlendi; 74 "BEKLENMEYEN" (çıkış kodu 1) 0514 kural setinin kapsamadığı genişletilmiş fikstür kalemleridir ve tek tek eşlendi: (a) kalıp 5 anahtar +1,610281 = 08-R6 +1,621464 + H4b −0,011183; BK1 açıklık/kalıp ±0,011183 = H4b; (b) Keşif REBAR −2,039365 = K36+K50 −2,354365 + G4 +0,315; REBAR_BREAKDOWN curb 315 kg, REBAR_TRACE adet +3, hakediş REBAR onaylı +0,18 = G4; REBAR_TRACE sum_t +0,242034 = G4 +0,315 + K50 türev −0,072966; hakediş REBAR notu = K34/G4 metni; (c) pano DOSP −7,85 ve KAPLAMA 7,85 = K08/G6 (fikstür kaplaması D1 6,0 + D2 1,85; 0514 kuralı yalnız D1'i bilir); Toplam Beton −1,680964 = K36+K50 −9,530964 + G6 +7,85; Excel Özet Beton C30/37 −9,530964 = K36+K50, Beton Kaplama 6,0 / 1,85 = G6, Toplam Kalıp +1,61 = 08-R6+H4b; (d) CSV 29 satır + 7 toplam = G5 (9 sütun, yeni satır düzeni) + E (Türkçe başlık): Beton 110,426 → 134,669 (BK brüt→net −0,732, iç beton tek satır 9,126 → 26,251, kaplama ek kalemi +7,85), Kalıp 138,5 → 193,67 (BK kalıbı +55,17 CSV'ye girdi), Çelik 0 → 54,808 (boru çeliği), Donati_t 19,989 = Keşif REBAR; (e) Excel Ayrıntılı Metraj 15 anahtar **karşılaştırılamadı**: 0.51.4 sayfasında `Boru Çeliği (t)` sütunu yok (K41), betik sayfayı bulamadı (eski tarafta 1 HATA satırı); F1 tek satır düzeltmesi uçtan uca kanıtlanmadı. Bileşen toplamları gözlenen farklarla 6 ondalıkta (CSV 3 ondalıkta) ayrı bir `ruby -e` hesabıyla doğrulandı; uydurma eşleme yok. `compare.rb` 0514 kural seti değiştirilmedi. SketchUp içi CSV karşılaştırması yapılmadı; metrajı değiştiren işler "kabul bekliyor" |
| Performans (H4a ölçümü; sahte nesne, SketchUp süresi DEĞİL) | `ruby tools/test/h_h4a_k35_perf.rb src/marine_structures_tools 5` (Ruby 3.1.2, 5 tekrar, medyan): `pile_boq_expand_rows` n=50/500/2000 × 1/4 AYRI POZ kaynağı × kayıtlı/kayıtsız — çağrı sayısı n'den bağımsız: kaynak başına `pile_boq_group_quantities` 1, `pile_boq_codes_stored` 1, `collect_elements` 1; `prog2_last_period` kayıtsızda kaynak başına 1, kayıtlıda 0. En yavaş: n=2000, 4 kaynak 0,313–0,420 s; `boq_rows(true)` (Keşif tam) n=2000, 4 kaynak 0,581–0,640 s. Kayıtlı ↔ kayıtsız satırlar birebir. `mst_pile_orientation_bk_openings!` kazık 200/1000 × BK 50/200: `collect_elements` 2, en yavaş 0,025 s (1000 kazık, 200 BK, tüm kazıklar seçili). Eşik 1 s (kullanıcı kararı) aşılmadı; kod değiştirilmedi. SketchUp içi ölçüm: 08 satır H-9 |
| SketchUp 2020 kabulü (kullanıcı) | Yapılmadı / denenmedi. Liste: `08_sketchup_kabul_listesi_0.51.5.md` |
| Görsel | Yok |
| Ajan değerlendirmesi | `16_kabul_denetim.md`: genel "kısmen karşılandı" (ajan incelemesi; kullanıcı onayı değil) |

### 6.1 Kanıt durumu — kaynak `930876a` (03.11.2026; ana oturum bildirimi, mst-dokumantasyon komut çalıştırmadı)
| Düzey | Durum |
|---|---|
| Statik | Ruby 2.5 denetimi 66 dosya / 0 hata |
| Sahte nesne | `v1` 35 geçti / 0 kaldı; `v2` 24 geçti / 0 kaldı; 54 test dosyasının 53'ü 0 kalan; `u1` 87 geçti / 1 kaldı (`editor_payload`, 0.51.4'ten beri, §4.1). Yalnız mantığı sınar |
| Golden-master (sahte fikstür) | 433/433 aynı. Kontrollü Düzenleme yolunu sınamıyor (§4.1) |
| Paket | RBZ adı / SHA-256: paketleme sonrası yazılacak |
| SketchUp 2020 kabulü (kullanıcı) | SketchUp içinde denenmedi. Liste: `08_sketchup_kabul_listesi_0.51.5.md` §10 |

### 6.2 Kanıt durumu — kaynak `dd952bb` (03.11.2026; ana oturum komut çıktıları) *(6.1'in yerine geçer)*
| Düzey | Durum |
|---|---|
| Statik | `ruby -c` (değişen dosyalar) hatasız; Ruby 2.5 denetimi 66 dosya / 0 hata; `node --check` project_workspace.js hatasız |
| Sahte nesne | `tools/test` 55 dosya, hepsi 0 kalan (`u1` 89/0, `v1` 35/0, `v2` 24/0, `v3` 15/0; `v3` 25/5 testi düzeltmesiz kodda kaldığı doğrulandı). `r_gecikme` G5a beklentisi 25/5 kararına göre güncellendi |
| Golden-master (sahte fikstür) | 10e520d ↔ çalışma ağacı 433/433 aynı; uçtan uca 0.51.4 farkı c8f9d70 farkıyla birebir. Kontrollü Düzenleme yolu ve Excel "Poz Metrajları" ara toplam düzeni golden kapsamında değil (v3 testiyle sınandı) |
| Paket | RBZ adı / SHA-256: paketleme sonrası yazılacak. *(Yazıldı, 03.11.2026 mst-test-paketleme: `dist\MST_v0.51.5_TB1_FIX1_TEST.rbz`, src = `831f0d0` (son kod `dd952bb`; paket HEAD `e7e8a7c`'de üretildi, o commit yalnız runner/), 201 dosya, 1.208.568 bayt, SHA-256 `38d83120232e98e86ac95af02f670ee7c0b927cc34899bacc8f00c563914f50e`; paket ↔ src 201/201, 0.51.4 paketine göre eklenen 0 / çıkan 0, iki üretim aynı SHA, `unzip -t` hatasız. Runner 1.2.4 `dist\MST_TB1_Integration_TestRunner_v1.2.4_for_0.51.5.rbz`, 3 dosya, 17.375 bayt, SHA-256 `c96075b570b1173851afbc3c27c87f2ad56d17810ce204f3ce824cdd54bd5c4d`, expected_sources `831f0d0` src'sinden 201/201. Önceki paketler (MST `75c0ea66…`, runner 1.2.3 `a02b4383…`) `dist\gecersiz_75c0ea66\`. Bu paketleme öncesi tam statik ve `tools/test` 55 dosya 1439 geçti / 0 kaldı)* |
| SketchUp 2020 kabulü (kullanıcı) | SketchUp içinde denenmedi |
| Görsel | Yok |
| Ajan incelemesi | 25, 26 (kaynak `10e520d`), 27, 28 (kaynak `0983966`); bulguların ana oturum sonucu 27 tablosunda. Onay sayılmaz |

## Donma düzeltmesi (02.11.2026)
Paket yeniden üretildi: kaynak c42a0eb (donma düzeltmesi, metraj değişmez; bkz. 20_donma_duzeltmesi.md), MST SHA-256 75c0ea66779cbe8d89fb193d07f847cfcdc9549450a272c03c5f79adf278c773; runner 1.2.3 SHA-256 a02b4383ab28514c96f3f3f96dabeae896a98d646b84b71719a0e37805cb59ea. Önceki paketler dist\gecersiz_82bf9518\.
Donma düzeltmesi D4+D5 sonrası paket: kaynak 5c852a1, MST SHA-256 75c0ea66779cbe8d89fb193d07f847cfcdc9549450a272c03c5f79adf278c773; runner 1.2.3 SHA-256 a02b4383ab28514c96f3f3f96dabeae896a98d646b84b71719a0e37805cb59ea. Önceki paketler dist\gecersiz_de211466\.
Aksesuar iç bağlantısı (Q1) ve Revizyonlar düğmeyle hesaplama (Q2) sonrası paket: kaynak d5fcfca, MST SHA-256 75c0ea66779cbe8d89fb193d07f847cfcdc9549450a272c03c5f79adf278c773; runner 1.2.3 SHA-256 a02b4383ab28514c96f3f3f96dabeae896a98d646b84b71719a0e37805cb59ea. Önceki paketler dist\gecersiz_7fb342bd\.

### 6.3 SketchUp sonucu ve son paket (03.11.2026)
- **Kullanıcı bildirdi** (G:\Drive'ım\MST_TB1_Test_20261103_161216.json): runner 1.2.4, SketchUp 20.0.363, Ruby 2.5.5, kip core_and_model_read, paket 38d83120 (201/201 dosya doğrulandı): 33 kontrol — 32 geçti, 0 kaldı, 1 uyarı (95 çelik boru kazıkta formwork_m2 'eksik'; model 328 desteklenen eleman, 100 okundu). Yalnız motor + okuma kontrolleri; 08 §10 arayüz maddeleri bu sonuçla kanıtlanmaz.
- Uyarı düzeltildi (3e283f0, kullanıcı kararı): çelik boru kazık kalıbı 'uygulanmaz' (değer 0 aynı; metraj toplamı değişmez; Çalışma Alanı kalıp kartı 'tamamlanmadı' yerine doğru durum). Tüm takım 55 dosya 0 kalan, Ruby 2.5 66/0, golden 433/433.
- **GÜNCEL PAKET**: dist\MST_v0.51.5_TB1_FIX1_TEST.rbz SHA-256 e6d505e14ef7c60741af9fd4b08d91286d9805be600731ebd40eb6d93bc9ff92 (201 dosya, iki üretim aynı); runner 1.2.5 cce7cd14576b8bc773103832439e1eb505d449bf7de47471372259ba61a66db2. Teslim: OneDrive\Masaüstü\CLAUDE\MST_v0.51.5_TESLIM_6. 38d83120 / 1.2.4 → dist\gecersiz_38d83120.
