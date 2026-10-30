# Parti B / Undo: K11 (fazla commit), K12 (saydam islemde abort), K13 (rescue'suz islem), K15 (toplu prekast tek islem),
# K62 (komut basina tek Geri Al), K14 (dolgu kayitlari islem icinde, okuma yazmaz), S9 (otomatik kayit hatasi gorunur).
# Kullanim: ruby tools/test/b_undo.rb <src/marine_structures_tools>
require_relative 'b_helper'
require 'date'
main = A1.src('main.rb')
piles = A1.src('mst_v50_piles.rb')
sched = A1.src('mst_schedule.rb')
rt = A1.src('mst_rebar_tools.rb')
rl = A1.src('rockfill_live.rb')
pc = A1.src('mst_pc_rebar.rb')

module Sketchup
  def self.status_text=(_v); end
end
module UI
  def self.beep; end
end
class FakeModel
  def set_attribute(d, k, v); $log << [:mset, k, @open_ops]; super; end
  def select_tool(_t); end
end
class FakeSel < Array
  def add(x); self << x; end
  def to_a; Array.new(self); end
end
def outside_sets; $log.select { |x| x[0] == :mset && x[2].zero? }.map { |x| x[1] }; end

# ------------------------------------------------------------------ K11 + K29(2318): kalip yuzu araclari
module MarineStructuresTools
  DICT = A1::DICT
  extend self
  def mst_formwork_owner(_m); $owner; end
  def active_head_beam(_m); $owner; end
  def material_for(*_a); :mat; end
  def head_beam_formwork_area(_o); 10.0; end
  def head_beam_pile_opening_area(_o); 1.0; end
  def mst_marked_formwork_area(_e); 5.0; end
  def commit_with_dependencies(m); $log << [:cwd]; m.commit_operation; end
  def mst_formwork_label(_t); 'BK'; end
  def face_area_m2(_f); 1.0; end
  def bk_formwork_override_map(_hb, _c); {}; end
  def bk_store_formwork_override_map(_hb, map); $stored = map; end
  def bk_formwork_face_key(_f); 'BOTTOM'; end
  def bk_formwork_face_keys(_hb); { $face => ['BOTTOM@1/2', 'BOTTOM'] }; end
  def mst_hb_ents(hb); hb.is_a?(Sketchup::ComponentInstance) ? hb.definition.entities : hb.entities; end
end
Object.class_eval(A1.grab(main, 'class MSTUniversalFormworkFaceTool'))
Object.class_eval(A1.grab(main, 'class MSTBKFormworkFaceTool'))
class PH; def do_pick(*_a); end; def count; 1; end; def leaf_at(_i); $face; end; end
class View; def pick_helper; PH.new; end; def invalidate; end; def tooltip=(_v); end; end

a1_reset!
$face = FakeFace.new(1, 'BOTTOM', [0, 0, -1], [0, 0, 0], 2.0)
$owner = Sketchup::Group.new(2, 'element_type' => 'deck_slab'); $owner.entities = [$face]
MSTUniversalFormworkFaceTool.new.onLButtonDown(0, 0, 0, View.new)
t('K11 Evrensel Kalıp: tek start + tek commit (commit_with_dependencies)', ops, [:start, :commit])
a1_reset!
$owner = Sketchup::Group.new(3, 'element_type' => 'head_beam'); $owner.entities = [$face]
MSTBKFormworkFaceTool.new.onLButtonDown(0, 0, 0, View.new)
t('K11 BK Kalıp Yüzeyi aracı (kopya satır): tek commit', ops, [:start, :commit])
a1_reset!
d1 = Sketchup::ComponentDefinition.new(50); d1.entities = [$face]
$owner = Sketchup::ComponentInstance.new(4, 'element_type' => 'head_beam'); $owner.definition = d1
MSTBKFormworkFaceTool.new.onLButtonDown(0, 0, 0, View.new)
t('K29 BK aracı, tek örnekli Component BK: hata yok, tek işlem', [ops, $msgs.none? { |m| m.include?('hatası') }], [[:start, :commit], true])
a1_reset!
$owner2 = Sketchup::ComponentInstance.new(5, 'element_type' => 'head_beam'); $owner2.definition = d1
MSTBKFormworkFaceTool.new.onLButtonDown(0, 0, 0, View.new)
t('K29 BK aracı, çok kopyalı Component BK: paylaşılan tanıma yazılmaz, işlem açılmaz', [ops, $face.a('formwork_manual_override'), $msgs.last.to_s.include?('ortak tanım')], [[], 'include', true])

# ------------------------------------------------------------------ K12: saydam islemde hata
class Host
  def mst_kd_apply_grid!(*_a); $log << [:grid]; raise 'ızgara hatası'; end
end
snip = b_slice(piles, ' if use_ax && made>0', "\n made\nrescue")
Host.class_eval("def k12_run(model,ax,tg,use_ax,made)\n#{snip}\nend")
a1_reset!
Host.new.k12_run($model, {}, {}, true, 3)
t('K12 aks ızgarası hatası: saydam işlem abort edilmez, commit ile kapanır', ops, [:start, :commit])
t('K12 hata kullanıcıya bildirilir', $msgs.last.to_s.include?('aks ızgarası kurulamadı'), true)
t('K12 (statik) döşeme otomatik güncelleme saydam işleminde abort yok', b_slice(main, "model.start_operation('MST Döşeme Güncelle',true,false,true)", "\n unless quiet").include?('model.abort_operation'), false)

# ------------------------------------------------------------------ K13
class FakeDicts; def [](_k); true; end; def delete(_k); $log << [:dict_delete]; end; end
class Host
  def commit_with_dependencies(m); raise 'bağımlılık hatası' if $cwd_raise; $log << [:cwd]; m.commit_operation; end
  def qto_summary(*_a); end
  def material_for(*_a); :mat; end
  def head_beam_formwork_area(_h); raise 'alan hatası'; end
  def head_beam_pile_opening_area(_h); 0.0; end
  def active_head_beam(_m); $hb; end
end
A1.load(Host, main, 'def unregister_selected_element', 'def set_selected_faces_formwork(')
a1_reset!; $cwd_raise = true
e = FakeEnt.new(7, 'element_type' => 'head_beam'); def e.attribute_dictionaries; FakeDicts.new; end
$model.selection = FakeSel.new([e])
begin; Host.new.unregister_selected_element; rescue => ex; obs('unregister istisnası', ex.message); end
t('K13 tanım kaldırma hatası: açık işlem kalmaz', [ops, $model.open_ops], [[:start, :abort], 0])
a1_reset!; $cwd_raise = false
$hb = Sketchup::Group.new(8, 'element_type' => 'head_beam')
$model.selection = FakeSel.new([FakeFace.new(9, 'LONG_SIDE', [0, 1, 0], [0, 0, 0], 1.0)])
begin; Host.new.set_selected_faces_formwork(true); rescue => ex; obs('kalıp yüzü istisnası', ex.message); end
t('K13 kalıp yüzü hatası: açık işlem kalmaz', [ops, $model.open_ops], [[:start, :abort], 0])
class Host
  MST_SP_RATES = [['a', 'A', 1, 'kaynak']].freeze
  def mst_sp_params(_m = nil); { 'a' => 1.0, 'start' => '2026-01-01', 'reverse' => 0.0 }; end
end
A1.load(Host, sched, 'def mst_sp_settings_ui')
a1_reset!
def $model.set_attribute(*_a); $log << [:mset_fail]; raise 'yazılamadı'; end
$ib_queue = [['2', '2026-02-01', '0']]
Host.new.mst_sp_settings_ui
t('K13 iş programı ayarı yazım hatası: açık işlem kalmaz', [ops, $model.open_ops], [[:start, :abort], 0])

# ------------------------------------------------------------------ K15: toplu prekast
GATED = main.include?("start_operation('Prekast Yerleşimi - Çoklu Tip',true) unless @precast_batch_mode")
class Host
  def selected_head_beams; Sketchup.active_model.selection.to_a; end
  def commit_with_dependencies(m); $log << [:cwd]; m.commit_operation; end
end
A1.load(Host, main, 'def create_flat_precast(')
class Host
  alias_method :cfp_real, :create_flat_precast
  def create_flat_precast(d = nil)
    return cfp_real(d) if selected_head_beams.length > 2
    own = !(GATED && @precast_batch_mode)   # aralik islevi: yuklenen surumdeki islem kuralina gore
    $model.start_operation('aralık') if own
    r = $inner.shift
    (r ? $model.commit_operation : $model.abort_operation) if own
    r
  end
end
mk_bk = ->(pid, x) { b = Sketchup::Group.new(pid, 'element_type' => 'head_beam'); b.bounds = FakeBounds.new([x * INCH, 0, 0], [(x + 1) * INCH, 10 * INCH, 1]); b }
a1_reset!; $model.selection = FakeSel.new([mk_bk.(11, 0), mk_bk.(12, 10), mk_bk.(13, 20), mk_bk.(14, 30)]); $inner = [true, true, true]
Host.new.create_flat_precast({})
t('K15 toplu prekast (3 aralık) başarı: tek işlem (tek Geri Al)', ops, [:start, :commit])
a1_reset!; $model.selection = FakeSel.new([mk_bk.(11, 0), mk_bk.(12, 10), mk_bk.(13, 20), mk_bk.(14, 30)]); $inner = [true, false]
Host.new.create_flat_precast({})
t('K15 toplu prekast 2. aralıkta durdu: yarım yerleşim kalmaz (tek abort)', [ops, $msgs.last.to_s.include?('geri alındı')], [[:start, :abort], true])

# ------------------------------------------------------------------ K62
class Host
  def collect_elements(ents, out); out.concat(ents.to_a); end
  def mst_rt_sets(_x); [1]; end
  def mst_rt_clashes(_es); i = FakeEnt.new(99); [{ a: 'A', b: 'B', bar_a: { inst: i }, bar_b: { inst: i } }]; end
  def mst_rt_visible?(_m = nil); false; end
  def mst_rt_set_visible!(_on, _m = nil); $log << [:visible]; 1; end
end
A1.load(Host, rt, 'def mst_rt_clash_ui')
a1_reset!; $model.entities = [FakeEnt.new(1), FakeEnt.new(2)]
Host.new.mst_rt_clash_ui
seq = $log.map(&:first).select { |x| %i[start commit visible].include?(x) }
t('K62 çakışma boyama: donatı görünürlüğü aynı işlemde (tek Geri Al)', seq, %i[start visible commit])
mat = b_slice(rl, "when 'material'", "when 'type','type_update'")
t('K62 (statik) Tip Kesite Malzeme Ata: durum kaydı commit\'ten önce, ikinci işlem (rf_live_store) yok',
  [mat.index('RF_LIVE_KEY') && mat.index('RF_LIVE_KEY') < mat.index('model.commit_operation'), mat.include?('rf_live_store')], [true, false])
act = b_slice(rl, "if action=='activate'", 'rf_live_send(dialog,state,')
t('K62 (statik) Canlı QTO Kaynağı: durum + kaynak tek işlemde', [act.scan('start_operation').length, act.index('RF_LIVE_KEY').to_i < act.index('ROCKFILL_SOURCE_KEY').to_i, act.index('rf_live_store').to_i > act.index('else').to_i], [1, true, true])
pcs = b_slice(pc, " p=mst_pc_params(fam,vals)", "send_boq(@d)")
t('K62 (statik) Prekast Donatısı: mst_pc_last_* işlem içinde', pcs.index("start_operation('MST Prekast Donatısı'") < pcs.index('"mst_pc_last_#{fam}"'), true)

# ------------------------------------------------------------------ K14 + S9 dolgu
class Host
  ROCKFILL_LIBRARY_KEY = 'rockfill_material_library_json'.freeze
  ROCKFILL_PROJECT_KEY = 'rockfill_section_chain_json'.freeze
  ROCKFILL_PROJECT_KEY_ALT2 = 'rockfill_section_chain_alt02_json'.freeze
  ROCKFILL_ACTIVE_ALT_KEY = 'rockfill_active_alternative'.freeze
end
A1.load(Host, main, 'def rockfill_project_key(', 'def rockfill_save_library(', 'def rockfill_autosave_library(', 'def rockfill_autosave_project(',
        'def rockfill_load_project(')
A1.load_opt(Host, main, 'def mst_json_attr_bad?('); A1.load_opt(Host, main, 'def mst_json_attr_guard!(')   # A1 (0.51.4'te yok)
A1.load_opt(Host, main, 'def mst_rf_write!('); A1.load_opt(Host, main, 'def mst_rf_autosave_warn(')
class Dlg; def execute_script(s); $script = s; end; end
h = Host.new
a1_reset!
h.rockfill_load_project(Dlg.new)
t('K14 kesit zinciri yükleme (salt okuma): yazma ve işlem yok', [ops, outside_sets], [[], []])
a1_reset!
h.rockfill_load_project(Dlg.new, '02')
t('K14 başka alternatif seçimi: yazma işlem içinde', [ops, outside_sets], [[:start, :commit], []])
a1_reset!
js = JSON.generate('alternative' => '01', 'sections' => [{ 'station' => 0 }, { 'station' => 10 }])
h.rockfill_autosave_project(js)
t('K14 otomatik kayıt (kesit): iki yazma tek işlemde', [ops, outside_sets], [[:start, :commit], []])
$log = []
h.rockfill_autosave_project(js)
t('K14 değişmeyen otomatik kayıt: işlem açılmaz', ops, [])
a1_reset!
h.rockfill_save_library('[{"code":"A","name":"B","density":1.8}]', Dlg.new)
t('K14 kütüphane kaydı işlem içinde', [ops, outside_sets], [[:start, :commit], []])
a1_reset!
$model.set_attribute(A1::DICT, 'rockfill_material_library_json', '[bozuk'); $log = []; $msgs = []
2.times { h.rockfill_autosave_library('[{"code":"A","name":"B","density":1.8}]') }
t('S9 otomatik kayıt hatası kullanıcıya bir kez gösterilir (puts yerine)', $msgs.count { |m| m.include?('otomatik kaydı yapılamadı') }, 1)
t('S9 bozuk kütüphane yine ezilmez (A1 K20 korunur)', $model.a('rockfill_material_library_json'), '[bozuk')
a1_finish
