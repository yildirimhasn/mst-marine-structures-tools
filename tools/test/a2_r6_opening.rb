# A2 / 08-R6 (alt kalip kapaliyken kazik acikligi dusulmez) ve egik kazik acikligi elips (pi/4*d*d/cos).
# Kullanim: ruby tools/test/a2_r6_opening.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
class Host
  def face_area_m2(f); f.area_m2; end
  def mst_vk_contact_m2(_g); 0.0; end
  def mst_hb_culvert_form_deduct(_g); 0.0; end
end
A1.load(Host, main, 'def mst_hb_ents(', 'def head_beam_formwork_area(', 'def head_beam_pile_opening_area(', 'def head_beam_gross_formwork_area(',
        'def head_beam_net_formwork_area(', 'def pile_batter_ratio(')
ELL = A1.load_opt(Host, main, 'def mst_pile_opening_m2(') & A1.load_opt(Host, main, 'def mst_pile_opening_ratio(')
obs('mst_pile_opening_m2 tanımlı', ELL)
h = Host.new
D = A1::DICT
def face(type, fw, area)
  f = Sketchup::Face.new(rand(1_000_000), 'formwork_type' => type, 'formwork' => fw); f.area_m2 = area; f
end
# BK 10 × 1.2 × 1.0: alt 12, uzun yüzler 2×10, uçlar 2×1.2; 3 × Ø1016 açıklık 2.432 m²
OPEN = 3 * Math::PI / 4 * 1.016**2
def bk(bottom_fw)
  b = Sketchup::Group.new(1, 'element_type' => 'head_beam', 'pile_opening_area_m2' => OPEN)
  b.entities = [face('BOTTOM', bottom_fw, 12.0), face('LONG_SIDE', true, 10.0), face('LONG_SIDE', true, 10.0), face('END_FACE', true, 1.2), face('END_FACE', true, 1.2),
                face('TOP_OR_CONTACT', false, 12.0)]
  b
end
on = bk(true); off = bk(false)
obs('alt kalıp AÇIK: brüt / açıklık / net', [h.head_beam_gross_formwork_area(on).round(3), h.head_beam_pile_opening_area(on).round(3), h.head_beam_net_formwork_area(on).round(3)])
obs('alt kalıp KAPALI: brüt / açıklık / net', [h.head_beam_gross_formwork_area(off).round(3), h.head_beam_pile_opening_area(off).round(3), h.head_beam_net_formwork_area(off).round(3)])
t('08-R6: alt kalıp açık → net = 34.4 − 2.432 = 31.968 (değişmez)', h.head_beam_net_formwork_area(on).round(3), 31.968)
t('08-R6: alt kalıp kapalı → açıklık düşülmez, net = brüt 22.4 (0.51.4: 19.968)', h.head_beam_net_formwork_area(off).round(3), 22.4)
mixed = bk(true); mixed.entities << face('BOTTOM', false, 1.0)
t('08-R6: alt yüzlerin bir kısmı kalıpta → eski kural (açıklık düşülür; bilinen sınır)', h.head_beam_pile_opening_area(mixed).round(3), OPEN.round(3))
legacy = Sketchup::Group.new(2, 'element_type' => 'head_beam', 'pile_opening_area_m2' => OPEN); legacy.entities = []
t('08-R6: yüzü sınıflanmamış (BOTTOM yok) eski BK → kayıtlı açıklık', h.head_beam_pile_opening_area(legacy).round(3), OPEN.round(3))
if ELL
  circ = Math::PI / 4 * 1.016**2
  t('elips: düşey kazık daire 0.810732', h.mst_pile_opening_m2(1016.0, 0.0).round(6), circ.round(6))
  e16 = circ * Math.sqrt(1 + 1.0 / 36)
  obs('elips 1:6 eğik Ø1016 (π/4·d·d/cosθ, cosθ=6/√37)', e16.round(6))
  t('elips: 1:6 eğik kazık 0.821915 (0.51.4: 0.810732)', h.mst_pile_opening_m2(1016.0, 1.0 / 6).round(6), e16.round(6))
  pb = Sketchup::Group.new(5, 'orientation_mode' => 'BATTERED', 'batter_ratio' => '1/6')
  pv = Sketchup::Group.new(6, 'orientation_mode' => 'VERTICAL', 'batter_ratio' => '1/6')
  t('elips: oran yalnız BATTERED kazıkta', [h.mst_pile_opening_ratio(pb).round(6), h.mst_pile_opening_ratio(pv)], [(1.0 / 6).round(6), 0.0])
else
  t('elips işlevi var', false, true)
end
# BK oluşturma ve kazık çapı değişimi yollarında elips formülü kullanılıyor mu (statik)
t('create_head_beam_for_piles + çok akslı: elips (2 yer)', main.scan('pile_opening_area=piles.sum{|pi|mst_pile_opening_m2(').length, 2)
t('kazık çapı değişince açıklık: elips', main.include?('open_new=d_after.each_with_index.sum{|dmm,i|mst_pile_opening_m2(dmm,r_after[i])}'), true)
a1_finish
