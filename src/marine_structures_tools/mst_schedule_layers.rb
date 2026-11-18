# frozen_string_literal: true
module MAG
module MarineStructuresTools
# Parametric sections store OUTSIDE -> INSIDE. Scheduling explicitly opts into
# INSIDE -> OUTSIDE, with a conservative whole-job barrier between materials.
# Faces and net solids carry no dependable construction order.
def mst_sp_layer_order(input,required)
 raise 'Net katı modelinden tabaka yapım sırası çıkarılamaz.' unless (input['solids']||[]).empty?
 types=input.fetch('types');reaches=input.fetch('reaches')
 raise 'Tabaka sırası için atanmış parametrik kesit gerekli.' if reaches.empty?
 edges={};nodes=[]
 reaches.each do |reach|
  spec=types.fetch(reach.fetch('type'))
  raise 'Tabaka sırası yalnız parametrik kesitlerde desteklenir; çizili yüzeyden sıra tahmin edilmez.' unless spec['mode']=='parametric'
  layers=spec['layers'];raise 'Parametrik kesitin tabaka listesi boş.' unless layers.is_a?(Array)&&!layers.empty?
  codes=layers.map{|l|l.fetch('code').to_s}
  raise 'Aynı kesitte tekrarlı veya boş malzeme koduyla tabaka sırası belirsiz.' if codes.any?{|c|c.strip.empty?} || codes.uniq.size!=codes.size
  codes.reverse_each{|c|nodes<<c unless nodes.include?(c)}
  codes.reverse.each_cons(2){|a,b|(edges[a]||=[])<<b unless (edges[a]||[]).include?(b)}
 end
 missing=required-nodes;raise "Metraj malzemelerinin tabaka sırası yok: #{missing.join(', ')}" unless missing.empty?
 remaining=nodes.dup;ordered=[]
 until remaining.empty?
  ready=remaining.find{|c|remaining.none?{|a|(edges[a]||[]).include?(c)}}
  raise 'Kesitlerin tabaka sıraları çelişiyor; yapım programı için kesitleri düzeltin veya birleşik modu seçin.' unless ready
  ordered<<ready;remaining.delete(ready)
 end
 ordered.select{|c|required.include?(c)}
end

def mst_sp_layer_items(items,prm)
 mode=Float(prm.fetch('fill_layers',0)) rescue nil
 raise 'Dolgu tabaka programı ayarı yalnız 0 veya 1 olabilir.' unless [0.0,1.0].include?(mode)
 fills=items.select{|i|i[:kind]=='fill'}
 return items if mode==0 || fills.empty?
 raise 'Tabaka programı için Alternatif-2 model geometrisi gerekli; alan/referans kaynağından sıra tahmin edilmez.' unless rockfill_source_selection['mode']=='geometry'
 required=fills.flat_map{|i|i[:materials].map{|m|m[:code]}}.uniq
 order=mst_sp_layer_order(rf_live_input(rf_live_state),required)
 expanded=items.reject{|i|i[:kind]=='fill'}+fills.flat_map do |i|
  # The same material in a quantity interval is a single construction activity.
  i[:materials].group_by{|m|m[:code]}.map do |code,mats|
   volume=mats.sum{|m|m[:volume_m3]};ton=mats.sum{|m|m[:tonnage_t]}
   raise 'Tabaka miktarı sonlu ve pozitif olmalı.' unless [volume,ton].all?{|v|v.finite?&&v>0}
   i.merge(id:"#{i[:id]} / #{code}",activity_uid:JSON.generate([i[:activity_uid],code]),
           layer_rank:order.index(code),layer_code:code,fill_m3:volume,fill_t:ton,materials:mats,
           source_quantities:{"ROCKFILL:#{code}"=>ton},quantity_basis:'parametric_inner_to_outer_global_material_barrier')
  end
 end
 # No physical BIM identity is created or changed by this planning split.
 expanded
end
end
end
