# 42 Kod incelemesi — PK tip kütüphanesi, ADR-0515-K3 a35894c..daf301e (mst-kod-inceleme, 10.11.2026; salt okuma, komut çalıştırmadı; ana oturum kaydetti)
Yöntem: git farkı görülemedi; `K3` / `karar 9` işaretli bölgeler ve çağrı yerleri okundu. Test kanıtı yok. Okunan: main.rb 4560-4760, 5968-6056, 12482, 12620-12655, 12779-12870, 13090-13190, 13300-14140; pk_library_file.rb (tamamı); ui.html 1529-1555, 2520-2623, 2740-3157; dependency_rebuild.rb:162; mst_pc_rebar.rb:247. Okunmayan: chDrawIso/channelIsoSvg (2331-2400), structure_copy.rb, kn_place SUPPORT yolu (14280-14310), mst_ch_* yardımcıları, testler. Sonuç: 1 engelleyici, 3 önemli, 8 küçük.

## Engelleyici
**E1 JS listesi kütüphanenin kaynağı sayılıyor; Geri Al sonrası liste yenilenmiyor** (`main.rb:13434`, `pk_library_file.rb:190`, `ui.html:2795`, `:2616`). `loadPrecastTypeLibrary` yalnız callback yanıtlarında; `onTransactionUndo` ile JS listesini yenileyen yol yok. Senaryo 1: Tipi Güncelle (rev 1→2) → Ctrl+Z → başka "PK Tipi Olarak Kaydet" → modele rev 2 kaydı (yeni kesit) geri yazılır, örnekler rev 1 geometride. Senaryo 2: geri alınan kayıt sonraki kayıtla / İçe Al ile sessizce geri gelir. Kayıtlı veri + Undo kuralını bozar (aynı desen 4648 yerleşimde zaten vardı; K3 revizyon anlamı ekler). Öneri: Ruby model kütüphanesini esas alsın, yalnız yeni kaydı eklesin; olmazsa istek taban özeti taşısın, uyuşmazsa ret + JS listesi yenilensin.

## Önemli
- **Ö1 Group paylaşımlı tanım** (`main.rb:13703`): `entities.clear!` öncesi `make_unique` yok; Ctrl+C/V kopyalı PK Group'ları aynı tanımı paylaşır → "yalnız bu eleman"da kardeşlerin geometrisi de değişir, öznitelikleri eski kalır (geometri ↔ metraj tutarsız). Aynı desen 12586. Öneri: birden çok örnek varsa `mst_make_unique_keep_data!`.
- **Ö2 Karar 9 komşu denetimi destek PID'siz PK'da sessizce atlanır** (`13559`) → plana "komşu denetimi yapılamadı" uyarısı.
- **Ö3 Onaylanan plan ↔ uygulanan eşitlik denetimi yok** (`13860`): plan sonrası modele PK eklenirse onaylanmamış örnekler de güncellenir → istek plandaki PID listesini taşısın, Ruby eşitliği denetlesin.

## Küçük
- K1 yuvarlama Ruby ↔ JS farklı (`13313` ↔ ui.html:2926): 1.00005 Ruby "1.0001", JS "1.0000" (Ruby yeniden denetler; yalnız not tutarsız).
- K2 oturmasız eski kayıtta JS notu "tip bağı kurulamaz" (`2963`) ↔ `2988` ve Ruby `13377` kesitle bağ kurar.
- K3 boş dize oturma: `pkf_sig` '-' (`pk_library_file.rb:63`), geom_sig/JS 0,0000; `rec_seat` boş dizeyi boş sayar, `same_geom` yalnız nil.
- K4 içe almada geom_sig yeniden hesaplanmaz (`pk_library_file.rb:231`) → bayat imzalı kayıt form bağında hep reddedilir; doğrulanmış `k2` yerine ham kod yazılır.
- K5 eski bağ eşlemesi `upcase` (`13827`), diğerleri `downcase` → Türkçe ı/i kenar durumu.
- K6 PK Sil onayında adet yok; "Prekast Layout" grubu seçiliyse içindeki tüm PK'lar silinir (`12868`).
- K7 iki SketchUp aynı anda dosyaya yazarsa kilit yok; `.bak` yalnız bir önceki.
- K8 ölçekli örnekte (≠ 1) ortadan kaydırma (`13718`) ebeveyn birimiyle → merkez kayar.

## Doğrulanan (sorun yok)
Undo/işlem: her callback tek normal işlem, hata yolunda abort; apply_rec! / decks_regen! / mst_deck_regenerate! (5968-6005) işlem açmaz; mst_pc_after_rebuild! hatasını içte yakalar; transparent mst_deck_after_edit K3 yollarından çağrılmaz; Dışa Ver işlem dışı, İçe Al tek işlem. Kimlik: element_uid hiçbir yolda yazılmaz; pk_rev / rev_log yalnız eklenir (`13868`). Component kendi boyuyla yeni tanım (`13699`); aynalıda kaydırma yerel yaxis ile doğru. Arayüz ES5 (Chromium 64); callback/yanıt adları eşleşir; mstPkTypePlan geç yanıtı yok sayar. Regresyon: PD/PDÖ/PV satırlarında (4610-4618) K3 yok; TOP/POCKET/MANUAL elev_attrs aynı; "PD Kotlarını BK ile Güncelle" SUPPORT'u atlar. Metraj: P4 değiştirir; CHANGELOG/07 kaydı yok (P6'da yazılacak).

**Soru:** form PK'sında `precast_type_id` boşken kod yerine `precast_id` geçiyor (12484) — kod çakışma denetimi bu fiziksel kimliği tip kodu sayıyor mu?
