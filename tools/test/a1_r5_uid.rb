# A1 / R-5 (K06): uid_owner_pid, mst_uid_owner, tretuvar bağı, revision_diff, mst_copy_dicts!, repair_bim_identity.
# Kullanim: ruby tools/test/a1_r5_uid.rb <src/marine_structures_tools>
require_relative 'a1_helper'
main = A1.src('main.rb')
dep = A1.src('dependency_rebuild.rb')

class Host
  attr_accessor :boxes
  def mst_pile_ids_for_beam(_b); []; end
  def mst_identity_id_key(_t); nil; end
  def bim_type_prefix(_t); 'D'; end
  def mst_next_unique_physical_id(_p, _u); 'X'; end
  def mst_all_elements; []; end
  def model_audit; $log << [:audit]; end
  def mst_world_box(e); e.box; end
end
A1.load(Host, main, 'def ensure_uid(', 'def revision_diff(', 'def mst_copy_dicts!(', 'def repair_bim_identity', 'def mst_world_box_center(')
A1.load(Host, dep, 'def dependency_graph(')
has_owner = A1.load_opt(Host, dep, 'def mst_uid_owner(')
# Parti B (K07) düzeneği: dependency_graph kaplamaları ayrı toplayıcıyla ekler (bu testte kaplama yok)
module Sketchup; class Group < FakeEnt; end; end unless defined?(Sketchup::Group)
A1.load_opt(Host, dep, 'def mst_collect_toppings('); A1.load_opt(Host, dep, 'def mst_topping_parent_deck(')
obs('mst_uid_owner tanımlı', has_owner)
h = Host.new
box = ->(x0, x1) { { 'x' => [x0, x1], 'y' => [0.0, 5.0] } }

# ---- mst_uid_owner karar yolu
if has_owner
  a = FakeEnt.new(100, 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100); b = FakeEnt.new(200, 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100)
  t('owner: kayıtlı sahip', h.mst_uid_owner([b, a]), [a, 'kayıtlı sahip'])
  a = FakeEnt.new(100, 'element_uid' => 'MST-100-1'); b = FakeEnt.new(50, 'element_uid' => 'MST-100-1')
  t('owner: UID içindeki PID', h.mst_uid_owner([b, a]), [a, 'UID içindeki PID'])
  a = FakeEnt.new(300, 'element_uid' => 'ABC'); b = FakeEnt.new(250, 'element_uid' => 'ABC')
  t('owner: en eski PID', h.mst_uid_owner([a, b]), [b, 'en eski PID'])
else
  t('owner: mst_uid_owner var', false, true)
end

# ---- ensure_uid sahiplik yazar
a1_reset!; x = FakeEnt.new(7, 'element_type' => 'curb'); h.ensure_uid(x)
t('ensure_uid: uid_owner_pid yazıldı', x.a('uid_owner_pid'), 7)

# ---- dependency_graph: kopya döşemeli tretuvar bağı
a1_reset!
d = FakeEnt.new(100, 'element_type' => 'deck_slab', 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'id' => 'D1')
dc = FakeEnt.new(200, 'element_type' => 'deck_slab', 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'id' => 'D1')
c = FakeEnt.new(101, 'element_type' => 'curb', 'element_uid' => 'MST-101-1', 'parent_uid' => 'MST-100-1')
$model.entities = [dc, d, c]
_all, children, = h.dependency_graph($model)
t('K06 tretuvar: kopya döşeme varken asıl döşemeye bağlı kalır', children[d].include?(c), true)
t('K06 tretuvar: kopya döşemeye bağlanmaz', children[dc].include?(c), false)
d2 = FakeEnt.new(300, 'element_type' => 'deck_slab', 'element_uid' => 'XYZ'); d3 = FakeEnt.new(301, 'element_type' => 'deck_slab', 'element_uid' => 'XYZ')
c2 = FakeEnt.new(302, 'element_type' => 'curb', 'element_uid' => 'C2', 'parent_uid' => 'XYZ')
$model.entities = [d2, d3, c2]
_all, children, = h.dependency_graph($model)
t('K06 tretuvar: sahip belirsiz (en eski PID) → bağ kurulmaz', children[d2].include?(c2) || children[d3].include?(c2), false)

# ---- revision_diff mükerrer UID
prev = [{ 'uid' => 'U', 'pid' => 1, 'concrete_m3' => 1.0 }]
curr = [{ uid: 'U', pid: 1, concrete_m3: 1.0 }, { uid: 'U', pid: 2, concrete_m3: 1.0 }]
r = h.revision_diff(prev, curr)
t('K06 revision_diff: kopya "eklendi" (U~PID-2)', r[:added].map { |x| x[:uid] }, ['U~PID-2'])
t('K06 revision_diff: asıl değişmedi/silinmedi', [r[:deleted].size, r[:changed].size], [0, 0])
t('K06 revision_diff: beton farkı +1.0', r[:delta][:concrete_m3], 1.0)
r = h.revision_diff([{ 'uid' => 'U', 'pid' => 1, 'concrete_m3' => 1.0 }, { 'uid' => 'U', 'pid' => 2, 'concrete_m3' => 1.0 }], curr)
t('K06 revision_diff: iki tarafta mükerrer → fark yok', [r[:added].size, r[:deleted].size, r[:changed].size], [0, 0, 0])
r = h.revision_diff([{ 'uid' => 'U', 'pid' => 1 }], [{ uid: 'U', pid: 9 }])
t('K06 revision_diff: tek kayıtta PID değişimi (Group→Component) UID ile eşleşir', [r[:added].size, r[:deleted].size], [0, 0])

# ---- mst_copy_dicts! sahiplik
a1_reset!
f = FakeEnt.new(5, 'element_uid' => 'MST-5-1'); to = FakeEnt.new(9); h.mst_copy_dicts!(f, to)
t('copy_dicts: kayıt yoksa sahiplik yeni varlığa', to.a('uid_owner_pid'), 9)
f = FakeEnt.new(5, 'element_uid' => 'MST-3-1', 'uid_owner_pid' => 3); to = FakeEnt.new(9); h.mst_copy_dicts!(f, to)
t('copy_dicts: kaynak kopyaysa sahiplik taşınmaz', to.a('uid_owner_pid'), 3)

# ---- repair_bim_identity
a1_reset!
pj = '{"DECK":{"claim":100,"ok":[["2026-10-01",100,"x"]]}}'
d = FakeEnt.new(100, { 'element_type' => 'deck_slab', 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'id' => 'D1', 'progress_items_json' => pj, 'progress_status' => 'Onaylandı' }, box.(0.0, 10.0))
dc = FakeEnt.new(200, { 'element_type' => 'deck_slab', 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'id' => 'D2', 'progress_items_json' => pj, 'progress_status' => 'Onaylandı' }, box.(20.0, 30.0))
c = FakeEnt.new(101, { 'element_type' => 'curb', 'element_uid' => 'MST-101-1', 'uid_owner_pid' => 101, 'id' => 'TR1', 'parent_uid' => 'MST-100-1' }, box.(4.0, 6.0))
cc = FakeEnt.new(201, { 'element_type' => 'curb', 'element_uid' => 'MST-101-1', 'uid_owner_pid' => 101, 'id' => 'TR2', 'parent_uid' => 'MST-100-1' }, box.(24.0, 26.0))
$model.entities = [dc, cc, d, c]
h.repair_bim_identity
t('K06 onarım: asıl döşeme UID korunur', d.a('element_uid'), 'MST-100-1')
t('K06 onarım: kopya döşemeye yeni UID', dc.a('element_uid').to_s.start_with?('MST-200-') && dc.a('element_uid').to_s.end_with?('-R'), true)
t('K06 onarım: copied_from_uid + uid_owner_pid', [dc.a('copied_from_uid'), dc.a('uid_owner_pid')], ['MST-100-1', 200])
t('K06 onarım: kopya ilerlemesi devralındı (aynen)', [dc.a('progress_inherited_json'), dc.a('progress_items_json')], [pj, nil])
t('K06 onarım: kopya durumu Planlandı, eski durum saklı', [dc.a('progress_status'), dc.a('progress_inherited_status')], ['Planlandı', 'Onaylandı'])
t('K06 onarım: asıl ilerleme değişmez', [d.a('progress_items_json'), d.a('progress_status')], [pj, 'Onaylandı'])
t('K06 onarım: kopya tretuvar kopya döşemeye (yeni UID) bağlandı', [cc.a('parent_uid') == dc.a('element_uid'), cc.a('parent_uid').to_s.start_with?('MST-200-')], [true, true])
t('K06 onarım: asıl tretuvar asıl döşemede', c.a('parent_uid'), 'MST-100-1')
t('K06 onarım: önizleme asıl → kopya + karar yolu', $msgs.first.to_s.include?('D1 (PID 100) → D2 (PID 200) · kayıtlı sahip'), true)
t('K06 onarım: tek işlem', ops, [:start, :commit])
a1_finish
