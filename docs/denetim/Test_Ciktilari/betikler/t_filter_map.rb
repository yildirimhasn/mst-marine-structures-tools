# filter_map (0.51.3) <-> map.compact (0.51.4) esdegerlik testi (SketchUp disinda).
# Kullanim: ruby t_filter_map.rb <0513_klasor> <0514_klasor>   (klasor = .../marine_structures_tools)
old_dir, new_dir = ARGV
rd = ->(d, f) { File.read(File.join(d, f), encoding: 'UTF-8') }
grab = ->(src, sig, term) { a = src.index(sig) or abort("bulunamadi: #{sig}"); src[a..src.index(term, a) + term.length - 1] }
$ok = 0; $bad = 0
t = ->(label, got, exp) { g = got == exp; g ? $ok += 1 : $bad += 1; puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}#{g ? '' : ": #{got.inspect} != #{exp.inspect}"}" }

# 0) Genel fark: filter_map false'u da atar, map.compact atmaz
arr = [1, nil, false, 2]
puts "Bilgi: #{arr.inspect}.filter_map{|x|x} = #{arr.filter_map { |x| x }.inspect}; map{|x|x}.compact = #{arr.map { |x| x }.compact.inspect}"

# 1) HeadBeamEditor.change_list
module ControlledEditor; FIELDS = { 'head_beam' => { 'length_m' => 'Boy', 'width_m' => 'Genişlik', 'height_m' => 'Yükseklik' } }.freeze; end
old_hb = rd.(old_dir, 'headbeam_editor.rb')
expr = old_hb[/changes=(values\.filter_map\{.*?\} unless same\})/, 1] or abort 'eski filter_map ifadesi bulunamadi'
class HBOld; end
HBOld.class_eval("def change_list(h,values)\n#{expr}\nend")
class HBNew; end
HBNew.class_eval(grab.(rd.(new_dir, 'headbeam_editor.rb'), 'def change_list(h,values)', "\n   end\n"))
class HBRaw; end # ham blok ciktisi (compact oncesi) -> false var mi?
HBRaw.class_eval("def change_list(h,values)\n#{expr.sub('filter_map', 'map')}\nend")
rng = Random.new(42)
cls = %w[C25/30 C30/37 C35/45]
false_seen = 0
500.times do |i|
  base = { 'length_m' => rng.rand(1..5).to_f, 'width_m' => rng.rand(1..3).to_f, 'height_m' => [1.0, '1.0', nil][rng.rand(3)], 'concrete_class' => [cls.sample(random: rng), nil][rng.rand(2)] }
  vals = { 'length_m' => [base['length_m'], base['length_m'] + 1e-12, base['length_m'] + 0.5][rng.rand(3)], 'width_m' => base['width_m'].to_f,
           'height_m' => [1.0, 2.0][rng.rand(2)], 'concrete_class' => cls.sample(random: rng) }
  a = HBOld.new.change_list(base, vals); b = HBNew.new.change_list(base, vals)
  false_seen += HBRaw.new.change_list(base, vals).count { |x| x == false }
  if a != b then t.("change_list durum #{i}", b, a); break end
end
t.('change_list 500 rastgele durumda eski=yeni', $bad, 0)
t.('change_list blok çıktısında false yok (yalnız Hash/nil)', false_seen, 0)

# 2) HealthHistory.compare_reports
def load_hh(dir, klass)
  src = File.read(File.join(dir, 'health_history.rb'), encoding: 'UTF-8')
  g = ->(sig) { a = src.index(sig) or abort("bulunamadi #{sig}"); src[a..src.index("\n   end\n", a) + 7] }
  %w[def\ bag_difference def\ finding_key def\ quantity_changed? def\ compare_reports].each do |sig|
    body = sig == 'def finding_key' ? src[/^\s*def finding_key.*$/] : g.(sig)
    klass.class_eval(body)
  end
  klass.class_eval('def validate_report(_);end')
end
class HHOld; end; class HHNew; end
load_hh(old_dir, HHOld); load_hh(new_dir, HHNew)
mkq = ->(r) { { value: [1.0, 2.0, 2.0000001, nil][r.rand(4)], state: %w[calculated missing invalid estimated][r.rand(4)], unit: 't', method: %w[a b][r.rand(2)], engine_version: '2-tb1' } }
mkrec = lambda do |r, i|
  q = {}; %i[steel_t rebar_t concrete_m3].each { |k| q[k] = mkq.(r) if r.rand < 0.7 }
  q.each_value { |v| v[:value] ||= 0.0 unless %w[missing invalid].include?(v[:state]) }
  { key: "k#{i}", uid: ["u#{i}", '', "u#{i}"][r.rand(3)], id: "P#{i}", label: 'L', type: 'steel_pipe_pile', state: 'checked', geometry: r.rand(2),
    checks: Array.new(r.rand(3)) { { severity: 'w', category: 'c', code: "C#{r.rand(3)}", message: 'm' } }, quantities: q }
end
diffs = 0
300.times do |i|
  r = Random.new(i)
  before = { created_at: 'a', version: 'x', records: Array.new(r.rand(1..6)) { |j| mkrec.(r, j) } }
  after = Marshal.load(Marshal.dump(before)); after[:created_at] = 'b'
  after[:records].each { |rec| rec[:quantities].each_value { |v| v[:value] = v[:value].to_f + [0, 0, 1e-9, 0.5][r.rand(4)] if v[:value] } ; rec[:quantities].delete(:rebar_t) if r.rand < 0.2 }
  after[:records] << mkrec.(r, 99) if r.rand < 0.3
  a = HHOld.new.compare_reports(before, after); b = HHNew.new.compare_reports(before, after)
  diffs += 1 if a != b
end
t.('compare_reports 300 rastgele rapor çiftinde eski=yeni', diffs, 0)
# quantity_changed? false/true dondurur; blok {..} if ... -> nil veya Hash; false asla blok sonucu olmaz
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
