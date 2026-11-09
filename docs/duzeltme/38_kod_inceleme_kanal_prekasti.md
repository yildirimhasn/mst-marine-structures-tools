# 38 Kod incelemesi — kanal prekastı (PK), ADR-0515-K2 90eb4ce..3af76ef (mst-kod-inceleme, 09.11.2026; salt okuma, komut çalıştırmadı; ana oturum kaydetti)
Yöntem: git diff görülemedi; değişen yerler `ADR-0515-K2`/`P1–P4` işaretleri ve ADR 37 satır listesiyle bulundu (işaretsiz fark kaçmış olabilir). Okunmayan: paint_channel_precast_formwork ayrıntısı, mst_precast_build_geometry!, boq_pro.rb, model_health.rb. Satırlar main.rb, aksi belirtilmedikçe. Sonuç: 1 engelleyici, 1 önemli, 4 küçük, 3 bilgi. Test kanıtı yok.

## Engelleyici
**E1** `structure_copy.rb:21` ↔ `main.rb:13393-13395`: `MST_SC_UID_KEYS` içinde `seat_bk_left_uid` / `seat_bk_right_uid` yok; Yapıyı Kopyala bunları aynen kopyalar, `mst_pk_reseat_plan` BK'yı önce UID ile arar. Senaryo: POCKET PK'lı yapı kopyalanır → kaynak BK cebi değişince kopya PK da kaynak cep kotuna taşınır (dz yanlış); kopya BK düzenlenince kopya PK oturtulmaz. Öneri: iki anahtar `MST_SC_UID_KEYS`'e (yeniden eşleme ve denetim :303, :548). Mimar onayı. (Ana oturum doğruladı: liste satır 21'de bu anahtarlar yok.)

## Önemli
**Ö1** `:4589`: POCKET'te `y` `lb.bounds`tan (BK üst kabının yerel uzayı), `mst_pk_seat_find` dünya uzayındaki cep kutularıyla (`mst_bk_pockets`) karşılaştırır. BK'lar ötelenmiş grup / tek örnekli bileşen içindeyse "PK altında kanal cebi yok" → yerleşim geri alınır; öteleme cep aralığına denk gelirse yanlış cep. Öneri: `y0..y1` `mst_world_tr(lb)` ile dünyaya çevrilsin ya da sınır olarak belgelensin.

## Küçük
- **K1** `:13528`: U dışı tipte KN önizlemesi "iç 0,000 × 0,000 m" — kesit özeti gösterilmeli.
- **K2** `channel_section.rb:150`: bozuk tip kaydında ofset NaN → `sort_by` ArgumentError; `mst_pk_geom` önce çağrıldığından `:13110` rescue'ya ulaşmaz → katalog tümden "okunamadı", `mst_kn_place` hata. Arayüz normalleştirdiği için olasılık düşük.
- **K3** `:4615`, `:4713`: `channel_fw_ledge` / `fw_ledge` arayüzden gönderilmiyor; BASE_LEDGE kalıbı hep açık, kapatılamaz (karar 4 "varsayılan kalıplı" karşılanıyor, seçim yok).
- **K4** `:5104`, `:8478`: kopyalanan döşemenin `deck_plan_json.channels` kaynak PK UID'lerini taşır → kopya PK silinince uyarı yok, kaynak silinince kopyada yanlış uyarı.

## Bilgi
- **B1** `controlled_editor.rb:221` etkisiz (destekli PK geometri değişikliği :134'te reddediliyor; desteksizde pids boş). Zararsız.
- **B2** `mst_pk_reseat_after_edit` (:13421) her BK düzenlemesinde POCKET PK olmasa da tüm modeli tarar; uyarı kutusu `quiet=true` iken de gösterilir.
- **B3** yeniden oturtma döngüsü (:13429-13434) yarıda istisnada yapılan taşımaları commit eder — transparent kurala uygun.

## Denetlenen ve sorun bulunmayan
- İşlem: `mst_pk_reseat_after_edit` (:13427), `mst_deck_after_edit` (:5990) transparent, abort yok, hata yolunda commit; `commit_with_dependencies` tek commit; iç içe yok. BK zinciri: BK normal → yeniden oturtma (transparent) → isteğe bağlı onaylı `mst_kn_place` (yeni normal) → döşeme (transparent): KN onayı yoksa 1, varsa 2 Geri Al (ikincisi öncekiyle aynı). `sync_precast_to_head_beams` commit (:4672) sonra transparent döşeme (:4675); hata yolunda abort, döşemeye geçmez. `create_flat_precast` toplu kipte işlem açmaz, POCKET hatası raise ile çağıranın abort yoluna. `create_channel_precast` tek işlem.
- Kayıtlı veri: `section` yalnız U dışında (`:12697`, `:13564`, imza `:6655`, ölçü anahtarı `:12460`); kot anahtarları yalnız verildiğinde (`:13296`), TOP'ta yok; `kn_from_pocket` korunur; UID önce, PID ikinci yol.
- Dönüşüm: `mst_deck_pk_strips!` (:5193) `mst_world_tr × transformation`; aynalama minmax, dönüş ret + uyarı.
- Kapsam dışı farklar gerekli: POCKET/MANUAL atlama (:4654), `l==r` dalı (:4663, karar 10), `mst_audit_v0515` ek çağrı (:8561, karar 7), 5 test dosyasındaki `A1.load_opt` satırı.
- HtmlDialog ↔ Ruby: callback adları ve alanlar eşleşiyor (`:11093-11097` ↔ ui.html `:2299`, `:2313`, `:2413`, `:2434`, `:1513`); null yolları Türkçe; yeni JS sözdizimi yok (Chromium 64).
- Hata yolları: tek BK / BK yok, cep yok, geçersiz kesit, bozuk JSON, sıfır boy ele alınıyor.
