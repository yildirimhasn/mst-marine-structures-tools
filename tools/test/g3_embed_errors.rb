# Parti G-a / G3-#13: mst_bk_pile_embed hata yollari (kazik basina derinlik hatasi, dis hata, registered_external)
# ve mst_audit_v0515 ERROR / UYARI satirlari + kazik orijini denetimi.
# Kullanim: ruby tools/test/g3_embed_errors.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')
class Host
  def mst_bk_connected_piles(_b); raise 'sahte bağlantı hatası' if $conn_fail; $piles; end
end
A1.load(Host, bm, 'def mst_hb_zones_list(', 'def mst_hb_zone_info(', 'def mst_hb_zone_segments(', 'def mst_hb_bottom_depth(')
A1.load(Host, main, 'def mst_bk_pile_embed(', 'def pile_batter_ratio(', 'def mst_attr_hash(')
h = Host.new
A = Math::PI / 4.0 * 1.016**2
def bk(attrs = {})
  b = Sketchup::Group.new(100, { 'element_type' => 'head_beam', 'id' => 'BK-1', 'length_m' => 10.0, 'width_m' => 1.2, 'height_m' => 1.0,
                                 'bottom_elevation_m' => 1.0, 'top_elevation_m' => 2.0,
                                 'end_tooth_enabled' => '1', 'end_tooth_length_m' => 1.5, 'end_tooth_slope_m' => 0.3, 'end_tooth_depth_m' => 0.5 }.merge(attrs))
  b.transformation = Geom::Transformation.translation([5.0.m, 7.0.m, 1.0.m]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, Math::PI / 6)
  b.parent = :ano
  b
end
def pile_at(b, a, y = 0.6, zl = 0.2, extra = {})
  p = Sketchup::Group.new(200 + (a * 100).round, { 'pile_id' => "P@#{a}", 'top_elevation_m' => 1.2, 'diameter_mm' => 1016.0 }.merge(extra))
  p.transformation = b.transformation * Geom::Transformation.translation([a.m, y.m, zl.m])
  p.parent = :ano
  p
end
a1_reset!
b = bk
# ---- normal: değişmez
$piles = [pile_at(b, 9.5), pile_at(b, 5.0)]
x = h.mst_bk_pile_embed(b)
t('normal: düşüm A·0.7 + A·0.2 (K50 değişmez), hata anahtarı yok', [near(x[:volume_m3], A * 0.9), x.key?(:error), x[:items].map { |i| i.key?(:depth_error) }], [true, false, [false, false]])
t('normal: orijin bilgisi (y=0.6, z=1.2 = üst kot)', x[:items].map { |i| [i[:axis_y_m].round(6), i[:origin_z_m].round(6), i[:width_m]] }, [[0.6, 1.2, 1.2], [0.6, 1.2, 1.2]])
# ---- kazık başına derinlik hatası: yalnız o kazık dep=0, diğeri etkilenmez
orig = Host.instance_method(:mst_hb_bottom_depth)
Host.send(:define_method, :mst_hb_bottom_depth) { |zh, zl, a| raise 'sahte derinlik hatası' if a > 9.0; orig.bind(self).call(zh, zl, a) }
x = h.mst_bk_pile_embed(b)
it = x[:items].find { |i| i[:pile_id] == 'P@9.5' }
t('derinlik hatası: o kazıkta dep=0 (A·0.2), depth_error, axis_a_m=nil', [near(it[:volume_m3], A * 0.2), it[:bottom_depth_m], it[:depth_error], it[:axis_a_m]], [true, 0.0, 'sahte derinlik hatası', nil])
t('derinlik hatası: BK düşümü sıfırlanmaz (A·0.4; 0.51.5 önce: 0)', near(x[:volume_m3], A * 0.4), true)
Host.send(:define_method, :mst_hb_bottom_depth, orig)
# ---- dış hata
$conn_fail = true
x = h.mst_bk_pile_embed(b)
$conn_fail = false
t('dış hata: {volume_m3:0, items:[], error:}', [x[:volume_m3], x[:items], x[:error]], [0.0, [], 'sahte bağlantı hatası'])
# ---- registered_external kazık: derinlik 0 (eski kural)
$piles = [pile_at(b, 9.5, 0.6, 0.2, 'registered_external' => true)]
x = h.mst_bk_pile_embed(b)
t('registered_external (true): dep=0 → A·0.2', [near(x[:volume_m3], A * 0.2), x[:items][0][:bottom_depth_m], x[:items][0][:axis_y_m]], [true, 0.0, nil])
$piles = [pile_at(b, 9.5, 0.6, 0.2, 'registered_external' => 'true')]
t('registered_external ("true"): dep=0', near(h.mst_bk_pile_embed(b)[:volume_m3], A * 0.2), true)

# ---- mst_audit_v0515
class Host
  def mst_bk_pile_embed(b); $emb[b.persistent_id] || { volume_m3: 0.0, items: [] }; end
  def mst_pile_rebar_active(_e); false; end
end
a2_const(Host, main, 'MST_AUDIT_ERROR_FLAGS')
A1.load(Host, main, 'def mst_audit_v0515(')
%w[mst_tr_scale_info mst_bk_span_frame_error mst_pv_tooth_seat_warnings].each { |f| A1.load_opt(Host, main, "def #{f}(") }
A1.load_opt(Host, A1.src('mst_rebar_tools.rb'), 'def mst_rt_world_tr(')
%w[mst_collect_toppings mst_topping_parent_deck].each { |f| A1.load_opt(Host, A1.src('dependency_rebuild.rb'), "def #{f}(") }
A1.load_opt(Host, bm, 'def mst_vk_support_state(')
%w[mst_cv_embed_overlap? mst_curb_corner_overlap].each { |f| A1.load_opt(Host, main, "def #{f}(") }   # Parti H H7 / H8 yardımcıları
A1.load_opt(Host, bm, 'def mst_hb_culvert_groups('); A1.load_opt(Host, main, 'def mst_hb_ents(')
class Host; def pile_bim_qto_item(_p); {}; end; def mst_boq_info_rows(_a = nil); []; end; end
bg = bk; bg.transformation = nil   # K23 ölçek denetimi bu testte dışarıda (sahte dönüşüm 16 değer değil)
bc = Sketchup::ComponentInstance.new(101, 'element_type' => 'head_beam', 'id' => 'BK-C')
ok = { pile_id: 'P-OK', pid: 31, diameter_mm: 1016.0, axis_a_m: 5.0, axis_y_m: 0.6, origin_z_m: 1.2, width_m: 1.2, pile_top_m: 1.2 }
$emb = { 101 => { volume_m3: 0.0, items: [], error: 'sahte' },
         100 => { volume_m3: 1.0, items: [ok,
                                            ok.merge(pile_id: 'P-DE', pid: 32, axis_a_m: nil, depth_error: 'derinlik x').reject { |k, _| %i[axis_y_m origin_z_m width_m pile_top_m].include?(k) },
                                            ok.merge(pile_id: 'P-Y', pid: 33, axis_y_m: 1.5),
                                            ok.merge(pile_id: 'P-Z', pid: 34, origin_z_m: 1.25)] } }
$model.entities = []
out = h.mst_audit_v0515([bg, bc], [bg, bc])
out.each { |o| obs('Model Kontrolü', [o[0], o[2], o[3]]) }
t('hata → ERROR (Component BK dahil), ileti', out.select { |o| o[0] == 'ERROR' }.map { |o| o[3] }, ['BK-C: BK gömülme düşümü hesaplanamadı (sahte); BK betonu brüt alındı.'])
t('depth_error → UYARI', out.count { |o| o[0] == 'WARNING' && o[3].include?('P-DE kazığında taban derinliği hesaplanamadı') }, 1)
orig_w = out.select { |o| o[3].include?('kazık orijini kazık başı merkezi olmayabilir; gömülme derinliği doğrulanmalı') }
t('orijin denetimi: y∉[0,width] ve |z−üst kot|>0,01 → UYARI; doğru kazıkta yok', orig_w.map { |o| o[3][/P-[A-Z]+/] }, %w[P-Y P-Z])
t('orijin uyarıları WARNING / Hesap Hatası', orig_w.map { |o| [o[0], o[2]] }.uniq, [['WARNING', 'Hesap Hatası']])
a1_finish
