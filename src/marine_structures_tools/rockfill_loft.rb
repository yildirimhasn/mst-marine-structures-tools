# frozen_string_literal: true
module MAG
module MarineStructuresTools
module RockfillGeometry
 def polygon_area(p)
  o=p.first
  edges(p).sum{|a,b|(a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])}/2.0
 end
 def clean_polygon(p)
  p=p.map{|q|q.map{|v|v.round(7)}}.each_with_object([]){|q,a|a<<q if a.empty? || a.last!=q}
  p.pop if p.size>1 && p.last==p.first
  loop do
   i=p.each_index.find{|j|a=p[j-1];b=p[(j+1)%p.size];cross(a,p[j],b).abs<=1e-6*Math.hypot(b[0]-a[0],b[1]-a[1])}
   break unless i && p.size>3
   p.delete_at(i)
  end
  p
 end
 # Cancel shared strip boundaries after splitting at every collinear vertex.
 # This recovers actual material outlines, not a bounding-box solid.
 def cell_boundaries(cells)
  polygons=cells.map{|c|clean_polygon(c['points'])}.select{|p|p.size>=3 && polygon_area(p).abs>1e-9}
  polygons.each{|p|p.reverse! if polygon_area(p)<0}
  points=polygons.flatten(1).uniq;segments={}
  polygons.each do |poly|
   edges(poly).each do |a,b|
    dx=b[0]-a[0];dy=b[1]-a[1];den=dx*dx+dy*dy;next if den<1e-16
    cuts=points.select{|p|cross(a,b,p).abs<1e-6*Math.sqrt(den) && (p[0]-a[0])*(p[0]-b[0])+(p[1]-a[1])*(p[1]-b[1])<=1e-8}
    cuts.sort_by!{|p|((p[0]-a[0])*dx+(p[1]-a[1])*dy)/den}
    cuts.each_cons(2) do |u,v|
     next if u==v
     if segments.delete([v,u]);next;end
     raise 'Malzeme sınırları üst üste.' if segments.key?([u,v])
     segments[[u,v]]=true
    end
   end
  end
  links={};segments.keys.each{|a,b|raise 'Kesit sınırında dallanma var.' if links.key?(a);links[a]=b}
  loops=[]
  until links.empty?
   start=links.keys.min;at=start;poly=[]
   loop do
    poly<<at;at=links.delete(at);raise 'Kesit sınırı açık.' unless at
    break if at==start
    raise 'Kesit sınırı döngüsü hatalı.' if poly.include?(at)
   end
   poly=clean_polygon(poly)
   loops<<poly.rotate(poly.each_index.min_by{|i|poly[i]})
  end
  loops.sort_by{|p|[p.sum{|q|q[0]}/p.size,p.sum{|q|q[1]}/p.size]}
 end
 def cap_triangles(poly)
  ids=(0...poly.size).to_a;out=[]
  while ids.size>3
   index=ids.each_index.find do |i|
    a,b,c=ids[i-1],ids[i],ids[(i+1)%ids.size]
    cross(poly[a],poly[b],poly[c])>1e-10 && ids.none? do |j|
     next false if [a,b,c].include?(j)
     cross(poly[a],poly[b],poly[j])>=-1e-10 && cross(poly[b],poly[c],poly[j])>=-1e-10 && cross(poly[c],poly[a],poly[j])>=-1e-10
    end
   end
   raise 'Kesit yüzeyi üçgenlenemiyor; kendisiyle kesişen sınırı kontrol edin.' unless index
   out<<[ids[index-1],ids[index],ids[(index+1)%ids.size]];ids.delete_at(index)
  end
  out<<ids;out
 end
 def world_section_point(p,fr)
  [fr['origin'][0]+p[0]*fr['normal'][0],fr['origin'][1]+p[0]*fr['normal'][1],p[1]]
 end
 def match_perimeters(pa,pb)
  # Preserve every original corner; introduce only points on existing edges.
  paths=[pa,pb].map do |poly|
   lengths=edges(poly).map{|a,b|Math.hypot(b[0]-a[0],b[1]-a[1])};total=lengths.sum
   raise 'Kesit çevresi sıfır.' unless total>1e-8
   ss=[0.0];lengths.each{|l|ss<<ss[-1]+l/total};[poly,ss]
  end
  knots=paths.flat_map{|p,ss|ss[0...-1]}.sort.uniq{|v|v.round(10)}
  raise 'Geçişte 512 köşe sınırı aşıldı; kesiti sadeleştirin.' if knots.size>512
  paths.map do |poly,ss|
   knots.map do |v|
    i=(0...poly.size).find{|j|v<ss[j+1]-1e-12}||poly.size-1
    f=(v-ss[i])/(ss[i+1]-ss[i]);a=poly[i];b=poly[(i+1)%poly.size]
    2.times.map{|j|a[j]+f*(b[j]-a[j])}
   end
  end
 end
 def loft_pair(pa,pb,fa,fb,radial=false)
  resampled=pa.size!=pb.size
  pa,pb=match_perimeters(pa,pb) if resampled
  n=pa.size
  # Match cyclic ordering by relative, centred coordinates; never reverse winding.
  ca=2.times.map{|i|pa.sum{|p|p[i]}/n};cb=2.times.map{|i|pb.sum{|p|p[i]}/n}
  shift=(0...n).min_by{|k|n.times.sum{|i|2.times.sum{|j|((pa[i][j]-ca[j])-(pb[(i+k)%n][j]-cb[j]))**2}}}
  pb=pb.rotate(shift)
  [0.25,0.5,0.75].each do |f|
   p=n.times.map{|i|2.times.map{|j|pa[i][j]*(1-f)+pb[i][j]*f}}
   raise 'Loft geçişi katlanıyor.' if polygon_area(p)<=1e-9
   edges(p).each_with_index{|(a,b),i|edges(p).each_with_index{|(c,d),j|raise 'Loft sınırları kesişiyor.' if j>i+1 && line_cross(a,b,c,d)}}
  end
  a=pa.map{|p|world_section_point(p,fa)};b=pb.map{|p|world_section_point(p,fb)}
  direction=2.times.map{|j|fb['origin'][j]-fa['origin'][j]}
  raise 'Kurpta iç taraf katlanıyor; aksı veya kesit aralığını düzenleyin.' unless radial || n.times.all?{|i|2.times.sum{|j|(b[i][j]-a[i][j])*direction[j]}>1e-8}
  tris=cap_triangles(pa).map{|ids|ids.reverse.map{|i|a[i]}}+cap_triangles(pb).map{|ids|ids.map{|i|b[i]}}
  n.times{|i|j=(i+1)%n;tris<<[a[i],a[j],b[j]];tris<<[a[i],b[j],b[i]]}
  tris.reject! do |u,v,w|
   x=3.times.map{|j|v[j]-u[j]};y=3.times.map{|j|w[j]-u[j]}
   ((x[1]*y[2]-x[2]*y[1])**2+(x[2]*y[0]-x[0]*y[2])**2+(x[0]*y[1]-x[1]*y[0])**2)<1e-18
  end
  [tris,closed_mesh_volume(tris),resampled]
 end
 def convex_hull(points)
  pts=points.map{|p|p[0,2]}.uniq.sort;return pts if pts.size<3
  halves=[pts,pts.reverse].map do |list|
   list.each_with_object([]){|p,h|h.pop while h.size>=2 && cross(h[-2],h[-1],p)<=1e-9;h<<p}[0...-1]
  end
  halves.flatten(1)
 end
 def overlap_area(a,b)
  p=a
  edges(b).each do |u,v|
   q=[];break if p.empty?
   edges(p).each do |x,y|
    dx=cross(u,v,x);dy=cross(u,v,y);ix=dx>=-1e-9;iy=dy>=-1e-9
    q<<x if ix
    if ix!=iy
     f=dx/(dx-dy);q<<2.times.map{|i|x[i]+f*(y[i]-x[i])}
    end
   end
   p=q
  end
  p.size>=3 ? polygon_area(p).abs : 0.0
 end
 def loft_body(input,result)
  pieces=[];totals={};footprints=[]
  result['rows'].each do |row|
   a,b=[row['start'],row['end']].map{|sta|result['sections'].find{|s|s['station']==sta && s['type']==row['type']}}
   grouped=[a,b].map{|s|s.fetch('cells').group_by{|c|c['code']}.transform_values{|cells|material_components(cells)}}
   raise 'Malzeme bu aralıkta başlayıp bitiyor; geçişe ara kesit ekleyin.' unless grouped[0].keys.sort==grouped[1].keys.sort
   world=[]
   grouped[0].each do |code,loops|
    other=grouped[1][code];raise 'Kesitte ayrı bölge sayısı değişiyor; geçişi ayrı hesaplayın.' unless loops.size==other.size
    loops.each_with_index do |pa,i|
     tris,volume,resampled,tapered=loft_component(pa,other[i],a['frame'],b['frame'],false,input['void_transition']=='point')
     pieces<<{'code'=>code,'start'=>row['start'],'end'=>row['end'],'triangles'=>tris,'volume'=>volume,'resampled'=>resampled,'voids'=>[pa['holes'].size,(tapered||0)].max,'tapered_voids'=>tapered||0}
     world.concat(tris.flatten(1));totals[code]=(totals[code]||0)+volume
    end
   end
   hull=convex_hull(world)
   footprints.each{|old|raise 'Loft bölgeleri planda üst üste geliyor; aksı bağımsız bölgelere ayırın.' if overlap_area(old,hull)>1e-5}
   footprints<<hull
   raise 'Katı üretimi en fazla 5000 parça destekler; kesit aralığını büyütün.' if pieces.size>5000
  rescue=>e
   raise "#{format('%.3f',row['start'])}–#{format('%.3f',row['end'])} m: #{e.message}"
  end
  {'pieces'=>pieces,'totals'=>totals,'scope'=>'Gövde; baş katısı dahil değil','reference'=>result['body_totals']||result['totals']}
 end
 def loft_all(input,result)
  output=loft_body(input,result)
  if result['head']
   axis=input['axis'];sta=chain(axis);fr=frame(axis,sta,sta.last)
   spec=input['types'].fetch(input['reaches'].max_by{|r|r['from']}['type'])
   sweep=result['head'].fetch('angle',180).to_f;radians=sweep*Math::PI/180;n=(sweep/result['head']['step']).round;previous=nil
   (0..n).each do |i|
    weight=i.to_f/n;angle=-radians/2+radians*weight;t=fr['tangent']
    normal=[t[0]*Math.cos(angle)-t[1]*Math.sin(angle),t[0]*Math.sin(angle)+t[1]*Math.cos(angle)]
    radial={'origin'=>fr['origin'],'normal'=>normal,'tangent'=>[-normal[1],normal[0]]}
    bed=seabed_profile(input['triangles'],radial);bed=excavation_profile(input,radial,bed)[0]
    slope=number(spec['slope_left'])*(1-weight)+number(spec['slope_right'])*weight
    parts=parametric(spec.merge('slope_left'=>slope,'slope_right'=>slope),bed)
    grouped=section(parts,bed,true,[0,nil])['cells'].group_by{|c|c['code']}.transform_values{|v|material_components(v)}
    if previous
     old,old_frame=previous
     raise 'Başta malzeme başlayıp bitiyor; başı ayrı bölgelere ayırın.' unless old.keys.sort==grouped.keys.sort
     old.each do |code,loops|
      raise 'Başta kesit topolojisi değişiyor; daha sık açı aralığı deneyin.' unless loops.size==grouped[code].size
      loops.each_with_index do |pa,j|
       tris,volume,resampled,tapered=loft_component(pa,grouped[code][j],old_frame,radial,true)
       output['pieces']<<{'code'=>code,'start'=>(i-1)*sweep/n,'end'=>i*sweep/n,'region'=>'head','triangles'=>tris,'volume'=>volume,'resampled'=>resampled,'voids'=>[pa['holes'].size,(tapered||0)].max,'tapered_voids'=>tapered||0}
       output['totals'][code]=(output['totals'][code]||0)+volume
      end
     end
    end
    previous=[grouped,radial]
   rescue=>e
    raise "Baş #{format('%.3f',i*sweep/n)}°: #{e.message}"
   end
  end
  output['scope']=result['head'] ? 'Gövde + baş' : 'Gövde'
  output['reference']=result['totals']
  output['tapered_voids']=output['pieces'].sum{|p|p['tapered_voids']||0}
  output['void_pieces']=output['pieces'].count{|p|p['voids'].to_i>0}
  output['resampled_pairs']=output['pieces'].count{|p|p['resampled']}
  cut=excavation_meshes(input,result);output['pieces'].concat(cut['pieces'])
  output['excavation_solid_m3']=cut['volume'];output['excavation_reference_m3']=result['excavation_m3']
  output
 end
end
end
end
