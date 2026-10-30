# Parti B / K22 asama 1 (dondurulmus BK: prekast olusturulmaz, mevcut prekasta uyari), K23 (olcekli / aynali donusum uyarisi),
# K10 ara cozum (BK'si degisen VK/BBK uyarisi), K54 (PV dis < oturma uyarisi; G1), K21 (S7/S8 gorunur hata), K18 (formwork_net_error).
# Kullanim: ruby tools/test/b_audit_k22_k23_k10_k54.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')
D = A1::DICT
class Host
  def element_visible_id(e); e.get_attribute(DICT, 'id', "PID-#{e.persistent_id}").to_s; end
  def mst_boq_info_rows(_a = nil); []; end
  def mst_bk_pile_embed(_b); { items: [] }; end
  def mst_pile_rebar_active(_e); false; end
  def mst_collect_toppings(_e); []; end
  def pile_bim_qto_item(p); raise 'kesit verisi eksik' if p.get_attribute(DICT, 'broken', false); {}; end
  def accessory_rows; raise 'aksesuar kaydı okunamadı' if $acc_broken; []; end
end
NEW = %w[mst_bk_span_frame_error mst_audit_v0515 mst_tr_scale_info mst_pv_tooth_seat_warnings].map { |f| A1.load_opt(Host, main, "def #{f}(") }.all?
obs('K22 / K23 / K54 işlevleri tanımlı', NEW)
if NEW
  a2_const(Host, main, 'MST_AUDIT_ERROR_FLAGS')
  A1.load(Host, A1.src('mst_rebar_tools.rb'), 'def mst_rt_world_tr(')
  A1.load(Host, bm, 'def mst_vk_support_state(')
  %w[mst_topping_parent_deck mst_uid_owner].each { |f| A1.load(Host, A1.src('dependency_rebuild.rb'), "def #{f}(") }
end
h = Host.new
rot = ->(deg) { Geom::Transformation.rotation(ORIGIN, Z_AXIS, deg * Math::PI / 180.0) }
mk_bk = lambda do |pid, deg, ox, l = 20.0, w = 1.2, rev = 0, top = 3.0|
  tr = Geom::Transformation.translation([ox * INCH, 0, 0]) * rot.(deg)
  b = Sketchup::Group.new(pid, 'element_type' => 'head_beam', 'id' => "BK-#{pid}", 'width_m' => w, 'length_m' => l, 'bk_revision_no' => rev, 'top_elevation_m' => top)
  b.transformation = tr; b.bounds = b_world_bounds([0, 0, 0], [l, w, 1.0], tr); b
end

# ------------------------------------------------------------------ K22
std1 = mk_bk.(1, 90, 0); std2 = mk_bk.(2, 90, 12)        # BK ekseni model Y (standart yapi)
multi = mk_bk.(3, 0, 30, 6.0, 4.0)                        # cok aksli BK: yerel X = model X (90° kati)
r1 = mk_bk.(4, 120, 0); r2 = mk_bk.(5, 120, 12)           # yapi 30° dondurulmus
tiny = mk_bk.(6, 90.005, 0)                                # 0,005°: sinir kutusu fazlasi < 5 mm
nowid = mk_bk.(7, 90, 0, 20.0, 0.0)
if NEW
  t('K22 döndürülmemiş yapı (BK ∥ model Y): hata yok → 0.51.4 ile aynı yol', [std1, std2, multi, tiny, nowid].map { |b| h.mst_bk_span_frame_error(b) }, [nil, nil, nil, nil, nil])
  m = h.mst_bk_span_frame_error(r1)
  obs('K22 30° döndürülmüş BK iletisi', m)
  t('K22 30° döndürülmüş yapı: Türkçe hata, açı 30.0°, prekast oluşturulmaz', [m.to_s.include?('30.0° döndürülmüş'), m.to_s.end_with?('Prekast oluşturulmadı.')], [true, true])
  t('K22 genişlik kaydı yoksa yalnız 90° katı olmayan açı hata', h.mst_bk_span_frame_error(mk_bk.(8, 120, 0, 20.0, 0.0)).nil?, false)
end
t('K22 (statik) 4 çağrı noktası: düz / vinç prekast, boy uyarlama, kanal adayı', [
  b_slice(main, 'def create_flat_precast', 'def sync_precast_to_head_beams').include?('mst_bk_span_frame_error(lb) || mst_bk_span_frame_error(rb)'),
  b_slice(main, 'def create_crane_precast', 'def create_deck_curbs').include?('mst_bk_span_frame_error(lb) || mst_bk_span_frame_error(rb)'),
  b_slice(main, 'def mst_precast_resize_plan', "[{'element'=>dep").include?('return [nil,er] if er'),
  b_slice(main, 'def mst_kn_place_plan', 'def mst_kn_preview_text').include?('warns << "#{span}: #{er}";next')], [true, true, true, true])
# 0.51.4 karsilastirmasi: dondurulmus yapida sinir kutusundan olculen aciklik (uyarisiz)
clr = ->(a, b) { (b.bounds.min.x - a.bounds.max.x) / INCH }
obs('K22 0.51.4 sınır kutusu açıklığı: standart / 30° döndürülmüş (m)', [clr.(std1, std2).round(3), clr.(r1, r2).round(3)])

# ------------------------------------------------------------------ Model Kontrolu
a1_reset!
pd_ok = Sketchup::Group.new(20, 'element_type' => 'flat_precast', 'id' => 'PD-1', 'support_left_pid' => 1, 'support_right_pid' => 2); pd_ok.transformation = Geom::Transformation.new
pd_rot = Sketchup::Group.new(21, 'element_type' => 'flat_precast', 'id' => 'PD-2', 'support_left_pid' => 4, 'support_right_pid' => 5); pd_rot.transformation = rot.(30)
sc = Sketchup::Group.new(22, 'element_type' => 'curb', 'id' => 'TR-S'); sc.transformation = Geom::Transformation.scaling(1.2, 1, 1)
mir = Sketchup::Group.new(23, 'element_type' => 'curb', 'id' => 'TR-M'); mir.transformation = Geom::Transformation.scaling(-1, 1, 1)
outer = Sketchup::Group.new(24, {}); outer.transformation = Geom::Transformation.scaling(1, 1, 1.5)
odef = Sketchup::ComponentDefinition.new(25); odef.instances << outer
nest = Sketchup::Group.new(26, 'element_type' => 'curb', 'id' => 'TR-N'); nest.transformation = Geom::Transformation.new; nest.parent = odef
plain = Sketchup::Group.new(27, 'element_type' => 'curb', 'id' => 'TR-0'); plain.transformation = rot.(45)
vk_b = mk_bk.(30, 90, 40); vk_b2 = mk_bk.(31, 90, 50)
vk = Sketchup::Group.new(32, 'element_type' => 'head_beam', 'beam_role' => 'VK', 'id' => 'VK-01'); vk.transformation = Geom::Transformation.new
vk2 = Sketchup::Group.new(33, 'element_type' => 'head_beam', 'beam_role' => 'BBK', 'id' => 'BBK-01'); vk2.transformation = Geom::Transformation.new
if NEW
  vk.set_attribute(D, 'link_support_state_json', JSON.generate([h.mst_vk_support_state(vk_b), h.mst_vk_support_state(vk_b2)]))
  vk2.set_attribute(D, 'link_support_state_json', JSON.generate([h.mst_vk_support_state(vk_b2), [999, 0, 3.0, 0, 0]]))
end
vk_b.set_attribute(D, 'bk_revision_no', 1); vk_b.set_attribute(D, 'top_elevation_m', 3.25)   # VK olusturulduktan sonra BK revize
pv = Sketchup::Group.new(40, 'element_type' => 'crane_precast', 'id' => 'PV-01', 'extra_depth_m' => 0.4, 'width_m' => 1.0, 'left_tooth_m' => 0.10, 'right_tooth_m' => 0.20, 'seat_left_m' => 0.15, 'seat_right_m' => 0.15)
pv.transformation = Geom::Transformation.new
pile = Sketchup::Group.new(41, 'element_type' => 'steel_pipe_pile', 'id' => 'P-1', 'broken' => true); pile.transformation = Geom::Transformation.new
fw = Sketchup::Group.new(42, 'element_type' => 'head_beam', 'id' => 'BK-F', 'formwork_net_error' => 'yüz okunamadı'); fw.transformation = Geom::Transformation.new
$acc_broken = true
all = [std1, std2, r1, r2, pd_ok, pd_rot, sc, mir, nest, plain, vk_b, vk_b2, vk, vk2, pv, pile, fw]
out = NEW ? h.mst_audit_v0515(all, all) : []
out.each { |x| obs('Model Kontrolü', [x[0], x[2], x[3][0, 120]]) }
sel = ->(s) { out.select { |x| x[3].include?(s) }.map { |x| x[1] && x[1].persistent_id } }
t('K22 Model Kontrolü: döndürülmüş BK\'lara dayanan mevcut prekast UYARI, standart olan yok', sel.('Bu prekastın boyu ve metrajı yanlış olabilir'), [21])
t('K23 ölçekli (X×1.2), aynalı ve ölçekli üst grup içindeki eleman UYARI; döndürülmüş ölçeksiz yok', sel.('dönüşüm zincirinde ölçek').sort, [22, 23, 26])
t('K23 mesajı ölçek değerini taşır', out.find { |x| x[1] && x[1].persistent_id == 26 }.to_a[3].to_s.include?('Z×1.5000'), true)
t('K10 BK revize + kot değişti → VK UYARI; bulunamayan destek BK → BBK UYARI', [sel.('oluşturulduktan sonra değişti'), sel.('modelde bulunamadı')], [[32], [33]])
t('K10 mesajı değişikliği yazar (RV-00 → RV-01, üst kot)', out.find { |x| x[3].include?('oluşturulduktan sonra değişti') }.to_a[3].to_s.include?('revizyon RV-00 → RV-01, üst kot 3.000 → 3.250 m'), true)
t('K54 PV sol diş 0.10 < oturma 0.15: UYARI (kesişim 1.0×0.4×0.05 = 0.020 m³); sağ diş 0.20 uyarı yok', out.select { |x| x[2] == 'Prekast Metrajı' }.map { |x| x[3][/(sol|sağ) diş/] + ' ' + x[3][/\(([\d.]+) m³\)/, 1].to_s }, ['sol diş 0.020'])
t('K21 kazık imalat / iç beton hesabı hatası HATA (sessiz 0 değil)', out.select { |x| x[0] == 'ERROR' && x[3].include?('kazık imalat') }.map { |x| x[1].persistent_id }, [41])
t('K21 aksesuar listesi hatası HATA (ankraj 0 kg)', out.any? { |x| x[0] == 'ERROR' && x[3].include?('ankraj donatısı 0 kg') }, true)
t('K18 formwork_net_error UYARI (Hesap Hatası)', out.any? { |x| x[0] == 'WARNING' && x[2] == 'Hesap Hatası' && x[3].include?('Net kalıp alanı güncellenemedi') }, true)

# ------------------------------------------------------------------ K54 G1: PV profili (gercek kurucu)
class FFace; attr_reader :pts; def initialize(p); @pts = p; end; def normal; Geom::Vector3d.new(0, 1, 0); end; def reverse!; end; def pushpull(_d); end; end
class FEnts; attr_reader :faces; def initialize; @faces = []; end; def add_face(pts); f = FFace.new(pts); @faces << f; f; end; end
A1.load(Host, main, 'def build_crane_precast_solid(')
fe = FEnts.new
h.build_crane_precast_solid(fe, 6.0 * INCH, 1.0, 0.30, 0.40, 0.10, 0.20)
deep = fe.faces[0].pts.select { |p| p.z < -1e-9 }.map { |p| p.x / INCH }
obs('K54 G1 derin bölüm x aralığı (m, prekast yerel)', [deep.min.round(3), deep.max.round(3)])
t('K54 G1: derin orta bölüm sol dişten (0.10 m) başlıyor; oturma 0.15 m → 0.05 m BK gövdesinde (yeniden üretildi)', [deep.min.round(3), (0.15 - deep.min).round(3)], [0.1, 0.05])
t('K54 (statik) 0.51.4 vinç prekastında diş–oturma kontrolü yok; yenide yalnız uyarı (geometri değişmez)',
  b_slice(main, 'def create_crane_precast', 'def create_deck_curbs').include?('mst_pv_tooth_seat_warnings'), true)
a1_finish
