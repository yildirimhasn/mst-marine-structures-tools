# frozen_string_literal: true
module MAG
module MarineStructuresTools
def mst_column_geometry_metrics(entity)
 faces=entity.definition.entities.grep(Sketchup::Face)
 points=faces.flat_map{|f|f.vertices.map{|v|v.position.to_a.map(&:to_m)}}
 closed=!faces.empty?&&faces.flat_map(&:edges).uniq.all?{|edge|edge.faces.size==2}
 return [[],0.0,false] if points.empty?
 bounds=3.times.flat_map{|i|values=points.map{|p|p[i]};[values.min,values.max]}
 cross=lambda{|a,b|[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
 dot=lambda{|a,b|3.times.sum{|i|a[i]*b[i]}}
 volume=faces.sum do |face|
  face.loops.sum do |loop|
   poly=loop.vertices.map{|v|v.position.to_a.map(&:to_m)}
   normal=[0.0,0.0,0.0]
   poly.each_with_index{|a,i|c=cross.call(a,poly[(i+1)%poly.size]);3.times{|j|normal[j]+=c[j]}}
   winding=dot.call(normal,face.normal.to_a)>=0 ? 1.0 : -1.0
   sign=loop==face.outer_loop ? winding : -winding
   (1...poly.size-1).sum{|i|sign*dot.call(poly[0],cross.call(poly[i],poly[i+1]))/6.0}
  end
 end
 [bounds,volume,closed]
end
def mst_column_walk(entities,type,data_key,validator,out=[],parent=Geom::Transformation.new,cache={}, &visit)
 entities.each do |entity|
  next unless entity.is_a?(Sketchup::Group)||entity.is_a?(Sketchup::ComponentInstance)
  world=parent*entity.transformation
  unless entity.get_attribute(DICT,'element_type')==type
   mst_column_walk(mst_container_entities(entity),type,data_key,validator,out,world,cache,&visit)
   next
  end
  label=type=='bored_pile' ? 'Fore kazık' : 'Jet grout'
  raw=JSON.parse(entity.get_attribute(DICT,data_key,'{}'))
  raise "#{label} tip verisi eksik; kendi ekranından yeniden tanımlayın." unless raw.is_a?(Hash)&&!raw.empty?
  data=send(validator,raw)
  # Transformation#xaxis/yaxis/zaxis are unit directions in SketchUp 2020.
  # Transform unit basis points so the measured vectors retain actual scale.
  origin=Geom::Point3d.new(0,0,0).transform(world)
  axes=[[1,0,0],[0,1,0],[0,0,1]].map{|p|Geom::Point3d.new(p).transform(world)-origin}
  valid=axes.all?{|v|(v.length-1).abs<1e-7} && axes[0].z.abs<1e-7 && axes[1].z.abs<1e-7 &&
   (axes[2].z-1).abs<1e-7 && axes[0].dot(axes[1]).abs<1e-7
  raise "#{label} ölçeklenmiş veya eğilmiş. Çap ve kotları kendi ekranından güncelleyin." unless valid
  raise "#{label} model kotu kayıtlı üst kottan farklı. Kotlarını kendi ekranından güncelleyin." if (world.origin.z.to_m-data['top']).abs>0.0001
  enabled=type!='jet_grout'||data['enabled']
  if enabled
   definition=entity.definition;diameter=data['diameter']/1000.0;length=data['top']-data['bottom']
   key=[definition,diameter,length]
   unless cache[key]
    # SketchUp 2020 may retain expanded definition bounds/volume after abort.
    # Read current vertices and oriented face loops instead of those caches.
    actual,mesh_volume,closed=mst_column_geometry_metrics(entity)
    raise "#{label} kapalı katı değil; geometriyi kendi ekranından yeniden oluşturun." unless closed
    expected=[-diameter/2,diameter/2,-diameter/2,diameter/2,-length,0.0]
    raise "#{label} geometrisi kayıtlı çap veya boydan farklı; metraj durduruldu." unless actual.zip(expected).all?{|a,b|(a-b).abs<=0.0001}
    nominal=Math::PI*diameter**2/4*length
    raise "#{label} katı hacmi veya yüz yönleri kayıtlı kesitle uyuşmuyor; metraj durduruldu." if (mesh_volume/nominal-1).abs>0.002
    cache[key]=true
   end
  elsif entity.definition.entities.grep(Sketchup::Face).any?
   raise "#{label} Var/Yok kaydı ile geometri farklı; kendi ekranından güncelleyin."
  end
  visit.call(data,world) if visit
  out<<entity
 end
 out
end
end
end
