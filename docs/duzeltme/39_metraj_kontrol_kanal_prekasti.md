# 39 Metraj kontrolü — kanal prekastı (PK), ADR-0515-K2 P1a–P4 (mst-metraj-kontrol, 09.11.2026; salt okuma, test çalıştırmadı; ana oturum kaydetti)
Kaynak: çalışma ağacı `src` (ajan 909732c ile aynı olduğunu doğrulayamadı; 909732c → 3af76ef arasında yalnız ui.html değişti). "Uyuyor" sonuçları elle hesaptır.

## Elle beklenen hesap ↔ kod
- **Kesit alanı** taban × toplam + Σ açık çıkıntı genişlik × yükseklik: U 0,24 + 2 × 0,12 = 0,48 m²; L/K 0,36; UU 0,525; ofsetli OZEL 0,42 — `channel_section.rb:222` uyuyor. Hacim = alan × boy (`main.rb:4726`, `:12552`, `:13572`) uyuyor.
- **Eski U:** U-eşdeğeri kesit eski formülle (`mst_ch_u_*`); imza/tanım anahtarına `section` yalnız U dışında (`main.rb:6655`, `:12460`). Bayt eşitliği sahte nesne testine dayanır (kp1 4.x–8.x); "eski ifadeler" teste elle kopyalanmış (`kp1_channel_section.rb:198`, `:204-206`), git'ten okunmuyor.
- **Kalıp (L, boy l):** alt 1,2l; dış yan 0,2 + 0,2 + 0,6 + 0,6 = 1,6l; ledge 1,0l (ayrı rol); iç 0; alınlar 2 × 0,36 — `channel_section.rb:249-259` uyuyor. Çıkıntı üstü kalıp yok (eski U ile tutarlı). Çift sayım / eksik yüz bulunmadı.
- **Döşeme (BK 0–1 / 4–5, PK 1–4, döşeme 0,40 m):** brüt 2,40; BK üstü 0,96. L: çıkıntı üstü 0,06 → net 1,02; açıklık 0,30; kesinti 1,08; eski yol 1,32 → 1,02 (fark = açıklık). K: dolu ledge 2,10 → net 3,12; dolgu 0,90; kesinti 0,18. UU açıklık 0,24, OZEL net 1,47 uyuyor. Brüt = (net − dolgu) + kesinti + açıklık (`main.rb:5101`); açıklık hücre başına bir kez (`:4990`).
- **Varsayılanlar:** UU orta açık (karar 15), K/OZEL dolu (karar 14) — `channel_section.rb:23`, `:351` uyuyor.

## Donatı
U dışı PK parametrik planı reddedilir (`mst_pc_rebar.rb:55`); hacim × `rebar_rate('channel_precast')` (`main.rb:3559-3562`, varsayılan 120 kg/m³ `:3527`). Sınıf: hacim × kg/m³ tahmini (3B değil), kaynak '%' işaretli, BIM'den ayrı; bindirme/kanca/filiz/sehpa ayrı değil; çift sayım yok. İlerleme alanı (`progress_items_json`) bu yollarda kullanılmıyor (pursantaj ≠ ilerleme).

## Bulgular
**Engelleyici:** yok.

**Önemli**
1. Dolu ledge betonunun BK üstü altına inen kısmı BK'da cep olup olmadığına bakılmadan eklenir (`main.rb:4974`, `:4985`, `:4992`). PK'nın BK üzerine taşan oturma bölgesinde cep yoksa (ör. elle kot) döşeme betonu BK betonuyla çakışır → çift sayım. Testte PK BK'ya taşmıyor (`kp4_pk_deck.rb:163-164`). Cep varsa BK hacminden cebin düşüldüğü doğrulanmadı.
2. Ledge dolgusu net döşeme betonuna girer; döşeme donatısı oranla ise donatı da dolgu × oran artar (`main.rb:3562`). Dolgunun döşeme pozu / donatı oranıyla metrajlanmasının dayanağı: **belge gerekli**.
3. Golden fixture PK ve döşeme değerlerini sabit öznitelik olarak yazar (`tools/golden/fixture.rb:101-124`): golden yalnız okuma/toplama/BOQ eşleşmesini kanıtlar; PK hacim/kalıp formülü, döşeme planı ve yeni anahtarları kanıtlamaz. Eski U döşemesinin aynılığı yalnız kp4 2.x'e (dc61429 git karşılaştırması, sahte nesne) dayanır.

**Küçük**
- Raporda U dışı PK "iç 0,00 × 0,00" görünür; gruplama bu sıfırlarla (`main.rb:3937`, `:4317-4318`). Toplamlar doğru.
- Donatı kaynak etiketi "% 120" (`main.rb:3572`); değer kg/m³.
- `ledge_fill_volume` en dış çıkıntı şeridinde BK üstü altındaki dolguyu da içerir (`main.rb:4974`); ad kapsamından dar.
- Ledge kalıbı ayrı anahtar değil; yalnız `formwork_area_m2` içinde (`main.rb:4727`).

**Bilgi**
- BOQ: döşeme ve PK yalnız `concrete_volume_m3` / `formwork_area_m2` ile okunur (`quantity_service.rb:65`, `main.rb:3684-3692`); `ledge_fill_volume_m3`, `precast_cut_volume_m3`, `channel_opening_volume_m3` kayıt amaçlı, BOQ'ya girmez; BOQ net değeri alır.
- Eski döşeme yolu `create_deck_slab_legacy_v034` (`main.rb:6129`) U dışı PK'da açıklık üretmez; çağrılıp çağrılmadığı doğrulanmadı.
- U iken donatılı PK U dışına çevrilince eski `rebar_mode` taşınıp taşınmadığı doğrulanmadı.

## Açık sorular / gerekli belgeler
Ledge dolgusunun döşeme pozu, beton sınıfı, donatı oranı dayanağı; PK 120 kg/m³ dayanağı; BK cep hacminin BK betonundan düşülüp düşülmediği. SketchUp içi kabul yapılmadı.
