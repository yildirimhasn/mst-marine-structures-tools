# A2 / K35: kazik "ayri poz" NN'i kesit grubuna kalici bagli (ADR-0515 §4, karar B).
# Kullanim: ruby tools/test/a2_k35_codes.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
class Host
  PILE_BOQ_GROUP_KEYS = %w[PILE_STEEL PILE_INFILL].freeze
  def pile_boq_mode(_k); 'separate'; end
  def pile_boq_group_quantities(key); key == 'PILE_STEEL' ? $groups : []; end
  def boq_price(code, dflt); $prices.key?(code) ? $prices[code] : dflt; end
  def prog2_last_period; $last; end
end
A1.load(Host, main, 'def pile_boq_expand_rows(')
A1.load_opt(Host, main, 'def mst_json_attr_bad?('); A1.load_opt(Host, main, 'def mst_json_attr_guard!(')
NEW = %w[pile_boq_group_key pile_boq_codes_stored pile_boq_codes_for pile_boq_codes_persist!].all? { |n| A1.load_opt(Host, main, "def #{n}(") }
Host.class_eval("PILE_BOQ_CODES_KEY='pile_boq_group_codes_json'.freeze") if NEW
obs('K35 işlevleri tanımlı', NEW)
h = Host.new
D = A1::DICT
def grp(d, t, qty, pid); ["Ø#{format('%.1f', d)} / #{format('%.1f', t)} mm", qty, [FakeEnt.new(pid)], [d, t]]; end
G914 = grp(914.0, 14.0, 10.0, 1); G1016 = grp(1016.0, 16.0, 20.0, 2); G1220 = grp(1220.0, 20.0, 30.0, 3)
ROW = { code: 'ÖBF-001', name: 'Çelik boru kazık', source: 'PILE_STEEL', quantity: 0.0, unit_price: 100.0, status: 'MODEL' }
def codes(h) ; h.pile_boq_expand_rows([ROW.merge(quantity: $groups.sum { |g| g[1] })]).map { |r| [r[:group_label], r[:code]] }; end
a1_reset!
$prices = {}
# 1. dönem: Ø1016 ve Ø1220 (sıra 01, 02) — hakediş geçmişinde kayıtlı
$groups = [G1016, G1220]
first = codes(h)
t('ilk durum: 01 = Ø1016, 02 = Ø1220', first, [['Ø1016.0 / 16.0 mm', 'ÖBF-001-01'], ['Ø1220.0 / 20.0 mm', 'ÖBF-001-02']])
$last = { 'no' => 1, 'rows' => first.map { |lab, c| { 'key' => "PILE_STEEL@#{c}", 'code' => c, 'name' => "Çelik boru kazık (#{lab})" } } }
# 2. dönem: Ø914 grubu eklendi (çap sırasında başa gelir)
$groups = [G914, G1016, G1220]
second = codes(h)
obs('K35 Ø914 eklenince kodlar', second)
t('K35: Ø1016 ve Ø1220 kodlarını korur, Ø914 yeni numara 03 (0.51.4: 01/02/03 kayar)', second,
  [['Ø914.0 / 14.0 mm', 'ÖBF-001-03'], ['Ø1016.0 / 16.0 mm', 'ÖBF-001-01'], ['Ø1220.0 / 20.0 mm', 'ÖBF-001-02']])
t('K35: hakediş satır anahtarı (previous_ eşlemesi) Ø1016 için aynı', second.find { |l, _| l.start_with?('Ø1016') }[1], 'ÖBF-001-01')
if NEW
  t('K35: okuma yazmaz', sets.length, 0)
  r = h.pile_boq_codes_persist!($model)
  stored = JSON.parse($model.a('pile_boq_group_codes_json'))
  t('K35: açık işlemde kalıcı yazım', [r, stored['PILE_STEEL']], [true, { 'd=1016.000|t=16.000' => 1, 'd=1220.000|t=20.000' => 2, 'd=914.000|t=14.000' => 3 }])
  $log = []
  t('K35: değişiklik yoksa yazılmaz', [h.pile_boq_codes_persist!($model), sets.length], [false, 0])
  # Ø1016 grubu silindi, Ø1100 eklendi → 01 yeniden kullanılmaz
  g1100 = grp(1100.0, 18.0, 5.0, 4)
  $groups = [G914, g1100, G1220]
  t('K35: silinen numara yeniden kullanılmaz (Ø1100 → 04)', codes(h), [['Ø914.0 / 14.0 mm', 'ÖBF-001-03'], ['Ø1100.0 / 18.0 mm', 'ÖBF-001-04'], ['Ø1220.0 / 20.0 mm', 'ÖBF-001-02']])
  # kayıt yok + geçmiş yok → bugünkü sıra (eski davranışla aynı)
  a1_reset!; $last = nil; $groups = [G914, G1016, G1220]
  t('K35: kayıt ve geçmiş yoksa 0.51.4 ile aynı (01, 02, 03)', codes(h).map { |_, c| c }, %w[ÖBF-001-01 ÖBF-001-02 ÖBF-001-03])
  # etiket iki gruba uyuyorsa tohumlanmaz
  ga = grp(1016.0, 16.0, 1.0, 5); gb = grp(1016.04, 16.0, 1.0, 6)
  $groups = [ga, gb]
  $last = { 'rows' => [{ 'key' => 'PILE_STEEL@ÖBF-001-07', 'name' => 'Çelik boru kazık (Ø1016.0 / 16.0 mm)' }] }
  t('K35: belirsiz etiket tohumlanmaz; geçmiş numarası ayrılır (08, 09)', codes(h).map { |_, c| c }, %w[ÖBF-001-08 ÖBF-001-09])
  # bozuk kayıt: okuma bellekte, yazma reddedilir
  a1_reset!; $model.set_attribute(D, 'pile_boq_group_codes_json', '{bozuk'); $log = []
  err = begin; h.pile_boq_codes_persist!($model); nil; rescue => e; e.message; end
  t('K35: bozuk kayıt üzerine yazılmaz (Türkçe hata)', [err.to_s.include?('okunamadı'), $model.a('pile_boq_group_codes_json')], [true, '{bozuk'])
  # birim fiyat da NN ile gelir
  a1_reset!; $model.set_attribute(D, 'pile_boq_group_codes_json', JSON.generate('PILE_STEEL' => { 'd=1016.000|t=16.000' => 1, 'd=1220.000|t=20.000' => 2 }))
  $prices = { 'ÖBF-001-01' => 111.0, 'ÖBF-001-02' => 222.0 }; $groups = [G914, G1016, G1220]; $last = nil
  rows = h.pile_boq_expand_rows([ROW.merge(quantity: 60.0)])
  t('K35: birim fiyat kod-NN ile kesite bağlı kalır', rows.map { |r| [r[:group_label][0, 6], r[:unit_price]] }, [['Ø914.0', 100.0], ['Ø1016.', 111.0], ['Ø1220.', 222.0]])
end
# kalıcı yazım çağrıları (statik): progress_save, boq_set_prices, boq2_save_items, boq_set_pile_modes
boq = A1.src('boq_pro.rb')
t('K35: kalıcı yazım 4 açık işlemde', [main.scan('pile_boq_codes_persist!(model)').length, boq.scan('pile_boq_codes_persist!(model)').length], [2, 2])
a1_finish
