# KP3 (ADR-0515-K2, docs/duzeltme/37 K3, K5 — kullanıcı kararları 2, 6, 12, 13; 09.11.2026) — Kanal prekastı parti P3 (Ruby):
#  kot yöntemi (elevation_mode TOP | POCKET | MANUAL, elevation_ref_m, elevation_ref_face TOP | BOTTOM), cep bağı
#  (seat_bk_left_uid / seat_bk_right_uid + taraf), channel_top_ref (tipte seçilen üst yüzey), salt okuma kot önizlemesi
#  (pk_elevation_preview → mstPkElevation), BK cebi değişince POCKET modlu PK'nın cebe yeniden oturması (transparent işlem, abort yok),
#  eski model (anahtar yok → TOP, önceki kot birebir).
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir. Kanıt düzeyi: sahte nesne. SketchUp içinde gerçek Geri Al zinciri, dönük / iç içe
#  BK cep kutusu, Component yer değiştirmesi KANITLANMAZ.
# Kullanim: ruby tools/test/kp3_pk_elevation.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kp3_pk_elevation.rb <marine_structures_tools klasoru>'
DIR = File.expand_path(dir)
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(DIR, 'main.rb')
$stderr = $stderr_keep
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze unless defined?(D)
IN = 39.37007874015748

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 300]} (beklenen #{exp.inspect[0, 300]})"
end
def near(a, b, eps = 1e-9); !a.nil? && !b.nil? && (a.to_f - b.to_f).abs <= eps; end

# sahte geometri (kp2_pk_catalog.rb ile aynı)
class Sketchup::Material; attr_accessor :color; end
class Sketchup::Entity
  def transform!(tr); raise 'sahte dönüşüm hatası' if $transform_fail; @transformation = tr * @transformation; self; end
end
# start_operation'ın tüm bağımsız değişkenleri (transparent bayrağı) kaydedilir
class Sketchup::Model
  def start_operation(*a); @ops << [:start, a[0]]; ($op_args ||= []) << a; true; end
end
class FakeColl < Sketchup::Entities
  def initialize(kind); super(); @kind = kind; end
  def [](k); k.is_a?(String) ? find { |x| x.name == k } : super; end
  def add(name); x = @kind.new(nil, {}); x.name = name; x.entities.parent = x if x.respond_to?(:entities); push(x); x; end
end
class FakeFace < Sketchup::Face
  def initialize(ents, pts)
    super(nil, {})
    @ents = ents; @pts = pts.map { |p| p.to_a.map(&:to_f) }
    nx = 0.0; ny = 0.0; nz = 0.0
    @pts.each_with_index do |a, i|
      b = @pts[(i + 1) % @pts.length]
      nx += (a[1] - b[1]) * (a[2] + b[2]); ny += (a[2] - b[2]) * (a[0] + b[0]); nz += (a[0] - b[0]) * (a[1] + b[1])
    end
    l = Math.sqrt(nx * nx + ny * ny + nz * nz)
    @normal = Geom::Vector3d.new(nx / l, ny / l, nz / l)
    @area_in2 = l / 2.0
    @bounds = Geom::BoundingBox.new.add(@pts.map { |p| Geom::Point3d.new(*p) })
  end
  def reverse!; @pts.reverse!; @normal = @normal.reverse; self; end
  def pushpull(d)
    yz = @pts.map { |p| [p[1], p[2]] }
    sa = 0.0; yz.each_with_index { |a, i| b = yz[(i + 1) % yz.length]; sa += a[0] * b[1] - b[0] * a[1] }
    yz.reverse! if sa < 0
    @ents.delete(self)
    mk = lambda do |normal, area_in2, pts|
      f = Sketchup::Face.new(nil, {}); f.normal = Geom::Vector3d.new(*normal); f.instance_variable_set(:@area_in2, area_in2)
      f.bounds = Geom::BoundingBox.new.add(pts.map { |p| Geom::Point3d.new(*p) }); f.parent = @ents; @ents << f; f
    end
    mk.([-1, 0, 0], sa.abs / 2.0, yz.map { |y, z| [0.0, y, z] })
    mk.([1, 0, 0], sa.abs / 2.0, yz.map { |y, z| [d, y, z] })
    yz.each_with_index do |a, i|
      b = yz[(i + 1) % yz.length]; dy = b[0] - a[0]; dz = b[1] - a[1]; len = Math.sqrt(dy * dy + dz * dz)
      mk.([0, dz / len, -dy / len], len * d, [[0.0, a[0], a[1]], [d, b[0], b[1]]])
    end
    nil
  end
end
class Sketchup::Entities
  def kp1_owner; parent.is_a?(Sketchup::Group) ? parent.definition : parent; end
  def add_group; g = Sketchup::Group.new(nil, {}); push(g); g.parent = kp1_owner; ($all_ents ||= {})[g.persistent_id] = g; g; end
  def add_face(*pts); pts = pts[0] if pts.length == 1; f = FakeFace.new(self, pts); push(f); f.parent = self; f; end
  def add_instance(defn, tr)
    i = Sketchup::ComponentInstance.new(nil, {}); i.definition = defn; i.transformation = tr; push(i); i.parent = kp1_owner
    ($all_ents ||= {})[i.persistent_id] = i
  end
  def clear!; clear; end
  def add(x); push(x); end
end
class Sketchup::Group
  def erase!; @erased = true; pr = parent; (pr.is_a?(Sketchup::Entities) ? pr : pr.entities).delete(self); end
end
$model.materials = FakeColl.new(Sketchup::Material)
$model.layers = FakeColl.new(Sketchup::Layer)
$model.definitions = FakeColl.new(Sketchup::ComponentDefinition)
def fresh_model
  $model.entities = Sketchup::Entities.new; $model.entities.parent = $model
  $model.selection = Sketchup::Entities.new
  $model.ops.clear; $op_args = []
  $model.set_attribute(D, 'precast_type_library_json', '[]')
  $all_ents = {}; $ui_msgs = []; $transform_fail = false
end
def put(e); $model.entities << e; e.parent = $model.entities; ($all_ents ||= {})[e.persistent_id] = e; e; end
# Y yönünde BK (yerel X = boy → dünya Y): başlangıç cebi Y 2,00–3,24, derinlik dep (cep tabanı = üst − dep)
def bk_y(pid, x0, x1, top = 3.0, dep = 0.8, off = 2.0, seat = true)
  a = { 'element_type' => 'head_beam', 'element_uid' => "BK-U#{pid}", 'head_beam_id' => "BK#{pid}", 'top_elevation_m' => top, 'height_m' => 1.0, 'width_m' => x1 - x0, 'length_m' => 10.0 }
  a.merge!('start_seat_enabled' => '1', 'start_seat_offset_m' => off, 'start_seat_length_m' => 1.24, 'start_seat_depth_m' => dep) if seat
  b = Sketchup::Group.new(pid, a)
  b.transformation = Geom::Transformation.new([[0, -1, 0], [1, 0, 0], [0, 0, 1]], [x1 * IN, 0, (top - 1.0) * IN])
  b.bounds = Geom::BoundingBox.new([x0 * IN, 0, (top - 1.0) * IN], [x1 * IN, 10 * IN, top * IN])
  put(b)
end
def attrs(e); h = {}; e.attribute_dictionary(D, false)&.each_pair { |k, v| h[k] = v }; h; end
def pks; a = []; M.collect_elements($model.entities, a); a.select { |e| e.get_attribute(D, 'element_type') == 'channel_precast' }; end

HAVE = %i[mst_pk_elev_opts mst_pk_elev_target mst_pk_top_ref mst_pk_elevation_preview mst_pk_send_elevation mst_pk_reseat_plan mst_pk_reseat_after_edit].all? { |s| M.respond_to?(s) }
t('P3 işlevleri tanımlı', HAVE, true)

dfl = M.mst_ch_default
sec_uu = M.mst_ch_preset(dfl, 'UU')                                   # sol / sağ 0,60, orta 0,30, taban 0,20
sec_l = M.mst_ch_preset(dfl.merge('total_width_m' => 1.0), 'L')       # sağ 0,60
LIB = [
  { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 },
  { 'uid' => 'pk1', 'family' => 'PK', 'name' => 'PK-U', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37' },
  { 'uid' => 'pk3', 'family' => 'PK', 'name' => 'PK-UU', 'section' => sec_uu, 'concrete' => 'C30/37' },
  { 'uid' => 'pk5', 'family' => 'PK', 'name' => 'PK-UUM', 'section' => sec_uu, 'channel_top_ref' => 'mid', 'concrete' => 'C30/37' }
].freeze

# ---------------------------------------------------------------- 1. kot girdisi + hedef kot
if HAVE
  o = M.mst_pk_elev_opts({})
  t('1.1 girdi yok → TOP, yazılmaz (given false)', [o['mode'], o['face'], o['ref_m'], o['given']], ['TOP', 'TOP', nil, false])
  o = M.mst_pk_elev_opts({ 'pk_elevation_mode' => 'manual', 'pk_elevation_ref_m' => '2,45', 'pk_elevation_ref_face' => 'bottom' }, 'pk_')
  t('1.2 önekli girdi (Prekast Yerleşimi): MANUAL, 2,45, BOTTOM', [o['mode'], o['ref_m'], o['face'], o['given']], ['MANUAL', 2.45, 'BOTTOM', true])
  o = M.mst_pk_elev_opts('elevation_mode' => 'XYZ', 'elevation_ref_face' => 'yan')
  t('1.3 tanınmayan mod / yüz → TOP / TOP, given false', [o['mode'], o['face'], o['given']], ['TOP', 'TOP', false])
  top0 = 3.0 + 0.3; oh = 0.8
  tg = M.mst_pk_elev_target(M.mst_pk_elev_opts({}), oh, top0)
  t('1.4 TOP: alt = üst − yükseklik (eski ifade, bit düzeyi), üst = PD üstü', [tg['ok'], tg['bottom'] == top0 - oh, tg['top'] == top0], [true, true, true])
  tg = M.mst_pk_elev_target(M.mst_pk_elev_opts('elevation_mode' => 'MANUAL', 'elevation_ref_m' => 3.4), oh, top0)
  t('1.5 MANUAL üst yüzey 3,40: alt 2,60', [tg['ok'], near(tg['bottom'], 2.6), tg['top']], [true, true, 3.4])
  tg = M.mst_pk_elev_target(M.mst_pk_elev_opts('elevation_mode' => 'MANUAL', 'elevation_ref_m' => 2.5, 'elevation_ref_face' => 'BOTTOM'), oh, top0)
  t('1.6 MANUAL alt yüzey 2,50: üst 3,30', [tg['ok'], tg['bottom'], near(tg['top'], 3.3)], [true, 2.5, true])
  tg = M.mst_pk_elev_target(M.mst_pk_elev_opts('elevation_mode' => 'MANUAL'), oh, top0)
  t('1.7 MANUAL kot yok → Türkçe hata', [tg['ok'], tg['errors'].join.include?('referans kotu')], [false, true])
  tg = M.mst_pk_elev_target(M.mst_pk_elev_opts('elevation_mode' => 'POCKET'), oh, top0, 2.2)
  t('1.8 POCKET: alt = cep tabanı 2,20, üst 3,00', [tg['ok'], tg['bottom'], near(tg['top'], 3.0)], [true, 2.2, true])
  tg = M.mst_pk_elev_target(M.mst_pk_elev_opts('elevation_mode' => 'POCKET'), oh, top0, nil)
  t('1.9 POCKET cep yok → Türkçe hata', [tg['ok'], tg['errors'].join.include?('kanal cebi')], [false, true])

  # ---------------------------------------------------------------- 2. channel_top_ref (karar 2, 12)
  t('2.1 tipte seçili açık çıkıntı (orta) kabul', M.mst_pk_top_ref({ 'channel_top_ref' => 'mid' }, sec_uu), 'mid')
  t('2.2 kapalı / bilinmeyen çıkıntı → nil (en yüksek açık çıkıntı)', [M.mst_pk_top_ref({ 'channel_top_ref' => 'mid' }, sec_l), M.mst_pk_top_ref({ 'channel_top_ref' => 'xx' }, sec_uu), M.mst_pk_top_ref({}, sec_uu)], [nil, nil, nil])
  g5 = M.mst_pk_geom(LIB[3], true); g3 = M.mst_pk_geom(LIB[2], true)
  t('2.3 mst_pk_geom: channel_top_ref orta → yükseklik taban + 0,30; seçimsiz en yüksek 0,80', [near(g5['oh'], 0.5), near(g3['oh'], 0.8)], [true, true])
end

# ---------------------------------------------------------------- 3. Prekast Yerleşimi (create_flat_precast)
def layout(rows, extra = {})
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
  l = bk_y(9101, 0.0, 1.0); r = bk_y(9102, 4.0, 5.0)
  $model.selection.push(l, r)
  data = { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(LIB), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '2.02',
           'channel_fw_inner' => '1', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }.merge(extra)
  r0 = M.create_flat_precast(data)
  [r0, pks[0], l, r]
end
ROWS_U = [{ 'type_uid' => 'pk1', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }].freeze
ok, pk, = layout(ROWS_U)
a = pk ? attrs(pk) : {}
t('3.1 TOP (girdi yok, eski davranış): alt = 3,30 − 0,80 (eski ifade), üst 3,30, yeni anahtar yazılmaz',
  [ok, a['bottom_elevation_m'] == (3.0 + 0.3) - M.mst_ch_u_height(0.6, 0.2), a['top_elevation_m'] == 3.0 + 0.3, (a.keys & %w[elevation_mode elevation_ref_m elevation_ref_face seat_bk_left_uid seat_bk_right_uid channel_top_ref])],
  [true, true, true, []])
if HAVE
  ok, pk, = layout(ROWS_U, 'pk_elevation_mode' => 'MANUAL', 'pk_elevation_ref_m' => '2.5', 'pk_elevation_ref_face' => 'BOTTOM')
  a = pk ? attrs(pk) : {}
  t('3.2 MANUAL alt yüzey 2,50: alt 2,50, üst 3,30; anahtarlar', [ok, a['bottom_elevation_m'], near(a['top_elevation_m'], 3.3), a['elevation_mode'], a['elevation_ref_m'], a['elevation_ref_face']],
    [true, 2.5, true, 'MANUAL', 2.5, 'BOTTOM'])
  ok, pk, = layout(ROWS_U, 'pk_elevation_mode' => 'MANUAL', 'pk_elevation_ref_m' => '3.4', 'pk_elevation_ref_face' => 'TOP')
  a = pk ? attrs(pk) : {}
  t('3.3 MANUAL üst yüzey 3,40: üst 3,40, alt 2,60', [ok, a['top_elevation_m'], near(a['bottom_elevation_m'], 2.6), a['elevation_ref_face']], [true, 3.4, true, 'TOP'])
  ok, pk, = layout(ROWS_U, 'pk_elevation_mode' => 'MANUAL')
  t('3.4 MANUAL kot yok: oluşturulmaz, işlem geri alınır, Türkçe neden', [ok, pk, $model.ops.map(&:first).last, $ui_msgs.last.to_s.include?('referans kotu')], [false, nil, :abort, true])
  ok, pk, l, r = layout(ROWS_U, 'pk_elevation_mode' => 'POCKET')
  a = pk ? attrs(pk) : {}
  t('3.5 POCKET: alt = cep tabanı 2,20, üst 3,00; cep bağı UID + taraf, destek PID korunur',
    [ok, near(a['bottom_elevation_m'], 2.2), near(a['top_elevation_m'], 3.0), a['elevation_mode'], a['seat_bk_left_uid'], a['seat_bk_left_side'], a['seat_bk_right_uid'], a['seat_bk_right_side'], a['support_left_pid'], a.key?('elevation_ref_m')],
    [true, true, true, 'POCKET', 'BK-U9101', 'start', 'BK-U9102', 'start', 9101, false])
  ok, pk, = layout(ROWS_U, 'pk_elevation_mode' => 'POCKET', 'pd_y_offset_m' => '5.0')
  t('3.6 POCKET, PK altında cep yok: oluşturulmaz, Türkçe neden', [ok, pk, $ui_msgs.last.to_s.include?('kanal cebi yok')], [false, nil, true])
  ok, pk, = layout([{ 'type_uid' => 'pk5', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }], 'pd_y_offset_m' => '0.5')
  a = pk ? attrs(pk) : {}
  t('3.7 channel_top_ref orta (TOP): orta çıkıntı üstü = PD üstü 3,30 → alt 2,80; üst kot = gerçek üst (alt + 0,80); anahtar yazılır',
    [ok, near(a['bottom_elevation_m'], 3.3 - 0.5), near(a['top_elevation_m'], 3.3 - 0.5 + 0.8), a['channel_top_ref']], [true, true, true, 'mid'])
  ok, pk, = layout([{ 'type_uid' => 'pk3', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }], 'pd_y_offset_m' => '0.5')
  a = pk ? attrs(pk) : {}
  t('3.8 U dışı seçimsiz (TOP): eski P1a kotu (alt = 3,30 − 0,80), channel_top_ref yazılmaz',
    [ok, a['bottom_elevation_m'] == (3.0 + 0.3) - M.mst_ch_height(sec_uu), a['top_elevation_m'] == 3.0 + 0.3, a.key?('channel_top_ref')], [true, true, true, false])
end

# ---------------------------------------------------------------- 4. KN cebe yerleştirme
if HAVE
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
  l = bk_y(9201, 0.0, 1.0); r = bk_y(9202, 4.0, 5.0)
  pd = Sketchup::Group.new(9203, 'element_type' => 'flat_precast', 'precast_id' => 'PD9203', 'support_left_pid' => 9201, 'support_right_pid' => 9202, 'joint_m' => 0.02, 'seat_each_side_m' => 0.15, 'project' => 'P1')
  pd.bounds = Geom::BoundingBox.new([0.85 * IN, 4.0 * IN, 2.7 * IN], [4.15 * IN, 5.0 * IN, 3.0 * IN]); put(pd)   # PD üstü 3,00 = cep tabanı 2,20 + PK-U 0,80
  kp = M.mst_kn_place_plan($model, nil, nil, nil)
  c0 = kp['cands'][0]
  t('4.1 KN plan TOP (girdi yok): alt = cep tabanı 2,20 (eski), elev yok', c0 && [near(c0['z0'], 2.2), c0['elev'], c0['type']['name']], [true, nil, 'PK-U'])
  kp = M.mst_kn_place_plan($model, nil, nil, nil, M.mst_pk_elev_opts('elevation_mode' => 'MANUAL', 'elevation_ref_m' => 3.5, 'elevation_ref_face' => 'TOP'))
  c1 = kp['cands'][0]
  t('4.2 KN plan MANUAL üst 3,50: alt 2,70, sağ cep kayıtlı', c1 && [near(c1['z0'], 2.7), c1['pocket_r'] && c1['pocket_r']['bk']], [true, r])
  kp = M.mst_kn_place_plan($model, nil, nil, nil, M.mst_pk_elev_opts('elevation_mode' => 'POCKET'))
  c2 = kp['cands'][0]
  inst = c2 && M.mst_kn_create_pk!(c2, $model, nil)
  a = inst ? attrs(inst) : {}
  t('4.3 KN POCKET: alt = cep tabanı, cep bağı UID + taraf, kn_from_pocket yazılmaya devam',
    [near(a['bottom_elevation_m'], 2.2), a['elevation_mode'], a['seat_bk_left_uid'], a['seat_bk_right_uid'], a['seat_bk_left_side'], a['kn_from_pocket']], [true, 'POCKET', 'BK-U9201', 'BK-U9202', 'start', 'BK9201:start'])
  inst0 = c0 && M.mst_kn_create_pk!(c0, $model, nil)
  t('4.4 KN TOP: yeni anahtar yazılmaz', inst0 && (attrs(inst0).keys & %w[elevation_mode seat_bk_left_uid seat_bk_right_uid]), [])
end

# ---------------------------------------------------------------- 5. kot önizlemesi (salt okuma)
class FakeDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; end; end
if HAVE
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
  l = bk_y(9301, 0.0, 1.0); r = bk_y(9302, 4.0, 5.0)
  $writes = []; $model.ops.clear
  pv = M.mst_pk_elevation_preview($model, [l, r], { 'elevation_mode' => 'POCKET', 'kod' => 'PK-U', 'ref_top_m' => 3.3 })
  t('5.1 önizleme POCKET: alt 2,20, üst 3,00, cep tabanı 2,20, uyarı yok; yazım / işlem yok',
    [pv['ok'], near(pv['alt_kot_m'], 2.2), near(pv['ust_kot_m'], 3.0), near(pv['cep_tabani_m'], 2.2), pv['uyarilar'], pv['mod'], $writes, $model.ops], [true, true, true, true, [], 'POCKET', [], []])
  pv = M.mst_pk_elevation_preview($model, [l, r], { 'kod' => 'PK-U', 'ref_top_m' => 3.4 })
  t('5.2 önizleme TOP (girdi yok), referans üst 3,40: alt 2,60; cebe oturmuyor uyarısı',
    [pv['ok'], pv['mod'], near(pv['alt_kot_m'], 2.6), pv['uyarilar'].join.include?('cebe oturmuyor')], [true, 'TOP', true, true])
  pv = M.mst_pk_elevation_preview($model, [l, r], { 'elevation_mode' => 'MANUAL', 'elevation_ref_m' => 2.1, 'elevation_ref_face' => 'BOTTOM', 'kod' => 'PK-UUM' })
  t('5.3 önizleme MANUAL alt 2,10 (orta üst yüzey): üst yüzey 2,60, gerçek üst 2,90; cep tabanının altında uyarısı',
    [pv['ok'], near(pv['referans_ust_kot_m'], 2.6), near(pv['ust_kot_m'], 2.9), pv['ust_yuzey'], pv['uyarilar'].join.include?('altında')], [true, true, true, 'mid', true])
  pv = M.mst_pk_elevation_preview($model, [l], { 'kod' => 'PK-U' })
  t('5.4 tek BK → Türkçe neden', [pv['ok'], pv['neden']], [false, 'Kot önizlemesi için iki BK seçin.'])
  pv = M.mst_pk_elevation_preview($model, [l, r], { 'kod' => 'YOK' })
  t('5.5 bilinmeyen tip → Türkçe neden', [pv['ok'], pv['neden'].to_s.include?('YOK')], [false, true])
  pv = M.mst_pk_elevation_preview($model, [l, r], { 'elevation_mode' => 'POCKET', 'section' => sec_uu, 'channel_top_ref' => 'mid' })
  t('5.6 önizleme form kesiti + üst yüzey seçimi: alt 2,20, üst yüzey 2,70', [pv['ok'], near(pv['alt_kot_m'], 2.2), near(pv['referans_ust_kot_m'], 2.7)], [true, true, true])
  $model.selection.push(l, r)
  dl = FakeDlg.new; $writes = []; $model.ops.clear
  M.mst_pk_send_elevation(dl, '{"elevation_mode":"POCKET","kod":"PK-U","ref_top_m":3.3}')
  pl = JSON.parse(dl.js[0].to_s[/mstPkElevation\((.*)\)\z/m, 1]) rescue nil
  t('5.7 pk_elevation_preview: korumalı JS çağrısı, yük, yazım / işlem yok',
    [dl.js[0].to_s.start_with?('window.mstPkElevation && mstPkElevation('), pl && pl['ok'], pl && near(pl['alt_kot_m'], 2.2), $writes, $model.ops], [true, true, true, [], []])
  dl = FakeDlg.new
  M.mst_pk_send_elevation(dl, 'bozuk{')
  pl = JSON.parse(dl.js[0].to_s[/mstPkElevation\((.*)\)\z/m, 1]) rescue nil
  t('5.8 bozuk girdi → Türkçe neden, hata yok', [pl && pl['ok'], pl && pl['neden'].to_s.empty?], [false, false])
end
src = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
t('5.9 show_dialog callback kaydı (pk_elevation_preview)', src.include?("add_action_callback('pk_elevation_preview')"), true)

# ---------------------------------------------------------------- 6. BK cebi değişince yeniden oturtma (karar 6)
def pk_seat(pid, mode, z0, y0 = 2.02, y1 = 3.22, extra = {})
  a = { 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => "PK#{pid}", 'support_left_pid' => 9401, 'support_right_pid' => 9402,
        'bottom_elevation_m' => z0, 'top_elevation_m' => z0 + 0.8 }
  a.merge!('elevation_mode' => mode, 'seat_bk_left_uid' => 'BK-U9401', 'seat_bk_left_side' => 'start', 'seat_bk_right_uid' => 'BK-U9402', 'seat_bk_right_side' => 'start') if mode
  e = Sketchup::Group.new(pid, a.merge(extra))
  e.bounds = Geom::BoundingBox.new([0.85 * IN, y0 * IN, z0 * IN], [4.15 * IN, y1 * IN, (z0 + 0.8) * IN]); put(e)
end
def reseat_setup(dep = 0.9, off = 2.0)
  fresh_model
  l = bk_y(9401, 0.0, 1.0, 3.0, dep, off); r = bk_y(9402, 4.0, 5.0, 3.0, dep, off)   # cep derinliği 0,80 → dep (taban 3,0 − dep)
  [l, r]
end
if HAVE
  l, r = reseat_setup
  pp = pk_seat(9411, 'POCKET', 2.2); pt = pk_seat(9412, 'TOP', 2.2); pm = pk_seat(9413, 'MANUAL', 2.2); po = pk_seat(9414, nil, 2.2)
  els = []; M.collect_elements($model.entities, els)
  plan = M.mst_pk_reseat_plan([l], els)
  t('6.1 plan: yalnız POCKET PK taşınır (dz −0,10 → cep tabanı 2,10); TOP / MANUAL / eski (anahtarsız) dokunulmaz',
    [plan['moves'].map { |m| m['e'] }, plan['moves'][0] && near(plan['moves'][0]['dz'], -0.1), plan['moves'][0] && near(plan['moves'][0]['bottom'], 2.1), plan['warnings']], [[pp], true, true, []])
  $model.ops.clear; $op_args = []; $ui_msgs = []
  res = M.mst_pk_reseat_after_edit([l], $model, true)
  t('6.2 uygulama: tek transparent işlem (start 4. bağımsız değişken true), commit, abort yok',
    [$model.ops.map(&:first), $op_args.map { |x| x[3] }, $model.ops.include?([:abort])], [%i[start commit], [true], false])
  t('6.3 PK kotu ve öznitelikleri: z dönüşümü −0,10 m, alt 2,10, üst 2,90; diğerleri yerinde',
    [near(pp.transformation.to_a[14], -0.1 * IN, 1e-6), near(pp.get_attribute(D, 'bottom_elevation_m'), 2.1), near(pp.get_attribute(D, 'top_elevation_m'), 2.9),
     [pt, pm, po].map { |e| e.transformation.identity? }, res['moved']], [true, true, true, [true, true, true], [pp]])
  t('6.4 sessiz kip, uyarı yok → ileti yok', $ui_msgs, [])
  # hata yolu: transparent işlem yine commit, abort yok, hata bildirilir
  l, r = reseat_setup
  pp = pk_seat(9421, 'POCKET', 2.2)
  $transform_fail = true; $ui_msgs = []
  res = M.mst_pk_reseat_after_edit([l], $model, true)
  $transform_fail = false
  t('6.5 hata: commit ile kapanır, abort yok, Türkçe bildirim', [$model.ops.map(&:first), $model.ops.include?([:abort]), res['errors'].length, $ui_msgs.join.include?('sahte dönüşüm hatası')],
    [%i[start commit], false, 1, true])
  # yatay kayma: cep ofseti değişti → oturtma yok, uyarı
  l, r = reseat_setup(0.9, 2.5)
  pp = pk_seat(9431, 'POCKET', 2.2); $ui_msgs = []
  res = M.mst_pk_reseat_after_edit([l], $model, true)
  t('6.6 yatay kayma: taşınmaz, işlem açılmaz, uyarı', [res['moved'], $model.ops, $ui_msgs.join.include?('yatayda kaydı')], [[], [], true])
  # cep artık yok
  fresh_model
  l = bk_y(9401, 0.0, 1.0, 3.0, 0.8, 2.0, false); r = bk_y(9402, 4.0, 5.0, 3.0, 0.8, 2.0, false)
  pp = pk_seat(9441, 'POCKET', 2.2); $ui_msgs = []
  res = M.mst_pk_reseat_after_edit([l], $model, true)
  t('6.7 cep kaldırıldı: taşınmaz, işlem açılmaz, uyarı', [res['moved'], $model.ops, $ui_msgs.join.include?('cebi artık yok')], [[], [], true])
  # UID yoksa destek PID ile (ikinci yol); düzenlenmeyen BK'ya bağlı PK'ya dokunulmaz
  l, r = reseat_setup
  pq = pk_seat(9451, nil, 2.2, 2.02, 3.22, 'elevation_mode' => 'POCKET')
  els = []; M.collect_elements($model.entities, els)
  t('6.8 UID yok → destek PID ile bulunur, taraf yoksa Y örtüşmesi', M.mst_pk_reseat_plan([r], els)['moves'].map { |m| m['e'] }, [pq])
  other = bk_y(9499, 8.0, 9.0)
  t('6.9 düzenlenen BK PK desteği değil → plan boş', M.mst_pk_reseat_plan([other], els)['moves'], [])
  # mst_kn_after_edit zinciri yeniden oturtmayı çağırır
  l, r = reseat_setup
  pp = pk_seat(9461, 'POCKET', 2.2)
  $model.ops.clear; $op_args = []
  begin; M.mst_kn_after_edit([l]); rescue => e; puts "  (kn_after_edit istisnası: #{e.message})"; end
  t('6.10 mst_kn_after_edit → PK cebe oturur (transparent ilk işlem, abort yok)',
    [near(pp.get_attribute(D, 'bottom_elevation_m'), 2.1), $op_args.first && $op_args.first[0], $op_args.first && $op_args.first[3], $model.ops.include?([:abort])], [true, 'MST Kanal Prekastı Cebe Oturt', true, false])
end

# ---------------------------------------------------------------- 7. P3 sonrası (kp3c): cep uyumu yükünde BK üstü; denetimde tanımlı üst yüzey
if HAVE
  # 7a. mst_pk_pocket_candidates → ciftler[].bk_ust_m (cep bölgesindeki BK üstü, dünya kutusu)
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
  l = bk_y(9501, 0.0, 1.0); r = bk_y(9502, 4.0, 5.0)
  pd = Sketchup::Group.new(9503, 'element_type' => 'flat_precast', 'precast_id' => 'PD9503', 'support_left_pid' => 9501, 'support_right_pid' => 9502, 'joint_m' => 0.02)
  pd.bounds = Geom::BoundingBox.new([0.85 * IN, 4.0 * IN, 2.7 * IN], [4.15 * IN, 5.0 * IN, 3.0 * IN]); put(pd)
  c = M.mst_pk_pocket_candidates($model, [l, r])['ciftler'][0]
  t('7.1 bk_ust_m = BK üstü 3,00; uyarı yok; mevcut alanlar aynı (referans üst = PD üstü, uyarı yok, cep uygun)',
    [near(c['bk_ust_m'], 3.0), c['bk_ust_uyari'], near(c['referans_ust_m'], 3.0), c['uyarilar'], c['cep_uygun']], [true, nil, true, [], true])
  fresh_model
  l = bk_y(9511, 0.0, 1.0, 3.0, 0.8); r = bk_y(9512, 4.0, 5.0, 3.1, 0.9)   # cep tabanları eşit (2,20), BK üstleri farklı
  c = M.mst_pk_pocket_candidates($model, [l, r], nil, { 'ref_top_m' => 3.0 })['ciftler'][0]
  t('7.2 BK üstleri farklı → bk_ust_m nil + Türkçe uyarı (ayrı alan); uyarilar / cep_uygun değişmez',
    [c['bk_ust_m'], c['bk_ust_uyari'].to_s.include?('farklı'), c['uyarilar'], c['cep_uygun']], [nil, true, [], true])
  fresh_model
  l = bk_y(9521, 0.0, 1.0); r = bk_y(9522, 4.0, 5.0, 3.0, 0.8, 2.0, false)
  c = M.mst_pk_pocket_candidates($model, [l, r], nil, { 'ref_top_m' => 3.0 })['ciftler'][0]
  t('7.3 karşı cep yok → bk_ust_m nil, neden yazılı', [c.key?('bk_ust_m'), c['bk_ust_m'], c['bk_ust_uyari'].to_s.empty?], [true, nil, false])

  # 7b. mst_kn_audit: channel_top_ref seçili PK'da PD üstü karşılaştırması tanımlı üst yüzeyle (alt + mst_ch_height(cs, ref))
  aud = lambda do |ref, real_top, pd_top|
    fresh_model
    bk_y(9531, 0.0, 1.0); bk_y(9532, 4.0, 5.0)
    pd = Sketchup::Group.new(9533, 'element_type' => 'flat_precast', 'precast_id' => 'PD9533', 'support_left_pid' => 9531, 'support_right_pid' => 9532, 'joint_m' => 0.02)
    pd.bounds = Geom::BoundingBox.new([0.85 * IN, 4.0 * IN, (pd_top - 0.3) * IN], [4.15 * IN, 5.0 * IN, pd_top * IN]); put(pd)
    a = { 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => 'PK9534', 'support_left_pid' => 9531, 'support_right_pid' => 9532, 'joint_m' => 0.02,
          'bottom_elevation_m' => 2.2, 'top_elevation_m' => real_top, 'channel_section_json' => M.mst_ch_json(sec_uu) }
    a['channel_top_ref'] = ref if ref
    pk = Sketchup::Group.new(9534, a)
    pk.bounds = Geom::BoundingBox.new([0.85 * IN, 2.02 * IN, 2.2 * IN], [4.15 * IN, 3.22 * IN, real_top * IN]); put(pk)
    els = []; M.collect_elements($model.entities, els)
    M.mst_kn_audit(els)[0].select { |x| x[3].to_s.include?('PD üstü') }.map { |x| x[3] }.uniq   # iki BK cebi aynı PK'yı ayrı denetler
  end
  t('7.4 channel_top_ref orta: tanımlı üst 2,70 = PD üstü 2,70 → uyarı yok (gerçek üst 3,00 korunur)', aud.('mid', 3.0, 2.7), [])
  w = aud.('mid', 3.0, 3.0)
  t('7.5 channel_top_ref orta, PD üstü 3,00: uyarı tanımlı üst 2,700 ile', [w.length, w[0].to_s.include?('2.700'), w[0].to_s.include?('3.000 m, PD')], [1, true, false])
  t('7.6 channel_top_ref yok: eski davranış (gerçek üst 3,00 = PD 3,00 → uyarı yok; PD 2,70 → uyarı 3,000)',
    [aud.(nil, 3.0, 3.0), aud.(nil, 3.0, 2.7).map { |x| x.include?('üst kotu 3.000 m') }], [[], [true]])
end

puts "\nKP3: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
