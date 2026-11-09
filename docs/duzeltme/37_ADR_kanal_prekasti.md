# 37 ADR-0515-K2 — Kanal prekastı: tek parametrik kesit, Prekast Yerleşimi seçimi, 3 kot yöntemi, döşeme boşluğu (mst-mimar, 09.11.2026; salt okuma, kod yazmadı, test çalıştırmadı; ana oturum kaydetti)
Durum: Önerildi. Kaynak `src/marine_structures_tools` @ `f0035e6` (rapor 35 satırları doğrulandı: 4588, 4652, 4845, 12389, 12751, 12828, 12964, 13003). Satırlar main.rb, aksi belirtilmedikçe. Girdi: rapor 35, referans 36.

## Bağlam (doğrulanan)
- PK üç yoldan oluşur, hepsi U formülünü tekrarlar: tek kanal formu (:4652; Group, 3 iç grup, kalıp boyanmaz, support_*_pid yok → bağımlılık ağında değil, dependency_rebuild.rb:44-53), Prekast Yerleşimi (:4588-4592), KN cebe yerleştirme (:12964-12985).
- Kesit ölçüsü okuyan diğer yerler: MST_PRECAST_DEF_DIMS (:12502), hacim (:12510), rol bazlı kalıp (:12612), geometri (:12557), tip imzası (:6531), donatı (mst_pc_rebar.rb:53-55), döşeme iw/base (:5101), Model Sağlığı (:8565), raporlar (:3926, :9268), Kontrollü Düzenleme (controlled_editor.rb:10, :29, :160).
- Kalıp sınıflandırması U'ya göre (paint_channel_precast_formwork :291-325): dış yan yüz yalnız y=0 / y=ow; taban üstündeki her yukarı bakan yüz INNER_FLOOR → ofsetli çıkıntı dış yüzü ve taban ledge'i yanlış role düşer.
- mst_def_key params'taki tüm anahtarları içerir (:779-781): anahtar eklemek eski U tanım anahtarını değiştirir.
- Döşeme (:4886-4923): prekast kutusu z0..z1 tam boşaltılır (:4919-4920); kanal açıklığı kutu ortasına simetrik iw genişliğinde, taban üstünden döşeme üstüne; hücre bazlı aralık çıkarma çift düşümü önler.
- Döşeme yeniden üretimi yalnız BK düzenlemesi ve KN yerleşimi sonrası (:13007, :13022); mst_deck_after_edit transparent (:5881-5896); bağımlılık observer'ı yalnız metadata (dependency_rebuild.rb:206-228) → PK silinince döşeme güncellenmez.

## Bulgular
1. Group/Component/Type: yerleşim + KN varsayılanı Component (:4598-4601, :12968); tanım düzenlenmez, parça başka tanıma geçirilir (:12641-12649); tip adı precast_type_id, type_id imzadan (:8033-8048); kesit değişikliği = yeni tanım + yeni type_id, diğer örneklere sızmaz.
2. Kimlik: KN bağı kn_from_pocket = "görünür BK kodu:taraf" (:12981) — BK kodu değişirse kopar; destekler PID (support_left/right_pid); UID'ye dokunulmaz.
3. Dönüşüm: cep kutusu dünya uzayında (:12753-12757); KN kapsayıcı dönüşümünü yalnız tek örnekli tanımda tersine çevirir (:12971); kesit yerel düzlemi y-z (y en, z taban altından yukarı).
4. Kayıtlı veri: precast_type_library_json JS'ten gelen tam listeyle üzerine yazılır (:4604); JS bilinmeyen alanları tutuyor gibi (ui.html:1406) — tamamı okunmadı.
5. Bağımlılık/QTO: PK BK'nın, döşeme PK'nın çocuğu (dependency_rebuild.rb:44-53); BK kotu değişince bağımlılar aynı dz ile taşınır (:1991); cep derinliği/ofseti değişince PK yeniden oturtulmaz (:13003-13005).
6. Undo: yerleşim + KN normal işlem (:12988-12998); mst_kn_place BK işleminden sonra ayrı normal işlem (onay penceresi) → BK düzenlemesi iki Geri Al; döşeme güncellemesi transparent.

## Kararlar
- **K1 Veri modeli (önerilen A):** öğe üzerinde tek `channel_section_json` = `{"v":1,"preset":"U|L|UU|K|OZEL","total_width_m","base_m","left|mid|right":{"on","width_m","height_m","offset_m"}}` (sol ofset soldan, orta soldan, sağ sağdan; pasif çıkıntı değerleri saklanır); aynı nesne tip kaydında `section`. Yoksa eski U eşlemesi: toplam = wi + 2tw, taban = tb, sol/sağ açık tw × di ofset 0, orta kapalı. Eski anahtarlar (inner_width_m, inner_depth_m, base_thickness_m, wall_thickness_m, outer_width_m) silinmez, anlamı değişmez: U-eşdeğeri kesitte (simetrik, iki yan, ofset 0, eşit yükseklik, orta yok) gerçek değer; U değilse 0 (açık karar 1) — eski sürüm U dışını yeniden kurmayı reddeder (:12590, :8907). width_m / outer_width_m = toplam genişlik. Uyumluluk: yeni anahtar eski sürümde okunmaz; eski sürümde U dışı PK'nın döşeme açıklığı çıkmaz (iw = 0, :4886). B (≈13 skaler anahtar) önerilmez.
- **K2 Tek kesit kaynağı:** yeni modül `channel_section.rb` (saf Ruby): mst_ch_section(e|h) (eski eşlemeli), mst_ch_profile (dış kontur), mst_ch_area (taban × toplam + Σ genişlik × yükseklik), mst_ch_formwork(len, flags), mst_ch_valid? (yalnız geometrik). Bağlanacak tekrarlar: :4589-4591, :4677, :8910-8917, :12390-12401, :12510, :12557-12560, :12612-12613, :12975, controlled_editor.rb:25/:141. Tanım anahtarına ve tip imzasına (:6531) `section` yalnız U-eşdeğeri olmayan kesitte eklenir (BK cep eki deseni :6525) → eski U anahtarları değişmez. Geometri tek yüz itme (taban ∪ açık çıkıntılar), Group/Component deseni korunur, iç grup yok. Kalıp rolleri kesitten (yeni rol gerekebilir, açık karar 4). Geçersiz: açık çıkıntıda ölçü ≤ 0; ofset + genişlik > toplam; açık çıkıntılar çakışır/bitişir; hiç çıkıntı yok (açık karar 5). Canlı önizleme JS'te aynı formül, modeli değiştirmez; test Ruby ↔ JS sonucunu karşılaştırır.
- **K3 Tanımlı yüzeyler:** alt oturma = taban altı (z = 0), tüm ön ayarlarda. Üst: (a) en yüksek açık çıkıntı üstü (bugünkü U: taban + di, :4591, :4678), (b) tipte seçilen çıkıntı, (c) taban üstü — öneri (a) varsayılan, (b) isteğe bağlı (açık karar 2); (b) için `channel_top_ref`.
- **K4 Yerleşim + cep uyumu:** kaynak precast_type_library_json, sonra modeldeki PK'lar (:12840-12855). Uyum: dış genişlik = cep genişliği − 2 × derz (±5 mm MST_KN_TOL); toplam yükseklik = referans üst − cep tabanı; iki cebin taban kotu ve hizası (:12885-12893); cep derinliği ≤ toplam yükseklik. Uyumsuzluk metni ölçü + beklenen + mevcut ("dış genişlik 1,150 ≠ 1,200 m"). mst_kn_find_pk_type ilk uyanı döndürür (:12847) → tüm adayları gerekçeyle döndüren salt okuma varyant eklenir, eski korunur.
- **K5 Kot yöntemi:** `elevation_mode` TOP | POCKET | MANUAL (yoksa TOP), `elevation_ref_m`, `elevation_ref_face` TOP | BOTTOM; cep bağı `seat_bk_left_uid`, `seat_bk_right_uid` + taraf (PID ikinci yol; kn_from_pocket yazılmaya devam). BK cebi değişince mst_kn_after_edit genişler: POCKET PK cep tabanına yeniden oturur, yatay kayma denetlenir. Undo: BK komut zinciri içinde, onaysız, transparent (desen :5881-5896, abort yok) — öneri (açık karar 6); seçenek ayrı normal işlem.
- **K6 Döşeme boşluğu:** opens PK başına çok aralığa genelleşir (açık gözler: çıkıntılar arası + isteğe bağlı dış ledge); merkez varsayımı kalkar, yön kesit verisinden + dünya dönüşümü (aynalama/dönüş SketchUp'ta doğrulanmalı). Kutu tam boşaltma (:4920) dış ledge'in dolmasını engeller; "ledge dolar" kararıyla kontur boşaltılır (açık karar 3). Çift düşüm: hücre + aralık çıkarma korunur. Tetik: PK tip/ölçü/kot/konum düzenlemesi sonrası destek BK'larıyla mst_deck_after_edit. Silme: (A) observer + transparent zamanlayıcı / (B) Model Sağlığı uyarısı + "Döşemeyi güncelle" (:5906) — öneri B (açık karar 7). deck_revision_no ileri yazılır (:5898, beklenen).
- **K7 Kontrollü Düzenleme / boy:** boy yolu (:12437-12449) mst_ch_*'a; Component yolu section parametresiyle tanım değiştirir. Kontrollü Düzenleme U dışını reddeder (controlled_editor.rb:29) → öneri: U dışı PK için "Kanal Prekastı formundan düzenleyin" (açık karar 8).
- **K8 Riskler / test / partiler:** riskler — eski U imzası/tanım anahtarı değişmesi (tip churn), kalıp rolü, eski sürümde açma, çok kopyalı PK tanımı, KN Y-yönü sınırı (:12878). Sahte nesne: eski U alan/hacim/imza bugünküyle bayt düzeyinde aynı, geçerlilik, uyum metinleri, kot, döşeme aralıkları + çift düşüm. Yalnız SketchUp: yüz sınıflandırma, itme, Component değiştirme, Geri Al zinciri, kaydet-aç, eski model. Partiler: P1 kesit modülü + form/önizleme + üretim (3 yol); P2 yerleşim listesi + cep uyumu; P3 kot yöntemleri + bağ; P4 döşeme + metraj; P5 uyumluluk, regresyon, golden, tek RBZ.

## Seçenekler
A) tek JSON + koşullu eski anahtar + tek kesit modülü (önerilen) · B) ayrı skaler anahtarlar · C) dört ayrı tip/formül (video kararıyla çelişir).

**Metraja etki: VAR** — PK beton/kalıp (yeni kesitler; eski U değişmemeli), döşeme net beton + channel_opening_volume_m3 + kalıp, PK donatısı (mst_pc_rebar.rb:25-31, :53-55 duvar + taban varsayar; U dışı için belge gerekli) → CHANGELOG "Metraj sonucunu değiştirenler" + golden-master (eski U modelinde fark 0).
**Dokunulmayacak:** dependency_rebuild.rb, finalize_bim_identity, mst_sync_precast_type_library mantığı, UID üretimi, RevisionLog, boq_pro formülleri, BK cep geometrisi (:417-452).

## Doğrulanamayan
ui.html JS'in tip kaydını gidiş-dönüşte koruması; rebuild_channel_parametric başka dinamik çağıran (tarama tam değil); eski sürümün 0 değerli eski anahtarlarla canlı davranışı; aynalı/dönük PK'da kesit yönü; okunmayan boq_pro.rb, model_health.rb, structure_copy.rb (PK alan kopyası).

## Açık kararlar (kullanıcı)
1. U dışı kesitte eski anahtarlar: a) 0 yaz (eski sürüm reddeder) / b) zarf değeri / c) yazma — öneri a.
2. Üst yüzey: a) en yüksek çıkıntı / b) tipte seçilebilir / c) taban üstü — öneri a varsayılan + b isteğe bağlı.
3. Döşemede açık göz: a) yalnız çıkıntılar arası / b) + dış ledge açık / c) dış ledge döşeme betonuyla dolar — öneri a + c (belge gerekirse sor).
4. Kalıp: taban üst ledge'i iç kalıp mı ayrı rol mü — öneri ayrı rol, varsayılan kalıp.
5. Çıkıntısız düz plak: a) ret / b) izin — öneri a.
6. BK düzenlemesi sonrası PK yeniden oturtma: a) transparent tek Geri Al / b) ayrı normal işlem — öneri a.
7. PK silinince döşeme: a) observer otomatik / b) Sağlık uyarısı + elle güncelle — öneri b.
8. U dışı PK Kontrollü Düzenleme: a) desteklenir / b) forma yönlendirilir — öneri b (P1).
9. U dışı kesit donatısı: a) hacim × oran / b) donatı planı için belge — öneri a.
10. Tek kanal formu (Group, iç grup, destek PID yok): a) yeni kesitle Component + destek PID / b) olduğu gibi — öneri a (bağımlılık ve metrajı etkiler).

Kullanıcı kararları bu bölümün altına eklenecek.

## Kullanıcı kararları (09.11.2026; "önerilerle devam")
0. Dört şekil ayrı tip değil, tek parametrik kesitin ön ayarları; her PK kodu bir ölçü takımı taşır.
1. U dışı kesitte eski U anahtarlarına 0 yazılır (a).
2. Üst yüzey: varsayılan en yüksek açık çıkıntı üstü; tipte isteğe bağlı çıkıntı seçimi (`channel_top_ref`).
3. Döşeme: çıkıntılar arası kanal gözleri açık; prekast gövdesi dışındaki alçak taban (dış ledge) üstü döşeme betonuyla dolar (a + c) → kutu yerine kontur boşaltılır.
4. Taban üst ledge kalıbı ayrı rol, varsayılan kalıplı.
5. Çıkıntısız düz plak reddedilir.
6. BK cebi değişince POCKET modlu PK otomatik yeniden oturur; BK düzenlemesiyle tek Geri Al (transparent, abort yok).
7. PK silinince döşeme: Model Kontrolü uyarısı + elle "Döşemeyi güncelle" (observer yok).
8. U dışı PK Kontrollü Düzenlemede desteklenmez; Kanal Prekastı formuna yönlendirilir.
9. U dışı kesit donatısı hacim × kg/m³ (ayrıntılı plan için belge gerekli).
10. Tek kanal formu yeni kesitle Component + destek PID (bağımlılık ve metraj etkisi kabul).
11. (09.11.2026, P1a sonrası) Sol / sağ taban üstü (yan çıkıntının dış tarafı) döşemede "açık kalır / döşeme doldurur" tipte seçilir; varsayılan L ve U açık, K dolu (karar 3 bu seçimle uygulanır).
12. (ana oturum, teknik) U-eşdeğeri girdide channel_section_json yalnız açık `section` verisi varsa yazılır (eski girdide yazılan anahtarlar birebir aynı); U dışında outer_width_m / width_m = toplam genişlik, iç ölçü anahtarları 0. Tek BK'lı form PK BK boyu değişince yeniden boyutlanmaz (bilinen sınır, P5 notu). channel_top_ref üretime P3 içinde bağlanır.
