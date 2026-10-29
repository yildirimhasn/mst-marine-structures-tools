# A2 / K55 (Dolgu Alt-1: kutuphanede olmayan malzeme sessiz 0 t degil) ve R-4 acik kalanlari
# (manual_progress_json ve rebar_history_json bozukken ezilmez).
# Kullanim: ruby tools/test/a2_k55_r4.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
boq = A1.src('boq_pro.rb')
rt = A1.src('mst_rebar_tools.rb')
class Host
  def rockfill_project_key; 'rockfill_project_json'; end
  def rockfill_library; $lib; end
  def boq2_num(x); Float(x) rescue nil; end
  def boq2_today; '2026-10-29'; end
  def boq2_date_ok?(_d); true; end
  def boq2_user; 'test'; end
end
A1.load(Host, main, 'def rockfill_section_areas(', 'def rockfill_qto_alt1_data')
A1.load(Host, boq, 'def prog2_manual', 'def prog2_manual_set(', 'def prog2_norm(', 'def prog2_rec_apply(')
A1.load(Host, rt, 'def mst_rt_history(', 'def mst_rt_history_push!(')
h = Host.new
D = A1::DICT

# ---- K55: A1=40, A2=60, L=20 → 1000 m³; CORE-01 kütüphanede (1.8 t/m³), XX-99 yok
a1_reset!
$lib = [{ 'code' => 'CORE-01', 'name' => 'Çekirdek', 'density' => 1.8 }]
$model.set_attribute(D, 'rockfill_project_json', JSON.generate('sections' => [{ 'id' => 'S1', 'station' => 0, 'areas' => { 'CORE-01' => 40, 'XX-99' => 5 } },
                                                                               { 'id' => 'S2', 'station' => 20, 'areas' => { 'CORE-01' => 60, 'XX-99' => 5 } }]))
res = begin; q = h.rockfill_qto_alt1_data; [:ok, q[:materials].map { |m| [m[:code], m[:tonnage_t].round(3)] }]; rescue => e; [:hata, e.message]; end
obs('K55 sonuç', res)
t('K55: bilinmeyen malzeme kodu → hata (0.51.4: XX-99 = 0 t sessiz)', [res[0], res[1].to_s.include?('XX-99') && res[1].to_s.include?('kütüphanesinde kayıt yok')], [:hata, true])
$lib << { 'code' => 'XX-99', 'name' => 'Filtre', 'density' => 2.0 }
q = h.rockfill_qto_alt1_data
t('K55: kayıt eklenince tonaj (CORE 1000 m³ × 1.8 = 1800 t; XX 100 m³ × 2.0 = 200 t)', q[:materials].map { |m| [m[:code], m[:tonnage_t].round(3)] }, [['CORE-01', 1800.0], ['XX-99', 200.0]])
$lib[1]['density'] = 0
res2 = begin; h.rockfill_qto_alt1_data; :ok; rescue => e; e.message; end
t('K55: yoğunluk 0 → hata', res2.to_s.include?('yoğunluk'), true)
$model.set_attribute(D, 'rockfill_project_json', JSON.generate('sections' => [{ 'id' => 'S1', 'station' => 0, 'areas' => { 'CORE-01' => 40, 'XX-99' => 0 } },
                                                                               { 'id' => 'S2', 'station' => 20, 'areas' => { 'CORE-01' => 60, 'XX-99' => 0 } }]))
$lib.pop
t('K55: alanı 0 olan bilinmeyen kod hata vermez (satır zaten yok)', h.rockfill_qto_alt1_data[:materials].map { |m| m[:code] }, ['CORE-01'])

# ---- R-4: manual_progress_json bozuk
class Host; MST_RT_HISTORY_MAX = 10; end
a1_reset!
$model.set_attribute('MAG_MST_Progress', 'manual_progress_json', '{"A":{"claim":50,')
$log = []
err = begin; h.prog2_manual_set(JSON.generate('source' => 'MOBILIZATION', 'pct' => 100, 'ok' => true)); nil; rescue => e; e.message; end
t('R-4: bozuk elle ilerleme kaydı ezilmez (0.51.4: {} sayılıp üzerine yazılır)', [err.to_s.include?('okunamadı'), $model.get_attribute('MAG_MST_Progress', 'manual_progress_json'), ops], [true, '{"A":{"claim":50,', []])
$model.set_attribute('MAG_MST_Progress', 'manual_progress_json', '')
h.prog2_manual_set(JSON.generate('source' => 'MOBILIZATION', 'pct' => 100, 'ok' => true))
t('R-4: boş kayıtta yazılır', JSON.parse($model.get_attribute('MAG_MST_Progress', 'manual_progress_json')).keys, ['MOBILIZATION'])

# ---- R-4: rebar_history_json bozuk
a1_reset!
e = FakeEnt.new(1, 'rebar_schedule_json' => '{"Poz 1":{"kg":10}}', 'rebar_mode' => 'drawing_detail', 'rebar_t' => 0.01, 'rebar_history_json' => '[{"at":"x"')
err = begin; h.mst_rt_history_push!(e); nil; rescue => ex; ex.message; end
t('R-4: bozuk donatı geçmişi ezilmez (0.51.4: [] sayılıp üzerine yazılır)', [err.to_s.include?('okunamadı'), e.a('rebar_history_json')], [true, '[{"at":"x"'])
e2 = FakeEnt.new(2, 'rebar_schedule_json' => '{"Poz 1":{"kg":10}}', 'rebar_mode' => 'drawing_detail', 'rebar_t' => 0.01)
h.mst_rt_history_push!(e2)
t('R-4: geçmiş yoksa yazılır', JSON.parse(e2.a('rebar_history_json')).length, 1)
a1_finish
