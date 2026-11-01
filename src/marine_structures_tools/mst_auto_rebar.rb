# frozen_string_literal: true
# v0.48 AR1 — Otomatik donatı: kanallı / boşluklu (eklenti dışı tanıtılan) BK'da proje çizimi olmadan.
#  1) BK'nın gerçek yüzeylerinden 5 cm ızgaralı kot haritası (alt / üst) çıkarılır.
#  2) Bölgeler kendiliğinden tanınır: alt döşeme, kanal tabanları, geniş bloklar, ince duvarlar ve başlıkları,
#     basamak (kanal kenarı) yüzleri, dış yüzler.
#  3) Kurallar (BK-9 projesinden): alt ağ + enine kapalı etriye çifti, ara ağ, her açık üst yüzeyde iki yönlü ağ
#     (yüksek betona kenetlenir, kenarda U bacak), kanal kenarında C, dış yüzlerde C + gövde, duvarlarda etriye + yatay + filiz.
#  4) 12 m stok boyu (bindirme 60Ø), çakışma giderme, her çubuk betonun içinde mi kontrolü; sığmayan çubuk çizilmez.
# Tonaj: çizilen 3B çubuklar (Ø²/162 × boy). Çizim mst_dwg_rebar.rb motoruyla (poz grupları, Component tanımları, tek Geri Al).
require 'json'
module MAG
module MarineStructuresTools

MST_AR_MODE='auto_detail'
MST_AR_DRAWING='OTOMATİK'
MST_AR_DEFAULTS={'cover_mm'=>60.0,'bot_d'=>32.0,'bot_s'=>150.0,'mid_d'=>14.0,'mid_s'=>150.0,'top_d'=>32.0,'top_s'=>150.0,
 'side_d'=>32.0,'side_s'=>150.0,'edge_d'=>32.0,'edge_s'=>150.0,'wall_d'=>14.0,'wall_s'=>150.0,'stock_m'=>12.0,
 'lap_d'=>50.0,'stir_legs'=>0.0,'stir_d'=>16.0,'stir_s'=>150.0}.freeze
MST_AR_FIELDS=[['cover_mm','Pas payı (net, mm)',25,120],['bot_d','Alt ağ Ø (boyuna + enine U)',10,40],['bot_s','Alt ağ aralık (mm)',75,400],
 ['mid_d','Ara ağ Ø (ara boyuna + ters U)',8,32],['mid_s','Ara ağ aralık (mm)',75,400],['top_d','Üst ağlar Ø (blok üstü, kanal tabanı)',10,40],
 ['top_s','Üst ağlar aralık (mm)',75,400],['side_d','Dış yüz Ø (C + gövde)',10,40],['side_s','Dış yüz aralık (mm)',75,400],
 ['edge_d','Kanal kenarı C Ø',10,40],['edge_s','Kanal kenarı aralık (mm)',75,400],['wall_d','İnce duvar Ø (etriye, yatay, filiz)',8,32],
 ['wall_s','İnce duvar aralık (mm)',75,400],['stock_m','Çubuk stok boyu (m)',6,18],['lap_d','Bindirme boyu (×Ø, şaşırtmalı)',30,80],
 ['stir_legs','İç içe etriye kol sayısı (0 = yok; 2, 4, 6…)',0,12],['stir_d','Etriye Ø',8,32],['stir_s','Etriye aralık (mm)',75,400]].freeze
MST_AR_ZONES=['Alt ağ','Ara ağ','Üst ağ','Kanal kenarı','Dış yüz','Gövde','Duvar','Etriye'].freeze

def mst_ar_params(h=nil)
 p=MST_AR_DEFAULTS.dup
 # v0.49 RS1: proje donatı ayarları (BK pas payı, bindirme ×Ø) varsayılanı belirler; BK'da kayıtlı değer önce gelir
 if respond_to?(:mst_rs_get)
  p['cover_mm']=mst_rs_get('cover_bk_mm').to_f;p['lap_d']=mst_rs_get('lap_d').to_f
 end
 (h || {}).each{|k,v|p[k.to_s]=v.to_f if p.key?(k.to_s)}
 p
end

# ---------------------------------------------------------------- çerçeve (ölçü bilinmiyor: en küçük alanlı dik kutu)
def mst_ar_frame(pts,edges)
 bins=Hash.new(0.0);hz=[]
 edges.each do |a,b|
  dx=b[0]-a[0];dy=b[1]-a[1];dz=b[2]-a[2];l=Math.sqrt(dx*dx+dy*dy)
  next if l<0.05 || dz.abs>1e-4*[l,1].max
  t=Math.atan2(dy,dx)%Math::PI;bins[((t/Math::PI*360).round)%360]+=l;hz << [t,l]
 end
 raise 'Yatay kenar bulunamadı (eleman katı değil mi?)' if bins.empty?
 refine=lambda do |t0|
  sx=0.0;sy=0.0
  hz.each{|t,l|d=((t-t0+Math::PI/2)%Math::PI)-Math::PI/2;next if d.abs>Math::PI/180;sx+=l*Math.cos(2*t);sy+=l*Math.sin(2*t)}
  sx.abs+sy.abs<1e-12 ? t0 : Math.atan2(sy,sx)/2
 end
 best=nil
 bins.sort_by{|_,l|-l}.first(3).map{|k,_|refine.(k*Math::PI/360)}.each do |t|
  ev=[Math.cos(t),Math.sin(t),0.0];eu=[ev[1],-ev[0],0.0]
  us=pts.map{|p|p[0]*eu[0]+p[1]*eu[1]};vs=pts.map{|p|p[0]*ev[0]+p[1]*ev[1]};zs=pts.map{|p|p[2]}
  w=us.max-us.min;l=vs.max-vs.min
  if w>l   # boy ekseni her zaman v
   eu,ev=[-ev[0],-ev[1],0.0],eu
   us=pts.map{|p|p[0]*eu[0]+p[1]*eu[1]};vs=pts.map{|p|p[0]*ev[0]+p[1]*ev[1]};w,l=l,w
  end
  fr={'eu'=>eu,'ev'=>ev,'o'=>[us.min,vs.min,zs.min],'W'=>w,'L'=>l,'H'=>zs.max-zs.min,'area'=>w*l}
  best=fr if best.nil? || fr['area']<best['area']-1e-9
 end
 best
end
def mst_ar_to_local(fr,p)
 eu,ev=fr['eu'],fr['ev'];ou,ov,oz=fr['o']
 [p[0]*eu[0]+p[1]*eu[1]-ou,p[0]*ev[0]+p[1]*ev[1]-ov,p[2]-oz]
end

# ---------------------------------------------------------------- kot haritası
def mst_ar_heightfield(tris,fr,g=0.05)
 lt=tris.map{|t|t.map{|p|mst_ar_to_local(fr,p)}}
 idx=mst_dr_index(lt)
 nu=(fr['W']/g-1e-6).ceil;nv=(fr['L']/g-1e-6).ceil
 top=Array.new(nu){Array.new(nv)};bot=Array.new(nu){Array.new(nv)};multi=0
 nu.times do |i|
  x=(i+0.5)*g+1.37e-6
  nv.times do |j|
   y=(j+0.5)*g+2.11e-6
   zs=[]
   (idx[:grid].fetch([(x/idx[:cell]).floor,(y/idx[:cell]).floor],nil) || []).each do |k|
    a,b,c,den=idx[:items][k]
    l1=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/den
    next if l1<0 || l1>1
    l2=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/den
    next if l2<0 || l1+l2>1
    zs << l1*a[2]+l2*b[2]+(1-l1-l2)*c[2]
   end
   zs=zs.sort.each_with_object([]){|z,o|o << z if o.empty? || z-o[-1]>1e-6}
   next if zs.length<2
   multi+=1 if zs.length>2
   bot[i][j]=zs.first;top[i][j]=zs.last
  end
 end
 {g:g,nu:nu,nv:nv,top:top,bot:bot,multi:multi,W:fr['W'],L:fr['L'],idx:idx}
end

# bölgeler: kotlar, ince (duvar) hücreler, alt kot
def mst_ar_analyze(hf)
 nu,nv,top=hf[:nu],hf[:nv],hf[:top];g=hf[:g]
 cells=[];nu.times{|i|nv.times{|j|cells << top[i][j] if top[i][j]}}
 raise 'Kot haritası boş.' if cells.empty?
 levels=[];cells.map{|t|t.round(3)}.uniq.sort.each{|t|levels << t if levels.empty? || t-levels[-1]>0.02}
 bots=[];nu.times{|i|nv.times{|j|bots << hf[:bot][i][j] if hf[:bot][i][j]}}
 z0=bots.min;lmin=cells.min;zmax=cells.max
 lv=->(t){levels.min_by{|l|(l-t).abs}}
 # her kot için "o kot ve üstü" maskesinde u / v yönlü kesintisiz boylar
 urun={};vrun={}
 levels.each do |l|
  ur=Array.new(nu){Array.new(nv,0.0)};vr=Array.new(nu){Array.new(nv,0.0)}
  nv.times do |j|
   i=0
   while i<nu
    if top[i][j] && top[i][j]>=l-0.01
     k=i;k+=1 while k<nu && top[k][j] && top[k][j]>=l-0.01
     (i...k).each{|m|ur[m][j]=(k-i)*g};i=k
    else i+=1 end
   end
  end
  nu.times do |i|
   j=0
   while j<nv
    if top[i][j] && top[i][j]>=l-0.01
     k=j;k+=1 while k<nv && top[i][k] && top[i][k]>=l-0.01
     (j...k).each{|m|vr[i][m]=(k-j)*g};j=k
    else j+=1 end
   end
  end
  urun[l]=ur;vrun[l]=vr
 end
 # geniş = 0.6 × 0.6 m'lik bir kare tamamen o kotta / üstünde kalabiliyor (açma: aşındır + genişlet; önek toplamlarıyla)
 r=(0.6/g).round
 wide={}
 levels.each do |l|
  m=Array.new(nu){|i|Array.new(nv){|j|top[i][j] && top[i][j]>=l-0.01 ? 1 : 0}}
  ps=mst_ar_prefix(m,nu,nv)
  er=Array.new(nu){|i|Array.new(nv){|j|i+r<=nu && j+r<=nv && mst_ar_box(ps,i,j,i+r,j+r)==r*r ? 1 : 0}}   # sol-alt köşesi (i, j) olan kare
  pe=mst_ar_prefix(er,nu,nv)
  wide[l]=Array.new(nu){|i|Array.new(nv){|j|mst_ar_box(pe,[i-r+1,0].max,[j-r+1,0].max,i+1,j+1)>0}}
 end
 thin=Array.new(nu){Array.new(nv,false)};tu=Array.new(nu){Array.new(nv,false)};tv=Array.new(nu){Array.new(nv,false)}
 nu.times do |i|
  nv.times do |j|
   t=top[i][j];next unless t && t>lmin+0.25
   l=lv.(t);next if wide[l][i][j]
   a=urun[l][i][j];b=vrun[l][i][j]
   thin[i][j]=true
   if a<0.6 || b<0.6 then tu[i][j]=a<0.6;tv[i][j]=b<0.6
   else (a<=b ? tu : tv)[i][j]=true end      # duvar birleşim köşesi: kısa yöndeki duvara
  end
 end
 full=cells.length==nu*nv
 {z0:z0,lmin:lmin,zmax:zmax,levels:levels,thin:thin,tu:tu,tv:tv,urun:urun,vrun:vrun,rect:full,
  bottom_flat:(bots.max-bots.min)<0.03,multi:hf[:multi]}
end

# ---------------------------------------------------------------- yardımcılar
def mst_ar_prefix(m,nu,nv)
 ps=Array.new(nu+1){Array.new(nv+1,0)}
 nu.times{|i|row=0;nv.times{|j|row+=m[i][j];ps[i+1][j+1]=ps[i][j+1]+row}}
 ps
end
def mst_ar_box(ps,i0,j0,i1,j1);ps[i1][j1]-ps[i0][j1]-ps[i1][j0]+ps[i0][j0];end
def mst_ar_lin(a,b,s)
 return [] if b<a-1e-9
 n=((b-a)/s+1e-6).floor+1
 n==1 ? [(a+b)/2.0] : (0...n).map{|k|a+(b-a)*k/(n-1).to_f}
end
def mst_ar_cell(hf,u,v)
 i=(u/hf[:g]).floor;j=(v/hf[:g]).floor
 return nil if i<0 || j<0 || i>=hf[:nu] || j>=hf[:nv]
 [i,j]
end
def mst_ar_top(hf,u,v);c=mst_ar_cell(hf,u,v);c ? hf[:top][c[0]][c[1]] : nil;end
# düz çubuk (eksen ax: 0 = u, 1 = v) s → e, sabit diğer koordinat c, kot z; uç kancaları [h_s, h_e] (+ yukarı, − aşağı)
# stok boyunu aşarsa parçalara böler; bindirme lap_d × Ø (v0.49: varsayılan 50Ø), ikinci parça yanal d kadar kaydırılır
# off: bindirmedeki ikinci parçanın kayma vektörü [du, dv, dz] (komşuya / içeri doğru)
# v0.49 LP1 şaşırtma: aynı katmandaki (eksen, kot, Ø) komşu çubuklarda ilk parça sırayla tam / (stok − 1.3 × bindirme) boyu —
# bindirmeler aynı kesitte toplanmaz (bir kesitte çubukların en çok yarısı eklenir).
def mst_ar_straight(ax,s,e,c,z,d,stock,hooks=[0.0,0.0],off=nil)
 dm=d/1000.0;lap=(@mst_ar_lap_d || 50.0)*dm;out=[]
 sk=[ax,(z*200).round,d.round];@mst_ar_stag ||= Hash.new(0);odd=(@mst_ar_stag[sk]+=1).even? && @mst_ar_stagger!=false
 off ||= ax==1 ? [dm,0.0,0.0] : [0.0,dm,0.0]
 pt=->(along,lat,zz){q=ax==1 ? [c,along,zz] : [along,c,zz];lat ? [q[0]+off[0],q[1]+off[1],q[2]+off[2]] : q}
 cur=s;k=0
 loop do
  hs=(k==0 ? hooks[0].abs : 0.0)
  rest=e-cur+hooks[1].abs
  last=hs+rest<=stock+1e-9
  first=(k==0 && odd) ? stock-1.3*lap : stock   # şaşırtmalı: komşu çizgide ekler 1.3 × bindirme kaydırılır (TS EN 1992-1-1 8.7.2: aynı kesitte en çok %50)
  pe=last ? e : [cur+(first-hs),e-(lap+0.3)].min   # sonraki parça en az bindirme + 30 cm (stok boyunu aşmaz, e'yi geçmez)
  lat=k.odd?
  p=[]
  p << pt.(cur,lat,z+hooks[0]) if k==0 && hooks[0].abs>1e-6
  p << pt.(cur,lat,z) << pt.(pe,lat,z)
  p << pt.(pe,lat,z+hooks[1]) if last && hooks[1].abs>1e-6
  out << p
  break if last || pe-lap<=cur+lap
  cur=pe-lap;k+=1
 end
 out
end

# ---------------------------------------------------------------- kurallar → çubuklar (yerel u, v, z)
def mst_ar_plan_bars(hf,an,prm)
 bars=[];g=hf[:g];w=hf[:W];ll=hf[:L];stock=prm['stock_m']
 @mst_ar_lap_d=prm['lap_d'];@mst_ar_stag=Hash.new(0);@mst_ar_stagger=(respond_to?(:mst_rs_get) ? mst_rs_get('stagger').to_i!=0 : true)
 cov=prm['cover_mm']/1000.0
 stir_on=mst_ar_stirrups_ok?(an,prm)
 cov+=prm['stir_d']/1000.0 if stir_on   # v0.49 ET1: etriye en dışta (pas payında), diğer çubuklar etriyenin içinde
 cc=->(d){cov+d/2000.0}
 add=lambda do |zone,d,pts,ax|
  l=mst_dr_len(pts);next if l<0.3
  bars << {zone:zone,d:d,pts:pts,len:l,ax:ax}
 end
 z0=an[:z0];lmin=an[:lmin]
 db,dm,dt,ds,de,dw=%w[bot_d mid_d top_d side_d edge_d wall_d].map{|k|prm[k]}
 zb=z0+cc.(db)                                     # alt enine U yatayı
 zm=[z0+0.625*(lmin-z0),lmin-0.30].min             # ara ağ / ters U kotu
 zm=[zm,zb+0.25].max
 # ---- 1. alt ağ: enine U çifti, alt boyuna, ara boyuna
 cb=cc.(db);cm=cc.(dm)
 vpos=mst_ar_lin(cb,ll-cb,prm['bot_s']/1000.0)
 vpos.each_with_index do |v,k|
  add.('Alt ağ',db,[[cb,v,zm],[cb,v,zb],[w-cb,v,zb],[w-cb,v,zm]],1)
  vv=v+(k==0 ? 0.06 : k==vpos.length-1 ? -0.06 : k<vpos.length/2 ? 0.025 : -0.025)   # uçtakiler uç yüz C'sinin içinde
  add.('Ara ağ',dm,[[cb,vv,zb],[cb,vv,zm],[w-cb,vv,zm],[w-cb,vv,zb]],1)
 end
 ul=cb+db/1000.0;zl=zb+db/1000.0
 upos=mst_ar_lin(ul,w-ul,prm['bot_s']/1000.0)
 hb=[17*db/1000.0,zm-zl].min
 upos.each{|u|mst_ar_straight(1,cb,ll-cb,u,zl,db,stock,[hb,hb],[(u<w/2 ? 1 : -1)*db/1000.0,0,0]).each{|p|add.('Alt ağ',db,p,0)}}
 zmm=zm-dm/1000.0;hm=-[0.55,zmm-(zl+db/1000.0+0.035)].min   # kanca ucu dış C ayağının (alt boyunanın 1 Ø üstü) üstünde
 mend=cc.(prm['side_d'])+db/1000.0+prm['side_d']/1000.0+0.045   # uçlarda gövde çubuklarının içinde
 mst_ar_lin(ul,w-ul,prm['mid_s']/1000.0).each_with_index do |u,k|
  uu=u+(k.even? ? 0.04 : -0.04);uu=u if uu<ul || uu>w-ul
  uu=ul+0.075 if k==0;uu=w-ul-0.075 if u>w-ul-1e-6   # kenardakiler gövde çubuklarından uzak
  mst_ar_straight(1,mend,ll-mend,uu,zmm,dm,stock,[hm,hm],[(uu<w/2 ? 1 : -1)*dm/1000.0,0,0]).each{|p|add.('Ara ağ',dm,p,0)}
 end
 # ---- 2. açık üst yüzey ağları (her kot): boyuna (alt kat) + enine (üst kat)
 walls=mst_ar_walls(hf,an)
 cwd0=cc.(dw)
 legs_u=walls.select{|x|x[:ax]==1}.flat_map{|x|h=x[:t]/2.0-cwd0;[x[:c]-h,x[:c]+h]}   # v boyunca duvarların etriye bacakları (u)
 legs_v=walls.select{|x|x[:ax]==0}.flat_map{|x|h=x[:t]/2.0-cwd0;[x[:c]-h,x[:c]+h]}
 near=->(x,arr){arr.any?{|y|(x-y).abs<0.045}}
 ex=->(i,j,l){t=hf[:top][i][j];t && (t-l).abs<0.011 && !an[:thin][i][j]}
 an[:levels].each do |l|
  next if l<=z0+0.3
  ztt=l-cc.(dt);ztl=ztt-dt/1000.0;ct=cc.(dt)
  hook_d=-[17*dt/1000.0,ztl-(zm+dm/1000.0+0.05)].min
  # boyuna (v yönü)
  mu=[ct+2*dt/1000.0,cc.(ds)+db/1000.0+ds/1000.0].max   # boyuna çubuk: enine U bacağının, kanal kenarı ve dış yüz C'lerinin içinde
  mst_ar_lin(mu,w-mu,prm['top_s']/1000.0).each do |u|
   next if near.(u,legs_u)
   ok=lambda do |j|   # bu v hücresinde u ± pas açık mı
    [u-mu,u,u+mu].all?{|x|c=mst_ar_cell(hf,x,(j+0.5)*g);c && hf[:top][c[0]][c[1]] && hf[:top][c[0]][c[1]]>=l-0.011} &&
     [u,u-0.06,u+0.06].any?{|x|(c=mst_ar_cell(hf,x,(j+0.5)*g)) && ex.(c[0],c[1],l)}   # açık yüzeye 6 cm yakın çizgi de (kanal kenarı C düşeyine değmez)
   end
   runs=mst_ar_runs(hf,hf[:nv]){|j|ok.(j)}
   segs=mst_ar_extend(runs,hf[:nv],g,60*dt/1000.0){|j|c=mst_ar_cell(hf,u,(j+0.5)*g);c && hf[:top][c[0]][c[1]] && hf[:top][c[0]][c[1]]>l+0.011}
   segs.each do |a,b,ea,eb|
    s=a+(ea==:edge || ea==:drop ? ct : 0);e=b-(eb==:edge || eb==:drop ? ct : 0)
    next if e-s<0.8
    mst_ar_straight(1,s,e,u,ztl,dt,stock,[ea==:edge ? hook_d : 0.0,eb==:edge ? hook_d : 0.0],[(u<w/2 ? 1 : -1)*dt/1000.0,0,0]).each{|p|add.('Üst ağ',dt,p,0)}
   end
  end
  # enine (u yönü)
  mv=[ct+dt/1000.0,cc.(ds)+db/1000.0+ds/1000.0].max   # enine çubuk: boyuna kancaların ve uç yüz C düşeylerinin içinde
  mst_ar_lin(mv,ll-mv,prm['top_s']/1000.0).each do |v|
   next if near.(v,legs_v)
   ok=lambda do |i|
    [v-mv,v,v+mv].all?{|y|c=mst_ar_cell(hf,(i+0.5)*g,y);c && hf[:top][c[0]][c[1]] && hf[:top][c[0]][c[1]]>=l-0.011} &&
     [v,v-0.06,v+0.06].any?{|y|(c=mst_ar_cell(hf,(i+0.5)*g,y)) && ex.(c[0],c[1],l)}
   end
   runs=mst_ar_runs(hf,hf[:nu]){|i|ok.(i)}
   segs=mst_ar_extend(runs,hf[:nu],g,30*dt/1000.0){|i|c=mst_ar_cell(hf,(i+0.5)*g,v);c && hf[:top][c[0]][c[1]] && hf[:top][c[0]][c[1]]>l+0.011}
   segs.each do |a,b,ea,eb|
    s=a+(ea==:edge || ea==:drop ? ct : 0);e=b-(eb==:edge || eb==:drop ? ct : 0)
    next if e-s<0.8
    leg=->(kind){kind==:edge || kind==:drop ? -[0.60,ztt-(zm+dm/1000.0+0.05)].min : 0.0}
    mst_ar_straight(0,s,e,v,ztt,dt,stock,[leg.(ea),leg.(eb)],[0,(v<ll/2 ? 1 : -1)*dt/1000.0,0]).each{|p|add.('Üst ağ',dt,p,1)}
   end
  end
 end
 # ---- 3. kanal kenarı (basamak) C çubukları
 mst_ar_steps(hf,an).each do |st|
  hi,lo=st[:hi],st[:lo];c=cc.(de);dd=de/1000.0
  zf=[lo-0.275,zm+dm/1000.0+dd+0.03].max
  next if st[:b]-st[:a]<0.7
  mst_ar_lin(st[:a]+0.25,st[:b]-0.25,prm['edge_s']/1000.0).each do |q|   # köşelerden (dik yüzlerin C'leri) uzak
   f=st[:face];sg=st[:hi_side]      # sg = -1: yüksek taraf f'nin küçük tarafında
   n=->(x){f+sg*x}
   loc=st[:ax]==0 ? ->(nn,zz){[n.(nn),q+0.05,zz]} : ->(nn,zz){[q+0.05,n.(nn),zz]}
   nn=cc.(dt)+dt/1000.0           # üst ağ U bacağının içinde
   zt=hi-cc.(dt)-dt/1000.0-dd     # üst ağın iki katının altında
   zt-=dd if st[:ax]==1             # iç köşede dik yüzün C'sinin altında
   zf2=zf+(st[:ax]==1 ? dd : 0.0)
   add.('Kanal kenarı',de,[loc.(0.75,zt),loc.(nn,zt),loc.(nn,zf2),loc.(nn+0.30,zf2)],st[:ax]==0 ? 1 : 0)
  end
  # kanal yüzü yatay çubukları (BK-9 poz 6 / 30 / 39 / 40): C düşeylerinin içinde, kanal tabanından üst ağın altına
  dwy=dw/1000.0
  inn=cc.(dt)+dt/1000.0+dd/2+dwy/2
  zs=mst_ar_lin(lo+0.034,hi-0.216,prm['wall_s']/1000.0)
  f=st[:face];sg=st[:hi_side]
  zs.each do |z|
   mst_ar_straight(st[:ax]==0 ? 1 : 0,st[:a]+0.10,st[:b]-0.10,f+sg*inn,z,dw,stock,[0.0,0.0],st[:ax]==0 ? [sg*dwy,0,0] : [0,sg*dwy,0]).each{|p|add.('Kanal kenarı',dw,p,2)}
  end
 end
 # ---- 4. dış yüzler: C (üstten alta) + gövde (yatay)
 csd=cc.(ds);dsd=ds/1000.0;zfoot=zl+db/1000.0
 sides=[[0,0.0,1],[0,w,-1],[1,0.0,1],[1,ll,-1]]   # [yüz normali ekseni, yüz konumu, içeri yön]
 sides.each do |ax,f,inw|
  span=ax==0 ? ll : w
  mst_ar_lin(0.25,span-0.25,prm['side_s']/1000.0).each do |q|   # köşelerde dik yüzün C'leriyle çakışmasın
   uv=->(nn){ax==0 ? [f+inw*nn,q] : [q,f+inw*nn]}
   next if ax==0 && stir_on   # v0.49 ET1: etriyeli kesitte uzun yüz C'leri yerine etriye
   cq=mst_ar_cell(hf,*uv.(0.01));next unless cq && hf[:top][cq[0]][cq[1]]
   next if an[:thin][cq[0]][cq[1]]                     # ince duvar ucu: duvar etriyeleri var
   mq=csd+0.03                                          # C düzlemi pas payı kadar komşu kotlara da sığmalı
   ts=[-mq,0.0,mq].map{|o|ax==0 ? mst_ar_top(hf,f+inw*0.01,q+o) : mst_ar_top(hf,q+o,f+inw*0.01)}
   next if ts.any?(&:nil?)
   t=ts.min
   # içeri doğru aynı kotta kalınan boy (üst kol)
   r=0.0;r+=g while r<1.0 && (tt=mst_ar_top(hf,*uv.(r+g/2))) && tt>=t-0.011
   nC=csd+db/1000.0                       # alt / üst U bacaklarının içinde
   zt=t-cc.(dt)-dt/1000.0-dsd             # üst ağın iki katının altında
   zt-=dsd if ax==1                       # uç yüzlerde: köşede yan yüz C'sinin altında
   zf2=zfoot+(ax==1 ? dsd : 0.0)
   arm=[0.75,r-nC-0.05].min
   pt=->(nn,zz){a=uv.(nn);[a[0],a[1],zz]}
   p=[];p << pt.(arm,zt) if arm>=0.2
   p << pt.(nC,zt) << pt.(nC,zf2) << pt.(nC+0.5,zf2)
   add.('Dış yüz',ds,p,ax==0 ? 1 : 0)
  end
  # gövde: alt döşeme ve üst bölge kotları (ara ağdan ve kanal tabanı ağından uzak)
  zs=mst_ar_lin(zb+0.195,an[:zmax]-0.26,prm['side_s']/1000.0).reject{|z|(z-zm).abs<0.12}
  ins=csd+db/1000.0+dsd        # dış C düşeyinin içinde
  zs.each do |z|
   runs=mst_ar_runs(hf,ax==0 ? hf[:nv] : hf[:nu]) do |k|
    q=(k+0.5)*g;a=ax==0 ? [f+inw*0.01,q] : [q,f+inw*0.01];t=mst_ar_top(hf,*a);t && t>=z+0.26
   end
   runs.each do |a,b|
    s=a*g+ins+dsd;e=b*g-ins-dsd
    s=[s,ins+dsd].max;e=[e,span-ins-dsd].min;next if e-s<1.0
    mst_ar_straight(ax==0 ? 1 : 0,s,e,f+inw*ins,z,ds,stock,[0.0,0.0],ax==0 ? [inw*dsd,0,0] : [0,inw*dsd,0]).each{|p|add.('Gövde',ds,p,2)}
   end
  end
 end
 # ---- 5. ince duvarlar: etriye (2 C), yatay (iki yüz), başlıkta üst çubuk + filiz
 mst_ar_walls(hf,an).each do |wl|
  cwd=cc.(dw);ddw=dw/1000.0;t=wl[:t];uc=wl[:c];top=wl[:top]
  half=t/2.0-cwd;next if half<0.03
  a=wl[:a]+cwd+0.05;b=wl[:b]-cwd-0.05
  # aynı aralıkta ise etriyeler (2 C + filiz, 6 cm) kanal tabanı ağının iki çubuğu arasına
  sw=prm['wall_s']/1000.0;stt=prm['top_s']/1000.0;ctt=cc.(dt)
  grid=wl[:ax]==1 ? mst_ar_lin(ctt+dt/1000.0,ll-ctt-dt/1000.0,stt) : mst_ar_lin(ctt+2*dt/1000.0,w-ctt-2*dt/1000.0,stt)
  pos=if (sw-stt).abs<1e-6
   grid.each_cons(2).map{|x,y|(x+y)/2.0-0.03}.select{|q|q>=a-1e-9 && q<=b+1e-9}
  else mst_ar_lin(a,b,sw) end
  pos=pos.reject{|q|wl[:skip].any?{|s0,s1|q>s0-0.05 && q<s1+0.05}}
  pt=wl[:ax]==1 ? ->(n,q,z){[uc+n,q,z]} : ->(n,q,z){[q,uc+n,z]}
  zfw=lmin-0.30;zt=top-cwd
  pos.each do |q|
   add.('Duvar',dw,[pt.(half-0.15,q,zfw),pt.(-half,q,zfw),pt.(-half,q,zt),pt.(half,q,zt)],wl[:ax])
   add.('Duvar',dw,[pt.(-half+0.15,q+0.03,zfw),pt.(half,q+0.03,zfw),pt.(half,q+0.03,zt),pt.(-half,q+0.03,zt)],wl[:ax])
   if wl[:kerb]
    k=wl[:kerb];add.('Duvar',dw,[pt.(k[:c]-uc,q+0.06,top-0.645),pt.(k[:c]-uc,q+0.06,k[:top]-cwd-0.02),pt.(k[:c]-uc+0.05,q+0.06,k[:top]-cwd-0.02)],wl[:ax])
   end
  end
  hz=mst_ar_lin(lmin+0.05,top-cwd-ddw-0.08,prm['wall_s']/1000.0)
  [-1,1].each do |sg|
   hz.each{|z|mst_ar_straight(wl[:ax],wl[:a]+cwd,wl[:b]-cwd,uc+sg*(half-ddw),z,dw,stock,[0.0,0.0],wl[:ax]==1 ? [-sg*ddw,0,0] : [0,-sg*ddw,0]).each{|p|add.('Duvar',dw,p,2)}}
  end
  if wl[:kerb]
   k=wl[:kerb];mst_ar_straight(wl[:ax],k[:a]+cwd,k[:b]-cwd,k[:c],k[:top]-cwd,dw,stock,[0.0,0.0],[0,0,-ddw]).each{|p|add.('Duvar',dw,p,0)}
  end
 end
 # ---- 6. v0.49 ET1 iç içe kapalı etriyeler (kol sayısı n: dış etriye + n/2−1 iç etriye, kollar eşit aralıklı)
 # etriye düzlemleri alt U çiftlerinin arasında (aralık ≈ etriye aralığı); iç etriyeler bir Ø yanda
 mids=stir_on ? vpos.each_cons(2).map{|a,b|(a+b)/2.0} : [];k=[(prm['stir_s']/prm['bot_s']+1e-9).floor,1].max   # gerçek aralık ≤ istenen
 mst_ar_stirrups(hf,an,prm,mids.each_with_index.select{|_,i|i%k==0}.map(&:first)).each{|p|bars << {zone:'Etriye',d:prm['stir_d'],pts:p,len:mst_dr_len(p),ax:1,stir:true}}
 bars.each{|b|b[:stir]=true if b[:zone]=='Duvar' && b[:pts].length>=4}
 bars
end

# v0.49 ET1 — iç içe etriyeler. Her v kesitinde dış etriye pas payında, iç etriyeler aynı kotlarda daha dar;
# n kol genişlik boyunca eşit aralıklı: i. etriye i. ve (n−1−i). kollarda. Yükseklik kesitin o genişlikteki en alçak üst kotundan;
# iç etriyeler yalnız üstü düz kesitte (kanal / ince duvar geçen yerde dış etriye kalır).
# 135° kancalar sol üst köşede, çekirdeğe doğru, max(10Ø, 100 mm).
# iç içe etriye yalnız üstü düz (tek kot, kanal / ince duvar yok) BK'da: kanallı BK'da kesit boyunca kapalı etriye konmaz
def mst_ar_stirrups_ok?(an,prm)
 prm['stir_legs'].to_i>=2 && an[:levels].length==1 && an[:thin].none?{|r|r.any?}
end
def mst_ar_stirrups(hf,an,prm,vlist=nil)
 n=prm['stir_legs'].to_i;return [] if n<2
 n+=1 if n.odd?
 sd=prm['stir_d']/1000.0;cov=prm['cover_mm']/1000.0;cs=cov+sd/2.0;w=hf[:W];ll=hf[:L];z0=an[:z0]
 ext=[10*sd,0.10].max/Math.sqrt(2)
 legs=(0...n).map{|k|cs+(w-2*cs)*k/(n-1).to_f}
 out=[]
 (vlist || mst_ar_lin(cs+0.05,ll-cs-0.05,prm['stir_s']/1000.0)).each do |v0|
  (0...n/2).each do |i|
   v=v0+i*(sd+0.003)   # iç etriye dış etriyenin yanında (aynı düzlemde değil)
   ua=legs[i];ub=legs[n-1-i];next if ub-ua<0.15
   tops=[];u=ua-cs;while u<=ub+cs+1e-9;t=mst_ar_top(hf,[[u,0.001].max,w-0.001].min,v);tops << t;u+=hf[:g];end
   next if tops.any?(&:nil?)
   next if i>0 && tops.max-tops.min>0.05   # iç etriye yalnız düz kesitte (kanal / duvar geçen yerde konmaz)
   zt=tops.min-cs;zb=z0+cs
   next if zt-zb<0.20
   out << [[ua+ext,v,zt-ext],[ua,v,zt],[ub,v,zt],[ub,v,zb],[ua,v,zb],[ua,v,zt],[ua+ext,v+sd,zt-ext]]
  end
 end
 out
end

# k=0..n-1 boyunca blok koşuları [a, b) (hücre indeksi)
def mst_ar_runs(hf,n)
 out=[];k=0
 while k<n
  if yield(k)
   m=k;m+=1 while m<n && yield(m)
   out << [k,m];k=m
  else k+=1 end
 end
 out
end
# açık koşuları yüksek betona doğru A kadar uzat, birleştir; uç türü: :edge (eleman kenarı), :drop (alçalma), :anchor (betonda biter)
def mst_ar_extend(runs,n,g,anch)
 segs=runs.map do |a,b|
  ea=:drop;eb=:drop
  if a==0 then ea=:edge
  elsif yield(a-1)
   m=a;m-=1 while m>0 && yield(m-1) && (a-m+1)*g<=anch
   ea=m==0 ? :edge : :anchor;a=m
  end
  if b>=n then eb=:edge
  elsif yield(b)
   m=b;m+=1 while m<n && yield(m) && (m+1-b)*g<=anch
   eb=m>=n ? :edge : :anchor;b=m
  end
  [a*g,b*g,ea,eb]
 end
 merged=[]
 segs.sort_by(&:first).each do |s|
  if merged.any? && s[0]<=merged[-1][1]+1e-9
   if s[1]>merged[-1][1] then merged[-1][1]=s[1];merged[-1][3]=s[3] end
  else merged << s.dup end
 end
 merged
end

# basamak yüzleri: geniş yüksek hücre ↔ alçak hücre (fark > 0.25 m), aynı doğru üzerinde birleşik parçalar
def mst_ar_steps(hf,an)
 g=hf[:g];top=hf[:top];thin=an[:thin];out=[]
 # u yönü geçişleri (yüz u = sabit, boyunca v)
 keyed=Hash.new{|h,k|h[k]=[]}
 (hf[:nu]-1).times do |i|
  hf[:nv].times do |j|
   t1=top[i][j];t2=top[i+1][j];next unless t1 && t2 && (t1-t2).abs>0.25
   hi_i=t1>t2 ? i : i+1;next if thin[hi_i][j]
   keyed[[(i+1)*g,t1>t2 ? -1 : 1,[t1,t2].max.round(2),[t1,t2].min.round(2)]] << j
  end
 end
 keyed.each{|(f,sd,hi,lo),js|mst_ar_groups(js).each{|a,b|out << {ax:0,face:f,hi_side:sd,hi:hi,lo:lo,a:a*g,b:(b+1)*g} if (b+1-a)*g>=0.3}}
 keyed=Hash.new{|h,k|h[k]=[]}
 (hf[:nv]-1).times do |j|
  hf[:nu].times do |i|
   t1=top[i][j];t2=top[i][j+1];next unless t1 && t2 && (t1-t2).abs>0.25
   hi_j=t1>t2 ? j : j+1;next if thin[i][hi_j]
   keyed[[(j+1)*g,t1>t2 ? -1 : 1,[t1,t2].max.round(2),[t1,t2].min.round(2)]] << i
  end
 end
 keyed.each{|(f,sd,hi,lo),is|mst_ar_groups(is).each{|a,b|out << {ax:1,face:f,hi_side:sd,hi:hi,lo:lo,a:a*g,b:(b+1)*g} if (b+1-a)*g>=0.3}}
 out
end
def mst_ar_groups(ks)
 out=[];ks.sort.each{|k|out.any? && k==out[-1][1]+1 ? out[-1][1]=k : out << [k,k]};out
end

# ince duvarlar: tu (v boyunca duvar) / tv (u boyunca duvar) hücre öbekleri
def mst_ar_walls(hf,an)
 g=hf[:g];top=hf[:top];out=[]
 [[1,an[:tu]],[0,an[:tv]]].each do |ax,mask|
  seen={}
  hf[:nu].times do |i|
   hf[:nv].times do |j|
    next unless mask[i][j] && !seen[[i,j]]
    comp=[];st=[[i,j]];seen[[i,j]]=true
    until st.empty?
     a,b=st.pop;comp << [a,b]
     [[a+1,b],[a-1,b],[a,b+1],[a,b-1]].each{|x,y|next if x<0 || y<0 || x>=hf[:nu] || y>=hf[:nv] || seen[[x,y]] || !mask[x][y];seen[[x,y]]=true;st << [x,y]}
    end
    along=comp.map{|a,b|ax==1 ? b : a};across=comp.map{|a,b|ax==1 ? a : b}
    len=(along.max-along.min+1)*g;next if len<0.6
    tops=comp.map{|a,b|top[a][b].round(2)}
    body=tops.min                      # gövde üstü; daha yüksek dar hücreler başlık
    c0=(across.min*g);c1=(across.max+1)*g
    kc=comp.select{|a,b|top[a][b]>body+0.05}
    kerb=nil
    unless kc.empty?
     ka=kc.map{|a,b|ax==1 ? b : a};kx=kc.map{|a,b|ax==1 ? a : b}
     kerb={a:ka.min*g,b:(ka.max+1)*g,c:(kx.min*g+(kx.max+1)*g)/2.0,top:kc.map{|a,b|top[a][b]}.max}
    end
    # dik duvarlarla kesişen bölgeler (etriye konmaz)
    other=ax==1 ? an[:tv] : an[:tu]
    sk=mst_ar_groups(comp.select{|a,b|other[a][b]}.map{|a,b|ax==1 ? b : a}.uniq).map{|p,q|[p*g,(q+1)*g]}
    out << {ax:ax,a:along.min*g,b:(along.max+1)*g,c:(c0+c1)/2.0,t:c1-c0,top:body,kerb:kerb,skip:sk}
   end
  end
 end
 out
end

# ---------------------------------------------------------------- çakışma giderme (dağıtım ekseninde ≤ 9 cm)
def mst_ar_segdist(p1,q1,p2,q2)
 d1=[q1[0]-p1[0],q1[1]-p1[1],q1[2]-p1[2]];d2=[q2[0]-p2[0],q2[1]-p2[1],q2[2]-p2[2]];r=[p1[0]-p2[0],p1[1]-p2[1],p1[2]-p2[2]]
 dot=->(x,y){x[0]*y[0]+x[1]*y[1]+x[2]*y[2]}
 a=dot.(d1,d1);e=dot.(d2,d2);f=dot.(d2,r);c=dot.(d1,r);b=dot.(d1,d2);den=a*e-b*b
 s=den>1e-12 ? [[(b*f-c*e)/den,0.0].max,1.0].min : 0.0
 t=e>1e-12 ? (b*s+f)/e : 0.0
 if t<0 then t=0.0;s=a>1e-12 ? [[-c/a,0.0].max,1.0].min : 0.0
 elsif t>1 then t=1.0;s=a>1e-12 ? [[(b-c)/a,0.0].max,1.0].min : 0.0 end
 Math.sqrt((0..2).sum{|k|(p1[k]+d1[k]*s-p2[k]-d2[k]*t)**2})
end
def mst_ar_resolve!(bars,cell=0.4)
 grid=Hash.new{|h,k|h[k]=[]};segs=[]
 cells=lambda do |a,b,pad|
  lo=(0..2).map{|k|((([a[k],b[k]].min)-pad)/cell).floor};hi=(0..2).map{|k|((([a[k],b[k]].max)+pad)/cell).floor}
  out=[];(lo[0]..hi[0]).each{|x|(lo[1]..hi[1]).each{|y|(lo[2]..hi[2]).each{|z|out << [x,y,z]}}};out
 end
 clash=lambda do |pts,d|
  pts.each_cons(2) do |a,b|
   seen={}
   cells.(a,b,0.04).each do |c|
    grid.fetch(c,[]).each do |i|
     next if seen[i];seen[i]=true
     p,q,d2=segs[i]
     if mst_ar_segdist(a,b,p,q)<(d+d2)/2000.0-0.0015 then @mst_ar_last_hit=segs[i][3];return true end
    end
   end
  end
  false
 end
 steps=[0.0]+(1..12).flat_map{|k|[k*0.0075,-k*0.0075]}   # ≤ 9 cm (v0.49: 6 → 9 cm, köşe detayları)
 moved=0;left=0
 bars.each do |br|
  pick=nil
  steps.each do |st|
   p=br[:pts].map{|q|q2=q.dup;q2[br[:ax]]+=st;q2}
   next if clash.(p,br[:d])
   pick=[st,p];break
  end
  if pick
   moved+=1 if pick[0]!=0.0;br[:pts]=pick[1]
  else left+=1;br[:clash]=true;br[:clash_with]=@mst_ar_last_hit end
  br[:pts].each_cons(2){|a,b|i=segs.length;segs << [a,b,br[:d],br[:zone]];cells.(a,b,0.0).each{|c|grid[c] << i}}
 end
 {moved:moved,left:left}
end

# ---------------------------------------------------------------- tam plan (SketchUp'sız)
def mst_ar_plan(pts,edges,tris,prm=nil)
 prm=mst_ar_params(prm)
 fr=mst_ar_frame(pts,edges)
 hf=mst_ar_heightfield(tris,fr)
 an=mst_ar_analyze(hf)
 bars=mst_ar_plan_bars(hf,an,prm)
 rs=mst_ar_resolve!(bars)
 m=mst_dr_mapper(fr,false,false)
 idx=mst_dr_index(tris)
 bad=mst_dr_check(bars,m,idx)
 keep=bars-bad
 # v0.49 RB5: tonaj oval bükümlü açınım (eksen) boyundan
 keep.each{|b|b[:len]=mst_dr_round(b[:pts],mst_dr_bend_r(b[:d],b[:stir]))[1]}
 # otomatik poz: bölge + Ø (poz grubu = bölge)
 grp=keep.group_by{|b|[b[:zone],b[:d].round]}.sort_by{|(z,d),_|[MST_AR_ZONES.index(z) || 9,-d]}
 sched=[];names={};qa=[]
 grp.each_with_index do |((z,d),v),i|
  v.each{|b|b[:poz]=i+1;b[:batch]=1;b[:label]="#{z} Ø#{d}"}
  msum=v.sum{|b|b[:len]};kgz=msum*mst_dr_kgm(d)
  sched << {'poz'=>i+1,'d'=>d.to_f,'n'=>v.length,'len'=>(msum/v.length).round(3),'shape'=>z}
  names[i+1]=format('Poz %02d — %s Ø%d · %d çubuk · %.1f m · %.3f t',i+1,z,d,v.length,msum,kgz/1000.0)
  qa << {'poz'=>i+1,'d'=>d.to_f,'n'=>v.length,'len'=>msum/v.length,'shape'=>z,'external'=>0,'kg'=>kgz,'drawn'=>v.length,'drawn_kg'=>kgz,'state'=>'tam'}
 end
 spec={'format'=>'mst-drawing-rebar/1','drawing'=>MST_AR_DRAWING,'schedule'=>sched,'group_names'=>names,'dims'=>{'W'=>fr['W'],'L'=>fr['L'],'H'=>fr['H']},'probes'=>[],'groups'=>[]}
 kg=keep.sum{|b|b[:len]*mst_dr_kgm(b[:d])}
 zones=MST_AR_ZONES.map{|z|bs=keep.select{|b|b[:zone]==z};[z,bs.length,bs.sum{|b|b[:len]*mst_dr_kgm(b[:d])}]}
 {frame:fr,hf:hf,an:an,prm:prm,bars:keep,dropped:bad,resolve:rs,map:m,spec:spec,kg:kg,zones:zones,
  orient:{fu:false,fv:false,ok:0,n:0},qa:qa,sched_kg:kg,
  by_d:keep.group_by{|b|b[:d].round}.map{|d,bs|[d,bs.sum{|b|b[:len]},bs.sum{|b|b[:len]*mst_dr_kgm(d)}]}.sort}
end
def mst_ar_text(eid,pl)
 an=pl[:an];fr=pl[:frame]
 walls=mst_ar_walls(pl[:hf],an);steps=mst_ar_steps(pl[:hf],an)
 l=["#{eid} — OTOMATİK DONATI (model değişmedi — önizleme)",
    format('Eleman: %.2f × %.2f × %.2f m · alt %s · kotlar (BK altından): %s',fr['L'],fr['W'],fr['H'],an[:bottom_flat] ? 'düz' : 'DÜZ DEĞİL',an[:levels].map{|x|format('%.2f',x-an[:z0])}.join(' / ')),
    "Tanınan: #{an[:levels].length} üst kot · #{steps.length} kanal kenarı yüzü · #{walls.length} ince duvar (#{walls.count{|w|w[:kerb]}} başlıklı)#{an[:rect] ? '' : ' · plan dikdörtgen değil'}#{an[:multi]>0 ? " · #{an[:multi]} noktada üst üste yüzey" : ''}",
    '', 'Bölge           Çubuk     Tonaj']
 pl[:zones].each{|z,n,kg|l << format('%-15s %6d   %7.3f t',z,n,kg/1000.0) if n>0}
 l << ''
 pl[:by_d].each{|d,m,kg|l << format('Ø%-3d %9.1f m  %8.3f t',d,m,kg/1000.0)}
 l << format('Toplam: %d çubuk · %.3f t (çizilen çubuklardan; pursantaj kullanılmaz)',pl[:bars].length,pl[:kg]/1000.0)
 l << "Çakışmayı önlemek için #{pl[:resolve][:moved]} çubuk ≤ 9 cm kaydırıldı#{pl[:resolve][:left]>0 ? "; #{pl[:resolve][:left]} çakışma kaldı" : ''}."
 l << "Betona sığmayan #{pl[:dropped].length} çubuk çizilmeyecek (#{pl[:dropped].group_by{|b|b[:zone]}.map{|k,v|"#{k} #{v.length}"}.join(', ')})." unless pl[:dropped].empty?
 l << format('Parametreler: pas %d mm · alt Ø%d/%d · ara Ø%d/%d · üst Ø%d/%d · dış yüz Ø%d/%d · kanal kenarı Ø%d/%d · duvar Ø%d/%d · stok %.0f m · bindirme %dØ şaşırtmalı%s',
   *%w[cover_mm bot_d bot_s mid_d mid_s top_d top_s side_d side_s edge_d edge_s wall_d wall_s].map{|k|pl[:prm][k].round},pl[:prm]['stock_m'],pl[:prm]['lap_d'].round,
   pl[:prm]['stir_legs'].to_i>=2 ? format(' · etriye %d kollu Ø%d/%d',pl[:prm]['stir_legs'].round,pl[:prm]['stir_d'].round,pl[:prm]['stir_s'].round) : '')
 l << 'İç içe etriye konmadı: yalnız üstü düz (kanalsız) BK\'da; bu BK\'da kanal / duvar var.' if pl[:prm]['stir_legs'].to_i>=2 && !mst_ar_stirrups_ok?(an,pl[:prm])
 l << 'Bükümler oval: büküm iç çapı etriyede 4Ø, Ø ≤ 16 için 6Ø, Ø > 16 için 7Ø (TS 500 / TS EN 1992-1-1); tonaj açınım boyundan.'
 l.join("\n")
end

# ---------------------------------------------------------------- SketchUp
def mst_ar_ask(e)
 last=(JSON.parse(e.get_attribute(DICT,'rebar_auto_json','').to_s) rescue nil) || {}
 prm=mst_ar_params(last)
 r=UI.inputbox(MST_AR_FIELDS.map{|_,lab,_,_|lab},MST_AR_FIELDS.map{|k,_,_,_|v=prm[k];v==v.round ? v.round.to_s : v.to_s},"Otomatik Donatı — #{element_visible_id(e)}")
 return nil unless r
 out={}
 MST_AR_FIELDS.each_with_index do |(k,lab,lo,hi),i|
  x=(Float(r[i].to_s.strip.tr(',','.')) rescue nil)
  raise "#{lab}: #{lo}–#{hi} arasında sayı olmalı." unless x && x>=lo && x<=hi
  out[k]=x
 end
 out
end
def mst_ar_ui(e)
 model=Sketchup.active_model
 raise "#{element_visible_id(e)}: yalnız Başlık Kirişi (BK)" unless e.get_attribute(DICT,'element_type','').to_s=='head_beam'
 raise "Component #{e.definition.count_instances} yerde kullanılıyor; önce Make Unique" if e.is_a?(Sketchup::ComponentInstance) && e.definition.count_instances>1
 prm=mst_ar_ask(e);return 0 unless prm
 pts,edges,tris=mst_dr_geometry(e)
 raise "#{element_visible_id(e)}: yüzey bulunamadı." if tris.empty?
 pl=mst_ar_plan(pts,edges,tris,prm)
 txt=mst_ar_text(element_visible_id(e),pl);puts txt
 raise "#{element_visible_id(e)}: çizilecek çubuk çıkmadı." if pl[:bars].empty?
 return 0 unless UI.messagebox("#{txt[0,3000]}\n\nDonatı bu kurallarla 3B oluşturulsun mu? (tek Geri Al)",MB_YESNO)==IDYES
 model.start_operation('MST Otomatik Donatı',true)
 begin
  mst_ar_draw!(e,pl)
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 UI.messagebox(format("%s: %d çubuk çizildi · %.3f t.\nKeşif / hakediş donatısı çizilen çubuklardan (pursantaj değil).%s",element_visible_id(e),pl[:bars].length,pl[:kg]/1000.0,(respond_to?(:mst_rt_visible_note) ? mst_rt_visible_note : '')))
 1
end
def mst_ar_draw!(e,pl)
 mst_dr_draw!(e,pl[:spec],pl)
 {'rebar_mode'=>MST_AR_MODE,'rebar_drawing'=>MST_AR_DRAWING,'rebar_auto_json'=>JSON.generate(pl[:prm]),'rebar_source'=>'Otomatik (çizilen çubuklar)',
  'rebar_kind'=>'AUTO','rebar_drawing_batches'=>'oto'}.each{|k,v|e.set_attribute(DICT,k,v)}
 e.delete_attribute(DICT,'rebar_drawing_orient')
 e
end
def mst_ar_selected_ui
 sel=Sketchup.active_model.selection.to_a.select{|x|x.respond_to?(:get_attribute) && x.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise 'Önce donatısı çizilecek tek bir Başlık Kirişi seçin.' unless sel.length==1
 n=mst_ar_ui(sel.first)
 send_boq(@d) if @d && n.to_i>0 rescue nil
 n
rescue => ex
 UI.messagebox("Otomatik donatı: #{ex.message}")
 0
end

end
end
