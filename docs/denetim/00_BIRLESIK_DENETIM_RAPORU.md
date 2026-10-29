# MST v0.51.4 TB1 RUBY25 — Birleşik Denetim Raporu (29.10.2026)

Yalnız denetim yapıldı. Kod düzeltilmedi, dosya değiştirilmedi, RBZ üretilmedi. Depo `git status` boş; Drive'daki orijinal SHA-256 değişmedi.

## 0. Özet: mevcut kullanım durumu

- **Paket:** `G:\Drive'ım\MST_v0.51.4_TB1_Ruby25_TEST.rbz`
  - Drive aramasında tek eşleşme, Drive kökünde.
  - Boyut 1.159.904 bayt; değiştirilme tarihi 28.10.2026 23:35.
  - SHA-256 `5684BEC3…2AC42`. Downloads kopyası aynı.
- **Kurulu sürüm:** SketchUp 2020'de kurulu eklenti bu paketle 201/201 dosya aynı. CLAUDE.md'de "kurulu = 0.51.2 TB1" yazıyor; bu bilgi artık geçerli değil. `mst_kn1_test` kurulu değil. `mst_tb1_integration_runner` 1.1.0 kurulu ve bu pakete uyumlu.
- **Sürüm tutarlılığı:** Paket adı, `MST_BUILD='v0.51.4 TB1 RUBY25'` (main.rb:27) ve `VERSION='0.51.4'` (qto_workspace.rb:4) uyumlu.
  - 0.51.4 = 0.51.3 TB1 Integrated + 5 dosya. Değişiklikler: sürüm adları; `filter_map` ve `.then` kaldırıldı.
  - Yerel depo (0.52.0-dev1) ayrı bir hat: 106 ortak dosyadan 89'u aynı.
  - README v0.36.7'den kalma. 0.51.3 ve 0.51.4 için sürüm notu yok.
- **Yüklenebilirlik (statik):**
  - Ruby 2.5 dilbilgisiyle 66/66 dosya hatasız ayrıştı.
  - Ruby 2.6+ yöntemi yok. SketchUp 2021+ API'si yok.
  - Bütün `require` hedefleri mevcut.
  - JS: 13/13 dosya ve 27 gömülü script hatasız. Chromium 64'te olmayan JS özelliği yok.
  - **Sonuç:** Statik olarak yüklenmeme bulgusu yok. Ancak gerçek Ruby 2.5.5 / SketchUp 2020 çalıştırması yapılmadı.
- **Kullanım durumu (kanıt yalnız statik okuma + sahte nesne testi; SketchUp'ta hiçbir şey denenmedi):**
  - Eklentinin temel modelleme ve metraj zinciri kaynakta mevcut ve menü/araç çubuğuna bağlı.
  - **Metrajı doğrudan bozan 3 bulgu var:**
    - C35/45 dışındaki prekast betonu BOQ'ya girmiyor.
    - Component kazıkta "iç beton YOK" seçilse de iç beton sayılıyor.
    - Döndürülmüş yapıda prekast boyu yanlış hesaplanıyor.
  - **Veri kaybı:** Revizyon arşivi 20 kayıttan sonra en eski kaydı siliyor (sahte nesne testiyle de doğrulandı).
  - **Çalışmayan arayüz yolları:**
    - "Eleman Düzenle → Uygula" hiç çalışmıyor.
    - Kronman ve eski Alternatif-01 dolgu sayfası, SketchUp 2020'de çalışıp çalışmadığı belli olmayan `skp:` yoluna bağlı.

### En önemli bulgular

| ID | Öncelik | Kısa |
|---|---|---|
| MST-K33 | Kritik | C35/45 dışı prekast ve bordür betonu beton pozuna girmez (boş sınıf → C30/37) |
| MST-K36 | Kritik | Component kazıkta "iç beton YOK" seçilse de hacim ve donatı sayılır |
| MST-K22 | Kritik | Döndürülmüş yapıda prekast boyu: örnekte 10,30 m yerine 3,96 m, uyarı yok |
| MST-K02 | Kritik | Revizyon arşivi: 21. kayıttan sonra en eski kayıt silinir, ad "Rev.21" olarak tekrarlanır, keşif özeti eklenmez |
| MST-K35 | Kritik (doğrulama bekliyor) | Kazık "ayrı poz" hakedişinde önceki dönem miktarı başka kesite kayabilir |
| MST-K01 | Yüksek | Eleman Düzenle → Uygula: tanımsız işlev, sessiz başarısızlık |
| MST-K04 | Yüksek | Eleman Kütüphanesi'ni açmak revision, schema ve type_id değerlerini geriye yazar |
| MST-K24 | Yüksek | Kronman ve Alt-01 yalnız `skp:` yolunda; çalışmazsa sessiz |
| MST-K50 (2. tur) | Kritik | Kazık dişin/taban bölgesinin altındaysa BK betonundan gömülme eksik düşülür (BK betonu fazla) |
| MST-K57 (2. tur) | Kritik | "Donatıyı Sil" Component prekastta 3B'yi siler ama tonaj metrajda kalır; paftadan metraj da etkilenir |
| MST-K58 (2. tur) | Kritik (doğrulama bekliyor) | Donatılı Component prekastın boyu değişince aynı boydaki başka prekastlara donatı/tonaj sızar |
| MST-K59 (2. tur) | Yüksek | Kazık kafes hesabı hata verirse kazık donatısı sessizce 0 olur |

> 2. tur (kullanıcının "devam et" talimatıyla yapılan ek inceleme) sonuçları §8'dedir. Önceki tabloda değişen öncelikler: K32 → Düşük (yalnız görünüm), K14 → Düşük (skp:'ye bağlı), K35 ikinci teyitli Kritik, K34/K38 ikinci teyitli Yüksek.

## 1. Ana bulgu tablosu

Doğrulama durumu kısaltmaları:
- **S:** statik okuma
- **A:** ana oturumun satır teyidi
- **2K:** ikinci ajanın bağımsız teyidi
- **T:** sahte nesne testi

SketchUp kanıtı hiçbir bulguda yok. "Etiket", kullanıcının istediği 6 sınıftan biridir.

| Bulgu ID | Öncelik | Modül | Dosya ve satır/metot | Sorun | Tetikleyen işlem | Etkisi | Kanıt | Önerilen düzeltme | Doğrulama durumu |
|---|---|---|---|---|---|---|---|---|---|
| MST-K33 | Kritik | BOQ / prekast | main.rb:3514-3515 `boq_quantities`; 4305 | PRECAST_C35_45 ve CAST_C35_45_OTHER yalnız C35/45'i alır. Sınıf boşsa C30/37 varsayılır | Prekast/bordür C35/45 dışında veya sınıf boş | Beton BOQ eksik; örnek 10 m³ → beton 0, montaj 10 | 08; satırlar okundu, başka poz anahtarı yok | Sınıfa göre poz veya uyarı. Poz/sınıf eşlemesi için proje poz listesi gerekli | Doğrulanmış hata (S+A+D); önemi poz tarifine bağlı |
| MST-K36 | Kritik | Kazık / iç beton | qto_workspace.rb:80-82 `pile_qto_concrete`; pile_manufacturing.rb:203 | `children` kontrolü `infill_enabled=0` kontrolünden önce; Component'te paylaşılan çocuk silinmez | Component kazıkta iç beton YOK | İç beton hacmi ve kafes donatısı fazla sayılır; arayüzde "VAR" görünür | 08; satırlar okundu | `infill_enabled` kontrolünü öne almak. Metrajı değiştirir; golden-master gerekir | Doğrulanmış hata (S+A+D) |
| MST-K22 | Kritik | Prekast | main.rb:4270-4309, 4419-4437, 11130 | Açıklık ve boy `bounds.x` ile ölçülüyor | Model X eksenine paralel olmayan yapıda prekast | 30° örnek: 3,96 m (olması gereken 10,30 m), hacimde −%61,6, uyarı yok | 04 K1, 08 K1 örnek hesap, 07 teyit | Açıklığı BK yerel ekseninde ölçmek veya uyarı vermek | Doğrulanmış (S+2K); SketchUp testi gerekli |
| MST-K02 | Kritik | Revizyon | main.rb:9252 `last(20)`, 9352 `length+1`; boq_pro.rb:840 | Kayıt sınırı, ad tekrarı, keşif eklenmemesi | 21. ve sonraki snapshot | Revizyon geçmişi kaybı | t_h1_snapshot.rb çıkış 1, "3 geçti, 3 kaldı" | Numara = en büyük Rev.NN + 1; silme kararı kullanıcıda; tek işlem | Doğrulanmış (S+A+2K+T) |
| MST-K35 | Kritik | Hakediş | main.rb:3585; boq_pro.rb:383, 495, 644 | Ayrı poz satır anahtarı sıra numarası (code-01…) | Kazık kesit grubu silinip eklenince | `previous_` miktarı başka kesite kayar | 08 (tek kaynak) | Anahtarı kesit etiketine bağlamak | Olası risk (S); SketchUp testi gerekli |
| MST-K01 | Yüksek | Eleman Düzenle | main.rb:10133 `universal_edit` → `update_selected_element` | İşlev tanımsız | Eleman Düzenle → Güncelle → Tamam | NameError yalnız konsolda; işlem yapılmaz, mesaj yok | 02, 05, 07; grep | Türkçe hata ver veya Kontrollü Düzenleme'ye yönlendir | Doğrulanmış (S+A+2K) |
| MST-K04 | Yüksek | BIM kimliği | main.rb:6377-6403 `standardize_model_metadata` | Bütün elemanlara revision='v0.20.0' ve schema 2.0 yazar; aynı imzada type_id tek değere zorlanır | Eleman Kütüphanesi, BIM Core, Dependency stamp | Revizyon ve tip kimliği geriye yazılır | 03, 07; satırlar okundu | Yalnız eksik anahtarı yaz; görüntüleme yazmasın | Doğrulanmış (S+A+2K) |
| MST-K05 | Yüksek | Bağımlılık | main.rb:8263, 8269 `stamp_dependency_metadata` | revision='v0.20.0'; tek ebeveynli elemanda parent_uid üzerine yazar | Dependency stamp | Kimlik/revizyon bozulur | 03, 07 | Yalnız ileri yaz | Doğrulanmış (S+2K) |
| MST-K06 | Yüksek | UID / kopyalama | dependency_rebuild.rb:57-62; main.rb:9256 | Kopyalama anında UID yeniden atanmıyor; tretuvar bağı `matches==1` şartıyla kopuyor; ilerleme kopyaya taşınabilir | Ctrl+Move, kopyala-yapıştır | Aynı UID ile iki eleman; asıl döşemenin tretuvar bağı kopar; revizyon farkı karışır; kopya onaylı görünebilir | 03 H3/H8, 07 kısmen, 08 R2 | Çakışma tespiti ve yeniden atama (mimar kararı). Sonradan tespit var: Audit 7940, onarım 7460 | Doğrulanmış kısmen (S+2K); SketchUp testi gerekli |
| MST-K24 | Yüksek | Kronman / dolgu Alt-01 | ui.html'de 20 `skp:` oluşumu (702, 745, 1082, 1168-1169, 2180-2238) | HtmlDialog'da `skp:` yolu belirsiz; Ruby URL çözmüyor (9054) | Kronman oluştur/yükle/revize/aks; Alt-01 kaydet/yükle; Seçili Eleman Bilgisi | Bu işlevler hiç çalışmayabilir; otomatik kayıt sessizce kaybolur | 02, 05, 07 | `sketchup.X(p)` çağrısına geçmek; Ruby tarafı değişmez | SketchUp testi gerekli |
| MST-K34 | Yüksek | Hakediş | boq_pro.rb:465 `min(Σ,qty)`; main.rb:3384, 3431 | REBAR satırında kaplama ve ankraj donatısı var; eleman ilerlemesinde yok | Hakediş onayı | Bu donatılar hakedişe hiç girmez (örnek 15,2 t → 15,0 t) | 08 (tek kaynak) | Elle satır veya ayrı kalem | Olası risk (S) |
| MST-K38 | Yüksek | Hakediş tutarı | boq_pro.rb:585 ile 990-993 | İcmal ve cetvel farklı fiyat kuralı kullanıyor | Dönemler arasında fiyat/kur değişince | 1600 ile 1800 gibi farklı tutarlar | 08 | Sözleşmeye göre tek kural (belge gerekli) | Olası risk (S) |
| MST-K23 | Yüksek | Metraj / dönüşüm | quantity_service.rb, main.rb:2188 | Metraj attribute'tan okunuyor, ölçek dikkate alınmıyor | Scale aracı | BK 15 m³ × 1,2 → geometri 18, metraj 15 | 03, 08 | Ölçeklenmiş öğeyi Model Kontrolü'nde işaretlemek | Olası risk; SketchUp testi gerekli |
| MST-K09 | Yüksek | BK menfez | mst_v50_beams.rb:131-165, 125-126; main.rb:2784 | Çok örnekli Component BK'da menfez paylaşılan definition'a çiziliyor; "unique yap" sorulmuyor | Component BK'ya menfez | Boşluk ve sac bütün örneklerde; metraj değişir | 03, 07 | Unique yap sorusu veya engelleme | Doğrulanmış (S+2K) |
| MST-K19 | Yüksek | İlerleme | boq_pro.rb:397, 750-755 | Bozuk `progress_items_json` boş sayılıyor | İlerleme kaydı (bozuk veride) | Elemanın tüm onay geçmişi silinir | 04, 07 | Bozuk JSON'da dur ve bildir | Doğrulanmış (S+2K); tetiklenmesi dış bozulmaya bağlı |
| MST-K27 | Yüksek | Aksesuar kütüphanesi | accessories.rb:228-238, 265, 302 | Bozuk dosya `[]` sayılıyor; atomik olmayan `File.write` | Kütüphane bozukken öğe ekleme/silme | Kullanıcı kütüphanesinin tamamı kaybolur | 07; satırlar okundu | boq_library gibi atomik yazım; bozuk dosyanın üzerine yazmamak | Doğrulanmış (S+A) |
| MST-K12 | Yüksek | Undo / DXF kazık | mst_v50_piles.rb:468-473 | Transparent işlem `abort` ile kapatılıyor | DXF dispozisyonunda aks ızgarası hatası | Önceki işlem geri alınabilir; mesaj "oluşturuldu" der | 04, 07 | Hatada da commit ile kapatıp bildirmek | Doğrulanmış (S+2K); SketchUp testi gerekli |
| MST-K07 | Orta | Kaplama | main.rb:2098, 2117, 8211; 5919, 6007 | `deck_topping` toplanmıyor | Kaplama oluşturma, BK kot/aks değişikliği | Mükerrer kaplama kontrolü çalışmaz; kaplama taşınmaz; bağ observer tarafından silinir | 03, 07 | Ayrı kaplama toplayıcı (`collect_elements` değişirse golden-master) | Doğrulanmış (S+2K) |
| MST-K10 | Orta | VK/BBK | dependency_rebuild.rb:31-36 | Bağımlılık grafiğinde yok | BK kot/aks değişikliği | Vinç ve boylama kirişi izlemez | 03 | `support_*_pid` ile grafiğe bağlamak (metrajı değiştirir) | Eksik özellik |
| MST-K16 | Orta | BK menfez | mst_v50_beams.rb:126 `rescue nil` | Çizim hatası yutuluyor; geçersiz kayıt kalıyor | Menfez BK dışında kalırsa | Uyarı yok | 04, 07 (Kritik değil) | Uyarı vermek | Olası risk |
| MST-K20 | Orta | Dolgu / proje kayıtları | main.rb:9093, 9130-9135; 10377, 10447, 10829, 10893 | Bozuk JSON varsayılana dönüyor, sonra üzerine yazılıyor | Bozuk kayıtla düzenleme | Kütüphane/aks verisi ezilir | 04, 07 | Bozuk içerikte yazmamak | Olası risk |
| MST-K26 | Orta | Revizyon | boq_pro.rb:836; main.rb:10115 | Sarmalayıcıda rescue yok | Revizyon arşivi bozuk | Kullanıcı hiçbir şey görmez | 07 | Rescue ve mesaj | Olası risk (S) |
| MST-K03 | Orta | Revizyon / Undo | main.rb:9252, 9355; boq_pro.rb:843 | İşlem dışında 3 ayrı yazma | Snapshot | Çok adımlı Ctrl+Z | 03 H9 = 04 U5; T gözlemi | Tek `start_operation` | Doğrulanmış (S+T) |
| MST-K28 | Orta | Undo | main.rb:6433-6435, 8255-8256 | İki ayrı işlem açılıyor | BIM Core / Dependency | 2 Ctrl+Z | 07 | Tek işlem | Olası risk (S) |
| MST-K14 | Orta | Dolgu Undo | main.rb:9096-9150 | İşlem dışı `set_attribute`; okuma sırasında da yazıyor | Alt-01 otomatik kayıt (250 ms) | Geri Al geçmişi karışır | 04 | İşlem içine almak | Olası risk (skp:'ye bağlı) |
| MST-K42 | Orta | Kazık formu | ui.html:1185 `updateDrivingAuto` | Deniz tabanı silinince eski çakım boyu alanda kalıyor | Kot silme ve kaydetme | Bayat çakım metrajı olabilir | 06 (test 0.52-dev1 için yazılmış), 07 | Niyet kararı: temizle ve uyar | Olası risk; kullanıcı kararı |
| MST-K08 | Orta | Pano | main.rb:3871, 3888-3892 | Döşeme satırına kaplama ekleniyor | Kaplamalı döşeme | DİĞER satırı eksi; yalnız gösterim | 08 | Satırları ayırmak | Doğrulanmış (S) |
| MST-K39 | Orta | Kazık BOQ | main.rb:8497-8504 | Tapa ağırlığı BOQ'ya geçmiyor | BOQ | Tapa (örnek 68,75 kg/adet) hiçbir pozda yok | 08 | Tarife göre kalem (belge gerekli) | Eksik özellik |
| MST-K40 | Orta | Donatı | mst_dr_auto.rb:583 | Yerleştirilemeyen pozlar raporlanmıyor | Paftadan 3B donatı | Görünmeyen fark | 08 | Ayrı satır | Eksik özellik |
| MST-K41 | Orta | QTO gösterimi | quantity_service.rb:78; main.rb:3305, 3321, 3901, 8558, 8593 | "Çelik / Tonaj" sütunu boru çeliği, donatı ve dolgu tonajını birleştiriyor | Pano / Excel | Yanlış okuma riski; BOQ etkilenmez | 06, 08 | Sütunları ayırmak | Olası risk |
| MST-K32 | Orta | Arayüz (Chromium 64) | ui.html:325 (`inset`, `min()`); flex `gap` ~105 satır | Desteklenmeyen CSS | SketchUp 2020'de pencere açılışı | Boşluklar 0; kazık özel ayar penceresi ortalanmayabilir | 00, 05 | Yedek CSS | SketchUp testi gerekli |
| MST-K46 | Orta | Hakediş | boq_pro.rb:355-660 (yeniden tanımlar); main.rb:8083 | progress_* işlevleri boq_pro'da yeniden tanımlanıyor; tarihsiz çağrı davranışı okunmadı | Model Kontrolü hakediş sütunu | Belirsiz | 01, 02 | Okuma ve test | Erişim/veri yetersizliği |
| MST-K43 | Orta | Aks yönetimi | main.rb:8797 → 12464 | Eski tanım geçersiz kaldı; auto_organize (8689) ve manual_axis (8768) erişilemiyor | — | Özellik kaybı | 02 | Kullanıcı kararı (silme değil) | Eksik özellik |
| MST-K49 | Orta | Performans | dependency_rebuild.rb:149; project_workspace.rb:170 | Her işlem kaydında tam tarama; O(n²) eğilimi | Büyük model | Gecikme | 03, 06 | Önce ölçüm (plan 06'da) | SketchUp testi gerekli |
| MST-K11 | Düşük | Kalıp araçları | main.rb:2344-2345 (erişilemez), 2432 | Çift commit | Evrensel Kalıp tıklaması | Büyük olasılıkla etkisiz | 04, 07; satırlar okundu | Fazla commit'i kaldırmak | Doğrulanmış (kural); etkisi SketchUp testi |
| MST-K13 / K15 | Düşük | Undo | main.rb:2258-2280, 6143; mst_schedule.rb:297; 10325-10393; 4270 | Rescue yok; okuma sırasında yazma; toplu prekast ayrı işlemler | Çeşitli | Açık kalan işlem; kısmi geri alma | 04 | ensure/abort; tek işlem | Olası risk |
| MST-K17 / K18 / K21 | Düşük | Sessiz rescue | mst_v50_beams.rb:122, 157, 173; boq_pro.rb:358; mst_v50_misc.rb:84; main.rb:9134 | Hata yutuluyor | Bozuk veri / hata | Sessiz 0 değer veya eski değer | 04 | Uyarı | Olası risk |
| MST-K25 | Düşük | Kronman | main.rb:9046 | Ruby'de `\'` → JS sözdizimi hatası | Kenar seçmeden "Aks oku" | "Aks okunuyor…" yazısı ekranda kalır | 07; satır okundu | `JSON.generate` ile metin | Doğrulanmış (S+A); skp: yoluna bağlı |
| MST-K29 | Düşük | Çeşitli | main.rb:2318, 9821/9827, 10136, 9886 | Component'te `hb.entities`; kaçışsız aks adı; rescue'suz parse; tip karışması | Kenar durumları | — | 07 | — | Olası risk |
| MST-K30 / K31 | Düşük | Arayüz | main.rb:9970, pile_drilling.rb:74-76; main.rb:9571 | Tanımsız JS işlevleri (çağıranı olmayan callback'lerde); eski menü BOQ sekmesini bulamıyor | Eski menü "Keşif / BOQ Engine" | Sayfa açılmaz | 05, 07 | `mstShowPage('boq')` | Doğrulanmış (S+2K) |
| MST-K37 | Düşük | Kazık önizleme | pile_manufacturing.rb:226-241 | Önizleme formülü QTO'dan farklı | Toplu VAR/YOK | 100,22 / 101,80 kg | 08 | Tek formül | Doğrulanmış (S) |
| MST-K45 | Düşük | Araç çubuğu | main.rb:10288 | `tb.show` koşulsuz (0.51.3 Onaylı'daki düzeltme bu hatta yok) | SketchUp yeniden açılışı | Kapatılan araç çubuğu geri gelir | 01, 02, 10 | `TB_HIDDEN` kontrolü | SketchUp testi gerekli |
| MST-K47 / K48 | Düşük | Dokümantasyon / dil | README.txt; RELEASE_UI9.txt; main.rb:10241, 9680-9689; boq_library.rb:302; quantity_service.rb:72 | Eski sürüm metni; İngilizce menü; Türkçe karaktersiz hata; terim ikilikleri | — | Kullanılabilirlik | 05, 10 | Sürüm notu, terim sözlüğü (kullanıcı kararı) | Doğrulanmış (S) |
| MST-K44 | — | Dalgakıran | — | Modül yok; yalnız "mendirek" metni | — | — | 01, 02 | Tanım belgesi gerekli | Eksik özellik |

## 2. Modül kapsam durumu

Sütunların anlamı:
- **Kaynakta:** kod pakette var.
- **Arayüz:** menü, araç çubuğu veya sayfa yolu izlendi.
- **Canlı:** bütün satırlarda "yapılmadı".

| Alan | Durum | Not |
|---|---|---|
| Proje / sistem / aktif yapı / aks | Kısmen | K43 |
| Düşey/eğik çelik kazık ve bileşenleri | Kısmen | Çember, iç beton, PE ve çakım bağlı. Tapa BOQ'da yok (K39). K36, K42. Foraj düzenleme arayüzü yok |
| Fore kazık | Mevcut ve bağlı | Bilinen sınır: muhafaza borusu çapa göre ayrılmıyor |
| Jet grout | Mevcut ve bağlı | Hacim nominal; örtüşme düşülmez |
| Başlık kirişi, cep/kanal, menfez | Kısmen | Diş/konsol için ayrı işlev bulunamadı; doğrulanamadı. K09, K16 |
| Normal / vinç / kanal prekast | Kısmen | K33, K22 |
| Boyuna kiriş / vinç kirişi | Kısmen | K10 |
| Döşeme / kaplama / tretuvar | Kısmen | K07, K08 |
| Kronman | Doğrulanamadı | Yalnız skp: yolu var (K24, K25) |
| İskele / rıhtım / dolfen | Kısmen | Yalnız sistem etiketi düzeyinde |
| Kazı-dolgu Alt-1 / Alt-2 | Kısmen | Tek sağlayıcı; ikisi aynı anda BOQ'ya geçmiyor. Eski Alt-01 sayfası skp: yolunda |
| Batimetri / deniz tabanı / kesitler | Mevcut ve bağlı (statik) | rockfill_* ayrıntılı incelenmedi |
| Dalgakıran | Eksik | K44 |
| BIM / donatı / pursantaj | Kısmen | Pursantaj ile ilerleme karışmıyor. K40; R4 (paftada ankraj varsa çift sayım; belge gerekli) |
| Metraj / BOQ / birim fiyat / keşif | Kısmen | K33, K41, K31 |
| İş programı | Mevcut ve bağlı | — |
| İlerleme / hakediş | Kısmen | K19, K34, K35, K38, K46 |
| Model Kontrolü, onarım, revizyon | Kısmen | K02, K04 |

## 3. Bağımlılık zinciri (statik)

| Halka | Durum |
|---|---|
| Kazık → BK | Bağlı |
| BK → prekast | Bağlı. Kimlik `persistent_id` ile tutuluyor. Kot ve aks aktarılıyor; genişlik değişikliği yalnız uyarı veriyor |
| BK/prekast → döşeme | Döşeme yalnız taşınıyor; ölçüsü yeniden kurulmuyor |
| Döşeme → tretuvar | Bağlı; kopyalamada kopuyor (K06) |
| Döşeme → kaplama | Kopuk (K07) |
| BK → VK/BBK | Kopuk (K10) |
| Metraj | Rapor anında attribute'tan okunuyor |

"Dependency Auto Rebuild" geometri kurmuyor; yalnız bağımlılık meta verisini yazıyor.

Değişiklik olmadan oluşan revizyon:
- BK form revizyonunda yok.
- K04 ve K05 değişiklik olup olmadığına bakmadan revizyon alanını geri yazıyor.

## 4. Bağımsız örnek hesaplar (metraj-kontrol, elle izlendi; katsayılar için belge gerekli)

Örnek kazık: Ø1016×16 mm, L=30 m, ρ=7850.

| Kalem | Hesap | Sonuç |
|---|---|---|
| Boru | — | 11 837,5 kg = kod |
| İç beton, h=12 m | — | 9,126 m³ = kod |
| Üst çember | — | 101,80 kg = QTO |
| Alt çember | — | 114,59 kg = QTO |
| Çakım boyu, 1:6 eğim | — | 22,303 m = kod |
| BK gömülme hacmi | — | 0,405 m³ = kod |
| PE kaplama | — | 31,92 m² = kod |
| Tapa | 68,75 kg hesaplanıyor | BOQ'da satırı yok (K39) |
| Hakediş ağırlıklandırma | — | Asıl yol doğru (10). Yedek yol 50 (beklenen 10); seçim gösterimi %50 |
| Döndürülmüş prekast | — | 3,96 m; olması gereken 10,30 m (K22) |

BK, döşeme ve dolgu hacmi için bağımsız örnek hesap yapılmadı.

## 5. Çalışan ajanlar ve yapılan kontroller

Ajanlar sırayla çalıştı; hiçbiri paralel çalışmadı. Her ajana önceki raporların hepsi verildi.

| # | Ajan | Rapor |
|---|---|---|
| 1 | mst-proje-yonetici | `out\01_proje_yonetici.md` |
| 2 | mst-kaynak-analiz | `out\02_kaynak_analiz.md` |
| 3 | mst-mimar | `out\03_mimar.md` |
| 4 | mst-uygulayici | `out\04_uygulayici.md` (salt okuma modunda) |
| 5 | mst-arayuz-tr | `out\05_arayuz_tr.md` (salt okuma modunda) |
| 6 | mst-test-paketleme | `out\06_test_paketleme.md` (+ `out\tests\`) |
| 7 | mst-kod-inceleme | `out\07_kod_inceleme.md` |
| 8 | mst-metraj-kontrol | `out\08_metraj_kontrol.md` |
| 9 | mst-kabul-denetim | `out\09_kabul_denetim.md` |
| 10 | mst-dokumantasyon | Ana oturum bu oturumda dosyaya yazmadı; özeti bu raporun 7. bölümünde |

Ajanlar arasındaki görüş ayrılıkları kabul denetiminde (09, D1–D10) karara bağlandı:
- B1 (K01): Yüksek.
- S1 (K16): Orta.
- U1 (K11): Düşük.
- Observer tekrarı: yok.
- nav_* ikonları: kullanılıyor.
- `skp:`: yalnız ui.html'de.
- H3: sonradan tespit var.
- Dosya sayısı: 200 + yükleyici.

**Tamamlanan kontroller:**
- SHA ve zip bütünlüğü
- Envanter ve manifest
- Ruby sözdizimi (3.1) ve Ruby 2.5 dilbilgisi
- Ruby 2.6+ yöntem / SketchUp API taraması
- JS: node --check ve gömülü script
- JSON
- Chromium 64 JS/CSS taraması
- require zinciri
- 17 yeniden tanım
- Menü/araç çubuğu → işlev haritası
- JS ↔ Ruby callback eşleşmesi (215 `execute_script`)
- Undo sayımı
- Sessiz rescue taraması
- Bağımlılık ve UID analizi
- Metraj çift sayım taraması
- Sahte nesne testleri:

| Test | Çıkış kodu | Sonuç |
|---|---|---|
| H1 | 1 | 3 geçti, 3 kaldı |
| `.then` | 0 | 16/16 |
| `filter_map` | 0 | 3/3 |

**Doğrulanamayanlar:**
- SketchUp 2020 / Ruby 2.5.5 çalışma zamanı.
- Undo, kaydet ve yeniden açma.
- `skp:` yolu.
- Chromium 64 görünümü.
- Performans ölçümü.
- Golden-master BOQ CSV (referans CSV yok).
- Formül ve katsayıların doğruluğu (belge gerekli).
- Ayrıntılı incelenmeyen alanlar:
  - rockfill_* iç akışları
  - donatı modüllerinin kod incelemesi
  - Diş/konsol ayrıntısı

## 6. SketchUp kabul listesi

`out\06_test_paketleme.md` içinde 24 madde var. Hepsi model kopyası üzerinde yapılmalı.

Önerilen öncelik sırası:
1. Runner menü 1 (Ruby 2.5)
2. Golden-master BOQ CSV
3. K33
4. K36
5. K22
6. K02
7. K01
8. K24
9. K04
10. K06
11. K35

## 7. Dokümantasyon ve CLAUDE.md uyumsuzlukları (mst-dokumantasyon, yalnız tespit)

**Paket dokümantasyonu:**
- README v0.36.7'den kalma.
- RELEASE_UI9.txt'nin son kaydı 0.51.2.
- boq_library.rb:302'deki başlık "v0.31.6" gösteriyor.
- Eklenti açıklaması İngilizce.
- RELEASE'teki "Ruby 2.5.5'te testler geçti" iddiası bu denetimde doğrulanamadı.

**CLAUDE.md'de güncellenmesi gerekenler (kullanıcı onayıyla):**
- Kurulu sürüm: 0.51.4. `mst_kn1_test` kurulu değil.
- 0.51.3 Integrated ve 0.51.4 paket tablosuna eklenmeli.
- `MAG_MST_HealthHistory` ve `MAG_MST_BOQ2` sözlük listesine eklenmeli.
- BOQ kütüphanesi ve dolgu kütüphanesi kullanıcı dosyaları listesine eklenmeli.
- tb.show düzeltmesinin bu hatta olmadığı not edilmeli.

**Terim önerileri (karar kullanıcıda):**

| Önerilen terim | Yerine geçtiği |
|---|---|
| Tretuvar | Bordür |
| Kaplama betonu | Topping |
| Çakım | çakma |
| Model Kontrolü | Model Audit |
| Aks Yöneticisi | Axis Manager |
| Eleman Kütüphanesi | Element Library |
| Ortalama Uç Alan | Average End Area |

"Vinç / Boylama Kirişi" yerine "Vinç Kirişi (VK)" ve "Boylama Kirişi (BBK)" ayrı yazılmalı. BBK açılımı için belge gerekli.

## 8. 2. tur (devam) sonuçları — 29.10.2026

Bu turda üç rol çalıştı; kod düzeltilmedi, dosya değişmedi:

| Rol | Rapor |
|---|---|
| mst-metraj-kontrol | `out\11_metraj_kontrol_tur2.md` |
| mst-kod-inceleme | `out\12_kod_inceleme_tur2.md` |
| mst-kabul-denetim | `out\13_kabul_denetim_tur2.md` |

Dokümantasyon raporu `out\10_dokumantasyon.md` dosyasına kaydedildi.

### 8.1 Ek bağımsız örnek hesaplar

Bütün örneklerde kodun sonucu beklenen değerle aynı çıktı. Örnekler elle izlendi; katsayılar için belge gerekli.

| Kalem | Girdi / açıklama | Beklenen = kodun sonucu |
|---|---|---|
| BK hacmi | Diş + cep (L=10, h=1,0, b=1,2) | 12,594 m³ |
| BK net beton | 3 kazık gömülmesi + menfez düşülmüş | 11,198 m³ |
| BK kalıp | Brüt 37,050 m² | Net 34,318 m² |
| PD | — | 1,548 m³ |
| PK kanal | — | 1,419 m³ |
| PV vinç | — | 2,61 m³ |
| Döşeme + prekast | 9,55 + 6,45 m³ | 16,0 m³ (brüt); çift düşüm/çift sayım yok |
| Kaplama | Tek eğim | 10 m³ |
| Kaplama | Sırt eğim | 7,5 m³ |
| Dolgu, ortalama uç alan | Tek aralık | 1000 m³ |
| Dolgu, ortalama uç alan | Geçiş istasyonlu | 1040 m³ |

**BK diş/konsol:** Ayrı bir işlev yok. Diş, cep ve taban bölgeleri tek bir X-Z profilinin noktalarıdır ve hacimleri profil alanıyla metraja girer (main.rb:396-476). Çok akslı BK düz kutu olarak çizilir.

**Sorun bulunmayan kontroller:**
- Donatı modüllerinin Undo katmanları doğru; iç içe `start_operation` yok.
- Çift 3B donatı oluşturan yol yok.
- Çok kopyalı Component BK donatı koruması var.
- Rockfill'de observer/timer yok.
- Katı denetimi var.
- TIN dejenere üçgende sessiz kalmıyor, hata veriyor.

### 8.2 Yeni bulgular

| Bulgu ID | Öncelik | Modül | Dosya ve satır/metot | Sorun | Tetikleyen işlem | Etkisi | Kanıt | Önerilen düzeltme | Doğrulama durumu |
|---|---|---|---|---|---|---|---|---|---|
| MST-K50 | Kritik | BK beton | main.rb:2502-2512 `mst_bk_pile_embed` | Gömülme ana gövde tabanından ölçülüyor; diş/bölge derinliği yok sayılıyor | Kazık dişin veya alçak bölgenin altında | BK betonu fazla (örnek: 0,567 m³ yerine 0,162 m³ düşülüyor) | 11 | Gömülmeyi yerel taban kotundan ölçmek; golden-master | Doğrulanmış (S+A) |
| MST-K57 | Kritik | Donatı silme | mst_dwg_rebar.rb:552-556, 382-395; main.rb:3382-3383 | Süzgeç yalnız `rebar_mode` alanına bakıyor; paftadan metraj ve prekast donatısını da yakalıyor | "Çizimden/Otomatik Donatıyı Sil" (seçim boşsa bütün model) | Component prekastta 3B silinir ama tonaj definition'dan okunmaya devam eder; pafta verisi kalır | 12, 13 | Süzgece eleman türü / `rebar_kind`; prekastı `mst_pc_clear!` ile silmek | Doğrulanmış (S+A+D); "bütün kopyalarda 3B silinir" kısmı SketchUp testi gerektirir |
| MST-K58 | Kritik (doğrulama bekliyor) | Prekast donatısı | main.rb:11214, 11222, 11407-11409; mst_pc_rebar.rb:222, 227 | Boy değişince parça paylaşılan definition'a geçiyor; çizim ve öznitelikler bütün örneklere yazılıyor | Donatılı Component prekastın boyunu değiştirmek | Seçilmemiş aynı boylu prekastlara donatı/tonaj sızar | 12 (tek kaynak) | "Unique yap / ayır" sorusu | Olası risk (S); SketchUp testi gerekli |
| MST-K59 | Yüksek | Kazık donatısı | main.rb:12026-12034, 12122-12127 | Hata durumunda `pile_cage_rebar_kg=0`; `pile_rebar_error` hiçbir yerde okunmuyor | Kafesli kazıkta ölçü/kot değişikliği sırasında hesap hatası | Kazık donatı metrajı sessizce 0 | 12, 13; grep | Kullanıcıya bildirmek; pursantaja dönmek | Doğrulanmış (S+A+D) |
| MST-K51 | Yüksek | BK kalıp | main.rb:2193-2209, 2225-2228, 2240-2245 | Yüz anahtarı yalnız tür + normal; tabanlar ve uç/cep yüzleri aynı anahtarda | Tek yüzü kalıptan çıkarıp BK'yı revize etmek | Kalıp seçimi aynı anahtardaki bütün yüzlere yayılır | 11 | Yüz anahtarına konum bilgisi eklemek | Olası risk (S, tek kaynak) |
| MST-K53 | Yüksek | Kaplama | main.rb:5530, 5578 → 5083-5087; mst_v50_misc.rb:59-62 | Döşeme yenilemesi oluşturma anındaki girdiyi okuyor | Kaplama eğimi/ekleme sonrası BK/PD değişikliği | Kaplama kalınlığı ve metrajı sessizce eski değere döner | 11 | Yenilemede kaplama durumunu korumak | Olası risk (S, tek kaynak) |
| MST-K55 | Yüksek | Dolgu Alt-1 | main.rb:9180-9182; boq_mapping.rb:16 | Kütüphanede olmayan malzemenin yoğunluğu 0 alınıyor | Bilinmeyen malzeme kodu | Tonaj uyarısız 0 (Alt-2 bu durumda hata veriyor) | 11; satırlar okundu | Hata/uyarı vermek | Doğrulanmış (S+A) |
| 08-R6 | Orta | BK kalıp | main.rb:2460, 1445, 1815 | Alt yüz kalıp dışındayken kazık açıklığı yine düşülüyor | Alt kalıbı kapatmak | Net kalıp eksik | 08, 11 | Koşullu düşüm | Olası risk (koşullu) |
| MST-K52 | Orta | Kaplama | main.rb:3473-3474 ile 4098 | `topping_enabled` alanı olmayan eski döşemede BOQ kaplamayı 0,10 m ile ekliyor, rapor eklemiyor | Eski model | BOQ ile rapor tutmaz | 11 | Niyet/belge | Olası risk |
| MST-K60 | Orta | Prekast donatısı | mst_pc_rebar.rb:244-249 | Çizim hatasında 3B yok, eski tonaj kalıyor; `pc_rebar_error` okunmuyor | Prekast yeniden kurulurken hata | Sessiz uyuşmazlık | 12 | Bildirmek | Olası risk (S) |
| MST-K61 | Orta | Donatı çakışma | mst_rebar_tools.rb:543-548 | Yalnız yerel `transformation` kullanılıyor | Üst grup içindeki eleman | Yanlış ya da kaçan çakışma | 12 | Tam dönüşüm zinciri | Olası risk (S) |
| MST-K63 | Orta | Donatı geri yükleme | mst_dwg_rebar.rb:389-395; main.rb:2844-2845 | Önceki BIM verisi geri yüklemeden önce siliniyor | Geri yükleme hatası | BIM donatısı kaybolur, pursantaja döner | 12 | Önce kur, sonra sil | Olası risk (S) |
| MST-K54 / K56 / K62 | Düşük | PV / Alt-1 / Undo | main.rb:4313; 9168; rockfill_live.rb:239-245, 312-317 | PV diş < oturma kontrolü yok; aynı istasyonda iki kesit sıralaması kararsız; komut başına 2 Ctrl+Z | — | Çift hacim / yanlış aralık / Undo | 11, 12 | — | Olası risk |

### 8.3 Ek olası riskler (belge veya test gerekli)
- **DXF "L=" birimsiz metre okunuyor** (mst_dx_rebar.rb:23-27). cm paftada tonaj ×100 çıkar ve makullük denetimi yok.
- **Otomatik pafta toleransı** çizim biriminde uygulanıyor; INSUNITS 0 ise metre varsayılıyor.
- **Performans riskleri:**
  - TIN ≤ 5000 nokta.
  - BOQ yenilemesinde her seferinde canlı geometri / O(n²) hesap (boq_mapping.rb:7).
- **Donatı revizyon geçmişi** son 10 kaydı tutuyor (mst_rebar_tools.rb:484).
- **Pursantaj oranı:** `mst_dr_clear!` her öğeye BK pursantajını yazıyor; prekast/pafta öğesi için doğru oran mı, belge gerekli.
- **Prekast derz harcı** hiçbir pozda sayılmıyor.

### 8.4 Güncel öncelik özeti

**Kritik:**
- K33: C35/45 dışı prekast betonu
- K36: Component kazık iç betonu
- K22: Döndürülmüş prekast boyu
- K02: Revizyon arşivi
- K35: Hakediş ayrı poz kayması (ikinci teyitli)
- K50: Diş altı kazık gömülmesi
- K57: Donatı silme
- K58: Prekast donatı sızıntısı (doğrulama bekliyor)

**Yüksek:**
- K01, K04, K05, K06, K24, K34, K38, K23, K09, K19, K27, K12
- K59, K51, K53, K55

**Düşürülenler:**
- K32 → Düşük: yalnız görünüm. Kazık ayar perdesi hiç açılmadığı için `inset` işlevsiz.
- K14 → Düşük: fiilen `skp:` yoluna bağlı.

### 8.5 Durum
Genel sonuç: **kısmen karşılandı.** Sekiz bölümden yalnız 2. bölüm (dokümantasyon) "karşılandı" oldu; ötekiler kısmen kaldı.

**Hâlâ doğrulanamayanlar:**
- SketchUp 2020 / Ruby 2.5.5 çalışma zamanı ve Chromium sürümü.
- Undo, kaydet ve yeniden açma.
- `skp:` yolu.
- Performans.
- Golden-master CSV.
- Belge gerektiren formül, katsayı ve poz eşlemeleri.
- Tek kaynaklı bulgular: K51, K52, K53, K54, K56, K58, K60–K63.
- Gövdesi okunmayan dosyalar:
  - rockfill_cut_mesh, void_loft, transitions, refinement, report
  - mst_ar_plan, mst_dr_plan, mst_dra_*
  - mst_pile_rebar_calc
  - HeadBeamEditor

Bu turda sahte nesne testi çalıştırılmadı.

**SketchUp kabul listesine eklenecek maddeler:**
- K50: Dişin altında kazık bulunan BK.
- K51: Diş tabanını kalıptan çıkarıp BK'yı revize etmek.
- K53: Kaplama eğimi uygulandıktan sonra BK kotunu değiştirmek.
- K57: Seçim boşken "Donatıyı Sil".
- K58: İki Component PD'nin boylarını eşitlemek.
- K59: Kafesli kazıkta hesap hatası.
- DXF "L=" birim denemesi.
