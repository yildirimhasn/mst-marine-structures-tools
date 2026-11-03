# R (03.11.2026, kullanıcı kararı "Gecikmeler: Hepsini düzelt" + isimlendirme açıkları) — G1–G5 sayaç ve davranış testleri.
#  G1 Çalışma Alanı: işlem sonrası tam yenileme yalnız sayfa açıkken; kapalıyken "bayat", dönüşte tek yenileme; sayfa bilinmiyorsa
#     eski davranış; controlled_editor_apply tek yenileme; ağaç tıklamasında ağaç bir kez.
#  G2 Kontrollü Düzenleme: Önizle'de imza yalnız hedef + bağımlılık ağacı; ağaç işlem başına bir kez; bayat önizleme algılama matrisi;
#     request'siz parmak izi eski algoritmayla birebir.
#  G3 Revizyon kaydı: boq_rows bir kez; arşiv ayrıştırma azalır.
#  G4 Keşif açılışı: boq2_get model taramaz (ölçüm; değişiklik yok).
#  G5 Aks Yöneticisi: değişikliksiz kayıtta işlem / yazım yok; kullanılan aks onaysız kalkmaz; kazık raporu, ilişki denetimi ve
#     Kazık Özel Ayarları görünen ad "Ad (kod)".
#  E  Eşdeğerlik: tools/test/r_dump.rb yeni kaynak ve tabanda (c1e3a59, git archive) ayrı süreçte; tüm senaryo özetleri aynı.
# Kullanim: ruby tools/test/r_gecikme.rb <src/marine_structures_tools> [taban klasörü | taban commit=c1e3a59]
require 'digest'
require 'stringio'
require 'tmpdir'
require 'open3'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/r_gecikme.rb <marine_structures_tools klasoru> [taban]'
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.expand_path(File.join(dir, 'main.rb'))
$stderr = $stderr_keep
require_relative '../golden/fixture'
require_relative 'r_helper'
M = MAG::MarineStructuresTools

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 200]} (beklenen #{exp.inspect[0, 200]})"
end

$cnt = Hash.new(0)
def count(name, mod = M)
  o = mod.method(name)
  mod.define_singleton_method(name) { |*a, &b| $cnt[name] += 1; o.call(*a, &b) }
end
%i[project_workspace_refresh revision_geometry_signature boq_rows boq2_payload collect_elements].each { |n| count(n) }
# Çalışma Alanı ağacının gerçek taraması: yeni kodda entries_scan (entries önbellekten dönebilir), tabanda entries
SCAN = M::ProjectWorkspace.respond_to?(:entries_scan) ? :entries_scan : :entries
count(SCAN, M::ProjectWorkspace)
module JSON
  class << self
    alias_method :r_parse, :parse
    def parse(s, *a)
      st = $model.get_attribute('MAG_MST_RevisionLog', 'snapshots', nil)
      $cnt[:snap_parse] += 1 if s.is_a?(String) && (st ? s.equal?(st) : s == '[]')
      r_parse(s, *a)
    end
  end
end
def take(n); v = $cnt[n]; $cnt[n] = 0; v; end
def zero!; $cnt.clear; end
def commit!; M::WorkspaceModelObserver.new.onTransactionCommit($model); r_timers; end
def loaded(d); d.out.count { |s| s.start_with?('projectWorkspaceLoaded') }; end
mask = ->(s) { s.gsub(/"model_token":"\d+"/, '"model_token":"*"') }

# ---------------- G1 ----------------
d = r_setup
M.project_workspace_refresh(d); d.cb['workflow_status'].call(nil, 'project_workspace'); r_timers; zero!
commit!
t('G1 sayfa Çalışma Alanı: işlem sonrası tam yenileme 1 (eski davranış)', take(:project_workspace_refresh), 1)
d.cb['workflow_status'].call(nil, 'boq'); r_timers; zero!; d.out.clear
r_target.set_attribute(D, 'concrete_class', 'C40/50')
commit!; commit!
t('G1 sayfa Keşif: iki işlem sonrası tam yenileme 0', take(:project_workspace_refresh), 0)
t('G1 sayfa Keşif: Çalışma Alanı "bayat" işaretlendi', M.instance_variable_get(:@workspace_stale), true)
M::WorkspaceSelectionObserver.new.onSelectionBulkChange($model.selection); r_timers
t('G1 sayfa Keşif + bayat: seçim değişikliği eski listeyle gönderilmedi', d.out.size, 0)
M.project_workspace_refresh(d); d.cb['workflow_status'].call(nil, 'project_workspace'); r_timers   # T('project_workspace') + refresh()
t('G1 dönüş: tek tam yenileme (refresh() + workflow_status)', take(:project_workspace_refresh), 1)
got = d.out.grep(/projectWorkspaceLoaded/).last.then { |s| mask.(s) }
d2 = RDlg.new; M.project_workspace_refresh(d2)
t('G1 dönüş: yüklenen veri taze tam yenilemeyle aynı', got, mask.(d2.out.last))
t('G1 dönüş: bayat işareti kalktı', M.instance_variable_get(:@workspace_stale), false)
# yedek: sayfa yenileme çağrısı olmadan açılırsa workflow_status yeniler
d.cb['workflow_status'].call(nil, 'qto'); commit!; zero!
d.cb['workflow_status'].call(nil, 'project_workspace'); r_timers
t('G1 yedek: bayatken sayfa kimliği Çalışma Alanı gelince tek yenileme', take(:project_workspace_refresh), 1)
# sayfa bilinmiyor (eski arayüz: workflow_status argümansız)
d = r_setup
M.project_workspace_refresh(d); d.cb['workflow_status'].call(nil); r_timers; zero!
commit!
t('G1 sayfa bilinmiyor (argümansız workflow_status): eski davranış, yenileme 1', take(:project_workspace_refresh), 1)
# ağaç tıklaması
pc = r_target
zero!
M.project_workspace_action(JSON.generate('model_token' => $model.object_id.to_s, 'keys' => [r_key(pc)], 'zoom' => false, 'edit' => false), d); r_timers
t('G1 ağaç tıklaması: Çalışma Alanı ağacı 1 kez taranır (eski 2)', take(SCAN), 1)
M.project_workspace_action(JSON.generate('model_token' => $model.object_id.to_s, 'keys' => [r_key(pc)], 'zoom' => false, 'edit' => true), d); r_timers
t('G1 Elemanı Düzenle (Kontrollü Düzenleme açılışı): ağaç 1 kez (eski 4)', take(SCAN), 1)
t('G1 tıklama sonrası okuma batch kapalı', [M.instance_variable_get(:@mst_scan_batch_on), M.instance_variable_get(:@mst_read_batch_on)], [false, nil])

# ---------------- G2 ----------------
d = r_setup
M.project_workspace_refresh(d); d.cb['workflow_status'].call(nil, 'project_workspace'); r_timers
pc = r_target
nent = M::ProjectWorkspace.entries($model).size
zero!
M.controlled_editor_preview(JSON.generate(r_req(pc, 'C40/50')), d)
t('G2 Önizle hata yok', d.out.grep(/controlledEditorError/), [])
t("G2 Önizle: geometri imzası hedef + bağımlılık (1; eski #{nent})", take(:revision_geometry_signature), 1)
t('G2 Önizle: Çalışma Alanı ağacı 1 kez (eski 3)', take(SCAN), 1)
tok = M.instance_variable_get(:@controlled_editor_pending)[:token]
mo = M::WorkspaceModelObserver.new
$model.define_singleton_method(:commit_operation) { @ops << [:commit]; mo.onTransactionCommit(self); true }   # SketchUp: gözlemci commit içinde
d.out.clear; zero!
M.controlled_editor_apply(JSON.generate('token' => tok), d); r_timers
t('G2 Uygula hata yok', d.out.grep(/controlledEditorError/), [])
t('G2 Uygula: geometri imzası 1', take(:revision_geometry_signature), 1)
t('G2 Uygula: ağaç 3 kez (denetim 1 + işlem içi tip eşleme 1 + yenileme 1; eski 6)', take(SCAN), 3)
t('G1 Uygula: Çalışma Alanı tam yenileme 1 (açık yenileme; gözlemci yenilemesi iptal; eski 2)', [take(:project_workspace_refresh), loaded(d)], [1, 1])
t('G2 Uygula: tek işlem', $model.ops, [[:start, 'MST Kontrollü Eleman Düzenleme'], [:commit]])
$model.singleton_class.send(:remove_method, :commit_operation)

# Bayat önizleme algılama matrisi (parmak izi doğrudan): BK1 hedef, PD2 BK1'e oturur (bağımlılık), PD1 ilgisiz
class REdgeV; attr_accessor :position; def initialize(p); @position = Geom::Point3d.new(*p); end; end
class REdge < Sketchup::Edge
  def initialize(a, b); super(nil, {}); @v = [REdgeV.new(a), REdgeV.new(b)]; end
  def vertices; @v; end
  undef_method :transformation
end
fp_setup = lambda do
  r_setup
  pd2 = $all_ents[6002]
  pd2.set_attribute(D, 'support_left_pid', 4001); pd2.set_attribute(D, 'support_right_pid', 4002)
  [$all_ents[4001], pd2, $all_ents[6001]].each { |g| e = REdge.new([0, 0, 0], [10, 0, 0]); g.entities << e; e.parent = g.entities }
  { 'model_token' => $model.object_id.to_s, 'keys' => [r_key($all_ents[4001])] }
end
FP2 = M::ControlledEditor.method(:fingerprint).parameters.size > 1   # taban: fingerprint(model)
fpr = ->(req) { FP2 ? M::ControlledEditor.fingerprint($model, req) : M::ControlledEditor.fingerprint($model) }
cases = {
  'hedef öznitelik' => [-> { $all_ents[4001].set_attribute(D, 'width_m', 1.3) }, true],
  'hedef iç geometri (kenar köşesi)' => [-> { $all_ents[4001].entities.grep(REdge).first.vertices[1].position = Geom::Point3d.new(11, 0, 0) }, true],
  'bağımlı (PD2) iç geometri' => [-> { $all_ents[6002].entities.grep(REdge).first.vertices[1].position = Geom::Point3d.new(11, 0, 0) }, true],
  'ilgisiz eleman öznitelik' => [-> { $all_ents[6001].set_attribute(D, 'concrete_class', 'C50/60') }, true],
  'ilgisiz eleman taşındı (dönüşüm)' => [-> { $all_ents[6001].transformation = Geom::Transformation.translation([1, 0, 0]) }, true],
  'ilgisiz eleman alt varlık özniteliği' => [-> { $all_ents[6001].entities.grep(REdge).first.set_attribute(D, 'formwork', true) }, true],
  'model özniteliği' => [-> { $model.set_attribute(D, 'type_counter_PD', 9) }, true],
  'yeni eleman' => [-> { g = Sketchup::Group.new(7777, 'element_type' => 'curb'); $model.entities << g; g.parent = $model.entities }, true],
  'ilgisiz eleman yalnız iç geometri (tip eşlemeyi etkilemez)' => [-> { $all_ents[6001].entities.grep(REdge).first.vertices[1].position = Geom::Point3d.new(12, 0, 0) }, false]
}
cases.each do |name, (mut, want)|
  req = fp_setup.call
  a = fpr.(req)
  mut.call
  b = fpr.(req)
  t("G2 bayat algılama: #{name} → #{want ? 'algılanır' : 'algılanmaz (bilinçli; uygulama bu geometriyi okumaz)'}", a != b, want)
end
req = fp_setup.call
a = fpr.(req)
$model.entities.delete($all_ents[4001])
t('G2 bayat algılama: hedef silindi → eski tam imzaya düşer, eşleşmez', fpr.(req) != a, true)
# request'siz parmak izi = eski algoritma (c1e3a59 controlled_editor.rb:70-80, kopya)
old_fp = lambda do |model|
  api = M
  records = M::ProjectWorkspace.entries(model).map do |entry|
    e = entry[:entity]
    attrs = api.mst_attr_hash(e).sort_by { |k, _v| k }
    ents = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    surface = ents.map { |part| [api.mst_attr_hash(part), part.respond_to?(:material) && part.material ? part.material.name : nil, part.respond_to?(:back_material) && part.back_material ? part.back_material.name : nil] }
    [entry[:key], attrs, surface, api.revision_geometry_signature(e), entry[:path].map { |n| [n.transformation.to_a, n.locked?, n.definition.instances.size] }]
  end
  api.revision_digest([api.mst_attr_hash(model).sort_by { |k, _v| k }, records])
end
fp_setup.call
t('G2 request\'siz parmak izi eski algoritmayla birebir', M::ControlledEditor.fingerprint($model), old_fp.($model))
t('G2 imza önbelleği kapsam dışında kapalı', M.instance_variable_get(:@mst_rev_shape_memo), nil)

# ---------------- G3 ----------------
d = r_setup
M.revision_create_snapshot(d)   # Rev.01 (arşiv boştu)
$all_ents[6002].set_attribute(D, 'concrete_volume_m3', 1.75); $model.ops.clear; zero!
M.revision_create_snapshot(d)   # Rev.02: kayıtlı arşiv var (ayrıştırma sayımı kayıtlı metin nesnesiyle)
t('G3 Anlık Kayıt (kayıt yolu): boq_rows 1 (eski 2)', take(:boq_rows), 1)
t('G3 Anlık Kayıt (kayıt yolu): arşiv ayrıştırma 2 (eski 3)', take(:snap_parse), 2)
t('G3 kayıt yolu: tek işlem', $model.ops, [[:start, 'MST Revizyon Kaydı'], [:commit]])
zero!; $ui_msgs = []
M.revision_create_snapshot(d)
t('G3 değişiklik yok yolu: boq_rows 1 (eski 2)', take(:boq_rows), 1)
t('G3 değişiklik yok yolu: arşiv ayrıştırma 1 (eski 3)', take(:snap_parse), 1)
t('G3 değişiklik yok yolu: işlem açılmadı, ileti', [$model.ops.size, $ui_msgs.any? { |s| s.include?('değişiklik yok') }], [2, true])
zero!; d.out.clear
M.revision_send(d)
t('G3 Revizyonlar ↻ Yenile: arşiv ayrıştırma 1 (eski 2)', take(:snap_parse), 1)
t('G3 kapsamlar kapandı', [M.instance_variable_get(:@mst_rev_snaps_memo), M.instance_variable_get(:@mst_revision_boq_reuse), M.instance_variable_get(:@mst_read_batch_on)], [nil, nil, nil])
$model.set_attribute('MAG_MST_RevisionLog', 'snapshots', '{bozuk'); $ui_msgs = []; o0 = $model.ops.size
M.revision_create_snapshot(d)
t('G3 bozuk arşiv: işlem açılmadı, ileti', [$model.ops.size - o0, $ui_msgs.first.to_s.include?('okunamadı')], [0, true])

# ---------------- G4 ----------------
d = r_setup; zero!
d.cb['boq2_get'].call(nil)
t('G4 boq2_get (Keşif açılışında ikinci çağrı): model taraması yok, boq_rows yok', [take(:collect_elements), take(:boq_rows), take(:boq2_payload)], [0, 0, 1])

# ---------------- G5 ----------------
d = r_setup
ax = r_axis_open
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(r_axis_payload))   # ilk kayıt: yalnız varsayılan ızgaralar (BD-01, RIHTIM-01) farklı
# 03.11.2026 rapor 25/5 (kullanıcı kararı "düzelt"): varsayılan ızgara tek başına değişiklik sayılmaz — eski beklenti [start, commit]
t('G5a ilk kayıt (yalnız kayıtsız varsayılan ızgaralar): işlem açılmaz (25/5)', $model.ops.map(&:first), [])
$model.ops.clear
ax = r_axis_open
x = r_axis_payload
w0 = $writes.size; $ui_msgs = []
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(x))
t('G5a değişikliksiz kayıt: işlem açılmaz (boş Geri Al yok)', $model.ops, [])
t('G5a değişikliksiz kayıt: model yazımı yok', $writes[w0..].map { |_p, _d, k| k }, [])
t('G5a değişikliksiz kayıt: Türkçe durum iletisi', ax.out.last.to_s.include?('Değişiklik yok'), true)
x2 = r_axis_payload; x2['project'] = 'GOLDEN-2'
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(x2))
t('G5a proje adı değişti: tek işlem, yazıldı', [$model.ops, $model.get_attribute(D, 'project_name')], [[[:start, 'MST Aks Kaydı'], [:commit]], 'GOLDEN-2'])
d = r_setup; ax = r_axis_open
$model.set_attribute(D, 'axis_grids_json', '{bozuk'); $ui_msgs = []
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(r_axis_payload))
t('G5a bozuk aks kaydı: işlem açılmadan hata (eski: aç + geri al)', [$model.ops, $ui_msgs.first.to_s.include?('okunamadı')], [[], true])
# G5b
d = r_setup; ax = r_axis_open
x = r_axis_payload; x['grids']['ISKELE::ANO-01']['x'].reject! { |r| r['name'] == 'X-02' }
w0 = $writes.size; $ui_msgs = []
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(x))
t('G5b kullanılan aks (X-02, kazık P9) onaysız silinemez: işlem yok', [$model.ops, $writes[w0..].size], [[], 0])
t('G5b Türkçe hata iletisi (yapı / aks / neden)', $ui_msgs.first.to_s.then { |s| s.include?('onaysız') && s.include?('ANO-01 / X X-02') && s.include?('1 eleman') }, true)
x['grids']['ISKELE::ANO-01']['x'] = [{ 'name' => 'X-01', 'gap_m' => 0.0 }, { 'name' => 'X-2', 'gap_m' => 5.0 }]
$ui_msgs = []
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(x))
t('G5b kullanılan aksın kodu değişti (X-02 → X-2): onaysız kayıt yok', [$model.ops, $ui_msgs.first.to_s.include?('X-02')], [[], true])
x['removed_used_axes'] = ['ISKELE::ANO-01::x::X-02']; $ui_msgs = []
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(x))
t('G5b önizlemede onaylanmış (removed_used_axes): kaydedilir, tek işlem', [$model.ops.map(&:first), $ui_msgs], [%i[start commit], []])
t('G5b kazık verisi değişmedi (grid_x_axis kod)', $all_ents[1009].get_attribute(D, 'grid_x_axis'), 'X-02')
d = r_setup; ax = r_axis_open
x = r_axis_payload; x['grids']['ISKELE::ANO-01']['x'] = [{ 'name' => 'X-02', 'gap_m' => 0.0 }, { 'name' => 'X-03', 'gap_m' => 5.0 }]; $ui_msgs = []
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(x))
t('G5b kullanılmayan aks (X-01) silinir, onay gerekmez', [$model.ops.map(&:first).first, $ui_msgs.grep(/onaysız/)], [:start, []])
t('G5b Aks Yöneticisi JS yükü removed_used_axes gönderir', [ax.html.include?('removed_used_axes:removedUsed()'), ax.html.include?('function removedUsed()')], [true, true])
# G5c
d = r_setup(names: true)
html = M.takeoff('pile').html.to_s
row = html[/<tr class='bim-pile-row'[^>]*data-structure='ANO-01'.*?<\/tr>/m].to_s
t('G5c kazık raporu Yapı sütunu "Ad (kod)"', row.include?('<td>Ana İskele (ANO-01)</td>'), true)
t('G5c kazık raporu süzgeç değeri kod (data-structure, option value)', [row.include?("data-structure='ANO-01'"), html.include?("<option value='ANO-01'>Ana İskele (ANO-01)</option>")], [true, true])
t('G5c kazık raporu arama metni görünen adı içerir', row[/data-search='([^']*)'/, 1].to_s.include?('ana i̇skele') || row[/data-search='([^']*)'/, 1].to_s.include?('ana iskele'), true)
ra = M::RelationshipAudit.analyze($model)[:records].flat_map { |r| r[:checks].map { |c| c[:message] } }.grep(/yapı bilgileri uyuşmuyor/).first.to_s
t('G5c ilişki denetimi iletisi yapı "Ad (kod)"', ra.include?('(A1 / İskele Gövdesi (ISKELE))'), true)
ov = r_capture_override(M, d, 'axis_name' => 'X-01', 'points' => [{ 'point_index' => 0, 'point_name' => 'A', 'data' => {} }, { 'point_index' => 1, 'point_name' => 'B', 'data' => {} }])
t('G5c Kazık Özel Ayarları başlığı "Ad (kod)"', ov[:head], 'Kıyı Aksı (X-01)')
t('G5c nokta listesi görünen ad; adsız nokta kod', ov[:options], ['Kıyı Aksı (X-01)/Ön Sıra (A)', 'Kıyı Aksı (X-01)/B'])
t('G5c yük kod kalır (axis_name / point_name)', JSON.parse(ov[:payload]), { 'axis_name' => 'X-01', 'points' => [{ 'point_index' => 0, 'point_name' => 'A', 'data' => {} }, { 'point_index' => 1, 'point_name' => 'B', 'data' => {} }] })
t('G5c geri gönderilen değerler değişmedi (save())', ov[:save], 'function save(){sketchup.pile_override_save(JSON.stringify({axis_index:payload.axis_index,point_index:payload.points[cur].point_index,data:data()}))}')
$model.set_attribute(D, 'structure_display_names_json', '{}'); $model.set_attribute(D, 'axis_display_names_json', '{}')
ov = r_capture_override(M, d, 'axis_name' => 'X-01', 'structure' => 'ANO-01', 'points' => [{ 'point_index' => 0, 'point_name' => 'A', 'data' => {} }])
t('G5c görünen ad yoksa kod (eski metin)', [ov[:head], ov[:options]], ['X-01', ['X-01/A']])

# ---------------- E: eşdeğerlik (yeni ↔ taban, ayrı süreç) ----------------
root = File.expand_path('../..', __dir__)
ref = ARGV[1] || 'c1e3a59'
Dir.mktmpdir('mst_r') do |tmp|
  refdir = if File.directory?(ref.to_s)
             ref
           else
             tar = File.join(tmp, 'ref.tar')
             ok = system('git', '-C', root, 'archive', '-o', tar, ref, 'src', out: File::NULL, err: File::NULL) && Dir.chdir(tmp) { system('tar', '-xf', 'ref.tar') }
             ok ? File.join(tmp, 'src', 'marine_structures_tools') : nil
           end
  if refdir.nil?
    t("E taban #{ref} açılamadı", false, true)
  else
    dump = lambda do |src|
      o, = Open3.capture2e('ruby', File.join(__dir__, 'r_dump.rb'), src)
      line = o.lines.grep(/\ARDUMP /).last
      line ? JSON.parse(line.sub('RDUMP ', '')) : { 'hata' => o.lines.last(3).join }
    end
    a = dump.(File.expand_path(dir)); b = dump.(refdir)
    # 03.11.2026 (kullanıcı kararı, runner 1.2.4 uyarısı): çelik boru kazık kalıbı "eksik" → "uygulanmaz" (değer 0 aynı). Çalışma Alanı
    # yükünü içeren üç özet bu yüzden tabandan farklıdır; model yazımları (ce_apply_state) ve diğerleri birebir kalmalı.
    pile_fw = %w[ws_return_loaded ce_preview ce_apply_loaded_last]
    # 04.11.2026 (kullanıcı talimatı, METRAJ DEĞİŞİR): tapa manipülasyona + PILE_PLUG satırı, prekast sınıf satırları
    # (PRECAST_CONCRETE#<sınıf>). Keşif / revizyon arşivi / detay metraj özetleri bu yüzden tabandan farklıdır; miktar ayrıntısı
    # tools/test/v4_tapa_prekast_poz.rb ve golden-master farkındadır. Diğer özetler birebir kalmalı.
    metraj = %w[rev_archive_sha boq_open takeoff]
    (a.keys | b.keys).each do |k|
      if pile_fw.include?(k) then t("E #{k}: tabandan farklı (yalnız kazık kalıbı durumu; açıklanmış)", a[k] != b[k] && !a[k].nil?, true)
      elsif metraj.include?(k) then t("E #{k}: tabandan farklı (04.11 tapa + prekast sınıf metraj değişikliği; açıklanmış)", a[k] != b[k] && !a[k].nil?, true)
      else t("E #{k}: yeni = taban (#{ref})", a[k], b[k])
      end
    end
  end
end

puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
