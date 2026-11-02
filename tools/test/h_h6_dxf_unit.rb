# Parti H / H6 (kullanıcı kararı C): DXF $INSUNITS tanımsızken üç yolda ön seçimsiz birim sorusu ("— seçin —"),
# seçilmezse / vazgeçilirse iptal; kazık dispozisyonunda son çare sessiz "varsayılan (m)" yerine soru. Soru işlemden önce.
# "L =" yazı birimi ↔ $INSUNITS kuralı değişmez.
# Kullanim: ruby tools/test/h_h6_dxf_unit.rb <src/marine_structures_tools>
require_relative 'b_helper'
dxf = A1.src('mst_dxf.rb')
dxr = A1.src('mst_dx_rebar.rb')
dra = A1.src('mst_dr_auto.rb')
piles = A1.src('mst_v50_piles.rb')
$ib_args = []
module UI
  def self.inputbox(*a); $ib_args << a; $ib_queue.shift; end
end
a2_const(Host, dxf, 'MST_DXF_INSUNITS')
A1.load(Host, dxf, 'def mst_dxf_unit(', 'def mst_dxf_unit_name(')
A1.load(Host, dxr, 'def mst_dxr_l_unit(', 'def mst_dxr_unitless_l?(')
%w[MST_KD_PILE_LAYER MST_KD_NOT_PILE MST_KD_NO_LAYER MST_KD_ANG_LAYER].each { |c| Host.class_eval(piles[/^#{c}=.*$/]) }
A1.load(Host, piles, 'def mst_kd_scan(')
NEW = dxf.include?("\nMST_DXF_UNIT_PICK=") && A1.load_opt(Host, dxf, 'def mst_dxf_ask_unit(')
a2_const(Host, dxf, 'MST_DXF_UNIT_PICK') if NEW
t('H6 ortak soru yardımcısı mst_dxf_ask_unit tanımlı', NEW, true)
h = Host.new

if NEW
  a1_reset!; $ib_args = []; $ib_queue = [['— seçin —']]
  r = h.mst_dxf_ask_unit('Birim?', 'Başlık')
  t('H6 ön seçim yok: varsayılan "— seçin —", liste "— seçin —|mm|cm|m"', [$ib_args[0][1], $ib_args[0][2]], [['— seçin —'], ['— seçin —|mm|cm|m']])
  t('H6 seçilmeden Tamam: nil (iptal) + ileti', [r, $msgs.last.to_s.include?('birimi seçilmedi; işlem iptal edildi')], [nil, true])
  a1_reset!; $ib_queue = [nil]
  t('H6 vazgeç: nil, ileti yok', [h.mst_dxf_ask_unit('Birim?', 'Başlık'), $msgs], [nil, []])
  a1_reset!; $ib_queue = [['mm'], ['cm'], ['m']]
  t('H6 seçim: mm / cm / m', 3.times.map { h.mst_dxf_ask_unit('Birim?', 'Başlık') }, [0.001, 0.01, 1.0])
end

# Paftadan donatı ("L =")
fl = [{ 't' => 'TEXT', 'text' => 'L=250', 'x' => 20.0, 'y' => 0.0, 'h' => 2.5 }]
a1_reset!; $ib_args = []; $ib_queue = [['— seçin —']]
r = h.mst_dxr_l_unit({ 'insunits' => 0 }, fl)
t('H6 paftadan donatı: $INSUNITS 0 → ön seçimsiz soru, seçilmezse iptal (önceden m)', [r, ($ib_args[0] || [])[1]], [nil, ['— seçin —']])
a1_reset!; $ib_queue = [['cm']]
t('H6 paftadan donatı: kullanıcı seçimi açıklamada', h.mst_dxr_l_unit({ 'insunits' => 0 }, fl), [0.01, 'cm (kullanıcı seçimi; $INSUNITS tanımsız)'])
a1_reset!; $ib_args = []
t('H6 "L =" ↔ $INSUNITS kuralı değişmez (5 = cm, soru yok)', [h.mst_dxr_l_unit({ 'insunits' => 5 }, fl), $ib_args.size], [[0.01, 'cm ($INSUNITS 5)'], 0])

# Paftadan 3B donatı (statik: önceki "cm" ön seçimi yok, soru işlemden önce)
ui = b_slice(dra, 'def mst_dra_ui', "\nend\n")
t('H6 3B pafta: ortak soru, "cm" ön seçimi ve "|| 0.01" yedeği yok, iptal 0', [ui.include?("u=mst_dxf_ask_unit('Paftanın çizim birimi'"), ui.include?("['cm'],['mm|cm|m']"), ui.include?('|| 0.01;'), ui.include?('return 0 unless u')], [true, false, false, true])
t('H6 3B pafta: soru start_operation öncesinde', ui.index('mst_dxf_ask_unit(').to_i < ui.index('model.start_operation(').to_i, true)

# Kazık dispozisyonu: çap ve $INSUNITS ile bulunamayan birim
circ = [{ 't' => 'CIRCLE', 'l' => 'KAZIK', 'x' => 0.0, 'y' => 0.0, 'r' => 10_000.0 }, { 't' => 'CIRCLE', 'l' => 'KAZIK', 'x' => 50_000.0, 'y' => 0.0, 'r' => 10_000.0 }]
sc = h.mst_kd_scan({ 'insunits' => 0 }, circ, nil)
t('H6 kazık: birim ne ölçüden ne $INSUNITS\'ten → "varsayılan (m)" işareti (çağıran sorar)', [sc['unit'], sc['unit_src']], [1.0, 'varsayılan (m)'])
sc2 = (h.mst_kd_scan({ 'insunits' => 0 }, circ, nil, 0.001) rescue nil)
t('H6 kazık: kullanıcı seçimiyle yeniden tarama (birim + kaynak + çap)', sc2 && [sc2['unit'], sc2['unit_src'], sc2['dia_mm']], [0.001, 'kullanıcı seçimi; $INSUNITS tanımsız', 20_000.0])
sc3 = (h.mst_kd_scan({ 'insunits' => 6 }, circ, nil, 0.001) rescue nil)
t('H6 kazık: $INSUNITS biliniyorsa seçim kullanılmaz', sc3 && [sc3['unit'], sc3['unit_src']], [1.0, '$INSUNITS'])
kd = b_slice(piles, 'def mst_kd_ui', "\nrescue => ex")
t('H6 kazık arayüzü: varsayılan (m) ise ön seçimsiz soru, iptal 0, generate_layout öncesi',
  [kd.include?("if sc['unit_src']=='varsayılan (m)'"), kd.include?('return 0 unless up'), kd.index('mst_dxf_ask_unit(').to_i < kd.index('generate_layout(data)').to_i], [true, true, true])
a1_finish
