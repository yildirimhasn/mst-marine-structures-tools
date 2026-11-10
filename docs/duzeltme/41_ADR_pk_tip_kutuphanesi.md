# 41 ADR-0515-K3 — PK tip kütüphanesi, tip/örnek/revizyon kimliği, yapı bazlı yerleşim (mst-mimar, 10.11.2026; salt okuma, kod yazmadı, test çalıştırmadı; ana oturum kaydetti)
Durum: Önerildi. Kod: `src/marine_structures_tools` @ cf893fd; satırlar main.rb, aksi belirtilmedikçe. Girdi: talimat 40a, kaynak analizi 40, ADR 37.

## Bağlam (doğrulandı)
- Tip kütüphanesi model içinde tek attribute `precast_type_library_json` (DICT); tek yazım yeri Prekast Yerleşimi (:4642) → kütüphane düzenlemesi yerleşim çalışmadan kaydedilmez. JS kaydı `{uid:'pt_pk_…', family, name, section…}` (ui.html:1462-1489).
- Kanal Prekastı formu kütüphaneyi ne okur ne yazar (:4698-4749); "Tipi Olarak Kaydet" yok.
- Öğe tipe yalnız adla bağlı: `precast_type_id = precast_type = name` (:4623, :4630); kütüphane `uid`'si öğeye yazılmaz.
- `type_id` / `library_type_id` imzadan (boy dahil, `KP-Txx`), `finalize_bim_identity` yerleşimin yazdığı adın üzerine yazar (:6795-6799, :6674).
- Öğedeki `revision` yazılım sürüm metni (:6804, controlled_editor.rb:214); RevisionLog model anlık görüntüsü (:10111, :10303) — ikisi de geometri revizyonu değil.
- Paylaşılan tanım düzenlenmez: tanım anahtarı tip+kesit+boy+kalıp+malzeme+donatı (:12707-12723); değişen parça yeni anahtarın tanımına geçer (:12680-12684, :12839-12847).
- Tip adı değiştirme yalnız öğeleri değiştirir, kütüphaneyi değil (:12667-12670).
- Kot TOP | POCKET | MANUAL (:13259, :13284-13298); form PK'yı BK üstüne oturtur (:4716-4718).
- Yapı aidiyeti `system` / `structure` / `ano` (ADR 31). Atomik yazım deseni: boq_library.rb:99-112, accessories.rb:237-261.

## Karar başına analiz
**(a) Tipi Olarak Kaydet.** Kayda: `section`, `geom_sig`, `concrete`, kalıp seçimleri, `seat`, `created_at`, `pk_rev`, `rev_log`. Birim hacim/kalıp kesitten hesaplanır (saklanmaz); kullanıldığı proje/yapılar saklanmaz, öğelerden hesaplanır (bayatlamaz). Aynı `geom_sig` → mevcut tip gösterilir. Ad benzersizliği zaten denetleniyor (:4579, :12649). Normal işlem: önce doğrulama, sonra start/commit, hatada abort. Metraj: yok.
**(b) Kütüphanenin yeri.** A yalnız model (bugün; projeler arası yok) · B yalnız kullanıcı dosyası (model taşınınca tip verisi kaybolur) · **C önerilen:** model kopyası esas + kullanıcı dosyası `%APPDATA%\MarineStructuresTools\PKLibrary\pk_types.json`, yalnız elle içe al / dışa ver, otomatik eşzamanlama yok. Çakışma: aynı kod + farklı `geom_sig` birleşmez, yeniden adlandırma istenir. Bozuk dosyanın üzerine yazılmaz.
**(c) Kimlik.** PK Type ID = `precast_type_id` (kod); kayıt `uid`'si öğeye yeni `precast_type_uid` (eski modelde yoksa adla eşleme). `type_id`/`library_type_id` aynen (otomatik, boya bağlı). PK Revision yeni anahtarlar: kayıtta `pk_rev` (tam sayı, yalnız artar), öğede `precast_type_rev`; `revision`, `bk_revision_no`, RevisionLog bu amaçla kullanılmaz. `element_uid` hiçbir yolda yeniden üretilmez. Eski sürüm yeni anahtarları okumaz (zararsız).
**(d) Tip düzenleme.** Yalnız seçilen: "yetim" örnek olmasın diye zorunlu "yeni tip olarak kaydet + seçilene uygula". Tüm örnekler: önce salt okuma plan (örnek/yapı sayısı, cep uyumu); uymayan tek örnek varsa başlamaz. Tek normal işlem "PK Tipini Güncelle": Component örneği kendi boyuyla yeni tanıma (:12839 deseni), Group yeniden kurulur; hacim/kalıp yeniden yazılır, `mst_precast_canonical_type!` (:12613) + `mst_pc_after_rebuild!`; kot öğenin kot yöntemiyle; etkilenen BK döşemeleri aynı işlemde (transparent `mst_deck_after_edit` kendi işlemini açmadan çağrılmalı); `commit_with_dependencies`, hatada abort. Paylaşılan tanım düzenlenmez. **Metraj: VAR** (PK beton/kalıp/donatı, döşeme net beton, kanal açıklığı) → golden-master.
**(e) Yapı bazlı yerleşim.** Yeni yerleşim kaydı gerekmez: kayıt öğenin kendisi (`precast_type_id` + `precast_type_uid` + `structure`). Kütüphane ortak, kullanım öğelerden. "Tüm örnekleri güncelle" varsayılan kapsamı seçili yapı; "tüm yapılar" yapı başına sayılarla onaylatılır.
**(f) Kot.** Kayıtlı değerler yeniden adlandırılmaz (arayüz etiketi değişebilir). A önerilen: yeni `SUPPORT` modu (alt yüz = BK üstü, BK değişince izler; eski sürüm TOP okur :13271-13273; yeniden oturtma bugün yalnız POCKET'ta). B: MANUAL + BOTTOM, ref = BK kotu (eski sürümle uyumlu, BK değişince izlemez). Metraj: döşemede kanal açıklığı yüksekliği etkilenebilir.
**(g) PK silinince.** Karar 7 ile talimat çelişir. A observer + transparent zamanlayıcı (yeniden tetiklenme riski, karar 7'yi bozar) · **B önerilen:** "PK Sil" komutu — PK silinir, ilgili döşemeler aynı normal işlemde yeniden kurulur (:6048 elle güncelleme deseni) · C bugünkü. Kullanıcı kararı.
**(h) 3B önizleme.** Mevcut SVG kesitin (ui.html:946) aynı profille izometrik uzatılmışı; WebGL yok (sürücü riski); callback yok, model değişmez; test JS ↔ Ruby profil eşitliği.
**(i) Atomiklik.** Doğrulama işlem açılmadan; model değişiklikleri + kütüphane attribute'u tek normal işlemde. Kullanıcı dosyası Geri Al dışında: commit sonrası atomik yazım; dosya hatası ayrıca bildirilir, model geri alınmaz.

## Riskler
Ada bağlı tip bağı (ad değiştirme kütüphaneyle eşleşmiyor :12667); kütüphane modele kaydedilmeden kalabilir (:4642); toplu düzenlemede cep uyumsuzluğu; çok kopyalı tanım; eski sürüm `SUPPORT`'u okuyamaz.

## Testler
Sahte nesne: `geom_sig` tekrar tespiti, eski JSON bayt düzeyinde korunur, plan/kapsam sayımı, ret yolları, kot hedefleri, SVG ↔ Ruby profil. Yalnız SketchUp: tanım geçişi, tek Ctrl+Z, kaydet-aç, eski modeli açma, döşemenin yeniden kurulması, dosya içe/dışa.

## Kullanıcıya sorulacak kararlar
1. Kütüphanenin yeri A/B/C — öneri C, elle aktarma.
2. Yeni anahtarlar `precast_type_uid`, `pk_rev` / `precast_type_rev` — öneri evet.
3. "Yalnız seçilen" düzenleme zorunlu yeni tip — öneri evet.
4. "Tüm örnekler" kapsamı — öneri varsayılan yapı, seçenekle tüm model.
5. Tip değişince kot — öneri öğenin kot yöntemiyle yeniden hesap.
6. Alt kot `SUPPORT` mu MANUAL+BOTTOM mu — öneri `SUPPORT`.
7. PK silme: B komutu mu, karar 7 aynen mi — öneri B.
8. Önizleme SVG izometrik — öneri evet.

## Parti planı
P1 Tip kaydı (model içi): "PK Tipi Olarak Kaydet", tekrar tespiti, kütüphanenin işlemle kaydı, yeni öğeye `precast_type_uid` — kabul: eski model JSON'u değişmez, golden 0 fark. P2 Form ↔ kütüphane: formda tip seçimi, kullanım listesi, 3B SVG — golden 0, önizleme modeli değiştirmez. P3 `SUPPORT` kot — TOP/POCKET/MANUAL çıktıları aynı. P4 Tip düzenleme (3 seçenek) + PK Sil — tek Ctrl+Z, çok kopyalı tanım değişmez, golden farkları açıklanmış. P5 Kullanıcı dosyası içe/dışa — bozuk dosyanın üzerine yazılmaz. P6 Tam regresyon, golden, tek RBZ.

## Uygulayıcıya sınırlar
Dokunulmayacak (ADR 37): `dependency_rebuild.rb`, `finalize_bim_identity`, `mst_sync_precast_type_library`, UID üretimi, RevisionLog, `boq_pro` formülleri, BK cep geometrisi; ek: `type_id`/`library_type_id` kuralı, öğedeki `revision` anlamı, `mst_def_key`.

## Doğrulanamayan
PK silindikten sonra döşeme yeniden kurulumunun yalnız ilgili açıklığı değiştirdiği (SketchUp'ta denenmeli); `mst_deck_after_edit`'in normal işlem içinden güvenle çağrılabildiği (kendi işlem açma yolu okunmadı).

Kullanıcı kararları bu bölümün altına eklenecek.

## Kullanıcı kararları (10.11.2026)
1. Kütüphane: **C** — model kopyası esas + kullanıcı dosyası (`%APPDATA%\MarineStructuresTools\PKLibrary\pk_types.json`), elle içe al / dışa ver, otomatik eşzamanlama yok, aynı kod + farklı geometri birleşmez.
2. (ana oturum, mimar önerisi) Yeni anahtarlar `precast_type_uid` (öğe), `pk_rev` (kayıt), `precast_type_rev` (öğe); eski modelde adla eşleme.
3. "Yalnız bu eleman" düzenlemesi zorunlu yeni tip açar.
4. "Tüm örnekleri güncelle": varsayılan seçili yapı, seçenekle tüm model; önce plan (yapı başına adet, cep uyumu), uymayan örnek varsa başlamaz, tek Geri Al.
5. (ana oturum, mimar önerisi) Tip değişince kot öğenin kot yöntemiyle yeniden hesaplanır.
6. Alt kot: yeni **`SUPPORT`** modu (alt yüz BK üstüne, BK değişince izler; eski sürüm TOP okur). TOP/POCKET/MANUAL kayıtlı değerleri değişmez.
7. PK silme: **"PK Sil" komutu** (PK + ilgili döşeme aynı normal işlemde, tek Geri Al); SketchUp Delete ile silmede karar 7 (uyarı + elle güncelle) geçerli kalır.
8. (ana oturum, mimar önerisi) 3B önizleme: SVG izometrik, WebGL yok.
9. (10.11.2026, P4 sonrası, kullanıcı) Tip güncellemesinde/seçili PK'ya uygulamada kesit genişlerse komşu prekastla (PD/PDÖ/PV/PK) çakışan örnek **uygun değil** sayılır ("komşu … ile X mm çakışır"), işlem başlamaz; kesit **ortadan** (iki yana eşit) büyür/küçülür; komşular kendiliğinden kaydırılmaz; `layout_width_m` güncellenir.
