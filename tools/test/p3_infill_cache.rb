# P4 / D4 (0.51.5 donma düzeltmesi, 2. aşama):
#  D4 — pile_qto_infill_children okuma batch'inde (mst_read_batch) kazık başına bir kez ham entities taraması yapar (anahtar: Group
#       kazıkta persistent_id, Component kazıkta tanımın persistent_id'si); yazma batch'inde ve batch dışında önbellek yok.
#  P4 — revision_send, send_boq_mapping (gömülü ÖBF eşleştirme), bp_send (gömülü Fore Kazık) mst_read_batch ile sarılı.
# Eklenti golden-master sahtesiyle (tools/golden/sketchup_stub.rb) gerçek yükleme sırasıyla yüklenir; model tools/golden/fixture.rb
# (P2 / P2B aynı Component tanımını paylaşır) + kayıtlı revizyon anlık kaydı (sonra P4 boyu değiştirilir → revizyon farkı dolu).
# Sınanan:
#  1) Her giriş noktasında pile_qto_infill_children'ın ham entities taraması (Entities#select) entities nesnesi başına ≤ 1.
#  2) Çıktı eşdeğerliği: batch'li ve batch'siz (mst_read_batch → yalnız yield) — diyaloğa giden JS / dönüş değeri, model yazımları,
#     son öznitelik durumu birebir aynı (send_boq, qto_summary, progress_send, boq_rows, revision_send/revision_payload,
#     send_boq_mapping, bp_send, project_workspace_refresh).
#  3) Component paylaşılan tanım: P2 ve P2B tek tarama, aynı sonuç; P2 "iç beton YOK" hacmi 0 kalır.
#  4) Batch dışı: her çağrı tarar, önbellek kurulmaz. Yazma batch'i (mst_scan_batch): her çağrı tarar, önbellek kurulmaz.
#  5) Dönen dizi değiştirilse önbellek bozulmaz; geçersizleşen (silinen) çocuk süzülür; batch sonunda (hata yolunda da) önbellek silinir.
# Kullanim: ruby tools/test/p3_infill_cache.rb <src/marine_structures_tools>
require 'digest'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/p3_infill_cache.rb <marine_structures_tools klasoru>'
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
require_relative '../golden/fixture'
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze unless defined?(D)
$now = 1_800_000_000.0
class << Time; def now; Time.at($now); end; end

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 160]} (beklenen #{exp.inspect[0, 160]})"
end

class RecDialog
  attr_reader :out
  def initialize; @out = []; end
  def execute_script(j); @out << j; true; end
  def set_html(h); @out << "HTML:#{h}"; true; end
  def visible?; true; end
  def method_missing(*_a); nil; end
  def respond_to_missing?(*) true end
end

# pile_qto_infill_children içindeki ham taramayı say (entities nesnesi başına)
$in_pq = false
$scan = Hash.new(0)
$pq_calls = 0
module P3CountSelect
  def select(*a, &b)
    $scan[object_id] += 1 if $in_pq
    super
  end
end
Sketchup::Entities.prepend(P3CountSelect)
ORIG_PQ = M.method(:pile_qto_infill_children)
M.define_singleton_method(:pile_qto_infill_children) do |p|
  $pq_calls += 1
  $in_pq = true
  begin
    ORIG_PQ.call(p)
  ensure
    $in_pq = false
  end
end
$full = 0
orig_raw = M.method(:mst_collect_elements_raw)
M.define_singleton_method(:mst_collect_elements_raw) do |ents, out|
  $full += 1 if ents.respond_to?(:parent) && ents.parent.is_a?(Sketchup::Model)
  orig_raw.call(ents, out)
end
HAS_RB = M.respond_to?(:mst_read_batch)
ORIG_RB = HAS_RB ? M.method(:mst_read_batch) : nil
def batching(on)
  if on && HAS_RB
    M.define_singleton_method(:mst_read_batch, &ORIG_RB)
  elsif HAS_RB
    M.define_singleton_method(:mst_read_batch) { |*_a, &b| b.call }
  end
end
def rb_state
  [M.instance_variable_get(:@mst_scan_batch_on), M.instance_variable_get(:@mst_read_batch_on), M.instance_variable_get(:@mst_infill_children_cache)]
end

def build
  golden_build_fixture
  M.instance_variable_set(:@mst_pile_idx_cache, nil)
  M.instance_variable_set(:@mst_last_audit, nil)
  $now = 1_800_000_000.0
  # kayıtlı revizyon (batch dışında, saf kurucuyla) → sonra P4 boyu değişir: revizyon farkı "değişen" satırı üretir
  batching(false)
  snap = M.revision_create_snapshot_base(M.revision_snapshots, M.revision_current_snapshot)
  $model.set_attribute(M::REVISION_DICT, 'snapshots', JSON.generate([snap]))
  $all_ents[1004].set_attribute(D, 'length_m', 26.0)
  $all_ents[1004].set_attribute(D, 'actual_length_m', 26.0)
  batching(true)   # çağıran (run_entry) gerekirse yeniden kapatır
  $writes = []
end

def state_sig
  rows = ([$model] + $all_ents.values.sort_by(&:persistent_id)).map do |e|
    [e.persistent_id, e.attribute_dictionaries.compact.flat_map { |dd| dd.keys.sort.map { |k| [dd.name, k, dd[k].to_s] } }]
  end
  Digest::SHA256.hexdigest(Marshal.dump(rows))[0, 16]
end

def jsonish(v)
  JSON.generate(v)
rescue StandardError
  v.inspect
end

ENTRIES = {
  'send_boq' => ->(d) { M.send_boq(d) },
  'qto_summary' => ->(d) { M.qto_summary(d) },
  'progress_send' => ->(d) { M.progress_send(d) },
  'boq_rows' => ->(d) { M.mst_read_batch { d.out << jsonish(M.boq_rows(true)) } },
  'revision_send' => ->(d) { M.revision_send(d) },
  'revision_payload' => ->(d) { M.mst_read_batch { d.out << jsonish(M.revision_payload) } },
  'send_boq_mapping' => ->(d) { M.send_boq_mapping(d) },
  'bp_send' => ->(d) { M.instance_variable_set(:@bp_dialog, d); M.bp_send },
  'project_workspace_refresh' => ->(d) { M.project_workspace_refresh(d) }
}.freeze

def run_entry(name, on)
  build
  batching(on)
  $ui_msgs = []
  d = RecDialog.new
  $full = 0; $scan.clear; $pq_calls = 0
  w0 = $writes.size
  ENTRIES[name].call(d)
  { out: d.out.map { |s| s.gsub(/"model_token":"\d+"/, '"model_token":"*"') }, writes: $writes[w0..].map { |pid, dd, k| [pid, dd, k] },
    full: $full, scan_max: $scan.values.max.to_i, scan_sum: $scan.values.sum, pq: $pq_calls, sig: state_sig, msgs: $ui_msgs.dup,
    err: d.out.grep(/Error\(|qtoError|progressError|projectWorkspaceError|revisionError|mappingError|bpError/).first }
end

puts "mst_read_batch tanımlı: #{HAS_RB}"
ENTRIES.each_key do |name|
  a = run_entry(name, false)
  b = run_entry(name, true)
  t("#{name}: hata iletisi yok", [b[:err], b[:msgs]], [nil, []])
  t("#{name}: çıktı batch'li = batch'siz (#{b[:out].sum(&:bytesize)} bayt)", Digest::SHA256.hexdigest(b[:out].join("\n")), Digest::SHA256.hexdigest(a[:out].join("\n")))
  t("#{name}: model yazımları aynı (#{b[:writes].size})", b[:writes], a[:writes])
  t("#{name}: son öznitelik durumu aynı", b[:sig], a[:sig])
  puts "      pile_qto_infill_children çağrı=#{b[:pq]}; ham tarama batch'siz=#{a[:scan_sum]} (en çok #{a[:scan_max]}/kazık) batch'li=#{b[:scan_sum]} (en çok #{b[:scan_max]}/kazık); tam model taraması #{a[:full]} → #{b[:full]}"
  t("#{name}: ham entities taraması kazık başına ≤ 1", b[:scan_max] <= 1, true)
  t("#{name}: tam model taraması ≤ 1", b[:full] <= 1, true)
  t("#{name}: batch sonrası durum temiz", rb_state, [false, nil, nil])
end
batching(true)

# 3) Component paylaşılan tanım
build
p2 = $all_ents.values.find { |e| e.persistent_id == 1002 } || $model.entities.find { |e| e.persistent_id == 1002 }
p2b = $model.entities.find { |e| e.persistent_id == 1005 }
$scan.clear
r = nil
if HAS_RB
  M.mst_read_batch do
    r = [M.pile_qto_infill_children(p2).map(&:persistent_id), M.pile_qto_infill_children(p2b).map(&:persistent_id),
         M.pile_qto_concrete(p2).round(6), M.pile_qto_concrete(p2b).round(6)]
  end
end
t('Component: P2 / P2B aynı tanım tek tarama', $scan.values.sum, 1)
t('Component: sonuçlar (çocuk PID, P2 iç beton YOK = 0, P2B = 9.126)', r, [[2002], [2002], 0.0, V_INFILL.round(6)])

# 4) batch dışı ve yazma batch'i
build
p1 = $model.entities.find { |e| e.persistent_id == 1001 }
$scan.clear
x1 = M.pile_qto_infill_children(p1); x2 = M.pile_qto_infill_children(p1)
t('batch dışı: her çağrı tarar (2 çağrı)', $scan.values.sum, 2)
t('batch dışı: sonuç ve önbellek yok', [x1.map(&:persistent_id), x2.map(&:persistent_id), M.instance_variable_get(:@mst_infill_children_cache)], [[2001], [2001], nil])
$scan.clear
inner = nil
M.mst_scan_batch($model) do
  M.pile_qto_infill_children(p1); M.pile_qto_infill_children(p1)
  inner = M.instance_variable_get(:@mst_infill_children_cache)
  M.send_boq(RecDialog.new)   # yazma batch'ine katılan okuma girişi: okuma bayrağı açılmaz
end
t('yazma batch\'i: her çağrı tarar, önbellek kurulmaz', [$scan.values.sum >= 2, inner], [true, nil])
t('yazma batch\'i: send_boq içinde de önbellek yok (her çağrı tarar)', $scan.values.max.to_i > 1 || $scan.values.sum >= 2, true)

# 5) değişikliğe karşı koruma, geçersiz öğe, temizlik
if HAS_RB
  build
  p1 = $model.entities.find { |e| e.persistent_id == 1001 }
  res = nil
  M.mst_read_batch do
    a = M.pile_qto_infill_children(p1)
    a << :bozuk; a.clear
    b = M.pile_qto_infill_children(p1)
    $all_ents[2001].erase!
    c = M.pile_qto_infill_children(p1)
    res = [b.map(&:persistent_id), c, b.frozen?]
  end
  t('dönen dizi değiştirildi → önbellek bozulmadı; silinen çocuk süzüldü; dönen dizi donmuş değil', res, [[2001], [], false])
  t('batch sonrası önbellek silindi', rb_state, [false, nil, nil])
  build
  err = nil
  begin
    M.mst_read_batch { M.pile_qto_infill_children($model.entities.find { |e| e.persistent_id == 1001 }); raise 'deneme hatası' }
  rescue StandardError => e
    err = e.message
  end
  t('hata: istisna geçti, önbellek ve batch durumu sıfırlandı', [err, rb_state], ['deneme hatası', [false, nil, nil]])
  # iç içe okuma: iç batch dış önbelleği silmez
  build
  p1 = $model.entities.find { |e| e.persistent_id == 1001 }
  $scan.clear
  M.mst_read_batch do
    M.pile_qto_infill_children(p1)
    M.mst_read_batch { M.pile_qto_infill_children(p1) }
    M.pile_qto_infill_children(p1)
  end
  t('iç içe okuma batch\'i: tek tarama', $scan.values.sum, 1)
  # ardışık batch'ler önbellek paylaşmaz
  $scan.clear
  M.mst_read_batch { M.pile_qto_infill_children(p1) }
  M.mst_read_batch { M.pile_qto_infill_children(p1) }
  t('ardışık iki okuma batch\'i: her biri yeniden tarar', $scan.values.sum, 2)
end

puts "\n#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
