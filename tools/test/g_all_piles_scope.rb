# Parti G-b: Kazık formu "Hedef Kazıklar" → "Projedeki tüm kazıklar" (scope 'ALL').
# mst_resolve_pile_targets: 'ALL' → tüm BIM kazıkları (mst_all_bim_piles); mevcut değerler (ACTIVE / SELECTED / TYPE / IDS / bilinmeyen)
# değişmez. Aynı çözümleyiciyi kullanan önizleme (sayı), Group→Component ve Component→Group onay iletileri ALL ile sınanır
# (onay sorusuna "Hayır" → işlem açılmaz). Golden-master sahtesi + fikstür (P1, P2, P2B, P3, P4).
# Kullanim: ruby tools/test/g_all_piles_scope.rb <src/marine_structures_tools>
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/g_all_piles_scope.rb <marine_structures_tools klasoru>'
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
ids = ->(es) { es.map { |e| e.get_attribute(D, 'pile_id', '?') }.sort }
req = ->(scope, extra = {}) { { 'reference_id' => 'P1', 'reference_pid' => '1001', 'scope' => scope, 'id_expression' => '', 'changes' => {} }.merge(extra) }
res = lambda do |data|
  ids.(M.mst_resolve_pile_targets(data))
rescue StandardError => e
  "HATA: #{e.message}"
end

all_ids = ids.(M.mst_all_bim_piles($model))
t('fikstür: modeldeki BIM kazıkları', all_ids, %w[P1 P2 P2B P3 P4])
t("ALL → projedeki tüm kazıklar", res.(req.('ALL')), all_ids)
t('ACTIVE → yalnız referans kazık (değişmedi)', res.(req.('ACTIVE')), %w[P1])
t('boş / bilinmeyen kapsam → yalnız referans (ALL kendiliğinden seçilmez)', [res.(req.('')), res.(req.('TUM')), res.(req.('all'))], [%w[P1], %w[P1], %w[P1]])
t('IDS → yalnız verilen ID (değişmedi)', res.(req.('IDS', 'id_expression' => 'P3')), %w[P3])
$model.selection.replace([$all_ents[1003]])
t('SELECTED → yalnız seçili kazık (değişmedi)', res.(req.('SELECTED')), %w[P3])

# Önizleme: sayı ve satırlar ALL ile
pv = begin
  M.mst_pile_target_preview_payload(req.('ALL'))
rescue StandardError => e
  { 'count' => "HATA: #{e.message}" }
end
t('önizleme (pile_target_preview) ALL: hedef sayısı', pv['count'], 5)
t('önizleme ALL: satır anahtarları = tüm kazık PID', Array(pv['rows']).map { |r| r['key'].to_i }.sort, [1001, 1002, 1003, 1004, 1005])

# Dönüşümler: onay sorusu ALL kümesini sayıyla gösterir; "Hayır" → işlem açılmaz
module UI
  def self.messagebox(m, *_a); ($ui_msgs ||= []) << m.to_s; IDNO; end
end
$ui_msgs = []
r1 = (M.mst_pile_convert_targets(req.('ALL')) rescue "HATA: #{$!.message}")
t('Group → Component ALL: "Hayır" → nil', r1, nil)
m1 = $ui_msgs.last.to_s; puts "GÖZLEM ileti: #{m1.inspect}"
# fikstürde P1/P3 iç beton alt kotu kayıtlı değil → plan atlar; ALL kümesi = çevrilecek + zaten Component + atlanan = 5
cnt = ->(m, re) { m[re, 1].to_i }
t('Group → Component ALL: iletide 5 kazığın tamamı (1 çevrilecek P4 + 2 zaten Component + 2 atlanan P1/P3)',
  [cnt.(m1, /(\d+) Group kazık Component'e çevrilecek/), cnt.(m1, /(\d+) kazık zaten Component/), m1.scan(/^P\d+: /).size], [1, 2, 2])
$ui_msgs = []
r2 = (M.mst_pile_revert_targets(req.('ALL')) rescue "HATA: #{$!.message}")
t('Component → Group ALL: "Hayır" → nil', r2, nil)
m2 = $ui_msgs.last.to_s; puts "GÖZLEM ileti: #{m2.inspect}"
t('Component → Group ALL: iletide 5 kazığın tamamı (1 çevrilecek P2 + 3 zaten Group + 1 atlanan P2B)',
  [cnt.(m2, /(\d+) Component kazık Group'a çevrilecek/), cnt.(m2, /(\d+) kazık zaten Group/), m2.scan(/^P\d+B?: /).size], [1, 3, 1])
t('dönüşümler onaysız işlem açmaz', $model.ops, [])

ui = File.read(File.join(dir, 'ui.html'), encoding: 'UTF-8')
sel = ui[/<select id="mstPileTargetScope".*?<\/select>/m].to_s
t('ui.html Hedef Kazıklar: ALL seçeneği', sel.include?('<option value="ALL">Projedeki tüm kazıklar</option>'), true)
t('ui.html Hedef Kazıklar: varsayılan ilk seçenek ACTIVE (ALL bilinçli seçilir)', sel[/<option value="(\w+)"/, 1], 'ACTIVE')
t('ui.html Hedef Kazıklar: seçeneklerde "selected" yok', sel.include?('selected'), false)
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
