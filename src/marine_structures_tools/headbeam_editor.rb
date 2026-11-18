# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  module HeadBeamEditor
   extend self
   FEATURES={
    'start_tooth'=>%w[length depth slope], 'end_tooth'=>%w[length depth slope],
    'start_seat'=>%w[offset length depth], 'end_seat'=>%w[offset length depth]
   }.freeze
   PROFILE_KEYS=FEATURES.flat_map{|prefix,keys|["#{prefix}_enabled"]+keys.map{|key|"#{prefix}_#{key}_m"}}.freeze
   def api;MarineStructuresTools;end
   def signature_data(e)
    FEATURES.map do |prefix,keys|
     on=e.get_attribute(DICT,"#{prefix}_enabled",'0').to_s=='1'
     [prefix,on,on ? keys.map{|key|e.get_attribute(DICT,"#{prefix}_#{key}_m",0).to_f.round(6)} : []]
    end
   end
   def normalized(h)
    data=h.dup
    %w[length_m width_m height_m].each do |key|
     data[key]=QuantityService.number(h[key],key)
     raise "#{key}: sıfırdan büyük ölçü gerekli." unless data[key]>0
    end
    FEATURES.each do |prefix,keys|
     flag=h.fetch("#{prefix}_enabled",'0').to_s
     raise "#{prefix}: etkinlik kaydı geçersiz." unless %w[0 1].include?(flag)||flag.empty?
     data["#{prefix}_enabled"]=flag=='1' ? '1' : '0'
     keys.each{|key|name="#{prefix}_#{key}_m";data[name]=flag=='1' ? QuantityService.number(h[name],name) : 0.0}
     next unless flag=='1'
     length=data["#{prefix}_length_m"];depth=data["#{prefix}_depth_m"]
     raise "#{prefix}: uzunluk ve derinlik sıfırdan büyük olmalı." unless length>0&&depth>0
     if prefix.include?('tooth')
      raise "#{prefix}: eğim boyu diş boyundan büyük olamaz." if data["#{prefix}_slope_m"]>length
      raise "#{prefix}: diş boyu kiriş boyundan küçük olmalı." unless length<data['length_m']
     else
      raise "#{prefix}: oturma derinliği kiriş yüksekliğinden küçük olmalı." unless depth<data['height_m']
      raise "#{prefix}: oturma bölgesi kiriş sınırını aşıyor." if data["#{prefix}_offset_m"]+length>data['length_m']
     end
    end
    if data['start_tooth_enabled']=='1'&&data['end_tooth_enabled']=='1'
     raise 'Başlangıç ve son dişleri üst üste gelemez.' unless data['start_tooth_length_m']+data['end_tooth_length_m']<data['length_m']
    end
    if data['start_seat_enabled']=='1'&&data['end_seat_enabled']=='1'
     raise 'Başlangıç ve son oturma bölgeleri üst üste gelemez.' if data['start_seat_offset_m']+data['start_seat_length_m']>data['length_m']-data['end_seat_offset_m']-data['end_seat_length_m']
    end
    data
   end
   def profile(h)
    data=normalized(h)
    scale=api.m(1).to_f
    points=api.recess_profile_points(api.m(data['length_m']),api.m(data['height_m']),data).map{|x,z|[x/scale,z/scale]}
    loop do
     index=points.each_index.find do |i|
      a=points[(i-1)%points.size];b=points[i];c=points[(i+1)%points.size]
      ((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0])).abs<1e-12
     end
     break unless index&&points.size>3
     points.delete_at(index)
    end
    points
   end
   # Normalize the existing SketchUp profile to metres before area calculations.
   def metrics(h,flags)
    data=normalized(h);points=profile(data);width=data['width_m']
    area=api.polygon_area_xz(points)
    parts={'LONG_SIDE'=>2*area,'BOTTOM'=>0.0,'RECESS_SLOPE'=>0.0,'END_FACE'=>0.0,'TOP_OR_CONTACT'=>0.0}
    points.each_with_index do |p,i|
     q=points[(i+1)%points.size];dx=q[0]-p[0];dz=q[1]-p[1];length=Math.hypot(dx,dz)
     next if length<1e-12
     nz=dx/length
     role=nz>0.999 ? 'TOP_OR_CONTACT' : nz < -0.001 ? (nz < -0.999 ? 'BOTTOM' : 'RECESS_SLOPE') : 'END_FACE'
     parts[role]+=length*width
    end
    gross=parts.sum{|role,value|flags.fetch(role,false) ? value : 0.0}
    opening=QuantityService.number(h.fetch('pile_opening_area_m2',0),'kazık açıklığı')
    {points:points,volume:area*width,gross:gross,net:[gross-opening,0.0].max,parts:parts,opening:opening}
   end
   def role(face)
    n=face.normal
    return 'TOP_OR_CONTACT' if n.z>0.999
    return 'LONG_SIDE' if n.y.abs>0.999
    return n.z < -0.999 ? 'BOTTOM' : 'RECESS_SLOPE' if n.z < -0.001
    'END_FACE'
   end
   def flags(e)
    faces=e.entities.grep(Sketchup::Face)
    raise 'Başlık kirişi yüzleri bulunamadı.' if faces.empty?
    result={}
    faces.group_by{|face|role(face)}.each do |key,group|
     values=group.map{|face|face.get_attribute(DICT,'formwork',nil)}.uniq
     raise "#{key}: farklı/eksik kalıp yüzü seçimleri var. Bu düzenleyici yalnız aynı yüz rolündeki ortak seçimleri koruyabilir." unless values.size==1&&[true,false].include?(values.first)
     result[key]=values.first
    end
    result
   end
   def validate_geometry(e,h)
    result=metrics(h,flags(e));points=result[:points]
    expected=[0,h['width_m'].to_f].flat_map{|y|points.map{|x,z|[api.m(x).to_f.round(6),api.m(y).to_f.round(6),api.m(z).to_f.round(6)]}}.uniq
    actual=e.entities.grep(Sketchup::Face).flat_map{|face|face.vertices.map{|v|v.position.to_a.map{|n|n.to_f.round(6)}}}.uniq
    raise 'Başlık kirişi geometri profili kayıtlı parametrik kesitle uyuşmuyor.' unless actual.all?{|p|expected.include?(p)}&&actual.size>=8
    volume=e.volume.to_f/(api.m(1).to_f**3)
    raise 'Başlık kirişi kapalı/uyumlu parametrik katı değil.' unless e.manifold?&&(volume-result[:volume]).abs<[1e-7,result[:volume]*1e-7].max
    raise 'Geometri dışındaki not/ölçü veya bağımsız kenarlar korunamıyor; işlem durduruldu.' unless e.entities.all?{|part|part.is_a?(Sketchup::Face)||(part.is_a?(Sketchup::Edge)&&!part.faces.empty?)}
    materials(e)
   end
   def materials(e)
    e.entities.grep(Sketchup::Face).group_by{|face|role(face)}.transform_values do |faces|
     pairs=faces.map{|face|[face.material,face.back_material]}.uniq
     raise 'Aynı yüz rolünde farklı malzemeler var; yüz malzemeleri kaybedilmeden düzenleme yapılamıyor.' unless pairs.size==1
     pairs.first
    end
   end
   def change_list(h,values)
    values.map{|key,value|old=h[key];same=key=='concrete_class' ? value==old.to_s : (value-old.to_f).abs<=1e-9;{label:ControlledEditor::FIELDS['head_beam'][key]||'Beton sınıfı',before:old,after:value} unless same}.compact
   end
   def plan(model,request,entry)
    e=entry[:entity];raw=request['values'];h=api.mst_attr_hash(e)
    raise 'Başlık kirişi alanları eksik veya desteklenmiyor.' unless raw.is_a?(Hash)&&raw.keys.sort==%w[concrete_class height_m length_m width_m].sort
    values=%w[length_m width_m height_m].each_with_object({}){|key,result|result[key]=QuantityService.number(raw[key],key)}
    values['concrete_class']=raw['concrete_class'].to_s.strip
    raise 'Geçerli beton sınıfı seçin.' unless ControlledEditor::CLASSES.include?(values['concrete_class'])
    next_data=normalized(h.merge(values));flags_now=flags(e)
    changed=values.any?{|key,value|key!='concrete_class'&&(value-h[key].to_f).abs>1e-9}
    changes=change_list(h,values)
    raise 'Değişiklik bulunamadı.' if changes.empty?
    deps=api.mst_dependency_tree(e)
    if changed
     ElevationSync.placement(entry);ElevationSync.verify_levels(entry);validate_geometry(e,h)
     raise 'Detaylı donatılı başlık kirişinin ölçüleri donatıyla birlikte yeniden oluşturulmalıdır.' if %w[bim_detail drawing_detail auto_detail].include?(h['rebar_mode'].to_s)
     raise 'Bağlı prekast/döşeme var; kiriş ölçüleri bağlantılı geometriyle birlikte yeniden oluşturulmalıdır.' unless deps.empty?
     pile_ids=RelationshipAudit.tokens(h['connected_pile_ids'])
     unless pile_ids.empty?
      raise 'Kazıklara bağlı kirişin boyu ve uç taşmaları bu akıştan değiştirilemez.' if (values['length_m']-h['length_m'].to_f).abs>1e-9
      raise 'Kazıklara bağlı kirişin genişliği, kazık yerleşimleri geometrik olarak denetlenmeden küçültülemez.' if values['width_m']<h['width_m'].to_f-1e-9
      audit=RelationshipAudit.analyze(model)[:records].find{|r|r[:key]==entry[:key]}
      raise 'Başlık kirişi ilişki kaydı bulunamadı.' unless audit
      raise "Başlık kirişi ilişkisi geçersiz: #{audit[:checks].first[:message]}" unless audit[:checks].empty?
      piles=ProjectWorkspace.entries(model).map{|r|r[:entity]}.select{|p|p.get_attribute(DICT,'element_type')=='steel_pipe_pile'&&pile_ids.include?(api.element_visible_id(p))}
      diameters=piles.map{|p|QuantityService.number(p.get_attribute(DICT,'diameter_mm',nil),'kazık çapı')/1000.0}
      raise 'Kiriş genişliği kazık çapından küçük olamaz.' unless diameters.all?{|d|d>0&&d<=values['width_m']}
      # FIX-01: eğik kazıkta kayıtlı açıklık elipstir (BK oluşturma, H4b yönelim güncellemesi ve mst_bk_follow_plan ile aynı
      # formül: mst_pile_opening_m2 × mst_pile_opening_ratio). Daire formülü eğik kazıklı her BK'da düzenlemeyi reddediyordu.
      opening=piles.sum{|p|api.mst_pile_opening_m2(QuantityService.number(p.get_attribute(DICT,'diameter_mm',nil),'kazık çapı'),api.mst_pile_opening_ratio(p))}
      raise 'Kazık açıklığı kaydı mevcut kazık çaplarıyla (ve eğimleriyle) uyuşmuyor.' if (opening-QuantityService.number(h.fetch('pile_opening_area_m2',nil),'kazık açıklığı')).abs>1e-7
     end
    end
    result=metrics(next_data,flags_now)
    result[:volume]=QuantityService.value(e,:concrete_m3) unless changed
    result[:net]=QuantityService.value(e,:formwork_m2) unless changed
    {entry:entry,values:values,geometry_changed:changed,changes:changes,volume:result[:volume],formwork:result[:net],dependencies:deps.size}
   end
   def rebuild(e,values)
    h=api.mst_attr_hash(e);flags_now=flags(e);updated=normalized(h.merge(values));result=metrics(updated,flags_now)
    materials_now=materials(e)
    points=result[:points].map{|x,z|Geom::Point3d.new(api.m(x),0,api.m(z))}
    e.entities.clear!;face=e.entities.add_face(points);raise 'Başlık kirişi profili oluşturulamadı.' unless face
    face.reverse! if face.normal.y<0;face.pushpull(api.m(updated['width_m']))
    e.entities.grep(Sketchup::Face).each do |f|
     kind=role(f);on=flags_now.fetch(kind,false)
     f.set_attribute(DICT,'formwork',on);f.set_attribute(DICT,'formwork_type',kind)
     f.material,f.back_material=materials_now.fetch(kind,[nil,nil])
    end
    width_shift=(updated['width_m']-h['width_m'].to_f)/2
    e.transformation=e.transformation*Geom::Transformation.translation([0,-api.m(width_shift),0]) if width_shift.abs>1e-9
    updated['top_elevation_m']=ElevationSync.number(h['bottom_elevation_m'],'kiriş alt kotu')+updated['height_m']
    updated['concrete_volume_m3']=result[:volume];updated['formwork_area_m2']=result[:gross];updated['formwork_gross_area_m2']=result[:gross];updated['formwork_net_area_m2']=result[:net]
    updated['formwork_bottom_m2']=%w[BOTTOM RECESS_SLOPE].sum{|key|flags_now[key] ? result[:parts][key] : 0.0}
    updated['formwork_long_sides_m2']=flags_now['LONG_SIDE'] ? result[:parts]['LONG_SIDE'] : 0.0
    updated['formwork_end_faces_m2']=flags_now['END_FACE'] ? result[:parts]['END_FACE'] : 0.0
    api.mst_restore_attrs(e,updated)
    validate_geometry(e,updated)
   end
  end
 end
end
