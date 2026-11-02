# Golden-master BOQ/QTO cikti ureticisi (SketchUp DISINDA, sahte nesne). Eklenti gercek yukleme sirasiyla yuklenir
# (sketchup_stub.rb + <klasor>/main.rb), fixture.rb modeli kurulur ve yalniz metraj okuyuculari cagrilir.
# Kullanim: ruby tools/golden/golden_qto.rb <marine_structures_tools klasoru> <cikti.csv>
# CSV (UTF-8, ';'): bolum;anahtar;deger   — sayilar 9 ondalik. Hata veren okuyucu "HATA: <ileti>" yazar (uydurma deger yok).
require_relative 'sketchup_stub'
dir, out = ARGV
abort 'kullanim: ruby tools/golden/golden_qto.rb <klasor> <cikti.csv>' unless dir && out
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
require_relative 'fixture'
M = MAG::MarineStructuresTools
golden_build_fixture
$writes = []   # fikstur yazimlari sayilmaz; asagidaki sayi okuyucularin yazimidir

rows = []
fmt = ->(v) { v.is_a?(Numeric) ? format('%.9f', v.to_f) : v.to_s.gsub(/[;\r\n]/, ' ') }
put = ->(sec, key, val) { rows << [sec, key, fmt.(val)] }
safe = lambda do |sec, key, &blk|
  begin
    put.(sec, key, blk.call)
  rescue StandardError => e
    put.(sec, key, "HATA: #{e.class}: #{e.message[0, 160]}")
  end
end
def eid(e)
  e.get_attribute(D, 'pile_id', nil) || e.get_attribute(D, 'head_beam_id', nil) || e.get_attribute(D, 'deck_id', nil) ||
    "#{e.get_attribute(D, 'element_type', '')}-#{e.persistent_id}"
end

# 1) BOQ kaynak miktarlari (boq_quantities)
begin
  M.boq_quantities.sort.each { |k, v| put.('BOQ_QTY', k, v) }
rescue StandardError => e
  put.('BOQ_QTY', '*', "HATA: #{e.class}: #{e.message[0, 160]}")
end
# 2) BOQ satirlari (boq_rows, pasifler dahil) — kod, kaynak, miktar
begin
  M.boq_rows(true).each { |r| put.('BOQ_ROW', "#{r[:code]}|#{r[:source]}|#{r[:unit]}", r[:quantity]) }
rescue StandardError => e
  put.('BOQ_ROW', '*', "HATA: #{e.class}: #{e.message[0, 160]}")
end
# 3) BOQ bilgi satirlari (yalniz tanimliysa; toplam disi)
if M.respond_to?(:mst_boq_info_rows)
  begin
    M.mst_boq_info_rows.each { |r| put.('BOQ_INFO', r[:source], r[:quantity]) }
  rescue StandardError => e
    put.('BOQ_INFO', '*', "HATA: #{e.message[0, 160]}")
  end
else
  put.('BOQ_INFO', '*', 'işlev yok')
end
# 4) Donati dokumu (ÖBF-004)
begin
  all = []; M.collect_elements($model.entities, all)
  M.mst_boq_rebar_breakdown(all).each { |r| put.('REBAR_BREAKDOWN', r[:key], r[:kg]) }
rescue StandardError => e
  put.('REBAR_BREAKDOWN', '*', "HATA: #{e.message[0, 160]}")
end
# 5) QTO ozeti (qto3_snapshot)
begin
  s = M.qto3_snapshot
  s[:rows].each { |r| %i[count length_m concrete_m3 formwork_m2 steel_t].each { |k| put.('QTO3_ROW', "#{r[:type]}|#{k}", r[k]) } }
  s[:totals].each { |k, v| put.('QTO3_TOTAL', k, v) }
  s[:concrete_by_class].sort.each { |k, v| put.('QTO3_CLASS', k, v) }
rescue StandardError => e
  put.('QTO3_ROW', '*', "HATA: #{e.class}: #{e.message[0, 160]}")
end
# 6) Kazik grubu miktarlari (ayri poz)
%w[PILE_STEEL PILE_INFILL PILE_DRIVING].each do |k|
  begin
    M.pile_boq_group_quantities(k).each { |label, q, _ps, _g| put.('PILE_GROUP', "#{k}|#{label}", q) }
  rescue StandardError => e
    put.('PILE_GROUP', k, "HATA: #{e.message[0, 160]}")
  end
end
# 7) Oge bazinda miktarlar
all = []; M.collect_elements($model.entities, all)
all.sort_by { |e| [e.get_attribute(D, 'element_type', ''), eid(e)] }.each do |e|
  id = "#{e.get_attribute(D, 'element_type', '')}|#{eid(e)}"
  %i[count length_m concrete_m3 formwork_m2 steel_t rebar_t].each { |k| safe.('ELEM', "#{id}|#{k}") { M::QuantityService.value(e, k) } }
  safe.('ELEM', "#{id}|rebar_kg") { M.mst_element_rebar(e)['kg'] }
  safe.('ELEM', "#{id}|rebar_source") { M.mst_element_rebar(e)['source'] }
  case e.get_attribute(D, 'element_type', '')
  when 'steel_pipe_pile'
    safe.('ELEM', "#{id}|pile_qto_concrete") { M.pile_qto_concrete(e) }
    safe.('ELEM', "#{id}|pile_rebar_t") { M.mst_pile_rebar_t(e) }
    safe.('ELEM', "#{id}|driving_m") { M.pile_driving_length(e) }
    safe.('ELEM', "#{id}|infill_class") { M.pile_report_concrete_class(e) }
    it = (M.pile_bim_qto_item(e) rescue nil)
    %i[steel_t concrete_m3 pe_m2 drilling_m plug_kg upper_ring_kg lower_ring_kg].each { |k| put.('ELEM', "#{id}|bim_#{k}", it ? it[k] : 'HATA') }
  when 'head_beam'
    safe.('ELEM', "#{id}|gross_concrete") { M.head_beam_gross_concrete(e) }
    safe.('ELEM', "#{id}|pile_embed_m3") { M.head_beam_pile_embed_volume(e) }
    safe.('ELEM', "#{id}|gross_formwork") { M.head_beam_gross_formwork_area(e) }
    safe.('ELEM', "#{id}|pile_opening_m2") { M.head_beam_pile_opening_area(e) }
  end
end
safe.('TOPPING', 'area_m2') { M.topping_quantities(all)[0] }
safe.('TOPPING', 'volume_m3') { M.topping_quantities(all)[1] }

# 8) Pano / Metraj sayfasi yuku (qto_summary -> setQTO JSON): sayisal alanlar ve Ana Metraj Ozeti satir hucreleri (gosterim)
class GoldenDialog; attr_reader :js; def initialize; @js = []; end; def execute_script(j); @js << j; true; end; def visible?; true; end; end
begin
  gd = GoldenDialog.new
  M.qto_summary(gd)
  j = gd.js.find { |x| x.start_with?("setQTO(") }
  data = JSON.parse(j[/\AsetQTO\((.*)\);?\z/m, 1])
  %w[pile_count pile_length steel_ton total_concrete total_formwork pd_count pd_volume channel_count channel_volume].each { |k| put.("QTO_SUMMARY", k, data[k]) if data.key?(k) }
  (data["concrete_breakdown"] || {}).sort.each { |k, v| put.("QTO_SUMMARY", "concrete_breakdown|#{k}", v) }
  data["rows"].to_s.scan(%r{<tr>(.*?)</tr>}m).flatten.each do |tr|
    cells = tr.scan(%r{<td[^>]*>(.*?)</td>}m).flatten.map { |c| c.gsub(%r{<small.*?</small>}m, "").gsub(/<[^>]+>/, "").strip }
    put.("QTO_SUMMARY_ROW", "#{cells[0]}|#{cells[1]}", cells[2..-1].join(" | "))
  end
rescue StandardError => e
  put.("QTO_SUMMARY", "*", "HATA: #{e.class}: #{e.message[0, 160]}")
end

# 9) pursantaj oranlari (karsilastirma betiginin beklenen farki hesaplamasi icin)
%w[pile head_beam deck topping].each { |k| safe.("RATE", k) { M.rebar_rate(k) } }

# 10) Parti G-b: Kesif REBAR izleme (hakedis eleman kumesi) — adet ve eleman donatisi toplami
safe.('REBAR_TRACE', 'count') { M.boq_trace_entities('REBAR').size }
safe.('REBAR_TRACE', 'sum_t') { M.boq_trace_entities('REBAR').sum { |e| M.progress_entity_quantity(e, 'REBAR').to_f } }
# 11) Parti G-b: Kesif / Metraj CSV (export_boq_csv gercek ciktisi; satir anahtari = sira + ilk 3 sutun)
require 'tmpdir'
require 'csv'
begin
  Dir.mktmpdir('mst_golden_csv') do |tmp|
    path = File.join(tmp, 'g.csv')
    UI.define_singleton_method(:savepanel) { |*_a| path }
    M.export_boq_csv
    crows = CSV.read(path, encoding: 'UTF-8')
    put.('CSV', 'header', crows[0].join('|'))
    crows.drop(1).each_with_index { |r, i| put.('CSV', "#{i}|#{r[0]}|#{r[1]}|#{r[2]}", r[3..-1].join('|')) }
    (5...crows[0].size).each { |c| put.('CSV_TOTAL', crows[0][c], crows.drop(1).sum { |r| r[c].to_f }) }
  end
rescue StandardError => e
  put.('CSV', '*', "HATA: #{e.class}: #{e.message[0, 160]}")
end
# 12) Parti G-b: Ayrintili Metraj (Excel) — Ozet ve Ayrintili Metraj sayfa satirlari (xlsx_sheet_xml girdisi)
begin
  sheets = {}
  orig_x = M.method(:xlsx_sheet_xml)
  M.define_singleton_method(:xlsx_sheet_xml) { |h, r, w| sheets[h] = r; orig_x.call(h, r, w) }
  Dir.mktmpdir('mst_golden_xlsx') do |tmp|
    path = File.join(tmp, 'g.xlsx')
    UI.define_singleton_method(:savepanel) { |*_a| path }
    M.export_professional_excel
  end
  summ = sheets.find { |h, _| h == %w[Kalem Miktar Birim] }&.last or raise 'Özet sayfası yok'
  summ.each { |r| put.('EXCEL_SUMMARY', r[0], r[1]) if r[1].is_a?(Numeric) }
  det = sheets.find { |h, _| h.include?('Boru Çeliği (t)') }&.last or raise 'Ayrıntılı Metraj sayfası yok'
  det.each { |r| put.('EXCEL_DETAIL', "#{r[0]}|#{r[1]}|#{r[2]}", r[3..-1].map { |v| fmt.(v) }.join('|')) }
  put.('EXCEL_DETAIL_TOTAL', 'beton_m3', det.sum { |r| r[5].to_f })
  put.('EXCEL_DETAIL_TOTAL', 'donati_t', det.sum { |r| r[9].to_f })
rescue StandardError => e
  put.('EXCEL_SUMMARY', '*', "HATA: #{e.class}: #{e.message[0, 160]}")
end
# 13) Parti G-b: hakedis canli satirlari (gecmis yok; D1 onayli, C1 eski durum Onaylandi, D1K kopyanin kopyasi onaysiz)
begin
  M.progress_live_rows('2026-11-02').each do |r|
    put.('HAKEDIS', "#{r[:key]}|approved", r[:approved_quantity])
    put.('HAKEDIS', "#{r[:key]}|warning", r[:warning].to_s) unless r[:warning].to_s.empty?
  end
rescue StandardError => e
  put.('HAKEDIS', '*', "HATA: #{e.class}: #{e.message[0, 160]}")
end

File.open(out, 'w:UTF-8') do |f|
  f.puts 'bolum;anahtar;deger'
  rows.each { |r| f.puts r.join(';') }
end
puts "kaynak=#{dir}"
puts "satir=#{rows.size} hata=#{rows.count { |r| r[2].start_with?('HATA') }}"
puts "stub_misses=#{$stub_misses.sort_by { |_, v| -v }.first(15).to_h}"
puts "model_yazimi(set/delete_attribute)=#{($writes || []).size} islem=#{$model.ops.size}"
