# frozen_string_literal: true
require_relative 'rockfill_tin'
module MAG
module MarineStructuresTools
module RockfillGeometry
 def inside_polygon(point,poly)
  x,y=point;inside=false
  edges(poly).each do |a,b|
   if (a[1]>y)!=(b[1]>y)
    at=a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]).to_f
    inside=!inside if x<at
   end
  end
  inside
 end
 def material_components(cells)
  loops=cell_boundaries(cells);outer=loops.select{|p|polygon_area(p)>0};holes=loops.select{|p|polygon_area(p)<0}
  components=outer.map{|p|{'outer'=>p,'holes'=>[]}}
  holes.each do |hole|
   candidates=components.select{|c|inside_polygon(hole.first,c['outer'])}
   raise 'Boşluk için dış malzeme sınırı bulunamadı.' if candidates.empty?
   candidates.min_by{|c|polygon_area(c['outer']).abs}['holes']<<hole
  end
  components.each{|c|c['holes'].sort_by!{|p|[p.sum{|q|q[0]}/p.size,p.sum{|q|q[1]}/p.size]}}
  components
 end
 def void_cap(loops)
  lines=loops.flat_map{|p|edges(p).map{|a,b|[a+[0.0],b+[0.0]]}}
  triangles=RockfillTIN.triangulate(lines).map{|t|t.map{|p|p[0,2]}}
  triangles.select! do |t|
   center=[t.sum{|p|p[0]}/3.0,t.sum{|p|p[1]}/3.0]
   loops.count{|p|inside_polygon(center,p)}.odd?
  end
  triangles.each{|t|t.reverse! if polygon_area(t)<0}
  area=triangles.sum{|t|polygon_area(t)};target=loops.sum{|p|polygon_area(p)}
  raise 'Boşluklu kesit kapak alanı doğrulanamadı.' if (area-target).abs>[1e-6,target.abs*1e-7].max
  triangles
 end
 def segments_touch(a,b,c,d)
  return false if [a[0],b[0]].max<[c[0],d[0]].min-1e-8 || [c[0],d[0]].max<[a[0],b[0]].min-1e-8 || [a[1],b[1]].max<[c[1],d[1]].min-1e-8 || [c[1],d[1]].max<[a[1],b[1]].min-1e-8
  cross(a,b,c)*cross(a,b,d)<=1e-12 && cross(c,d,a)*cross(c,d,b)<=1e-12
 end
 def vsub(a,b);3.times.map{|i|a[i]-b[i]};end
 def vcross(a,b);[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];end
 def vdot(a,b);3.times.sum{|i|a[i]*b[i]};end
 def segment_triangle(a,b,tri)
  e1=vsub(tri[1],tri[0]);e2=vsub(tri[2],tri[0]);d=vsub(b,a);h=vcross(d,e2);det=vdot(e1,h)
  return false if det.abs<1e-10
  s=vsub(a,tri[0]);u=vdot(s,h)/det;return false if u< -1e-8 || u>1+1e-8
  q=vcross(s,e1);v=vdot(d,q)/det;return false if v< -1e-8 || u+v>1+1e-8
  t=vdot(e2,q)/det;t>=-1e-8 && t<=1+1e-8
 end
 def triangles_touch(a,b)
  return false if 3.times.any?{|i|a.map{|p|p[i]}.max<b.map{|p|p[i]}.min-1e-8 || b.map{|p|p[i]}.max<a.map{|p|p[i]}.min-1e-8}
  return true if edges(a).any?{|u,v|segment_triangle(u,v,b)} || edges(b).any?{|u,v|segment_triangle(u,v,a)}
  normal=vcross(vsub(a[1],a[0]),vsub(a[2],a[0]));length=Math.sqrt(vdot(normal,normal))
  return false if length<1e-12 || b.any?{|p|vdot(normal,vsub(p,a[0])).abs>length*1e-7}
  drop=(0..2).max_by{|i|normal[i].abs};aa=a.map{|p|p.each_with_index.reject{|v,i|i==drop}.map(&:first)};bb=b.map{|p|p.each_with_index.reject{|v,i|i==drop}.map(&:first)}
  edges(aa).any?{|u,v|edges(bb).any?{|x,y|segments_touch(u,v,x,y)}} || inside_polygon(aa.first,bb) || inside_polygon(bb.first,aa)
 end
 def loft_component(ca,cb,fa,fb,radial=false,allow_taper=false)
  return loft_pair(ca['outer'],cb['outer'],fa,fb,radial) if ca['holes'].empty? && cb['holes'].empty?
  ca,cb,taper_count=taper_components(ca,cb,allow_taper)
  pairs=[];changed=false
  ([ca['outer']]+ca['holes']).zip([cb['outer']]+cb['holes']).each do |pa,pb|
   if pa.size!=pb.size;pa,pb=match_perimeters(pa,pb);changed=true;end
   n=pa.size;ac=2.times.map{|i|pa.sum{|p|p[i]}/n};bc=2.times.map{|i|pb.sum{|p|p[i]}/n}
   shift=(0...n).min_by{|k|n.times.sum{|i|2.times.sum{|j|((pa[i][j]-ac[j])-(pb[(i+k)%n][j]-bc[j]))**2}}}
   pairs<<[pa,pb.rotate(shift)]
  end
  (0..8).each do |step|
   f=step/8.0;loops=pairs.map{|a,b|a.each_index.map{|i|2.times.map{|j|a[i][j]*(1-f)+b[i][j]*f}}}
   loops.each_with_index do |p,index|
    next if index>0 && (step==0 || step==8) && p.uniq.size==1
    area=polygon_area(p);raise 'Boşluk geçişinde sınır yönü katlanıyor.' unless index==0 ? area>1e-9 : area< -1e-9
    edges(p).each_with_index{|(a,b),i|edges(p).each_with_index{|(c,d),j|raise 'Boşluk sınırı kendiyle kesişiyor.' if j>i+1 && !(i==0 && j==p.size-1) && segments_touch(a,b,c,d)}}
   end
   loops[1..-1].each{|p|raise 'Boşluk dış malzeme sınırından çıkıyor.' unless p.all?{|v|inside_polygon(v,loops[0])}}
   loops.each_with_index do |p,i|
    loops[i+1..-1].each do |q|
     raise 'Boşluk sınırları birbirine veya dış sınıra değiyor.' if edges(p).any?{|a,b|edges(q).any?{|c,d|segments_touch(a,b,c,d)}}
    end
   end
  end
  caps=void_cap(pairs.map(&:first).reject{|p|polygon_area(p).abs<1e-10}).map{|t|t.reverse.map{|p|world_section_point(p,fa)}}+void_cap(pairs.map(&:last).reject{|p|polygon_area(p).abs<1e-10}).map{|t|t.map{|p|world_section_point(p,fb)}}
  direction=2.times.map{|i|fb['origin'][i]-fa['origin'][i]}
  shells=pairs.map do |pa,pb|
   a=pa.map{|p|world_section_point(p,fa)};b=pb.map{|p|world_section_point(p,fb)}
   raise 'Boşluklu katı kurpta geriye katlanıyor.' unless radial || a.each_index.all?{|i|2.times.sum{|j|(b[i][j]-a[i][j])*direction[j]}>1e-8}
   a.each_index.flat_map{|i|j=(i+1)%a.size;[[a[i],a[j],b[j]],[a[i],b[j],b[i]]]}
  end
  shells.each{|shell|shell.reject!{|t|u=vsub(t[1],t[0]);v=vsub(t[2],t[0]);n=vcross(u,v);vdot(n,n)<1e-18}}
  shells.each_with_index do |shell,i|
   shells[i+1..-1].each{|other|raise 'Üç boyutlu boşluk duvarları kesişiyor.' if shell.any?{|a|other.any?{|b|triangles_touch(a,b)}}}
  end
  tris=caps+shells.flatten(1)
  [tris,closed_mesh_volume(tris),changed,taper_count]
 end
end
end
end
