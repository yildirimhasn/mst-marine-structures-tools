# MST v0.51.4 TB1 RUBY25 — ana oturum ön kontrolleri (29.10.2026)

## Dosya
- Drive: `G:\Drive'ım\MST_v0.51.4_TB1_Ruby25_TEST.rbz` (Drive kökü, id 1b14llb9qYOUY84v6MqbbRg5beaOQb8LX), 1.159.904 bayt, değiştirilme 28.10.2026 20:35:03Z (23:35 yerel). Drive aramasında tek eşleşme.
- SHA-256: 5684BEC3375E57403C13B4C0476D8DAA3547659A6B376A40274B53A303F2AC42 (Downloads kopyası aynı).
- İnceleme kopyası (açılmış): `review_v0514/pkg/` → `marine_structures_tools.rb` + `marine_structures_tools/` (201 dosya: 66 rb, 13 js, 13 html, 3 css, 7 json, 97 png, 2 txt).
- Kurulu SketchUp 2020 eklentisi ile 201/201 dosya aynı (kurulu sürüm = bu paket). Kurulu ek test eklentileri: `mst_tb1_integration_runner` (1.1.0), `mst_parity_export`, `mst_demo_bathymetry`.

## Sürüm
- `main.rb:27 MST_BUILD = 'v0.51.4 TB1 RUBY25'`, `qto_workspace.rb:4 VERSION = '0.51.4'`; yükleyici `EXTENSION.version=VERSION`. Tutarlı.
- 0.51.4 = `MST_v0.51.3_TB1_Integrated_TEST` (201 dosya) + 5 dosya farkı: sürüm adları + Ruby 2.5 uyumu (`filter_map`→`map.compact` headbeam_editor.rb/health_history.rb; `.then`→if/else quantity_service.rb). Fark dosyası: `out/diff_0513int_to_0514.diff`.
- `MST_v0.51.2_TB1_TEST` ile 158/168 aynı. Yerel depo `src/` (0.52.0-dev1) ile 106 ortak dosyadan 89 aynı, 17 farklı; 95 dosya yalnız pakette, 14 yalnız depoda → ayrı sürüm hattı.
- `RELEASE_UI9.txt` son kaydı 0.51.2 TB1; 0.51.3 ve 0.51.4 için sürüm notu yok. `README.txt` v0.36.7'den kalma (eski).
- `MST_FEATURES` listesi (main.rb:29) kod içi özellik etiketleri.

## Statik kontroller (bu oturumda çalıştırıldı)
- `ruby -c` (Ruby 3.1.2): 66/66 Syntax OK.
- Ruby 2.5 dilbilgisi (`parser` gem 3.3.13, `Parser::Ruby25`): 66 dosya, 0 hata.
- Ruby 2.6+ yöntem taraması (filter_map, tally, then, except, intersection, union, difference, filter, Integer(exception:), to_h blok, Enumerator.produce): Ruby kodunda eşleşme yok (tek eşleşme main.rb:9827 gömülü JS `filter`).
- `node --check`: 13/13 js geçti. JSON: 7/7 ayrıştı.
- JS (SketchUp 2020 CEF ≈ Chromium 64): `?.`, `??`, `replaceAll`, `flat/flatMap`, `Object.fromEntries`, `matchAll`, `globalThis`, `allSettled`, `.at(` js/html'de bulunmadı.
- CSS: `gap:` ~249, `display:flex` 150, `position:sticky` 21, `min(`/`max(` (CSS mi JS mi ayrılmadı), `accent-color` 1. Flex `gap` Chromium 84+, CSS `min()/max()` 79+, `accent-color` 93+ → SU2020'de görsel bozulma riski (doğrulanmadı).
- `require_relative` hedeflerinin hepsi mevcut; main.rb dışında yüklenmeyen rb yok. html/js/css dosyalarının hepsine başvuru var. `icons/nav_*.png` (adla başvuru yok; dinamik ad olabilir — doğrulanmadı).
- Yükleme sırası: main.rb başında 16 modül, 10164-10178 arası 15 modül, dosya sonunda 12637-12650 arası 14 modül (boq_pro "en sonda: BOQ/hakediş fonksiyonlarını genişletir" — sonradan yüklenen dosyaların main.rb işlevlerini yeniden tanımlama olasılığı incelenmeli).
- main.rb 12.653 satır; Ruby toplam ~25.800 satır.

## Ortam sınırı
- SketchUp çalışma zamanına erişim yok; geometri/arayüz/Undo davranışı doğrulanamaz. Ruby 2.5 yorumlayıcısı yok; yalnız dilbilgisi + yöntem taraması.

## Ek statik çıktılar (ana oturum, parser tabanlı)
- `out/redefinitions.txt`: 1428 metot tanımı; 17 metot birden fazla kez tanımlı. 13'ü boq_pro.rb'de (9'u `alias_method ..._base` ile sarmalanmış, 4'ü alias'sız: progress_approved_quantity, progress_live_rows, progress_save, progress_delete_period → main.rb sürümünü tamamen geçersiz kılar), 3'ü mst_labels.rb'de alias'lı sarmalama, 1'i aynı dosyada iki kez: `project_ano_axis_manager` main.rb:8797 ve main.rb:12464 (alias yok; sonraki tanım geçerli).
- `out/static_metrics.txt`: observer kayıtları (dependency_rebuild.rb:184/190, health_freshness.rb, project_workspace.rb), timer'lar, menü/toolbar kaydı yalnız main.rb (file_loaded guard main.rb:10233-10290), sessiz rescue sayıları (main.rb 86, mst_rebar_tools 17, boq_pro 15, mst_v50_beams 13, mst_dwg_rebar 12 ...).
