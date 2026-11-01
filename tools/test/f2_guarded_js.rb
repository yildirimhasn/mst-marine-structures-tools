# Parti F / F2 — eski foraj düzenleyicisi ve "seçili BIM kazığı yükle" callback'lerinin ürettiği JS (SketchUp dışında).
# drilling_edit_action (pile_drilling.rb) sahte nesneyle çalıştırılır; pile_load_selected_bim bloğunun execute_script dizgisi
# main.rb'den alınıp Ruby ile değerlendirilir. Üretilen JS, node ile tanımsız işlev ortamında çalıştırılır:
# ReferenceError olmamalı, Türkçe yönlendirme iletisi (alert) gösterilmeli; işlev tanımlıysa işlev çağrılmalı.
# Kullanim: ruby tools/test/f2_guarded_js.rb <src/marine_structures_tools>
require_relative 'a1_helper'
require 'open3'
pd = A1.src('pile_drilling.rb')
main = A1.src('main.rb')

class FakeDialog; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; true; end; end
class Host
  def drilling_edit_state(_s); { count: 2, enabled: '1', length: 6.0, model_token: 'x' }; end
  def qto_summary(_d); end
  def send_boq(_d); end
end
A1.load(Host, pd, 'def drilling_edit_action(')
h = Host.new
a1_reset!
d = FakeDialog.new
h.instance_variable_set(:@d, d)

def run_js(js, define = nil)
  pre = "var shown=[];function alert(m){shown.push(String(m));}\n"
  pre += "function #{define}(x){shown.push('CALLED:'+#{define.inspect});}\n" if define
  code = pre + "try{#{js}\nconsole.log(JSON.stringify({ok:true,shown:shown}));}catch(e){console.log(JSON.stringify({ok:false,err:String(e)}));}"
  out, st = Open3.capture2e('node', '-e', code)
  abort("node çalışmadı: #{out}") unless st.success?
  JSON.parse(out.lines.last)
end

h.drilling_edit_action('read', '{"scope":"selected"}')
r = run_js(d.js.last)
t('F2: setDrillingEditor tanımsız → ReferenceError yok', r['ok'], true)
t('F2: setDrillingEditor tanımsız → yönlendirme iletisi', r['shown'].to_a.any? { |m| m.include?('Mevcut Kazığı Güncelle') }, true)
r = run_js(d.js.last, 'setDrillingEditor')
t('F2: setDrillingEditor tanımlıysa çağrılır, ileti yok', r['shown'], ['CALLED:setDrillingEditor'])
h.drilling_edit_action('bogus', '{}')
r = run_js(d.js.last)
t('F2: drillingEditError tanımsız → ReferenceError yok, ileti + hata nedeni', [r['ok'], r['shown'].to_a.any? { |m| m.include?('Kazık sayfasındaki') && m.include?('Bilinmeyen foraj işlemi.') }], [true, true])
r = run_js(d.js.last, 'drillingEditError')
t('F2: drillingEditError tanımlıysa çağrılır', r['shown'], ['CALLED:drillingEditError'])
t('F2: read / hata yolunda SketchUp işlemi açılmadı', ops, [])

# pile_load_selected_bim: callback satırındaki execute_script dizgisi
line = main.lines.find { |l| l.include?("add_action_callback('pile_load_selected_bim')") } or abort('callback yok')
lit = line[/execute_script\((".*?")\)\s*if @d/, 1] or abort('execute_script dizgisi bulunamadı')
p = { 'pile_id' => 'P1' }
js = eval(lit) # rubocop:disable Security/Eval — yalnız kaynaktaki dizgi literali, yerel p ile
r = run_js(js)
t('F2: loadSelectedBimPile tanımsız → ReferenceError yok', r['ok'], true)
t('F2: loadSelectedBimPile tanımsız → "Modelden Seçili Kazığı Yükle" yönlendirmesi', r['shown'].to_a.any? { |m| m.include?('Modelden Seçili Kazığı Yükle') }, true)
r = run_js(js, 'loadSelectedBimPile')
t('F2: loadSelectedBimPile tanımlıysa çağrılır', r['shown'], ['CALLED:loadSelectedBimPile'])
a1_finish
