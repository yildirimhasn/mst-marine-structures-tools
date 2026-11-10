# KQ6 (docs/duzeltme/41 kullanıcı kararları 10–11; bulgular 42 E1, Ö1–Ö3, K1, K3–K8 ve 43 önemli 1–3) — kabul ölçütü: "hatalı veri, çizim,
#  metraj olmayacak şekilde" (belirsizlikte işlem yapılmaz, Türkçe neden). Kapsam:
#  E1 model kütüphanesi esas + liste_bayat, Geri Al / Yinele bildirimi; Ö1 paylaşılan Group tanımı; Ö2 destek bağsız komşu denetimi;
#  Ö3 plan_pids; 43/1 oturma farkı (yerleşim / KN / tip uygulama reddi); 43/2 ayrıntılı donatı; 43/3 daralmada derz > 0,05;
#  K1 n4 yuvarlama; K3 boş oturma; K4 içe almada imza + kod; K5 kod anahtarı; K6 PK Sil kapsayıcı + önizleme; K7 dosya kilidi + değişiklik
#  denetimi; K8 ölçekli örnek; karar 11 satır etiketi "rev N".
# Gerçek main.rb (golden SketchUp sahtesi). Kanıt düzeyi: sahte nesne. SketchUp içi Geri Al, HtmlDialog, gerçek make_unique KANITLANMAZ.
# Kullanim: ruby tools/test/kq6_inceleme_42_43.rb <src/marine_structures_tools>
require 'stringio'
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kq6_inceleme_42_43.rb <marine_structures_tools klasoru>'
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
require 'tmpdir'
require 'fileutils'
SRC_MAIN = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
SRC_PKF = File.binread(File.join(DIR, 'pk_library_file.rb')).force_encoding('UTF-8')
SEC_L = M.mst_ch_preset(M.mst_ch_default, 'L')
SEC_L13 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.3))
SEC_L10 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.0))
SEC_L118 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.18))
JL = secj(SEC_L)
REC_L = { 'uid' => 'pt_pk_1_1', 'family' => 'PK', 'name' => 'PK-L', 'title' => 'L Kanal', 'section' => JL, 'concrete' => 'C30/37',
          'fw_bottom' => false, 'fw_sides' => true, 'fw_inner' => true, 'fw_ends' => false, 'fw_ledge' => true,
          'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'geom_sig' => M.mst_pk_geom_sig(SEC_L, 0.15, 0.15), 'created_at' => '2026-11-10T10:00:00+03:00',
          'pk_rev' => 1, 'rev_log' => [{ 'rev' => 1, 'at' => '2026-11-10T10:00:00+03:00', 'note' => 'oluşturuldu' }] }.freeze
REC_PD = { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 }.freeze
def place(n_pk, extra = {}, lib = [REC_PD, REC_L], pd = 1)
  fresh_model
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate(lib))
  l = bk_y(9101, 0.0, 1.0); r = bk_y(9102, 4.0, 5.0)
  $model.selection.push(l, r)
  rows = [{ 'type_uid' => lib.find { |x| x['family'] == 'PK' }['uid'], 'count' => n_pk }]
  rows << { 'type_uid' => 'pd1', 'count' => pd } if pd > 0
  data = { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(lib), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '2.02',
           'channel_fw_inner' => '1', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }.merge(extra)
  ok = M.create_flat_precast(data)
  $model.selection.clear; ops_clear
  [ok, pks.sort_by { |e| e.transformation.to_a[13] }, l, r]
end
RQS = ->(kod, sec, h = {}) { { 'kod' => kod, 'ad' => "#{kod} adı", 'section' => secj(sec), 'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'uygula' => 'secim' }.merge(h) }
RQ = { 'tip_uid' => 'pt_pk_1_1', 'section' => secj(SEC_L118), 'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'concrete' => 'C30/37',
       'fw' => { 'bottom' => false, 'sides' => true, 'inner' => true, 'ends' => false, 'ledge' => true }, 'channel_top_ref' => nil, 'kapsam' => 'model' }.freeze
def mlib; JSON.parse(libtxt); end
def allel; x = []; M.collect_elements($model.entities, x); x; end
module UI; def self.messagebox(m, *_a); ($ui_msgs ||= []) << m.to_s; 6; end; end
class FakeDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; end; def visible?; true; end; end
def fn(name); SRC_MAIN[/^def #{Regexp.escape(name)}.*?^end\n/m].to_s; end

# ---------------------------------------------------------------- K1 / K3 / K5 / karar 11 yardımcıları
t('K1 n4: yarım değer sıfırdan uzağa (1,00005 → 1,0001; −1,00005 → −1,0001; 0,00005 → 0,0001; −0,00004 → 0,0000; 1,2; 2,00015)',
  ([1.00005, -1.00005, 0.00005, -0.00004, 1.2, 2.00015].map { |v| M.mst_pk_n4(v) } rescue $!.message), %w[1.0001 -1.0001 0.0001 0.0000 1.2000 2.0002])
t('K3 boş dize oturma = nil (geom_sig "-"), same_geom eski kayıt gibi, pkf_sig aynı kural',
  ([M.mst_pk_geom_sig(SEC_L, '', ' ') == M.mst_pk_geom_sig(SEC_L, nil, nil),
    M.mst_pk_rec_same_geom?(REC_L.merge('seat_left_m' => '', 'seat_right_m' => ''), M.mst_pk_section_sig(SEC_L), 0.15, 0.15),
    M.mst_pkf_sig(REC_L.merge('seat_left_m' => '', 'seat_right_m' => '', 'geom_sig' => nil)) == M.mst_pk_geom_sig(SEC_L, nil, nil)] rescue $!.message), [true, true, true])
t('K5 kod anahtarı: PK-I / pk-ı / pk-i / PK-İ aynı; boş kod eşleşmez',
  (M.respond_to?(:mst_pk_code_key) ? [%w[PK-I pk-ı pk-i PK-İ].map { |k| M.mst_pk_code_key(k) }.uniq.length, M.mst_pk_same_code?('', '')] : 'tanımsız'), [1, false])
t('K5 tek yardımcı: ham upcase / downcase kod karşılaştırması kalmadı (K3 işlevleri + pk_library_file.rb)',
  SRC_MAIN.scan(/mst_precast_type_id\(e\)\.(?:upcase|downcase)==kod/).length + SRC_PKF.scan(/\.downcase==/).length +
  %w[mst_pk_type_save mst_pk_update_build].sum { |f| fn(f).scan(/\.(?:upcase|downcase)==/).length }, 0)
t('karar 11 satır etiketi: rev yoksa boş, tek rev " rev 2", karışık " rev 1, 2"; takeoff PK satırı yardımcıyı kullanır',
  (M.respond_to?(:mst_pk_rev_label) ? [M.mst_pk_rev_label([Sketchup::Group.new(nil, {})]), M.mst_pk_rev_label([Sketchup::Group.new(nil, 'precast_type_rev' => 2)]),
   M.mst_pk_rev_label([Sketchup::Group.new(nil, 'precast_type_rev' => 2), Sketchup::Group.new(nil, 'precast_type_rev' => 1), Sketchup::Group.new(nil, {})]),
   fn('takeoff').include?('mst_pk_rev_label(arr)')] : 'tanımsız'), ['', ' rev 2', ' rev 1, 2', true])

# ---------------------------------------------------------------- E1 model esas + liste_bayat
ok, ps, = place(1, 'pd_joint_m' => '0.12'); sel(ps[0]); l0 = libtxt
r = M.mst_pk_type_save(RQS.('PK-N', SEC_L13).merge('kutuphane' => [REC_PD, REC_L, REC_L.merge('uid' => 'pt_pk_9_9', 'name' => 'PK-HAYALET')]), $model)
t('E1.1 arayüz listesinde modelde olmayan PK kaydı → liste_bayat, işlem yok, kütüphane aynı, yanıtta model listesi',
  [r['ok'], r['durum'], r['neden'].to_s.include?('Tip listesi modelle uyuşmuyor'), ops, libtxt == l0, r['kutuphane_json'] == l0], [false, 'liste_bayat', true, [], true, true])
r = M.mst_pk_type_save(RQS.('PK-N', SEC_L13).merge('kutuphane' => [REC_PD, REC_L.merge('pk_rev' => 2, 'section' => secj(SEC_L13), 'geom_sig' => M.mst_pk_geom_sig(SEC_L13, 0.15, 0.15))]), $model)
t('E1.2 arayüzde modelden farklı rev / geometri (Geri Al sonrası bayat) → liste_bayat, işlem yok', [r['durum'], ops, libtxt == l0], ['liste_bayat', [], true])
r = M.mst_pk_type_save(RQS.('PK-N', SEC_L13).merge('kutuphane' => [REC_PD, REC_L, { 'uid' => 'pd_yerel', 'family' => 'PD', 'name' => 'PD-YEREL', 'width' => 1.0, 'height' => 0.3 }]), $model)
nl = mlib
t('E1.3 PK dışı yerel kayıt denetime girmez ve modele yazılmaz; taban model listesi + yalnız yeni kayıt',
  [r['ok'], r['durum'], nl.map { |x| x['uid'] }[0, 2], nl.length, nl.any? { |x| x['uid'] == 'pd_yerel' }, r['kutuphane_json'] == libtxt], [true, 'kaydedildi', %w[pd1 pt_pk_1_1], 3, false, true])
ok, ps, = place(1, 'pd_joint_m' => '0.12'); sel(ps[0])
yerel = { 'uid' => 'pt_pk_99_1', 'family' => 'PK', 'name' => 'PK-U-YEREL', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37' }
r = M.mst_pk_type_save(RQS.('PK-N2', SEC_L13).merge('kutuphane' => [REC_PD, REC_L, yerel]), $model)
t('E1.3b hiç kaydedilmemiş eski U satırı (modelde yok, pk_rev / geom_sig yok) bayat sayılmaz: kayıt ok, yerel satır modele yazılmaz',
  [r['ok'], r['durum'], mlib.any? { |x| x['uid'] == 'pt_pk_99_1' }], [true, 'kaydedildi', false])
ok, ps, = place(1, 'pd_joint_m' => '0.12'); sel(ps[0]); l0 = libtxt
r = M.mst_pk_type_save(RQS.('PK-N3', SEC_L13).merge('kutuphane' => [REC_PD, REC_L, yerel.merge('pk_rev' => 1)]), $model)
t('E1.3c bir kez kaydedilmiş (pk_rev var) ama modelde olmayan satır → liste_bayat', [r['durum'], ops, libtxt == l0], ['liste_bayat', [], true])
# karar 11 tam: gruplama anahtarında precast_type_rev; K5 kalanlar (yerleşim ad benzersizliği, KN otomatik ad)
t('karar 11: Detaylı Metraj PK gruplama anahtarında precast_type_rev (yoksa boş)', fn('takeoff').include?("g.get_attribute(DICT,'precast_type_rev',nil)") && fn('takeoff').include?('dims=k.length==5'), true)
$ui_msgs = []
ok, = place(1, {}, [REC_PD, REC_L.merge('name' => 'PK-I'), REC_L.merge('uid' => 'pt_pk_1_2', 'name' => 'pk-ı')])
t('K5 yerleşim: PK-I / pk-ı aynı kod → "benzersiz olmalıdır", yerleşim yok', [ok == true, $ui_msgs.join.include?('benzersiz'), pks.length], [false, true, 0])
ctx = { 'reg' => {}, 'used' => { 'PK-I' => true }, 'pk_names' => { M.mst_pk_code_key('PK-I') => true } }
t('K5 KN otomatik ad: pk-ı tabanı PK-I ile çakışır → pk-ı-B', M.mst_kn_type_name('pk-ı', 3.3, { 'wi' => 0.8, 'di' => 0.6, 'tb' => 0.2, 'tw' => 0.2 }, ctx), 'pk-ı-B')
ps = place(3, 'pd_joint_m' => '0.12')[1]; l0 = libtxt; pids = ps.map(&:persistent_id)
r = M.mst_pk_type_update_apply(RQ.merge('onay' => true, 'plan_pids' => pids, 'kutuphane' => [REC_PD, REC_L.merge('pk_rev' => 0)]), $model)
t('E1.4 Tüm örnekler bayat listeyle → liste_bayat, işlem yok', [r['ok'], r['durum'], ops, libtxt == l0, r['kutuphane_json'] == l0], [false, 'liste_bayat', [], true, true])
dl = FakeDlg.new; M.instance_variable_set(:@d, dl); $writes = []
obs = (M::MstPkUndoObserver.new rescue nil)
obs&.onTransactionUndo($model); obs&.onTransactionRedo($model)
t('E1.5 Geri Al / Yinele gözlemcisi: açık pencerede loadPrecastTypeLibrary(model) + mstPkRefresh, yazım yok',
  [!obs.nil?, dl.js.length, dl.js.all? { |s| s.include?("loadPrecastTypeLibrary(#{JSON.generate(libtxt)})") && s.include?('mstPkRefresh()') }, $writes], [true, 2, true, []])
t('E1.6 gözlemci pencere açılınca bağlanır, kapanınca çözülür', [fn('show_dialog').include?('mst_pk_undo_attach(Sketchup.active_model)'), fn('show_dialog').include?('mst_pk_undo_detach')], [true, true])
M.instance_variable_set(:@d, nil)

# ---------------------------------------------------------------- Ö3 plan_pids
ps = place(3, 'pd_joint_m' => '0.12')[1]; pids = ps.map(&:persistent_id)
r = M.mst_pk_type_update_apply(RQ.merge('onay' => true, 'plan_pids' => pids[0, 2]), $model)
t('Ö3.1 plandaki PID kümesi ≠ kapsam → plan_degisti, işlem yok', [r['ok'], r['durum'], ops], [false, 'plan_degisti', []])
r = M.mst_pk_type_update_apply(RQ.merge('onay' => true), $model)
t('Ö3.2 plan_pids yok → plan_degisti, işlem yok', [r['ok'], r['durum'], ops], [false, 'plan_degisti', []])
r = M.mst_pk_type_update_apply(RQ.merge('onay' => true, 'plan_pids' => pids.reverse.map(&:to_s)), $model)
t('Ö3.3 plan_pids eşit (sıra / metin önemsiz) → güncellenir', [r['ok'], r['guncellenen'], ops], [true, 3, %i[start commit]])

# ---------------------------------------------------------------- Ö1 paylaşılan Group tanımı
class Sketchup::Group
  def make_unique
    return self unless definition.count_instances > 1
    definition.instances.delete(self); nd = Sketchup::ComponentDefinition.new(nil, {}); ents = Sketchup::Entities.new(@entities.to_a); ents.parent = self
    nd.entities = ents; nd.instances << self; @entities = ents; @definition = nd; self
  end
  def kq6_share(o); o.instance_variable_set(:@entities, @entities); definition.instances << o; o.instance_variable_set(:@definition, definition); end
end
ok, ps, = place(2, 'pd_joint_m' => '0.12'); a, b = ps
a.kq6_share(b); shared = b.entities.to_a.dup; sel(a)
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
t('Ö1 kopya Group tanımı paylaşıyorsa önce ayrılır: kardeşin geometrisi aynı nesneler, seçilen yeniden kuruldu',
  [r['ok'], b.entities.to_a.length == shared.length && b.entities.to_a.each_with_index.all? { |x, i| x.equal?(shared[i]) }, a.definition != b.definition, a.entities.grep(Sketchup::Face).map { |f| (f.area / IN / IN).round(6) }.include?(0.38)],
  [true, true, true, true])
t('Ö1 aynı desen (BK3 boy uyarlama, mst_apply_precast_resize!) Group ayırma', fn('mst_apply_precast_resize!').include?('mst_make_unique_keep_data!'), true)

# ---------------------------------------------------------------- Ö2 destek bağı yok
ok, ps, = place(1, 'pd_joint_m' => '0.12'); a = ps[0]
%w[support_left_pid support_right_pid].each { |k| a.delete_attribute(D, k) }
nd, = M.mst_pk_neighbor_check(a, 1.3, allel)
t('Ö2 destek PID yok + genişlik değişir → uygun değil "komşu denetimi yapılamadı: destek BK bağı yok"', nd.any? { |s| s.include?('komşu denetimi yapılamadı: destek BK bağı yok') }, true)
nd, = M.mst_pk_neighbor_check(a, 1.2, allel)
t('Ö2 genişlik aynı → denetim gerekmez', nd, [])

# ---------------------------------------------------------------- 43/3 daralmada derz
ok, ps, = place(2); a, b = ps; sel(a); l0 = libtxt
r = M.mst_pk_type_save(RQS.('PK-L10', SEC_L10), $model)
t('43/3 1,20 → 1,00, derz 0,02 + 0,10 = 120 mm > 50 mm → ok false, neden, işlem / kayıt yok',
  [r['ok'], r['neden'].to_s.include?("komşu #{M.element_visible_id(b)} ile derz 120 mm'ye çıkar") && r['neden'].to_s.include?('tam kalınlığa döner'), ops, libtxt == l0], [false, true, [], true])
r = M.mst_pk_type_save(RQS.('PK-L118', SEC_L118), $model)
t('43/3 1,20 → 1,18 (derz 30 mm ≤ 50) → uygulanır', [r['ok'], r['neden']], [true, nil])

# ---------------------------------------------------------------- 43/1 oturma farkı
REC_L25 = REC_L.merge('uid' => 'pt_pk_3_3', 'name' => 'PK-L25', 'seat_left_m' => 0.25, 'seat_right_m' => 0.25, 'geom_sig' => M.mst_pk_geom_sig(SEC_L, 0.25, 0.25)).freeze
$ui_msgs = []
ok, ps, = place(1, {}, [REC_PD, REC_L25])
t('43/1.1 yerleşim: PK tipi oturması (0,25) PD oturmasından (0,15) farklı → yerleşim yok, Türkçe neden, işlem açılmadı',
  [ok == true, ps.length, $ui_msgs.join.include?('oturma'), $model.ops], [false, 0, true, []])
ok, ps, = place(2, {}, [REC_PD, REC_L25], 0)
t('43/1.2 yalnız PK (aynı oturma) → yerleşir, boy 3,50', [ok, ps.length, ps.all? { |e| near(e.get_attribute(D, 'length_m'), 3.5) }], [true, 2, true])
ok, ps, = place(1, 'pd_joint_m' => '0.12'); sel(ps[0]); l0 = libtxt
r = M.mst_pk_type_save(RQS.('PK-L25B', SEC_L, 'seat_left_m' => 0.25, 'seat_right_m' => 0.25), $model)
t('43/1.3 seçili PK oturma 0,15 → 0,25, aynı açıklıkta PD 3,30 m → ok false "oturma farkı", işlem / kayıt yok',
  [r['ok'], r['neden'].to_s.include?('oturma farkı'), ops, libtxt == l0], [false, true, [], true])
ok, ps, = place(2, {}, [REC_PD, REC_L], 0); sel(*ps)
r = M.mst_pk_type_save(RQS.('PK-L25C', SEC_L, 'seat_left_m' => 0.25, 'seat_right_m' => 0.25), $model)
t('43/1.4 açıklıktaki tüm prekastlar birlikte değişirse uygun (boy 3,50)', [r['ok'], ps.map { |e| e.get_attribute(D, 'length_m').round(6) }], [true, [3.5, 3.5]])
t('43/1.5 KN yerleşimi: kayıt oturması PD oturmasından farklıysa kanal yerleştirilmez (neden)', SRC_MAIN.include?('kayıttaki oturma') && SRC_MAIN.include?("mst_pk_n4(ty['seat'])!=mst_pk_n4(seat)"), true)

# ---------------------------------------------------------------- 43/2 ayrıntılı donatı
ok, ps, = place(1, 'pd_joint_m' => '0.12'); a = ps[0]
a.set_attribute(D, 'rebar_mode', 'drawing_detail'); a.set_attribute(D, 'rebar_t', 0.5); sel(a); l0 = libtxt
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
t('43/2.1 çizimden donatılı PK + kesit değişir → ok false (tonaj yeniden hesaplanamaz), işlem yok, rebar_t aynı',
  [r['ok'], r['neden'].to_s.include?('tonaj yeniden hesaplanamaz'), ops, a.get_attribute(D, 'rebar_t')], [false, true, [], 0.5])
a.set_attribute(D, 'rebar_mode', 'auto_detail'); a.set_attribute(D, 'pc_rebar_json', '{}')
M.singleton_class.send(:alias_method, :kq6_pcar, :mst_pc_after_rebuild!)
M.define_singleton_method(:mst_pc_after_rebuild!) { |e| e.set_attribute(D, 'pc_rebar_error', 'sahte donatı hatası') }
# parametrik donatı yalnız U kesitte (L ön ayarı U dışı): U kaydı, uygunluk + yeniden kurulum doğrudan
SEC_U = M.mst_ch_preset(M.mst_ch_default, 'U')
REC_U = REC_L.merge('uid' => 'pt_pk_8_8', 'name' => 'PK-U', 'section' => secj(SEC_U), 'geom_sig' => M.mst_pk_geom_sig(SEC_U, 0.15, 0.15))
ix = M.mst_pk_bk_index(allel)
t('43/2.2a parametrik donatı + U kesit → uygunluk denetiminde donatı nedeni yok', M.mst_pk_apply_check(a, REC_U, ix, []).grep(/donatı/), [])
er = (M.mst_pk_apply_rec!(a, REC_U, $model); nil) rescue $!.message
t('43/2.2 parametrik donatı yeni ölçüde çizilemezse mst_pk_apply_rec! istisna verir (çağıran abort eder; eski tonaj sessizce kalmaz)', er.to_s.include?("yeni ölçüde yeniden hesaplanamadı"), true)
M.define_singleton_method(:mst_pc_after_rebuild!) { |e| e.set_attribute(D, 'rebar_t', 0.123); e.delete_attribute(D, 'pc_rebar_error') }
ok, ps, = place(1, 'pd_joint_m' => '0.12'); a = ps[0]; a.set_attribute(D, 'rebar_mode', 'auto_detail'); a.set_attribute(D, 'pc_rebar_json', '{}'); a.set_attribute(D, 'rebar_t', 0.5)
er = (M.mst_pk_apply_rec!(a, REC_U, $model); nil) rescue $!.message
t('43/2.3 parametrik donatı yeniden çizildi → uygulanır, rebar_t yeni', [er, a.get_attribute(D, 'rebar_t')], [nil, 0.123])
M.singleton_class.send(:alias_method, :mst_pc_after_rebuild!, :kq6_pcar)
ok, ps, = place(1, 'pd_joint_m' => '0.12'); a = ps[0]; a.set_attribute(D, 'rebar_mode', 'auto_detail'); a.set_attribute(D, 'pc_rebar_json', '{}'); sel(a)
sx = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.25))
r = M.mst_pk_type_save(RQS.('PK-X', sx), $model)
t('43/2.4 parametrik donatı + U dışı kesit → uygun değil (işlem yok)', [M.mst_ch_u_equiv?(sx), r['ok'], r['neden'].to_s.include?('U dışı'), ops], [false, false, true, []])

# ---------------------------------------------------------------- K8 ölçek
ok, ps, = place(1, 'pd_joint_m' => '0.12'); a = ps[0]; o = a.transformation.to_a
a.transformation = Geom::Transformation.new([[1, 0, 0], [0, 2, 0], [0, 0, 1]], [o[12], o[13], o[14]]); sel(a)
r = M.mst_pk_type_save(RQS.('PK-L2', SEC_L13), $model)
t('K8.1 eşit olmayan ölçekli örnek → ok false (ölçek belirsiz), işlem yok', [r['ok'], r['neden'].to_s.include?('ölçek'), ops], [false, true, []])
ok, ps, = place(1, 'pd_joint_m' => '0.12'); a = ps[0]; o = a.transformation.to_a
a.transformation = Geom::Transformation.new([[2, 0, 0], [0, 2, 0], [0, 0, 2]], [o[12], o[13], o[14]]); y0 = o[13] / IN
begin; M.mst_pk_apply_rec!(a, REC_L.merge('section' => secj(SEC_L118), 'name' => 'PK-L118'), $model); rescue => ex; puts "  K8.2 istisna: #{ex.message}"; end
t('K8.2 eşit ölçek 2: ortadan kaydırma yerel birimle (0,01 × 2 = +0,02 m)', near(a.transformation.to_a[13] / IN, y0 + 0.02, 1e-9), true)

# ---------------------------------------------------------------- K6 PK Sil
ok, ps, = place(2, 'pd_joint_m' => '0.12'); lay = $model.entities.find { |x| x.is_a?(Sketchup::Group) && x.get_attribute(D, 'element_type') == 'precast_layout' }
sel(lay); n0 = pks.length
r = M.mst_pk_delete($model)
pv = (M.mst_pk_delete_preview($model) rescue nil)
t('K6.1 "Prekast Layout" seçili → silme yok, ok false, neden; önizleme de ok false', [r['ok'], r['neden'].to_s.include?('kapsayıcı'), pks.length == n0, ops, pv && pv['ok']], [false, true, true, [], false])
sel(ps[0]); $writes = []
pv = (M.mst_pk_delete_preview($model) rescue {})
t('K6.2 önizleme salt okuma: adet 1, kodlar, dosemeler sayı', [pv['ok'], pv['adet'], pv['kodlar'], pv['dosemeler'], $writes, ops], [true, 1, [M.element_visible_id(ps[0])], 0, [], []])
t('K6.3 pk_delete_preview callback kaydı', SRC_MAIN.include?("add_action_callback('pk_delete_preview')"), true)

# ---------------------------------------------------------------- K4 içe alma imzası, K7 dosya kilidi
TMP = Dir.mktmpdir('kq6'); M.mst_pkf_base = TMP; PATH = M.mst_pkf_path
fd = REC_L.merge('uid' => 'pt_pk_7_7', 'name' => 'PK-D', 'section' => secj(SEC_L13), 'geom_sig' => 'pk1|bayat')
fresh_model; $model.set_attribute(D, 'precast_type_library_json', JSON.generate([REC_PD]))
FileUtils.mkdir_p(File.dirname(PATH)); File.binwrite(PATH, JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => [fd]))
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7] }, $model)
im = mlib.find { |x| x['uid'] == 'pt_pk_7_7' } || {}
t('K4 içe almada geom_sig kesit + oturmadan yeniden hesaplanır (bayat imza yazılmaz)', [r['ok'], r['eklenen'], im['geom_sig'] == M.mst_pk_geom_sig(SEC_L13, 0.15, 0.15)], [true, 1, true])
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7], 'kutuphane' => [REC_PD, REC_L] }, $model)
t('E1 içe al bayat listeyle → liste_bayat', [r['ok'], r['durum']], [false, 'liste_bayat'])
fresh_model; $model.set_attribute(D, 'precast_type_library_json', JSON.generate([REC_PD, REC_L]))
File.binwrite(PATH + '.lock', 'baska'); before = File.binread(PATH)
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('K7.1 taze kilit varsa yazılmaz, neden, dosya aynı', [r['ok'], r['neden'].to_s.include?('kilit'), File.binread(PATH) == before], [false, true, true])
File.utime(Time.now - 3600, Time.now - 3600, PATH + '.lock')
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('K7.2 süresi dolmuş kilit kaldırılır, yazılır, kilit dosyası kalmaz', [r['ok'], r['eklenen'], File.exist?(PATH + '.lock')], [true, 1, false])
M.singleton_class.send(:alias_method, :kq6_read, :mst_pkf_read)
M.define_singleton_method(:mst_pkf_read) { |*a| x = kq6_read(*a); File.binwrite(PATH, JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => [], 'baska' => 1)); x }
$model.set_attribute(D, 'precast_type_library_json', JSON.generate([REC_PD, REC_L.merge('pk_rev' => 5)]))
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
M.singleton_class.send(:alias_method, :mst_pkf_read, :kq6_read)
t('K7.3 okunduktan sonra dosya başka yerde değişti → yazılmaz, "listeyi yenileyin", başka yazım korunur',
  [r['ok'], r['neden'].to_s.include?('başka yerde değişti'), (JSON.parse(File.binread(PATH))['baska'] rescue nil)], [false, true, 1])
FileUtils.rm_rf(TMP)

puts "\nKQ6: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
