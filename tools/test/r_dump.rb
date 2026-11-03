# R (03.11.2026, gecikme düzeltmeleri G1–G5) — eşdeğerlik dökümü. Bir kaynak klasörü için senaryoları çalıştırır, her senaryonun
# diyalog çıktısını, model yazımlarını, işlemlerini ve son öznitelik durumunu tek JSON satırı olarak basar. r_gecikme.rb bunu
# yeni kaynak ve taban (c1e3a59) için ayrı süreçte çalıştırıp karşılaştırır. Tek başına GEÇTİ/KALDI basmaz.
# Eklenti golden-master sahtesiyle (tools/golden/sketchup_stub.rb) gerçek yükleme sırasıyla yüklenir; model tools/golden/fixture.rb.
# Kullanim: ruby tools/test/r_dump.rb <marine_structures_tools>
require 'digest'
require 'stringio'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/r_dump.rb <marine_structures_tools klasoru>'
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.expand_path(File.join(dir, 'main.rb'))
$stderr = $stderr_keep
require_relative '../golden/fixture'
require_relative 'r_helper'
M = MAG::MarineStructuresTools

out = {}
mask = ->(a) { a.map { |s| s.gsub(/"model_token":"\d+"/, '"model_token":"*"').gsub(/"token":"[0-9a-f]{32}"/, '"token":"*"').gsub(/model_token:\d+/, 'model_token:*') } }
h = ->(x) { puts "V #{x.inspect[0, 700]}" if ENV["RDUMP_V"]; Digest::SHA256.hexdigest(Marshal.dump(x))[0, 16] }

# --- G1: Çalışma Alanı; işlem Keşif sayfasındayken, sonra Çalışma Alanı'na dönüş ---
d = r_setup
M.project_workspace_refresh(d); r_timers
d.cb['workflow_status'].call(nil, 'boq'); r_timers
pc = r_target
pc.set_attribute(D, 'concrete_class', 'C40/50')   # işlemle değişen öznitelik
M::WorkspaceModelObserver.new.onTransactionCommit($model); r_timers
d.out.clear
M.project_workspace_refresh(d); d.cb['workflow_status'].call(nil, 'project_workspace'); r_timers   # T('project_workspace') + refresh()
out['ws_return_loaded'] = h.(mask.(d.out.grep(/projectWorkspaceLoaded/)).last)
d.out.clear
M.project_workspace_action(JSON.generate('model_token' => $model.object_id.to_s, 'keys' => [r_key(pc)], 'zoom' => true, 'edit' => false), d); r_timers
out['tree_click'] = h.([mask.(d.out), $model.selection.map(&:persistent_id)])
d.out.clear
M.project_workspace_action(JSON.generate('model_token' => $model.object_id.to_s, 'keys' => [r_key(pc)], 'zoom' => false, 'edit' => true), d); r_timers
out['tree_edit'] = h.(mask.(d.out))

# --- G2: Kontrollü Düzenleme (beton sınıfı; geometri değişikliği → hata yolu) ---
d = r_setup
M.project_workspace_refresh(d); r_timers
pc = r_target
req = r_req(pc, 'C40/50')
w0 = $writes.size
M.controlled_editor_preview(JSON.generate(req), d)
out['ce_preview'] = h.(mask.(d.out))
tok = M.instance_variable_get(:@controlled_editor_pending)&.dig(:token)
d.out.clear
M.controlled_editor_apply(JSON.generate('token' => tok), d); r_timers
out['ce_apply_out'] = h.(mask.(d.out.reject { |s| s.start_with?('projectWorkspaceLoaded') }))
out['ce_apply_loaded_last'] = h.(mask.(d.out.grep(/projectWorkspaceLoaded/)).last)
out['ce_apply_state'] = [r_state_sig, $model.ops, $writes[w0..].map { |pid, dd, k| [pid, dd, k] }].then { |x| h.(x) }
d.out.clear
M.controlled_editor_preview(JSON.generate(r_req(pc, 'C40/50', 'length_m' => 6.0)), d)
out['ce_geom_error'] = mask.(d.out)
# önizlemeden sonra hedefin özniteliği değişti → bayat
d.out.clear
M.controlled_editor_preview(JSON.generate(r_req(pc, 'C45/55')), d)
tok = M.instance_variable_get(:@controlled_editor_pending)&.dig(:token)
pc.set_attribute(D, 'formwork_area_m2', 7.5)
M.controlled_editor_apply(JSON.generate('token' => tok), d); r_timers
out['ce_stale_target'] = mask.(d.out.grep(/controlledEditorError/))

# --- G3: revizyon kaydı (kayıt, değişiklik yok, değişiklik sonrası kayıt) ---
d = r_setup
w0 = $writes.size; $ui_msgs = []
r1 = M.revision_create_snapshot(d)
r2 = M.revision_create_snapshot(d)
$all_ents[6002].set_attribute(D, 'concrete_volume_m3', 1.75)
r3 = M.revision_create_snapshot(d)
arch = $model.get_attribute('MAG_MST_RevisionLog', 'snapshots', '').to_s
out['rev'] = h.([r1, r2, r3, mask.(d.out), $ui_msgs, $model.ops, $writes[w0..].map { |pid, dd, k| [pid, dd, k] }])
out['rev_archive_sha'] = Digest::SHA256.hexdigest(arch)
d.out.clear
M.revision_send(d)
out['rev_send'] = h.(mask.(d.out))

# --- G4: Keşif açılışı (boq_refresh = send_boq, ardından boq2_get) ---
d = r_setup
M.send_boq(d); d.cb['boq2_get'].call(nil)
out['boq_open'] = h.(mask.(d.out))

# --- G5: Aks Yöneticisi kaydı (değişiklik var), kazık raporu ve özel ayar penceresi (görünen ad yok) ---
d = r_setup
ax = r_axis_open
w0 = $writes.size; o0 = $model.ops.size; $ui_msgs = []
x = r_axis_payload
x['grids']['ISKELE::ANO-01']['x'] << { 'name' => 'X-03', 'gap_m' => 4.0 }
ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(x))
out['axis_change'] = h.([$ui_msgs, $model.ops[o0..], $writes[w0..].map { |pid, dd, k| [pid, dd, k] }, ax.out.map { |s| s.sub(/Kaydedildi.*/, 'Kaydedildi') }, r_state_sig])
d = r_setup
out['takeoff'] = h.((M.takeoff('all').html rescue $!.message))
ra = M::RelationshipAudit.analyze($model)[:records].map { |r| [r[:key], r[:checks]] }
out['relationship_audit'] = h.(ra)
pd = r_capture_override(M, d, 'axis_name' => 'X-01', 'points' => [{ 'point_index' => 0, 'point_name' => 'A', 'data' => {} }])
out['override_html'] = h.(pd)
puts "RDUMP #{JSON.generate(out)}"
