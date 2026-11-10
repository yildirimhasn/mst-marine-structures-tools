# KQ2 (ADR-0515-K3 P2, docs/duzeltme/41 + talimat 40a madde 6–7; 10.11.2026) — PK tip bağı ve kayıttan yükleme (Ruby):
#  1) Kanal Prekastı formu (create_channel_precast) isteğe bağlı tip_uid: kayıt bulunur ve formdaki kesit + oturmanın geom_sig'i kayıtla
#     eşitse öğeye precast_type_id = kayıt kodu, precast_type_uid, precast_type_rev; eşit değil / bulunamadı → tip bağı yok + Türkçe not;
#     tip_uid yok → bugünkü davranış (yeni anahtar yok, ileti yok).
#  2) Prekast Yerleşimi ve KN cebe yerleştirme: kayıttaki fw_bottom / fw_sides / fw_inner / fw_ends ve oturma (seat_left_m = seat_right_m)
#     kayıtta varsa geçerli, yoksa form / varsayılan (eski kayıt birebir); ledge: "açıkça kapatan kazanır" (38 K3) aynen; sol ≠ sağ oturma → durur.
#  3) Katalog kullanım satırında yapı sistemi (sistem / sistem_ad).
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir. Kanıt düzeyi: sahte nesne. SketchUp içinde tek Ctrl+Z, HtmlDialog akışı KANITLANMAZ.
# Sahte geometri / BK fikstürü kq1_pk_type_save.rb ile aynı.
# Kullanim: ruby tools/test/kq2_pk_type_link.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kq2_pk_type_link.rb <marine_structures_tools klasoru>'
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

# ---------------------------------------------------------------- sahte geometri (kq1_pk_type_save.rb ile aynı)
class Sketchup::Material; attr_accessor :color; end
class Sketchup::Entity
  def transform!(tr); @transformation = tr * @transformation; self; end
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
def fresh_model(lib = [])
  $model.entities = Sketchup::Entities.new; $model.entities.parent = $model
  $model.selection = Sketchup::Entities.new
  $model.definitions.clear; $model.ops.clear
  $model.set_attribute(D, 'precast_type_library_json', lib.is_a?(String) ? lib : JSON.generate(lib))
  $all_ents = {}; $ui_msgs = []
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
LINK_KEYS = %w[precast_type_id precast_type_uid precast_type_rev].freeze

HAVE = %i[create_channel_precast mst_pk_type_save mst_pk_geom_sig mst_pk_type_catalog mst_kn_place_plan].all? { |s| M.respond_to?(s) }
t('işlevler tanımlı', HAVE, true)

dfl = M.mst_ch_default
sec_l = M.mst_ch_preset(dfl.merge('total_width_m' => 1.0), 'L')
sec_uu = M.mst_ch_preset(dfl, 'UU')
sec_u = M.mst_ch_from_u(0.8, 0.6, 0.2, 0.2)
OLD_PK = { 'uid' => 'pk1', 'family' => 'PK', 'name' => 'PK-U', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37' }.freeze
PD_T = { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 }.freeze
# P1 ile kaydedilmiş kayıt (mst_pk_type_save çıktısı)
def saved_rec(sec, kod, h = {})
  fresh_model([OLD_PK, PD_T])
  r = M.mst_pk_type_save({ 'kod' => kod, 'ad' => "#{kod} ad", 'section' => sec, 'concrete' => 'C30/37', 'seat_left_m' => 0.15, 'seat_right_m' => 0.15,
                           'fw' => { 'bottom' => false, 'sides' => true, 'inner' => true, 'ends' => false, 'ledge' => true }, 'kutuphane' => [OLD_PK, PD_T] }.merge(h), $model)
  r['tip']
end
FORM = { 'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'length_mode' => 'AUTO', 'manual_length_m' => 3.3, 'concrete_class' => 'C30/37',
         'fw_bottom' => false, 'fw_sides' => true, 'fw_inner' => true, 'fw_ends' => false, 'fw_top' => false }.freeze
def form_run(lib, form)
  fresh_model(lib)
  hb = bk_y(9301, 0.0, 1.0); $model.selection.push(hb)
  M.create_channel_precast(form)
  pks.first
end
VOLATILE = %w[element_uid uid_owner_pid precast_id type_id library_type_id type_signature mst_tag].freeze   # mst_tag: etiket tip koduyla (1.3b)
def stable(e); attrs(e).reject { |k, _| VOLATILE.include?(k) || LINK_KEYS.include?(k) }; end

if HAVE
  # ================================================================ 1. Kanal Prekastı formu: tip_uid
  rl = saved_rec(sec_l, 'PK-L1')
  lib1 = JSON.parse($model.get_attribute(D, 'precast_type_library_json', '[]'))
  base = form_run(lib1, FORM.merge('section' => sec_l))
  ba = attrs(base)
  t('1.1 tip_uid yok: yeni anahtar yazılmaz, ileti yok, tek start + commit (bugünkü davranış)',
    [LINK_KEYS.map { |k| ba.key?(k) }, $ui_msgs, $model.ops.map(&:first), ba['precast_type']], [[false, false, false], [], %i[start commit], 'KANAL_PREKASTI_L'])
  lk = form_run(lib1, FORM.merge('section' => sec_l, 'tip_uid' => rl['uid']))
  la = attrs(lk)
  t('1.2 tip_uid + aynı geom_sig: precast_type_id = kod, uid, rev; ileti yok; tek start + commit',
    [la['precast_type_id'], la['precast_type_uid'], la['precast_type_rev'], $ui_msgs, $model.ops.map(&:first)], ['PK-L1', rl['uid'], 1, [], %i[start commit]])
  t('1.3 bağlı öğenin diğer anahtarları (hacim, kalıp, kot, kesit, precast_type) bağsızla aynı', stable(lk), stable(base))
  t('1.3b bağlı öğenin etiketi tip koduyla (yerleşimdeki PK gibi)', [la['mst_tag'], ba['mst_tag']], ['MST | ANO-01 | PK | PK-L1', 'MST | ANO-01 | PK | KANAL_PREKASTI_L'])
  ne = form_run(lib1, FORM.merge('section' => sec_l, 'seat_left_m' => 0.10, 'tip_uid' => rl['uid']))
  t('1.4 oturma farklı (geom_sig eşit değil): tip bağı yazılmaz, Türkçe not, öğe oluşturulur',
    [ne.nil?, ne && LINK_KEYS.map { |k| attrs(ne).key?(k) }, $ui_msgs.length, $ui_msgs.join.include?('tip bağı'), $model.ops.map(&:first)], [false, [false, false, false], 1, true, %i[start commit]])
  ng = form_run(lib1, FORM.merge('section' => sec_uu, 'tip_uid' => rl['uid']))
  t('1.5 kesit farklı: tip bağı yok + not', [ng && LINK_KEYS.map { |k| attrs(ng).key?(k) }, $ui_msgs.join.include?('PK-L1')], [[false, false, false], true])
  nf = form_run(lib1, FORM.merge('section' => sec_l, 'tip_uid' => 'pt_pk_yok'))
  t('1.6 kayıt bulunamadı: tip bağı yok + not', [nf && LINK_KEYS.map { |k| attrs(nf).key?(k) }, $ui_msgs.join.include?('bulunamadı')], [[false, false, false], true])
  ol = form_run([OLD_PK], FORM.merge('inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2, 'tip_uid' => 'pk1'))
  t('1.7 eski kayıt (geom_sig / oturma / pk_rev yok), aynı U kesit: kod + uid yazılır, rev yazılmaz',
    [ol && attrs(ol)['precast_type_id'], ol && attrs(ol)['precast_type_uid'], ol && attrs(ol).key?('precast_type_rev'), $ui_msgs], ['PK-U', 'pk1', false, []])
  st = lib1.map { |x| x['uid'] == rl['uid'] ? x.merge('geom_sig' => 'pk1|bayat') : x }
  sg = form_run(st, FORM.merge('section' => sec_l, 'tip_uid' => rl['uid']))
  t('1.8 kayıttaki geom_sig kayıt geometrisiyle tutarsız: bağ yok + not', [sg && attrs(sg).key?('precast_type_uid'), $ui_msgs.length], [false, 1])
  bd = form_run(lib1, FORM.merge('section' => sec_l, 'tip_uid' => '  '))
  t('1.9 boş tip_uid = yok: ileti yok, bağ yok', [bd && attrs(bd).key?('precast_type_uid'), $ui_msgs], [false, []])

  # ================================================================ 2. Prekast Yerleşimi: kayıttan kalıp + oturma
  lay = lambda do |lib, rows, extra = {}|
    fresh_model(lib)
    l = bk_y(9101, 0.0, 1.0); r = bk_y(9102, 4.0, 5.0); $model.selection.push(l, r)
    data = { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(lib), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02',
             'pd_y_offset_m' => '2.02', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_inner' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }.merge(extra)
    [M.create_flat_precast(data), pks]
  end
  ok, ps = lay.([OLD_PK, PD_T], [{ 'type_uid' => 'pk1', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }])
  a = ps[0] && attrs(ps[0]); ft = M.mst_ch_u_fw_terms(3.3, 0.8, 0.6, 0.2, 0.2)
  t('2.1 eski kayıt (fw / oturma yok): form onay kutuları + pd_seat (boy 3,30, kalıp = yan + iç, oturma 0,15, x0 0,85)',
    [ok, a && near(a['length_m'], 3.3), a && near(a['formwork_area_m2'], ft[1] + ft[2]), a && a['seat_each_side_m'], ps[0] && near(ps[0].transformation.origin.x / IN, 0.85)],
    [true, true, true, 0.15, true])
  rf = { 'uid' => 'pt_pk_9_1', 'family' => 'PK', 'name' => 'PK-L9', 'section' => JSON.parse(M.mst_ch_json(sec_l)), 'concrete' => 'C30/37',
         'fw_bottom' => true, 'fw_sides' => false, 'fw_inner' => true, 'fw_ends' => true, 'fw_ledge' => true, 'seat_left_m' => 0.10, 'seat_right_m' => 0.10, 'pk_rev' => 2 }
  # 43/1 (docs/duzeltme/43, karar 10): oturması PD'den farklı tip PD ile aynı yerleşimde reddedilir → 2.2 yalnız PK yerleşimi
  ok, ps = lay.([rf, PD_T], [{ 'type_uid' => 'pt_pk_9_1', 'count' => 1 }])
  a = ps[0] && attrs(ps[0]); cs = ps[0] && M.mst_ch_section(ps[0])
  t('2.2 kayıtta fw_* + oturma 0,10: boy 3,20, oturma 0,10, x0 0,90, kalıp kayıttaki seçimle',
    [ok, a && near(a['length_m'], 3.2), a && a['seat_each_side_m'], ps[0] && near(ps[0].transformation.origin.x / IN, 0.9),
     a && cs && near(a['formwork_area_m2'], M.mst_ch_formwork(cs, a['length_m'], bottom: true, sides: false, inner: true, ends: true, ledge: true))],
    [true, true, 0.10, true, true])
  $ui_msgs = []
  ok, ps = lay.([rf, PD_T], [{ 'type_uid' => 'pt_pk_9_1', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }])
  t('2.3 (43/1) kayıt oturması 0,10 ≠ PD form oturması 0,15 aynı yerleşimde: yerleşim yok, işlem açılmaz, Türkçe neden (döşeme cebi)',
    [ok == true, ps.length, $model.ops.map(&:first), $ui_msgs.join.include?('oturma') && $ui_msgs.join.include?('döşeme')], [false, 0, [], true])
  ok, ps = lay.([rf, PD_T], [{ 'type_uid' => 'pt_pk_9_1', 'count' => 1 }], 'channel_fw_ledge' => '0')
  a = ps[0] && attrs(ps[0]); cs = ps[0] && M.mst_ch_section(ps[0])
  t('2.4 ledge: kayıt açık + form kapalı → kapalı (açıkça kapatan kazanır, 38 K3 aynen)',
    a && cs && near(a['formwork_area_m2'], M.mst_ch_formwork(cs, a['length_m'], bottom: true, sides: false, inner: true, ends: true, ledge: false)), true)
  ok, ps = lay.([rf.merge('seat_right_m' => 0.20), PD_T], [{ 'type_uid' => 'pt_pk_9_1', 'count' => 1 }])
  t('2.5 kayıtta sol ≠ sağ oturma: yerleşim durur (işlem geri alınır), Türkçe neden, PK yok',
    [ok == true, ps.length, $model.ops.map(&:first), $ui_msgs.join.include?('oturma')], [false, 0, %i[start abort], true])
  ru = { 'uid' => 'pt_pk_9_2', 'family' => 'PK', 'name' => 'PK-U9', 'section' => JSON.parse(M.mst_ch_json(sec_u)), 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2,
         'fw_bottom' => true, 'fw_sides' => false, 'fw_inner' => false, 'fw_ends' => true, 'fw_ledge' => true, 'seat_left_m' => 0.15, 'seat_right_m' => 0.15 }
  ok, ps = lay.([ru, PD_T], [{ 'type_uid' => 'pt_pk_9_2', 'count' => 1 }])
  a = ps[0] && attrs(ps[0])
  t('2.6 U-eşdeğeri kayıt: kalıp kayıttan (taban + uç), oturma kayıtla aynı (0,15)', [ok, a && near(a['formwork_area_m2'], ft[0] + ft[3]), a && a['seat_each_side_m']], [true, true, 0.15])

  # ================================================================ 3. KN cebe yerleştirme
  kn = lambda do |rec, ps_ = 0.15|   # ps_: açıklıktaki PD oturması (43/1: kayıt oturması buna eşit olmalı)
    fresh_model([rec])
    bk_y(9201, 0.0, 1.0); bk_y(9202, 4.0, 5.0)
    pd = Sketchup::Group.new(9203, 'element_type' => 'flat_precast', 'precast_id' => 'PD9203', 'support_left_pid' => 9201, 'support_right_pid' => 9202, 'joint_m' => 0.02, 'seat_each_side_m' => ps_, 'project' => 'P1')
    pd.bounds = Geom::BoundingBox.new([(1.0 - ps_) * IN, 4.0 * IN, 2.7 * IN], [(4.0 + ps_) * IN, 5.0 * IN, 3.0 * IN]); put(pd)
    M.mst_kn_place_plan($model, nil, nil, nil)
  end
  old = { 'uid' => 'pt_pk_1_1', 'family' => 'PK', 'name' => 'PK-KN', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37' }
  kp = kn.(old); c0 = kp['cands'][0]
  t('3.1 KN eski kayıt: oturma PD\'den (0,15), boy 3,30, x0 0,85, kalıp varsayılan 0010', c0 && [c0['seat'], near(c0['length'], 3.3), near(c0['x0'], 0.85), c0['type']['fw']], [0.15, true, true, '0010'])
  r10 = old.merge('fw_bottom' => true, 'fw_sides' => false, 'fw_inner' => true, 'fw_ends' => true, 'seat_left_m' => 0.10, 'seat_right_m' => 0.10)
  kp = kn.(r10)
  t('3.1b (43/1) KN kayıt oturması 0,10 ≠ açıklıktaki PD oturması 0,15: aday yok, Türkçe uyarı (döşeme cebi)', [kp['cands'].length, kp['warnings'].join.include?('kayıttaki oturma')], [0, true])
  kp = kn.(r10, 0.10)
  c0 = kp['cands'][0]
  t('3.2 KN kayıtta fw_* + oturma 0,10: oturma 0,10, boy 3,20, x0 0,90, kalıp 1011', c0 && [c0['seat'], near(c0['length'], 3.2), near(c0['x0'], 0.9), c0['type']['fw']], [0.10, true, true, '1011'])
  inst = c0 && M.mst_kn_create_pk!(c0, $model, nil)
  t('3.3 KN oluşturulan PK: seat_each_side_m 0,10, boy 3,20', inst && [inst.get_attribute(D, 'seat_each_side_m'), near(inst.get_attribute(D, 'length_m'), 3.2)], [0.10, true])
  kp = kn.(old.merge('seat_left_m' => 0.10, 'seat_right_m' => 0.20))
  t('3.4 KN kayıtta sol ≠ sağ oturma: aday yok, Türkçe uyarı', [kp['cands'].length, kp['warnings'].join.include?('oturma')], [0, true])
  csx = M.mst_ch_preset(dfl.merge('total_width_m' => 1.2), 'L')
  kp = kn.({ 'uid' => 'pt_pk_1_2', 'family' => 'PK', 'name' => 'PK-KL', 'section' => JSON.parse(M.mst_ch_json(csx)), 'fw_ledge' => false, 'fw_sides' => true })
  c0 = kp['cands'][0]
  t('3.5 KN U dışı: fw_sides kayıttan 1, ledge kapalı (38 K3), diğerleri varsayılan', c0 && c0['type']['fw'], '01100')

  # ================================================================ 4. katalog: kullanım satırında yapı sistemi
  fresh_model([rf])
  $model.set_attribute(D, 'system_structures_json', '{"ISKELE":["ANO-01"],"RIHTIM":["RIHTIM-01"],"DOLFEN":["BD-01"]}')
  mk = ->(pid, h) { put(Sketchup::Group.new(pid, { 'element_type' => 'channel_precast', 'precast_type_id' => 'PK-L9', 'precast_type_uid' => 'pt_pk_9_1', 'channel_section_json' => M.mst_ch_json(sec_l) }.merge(h))) }
  mk.(7101, 'structure' => 'ANO-01', 'system' => 'ISKELE'); mk.(7102, 'structure' => 'RIHTIM-01'); mk.(7103, 'ano' => 'BD-01'); mk.(7104, {})
  el = M.mst_pk_type_catalog($model).find { |e| e['kod'] == 'PK-L9' }
  t('4.1 kullanım: sistem (öğeden, yoksa yapı listesinden) ve sistem_ad',
    el && el['kullanim'].map { |k| [k['yapi'], k['sistem'], k['sistem_ad'], k['adet']] },
    [['ANO-01', 'ISKELE', 'İSKELE', 1], ['BD-01', 'DOLFEN', 'DOLFEN', 1], ['RIHTIM-01', 'RIHTIM', 'RIHTIM', 1], ['', '', 'Sistem belirtilmemiş', 1]])
end

puts "\nKQ2: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
