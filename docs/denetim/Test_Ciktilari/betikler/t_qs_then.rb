# QuantityService: 0.51.3 (.then) <-> 0.51.4 (if/else) esdegerlik testi (SketchUp disinda).
# Kullanim: ruby t_qs_then.rb <0513_quantity_service.rb> <0514_quantity_service.rb>
old_src = File.read(ARGV[0], encoding: 'UTF-8').sub(/^module MAG\b/, 'module OLDNS')
new_src = File.read(ARGV[1], encoding: 'UTF-8').sub(/^module MAG\b/, 'module NEWNS')

API_BODY = <<~R
  DICT = 'd'
  extend self
  def pile_weight(d, t, l); Math::PI / 4 * ((d / 1000.0)**2 - ((d - 2 * t) / 1000.0)**2) * l * 7850; end
  def pile_qto_infill_children(_); []; end
  def rebar_rate(_); 100.0; end
  def mst_element_rebar(_); nil; end
R
%w[OLDNS NEWNS].each { |ns| eval("module #{ns}; module MarineStructuresTools; #{API_BODY}; end; end") }
eval(old_src); eval(new_src)

class Rec
  def initialize(h); @h = h; end
  def get_attribute(_d, k, dflt = nil); @h.key?(k) ? @h[k] : dflt; end
  def persistent_id; 7; end
end
cases = {
  'kazık weight_kg 1500'           => { 'element_type' => 'steel_pipe_pile', 'weight_kg' => '1500' },
  'kazık theoretical 2.000,5 yok'  => { 'element_type' => 'steel_pipe_pile', 'theoretical_weight_kg' => '2000,5' },
  'kazık ağırlık yok'              => { 'element_type' => 'steel_pipe_pile' },
  'kazık ağırlık bozuk'            => { 'element_type' => 'steel_pipe_pile', 'weight_kg' => 'abc' },
  'kazık ağırlık negatif'          => { 'element_type' => 'steel_pipe_pile', 'weight_kg' => -5 },
  'BK steel_t (rebar dalı)'        => { 'element_type' => 'head_beam', 'concrete_volume_m3' => 10 },
  'döşeme bim rebar_t'             => { 'element_type' => 'deck_slab', 'rebar_mode' => 'bim_detail', 'rebar_t' => '1,5' },
  'bilinmeyen tip'                 => { 'element_type' => 'xyz' },
}
modes = { 'kanonik ağırlık işlevi YOK' => false, 'kanonik ağırlık işlevi VAR' => true }
ok = 0; bad = 0
run = lambda do |tag|
  modes.each do |mlabel, canon|
    [OLDNS, NEWNS].each do |ns|
      api = ns::MarineStructuresTools
      if canon then api.send(:define_method, :mst_pile_canonical_weight_kg) { |_p| 0 }
      elsif api.method_defined?(:mst_pile_canonical_weight_kg) then api.send(:remove_method, :mst_pile_canonical_weight_kg) end
    end
    cases.each do |label, h|
      e = Rec.new(h.merge('diameter_mm' => 1000, 'thickness_mm' => 10, 'length_m' => 20))
      a = OLDNS::MarineStructuresTools::QuantityService.record(e, :steel_t)
      b = NEWNS::MarineStructuresTools::QuantityService.record(e, :steel_t)
      same = a == b
      same ? ok += 1 : bad += 1
      puts "#{same ? 'AYNI ' : 'FARKLI'} [#{tag} | #{mlabel}] #{label}: eski=#{a.reject { |k, _| k == :source_pid }.inspect}#{same ? '' : " yeni=#{b.inspect}"}"
    end
  end
end
puts "Ruby #{RUBY_VERSION}; Kernel#then var mı: #{Kernel.method_defined?(:then)}"
run.('Ruby 3.1, then mevcut')
# Ruby 2.5 benzetimi: Kernel#then kaldirilir (2.5'te yalniz yield_self vardi)
Kernel.send(:remove_method, :then)
puts "Kernel#then kaldırıldı (Ruby 2.5 benzetimi): #{Kernel.method_defined?(:then)}"
ok25 = ok; bad25 = bad
run.('then yok (2.5 benzetimi)')
puts "Ruby 3.1 koşusu: #{ok25} aynı, #{bad25} farklı (beklenen: hepsi aynı)"
puts "2.5 benzetimi: #{ok - ok25} aynı, #{bad - bad25} farklı (beklenen: eski sürüm .then dalında 'invalid')"
