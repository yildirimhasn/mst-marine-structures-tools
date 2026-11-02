# Parti H / H3 (Parti B ayrı önerileri): (a) ortak net kalıp yardımcısı mst_bk_set_net_formwork!, (b) send_boq hatası görünür,
# (c) sp_last_json yalnız değer farklıysa kendi normal işlemiyle, (d) son girdi kayıtları (VK işlem içinde; kazık: üretimden sonra
# yalnız made>0 ise saydam işlem, hata olsa da commit), (e) active_ano / active_structure_zone yalnız değer farklıysa,
# (f) kaplama gösterimi mst_display_id (element_visible_id değişmez).
# Kullanim: ruby tools/test/h_h3_writes.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')
bq = A1.src('boq_pro.rb')
sched = A1.src('mst_schedule.rb')
piles = A1.src('mst_v50_piles.rb')
D = A1::DICT
class FakeModel
  def start_operation(*a); $log << [:start, a[0], a[3] == true]; @open_ops += 1; end
end
h = Host.new

# ---- (a)
class Host
  def head_beam_net_formwork_area(_b); raise 'yüz okunamadı' if $net_raise; 9.0; end
end
HA = A1.load_opt(Host, bm, 'def mst_bk_set_net_formwork!(')
t('H3a mst_bk_set_net_formwork! tanımlı', HA, true)
if HA
  a1_reset!; b = Sketchup::Group.new(1, 'element_type' => 'head_beam', 'formwork_net_area_m2' => 7.0); $net_raise = true
  t('H3a hata yutulmaz: false, eski değer + formwork_net_error', [h.mst_bk_set_net_formwork!(b), b.a('formwork_net_area_m2'), b.a('formwork_net_error')], [false, 7.0, 'yüz okunamadı'])
  $net_raise = false
  t('H3a başarı: true, yeni değer, bayrak silinir', [h.mst_bk_set_net_formwork!(b), b.a('formwork_net_area_m2'), b.a('formwork_net_error')], [true, 9.0, nil])
  t('H3a kendi işlemi yok (çağıranın işlemi içinde)', ops, [])
end
vk = b_slice(bm, 'def mst_vk_ui', "\nrescue => ex")
t('H3a VK/BBK net kalıp yazımı ortak yardımcıyla (rescue nil yok)', [vk.include?('[b1,b2].each{|b|mst_bk_set_net_formwork!(b)}'), vk.include?("head_beam_net_formwork_area(b)) rescue nil")], [true, false])
t('H3a mst_v50_after_bk_change! ortak yardımcıyı kullanır', b_slice(bm, 'def mst_v50_after_bk_change!(hb)', "\nend\n").include?('mst_bk_set_net_formwork!(hb)'), true)
t('H3d VK son girdisi işlem içinde (start_operation sonrası)', vk.index("model.start_operation(\"MST \#{MST_VK_ROLES[role]}\",true)").to_i < vk.index("model.set_attribute(DICT,'mst_vk_last_json'").to_i, true)

# ---- (b)
class Host
  def send_boq_base(_d); raise 'pano hatası'; end
  def boq2_payload; {}; end
end
Host.class_eval(A1.grab(bq, 'def send_boq(dialog=@d)'))
a1_reset!
require 'stringio'
old_err = $stderr; $stderr = StringIO.new
2.times { h.send_boq(nil) }
warned = $stderr.string; $stderr = old_err
t('H3b send_boq hatası: konsola uyarı (warn), puts değil', warned.include?('MST BOQ2: pano hatası'), true)
t('H3b oturumda bir kez kullanıcı iletisi', $msgs.select { |m| m.include?('Keşif ekranı güncellenemedi: pano hatası') }.size, 1)

# ---- (c)
snip = b_slice(sched, ' sp_last=JSON.generate', "\n {xlsx:")
Host.class_eval("def h3c(model,sch)\n#{snip}\nend")
pile = FakeEnt.new(55)
sch = { acts: [{ item: { e: pile }, kind: 'pile', sd: '2026-01-01', fd: '2026-01-05' }] }
a1_reset!
h.h3c($model, sch)
t('H3c ilk kayıt: kendi normal işlemi "MST İş Programı Kaydı"', [ops, $log.find { |x| x[0] == :start }[1], $model.a('sp_last_json')], [[:start, :commit], 'MST İş Programı Kaydı', '[[55,"pile","2026-01-01","2026-01-05"]]'])
$log = []; h.h3c($model, sch)
t('H3c aynı değer: yazılmaz, işlem açılmaz (Geri Al geçmişi dolmaz)', [ops, sets.size], [[], 0])

# ---- (d) kazık son girdisi
HD = A1.load_opt(Host, piles, 'def mst_kz_save_last!(')
t('H3d mst_kz_save_last! tanımlı', HD, true)
if HD
  a1_reset!
  h.mst_kz_save_last!($model, 'mst_af_last_json', '{"x0":"0"}')
  t('H3d saydam işlem (4. bağımsız değişken true) + commit', [$log.select { |x| x[0] == :start }.map { |x| x[2] }, ops, $model.a('mst_af_last_json')], [[true], [:start, :commit], '{"x0":"0"}'])
  a1_reset!
  def $model.set_attribute(*_a); raise 'yazım hatası'; end
  old_err = $stderr; $stderr = StringIO.new
  h.mst_kz_save_last!($model, 'mst_kd_last_json', '{}')
  w = $stderr.string; $stderr = old_err
  t('H3d yazım hatasında abort yok, commit ile kapanır, hata bildirilir', [ops, $model.open_ops, w.include?('yazım hatası')], [[:start, :commit], 0, true])
end
af = b_slice(piles, 'def mst_af_ui', "\nrescue => ex")
kd = b_slice(piles, 'def mst_kd_ui', "\nrescue => ex")
t('H3d A-çerçeve: son girdi generate_layout sonrası, yalnız üretildiyse', [af.index('generate_layout(data)').to_i < af.index("'mst_af_last_json',JSON.generate(p)) if mst_kz_existing_ids(model).length-n0>0").to_i, af.include?("model.set_attribute(DICT,'mst_af_last_json'")], [true, false])
t('H3d DXF dispozisyon: son girdi generate_layout sonrası, made>0', [kd.index('generate_layout(data)').to_i < kd.index("mst_kz_save_last!(model,'mst_kd_last_json'").to_i, kd.include?("File.basename(path)))) if made>0"), kd.include?("model.set_attribute(DICT,'mst_kd_last_json'")], [true, true, false])

# ---- (e)
class Host
  def mst_ano_layouts(_m); [{ 'name' => 'ANO-01' }, { 'name' => 'ANO-02' }]; end
  def mst_recalculate_ano_origins(r); r; end
  def mst_structure_zones_for(_a, _m = nil); ['ANA YAPI', 'İSKELE']; end
end
A1.load(Host, main, 'def mst_active_ano_context(', 'def mst_active_structure_zone(')
a1_reset!; $model.set_attribute(D, 'active_ano', 'ANO-02'); $log = []
t('H3e active_ano aynı: yazılmaz', [h.mst_active_ano_context($model)['name'], sets.size], ['ANO-02', 0])
a1_reset!; $model.set_attribute(D, 'active_ano', 'YOK'); $log = []
t('H3e active_ano geçersiz: ilk satıra düzeltilir (yazılır)', [h.mst_active_ano_context($model)['name'], sets.map { |x| x[3] }], ['ANO-01', ['active_ano']])
a1_reset!
t('H3e active_ano kayıtsız: önceki gibi yazılır (kayıtlı durum aynı)', [h.mst_active_ano_context($model)['name'], $model.a('active_ano')], ['ANO-01', 'ANO-01'])
a1_reset!; $model.set_attribute(D, 'active_structure_zone__A1', 'İSKELE'); $log = []
t('H3e active_structure_zone aynı: yazılmaz', [h.mst_active_structure_zone('A1', $model), sets.size], ['İSKELE', 0])
a1_reset!; $model.set_attribute(D, 'active_structure_zone__A1', ' İSKELE '); $log = []
t('H3e boşluklu kayıt: kırpılmış değer yazılır (önceki davranış)', [h.mst_active_structure_zone('A1', $model), $model.a('active_structure_zone__A1')], ['İSKELE', 'İSKELE'])

# ---- (f)
HF = A1.load_opt(Host, main, 'def mst_display_id(')
A1.load(Host, main, 'def element_visible_id(')
t('H3f mst_display_id tanımlı', HF, true)
if HF
  top = FakeEnt.new(77, 'element_type' => 'deck_topping', 'topping_id' => 'TOP-D1')
  top2 = FakeEnt.new(78, 'element_type' => 'deck_topping')
  pl = FakeEnt.new(79, 'element_type' => 'steel_pipe_pile', 'pile_id' => 'P-001')
  t('H3f kaplama topping_id ile; kimliksiz kaplama ve diğerleri değişmez', [h.mst_display_id(top), h.mst_display_id(top2), h.mst_display_id(pl)], ['TOP-D1', 'PID-78', 'P-001'])
  t('H3f element_visible_id değişmedi (kaplama PID-n)', h.element_visible_id(top), 'PID-77')
end
t('H3f bağımlılık listesi gösterimi mst_display_id ile', b_slice(main, 'def mst_dependency_payload(e)', "\nend\n").include?("{'id'=>mst_display_id(x),"), true)
a1_finish
