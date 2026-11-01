# Parti F / F1 — Ayrıntılı Metraj (Excel) sayfasında kazık içi beton bir kez sayılır.
# Eklenti golden-master sahtesiyle (tools/golden/sketchup_stub.rb + fixture.rb) gerçek yükleme sırasıyla yüklenir,
# export_professional_excel çalıştırılır ve 'Ayrıntılı Metraj' sayfası satırları (xlsx_sheet_xml girdisi) okunur.
# Fikstürde iç beton: P1 Group kazık + fiziksel iç beton çocuğu (V), P2 Component "iç beton YOK" (0),
# P2B Component kazık, paylaşılan tanım, parametre V; P3 Group kazık, parametre 8.0 m³; P4 iç beton yok.
# Bağımsız beklenen iç beton = V + V + 8.0 (V = π/4·0.984²·12 = 9.126 m³).
# Kullanim: ruby tools/test/f1_infill_excel.rb <src/marine_structures_tools>
require 'tmpdir'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/f1_infill_excel.rb <marine_structures_tools klasoru>'
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
require_relative '../golden/fixture'
M = MAG::MarineStructuresTools
golden_build_fixture

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end
def obs(label, val); puts "GÖZLEM #{label}: #{val.inspect}"; end

sheets = {}
orig = M.method(:xlsx_sheet_xml)
M.define_singleton_method(:xlsx_sheet_xml) { |headers, rows, widths| sheets[headers] = rows; orig.call(headers, rows, widths) }
Dir.mktmpdir('mst_f1') do |tmp|
  path = File.join(tmp, 'f1.xlsx')
  UI.define_singleton_method(:savepanel) { |*_a| path }
  M.export_professional_excel
end
detail = sheets.find { |h, _| h.include?('Boru Çeliği (t)') }&.last or abort('Ayrıntılı Metraj sayfası üretilmedi')
summary = sheets.find { |h, _| h == %w[Kalem Miktar Birim] }&.last || []
inf_rows = detail.select { |r| r[0].to_s.start_with?('Kazık İçi') }
inf_rows.each { |r| obs('iç beton satırı', r.first(8)) }
exp_v = (2 * V_INFILL + 8.0).round(3)
t('F1: iç beton tek satırda (0.51.4–f7046b5: fiziksel grup satırı + Özet satırı)', inf_rows.length, 1)
t('F1: Ayrıntılı Metraj iç beton toplamı = V + V + 8.0 (P1 fiziksel + P2B + P3)', inf_rows.sum { |r| r[5].to_f }.round(3), exp_v)
snap = M.qto3_snapshot
row = snap[:rows].find { |r| r[:type] == 'pile_infill_concrete' }
t('F1: iç beton donatısı Özet (qto3_snapshot) satırıyla aynı (çift değil)', inf_rows.sum { |r| r[9].to_f }.round(6), row[:steel_t].round(6))
tot = summary.find { |r| r[0] == 'Toplam Beton' }
t('F1: sayfadaki tüm beton = Özet "Toplam Beton"', detail.sum { |r| r[5].to_f }.round(3), tot && tot[1].to_f.round(3))
t('F1: Eleman Kütüphanesi adı tutarlı ("Kazık İçi Beton")',
  sheets.find { |h, _| h.include?('Tip İmzası') }&.last.to_a.select { |r| r[1].to_s.start_with?('Kazık İçi') }.map { |r| r[1] }.uniq, ['Kazık İçi Beton'])
t('F1: işlem açılmadı / kapatılmadı', $model.ops, [])
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
