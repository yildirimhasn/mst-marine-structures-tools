# G1–G6 (03.11.2026, gecikme düzeltmeleri) — çağrı sayısı ölçümü (SketchUp DIŞINDA, sahte nesne; süreler SketchUp süresi
# DEĞİLDİR — sayılar kanıttır). Aynı betik eski (taban) ve yeni kaynakta çalışır; tools/perf/scale_fixture.rb modeli kurulur.
# Ölçülen (her biri ayrı kurulumda):
#  ws_commit_page_ws   — Çalışma Alanı sayfası açıkken bir işlem (onTransactionCommit) sonrası project_workspace_refresh sayısı
#  ws_commit_page_boq  — Keşif sayfası açıkken (workflow_status('boq')) bir işlem sonrası project_workspace_refresh sayısı
#  ws_return           — ardından Çalışma Alanı'na dönüş (T → MSTProjectWorkspace.refresh() = project_workspace_refresh geri çağrısı)
#  ce_preview_sig / ce_preview_entries — Kontrollü Düzenleme Önizle: revision_geometry_signature / ProjectWorkspace.entries tam tarama
#  ce_apply_sig / ce_apply_entries / ce_apply_refresh — Uygula: imza / entries / Çalışma Alanı tam yenileme (açık + gözlemci)
#  tree_click_entries  — ağaç tıklaması (project_workspace_action) ProjectWorkspace.entries tam tarama
#  rev_create_boq_rows / rev_create_snap_parse — Anlık Kayıt Oluştur (kayıt yolu): boq_rows ve revizyon arşivi JSON ayrıştırma
#  rev_nochange_boq_rows / rev_nochange_snap_parse — aynı, değişiklik yok yolu
#  boq_open_payload    — Keşif açılışı (boq_refresh + boq2_get geri çağrıları): boq2_payload sayısı
#  code_usage_s        — mst_code_usage süresi (sahte, saniye; medyan / 5)
# Kullanım: ruby tools/perf/g_counts.rb <marine_structures_tools> [blok=30]   (blok × 20 = öğe; 30 → 600)
require 'json'
require 'stringio'
dir = ARGV[0] or abort 'kullanim: ruby tools/perf/g_counts.rb <marine_structures_tools> [blok=30]'
BLOCKS = (ARGV[1] || 30).to_i
require_relative '../golden/sketchup_stub'
$model = Sketchup::Model.new
$stderr_save = $stderr
$stderr = StringIO.new
require File.expand_path(File.join(dir, 'main.rb'))
$stderr = $stderr_save
require_relative 'scale_fixture'
M = MAG::MarineStructuresTools

class Sketchup::Entities
  def add(*e); e.flatten.each { |x| push(x) unless include?(x) }; true; end
end
class Sketchup::Drawingelement
  def locked?; false; end
end
$timers = []
module UI
  def self.start_timer(*_a, &b); $timers << b; $timers.length; end
  def self.stop_timer(id); $timers[id - 1] = nil if id.is_a?(Integer) && id > 0; true; end
end
def run_timers; until (t = $timers.each_with_index.find { |b, _| b }).nil?; $timers[t[1]] = nil; t[0].call; end; end

class Dlg
  attr_reader :out, :cb
  def initialize; @out = []; @cb = {}; end
  def execute_script(j); @out << j; true; end
  def add_action_callback(n, &b); @cb[n] = b; end
  def visible?; true; end
  def method_missing(*_a); nil; end
  def respond_to_missing?(*) true end
end

$cnt = Hash.new(0)
def count(name, mod = M)
  o = mod.method(name)
  mod.define_singleton_method(name) { |*a, &b| $cnt[name] += 1; o.call(*a, &b) }
end
%i[project_workspace_refresh revision_geometry_signature boq_rows boq2_payload].each { |n| count(n) }
# Çalışma Alanı ağacının gerçek taraması: yeni kodda entries_scan (entries kapsam önbelleğinden dönebilir), tabanda entries
SCAN = M::ProjectWorkspace.respond_to?(:entries_scan) ? :entries_scan : :entries
count(SCAN, M::ProjectWorkspace)
module JSON
  class << self
    alias_method :g_parse, :parse
    def parse(s, *a); $cnt[:snap_parse] += 1 if s.is_a?(String) && s.start_with?('[{"revision"'); g_parse(s, *a); end
  end
end

def setup
  perf_build_fixture(BLOCKS)
  M.instance_variable_set(:@mst_pile_idx_cache, nil)
  %i[@workspace_model @workspace_entries @workspace_rows @workspace_timer @controlled_editor_pending @mst_ui_page @workspace_stale].each { |v| M.instance_variable_set(v, nil) }
  $timers = []
  pc = $model.entities.find { |e| e.get_attribute(D, 'element_type') == 'flat_precast' }
  pc.set_attribute(D, 'element_uid', "MST-#{pc.persistent_id}-1700000000-K")
  pc.set_attribute(D, 'editor_formwork_flags', [true, true, true, false, false])
  %w[length_m width_m height_m].zip([5.0, 1.0, 0.25]).each { |k, v| pc.set_attribute(D, k, v) }
  d = Dlg.new
  M.instance_variable_set(:@d, d)
  M.mst_register_flow_callbacks(d)
  M.boq2_register_callbacks(d)
  [d, pc]
end
def key_of(e); JSON.generate([e.persistent_id]); end
res = {}
def take(name); v = $cnt[name]; $cnt[name] = 0; v; end

# G1: işlem sonrası
d, = setup
M.project_workspace_refresh(d); run_timers; $cnt.clear
d.cb['workflow_status'].call(nil, 'project_workspace'); run_timers; $cnt.clear
M::WorkspaceModelObserver.new.onTransactionCommit($model); run_timers
res['ws_commit_page_ws'] = take(:project_workspace_refresh)
d.cb['workflow_status'].call(nil, 'boq'); run_timers; $cnt.clear
M::WorkspaceModelObserver.new.onTransactionCommit($model); run_timers
M::WorkspaceModelObserver.new.onTransactionCommit($model); run_timers
res['ws_commit_page_boq'] = take(:project_workspace_refresh)
M.project_workspace_refresh(d); d.cb['workflow_status'].call(nil, 'project_workspace'); run_timers
res['ws_return'] = take(:project_workspace_refresh)

# ağaç tıklaması
d, pc = setup
M.project_workspace_refresh(d); run_timers; $cnt.clear
M.project_workspace_action(JSON.generate('model_token' => $model.object_id.to_s, 'keys' => [key_of(pc)], 'zoom' => false, 'edit' => false), d); run_timers
res['tree_click_entries'] = take(SCAN)

# G2: Kontrollü Düzenleme
d, pc = setup
M.project_workspace_refresh(d); run_timers; $cnt.clear
req = { 'model_token' => $model.object_id.to_s, 'keys' => [key_of(pc)], 'values' => { 'length_m' => 5.0, 'width_m' => 1.0, 'height_m' => 0.25, 'concrete_class' => 'C40/50' } }
M.controlled_editor_preview(JSON.generate(req), d)
err = d.out.grep(/controlledEditorError/).first
res['ce_preview_error'] = err if err
res['ce_preview_sig'] = take(:revision_geometry_signature)
res['ce_preview_entries'] = take(SCAN)
tok = M.instance_variable_get(:@controlled_editor_pending)&.dig(:token)
mo = M::WorkspaceModelObserver.new
$model.define_singleton_method(:commit_operation) { @ops << [:commit]; mo.onTransactionCommit(self); true }
M.controlled_editor_apply(JSON.generate('token' => tok), d); run_timers
err = d.out.grep(/controlledEditorError/).last
res['ce_apply_error'] = err if err
res['ce_apply_sig'] = take(:revision_geometry_signature)
res['ce_apply_entries'] = take(SCAN)
res['ce_apply_refresh'] = take(:project_workspace_refresh)

# G3: revizyon kaydı
setup; $cnt.clear
M.revision_create_snapshot(Dlg.new)
res['rev_create_boq_rows'] = take(:boq_rows)
res['rev_create_snap_parse'] = take(:snap_parse)
M.revision_create_snapshot(Dlg.new)
res['rev_nochange_boq_rows'] = take(:boq_rows)
res['rev_nochange_snap_parse'] = take(:snap_parse)

# G4: Keşif açılışı (T('boq') → refreshBOQ → boq_refresh = send_boq; boq_pro.js hookT → boq2_get)
d, = setup; $cnt.clear
M.send_boq(d)
d.cb['boq2_get'].call(nil)
res['boq_open_payload'] = take(:boq2_payload)

# G6: mst_code_usage süresi
setup
ts = 5.times.map { t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC); M.mst_code_usage($model); Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 }
res['code_usage_s'] = ts.sort[2].round(4)
all = []; M.collect_elements($model.entities, all)
res['n'] = all.size
puts JSON.generate(res)
