# 11 mst-metraj-kontrol 2. tur (salt okuma; elle izlendi; katsayılar için belge gerekli)

## Bağımsız örnekler (hepsinde kod = beklenen)
- BK hacmi: L=10, h=1,0, b=1,2, başta diş (1,5 / eğim 0,3 / derinlik 0,5), sonda cep (0,2 / 0,6 / 0,3) → kesit 10,495 m², hacim 12,594 m³ (main.rb:1429,1798 recess_profile_points 396-476).
- BK net beton: 3×Ø1016 gömülme 0,5 (1,2161) + menfez 0,18 → 11,198 m³ (2513, 2527, mst_v50_beams:88).
- BK kalıp: brüt 37,050; kazık açıklığı −2,432, menfez −0,30 → net 34,318 m² (classify_box_faces 365-394, 2460). Cep duvarı uç yüz sayılıyor (belge gerekli).
- PD: 4,30×1,2×0,30 = 1,548 m³ (4295,4311). PK kanal: 0,33 m²×4,30 = 1,419 m³, iç kalıp 6,88 m² (4319). PV: 2,61 m³ (4314).
- Döşeme+prekast: brüt 16,0 = döşeme 9,55 + prekast 6,45; hücre yöntemi (4634,4645); precast_cut_volume (4757) yalnız rapor → çift düşüm/çift sayım yok.
- Kaplama: 100 m², TEK eğim %1, en ince 0,05, genişlik 10 → 10 m³; SIRT 7,5 m³ (mst_v50_misc:36-38; 3484-3485).
- Dolgu AEA: A1=40, A2=60, L=20 → 1000 m³; geçiş istasyonu x=8 → 1040; ×1,8 → 1800 t (Alt-1 main.rb:9182; Alt-2 rockfill_reference_cubage:42; canlı geometry_engine:188).
- BOQ dağılımı: HB_DECK_CONCRETE = BK net + döşeme (tretuvar ve baba dahil, sınıf süzgeci yok); DS2 tretuvarı döşeme içinde, çift sayılmaz; kaplama alanı tretuvar hücrelerini dışlar (4746).
- BK diş/konsol: ayrı işlev yok; diş (start/end_tooth_*), cep (start/end_seat_*) ve taban bölgeleri (bottom_zones_json, mst_v50_beams:53-60) tek X-Z profilinde; hacimleri profil alanıyla metraja girer. Çok akslı BK (1489-1496) düz kutu.

## Yeni doğrulanmış hatalar (statik)
- MST-K50: main.rb:2503-2510 kazık gömülmesi ana gövde tabanından (bottom_elevation_m) ölçülür, diş/bölge derinliği yok sayılır → kazık dişin altındaysa düşüm eksik (örnek 0,162 yerine beklenen 0,567 m³), BK betonu fazla. Ana oturum satırları okuyup teyit etti.
- MST-K51: main.rb:2193-2209, 2225-2228, 2240-2245 kalıp yüz anahtarı yalnız tür+normal; ana taban, diş tabanı ve bölge tabanları aynı BOTTOM, dış uç yüz ile cep duvarı aynı END_FACE → BK revizyonunda tek yüzün kalıp seçimi aynı anahtardaki tüm yüzlere yayılır.
- 08-R6 (koşullu hata): main.rb:2460,1445,1815 alt yüz kalıp dışındayken kazık açıklığı yine düşülür.
- MST-K52: main.rb:3473-3474 ile 4098 — topping_enabled olmayan eski döşemede BOQ kaplamayı 0,10 m ile ekler, detaylı rapor eklemez.
- MST-K53: main.rb:5530,5578 → 5083-5087; mst_v50_misc:59-62; 6008-6011 — döşeme yenilenince oluşturma anındaki deck_input_json okunur; kaplama eğimi/sonradan eklenen kaplama geri döner, metraj sessizce değişir.
- MST-K55: main.rb:9180-9182, boq_mapping.rb:16 — Alt-1'de kütüphanede olmayan malzeme kodu → yoğunluk 0, tonaj 0, uyarı yok (Alt-2 ve canlı geometri hata verir). Ana oturum teyit etti.

## Olası riskler
MST-K54 PV diş < oturma kontrolü yok (4313) → BK ile kesişen hacim çift sayılır. MST-K56 Alt-1 aynı istasyonda iki kesit sort_by kararsız (9168). Alt-1 boş malzeme alanını 0 sayar, Alt-2 boş bırakır (9181; reference_cubage:42,54). Menfez–kazık gömülmesi/cep kesişiminde çift düşüm (mst_v50_beams:86-88). Uçta cep (uzaklık 0) kendi üstüne dönen profil (407-433). Taban bölgesi uç dişlere taşarsa geometriye girmez ama listelenir (mst_v50_beams:46-56). Sehpa tüm BK'lardan düşülüyor (mst_v50_misc:91) — toplam doğru.

## İkinci teyit
- K35 Teyit, kapsam daha geniş: main.rb:3585 `"#{code}-%02d" idx+1` (ana oturum okudu); gruplar çap/et sıralı (3548); birim fiyat da aynı koddan okunur (3593) → fiyat da kayar; onaylı miktar trace_pids ile doğru kalır.
- K34 Teyit, kapsam daha geniş: mst_element_rebar (9384) kaplama ve ankrajı içermez; steel_pipe_pile için 0 döner (3385-3386) → kazık kafes donatısı hakedişe eleman bazında girmez.
- K38 Teyit: icmal 1600 / cetvel L 1800, J 1200 (ödenen 1000); belge gerekli.

## Eksik
Prekast derz harcı hiçbir yerde sayılmıyor (4693-4694; belge). Eğik kazık açıklığı daire (1433). Golden-master yok.
Öncelik önerisi: Yüksek K35, K34, K53, K50; Orta K51, R6, K52, K55, K38; Düşük K54, K56, menfez kesişimi.
