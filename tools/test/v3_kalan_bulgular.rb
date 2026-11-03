# V3 (03.11.2026) — kabul denetimi sonrası kalan bulgular (kullanıcı kararı: hepsi bu pakette).
#  25/8  Kontrollü Düzenleme Ruby tarafında başlık kirişini reddeder (BK, BK sayfasında düzenlenir).
#  25/5  Aks Yöneticisi kaydında işlem açılmadan önceki planlama modele yazmaz; kayıtlı ızgarası olmayan yapıda değişikliksiz kayıt
#        Geri Al adımı açmaz.
#  25/6  Kuru çalıştırma kaydedicisi (MstAttrRecorder) desteklemediği çağrıda sessizce yanlış yanıt vermez; değişiklik var sayılır.
#  25/7  Sahipsiz elemanları olan kod yeni yapı kodu olarak önerilmez; elle verilirse onay ister (yük: reattach_codes).
#  25/12 Gömülü sayfa açılışı Ruby'ye sayfa kimliğini bildirir (Çalışma Alanı gizli sayılır).
#  26/1a Keşif Excel "Poz Metrajları" ara toplamında adet "Yapı" sütununda değil; yalnız miktarı > 0 olan elemanlar sayılır.
# (editor_payload: tools/test/u1_ui_simplify.rb "R editor_selection" maddesi.)
# Kanıt düzeyi: sahte nesne + sahte DOM. SketchUp içi davranış KANITLANMAZ.
# Kullanim: ruby tools/test/v3_kalan_bulgular.rb <src/marine_structures_tools>
require 'stringio'
require 'tmpdir'
require 'open3'
require_relative '../golden/sketchup_stub'
DIR = File.expand_path(ARGV[0] || abort('kullanim: ruby tools/test/v3_kalan_bulgular.rb <marine_structures_tools klasoru>'))
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
def setup2
  r_setup(names: false)
  uv_main_dialog
  $model.set_attribute(D, 'system_structures_json', '{"DOLFEN":["BD-01"],"ISKELE":["ANO-01","ANO-02"],"RIHTIM":["RIHTIM-01"]}')
  $writes = []
end
def save_on(ax, pl)
  $model.ops.clear; $msgs.clear
  ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(pl))
  [$model.ops.dup, $msgs.dup]
end
COMMIT = [[:start, 'MST Aks Kaydı'], [:commit]].freeze

# ---------- 25/8 ----------
d = r_setup
bk = $all_ents.values.find { |e| e.get_attribute(D, 'element_type', '') == 'head_beam' }
d.out.clear
M.controlled_editor_preview(JSON.generate('model_token' => $model.object_id.to_s, 'keys' => [r_key(bk)], 'values' => {}), d)
err = d.out.grep(/controlledEditorError/).join
t('25/8 Kontrollü Düzenleme BK önizlemesini reddeder (Başlık Kirişi sayfasına yönlendirir)', [!bk.nil?, err.include?('Başlık Kirişi sayfasında')], [true, true])
M.project_workspace_action(JSON.generate('model_token' => $model.object_id.to_s, 'keys' => [r_key(bk)], 'zoom' => false, 'edit' => true), d) rescue nil
t('25/8 BK için Kontrollü Düzenleme formu açılmaz', d.out.grep(/controlledEditorLoaded/).size, 0)

# ---------- 25/5 ----------
setup2
ax = r_axis_open
ops, msgs = save_on(ax, r_axis_payload)
t('25/5 kayıtlı ızgarası olmayan ANO-02: değişikliksiz kayıt işlem açmaz', [ops, msgs], [[], []])
setup2
ax = r_axis_open
pl = r_axis_payload   # yük, sızıntı konmadan önce (yardımcı okuma işlevini çağırır)
$model.set_attribute(D, 'system_structures_json', '{"DOLFEN":["BD-01","ANO-01"],"ISKELE":["ANO-01","ANO-02"],"RIHTIM":["RIHTIM-01"]}')
$model.set_attribute(D, 'active_structure__RIHTIM', 'YOK-9')
pl['active']['RIHTIM'] = 'RIHTIM-01'
$writes = []; at_start = nil
$model.define_singleton_method(:start_operation) { |*a| at_start ||= $writes.size; @ops << [:start, a.first]; true }
ops, = save_on(ax, pl.merge('structure_names' => {}))
$model.singleton_class.send(:remove_method, :start_operation)
pre = $writes.first(at_start || $writes.size).map { |w| w[2] }.select { |k| k.to_s =~ /\A(system_structures_json|active_structure__)/ }
t('25/5 planlama işlem açılmadan yazmaz (geçiş yazımları işlemin içinde)', [ops.map(&:first), pre], [%i[start commit], []])

# ---------- 25/6 ----------
r_setup
rec = M::MstAttrRecorder.new($model)
e1 = begin; rec.delete_attribute(D); nil; rescue StandardError => e; e.class.name; end
e2 = begin; rec.attribute_dictionary(D); nil; rescue StandardError => e; e.class.name; end
t('25/6 kaydedici: anahtarsız silme ve sözlük okuma desteklenmez (açık hata)', [e1.to_s.end_with?('Unsupported'), e2.to_s.end_with?('Unsupported')], [true, true])
orig = M.method(:mst_axis_manager_save_payload)
M.define_singleton_method(:mst_axis_manager_save_payload) { |_x, m| m.delete_attribute(D) }
ch = (M.mst_axis_manager_payload_changes({}, $model) rescue :hata)
M.define_singleton_method(:mst_axis_manager_save_payload, &orig)
t('25/6 desteklenmeyen çağrıda değişiklik var sayılır (kayıt normal işlemle sürer)', [ch != :hata, ch.respond_to?(:empty?) && !ch.empty?], [true, true])

# ---------- 25/7 ----------
setup2
p = Sketchup::Group.new(1201, gf_pile_attrs('P81', 'structure' => 'ANO-05', 'ano' => 'ANO-05', 'system' => 'ISKELE', 'element_uid' => 'MST-V3-P81'))
$model.entities << p; p.parent = $model.entities; $all_ents[1201] = p
ax = r_axis_open
html = ax.html.to_s
script = html[%r{<script>\s*\(function\(\)\{\s*'use strict';(.*)\}\)\(\);\s*</script>}m, 1].to_s
vars = %w[systems reserved].map { |v| script[/^var #{v}=.*?;\n/].to_s }.join
fns = %w[z2 defaultStructure allCodes nextCode].map { |n| script[/function #{n}\(.*?\n/].to_s }.join
out, st = Dir.mktmpdir('mst_v3') { |dd| f = File.join(dd, 'n.js'); File.write(f, vars + fns + "console.log(JSON.stringify([nextCode('ISKELE'),nextCode('DOLFEN')]))"); Open3.capture2e('node', f) }
t('25/7 önerilen yeni kod sahipsiz elemanlı kodu atlar (ANO-05 sahipsiz → ANO-06)', [st.success?, (JSON.parse(out.lines.last) rescue out)], [true, %w[ANO-06 BD-02]])
pl = r_axis_payload
pl['systems']['ISKELE'] = %w[ANO-01 ANO-02 ANO-05]
pl['grids']['ISKELE::ANO-05'] = pl['grids']['ISKELE::ANO-02']
ops, msgs = save_on(ax, pl)
t('25/7 sahipsiz elemanlı kodla yeni yapı onaysız eklenmez', [ops, msgs.any? { |m| m.include?('ANO-05') && m.include?('sahipsiz') }], [[], true])
pl['reattach_codes'] = ['ISKELE::ANO-05']
ops, msgs = save_on(ax, pl)
t('25/7 onaylanınca eklenir (tek işlem)', [ops, msgs], [COMMIT, []])
t('25/7 Aks Yöneticisi yükü reattach_codes taşır', script.include?('reattach_codes:'), true)

# ---------- 26/1a ----------
r_setup
book = nil
M.define_singleton_method(:boq2_xl_write) { |_p, sheets| book = sheets }
M.boq2_kesif_xlsx_write('x.xlsx') rescue (book = nil)
sheet = book && book[:list].find { |n, _| n == 'Poz Metrajları' }
rows = sheet ? sheet[1].map { |r| r.map { |c| c.is_a?(Hash) ? c[:v] : c } } : []
blocks = []; cur = nil
rows.each do |r|
  if r.include?('Yapı Kodu') then cur = { n: 0 }
  elsif cur && r[0].to_s.start_with?('Eleman toplamı') then cur[:row] = r; blocks << cur; cur = nil
  elsif cur && r.size == 5 then cur[:n] += 1
  end
end
t('26/1a Poz Metrajları ara toplam satırları bulundu', blocks.size > 0, true)
t('26/1a ara toplamda "Yapı" sütunu boş', blocks.map { |b| b[:row][2] }.uniq, [''])
t('26/1a ara toplam etiketi miktarı > 0 olan eleman sayısını verir', blocks.map { |b| b[:row][0].to_s[/(\d+) eleman/, 1].to_i == b[:n] }.uniq, [true])

# ---------- 25/12 (sahte DOM) ----------
steps = [{ label: 'emb', js: "mstEmbedShow('accessories','Aksesuarlar','<html><head></head><body>x</body></html>');document.querySelector('.page.on').id" }]
out, st = Dir.mktmpdir('mst_v3') do |dd|
  f = File.join(dd, 'steps.json'); File.binwrite(f, JSON.generate(steps))
  Open3.capture2e('node', File.join(__dir__, 'u1_dom.js'), DIR, f)
end
r = out.lines.grep(/\ARES /).map { |l| JSON.parse(l.sub('RES ', '')) }.each_with_object({}) { |x, h| h[x['label']] = x }
calls = ((r['emb'] || {})['calls'] || []).select { |c| c[0] == 'workflow_status' }
t('25/12 gömülü sayfa açılınca sayfa kimliği Ruby\'ye bildirilir', [st.success?, (r['emb'] || {})['value'], calls.map { |c| c[1] }.uniq], [true, 'emb_accessories', ['emb_accessories']])
M.mst_ui_page_note('emb_accessories')
t('25/12 Ruby: gömülü sayfa açıkken Çalışma Alanı gizli sayılır', M.project_workspace_page_hidden?, true)

# ---------- runner 1.2.4 uyarısı: çelik boru kazıkta kalıp ----------
r_setup
pile = $all_ents.values.find { |e| e.get_attribute(D, 'element_type', '') == 'steel_pipe_pile' }
fq = M::QuantityService.record(pile, :formwork_m2)
t('Kazık kalıbı "uygulanmaz", değer 0 (eksik değil)', [fq[:state], fq[:value]], ['not_applicable', 0.0])

puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
