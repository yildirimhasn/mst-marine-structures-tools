# frozen_string_literal: true
module MAG
module MarineStructuresTools
module RockfillGeometry
 # A point in the visibility kernel sees every boundary edge from inside.
 # Preserve the previous mean for convex polygons; clip half-planes for concave ones.
 def taper_point(hole)
  raise 'Kapanış boşluğunun sınır yönü geçersiz.' unless polygon_area(hole)< -1e-9
  point=2.times.map{|j|hole.sum{|p|p[j]}/hole.size.to_f}
  return point if edges(hole).all?{|a,b|cross(a,b,point)< -1e-9}
  xs=hole.map(&:first);ys=hole.map(&:last)
  kernel=[[xs.min,ys.min],[xs.max,ys.min],[xs.max,ys.max],[xs.min,ys.max]]
  edges(hole).each do |a,b|
   clipped=[]
   edges(kernel).each do |u,v|
    du=cross(a,b,u);dv=cross(a,b,v);iu=du<=0;iv=dv<=0
    clipped<<u if iu
    if iu!=iv
     t=du/(du-dv).to_f;clipped<<2.times.map{|j|u[j]+t*(v[j]-u[j])}
    end
   end
   kernel=clipped.uniq
   break if kernel.size<3
  end
  raise 'İçbükey boşluk için güvenli tek kapanış noktası bulunamadı; ayrı geçiş tanımlayın.' if kernel.size<3 || polygon_area(kernel).abs<1e-9
  point=2.times.map{|j|kernel.sum{|p|p[j]}/kernel.size.to_f}
  raise 'İçbükey boşluğun kapanış noktası sınıra çok yakın; ayrı geçiş tanımlayın.' unless edges(hole).all?{|a,b|cross(a,b,point)< -1e-9}
  point
 end
 def taper_components(ca,cb,enabled)
  return [ca,cb,0] if ca['holes'].size==cb['holes'].size
  raise 'İç boşluk sayısı değişiyor; noktasal kapanışı açıkça seçin veya ayrı bölge tanımlayın.' unless enabled
  small,large=ca['holes'].size<cb['holes'].size ? [ca,cb] : [cb,ca]
  used=[];pairs={}
  small['holes'].each_with_index do |hole,i|
   # Match persistent holes by equal boundaries, independent of vertex start/order.
   candidates=large['holes'].each_index.select{|j|!used.include?(j) && hole.size==large['holes'][j].size && hole.all?{|p|large['holes'][j].any?{|q|2.times.all?{|k|(p[k]-q[k]).abs<1e-7}}}}
   raise 'Kısmi boşluk geçişinde devam eden sınır eşleşmesi belirsiz. Ara kesit veya Özel Katı Geometrisi tanımlayın.' unless candidates.size==1
   used<<candidates.first;pairs[candidates.first]=hole
  end
  patched=large['holes'].each_with_index.map do |hole,j|
   next pairs[j] if pairs.key?(j)
   point=taper_point(hole)
   raise 'Kapanış noktası karşı kesitin net malzemesi içinde değil.' unless inside_polygon(point,small['outer']) && small['holes'].none?{|h|inside_polygon(point,h)}
   hole.map{point.dup}
  end
  changed=large['holes'].size-small['holes'].size
  replacement=small.merge('holes'=>patched)
  ca.equal?(small) ? [replacement,cb,changed] : [ca,replacement,changed]
 end
 def net_components(spec)
  raise 'Doğrusal tip geçişi yalnız çizilmiş kapalı kesitlerde desteklenir.' unless spec['mode']=='faces'
  points=spec.fetch('parts').flat_map{|p|p['loops'].flatten(1)}
  lo,hi=points.map(&:first).minmax;bottom=points.map(&:last).min-1
  section(spec['parts'],[[[lo-1,bottom],[hi+1,bottom]]],true)['cells'].group_by{|c|c['code']}.transform_values{|c|material_components(c)}
 end
 def blended_parametric(first,last,f,bed)
  a=first['layers'];b=last['layers']
  raise 'Parametrik geçişte tabaka kodları ve dıştan içe sırası aynı olmalı.' unless a.is_a?(Array) && b.is_a?(Array) && !a.empty? && a.map{|l|l['code']}==b.map{|l|l['code']}
  blended=first.dup
  %w[crest width slope_left slope_right].each do |key|
   x=number(first[key]);y=number(last[key])
   raise 'Geçiş uçlarında genişlik ve şevler pozitif olmalı.' if key!='crest' && (x<=0 || y<=0)
   blended[key]=x*(1-f)+y*f
  end
  blended['layers']=a.each_with_index.map do |layer,i|
   item=layer.dup
   if i<a.size-1
    x=number(layer['thickness']);y=number(b[i]['thickness'])
    raise 'Geçiş uçlarında tabaka kalınlığı pozitif olmalı.' unless x>0 && y>0
    item['thickness']=x*(1-f)+y*f
   end
   item
  end
  parametric(blended,bed)
 end
 def blended_parts(input,reach,station,bed)
  spec=input['types'].fetch(reach['type'])
  next_reach=input['reaches'].select{|r|r['from']>reach['from']}.min_by{|r|r['from']}
  return spec['mode']=='parametric' ? parametric(spec,bed) : spec.fetch('parts') unless input['type_transition']=='linear' && next_reach
  f=[[((station-reach['from'])/(next_reach['from']-reach['from']).to_f),0].max,1].min
  target=input['types'].fetch(next_reach['type'])
  raise 'Çizilmiş ve parametrik tipler arasında doğrusal geçiş desteklenmiyor.' unless spec['mode']==target['mode']
  return blended_parametric(spec,target,f,bed) if spec['mode']=='parametric'
  first=net_components(spec);last=net_components(target)
  raise 'Tip geçişinde malzeme kodları farklı; eşleşen malzemeleri tanımlayın.' unless first.keys.sort==last.keys.sort
  out=[]
  first.each do |code,components|
   raise 'Tip geçişinde malzeme bölünüyor/birleşiyor; ayrı bölge gerekli.' unless components.size==last[code].size
   components.each_with_index do |ca,i|
    ca,cb,count=taper_components(ca,last[code][i],input['void_transition']=='point')
    loops=([ca['outer']]+ca['holes']).zip([cb['outer']]+cb['holes']).map do |a,b|
     a,b=match_perimeters(a,b) if a.size!=b.size
     a.each_index.map{|k|2.times.map{|j|a[k][j]*(1-f)+b[k][j]*f}}
    end
    loops.each_with_index do |p,index|
     next if index>0 && p.uniq.size==1
     raise 'Tip geçişinde sınır yönü katlanıyor.' unless index==0 ? polygon_area(p)>1e-9 : polygon_area(p)< -1e-9
     edges(p).each_with_index{|(a,b),i|edges(p).each_with_index{|(c,d),j|raise 'Tip geçişinde sınır kendiyle kesişiyor.' if j>i+1 && !(i==0 && j==p.size-1) && segments_touch(a,b,c,d)}}
    end
    loops[1..-1].each{|p|raise 'Tip geçişinde boşluk dış sınırdan çıkıyor.' unless p.all?{|v|inside_polygon(v,loops.first)}}
    loops.each_with_index{|p,i|loops[i+1..-1].each{|q|raise 'Tip geçişi sınırları birbirine değiyor.' if edges(p).any?{|a,b|edges(q).any?{|c,d|segments_touch(a,b,c,d)}}}}
    out<<{'code'=>code,'loops'=>loops}
   end
  end
  out
 end
end
end
end
