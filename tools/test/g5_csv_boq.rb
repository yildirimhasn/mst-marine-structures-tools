# Parti G-b / G5 (metraj kontrolü C): Keşif / Metraj CSV = Keşif. Eklenti golden-master sahtesiyle gerçek yükleme sırasıyla
# yüklenir (tools/golden/sketchup_stub.rb + fixture.rb). export_boq_csv gerçek dosyaya yazar; ayrıca yuvarlanmamış satırlar
# (mst_boq_csv_rows) okunur. Kabul (1e-6): ΣDonati_t = boq_quantities['REBAR'], ΣCelik_t = PILE_STEEL,
# BK (head_beam) Beton = net BK betonu, iç beton satırı = PILE_INFILL, Kaplama Betonu = TOPPING_CONCRETE.
# Senaryo 2: sehpa (döşeme donatı çizelgesinde CHAIR) + aksesuar ankrajı → 'Keşif ek kalemi' satırları ve aynı eşitlikler.
# Fark satırı yoktur: eşitlik tutmazsa test kalır.
# Kullanim: ruby tools/test/g5_csv_boq.rb <src/marine_structures_tools>
require 'tmpdir'
require 'csv'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/g5_csv_boq.rb <marine_structures_tools klasoru>'
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
require_relative '../golden/fixture'
M = MAG::MarineStructuresTools
golden_build_fixture

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end
def near(label, got, exp, tol = 1e-6)
  g = got.is_a?(Numeric) && exp.is_a?(Numeric) && (got - exp).abs <= tol
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect}, tol #{tol})"
end

def csv_file
  rows = nil
  Dir.mktmpdir('mst_g5') do |tmp|
    path = File.join(tmp, 'g5.csv')
    UI.define_singleton_method(:savepanel) { |*_a| path }
    $ui_msgs = []
    M.export_boq_csv
    rows = File.exist?(path) ? CSV.read(path, encoding: 'UTF-8') : []
  end
  rows
end

def check(tag)
  q = M.boq_quantities
  all = []; M.collect_elements($model.entities, all)
  raw = M.respond_to?(:mst_boq_csv_rows) ? M.mst_boq_csv_rows(all) : nil
  t("#{tag} yuvarlanmamış CSV satırları (mst_boq_csv_rows) var", !raw.nil?, true)
  raw ||= []
  sum = ->(rs, c) { rs.sum { |r| r[c].to_f } }
  near("#{tag} ΣDonati_t = Keşif REBAR (ÖBF-004)", sum.(raw, 8), q['REBAR'])
  near("#{tag} ΣCelik_t (boru çeliği) = PILE_STEEL", sum.(raw, 7), q['PILE_STEEL'])
  hbs = all.select { |e| e.get_attribute(D, 'element_type', '') == 'head_beam' }
  near("#{tag} BK Beton_m3 = net BK betonu (Σ head_beam_net_concrete)", sum.(raw.select { |r| r[0] == 'head_beam' }, 5), hbs.sum { |b| M.head_beam_net_concrete(b) })
  decks = all.select { |e| e.get_attribute(D, 'element_type', '') == 'deck_slab' }
  near("#{tag} BK + Döşeme Beton_m3 = HB_DECK_CONCRETE", sum.(raw.select { |r| %w[head_beam deck_slab].include?(r[0]) }, 5), q['HB_DECK_CONCRETE'])
  inf = raw.select { |r| r[0] == 'pile_infill_concrete' }
  t("#{tag} iç beton tek satır", inf.length, 1)
  near("#{tag} iç beton Beton_m3 = PILE_INFILL", sum.(inf, 5), q['PILE_INFILL'])
  top = raw.select { |r| r[0] == 'Keşif ek kalemi' && r[1] == 'Kaplama Betonu' }
  near("#{tag} 'Keşif ek kalemi' Kaplama Betonu = TOPPING_CONCRETE", sum.(top, 5), q['TOPPING_CONCRETE'])
  near("#{tag} Bordür Beton_m3 (curb) = Σ bordür betonu", sum.(raw.select { |r| r[0] == 'curb' }, 5),
       all.select { |e| e.get_attribute(D, 'element_type', '') == 'curb' }.sum { |e| M.qto3_quantity(e, :concrete_m3) })
  near("#{tag} Sınıf sütunu = qto_material_class (BK1/BK2 C30/37)", raw.select { |r| r[0] == 'head_beam' }.map { |r| r[2] }.uniq == ['C30/37'] ? 1.0 : 0.0, 1.0)
  f = csv_file
  t("#{tag} dosya başlığı (8 sütun yerinde + Donati_t)", f[0], %w[Kategori Tip Malzeme/Sinif Adet Boy_m Beton_m3 Kalip_m2 Celik_t Donati_t])
  t("#{tag} dosya satır sayısı = yuvarlanmamış satır sayısı", f.length - 1, raw.length)
  near("#{tag} dosya ΣDonati_t = REBAR", f.drop(1).sum { |r| r[8].to_f }, q['REBAR'])
  near("#{tag} dosya ΣCelik_t = PILE_STEEL", f.drop(1).sum { |r| r[7].to_f }, q['PILE_STEEL'])
  near("#{tag} dosya Beton_m3 (%.3f biçim) toplamı ≈ yuvarlanmamış toplam", f.drop(1).sum { |r| r[5].to_f }, sum.(raw, 5), 0.0005 * raw.length)
  raw
end

raw = check('S1')
t('S1 ek kalem satırları (fikstür: yalnız kaplama)', raw.select { |r| r[0] == 'Keşif ek kalemi' }.map { |r| r[1] }.uniq, ['Kaplama Betonu'])
t('S1 işlem açılmadı', $model.ops, [])

# Senaryo 2: sehpa + aksesuar ankrajı
d1 = $all_ents[5001]
d1.set_attribute(D, 'rebar_schedule_json', JSON.generate('MAIN' => { 'kg' => 1500.0 }, 'CHAIR' => { 'kg' => 300.0 }))
M.define_singleton_method(:accessory_rows) { [{ 'quantity' => 2, 'anchor_rebar_kg' => 12.5 }] }
bd = M.mst_boq_rebar_breakdown((a = []; M.collect_elements($model.entities, a); a))
t('S2 Keşif dökümünde sehpa ve aksesuar satırı', bd.map { |r| r[:key] }.select { |k| %w[chair acc_anchor].include?(k) }.sort, %w[acc_anchor chair])
raw = check('S2')
ek = raw.select { |r| r[0] == 'Keşif ek kalemi' }
near('S2 Sehpa Donati_t = 1800 × 300 / 1800 kg', ek.select { |r| r[1] == 'Sehpa' }.sum { |r| r[8] }, 0.3)
near('S2 Aksesuar ankrajı Donati_t = 2 × 12.5 kg', ek.select { |r| r[1] == 'Aksesuar ankrajı' }.sum { |r| r[8] }, 0.025)
near('S2 Döşeme Donati_t sehpa düşülmüş (D1 1.8 t − 0.3 t + D2/D3/D1K pursantaj)', raw.select { |r| r[0] == 'deck_slab' }.sum { |r| r[8] },
     bd.find { |r| r[:key] == 'deck_slab' }[:kg] / 1000.0)
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
