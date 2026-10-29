# frozen_string_literal: true
module MAG
module MarineStructuresTools
module RockfillGeometry
 def clip_halfplane(poly,&distance)
  out=[];return out if poly.empty?
  edges(poly).each do |a,b|
   da=distance.call(a);db=distance.call(b);ia=da>=0;ib=db>=0
   out<<a if ia
   if ia!=ib
    f=da/(da-db);out<<2.times.map{|i|a[i]+f*(b[i]-a[i])}
   end
  end
  out.uniq{|p|p.map{|v|v.round(8)}}
 end
 def clip_convex(subject,boundary)
  p=subject
  edges(boundary).each{|a,b|p=clip_halfplane(p){|q|cross(a,b,q)};break if p.size<3}
  p
 end
 def xy_box(poly)
  [poly.map{|p|p[0]}.min,poly.map{|p|p[1]}.min,poly.map{|p|p[0]}.max,poly.map{|p|p[1]}.max]
 end
 def boxes_overlap(a,b)
  a[0]<b[2]+EPS && b[0]<a[2]+EPS && a[1]<b[3]+EPS && b[1]<a[3]+EPS
 end
 def tin_elevation(tri,p)
  a,b,c=tri;den=cross(a,b,c)
  raise 'Kazı TIN yüzeyinde düşey/dejenere üçgen var.' if den.abs<1e-10
  u=cross(p,b,c)/den;v=cross(a,p,c)/den
  u*a[2]+v*b[2]+(1-u-v)*c[2]
 end
 def covered_triangles(triangles,domain)
  box=xy_box(domain);pieces=[]
  triangles.each do |item|
   next unless boxes_overlap(item['box'],box)
   p=clip_convex(item['xy'],domain);next if p.size<3 || polygon_area(p).abs<1e-10
   pieces<<{'poly'=>p,'box'=>xy_box(p),'tri'=>item['tri']}
  end
  raise 'Kazı katısı: tek bölgede 5000 yüzey parçası sınırı; modeli bölgelere ayırın.' if pieces.size>5000
  sum=pieces.sum{|x|polygon_area(x['poly']).abs};area=polygon_area(domain).abs
  raise 'Kazı katısı: yüzey hesap koridorunu tam kapsamıyor veya örtüşüyor.' if (sum-area).abs>[1e-6,area*1e-8].max
  pieces.each_with_index do |p,i|
   pieces[i+1..-1].each do |q|
    next unless boxes_overlap(p['box'],q['box'])
    raise 'Kazı TIN yüzeyinde üst üste üçgenler var.' if overlap_area(p['poly'],q['poly'])>1e-7
   end
  end
  pieces
 end
 def cut_cell_mesh(poly,upper,lower)
  poly=clean_polygon(poly);poly.reverse! if polygon_area(poly)<0
  top=poly.map{|p|p+[tin_elevation(upper,p)]};bottom=poly.map{|p|p+[tin_elevation(lower,p)]}
  tris=cap_triangles(poly).flat_map{|ids|[ids.map{|i|top[i]},ids.reverse.map{|i|bottom[i]}]}
  poly.size.times do |i|
   j=(i+1)%poly.size;tris<<[bottom[i],bottom[j],top[j]];tris<<[bottom[i],top[j],top[i]]
  end
  tris.reject! do |a,b,c|
   u=3.times.map{|j|b[j]-a[j]};v=3.times.map{|j|c[j]-a[j]}
   ((u[1]*v[2]-u[2]*v[1])**2+(u[2]*v[0]-u[0]*v[2])**2+(u[0]*v[1]-u[1]*v[0])**2)<1e-18
  end
  [tris,closed_mesh_volume(tris)]
 end
 def excavation_meshes(input,result)
  ex=input['excavation'];return {'pieces'=>[],'volume'=>0.0} unless ex
  left=number(ex['left']);right=number(ex['right']);axis=input['axis'];stations=chain(axis)
  domains=[]
  result['rows'].each do |row|
   a,b=[row['start'],row['end']].map{|s|frame(axis,stations,s)}
   p=[[a,-left],[b,-left],[b,right],[a,right]].map{|fr,x|world_section_point([x,0],fr)[0,2]}
   p.reverse! if polygon_area(p)<0
   raise 'Kazı koridoru kurpta katlanıyor; aksı bölgelere ayırın.' unless p.each_index.all?{|i|cross(p[i-1],p[i],p[(i+1)%p.size])>1e-9}
   domains<<{'poly'=>p,'start'=>row['start'],'end'=>row['end'],'region'=>'body'}
  end
  if result['head']
   fr=frame(axis,stations,stations.last);sweep=result['head'].fetch('angle',180).to_f;radians=sweep*Math::PI/180;n=(sweep/result['head']['step']).round
   (0...n).each do |i|
    pp=[i,i+1].map do |k|
     angle=-radians/2+radians*k/n;t=fr['tangent']
     [fr['origin'][0]+right*(t[0]*Math.cos(angle)-t[1]*Math.sin(angle)),fr['origin'][1]+right*(t[0]*Math.sin(angle)+t[1]*Math.cos(angle))]
    end
    domains<<{'poly'=>[fr['origin'],*pp],'start'=>i*sweep/n,'end'=>(i+1)*sweep/n,'region'=>'head'}
   end
  end
  domains.each{|d|d['box']=xy_box(d['poly'])}
  domains.each_with_index do |p,i|
   domains[i+1..-1].each do |q|
    next unless boxes_overlap(p['box'],q['box'])
    raise 'Kazı hesap bölgeleri planda çakışıyor; aks/baş birleşimini düzeltin.' if overlap_area(p['poly'],q['poly'])>1e-6
   end
  end
  existing,design=[input['triangles'],ex['triangles']].map do |ts|
   ts.map{|t|xy=t.map{|p|p[0,2]};xy.reverse! if polygon_area(xy)<0;{'tri'=>t,'xy'=>xy,'box'=>xy_box(xy)}}
  end
  pieces=[];volume=0.0
  domains.each do |domain|
   upper=covered_triangles(existing,domain['poly']);lower=covered_triangles(design,domain['poly'])
   upper.each do |a|
    lower.each do |b|
     next unless boxes_overlap(a['box'],b['box'])
     poly=clip_convex(a['poly'],b['poly']);next if poly.size<3 || polygon_area(poly).abs<1e-10
     poly=clip_halfplane(poly){|p|tin_elevation(a['tri'],p)-tin_elevation(b['tri'],p)}
     next if poly.size<3 || polygon_area(poly).abs<1e-10
     # Integrate the linear height on the convex overlay polygon exactly.
     h=poly.map{|p|[tin_elevation(a['tri'],p)-tin_elevation(b['tri'],p),0].max}
     exact=(1...poly.size-1).sum{|j|cross(poly[0],poly[j],poly[j+1]).abs*(h[0]+h[j]+h[j+1])/6.0}
     next if exact<1e-9
     tris,v=cut_cell_mesh(poly,a['tri'],b['tri'])
     raise 'Kazı katısı hacim tutarlılık kontrolü geçmedi.' if (v-exact).abs>[1e-6,exact*1e-7].max
     pieces<<{'code'=>'__EXCAVATION__','start'=>domain['start'],'end'=>domain['end'],'region'=>domain['region'],'triangles'=>tris,'volume'=>v}
     volume+=v;raise 'Kazı katıları 10000 parça sınırını aştı; bölgeyi daraltın.' if pieces.size>10000
    end
   end
  rescue=>e
   raise "Kazı #{domain['region']} #{format('%.3f',domain['start'])}–#{format('%.3f',domain['end'])}: #{e.message}"
  end
  {'pieces'=>pieces,'volume'=>volume}
 end
end
end
end
