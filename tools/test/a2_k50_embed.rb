# A2 / K50: BK kazik gommesi yerel taban kotundan (dis + taban bolgesi) — ADR-0515 §5.
# Ayrica: kazik grup orijininin kazik basi merkezi oldugu (add_pile / pipe) dogrulanir.
# Kullanim: ruby tools/test/a2_k50_embed.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')

class Host
  def mst_bk_connected_piles(_b); $piles; end
  def mst_prof(_k); yield; end
  def finalize_bim_identity(*_a); end
  def mst_pile_core_attrs(*_a); {}; end
end
A1.load(Host, bm, 'def mst_hb_zones_list(', 'def mst_hb_zone_info(')
NEW = A1.load_opt(Host, bm, 'def mst_hb_zone_segments(') & A1.load_opt(Host, bm, 'def mst_hb_bottom_depth(')
A1.load(Host, main, 'def mst_bk_pile_embed(', 'def pile_batter_ratio(', 'def mst_attr_hash(', 'def pipe(', 'def add_pile(')
obs('yeni işlevler (mst_hb_zone_segments, mst_hb_bottom_depth)', NEW)
h = Host.new
D = A1::DICT

# ---- kazik orijini = kazik basi merkezi (add_pile: pipe yerelde z=0 ust, sonra rot, sonra (x,y,top) otelemesi)
class GeomEnts
  attr_reader :circles
  def initialize; @circles = []; end
  def add_group; g = Sketchup::Group.new(rand(1_000_000)); g.transformation = Geom::Transformation.new; g.entities = GeomEnts.new; g; end
  def add_circle(c, _n, r, _s); @circles << [c.to_a, r]; [:edge]; end
  def add_face(_e); FaceStub.new; end
end
class FaceStub
  def normal; Geom::Vector3d.new(0, 0, 1); end
  def reverse!; end
  def pushpull(d); $pushpull = d; end
  def erase!; end
  def valid?; true; end
end
class FakeEnt
  def transform!(t); @transformation = t * (@transformation || Geom::Transformation.new); end
end
a1_reset!
ents = GeomEnts.new
rot = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 0, 0), Math.atan(1.0 / 6.0))
h.define_singleton_method(:mst_pile_geometry) { |_d| { 'd' => 1016.0, 't' => 16.0, 'l' => 30.0, 'top' => 1.2, 'rot' => rot, 'r' => 1.0 / 6.0 } }
g = h.add_pile(ents, {}, 12.0, 34.0, 'P-1')
o = g.transformation.origin.to_a.map { |v| (v / INCH).round(6) }
t('Group kazık: orijin = (x, y, üst kot) — eğik kazıkta da', o, [12.0, 34.0, 1.2])
t('pipe: daireler yerel ORIGIN merkezli (z=0 = kazık üstü)', g.entities.circles.map { |c, _| c }.uniq, [[0.0, 0.0, 0.0]])
t('pipe: aşağı doğru itilir (pushpull negatif)', $pushpull < 0, true)
t('Component kazık: tr = translation(x,y,top) * rot (orijin kazık başı)', !!(main =~ /tr=Geom::Transformation\.translation\(\[m\(x\),m\(y\),m\(gm\['top'\]\)\]\)\n tr=tr\*gm\['rot'\]/), true)

# ---- BK: L=10 m, ana gövde tabanı +1.00, üst +2.00; SON uçta diş 1.50 / eğim 0.30 / derinlik 0.50; 30° döndürülmüş
def bk(attrs = {}, kind = Sketchup::Group)
  b = kind.new(100, { 'element_type' => 'head_beam', 'length_m' => 10.0, 'width_m' => 1.2, 'height_m' => 1.0,
                      'bottom_elevation_m' => 1.0, 'top_elevation_m' => 2.0,
                      'end_tooth_enabled' => '1', 'end_tooth_length_m' => 1.5, 'end_tooth_slope_m' => 0.3, 'end_tooth_depth_m' => 0.5 }.merge(attrs))
  b.transformation = Geom::Transformation.translation([5.0.m, 7.0.m, 1.0.m]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, Math::PI / 6)
  b.parent = :ano
  b
end
def pile_at(b, a, top = 1.2, extra = {})
  p = Sketchup::Group.new(200 + (a * 100).round, { 'pile_id' => "P@#{a}", 'top_elevation_m' => top, 'diameter_mm' => 1016.0 }.merge(extra))
  p.transformation = b.transformation * Geom::Transformation.translation([a.m, 0.6.m, 0.2.m])   # BK ekseninde, BK başından a m
  p.parent = :ano
  p
end
A = Math::PI / 4.0 * 1.016**2
b = bk
$piles = [pile_at(b, 9.5)]
v = h.mst_bk_pile_embed(b)[:volume_m3]
obs('K50 örnek (düz diş bölgesi a=9.5, kazık üstü ana tabandan +0.2, diş 0.5) hacim', v.round(4))
t('K50: düşüm = A·(0.2+0.5) = 0.5675 m³ (0.51.4: 0.1621)', near(v, A * 0.7, 1e-6), true)
$piles = [pile_at(b, 8.65)]
t('K50: eğimli geçişte (a=8.65; derinlik 0.5·0.15/0.30=0.25) düşüm A·0.45', near(h.mst_bk_pile_embed(b)[:volume_m3], A * 0.45), true)
$piles = [pile_at(b, 5.0)]
t('K50: diş dışında (a=5) değişmez A·0.2 = 0.1621', near(h.mst_bk_pile_embed(b)[:volume_m3], A * 0.2), true)
$piles = [pile_at(b, 9.5, 0.8)]
t('K50: kazık üstü ana tabanın altında ama dişte (top 0.8 → gömülme 0.3)', near(h.mst_bk_pile_embed(b)[:volume_m3], A * 0.3), true)
# taban bölgesi (bottom_zones_json) 3–5 m, derinlik 0.4, eğim 0.5
bz = bk('bottom_zones_json' => JSON.generate([{ 'a0' => 3.0, 'a1' => 5.0, 'depth' => 0.4, 'slope' => 0.5 }]))
$piles = [pile_at(bz, 4.0)]
t('K50: taban bölgesi düz kısmı (a=4, dz 0.4) düşüm A·0.6', near(h.mst_bk_pile_embed(bz)[:volume_m3], A * 0.6), true)
$piles = [pile_at(bz, 3.25)]
t('K50: taban bölgesi eğimi (a=3.25 → 0.2) düşüm A·0.4', near(h.mst_bk_pile_embed(bz)[:volume_m3], A * 0.4), true)
# uç dişine taşan bölge geometriye girmez (recess_profile_points) → derinlik 0
bo = bk('bottom_zones_json' => JSON.generate([{ 'a0' => 8.0, 'a1' => 9.5, 'depth' => 0.9, 'slope' => 0.0 }]))
$piles = [pile_at(bo, 6.0), pile_at(bo, 8.2)]
t('K50: uç dişine taşan bölge sayılmaz (geometride yok)', near(h.mst_bk_pile_embed(bo)[:volume_m3], A * 0.2 * 2), true)
# eğik kazık: hacim A·emb·√(1+r²)
$piles = [pile_at(b, 9.5, 1.2, 'orientation_mode' => 'BATTERED', 'batter_ratio' => '1/6')]
t('K50: eğik kazık √(1+r²) çarpanı korunur', near(h.mst_bk_pile_embed(b)[:volume_m3], A * 0.7 * Math.sqrt(1 + 1.0 / 36)), true)
# Component BK / farklı kap → derinlik 0 (eski kural)
bc = bk({}, Sketchup::ComponentInstance)
$piles = [pile_at(bc, 9.5)]
t('K50: Component BK → eski kural (A·0.2)', near(h.mst_bk_pile_embed(bc)[:volume_m3], A * 0.2), true)
pp = pile_at(b, 9.5); pp.parent = :baska
$piles = [pp]
t('K50: kazık BK ile aynı kapta değil → eski kural', near(h.mst_bk_pile_embed(b)[:volume_m3], A * 0.2), true)
bm2 = bk('head_beam_mode' => 'multi_axis')
$piles = [pile_at(bm2, 9.5)]
t('K50: çok akslı (kutu) BK → eski kural', near(h.mst_bk_pile_embed(bm2)[:volume_m3], A * 0.2), true)
# zone_info çıktısı değişmedi
zi = h.mst_hb_zone_info(h.mst_attr_hash(bz), 10.0)
t('mst_hb_zone_info çıktısı aynı biçim', [zi['base'], zi['zones'].map { |q| [q['kind'], q['a0'], q['f0'], q['f1'], q['a1']] }],
  [0.5, [['end', 8.5, 8.8, 10.0, 10.0], ['zone', 3.0, 3.5, 4.5, 5.0]]])
a1_finish
