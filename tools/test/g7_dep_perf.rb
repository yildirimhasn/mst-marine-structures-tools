# Parti G-b / G7 (kod inceleme #9): stamp_dependency_metadata ve repair_bim_identity — dependency_graph çağrı sayısı ve süre.
# Eklenti golden-master sahtesiyle (tools/golden/sketchup_stub.rb) gerçek yükleme sırasıyla yüklenir; sahte model n=50 ve n=200 öğe.
# Ölçülen: işlem başına dependency_graph çağrı sayısı ve süre (monoton saat). Kabul: çağrı sayısı n'den bağımsız (≤ 4).
# Eşdeğerlik: işlem sonunda tüm öznitelikler (öğeler + model) ve stamp'ın yazım sırası (pid, sözlük, anahtar, değer) imza olarak
# yazdırılır. İkinci argüman (karşılaştırma kaynağı) verilirse aynı betik o kaynakla alt süreçte çalıştırılır ve imzalar
# karşılaştırılır (stamp: yazım listesi + son durum; repair: son durum).
# Kullanim: ruby tools/test/g7_dep_perf.rb <src/marine_structures_tools> [<karşılaştırma kaynağı>]
require 'digest'
require 'open3'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/g7_dep_perf.rb <marine_structures_tools klasoru> [<karsilastirma klasoru>]'
ref = ARGV[1]
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze
FIXED = Time.at(1_800_000_000)
class << Time; def now; FIXED; end; end   # UID ve geçmiş zaman damgası belirlenimli olsun

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end

# n öğelik sahte model: birim = kazık, BK (kazığa bağlı), döşeme (BK'ya oturur), bordür (döşemeye bağlı), prekast (iki BK arası).
# repair için her 10. birimde döşemenin kopyası (aynı element_uid ve deck_id) ve UID'siz bir kronman.
def build(n, with_copies)
  $model = Sketchup::Model.new
  $pid_seq = 100_000
  ents = []
  units = n / 5
  bks = []
  units.times do |i|
    p = Sketchup::Group.new(10_000 + i, 'element_type' => 'steel_pipe_pile', 'pile_id' => "P#{i}", 'element_uid' => "MST-#{10_000 + i}-1",
                                        'diameter_mm' => 1016.0, 'thickness_mm' => 16.0, 'length_m' => 30.0, 'project' => 'G7', 'ano' => 'A1')
    b = Sketchup::Group.new(20_000 + i, 'element_type' => 'head_beam', 'head_beam_id' => "BK#{i}", 'element_uid' => "MST-#{20_000 + i}-1",
                                        'connected_pile_ids' => "P#{i}", 'length_m' => 10.0, 'width_m' => 1.2, 'height_m' => 1.0, 'project' => 'G7', 'ano' => 'A1')
    d = Sketchup::Group.new(30_000 + i, 'element_type' => 'deck_slab', 'deck_id' => "D#{i}", 'element_uid' => "MST-#{30_000 + i}-1",
                                        'support_pids' => (20_000 + i).to_s, 'project' => 'G7', 'ano' => 'A1')
    c = Sketchup::Group.new(40_000 + i, 'element_type' => 'curb', 'curb_id' => "TR#{i}", 'element_uid' => "MST-#{40_000 + i}-1",
                                        'parent_deck_id' => "D#{i}", 'project' => 'G7', 'ano' => 'A1')
    ents.push(p, b, d, c)
    bks << b
    next unless with_copies && (i % 10).zero?
    ents << Sketchup::Group.new(60_000 + i, 'element_type' => 'deck_slab', 'deck_id' => "D#{i}", 'element_uid' => "MST-#{30_000 + i}-1",
                                            'support_pids' => (20_000 + i).to_s, 'project' => 'G7', 'ano' => 'A1')
    ents << Sketchup::Group.new(70_000 + i, 'element_type' => 'crown_wall', 'project' => 'G7', 'ano' => 'A1')
  end
  # UID'siz fiziksel kaplama (D0'a bağlı): onarımdaki ensure_uid yan etkisi eşdeğerlikte görünür olsun
  ents << Sketchup::Group.new(80_000, 'element_type' => 'deck_topping', 'parent_deck_id' => 'D0', 'project' => 'G7', 'ano' => 'A1')
  units.times do |i|
    l = bks[i]; r = bks[(i + 1) % units]
    ents << Sketchup::Group.new(50_000 + i, 'element_type' => 'flat_precast', 'precast_id' => "PD#{i}", 'element_uid' => "MST-#{50_000 + i}-1",
                                            'support_left_pid' => l.persistent_id, 'support_right_pid' => r.persistent_id, 'project' => 'G7', 'ano' => 'A1')
  end
  $model.entities = Sketchup::Entities.new(ents)
  $model.entities.parent = $model
  ents.each { |e| e.parent = $model.entities }
  $all_ents = ents.each_with_object({}) { |e, h| h[e.persistent_id] = e }
  ents
end

def state_sig(ents)
  rows = ([$model] + ents.sort_by(&:persistent_id)).map do |e|
    attrs = e.attribute_dictionaries.compact.flat_map { |dd| dd.keys.sort.map { |k| [dd.name, k, dd[k]] } }
    [e.persistent_id, e.name, attrs]
  end
  Digest::SHA256.hexdigest(Marshal.dump(rows))[0, 16]
end

$dg = 0
orig_dg = M.method(:dependency_graph)
M.define_singleton_method(:dependency_graph) { |*a| $dg += 1; orig_dg.call(*a) }
M.define_singleton_method(:model_audit) { nil }                 # onarım sonundaki Model Kontrolü ölçüm dışı
M.define_singleton_method(:send_dependency_analysis) { |*_a| nil }
$vals = {}
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
sigs = {}
[50, 200].each do |n|
  # stamp_dependency_metadata
  ents = build(n, false)
  wlog = []
  Sketchup::Entity.class_eval { alias_method :g7_set, :set_attribute unless method_defined?(:g7_set) }
  Sketchup::Entity.send(:define_method, :set_attribute) { |d, k, v| ($g7_wlog ||= []) << [persistent_id, d, k, v]; g7_set(d, k, v) }
  $g7_wlog = []; $dg = 0
  t0 = clock.()
  M.stamp_dependency_metadata
  dt = clock.() - t0
  wlog = $g7_wlog
  puts format('ÖLÇÜM stamp_dependency_metadata n=%d öğe=%d: dependency_graph çağrısı=%d süre=%.3f s işlem=%s', n, ents.size, $dg, dt, $model.ops.map(&:first).inspect)
  $vals["stamp#{n}"] = $dg
  sigs["stamp#{n}_yazim"] = Digest::SHA256.hexdigest(Marshal.dump(wlog))[0, 16]
  sigs["stamp#{n}_son"] = state_sig(ents)
  t("G7 stamp n=#{n}: tek işlem (start=1 commit=1 abort=0)", [$model.ops.count { |o| o[0] == :start }, $model.ops.count { |o| o[0] == :commit }, $model.ops.count { |o| o[0] == :abort }], [1, 1, 0])
  t("G7 stamp n=#{n}: işlem sonunda bağımlılık bilgisi güncel (dependency_changes boş)", M.dependency_changes($model).size, 0)
  t("G7 stamp n=#{n}: dependency_graph çağrısı n'den bağımsız (≤ 4)", $dg <= 4, true)

  # repair_bim_identity
  ents = build(n, true)
  $dg = 0; $ui_msgs = []
  t0 = clock.()
  M.repair_bim_identity
  dt = clock.() - t0
  puts format('ÖLÇÜM repair_bim_identity n=%d öğe=%d: dependency_graph çağrısı=%d süre=%.3f s işlem=%s', n, ents.size, $dg, dt, $model.ops.map(&:first).inspect)
  $vals["repair#{n}"] = $dg
  sigs["repair#{n}_son"] = state_sig(ents)
  t("G7 repair n=#{n}: tek işlem (start=1 commit=1 abort=0)", [$model.ops.count { |o| o[0] == :start }, $model.ops.count { |o| o[0] == :commit }, $model.ops.count { |o| o[0] == :abort }], [1, 1, 0])
  t("G7 repair n=#{n}: işlem sonunda bağımlılık bilgisi güncel (dependency_changes boş)", M.dependency_changes($model).size, 0)
  t("G7 repair n=#{n}: kopya döşemeler yeni UID aldı", ents.select { |e| e.persistent_id >= 60_000 && e.persistent_id < 70_000 }.all? { |e| e.get_attribute(D, 'element_uid', '').end_with?('-R') }, true)
  t("G7 repair n=#{n}: dependency_graph çağrısı n'den bağımsız (≤ 4)", $dg <= 4, true)
  tp = ents.find { |e| e.persistent_id == 80_000 }
  t("G7 repair n=#{n}: UID'siz kaplama döşemesine bağlandı ve UID aldı (ensure_uid yan etkisi korunur)", [tp.get_attribute(D, 'element_uid', '').start_with?('MST-80000-'), tp.get_attribute(D, 'dependency_parent_ids', nil)], [true, 'D0'])
  t("G7 repair n=#{n}: dependency_schema son durumu 2.2 (ara 2.1 yazımı son durumda görünmez)", ents.select { |e| e.get_attribute(D, 'dependency_schema', nil) }.map { |e| e.get_attribute(D, 'dependency_schema') }.uniq, ['2.2'])
end
sigs.each { |k, v| puts "İMZA #{k}=#{v}" }

if ref
  out, st = Open3.capture2e('ruby', __FILE__, ref)
  theirs = out.scan(/^İMZA (\S+)=(\h+)$/).to_h
  puts "karşılaştırma kaynağı=#{ref} (çıkış #{st.exitstatus})"
  out.each_line { |l| puts "  [ref] #{l}" if l.start_with?('ÖLÇÜM') }
  sigs.each { |k, v| t("G7 eşdeğerlik #{k} (karşılaştırma kaynağıyla birebir)", v, theirs[k]) }
end
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
