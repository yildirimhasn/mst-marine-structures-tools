# A2 / K57 ("Donatıyı Sil" yalniz BK cizimden/otomatik) ve K63 (onceki BIM donatisi yalniz geri kurulursa silinir).
# Kullanim: ruby tools/test/a2_k57_k63_dwg.rb <src/marine_structures_tools>
require_relative 'a2_helper'
dw = A1.src('mst_dwg_rebar.rb')
class Host
  MST_DR_MODE = 'drawing_detail'.freeze
  def mst_dr_clear!(x); $cleared << x; true; end
  def send_boq(*_a); end
  def collect_elements(_ents, out); out.concat($all); end
end
A1.load(Host, dw, 'def mst_dr_remove_ui')
h = Host.new
D = A1::DICT
a1_reset!
$model.selection = []
$model.entities = []
bk_dr = Sketchup::Group.new(1, 'element_type' => 'head_beam', 'id' => 'BK-1', 'rebar_mode' => 'drawing_detail', 'rebar_kind' => 'DRAWING')
bk_auto = Sketchup::Group.new(2, 'element_type' => 'head_beam', 'id' => 'BK-2', 'rebar_mode' => 'auto_detail', 'rebar_kind' => 'AUTO')
bk_pafta = Sketchup::Group.new(3, 'element_type' => 'head_beam', 'id' => 'BK-3', 'rebar_mode' => 'drawing_detail', 'rebar_kind' => 'PAFTA', 'rebar_pafta_json' => '{"x":1}')
pc = Sketchup::ComponentInstance.new(4, 'element_type' => 'flat_precast', 'id' => 'PD-1', 'rebar_mode' => 'auto_detail', 'rebar_kind' => 'PREKAST-PD')
$all = [bk_dr, bk_auto, bk_pafta, pc]
$cleared = []
n = h.mst_dr_remove_ui
obs('K57 silinen', $cleared.map { |x| x.a('id') })
obs('K57 onay iletisi', $msgs.last)
t('K57: yalnız BK çizimden/otomatik silinir (0.51.4: 4 eleman, pafta ve prekast dahil)', [n, $cleared.map { |x| x.a('id') }], [2, %w[BK-1 BK-2]])
t('K57: iletide dışarıda kalanlar bildirilir', $msgs.last.to_s.include?('Paftadan metrajı olan 2 BK ve prekast donatısı bu işlemle silinmez'), true)
t('K57: tek işlem (start/commit)', ops, [:start, :commit])
a1_reset!; $model.selection = [bk_pafta, pc]; $cleared = []
h.mst_dr_remove_ui
t('K57: seçim yalnız pafta + prekast → hiçbir şey silinmez, işlem açılmaz', [$cleared.length, ops], [0, []])

# ---- K63
class Host
  def mst_rt_history_push!(_e); end
  def mst_dr_set_of(_e); []; end
  def mst_dr_erase_set!(_g); end
  def qto3_quantity(_e, _k); 10.0; end
  def rebar_rate(_k); 150.0; end
  def mst_dr_purge_defs!(_m); end
  def mst_hb_rebar_unsupported_reason(_e); nil; end
  def mst_hb_rebar_build!(e, _p); raise 'kurulum hatası (sahte)' if $build_fail; e.set_attribute(DICT, 'rebar_mode', 'bim_detail'); e.set_attribute(DICT, 'rebar_t', 1.7); end
  def mst_hb_rebar_clear!(e); e.delete_attribute(DICT, 'hb_rebar_json'); e.set_attribute(DICT, 'rebar_t', 1.5); end
end
A1.load(Host, dw, 'def mst_dr_clear!(')
prev = JSON.generate('mode' => 'bim_detail', 'hb' => '{"bars":1}')
def bk_with_prev(prev, kind = Sketchup::Group)
  kind.new(10, 'element_type' => 'head_beam', 'id' => 'BK-9', 'rebar_mode' => 'drawing_detail', 'rebar_t' => 2.0, 'rebar_prev_json' => prev)
end
a1_reset!; $build_fail = true
e = bk_with_prev(prev)
h.mst_dr_clear!(e)
obs('K63 hata sonrası rebar_prev_json / rebar_restore_error / rebar_t', [e.a('rebar_prev_json'), e.a('rebar_restore_error'), e.a('rebar_t')])
t('K63: kurulum hatasında önceki BIM kaydı korunur (0.51.4: silinir)', e.a('rebar_prev_json'), prev)
t('K63: rebar_restore_error yazılır', e.a('rebar_restore_error').to_s.include?('kurulum hatası'), true)
t('K63: donatı pursantajda (10 m³ × 150 = 1.5 t)', e.a('rebar_t'), 1.5)
$build_fail = false
e2 = bk_with_prev(prev)
h.mst_dr_clear!(e2)
t('K63: başarılı kurulumda kayıt ve hata silinir, BIM tonajı', [e2.a('rebar_prev_json'), e2.a('rebar_restore_error'), e2.a('rebar_t')], [nil, nil, 1.7])
e3 = bk_with_prev(prev, Sketchup::ComponentInstance); $log = []
h.mst_dr_clear!(e3)
t('K63: Component BK kurmaya girilmez, kayıt korunur + hata', [e3.a('rebar_prev_json'), e3.a('rebar_restore_error').to_s.include?('Component')], [prev, true])
e4 = bk_with_prev(JSON.generate('mode' => '', 'hb' => ''))
h.mst_dr_clear!(e4)
t('K63: geri yüklenecek BIM donatısı yoksa kayıt silinir (eski davranış)', [e4.a('rebar_prev_json'), e4.a('rebar_restore_error')], [nil, nil])
e5 = bk_with_prev('{bozuk')
h.mst_dr_clear!(e5)
t('K63: bozuk önceki kayıt silinmez + hata', [e5.a('rebar_prev_json'), !e5.a('rebar_restore_error').nil?], ['{bozuk', true])
a1_finish
