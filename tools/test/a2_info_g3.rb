# A2 / K33 (poz eslenmemis beton), K39 (tapa), K40 (yerlestirilemeyen donati pozlari) bilgi satirlari ve
# G3 Model Kontrolu (mst_audit_v0515: hata bayraklari, K50 sinir uyarisi) — ADR-0515 §11.
# Kullanim: ruby tools/test/a2_info_g3.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')
class Host
  REBAR_DEFAULTS = { 'pile' => 250.0 }.freeze
  PILE_BOQ_GROUP_KEYS = %w[PILE_STEEL].freeze
  def collect_elements(_e, out); out.concat($all); end
  def qto3_quantity(e, _k); e.get_attribute(DICT, 'concrete_volume_m3', 0).to_f; end
  def pile_fabrication_qto_row(ps, _l, _r = false); return nil if ps.empty?; r = Array.new(16, 0.0); r[4] = 2; r[8] = 0.1375; r; end
  def boq_rows; $rows.map(&:dup); end
  def boq_trace_payload(_s); { items: [], count: 0 }; end
  def rebar_rate(_k); 250.0; end
  def bored_pile_boq_rebar_rate; nil; end
  def qto3_snapshot; { scopes: { projects: ['P'] } }; end
  def pile_boq_mode(_k); 'combined'; end
  def mst_rebar_source_summary; []; end
  def mst_pile_rebar_active(e); e.get_attribute(DICT, 'pile_rebar_mode', '') == 'bim_detail'; end
  def mst_bk_pile_embed(_b); { volume_m3: 1.0, items: $embed_items }; end
end
class Dlg; def execute_script(s); $script = s; end; end
A1.load(Host, main, 'def qto_material_class(', 'def send_boq(', 'def mst_attr_hash(')
NEW = A1.load_opt(Host, main, 'def mst_boq_info_rows(') & A1.load_opt(Host, main, 'def mst_audit_v0515(')
A1.load(Host, bm, 'def mst_hb_zones_list('); A1.load_opt(Host, bm, 'def mst_hb_zone_segments('); A1.load_opt(Host, bm, 'def mst_hb_bottom_depth(')
a2_const(Host, main, 'MST_AUDIT_ERROR_FLAGS') if NEW
# Parti B düzeneği: mst_audit_v0515'e eklenen K22/K23/K10/K53/K54/K21 denetimlerinin çağırdığı yardımcılar (bu testteki öğelerde uyarı üretmezler)
%w[mst_tr_scale_info mst_bk_span_frame_error mst_pv_tooth_seat_warnings].each { |f| A1.load_opt(Host, main, "def #{f}(") }
A1.load_opt(Host, A1.src('mst_rebar_tools.rb'), 'def mst_rt_world_tr(')
%w[mst_collect_toppings mst_topping_parent_deck mst_uid_owner].each { |f| A1.load_opt(Host, A1.src('dependency_rebuild.rb'), "def #{f}(") }
A1.load_opt(Host, bm, 'def mst_vk_support_state(')
class Host; def pile_bim_qto_item(_p); {}; end; end
obs('bilgi satırı / G3 işlevleri tanımlı', NEW)
h = Host.new
D = A1::DICT
a1_reset!
pd1 = Sketchup::Group.new(1, 'element_type' => 'flat_precast', 'concrete_class' => 'C30/37', 'concrete_volume_m3' => 10.0)
pd2 = Sketchup::Group.new(2, 'element_type' => 'flat_precast', 'concrete_class' => 'C35/45', 'concrete_volume_m3' => 4.0)
pd3 = Sketchup::Group.new(3, 'element_type' => 'channel_precast', 'concrete_class' => '', 'concrete_volume_m3' => 1.419)
cb = Sketchup::Group.new(4, 'element_type' => 'curb', 'concrete_class' => 'C30/37', 'concrete_volume_m3' => 2.0)
pile = Sketchup::Group.new(5, 'element_type' => 'steel_pipe_pile', 'plug_enabled' => '1')
bk = Sketchup::Group.new(6, 'element_type' => 'head_beam', 'rebar_mode' => 'drawing_detail', 'rebar_kind' => 'DRAWING',
                         'rebar_schedule_json' => JSON.generate('Poz 1 Ø25' => { 'count' => 10, 'kg' => 400.0, 'drawn' => 10 },
                                                                'Poz 7 Ø16' => { 'count' => 4, 'kg' => 60.5, 'drawn' => 0 }))
$all = [pd1, pd2, pd3, cb, pile, bk]
$rows = [{ code: 'ÖBF-001', name: 'Beton C35/45', unit: 'm³', quantity: 4.0, unit_price: 100.0, total: 400.0, source: 'PRECAST_C35_45', status: 'MODEL' },
         { code: 'ÖBF-002', name: 'Montaj', unit: 'm³', quantity: 15.419, unit_price: nil, total: nil, source: 'PRECAST_INSTALL', status: 'FİYAT EKSİK' }]
if NEW
  info = h.mst_boq_info_rows($all)
  info.each { |r| obs('bilgi satırı', [r[:name], r[:quantity].round(4), r[:unit]]) }
  q33 = info.select { |r| r[:source].start_with?('INFO:UNMAPPED_CONCRETE') }.map { |r| [r[:source], r[:quantity].round(3)] }
  t('K33: C35/45 dışı prekast 10 m³ (C30/37), sınıfsız 1.419 m³, bordür 2 m³; C35/45 hariç', q33,
    [['INFO:UNMAPPED_CONCRETE#Prekast#C30/37', 10.0], ['INFO:UNMAPPED_CONCRETE#Prekast#belirtilmemiş', 1.419], ['INFO:UNMAPPED_CONCRETE#Bordür#C30/37', 2.0]])
  t('K39: tapa 2 adet, 137.5 kg pozsuz bilgi', info.find { |r| r[:source] == 'INFO:PILE_PLUG' }.values_at(:quantity, :unit), [137.5, 'kg'])
  t('K40: yerleştirilemeyen 1 poz 60.5 kg = 0.0605 t (REBAR\'a dahil notu)', [info.find { |r| r[:source] == 'INFO:REBAR_UNPLACED' }[:quantity].round(4),
                                                                              info.find { |r| r[:source] == 'INFO:REBAR_UNPLACED' }[:mapping_reason].include?('DAHİL')], [0.0605, true])
  t('bilgi satırları: fiyat yok, tutar yok, kütüphane bayrağı (fiyat girişi açılmaz)', info.all? { |r| r[:unit_price].nil? && r[:total].nil? && r[:library_price] && r[:info_only] }, true)
  h.send_boq(Dlg.new)
  data = JSON.parse($script[/setBOQ\((.*)\);\z/m, 1])
  t('send_boq: toplam ve eksik fiyat sayısı yalnız gerçek satırlardan (400 / 1)', [data['total'], data['missing_prices']], [400.0, 1])
  t('send_boq: gerçek satırlar önce, bilgi satırları sonda', [data['rows'].length, data['rows'][0]['code'], data['rows'][2]['code'], data['info_rows'].length], [2 + info.length, 'ÖBF-001', 'BİLGİ', info.length])
  t('boq_rows değişmez (hakediş / iş programı / Excel kaynağı)', h.boq_rows.length, 2)

  # ---- G3
  pile_err = Sketchup::Group.new(10, 'element_type' => 'steel_pipe_pile', 'pile_rebar_mode' => 'bim_detail', 'pile_rebar_error' => 'sığmıyor')
  pile_err2 = Sketchup::Group.new(11, 'element_type' => 'steel_pipe_pile', 'pile_rebar_error' => 'eski')   # kafes etkin değil → uyarı yok
  pc_err = Sketchup::Group.new(12, 'element_type' => 'flat_precast', 'pc_rebar_error' => 'çizim hatası')
  bk_err = Sketchup::Group.new(13, 'element_type' => 'head_beam', 'rebar_restore_error' => 'Önceki BIM donatısı geri yüklenemedi: x', 'culvert_error' => '1 menfez çizilemedi',
                               'length_m' => 10.0, 'end_tooth_enabled' => '1', 'end_tooth_length_m' => 1.5, 'end_tooth_slope_m' => 0.3, 'end_tooth_depth_m' => 0.5)
  $embed_items = [{ pile_id: 'P-1', pid: 21, diameter_mm: 1016.0, axis_a_m: 8.7 }, { pile_id: 'P-2', pid: 22, diameter_mm: 1016.0, axis_a_m: 5.0 }]
  els = [pile_err, pile_err2, pc_err, bk_err]
  out = h.mst_audit_v0515(els, [])
  out.each { |x| obs('Model Kontrolü', [x[0], x[2], x[3]]) }
  checks = out.map { |x| [x[0], x[2], x[1] && x[1].persistent_id] }
  t('G3: pile_rebar_error HATA (yalnız kafes etkinken)', checks.count { |c| c == ['ERROR', 'Hesap Hatası', 10] } == 1 && checks.none? { |c| c[2] == 11 }, true)
  t('G3: pc_rebar_error HATA', checks.include?(['ERROR', 'Hesap Hatası', 12]), true)
  t('G3: rebar_restore_error UYARI + culvert_error HATA', [checks.include?(['WARNING', 'Hesap Hatası', 13]), checks.include?(['ERROR', 'Hesap Hatası', 13])], [true, true])
  k50 = out.select { |x| x[3].include?('ayak izi') }
  t('G3/K50: ayak izi diş geçişini kesen kazık (a=8.7 ± 0.508) uyarı, a=5 uyarı yok', k50.map { |x| x[3][/P-\d/] }, ['P-1'])
  out2 = h.mst_audit_v0515([], $all)
  t('G3: K33/K39/K40 bilgi satırları Model Kontrolü\'nde UYARI (QTO → BOQ)', out2.map { |x| [x[0], x[2]] }.uniq, [['WARNING', 'Metraj → Keşif']])
  t('model_audit çağrısı ve QTO sağlık grubunda Hesap Hatası (statik)', [main.include?('mst_audit_v0515(elems,all).each'), main.include?("'Metraj Malzeme','Metraj Donatı','Hesap Hatası']")], [true, true])
end
a1_finish
