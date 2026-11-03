# V2 (03.11.2026) — Prekast NCR-003 (kullanıcı kararı: seçenek A + prekast tip adı güncellemesi).
#  A  Kontrollü Düzenleme formu Prekast sayfasında: Çalışma Alanı "Elemanı Düzenle" (normal / kanal prekastı) formu Prekast sayfasında açar,
#     doğru alt sekme (PD / PK) seçilir; Kapat sayfada kalır; açılış hatası Çalışma Alanı durumunda görünür.
#  T  Geometri değişince precast_type_id / precast_type, BK'ye bağlı boyutlandırmayla AYNI kuralla (mst_precast_new_type_name) güncellenir:
#     aynı tür + temel tip + ölçüde tip varsa o ad, yoksa "<temel>-B…" varyantı; temel tip precast_base_type_id. Önizlemede gösterilir.
#     Yalnız beton sınıfı değişirse ad değişmez; tip adı olmayan elemana yazım yok; diğer elemanlar değişmez; tek işlem.
# Kanıt düzeyi: sahte nesne + sahte DOM. Yeniden kurma (rebuild_flat_precast_parametric) ve profil doğrulaması TAKLİT edilir
# (sahte grupta yüz yok); gerçek geometri ve SketchUp davranışı KANITLANMAZ.
# Kullanim: ruby tools/test/v2_prekast_ncr003.rb <src/marine_structures_tools>
require 'stringio'
require 'tmpdir'
require 'open3'
require_relative '../golden/sketchup_stub'
DIR = File.expand_path(ARGV[0] || abort('kullanim: ruby tools/test/v2_prekast_ncr003.rb <marine_structures_tools klasoru>'))
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(DIR, 'main.rb')
$stderr = $stderr_keep
require_relative '../golden/fixture'
require_relative 'r_helper'
M = MAG::MarineStructuresTools
$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 260]} (beklenen #{exp.inspect[0, 260]})"
end

# --- taklitler: profil doğrulaması ve parametrik yeniden kurma (yalnız öznitelik; metraj l·w·h ve kalıp bayraklarıyla) ---
M::ControlledEditor.define_singleton_method(:validate_geometry) { |_e, _t| true }
M.define_singleton_method(:rebuild_flat_precast_parametric) do |e, v|
  l = v['length_m'].to_f; w = v['width_m'].to_f; h = v['height_m'].to_f
  %w[length_m width_m height_m].each { |k| e.set_attribute(D, k, v[k].to_f) }
  e.set_attribute(D, 'concrete_volume_m3', l * w * h); e.set_attribute(D, 'formwork_area_m2', l * w + 2 * l * h)
  e.set_attribute(D, 'concrete_class', v['concrete_class'])
end
M::QuantityService.define_singleton_method(:value) do |e, k|
  { concrete_m3: 'concrete_volume_m3', formwork_m2: 'formwork_area_m2' }.key?(k) ? e.get_attribute(D, { concrete_m3: 'concrete_volume_m3', formwork_m2: 'formwork_area_m2' }[k], 0).to_f : 0.0
end

PD_ATTRS = { 'precast_family' => 'PD', 'length_m' => 5.0, 'width_m' => 1.0, 'height_m' => 0.4, 'concrete_volume_m3' => 2.0, 'formwork_area_m2' => 9.0 }.freeze
def setup_pd(name1: 'PD-01', extra: [])
  d = r_setup
  pc = r_target
  PD_ATTRS.each { |k, v| pc.set_attribute(D, k, v) }
  pc.set_attribute(D, 'precast_type_id', name1) if name1
  pc.set_attribute(D, 'precast_type', name1) if name1
  # PD2: aynı eski tip ve ölçü (tip paylaşılır)
  pd2 = $all_ents[6002]
  (PD_ATTRS.merge('precast_type_id' => 'PD-01', 'precast_type' => 'PD-01', 'element_uid' => 'MST-GOLD-PD2')).each { |k, v| pd2.set_attribute(D, k, v) }
  extra.each { |id, attrs| g = Sketchup::Group.new(id, attrs); $model.entities << g; g.parent = $model.entities; $all_ents[id] = g }
  $model.ops.clear
  [d, pc, pd2]
end
def edit(d, pc, cls, dims)
  d.out.clear
  M.controlled_editor_preview(JSON.generate(r_req(pc, cls, dims)), d)
  pv = d.out.grep(/\AcontrolledEditorPreview\(/).last
  err = d.out.grep(/controlledEditorError/)
  pend = M.instance_variable_get(:@controlled_editor_pending)
  return [pv, err, nil] unless pend
  d.out.clear; $model.ops.clear
  M.controlled_editor_apply(JSON.generate('token' => pend[:token]), d); r_timers
  [pv, err + d.out.grep(/controlledEditorError/), $model.ops.dup]
end
OP = [[:start, 'MST Kontrollü Eleman Düzenleme'], [:commit]].freeze
attrs = ->(e) { %w[precast_type_id precast_type precast_base_type_id].map { |k| e.get_attribute(D, k, nil) } }

# T1: yeni ölçü (6 m) kayıtlı tipte yok → PD-01-B
d, pc, pd2 = setup_pd
pv, err, ops = edit(d, pc, 'C35/45', 'length_m' => 6.0)
t('T1 hata yok, tek işlem', [err, ops], [[], OP])
t('T1 önizleme tip değişikliğini gösterir (PD-01 → PD-01-B)', [pv.to_s.include?('Prekast tipi'), pv.to_s.include?('PD-01-B')], [true, true])
t('T1 düzenlenen eleman: precast_type_id / precast_type = PD-01-B, temel tip PD-01', attrs.(pc), %w[PD-01-B PD-01-B PD-01])
t('T1 aynı tipi paylaşan PD2 değişmez', attrs.(pd2), ['PD-01', 'PD-01', nil])
t('T1 element_uid korunur', pc.get_attribute(D, 'element_uid', ''), 'MST-GOLD-PD1')

# T2: yeni ölçüde aynı temel tipten kayıtlı tip var (PD-01-C, 6.5 m) → o ad
d, pc, pd2 = setup_pd(extra: [[6201, PD_ATTRS.merge('element_type' => 'flat_precast', 'length_m' => 6.5, 'precast_type_id' => 'PD-01-C', 'precast_type' => 'PD-01-C',
                                                    'precast_base_type_id' => 'PD-01', 'element_uid' => 'MST-V2-PD3')]])
pv, err, ops = edit(d, pc, 'C35/45', 'length_m' => 6.5)
t('T2 aynı temel tip + ölçüdeki kayıtlı tip adı alınır (PD-01-C)', [err, ops, attrs.(pc)], [[], OP, %w[PD-01-C PD-01-C PD-01]])

# T3: yalnız beton sınıfı → tip adı değişmez
d, pc, pd2 = setup_pd
pv, err, ops = edit(d, pc, 'C40/50', {})
t('T3 yalnız beton sınıfı: tip adı aynı, önizlemede tip satırı yok', [err, ops, attrs.(pc), pv.to_s.include?('Prekast tipi')], [[], OP, ['PD-01', 'PD-01', nil], false])

# T4: tip adı olmayan eleman → yazım yok
d, pc, pd2 = setup_pd(name1: nil)
pv, err, ops = edit(d, pc, 'C35/45', 'length_m' => 6.0)
t('T4 tip adı olmayan elemana tip adı yazılmaz', [err, ops, attrs.(pc)], [[], OP, [nil, nil, nil]])

# T5 (rapor 27/K2): yalnız fiziksel kimlik precast_id var (tip adı yok) → tip adı üretilmez
d, pc, pd2 = setup_pd(name1: nil)
pc.set_attribute(D, 'precast_id', 'PD-07')
pv, err, ops = edit(d, pc, 'C35/45', 'length_m' => 6.0)
t('T5 precast_id fiziksel kimlikten tip adı üretilmez', [err, ops, attrs.(pc), pc.get_attribute(D, 'precast_id', nil)], [[], OP, [nil, nil, nil], 'PD-07'])

# T6 (rapor 27/K3): milimetre altı değişiklik (ölçü anahtarı aynı) → tip adı aynı
d, pc, pd2 = setup_pd
pv, err, ops = edit(d, pc, 'C35/45', 'length_m' => 5.0004)
t('T6 mm altı boy değişikliği: tip adı PD-01 kalır, önizlemede tip satırı yok', [err, ops, attrs.(pc), pv.to_s.include?('Prekast tipi')], [[], OP, ['PD-01', 'PD-01', nil], false])

# --- A: arayüz (sahte DOM) ---
open_pd = { model_token: 't1', keys: ['k9'], id: 'PD1', label: 'Normal prekast', concrete_class: 'C35/45', classes: %w[C30/37 C35/45], note: nil,
            fields: [{ key: 'length_m', label: 'Boy (m)', value: 5 }, { key: 'width_m', label: 'Genişlik (m)', value: 1 }, { key: 'height_m', label: 'Kalınlık (m)', value: 0.4 }] }
open_pk = open_pd.merge(id: 'PK1', label: 'Kanal prekastı', fields: [{ key: 'length_m', label: 'Boy (m)', value: 5 }, { key: 'inner_width_m', label: 'İç genişlik (m)', value: 0.4 }])
rec = { key: 'k9', id: 'PD1', uid: 'u9', type: 'flat_precast', label: 'Normal prekast', fields: { project: 'P', system: 'ISKELE', structure: 'ANO-01', axis: 'X-01' }, quantities: {}, issues: [] }
page = "document.querySelector('.page.on').id"
steps = [
  { label: 'yer', js: "var s=document.getElementById('controlledEditor');[!!s.closest('#precast'),!!s.closest('#project_workspace')]" },
  { label: 'ws', js: "mstShowPage('project_workspace');projectWorkspaceLoaded(#{JSON.generate(model_token: 't1', records: [rec], selection: { keys: ['k9'] })});#{page}" },
  { label: 'başlık', js: "document.getElementById('pwEdit').title" },
  { label: 'aç pd', js: "controlledEditorLoaded(#{JSON.generate(open_pd)});[#{page},document.getElementById('controlledEditor').hidden,document.getElementById('precast').getAttribute('data-pctab')]" },
  { label: 'kapat', js: "document.getElementById('ceClose').click();[#{page},document.getElementById('controlledEditor').hidden]" },
  { label: 'aç pk', js: "mstShowPage('project_workspace');controlledEditorLoaded(#{JSON.generate(open_pk)});[#{page},document.getElementById('precast').getAttribute('data-pctab')]" },
  { label: 'hata', js: "controlledEditorReset();mstShowPage('project_workspace');controlledEditorError('Yalnız özgün grup geometrisi düzenlenebilir.');[#{page},document.getElementById('pwStatus').textContent]" }
]
out, st = Dir.mktmpdir('mst_v2') do |dd|
  f = File.join(dd, 'steps.json'); File.binwrite(f, JSON.generate(steps))
  Open3.capture2e('node', File.join(__dir__, 'u1_dom.js'), DIR, f)
end
r = out.lines.grep(/\ARES /).map { |l| JSON.parse(l.sub('RES ', '')) }.each_with_object({}) { |x, h| h[x['label']] = x }
v = ->(k) { (r[k] || {})['value'] }
t('A node sahte DOM çalıştı (yükleme hatasız)', [st.success?, (r['__load__'] || {})['err']], [true, []])
t('A form Prekast sayfasında (Çalışma Alanı içinde değil)', v.('yer'), [true, false])
t('A Elemanı Düzenle ipucu Prekast sayfasını söyler', v.('başlık').to_s.include?('Prekast sayfasında'), true)
t('A normal prekast: Prekast sayfası açılır, form görünür, PD sekmesi', v.('aç pd'), ['precast', false, 'pd'])
t('A Kapat: Prekast sayfasında kalınır, form gizlenir', v.('kapat'), ['precast', true])
t('A kanal prekastı: PK sekmesi', v.('aç pk'), %w[precast pk])
t('A açılış hatası Çalışma Alanı durumunda görünür', v.('hata'), ['project_workspace', 'Yalnız özgün grup geometrisi düzenlenebilir.'])
r.each { |k, x| next if k == '__load__'; t("node adımı hatasız: #{k}", x['err'], []) }

puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
