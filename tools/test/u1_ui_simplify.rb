# U1 (03.11.2026, entegre sürüm regresyonu; senaryo 1–2) — arayüz sadeleştirme (a5ea937, 7e804c9, c1e3a59, 10e520d):
#  Statik: menüde / araç çubuğunda "Eleman Düzenle" yok; TOOLS[0] = project_workspace; kılavuz g-t1 adımı project_workspace;
#          Keşif / Donatı / Bakım onclick'inde ikinci yenileme yok; askStatus sayfa kimliği gönderir; openPileOverrideDialog yükü structure içerir.
#  Sahte DOM (node, tools/test/u_fakedom.js): ui.html + bütün betikler tarayıcı sırasıyla yüklenir, mst_workflow.js init → buildNav GERÇEKTEN
#          çalışır; menü sırası, mstOpenStep, kılavuz "Bu sayfayı aç", tek yenileme sayaçları, Çalışma Alanı düğmeleri (Modelde Göster,
#          Elemanı Düzenle kazık / BK / PD / kanal, Bağlı Kot, Bağlı Beton Sınıfı, Kapsam Kontrolü, Metrajı Aç, Model Sağlığı, Mesnet,
#          Bağımlılıklar) → sketchup.* çağrıları; kazık ızgarası customAxes'e display_label kopyalanmaz.
#  Ruby (golden sahtesi, gerçek show_dialog): kaldırılan girişlerin geri çağrıları kayıtlı ve çağrılabilir; JS'in gönderdiği istekler gerçek
#          geri çağrılara geri oynatılır; Ruby'nin döndürdüğü betikler ikinci node turunda sayfada hatasız çalışır.
# Kanıt düzeyi: statik + sahte nesne. Gerçek HtmlDialog (Chromium 64), görünüm ve SketchUp seçimi KANITLANMAZ.
# Kullanim: ruby tools/test/u1_ui_simplify.rb <src/marine_structures_tools>
require 'digest'
require 'stringio'
require 'tmpdir'
require 'open3'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/u1_ui_simplify.rb <marine_structures_tools klasoru>'
DIR = File.expand_path(dir)
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
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 220]} (beklenen #{exp.inspect[0, 220]})"
end
def obs(label, v); puts "GÖZLEM #{label}: #{v.inspect[0, 300]}"; end
src = ->(f) { File.binread(File.join(DIR, f)).force_encoding('UTF-8') }
ui = src.('ui.html'); wf = src.('mst_workflow.js'); guide = src.('mst_guide.js'); main = src.('main.rb'); pwjs = src.('project_workspace.js')

# ---------------- 1) Statik ----------------
tabs = ui[%r{<div class="tabs">.*?</div>\s*<div id="mstGlobalContextSpacer"}m].to_s
t('S menü (ui.html .tabs): "Eleman Düzenle" girişi yok', tabs.include?('Eleman Düzenle'), false)
t('S ui.html: hiçbir düğme metni "Eleman Düzenle" değil (Kazık sayfası "✎ Eleman Düzenle" kalktı)', ui.scan(/<button[^>]*>[^<]*Eleman Düzenle\s*</).size, 0)
t('S ui.html: hiçbir onclick T(\'editor\' açmaz', ui.include?("T('editor'"), false)
t('S main.rb: Uzantılar menüsü / araç çubuğunda "Eleman Düzenle" yok', main.scan(/(add_item|UI::Command\.new)\([^)\n]*Eleman Düzenle/).size, 0)
t('S #workspaceNav ui.html\'de var ve Çalışma Alanı\'nı açar', tabs.include?(%q(id="workspaceNav" onclick="T('project_workspace',this);MSTProjectWorkspace.refresh()")), true)
t("S mst_workflow.js TOOLS[0].key == 'project_workspace'", wf[/var TOOLS=\[.*?\{key:'([a-z_]+)'/m, 1], 'project_workspace')
t('S TOOLS içinde editor girişi yok', wf[/var TOOLS=\[.*?\n\];/m].to_s.include?("key:'editor'"), false)
t("S kılavuz g-t1 step:'project_workspace'", guide[/\{id:'g-t1',grp:'[^']*',step:'([a-z_]+)'/, 1], 'project_workspace')
t('S kılavuz "Bu sayfayı aç" mstOpenStep(data-step) çağırır', guide.include?("mstOpenStep(b.getAttribute('data-step'))"), true)
boq_oc = ui.scan(/onclick="(T\('boq'[^"]*)"/).flatten
t("S ui.html T('boq' onclick'lerinde refreshBOQ yok", [boq_oc.size >= 1, boq_oc.grep(/refreshBOQ/)], [true, []])
t('S T() içinde boq yenilemesi tek yerde (if(id===\'boq\')refreshBOQ())', ui.scan("if(id==='boq')refreshBOQ()").size, 1)
t('S Donatı BIM onclick yalnız T(\'rebar\',this)', wf[/rebar\.setAttribute\('onclick',"([^"]*)"\)/, 1], "T('rebar',this)")
t('S Model Bakımı onclick yalnız T(\'maint\',this)', wf[/maint\.setAttribute\('onclick',"([^"]*)"\)/, 1], "T('maint',this)")
t('S askStatus açık sayfa kimliğini gönderir', wf.include?("var pg=document.querySelector('.page.on');sketchup.workflow_status(pg?pg.id:'');"), true)
t('S openPileOverrideDialog yükü structure içerir', ui[/function openPileOverrideDialog\(i\)\{.*?\n\}/m].to_s.include?("structure:window.currentPileStructure||''"), true)
t('S Çalışma Alanı JS→Ruby çağrı adları', pwjs.scan(/sketchup\.([a-z_]+)\(/).flatten.uniq.sort,
  %w[dependency_analysis elevation_sync material_change pile_load_selected_for_edit project_workspace_action project_workspace_refresh scoped_model_health])
wa = ui.index('<div id="project_workspace" class="page on">').to_i; wsui = ui[wa...(ui.index('id="pwDeps"', wa) || wa)].to_s
t('S Çalışma Alanı araç çubuğu: Model Sağlığı + Mesnet onclick', [wsui.include?('onclick="sketchup.model_health()"'), wsui.include?('onclick="sketchup.relationship_audit()"')], [true, true])
t('S Bağımlılıklar bölümü (pwDeps / pwDepRun) ui.html\'de', [ui.include?('id="pwDeps"'), ui.include?('id="pwDepRun"')], [true, true])

# ---------------- 2) Ruby: gerçek show_dialog (sahte HtmlDialog) ----------------
d0 = r_setup(names: true)
hd = Class.new(RDlg) { def initialize(*_a, **_k); super(); end }
UI.send(:remove_const, :HtmlDialog) if UI.const_defined?(:HtmlDialog, false)
UI.const_set(:HtmlDialog, hd); hd.const_set(:STYLE_DIALOG, 0)
$msgs = []
UI.define_singleton_method(:messagebox) { |*a| $msgs << a.first.to_s; 6 }
M.instance_variable_set(:@d, nil)
err = begin; M.show_dialog; nil; rescue StandardError => e; "#{e.class}: #{e.message}"; end
t('R show_dialog sahte HtmlDialog ile hatasız (tüm geri çağrılar kaydedildi)', err, nil)
d = M.instance_variable_get(:@d)
names = %w[element_info editor_selection dependency_analysis editor_preview project_workspace_refresh project_workspace_action mstBKLoadSelectedEdit
           pile_load_selected_for_edit elevation_sync material_change scoped_model_health model_health relationship_audit workflow_status
           controlled_editor_preview controlled_editor_apply controlled_editor_cancel dependency_stamp pile_load_central_grid pile_open_override qto_summary boq_refresh]
t('R kaldırılan girişlerin ve Çalışma Alanı işlemlerinin geri çağrıları kayıtlı', names.reject { |n| d.cb.key?(n) }, [])
# JS'in çağırdığı her sketchup.X (Çalışma Alanı + gizli Eleman Düzenleyici + BK / kazık düzenleme) kayıtlı
js_calls = (pwjs.scan(/sketchup\.([A-Za-z_]+)\(/).flatten + %w[editor_selection editor_preview element_info mstBKLoadSelectedEdit]).uniq
t('R Çalışma Alanı JS çağrılarının hepsi kayıtlı', js_calls.reject { |n| d.cb.key?(n) }, [])

key = ->(pid) { JSON.generate([pid]) }
token = $model.object_id.to_s
out_since = ->(n) { d.out[n..-1] }
call = lambda do |name, *args|
  n = d.out.size; $msgs.clear
  e = begin; d.cb[name].call(nil, *args); nil; rescue StandardError => x; "#{x.class}: #{x.message[0, 160]}"; end
  [e, out_since.(n), $msgs.dup]
end
sel = ->(*pids) { $model.selection.clear; pids.each { |p| $model.selection.add($all_ents[p]) } }

e, o, = call.('project_workspace_refresh')
loaded = o.grep(/\AprojectWorkspaceLoaded\(/).last
t('R project_workspace_refresh → projectWorkspaceLoaded', [e, !loaded.nil?], [nil, true])
TARGETS = { 'kazık P1' => 1001, 'BK1' => 4001, 'PD1' => 6001, 'kanal PK1' => 6003 }.freeze
selscript = {}
TARGETS.each do |lbl, pid|
  e, o, = call.('project_workspace_action', JSON.generate('model_token' => token, 'keys' => [key.(pid)], 'zoom' => false, 'edit' => false))
  selscript[lbl] = o.grep(/\AprojectWorkspaceSelection\(/).last
  t("R seçim isteği (#{lbl}) → projectWorkspaceSelection, model seçimi", [e, !selscript[lbl].nil?, $model.selection.to_a.map(&:persistent_id)], [nil, true, [pid]])
end
sel.(4001)
e, o, = call.('dependency_analysis')
dep_bk = o.grep(/\AsetDependencyAnalysis\(/).last
t('R dependency_analysis (BK1 seçili) → setDependencyAnalysis(ok)', [e, dep_bk.to_s.include?('"ok":true'), dep_bk.to_s.include?('"root_id":"BK1"')], [nil, true, true])
e, o, = call.('editor_selection')
ed_sel = o.grep(/\AsetEditorSelection\(/).last
# BİLİNEN KUSUR adayı (ayrı raporlanır): send_editor_selection tanımsız editor_payload çağırır (872d3a3 ve d5fcfca'da da aynı);
# yalnız gizli #editor sayfasının "Seçimi Yenile" düğmesinden erişilir. Beklenti değiştirilmez: hata KALDI olarak görünür.
obs('editor_selection: editor_payload tanımlı mı', M.respond_to?(:editor_payload, true))
t('R editor_selection (BK1) → setEditorSelection + setDependencyAnalysis [gizli Eleman Düzenleyici yolu]', [e,!ed_sel.nil?, o.grep(/\AsetDependencyAnalysis\(/).size], [nil, true, 1])
e, o, m = call.('mstBKLoadSelectedEdit')
bk_loaded = o.grep(/\AmstBKEditLoaded\(/).last
t('R mstBKLoadSelectedEdit (BK1) → mstBKEditLoaded, ileti yok', [e, !bk_loaded.nil?, m], [nil, true, []])
sel.(1001)
e, o, m = call.('pile_load_selected_for_edit')
pile_loaded = o.grep(/\AmstPileSelectionLoaded\(/).last
t('R pile_load_selected_for_edit (P1) → mstPileSelectionLoaded (count 1)', [e, pile_loaded.to_s.include?('"count":1'), m], [nil, true, []])
e, o, m = call.('element_info')
t('R element_info (P1 seçili) hatasız (bilgi penceresi / ileti)', [e, m.grep(/hata|Hata|yüklenemedi/)], [nil, []])
e, o, m = call.('pile_load_central_grid')
grid = o.grep(/\AloadCentralGridIntoPile\(/).last
t('R pile_load_central_grid → loadCentralGridIntoPile (display_label + structure_label)', [e, grid.to_s.include?('"display_label":"Kıyı Aksı"'), grid.to_s.include?('"structure_label":"Ana İskele (ANO-01)"')], [nil, true, true])

# ---------------- 3) Node turu 1: sayfa + tıklamalar ----------------
def node_run(steps)
  Dir.mktmpdir('mst_u1') do |tmp|
    f = File.join(tmp, 'steps.json'); File.binwrite(f, JSON.generate(steps))
    out, st = Open3.capture2e('node', File.join(__dir__, 'u1_dom.js'), DIR, f)
    res = out.lines.grep(/\ARES /).map { |l| JSON.parse(l.sub('RES ', '')) }
    puts out.lines.reject { |l| l.start_with?('RES ') }.first(20).map { |l| "  node| #{l}" }.join
    [res, st.success?]
  end
end
calls_of = ->(r, n) { r['calls'].select { |c| c[0] == n } }
steps = [
  { label: 'menu', js: "Array.prototype.slice.call(document.querySelector('.tabs').children).map(function(x){return [x.className.indexOf('nav-section')>=0?'S':'B',x.id,x.textContent.trim()]})" },
  { label: 'nav_qto', clickNav: "T('qto'" },
  { label: 'openStep', js: "mstOpenStep('project_workspace')" },
  { label: 'nav_guide', clickNav: "T('guide'" },
  { label: 'guide_go', js: "var b=document.querySelector('.gd-go[data-step=\"project_workspace\"]');b?(b.click(),'tıklandı'):'yok'" },
  { label: 'nav_boq', clickNav: "T('boq'" },
  { label: 'nav_rebar', clickNav: "T('rebar'" },
  { label: 'nav_maint', clickNav: "T('maint'" },
  { label: 'nav_ws', clickNav: "T('project_workspace'" },
  { label: 'loaded', js: "#{loaded};document.getElementById('pwStatus').textContent" }
]
TARGETS.each_key do |lbl|
  steps << { label: "sel #{lbl}", js: "#{selscript[lbl]};[document.getElementById('pwEdit').disabled,document.getElementById('pwEdit').textContent]" }
  steps << { label: "show #{lbl}", click: '#pwShow' }
  steps << { label: "edit #{lbl}", click: '#pwEdit' }
  if lbl == 'BK1'
    steps << { label: 'bk response', js: "#{selscript[lbl]};[document.getElementById('mstBKEditStatus').textContent, typeof mstBKMode!=='undefined'?mstBKMode:null]" }
  end
  if lbl == 'kazık P1'
    steps << { label: 'pile editor', js: 'projectWorkspaceOpenPileEditor()' }
  end
  steps << { label: "back #{lbl}", clickNav: "T('project_workspace'" }
  steps << { label: "reload #{lbl}", js: "#{loaded};''" }
end
steps += [
  { label: 'sel PD1 again', js: "#{selscript['PD1']};['pwElevation','pwMaterial','pwHealth','pwQTO','pwDepRun'].map(function(i){return [i,document.getElementById(i).disabled]})" },
  { label: 'elevation', click: '#pwElevation' },
  { label: 'material', click: '#pwMaterial' },
  { label: 'health', click: '#pwHealth' },
  { label: 'model_health', click: '#project_workspace button[onclick="sketchup.model_health()"]' },
  { label: 'relationship', click: '#project_workspace button[onclick="sketchup.relationship_audit()"]' },
  { label: 'sel BK1 dep', js: "#{selscript['BK1']};document.getElementById('pwDepRun').disabled" },
  { label: 'deprun', click: '#pwDepRun' },
  { label: 'depresp', js: "#{dep_bk};document.getElementById('pwDepStatus').textContent" },
  { label: 'qto', click: '#pwQTO' },
  { label: 'editor hidden', js: "[document.getElementById('editor')!==null, document.querySelectorAll('.tabs button').filter(function(b){return (b.getAttribute('onclick')||'').indexOf(\"T('editor'\")>=0}).length]" },
  (ed_sel ? { label: 'editor sel', js: "#{ed_sel};document.getElementById('ed_id').value" } : { label: 'editor sel', js: 'null' }),
  { label: 'editor preview', js: "applyEditor('selected')" },
  { label: 'grid', js: "#{grid};JSON.stringify(customAxes)" },
  { label: 'grid labels', js: 'mstGridAxisText(0)+"|"+mstGridPointText(0,0)' },
  { label: 'override', js: 'openPileOverrideDialog(0)' }
]
res, ok = node_run(steps)
R = res.map { |r| [r['label'], r] }.to_h
t('N node turu 1 tamamlandı (çıkış 0, tüm adımlar)', [ok, res.size], [true, steps.size + 1])
ld = R['__load__'] || {}
t('N ui.html + betikler sahte DOM\'da hatasız yüklendi (init dahil)', ld['err'], [])
menu = (R['menu'] || {})['value'] || []
ia = menu.index { |x| x[0] == 'S' && x[2] == 'ARAÇLAR' }
t('N buildNav: ARAÇLAR bölümünün ilk düğmesi #workspaceNav "Çalışma Alanı"', ia && menu[ia + 1], ['B', 'workspaceNav', 'Çalışma Alanı'])
t('N buildNav: ARAÇLAR sırası', ia && menu[ia + 1..-1].map { |x| x[2] }, ['Çalışma Alanı', 'Aksesuarlar', 'Model Bakımı', 'Ayarlar', 'Kullanma Kılavuzu'])
t('N buildNav: menüde "Eleman Düzenle" yok, bölüm başlıkları yalnız İŞ AKIŞI / ARAÇLAR', [menu.count { |x| x[2].include?('Eleman Düzenle') }, menu.select { |x| x[0] == 'S' }.map { |x| x[2] }], [0, ['İŞ AKIŞI', 'ARAÇLAR']])
t('N ilk açılışta Çalışma Alanı açık ve menüde seçili', [ld['calls'].to_a.include?(['project_workspace_refresh']), ld['calls'].to_a.include?(['workflow_status', 'project_workspace'])], [true, true])
r = R['openStep'] || {}
t("N mstOpenStep('project_workspace') sayfayı açar, menü seçili, yenileme 1, sayfa kimliği bildirilir",
  [r['page'], r['nav'], calls_of.(r, 'project_workspace_refresh').size, calls_of.(r, 'workflow_status')], ['project_workspace', 'Çalışma Alanı', 1, [['workflow_status', 'project_workspace']]])
r = R['guide_go'] || {}
t('N kılavuz g-t1 "Bu sayfayı aç" → Çalışma Alanı', [r['value'], r['page'], calls_of.(r, 'project_workspace_refresh').size], ['tıklandı', 'project_workspace', 1])
r = R['nav_boq'] || {}
t('N Keşif menüsü: boq_refresh 1 (çift yenileme yok), sayfa kimliği boq', [r['page'], calls_of.(r, 'boq_refresh').size, calls_of.(r, 'workflow_status')], ['boq', 1, [['workflow_status', 'boq']]])
r = R['nav_rebar'] || {}
t('N Donatı BIM menüsü: rebar_sources_get 1', [r['page'], calls_of.(r, 'rebar_sources_get').size, calls_of.(r, 'workflow_status')], ['rebar', 1, [['workflow_status', 'rebar']]])
r = R['nav_maint'] || {}
t('N Model Bakımı menüsü: maint_list 1', [r['page'], calls_of.(r, 'maint_list').size, calls_of.(r, 'workflow_status')], ['maint', 1, [['workflow_status', 'maint']]])
r = R['nav_ws'] || {}
t('N Çalışma Alanı menüsü: project_workspace_refresh 1', [r['page'], calls_of.(r, 'project_workspace_refresh').size], ['project_workspace', 1])
t('N projectWorkspaceLoaded gerçek Ruby verisiyle', [R['loaded'] && R['loaded']['err'], (R['loaded'] || {})['value'].to_s.include?('yapı elemanı okundu')], [[], true])
replay = []
TARGETS.each do |lbl, pid|
  s = R["sel #{lbl}"] || {}
  t("N #{lbl}: Elemanı Düzenle etkin", [s['err'], s['value']], [[], [false, 'Elemanı Düzenle']])
  sh = calls_of.(R["show #{lbl}"] || { 'calls' => [] }, 'project_workspace_action')
  rq = sh.map { |c| JSON.parse(c[1]) }
  t("N #{lbl}: Modelde Göster → project_workspace_action {zoom:true, edit:false}", rq.map { |x| [x['keys'], x['zoom'], x['edit']] }, [[[key.(pid)], true, false]])
  replay << ["Modelde Göster #{lbl}", 'project_workspace_action', sh.first && sh.first[1], pid, :select]
  ed = calls_of.(R["edit #{lbl}"] || { 'calls' => [] }, 'project_workspace_action').map { |c| JSON.parse(c[1]) }
  want_edit = lbl != 'BK1'
  t("N #{lbl}: Elemanı Düzenle → project_workspace_action edit=#{want_edit}", ed.map { |x| [x['keys'], x['zoom'], x['edit']] }, [[[key.(pid)], false, want_edit]])
  replay << ["Elemanı Düzenle #{lbl}", 'project_workspace_action', JSON.generate(ed.first || {}), pid, want_edit ? :edit : :select]
end
r = R['bk response'] || {}
t('N BK: seçim yanıtı → Başlık Kirişi sayfası, düzenleme kipi, mstBKLoadSelectedEdit çağrısı',
  [r['err'], r['page'], (r['value'] || [])[1], calls_of.(r, 'mstBKLoadSelectedEdit').size], [[], 'beam', 'edit', 1])
r = R['pile editor'] || {}
t('N Kazık: projectWorkspaceOpenPileEditor → Kazık sayfası + pile_load_selected_for_edit', [r['err'], r['page'], calls_of.(r, 'pile_load_selected_for_edit').size], [[], 'pile', 1])
r = R['sel PD1 again'] || {}
obs('PD1 seçiliyken düğme devre dışı durumları', r['value'])
%w[elevation elevation_sync material material_change health scoped_model_health].each_slice(2) do |lbl, cbn|
  rr = R[lbl] || { 'calls' => [] }
  c = calls_of.(rr, cbn)
  t("N PD1: #{cbn} çağrısı (model_token + keys)", [rr['value'], c.map { |x| JSON.parse(x[1])['keys'] }], ['tıklandı', [[key.(6001)]]])
  replay << ["#{cbn} PD1", cbn, c.first && c.first[1], 6001, :dialog]
end
t('N Model Sağlığı düğmesi → model_health', calls_of.(R['model_health'] || { 'calls' => [] }, 'model_health').size, 1)
t('N Mesnet ve Bağlantı Kontrolü düğmesi → relationship_audit', calls_of.(R['relationship'] || { 'calls' => [] }, 'relationship_audit').size, 1)
t('N Bağımlılıklar: BK1 seçiliyken düğme etkin, tıklama dependency_analysis', [(R['sel BK1 dep'] || {})['value'], calls_of.(R['deprun'] || { 'calls' => [] }, 'dependency_analysis').size], [false, 1])
t('N Bağımlılıklar: setDependencyAnalysis yanıtı Çalışma Alanı\'nda gösterilir', (R['depresp'] || {})['value'].to_s.start_with?('BK1 · Başlık kirişi:'), true)
r = R['qto'] || {}
t('N Metrajı Aç → Metraj sayfası', [r['value'], r['page']], ['tıklandı', 'qto'])
t('N gizli Eleman Düzenleyici sayfası DOM\'da, menüde girişi yok', (R['editor hidden'] || {})['value'], [true, 0])
if ed_sel
  t('N setEditorSelection (Ruby BK1 yanıtı) çalışır', [(R['editor sel'] || {})['err'], (R['editor sel'] || {})['value']], [[], 'BK1'])
else
  obs('N setEditorSelection', 'Ruby yanıtı yok (editor_selection hata verdi) — sınanamadı')
end
pv = calls_of.(R['editor preview'] || { 'calls' => [] }, 'editor_preview')
t('N applyEditor → editor_preview isteği', pv.size, 1)
ca = (R['grid'] || {})['value'].to_s
t('N kazık ızgarası: customAxes kod taşır, display_label / görünen ad kopyalanmaz', [ca.include?('display_label'), ca.include?('Kıyı Aksı'), ca.include?('"name":"X-01"')], [false, false, true])
t('N kazık ızgarası gösterimi görünen ad', (R['grid labels'] || {})['value'], 'Kıyı Aksı|Ön Sıra')
ov = calls_of.(R['override'] || { 'calls' => [] }, 'pile_open_override').map { |c| JSON.parse(c[1]) }
t('N openPileOverrideDialog yükü: structure kod, axis_name kod, display_label yok', ov.map { |x| [x['structure'], x['axis_name'], JSON.generate(x).include?('display_label')] }, [['ANO-01', 'X-01', false]])
all_err = res.reject { |x| x['label'] == '__load__' }.flat_map { |x| x['err'].map { |m| "#{x['label']}: #{m}" } }
t('N adımlarda betik hatası yok', all_err, [])
t('N adımlarda uyarı penceresi (alert) yok', res.flat_map { |x| x['alerts'] }, [])

# ---------------- 4) Geri oynatma: JS istekleri gerçek Ruby geri çağrılarına ----------------
back = []
replay.each do |lbl, cbn, raw, pid, kind|
  if raw.nil? || raw == '{}'
    t("G #{lbl}: istek yok", false, true); next
  end
  e, o, m = call.(cbn, raw)
  errjs = o.grep(/\A(projectWorkspaceError|controlledEditorError)\(/)
  case kind
  when :select
    t("G #{lbl}: hatasız, model seçimi = hedef", [e, errjs, $model.selection.to_a.map(&:persistent_id)], [nil, [], [pid]])
  when :edit
    if pid == 6003
      # Fikstürde PK1 ComponentInstance: Kontrollü Düzenleme bilinçli olarak yalnız Group kabul eder (controlled_editor.rb:53)
      t("G #{lbl} (Component): Türkçe red iletisi, işlem açılmaz", [e, errjs.map { |x| x[/"(.*)"/, 1] }, $model.ops.count { |x| x[0] == :start && x[1].to_s.include?('Kontrollü') }],
        [nil, ['Yalnız özgün grup geometrisi düzenlenebilir.'], 0])
      back.concat(o.map { |s| [lbl, s] })
      next
    end
    want = pid == 1001 ? /\AprojectWorkspaceOpenPileEditor\(\)/ : /\AcontrolledEditorLoaded\(/
    t("G #{lbl}: hatasız, #{pid == 1001 ? 'kazık düzenleyici' : 'Kontrollü Düzenleme'} açılır", [e, errjs, o.grep(want).size], [nil, [], 1])
  when :dialog
    t("G #{lbl}: hatasız, ileti yok", [e, errjs, m], [nil, [], []])
  end
  back.concat(o.map { |s| [lbl, s] })
end
if pv.first
  e, o, = call.('editor_preview', pv.first[1])
  t('G editor_preview (JS yükü) → showEditorChangePreview', [e, o.grep(/\AshowEditorChangePreview\(/).size], [nil, 1])
  back.concat(o.map { |s| ['editor_preview', s] })
end
sel.(1001)
e, o, = call.('pile_load_selected_for_edit'); back.concat(o.map { |s| ['pile_load_selected_for_edit', s] })
e, o, = call.('mstBKLoadSelectedEdit')
sel.(4001); e, o, = call.('mstBKLoadSelectedEdit'); back.concat(o.map { |s| ['mstBKLoadSelectedEdit', s] })

# ---------------- 5) Node turu 2: Ruby'nin döndürdüğü betikler sayfada çalışır ----------------
steps2 = [{ label: 'loaded', js: "#{loaded};''" }]
back.each_with_index { |(lbl, s), i| steps2 << { label: "#{i} #{lbl} :: #{s[0, 40]}", js: "#{s};''" } }
res2, ok2 = node_run(steps2)
t('N2 node turu 2 tamamlandı', [ok2, res2.size], [true, steps2.size + 1])
e2 = res2.flat_map { |x| x['err'].map { |m| "#{x['label']}: #{m}" } }
t("N2 Ruby yanıt betikleri (#{back.size}) sayfada hatasız (işlev tanımlı)", e2, [])
obs('N2 yanıt betiği işlevleri', back.map { |_, s| s[/\A[\w.]+/] }.uniq)
puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
