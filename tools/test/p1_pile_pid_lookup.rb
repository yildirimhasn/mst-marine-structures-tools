# P1 (0.51.5 donma kök nedeni): mst_bk_connected_piles bağlı kazıkları model.find_entity_by_persistent_id ile TEK TEK arıyordu
# (SketchUp'ta çağrı başına ≈25 ms ölçüldü; kullanıcı ölçümü). Düzeltme: kısa süreli (1,5 s) kazık dizini persistent_id → öğe;
# yalnız dizinde bulunmayan (ya da dizindeki nesnesi geçersiz) PID için eski çağrı.
# Eklenti golden-master sahtesiyle (tools/golden/sketchup_stub.rb) gerçek yükleme sırasıyla yüklenir; model tools/golden/fixture.rb.
# Sınanan:
#  1) qto3_snapshot / boq_rows(true): mst_bk_connected_piles İÇİNDEN yapılan find_entity_by_persistent_id sayısı ≤ bulunamayan PID
#     sayısı (bu modelde 0). Eski kodda sayı = Σ(çağrı × PID) → KALDI.
#  2) Sonuç eşdeğerliği: her BK için sonuç (öğeler, nesne kimliği ve sıra) eski algoritmanın bu betikteki birebir kopyasıyla aynı.
#  3) Kenar durumlar: (a) PID'lerden biri silinmiş, (b) PID collect_elements'ın görmediği yerde (BK içinde iç içe kazık,
#     yerleştirilmemiş Component tanımı içinde kazık), (c) dizin kurulduktan sonra yeni kazık, (d) element_type kazık değil /
#     sonradan değişmiş, (e) dizindeki nesne geçersiz, aynı PID yeni nesnede (Geri Al benzeri), (f) PID sırası korunur.
# Okuma işlevi: model yazımı yok, işlem açılmaz (ayrıca denetlenir).
# Kullanim: ruby tools/test/p1_pile_pid_lookup.rb <src/marine_structures_tools>
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/p1_pile_pid_lookup.rb <marine_structures_tools klasoru>'
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
require_relative '../golden/fixture'
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze unless defined?(D)

# Saat denetimli: dizin önbelleği (1,5 s) testte kendiliğinden eskimesin
$now = 1_800_000_000.0
class << Time; def now; Time.at($now); end; end

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end

# find_entity_by_persistent_id sayacı: toplam ve mst_bk_connected_piles içinden
ORIG_FIND = Sketchup::Model.instance_method(:find_entity_by_persistent_id)
$find_all = 0; $find_bk = 0; $in_bk = 0
module P1FindCount
  def find_entity_by_persistent_id(pid)
    $find_all += 1
    $find_bk += 1 if $in_bk > 0
    super
  end
end
Sketchup::Model.prepend(P1FindCount)
$bk_calls = 0; $bk_pids = 0
orig_bk = M.method(:mst_bk_connected_piles)
M.define_singleton_method(:mst_bk_connected_piles) do |b|
  $bk_calls += 1
  $bk_pids += b.get_attribute(D, 'connected_pile_persistent_ids', '').to_s.split(/[,\s]+/).map(&:to_i).reject { |x| x <= 0 }.uniq.length
  $in_bk += 1
  begin
    orig_bk.call(b)
  ensure
    $in_bk -= 1
  end
end
$collects = 0
orig_ce = M.method(:collect_elements)
M.define_singleton_method(:collect_elements) { |*a| $collects += 1; orig_ce.call(*a) }

# Eski algoritma (main.rb c8f9d70 mst_bk_connected_piles birebir kopyası; arama sayaçsız özgün çağrıyla)
def ref_connected(b)
  model = $model
  pids = b.get_attribute(D, 'connected_pile_persistent_ids', '').to_s.split(/[,\s]+/).map(&:to_i).reject { |x| x <= 0 }.uniq
  unless pids.empty?
    out = pids.map { |pid| (ORIG_FIND.bind(model).call(pid) rescue nil) }.compact.select { |e| e.valid? && e.get_attribute(D, 'element_type', '').to_s == 'steel_pipe_pile' }
    return out if out.length == pids.length
  end
  ids = b.get_attribute(D, 'connected_pile_ids', '').to_s.split(',').map(&:strip).reject(&:empty?).uniq
  return [] if ids.empty?
  ano = b.get_attribute(D, 'ano', '').to_s
  idx = M.mst_pile_index_by_id
  ids.map do |id|
    cs = idx.key?(id) ? idx[id] : []
    if cs.length > 1 && !ano.empty?
      same = cs.select { |p| [p.get_attribute(D, 'ano', '').to_s, p.get_attribute(D, 'structure', '').to_s].include?(ano) }
      cs = same unless same.empty?
    end
    if cs.length > 1 && b.respond_to?(:bounds)
      near = cs.select { |p| (p.bounds.intersect(b.bounds).valid? rescue false) }
      cs = near unless near.empty?
    end
    cs.first
  end.compact.uniq
end

def sig(list); list.map { |e| [e.persistent_id, e.object_id] }; end

# Sonuç ve arama sayısı: tek BK için
def check(label, b, max_find)
  f0 = $find_bk
  got = M.mst_bk_connected_piles(b)
  n = $find_bk - f0
  exp = ref_connected(b)
  t("#{label}: sonuç (pid, nesne, sıra) eski algoritmayla aynı", sig(got), sig(exp))
  t("#{label}: find_entity_by_persistent_id ≤ #{max_find}", n <= max_find, true)
  puts "      (find=#{n}, sonuç pid=#{got.map(&:persistent_id).inspect})"
  got
end

def fresh
  golden_build_fixture
  M.instance_variable_set(:@mst_pile_idx_cache, nil)
  $now += 10.0
end

def add_bk(pid, pids, ids, extra = {})
  b = Sketchup::Group.new(pid, { 'element_type' => 'head_beam', 'head_beam_id' => "BKP#{pid}", 'length_m' => 10.0, 'width_m' => 1.2,
                                 'height_m' => 1.0, 'bottom_elevation_m' => 1.0, 'top_elevation_m' => 2.0, 'concrete_volume_m3' => 11.85,
                                 'concrete_class' => 'C30/37', 'ano' => 'A1', 'project' => 'GOLDEN',
                                 'connected_pile_persistent_ids' => pids, 'connected_pile_ids' => ids }.merge(extra))
  b.entities = gf_bk_faces(true)
  $model.entities << b
  b.parent = $model.entities
  $all_ents[pid] = b
  b
end

def pile(pid, id)
  Sketchup::Group.new(pid, gf_pile_attrs(id))
end

# ---- 1) metraj okuyucuları: BK×kazık×tekrar ----
fresh
10.times { |i| add_bk(9000 + i, '1001,1003,1004,1002', 'P1,P3,P4,P2', 'element_uid' => "MST-P1-BK#{i}") }
$writes = []
$model.ops.clear
{ 'qto3_snapshot' => -> { M.qto3_snapshot }, 'boq_rows(true)' => -> { M.boq_rows(true) } }.each do |nm, op|
  $now += 10.0
  $find_bk = 0; $find_all = 0; $bk_calls = 0; $bk_pids = 0; $collects = 0
  err = nil
  begin
    op.call
  rescue StandardError => e
    err = "#{e.class}: #{e.message[0, 160]}"
  end
  t("#{nm}: hata yok", err, nil)
  puts "      ÖLÇÜM #{nm}: mst_bk_connected_piles çağrı=#{$bk_calls}, Σ PID=#{$bk_pids}, find (BK içinden)=#{$find_bk}, find (toplam)=#{$find_all}, collect_elements=#{$collects}"
  t("#{nm}: mst_bk_connected_piles çağrıldı", $bk_calls > 0, true)
  t("#{nm}: BK içinden find_entity_by_persistent_id ≤ bulunamayan PID (0)", $find_bk, 0)
end
t('okuyucular model yazmadı', $writes.size, 0)
t('okuyucular işlem açmadı', $model.ops.size, 0)

# ---- 2) eşdeğerlik: tüm BK'lar ----
$now += 10.0
all = []; M.collect_elements($model.entities, all)
bks = all.select { |e| e.get_attribute(D, 'element_type', '') == 'head_beam' }
t('BK sayısı', bks.size, 12)
same = bks.all? { |b| sig(M.mst_bk_connected_piles(b)) == sig(ref_connected(b)) }
t('tüm BK: sonuç eski algoritmayla aynı', same, true)

# ---- 3) kenar durumlar ----
# (f) sıra
fresh
b = add_bk(9100, '1003,1001', 'P3,P1')
r = check('(f) PID sırası 1003,1001', b, 0)
t('(f) sıra korunur', r.map(&:persistent_id), [1003, 1001])

# (a) silinmiş kazık (dizin önce kurulur, sonra silinir) → eski davranış: ID yoluna düşer
fresh
b = add_bk(9101, '1001,1003', 'P1,P3')
M.mst_bk_connected_piles(b)            # dizin kurulsun
$all_ents[1003].erase!
check('(a) dizin sonrası silinen kazık', b, 1)
fresh
$all_ents[1003].erase!
b = add_bk(9102, '1001,1003', 'P1,P3')
check('(a) dizin öncesi silinen kazık', b, 1)

# (b) collect_elements'ın görmediği yerde kazık: BK içinde iç içe; yerleştirilmemiş Component tanımı içinde
fresh
b = add_bk(9103, '1001,7001,7002', 'P1,PN1,PN2')
pn = pile(7001, 'PN1'); b.entities = b.entities.to_a + [pn]; $all_ents[7001] = pn
dn = Sketchup::ComponentDefinition.new(7100); pd = pile(7002, 'PN2'); dn.entities = Sketchup::Entities.new([pd]); pd.parent = dn.entities
$model.definitions << dn; $all_ents[7002] = pd
r = check('(b) iç içe / tanım içi kazık', b, 2)
t('(b) iç içe kazıklar bulundu', r.map(&:persistent_id), [1001, 7001, 7002])

# (c) dizin kurulduktan sonra eklenen kazık
fresh
b = add_bk(9104, '1001,7003', 'P1,PNEW')
M.mst_pile_index_by_id                 # dizin kurulsun (yeni kazık yok)
np = pile(7003, 'PNEW'); $model.entities << np; np.parent = $model.entities; $all_ents[7003] = np
r = check('(c) dizin sonrası yeni kazık', b, 1)
t('(c) yeni kazık bulundu', r.map(&:persistent_id), [1001, 7003])

# (d) PID kazık olmayan öğe; dizin sonrası element_type değişen kazık
fresh
b = add_bk(9105, '1001,5001', 'P1')
check('(d) kazık olmayan PID (döşeme)', b, 1)
fresh
b = add_bk(9106, '1001,1003', 'P1,P3')
M.mst_bk_connected_piles(b)
$all_ents[1003].set_attribute(D, 'element_type', 'bored_pile')
check('(d) dizin sonrası element_type değişti', b, 0)
fresh
b = add_bk(9107, '9999999', 'P4')
check('(d) var olmayan PID', b, 1)

# (e) dizindeki nesne geçersiz, aynı PID yeni nesnede
fresh
b = add_bk(9108, '1001,1003', 'P1,P3')
M.mst_bk_connected_piles(b)
old = $all_ents[1001]; old.erase!
nw = pile(1001, 'P1'); $model.entities << nw; nw.parent = $model.entities; $all_ents[1001] = nw
r = check('(e) aynı PID yeni nesne', b, 1)
t('(e) yeni nesne döndü (eski geçersiz değil)', r.first.equal?(nw), true)

# (g) önbellek süresi dolunca dizin yeniden kurulur (yeni kazık artık dizinde → find 0)
fresh
b = add_bk(9109, '1001,7004', 'P1,PX')
M.mst_pile_index_by_id
np = pile(7004, 'PX'); $model.entities << np; np.parent = $model.entities; $all_ents[7004] = np
$now += 2.0
check('(g) 1,5 s sonra dizin yenilendi', b, 0)

# (h) mst_pile_index_by_id dönüşü değişmedi (anahtar → dizi, yalnız steel_pipe_pile)
fresh
idx = M.mst_pile_index_by_id
t('(h) mst_pile_index_by_id anahtarları', idx.keys.sort, %w[P1 P2 P2B P3 P4])
t('(h) mst_pile_index_by_id P1 değeri', idx['P1'].map(&:persistent_id), [1001])
t('(h) bilinmeyen anahtar boş dizi', idx.key?('YOK') ? :var : idx['YOK'], [])

puts "\n#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
