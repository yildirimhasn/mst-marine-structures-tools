# V1 (03.11.2026) — rapor 25 / 26 bulgu düzeltmeleri (kullanıcı kararı: önerilerin hepsi; kod karakter kümesi harf/rakam/-/_/./boşluk).
#  25/1  C seçeneği: hedef kod (to) eski bir yapı koduysa ya da kullanılıyorsa (sahipsiz eleman) ret, işlem açılmaz.
#  25/2  Kullanılan yapının Aks Yöneticisi'nden silinmesi sunucuda onay ister (yük: removed_used_structures).
#  25/3  mst_code_usage: jet grout vb. her MST öğesi, iç içe aks görseli, prekast "X-01↔X-02" aks ayırıcısı.
#  25/4  show_boq_engine: boq_refresh tek kez (T('boq') zaten refreshBOQ çağırır).
#  25/9  Model Kontrolü iletileri erişilemeyen "Eleman Düzenleyici"yi göstermez.
#  25/10 Çalışma Alanı BK düzenleme bekleyişi yalnız ilk seçim yanıtına bağlı.
#  25/11 + karar: yeni yapı / aks kodu karakter kümesi JS ve Ruby'de aynı (görünen ad kuralı değişmez).
#  26/1b Çalışma Alanı ağacı yapı düğümünü koda göre kurar (etiket metni birleştirmez).
# Kanıt düzeyi: sahte nesne + sahte DOM. SketchUp içi davranış KANITLANMAZ.
# Kullanim: ruby tools/test/v1_bulgu_25_26.rb <src/marine_structures_tools>
require 'stringio'
require 'tmpdir'
require 'open3'
require_relative '../golden/sketchup_stub'
DIR = File.expand_path(ARGV[0] || abort('kullanim: ruby tools/test/v1_bulgu_25_26.rb <marine_structures_tools klasoru>'))
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(DIR, 'main.rb')
$stderr = $stderr_keep
require_relative '../golden/fixture'
require_relative 'r_helper'
require_relative 'u_views'
M = MAG::MarineStructuresTools
$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 260]} (beklenen #{exp.inspect[0, 260]})"
end
MAIN = File.read(File.join(DIR, 'main.rb'), encoding: 'UTF-8')

def add_ent(id, attrs, parent = $model.entities)
  g = Sketchup::Group.new(id, attrs)
  parent << g; g.parent = parent; $all_ents[id] = g
  g
end
def setup2
  r_setup(names: false)
  uv_main_dialog
  $model.set_attribute(D, 'system_structures_json', '{"DOLFEN":["BD-01"],"ISKELE":["ANO-01","ANO-02"],"RIHTIM":["RIHTIM-01"]}')
  $writes = []
end
def save(pl)
  $model.ops.clear; $msgs.clear
  ax = r_axis_open
  ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(pl))
  [$model.ops, $msgs.dup]
end
COMMIT = [[:start, 'MST Aks Kaydı'], [:commit]].freeze

# ---------- 25/1: hedef kod denetimi ----------
setup2
pl = r_axis_payload
pl['systems']['ISKELE'] = %w[ANO-01]
pl['grids'] = pl['grids'].reject { |k, _| k.start_with?('ISKELE::') }.merge('ISKELE::ANO-01' => pl['grids']['ISKELE::ANO-02'])
pl['active']['ISKELE'] = 'ANO-01'
pl['code_changes'] = [{ 'system' => 'ISKELE', 'from' => 'ANO-02', 'to' => 'ANO-01' }]
pl['removed_used_structures'] = ['ISKELE::ANO-01']
ops, msgs = save(pl)
t('25/1 kazıklı ANO-01 silinip boş ANO-02 kodu ANO-01 yapılır → ret, işlem yok', [ops, msgs.any? { |m| m.include?('ANO-01') && m.include?('hedef kod') }], [[], true])
t('25/1 ret sonrası yapı listesi değişmedi', M.mst_structures_for_system('ISKELE', $model), %w[ANO-01 ANO-02])

setup2
add_ent(1101, gf_pile_attrs('P71', 'structure' => 'ANO-05', 'ano' => 'ANO-05', 'system' => 'ISKELE', 'element_uid' => 'MST-V1-P71'))
pl = r_axis_payload
pl['systems']['ISKELE'] = %w[ANO-01 ANO-05]
pl['grids'] = pl['grids'].reject { |k, _| k == 'ISKELE::ANO-02' }.merge('ISKELE::ANO-05' => pl['grids']['ISKELE::ANO-02'])
pl['code_changes'] = [{ 'system' => 'ISKELE', 'from' => 'ANO-02', 'to' => 'ANO-05' }]
ops, msgs = save(pl)
t('25/1 hedef kod sahipsiz elemanda kullanılıyor (ANO-05, 1 kazık) → ret, işlem yok', [ops, msgs.any? { |m| m.include?('ANO-05') && m.include?('1 eleman') }], [[], true])

setup2
pl = r_axis_payload
pl['systems']['ISKELE'] = %w[ANO-01 ANO-03]
pl['grids'] = pl['grids'].reject { |k, _| k == 'ISKELE::ANO-02' }.merge('ISKELE::ANO-03' => pl['grids']['ISKELE::ANO-02'])
pl['code_changes'] = [{ 'system' => 'ISKELE', 'from' => 'ANO-02', 'to' => 'ANO-03' }]
ops, msgs = save(pl)
t('25/1 boş hedef kod (ANO-02 → ANO-03) kabul: tek işlem, ileti yok', [ops, msgs], [COMMIT, []])

# ---------- 25/2: kullanılan yapı silme ----------
setup2
pl = r_axis_payload
pl['systems']['ISKELE'] = %w[ANO-02]
pl['grids'].delete('ISKELE::ANO-01'); pl['active']['ISKELE'] = 'ANO-02'
ops, msgs = save(pl)
t('25/2 kazıklı ANO-01 onaysız silinmez: işlem yok, Türkçe ileti', [ops, msgs.any? { |m| m.include?('ANO-01') && m.include?('silin') }], [[], true])
t('25/2 onaysız silme sonrası liste aynı', M.mst_structures_for_system('ISKELE', $model), %w[ANO-01 ANO-02])
pl['removed_used_structures'] = ['ISKELE::ANO-01']
ops, msgs = save(pl)
t('25/2 önizlemede onaylanan silme kaydedilir: tek işlem', [ops, msgs], [COMMIT, []])
setup2
pl = r_axis_payload
pl['systems']['ISKELE'] = %w[ANO-01]
pl['grids'].delete('ISKELE::ANO-02')
ops, msgs = save(pl)
t('25/2 kullanılmayan ANO-02 onaysız silinir: tek işlem', [ops, msgs], [COMMIT, []])
ax_html = r_axis_open.html.to_s
t('25/2 Aks Yöneticisi yükü removed_used_structures taşır', ax_html.include?('removed_used_structures:'), true)

# ---------- 25/3: kullanım taraması kapsamı ----------
setup2
base = M.mst_code_usage($model)
add_ent(1102, { 'element_type' => 'jet_grout', 'ano' => 'ANO-07', 'element_uid' => 'MST-V1-JG' })
outer = add_ent(1103, {})
vis = Sketchup::Group.new(1104, { 'element_type' => 'axis_grid_visual', 'ano' => 'ANO-08' })
outer.entities = [vis]; $all_ents[1104] = vis
add_ent(1105, { 'element_type' => 'flat_precast', 'ano' => 'ANO-09', 'axis' => 'X-01↔X-02', 'element_uid' => 'MST-V1-PD' })
u = M.mst_code_usage($model)
t('25/3 jet grout ano kodu kullanılıyor sayılır', u['elements']['ANO-07'], 1)
t('25/3 iç içe aks görseli sayılır', u['visuals']['ANO-08'], 1)
t('25/3 prekast "X-01↔X-02" iki aks olarak sayılır', [u['axes'][['ANO-09', 'x', 'X-01']], u['axes'][['ANO-09', 'x', 'X-02']], u['axes'].key?(['ANO-09', 'x', 'X-01↔X-02'])], [1, 1, false])
t('25/3 mevcut sayımlar değişmez (ANO-01, A1)', [u['elements']['ANO-01'], u['elements']['A1']], [base['elements']['ANO-01'], base['elements']['A1']])

# ---------- 25/4: Keşif Motoru tek yenileme ----------
src = MAIN[/def show_boq_engine\n.*?\nend\n/m].to_s
t('25/4 show_boq_engine ayrıca refreshBOQ çağırmaz', [src.empty?, src.include?('refreshBOQ')], [false, false])

# ---------- 25/9: Eleman Düzenleyici iletileri ----------
t('25/9 Model Kontrolü iletisinde "Eleman Düzenleyici" yok', MAIN.scan(/add_issue\.call\([^\n]*Eleman Düzenleyici/).size, 0)

# ---------- karar + 25/11: kod karakter kümesi ----------
setup2
[['ANO (3)', false], ['ANO,3', false], ['ANO-03.A_1 B', true]].each do |code, ok|
  pl = r_axis_payload
  pl['systems']['ISKELE'] = %w[ANO-01 ANO-02] + [code]
  pl['grids']["ISKELE::#{code}"] = pl['grids']['ISKELE::ANO-02']
  ops, msgs = save(pl)
  t("Kod kümesi Ruby: yeni yapı kodu '#{code}' #{ok ? 'kabul' : 'ret'}", [ops == COMMIT, ok ? msgs : msgs.any? { |m| m.include?('izin verilmeyen karakter') }], [ok, ok ? [] : true])
  setup2
end
pl = r_axis_payload
pl['structure_names'] = { 'ANO-02' => 'Liman (Kuzey) #2' }
ops, msgs = save(pl)
t('Görünen ad kuralı değişmedi: "Liman (Kuzey) #2" kabul', [ops, msgs], [COMMIT, []])

# JS: Aks Yöneticisi sayfasındaki kod / ad denetimi (sayfanın gerçek işlevleri node'da)
ax_html = r_axis_open.html.to_s
script = ax_html[%r{<script>\s*\(function\(\)\{\s*'use strict';(.*)\}\)\(\);\s*</script>}m, 1].to_s
fns = %w[clean checkName checkCode].map { |n| script[/function #{n}\(.*?\n/].to_s }.join
consts = script[/var BADCH=.*?;\n/].to_s + script[/var CODECH=.*?;\n/].to_s
js = <<~JS
  #{consts}#{fns}
  function tr(f){try{f();return 'ok'}catch(e){return 'err:'+e.message}}
  console.log(JSON.stringify([tr(function(){checkCode('ANO (3)',40,'Yapı kodu')}),tr(function(){checkCode('ANO,3',40,'Yapı kodu')}),tr(function(){checkCode('A@=%',20,'Aks kodu')}),
    tr(function(){checkCode('ANO-03.A_1 B',40,'Yapı kodu')}),tr(function(){checkName('Liman (Kuzey) #2',40,'Görünen ad')})]));
JS
out, st = Dir.mktmpdir('mst_v1') { |d| f = File.join(d, 'k.js'); File.write(f, js); Open3.capture2e('node', f) }
res = (JSON.parse(out.lines.last) rescue [out])
t('Kod kümesi JS: ( , @ = % ret; "ANO-03.A_1 B" ve görünen ad kabul', [st.success?, res.map { |r| r.start_with?('ok') }], [true, [false, false, false, true, true]])
t('Kod kümesi JS: yapı kodu, yeni yapı kodu ve aks kodu checkCode kullanır',
  [script.include?("checkCode(el('structCode').value"), script.include?("checkCode(el('newStructure').value"), script.include?("checkCode(v,20,'Aks kodu')")], [true, true, true])
bk = MAIN[/add_action_callback\('mstBKAddProjectStructure'\)(?:.*?\n){4}/].to_s
t('25/11 mstBKAddProjectStructure ortak kod denetimini kullanır', bk.include?('mst_code_validate'), true)

# ---------- 26/1b + 25/10: Çalışma Alanı (sahte DOM) ----------
rec = lambda do |k, id, type, st, lab|
  { key: k, id: id, uid: "u-#{k}", type: type, label: type == 'head_beam' ? 'Başlık kirişi' : 'Çelik boru kazık', structure_label: lab,
    fields: { project: 'P', system: 'DOLFEN', structure: st, axis: 'X-01' }, quantities: {}, issues: [] }
end
records = [rec.('k1', 'P1', 'steel_pipe_pile', 'BD-01', 'LİMAN (BD-01)'), rec.('k2', 'P2', 'steel_pipe_pile', 'LİMAN (BD-01)', nil),
           rec.('k3', 'HB1', 'head_beam', 'BD-01', 'LİMAN (BD-01)')]
load = "projectWorkspaceLoaded(#{JSON.generate(model_token: 't1', records: records, selection: { keys: [] })})"
steps = [
  { label: 'tree', js: "var r=MSTProjectWorkspace.build(#{JSON.generate(records)});var s=r.children[0].children[0].children;[s.length,s.map(function(n){return n.keys.length}).sort()]" },
  { label: 'open', js: "window.REC=#{JSON.generate(records)};window.SEL=function(k){var s=MSTProjectWorkspace.summarize(REC.filter(function(r){return k.indexOf(r.key)>=0}));s.keys=k;return s};" \
                       "mstShowPage('project_workspace');#{load};document.querySelector('.page.on').id" },
  { label: 'sel k3', js: "projectWorkspaceSelection(SEL(['k3']),'t1');1" },
  { label: 'edit', click: '#pwEdit' },
  { label: 'other sel', js: "projectWorkspaceSelection(SEL(['k1']),'t1');document.querySelector('.page.on').id" },
  { label: 'late sel', js: "projectWorkspaceSelection(SEL(['k3']),'t1');document.querySelector('.page.on').id" },
  { label: 'edit2', click: '#pwEdit' },
  { label: 'own sel', js: "projectWorkspaceSelection(SEL(['k3']),'t1');document.querySelector('.page.on').id" }
]
out, st = Dir.mktmpdir('mst_v1') do |d|
  f = File.join(d, 'steps.json'); File.binwrite(f, JSON.generate(steps))
  Open3.capture2e('node', File.join(__dir__, 'u1_dom.js'), DIR, f)
end
r = out.lines.grep(/\ARES /).map { |l| JSON.parse(l.sub('RES ', '')) }.each_with_object({}) { |x, h| h[x['label']] = x }
t('node sahte DOM çalıştı (yükleme hatasız)', [st.success?, (r['__load__'] || {})['err']], [true, []])
t('26/1b kod "LİMAN (BD-01)" ile görünen adı "LİMAN (BD-01)" olan BD-01 ayrı düğüm', (r['tree'] || {})['value'], [2, [1, 2]])
t('25/10 BK bekleyişi: araya giren başka seçim yanıtı bekleyişi iptal eder', [(r['other sel'] || {})['value'], (r['late sel'] || {})['value']], %w[project_workspace project_workspace])
t('25/10 BK kendi seçim yanıtıyla BK sayfasını açar', (r['own sel'] || {})['value'], 'beam')
%w[open sel\ k3 edit other\ sel late\ sel edit2 own\ sel].each { |k| x = r[k] || {}; t("node adımı hatasız: #{k}", x['err'], []) }

puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
