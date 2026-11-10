# KQ3 (ADR-0515-K3 P3, docs/duzeltme/41 kullanıcı kararı 6; talimat 40a madde 8 "Alt kottan yerleştir") — PK kot yöntemi SUPPORT:
#  PK alt yüzü (z=0) iki destek BK'nın üst kotuna (dünya; iki BK üstü > 5 mm farklıysa yerleşim yok, tahmin yok). Cep varsa da cebe inmez.
#  Öğeye elevation_mode=SUPPORT + seat_bk_left/right_uid (+ cep altındaysa _side); elevation_ref_* yazılmaz.
#  BK üstü değişince (mst_kn_after_edit) SUPPORT PK yeniden oturur (transparent işlem, abort yok). TOP / POCKET / MANUAL çıktıları aynı.
# Gerçek main.rb (golden SketchUp sahtesi). Kanıt düzeyi: sahte nesne. SketchUp içi Geri Al zinciri, eğik BK KANITLANMAZ.
# Kullanim: ruby tools/test/kq3_pk_support.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kq3_pk_support.rb <marine_structures_tools klasoru>'
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

HAVE = %i[mst_pk_support_top mst_pk_support_find].all? { |s| M.respond_to?(s) }
t('SUPPORT yardımcıları tanımlı', HAVE, true)
LIB = [
  { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 },
  { 'uid' => 'pk1', 'family' => 'PK', 'name' => 'PK-U', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37' }
].freeze
ROWS_U = [{ 'type_uid' => 'pk1', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }].freeze
REF_KEYS = %w[elevation_ref_face elevation_ref_m].freeze

# ---------------------------------------------------------------- 1. girdi + hedef kot
o = M.mst_pk_elev_opts({ 'pk_elevation_mode' => 'support' }, 'pk_')
t('1.1 SUPPORT tanınır (given)', [o['mode'], o['given']], ['SUPPORT', true])
tg = (M.mst_pk_elev_target(o, 0.8, 3.3, 2.2, 3.0) rescue { 'ok' => :hata })
t('1.2 SUPPORT: alt = BK üstü 3,00 (cep tabanı 2,20 yok sayılır), üst 3,80', [tg['ok'], tg['bottom'], tg['top'] && near(tg['top'], 3.8)], [true, 3.0, true])
tg = (M.mst_pk_elev_target(o, 0.8, 3.3, 2.2, nil) rescue { 'ok' => :hata })
t('1.3 SUPPORT BK üstü yok → Türkçe hata', [tg['ok'], tg['errors'].to_a.join.include?('BK')], [false, true])
tg = M.mst_pk_elev_target(M.mst_pk_elev_opts('elevation_mode' => 'POCKET'), 0.8, 3.3, 2.2)
t('1.4 POCKET (eski 4 bağımsız değişken) aynı', [tg['ok'], tg['bottom']], [true, 2.2])

# ---------------------------------------------------------------- 2. Prekast Yerleşimi
$grp = nil
class Sketchup::Model
  def active_entities; $grp ? $grp.entities : @entities; end
end
def layout(rows, extra = {}, rtop = 3.0, gdy = nil, gdz = 0.0)
  fresh_model; $grp = nil
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
  l = bk_y(9101, 0.0, 1.0); r = bk_y(9102, 4.0, 5.0, rtop, 0.8 + rtop - 3.0)
  if gdy
    gr = Sketchup::Group.new(9100, {}); gr.transformation = Geom::Transformation.translation([0, gdy * IN, gdz * IN])
    [l, r].each { |b| $model.entities.delete(b); gr.entities << b; b.parent = gr.definition }
    put(gr); $grp = gr
  end
  $model.selection.push(l, r)
  data = { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(LIB), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '2.02',
           'channel_fw_inner' => '1', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }.merge(extra)
  r0 = M.create_flat_precast(data)
  [r0, pks[0], l, r]
end
TZ = ->(e) { e.transformation.to_a[14] / IN }
ok, pk, = layout(ROWS_U, 'pk_elevation_mode' => 'SUPPORT')
a = pk ? attrs(pk) : {}
t('2.1 SUPPORT (cep üstünde): alt 3,00 = BK üstü (cebe inmez), üst 3,80; mod + cep bağı UID + taraf; elevation_ref_* yok; destek PID korunur',
  [ok, near(a['bottom_elevation_m'], 3.0), near(a['top_elevation_m'], 3.8), a['elevation_mode'], a['seat_bk_left_uid'], a['seat_bk_right_uid'], a['seat_bk_left_side'], a['seat_bk_right_side'], a.keys & REF_KEYS, a['support_left_pid']],
  [true, true, true, 'SUPPORT', 'BK-U9101', 'BK-U9102', 'start', 'start', [], 9101])
ok, pk, = layout(ROWS_U, 'pk_elevation_mode' => 'SUPPORT', 'pd_y_offset_m' => '5.0')
a = pk ? attrs(pk) : {}
t('2.2 SUPPORT cep dışında: yine BK üstüne (3,00), taraf yazılmaz', [ok, near(a['bottom_elevation_m'], 3.0), a['seat_bk_left_uid'], a.key?('seat_bk_left_side')], [true, true, 'BK-U9101', false])
ok, pk, = layout(ROWS_U, { 'pk_elevation_mode' => 'SUPPORT' }, 3.1)
t('2.3 BK üstleri farklı (3,00 / 3,10): Prekast Yerleşimi zaten durur (önceki BK kot denetimi), PK yok', [ok, pk, $ui_msgs.last.to_s.include?('farklı')], [nil, nil, true])
if HAVE
  fresh_model
  l = bk_y(9111, 0.0, 1.0); r = bk_y(9112, 4.0, 5.0, 3.1, 0.9)
  st, p, q, ws = M.mst_pk_support_find(l, r, 2.02, 3.22)
  t('2.3b mst_pk_support_find: geometrik BK üstleri farklı → nil + Türkçe uyarı (tahmin yok)', [st, p, q, ws.join.include?('farklı')], [nil, nil, nil, true])
  st, p, q, ws = M.mst_pk_support_find(bk_y(9113, 0.0, 1.0), bk_y(9114, 4.0, 5.0), 2.02, 3.22)
  t('2.3c mst_pk_support_find: 3,00, cep tarafı start', [st && near(st, 3.0), p && p['side'], ws], [true, 'start', []])
end
ok, pk, = layout(ROWS_U, { 'pk_elevation_mode' => 'SUPPORT' }, 3.004)
t('2.4 BK üstleri 4 mm farklı (≤ 5 mm): yerleşir (sol BK üstü)', [ok, pk && near(attrs(pk)['bottom_elevation_m'], 3.0)], [true, true])
ok, pk, = layout(ROWS_U, { 'pk_elevation_mode' => 'SUPPORT' }, 3.0, 20.0, 1.0)
t('2.5 grup içi BK (+Y 20 / +Z 1,0): alt kot (dünya) 4,00; PK yerel z 3,00', [ok, pk && near(attrs(pk)['bottom_elevation_m'], 4.0), pk && near(TZ.(pk), 3.0, 1e-9)], [true, true, true])
ok, pk, = layout(ROWS_U, { 'pk_elevation_mode' => 'SUPPORT', 'pd_y_offset_m' => '9.5' })
t('2.6 PK BK boyunun dışına taşıyor: oluşturulmaz, Türkçe neden', [ok, pk, $ui_msgs.last.to_s.include?('BK boyu')], [false, nil, true])
ok, pk, = layout(ROWS_U, 'pk_elevation_mode' => 'POCKET')
a = pk ? attrs(pk) : {}
t('2.7 POCKET anahtarları aynı (elevation_ref_face yazılmaya devam), alt 2,20', [near(a['bottom_elevation_m'], 2.2), a['elevation_ref_face'], a.key?('elevation_ref_m'), a['seat_bk_left_side']], [true, 'TOP', false, 'start'])
ok, pk, = layout(ROWS_U)
a = pk ? attrs(pk) : {}
t('2.8 TOP (girdi yok): kot anahtarı yazılmaz, alt 2,50', [near(a['bottom_elevation_m'], 2.5), a.keys & (%w[elevation_mode seat_bk_left_uid] + REF_KEYS)], [true, []])

# ---------------------------------------------------------------- 3. KN cebe yerleştirme
$grp = nil
fresh_model
$model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
l = bk_y(9201, 0.0, 1.0); r = bk_y(9202, 4.0, 5.0)
pd = Sketchup::Group.new(9203, 'element_type' => 'flat_precast', 'precast_id' => 'PD9203', 'support_left_pid' => 9201, 'support_right_pid' => 9202, 'joint_m' => 0.02, 'seat_each_side_m' => 0.15)
pd.bounds = Geom::BoundingBox.new([0.85 * IN, 4.0 * IN, 2.7 * IN], [4.15 * IN, 5.0 * IN, 3.0 * IN]); put(pd)
kp = M.mst_kn_place_plan($model, nil, nil, nil, M.mst_pk_elev_opts('elevation_mode' => 'SUPPORT'))
c = kp['cands'][0]
t('3.1 KN plan SUPPORT: alt = BK üstü 3,00', c && near(c['z0'], 3.0), true)
kp4 = M.mst_kn_place_plan($model, nil, nil, nil, M.mst_pk_elev_opts('elevation_mode' => 'POCKET'))
t('3.4 KN POCKET aynı (alt 2,20)', kp4['cands'][0] && near(kp4['cands'][0]['z0'], 2.2), true)
inst = c && M.mst_kn_create_pk!(c, $model, nil)
a = inst ? attrs(inst) : {}
t('3.2 KN SUPPORT öznitelikleri', [near(a['bottom_elevation_m'], 3.0), a['elevation_mode'], a['seat_bk_left_uid'], a['seat_bk_right_side'], a.keys & REF_KEYS], [true, 'SUPPORT', 'BK-U9201', 'start', []])
t('3.3 önizleme metni BK üstü', M.mst_kn_preview_text(kp).include?('(BK üstü)'), true)

# ---------------------------------------------------------------- 4. kot önizlemesi
fresh_model
$model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
l = bk_y(9301, 0.0, 1.0); r = bk_y(9302, 4.0, 5.0)
$writes = []; $model.ops.clear
pv = M.mst_pk_elevation_preview($model, [l, r], { 'elevation_mode' => 'SUPPORT', 'kod' => 'PK-U', 'ref_top_m' => 3.3 })
t('4.1 önizleme SUPPORT: alt 3,00, üst 3,80, bk_ust_m 3,00, bk_ust_uyari nil, kaynak yazılı, uyarı yok, yazım / işlem yok',
  [pv['ok'], near(pv['alt_kot_m'], 3.0), near(pv['ust_kot_m'], 3.8), near(pv['bk_ust_m'], 3.0), pv['bk_ust_uyari'], pv['bk_ust_kaynagi'].to_s.empty?, pv['uyarilar'], pv['mod'], $writes, $model.ops],
  [true, true, true, true, nil, false, [], 'SUPPORT', [], []])
fresh_model
$model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
l = bk_y(9311, 0.0, 1.0); r = bk_y(9312, 4.0, 5.0, 3.1, 0.9)
pv = M.mst_pk_elevation_preview($model, [l, r], { 'elevation_mode' => 'SUPPORT', 'kod' => 'PK-U' })
t('4.2 BK üstleri farklı: ok false, bk_ust_m nil, bk_ust_uyari "farklı", uyarılarda', [pv['ok'], pv.key?('bk_ust_m'), pv['bk_ust_m'], pv['bk_ust_uyari'].to_s.include?('farklı'), pv['uyarilar'].to_a.join.include?('farklı')], [false, true, nil, true, true])
fresh_model
$model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
l = bk_y(9321, 0.0, 1.0, 3.0, 0.8, 2.0, false); r = bk_y(9322, 4.0, 5.0, 3.0, 0.8, 2.0, false)
pv = M.mst_pk_elevation_preview($model, [l, r], { 'elevation_mode' => 'SUPPORT', 'kod' => 'PK-U' })
t('4.3 cepsiz BK: SUPPORT yine hesaplanır (alt 3,00), cep uyarısı yok', [pv['ok'], near(pv['alt_kot_m'], 3.0), pv['uyarilar']], [true, true, []])
pv = M.mst_pk_elevation_preview($model, [l, r], { 'elevation_mode' => 'POCKET', 'kod' => 'PK-U' })
t('4.4 POCKET yükü değişmedi (bk_ust_* alanı yok)', [pv['ok'], pv.key?('bk_ust_m'), pv.key?('bk_ust_uyari'), pv.key?('bk_ust_kaynagi')], [false, false, false, false])

# ---------------------------------------------------------------- 5. BK üstü değişince yeniden oturtma
$kq3_status = []
Sketchup.define_singleton_method(:status_text=) { |v| $kq3_status << v.to_s }
def pk_sup(pid, z0, mode = 'SUPPORT', y0 = 2.02, y1 = 3.22)
  a = { 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => "PK#{pid}", 'support_left_pid' => 9401, 'support_right_pid' => 9402,
        'bottom_elevation_m' => z0, 'top_elevation_m' => z0 + 0.8, 'elevation_mode' => mode, 'seat_bk_left_uid' => 'BK-U9401', 'seat_bk_right_uid' => 'BK-U9402' }
  a.merge!('seat_bk_left_side' => 'start', 'seat_bk_right_side' => 'start') if mode == 'POCKET'
  e = Sketchup::Group.new(pid, a)
  e.bounds = Geom::BoundingBox.new([0.85 * IN, y0 * IN, z0 * IN], [4.15 * IN, y1 * IN, (z0 + 0.8) * IN]); put(e)
end
def rs(top_l = 3.1, top_r = 3.1)
  fresh_model
  [bk_y(9401, 0.0, 1.0, top_l, 0.9 + top_l - 3.0), bk_y(9402, 4.0, 5.0, top_r, 0.9 + top_r - 3.0)]   # cep tabanı 2,10
end
l, r = rs
ps = pk_sup(9411, 3.0); pp = pk_sup(9412, 2.2, 'POCKET'); pt = pk_sup(9413, 3.0, 'TOP')
els = []; M.collect_elements($model.entities, els)
plan = M.mst_pk_reseat_plan([l], els)
t('5.1 plan: SUPPORT +0,10 (BK üstü 3,10) ve POCKET −0,10 (cep 2,10); TOP dokunulmaz',
  [plan['moves'].map { |m| m['e'] }.sort_by(&:persistent_id), plan['moves'].map { |m| m['dz'].round(6) }.sort, plan['warnings']], [[ps, pp], [-0.1, 0.1], []])
$model.ops.clear; $op_args = []; $ui_msgs = []
res = M.mst_pk_reseat_after_edit([l], $model, true)
t('5.2 tek transparent işlem, commit, abort yok', [$model.ops.map(&:first), $op_args.map { |x| x[3] }, $model.ops.include?([:abort])], [%i[start commit], [true], false])
t('5.3 SUPPORT kot: z +0,10, alt 3,10, üst 3,90; TOP yerinde',
  [near(ps.transformation.to_a[14], 0.1 * IN, 1e-6), near(ps.get_attribute(D, 'bottom_elevation_m'), 3.1), near(ps.get_attribute(D, 'top_elevation_m'), 3.9), pt.transformation.identity?], [true, true, true, true])
l, r = rs
ps = pk_sup(9421, 3.0); $model.ops.clear; $op_args = []
begin; M.mst_kn_after_edit([l]); rescue => e; puts "  (kn_after_edit istisnası: #{e.message})"; end
t('5.4 mst_kn_after_edit (yalnız SUPPORT PK) → BK üstüne oturur, transparent, abort yok',
  [near(ps.get_attribute(D, 'bottom_elevation_m'), 3.1), $op_args.first && $op_args.first[3], $model.ops.include?([:abort])], [true, true, false])
l, r = rs
ps = pk_sup(9431, 3.0); $transform_fail = true; $ui_msgs = []
res = M.mst_pk_reseat_after_edit([l], $model, true); $transform_fail = false
t('5.5 hata: commit ile kapanır, abort yok, bildirim', [$model.ops.map(&:first), res['errors'].length, $ui_msgs.join.include?('sahte dönüşüm hatası')], [%i[start commit], 1, true])
l, r = rs(3.1, 3.2)
ps = pk_sup(9441, 3.0); $ui_msgs = []; $kq3_status = []
res = M.mst_pk_reseat_after_edit([l], $model, true)
t('5.6 BK üstleri farklı: taşınmaz, işlem yok, uyarı', [res['moved'], $model.ops, ($ui_msgs + $kq3_status).join.include?('farklı')], [[], [], true])
l, r = rs
ps = pk_sup(9451, 3.0, 'SUPPORT', 9.5, 10.7); $ui_msgs = []; $kq3_status = []
res = M.mst_pk_reseat_after_edit([l], $model, true)
t('5.7 yatay kayma (BK boyu dışı): taşınmaz, uyarı', [res['moved'], $model.ops, ($ui_msgs + $kq3_status).join.include?('BK boyu')], [[], [], true])
fresh_model
l = bk_y(9401, 0.0, 1.0, 3.1, 1.0); r = bk_y(9402, 4.0, 5.0, 3.1, 1.0)
pz = Sketchup::Group.new(9461, 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => 'PK9461', 'support_left_pid' => 9401, 'support_right_pid' => 9402,
                               'bottom_elevation_m' => 4.0, 'top_elevation_m' => 4.8, 'elevation_mode' => 'SUPPORT', 'seat_bk_left_uid' => 'BK-U9401', 'seat_bk_right_uid' => 'BK-U9402')
pz.bounds = Geom::BoundingBox.new([0.85 * IN, 2.02 * IN, 3.0 * IN], [4.15 * IN, 3.22 * IN, 3.8 * IN])
gr = Sketchup::Group.new(9400, {}); gr.transformation = Geom::Transformation.translation([0, 0, 1.0 * IN])
[l, r].each { |b| $model.entities.delete(b) }
[l, r, pz].each { |b| gr.entities << b; b.parent = gr.definition }
put(gr)
res = M.mst_pk_reseat_after_edit([l], $model, true)
t('5.8 grup +Z 1,0: yerel dz +0,10, alt kot (dünya) 4,10', [res['moved'], near(TZ.(pz), 0.1, 1e-9), near(pz.get_attribute(D, 'bottom_elevation_m'), 4.1)], [[pz], true, true])

# ---------------------------------------------------------------- 6. eski sürüm notu
src = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
t('6.1 kod içi not: eski sürüm SUPPORT kipini TOP okur', src.include?('SUPPORT kipini tanımaz'), true)

puts "\nKQ3: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)

