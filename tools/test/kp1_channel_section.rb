# KP1 (ADR-0515-K2, docs/duzeltme/37 — kullanıcı kararları 0–10; 09.11.2026) — Kanal prekastı tek parametrik kesit, parti P1a (Ruby).
#  channel_section.rb: varsayılan, ön ayarlar (ölçü korunur), eski U eşlemesi, geçerlilik metinleri, alan / yükseklik, kontur,
#  açık göz aralıkları, rol bazlı kalıp; U formül tekrarlarının tek kaynağa bağlanması (U-eşdeğerinde değerler ve anahtarlar
#  bugünküyle aynı); üç üretim yolu (Prekast Yerleşimi PK, Kanal Prekastı formu, KN cebe yerleştirme); Group boy yeniden kurma;
#  Kontrollü Düzenleme reddi (karar 8); prekast donatısı reddi (karar 9); tek BK'ya oturan kanal kot eşitleme (karar 10).
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir. Sahte ekleri: Entities#add_group / add_face / add_instance / clear!,
#  Face#pushpull (profil itme → yan / uç yüzler, normal ve alan), malzeme / katman / tanım koleksiyonları, transform!.
# Kanıt düzeyi: sahte nesne. SketchUp'ın gerçek yüz oluşturma / itme / yüz normali, Component tanım değiştirme, Ctrl+Z / Redo,
#  kaydet-aç ve gözlemciler KANITLANMAZ.
# Kullanim: ruby tools/test/kp1_channel_section.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kp1_channel_section.rb <marine_structures_tools klasoru>'
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
def near(a, b, eps = 1e-9); (a.to_f - b.to_f).abs <= eps; end
def safe; yield; rescue NoMethodError, NameError => e; "HATA #{e.class}: #{e.message[0, 120]}"; end

HAVE = M.respond_to?(:mst_ch_section) && M.respond_to?(:mst_ch_valid) && M.respond_to?(:mst_ch_profile)
t('channel_section.rb yüklü (mst_ch_section / mst_ch_valid / mst_ch_profile)', HAVE, true)
unless HAVE
  puts "\nKP1: #{$ok} geçti, #{$bad} kaldı"
  exit 1
end

# ---------------------------------------------------------------- sahte geometri
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
  $model.definitions.clear; $model.ops.clear
  $all_ents = {}
  $ui_msgs = []
end
def bk(pid, x0, x1, top = 3.0, y0 = 0.0, y1 = 10.0)
  b = Sketchup::Group.new(pid, 'element_type' => 'head_beam', 'top_elevation_m' => top, 'bottom_elevation_m' => top - 1.0, 'height_m' => 1.0,
                               'length_m' => (y1 - y0), 'element_uid' => "BK-#{pid}", 'head_beam_id' => "BK#{pid}")
  b.bounds = Geom::BoundingBox.new([x0 * IN, y0 * IN, (top - 1.0) * IN], [x1 * IN, y1 * IN, top * IN])
  $model.entities << b; b.parent = $model.entities; $all_ents[pid] = b
  b
end
def attrs(e); d = e.attribute_dictionary(D); d ? Hash[d.keys.map { |k| [k, d[k]] }] : {}; end
def marked_m2(e); M.mst_marked_area_m2(M.mst_container_entities(e).to_a); end
def find_pk; out = []; M.collect_elements($model.entities, out); out.select { |e| e.get_attribute(D, 'element_type') == 'channel_precast' }; end

# ---------------------------------------------------------------- 1. kesit verisi
df = M.mst_ch_default
t('1.1 varsayılan U: toplam 1,20, taban 0,20', [df['preset'], df['total_width_m'], df['base_m']], ['U', 1.2, 0.2])
t('1.2 varsayılan sol / sağ açık 0,20 × 0,60 ofset 0; orta kapalı 0,15 × 0,30 ofset 0,525',
  [df['left'], df['right'], df['mid']],
  [{ 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 0.0 }, { 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 0.0 },
   { 'on' => false, 'width_m' => 0.15, 'height_m' => 0.3, 'offset_m' => 0.525 }])
t('1.3 varsayılan U-eşdeğeri; eski ölçüler [0,80 0,60 0,20 0,20]', [M.mst_ch_u_equiv?(df), M.mst_ch_u_dims(df).map { |v| v.round(9) }], [true, [0.8, 0.6, 0.2, 0.2]])
dims = ->(s) { M::MST_CH_PARTS.map { |k| s[k].reject { |kk, _| kk == 'on' } } + [s['total_width_m'], s['base_m']] }
flags = ->(s) { M::MST_CH_PARTS.map { |k| s[k]['on'] } }
{ 'U' => [true, false, true], 'L' => [false, false, true], 'UU' => [true, true, true], 'K' => [false, false, true] }.each do |pr, exp|
  s = M.mst_ch_preset(df, pr)
  t("1.4 ön ayar #{pr}: yalnız açık/kapalı bayrakları değişir, ölçüler korunur", [s['preset'], flags.(s), dims.(s) == dims.(df)], [pr, exp, true])
end
t('1.5 K ile L farkı yalnız ön ayar adı', M.mst_ch_preset(df, 'K').reject { |k, _| k == 'preset' } == M.mst_ch_preset(df, 'L').reject { |k, _| k == 'preset' }, true)
t('1.6 ön ayar girdi kesiti değiştirmez', M.mst_ch_preset(df, 'L') && df['left']['on'], true)
leg = Sketchup::Group.new(nil, 'element_type' => 'channel_precast', 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2)
ls = M.mst_ch_section(leg)
t('1.7 eski U eşlemesi: toplam = wi + 2tw, taban = tb, sol / sağ tw × di ofset 0, orta kapalı',
  [ls['total_width_m'], ls['base_m'], ls['left'], ls['right'], ls['mid']['on'], ls['preset']],
  [0.8 + 2 * 0.2, 0.2, { 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 0.0 }, { 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 0.0 }, false, 'U'])
t('1.8 eski kayıt açık kesit sayılmaz (U yolu)', [M.mst_ch_explicit(leg), M.mst_ch_custom_section(leg)], [nil, nil])
t('1.9 tip kaydı eski alanları (inner_width / inner_depth / base / wall) eşlenir',
  M.mst_ch_section('family' => 'PK', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2)['total_width_m'], 0.8 + 2 * 0.2)
t('1.10 bozuk channel_section_json → açık kesit yok (eski anahtarlar)',
  M.mst_ch_custom_section(Sketchup::Group.new(nil, 'channel_section_json' => '{bozuk')), nil)
t('1.11 bilinmeyen yeni biçim (v=2) tahmin edilmez', M.mst_ch_parse('{"v":2,"total_width_m":1,"base_m":0.2}'), nil)
uj = Sketchup::Group.new(nil, 'element_type' => 'channel_precast', 'inner_width_m' => 1.0, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2,
                              'channel_section_json' => M.mst_ch_json(df))
t('1.12 U kesit kaydı eski anahtarlarla çelişirse (eski sürümde U ölçüsü değişmiş) eski anahtarlar geçerli', M.mst_ch_section(uj)['total_width_m'], 1.0 + 2 * 0.2)

# ---------------------------------------------------------------- 2. geçerlilik
vbase = M.mst_ch_preset(df.merge('total_width_m' => 1.8), 'UU')
t('2.1 geçerli üç çıkıntılı kesit', M.mst_ch_valid(vbase.merge('mid' => vbase['mid'].merge('offset_m' => 0.75))), [])
none = M.mst_ch_preset(df, 'OZEL'); M::MST_CH_PARTS.each { |k| none[k]['on'] = false }
t('2.2 çıkıntısız düz plak reddedilir (karar 5)', M.mst_ch_valid(none), ['En az bir çıkıntı açık olmalıdır (çıkıntısız düz plak kanal prekastı olarak oluşturulmaz).'])
bad = M.mst_ch_preset(df, 'U'); bad['left'] = bad['left'].merge('width_m' => 0.0)
t('2.3 açık çıkıntıda ölçü ≤ 0', M.mst_ch_valid(bad), ['Sol çıkıntı: genişlik ve yükseklik sıfırdan büyük olmalıdır.'])
pas = M.mst_ch_preset(df, 'L'); pas['left'] = pas['left'].merge('width_m' => 0.0)
t('2.4 pasif çıkıntının ölçüsü denetlenmez', M.mst_ch_valid(pas), [])
ov = M.mst_ch_preset(df, 'L'); ov['right'] = ov['right'].merge('offset_m' => 1.1)
t('2.5 ofset + genişlik > toplam', M.mst_ch_valid(ov), ['Sağ çıkıntı: ofset + genişlik (1,300 m) toplam genişliği (1,200 m) aşıyor.'])
neg = M.mst_ch_preset(df, 'L'); neg['right'] = neg['right'].merge('offset_m' => -0.1)
t('2.6 negatif ofset', M.mst_ch_valid(neg), ['Sağ çıkıntı: ofset negatif olamaz.'])
cl = M.mst_ch_preset(df, 'UU'); cl['mid'] = cl['mid'].merge('offset_m' => 0.1)
t('2.7 açık çıkıntılar çakışır', M.mst_ch_valid(cl), ['Sol ve Orta çıkıntılar çakışıyor veya bitişik; aralarında boşluk olmalıdır.'])
tc = M.mst_ch_preset(df, 'UU'); tc['mid'] = tc['mid'].merge('offset_m' => 0.2)
t('2.8 açık çıkıntılar bitişik', M.mst_ch_valid(tc), ['Sol ve Orta çıkıntılar çakışıyor veya bitişik; aralarında boşluk olmalıdır.'])
t('2.9 toplam ve taban ≤ 0', M.mst_ch_valid(df.merge('total_width_m' => 0.0, 'base_m' => -1.0)).first(2),
  ['Toplam genişlik sıfırdan büyük olmalıdır.', 'Taban kalınlığı sıfırdan büyük olmalıdır.'])
t('2.10 sayı olmayan değer', M.mst_ch_valid(M.mst_ch_parse(df.merge('base_m' => 'abc'))).include?('Taban kalınlığı sıfırdan büyük olmalıdır.'), true)
t('2.11 U-eşdeğeri değil: ofsetli sağ, farklı yükseklik, orta açık',
  [M.mst_ch_u_equiv?(M.mst_ch_preset(df, 'U').tap { |s| s['right']['offset_m'] = 0.05 }),
   M.mst_ch_u_equiv?(M.mst_ch_preset(df, 'U').tap { |s| s['right']['height_m'] = 0.5 }), M.mst_ch_u_equiv?(M.mst_ch_preset(df, 'UU'))], [false, false, false])

# ---------------------------------------------------------------- 3. alan / yükseklik / kontur / açık göz
ex = { 'v' => 1, 'preset' => 'UU', 'total_width_m' => 1.8, 'base_m' => 0.2, 'left' => { 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 0.0 },
       'mid' => { 'on' => true, 'width_m' => 0.15, 'height_m' => 0.3, 'offset_m' => 0.75 }, 'right' => { 'on' => true, 'width_m' => 0.2, 'height_m' => 0.6, 'offset_m' => 0.0 } }
u18 = M.mst_ch_preset(ex, 'U'); mr = M.mst_ch_preset(ex, 'OZEL').tap { |s| s['left']['on'] = false }; ro = M.mst_ch_preset(ex, 'L')
wide = M.mst_ch_preset(ex, 'L').tap { |s| s['right'] = s['right'].merge('width_m' => 0.9) }
t('3.1 alan: U 0,600 · orta + sağ 0,525 · yalnız sağ 0,480 · sağ 0,90 × 0,60 → 0,900 m²',
  [u18, mr, ro, wide].map { |s| M.mst_ch_area(s).round(6) }, [0.6, 0.525, 0.48, 0.9])
t('3.2 yükseklik: taban + en yüksek açık çıkıntı (karar 2)', [M.mst_ch_height(u18), M.mst_ch_height(M.mst_ch_preset(ex, 'OZEL').tap { |s| s['left']['on'] = false; s['right']['on'] = false })].map { |v| v.round(9) }, [0.8, 0.5])
t('3.3 yükseklik: tipte seçilen çıkıntı (channel_top_ref)', M.mst_ch_height(ex, 'mid').round(9), 0.5)
t('3.4 kontur U-eşdeğerinde eski U profiliyle aynı (nokta sırası ve değerler)',
  M.mst_ch_profile(M.mst_ch_section(leg)), [[0, 0], [0.8 + 2 * 0.2, 0], [0.8 + 2 * 0.2, 0.2 + 0.6], [0.8 + 2 * 0.2 - 0.2, 0.2 + 0.6], [0.8 + 2 * 0.2 - 0.2, 0.2], [0.2, 0.2], [0.2, 0.2 + 0.6], [0, 0.2 + 0.6]].map { |a| a.map(&:to_f) })
t('3.5 kontur L (yalnız sağ, ofset 0)', M.mst_ch_profile(ro).map { |a| a.map { |v| v.round(9) } }, [[0, 0], [1.8, 0], [1.8, 0.8], [1.6, 0.8], [1.6, 0.2], [0, 0.2]])
pa = ->(pts) { s = 0.0; pts.each_with_index { |a, i| b = pts[(i + 1) % pts.length]; s += a[0] * b[1] - b[0] * a[1] }; s / 2.0 }
t('3.6 kontur alanı = kesit alanı (üç çıkıntı, ofsetli sağ)', [ex, M.mst_ch_preset(ex, 'UU').tap { |s| s['right']['offset_m'] = 0.1 }].map { |s| (pa.(M.mst_ch_profile(s)) - M.mst_ch_area(s)).abs < 1e-12 }, [true, true])
t('3.7 açık göz aralıkları [y0, y1, alt z] (üç çıkıntı)', M.mst_ch_open_gaps(ex).map { |a| a.map { |v| v.round(9) } }, [[0.2, 0.75, 0.2], [0.9, 1.6, 0.2]])
t('3.8 açık göz: L kesitte yok, U\'da tek göz', [M.mst_ch_open_gaps(ro), M.mst_ch_open_gaps(u18).map { |a| a.map { |v| v.round(9) } }], [[], [[0.2, 1.6, 0.2]]])
off = M.mst_ch_preset(ex, 'U').tap { |s| s['left']['offset_m'] = 0.1; s['right']['offset_m'] = 0.15 }
t('3.9 dış ledge aralıkları (ofsetli U)', M.mst_ch_ledges(off).map { |a| a.map { |v| v.round(9) } }, [[0.0, 0.1], [1.65, 1.8]])

# ---------------------------------------------------------------- 4. kalıp rolleri ve U formülü tek kaynak
wi, di, tb, tw, l = 0.8, 0.6, 0.2, 0.2, 3.3
ow = wi + 2 * tw; oh = tb + di
old_terms = [l * ow, 2 * l * oh, l * (wi + 2 * di), 2 * (ow * tb + 2 * tw * di)]
t('4.1 mst_ch_u_fw_terms eski ifadelerle bit düzeyinde aynı', M.mst_ch_u_fw_terms(l, wi, di, tb, tw), old_terms)
srand(7)
same = (1..300).all? do
  a = [rand * 2 + 0.05, rand + 0.05, rand * 0.5 + 0.05, rand * 0.4 + 0.05, rand * 20 + 0.5].map { |v| v.round(3) }
  w, d, b, tt, ll = a; o = w + 2 * tt; h = b + d
  M.mst_ch_u_area(w, d, b, tt) == o * b + 2 * tt * d && M.mst_ch_u_area(w, d, b, tt) * ll == ((w + 2 * tt) * b + 2 * tt * d) * ll &&
    M.mst_ch_u_profile(w, d, b, tt) == [[0, 0], [o, 0], [o, h], [o - tt, h], [o - tt, b], [tt, b], [tt, h], [0, h]] &&
    M.mst_ch_u_fw_terms(ll, w, d, b, tt) == [ll * o, 2 * ll * h, ll * (w + 2 * d), 2 * (o * b + 2 * tt * d)] &&
    M.mst_ch_u_outer(w, tt) == w + 2.0 * tt && M.mst_ch_u_height(d, b) == b + d
end
t('4.2 rastgele 300 U ölçüsü: alan / hacim / profil / kalıp terimleri eski ifadelerle bit düzeyinde aynı', same, true)
r = M.mst_ch_formwork_roles(M.mst_ch_section(leg), l)
t('4.3 genel rol formülü U\'da eski terimlerle tutarlı (alt, yanlar, iç, uç; ledge 0)',
  [near(r['OUTER_BOTTOM'], old_terms[0]), near(r['OUTER_SIDE'], old_terms[1]), near(r['INNER_FLOOR'] + r['INNER_SIDE'], old_terms[2]), near(r['END_FACE'], old_terms[3]), r['BASE_LEDGE']], [true, true, true, true, 0.0])
rl = M.mst_ch_formwork_roles(off, 2.0)
t('4.4 ofsetli U: ledge ayrı rol (karar 4), dış yan = 2 × taban + iki dış yüz', [rl['BASE_LEDGE'].round(9), rl['OUTER_SIDE'].round(9), rl['INNER_FLOOR'].round(9), rl['INNER_SIDE'].round(9)],
  [(2.0 * 0.25).round(9), (2.0 * (0.4 + 1.2)).round(9), (2.0 * 1.15).round(9), (2.0 * 1.2).round(9)])
t('4.5 ledge bayrağı yoksa kalıplı; kapatılırsa düşer',
  [near(M.mst_ch_formwork(off, 2.0, bottom: false, sides: false, inner: false, ends: false), 0.5), M.mst_ch_formwork(off, 2.0, bottom: false, sides: false, inner: false, ends: false, ledge: false)], [true, 0.0])
t('4.6 yüz rolü: ofsetli çıkıntının dışa bakan yüzü OUTER_SIDE, göze bakan INNER_SIDE, ledge BASE_LEDGE, göz tabanı INNER_FLOOR',
  [M.mst_ch_face_kind(off, [0, -1, 0], 0.1, 0.5), M.mst_ch_face_kind(off, [0, 1, 0], 0.3, 0.5), M.mst_ch_face_kind(off, [0, 0, 1], 0.05, 0.2),
   M.mst_ch_face_kind(off, [0, 0, 1], 0.9, 0.2), M.mst_ch_face_kind(off, [0, 0, 1], 0.2, 0.8), M.mst_ch_face_kind(off, [0, -1, 0], 0.0, 0.1), M.mst_ch_face_kind(off, [1, 0, 0], 0.9, 0.3)],
  %w[OUTER_SIDE INNER_SIDE BASE_LEDGE INNER_FLOOR WALL_TOP OUTER_SIDE END_FACE])

# ---------------------------------------------------------------- 5. imza / ölçü anahtarı / tanım anahtarı (U aynı, U dışı kesitli)
old_sig = "channel_precast|#{[3.3, 0.8, 0.6, 0.2, 0.2, 'C30/37'].join('|')}"
lg2 = Sketchup::Group.new(nil, 'element_type' => 'channel_precast', 'length_m' => 3.3, 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2, 'concrete_class' => 'C30/37')
t('5.1 eski U tip imzası değişmez', M.element_signature(lg2), old_sig)
t('5.2 eski U ölçü anahtarı değişmez', M.mst_precast_dims_key(lg2), [3300, 800, 600, 200, 200])
lg2u = Sketchup::Group.new(nil, attrs(lg2).merge('channel_section_json' => M.mst_ch_json(M.mst_ch_section(lg2))))
t('5.3 U-eşdeğeri kesit kaydı olan parçada imza ve ölçü anahtarı eski U ile aynı', [M.element_signature(lg2u), M.mst_precast_dims_key(lg2u)], [old_sig, [3300, 800, 600, 200, 200]])
cu = Sketchup::Group.new(nil, 'element_type' => 'channel_precast', 'length_m' => 3.3, 'inner_width_m' => 0.0, 'inner_depth_m' => 0.0, 'base_thickness_m' => 0.0, 'wall_thickness_m' => 0.0,
                              'concrete_class' => 'C30/37', 'channel_section_json' => M.mst_ch_json(ro))
t('5.4 U dışı imzaya kesit eklenir', M.element_signature(cu), "channel_precast|3.3|0.0|0.0|0.0|0.0|C30/37|kesit:1800/200/right:200x600@0")
t('5.5 U dışı ölçü anahtarına kesit eklenir', M.mst_precast_dims_key(cu), [3300, 0, 0, 0, 0, 'kesit:1800/200/right:200x600@0'])
k_l = Sketchup::Group.new(nil, attrs(cu).merge('channel_section_json' => M.mst_ch_json(M.mst_ch_preset(ro, 'K'))))
t('5.6 K ve L aynı geometri → aynı imza (fark yalnız ad)', M.element_signature(k_l), M.element_signature(cu))
p_old = M.mst_precast_def_params(lg2)
t('5.7 U tanım parametrelerinde section yok; tanım anahtarı eski anahtar kümesiyle aynı',
  [p_old.key?('section'), M.mst_def_key('precast', p_old)], [false, M.mst_def_key('precast', { 'type' => 'channel_precast', 'family' => '', 'length_m' => 3.3, 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2, 'fw' => '0000', 'form_mat' => '', 'seg' => 1 })])
t('5.8 U-eşdeğeri kesit kaydı tanım anahtarını değiştirmez', M.mst_def_key('precast', M.mst_precast_def_params(lg2u)), M.mst_def_key('precast', p_old))
p_cu = M.mst_precast_def_params(cu)
t('5.9 U dışı tanım parametresinde section (geometri anahtarı) ve 5 rollü fw', [p_cu['section'], p_cu['fw']], [M.mst_ch_geom_key(ro), '00000'])
t('5.10 formül hacmi: U eski ifade, U dışı kesit alanı × boy',
  [M.mst_precast_formula_volume('channel_precast', attrs(lg2)) == ((0.8 + 2 * 0.2) * 0.2 + 2 * 0.2 * 0.6) * 3.3, near(M.mst_precast_formula_volume('channel_precast', attrs(cu)), 0.48 * 3.3)], [true, true])

# ---------------------------------------------------------------- 6. Prekast Yerleşimi (create_flat_precast 'PK')
def layout_data(lib, rows, extra = {})
  { 'pd_layout_rows' => JSON.generate(rows), 'precast_type_library' => JSON.generate(lib), 'pd_seat_m' => '0.15', 'pd_joint_m' => '0.02', 'pd_y_offset_m' => '0',
    'channel_fw_inner' => '1', 'channel_fw_bottom' => '0', 'channel_fw_sides' => '1', 'channel_fw_ends' => '0', 'pd_body_mode' => 'GROUP' }.merge(extra)
end
pd_t = { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3, 'concrete' => 'C30/37' }
pk_old = { 'uid' => 'pk1', 'family' => 'PK', 'name' => 'PK-01', 'inner_width' => 0.8, 'inner_depth' => 0.6, 'base' => 0.2, 'wall' => 0.2, 'concrete' => 'C30/37' }
fresh_model
l1 = bk(9001, 0.0, 1.0); r1 = bk(9002, 4.0, 5.0)
$model.selection.push(l1, r1)
M.create_flat_precast(layout_data([pd_t, pk_old], [{ 'type_uid' => 'pd1', 'count' => 1 }, { 'type_uid' => 'pk1', 'count' => 1 }]))
pk = find_pk.first
lm = (4.0 * IN - 1.0 * IN + 2 * 0.15.m) / IN
exp_fw = 0.0; ft = [lm * 1.2000000000000002, 2 * lm * 0.8, lm * (0.8 + 2 * 0.6), 2 * ((0.8 + 2 * 0.2) * 0.2 + 2 * 0.2 * 0.6)]; exp_fw += ft[1]; exp_fw += ft[2]
t('6.1 eski U tip kaydı: PK oluştu, işlem tek start + commit', [!pk.nil?, $model.ops.map(&:first)], [true, %i[start commit]])
if pk
  a = attrs(pk)
  t('6.2 eski U: yazılan ölçü / hacim / kalıp değerleri eski formülle bit düzeyinde aynı',
    [a['width_m'], a['inner_width_m'], a['inner_depth_m'], a['base_thickness_m'], a['wall_thickness_m'], a['concrete_volume_m3'], a['formwork_area_m2'], a['top_elevation_m'] - a['bottom_elevation_m']],
    [0.8 + 2 * 0.2, 0.8, 0.6, 0.2, 0.2, ((0.8 + 2 * 0.2) * 0.2 + 2 * 0.2 * 0.6) * lm, exp_fw, 3.3 - (3.3 - (0.2 + 0.6))])
  t('6.3 eski U: channel_section_json yazılmaz (anahtar kümesi aynı)', a.key?('channel_section_json'), false)
  t('6.4 eski U: boyanan kalıp alanı = kayıtlı kalıp alanı', near(marked_m2(pk), a['formwork_area_m2'], 1e-6), true)
  t('6.5 eski U: kalıp rolleri eski sınıflandırma (INNER_FLOOR / INNER_SIDE / OUTER_SIDE)',
    pk.entities.grep(Sketchup::Face).map { |f| f.get_attribute(D, 'formwork_type') }.sort.uniq, %w[INNER_FLOOR INNER_SIDE NON_FORMWORK OUTER_SIDE])
end
pk_l = { 'uid' => 'pk2', 'family' => 'PK', 'name' => 'PK-L1', 'section' => ro.merge('total_width_m' => 1.0, 'right' => ro['right'].merge('height_m' => 0.6)), 'concrete' => 'C30/37' }
fresh_model
l1 = bk(9011, 0.0, 1.0); r1 = bk(9012, 4.0, 5.0)
$model.selection.push(l1, r1)
M.create_flat_precast(layout_data([pd_t, pk_l], [{ 'type_uid' => 'pd1', 'count' => 1 }, { 'type_uid' => 'pk2', 'count' => 1 }], 'pd_body_mode' => 'COMPONENT'))
pk = find_pk.first
t('6.6 U dışı (L) tip kaydı: PK oluştu (Component), tek start + commit', [pk.class.name, $model.ops.map(&:first), $ui_msgs.grep(/hata/i)], ['Sketchup::ComponentInstance', %i[start commit], []])
if pk
  a = attrs(pk); sec = M.mst_ch_section(pk)
  t('6.7 U dışı: channel_section_json yazılır, eski U anahtarları 0 (karar 1), genişlik = toplam',
    [!a['channel_section_json'].to_s.empty?, a['inner_width_m'], a['inner_depth_m'], a['base_thickness_m'], a['wall_thickness_m'], a['width_m']], [true, 0.0, 0.0, 0.0, 0.0, 1.0])
  t('6.8 U dışı: hacim = kesit alanı × boy; yükseklik = taban + çıkıntı', [near(a['concrete_volume_m3'], (1.0 * 0.2 + 0.2 * 0.6) * lm), near(a['top_elevation_m'] - a['bottom_elevation_m'], 0.8)], [true, true])
  fl = { bottom: false, sides: true, inner: true, ends: false, ledge: true }
  t('6.9 U dışı: kalıp = rol formülü = boyanan (tanım) yüz alanı', [near(a['formwork_area_m2'], M.mst_ch_formwork(sec, lm, fl)), near(marked_m2(pk), a['formwork_area_m2'], 1e-6)], [true, true])
  t('6.10 U dışı: tanım anahtarında section var, fw 5 rol', [pk.definition.get_attribute(D, 'mst_def_key').to_s.include?('section='), M.mst_precast_def_params(pk)['fw']], [true, '01001'])
  t('6.11 U dışı: L kesitte ledge rolü boyandı, göz yok (INNER_FLOOR yok)',
    pk.definition.entities.grep(Sketchup::Face).map { |f| f.get_attribute(D, 'formwork_type') }.uniq.sort, %w[BASE_LEDGE NON_FORMWORK OUTER_SIDE])
end
pk_bad = { 'uid' => 'pk3', 'family' => 'PK', 'name' => 'PK-X', 'section' => none, 'concrete' => 'C30/37' }
fresh_model
l1 = bk(9021, 0.0, 1.0); r1 = bk(9022, 4.0, 5.0)
$model.selection.push(l1, r1)
M.create_flat_precast(layout_data([pd_t, pk_bad], [{ 'type_uid' => 'pd1', 'count' => 1 }, { 'type_uid' => 'pk3', 'count' => 1 }]))
t('6.12 geçersiz kesit: işlem geri alınır, Türkçe neden', [$model.ops.map(&:first), $ui_msgs.last.to_s.include?('çıkıntısız düz plak')], [%i[start abort], true])

# ---------------------------------------------------------------- 7. Kanal Prekastı formu (create_channel_precast; karar 10)
form = { 'inner_width_m' => 0.8, 'inner_depth_m' => 0.6, 'base_thickness_m' => 0.2, 'wall_thickness_m' => 0.2, 'seat_left_m' => 0.15, 'seat_right_m' => 0.15,
         'length_mode' => 'AUTO', 'manual_length_m' => 3.3, 'concrete_class' => 'C30/37', 'fw_bottom' => false, 'fw_sides' => true, 'fw_inner' => true, 'fw_ends' => false, 'fw_top' => false }
fresh_model
hb = bk(9031, 0.0, 1.0)
$model.selection.push(hb)
M.create_channel_precast(form)
pk = find_pk.first
t('7.1 form (eski U alanları): Component, tek start + commit, hata yok', [pk.class.name, $model.ops.map(&:first), $ui_msgs], ['Sketchup::ComponentInstance', %i[start commit], []])
if pk
  a = attrs(pk); len = 10.0 + 0.15 + 0.15; outer = 0.8 + 2.0 * 0.2; area = (outer * 0.2) + (2.0 * 0.2 * 0.6)
  t('7.2 form U: hacim / kalıp / iç kalıp / kot değerleri eski formülle bit düzeyinde aynı',
    [a['outer_width_m'], a['concrete_volume_m3'], a['formwork_area_m2'], a['formwork_inner_m2'], a['top_elevation_m'], a['precast_type']],
    [outer, area * len, (0.0 + 2.0 * len * (0.2 + 0.6) + len * (0.8 + 2.0 * 0.6) + 0.0), len * (0.8 + 2.0 * 0.6), 3.0 + 0.2 + 0.6, 'KANAL_PREKASTI_U'])
  t('7.3 form U: destek PID = seçili BK (karar 10), channel_section_json yok', [a['support_left_pid'], a['support_right_pid'], a.key?('channel_section_json')], [9031, 9031, false])
  t('7.4 form U: iç grup yok (tek itme), boyanan = kayıtlı kalıp', [pk.definition.entities.grep(Sketchup::Group).length, near(marked_m2(pk), a['formwork_area_m2'], 1e-6)], [0, true])
end
fresh_model
hb = bk(9041, 0.0, 1.0)
$model.selection.push(hb)
kf = form.merge('section' => M.mst_ch_preset(ex, 'UU'), 'fw_bottom' => true)
M.create_channel_precast(kf)
pk = find_pk.first
t('7.5 form U dışı (üç çıkıntı): Component, tek start + commit', [pk.class.name, $model.ops.map(&:first), $ui_msgs], ['Sketchup::ComponentInstance', %i[start commit], []])
if pk
  a = attrs(pk); len = 10.3; sec = M.mst_ch_section(pk)
  t('7.6 form U dışı: kesit kaydı, eski U anahtarları 0, dış genişlik = toplam, ön ayar etiketi',
    [M.mst_ch_valid(sec), a['inner_width_m'], a['wall_thickness_m'], a['outer_width_m'], a['precast_type'], sec['preset']], [[], 0.0, 0.0, 1.8, 'KANAL_PREKASTI_UU', 'UU'])
  t('7.7 form U dışı: hacim = 0,525 + … (kesit alanı) × boy; kalıp = rol formülü = boyanan',
    [near(a['concrete_volume_m3'], M.mst_ch_area(ex) * len), near(a['formwork_area_m2'], M.mst_ch_formwork(sec, len, bottom: true, sides: true, inner: true, ends: false)), near(marked_m2(pk), a['formwork_area_m2'], 1e-6)], [true, true, true])
  t('7.8 form U dışı: destek PID = BK, formwork_ledge kaydı', [a['support_left_pid'], a['support_right_pid'], a['formwork_ledge']], [9041, 9041, true])
end
fresh_model
hb = bk(9051, 0.0, 1.0)
$model.selection.push(hb)
M.create_channel_precast(form.merge('section' => ro.merge('right' => ro['right'].merge('offset_m' => 2.0))))
t('7.9 form geçersiz kesit: işlem açılmaz, Türkçe neden', [$model.ops.map(&:first).include?(:commit), $ui_msgs.last.to_s.include?('toplam genişliği')], [false, true])

# ---------------------------------------------------------------- 8. KN cebe yerleştirme (mst_kn_create_pk!)
fresh_model
lb = bk(9061, 0.0, 1.0); rb = bk(9062, 4.0, 5.0)
mate = Sketchup::Group.new(9063, 'element_type' => 'flat_precast', 'project' => 'P1'); $model.entities << mate; mate.parent = $model.entities
mat = M.material_for($model, 'MAG Kanal Kalıp #6DBE73', '#6DBE73')
cand = ->(ty) { { 'type' => ty, 'length' => 3.3, 'mate' => mate, 'x0' => 0.85, 'y0' => 2.0, 'z0' => 2.5, 'joint' => 0.02, 'seat' => 0.15, 'l' => lb, 'r' => rb, 'pocket' => { 'bk' => lb, 'side' => 'start' } } }
tu = { 'name' => 'PK-01', 'wi' => 0.8, 'di' => 0.6, 'tb' => 0.2, 'tw' => 0.2, 'concrete' => 'C30/37', 'fw' => '0010', 'form_mat' => mat.name }
iu = M.mst_kn_create_pk!(cand.(tu), $model, nil)
a = attrs(iu)
t('8.1 KN eski U: hacim / genişlik / kot eski formülle aynı, channel_section_json yok',
  [a['width_m'], a['concrete_volume_m3'], a['top_elevation_m'], a.key?('channel_section_json')], [0.8 + 2 * 0.2, ((0.8 + 2 * 0.2) * 0.2 + 2 * 0.2 * 0.6) * 3.3, 2.5 + (0.2 + 0.6), false])
t('8.2 KN eski U: tanım anahtarında section yok', iu.definition.get_attribute(D, 'mst_def_key').to_s.include?('section='), false)
tc_ = { 'name' => 'PK-L1', 'wi' => 0.0, 'di' => 0.0, 'tb' => 0.0, 'tw' => 0.0, 'section' => ro, 'concrete' => 'C30/37', 'fw' => '00101', 'form_mat' => mat.name }
ic = M.mst_kn_create_pk!(cand.(tc_), $model, nil)
a = attrs(ic)
t('8.3 KN U dışı: kesit kaydı, eski anahtarlar 0, hacim = alan × boy, kalıp = boyanan tanım',
  [!a['channel_section_json'].to_s.empty?, a['inner_width_m'], a['width_m'], near(a['concrete_volume_m3'], 0.48 * 3.3), near(a['formwork_area_m2'], M.mst_ch_formwork(ro, 3.3, inner: true, ledge: true), 1e-6)],
  [true, 0.0, 1.8, true, true])
t('8.4 KN U dışı: tanım def_params ile aynı anahtar (yeniden boyutlandırmada aynı tanım bulunur)',
  M.mst_def_key('precast', M.mst_precast_def_params(ic)), ic.definition.get_attribute(D, 'mst_def_key'))
$model.set_attribute(D, 'precast_type_library_json', JSON.generate([{ 'family' => 'PK', 'name' => 'PK-L1', 'section' => ro, 'concrete' => 'C30/37' }]))
ty = M.mst_kn_find_pk_type($model, [ic], 1.8, 0.8)
t('8.5 KN tip arama: U dışı kütüphane tipi dış genişlik + yükseklikle bulunur (5 rollü fw)', ty && [ty['name'], ty['section'] && M.mst_ch_geom_key(ty['section']), ty['fw'].length], ['PK-L1', M.mst_ch_geom_key(ro), 5])

# ---------------------------------------------------------------- 9. Group boy yeniden kurma / Component boy
g = Sketchup::Group.new(nil, attrs(cu).merge('length_m' => 3.3, 'seat_each_side_m' => 0.15)); $model.entities << g; g.parent = $model.entities
f0 = g.entities.add_face(M.mst_ch_profile(ro).map { |yy, zz| Geom::Point3d.new(0, yy.m, zz.m) }); f0.pushpull(3.3.m)
M.paint_channel_precast_formwork(g, 1.8, 0, 0, 0, { bottom: true, sides: false, inner: true, ends: false, ledge: true }, mat, nil, ro)
M.mst_rebuild_channel_precast_length(g, 4.0)
a = attrs(g)
t('9.1 U dışı Group boy yeniden kurma: aynı kesit, hacim ve kalıp yeni boyla, kalıp seçimi korunur',
  [a['length_m'], near(a['concrete_volume_m3'], 0.48 * 4.0), near(a['formwork_area_m2'], M.mst_ch_formwork(ro, 4.0, bottom: true, inner: true, ledge: true)), near(marked_m2(g), a['formwork_area_m2'], 1e-6)],
  [4.0, true, true, true])
M.mst_precast_component_set_length!(ic, 5.0)
t('9.2 U dışı Component boy: yeni tanım (kesitli anahtar), hacim alan × boy',
  [ic.definition.get_attribute(D, 'mst_def_key').to_s.include?('length_m=5|'), near(ic.get_attribute(D, 'concrete_volume_m3'), 0.48 * 5.0)], [true, true])

# ---------------------------------------------------------------- 10. Kontrollü Düzenleme reddi (karar 8), donatı (karar 9), kot eşitleme
CE = M::ControlledEditor
pw = M::ProjectWorkspace
pw.singleton_class.class_eval { alias_method :kp1_vr, :validate_request; alias_method :kp1_en, :entries }
$kp1_target = nil
pw.define_singleton_method(:validate_request) { |_m, _r, _l| [{ entity: $kp1_target, path: [], key: 'k' }] }
pw.define_singleton_method(:entries) { |_m| [] }
gc = Sketchup::Group.new(nil, attrs(cu)); $kp1_target = gc
msg = (CE.resolve($model, {}) rescue $!.message)
t('10.1 Kontrollü Düzenleme: U dışı PK Türkçe ret (karar 8)', msg, 'Bu kanal prekastı U kesit değil; Kanal Prekastı formundan düzenleyin.')
$kp1_target = Sketchup::Group.new(nil, attrs(lg2))
msg = (CE.resolve($model, {}) rescue $!.message)
t('10.2 Kontrollü Düzenleme: eski U PK bu retle durmaz', msg == 'Bu kanal prekastı U kesit değil; Kanal Prekastı formundan düzenleyin.', false)
pw.singleton_class.class_eval { alias_method :validate_request, :kp1_vr; alias_method :entries, :kp1_en }
msg = (M.rebuild_channel_parametric(gc, {}) rescue $!.message)
t('10.3 rebuild_channel_parametric U dışını reddeder', msg, 'Bu kanal prekastı U kesit değil; Kanal Prekastı formundan düzenleyin.')
msg = (M.mst_pc_dims(gc) rescue $!.message)
t('10.4 prekast donatısı: U dışı kesit hacim × kg/m³ (karar 9) — parametrik plan reddi', msg.to_s.start_with?('U kesit olmayan kanal prekastında parametrik donatı planı yok'), true)
t('10.5 prekast donatısı: eski U ölçüleri değişmez', M.mst_pc_dims(lg2), { 'L' => 3.3, 'W' => 0.8 + 2 * 0.2, 'H' => 0.2 + 0.6, 'wi' => 0.8, 'di' => 0.6, 'tb' => 0.2, 'tw' => 0.2 })
fresh_model
hb = bk(9071, 0.0, 1.0, 3.0)
on_bk = Sketchup::Group.new(nil, attrs(lg2).merge('support_left_pid' => 9071, 'support_right_pid' => 9071, 'bottom_elevation_m' => 3.0, 'top_elevation_m' => 3.8))
$model.entities << on_bk; on_bk.parent = $model.entities
M.sync_precast_to_head_beams
t('10.6 tek BK üstüne oturan kanal (form, karar 10) kot eşitlemede BK içine indirilmez', [on_bk.get_attribute(D, 'bottom_elevation_m'), $ui_msgs.last.to_s.include?('0 güncellendi')], [3.0, true])

puts "\nKP1: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
