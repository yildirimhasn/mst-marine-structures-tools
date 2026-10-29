# A2 / 08-R3 (yedek yol miktar agirlikli), K34 (REBAR tavani gorunurluk notu), K38 (icmal ↔ cetvel uyarisi),
# K46 (progress_approved_quantity tarihsiz cagri — yalniz davranis gozlemi).
# Kullanim: ruby tools/test/a2_boq_progress.rb <src/marine_structures_tools>
require_relative 'a2_helper'
boq = A1.src('boq_pro.rb')
main = A1.src('main.rb')
class Host
  def boq_trace_entities(_s); $es; end
  def progress_entity_quantity(e, _s); e.get_attribute(DICT, 'q', 0).to_f; end
  def boq_rows(_x = nil); $rows; end
  def boq2_currency; 'USD'; end
  def boq2_convert(v, _a, _b); v; end
  def prog2_last_period(_h = nil); nil; end
  def prog2_view_date; '2026-10-29'; end
end
A1.load(Host, boq, 'def prog2_base(', 'def prog2_row_key(', 'def prog2_row_entities(', 'def prog2_items(e)', 'def prog2_norm(', 'def prog2_rec(',
        'def prog2_clamp(', 'def prog2_ok_entry(', 'def prog2_rec_frac(', 'def prog2_legacy_ok?(', 'def prog2_frac(', 'def prog2_claim(',
        'def prog2_manual', 'def prog2_quantities(', 'def progress_approved_quantity(', 'def progress_live_rows(')
K38 = A1.load_opt(Host, boq, 'def prog2_icmal_cetvel_warning(')
h = Host.new
D = A1::DICT
def rec(*ok); JSON.generate('REBAR' => { 'claim' => ok.last[1], 'ok' => ok }); end
a1_reset!
# ---- 08-R3: REBAR 15.2 t; kazık (eleman donatısı 0) %100 onaylı, BK (15.0 t) başlanmamış
pile = FakeEnt.new(1, 'element_type' => 'steel_pipe_pile', 'q' => 0.0, 'progress_items_json' => rec(['2026-10-01', 100.0, 'x']))
bkx = FakeEnt.new(2, 'element_type' => 'head_beam', 'q' => 15.0)
$es = [pile, bkx]
row = { source: 'REBAR', code: 'ÖBF-004', name: 'Donatı', unit: 't', quantity: 15.2, unit_price: 1000.0 }
a = h.progress_approved_quantity(row, '2026-10-29')
obs('08-R3 onaylı miktar', a)
t('08-R3: donatısı 0 olan elemanın onayı adet oranıyla pay almaz (0.51.4: 15.2 × 1/2 = 7.6)', a, 0.0)
z1 = FakeEnt.new(3, 'q' => 0.0, 'progress_items_json' => JSON.generate('X' => { 'claim' => 100, 'ok' => [['2026-10-01', 100.0, 'x']] })); z2 = FakeEnt.new(4, 'q' => 0.0)
$es = [z1, z2]
t('08-R3: hiçbir elemanda miktar yoksa adet oranı korunur (10 × 1/2 = 5)', h.progress_approved_quantity({ source: 'X', quantity: 10.0 }, '2026-10-29'), 5.0)
b1 = FakeEnt.new(5, 'q' => 10.0, 'progress_items_json' => JSON.generate('X' => { 'claim' => 100, 'ok' => [['2026-10-01', 100.0, 'x']] })); b2 = FakeEnt.new(6, 'q' => 90.0)
$es = [b1, b2]
t('08 örnek 10/90, %100/%0 → 10 (değişmez)', h.progress_approved_quantity({ source: 'X', quantity: 100.0 }, '2026-10-29'), 10.0)

# ---- K46: tarihsiz çağrı (model_audit) — davranış gözlemi
k = FakeEnt.new(7, 'q' => 10.0, 'progress_items_json' => JSON.generate('X' => { 'claim' => 100, 'ok' => [['2026-01-01', 50.0, 'a'], ['2099-01-01', 100.0, 'b']] }))
$es = [k]
r46 = [h.progress_approved_quantity({ source: 'X', quantity: 10.0 }, nil), h.progress_approved_quantity({ source: 'X', quantity: 10.0 }, '2026-10-29')]
obs('K46 tarihsiz / 2026-10-29 tarihli onaylı miktar', r46)
t('K46: tarihsiz = tüm onay geçmişinin son kaydı (ileri tarihli dahil); tarihli = o tarihe kadar', r46, [10.0, 5.0])
t('K46: etkin tarihsiz çağrı yalnız model_audit (main.rb progress_live_rows/progress_save boq_pro.rb yeniden tanımıyla geçersiz; statik)',
  [main.scan('aq=progress_approved_quantity(r)').length, %w[progress_live_rows progress_save progress_approved_quantity].all? { |n| boq.include?("def #{n}(") }], [1, true])

# ---- K34: REBAR satırı 15.2 t, eleman toplamı 15.0 t → 0.200 t hakedişe eleman bazında girmez
a1_reset!
$es = [FakeEnt.new(2, 'element_type' => 'head_beam', 'q' => 15.0, 'progress_items_json' => rec(['2026-10-01', 100.0, 'x']))]
$rows = [{ source: 'REBAR', code: 'ÖBF-004', name: 'Donatı', unit: 't', quantity: 15.2, unit_price: 1000.0 }]
lr = h.progress_live_rows('2026-10-29').first
obs('K34 hakediş satırı (onaylı / uyarı)', [lr[:approved_quantity], lr[:warning]])
t('K34: kural değişmez — %100 onayda REBAR onaylı 15.0 t', lr[:approved_quantity], 15.0)
t('K34: görünürlük notu 0.200 t (0.51.4: not yok)', lr[:warning].to_s.include?('Hakedişe eleman bazında girmeyen donatı: 0.200 t'), true)
$rows = [{ source: 'HB_DECK_CONCRETE', code: 'ÖBF-005', name: 'Beton', unit: 'm³', quantity: 15.2, unit_price: 10.0 }]
t('K34: diğer satırlarda not yok', h.progress_live_rows('2026-10-29').first[:warning], nil)

# ---- K38
if K38
  rows = [{ previous: 10.0, current_period: 0.0, unit_price: 180.0 }]
  w = h.prog2_icmal_cetvel_warning(rows, [{ 'key' => 'A', 'cum' => 1600.0 }], 'USD')
  obs('K38 uyarı', w)
  t('K38: icmal 1600 ≠ cetvel 1800 → uyarı, fark −200', [!w.nil?, w && w[1].round(2)], [true, -200.0])
  t('K38: eşitse uyarı yok', h.prog2_icmal_cetvel_warning(rows, [{ 'key' => 'A', 'cum' => 1800.0 }], 'USD'), nil)
  t('K38: fiyatsız satırda önceki tutar cetvele girer (string anahtarlı arşiv satırı)', h.prog2_icmal_cetvel_warning([{ 'previous' => 5.0, 'current_period' => 1.0, 'unit_price' => nil, 'previous_amount' => 500.0 }], [{ 'key' => 'A', 'cum' => 500.0 }]), nil)
  t('K38: payload ve Excel icmalinde uyarı (statik)', [boq.include?("p[:icmal_warning]=wk[0]"), boq.include?('(wk=prog2_icmal_cetvel_warning(rows,icmal,cur)) && ic <<')], [true, true])
else
  t('K38 işlevi var', false, true)
end
a1_finish
