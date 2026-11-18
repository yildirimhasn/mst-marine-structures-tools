Marine Structures Tools 0.51.13 Kesit Onizleme TEST — ÖN1 — 12.11.2026

Paket: MST_v0.51.13_Kesit_Onizleme_TEST.rbz (VERSION 0.51.13, MST_BUILD v0.51.13 Kesit Onizleme TEST). Temel: MST_v0.51.12_BK_Sifir_Ofset_TEST.rbz.
Yenilik: Kazık, Fore Kazık, Jet Grout, Başlık Kirişi, Prekast (PD / PDÖ / PV / PK), Döşeme, Kronman ve Dolgu (Alt-02 parametrik)
sayfalarında Kanal Prekastı'ndaki gibi Kesit / Boyuna / 3B önizleme (mst_preview.js; model değişmez). Ayrıntı: RELEASE_UI9.txt "ÖN1".
Runner 1.2.12 bu paketi bekler. SketchUp 2020 içinde denenmedi.

=====================================================================
Aşağıdaki bölüm 0.51.5 TB1 FIX2 paketinin notudur (kayıt amaçlı korunmuştur).
=====================================================================
Marine Structures Tools 0.51.5 TB1 FIX2 — MST_FINAL_INTEGRATED — 10.11.2026

Paket: MST_FINAL_INTEGRATED.rbz (VERSION 0.51.5, MST_BUILD v0.51.5 TB1 FIX2).
Temel: MST_v0.51.5_TB1_FIX1_TEST.rbz (TESLIM_11, kaynak bf945e7, 204 dosya). Bu paket tam kaynak kod denetiminde
(10.11.2026) doğrulanan 10 düzeltmeyi (FIX-01 … FIX-10) içerir; ayrıntı RELEASE_UI9.txt sonundaki "0.51.5 TB1 FIX2"
kaydında ve teslim klasöründeki MST_REVIZYON_DEGISIKLIKLERI.md / MST_TEST_VE_ENTEGRASYON_RAPORU.md dosyalarındadır.

KANIT DURUMU (FIX2)
- Statik: ruby -c (69 Ruby dosyası), node --check (13 JS), JSON (7) — 0 hata; Ripper tabanlı çift tanım taraması
  (17 → 16; kalan 16 bilinçli alias_method genişletmesi).
- Sahte SketchUp API'si ile tüm eklenti yüklendi (1428 metod, 71 menü öğesi, 4 araç çubuğu); 15 birim / entegrasyon
  testi, 0 kalan (aynı testler FIX1 paketinde 8 kalan). TEST-04 (Ø1016, t 15→14, L 30 m, H/V 0,50) Hedef Küme yolu
  sahte modelde doğrulandı.
- Golden-master BOQ/QTO karşılaştırması: yalnız Group kazıklı modelde Metraj / Keşif değerleri FIX1 ile aynı; Component
  kazıklı ve eğik kazıklı BK'lı modellerde fark BEKLENİR (RELEASE notunda listelenir).
- SketchUp 2020 içinde: DENENMEDİ. Kabul kullanıcı tarafından model kopyası üzerinde yapılacak.

KANIT DURUMU (FIX1, 02.11.2026)
- Statik: Ruby 2.5 dilbilgisi denetimi (66 dosya, 0 hata) ve ruby -c sözdizimi hatasız — Parti C sonrası
  ana oturum çıktısı (02.11.2026); sürüm adı değişikliğinden sonraki son paket için yeniden çalıştırılmalı.
- Sahte nesne testleri (SketchUp dışı, yalnız mantık): A1, A2, B partilerinin 17 testi "0 kaldı".
- Golden-master BOQ/QTO karşılaştırması (0.51.4 ↔ 0.51.5): yapılmadı.
- SketchUp 2020 içinde: denenmedi. Kabul kullanıcı tarafından model kopyası üzerinde yapılacak.

KURULUM (denenmedi)
1. SketchUp 2020 > Window > Extension Manager > Install Extension > MST_v0.51.5_TB1_FIX1_TEST.rbz
2. SketchUp'ı tamamen kapatıp yeniden açın. Ana pencere başlığında "Marine Structures Tools v0.51.5" görünmeli.
3. İlk denemeyi projenizin KOPYASINDA yapın; asıl .skp dosyasını açmayın.

UYARI — TB1 entegrasyon test eklentisi (mst_tb1_integration_runner 1.1.0)
Kurulu test eklentisi 0.51.4 paketini bekler. Bu pakette sürüm adı ve dosya SHA-256 kontrolleri
beklenen şekilde BAŞARISIZ olur; bu sonuç pakette hata olduğunu göstermez. Yöntem adı kontrolleri geçerlidir.

Metrajı değiştiren düzeltmeler vardır: aynı modelin 0.51.4 ve 0.51.5 BOQ/QTO çıktılarını karşılaştırın.

=====================================================================
Aşağıdaki bölüm v0.36.7 paketinin notudur. Yerine geçti: 0.51.5 TB1 FIX1 notu (yukarıda).
Kayıt amaçlı korunmuştur; içindeki sürüm, test sayıları ve kurulum adımları güncel değildir.
=====================================================================

Marine Structures Tools v0.36.7 — Audit / BOQ / QTO birleşmiş sürüm

Temel alınan dosya:
MST_v0365t_Audit_Organization_Fix.rbz
Bu paket, yeni "t" sürümündeki geliştirmeleri önceki QTO çalışma alanı düzenlemeleriyle birleştirir.

KORUNAN YENİ GELİŞTİRMELER
- BOQ kazık imalatlarını TEK POZ / AYRI POZ olarak düzenleme.
- Kesit veya beton sınıfına göre ayrı pozlar, grup fiyatları ve kaynak seçimi.
- Tekli kazık editöründe standart/özel çap seçimi.
- Seçili kazıklarda toplu çap ve et kalınlığı güncelleme.
- Kesit değiştiğinde mevcut iç betonun yeniden üretilmesi.
- Pile Type Library Auto-Sync ve Audit düzeltme bağlantısı.
- Pile Organization Sync ve yeni Audit organizasyon kuralları.
- Kaynak eleman PID tekrarlarının giderilmesi.

UYARLANAN QTO VE ARAYÜZ
- Açılır Sistem > Yapı > Kesit metraj tablosu, arama ve kolon seçimi.
- Filtreye göre miktar kartları, ara toplamlar ve kaynak seçim kapsamı.
- Excel'de aynı hiyerarşi ve proje toplamı.
- Metraj okurken kazık cache verilerine yazılmaması.
- Eğik kazık çakım boyunun kazık doğrultusu boyunca hesaplanması.
- Otomatik (12 m parçalar) / Girilen adet ek hesabı.
- Virgüllü sayı ve 1/6 eğim oranı desteği.
- Temel veri ön kontrolü ve eksik kaynak uyarıları.
- Aktif yapı ve seçili nokta sayısını gösteren oluşturma düğmeleri.
- Tapa adedinin önizleme sırasında sıfırlanmasının giderilmesi.

BİRLEŞİM DÜZELTMELERİ
- Beton sınıfında yeni editörün güncel canlı sınıf alanı korunur. Alan yoksa fiziksel beton grubuna, ardından eski sınıf kaydına başvurulur.
- Eski kazıklarda infill_enabled alanının hiç bulunmaması, mevcut fiziksel betonun "BETON YOK" sayılmasına neden olmaz.
- Fiziksel beton grubu olmayan ve açıkça kapatılmış beton, eski hacim kaydı nedeniyle tekrar metraja girmez.
- Yeni beton oluşturulurken kazıktaki aktiflik ve beton sınıfı alanları da güncellenir.
- Ayrı BOQ pozlarının trace physical_count değeri ilgili gruba göre güncellenir.
- Kazık oluşturma doğrulaması, yeni tekli/toplu editördeki bağımsız taslak alanları denetlemez.
- Eklenti kayıt sürümü ve ana pencere sürümü ortak VERSION = 0.36.7 kaynağından gelir.

DOĞRULAMA
- Taklit SketchUp verileriyle 17 Ruby regresyon testi / 84 kontrol geçti.
- 18 JavaScript sayı, filtre, hiyerarşi ve giriş kapsamı kontrolü geçti.
- 11 Ruby dosyası ve 10 JavaScript bloğu/dosyası sözdizimi kontrolünden geçti.
- Yeni "t" sürümündeki 15 ilgili Ruby bölümünün aynen korunduğu doğrulandı; bunlara Model Audit ve organizasyon/tip senkronizasyonları da dahildir.
- Gerçek XLSX ZIP yazıcısı taklit modelle çalıştırıldı; XML parçaları doğrulandı.
- Birleşmiş arayüz yerel tarayıcıda açıldı; v0.36.7, hiyerarşik metraj ve yeni çap seçici doğrulandı. Gözlenen tarayıcı hata kaydı boştu.
- Paket içeriği dosya sayısı ve SHA-256 ile doğrulandı.

KURULUM VE GERÇEK MODEL KONTROLÜ
SketchUp > Extension Manager > Install Extension üzerinden yeni RBZ'yi yükleyin.
SketchUp'ı tamamen kapatıp yeniden açın; v0.36.7 görünmeli.
İlk kontrolü projenizin kopyasında yapın.

Bu oturumda gerçek SketchUp uygulamasında geometri/Undo/Redo doğrulaması yapılmadı.
Kontrol edin:
1. Aynı sistemde aynı kesitli iki yapı: metraj Seç düğmesi yalnız ilgili yapının kazıklarını seçmeli.
2. Ekran ve Excel Sistem/Yapı/Kesit toplamları uyuşmalı. Excel tüm projeyi aktarır; ekran araması dışa aktarma kapsamını daraltmaz.
3. TEK POZ ve AYRI POZ miktar toplamları aynı olmalı. Kaynaklar yalnız ilgili grubun elemanlarını seçmeli.
4. Toplu çap/et düzenlemede iç beton, çelik ağırlığı ve Type Library güncellenmeli; Pile ID/UID korunmalı.
5. Organizasyon ve tip senkronizasyonlarından sonra Model Audit çalıştırın.
6. Oluşturma, toplu düzenleme ve senkronizasyon Undo/Redo ile kontrol edilmeli.

AYRI POZ fiyatlandırma yöntemi "t" sürümündeki gibi korunmuştur. Kesit gruplarını ekleyip çıkardıktan sonra ayrı poz kodları ve fiyatlarını kontrol edin.
Düzeltilen hesaplar önceki sürümden farklı miktar verebilir; önceki raporla karşılaştırın.


--- Önceki paket notları ---
v0.26.2 - Existing pile drilling editor
Pile page: read selected pile groups or all project piles; set drilling on/off and optionally a positive length per pile.
Off preserves stored lengths. On can preserve each pile length or apply one entered length.
Validation precedes a single undoable operation. Geometry and BIM identity are unchanged. QTO and BOQ refresh after application.
Real SketchUp UI/Undo acceptance remains required.

v0.26.1 - Active BOQ and automatic drilling selection
BOQ displays only positive model quantities. Mobilization retains the existing 1 LS rule.
Drilling source is automatic and overrides old manual drilling mappings without deleting them.
Select unique matching pipe diameter/wall thickness among curated drilling definitions; otherwise use the unique general drilling definition. Mixed sizes use the general definition. Only drilling-enabled piles with positive drilling length inform selection.
Live compatible USD library prices are retained; missing prices remain partial. No appropriate definition produces an explicit missing-position status.
Other source mappings remain manual. Mapping screen retains inactive sources for configuration.

v0.26.0 - Project BOQ mapping
Open Kesif / BOQ > OBF - Model Miktari Eslestir.
Map each of the 18 existing quantity sources to a compatible USD library record.
Model-level JSON stores stable record IDs. Save the SKP to retain mappings.
Library price and tariff remain live; quantities always come from the model.
Missing/deleted/incompatible records are visible and cause partial totals.
One operation per mapping/reset; reset restores the original row and saved default price.
Mapping does not add a duplicate BOQ row or alter geometry, BIM or QTO.
Same library record cannot serve two quantity sources. No unit/currency conversion.
Refresh this window after Undo/Redo or library changes. Export/import the library JSON when moving to another computer.
Source selection is manual: matching units alone do not prove matching work scope.

v0.24.9 - Parametric precast formwork refresh
PD and channel edits recalculate selected formwork areas and repaint counted faces.
Original face selections/materials are retained; wall tops remain excluded.
Uses the existing editor operation, with no nested Undo operation.
Legacy elements without recoverable formwork selections require undo or recreation.
Ruby mock tests do not replace verification in SketchUp.

v0.24.8 - Library-linked BOQ coverage
BOQ now includes PILE_DRILLING (catalogue ÖBF-091, m) and TOPPING_CONCRETE (catalogue ÖBF-072, m3). Quantities use full-precision model takeoff. These two USD prices are read live from the catalogue by stable identity; no new default price is invented. Missing prices yield an explicit partial total. Edit prices in the library; existing 16 BOQ price inputs remain unchanged.

v0.24.7 - Source rate descriptions
Includes 316 distinct extracted texts from 13 Word files, retaining 388 source locations. Source tariff selector supports search, candidate title matches, preview and explicit transfer into the editable rate description. No automatic overwrite of existing descriptions. IGSAŞ PDF is a quantity summary, not a tariff source.

v0.24.6 - Unified USD archive and unit rate descriptions
Use Tek USD Arsivini Olustur / Guncelle to merge the bundled catalogue and 16 current model BOQ items into 327 definitions. Duplicate model snapshots are retained as history. Only mapped items receive current model quantity and USD price. Unknown/foreign prices remain in history without invented FX. Editable rate descriptions persist through save/export/import and merging. Template button creates an explicitly unfinished draft.

v0.24.5 - Catalogue codes use ÖBF-
Generated MST-P catalogue codes migrate on load while retaining record IDs, numeric suffixes, prices and quantities. Older catalogue imports normalize to the same codes.

v0.24.4 - Verified file persistence
Library uses APPDATA/MarineStructuresTools/BOQLibrary/records.json on Windows. Valid legacy preferences remain readable until migrated on save; they are not deleted. Writes use a temporary file, readback verification and rename. previous.json supports undo. Success is reported only after records load back correctly.

v0.24.3 - Unique BOQ catalogue
Curated catalogue imports replace the specified earlier source-row IDs in one backed-up save. Other records survive. Repeated catalogue keys are skipped, including after editing. Source prices are not chosen as catalogue prices.

v0.24.2 - Excel-derived BOQ archive support
JSON schema 2 preserves missing year/quantity/price and source provenance.
Schema 1 remains readable. Missing values display as a dash, not zero.
Additional catalogue units: pkt, saat, komp. Source fields survive edits.
The companion 19-file JSON archive is imported with JSON Ice Aktar.
Direct XLS/XLSX import is not part of the extension.
50 tests / 213 assertions passed, plus JS formatter and ZIP verification.
Real SketchUp import acceptance remains required.

v0.24.1 - First-run nil storage fix
Absent SketchUp preferences initialize an empty library. Existing records are preserved.
34 tests / 138 assertions passed. Excel import is not added in this hotfix.

Marine Structures Tools v0.24.0 - Marine BOQ Library
Open from Kesif / BOQ > Marine BOQ Library or Extensions menu.
Persistent library per SketchUp user/version, shared by models.
Fields: project, year/date, code, item, unit, quantity, unit price, currency,
optional BOQ source and notes. Add/edit/delete/search records, archive the
current model BOQ, and import/export versioned JSON libraries.
Repeated identical imports/snapshots are skipped; changed records sharing an
ID are retained as separate records. Last library mutation can be restored.
Model snapshot uses saved prices, current quantities and USD. No historical
project data is fabricated or preloaded. Save edits in the BOQ panel first.
Apply a selected price only on matching USD/source/unit; model quantities
remain unchanged. Price application is one SketchUp undo operation.
Other currencies and custom items (e.g. foraj) can be archived; they are not
automatically converted or added to the active BOQ template.
Export JSON to back up or migrate to another machine/SketchUp version.
Existing Audit, geometry, BIM inheritance, QTO, dependency and 2/3 decimal
presentation behaviors are retained. Real SketchUp acceptance is required.

v0.23.6.1 - Quantity Display Precision
Area (m2): 2 decimals. Volume (m3): 3 decimals.
BOQ display, remaining area labels, CSV and XLSX formatting updated.
Internal BOQ calculation precision is unchanged.

v0.23.6 - QTO / BOQ Quantity Consistency Fix
Derived from user-validated v0.23.5.1. Dependency module unchanged.
BOQ reads full-precision pile quantities; displayed report rows still round.
Explicit zero topping area is respected. Only absent legacy areas use the
existing gross-area-minus-curbs fallback. Disabled topping remains zero.
No geometry, identity, inheritance, Audit or dependency behavior is changed.
Mocked API tests cover 16 BOQ quantity keys and custom rates/prices.
Actual project quantities must still be compared in SketchUp with reports.

v0.23.5.1 - Ruby Compatibility / Batch Result Hotfix
Replaces Array#to_h with a block (requires Ruby 2.6+) with each_with_object.
The older Ruby implementation ignored the block and tried to convert a
Sketchup::Group into a key/value array, causing the reported TypeError.
Batch precast placement now counts only successful span operations and
stops on the first failure. Earlier committed spans remain in the model;
the message reports partial completion rather than unconditional success.
Validation: 12 mocked API tests / 49 assertions; Ruby syntax; ZIP CRC/source.
Actual SketchUp runtime validation remains required.

Marine Structures Tools v0.23.5 - Dependency Auto-Rebuild Fix

Based on the original v0.23.4 RBZ. Model Audit rules, BIM-complete creation,
and Project/Ano/Span inheritance are preserved.

Dependency caches are rebuilt from live Pile -> BK -> PD/Channel -> Deck ->
Curb relationships. Direct BK -> Deck support edges are retained as well.
Both precast support PIDs must resolve to live beams in the deck support set.
Stale dependency UID/ID lists are replaced, including empty lists.
Source relationship fields are retained so genuine missing support references
remain visible to Audit. No UID, Type ID, organization or geometry is changed
by the dependency rebuild. No missing identity is generated by this module.

All 21 plugin commit sites rebuild inside the existing operation. Native
commits schedule a deferred transparent operation only when cache values
differ. Pending work is cancelled for undo, redo and abort. No model edits
occur inside transaction observer callbacks. Opening a model only attaches
observers; existing caches refresh on the next committed model change.

Validation: Ruby 3.1 syntax; 10 mocked API regression tests / 41 assertions;
unchanged Audit/inheritance/identity methods; ZIP CRC and source comparison.
SketchUp runtime/geometry and real undo integration require the test below.

INSTALL / ACCEPTANCE TEST
Install this RBZ with Extension Manager, fully quit SketchUp, then reopen.
Use a copy of the model. Do not run Element Library, Identity Repair,
Deck Relationship Repair, or Project/Ano/Axis Manager before testing.
Delete/recreate PD and Channel elements supporting D-001; run Model Audit.
Verify the two old MST UIDs are absent and the current PD/Channel UIDs appear
in the Deck dependency_parent_uids. dependency_child_uids holds downstream
Curb UIDs, according to the directed structural dependency chain.
Check one Undo/Redo for creation, native Delete and relationship edits;
verify geometry, Type IDs and surviving element UIDs stay unchanged.
Audit target: 0 errors / 0 warnings, subject to other actual model findings.

Previous release notes follow:
-------------------------------------------------------------------------
Marine Structures Tools v0.23.4 — BIM-Complete Relationship & Organization Fix
- Newly created Normal PD and Kanal inherit Project/Ano/Span from their two supporting Head Beams.
- support_left/right UID plus canonical support UID/PID lists are written at creation.
- Deck inherits organization from its support BK list; curb inherits from parent deck when available.
- Audit remains strict; warnings are fixed at the source, not suppressed.

v0.21.2 — Deck BIM Relationship Repair

- Existing deck slabs can reconstruct support_pids/support_uids from real HB geometry and legacy precast supports.
- Deck Project/Ano/Axis/Span metadata is completed without changing geometry.
- New deck slabs write HB support PID/UID metadata at creation time.
- Model Audit 3.2 includes Deck Relationship Repair.
- Repair is one SketchUp operation and is undoable with one Ctrl+Z.

v0.16.0 — Channel Precast Inner Formwork

- Kanal Prekastı inner U faces are separated from wall-top surfaces.
- Inner channel floor + two inner vertical wall faces are included in formwork by default.
- Wall-top horizontal strips remain NON_FORMWORK.
- Visual formwork coloring and QTO use the same face/formwork rule.
- Front-face-only material rule preserved to prevent double area counting.
- v0.15.1 Universal Editor and v0.14.2 XLSX QTO preserved.

v0.15.1 UI Hotfix
- Universal Editor JS/HTML injection repaired.
- Parametric geometry editor restored from clean v0.14.2 UI base.
- v0.14.2 Real XLSX QTO preserved.

Marine Structures Tools v0.8.0 — Pile UI First Pass
- Pile tab redesigned as a professional engineering workspace.
- Existing pile input IDs and Ruby pile-generation callback preserved.
- Standard diameter dropdown preserved.
- Live pile section, bottom elevation, axis count and pile count added.
- Live schematic plan/section and selected design summary added.
- X remains Ano Length / HB axis direction; Y remains Pier Width / piles per HB.
- Head Beam, Precast and Quantity Takeoff engineering functions are not intentionally redesigned in this pass.

v0.8.1 Professional Pile UI:
- Professional engineering dashboard refinement based on approved mockup.
- Added live steel section area, unit mass, one-pile mass, total pile length and total steel mass.
- Added pile internal concrete area/volume-per-meter reference.
- Added compact quick-access controls and richer status bar.
- Preserved existing pile-generation callback, X/Y engineering convention, low-zone logic, infill logic and metadata IDs.
- Head Beam / Precast / Quantity Takeoff logic intentionally untouched.

v0.8.3 Professional Head Beam UI:
- Head Beam page redesigned into professional engineering workspace.
- Existing BK type manager, overhang fields, fender recess, Kanal Prekastı, axis assignments and generation callbacks preserved.
- Added live selected BK summary and schematic preview.
- Added engineering workflow/status presentation.
- Custom pile-axis layout remains available from v0.8.2.


v0.9.9.9 - Precast Type Identity
- Multi-BK precast visible IDs now represent geometry TYPES, not occurrence counters.
- Identical span/section geometry reuses the same PD/KP type ID.
- Different span length or section geometry receives a new type ID.
- Every physical precast also receives a hidden unique element_uid for traceability.
- Existing deck/formwork/takeoff geometry logic is unchanged.


v0.9.10.0 - Fender Tooth / Channel Deck Fix
- BK tooth editor now has an explicit BK type selector; tooth settings remain independent per BK type.
- Head Beam creation synchronizes current BK type/axis assignments before generation.
- Deck cut depth now uses actual precast top elevation relative to BK/deck bottom. U-channel total depth no longer over-cuts the slab.
- Existing deck physical-cut, formwork, Multi-BK precast and QTO logic otherwise preserved.


v0.9.10.1 - Fender Tooth Geometry Fix
- Corrected END tooth side profile orientation.
- End tooth now drops vertically at the outer HB end, stays at the lowered soffit, and returns to the normal HB soffit over the entered slope length.
- START tooth behavior and existing HB/precast/deck/QTO logic are unchanged.


v0.9.11.0 - Channel Precast Deck Opening
- Deck generation now detects channel_precast elements between selected Head Beams.
- A true physical opening is left in the slab over each channel, using the channel's net inner width and actual modeled length.
- Channel wall strips remain supported/covered; only the U-channel clear interior is opened.
- Removed opening volume is deducted from deck concrete QTO and stored as channel_opening_volume_m3.
- Opening inner faces are not added to deck formwork quantity.
- Existing Multi-BK precast, physical precast cut, deck edge formwork and metadata behavior are otherwise preserved.


v0.9.11.1 - Channel Opening Geometry Hotfix
- Prevents SketchUp 'Duplicate points in array' during channel deck opening creation.
- Adds 0.5 mm geometric tolerance for zero-width deck fragments and near-coincident channel breakpoints.
- Existing BK, PD, deck QTO and formwork rules are unchanged.


v0.9.12.0 - Deck Curb / Tretuvar
- Added optional curb/tretuvar generation to the Deck module.
- Four deck perimeter sides can be independently set to VAR/YOK.
- Curb bottom elevation is automatically the deck top elevation.
- User inputs: width, height, start/end offset, concrete class, formwork/concrete colors.
- Curb concrete volume and vertical-face formwork area are stored as model metadata and included in QTO.
- Existing v0.9.11.1 channel-opening, deck, precast and HB geometry is preserved.

v0.13.0 Engineering Intelligence Suite
- Model Audit 2.0: pile/BK/PD/channel/deck/curb identity, support, material and QTO metadata checks.
- Element Library: model-wide UID + geometry/material type signatures; identical geometry/materials share a type.
- Pile Layout 2.0 selected-pile editor: D/t/vertical length/top elevation/steel grade and independent X/Y rake (H/V).
  Raker geometry is rebuilt with horizontal project-elevation top/bottom annular cuts; actual axis length drives steel weight.
- Professional QTO/BOQ: existing model-based summary/detail reports retained and CSV export added.
- Metadata schema_version/revision/type_signature standardization added without changing stable deck/channel-opening geometry.

v0.14.0 — Universal Element Editor + Professional QTO
- New top-level Eleman Düzenle page for all Marine Structures element types.
- Selected-only / same-library-type update scope.
- Full pile geometry + Rake X/Y editing with horizontal project-elevation cuts.
- Safe metadata/material editing for BK, PD, Channel Precast, Deck and Curb without destructive scaling.
- Professional Excel 2003 XML workbook export with Summary, Detailed QTO and Element Library sheets.
- Rounded engineering quantities; CSV retained only as compatibility export.


v0.14.1 — Professional QTO Hotfix
- Fixed frozen String error in SpreadsheetML Excel export under frozen_string_literal.
- Universal Editor behavior unchanged; non-pile geometry remains protected pending element-specific rebuild engines.


v0.14.2 — Native XLSX QTO
- Professional QTO now writes a real .xlsx workbook with Summary, Detailed QTO and Element Library sheets.
- Excel number cells are rounded; filters, frozen headers and column widths added.
- Material/Class extraction corrected for pile infill concrete and steel piles.


v0.16.1 - Pile Fabrication & Installation QTO
- Added pile fabrication/installation metadata inputs: QTO zone, driving length, splice count, plug, upper/lower reinforcement rings (çarık), PE coating and drilling.
- Added Pile QTO worksheet to Professional XLSX export.
- Manipulation tonnage = pile fabrication steel + upper ring + lower ring.
- Plug weight calculated independently and excluded from manipulation tonnage.


v0.16.2 - Automatic Pile Fabrication Counts
- Splice count is automatic per pile: ceil(pile fabrication length / 12 m) - 1.
- Plug count is automatic: one plug for each pile when plug is enabled.
- Upper ring is explicitly outside-mounted; lower ring is inside-mounted. Ring circumference remains automatic from pile OD/ID; user inputs only strip width, thickness and count.
- Pile QTO recomputes automatic splice/plug counts from actual pile data, including existing model piles.


v0.19.0 Universal Element Editor 2.0
- Project/Ano/Axis/Zone BIM identity fields.
- UID-deduplicated dependency analysis.
- Controlled change preview before apply.
- Selected vs same-Type update scope.
- UID preservation, type signature refresh, dependency refresh.


v0.23.3 - BIM-Complete Creation Fix
- New Pile, Head Beam, Normal PD, Channel Precast, Deck and Curb elements receive Element UID, unique physical Element ID, canonical Type Signature and stable Type ID at creation time.
- Same geometry/material signature reuses the same Type ID; physical IDs/UIDs remain unique.
- Element Library is no longer required as a post-creation repair step for Type ID assignment.

v0.34.10j - Multi-Type Precast Library
- PD: normal precast, PDO/PDÖ: toothed-variable precast, PV: crane precast, PK: channel precast.
- User-defined visible type names; internal library uid keeps layout references stable during the session.
- Multiple types of every family can coexist in one Y-layout; widths come automatically from the selected type.
- Type library is saved into the SketchUp model after placement and restored when the dialog is reopened.
- QTO groups precast by user type name and distinguishes PDÖ/PV/PK families.

