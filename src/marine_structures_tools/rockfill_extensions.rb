# frozen_string_literal: true
module MAG
module MarineStructuresTools
module RockfillGeometry
 # Both surfaces are sampled on the same section. Outside the specified cut
 # corridor the existing seabed remains the founding surface.
 def excavation_profile(input,fr,existing)
  ex=input['excavation'];return [existing,0.0,0.0] unless ex
  left=number(ex.fetch('left'));right=number(ex.fetch('right'))
  raise 'Kazı koridoru genişlikleri pozitif olmalı.' unless left>0 && right>0
  design=seabed_profile(ex.fetch('triangles'),fr)
  knots=(existing+design).flatten(1).map(&:first)+[-left,right]
  existing.each{|a,b|design.each{|c,d|p=line_cross(a,b,c,d);knots<<p[0] if p}}
  knots=knots.sort.uniq{|x|x.round(8)};profile=[];area=0.0;moment=0.0
  knots.each_cons(2) do |a,b|
   next if b-a<EPS
   mid=(a+b)/2.0;inside=mid>-left && mid<right
   # Do not invent coverage outside the existing TIN.
   next unless existing.any?{|p,q|mid>=[p[0],q[0]].min-EPS && mid<=[p[0],q[0]].max+EPS}
   e1=bed_at(existing,a);e2=bed_at(existing,b)
   if inside
    d1=bed_at(design,a);d2=bed_at(design,b)
    h1=[e1-d1,0].max;h2=[e2-d2,0].max
    area+=(h1+h2)*(b-a)/2.0
    if b>0
     lo=[a,0].max;hl=h1+(h2-h1)*(lo-a)/(b-a)
     moment+=(b-lo)*((2*lo+b)*hl+(lo+2*b)*h2)/6.0
    end
    profile<<[[a,[e1,d1].min],[b,[e2,d2].min]]
   else;profile<<[[a,e1],[b,e2]];end
  end
  bed_at(existing,-left);bed_at(existing,right);bed_at(design,-left);bed_at(design,right)
  [profile,area,moment]
 end

 def head_quantities(input,result)
  option=input['head'];return nil unless option && option['enabled']
  if input['excavation']
   ex=input['excavation']
   raise 'Başta kazı koridoru iki tarafta eşit olmalı; başta aynı genişlik yarıçap olarak kullanılır.' if (number(ex['left'])-number(ex['right'])).abs>1e-8
  end
  axis=input['axis'];sta=chain(axis);fr=frame(axis,sta,sta.last)
  spec=input['types'].fetch(input['reaches'].max_by{|r|r['from']}['type'])
  raise 'Baş hesabı parametrik son tip gerektirir.' unless spec['mode']=='parametric'
  # Body must stay behind the final section plane. This conservative guard
  # admits curved approaches without counting cap/body overlap twice.
  result['sections'].each do |sec|
   ss=input['types'].fetch(sec['type']);parts=sec['parts'] || (ss['mode']=='parametric' ? parametric(ss,sec['bed']) : ss['parts'])
   cells=section(parts,sec['bed'],true)['cells'];pts=cells.flat_map{|c|c['points']}
   if input['excavation'];pts+=[[-number(input['excavation']['left']),0],[number(input['excavation']['right']),0]];end
   if pts.any?{|p|w=world_section_point(p,sec['frame']);2.times.sum{|j|(w[j]-fr['origin'][j])*fr['tangent'][j]}>1e-6}
    raise 'Baş ile gövde kapsamı çakışıyor; baş merkezini veya son aks doğrultusunu düzeltin.'
   end
  end
  degrees=number(option.fetch('step',5));raise 'Baş açı aralığı 0,5–15 derece olmalı.' unless degrees>=0.5 && degrees<=15
  sweep=number(option.fetch('angle',180));raise 'Baş açısı 0 dereceden büyük ve en fazla 180 derece olmalı. Daha geniş / geri dönen baş için Özel Katı Geometrisi kullanın.' unless sweep>0 && sweep<=180
  radians=sweep*Math::PI/180;n=(sweep/degrees).ceil
  run=lambda do |count|
   totals={};delta=radians/count;cut=0.0
   count.times do |i|
    angle=-radians/2+(i+0.5)*delta;t=fr['tangent'];normal=[t[0]*Math.cos(angle)-t[1]*Math.sin(angle),t[0]*Math.sin(angle)+t[1]*Math.cos(angle)]
    radial={'origin'=>fr['origin'],'normal'=>normal,'tangent'=>[-normal[1],normal[0]]}
    profile=seabed_profile(input['triangles'],radial)
    profile,cut_area,cut_moment=excavation_profile(input,radial,profile)
    cut+=cut_moment*delta
    weight=(angle+radians/2)/radians
    slope=number(spec['slope_left'])*(1-weight)+number(spec['slope_right'])*weight
    radial_spec=spec.merge('slope_left'=>slope,'slope_right'=>slope)
    parts=parametric(radial_spec,profile)
    # Clip the radial profile to r>=0. The back half is not part of the cap.
    cells=section(parts,profile,true,[0,nil])['cells']
    cells.each do |cell|
     a,b,c,d=cell['points'];r1=a[0];r2=b[0];h1=d[1]-a[1];h2=c[1]-b[1]
     moment=(r2-r1)*((2*r1+r2)*h1+(r1+2*r2)*h2)/6.0
     k=cell['code'];totals[k]=(totals[k]||0)+moment*delta
    end
   end
   [totals,cut]
  end
  coarse,coarse_cut=run.call(n);fine,fine_cut=run.call(n*2)
  error=(coarse.keys+fine.keys).uniq.sum{|k|((fine[k]||0)-(coarse[k]||0)).abs}
  {'totals'=>fine,'total'=>fine.values.sum,'excavation_m3'=>fine_cut,'cut_refinement_difference_m3'=>(fine_cut-coarse_cut).abs,'angle'=>sweep,'step'=>sweep/(n*2),'refinement_difference_m3'=>error,'center'=>fr['origin'],'method'=>'Radyal integral; şevler arasında açıya göre doğrusal geçiş; iki açısal çözünürlük karşılaştırması'}
 end

 # Oriented triangle volume with topology checks, independent of Ruby API
 # Group#volume. World coordinates include instance scaling and reflection.
 def closed_mesh_volume(triangles)
  raise 'Katı yüzeyleri boş.' if triangles.empty?
  origin=triangles.first.first;edges={};sum=0.0
  triangles.each do |tri|
   raise 'Katı ağı üçgen olmalı.' unless tri.size==3
   keys=tri.map{|p|p.map{|v|number(v).round(7)}}
   raise 'Katıda sıfır alanlı üçgen var.' if keys.uniq.size<3
   3.times do |i|
    a=keys[i];b=keys[(i+1)%3];key=[a,b].sort;(edges[key]||=[])<<(a==key.first ? 1 : -1)
   end
   a,b,c=tri.map{|p|3.times.map{|i|p[i]-origin[i]}}
   sum+=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6.0
  end
  raise 'Katı açık, yönleri tutarsız veya kenarlar çakışıyor. Solid Inspector ile düzeltin.' unless edges.values.all?{|v|v.size==2 && v.sum==0}
  raise 'Katı hacmi sıfır veya geçersiz.' unless sum.finite? && sum.abs>1e-9
  sum.abs
 end
end
end
end
