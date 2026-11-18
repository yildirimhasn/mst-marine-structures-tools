# frozen_string_literal: true
module MAG
module MarineStructuresTools
def mst_topping_face_key(points,normal)
 [normal.to_a.map{|v|v.round(7)},points.map{|p|p.to_a.map{|v|v.to_m.round(6)}}.sort]
end
def mst_topping_mark_formwork!(group,deck,z,ux,uy,additions)
 model=Sketchup.active_model;hex=deck.get_attribute(DICT,'formwork_color','#66A9E8').to_s;hex='#66A9E8' if hex.empty?
 material=material_for(model,"MAG Kaplama Kalıp #{hex}",hex);area=0.0
 group.entities.grep(Sketchup::Face).each do |face|
  points=face.vertices.map{|v|v.position.to_a.map(&:to_m)}
  center=3.times.map{|i|points.sum{|p|p[i]}/points.size}
  nu=face.normal.x*ux+face.normal.y*uy;nv=-face.normal.x*uy+face.normal.y*ux
  u=center[0]*ux+center[1]*uy+nu*1e-5;v=-center[0]*uy+center[1]*ux+nv*1e-5
  contact=additions.any?{|c|u>c['u0']-1e-7&&u<c['u1']+1e-7&&v>c['v0']-1e-7&&v<c['v1']+1e-7&&center[2]<z+c['h'].to_f+1e-7}
  form=face.normal.z.abs<1e-7&&!contact
  mark_formwork_face(face,form,material,nil,form ? 'SIDE_FORM':'CONTACT_OR_TOP')
  area+=face.area/(1.m**2) if form
 end
 group.set_attribute(DICT,'formwork_area_m2',area)
 group.set_attribute(DICT,'topping_formwork_schema','1')
 group.set_attribute(DICT,'formwork_rule','Free vertical sides only; bottom/top and curb/bollard contacts excluded.')
 area
end
def mst_deck_persist_topping_inputs!(deck)
 raw=deck.get_attribute(DICT,'deck_input_json','').to_s
 return if raw.empty?
 data=JSON.parse(raw)
 raise 'Döşeme giriş kaydı nesne olmalı.' unless data.is_a?(Hash)
 %w[topping_enabled topping_thickness_m topping_concrete_class].each do |key|
  value=deck.get_attribute(DICT,key,nil)
  data[key]=value unless value.nil?
 end
 deck.set_attribute(DICT,'deck_input_json',JSON.generate(data))
end
def mst_deck_sync_topping!(deck,model=Sketchup.active_model)
 uid=ensure_uid(deck);all=mst_collect_toppings(model.entities)
 candidates=all.select{|e|e.get_attribute(DICT,'element_type')=='deck_topping'&&e.get_attribute(DICT,'parent_uid','')==uid}
 raise 'Aynı döşemeye bağlı birden fazla fiziksel kaplama var; mükerrer kaydı kontrol edin.' if candidates.size>1
 old=candidates.first
 if deck.get_attribute(DICT,'topping_enabled','0').to_s!='1'
  old.erase! if old&&old.valid?
  return nil
 end
 plan=JSON.parse(deck.get_attribute(DICT,'deck_plan_json','{}'))
 rects=plan.fetch('surface_rects');z=deck.get_attribute(DICT,'top_elevation_m').to_f
 th=Float(deck.get_attribute(DICT,'topping_thickness_m',0.1));raise 'Kaplama kalınlığı pozitif ve sonlu olmalı.' unless th.finite?&&th>0
 ux,uy=JSON.parse(deck.get_attribute(DICT,'deck_u_axis'))
 additions=JSON.parse(deck.get_attribute(DICT,'deck_additions_json','[]'))
 boxes=rects.map{|u0,u1,v0,v1|[u0,u1,v0,v1,z,z+th]}
 mesh,_cells=mst_deck_boundary_mesh({'boxes'=>boxes,'faces'=>[],'split_z'=>additions.map{|c|z+[c['h'].to_f,th].min}},ux,uy)
 cc=deck.get_attribute(DICT,'topping_concrete_class','C35/45')
 if old && old.transformation.identity? && old.manifold? && old.get_attribute(DICT,'concrete_class')==cc &&
    (old.get_attribute(DICT,'thickness_m',0).to_f-th).abs<1e-9
  desired=mesh.polygons.map do |polygon|
   pts=polygon.map{|i|mesh.point_at(i.abs)}
   mst_topping_face_key(pts,(pts[1]-pts[0]).cross(pts[2]-pts[0]).normalize)
  end.sort
  actual=old.entities.grep(Sketchup::Face).map{|f|mst_topping_face_key(f.outer_loop.vertices.map(&:position),f.normal)}.sort
  if actual==desired
   mst_topping_mark_formwork!(old,deck,z,ux,uy,additions)
   return old
  end
 end
 g=old||model.entities.add_group;g.entities.clear!;g.transformation=Geom::Transformation.new
 g.entities.fill_from_mesh(mesh,true,0)
 raise 'Kaplama kapalı katı oluşturulamadı.' unless g.manifold?
 area=rects.sum{|r|(r[1]-r[0])*(r[3]-r[2])};vol=area*th
 raise 'Kaplama katı hacmi metrajıyla uyuşmuyor.' if (g.volume/(1.m**3)-vol).abs>[1e-4,vol*1e-7].max
 mat=material_for(model,'MST Kaplama Betonu','#C8CCD1');g.material=mat
 did=deck.get_attribute(DICT,'deck_id','D-001');g.name="TOP-#{did}"
 {'element_type'=>'deck_topping','topping_id'=>g.name,'parent_deck_id'=>did,'parent_uid'=>uid,'thickness_m'=>th,
  'concrete_class'=>cc,'concrete_volume_m3'=>vol,'plan_area_m2'=>area,
  'bottom_elevation_m'=>z,'top_elevation_m'=>z+th,'topping_rule'=>'DS3_SURFACE_MINUS_OPENINGS_AND_CURBS'}.each{|k,v|g.set_attribute(DICT,k,v)}
 %w[project system structure ano zone qto_zone].each{|k|v=deck.get_attribute(DICT,k,nil);g.set_attribute(DICT,k,v) unless v.nil?}
 mst_topping_mark_formwork!(g,deck,z,ux,uy,additions)
 finalize_bim_identity(g,model)
 mst_scan_cache_add(g)
 deck.set_attribute(DICT,'topping_area_m2',area);deck.set_attribute(DICT,'topping_volume_m3',vol)
 g
end
end
end
