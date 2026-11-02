# Parti G-a / G1 (kod inceleme #2): BIM Kimlik Onarımı — kopyanın kopyasında devralınmış ilerleme geçmişi
# (progress_inherited_history_json). ADR 13 §G1: 7 senaryo.
# Kullanim: ruby tools/test/g1_inherited_history.rb <src/marine_structures_tools>
require_relative 'a1_helper'
main = A1.src('main.rb')
dep = A1.src('dependency_rebuild.rb')
boq = A1.src('boq_pro.rb')

class Host
  def mst_identity_id_key(_t); nil; end
  def bim_type_prefix(_t); 'D'; end
  def mst_next_unique_physical_id(_p, _u); 'X'; end
  def mst_all_elements; []; end
  def model_audit; $log << [:audit]; end
  def mst_world_box(e); e.box; end
end
A1.load(Host, main, 'def ensure_uid(', 'def repair_bim_identity', 'def mst_world_box_center(')
A1.load(Host, dep, 'def mst_uid_owner(')
A1.load(Host, boq, 'def prog2_base(', 'def prog2_items(e)', 'def prog2_norm(', 'def prog2_rec(', 'def prog2_clamp(', 'def prog2_ok_entry(',
        'def prog2_rec_frac(', 'def prog2_legacy_ok?(', 'def prog2_frac(')
h = Host.new
H = 'progress_inherited_history_json'
box = { 'x' => [0.0, 1.0], 'y' => [0.0, 1.0] }
pj1 = '{"DECK":{"claim":100,"ok":[["2026-10-01",100,"x"]]}}'
pj2 = '{"DECK":{"claim":60,"ok":[["2026-10-20",60,"y"]]}}'
pj3 = '{"DECK":{"claim":30,"ok":[["2026-10-25",30,"z"]]}}'
deck = ->(pid, extra) { FakeEnt.new(pid, { 'element_type' => 'deck_slab', 'id' => "D#{pid}" }.merge(extra), box) }
hist = ->(e) { e.a(H).nil? ? nil : JSON.parse(e.a(H)) }

# 1) İlk onarım: eski davranış (geçmiş yazılmaz)
a1_reset!
own = deck.(100, 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'progress_items_json' => pj1, 'progress_status' => 'Onaylandı')
c1 = deck.(200, 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'progress_items_json' => pj1, 'progress_status' => 'Onaylandı')
$model.entities = [own, c1]
h.repair_bim_identity
t('G1-1 ilk onarım: progress_inherited_json/_status (eski davranış)', [c1.a('progress_inherited_json'), c1.a('progress_inherited_status'), c1.a('progress_items_json'), c1.a('progress_status')], [pj1, 'Onaylandı', nil, 'Planlandı'])
t('G1-1 ilk onarım: geçmiş anahtarı yazılmaz', c1.a(H), nil)
t('G1-1 önizleme cümlesi', $msgs.first.to_s.include?('Önceki devralma kaydı olan kopyada yeni devralma geçmişe eklenir; eski kayıt değişmez.'), true)

# 2) İkinci kuşak: onarılmış kopyaya (c1) ilerleme girildi, sonra Ctrl+Move → c2 aynı öznitelikleri taşır
c1.set_attribute(A1::DICT, 'progress_items_json', pj2); c1.set_attribute(A1::DICT, 'progress_status', 'Onaylandı')
u1 = c1.a('element_uid'); cf1 = c1.a('copied_from_uid')
c2 = FakeEnt.new(300, c1.raw_attrs.select { |(d, _), _| d == A1::DICT }.map { |(_, k), v| [k, v] }.to_h, box)
c2.set_attribute(A1::DICT, 'id', 'D300')
inh_json_before = c2.a('progress_inherited_json').dup; inh_st_before = c2.a('progress_inherited_status').dup
$model.entities = [own, c1, c2]; $log = []; $msgs = []
h.repair_bim_identity
g = hist.(c2)
t('G1-2 ikinci kuşak: c1 asıl (kayıtlı sahip), c2 kopya', [c1.a('element_uid'), c2.a('element_uid') != u1], [u1, true])
t('G1-2 geçmiş 1 kayıt', g.is_a?(Array) && g.length, 1)
t('G1-2 kayıt alanları', g && [g[0]['v'], g[0]['source'], g[0]['from_uid'], g[0]['new_uid'] == c2.a('element_uid'), g[0]['items_json'], g[0]['status'], g[0]['prev_copied_from_uid'], g[0]['prev_uid_owner_pid']],
  [1, 'repair_bim_identity', u1, true, pj2, 'Onaylandı', cf1, 200])
t('G1-2 eski tekil alanlar bayt bayt aynı', [c2.a('progress_inherited_json').b == inh_json_before.b, c2.a('progress_inherited_status').b == inh_st_before.b], [true, true])
t('G1-2 progress_items_json silindi, durum Planlandı', [c2.a('progress_items_json'), c2.a('progress_status')], [nil, 'Planlandı'])
t('G1-2 prog2_frac(kopya) = 0 (hakedişte çift sayım yok)', h.prog2_frac(c2, 'DECK'), 0.0)
t('G1-6 asıl öğeler değişmez (c1 ilerlemesi, own ilerlemesi)', [c1.a('progress_items_json'), c1.a('progress_status'), own.a('progress_items_json'), own.a('progress_status')], [pj2, 'Onaylandı', pj1, 'Onaylandı'])
t('G1-6 asıl öğede geçmiş yazılmaz', [c1.a(H), own.a(H)], [nil, nil])
t('G1-7 tek işlem: start=1 commit=1 abort=0', [ops.count(:start), ops.count(:commit), ops.count(:abort)], [1, 1, 0])

# 3) Üçüncü kuşak: c2'ye ilerleme girildi, Ctrl+Move → c3 (geçmiş 1 kayıtla gelir) → geçmiş 2
c2.set_attribute(A1::DICT, 'progress_items_json', pj3); c2.set_attribute(A1::DICT, 'progress_status', 'Tamamlandı')
u2 = c2.a('element_uid'); g_before = c2.a(H).dup
c3 = FakeEnt.new(400, c2.raw_attrs.select { |(d, _), _| d == A1::DICT }.map { |(_, k), v| [k, v] }.to_h, box); c3.set_attribute(A1::DICT, 'id', 'D400')
$model.entities = [own, c1, c2, c3]; $log = []; $msgs = []
h.repair_bim_identity
g3 = hist.(c3)
t('G1-3 üçüncü kuşak: geçmiş 2 kayıt, ilk kayıt değişmez', [g3.length, JSON.generate(g3[0]) == JSON.generate(JSON.parse(g_before)[0])], [2, true])
t('G1-3 ikinci kayıt', [g3[1]['from_uid'], g3[1]['items_json'], g3[1]['status'], g3[1]['prev_uid_owner_pid']], [u2, pj3, 'Tamamlandı', 300])
t('G1-3 asıl c2 geçmişi değişmez', c2.a(H), g_before)
t('G1-3 prog2_frac(c3) = 0', h.prog2_frac(c3, 'DECK'), 0.0)

# 4) Yalnız durum: önceki devralmada yalnız durum vardı, yeni kopyada da yalnız durum
a1_reset!
o4 = deck.(500, 'element_uid' => 'MST-500-R', 'uid_owner_pid' => 500, 'progress_status' => 'Onaylandı', 'progress_inherited_status' => 'Tamamlandı')
c4 = deck.(600, 'element_uid' => 'MST-500-R', 'uid_owner_pid' => 500, 'progress_status' => 'Onaylandı', 'progress_inherited_status' => 'Tamamlandı')
$model.entities = [o4, c4]
h.repair_bim_identity
g4 = hist.(c4)
t('G1-4 yalnız durum: geçmiş 1 kayıt, items_json nil, status Onaylandı', g4 && [g4.length, g4[0]['items_json'], g4[0]['status']], [1, nil, 'Onaylandı'])
t('G1-4 yalnız durum: progress_status Planlandı, eski durum alanı aynı', [c4.a('progress_status'), c4.a('progress_inherited_status'), c4.a('progress_items_json')], ['Planlandı', 'Tamamlandı', nil])
t('G1-4 prog2_frac = 0 (eski durum yolu)', h.prog2_frac(c4, 'DECK'), 0.0)

# 5) Bozuk geçmiş: işlem açılmaz, hiçbir şey yazılmaz
a1_reset!
o5 = deck.(700, 'element_uid' => 'MST-700-1', 'uid_owner_pid' => 700, 'progress_items_json' => pj1)
c5 = deck.(800, 'element_uid' => 'MST-700-1', 'uid_owner_pid' => 700, 'id' => 'D800', 'progress_items_json' => pj1, 'progress_inherited_json' => pj2, H => '{"bozuk":')
$model.entities = [o5, c5]
h.repair_bim_identity
t('G1-5 bozuk geçmiş: işlem açılmaz', ops, [])
t('G1-5 bozuk geçmiş: yazım yok', sets.size, 0)
t('G1-5 bozuk geçmiş: ileti', $msgs.last.to_s, 'D800: devralınmış ilerleme geçmişi (progress_inherited_history_json) okunamadı; üzerine yazılmadı, onarım yapılmadı.')
t('G1-5 bozuk geçmiş: kayıt aynen', [c5.a(H), c5.a('progress_items_json'), c5.a('element_uid')], ['{"bozuk":', pj1, 'MST-700-1'])
c5.set_attribute(A1::DICT, H, '{"a":1}'); $log = []; $msgs = []
h.repair_bim_identity
t('G1-5 geçmiş JSON ama dizi değil: işlem açılmaz', [ops, $msgs.last.to_s.include?('okunamadı')], [[], true])
a1_finish
