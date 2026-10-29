# 08 mst-metraj-kontrol raporu (salt okuma; örnekler elle izlendi; formül/katsayı doğruluğu için belge gerekli)

## 12 kontrol özeti
1 İç içe: kazık/iç beton sorun yok (main.rb:2093-2111; qto_workspace.rb:146-166 örnek başına). Çift sayım riski: MST dışı sarmalayıcı Component N kopya → BOQ ×N, iz/hakediş listeleri .uniq ile tek (main.rb:3684, boq_pro.rb:706).
2 Ana + alt bileşen: tek kaynak (çember 8506-8519, tapa 8497, iç beton qto_workspace:79, menfez mst_v50_beams:77-79/459-461, DS2 tretuvar 5073-5079, sehpa mst_v50_misc:87-97).
3 Silinen/eski kayıt: sorun yok (boq_pro.rb:624-631, 506-516) — ama H3, R2.
4 Boşluk: net (2524-2528, 2457-2461). Risk: menfez ile kazık gömülmesi çakışırsa çift düşüm; eğik kazık açıklığı daire alınıyor (1433).
5 Birleşimler: sorun yok (VK açıklık mst_v50_beams:320, döşeme prekast kesimi 4757, kademeli döküm v1=net−v2 253-255).
6 Prekast/yerinde: H1. 7 Kazık formülleri tutarlı; E1, H6. 8 Donatı: kazık başına tek kaynak; H4, R4. 9 Dolgu: tek sağlayıcı (rockfill_sources:23, boq_mapping:15) Alt-1/Alt-2 aynı anda BOQ'ya geçmez; jet grout nominal (jet_grout:114). 10 Toplamlar aynı işlevden; H5. 11 Hakediş H2,H3,H7,R3. 12 Ölçek K2.

## Bağımsız örnek (Ø1016×16, L=30, ρ=7850 — belge gerekli)
Boru 11 837.5 kg = kod (482) · iç beton h=12: 9.126 m³ (1:6 eğimde 9.251) = kod · üst çember w250: 101.80 kg = QTO (8511), önizleme 100.22 · alt çember w300: 114.59 = QTO (8518), önizleme 116.48 · tapa 68.75 kg = kod (8504) ama BOQ satırı yok (E1) · PE 10 m: 31.92 m² = kod · ek adedi 2 (12 m kuralı belge) · manipülasyon 12.054 t (tapa hariç) · çakım 1:6 taban −8 uç −30: 22.303 m = kod (3462) · BK gömülme 0.5 m: 0.405 m³ = kod (2513). Foraj kullanıcı girdisi (8526).
Hakediş ağırlık örneği (10/90, %100/%0): prog2_quantities 10 (doğru); yedek yol (467) 50; seçim gösterimi (725) %50 (yalnız gösterim).

## Doğrulanmış hatalar
- H1 Kritik (eksik metraj): main.rb:3514-3515 PRECAST_C35_45 ve CAST_C35_45_OTHER yalnız C35/45 sınıfını alır; prekast sınıfı boşsa 4305 varsayılan C30/37 → C35/45 dışı prekast ve bordür betonu hiçbir beton pozuna girmez, yalnız montajda (PRECAST_INSTALL) görünür. Örnek 10 m³ C30/37 → beton BOQ 0, montaj 10. Ana oturum satırları okuyup teyit etti; başka poz anahtarı yok (grep).
- H2 Yüksek: boq_pro.rb:465 min(Σ,qty); REBAR satırı kaplama donatısı + aksesuar ankrajını içerir (main.rb:3384,3431; mst_v50_misc:98-101), eleman miktarları içermez → %100 onayda bile kaplama/ankraj donatısı hakedişe girmez (15.0+0.2 t → 15.0 t).
- H3 Kritik (hakediş): main.rb:3585 kazık "ayrı poz" anahtarı code-01.. sıra numarası; boq_pro.rb:383,495,644 → kesit grubu silinince/eklenince previous_<anahtar> başka kesite kayar.
- H4 Kritik (fazla metraj): qto_workspace.rb:80-82 children kontrolü infill_enabled=0'dan önce; pile_manufacturing.rb:203 Component kazıkta paylaşılan çocuk silinmez → "iç beton YOK" yapılan Component kazıkta hacim ve donatı sayılmaya devam eder; arayüz VAR gösterir. Ana oturum teyit etti (qto_workspace.rb:70-74 definition.entities'e iner).
- H5 Orta (gösterim): main.rb:3871,3888-3892 pano döşeme satırına kaplama eklenir, DİĞER −kaplama.
- H6 Düşük: pile_manufacturing.rb:226-241 önizleme çember/tapa formülü QTO'dan farklı, adet 1.
- H7 Yüksek: boq_pro.rb:585 icmal A=önceki A+bu dönem×yeni fiyat; 990-993 cetvel kümülatif=toplam×yeni fiyat → fiyat/kur değişince 1600 vs 1800. Sözleşme gerekli.
- K1 Kritik: 30° döndürülmüş, BK 1.0×10 m, gerçek açıklık 10 m → hesaplanan 3.66 m, prekast 3.96 m (olması gereken 10.30 m), hacimde −%61.6, uyarı yok; geometri X'e paralel çizilir (main.rb:4281,4295,4309).
- K2 Yüksek: ölçek: BK 15 m³ ×1.2 → geometri 18, metraj 15 (main.rb:2188 ve attribute okumaları).

## Donatı sınıfları
BK/döşeme/prekast/kronman 3B veya hacim×kg/m³ tek dal (3379-3388); BK paftadan tablo (mst_dwg_rebar:452, mst_dx_rebar:91) — E2 yerleştirilemeyen pozlar (mst_dr_auto:583) ayrı gösterilmiyor; kazık kafesi 3B veya iç beton×250 (12006-12008, 12114, 12177); kaplama hacim×kg/m³ (3431); sehpa/ankraj ek satır — R4 paftada ankraj varsa çift sayım (belge); bordür QTO'da var BOQ'da hariç (quantity_service:8/105); fore kazık rebar_t (3374-3377). Birim ağırlık d²/162 (%0.12 fazla; belge). Pursantaj ile ilerleme karışmıyor. R5: "Çelik / Tonaj" sütunu boru çeliği + donatı + dolgu tonajını (3901) birleştiriyor (pano, Excel 8558/8593); BOQ etkilenmez.

## Olası riskler
R1 main.rb:649,3464 kot yok + çakım boş → driving_length_m=0, çakım metrajı 0. R2 Ctrl+Move progress_items_json taşınırsa kopya onaylı sayılır. R3 boq_pro.rb:467 adet ortalaması. R6 main.rb:1433,1445 alt kalıp kapalıyken kazık açıklığı düşülür. R7 rockfill_boq_source.rb:80/13. Eski v034 tretuvar köşe bindirmesi 4·w²·h (4471-4474; yol çağrılmıyor, eski modeller). 03-H5 metrajı değiştirir.

## Eksik
E1 tapa BOQ'ya geçmiyor; E2 yerleştirilemeyen pozlar raporlanmıyor; dönüşüm/attribute uyuşmazlığı denetimi yok; golden-master yok.
Açık belgeler: boru/çember/tapa/PE poz tarifleri ve ρ; 12 m ek kuralı; kg/m³ değerleri; bordür/kaplama donatı kapsamı; beton sınıfı/poz eşlemesi; fiyat farkı/kur; foraj kotları.
