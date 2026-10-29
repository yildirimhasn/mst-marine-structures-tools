# frozen_string_literal: true
# Pure metre-based geometry; independent of SketchUp UI and project names.
module MAG
module MarineStructuresTools
module RockfillGeometry
 extend self
 EPS=1.0e-8
 def number(v)
  n=Float(v.to_s.tr(',','.'));raise 'Sonlu sayısal değer gerekli.' unless n.finite?;n
 end
 def cross(a,b,c)
  (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
 end
 def line_cross(a,b,c,d)
  v=[b[0]-a[0],b[1]-a[1]];w=[d[0]-c[0],d[1]-c[1]];den=v[0]*w[1]-v[1]*w[0]
  return nil if den.abs<EPS
  t=((c[0]-a[0])*w[1]-(c[1]-a[1])*w[0])/den.to_f
  u=((c[0]-a[0])*v[1]-(c[1]-a[1])*v[0])/den.to_f
  (t>EPS && t<1-EPS && u>EPS && u<1-EPS) ? [a[0]+t*v[0],a[1]+t*v[1]] : nil
 end
 def edges(poly);poly.each_cons(2).to_a+[[poly[-1],poly[0]]];end
 def intervals(loops,x)
  zz=loops.flat_map{|p|edges(p).map{|a,b| (a[0]<=x && x<b[0]) || (b[0]<=x && x<a[0]) ? a[1]+(x-a[0])*(b[1]-a[1])/(b[0]-a[0]).to_f : nil}.compact}.sort
  raise 'Kesit sınırı kapanmıyor.' unless zz.length.even?
  zz.each_slice(2).select{|a,b|b-a>EPS}
 end
 def union(list)
  list.sort.each_with_object([]) do |pair,out|
   a,b=pair;next unless b-a>EPS
   if !out.empty? && a<=out[-1][1]+EPS;out[-1][1]=[b,out[-1][1]].max;else;out<<[a,b];end
  end
 end
 def subtract(list,cuts)
  cuts.each do |c,d|
   list=list.flat_map{|a,b|v=[];v<<[a,[b,c].min] if c>a;v<<[[a,d].max,b] if d<b;v}.select{|a,b|b-a>EPS}
  end
  list
 end
 def chain(axis)
  raise 'En az iki aks noktası gerekli.' unless axis.is_a?(Array)&&axis.size>=2
  lengths=axis.each_cons(2).map{|a,b|Math.hypot(b[0]-a[0],b[1]-a[1])}
  raise 'Aksın planda sıfır boylu kenarı var.' unless lengths.all?{|x|x>1e-6}
  axis.each_cons(2).with_index do |(a,b),i|
   axis.each_cons(2).with_index{|(c,d),j|raise 'Aks kendiyle kesişiyor.' if j>i+1 && line_cross(a,b,c,d)}
  end
  stations=[0.0];lengths.each{|x|stations<<stations[-1]+x};stations
 end
 def frame(axis,stations,s)
  i=(0...stations.size-1).find{|j|s<=stations[j+1]+EPS} || stations.size-2
  a,b=axis[i,2];len=stations[i+1]-stations[i];t=[[((s-stations[i])/len),0].max,1].min
  direction=[(b[0]-a[0])/len,(b[1]-a[1])/len]
  if i+2<axis.size && (s-stations[i+1]).abs<1e-6
   c=axis[i+2];l=stations[i+2]-stations[i+1];other=[(c[0]-b[0])/l,(c[1]-b[1])/l]
   direction=[direction[0]+other[0],direction[1]+other[1]];d=Math.hypot(*direction)
   raise 'Aks geri dönüyor; köşeyi ayrı hesap bölgesine ayırın.' if d<0.1
   direction.map!{|x|x/d}
  end
  {'origin'=>[a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])],'normal'=>[-direction[1],direction[0]],'tangent'=>direction}
 end
 def seabed_profile(triangles,fr)
  o=fr['origin'];normal=fr['normal'];t=fr['tangent'];segments=[]
  triangles.each do |tri|
   signed=tri.map{|p|(p[0]-o[0])*t[0]+(p[1]-o[1])*t[1]}
   next if signed.min>EPS || signed.max< -EPS
   pts=[]
   3.times do |i|
    a,b=tri[i],tri[(i+1)%3];da,db=signed[i],signed[(i+1)%3]
    pts<<a if da.abs<=EPS
    if da*db< -EPS*EPS
     f=da/(da-db);pts<<3.times.map{|k|a[k]+f*(b[k]-a[k])}
    end
   end
   points=pts.map{|p|[(p[0]-o[0])*normal[0]+(p[1]-o[1])*normal[1],p[2]]}.uniq{|p|p.map{|x|x.round(7)}}.sort_by(&:first)
   segments<<[points.first,points.last] if points.size>=2 && points.last[0]-points.first[0]>EPS
  end
  raise 'Bu istasyonda deniz tabanı yüzeyi bulunamadı.' if segments.empty?
  segments
 end
 def bed_at(segments,x)
  found=segments.select{|a,b|x>=a[0]-EPS && x<=b[0]+EPS}.map{|a,b|a[1]+(x-a[0])*(b[1]-a[1])/(b[0]-a[0])}
  raise 'Taban yüzeyinde boşluk veya kapsama dışı kesit var.' if found.empty?
  raise 'Taban yüzeyinde üst üste farklı kotlar var.' if found.max-found.min>1e-5
  found.sum/found.size
 end
 def envelope(left,right,crest,sl, sr,bottom)
  [[left,crest],[right,crest],[right+sr*(crest-bottom),bottom],[left-sl*(crest-bottom),bottom]]
 end
 def parametric(spec,profile)
  crest=number(spec['crest']);width=number(spec['width']);sl=number(spec['slope_left']);sr=number(spec['slope_right'])
  raise 'Kret genişliği ve şevler pozitif olmalı.' unless width>0 && sl>0 && sr>0
  bottom=[profile.flatten(1).map(&:last).min-0.01,crest-0.01].min
  layers=spec['layers'];raise 'Dıştan içe tabakalar ve son satırda çekirdek gerekli.' unless layers.is_a?(Array)&&!layers.empty?
  left=-width/2;right=width/2;out=[]
  layers.each_with_index do |layer,i|
   raise 'Malzeme kodu boş.' if layer['code'].to_s.strip.empty?
   outer=envelope(left,right,crest,sl,sr,bottom)
   if i==layers.size-1
    out<<{'code'=>layer['code'],'loops'=>[outer]};break
   end
   thickness=number(layer['thickness']);raise 'Tabaka kalınlığı pozitif olmalı.' unless thickness>0
   nl=left+thickness*(Math.sqrt(1+sl*sl)-sl);nr=right-thickness*(Math.sqrt(1+sr*sr)-sr);nc=crest-thickness
   raise 'Tabaka kalınlıkları kret genişliğini veya yüksekliğini tüketiyor.' unless nr>nl && nc>bottom
   inner=envelope(nl,nr,nc,sl,sr,bottom)
   out<<{'code'=>layer['code'],'loops'=>[outer,inner]};left,right,crest=nl,nr,nc
  end
  out
 end
 def section(parts,profile,with_cells=false,range=nil)
  return {'areas'=>{},'cells'=>[]} if parts.empty?
  all_edges=parts.flat_map{|p|p['loops'].flat_map{|l|edges(l)}}
  xmin=all_edges.flatten(1).map(&:first).min;xmax=all_edges.flatten(1).map(&:first).max
  xmin=[xmin,range[0]].max if range && range[0]
  xmax=[xmax,range[1]].min if range && range[1]
  return {'areas'=>{},'cells'=>[]} if xmax<=xmin
  lines=all_edges+profile
  knots=lines.flatten(1).map(&:first).select{|x|x>=xmin-EPS && x<=xmax+EPS}+[xmin,xmax]
  lines.each_with_index do |(a,b),i|
   lines[i+1..-1].each do |c,d|
    next if [a[0],b[0]].max<[c[0],d[0]].min || [c[0],d[0]].max<[a[0],b[0]].min
    p=line_cross(a,b,c,d);knots<<p[0] if p && p[0]>xmin && p[0]<xmax
   end
  end
  knots=knots.sort.uniq{|x|x.round(8)};areas={};cells=[]
  evaluate=lambda do |x|
   bed=bed_at(profile,x)
   concrete=union(parts.select{|p|p['code']=='__CONCRETE__'}.flat_map{|p|intervals(p['loops'],x)})
   groups={}
   parts.reject{|p|p['code']=='__CONCRETE__'}.each{|p|(groups[p['code']]||=[]).concat(intervals(p['loops'],x))}
   result={};occupied=[]
   groups.each do |code,list|
    cut=union(list).map{|a,b|[[a,bed].max,b]}.select{|a,b|b-a>EPS};cut=subtract(cut,concrete)
    clean=subtract(cut,occupied)
    overlap=cut.sum{|a,b|b-a}-clean.sum{|a,b|b-a}
    raise "#{code}: farklı malzeme yüzeyleri üst üste. Kapalı, ayrı tabaka yüzeyleri seçin." if overlap>1e-6
    result[code]=clean;occupied=union(occupied+clean)
   end
   result
  end
  knots.each_cons(2) do |a,b|
   next if b-a<1e-7
   mid=evaluate.call((a+b)/2)
   mid.each{|k,v|areas[k]=(areas[k]||0)+v.sum{|lo,hi|hi-lo}*(b-a)}
   if with_cells
    delta=(b-a)/4.0;ll=evaluate.call(a+delta);rr=evaluate.call(b-delta)
    mid.each do |k,list|
     list.each_index do |i|
      next unless ll[k][i] && rr[k][i]
      cells<<{'code'=>k,'points'=>[[a,1.5*ll[k][i][0]-0.5*rr[k][i][0]],[b,1.5*rr[k][i][0]-0.5*ll[k][i][0]],[b,1.5*rr[k][i][1]-0.5*ll[k][i][1]],[a,1.5*ll[k][i][1]-0.5*rr[k][i][1]]]}
     end
    end
   end
  end
  {'areas'=>areas,'cells'=>cells}
 end
 def calculate(input,with_cells=false)
  axis=input.fetch('axis');vertices=chain(axis);length=vertices.last;step=number(input['step']);raise 'Kesit aralığı pozitif olmalı.' unless step>0
  raise 'En fazla 2000 istasyon; aralığı büyütün.' if length/step>2000
  reaches=input.fetch('reaches').sort_by{|r|r['from']};raise 'İlk tip kesit 0+000 konumunda başlamalı.' if reaches.empty? || reaches.first['from']!=0
  raise 'Tip başlangıçları tekrarlı veya aks dışında.' unless reaches.map{|r|r['from']}.uniq.size==reaches.size && reaches.all?{|r|r['from']>=0 && r['from']<length}
  stations=vertices+(0..(length/step).floor).map{|i|i*step}+reaches.map{|r|r['from']}+(input['extra']||[])
  raise 'İlave istasyon aks dışında.' unless stations.all?{|x|x.finite? && x>=0 && x<=length+EPS}
  stations=stations.map(&:to_f).sort.uniq{|x|x.round(6)};raise 'En fazla 2000 istasyon destekleniyor.' if stations.size>2000
  triangles=input.fetch('triangles');raise 'Taban üçgenleri boş.' if triangles.empty?
  triangles.each{|t|raise 'Tabanda düşey/dejenere üçgen var.' if cross(*t).abs<1e-10}
  sections={};rows=[];totals={}
  stations.each_cons(2) do |a,b|
   reach=reaches.reverse.find{|r|r['from']<=(a+b)/2};type=reach.fetch('type')
   sa,sb=[a,b].map do |sta|
    key="#{type}:#{sta}"
    sections[key]||=begin
     fr=frame(axis,vertices,sta);bed=seabed_profile(triangles,fr);spec=input.fetch('types').fetch(type)
     bed,cut_area=excavation_profile(input,fr,bed)
     parts=blended_parts(input,reach,sta,bed)
     if spec['mode']=='faces'
      rock_points=parts.reject{|p|p['code']=='__CONCRETE__'}.flat_map{|p|p['loops'].flatten(1)}
      raise 'Tip kesitte taş malzemesi yok.' if rock_points.empty?
      minz=rock_points.map(&:last).min;lo,hi=rock_points.map(&:first).minmax
      low=bed.select{|aa,bb|bb[0]>=lo && aa[0]<=hi}.flatten(1).map(&:last).min
      raise 'Çizilmiş tip kesit tabandan daha sığ kalıyor. Kapalı tabaka sınırlarını daha derine uzatın veya parametrik kesit kullanın.' if low && low<minz-1e-5
     end
     result=section(parts,bed,with_cells)
     result.merge('parts'=>parts,'cut_area'=>cut_area,'station'=>sta,'type'=>type,'frame'=>fr,'bed'=>bed)
    rescue=>e
     raise "İstasyon #{format('%.3f',sta)} / #{type}: #{e.message}"
    end
   end
   values={};(sa['areas'].keys+sb['areas'].keys).uniq.each do |code|
    values[code]=((sa['areas'][code]||0)+(sb['areas'][code]||0))*0.5*(b-a)
    totals[code]=(totals[code]||0)+values[code]
   end
   rows<<{'start'=>a,'end'=>b,'type'=>type,'volumes'=>values,'a1'=>sa['areas'],'a2'=>sb['areas'],'excavation_m3'=>(sa['cut_area']+sb['cut_area'])*0.5*(b-a)}
  end
  raise 'Hesapta sonlu olmayan hacim var.' unless totals.values.all?{|x|x.finite?&&x>=0}
  output={'schema'=>'mst.rf02.live.v1','method'=>'AEA','total_length'=>length,'rows'=>rows,'sections'=>sections.values,'totals'=>totals,'total'=>totals.values.sum}
  output['assumptions']=[]
  output['assumptions']<<'Aynı yöntemle tanımlanmış tipler arasında doğrusal geçiş; son tip sabit. Parametrik tipte kot, genişlik, yatay/düşey şev oranı ve şeve dik tabaka kalınlığı istasyona göre doğrusal değişir.' if input['type_transition']=='linear'
  output['assumptions']<<'Boşluksuz uçta noktasal kapanış seçildi. Dışbükey boşlukta köşe ortalaması, içbükey boşlukta bütün sınırları içeriden gören bölgenin iç noktası kullanılır.' if input['void_transition']=='point'
  output['excavation_m3']=rows.sum{|r|r['excavation_m3']}
  head=head_quantities(input,output)
  if head
   output['body_totals']=totals.dup;output['head']=head;output['excavation_m3']+=head['excavation_m3']
   head['totals'].each{|k,v|totals[k]=(totals[k]||0)+v}
   output['total']=totals.values.sum
  end
  output
 end
end
end
end

require_relative 'rockfill_extensions'

require_relative 'rockfill_loft'

require_relative 'rockfill_cut_mesh'

require_relative 'rockfill_void_loft'

require_relative 'rockfill_transitions'

require_relative 'rockfill_refinement'
