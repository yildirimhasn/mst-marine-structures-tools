# Parti H / H1 (K43): "Seçili Elemana Elle Aks Ata…" menü maddesi (daraltılmış yazım: yalnız axis + axis_assignment,
# proje yalnız boşsa; ano / zone / active_ano yazılmaz), doğrulamalar işlemden önce, Model Kontrolü metinleri ve
# auto_organize_project / assign_manual_axis_to_selection'da "işlem açılmadan abort" kusuru.
# Kullanim: ruby tools/test/h_h1_axis.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
D = A1::DICT
class FakeSel < Array; def add(x); self << x; end; def to_a; Array.new(self); end; end
class Host
  def mst_project_elements; $elems; end
  def ensure_uid(e); e.get_attribute(DICT, 'element_uid', "U#{e.persistent_id}"); end
  def refresh_dependency_metadata_inline; end
  def mst_pile_ids_for_beam(_b); []; end
end
A1.load(Host, main, 'def mst_axis_label(', 'def auto_organize_project(', 'def assign_manual_axis_to_selection(')
NEW = ['def mst_manual_axis_targets(', 'def mst_manual_axis_assign!(', "def mst_manual_axis_ui\n"].map { |f| A1.load_opt(Host, main, f) }.all?
t('H1 yeni işlevler tanımlı (mst_manual_axis_targets / _assign! / _ui)', NEW, true)
h = Host.new
mk = lambda do
  a1_reset!
  p1 = Sketchup::Group.new(1, 'element_type' => 'steel_pipe_pile', 'project' => 'ESKİ', 'ano' => 'A1', 'zone' => 'A1', 'axis' => 'AKS-01')
  p2 = Sketchup::Group.new(2, 'element_type' => 'crown_wall', 'project' => '', 'ano' => '', 'axis' => '')
  $elems = [p1, p2]
  $model.selection = FakeSel.new([p1, p2])
  $model.set_attribute(D, 'project_name', 'MODEL PROJESİ'); $model.set_attribute(D, 'active_ano', 'ANO-07')
  $log = []
  [p1, p2]
end

if NEW
  p1, p2 = mk.()
  r = h.mst_manual_axis_assign!(h.mst_manual_axis_targets($model), '3', 'YENİ PROJE', $model)
  t('H1 dönüş: 2 eleman, aks etiketi AKS-03, 1 elemana proje yazıldı', [r[:count], r[:axis], r[:project_filled]], [2, 'AKS-03', 1])
  t('H1 yazılan anahtarlar yalnız axis / axis_assignment / (boşsa) project', sets.map { |x| x[3] }.uniq.sort, %w[axis axis_assignment project])
  t('H1 dolu proje korunur, boş proje doldurulur', [p1.a('project'), p2.a('project')], ['ESKİ', 'YENİ PROJE'])
  t('H1 ano / zone / active_ano / project_name yazılmaz', [p1.a('ano'), p1.a('zone'), p2.a('ano'), $model.a('active_ano'), $model.a('project_name')], ['A1', 'A1', '', 'ANO-07', 'MODEL PROJESİ'])
  t('H1 axis_assignment = manual (iki eleman)', [p1.a('axis_assignment'), p2.a('axis_assignment')], %w[manual manual])
  t('H1 normal işlem: start → commit_with_dependencies → commit (tek Geri Al)', [ops, $log.count { |x| x[0] == :cwd }, $model.open_ops], [[:start, :commit], 1, 0])
  t('H1 işlem adı', $log.find { |x| x[0] == :start }[1], 'MST Elle Aks Ataması')

  mk.()
  r = begin; h.mst_manual_axis_assign!(h.mst_manual_axis_targets($model), '  ', '', $model); rescue => e; e.message; end
  t('H1 boş aks: işlem açılmadan reddedilir (abort yok)', [r, ops, sets.size], ['Aks adı boş olamaz.', [], 0])
  mk.(); $model.selection = FakeSel.new([])
  r = begin; h.mst_manual_axis_assign!([], 'AKS-02', '', $model); rescue => e; e.message; end
  t('H1 boş seçim: işlem açılmadan reddedilir', [r, ops], ['Önce MST elemanı/elemanları seçin.', []])

  # Hata işlem içinde: abort, açık işlem kalmaz
  mk.()
  class Host; alias_method :cwd_real, :commit_with_dependencies; def commit_with_dependencies(m); raise 'bağımlılık hatası' if $cwd_raise; cwd_real(m); end; end
  $cwd_raise = true
  r = begin; h.mst_manual_axis_assign!(h.mst_manual_axis_targets($model), 'AKS-05', '', $model); rescue => e; e.message; end
  t('H1 işlem içi hata: abort, açık işlem yok', [r, ops, $model.open_ops], ['bağımlılık hatası', [:start, :abort], 0])
  $cwd_raise = false

  # UI: seçim yok → ileti, işlem yok; inputbox iptal → işlem yok; sonuç iletisi Türkçe
  mk.(); $model.selection = FakeSel.new([])
  t('H1 UI seçim yok: ileti, işlem yok', [h.mst_manual_axis_ui, ops, $msgs.last.to_s.include?('MST elemanı seçin')], [0, [], true])
  mk.(); $ib_queue = [nil]
  t('H1 UI vazgeç: işlem yok', [h.mst_manual_axis_ui, ops], [0, []])
  mk.(); $ib_queue = [['AKS-KR-01', 'MODEL PROJESİ']]
  n = h.mst_manual_axis_ui
  t('H1 UI: 2 eleman, tek işlem, ileti ano değişmedi der', [n, ops, $msgs.last.to_s.include?('Ano / yapı bilgisi değiştirilmedi')], [2, [:start, :commit], true])
end

# Kusur düzeltmesi: doğrulama hatası işlem açılmadan abort çağırmaz (önceki kullanıcı işlemini geri almaz)
mk.()
r = begin; h.auto_organize_project('project' => '', 'ano' => 'A1'); rescue => e; e.message; end
t('H1 auto_organize_project boş proje: abort çağrılmaz', [r, ops], ['Proje adı boş olamaz.', []])
mk.()
r = begin; h.assign_manual_axis_to_selection('project' => 'P', 'ano' => 'A', 'axis' => ''); rescue => e; e.message; end
t('H1 assign_manual_axis_to_selection boş aks: abort çağrılmaz', [r, ops], ['Manuel aks adı boş olamaz.', []])

# Menü ve Model Kontrolü metinleri (statik)
t('H1 menü: Tüm araçlar (eski menü) altında "Seçili Elemana Elle Aks Ata…"', main.include?("old_menu.add_item('Seçili Elemana Elle Aks Ata…'){mst_manual_axis_ui}"), true)
t('H1 auto_organize_project menüye / araç çubuğuna bağlanmadı', main.scan(/\{auto_organize_project/).size, 0)
path = 'Uzantılar → Deniz Yapıları Araçları (MST) → Tüm araçlar (eski menü) → Seçili Elemana Elle Aks Ata…'
t('H1 Model Kontrolü aks eksik metni yeni maddeye yönlendirir', main.include?("'Aks/Açıklık bilgisi eksik.','Elemanı seçip #{path} ile aks atayın.'"), true)
t('H1 Model Kontrolü artık olmayan "Proje / Ano / Aks Yöneticisi ile" yolunu göstermez', main.scan(/'Proje \/ Ano \/ Aks Yöneticisi ile/).size, 0)
a1_finish
