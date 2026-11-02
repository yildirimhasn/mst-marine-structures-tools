# Parti G-a / kod inceleme #7 (K35 guard yalniz AYRI POZ + kazik grubu varken), #10 (K15 toplu prekast istisnada
# Turkce ileti, tek abort), #8 (Model Kontrolu saglik gruplari: tum kontrol adlari bir gruba bagli).
# Kullanim: ruby tools/test/g_review_misc.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
D = A1::DICT

# ---- #7
class Host
  PILE_BOQ_GROUP_KEYS = %w[PILE_STEEL PILE_INFILL].freeze
  PILE_BOQ_CODES_KEY = 'pile_boq_group_codes_json'.freeze
  def pile_boq_mode(k); $modes[k] || 'combined'; end
  def pile_boq_group_quantities(key); key == 'PILE_STEEL' ? $groups : []; end
  def prog2_last_period; nil; end
end
A1.load(Host, main, 'def mst_json_attr_bad?(', 'def mst_json_attr_guard!(', 'def pile_boq_group_key(', 'def pile_boq_codes_stored(', 'def pile_boq_codes_for(', 'def pile_boq_codes_persist!(')
h = Host.new
grp = ['Ø1016.0 / 16.0 mm', 20.0, [FakeEnt.new(2)], [1016.0, 16.0]]
try = lambda do
  $log = []
  r = begin; h.pile_boq_codes_persist!($model); rescue => e; e.message; end
  [r, $model.a('pile_boq_group_codes_json'), sets.size]
end
a1_reset!; $model.set_attribute(D, 'pile_boq_group_codes_json', '{bozuk')
$modes = {}; $groups = [grp]
t('#7 bozuk kayıt + TEK POZ: engellemez (false), yazmaz', try.(), [false, '{bozuk', 0])
$modes = { 'PILE_INFILL' => 'separate' }; $groups = [grp]
t('#7 bozuk kayıt + AYRI POZ ama o imalatta kazık grubu yok: engellemez', try.(), [false, '{bozuk', 0])
$modes = { 'PILE_STEEL' => 'separate' }
r = try.()
t('#7 bozuk kayıt + AYRI POZ + kazık grubu: reddedilir, yazmaz', [r[0].is_a?(String) && r[0].include?('okunamadı'), r[1], r[2]], [true, '{bozuk', 0])
t('#7 ileti düzeltme yolunu söyler', r[0].to_s.include?('Kazık Keşif Pozu Birleştirme / Ayrıştırma bölümünde AYRI POZ seçili imalatları TEK POZ yapıp kaydedin'), true)
a1_reset!; $modes = { 'PILE_STEEL' => 'separate' }; $groups = [grp]
r = try.()
t('#7 sağlam (boş) kayıt + AYRI POZ: NN yazılır (değişmez davranış)', [r[0], JSON.parse(r[1].to_s)['PILE_STEEL'].values], [true, [1]])

# ---- #10
class FakeSel < Array; def add(x); self << x; end; def to_a; Array.new(self); end; end   # b_undo.rb ile aynı
GATED = main.include?("start_operation('Prekast Yerleşimi - Çoklu Tip',true) unless @precast_batch_mode")
class Host
  def selected_head_beams; Sketchup.active_model.selection.to_a; end
  def commit_with_dependencies(m); $log << [:cwd]; m.commit_operation; end
end
A1.load(Host, main, 'def create_flat_precast(')
class Host
  alias_method :cfp_real, :create_flat_precast
  def create_flat_precast(d = nil)
    return cfp_real(d) if selected_head_beams.length > 2
    r = $inner.shift
    raise 'sahte aralık istisnası' if r == :raise
    r
  end
end
mk_bk = ->(pid, x) { b = Sketchup::Group.new(pid, 'element_type' => 'head_beam'); b.bounds = FakeBounds.new([x * INCH, 0, 0], [(x + 1) * INCH, 10 * INCH, 1]); b }
a1_reset!; $model.selection = FakeSel.new([mk_bk.(11, 0), mk_bk.(12, 10), mk_bk.(13, 20)]); $inner = [true, :raise]
r = begin; Host.new.create_flat_precast({}); rescue => e; "KAÇTI: #{e.message}"; end
t('#10 aralık istisnası: tek abort, istisna kaçmaz', [ops, r], [[:start, :abort], false])
t('#10 Türkçe ileti hata nedeniyle', $msgs.last.to_s, "Toplu prekast yerleşimi durduruldu (2. BK aralığı oluşturulamadı: sahte aralık istisnası).\nÖnceki 1 aralık da geri alındı; model değişmedi.")
a1_reset!; $model.selection = FakeSel.new([mk_bk.(11, 0), mk_bk.(12, 10), mk_bk.(13, 20)]); $inner = [true, true]
Host.new.create_flat_precast({})
t('#10 başarı yolu değişmez', [ops, $msgs.last.to_s.include?('tamamlandı')], [[:start, :commit], true])

# ---- #8 (statik): health_groups kaynağı değerlendirilir; main.rb'deki tüm sabit kontrol adları bir gruba bağlı
src = main[/ health_groups=\{\n.*?\n \}\n/m] or abort('health_groups bulunamadı')
groups = eval(src.sub('health_groups=', ''))
bound = groups.values.flatten
names = main.scan(/add_issue\.call\('(?:ERROR|WARNING|INFO)',[^,]*,'([^']+)'/).flatten | main.scan(/out << \['(?:ERROR|WARNING)',[^,]*,'([^']+)'/).flatten
names |= main.scan(/MST_AUDIT_ERROR_FLAGS=\{.*?\n\}/m).empty? ? [] : ['Hesap Hatası']
obs('kontrol adları', names.sort)
t('#8 bağlı olmayan kontrol adı yok', names - bound, [])
t('#8 istenen adlar gruplarda', ['Fiziksel Boru / BIM / Metraj', 'Fiziksel Detay / Metraj', 'BK Donatı BIM', 'BK ↔ Kazık'].map { |n| groups.find { |_, v| v.include?(n) }&.first },
  %w[Metraj Metraj Metraj Bağımlılık])
a1_finish
