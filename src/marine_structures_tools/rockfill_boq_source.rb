# frozen_string_literal: true
require_relative 'rockfill_sources'
module MAG
module MarineStructuresTools
ROCKFILL_SOURCE_KEY='rockfill_active_quantity_source_v1'.freeze
RF02_MATERIAL_CODES={'CORE'=>'CORE-01','F30'=>'FILTER-02','F70'=>'FILTER-03','F220'=>'FILTER-04','A2'=>'ARMOUR-02','A6'=>'ARMOUR-03','A10'=>'ARMOUR-04','PLUG'=>'PLUG-01'}.freeze

def rockfill_source_selection
 value=JSON.parse(Sketchup.active_model.get_attribute(DICT,ROCKFILL_SOURCE_KEY,'{"mode":"alt1"}'))
 raise 'Dolgu miktar kaynağı bozuk; Alternatif-01 veya Alternatif-02 seçin.' unless value.is_a?(Hash) && %w[alt1 alt2 geometry special].include?(value['mode'])
 value
end

def rf02_checked_reference
 raw=Sketchup.active_model.get_attribute(DICT,RF02_CUBAGE_KEY,nil)
 raise 'Önce Akdeniz Projesi Kesitlerini Yükle düğmesine basın.' unless raw
 data=JSON.parse(raw)
 approved=JSON.parse(File.read(File.join(__dir__,'data','akdeniz_reference_sections.json'),encoding:'UTF-8'))
 result=rf02_reference_calculate(data)
 raise 'Bu referans sürümü geometrik kontrol kaydıyla eşleşmiyor. Güncel Akdeniz kesitlerini yükleyin.' unless result['complete_scope'] && data['reference_fingerprint']==approved['reference_fingerprint']
 result['fingerprint']=data['reference_fingerprint']
 result['source_mode']='approved_reference_geometry'
 result['boq_eligible']=true
 result
end

def rf02_quantity_data
 result=rf02_checked_reference
 lib=rockfill_library
 raise 'Dolgu malzeme kütüphanesi geçersiz.' unless lib.is_a?(Array)
 materials=result['materials'].map do |key,name|
  code=RF02_MATERIAL_CODES.fetch(key)
  matches=lib.select{|m|m.is_a?(Hash) && m['code']==code}
  raise "#{code}: malzeme kütüphanesinde tek kayıt gerekli." unless matches.length==1
  mat=matches.first; density=Float(mat['density']) rescue nil
  raise "#{code}: malzeme adı boş olamaz." if mat['name'].to_s.strip.empty?
  raise "#{code}: yoğunluk sonlu ve sıfırdan büyük olmalı (t/m³)." unless density && density.finite? && density>0
  volume=result['totals_m3'][key]; tonnage=volume*density
  raise "#{code}: tonaj sayısal sınırı aşıyor." unless tonnage.finite?
  {code:code,name:mat['name'].to_s,density:density,volume_m3:volume,tonnage_t:tonnage,reference_key:key}
 end
 {sections:result['rows'].map{|r|{id:r['from'],station:r['start_m']}}+[{id:'13',station:result['rows'].last['end_m']}],
  intervals:[],materials:materials,total_volume_m3:materials.sum{|r|r[:volume_m3]},total_tonnage_t:materials.sum{|r|r[:tonnage_t]},
  source_label:'Dolgu / Taş — Alternatif-02 (onaylı referans)',reference_result:result}
end

def rockfill_qto_data
 selected=rockfill_source_selection
 RockfillSources.provider(selected['mode']).quantities(self,selected)
end

def rockfill_boq_rows(library,seeds,map)
 rows=rockfill_boq_base_rows(library,seeds,map)
 if rockfill_source_selection['mode']=='alt2'
  rows.each do |row|
   row[:status]='ALT-02 · ONAYLI REFERANS' if row[:status]=='MODEL'
   row[:quantity_note]='Miktar: Alternatif-02, onaylı geçiş kabulleri. Tonaj = net hacim × malzeme kütüphanesi yoğunluğu.'
  end
 elsif rockfill_source_selection['mode']=='special'
  rows.each{|row|row[:status]='ALT-02 · NET KATI' if row[:status]=='MODEL';row[:quantity_note]='Miktar modellenmiş net kapalı katıdan okunur. AEA/Alternatif-01 eklenmez.'}
 elsif rockfill_source_selection['mode']=='geometry'
  rows.each do |row|
   row[:status]='ALT-02 · GEOMETRİ' if row[:status]=='MODEL'
   row[:quantity_note]='Miktar: seçili proje aksı, taban yüzeyi ve tip kesitlerden AEA. Geometri değişirse keşif açılışında yeniden hesaplanır.'
  end
 end
 if rockfill_source_selection['mode']=='geometry'
  quantity=rf_live_result['excavation_m3'].to_f
  if quantity>1e-8
   key='LIVE_EXCAVATION'
   rows << (map.key?(key) ? boq_mapped_row(key,'m³',quantity,map[key],library) : {code:'—',name:'Tasarım yüzeyine kadar kazı',unit:'m³',quantity:quantity,unit_price:nil,total:nil,source:key,status:'ÖBF EŞLEŞTİRİLMELİ',library_price:true,project_mapping:false})
  end
 end
 rows
end

def rockfill_takeoff_html
 return rf_special_report if rockfill_source_selection['mode']=='special'
 if rockfill_source_selection['mode']=='geometry'
  return '<h3>Alternatif-02 — Model Geometrisinden AEA</h3><p>Seçilen aks, taban ve tip kesitler okundu; Alternatif-01 eklenmez.</p>'+rf_live_extension_report+rockfill_alt1_takeoff_html
 end
 return rockfill_alt1_takeoff_html unless rockfill_source_selection['mode']=='alt2'
 q=rockfill_qto_data
 rows=q[:materials].map{|m|"<tr><td>#{html_escape(m[:code])}</td><td>#{html_escape(m[:name])}</td><td>#{format('%.3f',m[:density])}</td><td>#{format('%.3f',m[:volume_m3])}</td><td>#{format('%.3f',m[:tonnage_t])}</td></tr>"}.join
 notes=q[:reference_result]['assumptions'].map{|a|"<li>#{html_escape(a)}</li>"}.join
 "<h3>Dolgu / Taş — Alternatif-02</h3><p>Onaylı referans geometrisi ve geçiş kabulleri. Canlı model geometrisi değildir. Alternatif-01 bu miktarlara eklenmez.</p><table><tr><th>Kod</th><th>Malzeme</th><th>Yoğunluk (t/m³)</th><th>Net hacim (m³)</th><th>Tonaj (t)</th></tr>#{rows}<tr><td colspan='3'>TOPLAM</td><td>#{format('%.3f',q[:total_volume_m3])}</td><td>#{format('%.3f',q[:total_tonnage_t])}</td></tr></table><ul>#{notes}</ul>"
end

def rockfill_source_action(action,dialog)
 model=Sketchup.active_model
 if action=='alt1' || action=='alt2'
  selection={'mode'=>action}
  selection['fingerprint']=rf02_quantity_data[:reference_result]['fingerprint'] if action=='alt2'
  model.start_operation('Dolgu Aktif Miktar Kaynağı',true)
  begin
   model.set_attribute(DICT,ROCKFILL_SOURCE_KEY,JSON.generate(selection));model.commit_operation
  rescue
   model.abort_operation;raise
  end
 elsif action!='load'
  raise 'Bilinmeyen miktar kaynağı işlemi.'
 end
 state={'mode'=>rockfill_source_selection['mode'],'materials'=>[],'ready'=>false}
 begin
  q=rockfill_qto_data
  state.merge!({'materials'=>q[:materials],'total_volume_m3'=>q[:total_volume_m3],'total_tonnage_t'=>q[:total_tonnage_t],'ready'=>true})
  if state['mode']=='alt2' && rockfill_source_selection['fingerprint']!=q[:reference_result]['fingerprint']
   state['message']='Referans sürümü değişmiş. Alternatif-02 kaynağını yeniden etkinleştirin; eski bağlantıyla keşif üretilemez.'
  end
 rescue=>e
  state['message']=e.message
 end
 dialog.execute_script("rockfillSourceLoaded(#{JSON.generate(state)})")
 if action!='load'
  send_boq(dialog)
  qto_summary(dialog)
  send_boq_mapping(@boq_mapping_dialog) if @boq_mapping_dialog && @boq_mapping_dialog.visible?
 end
rescue=>e
 dialog.execute_script("rockfillSourceError(#{JSON.generate(e.message)})")
end
end
end
