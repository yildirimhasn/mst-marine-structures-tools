# Parti B / K07 (kaplama toplanmiyor, bagimlilik bagi yok, BK tasinirken kaplama kalir), K53 (doseme yenilemesi kaplamayi
# eski degere dondurur; parent_deck_revision_no uyarisi), K52 (kaplama durumu kayitli olmayan eski doseme uyarisi) — ADR-0515 §9.
# Kullanim: ruby tools/test/b_k07_k53_topping.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
dep = A1.src('dependency_rebuild.rb')
D = A1::DICT
COLLECTED = %w[steel_pipe_pile head_beam pile_infill_concrete flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile].freeze
class FakeEnts < Array; def clear!; clear; end; end
class Host
  # collect_elements gibi: yalniz MST_COLLECTED_TYPES (kaplama yok), tipsiz gruplara iner
  def collect_elements(ents, out)
    ents.each do |e|
      t = e.get_attribute(DICT, 'element_type', '').to_s
      out << e if COLLECTED.include?(t)
      collect_elements(e.entities || [], out) if t.empty? && e.is_a?(Sketchup::Group)
    end
    out
  end
  def mst_pile_ids_for_beam(_b); []; end
  def element_visible_id(e); e.get_attribute(DICT, 'deck_id', e.get_attribute(DICT, 'id', "PID-#{e.persistent_id}")).to_s; end
end
A1.load(Host, dep, 'def dependency_graph(')
NEWG = %w[mst_uid_owner mst_collect_toppings mst_topping_parent_deck].map { |f| A1.load_opt(Host, dep, "def #{f}(") }.all?
A1.load(Host, main, 'def mst_bk_dependents(', 'def mst_bk_beam_ancestors(')
obs('mst_collect_toppings / mst_topping_parent_deck tanımlı', NEWG)
h = Host.new

# ------------------------------------------------------------------ K07
a1_reset!
b1 = Sketchup::Group.new(1, 'element_type' => 'head_beam', 'id' => 'BK-1'); b1.entities = []
b2 = Sketchup::Group.new(2, 'element_type' => 'head_beam', 'id' => 'BK-2')
tin = Sketchup::Group.new(3, 'element_type' => 'deck_topping', 'parent_deck_id' => 'D-001'); b2.entities = [tin]   # MST elemanin icinde: taranmaz
dk = Sketchup::Group.new(10, 'element_type' => 'deck_slab', 'deck_id' => 'D-001', 'element_uid' => 'MST-10-1', 'uid_owner_pid' => 10, 'support_pids' => '1,2'); dk.entities = []
tp = Sketchup::Group.new(20, 'element_type' => 'deck_topping', 'parent_uid' => 'MST-10-1', 'parent_deck_id' => 'D-001', 'element_uid' => 'MST-20-1')
org = Sketchup::Group.new(30, {}); org.entities = [tp]   # tipsiz duzen grubu icinde
$model.entities = [b1, b2, dk, org]
t('K07 mst_collect_toppings: tipsiz grup içindeki kaplama bulunur, MST elemanı içine inilmez', NEWG ? h.mst_collect_toppings($model.entities) : nil, [tp])
_all, ch, par, = h.dependency_graph($model)
t('K07 dependency_graph: kaplama döşemenin çocuğu (parent_uid)', [ch[dk].include?(tp), par[tp]], [true, [dk]])
t('K07 mst_bk_dependents: BK taşınınca kaplama döşemeyle birlikte (aynı öteleme kuralı)', h.mst_bk_dependents(b1, ch).include?(tp), true)
t('K07 kaplamanın BK ataları = döşemenin BK\'ları (aynı Δ kuralı uygulanır)', h.mst_bk_beam_ancestors(tp, par).map(&:persistent_id).sort, [1, 2])
dc = Sketchup::Group.new(11, 'element_type' => 'deck_slab', 'deck_id' => 'D-001', 'element_uid' => 'MST-10-1', 'uid_owner_pid' => 10, 'support_pids' => '1,2')
$model.entities = [b1, b2, dk, dc, org]
_all, ch, = h.dependency_graph($model)
t('K07 kopya döşeme (aynı UID): kaplama kayıtlı sahip döşemeye bağlı', [ch[dk].include?(tp), ch[dc].include?(tp)], [true, false])
tp2 = Sketchup::Group.new(21, 'element_type' => 'deck_topping', 'parent_deck_id' => 'D-001')
$model.entities = [b1, b2, dk, tp2]
_all, ch, = h.dependency_graph($model)
t('K07 parent_uid yoksa parent_deck_id tek eşleşmeyle bağlanır', ch[dk].include?(tp2), true)
$model.entities = [b1, b2, dk, dc, tp2]
_all, ch, = h.dependency_graph($model)
t('K07 parent_deck_id iki döşemeye uyuyorsa bağ kurulmaz (tahmin yok)', ch[dk].include?(tp2) || ch[dc].include?(tp2), false)
t('K07 (statik) mükerrer kaplama kontrolü ayrı toplayıcıyla (önceden collect_elements kaplama vermediği için hiç eşleşmiyordu)',
  b_slice(main, 'def create_existing_deck_topping', 'faces=[]').include?('mst_collect_toppings(model.entities)'), true)
mv = b_slice(main, 'def mst_apply_axis_move_plans', "\n# Original grid")
t('K07 (statik) taşıma yalnız öteleme (kaplama yeniden kurulmaz)', mv.include?("(pl['deps']||[]).each do |dp|") && mv.include?('e.transform!(Geom::Transformation.translation([m(dp[\'dx\']),m(dp[\'dy\']),0]))'), true)
t('K07 (statik) deck_topping hiçbir yeniden kurma dağıtımında yok', main.scan(/when 'deck_topping'/).length == main.scan(/when 'deck_topping' then 'TOPPING'/).length &&
  !b_slice(main, 'def mst_deck_after_edit', "\n# 🔄").include?('deck_topping'), true)

# ------------------------------------------------------------------ K53 mst_deck_regenerate!
class Host
  def mst_deck_support_beams(_d, _m = nil); [1, 2]; end
  def mst_deck_inputs(*_a); [0, 0, [], [], []]; end
  def mst_deck_plan(*_a); { 'errors' => [], 'volume' => 10.0, 'topping_area' => 50.0, 'warnings' => [], 'boxes' => [] }; end
  def mst_deck_fill!(parent, _m, _h, data, pl, _i); fill_topping(parent, data, pl); end
end
A1.load(Host, main, 'def mst_deck_regenerate!(', 'def mst_deck_input_data(', 'def topping_quantities(')
# mst_deck_fill! icindeki gercek kaplama satirlari (kaynak metinden)
Host.class_eval("def fill_topping(parent,data,pl)\n#{b_slice(main, " topping_on=data['topping_enabled'].to_s=='1'", " curbs\nend")}\nend")
a1_reset!
inp = { 'deck_id' => 'D-001', 'thickness_m' => '0.30', 'topping_enabled' => '0', 'topping_thickness_m' => '0.10', 'topping_concrete_class' => '' }
deck = Sketchup::Group.new(40, 'element_type' => 'deck_slab', 'deck_id' => 'D-001', 'deck_input_json' => JSON.generate(inp), 'deck_revision_no' => 1,
                           # Kaplama Ekle + Kaplama Eğimi sonrasi dosemenin guncel kaplama durumu
                           'topping_enabled' => '1', 'topping_thickness_m' => 0.12, 'topping_concrete_class' => 'C30/37', 'topping_area_m2' => 48.0, 'topping_volume_m3' => 5.76)
deck.entities = FakeEnts.new
obs('K53 yenileme öncesi kaplama (alan, kalınlık, hacim)', h.topping_quantities([deck]).map { |v| v.round(3) })
h.mst_deck_regenerate!(deck, $model)
after = h.topping_quantities([deck]).map { |v| v.round(3) }
obs('K53 yenileme sonrası kaplama (alan, kalınlık × alan)', after)
t('K53 yenileme kaplamayı kapatmaz; kalınlık / sınıf korunur', [deck.a('topping_enabled'), deck.a('topping_thickness_m'), deck.a('topping_concrete_class')], ['1', 0.12, 'C30/37'])
t('K53 kaplama metrajı: 0.51.4 = 0 m³ → yeni = 50 m² × 0.12 m = 6.0 m³ (plan alanı)', after, [50.0, 6.0])
t('K53 deck_input_json güncel kaplama durumunu yansıtır', JSON.parse(deck.a('deck_input_json')).values_at('topping_enabled', 'topping_thickness_m'), ['1', '0.12'])
deck2 = Sketchup::Group.new(41, 'element_type' => 'deck_slab', 'deck_id' => 'D-002', 'deck_input_json' => JSON.generate(inp.merge('topping_enabled' => '1', 'topping_thickness_m' => '0.15')))
deck2.entities = FakeEnts.new
h.mst_deck_regenerate!(deck2, $model)
t('K53 öznitelikte kaplama alanı yoksa oluşturma girdisi kullanılır (eski davranış)', [deck2.a('topping_enabled'), deck2.a('topping_thickness_m')], ['1', 0.15])
t('K53 (statik) kaplama oluşturmada parent_deck_revision_no yazılır', b_slice(main, 'def create_existing_deck_topping', 'mst_assign_tag(g,model)').include?("'parent_deck_revision_no'"), true)

# ------------------------------------------------------------------ K53 / K52 Model Kontrolü
class Host
  def mst_boq_info_rows(_a = nil); []; end
  def mst_bk_pile_embed(_b); { items: [] }; end
  def pile_bim_qto_item(_p); {}; end
  def mst_pile_rebar_active(_e); false; end
end
NEWA = A1.load_opt(Host, main, 'def mst_audit_v0515(')
if NEWA
  a2_const(Host, main, 'MST_AUDIT_ERROR_FLAGS')
  %w[mst_tr_scale_info mst_bk_span_frame_error mst_pv_tooth_seat_warnings mst_attr_hash].each { |f| A1.load_opt(Host, main, "def #{f}(") }
  A1.load_opt(Host, A1.src('mst_rebar_tools.rb'), 'def mst_rt_world_tr(')
  A1.load_opt(Host, A1.src('mst_v50_beams.rb'), 'def mst_vk_support_state(')
end
a1_reset!
dk3 = Sketchup::Group.new(50, 'element_type' => 'deck_slab', 'deck_id' => 'D-003', 'element_uid' => 'MST-50-1', 'deck_revision_no' => 2, 'topping_enabled' => '1')
t_old = Sketchup::Group.new(51, 'element_type' => 'deck_topping', 'parent_uid' => 'MST-50-1', 'parent_deck_revision_no' => 1)
t_ok = Sketchup::Group.new(52, 'element_type' => 'deck_topping', 'parent_uid' => 'MST-50-1', 'parent_deck_revision_no' => 2)
t_leg = Sketchup::Group.new(53, 'element_type' => 'deck_topping', 'parent_uid' => 'MST-50-1')
dk4 = Sketchup::Group.new(54, 'element_type' => 'deck_slab', 'deck_id' => 'D-004')   # topping_enabled anahtari yok
$model.entities = [dk3, t_old, t_ok, t_leg, dk4]
out = NEWA ? h.mst_audit_v0515([dk3, dk4], [dk3, dk4]) : []
out.each { |x| obs('Model Kontrolü', [x[0], x[2], x[3][0, 110]]) }
t('K53 Model Kontrolü: döşeme RV-02, kaplama RV-01 → UYARI (yalnız eski kaplama; anahtarsız eski kaplamada yok)',
  out.select { |x| x[3].include?('kaplaması döşeme') }.map { |x| x[1].persistent_id }, [51])
t('K52 Model Kontrolü: kaplama durumu kayıtlı olmayan döşeme → UYARI (BOQ değişmez)', out.select { |x| x[3].include?('kaplama durumu kayıtlı değil') }.map { |x| x[1].persistent_id }, [54])
a1_finish
