# KQ1 (ADR-0515-K3 P1, docs/duzeltme/41 — kullanıcı kararları 1–8; 10.11.2026) — "PK Tipi Olarak Kaydet" (model içi kütüphane, Ruby):
#  pk_type_save → mstPkTypeSaved sözleşmesi (kaydedildi / ayni_geometri / mevcut_secildi / yeni / kod_cakisma), işlem açmadan doğrulama,
#  normal işlem "MST PK Tipini Kaydet" (başarıda commit, hatada abort + kütüphane değişmez), kaynak_pid ile modeldeki PK'dan tip,
#  geom_sig (ön ayar etiketi / pasif çıkıntı / döşeme ledge / üst referans hariç, oturma dahil), yerleşimde precast_type_uid / precast_type_rev,
#  katalogda title / pk_rev / created_at / kayıtsız etiketi / yapı bazlı kullanım (kullanim), eski kütüphanenin bayt korunumu.
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir. Kanıt düzeyi: sahte nesne. SketchUp içinde tek Ctrl+Z, kaydet-kapat-aç,
#  HtmlDialog ↔ JS akışı KANITLANMAZ. Sahte geometri / BK fikstürü kp3_pk_elevation.rb ile aynı.
# Kullanim: ruby tools/test/kq1_pk_type_save.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kq1_pk_type_save.rb <marine_structures_tools klasoru>'
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
# abort yolu: kütüphane yazımı başarısız (sahte)
class Sketchup::Model
  alias kq1_set set_attribute
  def set_attribute(d, k, v); raise 'sahte yazım hatası' if $lib_fail && k.to_s == 'precast_type_library_json'; kq1_set(d, k, v); end
end
class FakeDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; end; end

HAVE = %i[mst_pk_type_save mst_pk_send_type_save mst_pk_geom_sig mst_pk_type_link].all? { |s| M.respond_to?(s) }
t('K3 P1 işlevleri tanımlı', HAVE, true)

dfl = M.mst_ch_default
sec_l = M.mst_ch_preset(dfl.merge('total_width_m' => 1.0), 'L')       # sağ 0,20 × 0,60, taban 0,20
sec_k = M.mst_ch_preset(dfl.merge('total_width_m' => 1.0), 'K')       # L ile aynı geometri, yalnız etiket
sec_uu = M.mst_ch_preset(dfl, 'UU')
# eski kütüphane: JSON.generate dışı bayt düzeni (boşluklar) — okuma / reddedilen kayıt yollarında aynen kalmalı
OLD_TXT = '[ {"uid":"pd1","family":"PD","name":"PD-01","width":1.0,"height":0.3},  {"uid":"pk1","family":"PK","name":"PK-U","inner_width":0.8,"inner_depth":0.6,"base":0.2,"wall":0.2,"concrete":"C30/37"} ]'.freeze
OLD_LIB = JSON.parse(OLD_TXT).freeze
FW = { 'bottom' => false, 'sides' => true, 'inner' => true, 'ends' => false, 'ledge' => false }.freeze
def lib_txt; $model.get_attribute(D, 'precast_type_library_json', '[]').to_s; end
def req(h = {}); { 'kod' => 'PK-L1', 'ad' => 'L Kanal', 'section' => nil, 'concrete' => 'C30/37', 'fw' => FW, 'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'karar' => nil, 'kutuphane' => (JSON.parse(lib_txt) rescue []) }.merge(h); end
def save(h); $writes = []; $model.ops.clear; M.mst_pk_type_save(req(h)); end
def kq1_model(txt = OLD_TXT); fresh_model; $model.set_attribute(D, 'precast_type_library_json', txt); $lib_fail = false; end

if HAVE
  # ---------------------------------------------------------------- 1. geom_sig
  s1 = M.mst_pk_geom_sig(sec_l, 0.15, 0.15)
  t('1.1 ön ayar etiketi (L / K) imzaya girmez', s1 == M.mst_pk_geom_sig(sec_k, 0.15, 0.15), true)
  pas = JSON.parse(JSON.generate(sec_l)); pas['left']['width_m'] = 0.33
  dk = sec_l.merge('deck_ledge_left' => 'fill')
  t('1.2 pasif çıkıntı değeri / döşeme ledge seçimi imzaya girmez', [s1 == M.mst_pk_geom_sig(pas, 0.15, 0.15), s1 == M.mst_pk_geom_sig(dk, 0.15, 0.15)], [true, true])
  t('1.3 oturma ve ölçü (4 ondalık) imzaya girer; 5. ondalık girmez',
    [s1 == M.mst_pk_geom_sig(sec_l, 0.10, 0.15), s1 == M.mst_pk_geom_sig(sec_l.merge('base_m' => 0.21), 0.15, 0.15), s1 == M.mst_pk_geom_sig(sec_l.merge('base_m' => 0.20001), 0.15, 0.15)], [false, false, true])

  # ---------------------------------------------------------------- 2. kaydet
  kq1_model
  r = save('section' => sec_l)
  tp = r['tip'] || {}
  t('2.1 kaydedildi: ok, durum, normal işlem start → commit (abort yok)', [r['ok'], r['durum'], $model.ops], [true, 'kaydedildi', [[:start, 'MST PK Tipini Kaydet'], [:commit]]])
  t('2.2 kayıt alanları', [tp['uid'].to_s =~ /\Apt_pk_\d+_\d+\z/ ? true : false, tp['family'], tp['name'], tp['title'], tp['concrete'], tp['pk_rev'], tp['rev_log'] && tp['rev_log'].map { |x| [x['rev'], x['note']] },
                            tp['created_at'].to_s =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d\z/ ? true : false, tp['geom_sig'] == s1],
    [true, 'PK', 'PK-L1', 'L Kanal', 'C30/37', 1, [[1, 'oluşturuldu']], true, true])
  t('2.3 kalıp (fw_ledge mevcut anahtar), oturma, eski U alanları U dışında 0 (karar 13), birim hacim saklanmaz',
    [tp['fw_bottom'], tp['fw_sides'], tp['fw_inner'], tp['fw_ends'], tp['fw_ledge'], tp['seat_left_m'], tp['seat_right_m'], [tp['inner_width'], tp['inner_depth'], tp['base'], tp['wall']], (tp.keys & %w[concrete_volume_m3 formwork_area_m2 unit_volume_m3]), tp.key?('channel_top_ref')],
    [false, true, true, false, false, 0.15, 0.15, [0.0, 0.0, 0.0, 0.0], [], false])
  lib = JSON.parse(lib_txt)
  t('2.4 model kütüphanesi = istekteki liste + yeni kayıt; kutuphane_json modeldeki metin', [lib.length, lib.last['uid'] == tp['uid'], r['kutuphane_json'] == lib_txt, !M.mst_ch_explicit(lib.last).nil? && M.mst_ch_geom_key(M.mst_ch_explicit(lib.last)) == M.mst_ch_geom_key(sec_l)], [3, true, true, true])
  t('2.5 eski kayıtların içeriği aynen (alan / değer)', lib.first(2) == OLD_LIB, true)

  # ---------------------------------------------------------------- 3. aynı geometri / mevcut / yeni
  base_txt = lib_txt
  r = save('kod' => 'PK-L2', 'ad' => 'L ikinci', 'section' => sec_k)
  t('3.1 aynı geometri (K etiketi), karar yok → kaydetmez, ayni_geometri + mevcut; işlem / yazım yok',
    [r['ok'], r['durum'], r['mevcut'] && r['mevcut']['uid'] == tp['uid'], r['mevcut'] && r['mevcut']['kod'], r['mevcut'] && r['mevcut']['ad'], $model.ops, $writes, lib_txt == base_txt, r['kutuphane_json'] == base_txt],
    [true, 'ayni_geometri', true, 'PK-L1', 'L Kanal', [], [], true, true])
  r = save('kod' => 'PK-L2', 'ad' => 'L ikinci', 'section' => sec_l, 'karar' => 'mevcut')
  t('3.2 karar mevcut → mevcut_secildi, yazım yok', [r['ok'], r['durum'], r['mevcut'] && r['mevcut']['uid'] == tp['uid'], $model.ops, lib_txt == base_txt], [true, 'mevcut_secildi', true, [], true])
  r = save('kod' => 'PK-L2', 'ad' => 'L ikinci', 'section' => sec_l, 'karar' => 'yeni')
  t('3.3 karar yeni → ayrı kayıt (farklı uid), kütüphane 4', [r['ok'], r['durum'], r['tip'] && r['tip']['uid'] != tp['uid'], JSON.parse(lib_txt).length, $model.ops.map(&:first)], [true, 'kaydedildi', true, 4, %i[start commit]])
  r = save('kod' => 'PK-L3', 'ad' => 'L oturma farklı', 'section' => sec_l, 'seat_left_m' => 0.10)
  t('3.4 aynı kesit, farklı oturma → farklı geometri, kaydedilir', [r['ok'], r['durum']], [true, 'kaydedildi'])
  r = save('kod' => 'PK-U2', 'ad' => 'U eski', 'section' => M.mst_ch_from_u(0.8, 0.6, 0.2, 0.2))
  t('3.5 eski U kaydı (oturma bilgisi yok) ile aynı kesit → ayni_geometri (eski kayıt mevcut)', [r['durum'], r['mevcut'] && r['mevcut']['uid']], ['ayni_geometri', 'pk1'])
  r = save('kod' => 'PK-L9', 'ad' => 'x', 'section' => sec_uu, 'karar' => 'mevcut')
  t('3.6 karar mevcut ama aynı geometri yok → ok=false, yazım yok', [r['ok'], r['neden'].to_s.empty?, $model.ops], [false, false, []])

  # ---------------------------------------------------------------- 4. kod çakışması
  base_txt = lib_txt
  r = save('kod' => 'pk-l1', 'section' => sec_uu)
  t('4.1 aynı kod (büyük / küçük harf) farklı geometri → kod_cakisma + mevcut, birleştirme yok', [r['ok'], r['durum'], r['mevcut'] && r['mevcut']['kod'], $model.ops, lib_txt == base_txt], [true, 'kod_cakisma', 'PK-L1', [], true])
  r = save('kod' => 'PK-L1', 'section' => sec_l, 'karar' => 'yeni')
  t('4.2 aynı kod aynı geometri + karar yeni → kod_cakisma (aynı adla ikinci kayıt yok)', [r['durum'], $model.ops], ['kod_cakisma', []])
  r = save('kod' => 'PD-01', 'section' => sec_uu)
  t('4.3 başka sınıfın (PD) kodu → kod_cakisma', [r['durum'], r['mevcut'] && r['mevcut']['uid']], ['kod_cakisma', 'pd1'])
  put(Sketchup::Group.new(8801, 'element_type' => 'channel_precast', 'precast_type_id' => 'PK-M', 'channel_section_json' => M.mst_ch_json(sec_uu)))
  r = save('kod' => 'PK-M', 'section' => sec_l)
  t('4.4 modelde kullanılan kod (kütüphanede yok), farklı kesit → kod_cakisma (mevcut :12649 kuralı)', [r['durum'], r['mevcut'] && r['mevcut']['kod'], $model.ops], ['kod_cakisma', 'PK-M', []])
  r = save('kod' => 'PK-M', 'ad' => 'UU', 'section' => sec_uu)
  t('4.5 modelde aynı kod + aynı kesit → kaydedilir (tip modeldeki ada bağlanır)', [r['durum']], ['kaydedildi'])

  # ---------------------------------------------------------------- 5. geçersiz istek: işlem açılmaz
  kq1_model
  bad = [['kod', { 'kod' => '  ', 'section' => sec_l }, 'kod'], ['karakter', { 'kod' => 'PK/1', 'section' => sec_l }, 'izin verilmeyen'], ['ad', { 'ad' => '', 'section' => sec_l }, 'ad'],
         ['kesit', { 'section' => sec_l.merge('right' => sec_l['right'].merge('on' => false)) }, 'En az bir çıkıntı'], ['kesit yok', {}, 'Kesit'],
         ['oturma', { 'section' => sec_l, 'seat_left_m' => -0.1 }, 'Oturma']]
  bad.each do |lab, h, frag|
    r = save(h)
    t("5 geçersiz #{lab}: ok=false, Türkçe neden, işlem / yazım yok", [r['ok'], r['neden'].to_s.include?(frag), $model.ops, $writes, lib_txt == OLD_TXT], [false, true, [], [], true])
  end
  $model.set_attribute(D, 'precast_type_library_json', '{bozuk')
  r = save('section' => sec_l, 'kutuphane' => [])
  t('5.7 modeldeki kütüphane okunamıyor → üzerine yazılmaz', [r['ok'], $model.ops, lib_txt], [false, [], '{bozuk'])

  # ---------------------------------------------------------------- 6. abort yolu
  kq1_model
  $lib_fail = true
  r = save('section' => sec_l)
  $lib_fail = false
  t('6.1 yazım hatası: işlem açılır ve abort ile kapanır, ok=false, kütüphane değişmez', [r['ok'], $model.ops, lib_txt == OLD_TXT, r['neden'].to_s.include?('sahte yazım hatası'), r['kutuphane_json'] == OLD_TXT],
    [false, [[:start, 'MST PK Tipini Kaydet'], [:abort]], true, true, true])

  # ---------------------------------------------------------------- 7. kaynak_pid
  kq1_model
  src = put(Sketchup::Group.new(8901, 'element_type' => 'channel_precast', 'precast_type' => 'KANAL_PREKASTI_UU', 'channel_section_json' => M.mst_ch_json(sec_uu), 'concrete_class' => 'C35/45',
                                'seat_left_m' => 0.1, 'seat_right_m' => 0.2, 'formwork_bottom' => true, 'formwork_sides' => false, 'formwork_inner' => true, 'formwork_ends' => false, 'formwork_ledge' => false, 'channel_top_ref' => 'mid'))
  r = M.mst_pk_type_save('kod' => 'PK-UU1', 'ad' => 'Çift göz', 'kaynak_pid' => 8901, 'karar' => nil, 'kutuphane' => OLD_LIB)
  tp = r['tip'] || {}
  t('7.1 kaynak_pid: kesit / beton / oturma / kalıp / üst referans öğeden', [r['durum'], !tp['section'].nil? && M.mst_ch_geom_key(M.mst_ch_parse(tp['section'])) == M.mst_ch_geom_key(sec_uu), tp['concrete'], tp['seat_left_m'], tp['seat_right_m'], tp['fw_bottom'], tp['fw_sides'], tp['fw_ledge'], tp['channel_top_ref']],
    ['kaydedildi', true, 'C35/45', 0.1, 0.2, true, false, false, 'mid'])
  $model.set_attribute(D, 'precast_type_library_json', OLD_TXT)   # kaynak öğe yerinde kalır
  r = M.mst_pk_type_save('kod' => 'PK-UU1', 'ad' => 'Çift göz', 'kaynak_pid' => 8901, 'concrete' => 'C40/50', 'seat_left_m' => 0.25, 'kutuphane' => OLD_LIB)
  t('7.2 istekteki değer öğeyi geçersiz kılar, eksikler öğeden', [r['tip'] && r['tip']['concrete'], r['tip'] && r['tip']['seat_left_m'], r['tip'] && r['tip']['seat_right_m']], ['C40/50', 0.25, 0.2])
  t('7.3 kaynak öğe değişmedi (precast_type_id / uid yazılmadı)', [src.get_attribute(D, 'precast_type_id'), src.get_attribute(D, 'precast_type_uid')], [nil, nil])
  r = M.mst_pk_type_save('kod' => 'PK-UU2', 'ad' => 'x', 'kaynak_pid' => 424242, 'kutuphane' => OLD_LIB)
  t('7.4 kaynak_pid bulunamadı → ok=false', [r['ok'], r['neden'].to_s.include?('bulunamadı')], [false, true])

  # ---------------------------------------------------------------- 8. callback yanıtı
  kq1_model
  dl = FakeDlg.new
  M.mst_pk_send_type_save(dl, JSON.generate(req('section' => sec_l)))
  js = dl.js[0].to_s; pl = (JSON.parse(js[/mstPkTypeSaved\((.*)\)\z/m, 1]) rescue nil)
  t('8.1 window.mstPkTypeSaved korumalı çağrı, JSON yük', [js.start_with?('window.mstPkTypeSaved && mstPkTypeSaved('), pl && pl['ok'], pl && pl['durum'], pl && pl['kutuphane_json'] == lib_txt], [true, true, 'kaydedildi', true])
  dl = FakeDlg.new
  M.mst_pk_send_type_save(dl, '{bozuk')
  pl = (JSON.parse(dl.js[0].to_s[/mstPkTypeSaved\((.*)\)\z/m, 1]) rescue nil)
  t('8.2 okunamayan istek → ok=false yanıtı', [pl && pl['ok'], pl && pl['neden'].to_s.empty?], [false, false])

  mtxt = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
  t('8.3 show_dialog kaydı: pk_type_save → mst_pk_send_type_save (okunamayan istekte de mstPkTypeSaved ok=false)', mtxt.include?("@d.add_action_callback('pk_type_save'){|_,j|mst_pk_send_type_save(@d,j)}"), true)
  # ---------------------------------------------------------------- 9. yerleşimde precast_type_uid / precast_type_rev
  kq1_model
  sv = save('section' => sec_l)['tip']
  lib9 = JSON.parse(lib_txt)
  l = bk_y(9101, 0.0, 1.0); r9 = bk_y(9102, 4.0, 5.0); $model.selection.push(l, r9)
  data = { 'pd_layout_rows' => JSON.generate([{ 'type_uid' => sv['uid'], 'count' => 1 }, { 'type_uid' => 'pk1', 'count' => 1 }, { 'type_uid' => 'pd1', 'count' => 1 }]), 'precast_type_library' => JSON.generate(lib9),
           'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '2.02', 'channel_fw_inner' => '1', 'pd_body_mode' => 'GROUP' }
  ok = M.create_flat_precast(data)
  pk_new = pks.find { |e| e.get_attribute(D, 'precast_type_id') == 'PK-L1' }; pk_old = pks.find { |e| e.get_attribute(D, 'precast_type_id') == 'PK-U' }
  t('9.1 Prekast Yerleşimi: kayıtlı tip → precast_type_uid + precast_type_rev; mevcut anahtarlar aynen',
    [ok, !pk_new.nil? && pk_new.get_attribute(D, 'precast_type_uid') == sv['uid'], pk_new && pk_new.get_attribute(D, 'precast_type_rev'), pk_new && pk_new.get_attribute(D, 'precast_type'), pk_new && pk_new.get_attribute(D, 'precast_id')],
    [true, true, 1, 'PK-L1', 'PK-L1'])
  t('9.2 eski kayıt (pk_rev yok): uid yazılır, precast_type_rev yazılmaz', [pk_old && pk_old.get_attribute(D, 'precast_type_uid'), pk_old && pk_old.get_attribute(D, 'precast_type_rev', :yok)], ['pk1', :yok])
  # KN cebe yerleştirme (kp3 4. bölüm fikstürü; kütüphane tipi kayıtlı PK-U eşdeğeri)
  fresh_model
  rec = { 'uid' => 'pt_pk_1_1', 'family' => 'PK', 'name' => 'PK-KN', 'title' => 'KN', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37', 'pk_rev' => 3 }
  $model.set_attribute(D, 'precast_type_library_json', JSON.generate([rec]))
  l = bk_y(9201, 0.0, 1.0); r9 = bk_y(9202, 4.0, 5.0)
  pd = Sketchup::Group.new(9203, 'element_type' => 'flat_precast', 'precast_id' => 'PD9203', 'support_left_pid' => 9201, 'support_right_pid' => 9202, 'joint_m' => 0.02, 'seat_each_side_m' => 0.15, 'project' => 'P1')
  pd.bounds = Geom::BoundingBox.new([0.85 * IN, 4.0 * IN, 2.7 * IN], [4.15 * IN, 5.0 * IN, 3.0 * IN]); put(pd)
  c0 = M.mst_kn_place_plan($model, nil, nil, nil)['cands'][0]
  inst = c0 && M.mst_kn_create_pk!(c0, $model, nil)
  t('9.3 KN cebe yerleştirme: kütüphane tipi → precast_type_uid / rev', inst && [inst.get_attribute(D, 'precast_type_id'), inst.get_attribute(D, 'precast_type_uid'), inst.get_attribute(D, 'precast_type_rev')], ['PK-KN', 'pt_pk_1_1', 3])

  # ---------------------------------------------------------------- 10. katalog: yeni alanlar, kayıtsız form PK'sı, yapı bazlı kullanım
  kq1_model
  sv = save('section' => sec_l)['tip']
  txt10 = lib_txt
  mk = lambda do |pid, h|
    put(Sketchup::Group.new(pid, { 'element_type' => 'channel_precast', 'channel_section_json' => M.mst_ch_json(sec_l) }.merge(h).reject { |_, v| v.nil? }))
  end
  mk.(7001, 'precast_type_id' => 'PK-L1', 'precast_type_uid' => sv['uid'], 'structure' => 'ANO-01')
  mk.(7002, 'precast_type_id' => 'PK-L1', 'precast_type_uid' => sv['uid'], 'structure' => 'ANO-01')
  mk.(7003, 'precast_type_id' => 'PK-L1', 'precast_type_uid' => sv['uid'], 'ano' => 'RIHTIM-01')
  mk.(7004, 'precast_type_id' => 'PK-U', 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2, 'channel_section_json' => nil, 'structure' => 'BD-01')
  mk.(7005, 'precast_type' => 'KANAL_PREKASTI_UU', 'channel_section_json' => M.mst_ch_json(sec_uu), 'structure' => 'ANO-02')   # form PK'sı: precast_type_id yok
  $writes = []; $model.ops.clear
  cat = M.mst_pk_type_catalog($model)
  el = cat.find { |e| e['kod'] == 'PK-L1' }; eu = cat.find { |e| e['kod'] == 'PK-U' }; ef = cat.find { |e| e['kaynak'] == 'model' }
  t('10.1 kütüphane kaydı: title, pk_rev, created_at, kullanım (yapı bazlı, öğelerden)',
    el && [el['title'], el['pk_rev'], el['created_at'] == sv['created_at'], el['adet_modelde'], el['kullanim'].map { |k| [k['yapi'], k['adet']] }], ['L Kanal', 1, true, 3, [['ANO-01', 2], ['RIHTIM-01', 1]]])
  t('10.2 eski kayıt: yeni alanlar varsayılan (title boş, pk_rev 0, created_at nil), adla eşleme sürer', eu && [eu['title'], eu['pk_rev'], eu['created_at'], eu['adet_modelde'], eu['kullanim'].map { |k| [k['yapi'], k['adet']] }], ['', 0, nil, 1, [['BD-01', 1]]])
  t('10.3 form PK\'sı: kayıtsız etiketi (ön ayar + ölçü), KANAL_PREKASTI_ kodu gösterilmez',
    ef && [ef['kayitsiz'], ef['etiket'].to_s.start_with?('Kayıtsız'), ef['etiket'].to_s.include?('UU'), ef['etiket'].to_s.include?('KANAL_PREKASTI'), ef['kullanim'].map { |k| [k['yapi'], k['adet']] }], [true, true, true, false, [['ANO-02', 1]]])
  t('10.4 katalog salt okuma: yazım / işlem yok, kütüphane metni aynen', [$writes, $model.ops, lib_txt == txt10], [[], [], true])
  t('10.6 modelden gelen satır: kaynak_pid = ilk örneğin persistent_id; kütüphane satırında yok', [ef && ef['kaynak_pid'], el && el.key?('kaynak_pid')], [7005, false])
  r = M.mst_pk_type_save('kod' => 'PK-F1', 'ad' => 'Formdan', 'kaynak_pid' => ef && ef['kaynak_pid'], 'kutuphane' => JSON.parse(lib_txt))
  t('10.7 kaynak_pid ile "Tip kütüphanesine ekle": form PK kesiti kaydedilir', [r['durum'], r['tip'] && M.mst_pk_section_sig(M.mst_ch_parse(r['tip']['section'])) == M.mst_pk_section_sig(sec_uu)], ['kaydedildi', true])
  $writes = []
  pub = M.mst_pk_catalog_public(cat)
  t('10.5 genel kayıt JSON üretilebilir, kullanim dizisi', [(JSON.generate(pub) rescue nil).is_a?(String), pub.all? { |e| e['kullanim'].is_a?(Array) }], [true, true])

  # ---------------------------------------------------------------- 11. eski kütüphanenin bayt korunumu
  kq1_model
  M.mst_pk_type_catalog($model); save('kod' => 'PK-U2', 'section' => M.mst_ch_from_u(0.8, 0.6, 0.2, 0.2)); save('kod' => '', 'section' => sec_l)
  t('11.1 okuma + reddedilen kayıt sonrası eski metin bayt bayt aynı', lib_txt == OLD_TXT, true)
  save('section' => sec_l)
  t('11.2 kayıtta eski kayıtların alan / değerleri aynen, eski kayda yeni alan eklenmez', JSON.parse(lib_txt).first(2), OLD_LIB)
end

puts "\nKQ1: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
