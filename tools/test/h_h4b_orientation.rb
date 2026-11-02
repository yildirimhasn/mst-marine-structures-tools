# Parti H / H4b: kazık yönelimi değişince bağlı BK'nın kayıtlı kazık açıklığı (eğik kazıkta elips, BK oluşturma formülü)
# ve net kalıbı aynı işlemde güncellenir; commit_with_dependencies; seçim hatasında abort yok. METRAJI DEĞİŞTİRİR (kalıp).
# Kullanim: ruby tools/test/h_h4b_orientation.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')
D = A1::DICT
module Geom
  class Vector3d
    def cross(o); Vector3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x); end
    def angle_between(o); Math.acos([[(x * o.x + y * o.y + z * o.z) / (length * o.length), 1.0].min, -1.0].max); end
  end
end
class FakeModel
  def find_entity_by_persistent_id(pid); ($all_ents || {})[pid]; end
  def active_view; o = Object.new; def o.invalidate; end; o; end
end
class FakeSel < Array; def to_a; Array.new(self); end; end
class Host
  def face_area_m2(f); f.area_m2; end
  def mst_vk_contact_m2(_g); 0.0; end
  def mst_hb_culvert_form_deduct(_g); 0.0; end
end
A1.load(Host, main, 'def mst_hb_ents(', 'def head_beam_formwork_area(', 'def head_beam_pile_opening_area(', 'def head_beam_gross_formwork_area(',
        'def head_beam_net_formwork_area(', 'def pile_batter_ratio(', 'def pile_orientation(', 'def pile_rotation_transform(',
        'def apply_selected_pile_orientations(', 'def mst_pile_index_by_id', 'def mst_bk_connected_piles(', 'def mst_pile_ids_for_beam(')
NEW = A1.load_opt(Host, main, 'def mst_pile_opening_m2(') & A1.load_opt(Host, main, 'def mst_pile_opening_ratio(') &
      A1.load_opt(Host, main, 'def mst_pile_orientation_bk_openings!(') & A1.load_opt(Host, bm, 'def mst_bk_set_net_formwork!(')
t('H4b yardımcılar tanımlı (mst_pile_orientation_bk_openings!, mst_bk_set_net_formwork!)', NEW, true)
h = Host.new
CIRCLE = Math::PI / 4 * 1.016**2
ELLIPSE = CIRCLE * Math.sqrt(1 + 1.0 / 36)
def face(type, fw, area); f = Sketchup::Face.new(rand(1_000_000), 'formwork_type' => type, 'formwork' => fw); f.area_m2 = area; f; end
def faces; [face('BOTTOM', true, 12.0), face('LONG_SIDE', true, 10.0), face('LONG_SIDE', true, 10.0), face('END_FACE', true, 1.2), face('END_FACE', true, 1.2), face('TOP_OR_CONTACT', false, 12.0)]; end
def pile(pid, id, extra = {})
  p = Sketchup::Group.new(pid, { 'element_type' => 'steel_pipe_pile', 'pile_id' => id, 'diameter_mm' => 1016.0, 'length_m' => 30.0, 'top_elevation_m' => 1.2 }.merge(extra))
  p.transformation = Geom::Transformation.translation([5.m, 2.m, 1.2.m]); p
end
def build
  a1_reset!
  p1 = pile(1001, 'P1'); p3 = pile(1003, 'P3')
  bk = Sketchup::Group.new(4001, 'element_type' => 'head_beam', 'head_beam_id' => 'BK1', 'connected_pile_persistent_ids' => '1001,1003', 'connected_pile_ids' => 'P1,P3',
                                 'pile_opening_area_m2' => 2 * CIRCLE, 'formwork_net_area_m2' => 34.4 - 2 * CIRCLE)
  bk.entities = faces
  bk2 = Sketchup::Group.new(4002, 'element_type' => 'head_beam', 'head_beam_id' => 'BK2', 'connected_pile_persistent_ids' => '1003,1999', 'connected_pile_ids' => 'P3,PX',
                                  'pile_opening_area_m2' => 2 * CIRCLE)
  bk2.entities = faces
  bk3 = Sketchup::Group.new(4003, 'element_type' => 'head_beam', 'head_beam_id' => 'BK3', 'connected_pile_persistent_ids' => '1003')   # kayıtlı açıklık yok
  bk3.entities = faces
  $model.entities = [p1, p3, bk, bk2, bk3]
  $all_ents = $model.entities.map { |e| [e.persistent_id, e] }.to_h
  $log = []
  [p1, p3, bk, bk2, bk3]
end

if NEW
  p1, p3, bk, bk2, bk3 = build
  $model.selection = FakeSel.new([p3])
  n = h.apply_selected_pile_orientations('orientation_mode' => 'BATTERED', 'batter_ratio' => '1/6', 'azimuth_deg' => 0)
  t('H4b BK1 açıklık daire → daire + elips (0,810732 + 0,821915)', [n, bk.a('pile_opening_area_m2').round(6)], [1, (CIRCLE + ELLIPSE).round(6)])
  t('H4b beklenen fark +0,011183 m² (elips − daire)', (bk.a('pile_opening_area_m2') - 2 * CIRCLE).round(6), (ELLIPSE - CIRCLE).round(6))
  t('H4b BK1 net kalıp = brüt 34,4 − yeni açıklık', bk.a('formwork_net_area_m2').round(6), (34.4 - CIRCLE - ELLIPSE).round(6))
  t('H4b bağlı kazık listesi eşleşmeyen BK2 yazılmaz, uyarı', [bk2.a('pile_opening_area_m2').round(6), $msgs.last.to_s.include?('PID-4002: bağlı kazık listesi (2) modeldeki kazıklarla (1) eşleşmiyor')], [(2 * CIRCLE).round(6), true])
  t('H4b kayıtlı açıklığı olmayan BK3 yazılmaz (düşüm başlatılmaz)', [bk3.a('pile_opening_area_m2'), bk3.a('formwork_net_area_m2')], [nil, nil])
  t('H4b tek normal işlem: start → commit_with_dependencies → commit', [ops, $log.count { |x| x[0] == :cwd }, $model.open_ops], [[:start, :commit], 1, 0])
  t('H4b kazık yönelim öznitelikleri yazıldı', [p3.a('orientation_mode'), p3.a('batter_ratio').round(6)], ['BATTERED', (1.0 / 6).round(6)])

  p1, p3, bk, = build
  $model.selection = FakeSel.new([p1])
  h.apply_selected_pile_orientations('orientation_mode' => 'VERTICAL', 'batter_ratio' => '', 'azimuth_deg' => 0)
  t('H4b düşey → düşey: açıklık değişmez, BK yazılmaz', [bk.a('pile_opening_area_m2').round(6), sets.count { |x| x[1].equal?(bk) }], [(2 * CIRCLE).round(6), 0])

  build
  $model.selection = FakeSel.new([])
  r = begin; h.apply_selected_pile_orientations('orientation_mode' => 'BATTERED'); rescue => e; e.message; end
  t('H4b seçim yok: işlem açılmadan reddedilir (abort çağrılmaz)', [r, ops], ['SketchUp modelinde en az bir çelik boru kazık seçin.', []])

  p1, p3, bk, = build
  $model.selection = FakeSel.new([p3])
  class Host; alias_method :h4b_cwd, :commit_with_dependencies; def commit_with_dependencies(m); raise 'bağımlılık hatası' if $cwd_raise; h4b_cwd(m); end; end
  $cwd_raise = true
  r = begin; h.apply_selected_pile_orientations('orientation_mode' => 'BATTERED', 'batter_ratio' => '1/6'); rescue => e; e.message; end
  t('H4b işlem içi hata: abort, açık işlem yok', [r, ops, $model.open_ops], ['bağımlılık hatası', [:start, :abort], 0])
  $cwd_raise = false
end
a1_finish
