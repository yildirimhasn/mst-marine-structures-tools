# A1 / R-4 (K19, K20, K27): bozuk / boş / geçerli JSON ayrımı; bozukta yazma reddi; atomik dosya yazımı.
# Kullanim: ruby tools/test/a1_r4_json.rb <src/marine_structures_tools>
require_relative 'a1_helper'
main = A1.src('main.rb')
boq = A1.src('boq_pro.rb')
acc = A1.src('accessories.rb')

module Sketchup
  class ComponentInstance; end
  class Group; end
end
class FakeDef
  def save_as(path); $save_as += 1; File.binwrite(path, 'SKP'); true; end
  def name; 'Def'; end
end
class FakeComp < Sketchup::ComponentInstance
  def definition; FakeDef.new; end
  def name; 'Baba'; end
end
class FakeDlg; def execute_script(s); $scripts << s; end; end
class Host
  ROCKFILL_LIBRARY_KEY = 'rockfill_material_library_json'.freeze
  USER_ACCESSORY_CATEGORIES = { 'bollard' => 'Baba', 'fender' => 'Usturmaça' }.freeze
  def boq2_num(x); Float(x) rescue nil; end
  def boq2_today; '2026-10-29'; end
  def boq2_date_ok?(_d); true; end
  def prog2_selected_elements; $model.entities; end
  def boq_rows(_x = nil); [{ source: 'SRC', code: 'C1' }]; end
  def prog2_find_row(_k, rows); rows.first; end
  def prog2_row_entities(_r); $model.entities; end
  def boq_trace_entities(_k); $model.entities; end
  def prog2_base(src); src.to_s.split('#', 2)[0].to_s.split('@', 2)[0].to_s; end
  def prog2_norm(r); r; end
  def prog2_rec_apply(_r, pct, _ok, date, _l = nil); { 'claim' => pct, 'claim_date' => date }; end
  def prog2_legacy_ok?(_e); false; end
  def mst_save_axis_grid(*_a); $log << [:set, nil, 'x', 'axis_grid_via_save', nil]; end
end
A1.load(Host, boq, 'def prog2_items(e)', 'def prog2_apply(')
A1.load_opt(Host, boq, 'def prog2_items_for_write(')
obs('mst_json_attr_guard! tanımlı', A1.load_opt(Host, main, 'def mst_json_attr_bad?(') && A1.load_opt(Host, main, 'def mst_json_attr_guard!('))
A1.load(Host, main, 'def rockfill_save_library(', 'def rockfill_autosave_library(', 'def mst_system_structures(', 'def mst_default_structure_name(',
        'def mst_structures_for_system(', 'def mst_save_structures_for_system(', 'def mst_structure_zones(', 'def mst_structure_zones_for(',
        'def mst_add_structure_zone(', 'def mst_axis_manager_save_payload(')
A1.load(Host, acc, 'def user_accessory_library_dir', 'def user_accessory_index_path', 'def user_accessory_items', 'def user_accessory_write(',
        'def user_accessory_register_selected', 'def user_accessory_delete(')
A1.load_opt(Host, acc, 'def user_accessory_items_for_write')
# Parti B (K14 / S9) düzeneği: dolgu kayıtları mst_rf_write! ile yazılır, otomatik kayıt hatası mst_rf_autosave_warn ile bildirilir
A1.load_opt(Host, main, 'def mst_rf_write!('); A1.load_opt(Host, main, 'def mst_rf_autosave_warn(')
h = Host.new
D = A1::DICT
try = lambda do |&b|
  b.call
  :ok
rescue => e
  $msgs << e.message
  :raised
end

# ---- K19 ilerleme kaydı
a1_reset!
bad = '{"SRC":{"claim":50,"ok":[["2026-01-01",50,"x"]]'
e1 = FakeEnt.new(1, 'element_type' => 'deck_slab', 'progress_items_json' => bad)
$model.entities = [e1]
r = try.() { h.prog2_apply(JSON.generate('sources' => ['SRC'], 'pct' => 80, 'date' => '2026-10-29')) }
t('K19 bozuk progress_items_json: hata ile durur', r, :raised)
t('K19 bozuk kayıt baytları aynı', e1.a('progress_items_json'), bad)
t('K19 işlem açıldı ve geri alındı', ops, [:start, :abort])
t('K19 Türkçe ileti', $msgs.last.to_s.include?('ilerleme kaydı (progress_items_json) okunamadı'), true)
a1_reset!
e2 = FakeEnt.new(2, 'element_type' => 'deck_slab', 'progress_items_json' => '')
e3 = FakeEnt.new(3, 'element_type' => 'deck_slab', 'progress_items_json' => '{"DIGER":{"claim":10}}')
$model.entities = [e2, e3]
h.prog2_apply(JSON.generate('sources' => ['SRC'], 'pct' => 80, 'date' => '2026-10-29'))
t('K19 boş kayıt → yeni yazılır', JSON.parse(e2.a('progress_items_json')).keys, ['SRC'])
t('K19 geçerli kayıt → diğer kalem korunur', JSON.parse(e3.a('progress_items_json')).keys.sort, %w[DIGER SRC])

# ---- K20 model DICT kayıtları
dlg = FakeDlg.new; $scripts = []
a1_reset!
$model.set_attribute(D, 'rockfill_material_library_json', '[bozuk'); $log = []
h.rockfill_save_library('[{"code":"A","name":"B","density":1.8}]', dlg)
t('K20 dolgu kütüphanesi bozuk: kayıt ezilmez', $model.a('rockfill_material_library_json'), '[bozuk')
t('K20 dolgu kütüphanesi bozuk: Türkçe ileti', $msgs.any? { |m| m.include?('kaydı (rockfill_material_library_json) okunamadı') }, true)
h.rockfill_autosave_library('[{"code":"A","name":"B","density":1.8}]')
t('K20 otomatik kayıt da ezmez', $model.a('rockfill_material_library_json'), '[bozuk')
a1_reset!
h.rockfill_save_library('[{"code":"A","name":"B","density":1.8}]', dlg)
t('K20 dolgu kütüphanesi boş: yazılır', JSON.parse($model.a('rockfill_material_library_json').to_s).length, 1)

a1_reset!
$model.set_attribute(D, 'system_structures_json', '{bozuk'); $log = []
rows = h.mst_structures_for_system('ISKELE')
t('K20 sistem listesi bozuk: okuma varsayılanı döner', rows, ['ANO-01'])
t('K20 sistem listesi bozuk: okuma kaydı ezmez', $model.a('system_structures_json'), '{bozuk')
r = try.() { h.mst_save_structures_for_system('ISKELE', %w[ANO-01 ANO-02]) }
t('K20 sistem listesi bozuk: kaydetme reddedilir', [r, $model.a('system_structures_json')], [:raised, '{bozuk'])
$model.set_attribute(D, 'system_structures_json', '[1,2]')
r = try.() { h.mst_save_structures_for_system('ISKELE', %w[ANO-01]) }
t('K20 beklenmeyen tip (dizi) bozuk sayılır', [r, $model.a('system_structures_json')], [:raised, '[1,2]'])

a1_reset!
$model.set_attribute(D, 'structure_zones_json', 'xx'); $log = []
r = try.() { h.mst_add_structure_zone('ANO-01', 'B-2') }
t('K20 yapı/bölge listesi bozuk: ekleme reddedilir', [r, $model.a('structure_zones_json')], [:raised, 'xx'])
a1_reset!
h.mst_add_structure_zone('ANO-01', 'B-2')
t('K20 yapı/bölge listesi boş: ekleme yazılır', JSON.parse($model.a('structure_zones_json'))['ANO-01'], ['ANA YAPI', 'B-2'])

a1_reset!
$model.set_attribute(D, 'structure_placements_json', '{kırık'); $log = []
r = try.() { h.mst_axis_manager_save_payload({ 'project' => 'P', 'system' => 'ISKELE', 'systems' => { 'ISKELE' => ['ANO-01'] }, 'placements' => {} }, $model) }
t('K20 Aks Yöneticisi: yerleşim kaydı bozuk → hiçbir şey yazılmaz', [r, sets.size, $model.a('structure_placements_json')], [:raised, 0, '{kırık'])

# ---- K27 aksesuar kütüphanesi dosyası
tmp = Dir.mktmpdir('a1_k27')
ENV['APPDATA'] = tmp
lib = h.user_accessory_index_path
$save_as = 0
a1_reset!
$model.define_singleton_method(:selection) { [FakeComp.new] }
$inputbox_answer = ['Baba', 'Yeni Baba', 'Ü', 'M', '', '', '']
File.binwrite(lib, "[{\"id\":\"a\",\"name\":\"eski\"} bozuk")
before = File.binread(lib)
r = try.() { h.user_accessory_register_selected }
t('K27 bozuk kütüphane: kayıt reddedilir', r, :raised)
t('K27 bozuk kütüphane: dosya baytları aynı', File.binread(lib) == before, true)
t('K27 bozuk kütüphane: SKP kaydedilmez (öksüz dosya yok)', $save_as, 0)
r = try.() { h.user_accessory_delete('a') }
t('K27 bozuk kütüphane: silme de dosyayı değiştirmez', [r, File.binread(lib) == before], [:raised, true])
File.binwrite(lib, '')
h.user_accessory_register_selected
t('K27 boş dosya → 1 kayıt yazılır', JSON.parse(File.read(lib)).length, 1)
h.user_accessory_register_selected
t('K27 geçerli dosya → kayıt eklenir (2)', JSON.parse(File.read(lib)).length, 2)
t('K27 atomik yazım: geçici dosya kalmadı', Dir.glob(File.join(File.dirname(lib), '*.tmp')).size, 0)
FileUtils.rm_rf(tmp)
a1_finish
