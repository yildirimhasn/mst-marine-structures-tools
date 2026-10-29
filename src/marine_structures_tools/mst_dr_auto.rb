# frozen_string_literal: true
# v0.51 DR5 — Paftadan 3B donatı (otomatik): BK donatı paftasından (DXF) çizim paketi kurar (mst-drawing-rebar/1).
# Okunan: donatı tablosu (DX1 kroki satırları: poz, Ø, adet, aralık, L), büküm krokilerinin şekli (çizgi zinciri),
#  boy görünüşü (kiriş taban / üst profili, menfez), kesitler (çubuk noktaları + poz okları, etriye çizgileri), kesit harfleri.
# Kural:
#  · Boyuna poz: krokisi boy görünüşünün altında aynı x hizasında çizilir → v aralığı + uç kancaları; (u, z) kesitteki
#    noktalardan (ok ile poz balonuna bağlı). Kesitte etiketi yoksa aynı sıradaki (bindirmeli) pozdan alınır.
#  · Enine poz: kroki şekli kesit çizgileriyle örtüşür → (u, z) yeri ve takım başına adet; boyca dağılım: o kesitin
#    profiline (taban / üst / menfez) eşit bölgeler, aralık yazıdan (Ø16/15), adet tablodan (bölge alt kümesi adede göre seçilir).
#  · Yerleştirilemeyen poz metrajda kalır, önizlemede gerekçesiyle listelenir.
# Katman adları ipucudur (MAG: rebar / demir, rebar section / demir_(kesit), …; bozuk Türkçe harfler tolere edilir).
require 'json'
module MAG
module MarineStructuresTools

MST_DRA_VER='DR5'

def mst_dra_fold(s)
 s.to_s.downcase.tr('çğıöşüâîû','cgiosuaiu').gsub('i̇','i').gsub(/[^\x20-\x7e]/,'?').gsub(/\?+/,'?')
end
# katman rolü
def mst_dra_role(l)
 f=mst_dra_fold(l)
 return :dot if f=~/rebar section|demir.?\(kesit\)|demir_kesit/
 return :lead if f=~/notation|oku|arrow|ok(lar)?\b/ && f=~/rebar|donat|demir/
 return :rbar if f=~/\A(rebar|demir)\z/ || f=~/\Adonat.?\s*\(rebar\)\z/ || f=~/\Adonat.?_?\(?demir\)?\z/
 return :menfez if f=~/menfez|culvert/
 return :outline if f=~/cap beam|ba.?l.?k.?kiri|bk.?kesit/ && !(f=~/yaz|plan|title/)
 return :stage2 if f=~/2\.?\s*kademe|2nd stage/
 return :secline if f=~/kesit.?cizgi|section line|kesit_.izgisi/
 :other
end

# ---------------------------------------------------------------- yardımcılar
def mst_dra_segs(es)
 out=[]
 es.each do |e|
  if e['t']=='LINE' && e['x2'] then out << [[e['x'],e['y']],[e['x2'],e['y2']],e]
  elsif e['t']=='LWPOLYLINE' && e['pts']
   p=e['pts'];p.each_cons(2){|a,b|out << [a,b,e]};out << [p[-1],p[0],e] if e['closed']
  end
 end
 out.reject{|a,b,_|(a[0]-b[0]).abs+(a[1]-b[1]).abs<1e-9}
end
def mst_dra_bb(pts)
 xs=pts.map{|p|p[0]};ys=pts.map{|p|p[1]};[xs.min,ys.min,xs.max,ys.max]
end
def mst_dra_in?(bb,x,y,m=0);x>=bb[0]-m && x<=bb[2]+m && y>=bb[1]-m && y<=bb[3]+m;end
# nokta → doğru parçası uzaklığı
def mst_dra_pd(p,a,b)
 dx=b[0]-a[0];dy=b[1]-a[1];l2=dx*dx+dy*dy
 t=l2<1e-12 ? 0 : [[((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l2,0.0].max,1.0].min
 Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
end
# uç noktaları ortak (ya da birinin ucu diğerinin üstünde) parçalardan zincirler
def mst_dra_chains(segs,tol)
 par=(0...segs.length).to_a
 f=->(i){i=par[i] while par[i]!=i;i}
 key={}
 grid=Hash.new{|h,k|h[k]=[]};c=[tol*20,1e-6].max
 segs.each_with_index{|(a,b,_),i|[[a[0],b[0]].min,[a[0],b[0]].max].tap{|x0,x1|((x0/c).floor..(x1/c).floor).each{|gx|(([a[1],b[1]].min/c).floor..([a[1],b[1]].max/c).floor).each{|gy|grid[[gx,gy]] << i}}}}
 segs.each_with_index do |(a,b,_),i|
  [a,b].each do |p|
   (grid[[(p[0]/c).floor,(p[1]/c).floor]]).each do |j|
    next if j==i
    q=segs[j]
    next unless mst_dra_pd(p,q[0],q[1])<=tol
    ri=f.(i);rj=f.(j);par[ri]=rj if ri!=rj
   end
  end
 end
 g=Hash.new{|h,k|h[k]=[]};segs.each_index{|i|g[f.(i)] << segs[i]};g.values
end
# zincir → sıralı yol (uç noktasından başla); dallı ise nil
def mst_dra_path(ch,tol)
 pts=[];ch.each{|a,b,_|[a,b].each{|p|pts << p unless pts.any?{|q|(q[0]-p[0]).abs<=tol && (q[1]-p[1]).abs<=tol}}}
 id=->(p){pts.index{|q|(q[0]-p[0]).abs<=tol && (q[1]-p[1]).abs<=tol}}
 adj=Hash.new{|h,k|h[k]=[]};ch.each{|a,b,_|i=id.(a);j=id.(b);next if i==j;adj[i] << j;adj[j] << i}
 return nil if adj.values.any?{|v|v.length>2}
 st=adj.keys.find{|k|adj[k].length==1} || adj.keys.first
 return nil unless st
 path=[st];prev=nil;cur=st
 loop do
  nx=(adj[cur]-[prev]).first
  break if nx.nil? || (nx==st && path.length>2)
  path << nx;prev=cur;cur=nx
  break if path.length>adj.length+1
 end
 path << st if adj[cur].include?(st) && path.length==adj.length && adj.length>2 && path.last!=st && adj.values.all?{|v|v.length==2}
 path.map{|i|pts[i]}
end
def mst_dra_mainy(c)
 p=c['path'];return nil unless p
 sg=p.each_cons(2).select{|a,b|(a[1]-b[1]).abs<1e-3*[1,(b[0]-a[0]).abs].max}.max_by{|a,b|(b[0]-a[0]).abs}
 sg ? sg[0][1] : nil
end
def mst_dra_plen(p);p.each_cons(2).sum{|a,b|Math.hypot(b[0]-a[0],b[1]-a[1])};end

# ---------------------------------------------------------------- paftadaki kirişler (başlıklar + bölge)
def mst_dra_details(fl)
 tt=fl.select{|e|e['text'].to_s=~/DONATI\s*DETAY|REINFORCEMENT\s*DETAIL/i && e['text'].to_s=~/B\s*K\s*-?\s*\d|BA.LIK|CAP\s*BEAM/i && !(e['text'].to_s=~/PAFTA|BAKINIZ|SEE\s/i)}
 rects=[]
 fl.each do |e|
  next unless e['t']=='LWPOLYLINE' && e['pts'] && e['pts'].length>=4
  bb=mst_dra_bb(e['pts']);next if (bb[2]-bb[0])*(bb[3]-bb[1])<1.0
  xs=e['pts'].map{|p|p[0].round(1)}.uniq;ys=e['pts'].map{|p|p[1].round(1)}.uniq
  rects << bb if xs.length<=2 && ys.length<=2
 end
 h=tt.map{|t|t['h'].to_f}.max || 10
 tt.map do |t|
  nm=t['text'].to_s[/\(?\s*(B\s*K\s*-?\s*\d+[A-Z]?)\s*\)?/i,1].to_s.gsub(/\s+/,'').upcase
  fr=rects.select{|r|mst_dra_in?(r,t['x'],t['y']) && (r[2]-r[0])>40*t['h'].to_f}.min_by{|r|(r[2]-r[0])*(r[3]-r[1])}
  {'name'=>(nm.empty? ? t['text'].to_s[0,20] : nm.sub(/BK-?/,'BK-')),'title'=>t['text'].to_s.gsub(/\s+/,' ')[0,70],'x'=>t['x'],'y'=>t['y'],'h'=>t['h'].to_f,'frame'=>fr}
 end.uniq{|d|[d['name'],d['x'].round,d['y'].round]}.group_by{|d|d['name']}.map do |_,v|
  # aynı adlı başlıklardan krokisi (L = …) en çok olan bölge (pafta antedindeki küçük kopya değil)
  next v.first if v.length==1
  sc=v.map{|d|[d,mst_dra_region(fl,d).count{|e|e['text'].to_s=~/\AL\s*=\s*\d/i}]}
  mx=sc.map(&:last).max
  fr=sc.select{|d,n|d['frame'] && n>0}.max_by{|_,n|n}   # çerçeveli (kendi paftası) olan önce
  (fr || sc.max_by{|_,n|n}).first
 end
end
# başlığın bölgesi: çerçeve; yoksa başlıktan büyüyen yoğunluk kümesi
def mst_dra_region(fl,d,cell=nil)
 return fl.select{|e|e['x'] && mst_dra_in?(d['frame'],e['x'],e['y'])} if d['frame']
 cell||=[d['h']*12,40].max
 # her varlığın noktaları (çizgiler boyunca örneklenir)
 epts=lambda do |e|
  ps=[[e['x'],e['y']]];ps << [e['x2'],e['y2']] if e['x2'];ps+=e['pts'] if e['pts']
  out=[];ps.compact.each_cons(2){|a,b|k=[(Math.hypot(b[0]-a[0],b[1]-a[1])/(cell/2)).ceil,1].max;(0..k).each{|i|out << [a[0]+(b[0]-a[0])*i/k,a[1]+(b[1]-a[1])*i/k]}}
  out.empty? ? ps.compact : out
 end
 occ=Hash.new(false);fl.each{|e|next unless e['x'];epts.(e).each{|x,y|occ[[(x/cell).floor,(y/cell).floor]]=true}}
 st=[(d['x']/cell).floor,(d['y']/cell).floor];seen={st=>true};q=[st]
 until q.empty?
  c=q.pop
  (-2..2).each{|i|(-2..2).each{|j|n=[c[0]+i,c[1]+j];next if seen[n] || !occ[n];seen[n]=true;q << n}}
 end
 fl.select{|e|e['x'] && epts.(e).any?{|x,y|seen[[(x/cell).floor,(y/cell).floor]]}}
end

# ---------------------------------------------------------------- boy görünüşü + kesitler
# dış hat parçaları kümeleri → en geniş = boy görünüşü, diğerleri kesit
def mst_dra_views(fl,tol)
 os=mst_dra_segs(fl.select{|e|%i[outline menfez].include?(mst_dra_role(e['l']))})
 return nil if os.empty?
 # yakın parçalar aynı görünüş (boşluk ≤ 25 birim)
 chs=mst_dra_chains(os.select{|_,_,e|mst_dra_role(e['l'])==:outline},tol*25)
 vs=chs.map{|c|bb=mst_dra_bb(c.flat_map{|a,b,_|[a,b]});{'bb'=>bb,'segs'=>c}}.select{|v|v['bb'][2]-v['bb'][0]>tol*20}
 return nil if vs.empty?
 el=vs.max_by{|v|v['bb'][2]-v['bb'][0]}
 secs=vs.reject{|v|v.equal?(el) || (v['bb'][2]-v['bb'][0])>(el['bb'][2]-el['bb'][0])*0.6}
 {'elev'=>el,'secs'=>secs,'menfez'=>os.select{|_,_,e|mst_dra_role(e['l'])==:menfez}}
end
# boy görünüşünde v (çizim x) noktasındaki profil: taban, üst (tabandan sonraki ilk yatay çizgi), menfez
def mst_dra_prof(el,menfez,x)
 hs=el['segs'].select{|a,b,_|(a[1]-b[1]).abs<1e-6 && [a[0],b[0]].min<=x+1e-6 && [a[0],b[0]].max>=x-1e-6}.map{|a,_,_|a[1]}.sort
 return nil if hs.empty?
 bot=hs.first
 mf=menfez.select{|a,b,_|[a[0],b[0]].min<x && [a[0],b[0]].max>x && (a[1]-b[1]).abs<1e-6}.map{|a,_,_|a[1]}.min
 up=hs.select{|y|y>bot+1e-6};top=up.first
 [bot.round(2),top ? top.round(2) : nil,mf ? 1 : 0]
end
# profil sabit aralıklar: [[x0,x1,prof]]
def mst_dra_zones(el,menfez)
 xs=(el['segs'].flat_map{|a,b,_|[a[0],b[0]]}+menfez.flat_map{|a,b,_|[a[0],b[0]]}).map{|x|x.round(2)}.uniq.sort
 x0=el['bb'][0];x1=el['bb'][2];xs=xs.select{|x|x>=x0-0.02 && x<=x1+0.02}
 zs=[]
 xs.each_cons(2) do |a,b|
  next if b-a<1e-6
  pr=mst_dra_prof(el,menfez,(a+b)/2.0);next unless pr && pr[1]
  if zs.last && zs.last[2]==pr && (zs.last[1]-a).abs<1e-6 then zs.last[1]=b else zs << [a,b,pr] end
 end
 zs
end
# kesit görünüşü: dış hat kutusu, taban, gövde üstü (ilk yatay), menfez var mı
def mst_dra_secprof(sec,menfez,up=0.0)
 bb=sec['bb'];hs=sec['segs'].select{|a,b,_|(a[1]-b[1]).abs<1e-6 && (b[0]-a[0]).abs>(bb[2]-bb[0])*0.3}.map{|a,_,_|a[1]}.sort
 bot=bb[1];top=hs.find{|y|y>bot+1e-6} || bb[3]
 mf=menfez.any?{|a,b,_|x=(a[0]+b[0])/2.0;y=(a[1]+b[1])/2.0;x>=bb[0]-(bb[2]-bb[0])*0.1 && x<=bb[2]+(bb[2]-bb[0])*0.1 && y>=bb[1] && y<=bb[3]+up} ? 1 : 0
 [bot,top,mf]
end

# ---------------------------------------------------------------- ana kurucu
# fl: bölgenin varlıkları. dönüş: {'spec','report','ok'}
def mst_dra_build(fl,name='BK')
 rep=[];warn=[]
 sc=mst_dxr_scan(fl)
 rows=sc['rows'].select{|r|r['poz']>0 && r['len'].to_f>0}
 raise 'Paftada donatı tablosu (poz + "adet Ø" + "L = …" krokileri) bulunamadı.' if rows.empty?
 rsegs=mst_dra_segs(fl.select{|e|mst_dra_role(e['l'])==:rbar})
 raise 'Paftada donatı çizgisi (rebar / demir katmanı) yok.' if rsegs.empty?
 # birim: kroki zinciri boyu / L — çizim birimi / m
 hmed=rows.map{|r|r['h'] || 0}.max
 ftol=0.6
 chains=mst_dra_chains(rsegs,ftol).map{|c|p=mst_dra_path(c,ftol);{'segs'=>c,'path'=>p,'len'=>c.sum{|a,b,_|Math.hypot(b[0]-a[0],b[1]-a[1])},'bb'=>mst_dra_bb(c.flat_map{|a,b,_|[a,b]})}}
 ks=[]
 rows.each{|r|c=chains.min_by{|ch|bb=ch['bb'];dx=r['x']<bb[0] ? bb[0]-r['x'] : (r['x']>bb[2] ? r['x']-bb[2] : 0);dy=[(r['y']-bb[1]).abs,(r['y']-bb[3]).abs,(r['y']>bb[1] && r['y']<bb[3]) ? 0 : 1e9].min;dx+dy};ks << c['len']/r['len'] if c && c['len']>0}
 kk=ks.map{|x|[100.0,1000.0,1.0,10.0].min_by{|u|(Math.log(x/u)).abs}}.group_by{|x|x}.max_by{|_,v|v.length}&.first || 100.0
 u2m=->(x){x/kk}
 tol=0.006*kk   # 6 mm
 # krokiler: her satıra boyu uyan en yakın zincir
 used={}
 rows.each do |r|
  want=r['len']*kk
  cand=chains.reject{|c|used[c.object_id]}.select{|c|(c['len']-want).abs<=[0.012*want,0.02*kk].max && c['path']}
  c=cand.min_by{|ch|bb=ch['bb'];cx=(bb[0]+bb[2])/2.0;cy=(bb[1]+bb[3])/2.0;dy=[ (r['y']-bb[1]).abs,(r['y']-bb[3]).abs].min+((r['y']>=bb[1] && r['y']<=bb[3]) ? 0 : 0);Math.hypot([r['x']-bb[2],bb[0]-r['x'],0].max*0.5,dy)+((cx-r['x']).abs*0.05)}
  if c then used[c.object_id]=true;r['chain']=c else r['chain']=nil end
 end
 vw=mst_dra_views(fl,tol)
 raise 'Boy görünüşü (başlık kirişi dış hattı) bulunamadı.' unless vw
 el=vw['elev'];x0=el['bb'][0];x1=el['bb'][2];lm=u2m.(x1-x0)
 zones=mst_dra_zones(el,vw['menfez'])
 zb=zones.map{|z|z[2][0]}.min
 hmax=zones.map{|z|z[2][1]}.compact.max-zb
 # kesitler: genişlik ortak (çoğunluk)
 secs=vw['secs'].select{|s|(s['bb'][2]-s['bb'][0])>=0.5*kk && (s['bb'][3]-s['bb'][1])>=0.2*kk}
 wd=secs.map{|s|(s['bb'][2]-s['bb'][0]).round}.group_by{|x|x}.max_by{|_,v|v.length}&.first
 raise 'Kesit görünüşü bulunamadı.' unless wd
 secs=secs.select{|s|((s['bb'][2]-s['bb'][0])-wd).abs<=2*tol}
 wm=u2m.(wd)
 # kesit ↔ bölge profili (yükseklik + menfez)
 secs.each do |s|
  pr=mst_dra_secprof(s,vw['menfez'],1.6*kk);s['prof']=pr;h=pr[1]-pr[0]
  s['zones']=zones.select{|z|z[2][1] && ((z[2][1]-z[2][0])-h).abs<=2*tol && z[2][2]==pr[2]}
  s['zones']=zones.select{|z|z[2][1] && ((z[2][1]-z[2][0])-h).abs<=2*tol} if s['zones'].empty?
  s['zb']=s['zones'].empty? ? zb : s['zones'].first[2][0]
 end
 secs.select!{|s|!s['zones'].empty?}
 raise 'Kesitler boy görünüşündeki bölgelerle eşleşmedi.' if secs.empty?
 # kesit çerçevesinde nokta: (u, z) m — u kesit dış hattının solundan, z boy görünüşü tabanından
 loc=->(s,x,y){[u2m.(x-s['bb'][0]),u2m.(y-s['bb'][1]+s['zb']-zb)]}
 dots=fl.select{|e|mst_dra_role(e['l'])==:dot && %w[CIRCLE ARC].include?(e['t']) && e['r'].to_f<0.03*kk}
 lsegs=mst_dra_segs(fl.select{|e|mst_dra_role(e['l'])==:lead})
 nums=fl.select{|e|e['text'].to_s.strip=~/\A\d{1,3}\z/ && e['x']}
 cds=fl.select{|e|e['text'].to_s=~/Ø\s*\d/ && e['x']}
 # ok ağları
 lch=mst_dra_chains(lsegs,0.02*kk)
 placed={};why={}
 sch=rows.group_by{|r|r['poz']}.map do |pz,rs|
  d=rs.first['d'];n=rs.sum{|r|r['n']};len=rs.first['len']
  {'poz'=>pz,'d'=>d.to_i,'n'=>n,'len'=>len.round(3),'s'=>rs.map{|r|r['s']}.compact.first,'rows'=>rs,'shape'=>rs.map{|r|r['cd']}.uniq.join(' / ')}
 end.sort_by{|s|s['poz']}
 dup=sch.group_by{|s|s['poz']}.select{|_,v|v.length>1}.keys
 warn << "Aynı poz numarası farklı Ø / boyla: #{dup.join(', ')} (ilki kullanılır)" unless dup.empty?
 # nokta hangi kesitin: dış hattın 0.3 m yanında, 0.9 m üstünde / 0.3 m altında olan en yakın kesit
 own_sec=lambda do |x,y|
  secs.select{|s|b=s['bb'];x>=b[0]-0.3*kk && x<=b[2]+0.3*kk && y>=b[1]-0.3*kk && y<=b[3]+1.6*kk}.min_by{|s|b=s['bb'];Math.hypot([b[0]-x,x-b[2],0].max,[b[1]-y,y-b[3],0].max)}
 end
 tanch=Hash.new{|h,k|h[k]=[]};tlab=Hash.new{|h,k|h[k]=[]}
 # okla bağlanmamış balonlar da kesitin etiketi sayılır
 nums.each{|t|sc0=own_sec.(t['x'],t['y']);tlab[t['text'].strip.to_i] << sc0 if sc0}
 # --- kesitlerdeki poz grupları: ok zinciri → noktalar + balondaki numara
 secgrp=Hash.new{|h,k|h[k]=[]}   # poz → [[sec,[u,z]...]]
 secs.each do |s|
  bb=s['bb'];m=(bb[2]-bb[0])*0.6
  sd=dots.select{|e|own_sec.(e['x'],e['y']).equal?(s)}
  next if sd.empty?
  claimed={}
  lch.each do |ch|
   pts=ch.flat_map{|a,b,_|[a,b]}
   next unless pts.any?{|p|mst_dra_in?(bb,p[0],p[1],m)}
   ds=sd.select{|e|ch.any?{|a,b,_|mst_dra_pd([e['x'],e['y']],a,b)<=e['r'].to_f+0.004*kk}}
   # serbest uca en yakın numara
   ends=pts.select{|p|ch.count{|a,b,_|(a[0]-p[0]).abs+(a[1]-p[1]).abs<1e-6 || (b[0]-p[0]).abs+(b[1]-p[1]).abs<1e-6}==1}
   ends=pts.uniq if ends.empty?
   lab=nums.min_by{|t|ends.map{|p|Math.hypot(t['x']-p[0],t['y']-p[1])}.min || 1e9}
   next unless lab && ends.map{|p|Math.hypot(lab['x']-p[0],lab['y']-p[1])}.min.to_f<0.15*kk
   pz=lab['text'].strip.to_i
   if ds.empty?
    # enine poz oku: balondan uzak serbest uç(lar) bir çubuk çizgisinin üstünde
    far=ends.select{|p|Math.hypot(lab['x']-p[0],lab['y']-p[1])>0.15*kk && own_sec.(*p).equal?(s)}
    tanch[pz] << [s,far.map{|p|loc.(s,*p)}] unless far.empty?
    tlab[pz] << s
    next
   end
   ds.each{|e|claimed[e.object_id]=pz}
   secgrp[pz] << [s,ds.map{|e|loc.(s,e['x'],e['y'])}]
  end
  # sahipsiz noktalar: aynı yarıçaplı en yakın sahipli gruba (düşeyde ≤ 8 cm)
  sd.reject{|e|claimed[e.object_id]}.each do |e|
   own=sd.select{|q|claimed[q.object_id] && (q['r'].to_f-e['r'].to_f).abs<1e-3*kk && (q['x']-e['x']).abs<0.01*kk && (q['y']-e['y']).abs<0.08*kk}.min_by{|q|(q['y']-e['y']).abs}
   next unless own
   pz=claimed[own.object_id];g=secgrp[pz].find{|sg,_|sg.equal?(s)};g[1] << loc.(s,e['x'],e['y']) if g
  end
 end
 secpos=Hash[secgrp.map{|pz,l|ps=[];l.flat_map{|_,p|p}.each{|q|ps << q.map{|c|c.round(3)} unless ps.any?{|o|(o[0]-q[0]).abs<0.008 && (o[1]-q[1]).abs<0.008}};[pz,ps]}]
 $mst_dra_dbg={'secgrp'=>secgrp,'secs'=>secs,'lch'=>lch,'dots'=>dots,'nums'=>nums} if $mst_dra_debug
 # boy görünüşündeki yatay çubuk çizgileri
 eb=el['bb'];elr=rsegs.select{|a,b,_|(a[1]-b[1]).abs<1e-6 && [a[0],b[0]].min>=eb[0]-1 && [a[0],b[0]].max<=eb[2]+1 && a[1]>=eb[1]-0.1*kk && a[1]<=eb[3]+1.0*kk}
 # boy görünüşündeki poz okları: balon → çubuk çizgisi (z seviyesi)
 zlev=Hash.new{|h,k|h[k]=[]}
 lch.each do |ch|
  pts=ch.flat_map{|a,b,_|[a,b]}
  next unless pts.any?{|p|mst_dra_in?(eb,p[0],p[1],0.3*kk)}
  ends=pts.select{|p|ch.count{|a,b,_|(a[0]-p[0]).abs+(a[1]-p[1]).abs<1e-6 || (b[0]-p[0]).abs+(b[1]-p[1]).abs<1e-6}==1}
  lab=nums.min_by{|t|ends.map{|p|Math.hypot(t['x']-p[0],t['y']-p[1])}.min || 1e9}
  next unless lab && ends.map{|p|Math.hypot(lab['x']-p[0],lab['y']-p[1])}.min.to_f<0.15*kk
  ends.each do |p|
   next if Math.hypot(lab['x']-p[0],lab['y']-p[1])<0.15*kk
   ln=elr.find{|a,b,_|mst_dra_pd(p,a,b)<=0.01*kk}
   zlev[lab['text'].strip.to_i] << u2m.(ln[0][1]-zb).round(3) if ln
  end
 end
 alldots=[];secs.each{|sc4|dots.select{|e|own_sec.(e['x'],e['y']).equal?(sc4)}.each{|e|alldots << [sc4,loc.(sc4,e['x'],e['y'])]}}
 ($mst_dra_dbg['alldots']=alldots;$mst_dra_dbg['zlev']=zlev) if $mst_dra_debug
 # --- kesit etriye çizgileri (u,z m)
 secl={}
 secs.each{|s|secl[s.object_id]=rsegs.select{|a,b,_|own_sec.(*a).equal?(s) && own_sec.(*b).equal?(s)}.map{|a,b,_|[loc.(s,*a),loc.(s,*b)]}}
 cover=->(segs,a,b){l=Math.hypot(b[0]-a[0],b[1]-a[1]);return 0.0 if l<1e-9
  k=[(l/0.02).ceil,2].max;(0..k).count{|i|p=[a[0]+(b[0]-a[0])*i/k,a[1]+(b[1]-a[1])*i/k];segs.any?{|c,d|mst_dra_pd(p,c,d)<=0.012}}*l/(k+1)}
 groups=[];probes=[]
 lap=Hash.new(0)
 sch.each do |s|
  pz=s['poz'];r0=s['rows'].first;ch=r0['chain']
  (why[pz]='kroki çizgisi bulunamadı';next) unless ch && ch['path']
  path=ch['path'];bb=ch['bb']
  segl=path.each_cons(2).map{|a,b|[a,b,Math.hypot(b[0]-a[0],b[1]-a[1])]}
  hz=segl.select{|a,b,l|(a[1]-b[1]).abs<0.02*l}
  main=hz.max_by{|_,_,l|l}
  inel=!main.nil? && bb[0]>=x0-0.6*kk && bb[2]<=x1+0.6*kk && main[2]>=0.3*kk && main[2]>=0.5*(bb[2]-bb[0])
  ($mst_dra_dbg2||={})[pz]={'bb'=>bb.map{|c|c.round(1)},'x0'=>x0.round(1),'x1'=>x1.round(1),'main'=>main && main[2].round(1),'path'=>path.map{|q|q.map{|c|c.round(1)}}} if $mst_dra_debug
  # enine: kroki şekli bir kesitte çizgilerle örtüşüyor mu
  sn=[path[0].dup];path.each_cons(2){|a,b|dx=b[0]-a[0];dy=b[1]-a[1];q=sn.last;sn << (dy.abs<0.2*dx.abs && dx.abs>0.05*kk ? [q[0]+dx,q[1]] : (dx.abs<0.2*dy.abs && dy.abs>0.05*kk ? [q[0],q[1]+dy] : [q[0]+dx,q[1]+dy]))}
  shp=sn.map{|p|u2m.(p[0]-sn.map{|q|q[0]}.min).round(4)}.zip(sn.map{|p|u2m.(p[1]-sn.map{|q|q[1]}.min).round(4)})
  tmatch=[]
  secs.each do |sc2|
   ls=secl[sc2.object_id];next if ls.empty?
   epts=ls.flat_map{|c,d|[c,d]}.uniq{|p|p.map{|c|(c*200).round}}
   [[false,false],[true,false]].each do |mir,fl2|
    um=shp.map(&:first).max;zm=shp.map(&:last).max
    sp=shp.map{|u,z|[mir ? um-u : u,fl2 ? zm-z : z]}
    cands=sp.flat_map{|a0|epts.map{|p|[p[0]-a0[0],p[1]-a0[1]]}}.uniq{|t|t.map{|c|(c*200).round}}
    cands.each do |du,dz|
     q=sp.map{|u,z|[u+du,z+dz]}
     next if q.any?{|u,z|u< -0.01 || u>wm+0.01}
     sl=q.each_cons(2).map{|a,b|[a,b,Math.hypot(b[0]-a[0],b[1]-a[1])]};tot=sl.sum{|x|x[2]}
     cvs=sl.map{|a,b,_|cover.(ls,a,b)}
     body=sl.each_index.reject{|i3|(i3==0 || i3==sl.length-1) && sl.length>2 && sl[i3][2]<0.15*tot}
     bt=body.sum{|i3|sl[i3][2]};bc=body.sum{|i3|cvs[i3]}
     sig=q.map{|x|x.map{|c|(c*100).round}}.sort
     tmatch << [sc2,q,sig] if bc>=0.97*bt && cvs.sum>=0.8*tot && !tmatch.any?{|s3,_,g3|s3.equal?(sc2) && g3==sig}
    end
   end
  end
  ($mst_dra_dbg3||={})[pz]=tmatch.group_by{|x,_,_|x}.map{|k,v|[k['bb'][0].round,v.length]} if $mst_dra_debug
  tdone=false
  if !tmatch.empty?
   tdone=catch(:tfail) do
   bysec=tmatch.group_by{|sc2,_,_|sc2}
   lab=tlab[pz].uniq
   ks2=bysec.keys
   unl=->(c){!lab.empty? && !lab.any?{|x|x.equal?(c)}}
   sp=s['s'] ? (s['s']>=50 ? s['s']/1000.0 : s['s']/100.0) : 0.15
   best=nil
   (1..[ks2.length,6].min).each do |kn|
    ks2.combination(kn).each do |cmb|
     zz=cmb.flat_map{|c|c['zones']}.uniq{|z|z.first(2)}
     capsets=zz.sum{|z|u2m.(z[1]-z[0])/sp}
     next if capsets<0.5
     mx=cmb.map{|c|bysec[c].length}.min
     per=[[(s['n']/capsets).round,1].max,mx].min
     sc3=(capsets*per-s['n']).abs/[s['n'],1].max+0.03*cmb.count{|c|unl.(c)}+0.05*(per-1)
     best=[sc3,cmb,zz,per] if best.nil? || sc3<best[0]-1e-9 || ((sc3-best[0]).abs<1e-9 && cmb.length<best[1].length)
    end
   end
   if best.nil? || best[0]>0.25 then why[pz]=format('enine: adet %d, kesit bölgelerine uymuyor',s['n']);throw :tfail,false end
   e,cmb,zz,per=best
   if s['n']%per!=0 then why[pz]=format('enine: adet %d, takım başına %d ile bölünmüyor',s['n'],per);throw :tfail,false end
   sets=s['n']/per
   lens=zz.map{|z|u2m.(z[1]-z[0])};tot=lens.sum
   cnt=lens.map{|l|(l/tot*sets).floor};(sets-cnt.sum).times{j2=lens.each_index.max_by{|k|lens[k]/sp-cnt[k]};cnt[j2]+=1}
   vs=[];zz.each_with_index{|z,i2|a=u2m.(z[0]-x0);l=lens[i2];k=cnt[i2];c=[0.08,l/4].min;k.times{|j2|vs << (a+c+(j2+0.5)*(l-2*c)/k).round(4)}}
   # takım içindeki yerler: oku gösterilen eşleşme önce, sonra eksene göre simetriği, sonra ortaya yakın olanlar
   c0=cmb.first;cand=bysec[c0].map{|_,q,_|q}
   anc=tanch[pz].select{|sg,_|sg.equal?(c0)}.flat_map{|_,ps|ps}
   onshape=->(q,p){q.each_cons(2).any?{|a,b|mst_dra_pd(p,a,b)<=0.02}}
   pick=cand.select{|q|anc.any?{|p|onshape.(q,p)}}
   pick.dup.each{|q|m2=q.map{|u,z|[wm-u,z]};mm=cand.find{|c|c.zip(m2.reverse).all?{|x,y|(x[0]-y[0]).abs<0.01 && (x[1]-y[1]).abs<0.01} || c.zip(m2).all?{|x,y|(x[0]-y[0]).abs<0.01 && (x[1]-y[1]).abs<0.01}};pick << mm if mm && !pick.include?(mm)}
   cen=->(q){(q.map(&:first).sum/q.length-wm/2).abs}
   (cand-pick).sort_by{|q|cen.(q)}.each{|q|pick << q if pick.length<per}
   shapes=pick.first(per).map do |q|
    q=q.map(&:dup);tl=q.each_cons(2).sum{|a,b|Math.hypot(b[0]-a[0],b[1]-a[1])}
    zt=u2m.(c0['prof'][1]-c0['bb'][1])+u2m.(c0['zb']-zb)+1.6
    zl=u2m.(c0['zb']-zb)
    out=->(p){p[0]<0.02 || p[0]>wm-0.02 || p[1]<zl+0.02 || p[1]>zt}
    [[0,1],[q.length-1,q.length-2]].each do |e2,b2|
     next if q.length<3 || Math.hypot(q[e2][0]-q[b2][0],q[e2][1]-q[b2][1])>0.15*tl
     q[e2]=[2*q[b2][0]-q[e2][0],2*q[b2][1]-q[e2][1]] if out.(q[e2])   # kanca kirişin dışına bakıyorsa içe çevir
    end
    q
   end
   s['vs']=vs;s['tshapes']=shapes;s['kind']=:trans
   placed[pz]=format('enine · %d takım × %d · %d kesit',sets,per,cmb.length)
   why.delete(pz)
   true
   end
  end
  next if tdone
  if inel
   srcs=[pz]
   unless secpos[pz] && !secpos[pz].empty?
    # aynı sıradaki (bindirmeli) boyuna pozdan
    my=main[0][1]
    mc=sch.select{|o|o['poz']!=pz && secpos[o['poz']]}.flat_map{|o|o['rows'].map{|r2|[o,r2['chain']]}}.select{|o,c2|c2 && (y2=mst_dra_mainy(c2)) && (y2-my).abs<0.12*kk && c2['bb'][0]<bb[2]+0.6*kk && c2['bb'][2]>bb[0]-0.6*kk}
    srcs=mc.sort_by{|o,c2|(mst_dra_mainy(c2)-my).abs}.map{|o,_|o['poz']}.uniq
   end
   occ=s['rows'].map{|r|r['chain']}.compact.uniq
   # her kroki için: v aralığıyla örtüşen bölgelerin kesitlerindeki yerler
   merge=->(ls){ps=[];ls.each{|q|ps << q unless ps.any?{|o|(o[0]-q[0]).abs<0.008 && (o[1]-q[1]).abs<0.008}};ps}
   pos_for=lambda do |src,lo,hi|
    gs=secgrp[src]
    ov=gs.select{|sg,_|sg['zones'].any?{|z|z[0]<hi-0.05*kk && z[1]>lo+0.05*kk}}
    merge.((ov.empty? ? gs : ov).flat_map{|_,ps|ps}.map{|q|q.map{|c|c.round(3)}})
   end
   pick=nil
   srcs.each do |src|
    per=occ.map{|c|pos_for.(src,c['bb'][0],c['bb'][2])}
    tot=per.sum(&:length)
    if tot==s['n'] then pick=[per,false];break
    elsif tot*2==s['n'] then pick=[per,true];break
    end
    all=merge.(secgrp[src].flat_map{|_,ps|ps}.map{|q|q.map{|c|c.round(3)}})
    if all.length*occ.length==s['n'] then pick=[occ.map{all},false];break
    elsif all.length*occ.length*2==s['n'] then pick=[occ.map{all},true];break
    end
    # tek bir kesitin yerleri
    secgrp[src].each do |_,ps|
     ps=merge.(ps.map{|q|q.map{|c|c.round(3)}})
     if ps.length*occ.length==s['n'] then pick=[occ.map{ps},false];break
     elsif ps.length*occ.length*2==s['n'] then pick=[occ.map{ps},true];break end
    end
    break if pick
   end
   unless pick
    # aynı Ø ve kroki başına aynı adette kesit grubu olan poz
    sch.each do |o|
     next if o['poz']==pz || o['d']!=s['d'] || !secgrp.key?(o['poz'])
     secgrp[o['poz']].each do |_,ps|
      ps=merge.(ps.map{|q|q.map{|c|c.round(3)}})
      if ps.length*occ.length==s['n'] then pick=[occ.map{ps},false];break end
     end
     break if pick
    end
   end
   unless pick
    # boy görünüşündeki okun gösterdiği z seviyesindeki kesit noktaları
    zlev[pz].uniq.each do |zl|
     per=occ.map{|c|lo=c['bb'][0];hi=c['bb'][2]
      ov=alldots.select{|sg,q|(q[1]-zl).abs<=0.015 && sg['zones'].any?{|z|z[0]<hi-0.05*kk && z[1]>lo+0.05*kk}}
      ov=alldots.select{|sg,q|(q[1]-zl).abs<=0.015} if ov.empty?
      merge.(ov.map{|_,q|q.map{|c2|c2.round(3)}})}
     tot=per.sum(&:length)
     if tot==s['n'] then pick=[per,false];break
     elsif tot*2==s['n'] then pick=[per,true];break end
    end
   end
   unless pick
    # son çare: tek sıra (aynı z) yerler adetten biraz farklıysa sıra boyunca eşit aralıkla yeniden dağıt (kesitte eksik çizilmiş çubuk)
    need=s['n'].to_f/occ.length
    if need==need.round
     cands=(srcs.flat_map{|o|secgrp[o].map{|_,ps|ps}}+zlev[pz].uniq.map{|zl|alldots.select{|_,q|(q[1]-zl).abs<=0.015}.map{|_,q|q}})
     cands.each do |ps|
      ps=merge.(ps.map{|q|q.map{|c|c.round(3)}})
      next if ps.length<2 || (ps.map{|q|q[1]}.max-ps.map{|q|q[1]}.min)>0.015 || (ps.length-need).abs>[need*0.2,2].max
      u0,u1=ps.map(&:first).minmax;zz=ps.map(&:last).sum/ps.length
      row=(0...need.to_i).map{|k|[(u0+(u1-u0)*k/[need-1,1].max).round(3),zz.round(3)]}
      pick=[occ.map{row},false];warn << "Poz #{pz}: kesitte #{ps.length} çubuk çizili, tabloda #{need.to_i}/kroki — sıra boyunca eşit dağıtıldı"
      break
     end
    end
   end
   unless pick
    why[pz]=format('boyuna: kesitteki yer sayısı × kroki (%d) ≠ %d adet%s',occ.length,s['n'],zlev[pz].empty? ? '' : " (z #{zlev[pz].uniq.join('/')})");next
   end
   posl,mir=pick
   pos=posl.first
   lp=[]
   occ.each do |c|
    p=c['path'];sg=p.each_cons(2).select{|a,b|(a[1]-b[1]).abs<0.02*Math.hypot(b[0]-a[0],b[1]-a[1])}.max_by{|a,b|(b[0]-a[0]).abs};ym=sg[0][1]
    # boy görünüşündeki aynı boylu çubuk çizgisine hizala (kroki genelde yaklaşık hizada çizilir)
    ml=(sg[1][0]-sg[0][0]).abs;ms=[sg[0][0],sg[1][0]].min
    cand=elr.select{|a,b|((b[0]-a[0]).abs-ml).abs<=0.02*kk && ([a[0],b[0]].min-ms).abs<=0.6*kk}.min_by{|a,b|([a[0],b[0]].min-ms).abs}
    dx=cand ? [cand[0][0],cand[1][0]].min-ms : 0.0
    lo=p.map{|q|q[0]}.min+dx;hi=p.map{|q|q[0]}.max+dx
    dx+=x0+0.05*kk-lo if lo<x0+0.05*kk
    dx-=hi-(x1-0.05*kk) if hi>x1-0.05*kk
    pp=p.map{|q|[u2m.(q[0]+dx-x0),u2m.(q[1]-ym)]}
    ps=posl[occ.index(c)]
    lp << [pp,ps];lp << [pp.map{|v,dz|[lm-v,dz]},ps] if mir
   end
   s['kind']=:long;s['lpaths']=lp
   placed[pz]=format('boyuna · %s yer × %d kroki%s',posl.map(&:length).uniq.join('/'),occ.length,mir ? ' (simetrik)' : '')
   why.delete(pz)
  else
   why[pz]||='kroki kesitte / boy görünüşünde eşleşmedi'
  end
 end
 # --- gruplar
 dv=[-0.045,-0.015,0.015,0.045,-0.03,0.03,0.0]
 zone_poz=Hash.new{|h,k|h[k]=[]}
 sch.select{|s|s['kind']==:trans}.each{|s|zone_poz[s['vs'].first(1)] << s['poz']}
 ti=0
 sch.each do |s|
  pz=s['poz']
  if s['kind']==:long
   seen=Hash.new(0)
   s['lpaths'].each do |pp,pos|
    pos.each do |u,z|
     k=[u.round(2),z.round(2),pp.first[0].round(1)]
     sh=lap[[u.round(2),z.round(2)]].odd? ? 0.034*(u<wm/2 ? 1 : -1) : 0.0
     sgn=(pp.any?{|_,dz|z+dz<0.02} || pp.any?{|_,dz|z+dz>u2m.(hmax)+0.8}) ? -1 : 1   # kroki ters çizilmişse kanca kirişin içine döner
     path=pp.map{|v,dz|[0.0,v.round(4),(z+sgn*dz).round(4)]}
     groups << {'poz'=>pz,'batch'=>1,'label'=>"Poz #{pz} boyuna",'path'=>path,'at'=>[[(u+sh).round(4),0,0]]}
     seen[k]+=1
    end
   end
   s['lpaths'].flat_map{|_,ps|ps}.uniq.each{|u,z|lap[[u.round(2),z.round(2)]]+=1}
  elsif s['kind']==:trans
   off=dv[ti%dv.length];ti+=1
   s['tshapes'].each{|q|groups << {'poz'=>pz,'batch'=>2,'label'=>"Poz #{pz} enine",'path'=>q.map{|u,z|[u.round(4),0.0,z.round(4)]},'at'=>s['vs'].map{|v|[0,(v+off).round(4),0]}}}
  end
 end
 # yerleşmemiş pozlar: tabloda kalır
 drawn=Hash.new(0);groups.each{|g|drawn[g['poz']]+=g['at'].length}
 sch.each{|s|next unless drawn[s['poz']]>0 && drawn[s['poz']]!=s['n'];why[s['poz']]=format('adet %d çizildi / tablo %d',drawn[s['poz']],s['n']);groups.reject!{|g|g['poz']==s['poz']};placed.delete(s['poz'])}
 # profil ve kontrol noktaları (yerel m)
 zones.each do |a,b,(bt,tp,_)|
  next unless tp
  v=u2m.((a+b)/2.0-x0)
  probes << {'u'=>(wm/2).round(3),'v'=>v.round(3),'z'=>u2m.((bt+tp)/2.0-zb).round(3),'solid'=>true}
  probes << {'u'=>(wm/2).round(3),'v'=>v.round(3),'z'=>u2m.(bt-zb-0.05*kk).round(3),'solid'=>false} if bt-zb>0.1*kk
 end
 zmax=groups.flat_map{|g|g['path'].map{|q|q[2]}}.max.to_f
 h=u2m.(hmax)
 prof=zones.map{|a,b,pr|[u2m.(a-x0).round(3),u2m.(b-x0).round(3),pr.map{|x|x.is_a?(Float) ? u2m.(x-zb).round(3) : x}]}
 symm=prof.zip(prof.reverse).all?{|(a,b,p),(c,d,q)|((a-(lm-d)).abs<0.02) && p==q}
 spec={'format'=>'mst-drawing-rebar/1','drawing'=>name,'title'=>"#{name} — paftadan otomatik (#{MST_DRA_VER})",'source'=>'otomatik okuma','auto'=>true,
  'note'=>"Paftadan otomatik kuruldu: #{placed.length}/#{sch.length} poz 3B; diğerleri yalnız metrajda.",'frame'=>'u: genişlik, v: boy (boy görünüşü sol ucu 0), z: kiriş en alt tabanı 0',
  'dims'=>{'L'=>lm.round(3),'W'=>wm.round(3),'H'=>h.round(3),'tol'=>0.08},'symmetric'=>symm,'len_tol'=>0.025,
  'stirrup_poz'=>sch.select{|s|s['kind']==:trans}.map{|s|s['poz']},
  'schedule'=>sch.map{|s|{'poz'=>s['poz'],'d'=>s['d'],'n'=>s['n'],'len'=>s['len'],'shape'=>s['shape']}},
  'groups'=>groups,'probes'=>probes,'batches'=>{'1'=>'Boyuna','2'=>'Enine'},'external'=>[],'external_note'=>'','profile'=>prof}
 spec['stage2_top']=(zmax+0.05).round(3) if zmax>h+0.02
 spec['unplaced']=Hash[why.map{|k,v|[k.to_s,v]}]
 {'spec'=>spec,'placed'=>placed,'why'=>why,'warn'=>warn,'unit'=>kk,'zones'=>prof,'sections'=>secs.length}
end
# paftanın kendi profilinden kutu katı (bölge: v aralığı, taban, üst) → üçgenler; paketi buna göre dener
def mst_dra_profile_solid(spec)
 w=spec['dims']['W'].to_f;tris=[];edges=[]
 quad=->(a,b,c,d){tris << [a,b,c] << [a,c,d];edges << [a,b] << [b,c] << [c,d] << [d,a]}
 spec['profile'].each do |v0,v1,(bt,tp,_)|
  next unless tp
  box=[[0,v0,bt],[w,v0,bt],[w,v1,bt],[0,v1,bt],[0,v0,tp],[w,v0,tp],[w,v1,tp],[0,v1,tp]]
  b=box;quad.(b[0],b[3],b[2],b[1]);quad.(b[4],b[5],b[6],b[7]);quad.(b[0],b[1],b[5],b[4]);quad.(b[1],b[2],b[6],b[5]);quad.(b[2],b[3],b[7],b[6]);quad.(b[3],b[0],b[4],b[7])
 end
 [tris.flatten(1),edges,tris]
end
def mst_dra_selfcheck(spec)
 pl=mst_dr_plan(spec,*mst_dra_profile_solid(spec))
 {'bad'=>pl[:bad].length,'bad_poz'=>pl[:bad].map{|b|b[:poz]}.uniq.sort,'bars'=>pl[:bars].length,'qa_err'=>mst_dr_qa_errors(pl[:qa]).map{|r|r['poz']}}
rescue => e
 {'bad'=>-1,'err'=>e.message}
end
def mst_dra_report(r)
 sp=r['spec'];l=["#{sp['drawing']}: #{sp['dims']['L']} × #{sp['dims']['W']} × #{sp['dims']['H']} m · birim 1/#{r['unit'].round} m · bölge #{r['zones'].length} · kesit #{r['sections']}"]
 sp['schedule'].each do |s|
  l << format('  %3d Ø%-2d %4d × %6.2f  %s',s['poz'],s['d'],s['n'],s['len'],r['placed'][s['poz']] || "— #{r['why'][s['poz']]}")
 end
 l << "  UYARI: #{r['warn'].join('; ')}" unless r['warn'].empty?
 l.join("\n")
end

# ---------------------------------------------------------------- BK'ya uygula
# betona sığmayan pozları (bu BK'nın gerçek katısında) paketten çıkar: tablo metrajında kalır
def mst_dra_fit(spec,pts,edges,tris,why={})
 pl=mst_dr_plan(spec,pts,edges,tris)
 3.times do
  break if pl[:bad].empty? || !pl[:dims_ok] || !pl[:probes_ok]
  bp=pl[:bad].map{|b|b[:poz]}.uniq
  spec=spec.merge('groups'=>spec['groups'].reject{|g|bp.include?(g['poz'])})
  bp.each{|p|why[p]='bu BK\'nın katısına sığmadı (yalnız metraj)'}
  spec['unplaced']=(spec['unplaced'] || {}).merge(Hash[bp.map{|p|[p.to_s,why[p]]}])
  pl=mst_dr_plan(spec,pts,edges,tris)
 end
 [spec,pl]
end
def mst_dra_elem_dims(e)
 [e.get_attribute(DICT,'length_m',0).to_f,e.get_attribute(DICT,'width_m',0).to_f,e.get_attribute(DICT,'height_m',0).to_f]
end
def mst_dra_ui(path=nil)
 model=Sketchup.active_model
 sel=model.selection.to_a.select{|x|x.respond_to?(:get_attribute) && x.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise 'Önce donatısı çizilecek Başlık Kirişi(ni) seçin (aynı tipteki birden çok BK seçilebilir).' if sel.empty?
 sel.each{|e|why=mst_dr_supported_reason(e);raise "#{element_visible_id(e)}: #{why}" if why}
 path||=UI.openpanel('BK donatı paftası (DXF)',nil,'DXF|*.dxf||')
 return 0 unless path && File.file?(path)
 t0=Time.now
 fl=mst_dxf_flatten(mst_dxf_read(path))
 ds=mst_dra_details(fl)
 ds=[{'name'=>File.basename(path,'.*')[0,24],'title'=>File.basename(path),'x'=>0,'y'=>0,'h'=>10.0,'frame'=>nil,'all'=>true}] if ds.empty?
 d=ds.first
 if ds.length>1
  ed=mst_dra_elem_dims(sel.first)
  ds=ds.sort_by{|x|x['name']}
  r=UI.inputbox(['Paftadaki kiriş'],[ds.first['name']],[ds.map{|x|x['name']}.join('|')],"Paftadan 3B Donatı — #{File.basename(path)} (#{ed.map{|v|format('%.2f',v)}.join(' × ')} m)")
  return 0 unless r
  d=ds.find{|x|x['name']==r[0]} || ds.first
 end
 reg=d['all'] ? fl : mst_dra_region(fl,d)
 res=mst_dra_build(reg,"#{d['name']} · #{File.basename(path,'.*')}")
 spec=res['spec']
 plans=sel.map do |e|
  pts,edges,tris=mst_dr_geometry(e)
  sp2,pl=mst_dra_fit(spec,pts,edges,tris,res['why'])
  [e,sp2,pl]
 end
 e0,sp0,pl0=plans.first
 bl=mst_dr_blockers(pl0,sp0)
 txt=[mst_dra_report(res),'',mst_dr_text(element_visible_id(e0),sp0,pl0)]
 plans.drop(1).each{|e,sp2,pl|txt << format('%s: taşan %d · %s',element_visible_id(e),pl[:bad].length,mst_dr_blockers(pl,sp2).empty? ? 'çizilebilir' : 'UYMUYOR')}
 txt << format('(okuma + kurulum %.1f s)',Time.now-t0)
 txt=txt.join("\n");puts txt
 unless bl.empty?
  UI.messagebox("#{txt[0,2400]}\n\nÇİZİLMEDİ:\n#{bl.join("\n")}")
  return 0
 end
 ok=plans.select{|e,sp2,pl|mst_dr_blockers(pl,sp2).empty?}
 return 0 unless UI.messagebox("#{txt[0,2800]}\n\n#{ok.length} BK'ya 3B donatı çizilsin mi? Paket modele kaydedilir (aynı tipteki diğer BK'lar Çizimden Donatı ile kullanabilir). Tonaj pafta tablosundan. (tek Geri Al)",MB_YESNO)==IDYES
 model.start_operation("MST Paftadan 3B Donatı (#{d['name']})",true)
 begin
  mst_dr_model_store!(spec,model)
  ok.each{|e,sp2,pl|mst_dr_draw!(e,sp2,pl)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 send_boq(@d) if @d rescue nil
 UI.messagebox(format("%d BK'ya %d çubuk çizildi (%d/%d poz 3B).\nBOQ / hakediş donatısı: %.3f t / BK (pafta tablosu).%s",ok.length,ok.sum{|_,_,pl|pl[:bars].length},res['placed'].length,spec['schedule'].length,pl0[:sched_kg]/1000.0,(respond_to?(:mst_rt_visible_note) ? mst_rt_visible_note : '')))
 ok.length
rescue => ex
 UI.messagebox("Paftadan 3B donatı: #{ex.message}")
 0
end

end
end
