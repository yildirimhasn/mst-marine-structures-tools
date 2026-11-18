# frozen_string_literal: true
require_relative 'ground_sources'
module MAG
module MarineStructuresTools
# Source quantities retain the same keys/units as BOQ; synthetic fill activities
# are quantity-backed planning records, not additional physical BIM elements.
def mst_sp_ground_items
 items=[]
 bp_elements.each do |e|
  d=bp_validate(bp_data(e));q=bp_metrics(d)
  sources=mst_ground_source_quantities(e,d,q)
  items<<{e:e,kind:'bored',id:element_visible_id(e),c:mst_sp_center(e),box:mst_sp_box(e),vol:q[:volume],rebar_kg:q[:rebar]*1000,
          length_m:q[:length],drilling_m:q[:drilling],rebar_estimated_kg:(d['rebar_mode']=='rate' ? q[:rebar]*1000 : 0.0),rebar_supplied_kg:(d['rebar_mode']=='detailed' ? q[:rebar]*1000 : 0.0),source_quantities:sources,quantity_basis:'validated_fore_geometry',activity_uid:"bored:#{e.persistent_id}"}
 end
 jg_elements.each do |e|
  d=jg_validate(JSON.parse(e.get_attribute(DICT,'jet_grout_data')));next unless d['enabled'];q=jg_metrics(d)
  sources=mst_ground_source_quantities(e,d,q)
  items<<{e:e,kind:'jet',id:element_visible_id(e),c:mst_sp_center(e),box:mst_sp_box(e),vol:0.0,rebar_kg:0.0,
          length_m:q[:length],drilling_m:q[:drilling],ground_m3:q[:volume],cement_t:q[:cement],grout_m3:q[:grout],jg_steel_t:q[:steel],
          source_quantities:sources,quantity_basis:'gross_nominal_column_not_net_union_not_concrete',activity_uid:"jet:#{e.persistent_id}"}
 end
 items
end

def mst_sp_fill_items
 q=rockfill_qto_data;selection=rockfill_source_selection;mode=selection['mode'];items=[]
 materials=q[:materials]||[]
 if q[:intervals] && !q[:intervals].empty?
  segments=q[:intervals].map do |iv|
   {from:iv[:from_station].to_f,to:iv[:to_station].to_f,id:"#{iv[:from_id]}→#{iv[:to_id]}",materials:iv[:rows]||[]}
  end
 else
  segments=[{from:0.0,to:0.0,id:'Toplam kaynak',materials:materials}]
 end
 if mode=='geometry' && !Array(q[:intervals]).empty? && (head=q.dig(:geometry_result,'head'))
  head_materials=materials.map do |mat|
   volume=head.fetch('totals').fetch(mat[:code],0.0)
   next unless volume>0
   mat.merge(volume_m3:volume,tonnage_t:volume*mat.fetch(:density))
  end.compact
  station=q[:geometry_result].fetch('total_length')
  segments<<{from:station,to:station,id:'Dairesel baş',materials:head_materials}
 end
 segments.each_with_index do |seg,index|
  mats=seg[:materials].select{|m|m[:volume_m3].to_f>0}.map{|m|{code:m[:code].to_s,name:m[:name].to_s,volume_m3:m[:volume_m3].to_f,tonnage_t:m[:tonnage_t].to_f}}
  next if mats.empty?
  sources=Hash.new(0.0);mats.each{|m|sources["ROCKFILL:#{m[:code]}"]+=m[:tonnage_t]}
  volume=mats.sum{|m|m[:volume_m3]};ton=mats.sum{|m|m[:tonnage_t]}
  raise 'Dolgu program miktarı sonlu ve pozitif olmalı.' unless [volume,ton].all?{|v|v.finite?&&v>0}
  items<<{e:nil,kind:'fill',id:"Dolgu #{seg[:id]}",activity_uid:"fill:#{mode}:#{index}:#{seg[:from]}:#{seg[:to]}",
          c:[(seg[:from]+seg[:to])/2,0.0],box:[0,0,0,0],station:seg[:from],vol:0.0,rebar_kg:0.0,fill_m3:volume,fill_t:ton,
          materials:mats,source_quantities:sources,quantity_basis:'active_quantity_provider_interval_composite_not_layer_sequence'}
 end
 # Never silently multiply a material BOQ across all intervals.
 materials.each do |m|
  source="ROCKFILL:#{m[:code]}";actual=items.sum{|i|i[:source_quantities][source].to_f};expected=m[:tonnage_t].to_f
  raise "#{m[:code]}: dolgu faaliyetleri ve aktif metraj tonajı uyuşmuyor." if (actual-expected).abs>[1e-6,expected.abs*1e-9].max
 end
 if mode=='geometry'
  amount=q.dig(:geometry_result,'excavation_m3').to_f
  if amount>0
   items.unshift({e:nil,kind:'excavation',id:'Tasarım yüzeyine kadar kazı',activity_uid:'excavation:geometry',c:[0.0,0.0],box:[0,0,0,0],
                  vol:0.0,rebar_kg:0.0,excavation_m3:amount,source_quantities:{'LIVE_EXCAVATION'=>amount},quantity_basis:'active_geometry_excavation_separate_from_fill'})
  end
 end
 items
end

def mst_sp_positive(value,label,integer=false)
 n=Float(value) rescue nil
 raise "#{label}: sonlu pozitif #{integer ? 'tam sayı' : 'sayı'} gerekli." unless n && n.finite? && n>0 && (!integer || n==n.to_i)
 integer ? n.to_i : n
end

def mst_sp_add_ground_activities(by,prm,take,put,pool)
 finishes=[]
 [['bored','bored_rate','bored_rigs',:drilling_m],['jet','jg_rate','jg_rigs',:length_m]].each do |kind,rate,crews,key|
  list=by[kind]||[];next if list.empty?
  pl=pool.call(mst_sp_positive(prm[crews],mst_sp_label(kind)+' ekip sayısı',true));productivity=mst_sp_positive(prm[rate],mst_sp_label(kind)+' üretim verimi')
  list.each do |i|
   quantity=i[key];duration=quantity/productivity;s,f,u=take.call(pl,0.0,duration);put.call(i,kind,s,f,u,quantity,'m');finishes<<[i,f]
  end
 end
 finishes
end

def mst_sp_add_fill_activities(by,prm,take,put,pool)
 excavation_end=0.0
 [['excavation','excavation_rate','excavation_crews',:excavation_m3],['fill','fill_rate','fill_crews',:fill_m3]].each do |kind,rate,crews,key|
  list=by[kind]||[];next if list.empty?
  pl=pool.call(mst_sp_positive(prm[crews],mst_sp_label(kind)+' ekip sayısı',true));productivity=mst_sp_positive(prm[rate],mst_sp_label(kind)+' üretim verimi')
  layer_end=excavation_end
  groups=(kind=='fill' && prm['fill_layers'].to_i==1) ? list.group_by{|i|i.fetch(:layer_rank)}.sort.map(&:last) : [list]
  groups.each do |group|
   finishes=[]
   group.sort_by{|i|i[:station].to_f}.each do |i|
    ready=kind=='fill' ? layer_end : 0.0
    s,f,u=take.call(pl,ready,i[key]/productivity);put.call(i,kind,s,f,u,i[key],'m³');finishes<<f
    excavation_end=[excavation_end,f].max if kind=='excavation'
   end
   layer_end=finishes.max if kind=='fill' && prm['fill_layers'].to_i==1 && !finishes.empty?
  end
 end
end

def mst_sp_exact_weights(acts,source)
 list=acts.select{|a|a[:item] && a[:item][:source_quantities] && a[:item][:source_quantities].key?(source)}
 [list,list.map{|a|a[:item][:source_quantities][source]}]
end
end
end
module MAG
module MarineStructuresTools
def mst_sp_source_tables(sch,wk)
 ground=[['Hafta','Fore adet','Fore delgi m','JG iyileştirme m','JG nominal zemin m³','JG bilinen çimento t','JG çimento verisi eksik kolon','JG bilinen enjeksiyon m³','JG enjeksiyon verisi eksik kolon','JG bilinen çelik t','JG çelik verisi eksik kolon','Dolgu m³','Dolgu t','Kazı m³','Fore tahmini donatı t','Fore girilen detay donatı t']]
 wk.each{|r|ground<<[r['week'],r['bored'],r['bored_drill_m'],r['jg_length_m'],r['jg_ground_m3'],r['jg_cement_t'],r['jg_cement_missing'],r['jg_grout_m3'],r['jg_grout_missing'],r['jg_steel_t'],r['jg_steel_missing'],r['fill_m3'],r['fill_t'],r['excavation_m3'],r['bored_rebar_estimated_t'],r['bored_rebar_supplied_t']]}
 mats=[['Faaliyet kimliği','Faaliyet','Başlangıç','Bitiş','Malzeme kodu','Malzeme','Hacim m³','Tonaj t','Yapım sırası']]
 sch[:acts].select{|a|a[:kind]=='fill'}.each do |a|
  a[:item][:materials].each{|m|mats<<[a[:item][:activity_uid],a[:id],a[:sd].to_s,a[:fd].to_s,m[:code],m[:name],m[:volume_m3],m[:tonnage_t],a[:item][:layer_rank] ? a[:item][:layer_rank]+1 : 'Birleşik']}
 end
 missing=[['Kaynak','Miktar','Birim','Neden']]+Array(sch[:unpriced_boq]).map{|r|[r[:source],r[:quantity],r[:unit],r[:reason]]}
 basis=[['Kaynak','Dağıtım yöntemi','Kaynak miktarı / ağırlık toplamı','Faaliyet sayısı','BOQ miktarı','BOQ birimi']]+Array(sch[:boq_allocation_basis]).map{|r|[r[:source],r[:method],r[:weight_sum],r[:activity_count],r[:boq_quantity],r[:unit]]}
 [['Zemin ve Dolgu',ground],['Dolgu Malzemeleri',mats],['Fiyatsız BOQ',missing],['Dağıtım Esası',basis]]
end

def mst_sp_source_report_html(sch,wk)
 text='<h2>Zemin ve dolgu kapsamı</h2><p>Fore kazık süresi delgi metresi / fore verimi; jet grout süresi iyileştirme metresi / JG verimi ile hesaplanır. JG nominal kolon hacmi brüt geometrik toplamdır: beton veya çakışmalar düşülmüş net zemin hacmi değildir. Çimento, enjeksiyon ve çelik yalnız girilen verilerden gelir; eksik kolon sayıları ayrıca gösterilir.</p>'
 text+=sch[:fill_layer_mode]==1 ? '<p><b>Tabaka modu açık:</b> parametrik kesitlerin içten dışa sırasıyla her malzeme ayrı faaliyet olur. Bir malzeme bütün aralıklarda tamamlanmadan sonraki başlamaz. Bu muhafazakâr genel sıra yerel çalışma cephesi, kür veya özel yapım yönteminin yerine geçmez. Ekipler ortak dolgu hızını kullanır; malzeme başına ayrı hız/ekip henüz yoktur.</p>' : '<p>Dolgu faaliyetleri aktif miktar kaynağının kesit aralıklarına bağlı toplu üretim faaliyetleridir. Malzemeler ayrı hacim/tonaj ve BOQ kaynaklarıyla izlenir; bu program tabakaların yapım sırasını veya her malzeme için ayrı ekip üretimini çözmez. Referans/net katı yönteminde aralık yoksa tek toplam faaliyet oluşur. Kazı ayrı faaliyettir ve bu basit programda dolgudan önce tamamlanır. Fore/JG bağımsız ekiplerde başlar; aynı plan kapsamındaki başlık kirişi bu zemin faaliyetlerini bekler. Kronman aktif dolgu tamamlandıktan sonra ayarı1ise kronman dolgu bitişini bekler; bağımsız kronman için ayarı0yapın. Bu kabuller onaylı yapım yöntemi yerine geçmez.</p>'
 text+='<p>Haftalık miktarlar faaliyetin bitiş haftasına, bedeller bitiş ayına yazılır; günlere yayılmış gerçekleşme veya onaylı hakediş değildir. Fore/JG/dolgu/kazı bedeli kendi BOQ kaynak miktarıyla dağıtılır. Dolgu miktar faaliyetleri yeni fiziksel BIM elemanı sayılmaz ve 4D model renklendirmesine dahil edilmez.</p>'
 if Array(sch[:unpriced_boq]).any?
  text+='<p><b>Fiyatı/eşleştirmesi eksik BOQ var. Aylık bedel proje toplamını temsil etmez; eksik fiyat sıfır kabul edilmedi.</b></p>'
 end
 mst_sp_source_tables(sch,wk).each do |name,table|
  text+="<h3>#{mst_rt_h(name)}</h3><table><tr>"+table.first.map{|v|"<th>#{mst_rt_h(v)}</th>"}.join+'</tr>'
  table.drop(1).each{|row|text+='<tr>'+row.map{|v|"<td>#{mst_rt_h(v.is_a?(Float) ? format('%.6f',v) : v)}</td>"}.join+'</tr>'}
  text+='</table>'
 end
 text
end
end
end
