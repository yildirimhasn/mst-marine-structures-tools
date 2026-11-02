# frozen_string_literal: true
require 'securerandom'
module MAG
module MarineStructuresTools
BP_TYPES='bored_pile_types_v1'.freeze
def bp_defaults
 {'type_id'=>'FK-01','diameter'=>1200.0,'top'=>0.75,'bottom'=>-19.25,'drill_top'=>0.75,
  'concrete'=>'C40/50','rebar_mode'=>'rate','rebar_rate'=>254.0,'rebar_kg'=>0.0,'extra'=>0.0,
  'casing'=>'none','casing_length'=>0.0,'color'=>'#B58BDC','project'=>'','ano'=>'','axis'=>''}
end
def bp_validate(raw)
 d=bp_defaults.merge(raw)
 %w[diameter top bottom drill_top rebar_rate rebar_kg extra casing_length].each do |key|
  d[key]=Float(d[key].to_s.tr(',','.'))
  raise "Geçersiz sayı: #{key}" unless d[key].finite?
 end
 raise 'Tip kodu boş olamaz.' if d['type_id'].to_s.strip.empty?
 raise 'Çap sıfırdan büyük olmalı.' unless d['diameter']>0
 raise 'Beton üst kotu uç kotundan büyük olmalı.' unless d['top']>d['bottom']
 raise 'Delgi başlangıç kotu beton üst kotundan aşağıda olamaz.' if d['drill_top']<d['top']
 raise 'Beton sınıfı seçin.' unless %w[C25/30 C30/37 C35/45 C40/50 C45/55 C50/60].include?(d['concrete'])
 raise 'Donatı yöntemi geçersiz.' unless %w[rate detailed].include?(d['rebar_mode'])
 raise 'Muhafaza seçimi geçersiz.' unless %w[none temporary permanent].include?(d['casing'])
 raise 'Pursantaj, donatı ve ilave oranı negatif olamaz.' if %w[rebar_rate rebar_kg extra casing_length].any?{|k|d[k]<0}
 if d['casing']!='none'
  raise 'Muhafaza boyu delgi boyu içinde ve sıfırdan büyük olmalı.' unless d['casing_length']>0 && d['casing_length']<=d['drill_top']-d['bottom']
 end
 raise 'Sembol rengi geçersiz.' unless d['color'].to_s.match?(/\A#[0-9A-Fa-f]{6}\z/)
 d['type_id']=d['type_id'].strip
 d
end
def bp_metrics(d)
 length=d['top']-d['bottom'];volume=Math::PI*(d['diameter']/1000.0)**2/4*length
 result={length:length,drilling:d['drill_top']-d['bottom'],volume:volume,order:volume*(1+d['extra']/100),
  rebar:(d['rebar_mode']=='rate' ? volume*d['rebar_rate'] : d['rebar_kg'])/1000.0,
  casing:d['casing']=='none' ? 0.0 : d['casing_length']}
 raise 'Fore kazık miktarı sayısal sınırı aşıyor.' unless result.values.all?{|v|v.finite?}
 result
end
def bp_types
 JSON.parse(Sketchup.active_model.get_attribute(DICT,BP_TYPES,'{}'))
end
def bp_elements
 all=[];collect_elements(Sketchup.active_model.entities,all)
 all.select{|e|e.get_attribute(DICT,'element_type')=='bored_pile'}
end
def bp_data(e)
 JSON.parse(e.get_attribute(DICT,'bored_pile_data','{}'))
end
def bp_rows
 groups=bp_elements.group_by{|e|JSON.generate(bp_data(e).sort.to_h)}
 groups.map do |_,elements|
  d=bp_data(elements.first);q=bp_metrics(d);n=elements.length
  {data:d,count:n,length:q[:length],total_length:q[:length]*n,drilling:q[:drilling]*n,
   concrete:q[:volume]*n,order:q[:order]*n,rebar:q[:rebar]*n,casing:q[:casing]*n}
 end
end
def bp_write(group,data,x,y)
 d=bp_validate(data);q=bp_metrics(d)
 group.entities.clear!
 edges=group.entities.add_circle(ORIGIN,Z_AXIS,(d['diameter']/2).mm,64)
 face=group.entities.add_face(edges);raise 'Kazık yüzeyi oluşturulamadı.' unless face
 face.reverse! if face.normal.z<0;face.pushpull(-q[:length].m)
 group.transformation=Geom::Transformation.translation([x,y,d['top'].m])
 group.name="#{d['type_id']} • Ø#{d['diameter'].round} Fore Kazık"
 group.material=material_for(Sketchup.active_model,"MAG Fore Kazık #{d['color']}",d['color'])
 {'element_type'=>'bored_pile','bored_pile_data'=>JSON.generate(d),'element_uid'=>group.get_attribute(DICT,'element_uid',SecureRandom.uuid),
  'type_id'=>d['type_id'],'pile_id'=>d['type_id'],'length_m'=>q[:length],'actual_length_m'=>q[:length],
  'diameter_mm'=>d['diameter'],'top_elevation_m'=>d['top'],'bottom_elevation_m'=>d['bottom'],
  'concrete_class'=>d['concrete'],'concrete_volume_m3'=>q[:volume],'formwork_area_m2'=>0.0,
  'rebar_t'=>q[:rebar],'project'=>d['project'],'ano'=>d['ano'],'axis'=>d['axis']}.each{|k,v|group.set_attribute(DICT,k,v)}
 mst_assign_tag(group,Sketchup.active_model) if respond_to?(:mst_assign_tag)
end
class BoredPilePlacement
 def initialize(data);@model_token=Sketchup.active_model.object_id;@data=data;@ip=Sketchup::InputPoint.new;end
 def activate;Sketchup.status_text='Fore kazık merkezi seçin. Birden fazla kazık için tıklamaya devam edin; Esc ile bitirin.';end
 def onMouseMove(flags,x,y,view);@ip.pick(view,x,y);view.invalidate;end
 def draw(view);@ip.draw(view) if @ip.valid?;end
 def onLButtonDown(flags,x,y,view)
  @ip.pick(view,x,y);return unless @ip.valid?
  model=Sketchup.active_model
  return UI.messagebox('Aktif model değişti. Fore kazık yerleşimini bu projede yeniden başlatın.') unless model.object_id==@model_token
  return UI.messagebox('Önce grup düzenleme modundan çıkın.') if model.active_path
  model.start_operation('Fore Kazık Yerleştir',true)
  begin
   g=model.entities.add_group;p=@ip.position
   MarineStructuresTools.bp_write(g,@data,p.x,p.y);model.commit_operation
   MarineStructuresTools.bp_send
  rescue=>e;model.abort_operation;UI.messagebox(e.message);end
 end
 def onCancel(reason,view);Sketchup.active_model.select_tool(nil);end
end
def bp_send(message='')
mst_read_batch do   # v0.51.5 P4: salt okuma, tek model taraması (gömülü Fore Kazık sayfası)
 return unless @bp_dialog
 d={types:bp_types,defaults:bp_defaults,rows:bp_rows,message:message,
  project:Sketchup.active_model.get_attribute(DICT,'project_name',''),scopes:qto3_snapshot[:scopes],model_token:Sketchup.active_model.object_id.to_s}
 @bp_dialog.execute_script("bpLoaded(#{JSON.generate(d)})")
end # mst_read_batch
end
def show_bored_pile
 if @bp_dialog && @bp_dialog.visible?;@bp_dialog.bring_to_front;bp_send;return;end
 @bp_dialog=mst_html_dialog('bored_pile',dialog_title:'Fore Kazık • Teknik Model ve Metraj',preferences_key:'MAG_MST_BoredPile',width:1400,height:900,resizable:true)
 @bp_dialog.set_file(File.join(__dir__,'bored_pile.html'))
 @bp_dialog.add_action_callback('bp_action') do |_,action,json|
  begin
   payload=JSON.parse(json||'{}');model=Sketchup.active_model
   if action!='refresh' && payload['model_token']!=model.object_id.to_s
    raise 'Aktif model değişti. Modelden Yenile düğmesine basın.'
   end
   case action
   when 'refresh';bp_send
   when 'read'
    e=model.selection.to_a
    raise 'Tek bir fore kazık grubu seçin.' unless e.length==1 && e.first.get_attribute(DICT,'element_type')=='bored_pile'
    @bp_dialog.execute_script("bpEdit(#{JSON.generate(bp_data(e.first))})")
   when 'mapping';show_boq_mapping
   when 'save','place','update'
    d=bp_validate(payload.fetch('data'))
    raise 'Önce grup düzenleme modundan çıkın.' if model.active_path
    if action=='place'
     model.select_tool(BoredPilePlacement.new(d));bp_send('Modelde merkez noktalarına tıklayın; bitirmek için Esc. Z kotları formdan alınır.')
    else
     targets=action=='update' ? model.selection.to_a : []
     raise 'Güncellemek için yalnız kilitsiz fore kazık gruplarını seçin.' if action=='update' && (targets.empty? || targets.any?{|e|!e.is_a?(Sketchup::Group) || e.locked? || e.get_attribute(DICT,'element_type')!='bored_pile'})
     model.start_operation(action=='save' ? 'Fore Kazık Tipini Kaydet' : 'Fore Kazıkları Güncelle',true)
     begin
      types=bp_types;types[d['type_id']]=d;model.set_attribute(DICT,BP_TYPES,JSON.generate(types))
      targets.each{|e|o=e.transformation.origin;bp_write(e,d,o.x,o.y)}
      model.commit_operation
     rescue;model.abort_operation;raise;end
     bp_send(action=='save' ? 'Tip kaydedildi. Mevcut kazıklar değişmedi.' : "#{targets.length} kazık ve metrajı güncellendi. Ctrl+Z ile geri alınabilir.")
    end
   else;raise 'Bilinmeyen işlem.'
   end
  rescue=>e;@bp_dialog.execute_script("bpError(#{JSON.generate(e.message)})");end
 end
 @bp_dialog.show
end
def bp_sources
 rows=bp_rows;result=[]
 rows.group_by{|r|r[:data]['diameter']}.each do |diameter,arr|
  result<<{key:"BORED:DRILL:#{diameter}",name:"Ø#{diameter.round} mm Fore Kazık Delgisi",unit:'m',quantity:arr.sum{|r|r[:drilling]},diameter:diameter,kind:'drill'}
 end
 rows.group_by{|r|[r[:data]['diameter'],r[:data]['concrete']]}.each do |(diameter,cc),arr|
  result<<{key:"BORED:CONCRETE:#{diameter}:#{cc}",name:"Ø#{diameter.round} mm Fore Kazık Betonu (#{cc})",unit:'m³',quantity:arr.sum{|r|r[:concrete]},diameter:diameter,concrete:cc,kind:'concrete'}
 end
 rows.group_by{|r|r[:data]['casing']}.each do |kind,arr|
  next if kind=='none'
  result<<{key:"BORED:CASING:#{kind}",name:"Fore Kazık #{kind=='temporary' ? 'Geçici' : 'Kalıcı'} Muhafaza Borusu",unit:'m',quantity:arr.sum{|r|r[:casing]},kind:'casing'}
 end
 result
end
def bp_boq_rows(library,seeds,map)
 bp_sources.map do |source|
  key=source[:key];unit=source[:unit];qty=source[:quantity]
  next boq_mapped_row(key,unit,qty,map[key],library) if map.key?(key)
  candidates=seeds.select do |r|
   name=r['name'].upcase
   dia=name[/[Øø]\s*(\d+)/,1]
   r['unit']==unit && name.include?('FORE KAZIK') && dia && dia.to_f==source[:diameter] &&
    ((source[:kind]=='drill' && name.include?('DELG')) || (source[:kind]=='concrete' && name.include?('BETON') && name.include?(source[:concrete])))
  end
  if candidates.size==1
   seed=candidates.first;item=library.find{|r|r['id']==seed['id']}||seed
   boq_mapped_row(key,unit,qty,item,[item]).merge(project_mapping:false)
  else
   {code:'—',name:source[:name],unit:unit,quantity:qty,unit_price:nil,total:nil,source:key,status:'ÖBF EŞLEŞTİRİLMELİ',library_price:true}
  end
 end
end
def bp_report_html
 rows=bp_rows
 return '' if rows.empty?
 body=rows.map{|r|d=r[:data];"<tr><td>#{html_escape(d['type_id'])}</td><td>#{d['diameter'].round}</td><td>#{html_escape(d['concrete'])}</td><td>#{r[:count]}</td><td>#{format('%.3f',r[:total_length])}</td><td>#{format('%.3f',r[:concrete])}</td><td>#{format('%.3f',r[:rebar])}</td></tr>"}.join
 "<h3>Fore Kazık Metrajı</h3><p>Geometrik beton hacmi; donatı yöntemine göre pursantaj tahmini veya detay hesabından girilen miktar.</p><table><tr><th>Tip</th><th>Ø (mm)</th><th>Beton</th><th>Adet</th><th>Boy (m)</th><th>Beton (m³)</th><th>Donatı (t)</th></tr>#{body}</table>"
end
end
end
