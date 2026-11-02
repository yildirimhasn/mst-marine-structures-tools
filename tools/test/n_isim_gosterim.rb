# ADR-0515-I — görünen adın yansıdığı Ruby çıktıları (kimlik / gruplama kodla kalır):
# kazık etiketi (mst_labels), metraj kazık hiyerarşisi (qto_workspace: label = ad, key / structure = kod),
# BK canlı aksları (label / imza kod + display_label), Keşif / Hakediş Excel "Yapı" + "Yapı Kodu", statik denetimler
# (aks görseli axis_name kod, kazık ızgara yükü, Çalışma Alanı structure_label, takeoff ara toplam, Ayrıntılı Metraj kazık sayfası).
# Kullanim: ruby tools/test/n_isim_gosterim.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
labels = A1.src('mst_labels.rb')
qto = A1.src('qto_workspace.rb')
boq = A1.src('boq_pro.rb')
pw = A1.src('project_workspace.rb')
D = A1::DICT
NEW = A1.load_opt(Host, main, 'def mst_structure_display_names(')
t('ADR-0515-I okuyucu tanımlı (mst_structure_display_names)', NEW, true)
a1_finish unless NEW
A1.load(Host, main, 'def mst_axis_display_names(', 'def mst_structure_display(', 'def mst_structure_label(', 'def mst_axis_display(',
        'def mst_axis_grid_key(', 'def pile_report_system(', 'def pile_report_structure(', 'def mst_bk_live_axes')
Host.class_eval(labels[/^MST_LABEL_PILE_TYPES=.*$/] + "\n" + labels[/^MST_LABEL_TOP_TYPES=.*$/])
A1.load(Host, labels, 'def mst_label_pile_id(', 'def mst_label_structure(', 'def mst_label_xy(', 'def mst_label_z(', 'def mst_label_height(', 'def mst_label_plan(')
A1.load(Host, qto, 'def pile_qto_hierarchy(')
class Host
  def collect_piles(_e); $model.entities.map { |p| [p, nil] }; end
  def pile_fabrication_qto_row(items, label, _x); [label, items.size]; end
  def pile_report_concrete_classes(_i); []; end
end
h = Host.new
a1_reset!
$model.set_attribute(D, 'structure_display_names_json', JSON.generate('BD-01' => 'YANAŞMA DOLFENİ-01'))
$model.set_attribute(D, 'axis_display_names_json', JSON.generate('BD-01::BD-01' => { 'x' => { 'X-01' => 'AKS 1' }, 'y' => {} }))
$model.set_attribute(D, 'active_ano', 'BD-01')
pk = ->(pid, st, ax, x) { Sketchup::Group.new(pid, 'element_type' => 'steel_pipe_pile', 'ano' => st, 'structure' => st, 'system' => 'DOLFEN', 'axis' => ax, 'axis_no' => 1, 'pile_id' => 'P-01', 'global_x_m' => x, 'global_y_m' => 0.0) }
$model.entities = [pk.(1, 'BD-01', 'X-01', 0.0), pk.(2, 'BD-02', 'X-01', 9.0)]
$log = []
plan = h.mst_label_plan($model)
t('Kazık etiketi: aynı numara iki yapıda → "görünen ad · numara" (ayrım kodla)', plan.map { |r| r[:text] }.sort, ['BD-02 · P-01', 'YANAŞMA DOLFENİ-01 · P-01'])
hier = h.pile_qto_hierarchy($model.entities)
st = hier.select { |r| r[:level] == 'structure' }
t('Metraj hiyerarşisi: yapı satırı label = görünen ad, structure / key = kod', st.map { |r| [r[:label], r[:structure], JSON.parse(r[:key])[2], r[:structure_label]] },
  [['YANAŞMA DOLFENİ-01', 'BD-01', 'BD-01', 'YANAŞMA DOLFENİ-01'], ['BD-02', 'BD-02', 'BD-02', 'BD-02']])
t('Metraj hiyerarşisi: gruplama sırası kodla (BD-01, BD-02)', st.map { |r| r[:structure] }, %w[BD-01 BD-02])
$model.entities = [$model.entities.first]
live = h.mst_bk_live_axes
t('BK canlı aksları: label kod, display_label görünen ad, ano_label "(kod)" ekli', [live['axes'].first['label'], live['axes'].first['display_label'], live['ano_label']], ['X-01', 'AKS 1', 'YANAŞMA DOLFENİ-01 (BD-01)'])
t('BK aks imzası (axis_no / label / pile_ids) görünen addan bağımsız', main.include?("JSON.generate(live['axes'].map{|a|[a['axis_no'],a['label'],a['pile_ids']]})"), true)
t('Okuyucular modele yazmaz', sets.size, 0)

# Keşif / Hakediş Excel: "Yapı" (görünen ad) + "Yapı Kodu"; satır hücre sayısı başlıkla aynı
kes = A1.grab(boq, 'def boq2_kesif_xlsx_write(')
hak = A1.grab(boq, 'def boq2_hakedis_xlsx_write(')
t('Keşif Excel Poz Metrajları başlığı (5 sütun)', kes[/m << (\[.*?\])\.map\{\|h\|/, 1], "['Eleman','Tip','Yapı','Yapı Kodu','Miktar']")
krow = kes[/m << \[\{v:element_visible_id.*?\]\n/m].to_s
t('Keşif Excel eleman satırı 5 hücre (ad, kod)', [krow.scan('{v:').size, krow.include?('{v:mst_structure_display(yk,sn)'), krow.include?('{v:yk,')], [5, true, true])
ksub = kes[/m << \[\{v:"Eleman toplamı.*$/].to_s
t('Keşif Excel ara toplam satırı 5 hücre', ksub.scan('{v:').size, 5)
t('Hakediş Excel Onaylı Metraj başlığı (10 sütun)', hak[/mt << (\['Poz No'.*?\])\.map/, 1].to_s.scan(/'[^']*'/).size, 10)
hrow = hak[/mt << \[\{v:r\[:code\]\.to_s.*?\]\n/m].to_s
t('Hakediş Excel satırı 10 hücre (ad, kod)', [hrow.scan('{v:').size, hrow.include?('{v:mst_structure_display(yk,sn)'), hrow.include?('{v:yk,')], [10, true, true])

# Statik: diğer gösterim noktaları
vis = A1.grab(main, 'def mst_show_grid_visual(')
t('Aks görseli: metin görünen ad, axis_name / x_axis / y_axis kod', [vis.scan("mst_axis_display(ano,zone,").size, vis.scan("t.set_attribute(DICT,'axis_name',r['name'].to_s)").size, vis.include?("'x_axis'=>xr['name'].to_s")], [2, 2, true])
t('Aks görseli başlığı: görünen ad + (kod)', vis.include?('disp=mst_structure_display(code,nil,model)'), true)
t('Aks görseli imzası görünen adları içerir (ad değişince aynı işlemde yeniden çizilir)', A1.grab(main, 'def mst_grid_visual_signature(').include?('mst_axis_display_names(model)'), true)
t('Kazık ızgara yükü: name kod + display_label; structure_label', [main.include?("{'name'=>xr['name'].to_s,'display_label'=>mst_axis_display(structure,structure,'x'"), main.include?("'structure'=>structure,'structure_label'=>mst_structure_label(structure,nil,model)")], [true, true])
t('Çalışma Alanı: structure_label (süzgeç değeri fields.structure kod kalır)', [pw.include?('structure_label:(st.strip.empty?'), pw.include?("fields['structure']=e.get_attribute(DICT,'ano',nil) if fields['structure'].to_s.strip.empty?")], [true, true])
tk = A1.grab(main, 'def takeoff(')
t('Kazık raporu ara toplam etiketleri görünen ad (4), gruplama kodla', [tk.scan('mst_structure_display(structure,sn)').size, tk.include?('group_by{|p|pile_report_structure(p)}')], [4, true])
t('Ayrıntılı Metraj kazık sayfası structure_label kullanır', A1.grab(main, 'def export_professional_excel').include?('item[:structure_label] || item[:structure]'), true)
t('Aks taşıma onayında "(kod)" ekli yapı adı', A1.grab(main, 'def mst_axis_move_confirm(').scan('mst_structure_label(').size, 2)
a1_finish
