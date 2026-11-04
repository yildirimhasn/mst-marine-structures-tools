# K1 (ADR-0515-K1, docs/duzeltme/31; 04.11.2026) — Aks Yöneticisi "Yapıyı Kopyala": kaynak yapının tüm MST elemanları, aks ağı ve
# model düzeyi yapı kayıtları tek işlemde N kopya (structure_copy.rb) + mstBKAddProjectStructure işlem düzeltmesi.
# Gerçek main.rb (golden SketchUp sahtesi) yüklenir. Sahte ekleri: Group#copy EN KÖTÜ DURUM (tanım paylaşılır, öznitelik kopyalanmaz),
# Group / ComponentInstance#make_unique (iç Group'lar tanımı paylaşmaya devam eder), Entities#add_instance, transform!,
# start_operation anlık görüntü + abort_operation geri yükleme (sahte modelin tamamı).
# Kanıt düzeyi: sahte nesne. SketchUp'ın gerçek Group#copy / make_unique öznitelik ve tanım davranışı, persistent_id, Ctrl+Z / Redo,
# kaydet-aç ve gözlemciler KANITLANMAZ.
# Kullanim: ruby tools/test/k1_structure_copy.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/k1_structure_copy.rb <marine_structures_tools klasoru>'
DIR = File.expand_path(dir)
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(DIR, 'main.rb')
$stderr = $stderr_keep
require_relative '../golden/fixture'
require_relative 'r_helper'
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze unless defined?(D)

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 260]} (beklenen #{exp.inspect[0, 260]})"
end
def obs(label, v); puts "GÖZLEM #{label}: #{v.inspect[0, 400]}"; end
main_src = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
HAVE = M.respond_to?(:mst_structure_copy_plan) && M.respond_to?(:mst_structure_copy_apply!) && M.respond_to?(:mst_structure_copy_verify)
t('structure_copy.rb yüklü: mst_structure_copy_plan / _apply! / _verify tanımlı', HAVE, true)

# ---------------------------------------------------------------- sahte ekleri
$k1_copy_attrs = false   # SketchUp Group#copy'nin öznitelik kopyalayıp kopyalamadığı doğrulanmadı: en kötü durum
def k1_reg(e); ($all_ents ||= {})[e.persistent_id] = e; e; end
class Sketchup::Entity
  def transform!(tr); @transformation = tr * @transformation; self; end
end
class Sketchup::Entities
  def add_instance(defn, tr)
    i = Sketchup::ComponentInstance.new(nil, {}); i.definition = defn; i.transformation = tr; push(i); i.parent = self; k1_reg(i)
  end
end
def k1_clone(c)
  n = c.dup
  n.persistent_id = ($pid_seq += 1)
  n.instance_variable_set(:@attrs, c.instance_variable_get(:@attrs).dup)   # tanım kopyası iç öğe özniteliklerini taşır (varsayım)
  if c.is_a?(Sketchup::Group)
    d = c.definition; n.instance_variable_set(:@definition, d); d.instances << n   # iç Group tanımı paylaşmaya devam eder
  elsif c.is_a?(Sketchup::ComponentInstance)
    c.definition.instances << n
  end
  k1_reg(n)
end
class Sketchup::Group
  def copy
    d = definition
    g = Sketchup::Group.new(nil, {})
    g.instance_variable_set(:@entities, @entities); g.instance_variable_set(:@definition, d); d.instances << g
    g.transformation = @transformation; g.name = @name; g.layer = @layer; g.material = @material; g.hidden = @hidden
    g.instance_variable_set(:@attrs, @attrs.dup) if $k1_copy_attrs
    $model.entities << g; g.parent = $model; ($k1_log ||= []) << [:copy, persistent_id]
    k1_reg(g)
  end
  def make_unique
    d = definition
    return self if d.count_instances <= 1
    d.instances.delete(self)
    ne = Sketchup::Entities.new(@entities.map { |c| k1_clone(c) }); ne.parent = self; ne.each { |c| c.parent = ne }
    @entities = ne
    nd = Sketchup::ComponentDefinition.new(nil, {}); nd.entities = ne; nd.instances << self; @definition = nd
    ($k1_log ||= []) << [:group_unique, persistent_id]
    self
  end
end
class Sketchup::ComponentInstance
  def make_unique
    old = @definition
    return self if old.count_instances <= 1
    nd = Sketchup::ComponentDefinition.new(nil, {})
    nd.entities = Sketchup::Entities.new(old.entities.map { |c| k1_clone(c) }); nd.entities.parent = nd; nd.entities.each { |c| c.parent = nd.entities }
    self.definition = nd
    $model.definitions << nd
    ($k1_log ||= []) << [:ci_unique, persistent_id]
    self
  end
end
# anlık görüntü / geri yükleme: bilinen bütün varlıkların durumu + Entities içerikleri
def k1_snapshot
  ents = {}
  objs = ([$model] + $all_ents.values + $model.definitions.to_a + $all_ents.values.select { |e| e.is_a?(Sketchup::ComponentInstance) }.map(&:definition)).uniq
  st = objs.map do |o|
    iv = o.instance_variables.map { |v| [v, o.instance_variable_get(v)] }.to_h
    iv[:@attrs] = iv[:@attrs].dup if iv[:@attrs]
    iv[:@instances] = iv[:@instances].dup if iv[:@instances]
    [:@entities].each { |k| ents[iv[k].object_id] = [iv[k], iv[k].to_a.dup] if iv[k].is_a?(Sketchup::Entities) }
    [o, iv]
  end
  ents[$model.definitions.object_id] = [$model.definitions, $model.definitions.to_a.dup]
  { st: st, ents: ents.values, all: $all_ents.dup, pid: $pid_seq }
end
def k1_restore(s)
  s[:st].each { |o, iv| iv.each { |k, v| o.instance_variable_set(k, (k == :@attrs || k == :@instances) ? v.dup : v) } }
  s[:ents].each { |e, arr| e.replace(arr) }
  $all_ents = s[:all].dup
end
class Sketchup::Model
  def start_operation(*a); @ops << [:start, a[0]]; $k1_snap = k1_snapshot; true; end
  def commit_operation; @ops << [:commit]; $k1_snap = nil; true; end
  def abort_operation; @ops << [:abort]; k1_restore($k1_snap) if $k1_snap; $k1_snap = nil; true; end
end
def k1_attrs(e); e.attribute_dictionaries.compact.flat_map { |dd| dd.keys.sort.map { |k| [dd.name, k, dd[k].inspect] } }.sort; end
# sahte modelin tam dökümü (kökten; iç Group'lar, Component tanımları ve öznitelikleri)
def k1_dump
  de = lambda do |e|
    row = [e.class.name, e.persistent_id, e.name.to_s, e.transformation.to_a.map { |v| v.round(6) }, k1_attrs(e)]
    row << e.entities.map { |c| de.(c) } if e.is_a?(Sketchup::Group)
    row << [e.definition.persistent_id, k1_attrs(e.definition), e.definition.entities.map { |c| de.(c) }] if e.is_a?(Sketchup::ComponentInstance)
    row
  end
  [k1_attrs($model), $model.entities.map { |e| de.(e) }, $model.definitions.map(&:persistent_id)]
end
def k1_ops; $model.ops.map(&:first); end

# ---------------------------------------------------------------- fikstür
G = Sketchup::Group; CI = Sketchup::ComponentInstance; CD = Sketchup::ComponentDefinition
def tr(x, y, z = 0); Geom::Transformation.translation([x.m, y.m, z.m]); end
def g(pid, attrs, kids = [], at = nil)
  e = G.new(pid, attrs); e.entities = kids; e.transformation = at if at; e
end
def own(code, sys = 'ISKELE'); { 'system' => sys, 'structure' => code, 'ano' => code, 'zone' => code, 'project' => 'GOLDEN' }; end
GRID = { 'x' => M.mst_normalize_axis_rows([{ 'name' => 'X-01', 'gap_m' => 0.0 }, { 'name' => 'X-02', 'gap_m' => 5.0 }], 'X'),
         'y' => M.mst_normalize_axis_rows([{ 'name' => 'A', 'gap_m' => 0.0 }], 'Y'), 'system_axis_x' => '', 'system_axis_y' => '', 'x_dir' => '+X', 'y_dir' => '+Y' }.freeze
JG_DATA = JSON.generate('type_id' => 'JG-01', 'diameter' => 800, 'top' => 0, 'bottom' => -10, 'ano' => 'ANO-01', 'project' => 'GOLDEN').freeze

def k1_build(extra: nil)
  $model = Sketchup::Model.new
  $pid_seq = 900_000
  $all_ents = {}
  $k1_log = []
  pile = ->(pid, id, more = {}) { gf_pile_attrs(id, own('ANO-01').merge('element_uid' => "MST-#{pid}-1", 'uid_owner_pid' => pid, 'global_pile_id' => id, 'structure_zone' => 'ANO-01').merge(more)) }
  i1 = g(2101, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => 5.0, 'concrete_class' => 'C30/37', 'element_uid' => 'MST-2101-1', 'ano' => 'ANO-01')
  prs = g(2102, 'element_type' => 'pile_rebar_set', 'element_uid' => 'MST-2102-1', 'parent_uid' => 'MST-1101-1')
  p1 = g(1101, pile.(1101, 'P-001', 'global_x_m' => 100.0, 'global_y_m' => 50.0, 'axis_x_m' => 0.0, 'grid_x_axis' => 'X-01', 'infill_enabled' => '1',
                     'progress_items_json' => GB_PJ, 'progress_status' => 'Onaylandı', 'progress_inherited_json' => GB_PJ, 'progress_inherited_status' => 'Onaylandı',
                     'progress_inherited_history_json' => '[]', 'dependency_child_uids' => 'MST-1201-1'), [i1, prs], tr(0, 0, 1.2))
  p2 = g(1102, pile.(1102, 'P-002', 'global_x_m' => 105.0, 'global_y_m' => 50.0, 'axis_x_m' => 5.0, 'grid_x_axis' => 'X-02', 'orientation_mode' => 'BATTERED',
                     'batter_ratio' => 1.0 / 6.0, 'azimuth_deg' => 90.0, 'infill_enabled' => '1', 'infill_concrete_volume_m3' => 4.0), [], tr(5, 0, 1.2))
  pdef = CD.new(3101, 'mst_def_kind' => 'pile', 'mst_def_key' => 'K-1016')
  si = g(2103, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => 5.0, 'concrete_class' => 'C30/37')
  pdef.entities = Sketchup::Entities.new([si]); si.parent = pdef.entities
  p3 = CI.new(1103, pile.(1103, 'P-003', 'global_x_m' => 110.0, 'global_y_m' => 50.0, 'infill_enabled' => '1', 'infill_concrete_volume_m3' => 5.0))
  p3.definition = pdef; p3.transformation = tr(10, 0, 1.2)
  lay = g(1100, { 'element_type' => 'pile_layout', 'system' => 'ISKELE', 'structure' => 'ANO-01', 'global_origin_x_m' => 100.0, 'global_origin_y_m' => 50.0 }, [p1, p2, p3])
  bar = g(2203, 'element_type' => 'rebar_bar', 'diameter_mm' => 20.0, 'length_m' => 9.0)
  rs1 = g(2201, { 'element_type' => 'head_beam_rebar_set', 'element_uid' => 'MST-2201-1', 'parent_uid' => 'MST-1201-1', 'rebar_t' => 0.5 }, [bar])
  cv1 = g(2202, 'element_type' => 'bk_culvert', 'element_uid' => 'MST-2202-1', 'parent_uid' => 'MST-1201-1')
  bk_base = { 'element_type' => 'head_beam', 'concrete_volume_m3' => 10.0, 'formwork_area_m2' => 20.0, 'concrete_class' => 'C30/37', 'length_m' => 10.0,
              'width_m' => 1.2, 'height_m' => 1.0, 'bk_revision_no' => 3, 'type_id' => 'BK-T01', 'library_type_id' => 'BK-T01', 'type_signature' => 'SIG-BK' }
  bk1 = g(1201, bk_base.merge(own('ANO-01')).merge('head_beam_id' => 'BK-001', 'element_uid' => 'MST-1201-1', 'connected_pile_persistent_ids' => '1101, 1102',
                                                   'connected_pile_ids' => 'P-001,P-002', 'global_x_m' => 100.0, 'global_y_m' => 50.0), [rs1, cv1], tr(0, 0, 2))
  bkdef = CD.new(3201, 'mst_def_kind' => 'bk', 'mst_def_key' => 'BKK-10')
  rs2 = g(2301, 'element_type' => 'head_beam_rebar_set', 'element_uid' => 'MST-2301-1', 'parent_uid' => 'MST-1202-1')
  bkdef.entities = Sketchup::Entities.new([rs2]); rs2.parent = bkdef.entities
  bk2 = CI.new(1202, bk_base.merge(own('ANO-01')).merge('head_beam_id' => 'BK-002', 'element_uid' => 'MST-1202-1', 'connected_pile_persistent_ids' => '1103',
                                                        'connected_pile_ids' => 'P-003', 'concrete_volume_m3' => 8.0))
  bk2.definition = bkdef; bk2.transformation = tr(10, 0, 2); bk2.name = 'BK-002'
  pc1 = g(1301, own('ANO-01').merge('element_type' => 'flat_precast', 'precast_id' => 'PD-001', 'element_uid' => 'MST-1301-1', 'support_left_pid' => 1201,
                                    'support_right_pid' => 1202, 'support_left_uid' => 'MST-1201-1', 'support_right_uid' => 'MST-1202-1',
                                    'support_uids' => 'MST-1201-1,MST-1202-1', 'precast_type_id' => 'PT-01', 'type_id' => 'PD-T01', 'library_type_id' => 'PD-T01',
                                    'type_signature' => 'SIG-PD', 'concrete_volume_m3' => 1.5, 'formwork_area_m2' => 6.0, 'concrete_class' => 'C35/45'))
  drs = g(2401, 'element_type' => 'deck_rebar_set', 'element_uid' => 'MST-2401-1', 'parent_uid' => 'MST-1401-1')
  d1 = g(1401, own('ANO-01').merge('element_type' => 'deck_slab', 'deck_id' => 'D-001', 'element_uid' => 'MST-1401-1', 'support_pids' => '1201,1202',
                                   'support_uids' => 'MST-1201-1,MST-1202-1', 'support_hb_ids' => 'BK-001,BK-002', 'deck_revision_no' => 2,
                                   'concrete_volume_m3' => 15.0, 'formwork_area_m2' => 20.0, 'concrete_class' => 'C30/37'), [drs])
  t1 = g(1402, 'element_type' => 'deck_topping', 'parent_deck_id' => 'D-001', 'parent_uid' => 'MST-1401-1', 'topping_id' => 'TOP-D-001',
               'parent_deck_revision_no' => 2, 'concrete_volume_m3' => 6.0, 'ano_id' => 'ANO-01', 'element_uid' => 'MST-1402-1')
  cb1 = g(1403, own('ANO-01').merge('element_type' => 'curb', 'curb_id' => 'B-D-001-1', 'parent_deck_id' => 'D-001', 'parent_uid' => 'MST-1401-1',
                                    'parent_deck_uid' => 'MST-1401-1', 'parent_deck_revision_no' => 2, 'element_uid' => 'MST-1403-1',
                                    'concrete_volume_m3' => 1.2, 'formwork_area_m2' => 6.0, 'concrete_class' => 'C35/45'))
  segs = [g(1502, 'element_type' => 'crown_wall_segment', 'parent_crown_id' => 'KR-001', 'section_type' => 'A'),
          g(1503, 'element_type' => 'crown_wall_segment', 'parent_crown_id' => 'KR-001', 'section_type' => 'B')]
  kr = g(1501, own('ANO-01').merge('element_type' => 'crown_wall', 'id' => 'KR-001', 'element_uid' => 'MST-1501-1', 'concrete_volume_m3' => 20.0,
                                   'formwork_area_m2' => 40.0, 'concrete_class' => 'C30/37'), segs)
  kr.name = 'KR-001'
  jg = g(1601, 'element_type' => 'jet_grout', 'element_uid' => '0f0e-uuid-jg', 'jet_grout_data' => JG_DATA, 'type_id' => 'JG-01', 'project' => 'GOLDEN', 'ano' => 'ANO-01', 'axis' => 'X-01')
  acc = g(1701, 'element_type' => 'accessory', 'ano' => 'ANO-01', 'element_uid' => 'acc-uuid', 'accessory_type' => 'Usturmaça')
  pc2 = g(1302, own('ANO-01').merge('element_type' => 'flat_precast', 'precast_id' => 'PD-002', 'element_uid' => 'MST-1302-1', 'support_left_pid' => 1201,
                                    'concrete_volume_m3' => 1.0, 'formwork_area_m2' => 4.0, 'concrete_class' => 'C35/45'))
  pl = g(1800, { 'element_type' => 'precast_layout' }, [pc2]); pl.name = 'Prekast Layout'
  vis = g(1850, 'element_type' => 'axis_grid_visual', 'ano' => 'ANO-01', 'zone' => 'ANO-01')
  bk9 = g(1901, bk_base.merge(own('ANO-05')).merge('head_beam_id' => 'BK-009', 'element_uid' => 'MST-1901-1'))
  bkr = g(1911, bk_base.merge(own('RIHTIM-01', 'RIHTIM')).merge('head_beam_id' => 'BK-101', 'element_uid' => 'MST-1911-1'))
  dd = g(1921, own('BD-01', 'DOLFEN').merge('element_type' => 'deck_slab', 'deck_id' => 'D-101', 'element_uid' => 'MST-1921-1', 'concrete_volume_m3' => 7.0))
  roots = [lay, bk1, bk2, pc1, d1, t1, cb1, kr, jg, acc, pl, vis, bk9, bkr, dd]
  extra&.call(roots)
  $model.entities = Sketchup::Entities.new(roots)
  $model.entities.parent = $model
  roots.each { |e| e.parent = $model }   # SketchUp: kök öğenin parent'ı Model
  $model.definitions = Sketchup::Entities.new([pdef, bkdef])
  walk = ->(list) { list.each { |e| k1_reg(e); walk.(e.entities) if e.is_a?(G) } }
  walk.(roots); walk.(pdef.entities); walk.(bkdef.entities)
  { 'project_name' => 'GOLDEN', 'project_system_type' => 'ISKELE', 'active_structure__ISKELE' => 'ANO-01', 'active_structure__DOLFEN' => 'BD-01',
    'active_structure__RIHTIM' => 'RIHTIM-01', 'active_ano' => 'ANO-01',
    'system_structures_json' => '{"DOLFEN":["BD-01"],"ISKELE":["ANO-01","ANO-05"],"RIHTIM":["RIHTIM-01"]}',
    'axis_grids_json' => JSON.generate('ANO-01::ANO-01' => GRID, 'ANO-05::ANO-05' => GRID, 'RIHTIM-01::RIHTIM-01' => GRID, 'BD-01::BD-01' => GRID),
    'structure_placements_json' => JSON.generate('ISKELE::ANO-01' => { 'x_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 100.0 }, 'y_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 50.0 } }),
    'structure_display_names_json' => '{}' }.each { |k, v| $model.set_attribute(D, k, v) }
  %i[@mst_pile_idx_cache @mst_def_cache @mst_scan_batch_on @mst_read_batch_on].each { |v| M.instance_variable_set(v, nil) }
  $model.ops.clear
  $writes = []
  $grid_draws = []
  { lay: lay, p1: p1, p2: p2, p3: p3, bk1: bk1, bk2: bk2, pc1: pc1, pc2: pc2, d1: d1, t1: t1, cb1: cb1, kr: kr, jg: jg, acc: acc, pl: pl, bk9: bk9, bkr: bkr, dd: dd,
    rs1: rs1, rs2: rs2, cv1: cv1, drs: drs, i1: i1, si: si, bar: bar, pdef: pdef, bkdef: bkdef }
end
M.define_singleton_method(:mst_show_grid_visual) { |ano = nil, _m = nil, zone = nil, own_op = true, sys = nil| $grid_draws << [ano, zone, own_op, sys]; nil }
M.define_singleton_method(:mst_structure_copy_fault!) { |stage, i| $k1_fault&.call(stage, i) } if HAVE
$msgs = []
UI.define_singleton_method(:messagebox) { |*a| $msgs << a.first.to_s; 6 }
$ib = []
UI.define_singleton_method(:inputbox) { |*_a| $ib.shift }

def a(e, k); e.get_attribute(D, k); end
def ixs(code, sys = 'ISKELE')
  all = []; M.collect_elements($model.entities, all)
  ex = []; seen = {}; all.each { |e| seen[e] = true }; M.mst_code_usage_extra($model.entities, seen, ex, Hash.new(0), {})
  (all + ex).uniq.select { |e| e.valid? && a(e, 'element_type') != 'accessory' && M.mst_element_in_structure?(e, sys, code) }
end
def root_copies(src); $model.entities.select { |e| a(e, 'copied_from_uid') == a(src, 'element_uid') && !a(src, 'element_uid').to_s.empty? }; end
def kinds(list); list.group_by { |e| a(e, 'element_type').to_s }.map { |k, v| [k, v.length] }.sort; end
def req(h = {}); { 'system' => 'ISKELE', 'structure' => 'ANO-01', 'count' => '2', 'codes' => [], 'names' => [], 'dx' => '30', 'dy' => '0', 'dz' => '0' }.merge(h); end
def plan_of(h = {}); M.mst_structure_copy_plan(req(h), $model); end

unless HAVE
  puts "#{$ok} geçti, #{$bad} kaldı"
  exit 1
end

# ================================================================ 1) N=2 başarı (ANO-01 → ANO-02, ANO-03)
f = k1_build
before_src = M.mst_sc_signature(M.mst_structure_copy_plan(req, $model)['roots']) rescue nil
$writes = []; $model.ops.clear
pl = plan_of('names' => ['', 'Kuzey Kolu'])
t('1 ön kontrol hatasız', pl['errors'], [])
t('1 kod önerisi: son sayı artırılır (ANO-05 dolu değil, ANO-02/03)', pl['codes'], %w[ANO-02 ANO-03])
t('1 ön kontrol işlem açmaz, yazmaz', [k1_ops, $writes.length], [[], 0])
t('1 aksesuar sayısı (kopyalanmaz)', pl['accessories'], 1)
src_dump = k1_dump
res = M.mst_structure_copy_apply!(pl, $model)
t('1 sonuç başarılı', [res['ok'], res['error']], [true, nil])
t('1 tek işlem: start + commit (commit_with_dependencies), abort yok', $model.ops, [[:start, 'MST Yapı Kopyala ×2'], [:commit]])
t('1 mesaj: "1 aksesuar kopyalanmadı, çizelgeye elle ekleyin"', res['message'].to_s.include?('1 aksesuar kopyalanmadı, çizelgeye elle ekleyin'), true)
src_items = ixs('ANO-01')
%w[ANO-02 ANO-03].each_with_index do |c, ii|
  k = ii + 1
  cp = ixs(c)
  t("1 #{c}: tür bazında sayı = kaynak", kinds(cp), kinds(src_items))
  bk1c = cp.find { |e| a(e, 'copied_from_uid') == 'MST-1201-1' }
  bk2c = cp.find { |e| a(e, 'copied_from_uid') == 'MST-1202-1' }
  pcs = cp.select { |e| a(e, 'copied_from_uid') == 'MST-1301-1' }
  t("1 #{c}: BK1 / BK2 / PD1 kopyası tek", [bk1c.nil?, bk2c.nil?, pcs.length], [false, false, 1])
  piles = cp.select { |e| a(e, 'element_type') == 'steel_pipe_pile' }
  by = ->(u) { cp.find { |e| a(e, 'copied_from_uid') == u } }
  p1c = by.('MST-1101-1'); p2c = by.('MST-1102-1'); p3c = by.('MST-1103-1')
  t("1 #{c}: BK1 connected_pile_persistent_ids kopya kazıklara (biçim korunur)", a(bk1c, 'connected_pile_persistent_ids'), "#{p1c.persistent_id}, #{p2c.persistent_id}")
  t("1 #{c}: BK1 connected_pile_ids yeni kazık ID'lerine", a(bk1c, 'connected_pile_ids'), "#{a(p1c, 'pile_id')},#{a(p2c, 'pile_id')}")
  t("1 #{c}: BK2 (Component) bağlı kazık P3 kopyası", [a(bk2c, 'connected_pile_persistent_ids'), a(bk2c, 'connected_pile_ids')], [p3c.persistent_id.to_s, a(p3c, 'pile_id')])
  pc = pcs.first
  t("1 #{c}: prekast mesnetleri (PID Integer + UID) kopya BK'lara", [a(pc, 'support_left_pid'), a(pc, 'support_right_pid'), a(pc, 'support_left_uid'), a(pc, 'support_uids')],
    [bk1c.persistent_id, bk2c.persistent_id, a(bk1c, 'element_uid'), "#{a(bk1c, 'element_uid')},#{a(bk2c, 'element_uid')}"])
  dc = by.('MST-1401-1'); tc = $model.entities.find { |e| a(e, 'copied_from_uid') == 'MST-1402-1' && a(e, 'parent_uid') == a(dc, 'element_uid') }; cc = by.('MST-1403-1'); pc2c = by.('MST-1302-1'); krc = by.('MST-1501-1')
  t("1 #{c}: döşeme mesnet PID / UID / BK ID", [a(dc, 'support_pids'), a(dc, 'support_uids'), a(dc, 'support_hb_ids')],
    ["#{bk1c.persistent_id},#{bk2c.persistent_id}", "#{a(bk1c, 'element_uid')},#{a(bk2c, 'element_uid')}", "#{a(bk1c, 'head_beam_id')},#{a(bk2c, 'head_beam_id')}"])
  t("1 #{c}: tretuvar → kopya döşeme (parent_deck_id / parent_uid / parent_deck_uid)", [a(cc, 'parent_deck_id'), a(cc, 'parent_uid'), a(cc, 'parent_deck_uid')],
    [a(dc, 'deck_id'), a(dc, 'element_uid'), a(dc, 'element_uid')])
  t("1 #{c}: kaplama (kökte, ano yok) kopyalandı → kopya döşeme; topping_id / ano_id", [tc.nil?, tc && a(tc, 'parent_deck_id'), tc && a(tc, 'parent_uid'), tc && a(tc, 'topping_id'), tc && a(tc, 'ano_id')],
    [false, a(dc, 'deck_id'), a(dc, 'element_uid'), "TOP-#{a(dc, 'deck_id')}", c])
  t("1 #{c}: kapsayıcıdaki prekast (Prekast Layout) mesnedi kopya BK1", a(pc2c, 'support_left_pid'), bk1c.persistent_id)
  rsc = bk1c.entities.find { |x| a(x, 'element_type') == 'head_beam_rebar_set' }
  cvc = bk1c.entities.find { |x| a(x, 'element_type') == 'bk_culvert' }
  t("1 #{c}: BK1 donatı seti + menfez yeni UID, parent_uid kopya BK1", [rsc.equal?(f[:rs1]), a(rsc, 'parent_uid'), a(cvc, 'parent_uid'), a(rsc, 'copied_from_uid'), a(rsc, 'element_uid') =~ /\AMST-#{rsc.persistent_id}-\d+-C\z/ ? true : false],
    [false, a(bk1c, 'element_uid'), a(bk1c, 'element_uid'), 'MST-2201-1', true])
  barc = rsc.entities.first
  t("1 #{c}: iç içe donatı çubuğu ayrı nesne, öznitelik var", [barc.equal?(f[:bar]), a(barc, 'diameter_mm')], [false, 20.0])
  rs2c = bk2c.definition.entities.first
  t("1 #{c}: Component BK ayrık tanım; iç donatı seti yeni UID → kopya BK2", [bk2c.definition.equal?(f[:bkdef]), a(rs2c, 'parent_uid'), a(rs2c, 'copied_from_uid')],
    [false, a(bk2c, 'element_uid'), 'MST-2301-1'])
  t("1 #{c}: ayrılan BK tanımı mst_def_key taşımaz, mst_def_unique_of = BKK-10", [bk2c.definition.get_attribute(D, 'mst_def_key'), bk2c.definition.get_attribute(D, 'mst_def_unique_of')], [nil, 'BKK-10'])
  t("1 #{c}: Component kazık gövde tanımı paylaşılır", p3c.definition.equal?(f[:pdef]), true)
  i1c = p1c.entities.find { |x| a(x, 'element_type') == 'pile_infill_concrete' }
  t("1 #{c}: kazık içi beton yeni UID, copied_from_uid, ayrı nesne", [i1c.equal?(f[:i1]), a(i1c, 'copied_from_uid'), a(i1c, 'ano')], [false, 'MST-2101-1', c])
  t("1 #{c}: kronman segmentleri parent_crown_id = KR-001 (kronman id kuralı değişmez)", krc.entities.map { |x| a(x, 'parent_crown_id') }, %w[KR-001 KR-001])
  jgc = $model.entities.find { |e| a(e, 'copied_from_uid') == '0f0e-uuid-jg' && a(e, 'ano') == c }
  t("1 #{c}: jet grout kopyası; jet_grout_data ano = #{c}", [jgc.nil?, jgc && JSON.parse(a(jgc, 'jet_grout_data'))['ano']], [false, c])
  t("1 #{c}: ano / structure / zone yeni kod, system aynı (BK1, P1, PD2)", [bk1c, p1c, pc2c].map { |e| [a(e, 'ano'), a(e, 'structure'), a(e, 'zone'), a(e, 'system')] }, [[c, c, c, 'ISKELE']] * 3)
  t("1 #{c}: structure_zone yeni kod", a(p1c, 'structure_zone'), c)
  t("1 #{c}: global koordinat k × ofset (P1, BK1, yerleşim)", [a(p1c, 'global_x_m'), a(p1c, 'global_y_m'), a(bk1c, 'global_x_m')], [100.0 + 30 * k, 50.0, 100.0 + 30 * k])
  layc = $model.entities.find { |e| a(e, 'element_type') == 'pile_layout' && a(e, 'structure') == c }
  t("1 #{c}: yerleşim grubu global_origin_x_m, structure", [layc && a(layc, 'global_origin_x_m'), layc && a(layc, 'system')], [100.0 + 30 * k, 'ISKELE'])
  t("1 #{c}: yerel alanlar aynen (axis_x_m, grid_x_axis, azimuth_deg, batter_ratio)", [a(p1c, 'axis_x_m'), a(p1c, 'grid_x_axis'), a(p2c, 'azimuth_deg'), a(p2c, 'batter_ratio')],
    [0.0, 'X-01', 90.0, 1.0 / 6.0])
  t("1 #{c}: geometri dönüşümü k × 30 m (BK1, BK2 Component)", [(bk1c.transformation.t[0] - f[:bk1].transformation.t[0]).round(6), (bk2c.transformation.t[0] - f[:bk2].transformation.t[0]).round(6)],
    [(30 * k).m.round(6)] * 2)
  t("1 #{c}: ilerleme: Planlandı, progress_items / inherited / history yok, dependency_child_uids kopyalanmadı",
    [a(p1c, 'progress_status'), a(p1c, 'progress_items_json'), a(p1c, 'progress_inherited_json'), a(p1c, 'progress_inherited_status'), a(p1c, 'progress_inherited_history_json'), a(p1c, 'dependency_child_uids').to_s.include?('MST-1201-1')],
    ['Planlandı', nil, nil, nil, nil, false])
  t("1 #{c}: kimlik: UID MST-<yeni pid>-<zaman>-C, uid_owner_pid, copied_from_uid, copy_origin", [a(bk1c, 'element_uid') =~ /\AMST-#{bk1c.persistent_id}-\d+-C\z/ ? true : false, a(bk1c, 'uid_owner_pid'), a(bk1c, 'copied_from_uid'), a(bk1c, 'copy_origin')],
    [true, bk1c.persistent_id, 'MST-1201-1', 'structure_copy'])
  t("1 #{c}: tip anahtarları ve revizyon sayacı aynen", [a(bk1c, 'type_id'), a(bk1c, 'library_type_id'), a(bk1c, 'type_signature'), a(pc, 'precast_type_id'), a(bk1c, 'bk_revision_no'), a(dc, 'deck_revision_no'), a(cc, 'parent_deck_revision_no')],
    ['BK-T01', 'BK-T01', 'SIG-BK', 'PT-01', 3, 2, 2])
  t("1 #{c}: fiziksel ID yeni + entity.name", [a(bk1c, 'head_beam_id') != 'BK-001', bk1c.name == a(bk1c, 'head_beam_id'), a(p1c, 'pile_id') != 'P-001', a(p1c, 'global_pile_id') == a(p1c, 'pile_id')], [true, true, true, true])
end
all_t = []; M.collect_elements($model.entities, all_t)
typed = $all_ents.values.select { |e| e.valid? && !a(e, 'element_type').to_s.empty? && !a(e, 'element_uid').to_s.empty? }
reach = lambda { |list, out| list.each { |e| out << e; reach.(e.entities, out) if e.is_a?(G); reach.(e.definition.entities, out) if e.is_a?(CI) } ; out }
live = reach.($model.entities, []).uniq
uids = live.reject { |e| a(e, 'element_uid').to_s.empty? }.group_by { |e| a(e, 'element_uid') }.select { |_u, v| v.uniq.length > 1 }.keys
t('1 model genelinde mükerrer UID yok (iç öğeler dahil)', uids, [])
dupid = all_t.group_by { |e| [a(e, 'element_type'), M.element_visible_id(e)] }.select { |k, v| !k[1].start_with?('PID-') && v.uniq.length > 1 && M.mst_identity_id_key(k[0]) }.keys
t('1 fiziksel ID tür bazında benzersiz', dupid, [])
# commit_with_dependencies bütün modelin dependency_* kaydını yazar (fikstürde önceden yoktu); karşılaştırma bunlar hariç
nodep = ->(sig) { sig.map { |r| r.each_with_index.map { |v, i| i == 3 ? v.reject { |q| q[1].start_with?('dependency_') } : v } } }
t('1 kaynak yapı (ANO-01) imzası değişmedi (dependency_* hariç)', nodep.(M.mst_sc_signature(pl['roots'])) == nodep.(before_src), true)
deps = pl['roots'].flat_map { |r| M.mst_sc_tree(r) }.flat_map { |e| %w[dependency_child_uids dependency_parent_uids].map { |k| a(e, k).to_s } }.join(',')
t('1 kaynağın bağımlılık kaydı kopya öğe göstermez (çapraz bağ yok)', [deps.include?('MST-1201-1'), deps.include?('-C')], [true, false])
t('1 başka yapı (ANO-05 BK9) değişmedi', [a(f[:bk9], 'head_beam_id'), a(f[:bk9], 'ano')], ['BK-009', 'ANO-05'])
t('1 aksesuar kopyalanmadı', $model.entities.count { |e| a(e, 'element_type') == 'accessory' }, 1)
t('1 aks görseli kopyalanmadı; yeni ızgaradan mevcut işlevle çizildi (own_op=false)', [$model.entities.count { |e| a(e, 'element_type') == 'axis_grid_visual' }, $grid_draws],
  [1, [['ANO-02', 'ANO-02', false, 'ISKELE'], ['ANO-03', 'ANO-03', false, 'ISKELE']]])
ss = JSON.parse($model.get_attribute(D, 'system_structures_json'))
t('1 system_structures_json: ISKELE += ANO-02, ANO-03; diğer sistemler aynı', [ss['ISKELE'], ss['RIHTIM'], ss['DOLFEN']], [%w[ANO-01 ANO-05 ANO-02 ANO-03], ['RIHTIM-01'], ['BD-01']])
gr = JSON.parse($model.get_attribute(D, 'axis_grids_json'))
t('1 axis_grids_json: kaynak ızgara kopyası', [gr['ANO-02::ANO-02'] == gr['ANO-01::ANO-01'], gr['ANO-03::ANO-03'] == gr['ANO-01::ANO-01']], [true, true])
plc = JSON.parse($model.get_attribute(D, 'structure_placements_json'))
t('1 structure_placements_json: ABSOLUTE, kaynak başlangıcı + k × ofset', [plc['ISKELE::ANO-02'], plc['ISKELE::ANO-03']],
  [{ 'x_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 130.0 }, 'y_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 50.0 } },
   { 'x_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 160.0 }, 'y_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 50.0 } }])
t('1 structure_display_names_json: yalnız verilen görünen ad', JSON.parse($model.get_attribute(D, 'structure_display_names_json')), { 'ANO-03' => 'Kuzey Kolu' })
t('1 kaynak yerleşimi ve ızgarası değişmedi', [plc['ISKELE::ANO-01'], gr['ANO-01::ANO-01'] == JSON.parse(JSON.generate(GRID))],
  [{ 'x_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 100.0 }, 'y_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 50.0 } }, true])
# metraj eşitliği (QuantityService) — bağımsız okuma
qk = %i[concrete_m3 formwork_m2 rebar_t steel_t]
qsum = ->(list) { qk.map { |k| list.select { |e| M::MST_COLLECTED_TYPES.include?(a(e, 'element_type').to_s) }.sum { |e| M::QuantityService.record(e, k)[:value].to_f }.round(6) } }
t('1 QuantityService: ANO-02 ve ANO-03 metrajı = ANO-01', [qsum.(ixs('ANO-02')), qsum.(ixs('ANO-03'))], [qsum.(src_items)] * 2)
obs('1 ANO-01 metraj (beton, kalıp, donatı t, çelik t)', qsum.(src_items))
# bağımsızlık
bk1a = root_copies(f[:bk1]).find { |e| a(e, 'ano') == 'ANO-02' }; bk1b = root_copies(f[:bk1]).find { |e| a(e, 'ano') == 'ANO-03' }
p1a = ixs('ANO-02').find { |e| a(e, 'copied_from_uid') == 'MST-1101-1' }
bk1a.set_attribute(D, 'concrete_volume_m3', 99.0)
bk1a.entities.find { |x| a(x, 'element_type') == 'head_beam_rebar_set' }.set_attribute(D, 'rebar_t', 9.9)
p1a.set_attribute(D, 'length_m', 77.0)
p1a.entities.find { |x| a(x, 'element_type') == 'pile_infill_concrete' }.set_attribute(D, 'concrete_volume_m3', 0.1)
bk2a = root_copies(f[:bk2]).find { |e| a(e, 'ano') == 'ANO-02' }
bk2a.definition.entities.first.set_attribute(D, 'rebar_t', 7.7)
t('1 bağımsızlık: kopya BK / donatı / kazık / iç beton değişince kaynak değişmez',
  [a(f[:bk1], 'concrete_volume_m3'), a(f[:rs1], 'rebar_t'), a(f[:p1], 'length_m'), a(f[:i1], 'concrete_volume_m3'), a(f[:rs2], 'rebar_t')], [10.0, 0.5, 30.0, 5.0, nil])
t('1 bağımsızlık: diğer kopya (ANO-03) değişmez', [a(bk1b, 'concrete_volume_m3'), a(bk1b.entities.find { |x| a(x, 'element_type') == 'head_beam_rebar_set' }, 'rebar_t')], [10.0, 0.5])

# ================================================================ 2) RIHTIM ve DOLFEN birer kopya
f = k1_build
pr = M.mst_structure_copy_plan(req('system' => 'RIHTIM', 'structure' => 'RIHTIM-01', 'count' => '1', 'dx' => '0', 'dy' => '-20'), $model)
t('2 RIHTIM ön kontrol / kod önerisi', [pr['errors'], pr['codes']], [[], ['RIHTIM-02']])
r2 = M.mst_structure_copy_apply!(pr, $model)
t('2 RIHTIM-02: BK kopyası, sistem RIHTIM, tek işlem', [r2['ok'], kinds(ixs('RIHTIM-02', 'RIHTIM')), $model.ops.map(&:first)], [true, [['head_beam', 1]], %i[start commit]])
t('2 RIHTIM-02 system_structures_json', JSON.parse($model.get_attribute(D, 'system_structures_json'))['RIHTIM'], %w[RIHTIM-01 RIHTIM-02])
$model.ops.clear
pd = M.mst_structure_copy_plan(req('system' => 'DOLFEN', 'structure' => 'BD-01', 'count' => '1'), $model)
t('2 DOLFEN ön kontrol / kod önerisi', [pd['errors'], pd['codes']], [[], ['BD-02']])
r3 = M.mst_structure_copy_apply!(pd, $model)
t('2 BD-02: döşeme kopyası, sistem DOLFEN', [r3['ok'], kinds(ixs('BD-02', 'DOLFEN'))], [true, [['deck_slab', 1]]])
t('2 kaynak yerleşimi olmayan yapı: yerleşim ABSOLUTE 0 + ofset', JSON.parse($model.get_attribute(D, 'structure_placements_json'))['DOLFEN::BD-02'],
  { 'x_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 30.0 }, 'y_link' => { 'mode' => 'ABSOLUTE', 'coord_m' => 0.0 } })

# ================================================================ 3) ön kontrol reddi → işlem açılmaz, model değişmez
rej = lambda do |label, h = {}, want = nil, &setup|
  k1_build
  setup&.call
  d0 = k1_dump; $model.ops.clear; $writes = []
  p = M.mst_structure_copy_plan(req(h), $model)
  er = p['errors']
  ok_reason = want.nil? || er.any? { |x| x.include?(want) }
  t("3 red: #{label} → hata listesi, işlem / yazım yok, model aynı", [!er.empty?, ok_reason, k1_ops, $writes.length, k1_dump == d0], [true, true, [], 0, true])
  obs("3 #{label} hata", er.first(3))
  p
end
rej.('başka yapıyı gösteren bağ (PD1 → ANO-05 BK9)', {}, 'başka yapı') { $all_ents[1301].set_attribute(D, 'support_right_pid', 1901) }
rej.('belirsiz aidiyet (system/structure/ano boş BK)', {}, 'belirsiz') do
  x = G.new(1990, 'element_type' => 'head_beam', 'head_beam_id' => 'BK-099', 'element_uid' => 'MST-1990-1'); x.entities = []; x.parent = $model; $model.entities << x; k1_reg(x)
end
rej.('karışık kapsayıcı (ANO-01 + ANO-05)', {}, 'karışık') do
  x = G.new(1991, own('ANO-05').merge('element_type' => 'flat_precast', 'precast_id' => 'PD-091', 'element_uid' => 'MST-1991-1')); x.entities = []; k1_reg(x)
  $all_ents[1800].entities << x; x.parent = $all_ents[1800].entities
end
rej.('karşılıksız bağ (silinmiş kazık PID)', {}, 'bulunamadı') { $all_ents[1201].set_attribute(D, 'connected_pile_persistent_ids', '1101, 1102, 7777') }
rej.('bozuk JSON (axis_grids_json)', {}, 'okunamadı') { $model.set_attribute(D, 'axis_grids_json', '{bozuk') }
rej.('bozuk JSON (structure_placements_json)', {}, 'okunamadı') { $model.set_attribute(D, 'structure_placements_json', '[1]') }
rej.('çakışan kod (ANO-05 mevcut)', { 'count' => '1', 'codes' => ['ANO-05'] }, 'çakışıyor')
rej.('çakışan kod (büyük/küçük harf, ano-05)', { 'count' => '1', 'codes' => ['ano-05'] }, 'çakışıyor')
rej.('aynı kod iki kez', { 'codes' => %w[ANO-07 ano-07] }, 'çakışıyor')
rej.('başka sisteme ait kod biçimi (ISKELE → RIHTIM-09)', { 'count' => '1', 'codes' => ['RIHTIM-09'] }, 'kullanılamaz')
rej.('dönüş isteği', { 'rotation_deg' => '90' }, 'desteklenmiyor')
rej.('kirli Aks Yöneticisi', { 'dirty' => true }, 'kaydedilmemiş')
rej.('kopya sayısı 0', { 'count' => '0' }, '1–50')
rej.('kopya sayısı 51', { 'count' => '51' }, '1–50')
rej.('geçersiz ofset', { 'dx' => 'abc' }, 'ofset')
rej.('görünen ad mevcut kodla çakışıyor', { 'count' => '1', 'names' => ['ANO-05'] }, 'çakışıyor')

# ================================================================ 4) N=10, 9. kopyada enjekte hata → abort, model öncesiyle aynı
k1_build
d0 = k1_dump; $model.ops.clear
$k1_fault = ->(stage, i) { raise 'enjekte hata' if stage == 'copy' && i == 9 }
p10 = plan_of('count' => '10')
t('4 N=10 ön kontrol hatasız, 10 kod', [p10['errors'], p10['codes'].length, p10['codes'].last], [[], 10, 'ANO-12'])   # ANO-05 kullanılıyor, atlanır
r10 = M.mst_structure_copy_apply!(p10, $model)
$k1_fault = nil
t('4 9. kopyada hata: start + abort, commit yok', $model.ops.map(&:first), %i[start abort])
t('4 model işlem öncesiyle birebir aynı (sahte modelin tam dökümü)', k1_dump == d0, true)
t('4 sonuç: başarısız; aşama / kopya no / neden; geri alma doğrulandı', [r10['ok'], r10['stage'], r10['copy_index'], r10['error'], r10['rollback_verified']], [false, 'kopya', 9, 'enjekte hata', true])
t('4 mesaj: yapı, kopya no, kod, neden, geri alma doğrulandı', [r10['message'].include?('ANO-01'), r10['message'].include?('kopya 9'), r10['message'].include?("kopya 9 (#{p10['codes'][8]})"), r10['message'].include?('enjekte hata'), r10['message'].include?('doğrulandı')], [true] * 5)
t('4 kazık dizini önbelleği abort sonrası sıfır', M.instance_variable_get(:@mst_pile_idx_cache), nil)
# doğrulama aşamasında bozulan bağ → doğrulama hatası → abort
k1_build
d0 = k1_dump; $model.ops.clear
$k1_fault = lambda do |stage, _i|
  next unless stage == 'verify'
  c = $model.entities.find { |e| a(e, 'copied_from_uid') == 'MST-1201-1' }
  c.set_attribute(D, 'connected_pile_persistent_ids', '1101')   # kaynak kazığı gösteren bağ
end
rv = M.mst_structure_copy_apply!(plan_of('count' => '1'), $model)
$k1_fault = nil
t('4 son doğrulama başka yapıya bağı yakalar → abort, model aynı', [rv['ok'], rv['stage'], rv['error'].to_s.include?('kopya dışı'), $model.ops.map(&:first), k1_dump == d0], [false, 'doğrulama', true, %i[start abort], true])
obs('4 doğrulama hatası', rv['error'])
# kaynak imzası değişirse geri alma "doğrulanamadı" denir (abort sahte geri yüklemesi kapatılır)
k1_build
$k1_fault = ->(stage, i) { raise 'x' if stage == 'copy' && i == 1 }
class Sketchup::Model; alias k1_abort abort_operation; def abort_operation; @ops << [:abort]; $all_ents[1201].set_attribute(D, 'concrete_volume_m3', 1.0); true; end; end
rx = M.mst_structure_copy_apply!(plan_of('count' => '1'), $model)
class Sketchup::Model; alias abort_operation k1_abort; end
$k1_fault = nil
t('4 abort sonrası kaynak imzası farklı → rollback_verified=false, mesaj "güvenli" demez', [rx['rollback_verified'], rx['message'].include?('doğrulanamadı'), rx['message'].include?('güvenli olduğu varsayılmamalı')], [false, true, true])

# ================================================================ 5) Aks Yöneticisi düğmesi (gerçek project_ano_axis_manager; sahte HtmlDialog)
k1_build
ax = r_axis_open
html = ax.html.to_s
t('5 Aks Yöneticisi: axis_manager_structure_copy geri çağrısı kayıtlı', ax.cb.key?('axis_manager_structure_copy'), true)
t('5 HTML: mevcut "Yapıyı Kopyala" düğmesi yeni akışa bağlı; ayrı yeni düğme yok', [html.scan("id='copyStructure'").length, html.include?("el('copyStructure').addEventListener('click',copyStructureFull)"), html.include?('sketchup.axis_manager_structure_copy(')], [1, true, true])
t('5 JS: kaydedilmemiş değişiklik denetimi (stateKey ↔ savedKey) ve addStructure korunur', [html.include?('stateKey()!==savedKey'), html.include?('function addStructure(copy)')], [true, true])
$model.ops.clear; $msgs = []; $ib = [['should-not-be-used']]
ax.cb['axis_manager_structure_copy'].call(nil, JSON.generate('system' => 'ISKELE', 'structure' => 'ANO-01', 'dirty' => true))
t('5 kirli istek (Ruby savunması): soru sorulmaz, işlem açılmaz', [$ib.length, k1_ops, $msgs.last.to_s.include?('kaydedilmemiş')], [1, [], true])
$model.ops.clear; $msgs = []; $ib = [%w[2 30 0 0], ['', '']]; $timers = []
ax.cb['axis_manager_structure_copy'].call(nil, JSON.generate('system' => 'ISKELE', 'structure' => 'ANO-01', 'dirty' => false))
t('5 arayüz akışı: iki soru, onay, tek işlem', [$ib, $model.ops], [[], [[:start, 'MST Yapı Kopyala ×2'], [:commit]]])
t('5 arayüz: sonuç mesajı aksesuar uyarısı içerir; pencere yenilenir (zamanlayıcı)', [$msgs.last.to_s.include?('1 aksesuar kopyalanmadı'), $timers.length >= 1], [true, true])
$model.ops.clear; $msgs = []; $ib = [%w[1 0 0 0], ['ANO-05', '']]
ax.cb['axis_manager_structure_copy'].call(nil, JSON.generate('system' => 'ISKELE', 'structure' => 'ANO-01', 'dirty' => false))
t('5 arayüz: çakışan kod → hata listesi, işlem açılmaz', [k1_ops, $msgs.last.to_s.include?('işlem açılmadı')], [[], true])

# ================================================================ 5b) Group#copy öznitelikleri KOPYALARSA (diğer olası SketchUp davranışı)
$k1_copy_attrs = true
f = k1_build
rb = M.mst_structure_copy_apply!(plan_of('count' => '1'), $model)
p1c = ixs('ANO-02').find { |e| a(e, 'copied_from_uid') == 'MST-1101-1' }
bk1c = $model.entities.find { |e| a(e, 'copied_from_uid') == 'MST-1201-1' }
t('5b öznitelik kopyalayan Group#copy: ilerleme / bağımlılık kaydı silinir, kimlik yeni, kaynak aynı',
  [rb['ok'], a(p1c, 'progress_items_json'), a(p1c, 'progress_inherited_json'), a(p1c, 'progress_status'), a(bk1c, 'element_uid') == 'MST-1201-1', a(f[:p1], 'progress_items_json') == GB_PJ],
  [true, nil, nil, 'Planlandı', false, true])
$k1_copy_attrs = false
File.write(ENV['K1_JS_OUT'], html[%r{<script>(.*)</script>}m, 1]) if ENV['K1_JS_OUT']   # node --check için Aks Yöneticisi betiği
File.write(ENV['K1_HTML_OUT'], html) if ENV['K1_HTML_OUT']   # tools/test/k1_axis_dirty.js girdisi

# ================================================================ 6) mstBKAddProjectStructure işlem açıp kapatır
k1_build
hd = Class.new(RDlg) { def initialize(*_a, **_k); super(); end }
UI.send(:remove_const, :HtmlDialog) if UI.const_defined?(:HtmlDialog, false)
UI.const_set(:HtmlDialog, hd); hd.const_set(:STYLE_DIALOG, 0)
M.instance_variable_set(:@d, nil)
err = begin; M.show_dialog; nil; rescue StandardError => e; "#{e.class}: #{e.message}"; end
t('6 show_dialog hatasız', err, nil)
dlg = M.instance_variable_get(:@d)
class Sketchup::Model
  alias k1_set set_attribute
  def set_attribute(d, k, v); ($k1_msets ||= []) << [k, @k1_open.to_i]; k1_set(d, k, v); end
  alias k1_start start_operation; alias k1_commit commit_operation; alias k1_ab abort_operation
  def start_operation(*a); @k1_open = @k1_open.to_i + 1; k1_start(*a); end
  def commit_operation; @k1_open = @k1_open.to_i - 1; k1_commit; end
  def abort_operation; k1_ab; @k1_open = @k1_open.to_i - 1; end   # geri yükleme sayaç dahil eski durumu getirir
end
$model.ops.clear; $k1_msets = []; $msgs = []
dlg.cb['mstBKAddProjectStructure'].call(nil, JSON.generate('system' => 'ISKELE', 'name' => 'ANO-07', 'source' => 'ANO-01'))
t('6 BK yeni yapı (kaynaktan aks kopyası): tek start + commit', k1_ops, %i[start commit])
t('6 BK yeni yapı: model yazımlarının hepsi işlem içinde', $k1_msets.reject { |_k, o| o > 0 }.map(&:first), [])
t('6 BK yeni yapı: yapı listesi ve aks ağı yazıldı', [JSON.parse($model.get_attribute(D, 'system_structures_json'))['ISKELE'].include?('ANO-07'), JSON.parse($model.get_attribute(D, 'axis_grids_json')).key?('ANO-07::ANO-07')], [true, true])
$model.ops.clear; $k1_msets = []
orig = M.method(:mst_set_active_system_structure)
M.define_singleton_method(:mst_set_active_system_structure) { |*_a| raise 'yazım hatası' }
d0 = k1_dump
dlg.cb['mstBKAddProjectStructure'].call(nil, JSON.generate('system' => 'ISKELE', 'name' => 'ANO-08', 'source' => ''))
M.define_singleton_method(:mst_set_active_system_structure, &orig)
t('6 BK yeni yapı hata: start + abort, açık işlem yok, model aynı, hata bildirilir', [k1_ops, $model.instance_variable_get(:@k1_open), k1_dump == d0, $msgs.last.to_s.include?('yazım hatası')], [%i[start abort], 0, true, true])
$model.ops.clear
dlg.cb['mstBKAddProjectStructure'].call(nil, JSON.generate('system' => 'ISKELE', 'name' => 'ANO-01', 'source' => ''))
t('6 BK yeni yapı doğrulama reddi (mevcut kod): işlem açılmaz', k1_ops, [])
t('6 (statik) mstBKAddProjectStructure gövdesinde start/commit/abort', (lambda {
  s = main_src[main_src.index("@d.add_action_callback('mstBKAddProjectStructure')")...main_src.index("@d.add_action_callback('mstBKDeleteProjectStructure')")]
  [s.scan('start_operation').length, s.scan('commit_operation').length, s.scan('abort_operation').length]
}).call, [1, 1, 1])

puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
