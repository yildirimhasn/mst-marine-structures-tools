# KP4 (ADR-0515-K2, docs/duzeltme/37 K6 — kullanıcı kararları 3, 7, 11; 09.11.2026) — Kanal prekastı parti P4: döşeme boşluğu + metraj.
#  - PK başına çok aralıklı döşeme açıklığı: çıkıntılar arası kanal gözleri açık; sol / sağ taban üstü (dış ledge) tipte açık / dolu
#    (varsayılan U, L, UU açık; K ve OZEL dolu); dolu ledge döşeme betonuyla dolar (kontur boşaltma, kutu değil).
#  - Yön kesit verisi + dünya dönüşümünden (aynalı / dönük PK); kesit döşeme enine eksenine dik değilse uyarı, açıklık yok.
#  - Eski U (U-eşdeğeri) PK: döşeme planı dc61429 koduyla BİREBİR (net beton, kanal açıklığı, kalıp, kutular).
#  - Çift düşüm yok; silinen PK → Model Kontrolü uyarısı; PK düzenleme sonrası döşeme tetiği (transparent, abort yok).
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir; dc61429 mst_deck_plan / mst_deck_inputs git'ten okunup karşılaştırılır.
# Kanıt düzeyi: sahte nesne. SketchUp içinde yüz çizimi, gerçek Geri Al zinciri, iç içe Component dönüşümü KANITLANMAZ.
# Kullanim: ruby tools/test/kp4_pk_deck.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require 'open3'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kp4_pk_deck.rb <marine_structures_tools klasoru>'
DIR = File.expand_path(dir)
ROOT = File.expand_path('../..', DIR)
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
def r6(a); a.map { |x| x.is_a?(Array) ? r6(x) : (x.is_a?(Float) ? x.round(6) : x) }; end

class Sketchup::Model
  def start_operation(*a); @ops << [:start, a[0]]; ($op_args ||= []) << a; true; end
end
class Sketchup::Entity
  def transform!(tr); @transformation = tr * @transformation; self; end
end
def fresh_model
  $model.entities = Sketchup::Entities.new; $model.entities.parent = $model
  $model.selection = Sketchup::Entities.new
  $model.ops.clear; $op_args = []; $all_ents = {}; $ui_msgs = []
end
def put(e); $model.entities << e; e.parent = $model.entities; ($all_ents ||= {})[e.persistent_id] = e; e; end
# X yönünde BK dizisi (u = X, v = Y): BK x0..x1, Y 0..w, üst 3,00
def bk(pid, x0, x1, w = 1.2, top = 3.0)
  b = Sketchup::Group.new(pid, 'element_type' => 'head_beam', 'element_uid' => "BK-U#{pid}", 'head_beam_id' => "BK#{pid}", 'top_elevation_m' => top)
  b.bounds = Geom::BoundingBox.new([x0 * IN, 0, (top - 1.0) * IN], [x1 * IN, w * IN, top * IN]); put(b)
end
# PK: yerel yerleşim (x boy, y kesit 0..t, z taban altından); tr = yerel → dünya (metre öteleme), dünya kutusu tr'den
def pk(pid, sec, tr_rot, org, len = 3.0, extra = {})
  t0 = sec['total_width_m'].to_f; h = M.mst_ch_height(sec)
  tr = Geom::Transformation.new(tr_rot, org.map { |v| v * IN })
  pts = [0, len].product([0, t0], [0, h]).map { |x, y, z| Geom::Point3d.new(x * IN, y * IN, z * IN).transform(tr) }
  a = { 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => "PK#{pid}", 'element_uid' => "PK-U#{pid}",
        'support_left_pid' => 9001, 'support_right_pid' => 9002, 'inner_width_m' => 0.0, 'inner_depth_m' => 0.0, 'base_thickness_m' => 0.0, 'wall_thickness_m' => 0.0,
        'channel_section_json' => M.mst_ch_json(sec) }.merge(extra)
  e = Sketchup::Group.new(pid, a); e.transformation = tr
  e.bounds = Geom::BoundingBox.new.add(pts); put(e)
end
def pk_u(pid, x0, x1, y0, z0, wi = 0.8, di = 0.6, tb = 0.2, tw = 0.2, pidl = 9001, pidr = 9002)
  e = Sketchup::Group.new(pid, 'element_type' => 'channel_precast', 'precast_family' => 'PK', 'precast_id' => "PK#{pid}", 'element_uid' => "PK-U#{pid}",
                               'support_left_pid' => pidl, 'support_right_pid' => pidr, 'inner_width_m' => wi, 'inner_depth_m' => di, 'base_thickness_m' => tb, 'wall_thickness_m' => tw)
  e.bounds = Geom::BoundingBox.new([x0 * IN, y0 * IN, z0 * IN], [x1 * IN, (y0 + wi + 2 * tw) * IN, (z0 + tb + di) * IN]); put(e)
end
def pd(pid, x0, x1, y0, y1, z0 = 3.0, h = 0.3)
  e = Sketchup::Group.new(pid, 'element_type' => 'flat_precast', 'precast_id' => "PD#{pid}", 'support_left_pid' => 9001, 'support_right_pid' => 9002, 'height_m' => h)
  e.bounds = Geom::BoundingBox.new([x0 * IN, y0 * IN, z0 * IN], [x1 * IN, y1 * IN, (z0 + h) * IN]); put(e)
end
ID3 = [[1, 0, 0], [0, 1, 0], [0, 0, 1]].freeze
MIRY = [[1, 0, 0], [0, -1, 0], [0, 0, 1]].freeze      # yerel y aynalı
ROT180 = [[-1, 0, 0], [0, -1, 0], [0, 0, 1]].freeze   # Z çevresinde 180°
ROT90 = [[0, -1, 0], [1, 0, 0], [0, 0, 1]].freeze     # Z çevresinde 90°: kesit (yerel y) dünya −X = u yönünde
def plan_of(hbs, th = 0.4)
  ins = M.mst_deck_inputs($model, hbs, {})
  [M.mst_deck_plan(ins[2], ins[3], th, ins[4]), ins]
end

HAVE = %i[mst_ch_deck_ledges mst_ch_deck_strips mst_pk_deck_after_edit mst_deck_pk_missing_audit].all? { |s| M.respond_to?(s) }
t('P4 işlevleri tanımlı', HAVE, true)

# Kesitler (metre). L: toplam 1,20, taban 0,20, sağ çıkıntı 0,20 × 0,60 ofset 0 → sol ledge 0–1,00, H 0,80
dfl = M.mst_ch_default
SEC_L = M.mst_ch_preset(dfl, 'L')
SEC_K = M.mst_ch_preset(dfl, 'K')
SEC_UU = M.mst_ch_preset(dfl, 'UU')    # sol 0–0,20, orta 0,525–0,675 (0,30), sağ 1,00–1,20
SEC_OZ = M.mst_ch_parse('preset' => 'OZEL', 'total_width_m' => 1.2, 'base_m' => 0.2,
                        'left' => { 'on' => true, 'width_m' => 0.15, 'height_m' => 0.6, 'offset_m' => 0.1 },
                        'mid' => { 'on' => false, 'width_m' => 0.15, 'height_m' => 0.3, 'offset_m' => 0.5 },
                        'right' => { 'on' => true, 'width_m' => 0.15, 'height_m' => 0.6, 'offset_m' => 0.1 })   # ofsetli: ledge 0–0,10 ve 1,10–1,20
SEC_UOFS = M.mst_ch_preset(SEC_OZ, 'U')   # U ön ayarı + ofset (U-eşdeğeri değil): varsayılan açık

# ---------------------------------------------------------------- 1. kesit: ledge seçimi + şeritler (saf hesap)
if HAVE
  t('1.1 varsayılan ledge (karar 11): U / L / UU açık, K / OZEL dolu',
    [SEC_UOFS, SEC_L, SEC_UU, SEC_K, SEC_OZ].map { |s| M.mst_ch_deck_ledges(s).values_at('left', 'right') },
    [%w[open open], %w[open open], %w[open open], %w[fill fill], %w[fill fill]])
  s2 = M.mst_ch_parse(SEC_OZ.merge('deck_ledge_left' => 'open'))
  t('1.2 tipte açık seçim (deck_ledge_left) okunur, diğeri varsayılan', M.mst_ch_deck_ledges(s2).values_at('left', 'right'), %w[open fill])
  j = M.mst_ch_json(s2)
  t('1.3 seçim JSON gidiş-dönüşte korunur; geometri anahtarı / imza değişmez',
    [M.mst_ch_parse(j)['deck_ledge_left'], M.mst_ch_geom_key(s2) == M.mst_ch_geom_key(SEC_OZ), M.mst_ch_geom_sig(s2) == M.mst_ch_geom_sig(SEC_OZ)], ['open', true, true])
  t('1.4 seçimsiz kesitin JSON metni değişmez (yeni anahtar yazılmaz)', M.mst_ch_json(SEC_L).include?('deck_ledge'), false)
  t('1.5 geçersiz değer yok sayılır', M.mst_ch_parse(SEC_L.merge('deck_ledge_right' => 'xx')).key?('deck_ledge_right'), false)
  # şerit [y0, y1, kesim üstü, katı üstü, tür] (yerel metre). Elle: L → ledge 0–1,0 açık (kesim H 0,8, katı taban 0,2), sağ çıkıntı 1,0–1,2 (0,8)
  ds = M.mst_ch_deck_strips(SEC_L)
  t('1.6 L şeritleri + açık aralık', [r6(ds['strips']), r6(ds['opens'])], [[[0.0, 1.0, 0.8, 0.2, 'open'], [1.0, 1.2, 0.8, 0.8, 'proj']], [[0.0, 1.0]]])
  ds = M.mst_ch_deck_strips(SEC_K)
  t('1.7 K şeritleri: ledge dolu (kesim = katı = taban 0,2), açık aralık yok', [r6(ds['strips']), ds['opens']], [[[0.0, 1.0, 0.2, 0.2, 'fill'], [1.0, 1.2, 0.8, 0.8, 'proj']], []])
  ds = M.mst_ch_deck_strips(SEC_UU)
  # UU: dış çıkıntılar döşemeyi taşır; iki göz + aradaki (alçak) orta çıkıntı tek açık bölge 0,20–1,00
  t('1.8 UU şeritleri: göz + orta + göz tek açık aralık', [r6(ds['strips']), r6(ds['opens'])],
    [[[0.0, 0.2, 0.8, 0.8, 'proj'], [0.2, 0.525, 0.8, 0.2, 'open'], [0.525, 0.675, 0.8, 0.5, 'open'], [0.675, 1.0, 0.8, 0.2, 'open'], [1.0, 1.2, 0.8, 0.8, 'proj']], [[0.2, 1.0]]])
  ds = M.mst_ch_deck_strips(SEC_OZ)
  t('1.9 ofsetli (OZEL): iki ledge dolu, göz 0,25–0,95 açık', [r6(ds['strips']), r6(ds['opens'])],
    [[[0.0, 0.1, 0.2, 0.2, 'fill'], [0.1, 0.25, 0.8, 0.8, 'proj'], [0.25, 0.95, 0.8, 0.2, 'open'], [0.95, 1.1, 0.8, 0.8, 'proj'], [1.1, 1.2, 0.2, 0.2, 'fill']], [[0.25, 0.95]]])
  ds = M.mst_ch_deck_strips(s2)
  t('1.10 ofsetli, sol ledge açık: iki ayrı açık aralık', r6(ds['opens']), [[0.0, 0.1], [0.25, 0.95]])
end

# ---------------------------------------------------------------- 2. eski U: dc61429 ile birebir
old_src, st = Open3.capture2('git', '-C', ROOT, 'show', 'dc61429:src/marine_structures_tools/main.rb')
old_src = old_src.force_encoding('UTF-8')
oplan = old_src[/^def mst_deck_plan\(bks,pcs,th,curbs=\[\]\)\n.*?^end\n/m]
oins = old_src[/^def mst_deck_inputs\(model,hbs,data\)\n.*?^end\n/m]
t('2.0 dc61429 mst_deck_plan / mst_deck_inputs git\'ten okundu', [st.success?, !oplan.nil?, !oins.nil?], [true, true, true])
NEWKEYS = %w[channels ledge_fill_volume].freeze   # P4'te plana eklenen anahtarlar (eski U'da channels yalnız kimlik listesi, dolgu 0)
if oplan && oins
  M.module_eval(oplan.sub('def mst_deck_plan(', 'def mst_deck_plan_dc61429('))
  M.module_eval(oins.sub('def mst_deck_inputs(', 'def mst_deck_inputs_dc61429('))
  # 2a. aynı girdiyle plan (PD + derz + U kanal + PD boşluğu + tretuvar + iki U)
  bks = [{ 'id' => 'A', 'u0' => 0.0, 'u1' => 1.0, 'v0' => 0.0, 'v1' => 6.0, 'ztop' => 3.0 }, { 'id' => 'B', 'u0' => 4.0, 'u1' => 5.0, 'v0' => 0.0, 'v1' => 6.0, 'ztop' => 3.0 }]
  pcs = [{ 'id' => 'PD1', 'type' => 'flat_precast', 'u0' => 0.85, 'u1' => 4.15, 'v0' => 0.0, 'v1' => 0.98, 'z0' => 3.0, 'z1' => 3.3, 'iw' => 0.0, 'base' => 0.0 },
         { 'id' => 'PK1', 'type' => 'channel_precast', 'u0' => 0.85, 'u1' => 4.15, 'v0' => 1.0, 'v1' => 2.2, 'z0' => 2.5, 'z1' => 3.3, 'iw' => 0.8, 'base' => 0.2 },
         { 'id' => 'PD2', 'type' => 'flat_precast', 'u0' => 0.85, 'u1' => 4.15, 'v0' => 2.22, 'v1' => 3.2, 'z0' => 3.0, 'z1' => 3.3, 'iw' => 0.0, 'base' => 0.0 },
         { 'id' => 'PK2', 'type' => 'channel_precast', 'u0' => 0.85, 'u1' => 4.15, 'v0' => 4.0, 'v1' => 5.0, 'z0' => 2.7, 'z1' => 3.25, 'iw' => 0.6, 'base' => 0.15 }]
  curbs = [{ 'side' => '1', 'u0' => 0.0, 'u1' => 5.0, 'v0' => 0.0, 'v1' => 0.3, 'kind' => 'curb', 'h' => 0.2, 'id' => 'Tretuvar taraf 1' }]
  [[0.4, []], [0.4, curbs], [0.25, curbs], [0.6, []]].each_with_index do |(th, cb), i|
    a = M.mst_deck_plan_dc61429(bks, pcs, th, cb); b = M.mst_deck_plan(bks, pcs, th, cb)
    t("2.#{i + 1} U plan birebir (kalınlık #{th}, tretuvar #{cb.length}): tüm alanlar", b.reject { |k, _| NEWKEYS.include?(k) }, a)
  end
  # 2b. sahte modelde tüm yol (girdi + plan): eski U PK (channel_section_json yok)
  fresh_model
  ha = bk(9001, 0.0, 1.0, 6.0); hb = bk(9002, 4.0, 5.0, 6.0)
  pd(9101, 0.85, 4.15, 0.0, 0.98); pk_u(9102, 0.85, 4.15, 1.0, 2.5); pd(9103, 0.85, 4.15, 2.22, 3.2); pk_u(9104, 0.85, 4.15, 4.0, 2.7, 0.6, 0.4, 0.15, 0.2)
  oi = M.mst_deck_inputs_dc61429($model, [ha, hb], {}); ni = M.mst_deck_inputs($model, [ha, hb], {})
  t('2.5 eski U PK girdisi: eski alanlar aynı, şerit yok', [ni[3].map { |p| p.reject { |k, _| k == 'uid' } } == oi[3], ni[3].none? { |p| p.key?('strips') }], [true, true])
  a = M.mst_deck_plan_dc61429(oi[2], oi[3], 0.4, oi[4]); b = M.mst_deck_plan(ni[2], ni[3], 0.4, ni[4])
  t('2.6 eski U modeli: net beton, kanal açıklığı hacmi, kalıp, kutular birebir',
    [b['volume'] == a['volume'], b['opening_volume'] == a['opening_volume'], b['formwork'] == a['formwork'], b['boxes'] == a['boxes'], b['faces'] == a['faces'], b.reject { |k, _| NEWKEYS.include?(k) } == a,
     b['precast_cut_volume'] == a['precast_cut_volume'], b['ledge_fill_volume']], [true] * 7 + [0.0])
  # 2c. U ön ayarlı, ofset 0 açık kesit (U-eşdeğeri) → eski U yolu
  fresh_model
  ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0)
  e = pk_u(9105, 1.0, 4.0, 0.0, 2.5); e.set_attribute(D, 'channel_section_json', M.mst_ch_json(M.mst_ch_from_u(0.8, 0.6, 0.2, 0.2)))
  oi = M.mst_deck_inputs_dc61429($model, [ha, hb], {}); ni = M.mst_deck_inputs($model, [ha, hb], {})
  t('2.7 U-eşdeğeri açık kesit: eski yol (şerit yok), plan birebir',
    [ni[3][0].key?('strips'), M.mst_deck_plan(ni[2], ni[3], 0.4, ni[4]).reject { |k, _| NEWKEYS.include?(k) } == M.mst_deck_plan_dc61429(oi[2], oi[3], 0.4, oi[4])], [false, true])
end

# ---------------------------------------------------------------- 3. U dışı kesit: bağımsız elle hesap
# Ortak düzen: BK A x 0–1, BK B x 4–5, Y 0–1,20, üst 3,00; döşeme 0,40 → üst 3,40. PK x 1–4 (boy 3), Y 0–1,20, alt 2,50 (H 0,80 → üst 3,30).
# Brüt = 5 × 1,2 × 0,4 = 2,40. BK üstü iki hücre: 2 × (1 × 1,2 × 0,4) = 0,96 (PK BK üstüne taşmaz).
# Açıklık (u 1–4) içinde "prekast cebi" (DS1.3) PK üstüne (3,30) kadar kesilir; açık şerit 2,70'ten (taban üstü) döşeme üstüne açılır,
#  açıklık hacmi yalnız kesimin üstü (3,30–3,40) = eski U ile aynı anlam. Dolu şeritte (ledge / dış çıkıntı) döşeme kendi katı üstüne kadar iner.
if HAVE
  # 3.1 L (sol ledge açık varsayılan): ledge Y 0–1,0 açık → beton 0, açıklık 3 × 1,0 × 0,1 = 0,30; çıkıntı Y 1,0–1,2 → 3 × 0,2 × 0,1 = 0,06
  #  net = 0,96 + 0,06 = 1,02; prekast kesintisi = (3 × 1,0 × 0,3) + (3 × 0,2 × 0,3) = 1,08; kontrol 1,02 + 0,30 + 1,08 = 2,40
  #  kalıp: dış = BK hücreleri (u uç 1,2 × 0,4 + iki v kenarı 2 × 1 × 0,4) × 2 = 2,56 + çıkıntı şeridi v = 1,2 kenarı 3 × 0,1 = 2,86;
  #         iç = BK hücresinin açıklığa bakan yüzü 1,0 × 0,4 × 2 = 0,80 + çıkıntı şeridinin göze bakan yüzü 3 × 0,1 = 1,10; alt 0
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9201, SEC_L, ID3, [1.0, 0.0, 2.5])
  pl, = plan_of([ha, hb])
  t('3.1 L: net 1,02, açıklık 0,30 (1 adet), prekast kesintisi 1,08, kalıp dış 2,86 / iç 1,10 / alt 0, hata yok',
    [near(pl['volume'], 1.02), near(pl['opening_volume'], 0.30), pl['openings'].length, near(pl['precast_cut_volume'], 1.08), near(pl['formwork_outer'], 2.86), near(pl['formwork_inner'], 1.10), near(pl['formwork_bottom'], 0.0), pl['errors'], pl['warnings']],
    [true, true, 1, true, true, true, true, [], []])
  t('3.2 L açıklık dikdörtgeni: u 1–4, v 0–1,0, taban üstü 2,70', r6(pl['openings'].map { |o| [o['u0'], o['u1'], o['v0'], o['v1'], o['zf']] }), [[1.0, 4.0, 0.0, 1.0, 2.7]])
  # 3.3 K (ledge dolu): ledge Y 0–1,0 döşeme betonu 2,70–3,40 → 3 × 1,0 × 0,7 = 2,10; çıkıntı 0,06; net 0,96 + 2,10 + 0,06 = 3,12; açıklık 0
  #  kalıp: dış 2,56 + çıkıntı v=1,2 kenarı 0,3 + ledge v=0 kenarı 3 × 0,7 = 2,10 → 4,96; iç 0 (BK yüzü / çıkıntı yüzü temas); alt 0 (ledge üstü temas)
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9202, SEC_K, ID3, [1.0, 0.0, 2.5])
  pl, = plan_of([ha, hb])
  t('3.3 K: dış ledge döşemeyle dolu — net 3,12, açıklık 0, kalıp dış 4,96 / iç 0 / alt 0',
    [near(pl['volume'], 3.12), near(pl['opening_volume'], 0.0), pl['openings'].length, near(pl['formwork_outer'], 4.96), near(pl['formwork_inner'], 0.0), near(pl['formwork_bottom'], 0.0)],
    [true, true, 0, true, true, true])
  t('3.4 K: dolu ledge kutusu 2,70–3,40 (kontur boşaltma, kutu değil)', pl['boxes'].include?([1.0, 4.0, 0.0, 1.0, 2.7, 3.4]), true)
  # ledge dolgusunun BK üstü (3,00) altı: 3 × 1,0 × 0,3 = 0,90 (brüt kutu dışında, net betona dahil);
  #  prekast kesintisi (brüt kutu içinde) yalnız çıkıntı şeridi 3,00–3,30: 3 × 0,2 × 0,3 = 0,18; kontrol 3,12 − 0,90 + 0,18 = 2,40
  t('3.4b K: ledge dolgusu 0,90, prekast kesintisi 0,18 (negatif değil), (net − dolgu) + kesinti + açıklık = brüt',
    [near(pl['ledge_fill_volume'], 0.9), near(pl['precast_cut_volume'], 0.18), near(pl['volume'] - pl['ledge_fill_volume'] + pl['precast_cut_volume'] + pl['opening_volume'], 2.4)], [true, true, true])
  # 3.5 UU: dış çıkıntılar 2 × 0,06 = 0,12; açık bölge Y 0,2–1,0 (göz + orta + göz) → açıklık 3 × 0,8 × 0,1 = 0,24 (orta ayrıca düşülmez); net 1,08
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9203, SEC_UU, ID3, [1.0, 0.0, 2.5])
  pl, = plan_of([ha, hb])
  t('3.5 UU: net 1,08, açıklık 0,24 (tek açık bölge), prekast kesintisi 1,08',
    [near(pl['volume'], 1.08), near(pl['opening_volume'], 0.24), pl['openings'].length, near(pl['precast_cut_volume'], 1.08)], [true, true, 1, true])
  # 3.6 ofsetli OZEL (ledge dolu): ledge 2 × 3 × 0,1 × 0,7 = 0,42; çıkıntı 2 × 3 × 0,15 × 0,1 = 0,09; göz Y 0,25–0,95 açıklık 3 × 0,7 × 0,1 = 0,21
  #  net 0,96 + 0,42 + 0,09 = 1,47
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9204, SEC_OZ, ID3, [1.0, 0.0, 2.5])
  pl, = plan_of([ha, hb])
  t('3.6 ofsetli (ledge dolu): net 1,47, açıklık 0,21, 1 açıklık v 0,25–0,95',
    [near(pl['volume'], 1.47), near(pl['opening_volume'], 0.21), r6(pl['openings'].map { |o| [o['v0'], o['v1']] })], [true, true, [[0.25, 0.95]]])
  # 3.7 ofsetli, sol ledge açık (tip seçimi): sol ledge 3 × 0,1 × 0,1 = 0,03 açıklık; net 1,47 − 0,21 = 1,26; açıklık 0,24; 2 açıklık
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9205, M.mst_ch_parse(SEC_OZ.merge('deck_ledge_left' => 'open')), ID3, [1.0, 0.0, 2.5])
  pl, = plan_of([ha, hb])
  t('3.7 ofsetli, sol ledge açık: net 1,26, açıklık 0,24, 2 açıklık', [near(pl['volume'], 1.26), near(pl['opening_volume'], 0.24), pl['openings'].length], [true, true, 2])
  # 3.8 çift düşüm: (net − ledge dolgusu) + açıklık + prekast kesintisi = brüt; açıklık hücreleri bir kez
  #  elle (3.7): sağ ledge dolgusu BK üstü altı 3 × 0,1 × 0,3 = 0,09; kesinti = sağ ledge yok (dolu) + iki çıkıntı 2 × 3 × 0,15 × 0,3 = 0,27
  #  + göz 3 × 0,7 × 0,3 = 0,63 + sol açık ledge 3 × 0,1 × 0,3 = 0,09 → 0,99; kontrol (1,26 − 0,09) + 0,24 + 0,99 = 2,40
  t('3.8 çift düşüm yok: dolgu 0,09, kesinti 0,99, (net − dolgu) + açıklık + kesinti = brüt (2,40)',
    [near(pl['ledge_fill_volume'], 0.09), near(pl['precast_cut_volume'], 0.99), near(pl['volume'] - pl['ledge_fill_volume'] + pl['opening_volume'] + pl['precast_cut_volume'], 2.4)], [true, true, true])
  # U-eşdeğeri olmayan U (ofsetli, açık ledge) + eski U yan yana: eski U açıklığı değişmez
  fresh_model; ha = bk(9001, 0.0, 1.0, 3.0); hb = bk(9002, 4.0, 5.0, 3.0); pk(9206, SEC_UOFS, ID3, [1.0, 0.0, 2.5]); pk_u(9207, 1.0, 4.0, 1.8, 2.5)
  pl, = plan_of([ha, hb])
  ou = pl['openings'].select { |o| o['id'] == 'PK9207' }
  t('3.9 karışık: eski U açıklığı merkez ± iç genişlik/2 (v 2,0–2,8), U-ofsetli 3 açık aralık',
    [r6(ou.map { |o| [o['v0'], o['v1'], o['zf']] }), pl['openings'].count { |o| o['id'] == 'PK9206' }], [[[2.0, 2.8, 2.7]], 3])
end

# ---------------------------------------------------------------- 4. yön: aynalı / dönük / dik
if HAVE
  # 4.1 yerel y aynalı (orijin Y 1,2): çıkıntı dünya Y 0–0,2, ledge 0,2–1,2 açık → aynı hacim, çıkıntı kutusu v 0–0,2
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9301, SEC_L, MIRY, [1.0, 1.2, 2.5])
  pl, = plan_of([ha, hb])
  t('4.1 aynalı L: net 1,02, açıklık v 0,2–1,2, çıkıntı kutusu v 0–0,2',
    [near(pl['volume'], 1.02), r6(pl['openings'].map { |o| [o['v0'], o['v1']] }), pl['boxes'].include?([1.0, 4.0, 0.0, 0.2, 3.3, 3.4])], [true, [[0.2, 1.2]], true])
  # 4.2 Z çevresinde 180° (orijin X 4, Y 1,2): aynı sonuç
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9302, SEC_L, ROT180, [4.0, 1.2, 2.5])
  pl, = plan_of([ha, hb])
  t('4.2 180° dönük L: net 1,02, açıklık v 0,2–1,2', [near(pl['volume'], 1.02), r6(pl['openings'].map { |o| [o['v0'], o['v1']] })], [true, [[0.2, 1.2]]])
  # 4.3 ofsetli + aynalı: sol ledge açık seçimi aynada dünya sağına (v 1,1–1,2) düşer
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9303, M.mst_ch_parse(SEC_OZ.merge('deck_ledge_left' => 'open')), MIRY, [1.0, 1.2, 2.5])
  pl, = plan_of([ha, hb])
  t('4.3 aynalı ofsetli: açık yerel-sol ledge dünya v 1,1–1,2', r6(pl['openings'].map { |o| [o['v0'], o['v1']] }).sort, [[0.25, 0.95], [1.1, 1.2]])
  # 4.4 Z çevresinde 90°: kesit döşeme boyuna (u) yönünde → açıklık oluşturulmaz, Türkçe uyarı, kutu kesilir (eski davranış)
  fresh_model; ha = bk(9001, 0.0, 1.0, 4.0); hb = bk(9002, 4.0, 5.0, 4.0); pk(9304, SEC_L, ROT90, [3.2, 0.5, 2.5])
  pl, = plan_of([ha, hb])
  t('4.4 90° dönük: açıklık yok, uyarı (kesit yönü)', [pl['openings'].length, pl['warnings'].any? { |w| w.include?('PK9304') && w.include?('kesit yönü') }], [0, true])
end

# ---------------------------------------------------------------- 5. silinen PK → Model Kontrolü uyarısı (karar 7)
def deck_with(pj, extra = {})
  d = Sketchup::Group.new(9501, { 'element_type' => 'deck_slab', 'deck_id' => 'D-001', 'deck_plan_json' => JSON.generate(pj) }.merge(extra)); put(d)
end
if HAVE
  fresh_model; e = pk_u(9401, 1.0, 4.0, 0.0, 2.5)
  dk = deck_with({ 'boxes' => [], 'openings' => [{ 'id' => 'PK9401' }], 'channels' => [{ 'id' => 'PK9401', 'uid' => 'PK-U9401' }] })
  els = []; M.collect_elements($model.entities, els)
  t('5.1 PK var → uyarı yok', M.mst_deck_pk_missing_audit(els), [])
  e.erase!
  els = []; M.collect_elements($model.entities, els)
  w = M.mst_deck_pk_missing_audit(els)
  t('5.2 PK silindi → WARNING, Döşeme Metrajı, PK kimliği + "Seçili Döşemeyi Güncelle"',
    [w.length, w[0] && w[0][0], w[0] && w[0][2], w[0] && w[0][3].include?('PK9401'), w[0] && w[0][4].include?('Döşemeyi Güncelle'), w[0] && w[0][1] == dk], [1, 'WARNING', 'Döşeme Metrajı', true, true, true])
  # PK kimlik adı değişti ama UID aynı → uyarı yok
  fresh_model; e = pk_u(9402, 1.0, 4.0, 0.0, 2.5); e.set_attribute(D, 'precast_id', 'PK-YENI')
  deck_with({ 'boxes' => [], 'openings' => [{ 'id' => 'PK9402' }], 'channels' => [{ 'id' => 'PK9402', 'uid' => 'PK-U9402' }] })
  els = []; M.collect_elements($model.entities, els)
  t('5.3 ad değişti, UID aynı → uyarı yok', M.mst_deck_pk_missing_audit(els), [])
  # P4 öncesi döşeme (channels yok): açıklık kimliğiyle
  fresh_model; deck_with({ 'boxes' => [], 'openings' => [{ 'id' => 'PK9403' }] })
  els = []; M.collect_elements($model.entities, els)
  t('5.4 eski döşeme (channels yok), açıklığın PK\'sı yok → uyarı', M.mst_deck_pk_missing_audit(els).length, 1)
  fresh_model; deck_with({ 'boxes' => [] }, 'deck_plan_json' => 'bozuk{')
  els = []; M.collect_elements($model.entities, els)
  t('5.5 bozuk / boş plan → uyarı yok, hata yok', M.mst_deck_pk_missing_audit(els), [])
  src = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
  t('5.6 mst_audit_v0515 denetimi çağırır', src[/^def mst_audit_v0515.*?^end\n/m].to_s.include?('mst_deck_pk_missing_audit'), true)
  # plan çıktısı channels: kimlik + UID
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); pk(9404, SEC_L, ID3, [1.0, 0.0, 2.5])
  pl, = plan_of([ha, hb])
  t('5.7 plan channels: PK kimliği + UID', pl['channels'], [{ 'id' => 'PK9404', 'uid' => 'PK-U9404' }])
end

# ---------------------------------------------------------------- 6. tetik: PK düzenlemesi sonrası döşeme (transparent, abort yok)
if HAVE
  $regen = []
  M.singleton_class.send(:alias_method, :kp4_regen_orig, :mst_deck_regenerate!)
  M.define_singleton_method(:mst_deck_regenerate!) do |dk, _m = nil, _s = false|
    raise 'sahte yeniden üretim hatası' if $regen_fail
    $regen << dk
    rev = dk.get_attribute(D, 'deck_revision_no', 0).to_i + 1; dk.set_attribute(D, 'deck_revision_no', rev)
    { 'id' => 'D-001', 'old' => [1.0, 0.0], 'new' => [1.0, 0.0], 'warnings' => [], 'rev' => rev }
  end
  fresh_model; ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0); other = bk(9003, 8.0, 9.0)
  e = pk(9601, SEC_L, ID3, [1.0, 0.0, 2.5])
  dk = deck_with({ 'boxes' => [] }, 'support_pids' => '9001,9002', 'deck_revision_no' => 3)
  d2 = Sketchup::Group.new(9502, 'element_type' => 'deck_slab', 'deck_id' => 'D-002', 'deck_plan_json' => '{"boxes":[]}', 'support_pids' => '9003'); put(d2)
  $model.ops.clear; $op_args = []
  r = M.mst_pk_deck_after_edit([e], $model)
  t('6.1 PK destek BK\'larına dayanan döşeme yenilenir (diğeri değil), revizyon ileri (3 → 4)', [$regen, dk.get_attribute(D, 'deck_revision_no'), r.length], [[dk], 4, 1])
  t('6.2 tek transparent işlem (4. bağımsız değişken true), commit, abort yok', [$model.ops.map(&:first), $op_args.map { |x| x[3] }, $model.ops.include?([:abort])], [%i[start commit], [true], false])
  $model.ops.clear; $op_args = []; $regen = []
  t('6.3 desteksiz / geçersiz PK → işlem açılmaz', [M.mst_pk_deck_after_edit([pk(9602, SEC_L, ID3, [1.0, 0.0, 2.5], 3.0, 'support_left_pid' => 0, 'support_right_pid' => 0)], $model), $model.ops], [[], []])
  # hata yolu: commit_with_dependencies istisnası → yine commit, abort yok, bildirim
  M.singleton_class.send(:alias_method, :kp4_cwd_orig, :commit_with_dependencies)
  M.define_singleton_method(:commit_with_dependencies) { |*_a| raise 'sahte bağımlılık hatası' }
  $model.ops.clear; $op_args = []; $ui_msgs = []
  M.mst_pk_deck_after_edit([e], $model)
  M.singleton_class.send(:alias_method, :commit_with_dependencies, :kp4_cwd_orig)
  t('6.4 hata: commit ile kapanır, abort yok, Türkçe bildirim', [$model.ops.map(&:first), $model.ops.include?([:abort]), $ui_msgs.join.include?('sahte bağımlılık hatası')], [%i[start commit], false, true])
  # sync_precast_to_head_beams: TOP modlu PK kotu değişince döşeme tetiklenir (BK işlemi kapandıktan sonra)
  fresh_model
  ha = bk(9001, 0.0, 1.0); hb = bk(9002, 4.0, 5.0)
  e = pk_u(9603, 1.0, 4.0, 0.0, 2.4); e.set_attribute(D, 'bottom_elevation_m', 2.4)
  pd(9604, 1.0, 4.0, 1.3, 2.3).set_attribute(D, 'height_m', 0.3)
  dk = deck_with({ 'boxes' => [] }, 'support_pids' => '9001,9002')
  $model.ops.clear; $op_args = []; $regen = []
  M.sync_precast_to_head_beams
  t('6.5 PD kot eşitleme: PK taşındı → normal işlem commit, sonra transparent döşeme işlemi, abort yok',
    [$model.ops.map(&:first), $op_args.map { |x| x[3] }, $regen, $model.ops.include?([:abort])], [%i[start commit start commit], [nil, true], [dk], false])
  src = File.binread(File.join(DIR, 'controlled_editor.rb')).force_encoding('UTF-8')
  t('6.6 Kontrollü Düzenleme: PK geometri değişikliği commit sonrası döşeme tetiği', src.include?('mst_pk_deck_after_edit'), true)
  msrc = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
  obs = ->(s) { s.scan(/Observer\b/).length }
  t('6.7 silme observer\'ı yok (karar 7): main.rb observer başvuru sayısı dc61429 ile aynı', old_src.empty? ? nil : obs.(msrc) == obs.(old_src), true)
  M.singleton_class.send(:alias_method, :mst_deck_regenerate!, :kp4_regen_orig)
end

puts "\nKP4: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
