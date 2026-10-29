# A1 / R-2 (K04, K05, K28): standardize_model_metadata, element_library, bim_data_core_report,
# stamp_dependency_metadata, mst_dependency_payload.
# Kullanim: ruby tools/test/a1_r2_identity.rb <src/marine_structures_tools>
require_relative 'a1_helper'
main = A1.src('main.rb')

module EngineeringUI; def self.decorate(h); h; end; end
class FakeDialog; def set_html(h); $html = h; end; def show; end; end
class Host
  attr_accessor :parents_of
  def element_signature(e); e.get_attribute(DICT, 'sig', 'S').to_s; end
  def html_escape(s); s.to_s; end
  def bim_type_label(t); t.to_s; end
  def rockfill_qto_data; { materials: [], sections: [] }; end
  def mst_html_dialog(*_a); FakeDialog.new; end
  def mst_all_elements; $model.entities.dup; end
  def mst_direct_parents(e, _all = nil); (@parents_of || {})[e] || []; end
  def mst_direct_dependencies(_e, _all = nil); []; end
  def mst_element_by_pid(pid, all = mst_all_elements); all.find { |x| x.persistent_id == pid.to_i }; end
  def dependency_changes(_m); $dep_changes || []; end
  def send_dependency_analysis(*_a); end
  def mst_dependency_tree(_e); []; end
  def mst_dependency_impacts(_e); []; end
end
A1.load(Host, main, 'def ensure_uid(', 'def bim_type_prefix(', 'def next_library_type_id(', 'def standardize_model_metadata', 'def element_library',
        'def bim_data_core_report', 'def stamp_dependency_metadata', 'def mst_dependency_payload(')
obs('mst_standardize_changes tanımlı', A1.load_opt(Host, main, 'def mst_standardize_changes('))
h = Host.new
full = lambda do |pid, extra = {}|
  FakeEnt.new(pid, { 'element_type' => 'steel_pipe_pile', 'element_uid' => "MST-#{pid}-1", 'type_signature' => 'S', 'library_type_id' => 'P-T01', 'type_id' => 'P-T01',
                     'schema_version' => '2.1', 'revision' => 'v0.23.4', 'id' => "P#{pid}" }.merge(extra))
end
model_ok = -> { $model.set_attribute(A1::DICT, 'bim_schema_version', '2.1'); $model.set_attribute(A1::DICT, 'bim_core_revision', 'v0.20.0'); $log = [] }

# 1) K04: tam standart model → yazma yok, işlem yok
a1_reset!; e1 = full.(1); $model.entities = [e1]; model_ok.()
r = h.standardize_model_metadata
t('K04 tam modelde standardize dönüşü 0', r, 0)
t('K04 tam modelde işlem açılmaz', ops, [])
t('K04 öğe revision korunur (v0.23.4)', e1.a('revision'), 'v0.23.4')
t('K04 öğe schema_version korunur (2.1)', e1.a('schema_version'), '2.1')
t('K04 model bim_schema_version korunur (2.1)', $model.a('bim_schema_version'), '2.1')

# 2) K04: Eleman Kütüphanesi'ni açmak yazmaz
$log = []
h.element_library
t('K04 element_library yazmaz', sets.size, 0)
t('K04 element_library işlem açmaz', ops, [])
t('K04 element_library KPI "—"', $html.to_s.include?('<small>Standardize Edilen</small><b>—</b>'), true)

# 3) eksik UID / type id / registry / mevcut farklı type_id korunur
a1_reset!
e1 = full.(1)
e2 = full.(2, 'library_type_id' => '', 'type_id' => 'P-T05')
e3 = full.(3, 'library_type_id' => '', 'type_id' => '')
e4 = full.(4, 'library_type_id' => '', 'type_id' => '', 'sig' => 'YENI', 'type_signature' => '')
e5 = full.(5, 'type_id' => 'P-T09', 'library_type_id' => 'P-T09')
e6 = full.(6, 'element_uid' => '')
$model.entities = [e6, e5, e4, e3, e2, e1]; model_ok.(); $model.set_attribute(A1::DICT, 'type_counter_P', 7); $log = []
h.standardize_model_metadata
t('K04 type_id dolu/library boş → library_type_id=type_id', [e2.a('library_type_id'), e2.a('type_id')], %w[P-T05 P-T05])
t('K04 ikisi boş, bilinen imza → en küçük PID sahibinin tid (P-T01)', [e3.a('library_type_id'), e3.a('type_id')], %w[P-T01 P-T01])
t('K04 ikisi boş, yeni imza → yeni sayaç P-T08', [e4.a('library_type_id'), e4.a('type_id'), $model.a('type_counter_P')], ['P-T08', 'P-T08', 8])
t('K04 eksik type_signature yazıldı', e4.a('type_signature'), 'YENI')
t('K04 aynı imzada farklı mevcut type_id korunur (P-T09)', e5.a('type_id'), 'P-T09')
t('K04 eksik UID üretildi ve uid_owner_pid yazıldı', [e6.a('element_uid').to_s.start_with?('MST-6-'), e6.a('uid_owner_pid')], [true, 6])
t('K04 hiçbir öğede revision yazılmadı', sets.count { |x| x[3] == 'revision' }, 0)
t('K04 boş yer tutucu (project/ano/axis/zone/parent_uid) yazılmadı', sets.count { |x| %w[project ano axis zone parent_uid].include?(x[3]) }, 0)
t('K04 tek işlem', ops, [:start, :commit])

# 4) K28: BIM Data Core raporu tek işlem (değişiklik yoksa hiç)
a1_reset!; $model.entities = [full.(1)]; model_ok.()
h.bim_data_core_report
t('K28 bim_data_core_report (değişiklik yok) işlem sayısı 0', ops.count(:start), 0)
a1_reset!; $model.entities = [full.(1, 'schema_version' => '')]; model_ok.()
h.bim_data_core_report
t('K28 bim_data_core_report (1 değişiklik) tek start/commit', ops, [:start, :commit])

# 5) K05 / K28: Dependency stamp
a1_reset!
d = full.(10, 'element_type' => 'deck_slab')
c1 = full.(11, 'element_type' => 'curb', 'parent_uid' => 'X-ESKI')
c2 = full.(12, 'element_type' => 'curb', 'parent_uid' => '')
pc = full.(13, 'element_type' => 'flat_precast', 'support_left_pid' => 10, 'support_left_uid' => 'Y-ESKI', 'support_right_pid' => 10, 'support_right_uid' => '')
$model.entities = [d, c1, c2, pc]; model_ok.(); h.parents_of = { c1 => [d], c2 => [d] }
h.stamp_dependency_metadata
t('K05 dolu parent_uid ezilmez', c1.a('parent_uid'), 'X-ESKI')
t('K05 boş parent_uid doldurulur', c2.a('parent_uid'), 'MST-10-1')
t('K05 dolu support_left_uid ezilmez', pc.a('support_left_uid'), 'Y-ESKI')
t('K05 boş support_right_uid doldurulur', pc.a('support_right_uid'), 'MST-10-1')
t('K05 revision yazılmaz', sets.count { |x| x[3] == 'revision' }, 0)
t('K28 stamp tek işlem', ops, [:start, :commit])
$log = []; $msgs = []; $dep_changes = []
h.stamp_dependency_metadata
t('K05 ikinci çalıştırma: değişiklik yok → işlem yok', ops, [])
t('K05 "değişiklik gerekmedi" iletisi', $msgs.any? { |m| m.include?('değişiklik gerekmedi') }, true)

# 6) görüntüleme UID üretmez
a1_reset!; x = full.(20, 'element_uid' => ''); $model.entities = [x]
h.mst_dependency_payload(x)
t('R-2 mst_dependency_payload UID yazmaz', sets.size, 0)
a1_finish
