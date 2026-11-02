# P2 / P3 (0.51.5 donma düzeltmesi, ekran yenilemesi):
#  P2 — salt okuma giriş noktaları mst_read_batch ile tek model taraması yapar (mevcut mst_scan_batch önbelleği).
#  P3 — mst_structures_for_system / mst_active_structure_for_system yalnız değer farklıysa yazar.
# Eklenti golden-master sahtesiyle (tools/golden/sketchup_stub.rb) gerçek yükleme sırasıyla yüklenir; model tools/golden/fixture.rb
# + 10 ek BK (bağlı kazık PID'leriyle).
# Sınanan:
#  1) Her giriş noktasında tam model taraması (mst_collect_elements_raw, kök = Model) sayısı ≤ 1.
#  2) Çıktı eşdeğerliği: aynı fikstürde batch'li ve batch'siz (mst_read_batch → yalnız yield) çalıştırma — diyaloğa giden JS
#     dizgileri / dönüş değeri, model yazımları (sözlük, anahtar, değer) ve son öznitelik durumu birebir aynı.
#  3) İç içe: açık yazma batch'i (mst_scan_batch) içinde giriş noktası dış batch'i kullanır, durumunu sıfırlamaz; iç içe okuma batch'i.
#  4) Hata: blok hata verirse batch durumu geri yüklenir (kapalı, önbellek boş).
#  5) Kazık dizini okuma batch'inde süre sınırından bağımsız (aynı tarama); batch dışında eski 1,5 s kuralı.
#  6) P3: değer aynıysa mst_workflow_status model yazmaz; ilk durumda yazılan değerler eski kodla aynı.
# Kullanim: ruby tools/test/p2_read_batch.rb <src/marine_structures_tools>
require 'digest'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/p2_read_batch.rb <marine_structures_tools klasoru>'
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

$full = 0
orig_raw = M.method(:mst_collect_elements_raw)
M.define_singleton_method(:mst_collect_elements_raw) do |ents, out|
  $full += 1 if ents.respond_to?(:parent) && ents.parent.is_a?(Sketchup::Model)
  orig_raw.call(ents, out)
end
$audit_dlg = nil
M.define_singleton_method(:mst_html_dialog) { |*_a| $audit_dlg = RecDialog.new }
HAS_RB = M.respond_to?(:mst_read_batch)
ORIG_RB = HAS_RB ? M.method(:mst_read_batch) : nil
def batching(on)
  if on && HAS_RB
    M.define_singleton_method(:mst_read_batch, &ORIG_RB)
  elsif HAS_RB
    M.define_singleton_method(:mst_read_batch) { |*_a, &b| b.call }
  end
end

def build
  golden_build_fixture
  10.times do |i|
    pid = 9000 + i
    b = Sketchup::Group.new(pid, 'element_type' => 'head_beam', 'head_beam_id' => "BKP#{i}", 'length_m' => 10.0, 'width_m' => 1.2,
                                 'height_m' => 1.0, 'bottom_elevation_m' => 1.0, 'top_elevation_m' => 2.0, 'concrete_volume_m3' => 11.85,
                                 'concrete_class' => 'C30/37', 'ano' => 'A1', 'project' => 'GOLDEN',
                                 'connected_pile_persistent_ids' => '1001,1003,1004', 'connected_pile_ids' => 'P1,P3,P4')
    b.entities = gf_bk_faces(true)
    $model.entities << b; b.parent = $model.entities; $all_ents[pid] = b
  end
  M.instance_variable_set(:@mst_pile_idx_cache, nil)
  M.instance_variable_set(:@mst_last_audit, nil)
  $writes = []
  $now = 1_800_000_000.0   # her kurulum aynı saat: ensure_uid zaman damgası iki çalıştırmada aynı olsun
end

def state_sig
  rows = ([$model] + $all_ents.values.sort_by(&:persistent_id)).map do |e|
    [e.persistent_id, e.attribute_dictionaries.compact.flat_map { |dd| dd.keys.sort.map { |k| [dd.name, k, dd[k].to_s] } }]
  end
  Digest::SHA256.hexdigest(Marshal.dump(rows))[0, 16]
end

ENTRIES = {
  'send_boq' => ->(d) { M.send_boq(d) },
  'qto_summary' => ->(d) { M.qto_summary(d) },
  'progress_send' => ->(d) { M.progress_send(d) },
  'prog2_view' => ->(d) { M.boq2_set_view('{"date":""}'); M.progress_send(d) },
  'mst_workflow_status' => ->(d) { d.out << JSON.generate(M.mst_workflow_status) },
  'mst_send_rebar_page' => ->(d) { M.mst_send_rebar_page(d) },
  'project_workspace_refresh' => ->(d) { M.project_workspace_refresh(d) },
  'model_audit' => ->(d) { M.model_audit; d.out.concat($audit_dlg ? $audit_dlg.out : ['dialog yok']) }
}.freeze

def run_entry(name, on)
  build
  batching(on)
  $ui_msgs = []
  d = RecDialog.new
  $full = 0
  w0 = $writes.size
  ENTRIES[name].call(d)
  # model_token = Model#object_id (her kurulumda farklı sahte Model nesnesi) karşılaştırma dışı
  { out: d.out.map { |s| s.gsub(/"model_token":"\d+"/, '"model_token":"*"') }, writes: $writes[w0..].map { |pid, dd, k| [pid, dd, k] }, full: $full, sig: state_sig, msgs: $ui_msgs.dup,
    err: d.out.grep(/Error\(|qtoError|progressError|projectWorkspaceError/).first }
end

puts "mst_read_batch tanımlı: #{HAS_RB}"
ENTRIES.each_key do |name|
  a = run_entry(name, false)
  b = run_entry(name, true)
  t("#{name}: hata iletisi yok", [b[:err], b[:msgs]], [nil, []])
  t("#{name}: diyalog çıktısı batch'li = batch'siz (#{b[:out].sum(&:bytesize)} bayt)", Digest::SHA256.hexdigest(b[:out].join("\n")), Digest::SHA256.hexdigest(a[:out].join("\n")))
  t("#{name}: model yazımları aynı (#{b[:writes].size})", b[:writes], a[:writes])
  t("#{name}: son öznitelik durumu aynı", b[:sig], a[:sig])
  puts "      tam tarama: batch'siz=#{a[:full]} batch'li=#{b[:full]}"
  t("#{name}: tam model taraması ≤ 1", b[:full] <= 1, true)
end
batching(true)

# 3) iç içe
build
d = RecDialog.new
$full = 0
inner_on = nil
M.mst_scan_batch($model) do
  M.send_boq(d)
  inner_on = M.instance_variable_get(:@mst_scan_batch_on)
end
t('iç içe: yazma batch\'i içinde send_boq sonrası dış batch açık kaldı', inner_on, true)
t('iç içe: yazma batch\'i içinde tam tarama ≤ 1', $full <= 1, true)
t('iç içe: yazma batch\'inde okuma bayrağı açılmadı', M.instance_variable_get(:@mst_read_batch_on), nil)
if HAS_RB
  st = nil
  M.mst_read_batch do
    s1 = M.instance_variable_get(:@mst_read_batch_on)
    M.mst_read_batch { M.qto_summary(RecDialog.new) }
    st = [M.instance_variable_get(:@mst_scan_batch_on), M.instance_variable_get(:@mst_read_batch_on) == s1]
  end
  t('iç içe okuma: iç batch dış durumu korudu', st, [true, true])
end
t('batch sonrası kapalı', [M.instance_variable_get(:@mst_scan_batch_on), M.instance_variable_get(:@mst_scan_cache), M.instance_variable_get(:@mst_read_batch_on)], [false, nil, nil])

# 4) hata
if HAS_RB
  err = nil
  begin
    M.mst_read_batch { M.collect_elements($model.entities, []); raise 'deneme hatası' }
  rescue StandardError => e
    err = e.message
  end
  t('hata: istisna dışarı geçti', err, 'deneme hatası')
  t('hata: batch durumu geri yüklendi', [M.instance_variable_get(:@mst_scan_batch_on), M.instance_variable_get(:@mst_scan_cache), M.instance_variable_get(:@mst_read_batch_on)], [false, nil, nil])
  build
  ob = M.method(:boq_rows)
  M.define_singleton_method(:boq_rows) { |*_a| raise 'boq hatası' }
  $ui_msgs = []
  M.send_boq(RecDialog.new)
  M.define_singleton_method(:boq_rows, &ob)
  t('hata: send_boq iletisi gösterildi', $ui_msgs.any? { |m| m.include?('boq hatası') }, true)
  t('hata: send_boq sonrası batch kapalı', [M.instance_variable_get(:@mst_scan_batch_on), M.instance_variable_get(:@mst_read_batch_on)], [false, nil])
end

# 5) kazık dizini
if HAS_RB
  build
  cnt = 0
  oc = M.method(:collect_elements)
  M.define_singleton_method(:collect_elements) { |*a| cnt += 1; oc.call(*a) }
  bk = $all_ents[9000]
  M.mst_read_batch do
    M.mst_bk_connected_piles(bk)
    c1 = cnt
    $now += 10.0
    M.mst_bk_connected_piles(bk)
    t('dizin: okuma batch\'inde 10 s sonra yeniden kurulmadı', cnt, c1)
  end
  c2 = cnt
  M.mst_bk_connected_piles(bk)
  t('dizin: batch dışında batch dizini kullanılmadı (yeniden kuruldu)', cnt, c2 + 1)
  c3 = cnt
  $now += 1.0
  M.mst_bk_connected_piles(bk)
  t('dizin: batch dışında 1,5 s içinde önbellek', cnt, c3)
  $now += 2.0
  M.mst_bk_connected_piles(bk)
  t('dizin: batch dışında 1,5 s sonra yeniden kuruldu', cnt, c3 + 1)
  M.define_singleton_method(:collect_elements, &oc)
end

# 6) P3
build
$writes = []
M.mst_workflow_status
first = $writes.map { |_, _, k| k }
vals = %w[system_structures_json active_structure__ISKELE].map { |k| $model.get_attribute(D, k) }
t('P3 ilk çağrı: eksik değerler yazıldı', first.uniq.sort, %w[active_structure__ISKELE system_structures_json])
t('P3 ilk çağrı: yazılan değerler', vals, ['{"ISKELE":["ANO-01"]}', 'ANO-01'])
$writes = []
M.mst_workflow_status
t('P3 ikinci çağrı (değer aynı): model yazımı yok', $writes.size, 0)
%w[DOLFEN RIHTIM ISKELE].each { |s| M.mst_active_structure_for_system(s) }
$writes = []
%w[DOLFEN RIHTIM ISKELE].each { |s| M.mst_active_structure_for_system(s) }
t('P3 mst_active_structure_for_system tekrar: model yazımı yok', $writes.size, 0)
$model.set_attribute(D, 'active_structure__ISKELE', 'YOK-1')
$writes = []
r = M.mst_active_structure_for_system('ISKELE')
t('P3 geçersiz aktif yapı düzeltilir (eski davranış)', [r, $model.get_attribute(D, 'active_structure__ISKELE'), $writes.size > 0], ['ANO-01', 'ANO-01', true])

puts "\n#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
