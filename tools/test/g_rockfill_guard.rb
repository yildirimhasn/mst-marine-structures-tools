# Parti G-a / kod inceleme #1: bozuk dolgu kesit zinciri (rockfill_section_chain_json) sessizce bos sayilmaz,
# Kaydet / otomatik kayit guard'li; JS bozuk durumda otomatik kayit gondermez (node ile).
# Kullanim: ruby tools/test/g_rockfill_guard.rb <src/marine_structures_tools>
require_relative 'a1_helper'
require 'open3'
main = A1.src('main.rb')
html = A1.src('ui.html')
class FakeDialog; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; true; end; end
class Host
  ROCKFILL_PROJECT_KEY = 'rockfill_section_chain_json'.freeze
  ROCKFILL_PROJECT_KEY_ALT2 = 'rockfill_section_chain_alt02_json'.freeze
  ROCKFILL_ACTIVE_ALT_KEY = 'rockfill_active_alternative'.freeze
end
A1.load(Host, main, 'def mst_json_attr_bad?(', 'def mst_json_attr_guard!(', 'def mst_rf_write!(', 'def mst_rf_autosave_warn(', 'def rockfill_project_key(',
        'def rockfill_save_project(', 'def rockfill_autosave_project(', 'def rockfill_load_project(')
h = Host.new
K = 'rockfill_section_chain_json'
secs = JSON.generate('sections' => [{ 'id' => '1-1', 'station' => 0 }, { 'id' => '2-2', 'station' => 10 }], 'alternative' => '01')
loaded = ->(d) { JSON.parse(d.js.last[/rockfillProjectLoaded\((.*)\)\z/m, 1]) }

a1_reset!; $model.set_attribute(A1::DICT, K, '{"sections":[bozuk'); $log = []
d = FakeDialog.new
h.rockfill_load_project(d)
t('yükleme: bozuk kayıt → Türkçe uyarı', $msgs.last.to_s.include?('Dolgu kesit zinciri kaydı (rockfill_section_chain_json) okunamadı'), true)
t('yükleme: JS\'e bad=true, boş kesit', [loaded.(d)['bad'], loaded.(d)['sections']], [true, []])
t('yükleme: yazma / işlem yok', [sets.size, ops], [0, []])
$log = []; $msgs = []
h.rockfill_autosave_project(secs)
t('otomatik kayıt: bozuk kayıt ezilmez, işlem açılmaz', [$model.a(K), ops], ['{"sections":[bozuk', []])
t('otomatik kayıt: ileti (oturumda bir kez)', $msgs.length == 1 && $msgs[0].include?('okunamadı; mevcut kaydın üzerine yazılmadı'), true)
$log = []; $msgs = []
h.rockfill_save_project(secs, FakeDialog.new)
t('Kaydet: bozuk kayıt ezilmez, işlem açılmaz, Türkçe ileti', [$model.a(K), ops, $msgs.last.to_s.start_with?('Dolgu kesit zinciri hatası: Dolgu kesit zinciri kaydı')], ['{"sections":[bozuk', [], true])
a1_reset!; $model.set_attribute(A1::DICT, K, '[1,2]'); d = FakeDialog.new
h.rockfill_load_project(d)
t('yükleme: JSON ama Hash değil → bozuk (0.51.5 önce: TypeError)', loaded.(d)['bad'], true)
# sağlam kayıt: davranış değişmez
a1_reset!; $model.set_attribute(A1::DICT, K, JSON.generate('sections' => [{ 'id' => 'A', 'station' => 0 }])); d = FakeDialog.new; $log = []
h.rockfill_load_project(d)
t('sağlam kayıt: bad yok, kesitler gelir, ileti yok', [loaded.(d).key?('bad'), loaded.(d)['sections'].length, $msgs.length], [false, 1, 0])
h.rockfill_autosave_project(secs)
t('sağlam kayıt: otomatik kayıt yazar (tek işlem)', [ops, JSON.parse($model.a(K))['sections'].length], [%i[start commit], 2])
a1_reset!; d = FakeDialog.new
h.rockfill_load_project(d)
t('kayıt yok: boş liste, bad yok, ileti yok', [loaded.(d)['sections'], loaded.(d).key?('bad'), $msgs.length], [[], false, 0])

# ---- JS (node): bozuk durumda otomatik kayıt gönderilmez
grab = ->(sig) { l = html.lines.find { |x| x.start_with?(sig) } or abort("yok: #{sig}"); l }
js = grab.('function autoSaveRockfillProject(') + grab.('function rockfillProjectLoaded(')
pre = "var window={};var sent=[];var sketchup={rockfill_autosave_project:function(j){sent.push(j)}};window.sketchup=sketchup;" \
      "var rfSaveTimer=null,rfSections=[],rfAlternative='01';function setTimeout(f){f();return 1}function clearTimeout(){}" \
      "var document={getElementById:function(){return null}};function syncRFMaterials(){}function renderRockfillSections(){}function renderRockfillQTO(){}\n"
run = "#{js}\nrockfillProjectLoaded({sections:[],bad:true,alternative:'01'});rfSections=[{station:0},{station:10}];autoSaveRockfillProject();var a=sent.length;" \
      "rockfillProjectLoaded({sections:[{station:0},{station:5}],alternative:'01'});autoSaveRockfillProject();console.log(JSON.stringify([a,sent.length]));"
out, st = Open3.capture2e('node', '-e', pre + run)
abort("node çalışmadı: #{out}") unless st.success?
t('JS: bozuk yüklemeden sonra otomatik kayıt gönderilmez; sağlam yüklemede gönderilir', JSON.parse(out.lines.last), [0, 1])
a1_finish
