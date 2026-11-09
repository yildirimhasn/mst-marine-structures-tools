# KP1b (ADR-0515-K2, docs/duzeltme/37; 09.11.2026) — Kanal Prekastı formunun canlı önizleme hesabı (ui.html MST_CH_SECTION bloğu, JS)
# Ruby kesit modülüyle (channel_section.rb) aynı sonucu verir mi: geçerlilik metinleri, alan, yükseklik, profil, U-eşdeğeri, U ölçüleri, ön ayarlar.
# JS blok Node ile çalıştırılır (DOM yok). Kullanım: ruby tools/test/kp1b_section_js.rb <marine_structures_tools klasoru>
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../golden/sketchup_stub'
DIR = File.expand_path(ARGV[0].to_s); ARGV[0] or abort 'kullanim: ruby tools/test/kp1b_section_js.rb <marine_structures_tools klasoru>'
require 'stringio'
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(DIR, 'main.rb')
$stderr = $stderr_keep
M = MAG::MarineStructuresTools
$ok = 0; $bad = 0
def t(label, got, exp)
  if got == exp then $ok += 1; puts "GEÇTİ  #{label}"
  else $bad += 1; puts "KALDI  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
  end
end

html = File.read(File.join(DIR, 'ui.html'), encoding: 'UTF-8')
b = html.index('/* MST_CH_SECTION_BEGIN'); e = html.index('/* MST_CH_SECTION_END */')
t('ui.html MST_CH_SECTION bloğu bulundu', !b.nil? && !e.nil? && e > b, true)
exit 1 unless b && e
js_block = html[b...e]

part = ->(on, w, h, o) { { 'on' => on, 'width_m' => w, 'height_m' => h, 'offset_m' => o } }
sec = ->(tot, base, l, m, r, pre = 'OZEL') { { 'v' => 1, 'preset' => pre, 'total_width_m' => tot, 'base_m' => base, 'left' => l, 'mid' => m, 'right' => r } }
cases = [
  M.mst_ch_default,
  sec.(1.80, 0.20, part.(true, 0.20, 0.60, 0.0), part.(false, 0.15, 0.30, 0.75), part.(true, 0.20, 0.60, 0.0)),
  sec.(1.80, 0.20, part.(false, 0.20, 0.60, 0.0), part.(true, 0.15, 0.30, 0.75), part.(true, 0.20, 0.60, 0.0)),
  sec.(1.80, 0.20, part.(false, 0.20, 0.60, 0.0), part.(false, 0.15, 0.30, 0.75), part.(true, 0.20, 0.60, 0.0)),
  sec.(1.80, 0.20, part.(false, 0.20, 0.60, 0.0), part.(false, 0.15, 0.30, 0.75), part.(true, 0.90, 0.60, 0.0)),
  sec.(1.20, 0.20, part.(true, 0.20, 0.60, 0.10), part.(true, 0.15, 0.40, 0.525), part.(true, 0.20, 0.50, 0.05)),
  sec.(1.50, 0.25, part.(true, 0.25, 0.70, 0.0), part.(false, 0.0, 0.0, 0.0), part.(true, 0.25, 0.70, 0.0), 'U'),
  # geçersizler: çıkıntısız, taşma, çakışma, bitişik, sıfır ölçü, sıfır toplam / taban, negatif
  sec.(1.20, 0.20, part.(false, 0.2, 0.6, 0), part.(false, 0.15, 0.3, 0.525), part.(false, 0.2, 0.6, 0)),
  sec.(1.20, 0.20, part.(true, 0.2, 0.6, 1.1), part.(false, 0.15, 0.3, 0.525), part.(true, 0.2, 0.6, 0)),
  sec.(1.20, 0.20, part.(true, 0.4, 0.6, 0), part.(true, 0.15, 0.3, 0.3), part.(true, 0.2, 0.6, 0)),
  sec.(1.20, 0.20, part.(true, 0.2, 0.6, 0), part.(true, 0.15, 0.3, 0.2), part.(false, 0.2, 0.6, 0)),
  sec.(1.20, 0.20, part.(true, 0.0, 0.6, 0), part.(false, 0.15, 0.3, 0.525), part.(true, 0.2, -0.1, 0)),
  sec.(0.0, 0.0, part.(true, 0.2, 0.6, 0), part.(false, 0.15, 0.3, 0.525), part.(true, 0.2, 0.6, 0))
]
ruby_out = cases.map do |s|
  v = M.mst_ch_valid(s)
  r = { 'valid' => v, 'uEquiv' => M.mst_ch_u_equiv?(s) }
  if v.empty?
    r['area'] = M.mst_ch_area(s); r['height'] = M.mst_ch_height(s); r['profile'] = M.mst_ch_profile(s)
    r['uDims'] = M.mst_ch_u_dims(s) if r['uEquiv']
  end
  r['presets'] = %w[U L UU K].map { |pn| pr = M.mst_ch_preset(s, pn); %w[left mid right].map { |k| pr[k]['on'] } + [pr['preset']] }
  r
end

js = <<JS
var window = {}; var module = { exports: {} };
#{js_block}
var S = window.mstChSection || module.exports;
var cases = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
var out = cases.map(function (s) {
  var v = S.valid(s); var r = { valid: v, uEquiv: S.uEquiv(s) };
  if (v.length === 0) { r.area = S.area(s); r.height = S.height(s); r.profile = S.profile(s); if (r.uEquiv) r.uDims = S.uDims(s); }
  r.presets = ['U', 'L', 'UU', 'K'].map(function (pn) { var p = S.preset(JSON.parse(JSON.stringify(s)), pn); return [p.left.on, p.mid.on, p.right.on, p.preset]; });
  return r;
});
process.stdout.write(JSON.stringify(out));
JS
js_out = nil
Dir.mktmpdir do |d|
  File.write(File.join(d, 'kp1b.js'), js, encoding: 'UTF-8')
  File.write(File.join(d, 'cases.json'), JSON.generate(cases))
  o, er, st = Open3.capture3('node', File.join(d, 'kp1b.js'), File.join(d, 'cases.json'))
  t('JS blok Node ile hatasız çalıştı', [st.success?, er.strip], [true, ''])
  js_out = (JSON.parse(o) rescue nil)
end
exit 1 unless js_out
norm = ->(x) { x.is_a?(Float) ? x.round(12) : x.is_a?(Array) ? x.map { |y| norm.(y) } : x.is_a?(Hash) ? x.transform_values { |y| norm.(y) } : x }
cases.each_with_index do |_, i|
  r = norm.(ruby_out[i]); j = norm.(js_out[i])
  %w[valid uEquiv area height profile uDims presets].each do |k|
    next unless r.key?(k) || j.key?(k)
    t("vaka #{i + 1} #{k}: JS = Ruby", j[k], r[k])
  end
end
puts "\nKP1b: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
