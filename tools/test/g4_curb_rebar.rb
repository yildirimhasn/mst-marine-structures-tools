# Parti G-b / G4 (metraj kontrolü A): ayrı bordür / tretuvar öğesinin donatısı Keşif ÖBF-004 REBAR'a girer.
# Golden-master sahtesi + fikstür (bordürler C1 1.2, C2 0.6, C3 0.3 m³; D3 DS2 döşeme curb_volume_m3 0.4 + ayrı C3).
# Beklenen (bağımsız): bordür donatısı = Σ hacim × rebar_rate('deck') (150 kg/m³ varsayılan) = 2.1 × 150 = 315 kg.
# Kullanim: ruby tools/test/g4_curb_rebar.rb <src/marine_structures_tools>
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/g4_curb_rebar.rb <marine_structures_tools klasoru>'
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
  g = got.is_a?(Numeric) && (got - exp).abs <= tol
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end
typ = ->(e) { e.get_attribute(D, 'element_type', '').to_s }
coll = -> { a = []; M.collect_elements($model.entities, a); a }

all = coll.()
curbs = all.select { |e| typ.(e) == 'curb' }
rate = M.rebar_rate('deck')
t('fikstür: pursantaj deck = REBAR_DEFAULTS 150 kg/m³ (oran uydurulmadı)', rate, 150.0)
exp_kg = curbs.sum { |c| c.get_attribute(D, 'concrete_volume_m3', 0).to_f } * 150.0
bd = M.mst_boq_rebar_breakdown(all)
row = bd.find { |r| r[:key] == 'curb' }
near('G4 Keşif dökümünde Bordür / Tretuvar satırı = 2.1 m³ × 150 kg/m³', row ? row[:kg] : -1.0, exp_kg)
t('G4 satır adı ve sırası (Döşeme ve Kaplama betonundan sonra)', bd.map { |r| r[:key] }.first(5), %w[pile head_beam deck_slab topping curb])
q = M.boq_quantities
near('G4 REBAR = Σ döküm satırları', q['REBAR'], bd.sum { |r| r[:kg] } / 1000.0)
near('G4 REBAR − (bordürsüz döküm) = bordür hacmi × 150 / 1000', q['REBAR'] - bd.reject { |r| r[:key] == 'curb' }.sum { |r| r[:kg] } / 1000.0, exp_kg / 1000.0)
near('G4 QuantityService.boq_rebar_total = REBAR', M::QuantityService.boq_rebar_total(all), q['REBAR'])
tr = M.boq_trace_entities('REBAR')
t('G4 REBAR izlemesi tüm bordürleri içerir', curbs.all? { |c| tr.include?(c) }, true)
near('G4 izlemedeki bordür donatısı (hakediş eleman miktarı) = döküm satırı', tr.select { |e| typ.(e) == 'curb' }.sum { |e| M.progress_entity_quantity(e, 'REBAR') } * 1000.0, exp_kg)
t('G4 izleme kaplama öğesi içermez (deck_topping)', tr.any? { |e| typ.(e) == 'deck_topping' }, false)

# Model Kontrolü: gövdesinde bordür betonu olan döşemeye ayrı bordür bağlı (D3 + C3) → yalnız D3 için UYARI
au = M.mst_audit_v0515(all, all).select { |r| r[3].to_s.include?('döşeme gövdesinde bordür betonu') }
t('G4 Model Kontrolü uyarısı yalnız D3 (curb_volume_m3 > 0 ve ayrı bordür)', au.map { |r| [r[0], M.element_visible_id(r[1])] }, [%w[WARNING D3]])
t('G4 uyarı metni', au.first && au.first[3], 'D3: döşeme gövdesinde bordür betonu var (0.400 m³) ve döşemeye ayrıca 1 ayrı bordür / tretuvar öğesi bağlı (B-D3-1). Bordür betonu ve donatısı iki kez sayılıyor olabilir.')

# K34 notu yeni kapsamla tutarlı
src = File.read(File.join(dir, 'boq_pro.rb'), encoding: 'UTF-8')
t('G4 K34 hakediş notu: bordür eleman ilerlemesiyle ödenir', src.include?('Bordür / tretuvar donatısı eleman ilerlemesiyle ödenir'), true)
qs = File.read(File.join(dir, 'quantity_service.rb'), encoding: 'UTF-8')
t('G4 quantity_service yedek yolu: yalnız deck_topping dışlanır', qs.include?("reject{|e|type(e)=='deck_topping'}"), true)

# DS2 (bordür döşeme gövdesinde, ayrı bordür öğesi yok) → bordür satırı yok, REBAR değişmez
top_before = M.topping_quantities(all)[1]
curbs.each { |c| c.set_attribute(D, 'element_type', 'curb_off') }
all2 = coll.()
bd2 = M.mst_boq_rebar_breakdown(all2)
t('G4 DS2 (ayrı bordür yok): döküm satırı yok', bd2.any? { |r| r[:key] == 'curb' }, false)
near('G4 DS2: REBAR = Σ döküm (bordür satırı 0)', M.boq_quantities['REBAR'], bd2.sum { |r| r[:kg] } / 1000.0)
# eski tip D2'de kaplama alanı brüt − bordür alanı olduğundan bordür kalkınca kaplama donatısı da değişir (0.15 m³ × 20 kg/m³)
dtop = (M.topping_quantities(all2)[1] - top_before) * M.rebar_rate('topping') / 1000.0
near('G4 DS2: REBAR farkı = −bordür donatısı + kaplama alanı etkisi (yalnız eski tip D2)', M.boq_quantities['REBAR'] - q['REBAR'], -exp_kg / 1000.0 + dtop)
t('işlem açılmadı', $model.ops, [])
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
