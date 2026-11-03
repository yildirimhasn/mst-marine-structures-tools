# U3 (03.11.2026, entegre sürüm regresyonu; senaryo 3–5) — isimlendirme uçtan uca, eklenti golden sahtesiyle GERÇEK yükleme sırasında:
#  3  Otomatik kod: boş sistemde varsayılan (BD-01 / ANO-01 / RIHTIM-01); üç sistemde yeni yapı = aynı ön ek en büyük + 1, gerçek Aks Yöneticisi
#     kaydıyla (DOLFEN / İSKELE / RIHTIM); Aks Yöneticisi sayfa betiğinin (sahte DOM) önerdiği kod = Ruby mst_next_structure_code, üç sistem.
#  4  Özel ad ver → değiştir → temizle (yapı + aks), her biri tek "MST Aks Kaydı" işlemi.
#  5  Her durumda bütün çıktılar: üst bar yükü, Aks Yöneticisi yeniden açılış, kazık ızgarası (display_label), kazık etiketi (yinelenen
#     numarada "ad · numara"), metraj kazık hiyerarşisi, Çalışma Alanı kaydı, kazık raporu (takeoff: Yapı hücresi + ara toplamlar),
#     Excel Keşif "Poz Metrajları" ve Hakediş "Onaylı Metraj" (Yapı + Yapı Kodu) yeni adı gösterir, eski ad hiçbir çıktıda kalmaz;
#     metraj, BOQ özeti, bağımlılık ağı, revizyon imzaları ve eleman öznitelikleri dört durumda aynı.
# Kanıt düzeyi: sahte nesne (+ Aks Yöneticisi betiği sahte DOM). Aks görseli çizimi (metin varlıkları), gerçek dosya Excel'i ve SketchUp
# görünümü KANITLANMAZ (aks görseli metni: n_isim_gosterim statik).
# Kullanim: ruby tools/test/u3_isim_uctan_uca.rb <src/marine_structures_tools>
require 'stringio'
require 'tmpdir'
require 'open3'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/u3_isim_uctan_uca.rb <marine_structures_tools klasoru>'
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(File.expand_path(dir), 'main.rb')
$stderr = $stderr_keep
require_relative '../golden/fixture'
require_relative 'r_helper'
require_relative 'u_views'
M = MAG::MarineStructuresTools
$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 220]} (beklenen #{exp.inspect[0, 220]})"
end
def obs(label, v); puts "GÖZLEM #{label}: #{v.inspect[0, 300]}"; end
unless M.respond_to?(:mst_structure_display_names)
  t('ADR-0515-I okuyucu tanımlı', false, true); puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"; exit 1
end

# --- 3a) boş sistemde varsayılan kod ---
r_setup(names: false)
$model.set_attribute(D, 'system_structures_json', '{}')
t('3 boş kayıt: her sistemde varsayılan kod (DOLFEN BD-01, İSKELE ANO-01, RIHTIM RIHTIM-01)', %w[DOLFEN ISKELE RIHTIM].map { |s| M.mst_structures_for_system(s, $model) }, [%w[BD-01], %w[ANO-01], %w[RIHTIM-01]])

# --- kurulum: golden fikstür + Aks Yöneticisi ızgarası + yinelenen kazık numarası (P9 ANO-01 ve P9 BD-01) + D1 yapı kodu ANO-01 (Hakediş) ---
r_setup(names: false)
d = uv_main_dialog
dup = Sketchup::Group.new(1010, gf_pile_attrs('P9', 'structure' => 'BD-01', 'ano' => 'BD-01', 'system' => 'DOLFEN', 'element_uid' => 'MST-GOLD-P9B'))
$model.entities << dup; dup.parent = $model.entities; $all_ents[1010] = dup
$all_ents[5001].set_attribute(D, 'structure', 'ANO-01')
$writes = []

save = lambda do |pl|
  $model.ops.clear; $msgs.clear
  ax = r_axis_open
  ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(pl))
  [$model.ops, $msgs.dup, ax]
end

# --- 3b) üç sistemde yeni yapı: önerilen kod ---
ax = r_axis_open
html_ax = ax.html.to_s
pl = r_axis_payload
nexts = {}
%w[DOLFEN ISKELE RIHTIM].each do |s|
  all = pl['systems'].values.flatten
  nexts[s] = M.mst_next_structure_code(s, all)
  pl['systems'][s] = pl['systems'][s] + [nexts[s]]
end
t('3 önerilen kodlar (aynı ön ek en büyük + 1)', nexts, { 'DOLFEN' => 'BD-02', 'ISKELE' => 'ANO-02', 'RIHTIM' => 'RIHTIM-02' })
ops, msgs, = save.(pl)
t('3 yeni yapılar kaydedildi: tek işlem, ileti yok', [ops, msgs], [[[:start, 'MST Aks Kaydı'], [:commit]], []])
t('3 kayıtlı listeler', %w[DOLFEN ISKELE RIHTIM].map { |s| M.mst_structures_for_system(s, $model) }, [%w[BD-01 BD-02], %w[ANO-01 ANO-02], %w[RIHTIM-01 RIHTIM-02]])
t('3 sonraki öneri bir artar (BD-03 / ANO-03 / RIHTIM-03)', %w[DOLFEN ISKELE RIHTIM].map { |s| M.mst_next_structure_code(s, %w[DOLFEN ISKELE RIHTIM].flat_map { |x| M.mst_structures_for_system(x, $model) }) }, %w[BD-03 ANO-03 RIHTIM-03])

# Aks Yöneticisi sayfa betiği (sahte DOM): her sistemde önerilen yeni kod Ruby ile aynı
ax2 = r_axis_open
Dir.mktmpdir('mst_u3') do |tmp|
  File.binwrite(File.join(tmp, 'ax.html'), ax2.html.to_s)
  fire = "function __fire(e){if(e.onchange)e.onchange({target:e});(e.listeners.change||[]).forEach(function(f){f.call(e,{target:e})});}"
  steps = [{ label: 'fire', js: fire + ';1' }]
  %w[DOLFEN ISKELE RIHTIM].each do |s|
    steps << { label: s, js: "var s=document.getElementById('system');s.value='#{s}';__fire(s);document.getElementById('newStructure').value" }
  end
  f = File.join(tmp, 'steps.json'); File.binwrite(f, JSON.generate(steps))
  out, st = Open3.capture2e('node', File.join(__dir__, 'u1_dom.js'), tmp, f, 'ax.html')
  res = out.lines.grep(/\ARES /).map { |l| JSON.parse(l.sub('RES ', '')) }.map { |r| [r['label'], r] }.to_h
  t('3 Aks Yöneticisi betiği sahte DOM\'da hatasız', [st.success?, res.values.flat_map { |r| r['err'] }], [true, []])
  all = %w[DOLFEN ISKELE RIHTIM].flat_map { |x| M.mst_structures_for_system(x, $model) }
  %w[DOLFEN ISKELE RIHTIM].each do |s|
    t("3 Aks Yöneticisi önerisi (#{s}) = Ruby mst_next_structure_code", (res[s] || {})['value'], M.mst_next_structure_code(s, all))
  end
end

v0 = uv_views(d)
base_metraj = %w[boq_rows qto3_totals boq_digest dependency_graph revision_signatures __elem_sig].map { |k| [k, v0[k]] }.to_h

# --- 4) ad ver → değiştir → temizle ---
def names_payload(st, ax_x)
  pl = r_axis_payload
  pl['structure_names'] = st
  g = pl['grids']['ISKELE::ANO-01']
  g['x'][0]['display'] = ax_x
  pl
end
states = [
  ['ver', { 'ANO-01' => 'Ana İskele', 'BD-01' => 'Yanaşma Dolfeni', 'RIHTIM-01' => 'Kıyı Rıhtımı' }, 'Kıyı Aksı'],
  ['değiştir', { 'ANO-01' => 'Kuzey İskelesi', 'BD-01' => 'Yanaşma Dolfeni', 'RIHTIM-01' => 'Kıyı Rıhtımı' }, 'Kuzey Aksı'],
  ['temizle', { 'ANO-01' => '', 'BD-01' => '', 'RIHTIM-01' => '' }, '']
]
views = {}
prev = nil
states.each do |nm, st, axn|
  ops, msgs, = save.(names_payload(st, axn))
  t("4 #{nm}: tek işlem 'MST Aks Kaydı', ileti yok", [ops, msgs], [[[:start, 'MST Aks Kaydı'], [:commit]], []])
  t("4 #{nm}: elemanlara yazım yok", $writes.reject { |p, _, _| p == $model.persistent_id }.map { |p, _, k| [p, k] }, [])
  $writes = []
  v = uv_views(d); views[nm] = v
  want = st.reject { |_, x| x.empty? }
  t("4 #{nm}: kayıtlı yapı adları", v['names'][0], want)
  t("4 #{nm}: kayıtlı aks adı (ANO-01 / X-01)", v['names'][1].dig('ANO-01::ANO-01', 'x', 'X-01'), axn.empty? ? nil : axn)
  t("4 #{nm}: görünümlerde HATA yok", v.select { |_, x| x.to_s.start_with?('HATA') }.keys, [])
  t("4 #{nm}: okuma yolunda yazım yok", v['__writes'], [])
  base_metraj.each { |k, x| t("5 #{nm}: #{k} değişmedi", v[k], x) }
  ano = st['ANO-01']
  lab = ano.empty? ? 'ANO-01' : "#{ano} (ANO-01)"
  show = ano.empty? ? 'ANO-01' : ano
  dol = st['BD-01'].empty? ? 'BD-01' : st['BD-01']
  t("5 #{nm}: üst bar yükü structure_labels / structure_names", [v['label_maps']['structure_labels']['ANO-01'], v['label_maps']['structure_names']['ANO-01'], v['topbar'].include?("\"ANO-01\":#{JSON.generate(lab)}")], [lab, show, true])
  reopen = r_axis_open.html.to_s
  t("5 #{nm}: Aks Yöneticisi yeniden açılış adları", [(JSON.parse(reopen[/var names=({[^;]*})/, 1].to_s) rescue nil), axn.empty? || reopen.include?("\"display\":#{JSON.generate(axn)}")], [want, true])
  t("5 #{nm}: kazık ızgarası display_label / structure_label", [v['pile_grid'].include?("\"display_label\":#{JSON.generate(axn.empty? ? 'X-01' : axn)}"), v['pile_grid'].include?("\"structure_label\":#{JSON.generate(lab)}")], [true, true])
  t("5 #{nm}: kazık etiketi (yinelenen P9) 'ad · numara'", v['pile_labels'].select { |x| x.end_with?('· P9') }.sort, ["#{dol} · P9", "#{show} · P9"].sort)
  t("5 #{nm}: metraj kazık hiyerarşisi label ad, key kod", v['qto_hierarchy'].find { |r| r[1] == 'ANO-01' }.to_a.first(2), [show, 'ANO-01'])
  t("5 #{nm}: Çalışma Alanı kaydı (P9) structure_label, süzgeç kodu", v['workspace'].select { |r| r[0] == 'P9' && r[2] == 'ANO-01' }.map { |r| r[3] }, [lab])
  prow = v['takeoff_pile_html'][/<tr class='bim-pile-row'[^>]*data-structure='ANO-01'.*?<\/tr>/m].to_s
  t("5 #{nm}: kazık raporu (Kazık) Yapı hücresi \"Ad (kod)\", süzgeç kodu", [prow.include?("<td>#{lab}</td>"), v['takeoff_pile_html'].include?("<option value='ANO-01'>#{lab}</option>")], [true, true])
  t("5 #{nm}: Detaylı Metraj ara toplam satırı görünen ad", v['takeoff_html'].include?("<td>↳ #{show} — ARA TOPLAM</td>"), true)
  t("5 #{nm}: Excel Keşif Poz Metrajları başlığı ve (Yapı, Yapı Kodu)", [v['excel_kesif']['header'], v['excel_kesif']['pairs'].include?([show, 'ANO-01'])], [%w[Eleman Tip Yapı Yapı\ Kodu Miktar], true])
  t("5 #{nm}: Excel Hakediş Onaylı Metraj (Yapı, Yapı Kodu)", [(v['excel_hakedis']['header'] || [])[3..4], v['excel_hakedis']['pairs'].to_a.include?([show, 'ANO-01'])], [['Yapı', 'Yapı Kodu'], true])
  if prev
    old = prev[1]['ANO-01']
    unless old.empty? || old == ano
      left = v.reject { |k, _| k.start_with?('__') }.select { |_, x| JSON.generate(x).include?(old) }.keys
      t("5 #{nm}: eski ad (#{old}) hiçbir çıktıda kalmadı", left, [])
    end
    oax = prev[2]
    unless oax.empty? || oax == axn
      t("5 #{nm}: eski aks adı (#{oax}) hiçbir çıktıda kalmadı", v.reject { |k, _| k.start_with?('__') }.select { |_, x| JSON.generate(x).include?(oax) }.keys, [])
    end
  end
  prev = [nm, st, axn]
end
# temizle = hiç ad verilmemiş durum (gösterim)
%w[label_maps pile_labels qto_hierarchy workspace topbar pile_grid takeoff_html takeoff_pile_html relationship_audit excel_kesif excel_hakedis axis_display].each do |k|
  t("4 temizle: #{k} = ad verilmeden önceki durum", views['temizle'][k], v0[k])
end
t('4 temizle: ad kayıtları boş harita', views['temizle']['names'], [{}, {}])
puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
