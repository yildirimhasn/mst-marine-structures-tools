# Parti H / H4a: K35 (kazık ayrı poz NN kalıcı eşlemesi) ve H4b (yönelim → BK açıklığı) performans ÖLÇÜMÜ — ölçmeden optimizasyon yok.
# Eklenti golden-master sahtesiyle (tools/golden/sketchup_stub.rb) gerçek yükleme sırasıyla yüklenir. SketchUp DIŞI sahte nesne
# ölçümüdür; süreler SketchUp süresi DEĞİLDİR (SketchUp'ta Benchmark.realtime adımı kabul listesindedir).
#  A) pile_boq_expand_rows: n=50/500/2000 kazık × 1 ve 4 AYRI POZ kaynağı × kayıtlı / kayıtsız pile_boq_group_codes_json.
#     Sayılan: pile_boq_group_quantities, pile_boq_codes_stored, prog2_last_period, collect_elements çağrısı; süre (monoton saat).
#  B) boq_rows(true) (Keşif satır üretimi, tam) aynı matriste.
#  C) mst_pile_orientation_bk_openings!: n=200/1000 kazık × 50/200 BK; seçim = 2 kazık ve tüm kazıklar.
# Doğruluk denetimleri (GEÇTİ/KALDI): kayıtlı ↔ kayıtsız satırlar birebir; ölçüm sırasında model yazımı yok (A/B); tekrarlar arası
# çağrı sayısı sabit; C'de güncellenen BK sayısı beklenen. Eşik (kullanıcı kararı) 1 s: aşılırsa yalnız "EŞİK AŞILDI" yazılır,
# çıkış kodunu etkilemez (kod değiştirilmez).
# Kullanim: ruby tools/test/h_h4a_k35_perf.rb <src/marine_structures_tools> [tekrar=3]
require 'json'
require 'digest'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/h_h4a_k35_perf.rb <marine_structures_tools klasoru> [tekrar]'
REP = (ARGV[1] || 3).to_i
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze
LIMIT = 1.0

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end

# çağrı sayaçları (M extend self → iç çağrılar da tekil yöntemden geçer)
$cnt = Hash.new(0)
%i[pile_boq_group_quantities pile_boq_codes_stored prog2_last_period collect_elements mst_bk_connected_piles mst_bk_set_net_formwork!
   mst_vk_contact_index mst_pile_index_by_id].each do |nm|
  next unless M.respond_to?(nm)
  orig = M.method(nm)
  M.define_singleton_method(nm) { |*a, &b| $cnt[nm] += 1; orig.call(*a, &b) }
end
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
SECTIONS = [[914.0, 14.0], [1016.0, 16.0], [1220.0, 20.0], [1422.0, 22.0]].freeze
CLASSES = %w[C30/37 C35/45].freeze
SRC1 = %w[PILE_STEEL].freeze
SRC4 = %w[PILE_STEEL PILE_RINGS PILE_DRIVING PILE_INFILL].freeze

def pile_attrs(i, extra = {})
  d, th = SECTIONS[i % SECTIONS.size]
  { 'element_type' => 'steel_pipe_pile', 'pile_id' => "P#{i}", 'diameter_mm' => d, 'thickness_mm' => th,
    'length_m' => 30.0, 'actual_length_m' => 30.0, 'top_elevation_m' => 1.2, 'bottom_elevation_m' => -28.8,
    'seabed_elevation_m' => -8.0, 'steel_grade' => 'S355', 'project' => 'H4A', 'ano' => 'A1', 'structure' => 'ISKELE',
    'element_uid' => "MST-H4A-P#{i}", 'upper_ring_enabled' => '1', 'infill_enabled' => '1',
    'infill_concrete_volume_m3' => 8.0, 'infill_concrete_class' => CLASSES[(i / SECTIONS.size) % CLASSES.size] }.merge(extra)
end

def set_model(ents)
  $model = Sketchup::Model.new
  $model.entities = Sketchup::Entities.new(ents)
  $model.entities.parent = $model
  ents.each { |e| e.parent = $model.entities }
  $all_ents = ents.each_with_object({}) { |e, h| h[e.persistent_id] = e }
end

# A/B modeli: n kazık; kaynaklar AYRI POZ; 0.51.4'ten gelen hakediş geçmişi (1 dönem, etiketli satırlar) — kayıtsız durumda tohum yolu
def build_k35(n, srcs, stored)
  set_model((0...n).map { |i| Sketchup::Group.new(100_000 + i, pile_attrs(i)) })
  srcs.each { |k| $model.set_attribute(D, "pile_boq_mode_#{k}", 'separate') }
  hist_rows = srcs.flat_map do |k|
    M.pile_boq_group_quantities(k).each_with_index.map { |(lab, _q, _ps, _g), j| { 'key' => "#{k}@ÖBF-#{k}-#{format('%02d', j + 1)}", 'name' => "Kalem (#{lab})" } }
  end
  $model.set_attribute(M::PROGRESS_DICT, M::PROGRESS_HISTORY_KEY, JSON.generate([{ 'no' => 1, 'rows' => hist_rows }]))
  M.pile_boq_codes_persist!($model) if stored
  base = srcs.map { |k| { code: "ÖBF-#{k}", name: "Kalem #{k}", unit: 'x', source: k, quantity: M.pile_boq_group_quantities(k).sum { |g| g[1] }, unit_price: 100.0, status: 'MODEL' } }
  $cnt.clear; $writes = []
  base
end

def rows_sig(rows)
  a = rows.map { |r| [r[:code], r[:name], r[:quantity].round(9), r[:status]] }
  "#{a.size} satır, imza #{Digest::SHA256.hexdigest(Marshal.dump(a))[0, 16]}"
end

def measure(rep)
  times = []; counts = nil; res = nil; same_counts = true; writes = 0
  rep.times do
    prep = yield(:prep)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    res = yield(:run, prep)
    times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    c = $cnt.dup
    same_counts &&= (counts.nil? || counts == c)
    counts ||= c
    writes += $writes.size
  end
  ts = times.sort
  [ts.first, ts[ts.size / 2], counts, res, same_counts, writes]
end

thr = []
sigs = {}
puts "ÖLÇÜM ORTAMI ruby=#{RUBY_VERSION} platform=#{RUBY_PLATFORM} tekrar=#{REP} (sahte nesne; SketchUp süresi değildir)"
[50, 500, 2000].each do |n|
  [SRC1, SRC4].each do |srcs|
    [false, true].each do |stored|
      tag = format('n=%d kaynak=%d kayıt=%s', n, srcs.size, stored ? 'var' : 'yok')
      # A) pile_boq_expand_rows
      mn, md, c, res, sc, w = measure(REP) do |ph, prep|
        ph == :prep ? build_k35(n, srcs, stored) : M.pile_boq_expand_rows(prep.map(&:dup))
      end
      puts format('ÖLÇÜM K35 expand_rows %s: pile_boq_group_quantities=%d pile_boq_codes_stored=%d prog2_last_period=%d collect_elements=%d satır=%d süre_min=%.3f s süre_medyan=%.3f s',
                  tag, c[:pile_boq_group_quantities], c[:pile_boq_codes_stored], c[:prog2_last_period], c[:collect_elements], res.size, mn, md)
      thr << "K35 expand_rows #{tag} medyan #{format('%.3f', md)} s" if md > LIMIT
      t("H4a A #{tag}: tekrarlar arası çağrı sayısı sabit, ölçümde yazım yok", [sc, w], [true, 0])
      sigs["A #{n} #{srcs.size} #{stored}"] = rows_sig(res)
      # B) boq_rows(true) — Keşif satır üretimi (tam)
      mn, md, c, res, sc, w = measure(REP) do |ph, _prep|
        ph == :prep ? build_k35(n, srcs, stored) : M.boq_rows(true)
      end
      split = res.select { |r| r[:split_mode] == 'separate' }
      puts format('ÖLÇÜM K35 boq_rows %s: pile_boq_group_quantities=%d pile_boq_codes_stored=%d prog2_last_period=%d collect_elements=%d satır=%d ayrı_poz_satır=%d süre_min=%.3f s süre_medyan=%.3f s',
                  tag, c[:pile_boq_group_quantities], c[:pile_boq_codes_stored], c[:prog2_last_period], c[:collect_elements], res.size, split.size, mn, md)
      thr << "K35 boq_rows #{tag} medyan #{format('%.3f', md)} s" if md > LIMIT
      t("H4a B #{tag}: tekrarlar arası çağrı sayısı sabit, ölçümde yazım yok", [sc, w], [true, 0])
      sigs["B #{n} #{srcs.size} #{stored}"] = rows_sig(split)
    end
    t("H4a A n=#{n} kaynak=#{srcs.size}: kayıtlı ↔ kayıtsız satırlar birebir (kod, ad, miktar, durum)", sigs["A #{n} #{srcs.size} true"], sigs["A #{n} #{srcs.size} false"])
    t("H4a B n=#{n} kaynak=#{srcs.size}: kayıtlı ↔ kayıtsız ayrı poz satırları birebir", sigs["B #{n} #{srcs.size} true"], sigs["B #{n} #{srcs.size} false"])
    t("H4a A n=#{n} kaynak=#{srcs.size}: ayrı poz satır sayısı (kaynak × kesit grubu > kaynak)", sigs["A #{n} #{srcs.size} true"].to_i > srcs.size, true)
  end
end

# C) mst_pile_orientation_bk_openings! — kazıklar 1:6 eğik, BK'larda kayıtlı açıklık 2 daire → her bağlı BK güncellenir
CIRCLE = Math::PI / 4 * 1.016**2
def bk_faces
  [['BOTTOM', true, 12.0], ['LONG_SIDE', true, 10.0], ['LONG_SIDE', true, 10.0], ['END_FACE', true, 1.2], ['END_FACE', true, 1.2], ['TOP_OR_CONTACT', false, 12.0]].map do |ty, fw, a|
    f = Sketchup::Face.new(nil, 'formwork_type' => ty, 'formwork' => fw); f.area_m2 = a; f.normal = Geom::Vector3d.new(0, 0, ty == 'BOTTOM' ? -1 : 1); f
  end
end
def build_bk(n, nb)
  piles = (0...n).map { |i| Sketchup::Group.new(100_000 + i, pile_attrs(i, 'diameter_mm' => 1016.0, 'orientation_mode' => 'BATTERED', 'batter_ratio' => 1.0 / 6.0)) }
  bks = (0...nb).map do |j|
    a = piles[(2 * j) % n]; b = piles[(2 * j + 1) % n]
    g = Sketchup::Group.new(200_000 + j, 'element_type' => 'head_beam', 'head_beam_id' => "BK#{j}", 'ano' => 'A1',
                                         'connected_pile_persistent_ids' => "#{a.persistent_id},#{b.persistent_id}", 'connected_pile_ids' => "#{a.get_attribute(D, 'pile_id')},#{b.get_attribute(D, 'pile_id')}",
                                         'pile_opening_area_m2' => 2 * CIRCLE, 'formwork_net_area_m2' => 34.4 - 2 * CIRCLE)
    g.entities = bk_faces
    g
  end
  set_model(piles + bks)
  [piles, bks]
end
[[200, 50], [200, 200], [1000, 50], [1000, 200]].each do |n, nb|
  { 'seçim=2' => ->(ps) { ps.first(2) }, 'seçim=tüm' => ->(ps) { ps } }.each do |sl, pick|
    exp = nil
    mn, md, c, res, sc, = measure(REP) do |ph, prep|
      if ph == :prep
        ps, bks = build_bk(n, nb)
        sel = pick.(ps); sp = sel.map(&:persistent_id)
        exp = bks.count { |b| b.get_attribute(D, 'connected_pile_persistent_ids').split(',').map(&:to_i).any? { |x| sp.include?(x) } }
        $cnt.clear; $writes = []
        sel
      else
        M.mst_pile_orientation_bk_openings!(prep, $model)
      end
    end
    tag = format('kazık=%d BK=%d %s', n, nb, sl)
    puts format('ÖLÇÜM H4b bk_openings %s: collect_elements=%d mst_bk_connected_piles=%d mst_bk_set_net_formwork!=%d mst_vk_contact_index=%d güncellenen_BK=%d uyarı=%d süre_min=%.3f s süre_medyan=%.3f s',
                tag, c[:collect_elements], c[:mst_bk_connected_piles], c[:mst_bk_set_net_formwork!], c[:mst_vk_contact_index], res['updated'].size, res['warnings'].size, mn, md)
    thr << "H4b bk_openings #{tag} medyan #{format('%.3f', md)} s" if md > LIMIT
    t("H4a C #{tag}: güncellenen BK = seçili kazığa bağlı BK, uyarı yok, çağrı sayısı sabit", [res['updated'].size, res['warnings'].size, sc], [exp, 0, true])
  end
end

puts "EŞİK #{LIMIT} s (kullanıcı kararı; sahte nesne süresi): #{thr.empty? ? 'aşılmadı' : 'EŞİK AŞILDI — ' + thr.join('; ')}"
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
