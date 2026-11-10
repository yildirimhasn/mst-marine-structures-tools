# KQ4 (ADR-0515-K3 P4, docs/duzeltme/41 analiz (d), (g), (i); kullanıcı kararları 3, 4, 5, 7; talimat 40a madde 9, 10, 12) — PK tip düzenleme + PK Sil:
#  1. "Yalnız bu eleman(lar)": pk_type_save + uygula:"secim" — kayıt + seçili PK'lara tip AYNI normal işlemde (Group yeniden kurulur, Component
#     yeni anahtarın tanımına geçer, çok kopyalı tanım değişmez), element_uid / revision aynı, precast_type_uid / _rev yeni tipe; seçimde PK yoksa işlem yok.
#  2. "Tüm örnekler": pk_type_update_plan (salt okuma: yazım / işlem yok), yapı / model kapsamı, uymayan örnek → başlatılamaz, aynı geom_sig reddi;
#     pk_type_update_apply tek normal işlem "MST PK Tipini Güncelle", kapsam dışı eski rev'de, rev_log anlık görüntüsü, katalog eski_rev, abort yolu.
#  3. "PK Sil": tek normal işlem, bağlı döşeme aynı işlemde yeniden kurulur, diğer PK'nın açıklığı değişmez.
#  Metraj elle beklenen: L (toplam 1,20, taban 0,20, sağ çıkıntı 0,20 × 0,60) alan 1,20 × 0,20 + 0,20 × 0,60 = 0,36 m²; boy 3,00 + 2 × 0,15 = 3,30 →
#  beton 1,188 m³. Genişlik 1,20 → 1,30: alan 0,38 → 1,254 m³ (+0,066). Oturma 0,15 → 0,25: boy 3,50 → 0,36 × 3,50 = 1,260 m³, başlangıç −0,10 m.
# Gerçek main.rb (golden SketchUp sahtesi). Kanıt düzeyi: sahte nesne. SketchUp içinde tek Ctrl+Z / Yinele, gerçek Component tanım geçişi,
#  döşeme yüz çizimi (mst_deck_fill!) KANITLANMAZ (döşeme yeniden üretimi sahte: gerçek mst_deck_inputs + mst_deck_plan ile plan yazar).
# Kullanim: ruby tools/test/kq4_pk_type_edit.rb <src/marine_structures_tools>
require 'stringio'
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kq4_pk_type_edit.rb <marine_structures_tools klasoru>'
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
class Sketchup::ComponentInstance
  def erase!; @erased = true; pr = parent; (pr.is_a?(Sketchup::Entities) ? pr : pr.entities).delete(self); definition.instances.delete(self); end
end
$writes = []
def libtxt; $model.get_attribute(D, 'precast_type_library_json', '').to_s; end
def ops; $model.ops.map(&:first); end
def ops_clear; $model.ops.clear; $op_args = []; $writes = []; end
def vol(e); e.get_attribute(D, 'concrete_volume_m3').to_f; end
def sel(*es); $model.selection.clear; es.each { |e| $model.selection << e }; end
def secj(s); JSON.parse(M.mst_ch_json(s)); end

HAVE = %i[mst_pk_type_save_sel mst_pk_update_build mst_pk_type_update_apply mst_pk_delete mst_pk_apply_rec! mst_pk_decks_regen!].all? { |s| M.respond_to?(s) }
t('0.1 P4 işlevleri tanımlı', HAVE, true)
src = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
t('0.2 callback kayıtları (pk_type_update_plan / pk_type_update_apply / pk_delete)',
  %w[pk_type_update_plan pk_type_update_apply pk_delete].map { |c| src.include?("add_action_callback('#{c}')") }, [true, true, true])
unless HAVE
  puts "\nKQ4: #{$ok} geçti, #{$bad} kaldı"
  exit 1
end

SEC_L = M.mst_ch_preset(M.mst_ch_default, 'L')
SEC_L13 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.3))
SEC_L122 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.22))
JL = secj(SEC_L)
REC_L = { 'uid' => 'pt_pk_1_1', 'family' => 'PK', 'name' => 'PK-L', 'title' => 'L Kanal', 'section' => JL, 'concrete' => 'C30/37',
          'fw_bottom' => false, 'fw_sides' => true, 'fw_inner' => true, 'fw_ends' => false, 'fw_ledge' => true,
          'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'geom_sig' => M.mst_pk_geom_sig(SEC_L, 0.15, 0.15), 'created_at' => '2026-11-10T10:00:00+03:00',
          'pk_rev' => 1, 'rev_log' => [{ 'rev' => 1, 'at' => '2026-11-10T10:00:00+03:00', 'note' => 'oluşturuldu' }] }.freeze
REC_PD = { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 }.freeze
REC_L13 = REC_L.merge('uid' => 'pt_pk_2_2', 'name' => 'PK-L13', 'section' => secj(SEC_L13), 'geom_sig' => M.mst_pk_geom_sig(SEC_L13, 0.15, 0.15)).freeze
# yerleşim (Prekast Yerleşimi; kq3 BK fikstürü): BK x 0–1 / 4–5 (Y yönü, üst 3,00, başlangıç cebi Y 2,00–3,24 derinlik 0,80), PD 0,30
def place(n_pk, extra = {}, lib = [REC_PD, REC_L])
  fresh_model; $grp = nil
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(lib))
  l = bk_y(9101, 0.0, 1.0); r = bk_y(9102, 4.0, 5.0)
  $model.selection.push(l, r)
  rows = [{ 'type_uid' => 'pt_pk_1_1', 'count' => n_pk }, { 'type_uid' => 'pd1', 'count' => 1 }]
  data = { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(lib), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '2.02',
           'channel_fw_inner' => '1', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }.merge(extra)
  ok = M.create_flat_precast(data)
  $model.selection.clear; ops_clear
  [ok, pks.sort_by { |e| e.transformation.to_a[13] }, l, r]
end
RQS = ->(kod, sec, h = {}) { { 'kod' => kod, 'ad' => "#{kod} adı", 'section' => secj(sec), 'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'uygula' => 'secim' }.merge(h) }

# ---------------------------------------------------------------- 1. "Yalnız bu eleman(lar)" — Group
ok, ps, = place(2, 'pd_joint_m' => '0.12')   # karar 9: derz 0,12 → 1,30'a genişleme (iki yana 0,05) komşuyla çakışmaz
a, b = ps
t('1.0 fikstür: 2 Group PK, tipe bağlı, beton 0,36 × 3,30 = 1,188', [ok, ps.length, ps.map { |e| e.is_a?(Sketchup::Group) }, ps.map { |e| e.get_attribute(D, 'precast_type_uid') }, ps.map { |e| near(vol(e), 1.188, 1e-9) }],
  [true, 2, [true, true], %w[pt_pk_1_1 pt_pk_1_1], [true, true]])
uid_a = a.get_attribute(D, 'element_uid'); rv_a = a.get_attribute(D, 'revision'); lib0 = libtxt
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
t('1.1 seçim yok → ok false, işlem açılmaz, kütüphane aynı', [r['ok'], r['neden'].to_s.include?('seçili kanal prekastı'), ops, libtxt == lib0, r['guncellenen']], [false, true, [], true, 0])
sel(a); ops_clear
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13, 'concrete' => 'C35/45', 'fw' => { 'bottom' => false, 'sides' => true, 'inner' => true, 'ends' => false, 'ledge' => true }, 'channel_top_ref' => nil), $model)
nu = r['tip'] && r['tip']['uid']
t('1.2 kaydedildi + uygulandı: tek normal işlem "Kaydet ve Uygula" (transparent değil), guncellenen 1',
  [r['ok'], r['durum'], r['guncellenen'], $model.ops, $op_args.map { |x| x[3] }], [true, 'kaydedildi', 1, [[:start, 'MST PK Tipini Kaydet ve Uygula'], [:commit]], [nil]])
ea = attrs(a)
t('1.3 seçili PK: yeni tip kodu / uid / rev 1, element_uid ve revision aynı, kesit 1,30, beton 0,38 × 3,30 = 1,254, C35/45',
  [ea['precast_type_id'], ea['precast_type_uid'] == nu, ea['precast_type_rev'], ea['element_uid'] == uid_a, ea['revision'] == rv_a, near(ea['width_m'], 1.3), M.mst_ch_parse(ea['channel_section_json'].to_s)&.fetch('total_width_m'), near(ea['concrete_volume_m3'], 1.254, 1e-9), ea['concrete_class']],
  ['PK-L2', true, 1, true, true, true, 1.3, true, 'C35/45'])
t('1.4 kalıp = kesitten (rol formülü, yan + iç), kot TOP: alt 2,50 / üst 3,30 (yükseklik aynı)',
  [near(ea['formwork_area_m2'], M.mst_ch_formwork(SEC_L13, 3.3, { bottom: false, sides: true, inner: true, ends: false, ledge: true }), 1e-9), near(ea['bottom_elevation_m'], 2.5), near(ea['top_elevation_m'], 3.3)], [true, true, true])
eb = attrs(b)
t('1.5 seçilmeyen PK değişmez (eski tip / rev / beton)', [eb['precast_type_id'], eb['precast_type_uid'], eb['precast_type_rev'], near(eb['concrete_volume_m3'], 1.188, 1e-9)], ['PK-L', 'pt_pk_1_1', 1, true])
t('1.6 Group geometri yeniden kuruldu (kesit yüzü alanı 0,38 m²)', a.entities.grep(Sketchup::Face).map { |f| (f.area / IN / IN).round(6) }.include?(0.38), true)
# karar "mevcut": diğer PK'ya mevcut PK-L2 tipi (yeni kayıt yok)
sel(b); ops_clear; l1 = libtxt
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13, 'karar' => 'mevcut'), $model)
t('1.7 karar mevcut: mevcut_secildi + "MST PK Tipini Uygula" tek işlem, kütüphane aynı, PK yeni tipte',
  [r['ok'], r['durum'], r['guncellenen'], $model.ops, libtxt == l1, b.get_attribute(D, 'precast_type_uid') == nu, near(vol(b), 1.254, 1e-9)], [true, 'mevcut_secildi', 1, [[:start, 'MST PK Tipini Uygula'], [:commit]], true, true, true])
# oturma 0,15 → 0,25: boy 3,50, başlangıç −0,10 (yerel X = dünya X). 43/1 (karar 10): açıklıkta PD varken oturma farkı reddedilir → yalnız PK yerleşimi
ok, ps, = place(1, {}, [REC_L]); a = ps[0]; x0 = a.transformation.to_a[12] / IN; sel(a)
r = M.mst_pk_type_save(RQS.('PK-L25', SEC_L, 'seat_left_m' => 0.25, 'seat_right_m' => 0.25), $model)
t('1.8 oturma 0,25: boy 3,50, beton 0,36 × 3,50 = 1,260, başlangıç x −0,10, seat_each_side_m 0,25',
  [r['ok'], near(a.get_attribute(D, 'length_m'), 3.5), near(vol(a), 1.26, 1e-9), near(a.transformation.to_a[12] / IN, x0 - 0.1, 1e-9), a.get_attribute(D, 'seat_each_side_m')], [true, true, true, true, 0.25])
ok, ps, = place(1); sel(ps[0]); l1 = libtxt
r = M.mst_pk_type_save(RQS.('PK-LX', SEC_L, 'seat_right_m' => 0.25), $model)
t('1.9 yerleşim PK + sol ≠ sağ oturma: ok false, işlem / kayıt yok', [r['ok'], r['neden'].to_s.include?('eşit oturma'), ops, libtxt == l1], [false, true, [], true])
ok, ps, = place(1, 'pk_elevation_mode' => 'POCKET'); sel(ps[0]); l1 = libtxt
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
t('1.10 POCKET + cebe sığmayan kesit (1,30 > cep 1,24): ok false (cep uyumu), işlem / kayıt yok', [ok, r['ok'], r['neden'].to_s.include?('cep uyumu'), ops, libtxt == l1], [true, false, true, [], true])
ok, ps, = place(1, {}, [REC_L]); sel(ps[0]); $transform_fail = true   # 43/1: PD'siz (oturma farkı uygunluk reddine takılmadan hata yolu)
r = M.mst_pk_type_save(RQS.('PK-L26', SEC_L, 'seat_left_m' => 0.26, 'seat_right_m' => 0.26), $model)
$transform_fail = false
t('1.11 hata → abort (tek işlem, commit yok), ok false, guncellenen 0', [r['ok'], ops, r['guncellenen'], r['neden'].to_s.include?('geri alındı')], [false, %i[start abort], 0, true])

# ---------------------------------------------------------------- 2. "Yalnız bu eleman" — Component (çok kopyalı tanım değişmez)
ok, ps, = place(2, 'pd_body_mode' => 'COMPONENT', 'pd_joint_m' => '0.12')
a, b = ps
cmp = ps.length == 2 && ps.all? { |e| e.is_a?(Sketchup::ComponentInstance) } && a.definition == b.definition
t('2.0 fikstür: 2 Component PK aynı tanımı paylaşır', [ok, cmp], [true, true])
if cmp
  d0 = b.definition; n0 = d0.entities.length; f0 = d0.entities.dup; uid_a = a.get_attribute(D, 'element_uid')
  sel(a)
  r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
  t('2.1 seçili örnek yeni tanıma geçti; diğer örneğin tanımı ve tanım içeriği aynı (yerinde düzenleme yok)',
    [r['ok'], a.definition != d0, b.definition.equal?(d0), d0.entities.length == n0 && d0.entities.each_with_index.all? { |x, i| x.equal?(f0[i]) }, d0.instances], [true, true, true, true, [b]])
  t('2.2 element_uid aynı, beton 1,254, kalıp = yeni tanımın işaretli yüzleri', [a.get_attribute(D, 'element_uid') == uid_a, near(vol(a), 1.254, 1e-9), near(a.get_attribute(D, 'formwork_area_m2'), M.mst_marked_area_m2(a.definition.entities), 1e-9)], [true, true, true])
end

# ---------------------------------------------------------------- 3. "Tüm örnekler" — plan
def three(lib = [REC_PD, REC_L, REC_L13], joint = '0.12')
  ok, ps, = place(3, { 'pd_joint_m' => joint }, lib)
  ps[0].set_attribute(D, 'structure', 'ANO-01'); ps[1].set_attribute(D, 'structure', 'ANO-01'); ps[2].set_attribute(D, 'structure', 'RIHTIM-01')
  $model.set_attribute(D, 'active_ano', 'ANO-01'); ops_clear
  ps
end
ps = three
RQ = { 'tip_uid' => 'pt_pk_1_1', 'section' => secj(SEC_L122), 'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'concrete' => 'C30/37',
       'fw' => { 'bottom' => false, 'sides' => true, 'inner' => true, 'ends' => false, 'ledge' => true }, 'channel_top_ref' => nil, 'kapsam' => 'yapi' }.freeze
l0 = libtxt; pl = nil
M.send(:mst_plan_readonly) { pl = M.mst_pk_update_build(RQ, $model)[0] }
t('3.1 plan (yapi gönderilmedi → etkin yapı ANO-01 + yapi_ad): 2 örnek kapsamda, RIHTIM-01 1 adet kapsam dışı, başlatılabilir, yeni rev 2, geom değişti',
  [pl['ok'], pl['kapsam'], pl['yapi'], pl['yapi_ad'].is_a?(String) && !pl['yapi_ad'].empty?, pl['ornekler'].length, pl['yapi_ozet'].map { |y| [y['yapi'], y['adet'], y['uygun_degil']] }, pl['kapsam_disi'], pl['baslatilabilir'], pl['yeni_rev'], pl['tip'] && pl['tip']['kod'], pl['geom_degisti']],
  [true, 'yapi', 'ANO-01', true, 2, [['ANO-01', 2, 0]], [{ 'yapi' => 'RIHTIM-01', 'adet' => 1 }], true, 2, 'PK-L', true])
t('3.2 plan salt okuma: yazım yok, işlem yok, kütüphane bayt aynı', [$writes, ops, libtxt == l0], [[], [], true])
t('3.2b örnek satırı alanları', pl['ornekler'][0].keys.sort, %w[kod nedenler pid uid uyarilar uygun yapi])
M.send(:mst_plan_readonly) { pl = M.mst_pk_update_build(RQ.merge('kapsam' => 'model'), $model)[0] }
t('3.3 kapsam model: 3 örnek, kapsam dışı yok, yapı özeti iki yapı', [pl['ornekler'].length, pl['kapsam_disi'], pl['yapi_ozet'].map { |y| y['yapi'] }, pl['yapi']], [3, [], %w[ANO-01 RIHTIM-01], nil])
M.send(:mst_plan_readonly) { pl = M.mst_pk_update_build(RQ.merge('section' => secj(SEC_L13)), $model)[0] }
t('3.4 aynı geom_sig başka kayıtta (PK-L13) → başlatılamaz, birleşme yok', [pl['ok'], pl['baslatilabilir'], pl['neden'].to_s.include?('PK-L13') && pl['neden'].to_s.include?('birleştirilmez')], [true, false, true])
r = M.mst_pk_type_update_apply(RQ.merge('section' => secj(SEC_L13), 'onay' => true), $model)
t('3.5 apply aynı geom_sig: ok false, işlem yok, kütüphane bayt aynı', [r['ok'], ops, libtxt == l0], [false, [], true])
r = M.mst_pk_type_update_apply(RQ, $model)
t('3.6 apply onaysız: ok false, işlem yok', [r['ok'], ops], [false, []])
ok, ps, = place(1, 'pk_elevation_mode' => 'POCKET'); ps[0].set_attribute(D, 'structure', 'ANO-01'); $model.set_attribute(D, 'active_ano', 'ANO-01'); ops_clear
M.send(:mst_plan_readonly) { pl = M.mst_pk_update_build(RQ.merge('section' => secj(SEC_L13)), $model)[0] }
t('3.7 POCKET örnek cebe sığmaz → uygun false, nedenler, başlatılamaz', [pl['ornekler'].map { |o| o['uygun'] }, pl['ornekler'][0] && pl['ornekler'][0]['nedenler'].join.include?('cep uyumu'), pl['baslatilabilir'], pl['yapi_ozet'][0] && pl['yapi_ozet'][0]['uygun_degil']], [[false], true, false, 1])
r = M.mst_pk_type_update_apply(RQ.merge('section' => secj(SEC_L13), 'onay' => true), $model)
t('3.8 apply uymayan örnekle: işlem açılmaz', [r['ok'], ops], [false, []])
M.send(:mst_plan_readonly) { pl = M.mst_pk_update_build(RQ, $model)[0] }
t('3.9 1,22 ortadan (Y 2,01–3,23, cep 2,00–3,24) sığar → uygun', [pl['ornekler'].map { |o| o['uygun'] }, pl['baslatilabilir']], [[true], true])

# ---------------------------------------------------------------- 4. "Tüm örnekler" — apply
ps = three([REC_PD, REC_L]); uids = ps.map { |e| e.get_attribute(D, 'element_uid') }; l0 = libtxt
r = M.mst_pk_type_update_apply(RQ.merge('section' => secj(SEC_L13), 'onay' => true, 'plan_pids' => ps[0, 2].map(&:persistent_id)), $model)   # 42 Ö3: plan_pids
t('4.1 apply yapı ANO-01: tek normal işlem "MST PK Tipini Güncelle", guncellenen 2, tip rev 2, kapsam dışı uyarısı',
  [r['ok'], $model.ops, $op_args.map { |x| x[3] }, r['guncellenen'], r['tip'], r['uyarilar'].to_a.join.include?('eski revizyonda')],
  [true, [[:start, 'MST PK Tipini Güncelle'], [:commit]], [nil], 2, { 'uid' => 'pt_pk_1_1', 'kod' => 'PK-L', 'rev' => 2 }, true])
t('4.2 kapsam içi: rev 2, beton 1,254; kapsam dışı (RIHTIM-01): rev 1, beton 1,188; element_uid hepsi aynı',
  [ps.map { |e| e.get_attribute(D, 'precast_type_rev') }, ps.map { |e| vol(e).round(6) }, ps.map { |e| e.get_attribute(D, 'element_uid') } == uids], [[2, 2, 1], [1.254, 1.254, 1.188], true])
nl = JSON.parse(libtxt); nrec = nl.find { |x| x['uid'] == 'pt_pk_1_1' } || {}; le = (nrec['rev_log'] || [{}]).last
t('4.3 kayıt: pk_rev 2, section 1,30, geom_sig yeni; rev_log eski kayıt korunur + {rev 2, kapsam yapi, yapı ANO-01, kesit / oturma anlık görüntüsü, önceki rev 1 kesit 1,20}',
  [nrec['pk_rev'], nrec['section'] && nrec['section']['total_width_m'], nrec['geom_sig'] == M.mst_pk_geom_sig(SEC_L13, 0.15, 0.15), nrec['rev_log'] && nrec['rev_log'][0] == REC_L['rev_log'][0], le['rev'], le['kapsam'], le['yapi'], le['section'] && le['section']['total_width_m'], le['seat_left_m'], le['onceki'] && le['onceki']['rev'], le['onceki'] && le['onceki']['section']['total_width_m'], le['at'].to_s.empty?],
  [2, 1.3, true, true, 2, 'yapi', 'ANO-01', 1.3, 0.15, 1, 1.2, false])
t('4.4 diğer kayıt (PD-01) JSON metni bayt aynı', [l0.include?(JSON.generate(REC_PD)), libtxt.include?(JSON.generate(REC_PD))], [true, true])
cat = M.mst_pk_type_catalog($model).find { |x| x['uid'] == 'pt_pk_1_1' }
t('4.5 katalog kullanim: RIHTIM-01 eski_rev 1, ANO-01 eski_rev 0', cat && cat['kullanim'].map { |k| [k['yapi'], k['adet'], k['eski_rev']] }, [['ANO-01', 2, 0], ['RIHTIM-01', 1, 1]])
ok, ps, = place(1, {}, [REC_L]); $transform_fail = true   # 43/1: PD'siz; 42 Ö3: plan_pids
r = M.mst_pk_type_update_apply(RQ.merge('kapsam' => 'model', 'seat_left_m' => 0.3, 'seat_right_m' => 0.3, 'onay' => true, 'plan_pids' => ps.map(&:persistent_id)), $model)
$transform_fail = false
t('4.6 hata → abort, ok false, guncellenen 0', [r['ok'], ops, r['guncellenen'], r['neden'].to_s.include?('geri alındı')], [false, %i[start abort], 0, true])

# ---------------------------------------------------------------- 5. PK Sil + döşeme (kp4 fikstürü: BK X yönü, PK kesiti dünya Y)
$regen = []
M.singleton_class.send(:alias_method, :kq4_regen_orig, :mst_deck_regenerate!)
M.define_singleton_method(:mst_deck_regenerate!) do |dk, _m = nil, _s = false|
  raise 'sahte yeniden üretim hatası' if $regen_fail
  $regen << dk
  hbs = M.mst_deck_support_beams(dk); ins = M.mst_deck_inputs($model, hbs, {}); pl = M.mst_deck_plan(ins[2], ins[3], 0.4, ins[4])
  dk.set_attribute(D, 'deck_plan_json', JSON.generate(pl))
  { 'id' => 'D-001', 'old' => [0.0, 0.0], 'new' => [pl['volume'], 0.0], 'warnings' => [], 'rev' => 1 }
end
def bkx(pid, x0, x1, w = 4.0, top = 3.0)
  b = Sketchup::Group.new(pid, 'element_type' => 'head_beam', 'element_uid' => "BK-U#{pid}", 'head_beam_id' => "BK#{pid}", 'top_elevation_m' => top)
  b.bounds = Geom::BoundingBox.new([x0 * IN, 0, (top - 1.0) * IN], [x1 * IN, w * IN, top * IN]); put(b)
end
def pkx(pid, y0)
  e = Sketchup::Group.new(pid, 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => "PK#{pid}", 'element_uid' => "PK-U#{pid}", 'precast_type_id' => 'PK-L',
                               'support_left_pid' => 9001, 'support_right_pid' => 9002, 'inner_width_m' => 0.0, 'inner_depth_m' => 0.0, 'base_thickness_m' => 0.0, 'wall_thickness_m' => 0.0,
                               'channel_section_json' => M.mst_ch_json(SEC_L), 'length_m' => 3.0, 'bottom_elevation_m' => 2.5, 'top_elevation_m' => 3.3)
  e.transformation = Geom::Transformation.new([[1, 0, 0], [0, 1, 0], [0, 0, 1]], [1.0 * IN, y0 * IN, 2.5 * IN])
  e.bounds = Geom::BoundingBox.new([1.0 * IN, y0 * IN, 2.5 * IN], [4.0 * IN, (y0 + 1.2) * IN, 3.3 * IN]); put(e)
end
def deck_model
  fresh_model; $regen_fail = false
  bkx(9001, 0.0, 1.0); bkx(9002, 4.0, 5.0); a = pkx(9601, 0.0); b = pkx(9602, 2.0)
  d = Sketchup::Group.new(9501, 'element_type' => 'deck_slab', 'deck_id' => 'D-001', 'support_pids' => '9001,9002', 'deck_plan_json' => '{"boxes":[]}'); put(d)
  other = Sketchup::Group.new(9502, 'element_type' => 'deck_slab', 'deck_id' => 'D-002', 'support_pids' => '9003', 'deck_plan_json' => '{"boxes":[]}'); put(other)
  M.mst_deck_regenerate!(d); $regen = []; ops_clear
  [a, b, d, other]
end
a, b, d, other = deck_model
before = JSON.parse(d.get_attribute(D, 'deck_plan_json'))['openings']
vol0 = JSON.parse(d.get_attribute(D, 'deck_plan_json'))['volume']; oth0 = other.get_attribute(D, 'deck_plan_json')
r = M.mst_pk_delete($model)
t('5.1 seçim yok → ok false, işlem açılmaz', [r['ok'], ops, r['silinen'], r['dosemeler']], [false, [], 0, 0])
sel(a); ops_clear
r = M.mst_pk_delete($model)
after = JSON.parse(d.get_attribute(D, 'deck_plan_json'))['openings']
t('5.2 PK Sil: tek normal işlem "MST Kanal Prekastı Sil" (transparent değil), silinen 1 / dosemeler 1 (sayı), yalnız bağlı döşeme yenilendi',
  [r['ok'], $model.ops, $op_args.map { |x| x[3] }, r['silinen'], r['dosemeler'], r['silinen'].is_a?(Integer) && r['dosemeler'].is_a?(Integer), $regen, a.valid?, b.valid?],
  [true, [[:start, 'MST Kanal Prekastı Sil'], [:commit]], [nil], 1, 1, true, [d], false, true])
t('5.3 döşeme: silinen PK9601 açıklığı kalktı, PK9602 açıklığı birebir aynı',
  [before.map { |o| o['id'] }.uniq.sort, after.map { |o| o['id'] }.uniq, after == before.select { |o| o['id'] == 'PK9602' }], [%w[PK9601 PK9602], ['PK9602'], true])
# 43/4 (metraj kontrolü 43 §4, elle beklenen): silinen PK yerinde döşeme net beton artışı 1,38 m³ (açıklık + prekast cebi kalkar, şerit
# "PD yok" sayılıp tam kalınlık); diğer döşeme (D-002) değişmez
vol1 = JSON.parse(d.get_attribute(D, 'deck_plan_json'))['volume']
t('5.3b PK Sil: döşeme net beton artışı 1,38 m³ (elle beklenen, rapor 43 §4), diğer döşeme aynı', [(vol1 - vol0).round(9), other.get_attribute(D, 'deck_plan_json') == oth0], [1.38, true])
a, b, d, = deck_model; sel(a); $regen_fail = true
r = M.mst_pk_delete($model); $regen_fail = false
t('5.4 döşeme hatası → abort, ok false', [r['ok'], ops, r['neden'].to_s.include?('geri alındı')], [false, %i[start abort], true])
a, b, d, = deck_model; sel(b)
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13).reject { |k, _| k.start_with?('seat') }, $model)
t('5.5 secim + döşeme: tek işlem (start 1), döşeme aynı işlemde yenilendi, transparent işlem yok',
  [r['ok'], ops, $regen, $op_args.map { |x| x[3] }], [true, %i[start commit], [d], [nil]])
M.singleton_class.send(:alias_method, :mst_deck_regenerate!, :kq4_regen_orig)
t('5.6 P4 yolları transparent mst_deck_after_edit çağırmaz',
  %w[mst_pk_type_save_sel mst_pk_type_update_apply mst_pk_delete mst_pk_decks_regen!].map { |f| src[/^def #{Regexp.escape(f)}.*?^end\n/m].to_s.include?('mst_deck_after_edit') }, [false, false, false, false])

# ---------------------------------------------------------------- 6. karar 9: ortadan büyüme / küçülme, komşu çakışması, derz uyarısı, layout_width_m
SEC_L10 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.0))
ys = ->(e) { e.transformation.to_a[13] / IN }
ok, ps, = place(2, 'pd_joint_m' => '0.12'); a, b = ps; ya = ys.(a); yb = ys.(b); sel(a)
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
t('6.1 genişleme 1,20 → 1,30 ortadan: başlangıç y −0,05 (merkez sabit), komşu kaydırılmaz, width / layout_width_m 1,30',
  [r['ok'], near(ys.(a), ya - 0.05, 1e-9), near(ys.(b), yb, 1e-12), near(a.get_attribute(D, 'width_m'), 1.3), near(a.get_attribute(D, 'layout_width_m'), 1.3)], [true, true, true, true, true])
pid_b = M.element_visible_id(b)
t('6.2 derz azalması (0,12 → 0,07): uygun, uyarı "komşu … ile derz 70 mm (kayıtlı derz 120 mm)"',
  r['uyarilar'].to_a.any? { |w| w.include?("komşu #{pid_b} ile derz 70 mm") && w.include?('kayıtlı derz 120 mm') }, true)
ok, ps, = place(2); a, b = ps; ya = ys.(a); sel(a); l1 = libtxt
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
t('6.3 derz 0,02 + iki yana 0,05 → komşuyla 30 mm çakışır: ok false, metin, işlem / kayıt yok, konum aynı',
  [r['ok'], r['neden'].to_s.include?("komşu #{M.element_visible_id(b)} ile 30 mm çakışır"), ops, libtxt == l1, near(ys.(a), ya, 1e-12)], [false, true, [], true, true])
ok, ps, = place(2); a, b = ps; ya = ys.(a); sel(a)
r = M.mst_pk_type_save(RQS.('PK-L118', M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.18))), $model)   # 43/3: 1,00'a küçülme (derz 120 mm) kq6'da reddedilir
t('6.4 küçülme 1,20 → 1,18: çakışma / derz uyarısı yok, ortadan (y +0,01), layout_width_m 1,18',
  [r['ok'], r['uyarilar'].to_a.grep(/komşu/), near(ys.(a), ya + 0.01, 1e-9), near(a.get_attribute(D, 'layout_width_m'), 1.18)], [true, [], true, true])
ps = three([REC_PD, REC_L], '0.02')
M.send(:mst_plan_readonly) { pl = M.mst_pk_update_build(RQ.merge('section' => secj(SEC_L13)), $model)[0] }
o0 = pl['ornekler'].find { |o| o['pid'] == ps[0].persistent_id } || {}; o1 = pl['ornekler'].find { |o| o['pid'] == ps[1].persistent_id } || {}
t('6.5 tüm örnekler (iki komşu birlikte genişler): 0,02 − 2 × 0,05 → 80 mm, kapsam dışı komşuyla 30 mm; uygun değil, başlatılamaz',
  [o0['uygun'], o0['nedenler'].to_a.join.include?("komşu #{M.element_visible_id(ps[1])} ile 80 mm çakışır"), o1['nedenler'].to_a.join.include?("komşu #{M.element_visible_id(ps[2])} ile 30 mm çakışır"), pl['baslatilabilir']],
  [false, true, true, false])
ps = three([REC_PD, REC_L])
M.send(:mst_plan_readonly) { pl = M.mst_pk_update_build(RQ.merge('section' => secj(SEC_L13)), $model)[0] }
o0 = pl['ornekler'].find { |o| o['pid'] == ps[0].persistent_id } || {}
t('6.6 plan derz 0,12: uygun, örnek uyarısı (0,12 − 2 × 0,05 = 20 mm), başlatılabilir',
  [o0['uygun'], o0['uyarilar'].to_a.join.include?("komşu #{M.element_visible_id(ps[1])} ile derz 20 mm"), pl['baslatilabilir']], [true, true, true])

puts "\nKQ4: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
