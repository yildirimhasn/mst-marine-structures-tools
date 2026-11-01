# frozen_string_literal: true
require 'digest'
module MAG
module MarineStructuresTools
def rf02_reference_calculate(data)
 ending=data.is_a?(Hash) && data['ending_reference_model']
 return rf02_reference_sections_only(data) unless ending
 # Cached spatial union belongs to this exact reference snapshot.
 payload=data.dup; expected=payload.delete('reference_fingerprint')
 raise 'Referans verisi değişmiş. Baş birleşimi yeniden hesaplanmadan eski hacim kullanılamaz.' unless expected.is_a?(String) && Digest::SHA256.hexdigest(JSON.generate(payload))==expected
 result=rf02_reference_sections_only(data)
 raise 'Baş birleşimi kapsamı geçersiz.' unless data['excluded_intervals']==[['13','14']] && data['excluded_regions'].empty? && data['sections'][-2]['id']=='13' && data['sections'][-1]['id']=='14' && ending['from_section']=='13'
 raise 'Referans kabulleri eksik.' unless data['assumptions'].is_a?(Array) && data['assumptions'].all?{|x|x.is_a?(String)}
 keys=data['materials'].keys
 %w[volumes_m3 body_prism_m3 head_additions_m3 concrete_deduction_m3 refinement_difference_m3].each do |field|
  values=ending[field]
  raise 'Baş birleşimi hacimleri geçersiz.' unless values.is_a?(Hash) && values.keys.sort==keys.sort && values.values.all?{|x|x.is_a?(Numeric)&&x.finite?&&x>=0}
 end
 keys.each do |k|
  check=ending['body_prism_m3'][k]+ending['head_additions_m3'][k]-ending['concrete_deduction_m3'][k]
  raise 'Baş birleşimi bilançosu tutarsız.' unless (check-ending['volumes_m3'][k]).abs<1e-6
 end
 body={}
 keys.each do |k|
  values=result['rows'][0...-1].map{|r|r['volumes_m3'][k]}
  raise 'Gövde kesit alanı eksik.' if values.any?(&:nil?)
  body[k]=values.inject(0.0,:+)
 end
 result['body_totals_m3']=body
 result['ending_totals_m3']=ending['volumes_m3']
 result['totals_m3']=keys.each_with_object({}){|k,h|h[k]=body[k]+ending['volumes_m3'][k]}
 raise 'Toplam hacim sayısal sınırı aşıyor.' unless result['totals_m3'].values.all?(&:finite?)
 result['rows']=result['rows'][0...-1]
 result['ending_reference_model']=ending
 result['assumptions']=data['assumptions']
 result['partial']=false
 result['complete_scope']=true
 result['review_required']=true
 result['source_mode']='preliminary_reference_model'
 result['missing_intervals']=keys.each_with_object({}){|k,h|h[k]=0}
 result['boq_eligible']=false
 result
end
end
end
