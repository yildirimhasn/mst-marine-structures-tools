# Parti G-b / G6 (metraj kontrolü B): pano ve Excel "Toplam Beton" kaplama betonunu içerir; qto3_snapshot değişmez.
# Golden-master sahtesi + fikstür (kaplama D1 50 × 0.12 = 6.0 m³ C30/37; eski tip D2 (20 − 1.5) × 0.10 = 1.85 m³, sınıfsız → C35/45).
# Kabul: Toplam − Σ sınıf satırları = kaplama; pano KAPLAMA kırılımı; DİĞER değişmez; ui.html alt yazısı.
# Kullanim: ruby tools/test/g6_total_concrete.rb <src/marine_structures_tools>
require 'tmpdir'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/g6_total_concrete.rb <marine_structures_tools klasoru>'
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
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end

all = []; M.collect_elements($model.entities, all)
top = 6.0 + (20.0 - 5.0 * 0.3) * 0.10
near('fikstür: kaplama hacmi (bağımsız) = topping_quantities', M.topping_quantities(all)[1], top)
snap = M.qto3_snapshot
near('qto3_snapshot toplamı = satır toplamı (kaplama yok; snapshot değişmez)', snap[:totals][:concrete_m3], snap[:rows].sum { |r| r[:concrete_m3] })

class GDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(j); @js << j; true; end; def visible?; true; end; end
d = GDlg.new
M.qto_summary(d)
data = JSON.parse(d.js.find { |x| x.start_with?('setQTO(') }[/\AsetQTO\((.*)\);?\z/m, 1])
near('G6 pano Toplam Beton − qto3_snapshot = kaplama', data['total_concrete'] - snap[:totals][:concrete_m3], top)
near('G6 pano KAPLAMA kırılımı = kaplama', data['concrete_breakdown']['KAPLAMA'].to_f, top)
cb = data['concrete_breakdown']
near('G6 pano kırılımları toplamı = Toplam Beton', cb.values.sum, data['total_concrete'])
t('G6 pano kaplama satırı metni', data['rows'].include?("(Toplam Beton'a dahil; keşifte ayrı kalem ÖBF-072)"), true)

sheets = {}
orig = M.method(:xlsx_sheet_xml)
M.define_singleton_method(:xlsx_sheet_xml) { |h, r, w| sheets[h] = r; orig.call(h, r, w) }
Dir.mktmpdir('mst_g6') do |tmp|
  path = File.join(tmp, 'g6.xlsx')
  UI.define_singleton_method(:savepanel) { |*_a| path }
  M.export_professional_excel
end
summ = sheets.find { |h, _| h == %w[Kalem Miktar Birim] }&.last || []
tot = summ.find { |r| r[0] == 'Toplam Beton' }
cls = summ.select { |r| r[0] =~ /\ABeton (?!Kaplama)/ }
kap = summ.select { |r| r[0].to_s.start_with?('Beton Kaplama (') }
near('G6 Excel Toplam Beton − Σ sınıf satırları = kaplama', tot[1] - cls.sum { |r| r[1] }, top)
t('G6 Excel Beton Kaplama satırları (sınıf)', kap.map { |r| [r[0], r[1].round(6)] }, [['Beton Kaplama (C30/37)', 6.0], ['Beton Kaplama (C35/45)', 1.85]])
near('G6 Excel Σ sınıf satırları + Σ kaplama = Toplam Beton', cls.sum { |r| r[1] } + kap.sum { |r| r[1] }, tot[1])
near('G6 Excel Toplam Beton = pano Toplam Beton', tot[1], data['total_concrete'])
near('G6 Keşif değişmez: TOPPING_CONCRETE = kaplama (ayrı poz ÖBF-072)', M.boq_quantities['TOPPING_CONCRETE'], top)
ui = File.read(File.join(dir, 'ui.html'), encoding: 'UTF-8')
t('G6 ui.html Toplam Beton alt yazısı KAPLAMA içerir', ui.include?('<em id="qConcreteBreak">BK + PD + DOSP + KAPLAMA + KRONMAN + ÇBK</em>'), true)
t('işlem açılmadı', $model.ops, [])
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
