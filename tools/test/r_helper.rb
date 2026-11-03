# R testleri (03.11.2026, G1–G5) ortak yardımcıları. Eklenti ve tools/golden/fixture.rb yüklendikten sonra require edilir.
# Sahte ek: Entities#add, Drawingelement#locked?, UI.start_timer blokları sırayla çalıştırılır (r_timers), sabit saat.
D = 'MAG_MarineStructures'.freeze unless defined?(D)
$now = 1_800_000_000.0
class << Time; def now; Time.at($now); end; end
class Sketchup::Entities
  def add(*e); e.flatten.each { |x| push(x) unless include?(x) }; true; end
end
class Sketchup::Drawingelement
  def locked?; false; end
end
$timers = []
module UI
  def self.start_timer(*_a, &b); $timers << b; $timers.length; end
  def self.stop_timer(id); $timers[id - 1] = nil if id.is_a?(Integer) && id > 0 && id <= $timers.length; true; end
end
def r_timers
  loop do
    i = $timers.index { |b| b }
    break unless i
    b = $timers[i]; $timers[i] = nil; b.call
  end
end

class RDlg
  attr_reader :out, :cb, :html
  def initialize; @out = []; @cb = {}; end
  def execute_script(j); @out << j; true; end
  def add_action_callback(n, &b); @cb[n] = b; end
  def set_html(h); @html = h; end
  def visible?; true; end
  def show; true; end
  def close; true; end
  def method_missing(*_a); nil; end
  def respond_to_missing?(*) true end
end

R_SYS = '{"DOLFEN":["BD-01"],"ISKELE":["ANO-01"],"RIHTIM":["RIHTIM-01"]}'.freeze
# Aks Yöneticisi kaydıyla aynı biçim (mst_normalize_axis_rows; eski kayıt değil)
def r_grid_json
  m = MAG::MarineStructuresTools
  row = ->(n, g) { { 'name' => n, 'gap_m' => g } }
  JSON.generate('ANO-01::ANO-01' => { 'x' => m.mst_normalize_axis_rows([row.('X-01', 0.0), row.('X-02', 5.0)], 'X'),
                                      'y' => m.mst_normalize_axis_rows([row.('A', 0.0), row.('B', 6.0)], 'Y'),
                                      'system_axis_x' => '', 'system_axis_y' => '', 'x_dir' => '+X', 'y_dir' => '+Y' })
end

# Golden fikstür + Aks Yöneticisi kaydı (ANO-01: X-01, X-02 / A, B) + X-02 aksını kullanan kazık P9 (ANO-01) + düzenlenebilir PD1.
def r_setup(names: false)
  golden_build_fixture
  m = MAG::MarineStructuresTools
  %i[@mst_pile_idx_cache @mst_last_audit @workspace_model @workspace_entries @workspace_rows @workspace_timer @workspace_pending_full
     @controlled_editor_pending @mst_ui_page @workspace_stale @mst_send_boq_warned].each { |v| m.instance_variable_set(v, nil) }
  $timers = []
  { 'project_name' => 'GOLDEN', 'project_system_type' => 'ISKELE', 'system_structures_json' => R_SYS, 'active_structure__ISKELE' => 'ANO-01',
    'active_structure__DOLFEN' => 'BD-01', 'active_structure__RIHTIM' => 'RIHTIM-01', 'active_ano' => 'ANO-01', 'axis_grids_json' => r_grid_json,
    'axis_grid_revision' => 'v0.34.55', 'structure_placements_json' => '{}' }.each { |k, v| $model.set_attribute(D, k, v) }
  if names
    $model.set_attribute(D, 'structure_display_names_json', '{"ANO-01":"Ana İskele","ISKELE":"İskele Gövdesi"}')
    $model.set_attribute(D, 'axis_display_names_json', '{"ANO-01::ANO-01":{"x":{"X-01":"Kıyı Aksı"},"y":{"A":"Ön Sıra"}}}')
  end
  p9 = Sketchup::Group.new(1009, gf_pile_attrs('P9', 'structure' => 'ANO-01', 'ano' => 'ANO-01', 'system' => 'ISKELE', 'grid_x_axis' => 'X-02',
                                                    'grid_y_axis' => 'B', 'grid_point' => 'X-02/B', 'infill_enabled' => '0', 'axis_x_m' => 5.0, 'axis_y_m' => 6.0))
  p9.transformation = Geom::Transformation.translation([5.m, 6.m, 1.2.m])
  $model.entities << p9; p9.parent = $model.entities; $all_ents[1009] = p9
  pc = $all_ents[6001]
  { 'element_uid' => 'MST-GOLD-PD1', 'editor_formwork_flags' => [true, true, true, false, false], 'length_m' => 5.0, 'width_m' => 1.0,
    'height_m' => 0.4, 'ano' => 'A1', 'project' => 'GOLDEN' }.each { |k, v| pc.set_attribute(D, k, v) }
  $writes = []
  $model.ops.clear
  $model.selection.clear
  $now = 1_800_000_000.0
  d = RDlg.new
  m.instance_variable_set(:@d, d)
  m.mst_register_flow_callbacks(d)
  m.boq2_register_callbacks(d)
  d
end
def r_target; $all_ents[6001]; end
def r_key(e); JSON.generate([e.persistent_id]); end
def r_req(e, cls, dims = {})
  { 'model_token' => $model.object_id.to_s, 'keys' => [r_key(e)],
    'values' => { 'length_m' => 5.0, 'width_m' => 1.0, 'height_m' => 0.4, 'concrete_class' => cls }.merge(dims) }
end
def r_state_sig
  rows = ([$model] + $all_ents.values.sort_by(&:persistent_id)).map do |e|
    [e.persistent_id, e.attribute_dictionaries.compact.flat_map { |dd| dd.keys.sort.map { |k| [dd.name, k, dd[k].to_s] } }]
  end
  Digest::SHA256.hexdigest(Marshal.dump(rows))[0, 16]
end

# Aks Yöneticisi (gerçek project_ano_axis_manager; HtmlDialog sahte) → geri çağrıları olan diyalog
def r_axis_open
  m = MAG::MarineStructuresTools
  m.define_singleton_method(:mst_html_dialog) { |*_a, **_k| $r_ax = RDlg.new }
  m.project_ano_axis_manager
  $r_ax
end
# Aks Yöneticisi açılış verisiyle aynı yük (değişiklik yok)
def r_axis_payload
  m = MAG::MarineStructuresTools
  systems = {}; grids = {}; active = {}
  %w[DOLFEN ISKELE RIHTIM].each do |s|
    systems[s] = m.mst_structures_for_system(s, $model)
    systems[s].each do |n|
      g = m.mst_axis_grid_for(n, $model, n)
      grids["#{s}::#{n}"] = { 'x' => g['x'].map(&:dup), 'y' => g['y'].map(&:dup),
                              'system_axis_x' => '', 'system_axis_y' => '', 'x_dir' => g['x_dir'], 'y_dir' => g['y_dir'] }
    end
    active[s] = $model.get_attribute(D, "active_structure__#{s}", '').to_s
  end
  { 'project' => $model.get_attribute(D, 'project_name', '').to_s, 'system' => 'ISKELE', 'systems' => systems, 'active' => active, 'grids' => grids,
    'placements' => m.mst_structure_placements($model), 'structure_names' => m.mst_structure_display_names($model), 'code_changes' => [] }
end

# Kazık Özel Ayarları penceresi: başlık metni, nokta listesi metinleri (JS'in ürettiği), save() gövdesi, gömülü payload
def r_capture_override(m, d, payload)
  dlg = nil
  orig = m.method(:mst_html_dialog)
  m.define_singleton_method(:mst_html_dialog) { |*_a, **_k| dlg = RDlg.new }
  m.instance_variable_set(:@pile_override_dialog, nil)
  # gerçek show_dialog sahte HtmlDialog ile çalıştırılır; pile_open_override geri çağrısı oradan alınır
  hd = Class.new(RDlg) { def initialize(*_a, **_k); super(); end }
  UI.send(:remove_const, :HtmlDialog) if UI.const_defined?(:HtmlDialog, false)
  UI.const_set(:HtmlDialog, hd)
  hd.const_set(:STYLE_DIALOG, 0)
  m.instance_variable_set(:@d, nil)
  m.show_dialog rescue nil
  main = m.instance_variable_get(:@d)
  main.cb['pile_open_override'].call(nil, JSON.generate(payload))
  m.define_singleton_method(:mst_html_dialog, &orig)
  m.instance_variable_set(:@d, d)
  html = dlg ? dlg.html.to_s : ''
  head = html[%r{<b>⚙ Kazık Özel Ayarları</b><span>(.*?)</span>}, 1]
  emb = html[/const payload=(.*?);(?:const mstLbl|let cur)/, 1]
  lbl = html[/const mstLbl=(.*?);let cur/, 1]
  pl = JSON.parse(emb)
  opts = if lbl
           l = JSON.parse(lbl)
           pl['points'].each_with_index.map { |p, i| "#{l['axis']}/#{l['points'][i] || p['point_name']}" }
         else
           pl['points'].map { |p| "#{pl['axis_name']}/#{p['point_name']}" }
         end
  { head: head, options: opts, save: html[/function save\(\)\{.*?\)\)\}/], payload: emb }
end
