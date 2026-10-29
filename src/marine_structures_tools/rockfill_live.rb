# frozen_string_literal: true
require_relative 'axis_chain'
require_relative 'rockfill_geometry_engine'
require_relative 'rockfill_tin'
require_relative 'rockfill_loft_model'
require_relative 'rockfill_report'
require_relative 'rockfill_templates'
require 'digest'
module MAG
module MarineStructuresTools
RF_LIVE_KEY='rockfill_live_geometry_v1'.freeze
RF_LIVE_MATERIAL='rockfill_section_material'.freeze

def rf_live_excavation_sources
 return [] unless rockfill_source_selection['mode']=='geometry'
 rf_live_result['excavation_m3'].to_f>1e-8 ? [['—','Tasarım yüzeyine kadar kazı','m³',nil,'LIVE_EXCAVATION']] : []
end
def rf_live_extension_report
 r=rf_live_result;html="<p>Kazı: #{format('%.3f',r['excavation_m3'])} m³ — taş toplamından ayrı.</p>"
 (r['assumptions']||[]).each{|a|html+="<p>Hesap kabulü: #{html_escape(a)}</p>"}
 if r['head']
  html+="<h4>Dairesel baş #{r['head']['angle']}° (toplama dahil)</h4><p>Hacim: #{format('%.3f',r['head']['total'])} m³; açısal sıklaştırma farkı: #{format('%.3f',r['head']['refinement_difference_m3'])} m³. Aşağıdaki aralık tablosu yalnız gövdeyi kapsar.</p>"
  r['head']['totals'].each{|k,v|html+="<p>#{html_escape(k)}: Gövde #{format('%.3f',r['body_totals'][k]||0)} / Baş #{format('%.3f',v)} m³</p>"}
 end
 loft=rf_live_loft_status(rf_live_state,r)
 if loft && loft['current']
  html+="<h4>Otomatik kapalı katı kontrolü — #{html_escape(loft['scope'])}</h4>"
  loft['rows'].each{|c|html+="<p>#{html_escape(c['code'])}: Katı #{format('%.3f',c['solid_m3'])} m³; AEA/radyal #{format('%.3f',c['quantity_m3'])} m³; fark #{format('%.3f',c['difference_m3'])} m³</p>"}
 elsif loft
  html+='<p>Önceki otomatik katılar güncel değil; yeniden üretin.</p>'
 end
 (r['solid_comparison']||[]).each{|c|html+="<p>#{html_escape(c['code'])}: Katı #{format('%.3f',c['solid_m3'])} m³; fark #{format('%.3f',c['difference_m3'])} m³</p>"}
 html
end

def rf_live_state
 JSON.parse(Sketchup.active_model.get_attribute(DICT,RF_LIVE_KEY,'{"step":5.0,"extra":[],"types":{},"reaches":[]}'))
end
def rf_live_roots(ids)
 model=Sketchup.active_model;roots=model.entities.to_a
 ids.map do |id|
  e=model.find_entity_by_persistent_id(id)
  raise 'Bağlı geometri silinmiş veya başka grubun içine taşınmış. Kaynağı yeniden seçin.' unless e && e.valid? && roots.include?(e)
  e
 end
end
def rf_live_selection
 model=Sketchup.active_model
 raise 'Grup düzenleme modundan çıkıp modelin ana düzeyinde seçim yapın.' if model.active_path
 roots=model.selection.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)||e.is_a?(Sketchup::Face)||e.is_a?(Sketchup::Edge)}
 raise 'Önce modelden geometri seçin.' if roots.empty?
 roots
end
def rf_live_walk(entities,transform=Geom::Transformation.new,inherited=nil,&block)
 entities.each do |e|
  code=e.get_attribute(DICT,RF_LIVE_MATERIAL,inherited)
  if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
   child=e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
   rf_live_walk(child,transform*e.transformation,code,&block)
  else
   block.call(e,transform,code)
  end
 end
end
def rf_live_point(p,t)
 q=p.transform(t);[q.x.to_m,q.y.to_m,q.z.to_m]
end
def rf_live_axis(ids)
 edges=[];rf_live_walk(rf_live_roots(ids)){|e,t,c|edges<<e.vertices.map{|v|rf_live_point(v.position,t)} if e.is_a?(Sketchup::Edge)}
 AxisChain.order(edges)
end
def rf_live_surface(ids,mode)
 triangles=[];lines=[]
 rf_live_walk(rf_live_roots(ids)) do |e,t,code|
  if mode=='surface' && e.is_a?(Sketchup::Face)
   mesh=e.mesh(0)
   mesh.polygons.each do |poly|
    raise 'Taban yüzeyi üçgenlere ayrılamadı.' unless poly.size==3
    triangles<<poly.map{|i|rf_live_point(mesh.point_at(i.abs),t)}
   end
  elsif mode=='contours' && e.is_a?(Sketchup::Edge)
   lines<<e.vertices.map{|v|rf_live_point(v.position,t)}
  end
 end
 raise 'Yüzey en fazla 100000 üçgen olabilir; çalışma bölgesini seçin.' if triangles.size>100000
 if mode=='contours'
  key=[Sketchup.active_model.object_id,Digest::SHA256.hexdigest(JSON.generate(lines))]
  return @rf_live_tin[1] if @rf_live_tin && @rf_live_tin[0]==key
  result=RockfillTIN.triangulate(lines);@rf_live_tin=[key,result];result
 else;triangles;end
end
def rf_live_faces(spec)
 origin=spec.fetch('origin');angle=spec.fetch('angle')*Math::PI/180;u=[Math.cos(angle),Math.sin(angle),0]
 v=spec['plane']=='XY' ? [-Math.sin(angle),Math.cos(angle),0] : [0,0,1]
 normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];parts=[]
 rf_live_walk(rf_live_roots(spec.fetch('ids'))) do |e,t,code|
  next unless e.is_a?(Sketchup::Face)
  raise 'Tip kesitte malzeme atanmamış yüzey var. Malzeme seçip Yüzeye Ata kullanın.' if code.to_s.empty?
  loops=e.loops.map do |loop|
   loop.vertices.map do |vertex|
    p=rf_live_point(vertex.position,t);d=3.times.map{|i|p[i]-origin[i]}
    raise 'Kesit yüzeyleri seçilen düzlemde değil. Köken / düzlem / açıyı kontrol edin.' if 3.times.sum{|i|d[i]*normal[i]}.abs>0.001
    [3.times.sum{|i|d[i]*u[i]},3.times.sum{|i|d[i]*v[i]}+spec.fetch('datum')]
   end
  end
  parts<<{'code'=>code,'loops'=>loops}
 end
 raise 'Tip kesitte kapalı yüzey bulunamadı; yalnız çizgi/resim alan hesabına yetmez.' if parts.empty?
 {'mode'=>'faces','parts'=>parts}
end
def rf_live_input(state)
 raise 'Önce hesap aksını seçin.' unless state['axis_ids']
 raise 'Önce deniz tabanı yüzeyi veya 3B kot eğrilerini seçin.' unless state['surface_ids']
 axis=rf_live_axis(state['axis_ids']);axis.reverse! if state['reverse']
 types={};state['types'].each{|key,spec|types[key]=spec['mode']=='faces' ? rf_live_faces(spec) : (spec['mode']=='portable_faces' ? {'mode'=>'faces','parts'=>spec.fetch('parts')} : spec)}
 input={'axis'=>axis,'triangles'=>rf_live_surface(state['surface_ids'],state['surface_mode']),'types'=>types,'reaches'=>state['reaches'],'step'=>state['step'],'extra'=>state['extra']}
 if state.dig('excavation','enabled')
  ex=state['excavation'];raise 'Kazı tasarım yüzeyini seçin.' unless ex['ids']
  input['excavation']=ex.merge('triangles'=>rf_live_surface(ex['ids'],'surface'))
 end
 input['type_transition']=state['type_transition']||'step'
 input['void_transition']=state['void_transition']||'stop'
 input['head']=state['head']
 input['solids']=(state['solids']||{}).map do |code,ids|
  roots=rf_live_roots(ids);raise 'Her malzeme için tek, birleştirilmiş kapalı katı seçin.' unless roots.size==1 && (roots.first.is_a?(Sketchup::Group)||roots.first.is_a?(Sketchup::ComponentInstance))
  {'code'=>code,'triangles'=>rf_live_surface(ids,'surface')}
 end
 input
end
def rf_live_result(state=rf_live_state,cells=false)
 input=rf_live_input(state);fingerprint=Digest::SHA256.hexdigest(JSON.generate(input));cache_key=[Sketchup.active_model.object_id,fingerprint,cells]
 @rf_live_cache||={}
 return @rf_live_cache[cache_key] if @rf_live_cache.key?(cache_key)
 result=RockfillGeometry.calculate(input,cells);result['fingerprint']=fingerprint
 result['solid_comparison']=(input['solids']||[]).map do |solid|
  code=solid['code'];volume=RockfillGeometry.closed_mesh_volume(solid['triangles']);aea=result['totals'][code]||0
  {'code'=>code,'solid_m3'=>volume,'quantity_m3'=>aea,'difference_m3'=>volume-aea,'difference_percent'=>aea>0 ? (volume-aea)*100.0/aea : nil}
 end
 @rf_live_cache.clear;@rf_live_cache[cache_key]=result;result
end
def rf_live_qto
 result=rf_live_result;library=rockfill_library;materials=[]
 result['totals'].each do |code,volume|
  next if volume<=1e-8
  matches=library.select{|m|m['code']==code};raise "#{code}: malzeme kütüphanesinde tek kayıt gerekli." unless matches.size==1
  m=matches.first;density=RockfillGeometry.number(m['density']);raise "#{code}: yoğunluk pozitif olmalı." unless density>0
  ton=volume*density;raise 'Tonaj sayısal sınırı aşıyor.' unless ton.finite?
  materials<<{code:code,name:m['name'],density:density,volume_m3:volume,tonnage_t:ton}
 end
 by_code=materials.each_with_object({}){|m,h|h[m[:code]]=m}
 intervals=result['rows'].map do |r|
  rows=r['volumes'].map do |code,vol|
   m=by_code[code];next unless m
   m.merge(a1:r['a1'][code]||0,a2:r['a2'][code]||0,volume_m3:vol,tonnage_t:vol*m[:density])
  end.compact
  {from_id:format('%.3f',r['start']),to_id:format('%.3f',r['end']),from_station:r['start'],to_station:r['end'],length_m:r['end']-r['start'],rows:rows,volume_m3:rows.sum{|m|m[:volume_m3]},tonnage_t:rows.sum{|m|m[:tonnage_t]}}
 end
 {sections:result['sections'],intervals:intervals,materials:materials,total_volume_m3:materials.sum{|m|m[:volume_m3]},total_tonnage_t:materials.sum{|m|m[:tonnage_t]},source_label:'Dolgu / Taş — Alternatif-02 (model geometrisi)',geometry_result:result}
end
def rf_live_loft_status(state,preview)
 loft=state['loft_summary']
 if loft
  entity=Sketchup.active_model.find_entity_by_persistent_id(loft['group_id'])
  same=false
  if entity && entity.valid? && preview && preview['fingerprint']==loft['fingerprint']
   begin
    same=Digest::SHA256.hexdigest(JSON.generate(rf_live_surface([loft['group_id']],'surface')))==loft['geometry_fingerprint']
   rescue
    same=false
   end
  end
  loft=loft.merge('current'=>same)
 end
 loft
end

def rf_live_send(dialog,state=rf_live_state,message='')
 preview=state['last_result'];mode=rockfill_source_selection['mode']
 loft=rf_live_loft_status(state,preview)
 data={'type_transition'=>state['type_transition']||'step','void_transition'=>state['void_transition']||'stop','loft'=>loft,'excavation'=>state['excavation'],'head'=>state['head'],'solids'=>(state['solids']||{}).keys,'step'=>state['step'],'extra'=>state['extra'],'axis_ready'=>!!state['axis_ids'],'surface_ready'=>!!state['surface_ids'],'surface_mode'=>state['surface_mode'],'reverse'=>!!state['reverse'],'origin'=>state['origin'],'types'=>state['types'].map{|k,v|{'id'=>k,'name'=>v['name']||k,'mode'=>v['mode']}},'reaches'=>state['reaches'],'library'=>rockfill_library,'result'=>preview,'active'=>mode=='geometry','message'=>message}
 dialog.execute_script("rfLiveLoaded(#{JSON.generate(data)})")
end
def rf_live_store(state)
 model=Sketchup.active_model;model.start_operation('Alternatif-02 Proje Geometrisi',true)
 begin;model.set_attribute(DICT,RF_LIVE_KEY,JSON.generate(state));model.commit_operation;rescue;model.abort_operation;raise;end
end
class RockfillOriginTool
 def initialize(dialog);@dialog=dialog;@input=Sketchup::InputPoint.new;end
 def onMouseMove(flags,x,y,view);@input.pick(view,x,y);view.tooltip=@input.tooltip;view.invalidate;end
 def draw(view);@input.draw(view) if @input.valid?;end
 def onLButtonDown(flags,x,y,view)
  @input.pick(view,x,y);return unless @input.valid?
  api=MAG::MarineStructuresTools;state=api.rf_live_state;p=@input.position
  state['origin']=[p.x.to_m,p.y.to_m,p.z.to_m];api.rf_live_store(state);api.rf_live_send(@dialog,state,'Kesit kökeni seçildi; bu noktanın kotunu girin.');Sketchup.active_model.select_tool(nil)
 end
 def onCancel(reason,view);Sketchup.active_model.select_tool(nil);end
end
def rf_live_type_token(state,id)
 Digest::SHA256.hexdigest(JSON.generate([Sketchup.active_model.object_id,id,state['types'][id],state['reaches'].select{|r|r['type']==id}]))
end

def rf_live_action(action,json,dialog)
 state=rf_live_state;request=JSON.parse(json||'{}');model=Sketchup.active_model
 case action
 when 'type_edit'
  id=request.fetch('id');spec=state['types'].fetch(id);reach=state['reaches'].find{|r|r['type']==id};raise 'Tip bölgesi bulunamadı.' unless reach
  dialog.execute_script("rfLiveEditType(#{JSON.generate({'id'=>id,'spec'=>spec,'from'=>reach['from'],'token'=>rf_live_type_token(state,id)})})");return
 when 'templates_export','templates_import'
  rf_live_templates_file(action,state,dialog);return
 when 'load'
  state['last_result']=rf_live_result(state) if state['axis_ids'] && state['surface_ids'] && !state['reaches'].empty?
  rf_live_send(dialog,state);return
 when 'design_surface'
  ids=rf_live_selection.map(&:persistent_id);raise 'Kazı tasarım yüzeyi boş.' if rf_live_surface(ids,'surface').empty?
  state['excavation']||={};state['excavation']['ids']=ids
 when 'solid'
  code=request.fetch('code');raise 'Malzeme kodu geçersiz.' unless rockfill_library.any?{|m|m['code']==code}
  ids=rf_live_selection.map(&:persistent_id);raise 'Tek birleştirilmiş kapalı grup seçin.' unless ids.size==1
  RockfillGeometry.closed_mesh_volume(rf_live_surface(ids,'surface'));state['solids']||={};state['solids'][code]=ids
 when 'clear_solids';state['solids']={}
 when 'origin';model.select_tool(RockfillOriginTool.new(dialog));return
 when 'axis'
  state['axis_ids']=rf_live_selection.map(&:persistent_id);rf_live_axis(state['axis_ids'])
 when 'reverse';state['reverse']=!state['reverse']
 when 'tin_preview'
  raise 'Önce taban kaynağı seçin.' unless state['surface_ids']
  triangles=rf_live_surface(state['surface_ids'],state['surface_mode']);model.start_operation('Alternatif-02 TIN Önizleme',true)
  begin
   group=model.entities.add_group;group.name='ALT02 TABAN TIN ÖNİZLEME'
   triangles.each{|t|group.entities.add_face(t.map{|p|p.map{|v|v.m}})}
   model.commit_operation;model.selection.clear;model.selection.add(group);model.active_view.zoom(group)
  rescue;model.abort_operation;raise;end
  return
 when 'surface','contours'
  state['surface_ids']=rf_live_selection.map(&:persistent_id);state['surface_mode']=action
  tris=rf_live_surface(state['surface_ids'],action);raise 'Seçimde üçgen taban yüzeyi yok.' if tris.empty?
 when 'material'
  code=request.fetch('code');raise 'Geçersiz malzeme.' unless code=='__CONCRETE__' || rockfill_library.any?{|m|m['code']==code}
  roots=rf_live_selection;model.start_operation('Tip Kesite Malzeme Ata',true)
  begin
   count=0;rf_live_walk(roots){|e,t,c|if e.is_a?(Sketchup::Face);e.set_attribute(DICT,RF_LIVE_MATERIAL,code);count+=1;end}
   raise 'Malzeme atanacak kapalı yüzey bulunamadı.' if count==0
   model.commit_operation
  rescue;model.abort_operation;raise;end
  state.delete('last_result');rf_live_store(state);rf_live_send(dialog,state,'Seçilen kesit yüzeylerine malzeme atandı.');return
 when 'type','type_update'
  editing=action=='type_update'
  if editing
   id=request.fetch('id');raise 'Düzenlenen tip artık yok.' unless state['types'].key?(id)
   raise 'Tip veya proje değişti; Düzenle ile güncel kaydı yeniden açın.' unless request['token']==rf_live_type_token(state,id)
  end
  from=RockfillGeometry.number(request.fetch('from'));raise 'Başlangıç istasyonu negatif olamaz.' if from<0
  id="T#{(state['types'].keys.map{|k|k.delete('T').to_i}.max||0)+1}" unless editing
  spec={'mode'=>request.fetch('mode'),'name'=>request['name'].to_s}
  if spec['mode']=='faces'
   existing=editing ? state['types'][id] : nil
   keep_source=existing && existing['mode']=='faces' && request['rebind']!=true
   origin=keep_source ? existing['origin'] : state['origin']
   raise 'Önce kesit kökenini tıklayarak seçin.' unless origin
   ids=keep_source ? existing['ids'] : rf_live_selection.map(&:persistent_id)
   spec.merge!('ids'=>ids,'origin'=>origin,'plane'=>request.fetch('plane'),'angle'=>RockfillGeometry.number(request['angle']),'datum'=>RockfillGeometry.number(request['datum']))
   raise 'Kesit düzlemi XY veya XZ olmalı.' unless %w[XY XZ].include?(spec['plane'])
   rf_live_faces(spec)
  elsif spec['mode']=='portable_faces'
   spec=rf_template_spec(request)
   shift=RockfillGeometry.number(request.fetch('template_shift',0))
   spec['parts'].each{|p|p['loops'].each{|loop|loop.each{|point|point[1]+=shift}}}
   spec=rf_template_spec(spec)
  elsif spec['mode']=='parametric'
   %w[crest width slope_left slope_right].each{|k|spec[k]=RockfillGeometry.number(request.fetch(k))}
   spec['layers']=request.fetch('layers');RockfillGeometry.parametric(spec,[[[-100,spec['crest']-100],[100,spec['crest']-100]]])
  else;raise 'Geçersiz tip kesit yöntemi.';end
  rf_template_materials!(spec) if spec['mode']!='faces'
  raise 'Bu istasyonda başka tip var; farklı başlangıç seçin.' if state['reaches'].any?{|r|r['from']==from && r['type']!=id}
  if state['axis_ids']
   length=RockfillGeometry.chain(rf_live_axis(state['axis_ids'])).last
   raise 'Tip başlangıcı aksın sonundan küçük olmalı.' unless from<length
  end
  other=state['reaches'].reject{|r|r['type']==id}
  raise 'İlk tip 0 m başlangıcında kalmalı.' if editing && from!=0 && other.none?{|r|r['from']==0}
  state['types'][id]=spec;state['reaches']=other+[{'from'=>from,'type'=>id}]
  if editing
   state.delete('last_result');rf_live_store(state);dialog.execute_script('rfLiveTypeSaved()');rf_live_send(dialog,state,'Tip güncellendi; kimliği korundu. Geometriden Hesapla ile yeni miktarı kontrol edin.');return
  end
 when 'remove'
  id=request.fetch('id');state['types'].delete(id);state['reaches'].reject!{|r|r['type']==id}
 when 'settings','calculate','activate','show','loft','refine','report'
  if action=='settings' || action=='calculate' || action=='loft' || action=='refine' || action=='report' || (action=='activate' && request.key?('step'))
   if request.key?('excavation')
    state['excavation']=(state['excavation']||{}).merge(request['excavation'])
    state['excavation']['enabled']=request['excavation']['enabled']==true
    %w[left right].each{|k|state['excavation'][k]=RockfillGeometry.number(state['excavation'][k])}
   end
   %w[type_transition void_transition].each{|k|state[k]=request[k] if request.key?(k)}
   raise 'Geçersiz tip geçiş seçimi.' unless %w[step linear].include?(state['type_transition']||'step')
   raise 'Geçersiz boşluk geçiş seçimi.' unless %w[stop point].include?(state['void_transition']||'stop')
   state['head']=request['head'] if request.key?('head')
   state['step']=RockfillGeometry.number(request.fetch('step'));raise 'Kesit aralığı pozitif olmalı.' unless state['step']>0
   state['extra']=request['extra'].to_s.split(/[;\s]+/).reject(&:empty?).map{|x|RockfillGeometry.number(x)}
  end
  if action=='report'
   rf_live_export_report(state,dialog)
   return
  end
  if action=='refine'
   comparison=RockfillGeometry.refinement(rf_live_input(state))
   dialog.execute_script("rfLiveRefined(#{JSON.generate(comparison)})")
   return
  end
  if action=='loft';rf_live_create_loft(state,dialog);return;end
  if action=='calculate' || action=='activate'
   result=rf_live_result(state);state['last_result']=result
   rf_live_store(state)
   if action=='activate'
    rf_live_qto
    model.start_operation('Alternatif-02 Canlı QTO Kaynağı',true)
    begin;model.set_attribute(DICT,ROCKFILL_SOURCE_KEY,JSON.generate({'mode'=>'geometry'}));model.commit_operation;rescue;model.abort_operation;raise;end
    send_boq(dialog);qto_summary(dialog)
   end
   rf_live_send(dialog,state,'Geometriden hesaplandı. BOQ aynı geometriyi yeniden okuyarak miktarı günceller.');return
  elsif action=='show'
   result=rf_live_result(state);index=Integer(request.fetch('index'));raise 'Kesit seçimi geçersiz.' unless index>=0 && index<result['sections'].size
   section=result['sections'][index].dup;spec=state['types'].fetch(section['type'])
   parts=section['parts'] || (spec['mode']=='parametric' ? RockfillGeometry.parametric(spec,section['bed']) : rf_live_faces(spec)['parts'])
   section['cells']=RockfillGeometry.section(parts,section['bed'],true)['cells']
   fr=section['frame'];model.start_operation('Alternatif-02 Enkesiti Göster',true)
   begin
    group=model.entities.add_group;group.name="ALT02 KESİT #{format('%.3f',section['station'])} #{section['type']}"
    section['cells'].each do |cell|
     points=cell['points'].map{|x,z|Geom::Point3d.new((fr['origin'][0]+x*fr['normal'][0]).m,(fr['origin'][1]+x*fr['normal'][1]).m,z.m)}
     next if points.uniq.size<3
     face=group.entities.add_face(points);next unless face
     face.set_attribute(DICT,RF_LIVE_MATERIAL,cell['code']);color=cell['code'].each_byte.sum
     face.material=Sketchup::Color.new(70+color%150,70+(color*3)%150,70+(color*7)%150);face.back_material=face.material
    end
    section['bed'].each{|a,b|group.entities.add_line(*[a,b].map{|x,z|[(fr['origin'][0]+x*fr['normal'][0]).m,(fr['origin'][1]+x*fr['normal'][1]).m,z.m]})}
    model.commit_operation;model.selection.clear;model.selection.add(group);model.active_view.zoom(group)
   rescue;model.abort_operation;raise;end
   return
  end
 else;raise 'Bilinmeyen yeni proje işlemi.'
 end
 state.delete('last_result');rf_live_store(state);rf_live_send(dialog,state,'Proje girdisi kaydedildi. Geometriden Hesapla ile sonucu görün.')
rescue=>e
 dialog.execute_script("rfLiveError(#{JSON.generate(e.message)})")
end
end
end
