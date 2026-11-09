# Parti H / H7 (menfez – kazık gömülmesi kesişimi UYARISI), H8 (eski v0.34 tretuvar köşe bindirmesi UYARISI; sarmalayıcı
# Component ×N UYARISI), H9 (iki BİLGİ satırı). Yalnız Model Kontrolü satırı; metraj ve model değişmez (salt okuma).
# Kullanim: ruby tools/test/h_h7_h8_h9_audit.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')
class Host
  def mst_bk_pile_embed(b); $emb[b.persistent_id] || { volume_m3: 0.0, items: [] }; end
  def mst_pile_rebar_active(_e); false; end
  def pile_bim_qto_item(_p); {}; end
  def mst_boq_info_rows(_a = nil); []; end
end
a2_const(Host, main, 'MST_AUDIT_ERROR_FLAGS')
A1.load(Host, main, 'def mst_audit_v0515(', 'def mst_attr_hash(', 'def mst_hb_ents(')
A1.load_opt(Host, main, 'def mst_deck_pk_missing_audit(')   # ADR-0515-K2 P4: mst_audit_v0515 silinen PK denetimi
A1.load(Host, bm, 'def mst_hb_zones_list(', 'def mst_hb_culvert_groups(')
A1.load_opt(Host, bm, 'def mst_hb_zone_segments('); A1.load_opt(Host, bm, 'def mst_hb_bottom_depth(')
%w[mst_tr_scale_info mst_bk_span_frame_error mst_pv_tooth_seat_warnings].each { |f| A1.load_opt(Host, main, "def #{f}(") }
A1.load_opt(Host, A1.src('mst_rebar_tools.rb'), 'def mst_rt_world_tr(')
%w[mst_collect_toppings mst_topping_parent_deck].each { |f| A1.load_opt(Host, A1.src('dependency_rebuild.rb'), "def #{f}(") }
A1.load_opt(Host, bm, 'def mst_vk_support_state(')
NEW = A1.load_opt(Host, main, 'def mst_cv_embed_overlap?(') & A1.load_opt(Host, main, 'def mst_curb_corner_overlap(')
t('H7 / H8 yardımcıları tanımlı', NEW, true)
h = Host.new
D = A1::DICT
$model = FakeModel.new; $model.entities = []

# ---- H7
def culvert(box); Sketchup::Group.new(rand(1_000_000), 'element_type' => 'bk_culvert', 'cv_box_json' => JSON.generate(box)); end
def bk(pid, boxes)
  b = Sketchup::Group.new(pid, 'element_type' => 'head_beam', 'id' => "BK-#{pid}", 'length_m' => 10.0, 'width_m' => 1.2, 'height_m' => 1.0)
  b.entities = boxes.map { |x| culvert(x) }
  b
end
# kazık ekseni a=5.0, y=0.6, Ø1016 düşey; gömülme z ∈ [0, 0.2] (taban derinliği 0, gömülme 0.2)
it = { pile_id: 'P-1', pid: 31, diameter_mm: 1016.0, batter: 0.0, embed_m: 0.2, bottom_depth_m: 0.0, axis_a_m: 5.0, axis_y_m: 0.6, origin_z_m: 1.2, width_m: 1.2, pile_top_m: 1.2 }
if NEW
  t('H7 kutu kazık zarfını planda ve düşeyde kesiyor → örtüşme', h.mst_cv_embed_overlap?(bk(1, [[4.5, 0.0, 0.1, 5.5, 1.2, 0.5]]), it), true)
  t('H7 kutu planda uzakta (x 7–8) → yok', h.mst_cv_embed_overlap?(bk(2, [[7.0, 0.0, 0.0, 8.0, 1.2, 0.5]]), it), false)
  t('H7 kutu gömülmenin üstünde (z 0.3–0.8) → yok', h.mst_cv_embed_overlap?(bk(3, [[4.5, 0.0, 0.3, 5.5, 1.2, 0.8]]), it), false)
  t('H7 dişte (taban derinliği 0.5 → z −0.5…−0.3) kutu z 0–0.4 ile kesişmez', h.mst_cv_embed_overlap?(bk(4, [[4.5, 0.0, 0.0, 5.5, 1.2, 0.4]]), it.merge(bottom_depth_m: 0.5)), false)
  t('H7 eğik kazık zarfı d/2·√(1+r²): kutu kenarı 5,511 < 5,0 + 0,515 → örtüşme', h.mst_cv_embed_overlap?(bk(5, [[5.511, 0.0, 0.0, 6.0, 1.2, 0.5]]), it.merge(batter: 1.0 / 6)), true)
  t('H7 menfez yok / konum bilinmiyor → yok', [h.mst_cv_embed_overlap?(bk(6, []), it), h.mst_cv_embed_overlap?(bk(7, [[4.5, 0, 0.1, 5.5, 1.2, 0.5]]), it.merge(axis_y_m: nil))], [false, false])
end
b1 = bk(100, [[4.5, 0.0, 0.1, 5.5, 1.2, 0.5]])
$emb = { 100 => { volume_m3: 0.2, items: [it] } }
out = h.mst_audit_v0515([b1], [b1])
w7 = out.select { |o| o[3].include?('menfez ile P-1 kazığının gömülmesi kesişiyor') }
t('H7 Model Kontrolü UYARISI (Hesap Hatası, BK + kazık seçimi)', w7.map { |o| [o[0], o[2], o[5]] }, [['WARNING', 'Hesap Hatası', [100, 31]]])

# ---- H8 tretuvar köşe bindirmesi
def curb(pid, side, len, wid, os = 0.0, oe = 0.0)
  Sketchup::Group.new(pid, 'element_type' => 'curb', 'curb_id' => "B-D9-#{side}", 'parent_deck_id' => 'D9', 'side' => side, 'length_m' => len, 'width_m' => wid,
                           'height_m' => 0.3, 'start_offset_m' => os, 'end_offset_m' => oe, 'concrete_volume_m3' => len * wid * 0.3)
end
cs = [curb(61, '1', 10.0, 0.4), curb(62, '2', 10.0, 0.4), curb(63, '3', 0.4, 5.0), curb(64, '4', 0.4, 5.0)]
if NEW
  v, pairs = h.mst_curb_corner_overlap(cs.map { |c| [c.a('side'), c] }.to_h)
  t('H8 ofset 0: 4·w²·h = 4 × 0,4² × 0,3 = 0,192 m³, dört köşe', [v.round(6), pairs], [0.192, %w[1/3 1/4 2/3 2/4]])
  co = [curb(71, '1', 9.9, 0.4, 0.1), curb(72, '2', 9.9, 0.4, 0.1), curb(73, '3', 0.4, 4.9, 0.1), curb(74, '4', 0.4, 4.9, 0.1)]
  v2, = h.mst_curb_corner_overlap(co.map { |c| [c.a('side'), c] }.to_h)
  t('H8 başlangıç ofseti 0,1: (0,3² + 0,3·0,4 + 0,3·0,4 + 0,4²) × 0,3 = 0,147 m³', v2.round(6), 0.147)
  v3, = h.mst_curb_corner_overlap('1' => cs[0], '2' => cs[1])
  t('H8 yalnız uzun kenarlar: bindirme yok', v3, 0.0)
end
out = h.mst_audit_v0515(cs, cs)
w8 = out.select { |o| o[2] == 'Tretuvar Metrajı' && o[3].include?('köşelerde üst üste biniyor') }
t('H8 tretuvar UYARISI tahmini hacimle, kayıtlı değer değişmez', [w8.size, w8[0] && w8[0][3].include?('0.192 m³'), cs.map { |c| c.a('concrete_volume_m3') }], [1, true, [1.2, 1.2, 0.6, 0.6]])
new_curb = Sketchup::Group.new(81, 'element_type' => 'curb', 'parent_deck_id' => 'D9', 'length_m' => 10.0, 'width_m' => 0.4, 'height_m' => 0.3)
t('H8 tarafsız (yeni) tretuvarda uyarı yok', h.mst_audit_v0515([new_curb], [new_curb]).count { |o| o[2] == 'Tretuvar Metrajı' }, 0)

# ---- H8 sarmalayıcı Component ×N
p = Sketchup::Group.new(91, 'element_type' => 'steel_pipe_pile', 'id' => 'P-91')
q = Sketchup::Group.new(92, 'element_type' => 'steel_pipe_pile', 'id' => 'P-92')
out = h.mst_audit_v0515([p, p, p, q], [p, p, p, q])
w = out.select { |o| o[2] == 'Keşif → Hakediş' && o[3].include?('sarmalayıcı Component') }
t('H8 ×N: tek UYARI, N=3, yalnız çoğalan öğe', w.map { |o| [o[0], o[3].include?('1 MST öğesi çok kopyalı bir sarmalayıcı Component içinde 3 kez yer alıyor (P-91)'), o[3].include?('Keşif bu öğeleri 3 kez, hakediş 1 kez sayar'), o[5]] },
  [['WARNING', true, true, [91]]])
t('H8 ×N: çoğalma yoksa uyarı yok', h.mst_audit_v0515([p, q], [p, q]).count { |o| o[3].include?('sarmalayıcı Component') }, 0)

# ---- H9
bkd = Sketchup::Group.new(201, 'element_type' => 'head_beam', 'id' => 'BK-D', 'rebar_mode' => 'drawing_detail', 'rebar_schedule_json' => '{"P1":{"kg":100},"SEHPA-1":{"kg":5}}')
bkb = Sketchup::Group.new(202, 'element_type' => 'head_beam', 'id' => 'BK-B', 'rebar_mode' => 'bim_detail', 'rebar_schedule_json' => '{"CHAIR":{"kg":5}}')
bkn = Sketchup::Group.new(203, 'element_type' => 'head_beam', 'id' => 'BK-N', 'rebar_schedule_json' => '{"P1":{"kg":100}}')
dk1 = Sketchup::Group.new(211, 'element_type' => 'deck_slab', 'deck_id' => 'D-1', 'rebar_mode' => 'auto_detail', 'topping_enabled' => '1')
dk2 = Sketchup::Group.new(212, 'element_type' => 'deck_slab', 'deck_id' => 'D-2', 'rebar_mode' => 'bim_detail', 'topping_enabled' => '1')
dk3 = Sketchup::Group.new(213, 'element_type' => 'deck_slab', 'deck_id' => 'D-3', 'rebar_mode' => 'drawing_detail', 'topping_enabled' => '0')
els = [bkd, bkb, bkn, dk1, dk2, dk3]
$emb = {}
out = h.mst_audit_v0515(els, els)
i1 = out.select { |o| o[3].start_with?('Bilgi:') && o[3].include?('sehpa (CHAIR / SEHPA)') }
i2 = out.select { |o| o[3].start_with?('Bilgi:') && o[3].include?('kaplama hasırını') }
t('H9 sehpa BİLGİ yalnız BIM dışı + CHAIR/SEHPA satırlı BK', i1.map { |o| [o[2], o[5]] }, [['BK Metrajı', [201]]])
t('H9 kaplama hasırı BİLGİ yalnız paftadan/otomatik + kaplamalı döşeme', i2.map { |o| [o[2], o[5]] }, [['Döşeme Metrajı', [211]]])
t('H9 salt okuma: model yazımı yok', sets.size, 0)
a1_finish
