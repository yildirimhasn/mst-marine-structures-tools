# frozen_string_literal: true
module MAG
module MarineStructuresTools
module RockfillTIN
 extend self
 def circle(a,b,c)
  bx=b[0]-a[0];by=b[1]-a[1];cx=c[0]-a[0];cy=c[1]-a[1];d=2*(bx*cy-by*cx)
  return nil if d.abs<1e-12
  u=((bx*bx+by*by)*cy-(cx*cx+cy*cy)*by)/d.to_f
  v=((cx*cx+cy*cy)*bx-(bx*bx+by*by)*cx)/d.to_f
  [a[0]+u,a[1]+v,u*u+v*v]
 end
 def triangulate(segments)
  vertices=[];indices={};constraints=[]
  segments.each do |line|
   ids=line.map do |p|
    key=[p[0].round(6),p[1].round(6)]
    if indices.key?(key)
     id=indices[key];raise 'Aynı XY konumunda farklı batimetri kotları var.' if (vertices[id][2]-p[2]).abs>1e-5
     id
    else
     id=vertices.size;indices[key]=id;vertices<<p;id
    end
   end
   constraints<<ids.sort unless ids[0]==ids[1]
  end
  constraints.uniq!
  raise 'TIN için en az 3, en fazla 5000 farklı XY noktası gerekli.' unless vertices.size.between?(3,5000)
  n=vertices.size;cx=vertices.sum{|p|p[0]}/n.to_f;cy=vertices.sum{|p|p[1]}/n.to_f
  points=vertices.map{|p|[p[0]-cx,p[1]-cy]};span=points.flatten.map(&:abs).max*32+1
  points += [[-span,-span],[span,-span],[0,span]]
  triangles=[[n,n+1,n+2]];circles=[circle(*triangles[0].map{|i|points[i]})]
  (0...n).to_a.shuffle(random:Random.new(4701)).each do |id|
   p=points[id];bad=[];boundary=Hash.new(0)
   circles.each_with_index{|c,i|bad<<i if c && (p[0]-c[0])**2+(p[1]-c[1])**2<=c[2]+1e-9}
   raise 'TIN üçgenleme kararsız; kot eğrilerini veya yüzeyi kontrol edin.' if bad.empty?
   bad.each{|i|t=triangles[i];3.times{|j|boundary[[t[j],t[(j+1)%3]].sort]+=1}}
   bad.reverse_each{|i|triangles.delete_at(i);circles.delete_at(i)}
   boundary.each do |edge,count|
    next unless count==1
    tri=edge+[id];c=circle(*tri.map{|i|points[i]});next unless c
    triangles<<tri;circles<<c
   end
  end
  triangles.reject!{|t|t.any?{|i|i>=n}}
  raise 'Batimetri noktaları aynı doğru üzerinde; yüzey oluşturulamadı.' if triangles.empty?
  # Recover every contour segment as a TIN edge; never cut across an input contour.
  split=[]
  constraints.each do |a,b|
   aa=points[a];bb=points[b];dx=bb[0]-aa[0];dy=bb[1]-aa[1];len2=dx*dx+dy*dy
   interior=(0...n).select{|i|i!=a&&i!=b && RockfillGeometry.cross(aa,bb,points[i]).abs<1e-7 && (points[i][0]-aa[0])*dx+(points[i][1]-aa[1])*dy>0 && (points[i][0]-aa[0])*dx+(points[i][1]-aa[1])*dy<len2}
   chain=([a,b]+interior).sort_by{|i|(points[i][0]-aa[0])*dx+(points[i][1]-aa[1])*dy};chain.each_cons(2){|x,y|split<<[x,y].sort}
  end
  locked=[]
  split.uniq.each do |target|
   seen={};limit=triangles.size*3+10
   loop do
    adjacency=Hash.new{|h,k|h[k]=[]};triangles.each_with_index{|t,i|3.times{|j|adjacency[[t[j],t[(j+1)%3]].sort]<<i}}
    break if adjacency.key?(target)
    signature=triangles.map(&:sort).sort.hash;raise 'Batimetri sınırı çözülemedi. Üçgenlenmiş mevcut taban yüzeyini seçin.' if seen[signature] || limit<=0
    seen[signature]=true;limit-=1
    candidates=adjacency.select{|edge,ts|ts.size==2 && !locked.include?(edge) && RockfillGeometry.line_cross(*target.map{|i|points[i]},*edge.map{|i|points[i]})}
    flipped=false
    candidates.each do |edge,ts|
     a,b=edge;c=(triangles[ts[0]]-edge)[0];d=(triangles[ts[1]]-edge)[0]
     next unless RockfillGeometry.line_cross(points[a],points[b],points[c],points[d])
     triangles[ts[0]]=[c,d,a];triangles[ts[1]]=[c,d,b];flipped=true;break
    end
    raise 'Kesişen veya çözülemeyen kot eğrisi. Eğrileri düzeltin ya da mevcut TIN yüzeyi seçin.' unless flipped
   end
   locked<<target
  end
  # Consistent upward normals for the terrain preview and downstream mesh use.
  triangles.map do |t|
   tri=t.map{|i|vertices[i]}
   a,b,c=tri
   cross=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
   cross<0 ? [a,c,b] : tri
  end
 end
end
end
end
