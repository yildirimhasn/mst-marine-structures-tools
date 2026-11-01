# frozen_string_literal: true
module MAG
module MarineStructuresTools
RF02_CUBAGE_KEY = 'rockfill_alt2_reference_cubage_v1'.freeze

# Reference section calculation is intentionally independent of the live QTO.
# Missing areas and excluded intervals are never converted to zero quantities.
def rf02_reference_sections_only(data)
 raise 'Desteklenmeyen kesit dosyası.' unless data.is_a?(Hash) && data['schema']=='mst.rf02.sections.v1'
 materials=data['materials']; sections=data['sections']; exclusions=data['excluded_intervals']
 raise 'Malzeme listesi geçersiz.' unless materials.is_a?(Hash) && materials.length.between?(1,100) && materials.all?{|k,v|k.is_a?(String)&&v.is_a?(String)}
 raise 'En az iki, en fazla 10000 kesit gerekli.' unless sections.is_a?(Array) && sections.length.between?(2,10000)
 raise 'Kapsam dışı bölge listesi gerekli.' unless data['excluded_regions'].is_a?(Array) && data['excluded_regions'].all?{|s|s.is_a?(String)}
 raise 'Aralık istisnaları geçersiz.' unless exclusions.is_a?(Array)
 ids=[];previous=nil
 sections.each do |s|
  raise 'Kesit kaydı geçersiz.' unless s.is_a?(Hash)
  id=s['id']; station=s['station_m']; areas=s['areas_m2']
  raise 'Kesit kimliği boş veya tekrarlı.' unless id.is_a?(String) && !id.strip.empty? && !ids.include?(id)
  raise 'İstasyonlar sonlu, pozitif yönde ve artan olmalı.' unless station.is_a?(Numeric) && station.finite? && station>=0 && (!previous || station>previous)
  raise 'Kesit alanları geçersiz.' unless areas.is_a?(Hash) && (areas.keys-materials.keys).empty?
  areas.each_value{|v|raise 'Alan negatif veya geçersiz olamaz.' unless v.nil? || (v.is_a?(Numeric)&&v.finite?&&v>=0)}
  ids<<id;previous=station
 end
 adjacent=sections.each_cons(2).map{|a,b|[a['id'],b['id']]}
 raise 'İstisna aralığı ardışık kesitlerle eşleşmiyor.' unless exclusions.all?{|x|adjacent.include?(x)} && exclusions.uniq==exclusions
 transitions=data.fetch('step_transitions',[])
 raise 'Geçiş listesi geçersiz.' unless transitions.is_a?(Array)
 seen=[]
 transitions.each do |t|
  raise 'Geçiş kaydı geçersiz.' unless t.is_a?(Hash)
  pair=[t['from'],t['to']]; index=adjacent.index(pair); x=t['station_m']
  raise 'Geçiş konumu geçersiz.' unless index && !seen.include?(pair) && !exclusions.include?(pair) && x.is_a?(Numeric) && x.finite? && x>sections[index]['station_m'] && x<sections[index+1]['station_m']
  seen<<pair
 end
 rows=sections.each_cons(2).map do |a,b|
  length=b['station_m']-a['station_m'];excluded=exclusions.include?([a['id'],b['id']])
  transition=transitions.find{|t|t['from']==a['id'] && t['to']==b['id']}
  values={}
  materials.each_key do |key|
   aa=a['areas_m2'][key];bb=b['areas_m2'][key]
   values[key]=excluded || aa.nil? || bb.nil? ? nil : (transition ? aa*(transition['station_m']-a['station_m'])+bb*(b['station_m']-transition['station_m']) : (aa+bb)*0.5*length)
   raise 'Hacim sayısal sınırı aşıyor.' if values[key] && !values[key].finite?
  end
  {'from'=>a['id'],'to'=>b['id'],'start_m'=>a['station_m'],'end_m'=>b['station_m'],'length_m'=>length,'volumes_m3'=>values,'excluded'=>excluded,'method'=>transition ? 'Plan sınırında iki sabit tip kesit' : 'AEA'}
 end
 totals={};coverage={};missing={}
 materials.each_key do |key|
  known=rows.select{|r|!r['volumes_m3'][key].nil?}
  # A material present only in excluded head sections has no computed volume.
  present=sections.any?{|s|s['areas_m2'][key] && s['areas_m2'][key]>0}
  sum=known.map{|r|r['volumes_m3'][key]}.inject(0.0,:+)
  raise 'Toplam hacim sayısal sınırı aşıyor.' unless sum.finite?
  totals[key]=known.empty? || (present && sum==0 && known.length<rows.length) ? nil : sum
  coverage[key]=known.map{|r|r['length_m']}.inject(0.0,:+)
  missing[key]=rows.length-known.length
 end
 {'project'=>data['project'].to_s,'source'=>data['source'].to_s,'materials'=>materials,'rows'=>rows,'totals_m3'=>totals,'coverage_m'=>coverage,'missing_intervals'=>missing,
  'excluded_regions'=>data['excluded_regions'],'section_count'=>sections.length,'partial'=>rows.any?{|r|r['volumes_m3'].values.any?(&:nil?)} || !data['excluded_regions'].empty?,
  'source_mode'=>'reference_snapshot','boq_eligible'=>false}
end

def rf02_cubage(action,dialog)
 model=Sketchup.active_model
 if action=='example' || action=='import'
  path=action=='example' ? File.join(__dir__,'data','akdeniz_reference_sections.json') : UI.openpanel('Alternatif-02 referans kesit dosyası',nil,'JSON|*.json||')
  return unless path
  raise 'Kesit dosyası 5 MB sınırını aşıyor.' if File.size(path)>5*1024*1024
  data=JSON.parse(File.read(path,encoding:'UTF-8'))
 elsif action=='load' || action=='calculate'
  saved=model.get_attribute(DICT,RF02_CUBAGE_KEY,nil)
  unless saved
   dialog.execute_script('rf02CubageLoaded(null)');return
  end
  data=JSON.parse(saved)
 else
  raise 'Bilinmeyen kübaj işlemi.'
 end
 result=rf02_reference_calculate(data)
 result['head_reference']=rf02_head_reference(data['head_reference'])
 approved=JSON.parse(File.read(File.join(__dir__,'data','akdeniz_reference_sections.json'),encoding:'UTF-8'))
 result['basis_approved']=result['complete_scope'] && data['reference_fingerprint']==approved['reference_fingerprint']
 if result['basis_approved']
  result['boq_eligible']=true
  result['geometry_audit']=JSON.parse(File.read(File.join(__dir__,'data','akdeniz_geometry_audit.json'),encoding:'UTF-8'))
 end
 if action=='example' || action=='import'
  model.start_operation('Alternatif-02 Referans Kesitlerini Kaydet',true)
  begin
   model.set_attribute(DICT,RF02_CUBAGE_KEY,JSON.generate(data));model.commit_operation
  rescue
   model.abort_operation;raise
  end
 end
 dialog.execute_script("rf02CubageLoaded(#{JSON.generate(result)})")
rescue=>e
 dialog.execute_script("rf02CubageError(#{JSON.generate(e.message)})")
end
end
end

require_relative 'rockfill_complete_reference'
