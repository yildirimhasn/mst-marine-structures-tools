# A2 / K58 (G1: donatili Component prekastin boyu degisince donati/tonaj sizmasi), K60 (prekast cizim hatasinda eski tonaj),
# K09 (paylasilan tanim: soru, Make Unique + veri koruma, menfez otomatik yol) — ADR-0515 §2, §6.
# Kullanim: ruby tools/test/a2_k58_k60_k09_pc.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
pc = A1.src('mst_pc_rebar.rb')
bm = A1.src('mst_v50_beams.rb')

class FakeDefs < Array
  def add(name); d = Sketchup::ComponentDefinition.new(500_000 + length); d.name = name; self << d; d; end
end
class Host
  MST_DEF_SCHEMA = 1
  def mst_precast_face_flags(_e, _r); [[true, true, true, false, false], nil]; end
  def mst_precast_def_label(_p); 'Prekast'; end
  def mst_precast_build_geometry!(d, _p, _m = nil); d; end
  def mst_precast_formula_volume(_t, h, len = nil); (len || h['length_m']).to_f * 1.2 * 0.3; end
  def mst_marked_area_m2(_e); 0.0; end
  def mst_pc_family(_e); 'PD'; end
  def mst_pc_params(_f, h); h; end
  def mst_pc_dims(_e); {}; end
  def mst_pc_plan(*_a); { spec: {}, map: nil }; end
  def mst_dr_geometry(_e); [[], [], []]; end
  def mst_dr_draw!(e, _s, _p); raise 'çizim hatası (sahte)' if $draw_fail; $draws << (e.is_a?(Sketchup::ComponentInstance) ? e.definition : e); e.set_attribute(DICT, 'rebar_t', 0.42); end
  def mst_dr_set_of(e); $sets[e.is_a?(Sketchup::ComponentInstance) ? e.definition : e] || []; end
  def mst_dr_erase_set!(g); $log << [:erase_set, g]; end
  def mst_dr_purge_defs!(_m); end
  def rebar_rate(_k); 120.0; end
  def qto3_quantity(e, _k); e.get_attribute(DICT, 'concrete_volume_m3', 0).to_f; end
end
a2_const(Host, pc, 'MST_PC_ATTRS')
a2_const(Host, main, 'MST_PRECAST_DEF_DIMS')
a2_const(Host, main, 'MST_PRECAST_FW_ROLES')
a2_const(Host, main, 'MST_REBAR_RATE_KEYS')
a2_const(Host, main, 'MST_REBAR_BIM_TYPES')
A1.load(Host, main, 'def mst_def_value(', 'def mst_def_key(', 'def mst_def_find(', 'def mst_def_register!(', 'def mst_def_find_or_create(',
        'def mst_precast_def_params(', 'def mst_precast_definition(', 'def mst_precast_component_set_length!(', 'def mst_attr_hash(',
        'def mst_element_rebar(', 'def mst_hb_ents(')
A1.load(Host, pc, 'def mst_pc_peers(', 'def mst_pc_draw!(', 'def mst_pc_clear!(', 'def mst_pc_def_rebar(', 'def mst_pc_after_rebuild!(')
K09 = A1.load_opt(Host, main, 'def mst_shared_def_prompt(') & A1.load_opt(Host, main, 'def mst_make_unique_keep_data!(')
obs('K09 yardımcıları tanımlı', K09)
h = Host.new
D = A1::DICT
def piece(pid, len, extra = {})
  Sketchup::ComponentInstance.new(pid, { 'element_type' => 'flat_precast', 'precast_family' => 'PD', 'id' => "PD-#{pid}", 'element_uid' => "UID-#{pid}",
                                         'length_m' => len, 'width_m' => 1.2, 'height_m' => 0.3, 'concrete_volume_m3' => len * 0.36 }.merge(extra))
end
def reset_pc!
  a1_reset!
  $model.definitions = FakeDefs.new
  $draws = []; $sets = {}; $draw_fail = false
end

# ---- K58 (G1 yeniden üretim): A donatılı 4.30, B donatısız 4.00 (kendi tanımı); A'nın boyu 4.00 yapılır
reset_pc!
b = piece(2, 4.0)
d400 = h.mst_precast_definition($model, h.mst_precast_def_params(b)); b.definition = d400
a = piece(1, 4.3, 'pc_rebar_json' => '{"cover_mm":40}', 'rebar_mode' => 'auto_detail', 'rebar_t' => 0.5)
a.definition = h.mst_precast_definition($model, h.mst_precast_def_params(a))
h.mst_precast_component_set_length!(a, 4.0)
h.mst_pc_after_rebuild!(a)
obs('K58 A yeni tanımı = B tanımı (paylaşım)', a.definition == d400)
obs('K58 B (seçilmemiş, donatısız) rebar_mode / rebar_t', [b.a('rebar_mode'), b.a('rebar_t')])
obs('K58 çizimin yapıldığı tanım B tanımı mı', $draws.include?(d400))
t('K58: donatılı parça donatısız parçanın tanımına geçmez (0.51.4: geçer)', a.definition == d400, false)
t('K58: B\'ye donatı / tonaj sızmaz (0.51.4: auto_detail + tonaj)', [b.a('rebar_mode'), b.a('pc_rebar_json')], [nil, nil])
t('K58: B tanımına çizim yapılmaz', $draws.include?(d400), false)
t('K58: donatısız parçanın tanım anahtarı değişmez', d400.get_attribute(D, 'mst_def_key', '').include?('rebar='), false)
a2 = piece(3, 4.3, 'pc_rebar_json' => '{"cover_mm":40}')
h.mst_precast_component_set_length!(a2, 4.0)
t('K58: aynı boy + aynı donatı → aynı (donatılı) tanım paylaşılabilir', a2.definition == a.definition, true)

# ---- K60: çizim hatası → eski tonaj kalmaz, tanım kaydı okunmaz
reset_pc!
c = piece(5, 4.0, 'pc_rebar_json' => '{"cover_mm":40}', 'rebar_mode' => 'auto_detail', 'rebar_t' => 0.5, 'rebar_kind' => 'PREKAST-PD')
dc = Sketchup::ComponentDefinition.new(77, 'pc_rebar_attrs_json' => JSON.generate('rebar_t' => 0.5)); c.definition = dc
$sets[dc] = [:set1]
$draw_fail = true
h.mst_pc_after_rebuild!(c)
obs('K60 hata sonrası öznitelikler', [c.a('rebar_mode'), c.a('rebar_t'), c.a('pc_rebar_json'), c.a('pc_rebar_error')])
t('K60: pc_rebar_error yazıldı', c.a('pc_rebar_error').to_s.include?('çizim hatası'), true)
t('K60: rebar_mode / rebar_t silindi, pc_rebar_json korundu', [c.a('rebar_mode'), c.a('rebar_t'), c.a('pc_rebar_json')], [nil, nil, '{"cover_mm":40}'])
t('K60: tek örnekli tanımda 3B set silindi', $log.count { |x| x[0] == :erase_set }, 1)
r = h.mst_element_rebar(c)
obs('K60 mst_element_rebar', r)
t('K60: metraj pursantaja döner (1.44 m³ × 120 = 172.8 kg; 0.51.4: eski 0.5 t)', [r['source'], r['kg'].round(3)], ['%', 172.8])
$draw_fail = false
h.mst_pc_draw!(c)
t('K60: başarılı çizim bayrağı siler', c.a('pc_rebar_error'), nil)
c.set_attribute(D, 'pc_rebar_error', 'x'); h.mst_pc_clear!(c)
t('K60: Prekast Donatısı SİL bayrağı da siler', c.a('pc_rebar_error'), nil)

# ---- K09 otomatik yol: donatısı farklı parçayla paylaşılan tanım → çizilmez
reset_pc!
p1 = piece(11, 4.0, 'pc_rebar_json' => '{"cover_mm":40}'); p2 = piece(12, 4.0)
ds = Sketchup::ComponentDefinition.new(88); p1.definition = ds; p2.definition = ds
h.mst_pc_after_rebuild!(p1)
t('K09: paylaşılan + farklı donatı → çizim yok, p2 değişmez, hata', [$draws.length, p2.a('rebar_mode'), !p1.a('pc_rebar_error').nil?], [0, nil, true])
p3 = piece(13, 4.0, 'pc_rebar_json' => '{"cover_mm":40}'); p3.definition = ds; p2.definition = Sketchup::ComponentDefinition.new(89)
p1.delete_attribute(D, 'pc_rebar_error')
h.mst_pc_after_rebuild!(p1)
t('K09: paylaşan parçalar aynı donatılı → çizilir (eşler zaten aynı)', [$draws.length, p1.a('pc_rebar_error'), p3.a('rebar_mode')], [1, nil, 'auto_detail'])

if K09
  # ---- K09 yardımcıları
  reset_pc!
  od = Sketchup::ComponentDefinition.new(99, 'mst_def_kind' => 'head_beam', 'mst_def_key' => 'KEY-1', 'mst_def_params_json' => '{}', 'pc_rebar_attrs_json' => '{"rebar_t":1}')
  i1 = piece(21, 4.0); i2 = piece(22, 4.0); i3 = piece(23, 4.0)
  [i1, i2, i3].each { |x| x.definition = od }
  $ui_answer = IDNO
  t('K09 soru: Hayır → :cancel, yazma yok', [h.mst_shared_def_prompt(i1, 'Menfez ekleme'), sets.length], [:cancel, 0])
  t('K09 soru iletisi', $msgs.last.include?('tanımı 3 yerde kullanılıyor') && $msgs.last.include?('diğer 2 parça değişmez'), true)
  $ui_answer = IDYES
  t('K09 soru: Evet → :unique', h.mst_shared_def_prompt(i1, 'Menfez ekleme'), :unique)
  g1 = Sketchup::Group.new(30)
  t('K09 soru: Group → :not_shared', h.mst_shared_def_prompt(g1, 'x'), :not_shared)
  h.mst_make_unique_keep_data!(i1)
  nd = i1.definition
  t('K09 ayır: yeni tanım, diğer 2 parça eski tanımda', [nd != od, od.instances.length, od.instances.include?(i2)], [true, 2, true])
  t('K09 ayır: tanım verisi korundu (sahte make_unique kopyalamaz)', nd.get_attribute(D, 'pc_rebar_attrs_json'), '{"rebar_t":1}')
  t('K09 ayır: ortak tanım anahtarları yeni tanımda yok, kaynak anahtar kaydı', [nd.get_attribute(D, 'mst_def_kind'), nd.get_attribute(D, 'mst_def_key'), nd.get_attribute(D, 'mst_def_unique_of')], [nil, nil, 'KEY-1'])
  t('K09 ayır: örnek öznitelikleri ve element_uid örnekte', [i1.a('element_uid'), i1.a('id')], ['UID-21', 'PD-21'])
  t('K09 ayır: eski tanımın anahtarı değişmedi', od.get_attribute(D, 'mst_def_key'), 'KEY-1')

  # ---- K09 menfez: mst_cv_ui EKLE / TEMİZLE ve otomatik yeniden çizim
  class Host
    def mst_cv_bk_dims(_hb); [10.0, 1.2, 1.0]; end
    def mst_cv_plan(*_a); { 'void' => 0.18, 'steel_kg' => 10.0, 'form_deduct' => 0.3 }; end
    def mst_cv_draw!(hb, _s); $log << [:cv_draw, hb.definition]; end
    def mst_v50_after_bk_change!(_hb); end
    def mst_v50_num(v, _l); Float(v); end
  end
  a2_const(Host, bm, 'MST_CV_FIELDS')
  A1.load(Host, bm, 'def mst_cv_specs(', 'def mst_hb_culvert_groups(', 'def mst_cv_redraw!(', 'def mst_cv_ui')
  module UI
    def self.inputbox(*_a); $ib.shift; end
    def self.messagebox(m, _t = nil); $msgs << m.to_s; $mb.shift || IDYES; end
  end
  reset_pc!
  bd = Sketchup::ComponentDefinition.new(300, 'mst_def_kind' => 'head_beam', 'mst_def_key' => 'BK-KEY'); bd.entities = []
  hb1 = Sketchup::ComponentInstance.new(31, 'element_type' => 'head_beam', 'id' => 'BK-31', 'culverts_json' => '[]')
  hb2 = Sketchup::ComponentInstance.new(32, 'element_type' => 'head_beam', 'id' => 'BK-32', 'culverts_json' => '[]')
  hb1.definition = bd; hb2.definition = bd
  $model.selection = [hb1]
  $ib = [['EKLE'], %w[0.5 1.0 0 1.2 0.4 0.6 10 C]]; $mb = [IDYES, IDNO]
  r0 = h.mst_cv_ui
  t('K09 menfez EKLE: Hayır → iptal, işlem açılmaz, çizim yok', [r0, ops, $log.count { |x| x[0] == :cv_draw }], [0, [], 0])
  $ib = [['EKLE'], %w[0.5 1.0 0 1.2 0.4 0.6 10 C]]; $mb = [IDYES, IDYES]; $log = []
  r1 = h.mst_cv_ui; obs("son ileti", $msgs.last)
  seq = $log.map(&:first).select { |x| %i[start make_unique cv_draw commit abort].include?(x) }
  t('K09 menfez EKLE: soru işlemden önce; ayırma ve çizim aynı işlemde', [r1, seq], [1, %i[start make_unique cv_draw commit]])
  t('K09 menfez EKLE: çizim ayrılan tanıma, diğer BK tanımı değişmez', [$log.find { |x| x[0] == :cv_draw }[1] != bd, hb2.definition == bd, bd.instances.length], [true, true, 1])
  # TEMİZLE paylaşılan BK
  hb3 = Sketchup::ComponentInstance.new(33, 'element_type' => 'head_beam', 'id' => 'BK-33', 'culverts_json' => '[{"a0":1}]'); hb3.definition = bd
  $model.selection = [hb3]; $ib = [['TEMİZLE']]; $mb = [IDYES, IDYES]; $log = []
  h.mst_cv_ui
  t('K09 menfez TEMİZLE: ayırma işlem içinde', $log.map(&:first).select { |x| %i[start make_unique commit].include?(x) }, %i[start make_unique commit])
  # otomatik yol: paylaşılan Component BK'da menfez yeniden çizilmez
  hb4 = Sketchup::ComponentInstance.new(34, 'element_type' => 'head_beam', 'culverts_json' => '[{"a0":1}]'); hb5 = Sketchup::ComponentInstance.new(35, 'element_type' => 'head_beam')
  sd = Sketchup::ComponentDefinition.new(301); sd.entities = []; hb4.definition = sd; hb5.definition = sd; $log = []
  h.mst_cv_redraw!(hb4)
  t('K09 mst_cv_redraw!: paylaşılan tanımda çizim/silme yok, culvert_error', [$log.count { |x| %i[cv_draw erase].include?(x[0]) }, hb4.a('culvert_error').to_s.include?('2 yerde')], [0, true])
  hb6 = Sketchup::Group.new(36, 'element_type' => 'head_beam', 'culverts_json' => '[{"a0":1}]', 'culvert_error' => 'eski'); hb6.entities = []
  h.define_singleton_method(:mst_cv_draw!) { |_hb, _s| raise 'Menfez BK\'nın dışında.' }
  h.mst_cv_redraw!(hb6)
  t('K09 mst_cv_redraw!: çizim hatası sessiz yutulmaz → culvert_error', hb6.a('culvert_error').to_s.include?('1 menfez çizilemedi'), true)
end
a1_finish
