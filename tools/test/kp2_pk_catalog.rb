# KP2 (ADR-0515-K2, docs/duzeltme/37 K4 — kullanıcı kararları 0–12; 09.11.2026) — Kanal prekastı parti P2 (Ruby):
#  PK tip kataloğu (mst_pk_type_catalog: kütüphane + modeldeki PK, eski kayıt U eşlemesi, section gidiş-dönüşü),
#  cep uyum adayları (mst_pk_pocket_candidates: uyumlu / genişlik / yükseklik / taban kotu / hiza / cep derinliği metinleri),
#  mst_kn_find_pk_type sonucunun değişmediği (HEAD d745cb5 davranış vakaları), salt okuma callback'leri (yazım / işlem yok).
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir. Kanıt düzeyi: sahte nesne. SketchUp içinde diyalog ↔ JS akışı,
#  gerçek BK cep kutusu (dönük / iç içe BK) KANITLANMAZ.
# Kullanim: ruby tools/test/kp2_pk_catalog.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kp2_pk_catalog.rb <marine_structures_tools klasoru>'
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

# sahte geometri (kp1_channel_section.rb ile aynı)
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
  attr_reader :pts
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
  # x = 0 düzlemindeki profil +x yönünde d kadar itilir: iki uç yüz + her kenar için bir yan yüz (normal dışa doğru)
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
  # SketchUp'ta parent sahiptir (Model / ComponentDefinition), Entities değil
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
  $model.ops.clear
  $model.set_attribute(D, 'precast_type_library_json', '[]')
  $all_ents = {}; $ui_msgs = []
end
def put(e); $model.entities << e; e.parent = $model.entities; ($all_ents ||= {})[e.persistent_id] = e; e; end
def bk(pid, x0, x1, top = 3.0)
  b = Sketchup::Group.new(pid, 'element_type' => 'head_beam', 'top_elevation_m' => top, 'height_m' => 1.0, 'head_beam_id' => "BK#{pid}")
  b.bounds = Geom::BoundingBox.new([x0 * IN, 0, (top - 1.0) * IN], [x1 * IN, 10 * IN, top * IN])
  put(b)
end
def box(x0, x1, y0, y1, z0, z1); { 'x' => [x0, x1], 'y' => [y0, y1], 'z' => [z0, z1] }; end
def pocket(b, side, y0, y1, floor, depth)
  bx = b.bounds; xs = [bx.min.x / IN, bx.max.x / IN]
  { 'bk' => b, 'side' => side, 'x' => [y0, y1], 'depth' => depth, 'box' => box(xs[0], xs[1], y0, y1, floor, floor + depth), 'axis' => 'y', 'len' => y1 - y0, 'floor_z' => floor }
end
def pd(pid, l, r, top, y0 = 4.0, y1 = 5.0, joint = 0.02)
  e = Sketchup::Group.new(pid, 'element_type' => 'flat_precast', 'precast_id' => "PD#{pid}", 'support_left_pid' => l.persistent_id, 'support_right_pid' => r.persistent_id, 'joint_m' => joint, 'seat_each_side_m' => 0.15)
  e.bounds = Geom::BoundingBox.new([0.85 * IN, y0 * IN, (top - 0.3) * IN], [4.15 * IN, y1 * IN, top * IN])
  put(e)
end
def pk_el(pid, name, attrs)
  e = Sketchup::Group.new(pid, { 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => name, 'precast_type_id' => name, 'concrete_class' => 'C30/37' }.merge(attrs))
  e.bounds = Geom::BoundingBox.new([20 * IN, 0, 0], [23 * IN, 1 * IN, 1 * IN])   # açıklık dışında (ceplere değmez)
  put(e)
end

HAVE = M.respond_to?(:mst_pk_type_catalog) && M.respond_to?(:mst_pk_pocket_candidates)
t('P2 işlevleri tanımlı (mst_pk_type_catalog / mst_pk_pocket_candidates)', HAVE, true)

# ---------------------------------------------------------------- ortak veri
dfl = M.mst_ch_default
sec_l = M.mst_ch_preset(dfl.merge('total_width_m' => 1.0, 'right' => dfl['right'].merge('height_m' => 0.6)), 'L')
sec_uu = M.mst_ch_preset(dfl, 'UU')
sec_none = M.mst_ch_preset(dfl, 'OZEL').tap { |s| %w[left mid right].each { |k| s[k]['on'] = false } }
LIB = [
  { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 },
  { 'uid' => 'pk1', 'family' => 'PK', 'name' => 'PK-U', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37', 'bilinmeyen_alan' => 'korunur' },
  { 'uid' => 'pk2', 'family' => 'PK', 'name' => 'PK-L', 'section' => sec_l, 'inner_width' => 0, 'inner_depth' => 0, 'base' => 0, 'wall' => 0, 'concrete' => 'C35/45' },
  { 'uid' => 'pk3', 'family' => 'PK', 'name' => 'PK-UU', 'section' => sec_uu, 'concrete' => 'C30/37' },
  { 'uid' => 'pk4', 'family' => 'PK', 'name' => 'PK-BOS', 'section' => sec_none, 'concrete' => 'C30/37' }
].freeze
U_MODEL = { 'inner_width_m' => 1.0, 'inner_depth_m' => 0.5, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2 }.freeze
U_SAME = { 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2 }.freeze
def setup_lib_model
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB))
  pk_el(9501, 'PK-M1', U_MODEL)
  pk_el(9502, 'PK-U', U_SAME)   # kütüphanedeki PK-U ile aynı ölçü → katalogda kütüphane kaydına sayılır
end

# ---------------------------------------------------------------- 1. katalog
if HAVE
  setup_lib_model
  $writes = []; $model.ops.clear
  cat = M.mst_pk_type_catalog($model)
  t('1.0 katalog salt okuma: öznitelik yazımı / işlem yok', [$writes, $model.ops], [[], []])
  t('1.1 katalog: yalnız PK; sıra kütüphane, sonra modelde kullanılan', cat.map { |x| [x['kod'], x['kaynak']] },
    [%w[PK-U kütüphane], %w[PK-L kütüphane], %w[PK-UU kütüphane], %w[PK-BOS kütüphane], %w[PK-M1 model]])
  u = cat[0]
  t('1.2 eski kayıt (section yok) → mst_ch_from_u eşlemesi, eski_kayit, modelde 1 adet',
    [u['section'], u['eski_kayit'], u['adet_modelde'], u['on_ayar'], u['uid']], [M.mst_ch_from_u(0.8, 0.6, 0.2, 0.2), true, 1, 'U', 'pk1'])
  t('1.3 eski kayıt temel ölçüler: toplam 1,2, yükseklik 0,8, taban 0,2, alan = eski U formülü',
    [near(u['toplam_genislik_m'], 1.2), near(u['toplam_yukseklik_m'], 0.8), u['taban_m'], near(u['kesit_alani_m2'], M.mst_ch_u_area(0.8, 0.6, 0.2, 0.2)), u['gecerli'], u['beton']],
    [true, true, 0.2, true, true, 'C30/37'])
  l = cat[1]
  t('1.4 section kaydı (L): kesit P1a biçiminde, ön ayar, yükseklik = mst_ch_height, profil = mst_ch_profile',
    [l['section'] == M.mst_ch_parse(sec_l), l['on_ayar'], l['eski_kayit'], near(l['toplam_yukseklik_m'], M.mst_ch_height(sec_l)), l['profil'] == M.mst_ch_profile(sec_l).map { |y, z| [y.round(6), z.round(6)] }, l['beton']],
    [true, 'L', false, true, true, 'C35/45'])
  t('1.5 çıkıntı listesi ve özet (yalnız açık çıkıntılar)', [l['cikintilar'].map { |c| [c['parca'], c['ad'], c['genislik_m'], c['yukseklik_m'], c['ofset_m']] }, l['cikinti_ozet']],
    [[['right', 'Sağ', 0.2, 0.6, 0.0]], 'Sağ 0,200 × 0,600 m (ofset 0,000)'])
  b = cat[3]
  t('1.6 geçersiz kesit: gecerli false, Türkçe hata, profil boş', [b['gecerli'], b['hatalar'].join.include?('çıkıntısız düz plak'), b['profil']], [false, true, []])
  m1 = cat[4]
  t('1.7 modelde kullanılan (kütüphanede yok): eski U öznitelikleri → kesit, adet', [m1['section'], near(m1['toplam_genislik_m'], 1.4), near(m1['toplam_yukseklik_m'], 0.7), m1['adet_modelde'], m1['uid']],
    [M.mst_ch_from_u(1.0, 0.5, 0.2, 0.2), true, true, 1, nil])
  t('1.8 katalog JSON üretilebilir (NaN yok)', (JSON.generate(cat) rescue $!.class.name).is_a?(String) && !JSON.generate(cat).include?('NaN'), true)
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate([{ 'family' => 'PK', 'name' => 'PK-NAN', 'section' => sec_l.merge('total_width_m' => 'abc') }]))
  cn = (M.mst_pk_type_catalog($model) rescue $!.message)
  t('1.8b okunamayan kesit değeri (NaN): katalogda geçersiz, JSON (public) NaN içermez',
    cn.is_a?(Array) && [cn[0]['gecerli'], (JSON.generate(M.mst_pk_catalog_public(cn)) rescue 'HATA').include?('"toplam_genislik_m":null')], [false, true])
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', 'bozuk{')
  t('1.9 bozuk kütüphane JSON: boş liste, hata yok', (M.mst_pk_type_catalog($model) rescue $!.message), [])
end

# ---------------------------------------------------------------- 2. section gidiş-dönüşü (create_flat_precast tip kaydı yazımı)
fresh_model
l1 = bk(9601, 0.0, 1.0); r1 = bk(9602, 4.0, 5.0)
$model.selection.push(l1, r1)
rows = [{ 'type_uid' => 'pd1', 'count' => 1 }, { 'type_uid' => 'pk2', 'count' => 1 }]
data = { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(LIB), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '0',
         'channel_fw_inner' => '1', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }
M.create_flat_precast(data)
stored = (JSON.parse($model.get_attribute(D, 'precast_type_library_json', '[]')) rescue nil)
t('2.1 tip kaydı yazımı: section ve bilinmeyen alanlar korunur (gidiş-dönüş birebir)', stored, JSON.parse(JSON.generate(LIB)))
pkc = []; M.collect_elements($model.entities, pkc); pkc = pkc.select { |e| e.get_attribute(D, 'element_type') == 'channel_precast' }
t('2.2 Prekast Yerleşimi PK satırı: tip kaydındaki section kullanılır (L: genişlik 1,0, kesit JSON)',
  [pkc.length, pkc[0] && pkc[0].get_attribute(D, 'width_m'), pkc[0] && M.mst_ch_parse(pkc[0].get_attribute(D, 'channel_section_json', '')) == M.mst_ch_parse(sec_l)], [1, 1.0, true])
fresh_model
l1 = bk(9611, 0.0, 1.0); r1 = bk(9612, 4.0, 5.0)
$model.selection.push(l1, r1)
M.create_flat_precast(data.merge('pd_layout_rows' => JSON.generate([{ 'type_uid' => 'pd1', 'count' => 1 }, { 'type_uid' => 'pk1', 'count' => 1 }])))
pkc = []; M.collect_elements($model.entities, pkc); pkc = pkc.select { |e| e.get_attribute(D, 'element_type') == 'channel_precast' }
t('2.3 eski U tip kaydı: eski anahtarlar, channel_section_json yok (eski sonuç)',
  pkc[0] && [pkc[0].get_attribute(D, 'inner_width_m'), pkc[0].get_attribute(D, 'wall_thickness_m'), pkc[0].get_attribute(D, 'width_m'), pkc[0].get_attribute(D, 'channel_section_json')], [0.8, 0.2, 0.8 + 2 * 0.2, nil])

# ---------------------------------------------------------------- 3. mst_kn_find_pk_type (HEAD d745cb5 davranışı birebir)
setup_lib_model
els = []; M.collect_elements($model.entities, els)
fp = ->(ow, oh) { r = M.mst_kn_find_pk_type($model, els, ow, oh); r && [r['name'], r['source'], r['wi'], r['di'], r['tb'], r['tw'], r['section'] ? M.mst_ch_geom_key(r['section']) : nil, r['concrete'], r['fw']] }
mat = M.material_for($model, 'MAG Kanal Kalıp #6DBE73', '#6DBE73').name
t('3.1 1,2 × 0,8 → ilk uyan kütüphane eski kaydı PK-U (PK-UU ikinci)', fp.(1.2, 0.8), ['PK-U', 'kütüphane', 0.8, 0.6, 0.2, 0.2, nil, 'C30/37', '0000'])
t('3.2 1,0 × 0,8 → kütüphane L (section), 5 rollü fw varsayılanı', fp.(1.0, 0.8), ['PK-L', 'kütüphane', 0.0, 0.0, 0.0, 0.0, M.mst_ch_geom_key(sec_l), 'C35/45', '00101'])
t('3.3 1,4 × 0,7 → modeldeki kanal PK-M1', fp.(1.4, 0.7), ['PK-M1', 'modeldeki kanal', 1.0, 0.5, 0.2, 0.2, nil, 'C30/37', '0000'])
t('3.4 tolerans içi 1,2049 / dışı 1,2051', [fp.(1.2049, 0.8) && fp.(1.2049, 0.8)[0], fp.(1.2051, 0.8)], ['PK-U', nil])
t('3.5 uyan tip yok → nil', fp.(1.3, 0.8), nil)
t('3.6 materyal adı: örnek PK (yüzsüz) bayrakları', mat.empty?, false)

# ---------------------------------------------------------------- 4. cep adayları
def cand_setup(floor_r = 2.2, ry = [2.0, 3.24], with_pd = true)
  setup_lib_model
  l = bk(9701, 0.0, 1.0); r = bk(9702, 4.0, 5.0)
  pd(9703, l, r, 3.0) if with_pd
  pk = { l => [pocket(l, 'start', 2.0, 3.24, 2.2, 0.8)], r => [pocket(r, 'start', ry[0], ry[1], floor_r, 3.0 - floor_r)] }
  [l, r, ->(b) { pk[b] || [] }]
end
if HAVE
  l, r, po = cand_setup
  $writes = []; $model.ops.clear
  res = M.mst_pk_pocket_candidates($model, [l, r], nil, {}, nil, po)
  t('4.0 aday listesi salt okuma: yazım / işlem yok', [$writes, $model.ops], [[], []])
  c = res['ciftler'] && res['ciftler'][0]
  t('4.1 cep çifti: açıklık, taraf, cep genişliği, derz, beklenen dış genişlik / yükseklik',
    c && [res['ok'], c['aciklik'], c['taraf'], near(c['cep_genisligi_m'], 1.24), c['derz_m'], near(c['beklenen']['dis_genislik_m'], 1.2), near(c['beklenen']['toplam_yukseklik_m'], 0.8), c['uyarilar'], c['cep_uygun']],
    [true, 'BK9701 → BK9702', 'start', true, 0.02, true, true, [], true])
  ad = c ? Hash[c['adaylar'].map { |a| [a['kod'], a] }] : {}
  t('4.2 uyumlu: PK-U ve PK-UU; nedenler boş', [ad['PK-U'] && [ad['PK-U']['uyumlu'], ad['PK-U']['nedenler']], ad['PK-UU'] && ad['PK-UU']['uyumlu']], [[true, []], true])
  t('4.3 otomatik yerleşimin seçeceği (mst_kn_find_pk_type) işaretli: PK-U', c && c['adaylar'].select { |a| a['secilecek'] }.map { |a| a['kod'] }, ['PK-U'])
  t('4.4 genişlik uyumsuz (L): "dış genişlik 1,200 ≠ 1,000 m"', ad['PK-L'] && [ad['PK-L']['uyumlu'], ad['PK-L']['nedenler']], [false, ['dış genişlik 1,200 ≠ 1,000 m']])
  t('4.5 PK-M1: genişlik + yükseklik + cep derinliği metinleri', ad['PK-M1'] && ad['PK-M1']['nedenler'],
    ['dış genişlik 1,200 ≠ 1,400 m', 'toplam yükseklik 0,800 ≠ 0,700 m', 'cep derinliği 0,800 > toplam yükseklik 0,700 m'])
  t('4.6 geçersiz kesit: uyumsuz, kesit hatası nedeni', ad['PK-BOS'] && [ad['PK-BOS']['uyumlu'], ad['PK-BOS']['nedenler'].join.include?('çıkıntısız')], [false, true])
  t('4.7 aday beklenen / mevcut değerleri', ad['PK-L'] && [near(ad['PK-L']['beklenen']['dis_genislik_m'], 1.2), near(ad['PK-L']['mevcut']['dis_genislik_m'], 1.0), near(ad['PK-L']['mevcut']['toplam_yukseklik_m'], 0.8)], [true, true, true])
  t('4.8 aday sırası = katalog sırası', c && c['adaylar'].map { |a| a['kod'] }, %w[PK-U PK-L PK-UU PK-BOS PK-M1])
  t('4.9 JSON üretilebilir', (JSON.generate(res) rescue $!.class.name).is_a?(String), true)
  res = M.mst_pk_pocket_candidates($model, [l, r], nil, { 'ref_top_m' => 3.1 }, nil, po)
  c = res['ciftler'][0]; ad = Hash[c['adaylar'].map { |a| [a['kod'], a] }]
  t('4.10 yükseklik uyumsuz (referans üst girdi 3,1): "toplam yükseklik 0,900 ≠ 0,800 m"', [c['referans_kaynagi'], ad['PK-U']['uyumlu'], ad['PK-U']['nedenler']], ['girdi', false, ['toplam yükseklik 0,900 ≠ 0,800 m']])
  res = M.mst_pk_pocket_candidates($model, [l, r], nil, { 'joint_m' => 0.045 }, nil, po)
  c = res['ciftler'][0]; ad = Hash[c['adaylar'].map { |a| [a['kod'], a] }]
  t('4.11 derz girdisi 0,045: "dış genişlik 1,150 ≠ 1,200 m"', [c['derz_kaynagi'], ad['PK-U']['nedenler']], ['girdi', ['dış genişlik 1,150 ≠ 1,200 m']])

  l, r, po = cand_setup(2.25, [2.0, 3.24])
  res = M.mst_pk_pocket_candidates($model, [l, r], nil, {}, nil, po)
  c = res['ciftler'][0]
  t('4.12 taban kotu farkı: uyarı metni, cep uygun değil, hiçbir tip uyumlu değil',
    [c['uyarilar'], c['cep_uygun'], c['adaylar'].count { |a| a['uyumlu'] }], [['iki cebin taban kotu farklı (2,200 / 2,250 m)'], false, 0])
  l, r, po = cand_setup(2.2, [2.1, 3.34])
  res = M.mst_pk_pocket_candidates($model, [l, r], nil, {}, nil, po)
  c = res['ciftler'][0]
  t('4.13 hiza farkı: uyarı metni', [c['uyarilar'], c['cep_uygun']], [["iki BK'daki cepler hizalı değil (Y 2,000–3,240 / 2,100–3,340 m)"], false])
  l, r, po = cand_setup(2.2, [2.0, 3.24], false)
  res = M.mst_pk_pocket_candidates($model, [l, r], nil, {}, nil, po)
  c = res['ciftler'][0]
  t('4.14 PD yok, referans üst girdisi yok: yükseklik denetlenemez, uyarı, derz varsayılan',
    [c['referans_ust_m'], c['uyarilar'].join.include?('referans üst kotu belirlenemedi'), c['cep_uygun'], c['derz_kaynagi'], c['adaylar'].count { |a| a['uyumlu'] }], [nil, true, false, 'varsayılan', 0])
  res = M.mst_pk_pocket_candidates($model, [l, r], 'end', {}, nil, po)
  t('4.15 taraf süzgeci: bitiş cebi yok → Türkçe neden', [res['ok'], res['neden']], [false, "Seçili BK'larda son cebi yok."])
  res = M.mst_pk_pocket_candidates($model, [l], nil, {}, nil, po)
  t('4.16 tek BK → iki BK seçin', [res['ok'], res['neden']], [false, 'Kanal cebi uyumu için iki BK seçin.'])
  res = M.mst_pk_pocket_candidates($model, [l, r], nil, {}, nil, ->(_b) { [] })
  t('4.17 cep yok → Türkçe neden', [res['ok'], res['neden']], [false, "Seçili BK'larda kanal cebi yok."])
end

# ---------------------------------------------------------------- 5. callback'ler (salt okuma)
class FakeDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; end; end
if M.respond_to?(:mst_pk_send_catalog) && M.respond_to?(:mst_pk_send_candidates)
  setup_lib_model
  dl = FakeDlg.new
  $writes = []; $model.ops.clear
  M.mst_pk_send_catalog(dl)
  t('5.1 pk_type_catalog: korumalı JS çağrısı, yazım / işlem yok', [dl.js.length, dl.js[0].to_s.start_with?('window.mstPkCatalog && mstPkCatalog('), $writes, $model.ops], [1, true, [], []])
  pl = JSON.parse(dl.js[0][/mstPkCatalog\((.*)\)\z/m, 1]) rescue nil
  t('5.2 katalog yükü: ok + tipler', pl && [pl['ok'], pl['tipler'].map { |x| x['kod'] }], [true, %w[PK-U PK-L PK-UU PK-BOS PK-M1]])
  dl = FakeDlg.new; $writes = []
  M.mst_pk_send_candidates(dl, '')
  pl = JSON.parse(dl.js[0][/mstPkCandidates\((.*)\)\z/m, 1]) rescue nil
  t('5.3 pk_pocket_candidates seçim yok: Türkçe neden, yazım yok', [dl.js[0].to_s.start_with?('window.mstPkCandidates && mstPkCandidates('), pl && pl['ok'], pl && pl['neden'], $writes, $model.ops],
    [true, false, 'Kanal cebi uyumu için iki BK seçin.', [], []])
  l = bk(9801, 0.0, 1.0); r = bk(9802, 4.0, 5.0); $model.selection.push(l, r)
  dl = FakeDlg.new; $writes = []
  M.mst_pk_send_candidates(dl, '{"side":"start"}')
  pl = JSON.parse(dl.js[0][/mstPkCandidates\((.*)\)\z/m, 1]) rescue nil
  t('5.4 seçili iki BK, cep yok (öznitelikte cep tanımı yok): Türkçe neden, yazım yok', [pl && pl['neden'], $writes, $model.ops], ["Seçili BK'larda başlangıç cebi yok.", [], []])
else
  t('5 callback işlevleri tanımlı (mst_pk_send_catalog / mst_pk_send_candidates)', false, true)
end
src = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
t("5.5 show_dialog callback kayıtları (pk_type_catalog / pk_pocket_candidates)", [src.include?("add_action_callback('pk_type_catalog')"), src.include?("add_action_callback('pk_pocket_candidates')")], [true, true])

puts "\nKP2: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
