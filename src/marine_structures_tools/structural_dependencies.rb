# frozen_string_literal: true
module MAG
module MarineStructuresTools
# Runs inside the caller's transaction. Every failure rolls the whole edit back.
def mst_refresh_structural_dependents!(beams,model=Sketchup.active_model,before={})
 all=[];collect_elements(model.entities,all)
 by_pid=all.each_with_object({}){|e,h|h[e.persistent_id]=e}
 changed=beams.map(&:persistent_id)
 references=lambda do |e|
  ids=%w[support_left_pid support_right_pid].map{|k|e.get_attribute(DICT,k,0).to_i}
  ids.map{|pid|by_pid[pid]}
 end
 old_top=lambda{|b|h=before[b.persistent_id];h ? h['top_elevation_m'].to_f : b.get_attribute(DICT,'top_elevation_m').to_f}
 followers=all.select do |e|
  t=e.get_attribute(DICT,'element_type','')
  (%w[flat_precast channel_precast crane_precast].include?(t)||(t=='head_beam'&&respond_to?(:mst_v50_link?)&&mst_v50_link?(e)))&&
   %w[support_left_pid support_right_pid].any?{|k|changed.include?(e.get_attribute(DICT,k,0).to_i)}
 end
 # Never partially rebuild geometry that cannot be represented by this route.
 followers.each do |e|
  l,r=references.call(e);raise "#{element_visible_id(e)}: iki taşıyıcı BK bulunamadı." unless l&&r&&l!=r
  z1=l.get_attribute(DICT,'top_elevation_m').to_f;z2=r.get_attribute(DICT,'top_elevation_m').to_f
  raise "#{element_visible_id(e)}: bağlı BK üst kotları farklı; iki BK'yı aynı kot revizyonunda düzenleyin." if (z1-z2).abs>0.005
 end
 links=followers.select{|e|e.get_attribute(DICT,'element_type')=='head_beam'}
 links.each do |e|
  l,r=references.call(e);h=mst_attr_hash(e)
  offset=h.key?('link_top_offset_m') ? h['link_top_offset_m'].to_f : h['top_elevation_m'].to_f-[old_top.call(l),old_top.call(r)].min
  p={'pos_m'=>h['link_pos_m'],'width_m'=>h['width_m'],'height_m'=>h['height_m'],'top_m'=>[l,r].map{|b|b.get_attribute(DICT,'top_elevation_m').to_f}.min+offset}
  pl=mst_vk_plan(l,r,p);len=pl['span'];w=pl['width'];hei=pl['height']
  fm=material_for(model,"MAG Kalıp #{h['formwork_color']}",h['formwork_color'].to_s.empty? ? '#F4B183':h['formwork_color'])
  e.entities.clear!
  f=e.entities.add_face([0,-m(w/2),0],[m(len),-m(w/2),0],[m(len),m(w/2),0],[0,m(w/2),0]);f.reverse! if f.normal.z<0;f.pushpull(m(hei))
  e.entities.grep(Sketchup::Face).each do |fc|
   n=fc.normal;on=n.z< -0.999||n.y.abs>0.999
   mark_formwork_face(fc,on,fm,nil,on ? (n.z<0 ? 'BOTTOM':'LONG_SIDE'):'BK_CONTACT_OR_TOP')
  end
  vx,vy=pl['dir'];sx,sy=pl['start'];world=Geom::Transformation.axes(Geom::Point3d.new(m(sx),m(sy),m(pl['bottom'])),Geom::Vector3d.new(vx,vy,0),Geom::Vector3d.new(-vy,vx,0),Z_AXIS)
  e.transformation=mst_world_tr(e).inverse*world
  {'length_m'=>len,'top_elevation_m'=>pl['top'],'bottom_elevation_m'=>pl['bottom'],'concrete_volume_m3'=>len*w*hei,
   'formwork_area_m2'=>len*w+2*len*hei,'formwork_gross_area_m2'=>len*w+2*len*hei,'formwork_net_area_m2'=>len*w+2*len*hei,
   'formwork_bottom_m2'=>len*w,'formwork_long_sides_m2'=>2*len*hei,'formwork_end_faces_m2'=>0.0,
   'link_contact_json'=>JSON.generate(pl['contact']),'link_top_offset_m'=>offset,
   'rail_length_m'=>h['rail_kg_m'].to_f>0 ? len+(pl['w1']+pl['w2'])/2.0 : 0.0}.each{|k,v|e.set_attribute(DICT,k,v)}
  # v0.52.18 ADAY7 G-092: geometri silinip yeniden kurulduğu için eski 3B donatı gitti; kayıtlı donatı kg/mod bayat kalmaz.
  # bim_detail + kayıtlı parametre (hb_rebar_json): yeni boya göre yeniden kurulur. Parametresiz detay modu: işlem reddedilir (hepsi geri alınır).
  lmode=e.get_attribute(DICT,'rebar_mode','').to_s
  lhas=!e.get_attribute(DICT,'hb_rebar_json','').to_s.empty?
  if lmode=='bim_detail' && lhas
   mst_hb_rebar_build!(e,JSON.parse(e.get_attribute(DICT,'hb_rebar_json','{}').to_s))
  elsif %w[bim_detail drawing_detail auto_detail].include?(lmode)
   raise "#{element_visible_id(e)}: bağlantı kirişinin detaylı donatısı yeni boya göre yeniden kurulamıyor (kayıtlı donatı parametresi yok); bayat tonaj kalmaması için işlem geri alındı. Donatıyı yeniden çizin."
  end
 end
 followers.reject{|e|links.include?(e)}.each do |e|
  l,r=references.call(e)
  world=mst_world_tr(e)*e.transformation
  inverse=world.inverse
  raise "#{element_visible_id(e)}: prekast yatay olmalı." unless world.xaxis.z.abs<1e-6 && world.yaxis.z.abs<1e-6 && (world.zaxis.z-1).abs<1e-6
  bounds=[l,r].map do |beam|
   transform=inverse*mst_world_tr(beam)*beam.transformation
   xs=mst_container_entities(beam).grep(Sketchup::Face).flat_map do |face|
    face.vertices.map{|vertex|vertex.position.transform(transform).x}
   end
   raise "#{element_visible_id(e)}: BK kesit geometrisi bulunamadı." if xs.empty?
   [beam,*xs.minmax]
  end
  left,right=bounds.sort_by{|_,low,high|low+high}
  l=left[0]
  seat=e.get_attribute(DICT,'seat_each_side_m',e.get_attribute(DICT,'seat_left_m',0.15)).to_f
  seat_r=e.get_attribute(DICT,'seat_each_side_m',e.get_attribute(DICT,'seat_right_m',seat)).to_f
  len=(right[1]-left[2]).to_m+seat+seat_r
  raise "#{element_visible_id(e)}: yeni açıklık geçersiz." unless len>seat+seat_r
  dz=l.get_attribute(DICT,'top_elevation_m').to_f-old_top.call(l)
  target=Geom::Point3d.new(left[2]-m(seat),0,0).transform(world)
  target.z+=m(dz)
  newtr=Geom::Transformation.translation(target-world.origin)*world
  oldlen=e.get_attribute(DICT,'length_m').to_f
  if (len-oldlen).abs>1e-6
   detail=mst_pc_def_rebar(e)||{}
   rebar=e.get_attribute(DICT,'pc_rebar_json',detail['pc_rebar_json']).to_s
   mode=e.get_attribute(DICT,'rebar_mode',detail['rebar_mode']).to_s
   if %w[bim_detail drawing_detail auto_detail].include?(mode) && rebar.empty?
    raise "#{element_visible_id(e)}: donatı çiziminden gelen detay bu boy için yeniden tanımlanmalı."
   end
   case e
   when Sketchup::ComponentInstance;mst_precast_component_set_length!(e,len,model)
   else
    case e.get_attribute(DICT,'element_type')
    when 'flat_precast';mst_rebuild_flat_precast_length(e,len)
    when 'channel_precast';mst_rebuild_channel_precast_length(e,len)
    else;mst_rebuild_crane_precast_length(e,len)
    end
   end
   mst_precast_canonical_type!(e,{})
   unless rebar.empty?
    e.make_unique if e.is_a?(Sketchup::ComponentInstance) && e.definition.instances.size>1
    family=mst_pc_family(e)
    mst_pc_draw!(e,mst_pc_params(family,JSON.parse(rebar)))
   end
  end
  e.transformation=mst_world_tr(e).inverse*newtr
  %w[bottom_elevation_m main_bottom_elevation_m top_elevation_m].each{|k|v=e.get_attribute(DICT,k,nil);e.set_attribute(DICT,k,v.to_f+dz) if v.is_a?(Numeric)}
 end
 @mst_vk_idx=nil
 all.select{|e|e.get_attribute(DICT,'element_type')=='deck_slab'&&!(e.get_attribute(DICT,'support_pids','').split(',').map(&:to_i)&changed).empty?}.each{|d|mst_deck_regenerate!(d,model,true)}
 {precasts:followers.size-links.size,links:links.size}
end
end
end
