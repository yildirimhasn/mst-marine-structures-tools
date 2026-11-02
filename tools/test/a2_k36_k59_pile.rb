# A2 / K36 (Component kazikta "ic beton YOK") ve K59 (kafes hesabi hatasinda sessiz 0 yok) — ADR-0515 §6.
# Kullanim: ruby tools/test/a2_k36_k59_pile.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
qw = A1.src('qto_workspace.rb')
pm = A1.src('pile_manufacturing.rb')

class Host
  def qto3_quantity(e, _k); e.get_attribute(DICT, 'concrete_volume_m3', 0).to_f; end
  def rebar_rate(_k); 250.0; end
  def element_visible_id(e); e.get_attribute(DICT, 'pile_id', 'P'); end
  def save_infill_recipe(*_a); $log << [:recipe]; end
  def rebuild_saved_infill(p); $log << [:rebuild]; p.set_attribute(DICT, 'infill_enabled', '1'); end
end
module QuantityService; def self.number(v, _k); Float(v); end; end
class Host; QuantityService = ::QuantityService; end
A1.load(Host, qw, 'def pile_qto_infill_children(', 'def pile_qto_concrete(')
A1.load(Host, main, 'def mst_container_entities(', 'def mst_component_pile?(', 'def mst_bim_children(', 'def mst_pile_rebar_active(',
        'def mst_pile_rebar_t(', 'def mst_pile_rebar_qto!(', 'def mst_pile_rebar_params_of(')
EFF = A1.load_opt(Host, main, 'def mst_pile_rebar_effective?(')
A1.load(Host, pm, 'def pile_infill_child(', 'def pile_infill_enabled?(', 'def set_pile_infill(')
obs('mst_pile_rebar_effective? tanımlı', EFF)
h = Host.new
D = A1::DICT

# Ø1016×16, iç beton h=12 → π/4·0.984²·12 = 9.126 m³ (08 bağımsız örnek)
V = Math::PI / 4 * 0.984**2 * 12.0
def comp_pile(pid, enabled, extra = {})
  child = Sketchup::Group.new(9000 + pid, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => V)
  defn = Sketchup::ComponentDefinition.new(8000 + pid); defn.entities = [child]
  p = Sketchup::ComponentInstance.new(pid, { 'element_type' => 'steel_pipe_pile', 'pile_id' => "P-#{pid}", 'infill_enabled' => enabled,
                                             'infill_concrete_volume_m3' => (enabled == '1' ? V : 0.0), 'diameter_mm' => 1016.0, 'thickness_mm' => 16.0 }.merge(extra))
  p.definition = defn
  p
end
a1_reset!
c_on = comp_pile(1, '1')
c_off = comp_pile(2, '0')
obs('K36 Component kazık, iç beton VAR — hacim', h.pile_qto_concrete(c_on).round(3))
obs('K36 Component kazık, iç beton YOK (paylaşılan çocuk tanımda duruyor) — hacim', h.pile_qto_concrete(c_off).round(3))
t('K36: Component YOK → iç beton 0 (0.51.4: 9.126)', h.pile_qto_concrete(c_off), 0.0)
t('K36: Component VAR → 9.126 m³ değişmez', h.pile_qto_concrete(c_on).round(3), 9.126)
t('K36: YOK kazığın pursantaj donatısı 0 (0.51.4: 9.126×250 = 2.281 t)', h.mst_pile_rebar_t(c_off), 0.0)
g_child = Sketchup::Group.new(77, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => V)
g_on = Sketchup::Group.new(3, 'element_type' => 'steel_pipe_pile', 'infill_enabled' => '1'); g_on.entities = [g_child]
t('K36: Group kazık VAR (fiziksel çocuk) değişmez', h.pile_qto_concrete(g_on).round(3), 9.126)
t('K36: arayüz durumu Component YOK → YOK (0.51.4: VAR)', h.pile_infill_enabled?(c_off), false)
t('K36: arayüz durumu Component VAR → VAR', h.pile_infill_enabled?(c_on), true)
$log = []
r = h.set_pile_infill(c_off, true)
t('K36: Component YOK → VAR yapılabiliyor (0.51.4: çocuk var diye hiçbir şey yapmazdı)', [r, $log.any? { |x| x[0] == :rebuild }], [true, true])
c3 = comp_pile(4, '0'); $log = []
t('K36: Component zaten YOK → YOK yeniden yazılmaz', h.set_pile_infill(c3, false), false)
c4 = comp_pile(5, '1'); $log = []
t('K36: Component VAR → YOK (çocuk silinmez, değer 0)', [h.set_pile_infill(c4, false), c4.erased.nil?, c4.a('infill_enabled'), $log.none? { |x| x[0] == :erase }], [true, true, '0', true])

# ---- K59: kafes hesabı hata verirse
a1_reset!
p = comp_pile(10, '1', 'pile_rebar_mode' => 'bim_detail', 'pile_rebar_json' => '{"long_dia_mm":25}', 'pile_cage_rebar_kg' => 1500.0)
h.define_singleton_method(:mst_pile_rebar_params) { |x| x }
h.define_singleton_method(:mst_pile_rebar_calc) { |_g, _p, _o = nil| raise 'Donatı kafesi kazığa sığmıyor (iç çap 984 mm, pas payı 600 mm).' }
h.mst_pile_rebar_qto!(p)
obs('K59 hata sonrası pile_cage_rebar_kg', p.a('pile_cage_rebar_kg'))
obs('K59 hata sonrası pile_rebar_error', p.a('pile_rebar_error'))
t('K59: hata nedeni kaydedildi (0.51.4: kaydedilmez, 0 yazılır)', p.a('pile_rebar_error').to_s.include?('sığmıyor'), true)
t('K59: tonaj 0 yazılmadı (silindi)', p.a('pile_cage_rebar_kg'), nil)
exp = V * 250.0 / 1000.0
t('K59: kazık donatısı = iç beton × pursantaj (9.126 × 250 = 2.281 t; 0.51.4: 0)', h.mst_pile_rebar_t(p).round(4), exp.round(4))
q = comp_pile(11, '1')
t('K59 kabul: hata durumundaki tonaj = pile_rebar_mode boş tonajı', h.mst_pile_rebar_t(p).round(9), h.mst_pile_rebar_t(q).round(9))
t('K59: mst_pile_rebar_active değişmedi (parametreler korunur)', [h.mst_pile_rebar_active(p), p.a('pile_rebar_json')], [true, '{"long_dia_mm":25}'])
h.define_singleton_method(:mst_pile_rebar_calc) { |_g, _p, _o = nil| { 'kg' => 1400.0, 'n' => 16 } }
h.mst_pile_rebar_qto!(p)
t('K59: başarılı hesapta bayrak silinir, BIM tonajı kullanılır', [p.a('pile_rebar_error'), h.mst_pile_rebar_t(p)], [nil, 1.4])

# ---- Parti G-a / kod inceleme #3: K59 hata yolunda iç betonun rebar_t'si = iç beton oluşturma yolundaki durum.
# Oluşturma yolları (add_pile_infill, pile_manufacturing yeniden kurma) iç betona rebar_t / rebar_mode YAZMAZ;
# hata yolundaki silme bu durumla birebir aynıdır. Metraj: iç beton hacim × oran (QuantityService), rebar_t okunmaz.
ap = A1.grab(main, 'def add_pile_infill(')
t('#3: add_pile_infill iç betona rebar_t / rebar_mode yazmaz', [ap.include?("'rebar_t'"), ap.include?("'rebar_mode'")], [false, false])
t('#3: pile_manufacturing iç beton öznitelikleri rebar_t içermez', pm[/attrs=\{'element_type'=>'pile_infill_concrete'[^\n]*/].to_s.include?('rebar_t'), false)
A1.load(Host, main, 'def mst_pile_rebar_refresh!(')
a1_reset!
inf = Sketchup::Group.new(9100, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => V, 'rebar_mode' => 'bim_detail', 'rebar_t' => 1.4)
gp = Sketchup::Group.new(100, 'element_type' => 'steel_pipe_pile', 'pile_id' => 'P-G', 'pile_rebar_mode' => 'bim_detail', 'pile_rebar_json' => '{"long_dia_mm":25}')
gp.entities = [inf]
h.define_singleton_method(:mst_pile_rebar_calc) { |_g, _p, _o = nil| raise 'Donatı kafesi kazığa sığmıyor.' }
h.mst_pile_rebar_refresh!(gp)
fresh = Sketchup::Group.new(9101, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => V)
t('#3: hata sonrası iç beton anahtarları = yeni oluşturulmuş iç beton (rebar_t / rebar_mode yok)', inf.raw_attrs.keys.map(&:last).sort, fresh.raw_attrs.keys.map(&:last).sort)
t('#3: hata nedeni kazıkta', gp.a('pile_rebar_error').to_s.include?('sığmıyor'), true)
a1_finish
