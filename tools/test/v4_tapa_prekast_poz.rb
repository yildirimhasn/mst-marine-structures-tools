# V4 (04.11.2026) — kullanıcı talimatı (dayanak; METRAJ SONUCUNU DEĞİŞTİRİR):
#  T1  Kazık tapası manipülasyona girer: manipülasyon (t) = (boru + üst çarık + alt çarık + tapa) kg / 1000.
#  T2  Tapa ağırlığı kg olarak "ÇEŞİTLİ DEMİR İMALATI VE YERİNE KONULMASI" (kg) kütüphane pozuyla keşfe girer (kaynak PILE_PLUG);
#      INFO:PILE_PLUG bilgi satırı kalkar.
#  P1  Prekast betonu (C35/45 dışı) beton sınıfına göre "PREKAST BETONU (<sınıf>)" kütüphane pozuyla eşleşir (kaynak PRECAST_CONCRETE#<sınıf>).
#  P2  Sınıfı belirtilmemiş prekast "PREKAST BETONU" pozuyla eşleşir.
#  P3  Sınıfın kütüphane pozu yoksa satır "UYGUN POZ EKSİK" (fiyatsız, toplama girmez); kullanıcı poz ekleyince otomatik eşleşir.
#  P4  Prekast bilgi satırı (INFO:UNMAPPED_CONCRETE##Prekast) kalkar; bordür bilgi satırı kalır.
#  P5  PRECAST_C35_45 satırı ve izlemesi yalnız C35/45 elemanlarını kapsar (sınıf satırıyla çift sayım yok).
#  P6  Proje eşleştirmesi (ÖBF Eşleştirme) yeni kaynakları kabul eder ve otomatik eşleşmenin önüne geçer.
# Kanıt düzeyi: sahte nesne. SketchUp içi davranış KANITLANMAZ.
# Kullanim: ruby tools/test/v4_tapa_prekast_poz.rb <src/marine_structures_tools>
require 'stringio'
require 'tmpdir'
require 'json'
require_relative '../golden/sketchup_stub'
DIR = File.expand_path(ARGV[0] || abort('kullanim: ruby tools/test/v4_tapa_prekast_poz.rb <marine_structures_tools klasoru>'))
TMP = Dir.mktmpdir('mst_v4')
ENV['APPDATA'] = TMP   # kullanıcının gerçek kütüphanesi okunmaz/yazılmaz
LIB_DIR = File.join(TMP, 'MarineStructuresTools', 'BOQLibrary')
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(DIR, 'main.rb')
$stderr = $stderr_keep
require_relative '../golden/fixture'
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures' unless defined?(D)
$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 300]} (beklenen #{exp.inspect[0, 300]})"
end
def near(a, b, eps = 1e-6); (a.to_f - b.to_f).abs <= eps; end
def rec(id, code, name, unit, price = nil)
  { 'id' => id, 'project' => 'Ortak Poz Kataloğu', 'code' => code, 'name' => name, 'unit' => unit, 'currency' => 'USD',
    'unit_price' => price, 'catalog_key' => '' }
end
def write_lib(records)
  FileUtils.mkdir_p(LIB_DIR)
  File.write(File.join(LIB_DIR, 'records.json'), JSON.generate('schema' => 'mst.boq-library/2', 'records' => records))
end
LIB = [rec('lib-demir-kg', 'ÖBF-017', 'ÇEŞİTLİ DEMİR İMALATI VE YERİNE KONULMASI', 'kg', 4.5),
       rec('lib-demir-t', 'ÖBF-241', 'ÇEŞİTLİ DEMİR İMALATI VE YERİNE KONULMASI', 'ton', 4500.0),
       rec('lib-pc-3037', 'ÖBF-037', 'PREKAST BETONU (C30/37)', 'm³', 110.0),
       rec('lib-pc-3545', 'ÖBF-059', 'PREKAST BETONU (C35/45)', 'm³', 125.0),
       rec('lib-pc-gen', 'ÖBF-071', 'PREKAST BETONU', 'm³', 100.0),
       rec('lib-pc-c40', 'ÖBF-124', 'Prekast Betonu (C40)', 'm³', 130.0),
       rec('lib-pc-c40p', 'ÖBF-150', 'Prekast Betonu (C40) (Projeden)', 'm³', 131.0)]
write_lib(LIB)

golden_build_fixture
ents = $model.entities.to_a
# ek prekastlar: sınıfsız, C40 ("Prekast Betonu (C40)" adıyla eşleşmeli), C50/60 (kütüphanede yok)
extra = [Sketchup::Group.new(6101, 'element_type' => 'flat_precast', 'concrete_volume_m3' => 0.7, 'formwork_area_m2' => 2.0, 'concrete_class' => ''),
         Sketchup::Group.new(6102, 'element_type' => 'crane_precast', 'concrete_volume_m3' => 0.9, 'formwork_area_m2' => 2.0, 'concrete_class' => 'C40'),
         Sketchup::Group.new(6103, 'element_type' => 'channel_precast', 'concrete_volume_m3' => 1.1, 'formwork_area_m2' => 2.0, 'concrete_class' => 'C50/60')]
all = ents + extra
$model.entities = Sketchup::Entities.new(all)
$model.entities.parent = $model
all.each { |e| e.parent = $model.entities }
piles = all.select { |e| e.get_attribute(D, 'element_type', '') == 'steel_pipe_pile' }

# ---- T1: manipülasyon tapayı içerir
r = M.pile_fabrication_qto_row(piles, 'X', true)
plug_t = r[8].to_f; pipe_t = r[9].to_f; upper_kg = r[10].to_f; lower_kg = r[11].to_f
t('T1 fikstürde tapa var (> 0 kg)', plug_t > 0, true)
t('T1 manipülasyon = boru + üst + alt + tapa (t)', near(r[12], pipe_t + (upper_kg + lower_kg) / 1000.0 + plug_t), true)
q = M.boq_quantities
t('T1 PILE_MANIP keşif miktarı tapayı içerir', near(q['PILE_MANIP'], pipe_t + (upper_kg + lower_kg) / 1000.0 + plug_t), true)

# ---- T2: tapa kg → ÇEŞİTLİ DEMİR (kg)
t('T2 PILE_PLUG kaynak miktarı = tapa kg', near(q['PILE_PLUG'], plug_t * 1000.0), true)
rows = M.boq_rows(true)
pr = rows.find { |x| x[:source] == 'PILE_PLUG' }
t('T2 PILE_PLUG satırı var', !pr.nil?, true)
t('T2 PILE_PLUG → ÖBF-017 kg pozu (ton pozu değil)', pr && [pr[:code], pr[:unit], pr[:library_id]], ['ÖBF-017', 'kg', 'lib-demir-kg'])
t('T2 PILE_PLUG fiyat ve tutar kütüphaneden', pr && [pr[:unit_price], near(pr[:total], plug_t * 1000.0 * 4.5)], [4.5, true])
info = M.send(:mst_boq_info_rows)
t('T2 INFO:PILE_PLUG bilgi satırı yok', info.none? { |x| x[:source] == 'INFO:PILE_PLUG' }, true)

# ---- P1..P3
row_of = ->(cls) { rows.find { |x| x[:source] == "PRECAST_CONCRETE##{cls}" } }
c3037 = row_of.('C30/37')
t('P1 C30/37 → ÖBF-037', c3037 && [c3037[:code], c3037[:library_id], near(c3037[:quantity], 1.5), c3037[:unit_price], c3037[:status]],
  ['ÖBF-037', 'lib-pc-3037', true, 110.0, 'MODEL'])
c40 = row_of.('C40')
t('P1 C40 → "Prekast Betonu (C40)" (büyük/küçük harf farkı önemsiz; "(Projeden)" ekli poz seçilmez)', c40 && [c40[:code], near(c40[:quantity], 0.9)], ['ÖBF-124', true])
gen = row_of.('Sınıfsız')
t('P2 sınıfsız → ÖBF-071 PREKAST BETONU', gen && [gen[:code], near(gen[:quantity], 0.7), gen[:unit_price]], ['ÖBF-071', true, 100.0])
c50 = row_of.('C50/60')
t('P3 C50/60 kütüphanede yok → UYGUN POZ EKSİK, fiyatsız', c50 && [c50[:status], c50[:unit_price], c50[:total], near(c50[:quantity], 1.1)],
  ['UYGUN POZ EKSİK', nil, nil, true])
t('P3 neden metni beklenen poz adını söyler', c50 && c50[:mapping_reason].to_s.include?('PREKAST BETONU (C50/60)'), true)
t('P1 C35/45 için sınıf satırı yok (PRECAST_C35_45 satırı kalır)', row_of.('C35/45').nil? && rows.any? { |x| x[:source] == 'PRECAST_C35_45' }, true)
t('P1 PRECAST_C35_45 miktarı değişmez (2+3+4)', near(rows.find { |x| x[:source] == 'PRECAST_C35_45' }[:quantity], 9.0), true)
# kullanıcı C50/60 pozunu ekler → otomatik eşleşir
write_lib(LIB + [rec('lib-pc-5060', 'ÖBF-900', 'PREKAST BETONU (C50/60)', 'm³', 150.0)])
c50b = M.boq_rows(true).find { |x| x[:source] == 'PRECAST_CONCRETE#C50/60' }
t('P3 poz eklenince otomatik eşleşir', c50b && [c50b[:code], c50b[:unit_price]], ['ÖBF-900', 150.0])
# aynı ad iki kez → belirsiz, otomatik seçilmez
write_lib(LIB + [rec('lib-pc-5060', 'ÖBF-900', 'PREKAST BETONU (C50/60)', 'm³', 150.0), rec('lib-pc-5060b', 'ÖBF-901', 'PREKAST BETONU (C50/60)', 'm³', 151.0)])
c50c = M.boq_rows(true).find { |x| x[:source] == 'PRECAST_CONCRETE#C50/60' }
t('P3 aynı adlı iki poz → BİRDEN ÇOK UYGUN POZ, fiyatsız', c50c && [c50c[:status], c50c[:unit_price]], ['BİRDEN ÇOK UYGUN POZ', nil])
write_lib(LIB)

# ---- P4: bilgi satırları
info = M.send(:mst_boq_info_rows)
t('P4 prekast bilgi satırı yok', info.none? { |x| x[:source].to_s.start_with?('INFO:UNMAPPED_CONCRETE#Prekast') }, true)
t('P4 bordür bilgi satırı kalır (C30/37 bordür)', info.any? { |x| x[:source].to_s.start_with?('INFO:UNMAPPED_CONCRETE#Bordür') }, true)

# ---- P5: izleme / hakediş eleman kümesi
tr3545 = M.boq_trace_entities('PRECAST_C35_45').map(&:persistent_id).sort
t('P5 PRECAST_C35_45 izlemesi yalnız C35/45 prekast', tr3545, [6001, 6003, 6004])
tr3037 = M.boq_trace_entities('PRECAST_CONCRETE#C30/37').map(&:persistent_id)
t('P5 PRECAST_CONCRETE#C30/37 izlemesi', tr3037, [6002])
t('P5 sınıfsız izleme', M.boq_trace_entities('PRECAST_CONCRETE#Sınıfsız').map(&:persistent_id), [6101])
pd2 = all.find { |e| e.persistent_id == 6002 }
t('P5 hakediş eleman miktarı (sınıf satırı)', near(M.progress_entity_quantity(pd2, 'PRECAST_CONCRETE#C30/37'), 1.5), true)
p1 = all.find { |e| e.persistent_id == 1001 }
t('P5 hakediş eleman miktarı (PILE_PLUG, kg)', near(M.progress_entity_quantity(p1, 'PILE_PLUG'), M.pile_fabrication_qto_row([p1], 'X', true)[8] * 1000.0), true)
t('P5 iş programı: sınıf satırı prekast üretimine, tapa kazığa dağıtılır',
  [M.send(:mst_sp_boq_kinds, 'PRECAST_CONCRETE#C30/37'), M.send(:mst_sp_boq_kinds, 'PILE_PLUG')], [%w[pcprod], %w[pile]])

# ---- P6: proje eşleştirmesi
srcs = M.boq_mapping_templates.map { |x| x[4] }
t('P6 eşleştirme listesinde yeni kaynaklar', ['PILE_PLUG', 'PRECAST_CONCRETE#C30/37', 'PRECAST_CONCRETE#Sınıfsız', 'PRECAST_CONCRETE#C50/60'].all? { |k| srcs.include?(k) }, true)
M.save_boq_mapping('source' => 'PRECAST_CONCRETE#C50/60', 'id' => 'lib-pc-c40p')
t('P6 eşleştirme kaydı okunur', M.boq_project_mapping.keys, ['PRECAST_CONCRETE#C50/60'])
c50d = M.boq_rows(true).find { |x| x[:source] == 'PRECAST_CONCRETE#C50/60' }
t('P6 proje eşleştirmesi otomatiğin önüne geçer', c50d && [c50d[:code], c50d[:project_mapping], c50d[:unit_price]], ['ÖBF-150', true, 131.0])
begin
  M.save_boq_mapping('source' => 'PRECAST_CONCRETE#C50/60', 'id' => 'lib-demir-kg'); t('P6 birim uyuşmazlığı reddedilir', 'kabul edildi', 'hata')
rescue StandardError => e
  t('P6 birim uyuşmazlığı reddedilir', e.message, 'Poz birimi model miktarının birimiyle aynı olmalı.')
end

puts "\nV4: #{$ok} geçti, #{$bad} kaldı"
FileUtils.rm_rf(TMP)
exit($bad.zero? ? 0 : 1)
