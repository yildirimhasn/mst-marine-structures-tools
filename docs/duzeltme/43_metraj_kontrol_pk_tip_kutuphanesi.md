# 43 Metraj kontrolü — PK tip kütüphanesi, ADR-0515-K3 P1–P5 + karar 9 (mst-metraj-kontrol, 10.11.2026; salt okuma, test/git çalıştırmadı; ana oturum kaydetti)
Satırlar çalışma ağacı `src/marine_structures_tools` (ajan daf301e ile aynılığını doğrulayamadı; ana oturum: kayıt anında ağaç = daf301e). Elle hesaplar formülle; bağımsız dayanak yalnız 40a/41 kararları (kesit, oran, kalıp kuralı için belge yok).

## Elle beklenen hesap ↔ kod
1. **Kayıttaki fw/oturma** (`main.rb:4624-4636`, `:13342`, `:13350`): L 1,20 × 0,20 + 0,20 × 0,60 = 0,36 m²; açıklık 3,00, oturma 0,15 → boy 3,30, beton 1,188 m³; 1,30 → 0,38 m² → 1,254 m³; oturma 0,25 → boy 3,50, beton 1,260, başlangıç −0,10 — kq4 1.0/1.3/1.8 uyuşuyor. Kalıp (yan + iç + ledge açık): 1,20 için 3,30 × 1,6 + 3,30 × 1,0 = 8,58 m²; 1,30 için 5,28 + 3,63 = **8,91 m²** — test 1.4/2.2 kodun kendi işleviyle karşılaştırır (döngüsel), bu değeri doğrulamaz. Eski kayıtta fw/oturma yoksa form değeri; sonuç değişmez (statik).
2. **Tip güncelleme** (`:13656-13725`): hacim formülden; kalıp Group'ta rol formülünden, Component'te işaretli yüzlerden; donatı (hacim × kg/m³) raporda o anki hacimden (`:3562`); pursantaj ↔ ilerleme karışmıyor. Kapsam dışına dokunulmuyor (kq4 4.2); çift sayım yok. QTO gruplama: kod + beton + ön ayar + `geom_sig` (`:4318`) → aynı kodlu farklı geometriler ayrı satır, revizyon satırda görünmez; BOQ beton sınıfına göre toplar. Revizyonların ayrı poz olup olmayacağı: **belge gerekli**.
3. **SUPPORT kotu:** döşeme açıklığı geometriden (`:5198`, `:5233`). Varsayım BK üstü 3,00, cep tabanı 2,20, L yüksekliği 0,80, döşeme 3,00–3,40: POCKET açıklık yüksekliği 0,40, duvar üstünde 0,40 döşeme; SUPPORT taban üstü 3,20 → açıklık 0,20, duvar üstü 3,80 döşemeyi deler, duvar üstünde döşeme 0.
4. **PK Sil** (kp4 fikstürü): açıklık 0,40 × 1,00 × 3,00 = 1,20 m³, kesinti 0,20 × 0,30 × 3,00 = 0,18 m³; silinen PK yerinde döşeme 0,06 → 1,44 m³, **net artış 1,38 m³** (şerit "PD yok" sayılıp tam kalınlık varsayımı, `:4998`).
5. **Ortadan büyüme** (`:13716-13719`): döşeme aynı işlemde geometriden yeniden kurulur → yeni merkezle tutarlı. Derz değişiminin etkisi: Önemli 3.
6. **P5 içe alma:** kayıt aynen (`pk_library_file.rb:231`); hacim/kalıp kesitten → kesit + oturma aynıysa modelden bağımsız. Modele bağlı kalanlar: ledge form kutusu (`:4628`), `rebar_rate('channel_precast')`, açıklık.

## Bulgular
**Engelleyici:** yok.
**Önemli**
1. Kayıt oturması PD oturmasından farklıysa döşeme boşluğu eksik sayılabilir: prekast cebi tüm komşu parçalar için tek dikdörtgen (`:4955`, `:4994`); PD şeridi uçlarında BK üstünde prekast olmayan yerde z0..z0+hs da kesilir. Örnek Δ 0,10, PD genişliği 1,0, hs 0,30 → PD başına ≈ 0,06 m³ eksik döşeme. Tip güncellemesinde oturma değişince de aynı. Sahte nesne testiyle doğrulanmalı.
2. `rebar_mode` bim_detail / drawing_detail / auto_detail olan PK güncellenince `rebar_t` yeniden hesaplanmıyor; eski tonaj kalıyor (`:3553`, `:13707-13723`; yalnız `pc_rebar_json` yeniden çiziliyor).
3. Kesit küçülünce derz `MST_DECK_JOINT_MAX` 0,05'i (`:4864`) aşarsa şerit "PD yok" sayılır: tam kalınlık döşeme + alt kalıp. Komşu denetimi yalnız daralmayı raporlar (`:13556`, `:13573`).
4. PK Sil testi (kq4 5.3) yalnız açıklık kimliklerine bakar; net beton artışını doğrulamaz.
**Küçük**
- SUPPORT ile PK üstü döşeme üstünü aşabilir; uyarı yalnız PD için (`:4945`).
- Eski kaydı "Tüm örnekler" ile güncellerken istekte fw yoksa varsayılan '00101' (`:13803`); arayüz her zaman fw gönderir.
**Bilgi:** golden fikstürü PK için sabit değer yazar (`tools/golden/fixture.rb:112`); P1+ kayıt, düzenleme, SUPPORT, PK Sil, döşeme yeniden kurulumu golden'da yok — golden yalnız okuma/toplamayı kanıtlar.

## SketchUp kabulünde zorunlu karşılaştırmalar (model kopyası, önce ↔ sonra CSV)
1,20 → 1,30: PK beton 1,188 → 1,254 m³, kalıp 8,58 → 8,91 m²; oturma 0,25 → 3,50 m / 1,260 m³ ve PD şeridi döşeme betonu; PK Sil sonrası döşeme +1,38 m³, diğer açıklıklar aynı; POCKET ↔ SUPPORT açıklık hacmi; kapsam dışı yapı toplamı değişmez; içe alınan tip iki modelde aynı hacim/kalıp.

## Açık sorular / gerekli belgeler
Revizyonların ayrı satır/poz olup olmayacağı; PK kg/m³ oranının dayanağı; oturma farkı olan yerleşimde döşeme cebi kuralının dayanağı.
