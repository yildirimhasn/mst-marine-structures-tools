# 12 mst-kod-inceleme 2. tur (salt okuma; test çalıştırılmadı)
İncelenmeyen: rockfill_cut_mesh/void_loft/transitions/refinement/report gövdeleri (yalnız işlem/rescue taraması); mst_ar_plan/mst_dr_plan/mst_dra_* ayrıştırma gövdeleri, mst_pile_rebar_calc, HeadBeamEditor.

## Sorun bulunmadı
own_op=false işlevlerin tüm çağıranları işlem açıyor (dwg 530/559, dr_auto 630, auto_rebar 638, rebar_tools 211, pc 263/282, dx 124/144, main 2810/3245/3260); iç içe start_operation yok. Çok kopyalı Component BK koruması var (dwg:332, auto_rebar:630, dr_auto:595). Çift 3B donatı yolu yok (dwg:376-379; main:2789, 1724; controlled_editor:63). Kazık kafesi Component anahtarında donatı var (main:788,876). Rockfill'de observer/timer yok. Katı/manifold denetimi var (loft_model:26-29, extensions:87-102, special_solids:43-71,104). TIN dejenere/eşdoğrusal gürültülü hata veriyor (geometry_engine:164, tin:19,41,46). Birim .to_m doğru.

## Yeni doğrulanmış hatalar (statik)
- MST-K57 Yüksek: mst_dwg_rebar.rb:552-556 "Çizimden/Otomatik Donatıyı Sil" (tb_del) süzgeci yalnız rebar_mode ∈ [drawing_detail, auto_detail]; seçim boşsa tüm model. Paftadan metraj (mst_dx_rebar:91) ve prekast donatısı (mst_pc_rebar:223) da bu modları yazıyor → paftadan metrajın rebar_pafta_json'u kalır; Component prekastta set paylaşılan definition'dan silinir (tüm kopyalarda 3B gider), pc_rebar_attrs_json kalır, metraj çizilmiş tonajı göstermeye devam eder (main:3379-3383), boy değişince donatı geri çizilir (main:11222). Ana oturum süzgeç satırlarını teyit etti.
- MST-K58 Yüksek: main.rb:11214,11222 → 11407-11409; mst_pc_rebar.rb:222,227 — donatılı Component prekastın boyu değişince parça o boydaki paylaşılan definition'a geçer, mst_pc_draw! bu definition'a çizer ve öznitelikleri tüm örneklere kopyalar → seçilmemiş aynı boylu prekastlara donatı ve tonaj sızar.
- MST-K59 Yüksek (metrajı değiştirir): main.rb:12026-12034, 12122-12127 (okuma 12007) — mst_pile_rebar_calc hata verirse pile_cage_rebar_kg=0, pile_rebar_error hiçbir yerde okunmuyor (ana oturum grep ile teyit) → kazık donatı metrajı sessizce 0, pursantaja dönmez.
- MST-K60 Orta: mst_pc_rebar.rb:244-249 (çağıranlar main:8335,8352,11222) prekast yeniden kurulurken donatı çizimi hata verirse 3B yok, rebar_mode ve tonaj eski boydan kalır; pc_rebar_error okunmuyor.
- MST-K61 Orta: mst_rebar_tools.rb:543,547-548 çakışma kontrolü yalnız e.transformation; collect_elements iç içe gruplara iniyor (main:2101) → üst grup içindeki elemanlarda yanlış/kaçan çakışma.
- MST-K62 Düşük: rockfill_live.rb:239-245, 312-317; mst_pc_rebar.rb:281; mst_rebar_tools.rb:604 — komut başına 2 Ctrl+Z / işlem dışı yazma.
- MST-K63 Düşük: mst_dwg_rebar.rb:389-395, main.rb:2844-2845 — önceki BIM donatısı geri yüklenirken hata (Component BK'da hb.entities NoMethodError) → rebar_prev_json önceden silindiği için BIM donatısı kaybolur, pursantaja döner (rescue nil).

## Olası riskler
DXF "L=250" birimsiz metre okunuyor (mst_dx_rebar.rb:23-27) → cm paftada ×100, makullük denetimi yok. mst_dr_auto.rb:195-199 ftol=0.6 çizim biriminde; inç yok; INSUNITS yalnız kazık modülünde, 0 ise m (mst_dxf.rb:183). Performans: rockfill_tin.rb:33-44 (≤5000 nokta, O(n·T)), 55-72; geometry_engine:166-171; boq_mapping.rb:7 her BOQ'da canlı geometri/rf_special_qto O(n²) (special_solids:75); mst_rebar_tools.rb:263-264; mst_dwg_rebar.rb:353-364. TIN süper üçgen kenar boşluğu (gürültülü hata). Yanıltıcı ileti main:1724-1725, 2789-2790, 3241. Donatı revizyon geçmişi son 10 kayıt (mst_rebar_tools.rb:484). Kavisli aksta AEA düzeltmesi yok (yöntem; belge).

## İkinci teyit
K26 Teyit. K28 Teyit (8276 açık işlem yokken abort SU2020 davranışı doğrulanamadı). K14 Kısmen: yazmalar kodda var, ama çağrılar skp:+encodeURIComponent ile geliyor ve Ruby URL çözmüyor → JSON.parse hata, yazma olmaz; fiilen tek yazma rockfill_load_project (9147), o da skp: çalışırsa. K13 Teyit (kod), olasılık düşük; mst_schedule.rb:302 rescue var ama abort yok.

## CSS
ui.html:325 inset/min(): işlevsel etki yok — #pileOverrideBackdrop'a `open` sınıfı hiçbir yerde eklenmiyor (ana oturum grep ile teyit: yalnız 1588'de remove); openPileOverrideDialog ayrı Ruby penceresi açıyor. Flex/grid gap: teyit, yalnız görünüm. SU2020'nin Chromium 64 kullandığı bağımsız doğrulanmadı.
