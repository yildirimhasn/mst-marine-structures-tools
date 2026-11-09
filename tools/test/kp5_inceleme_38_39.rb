# KP5 (ADR-0515-K2, docs/duzeltme/38 + 39; kullanıcı kararı 18, 09.11.2026) — kanal prekastı inceleme bulgularının Ruby düzeltmeleri:
#  38 Ö1 (POCKET yerleşiminde PK Y aralığı dünya uzayında), 39 önemli 1 (cepsiz BK'da dolu ledge çift sayımı), 38 K1 + 39 küçük
#  (U dışı PK kesit özeti, donatı etiketi kg/m³), 38 K2 (bozuk kesit ofseti), 38 K3 (ledge kalıbı tip kaydı / form; açıkça kapatan kazanır),
#  38 B2 (yeniden oturtma erken çıkış, sessiz kipte uyarı kutusu yok). 38 E1 / K4 testleri k1_structure_copy.rb içinde.
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir. Kanıt düzeyi: sahte nesne. SketchUp içi yüz çizimi, gerçek Geri Al, iç içe
#  Component dönüşümü KANITLANMAZ.
# Kullanim: ruby tools/test/kp5_inceleme_38_39.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kp5_inceleme_38_39.rb <marine_structures_tools klasoru>'
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

class FakeDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; end; end
$status = []
Sketchup.define_singleton_method(:status_text=) { |v| $status << v.to_s }

dfl = M.mst_ch_default
SEC_L = M.mst_ch_preset(dfl.merge('total_width_m' => 1.0), 'L')   # sağ çıkıntı 0,20 × 0,60; sol ledge 0–0,80; yükseklik 0,80
SEC_K = M.mst_ch_preset(dfl, 'K')                                  # toplam 1,20; ledge 0–1,00 dolu (varsayılan)
LIB5 = [
  { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 },
  { 'uid' => 'pk1', 'family' => 'PK', 'name' => 'PK-U', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37' },
  { 'uid' => 'pkl', 'family' => 'PK', 'name' => 'PK-L', 'section' => SEC_L, 'concrete' => 'C30/37' },
  { 'uid' => 'pkl0', 'family' => 'PK', 'name' => 'PK-L0', 'section' => SEC_L, 'fw_ledge' => false, 'concrete' => 'C30/37' }
].freeze
def layout5(rows, extra = {}, lib = LIB5, group_dy = nil)
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(lib))
  l = bk_y(9101, 0.0, 1.0); r = bk_y(9102, 4.0, 5.0)
  if group_dy   # Ö1: BK'lar Y'de ötelenmiş tek örnekli grup içinde (kullanıcı grubu düzenliyor; seçim grup içinde)
    gr = Sketchup::Group.new(9100, {}); gr.transformation = Geom::Transformation.translation([0, group_dy * IN, 0])
    [l, r].each { |b| $model.entities.delete(b); gr.entities << b; b.parent = gr.definition }
    put(gr)
  end
  $model.selection.push(l, r)
  data = { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(lib), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '2.02',
           'channel_fw_inner' => '1', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }.merge(extra)
  r0 = M.create_flat_precast(data)
  [r0, pks[0], l, r]
end
ROWS_U = [{ 'type_uid' => 'pk1', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }].freeze

# ---------------------------------------------------------------- 1. 38 Ö1: POCKET, ötelenmiş grup içindeki BK
ok, pk, = layout5(ROWS_U, { 'pk_elevation_mode' => 'POCKET' }, LIB5, nil)
t('1.1 POCKET (grup yok, önceki durum): alt 2,20, cep bağı', [ok, pk && near(attrs(pk)['bottom_elevation_m'], 2.2), pk && attrs(pk)['seat_bk_left_uid']], [true, true, 'BK-U9101'])
ok, pk, = layout5(ROWS_U, { 'pk_elevation_mode' => 'POCKET' }, LIB5, 20.0)
t('1.2 POCKET, BK\'lar Y +20 m ötelenmiş grup içinde: cep bulunur (yerel Y 2,02 → dünya 22,02), alt 2,20, cep bağı',
  [ok, pk && near(attrs(pk)['bottom_elevation_m'], 2.2), pk && attrs(pk)['seat_bk_left_uid'], $ui_msgs.grep(/cebi yok/).length], [true, true, 'BK-U9101', 0])
ok, pk, = layout5(ROWS_U, { 'pk_elevation_mode' => 'POCKET', 'pd_y_offset_m' => '5.0' }, LIB5, 20.0)
t('1.3 POCKET, grup içinde cep dışı (yerel Y 5,0): oluşturulmaz, Türkçe neden', [ok, pk, $ui_msgs.last.to_s.include?('kanal cebi yok')], [false, nil, true])

# ---------------------------------------------------------------- 2. 39 önemli 1: dolu ledge betonu BK üstü altına yalnız cepte iner
def dbk(pid, x0, x1, pocket = false, top = 3.0)
  a = { 'element_type' => 'head_beam', 'element_uid' => "BK-U#{pid}", 'head_beam_id' => "BK#{pid}", 'top_elevation_m' => top, 'height_m' => 1.0, 'width_m' => x1 - x0, 'length_m' => 1.2 }
  a.merge!('start_seat_enabled' => '1', 'start_seat_offset_m' => 0.0, 'start_seat_length_m' => 1.2, 'start_seat_depth_m' => 0.5) if pocket   # cep Y 0–1,2, taban 2,50
  b = Sketchup::Group.new(pid, a)
  b.transformation = Geom::Transformation.new([[0, -1, 0], [1, 0, 0], [0, 0, 1]], [x1 * IN, 0, (top - 1.0) * IN])   # yerel X (boy) → dünya Y
  b.bounds = Geom::BoundingBox.new([x0 * IN, 0, (top - 1.0) * IN], [x1 * IN, 1.2 * IN, top * IN]); put(b)
end
def dpk(pid, sec, x0, len, z0 = 2.5)
  t0 = sec['total_width_m'].to_f; h = M.mst_ch_height(sec)
  e = Sketchup::Group.new(pid, 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => "PK#{pid}", 'element_uid' => "PK-U#{pid}",
                               'inner_width_m' => 0.0, 'inner_depth_m' => 0.0, 'base_thickness_m' => 0.0, 'wall_thickness_m' => 0.0, 'channel_section_json' => M.mst_ch_json(sec))
  e.transformation = Geom::Transformation.translation([x0 * IN, 0, z0 * IN])
  e.bounds = Geom::BoundingBox.new([x0 * IN, 0, z0 * IN], [(x0 + len) * IN, t0 * IN, (z0 + h) * IN]); put(e)
end
def dplan(hbs, th = 0.4); ins = M.mst_deck_inputs($model, hbs, {}); M.mst_deck_plan(ins[2], ins[3], th, ins[4]); end
# Düzen: BK A x 0–1, BK B x 4–5 (Y 0–1,2, üst 3,00); K kesitli PK x 0,5–4,5 (BK'lara 0,5'er m taşar), Y 0–1,2, alt 2,50, üst 3,30; döşeme 0,40 → 3,40.
# Elle (cepsiz): BK üstünde PK'sız hücreler 2 × 0,5 × 1,2 × 0,4 = 0,48; açıklık (u 1–4) ledge (Y 0–1,0) dolu 2,70–3,40: 3 × 1,0 × 0,7 = 2,10;
#  çıkıntı (Y 1,0–1,2) 3,30–3,40: 3 × 0,2 × 0,1 = 0,06; BK üstünde PK'lı hücreler (u 0,5–1 / 4–4,5, toplam 1,0 m): ledge 3,00–3,40 (BK betonu
#  altında dolgu YOK): 1,0 × 1,0 × 0,4 = 0,40; çıkıntı 1,0 × 0,2 × 0,1 = 0,02 → net 3,06. Dolgu (BK üstü altı) yalnız açıklıkta: 3 × 1,0 × 0,3 = 0,90.
#  Önceki kod BK üstündeki ledge hücrelerine de 2,70–3,00 dolgu ekliyordu (+1,0 × 1,0 × 0,3 = 0,30 → 3,36 / 1,20; çift sayım).
#  Kontrol: (net − dolgu) + prekast kesintisi + açıklık = brüt 5 × 1,2 × 0,4 = 2,40 → kesinti 0,24 (çıkıntı 4 × 0,2 × 0,3).
fresh_model; ha = dbk(9001, 0.0, 1.0); hb = dbk(9002, 4.0, 5.0); dpk(9201, SEC_K, 0.5, 4.0)
pl = dplan([ha, hb])
t('2.1 cepsiz BK, PK BK\'ya taşar: net 3,06, ledge dolgusu 0,90, kesinti 0,24, açıklık 0; brüt denkliği',
  [near(pl['volume'], 3.06), near(pl['ledge_fill_volume'], 0.9), near(pl['precast_cut_volume'], 0.24), near(pl['opening_volume'], 0.0),
   near(pl['volume'] - pl['ledge_fill_volume'] + pl['precast_cut_volume'] + pl['opening_volume'], 2.4), pl['errors']], [true, true, true, true, true, []])
# Cepli: BK'larda Y 0–1,2 cep (taban 2,50) — PK cebin içinde; ledge dolgusu cepte 2,70'e iner (önceki davranış: 3,36 / 1,20)
fresh_model; ha = dbk(9001, 0.0, 1.0, true); hb = dbk(9002, 4.0, 5.0, true); dpk(9202, SEC_K, 0.5, 4.0)
pl = dplan([ha, hb])
t('2.2 cepli BK: değişmedi — net 3,36, ledge dolgusu 1,20', [near(pl['volume'], 3.36), near(pl['ledge_fill_volume'], 1.2)], [true, true])
# PK BK'ya taşmaz (kp4 3.3 düzeni): değişmez
fresh_model; ha = dbk(9001, 0.0, 1.0); hb = dbk(9002, 4.0, 5.0); dpk(9203, SEC_K, 1.0, 3.0)
pl = dplan([ha, hb])
t('2.3 PK BK\'ya taşmıyor (kp4 3.3): net 3,12, dolgu 0,90 (değişmedi)', [near(pl['volume'], 3.12), near(pl['ledge_fill_volume'], 0.9)], [true, true])
# Eski U PK + cepli BK: plan dc61429 koduyla birebir (girdiye eklenen cep bilgisi U planını değiştirmez)
require 'open3'
old_src, st = Open3.capture2('git', '-C', File.expand_path('../..', DIR), 'show', 'dc61429:src/marine_structures_tools/main.rb')
oplan = old_src.force_encoding('UTF-8')[/^def mst_deck_plan\(bks,pcs,th,curbs=\[\]\)\n.*?^end\n/m]
if st.success? && oplan
  M.module_eval(oplan.sub('def mst_deck_plan(', 'def mst_deck_plan_kp5_old('))
  fresh_model; ha = dbk(9001, 0.0, 1.0, true); hb = dbk(9002, 4.0, 5.0, true)
  e = Sketchup::Group.new(9301, 'element_type' => 'channel_precast', 'precast_id' => 'PK9301', 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2)
  e.bounds = Geom::BoundingBox.new([0.85 * IN, 0, 2.5 * IN], [4.15 * IN, 1.2 * IN, 3.3 * IN]); put(e)
  ins = M.mst_deck_inputs($model, [ha, hb], {})
  a = M.mst_deck_plan_kp5_old(ins[2], ins[3], 0.4, ins[4]); b = M.mst_deck_plan(ins[2], ins[3], 0.4, ins[4])
  t('2.4 eski U PK + cepli BK: plan dc61429 ile birebir', b.reject { |k, _| %w[channels ledge_fill_volume].include?(k) } == a, true)
else
  t('2.4 dc61429 okunamadı', false, true)
end

# ---------------------------------------------------------------- 3. 38 K1 + 39 küçük: kesit özeti, gruplama, donatı etiketi
cs = M.mst_ch_parse(SEC_K)
t('3.1 kesit özeti: ön ayar + toplam genişlik × toplam yükseklik', [(M.mst_ch_summary(cs) rescue nil), (M.mst_ch_summary(cs, 3) rescue nil), (M.mst_ch_summary(M.mst_ch_preset(cs, 'OZEL')) rescue nil)],
  ['K 1.20 × 0.80 m', 'K 1.200 × 0.800 m', 'Özel 1.20 × 0.80 m'])
ty = { 'name' => 'PK-K', 'source' => 'kütüphane', 'wi' => 0.0, 'di' => 0.0, 'tb' => 0.0, 'tw' => 0.0, 'section' => cs }
c = { 'span' => 'A1', 'type' => ty, 'length' => 3.3, 'ow' => 1.2, 'oh' => 0.8, 'pocket' => { 'side' => 'start' }, 'y0' => 2.0, 'z0' => 2.2, 'elev' => nil }
txt = M.mst_kn_preview_text({ 'cands' => [c], 'warnings' => [] })
t('3.2 KN önizlemesi U dışı: "kesit K 1.200 × 0.800 m", "iç 0.000 × 0.000" yok', [txt.include?('kesit K 1.200 × 0.800 m'), txt.include?('iç 0.000 × 0.000')], [true, false])
tyu = ty.merge('wi' => 0.8, 'di' => 0.6, 'tb' => 0.2, 'tw' => 0.2); tyu.delete('section')
txt = M.mst_kn_preview_text({ 'cands' => [c.merge('type' => tyu)], 'warnings' => [] })
t('3.3 KN önizlemesi U: eski metin (iç 0.800 × 0.600 m)', txt.include?('iç 0.800 × 0.600 m'), true)
fresh_model
pku = Sketchup::Group.new(9501, 'element_type' => 'channel_precast', 'precast_id' => 'PK-U', 'length_m' => 3.3, 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2); put(pku)
pkk = Sketchup::Group.new(9502, 'element_type' => 'channel_precast', 'precast_id' => 'PK-K', 'length_m' => 3.3, 'inner_width_m' => 0.0, 'inner_depth_m' => 0.0, 'base_thickness_m' => 0.0, 'wall_thickness_m' => 0.0, 'channel_section_json' => M.mst_ch_json(cs)); put(pkk)
M.define_singleton_method(:boq_trace_entities) { |_s| [pku, pkk] }
pl = M.boq_trace_payload('X')
t('3.4 iz kaydı boyutu: U eski metin, U dışı kesit özeti', pl[:items].map { |i| i[:dimensions] }, ['L 3.3 m · iç 0.8 × 0.6 m', 'L 3.3 m · kesit K 1.20 × 0.80 m'])
src = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
t('3.5 metraj raporu PK gruplaması U dışında ön ayar + kesit imzasıyla (kaynak metni)', src.include?("cs ? [cs['preset'],mst_ch_geom_sig(cs)]"), true)
M.define_singleton_method(:mst_element_rebar) { |_e| { 'kg' => 120.0, 'source' => '%', 'rate' => 120.0 } }
t('3.6 donatı kaynak etiketi kg/m³ (değer aynı)', [M.mst_rebar_sum([pkk])['label'], M.mst_rebar_sum([pkk])['kg']], ['120 kg/m³', 120.0])
M.singleton_class.send(:remove_method, :mst_element_rebar)

# ---------------------------------------------------------------- 4. 38 K2: bozuk kesit ofseti
bad = { 'preset' => 'OZEL', 'total_width_m' => 1.2, 'base_m' => 0.2, 'left' => { 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 'abc' },
        'right' => { 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 0.0 } }
bs = M.mst_ch_parse(bad)
er = begin; M.mst_ch_active(bs); nil; rescue => ex; ex.class; end
t('4.1 NaN ofset: mst_ch_active çökmez; geçerlilik Türkçe hata', [er, M.mst_ch_valid(bs).join.include?('ofset')], [nil, true])
fresh_model
$model.set_attribute(D, 'precast_type_library_json', JSON.generate(LIB5 + [{ 'uid' => 'bz', 'family' => 'PK', 'name' => 'PK-BOZUK', 'section' => bad }]))
cat = begin; M.mst_pk_type_catalog($model, []); rescue => ex; ex; end
t('4.2 katalog tek bozuk tipte düşmez; bozuk tip "geçersiz", diğerleri geçerli',
  cat.is_a?(Array) ? cat.map { |x| [x['kod'], x['gecerli']] } : cat.inspect, [['PK-U', true], ['PK-L', true], ['PK-L0', true], ['PK-BOZUK', false]])
ty = begin; M.mst_kn_find_pk_type($model, [], 9.9, 9.9); rescue => ex; ex.class; end
t('4.3 KN tip araması bozuk tipte çökmez', ty, nil)

# ---------------------------------------------------------------- 5. 38 K3: ledge kalıbı (ana oturum kuralı: form '0' VEYA tip fw_ledge==false → kapalı)
lm = 3.0 + 0.3
roles = M.mst_ch_formwork_roles(M.mst_ch_parse(SEC_L), lm); ledge = roles['BASE_LEDGE']
fw_of = lambda do |uid, extra|
  ok, pk, = layout5([{ 'type_uid' => uid, 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }], { 'pd_y_offset_m' => '0.5' }.merge(extra))
  [ok, pk && attrs(pk)['formwork_area_m2'].to_f]
end
f_on = fw_of.('pkl', {}); f_form0 = fw_of.('pkl', 'channel_fw_ledge' => '0'); f_tip0 = fw_of.('pkl0', {}); f_both = fw_of.('pkl0', 'channel_fw_ledge' => '0')
f_tipt = fw_of.('pkl0', 'channel_fw_ledge' => '1')
t('5.0 L kesitinde ledge kalıp alanı > 0', ledge > 0, true)
t('5.1 yerleşim: form + tip anahtarı yok → kalıplı; form \'0\' → kapalı; tip fw_ledge=false → kapalı; ikisi → kapalı; tip false + form \'1\' → kapalı (kapatan kazanır)',
  [f_on[0], near(f_on[1] - f_form0[1], ledge), near(f_on[1] - f_tip0[1], ledge), near(f_both[1], f_tip0[1]), near(f_tipt[1], f_tip0[1])], [true, true, true, true, true])
fresh_model
$model.set_attribute(D, 'precast_type_library_json', JSON.generate([LIB5[2]]))
r1 = M.mst_kn_find_pk_type($model, [], 1.0, 0.8)
$model.set_attribute(D, 'precast_type_library_json', JSON.generate([LIB5[3]]))
r2 = M.mst_kn_find_pk_type($model, [], 1.0, 0.8)
$model.set_attribute(D, 'precast_type_library_json', JSON.generate([LIB5[3].merge('fw_ledge' => true)]))
r3 = M.mst_kn_find_pk_type($model, [], 1.0, 0.8)
t('5.2 KN yolu (yalnız tip kaydı): anahtarsız → 00101 (önceki), fw_ledge=false → 00100, true → 00101', [r1 && r1['fw'], r2 && r2['fw'], r3 && r3['fw']], %w[00101 00100 00101])

# ---------------------------------------------------------------- 6. 38 B2: yeniden oturtma erken çıkış + sessiz kip
fresh_model
l = bk_y(9401, 0.0, 1.0, 3.0, 0.9); r = bk_y(9402, 4.0, 5.0, 3.0, 0.9)
$kp5_calls = 0
M.singleton_class.send(:alias_method, :kp5_orig_plan, :mst_pk_reseat_plan)
M.define_singleton_method(:mst_pk_reseat_plan) { |*a| $kp5_calls += 1; kp5_orig_plan(*a) }
res = M.mst_pk_reseat_after_edit([l], $model, true)
t('6.1 modelde POCKET PK yok → erken çıkış (plan hesaplanmaz, işlem / ileti yok)', [$kp5_calls, $model.ops, $ui_msgs, res['moved']], [0, [], [], []])
def pk_seat5(pid, z0, y0 = 2.02, y1 = 3.22)
  a = { 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => "PK#{pid}", 'support_left_pid' => 9401, 'support_right_pid' => 9402,
        'bottom_elevation_m' => z0, 'top_elevation_m' => z0 + 0.8, 'elevation_mode' => 'POCKET', 'seat_bk_left_uid' => 'BK-U9401', 'seat_bk_left_side' => 'start',
        'seat_bk_right_uid' => 'BK-U9402', 'seat_bk_right_side' => 'start' }
  e = Sketchup::Group.new(pid, a); e.bounds = Geom::BoundingBox.new([0.85 * IN, y0 * IN, z0 * IN], [4.15 * IN, y1 * IN, (z0 + 0.8) * IN]); put(e)
end
fresh_model
l = bk_y(9401, 0.0, 1.0, 3.0, 0.9, 2.5); r = bk_y(9402, 4.0, 5.0, 3.0, 0.9, 2.5)   # cep kaydı → yatay kayma uyarısı
pk_seat5(9431, 2.2); $status = []
res = M.mst_pk_reseat_after_edit([l], $model, true)
t('6.2 sessiz kip, uyarı: uyarı kutusu yok; durum satırına yazılır; sonuçta uyarı', [$kp5_calls > 0, $ui_msgs, $status.join.include?('yatayda kaydı'), res['warnings'].length], [true, [], true, 1])
$ui_msgs = []
M.mst_pk_reseat_after_edit([l], $model, false)
t('6.3 sessiz değil: uyarı kutusu (önceki davranış)', $ui_msgs.join.include?('yatayda kaydı'), true)
M.singleton_class.send(:alias_method, :mst_pk_reseat_plan, :kp5_orig_plan)

puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
