# frozen_string_literal: true
# v0.47.8 DR1 — Çizimden donatı (proje çizimindeki pozlar tek tek 3B).
# Eklenti dışı çizilip tanıtılan kanallı BK'larda pursantaj yerine proje donatısı kullanılır:
#  · donatı paketi (data/rebar_drawings/<çizim>.json) çizimden okunmuş poz listesi + her pozun 3B yerleşimi,
#  · BK'nın gerçek geometrisinden yerel çerçeve (boy / genişlik / yükseklik) bulunur,
#  · çizimin dolu / boş (kanal) kontrol noktalarıyla BK'nın hangi yönde durduğu seçilir,
#  · her çubuğun her noktası (pas payı dahil) betonun içinde mi diye denetlenir — kanala giren çubuk varsa çizilmez,
#  · çubuklar poz başına tek Component tanımıyla yerleşir (hafif model), poz başına ayrı grup.
# Metraj: donatı tablosunun satırları (adet × boy × birim ağırlık). Pursantaj kullanılmaz.
require 'json'
module MAG
module MarineStructuresTools

MST_DR_SET='drawing_rebar_set'
MST_DR_DICT='MAG_MST_DR'
MST_DR_MODE='drawing_detail'
MST_DR_DIR=File.join(File.dirname(__FILE__),'data','rebar_drawings')
MST_DR_MIN_COVER=0.02   # çubuk yüzeyinden beton yüzüne en az (m) — kontrol için

# ---------------------------------------------------------------- paket
# v0.51 DR5: paftadan otomatik kurulan paketler modelde saklanır (aynı tipteki diğer BK'lar da kullanır)
MST_DR_MODEL_KEY='mst_dr_auto_specs_json'
def mst_dr_model_specs(model=(Sketchup.active_model rescue nil))
 return {} unless model
 h=(JSON.parse(model.get_attribute(DICT,MST_DR_MODEL_KEY,'{}').to_s) rescue {})
 h.is_a?(Hash) ? h : {}
end
def mst_dr_model_store!(spec,model=Sketchup.active_model)
 h=mst_dr_model_specs(model);h[spec['drawing'].to_s]=spec
 model.set_attribute(DICT,MST_DR_MODEL_KEY,JSON.generate(h))
 spec['drawing'].to_s
end
def mst_dr_list(dir=MST_DR_DIR)
 (Dir.glob(File.join(dir,'*.json')).map{|f|File.basename(f,'.json')}.sort+mst_dr_model_specs.keys.sort).uniq
end
def mst_dr_load(name,dir=MST_DR_DIR)
 ms=mst_dr_model_specs[name.to_s]
 return ms if ms.is_a?(Hash) && ms['format'].to_s=='mst-drawing-rebar/1'
 f=File.join(dir,"#{File.basename(name.to_s)}.json")
 raise "Donatı paketi bulunamadı: #{name}" unless File.file?(f)
 sp=JSON.parse(File.read(f,encoding:'UTF-8'))
 raise "#{name}: paket biçimi tanınmadı" unless sp['format'].to_s=='mst-drawing-rebar/1'
 %w[schedule groups dims probes].each{|k|raise "#{name}: '#{k}' eksik" unless sp[k]}
 sp
end
def mst_dr_kgm(d);d.to_f**2/162.0;end
def mst_dr_len(path)
 (0...path.length-1).sum{|i|a=path[i];b=path[i+1];Math.sqrt((a[0]-b[0])**2+(a[1]-b[1])**2+(a[2]-b[2])**2)}
end
# v0.49 RB5 — oval bükümler (TS 500 / TS EN 1992-1-1 Tablo 8.1N): büküm iç çapı etriyede 4Ø, Ø ≤ 16'da 6Ø, Ø > 16'da 7Ø.
# Eksen yarıçapı = iç çap / 2 + Ø / 2. Kısa bacakta yarıçap küçülür (teğet boyu ≤ bacağın yarısı).
def mst_dr_bend_r(d,stir=false)
 k=stir ? 4.0 : (d.to_f<=16.0 ? 6.0 : 7.0)
 (k*d.to_f/1000.0)/2.0+d.to_f/2000.0
end
# köşeleri yuvarlatılmış eksen çizgisi (≤ 15° adım) ve açınım (eksen) boyu
def mst_dr_round(pts,r,step=Math::PI/12)
 return [pts.map(&:dup),mst_dr_len(pts)] if pts.length<3 || r<=0
 sub=->(p,q){[q[0]-p[0],q[1]-p[1],q[2]-p[2]]};nrm=->(v){Math.sqrt(v[0]**2+v[1]**2+v[2]**2)};unit=->(v){l=nrm.(v);v.map{|x|x/l}}
 out=[pts[0].dup];tot=mst_dr_len(pts)
 (1...pts.length-1).each do |i|
  a=sub.(pts[i-1],pts[i]);b=sub.(pts[i],pts[i+1]);la=nrm.(a);lb=nrm.(b)
  if la<1e-9 || lb<1e-9 then out << pts[i].dup;next end
  cs=(a[0]*b[0]+a[1]*b[1]+a[2]*b[2])/(la*lb);th=Math.acos([[cs,1.0].min,-1.0].max)
  if th<1e-6 then out << pts[i].dup;next end
  t=[r*Math.tan(th/2),la/2,lb/2].min;rr=t/Math.tan(th/2)
  tot-=2*t-rr*th
  ua=unit.(a);ub=unit.(b)
  p1=pts[i].zip(ua).map{|q,x|q-x*t}
  dt=ua.zip(ub).sum{|m,n|m*n};w=unit.(ub.zip(ua).map{|x,y|x-y*dt})
  cen=p1.zip(w).map{|q,x|q+x*rr};n=[(th/step).ceil,2].max
  (0..n).each{|k|f=th*k/n;out << cen.each_index.map{|j|cen[j]-w[j]*rr*Math.cos(f)+ua[j]*rr*Math.sin(f)}}
 end
 out << pts[-1].dup
 [out,tot]
end
def mst_dr_sched(spec);Hash[spec['schedule'].map{|s|[s['poz'].to_i,s]}];end
def mst_dr_sched_kg(spec);spec['schedule'].sum{|s|s['n'].to_f*s['len'].to_f*mst_dr_kgm(s['d'])};end
def mst_dr_batches(spec);spec['groups'].map{|g|g['batch'].to_i}.uniq.sort;end

# bütün çubuklar (yerel u, v, z metre)
def mst_dr_expand(spec,batches=nil)
 sch=mst_dr_sched(spec);w=spec['dims']['W'].to_f
 out=[]
 spec['groups'].each do |g|
  next if batches && !batches.include?(g['batch'].to_i)
  poz=g['poz'].to_i;s=sch[poz] or raise "Poz #{poz} tabloda yok"
  (g['at'] || [[0,0,0]]).each do |a|
   p=g['path'].map{|q|[q[0]+a[0],q[1]+a[1],q[2]+a[2]]}
   ps=[p];ps << p.map{|q|[w-q[0],q[1],q[2]]} if g['mirror_u']
   stir=!!(g['label'].to_s=~/etriye/i) || (spec['stirrup_poz'] || []).include?(poz)
   ps.each{|pp|out << {poz:poz,d:s['d'].to_f,pts:pp,len:mst_dr_len(pp),label:g['label'].to_s,batch:g['batch'].to_i,stir:stir}}
  end
 end
 out
end

# poz başına: tablo ↔ çizilen
# tablo adedinden ayrı çizimde (parapet) kalan adet
def mst_dr_external(spec)
 h=Hash.new(0);(spec['external'] || []).each{|x|h[x['poz'].to_i]+=x['n'].to_i};h
end
# v0.49 PP1 — parapet: paketin ayrı parapet çiziminde kalan pozları. BK katısında parapet yoksa (eleman çizimden
# 0.3 m'den fazla yüksek değilse) bu pay tonajdan düşülür; parapet modeldeyse tonajda kalır.
def mst_dr_parapet_ext(spec)
 h=Hash.new(0);(spec['external'] || []).each{|x|h[x['poz'].to_i]+=x['n'].to_i if x['note'].to_s=~/parapet/i};h
end
def mst_dr_parapet_kg(spec)
 sch=mst_dr_sched(spec);mst_dr_parapet_ext(spec).sum{|p,n|s=sch[p];s ? n*s['len'].to_f*mst_dr_kgm(s['d']) : 0.0}
end
def mst_dr_parapet_present?(fr,spec);fr['H'].to_f>spec['dims']['H'].to_f+0.3;end
def mst_dr_qa(spec,bars)
 by=bars.group_by{|b|b[:poz]};ext=mst_dr_external(spec)
 spec['schedule'].map do |s|
  poz=s['poz'].to_i;bs=by[poz] || [];n=s['n'].to_i;x=ext[poz];own=n-x
  lens=bs.map{|b|b[:len]}
  len_ok=lens.all?{|l|(l-s['len'].to_f).abs<=[(spec['len_tol'] || 0.005).to_f*s['len'].to_f,0.01].max}   # otomatik pakette kroki çizim toleransı
  st=if own<=0 && bs.empty? then 'parapet çizimi'
   elsif bs.empty? then (spec['auto'] ? 'yalnız metraj' : 'sonraki pakette')
   elsif !len_ok then 'BOY HATALI'
   elsif bs.length>own then 'FAZLA'
   elsif bs.length==own then 'tam'
   else 'kısmi' end
  {'poz'=>poz,'d'=>s['d'].to_f,'n'=>n,'len'=>s['len'].to_f,'shape'=>s['shape'].to_s,'external'=>x,
   'kg'=>n*s['len'].to_f*mst_dr_kgm(s['d']),'drawn'=>bs.length,'drawn_kg'=>lens.sum*mst_dr_kgm(s['d']),'state'=>st}
 end
end
def mst_dr_qa_errors(qa);qa.select{|r|%w[FAZLA BOY\ HATALI].include?(r['state'])};end

# ---------------------------------------------------------------- yerel çerçeve
# pts: [[x,y,z]...] (m), edges: [[[x,y,z],[x,y,z]]...]; yatay kenarların baskın yönü boy eksenidir.
def mst_dr_frame(pts,edges,spec)
 bins=Hash.new(0.0);hz=[]
 edges.each do |a,b|
  dx=b[0]-a[0];dy=b[1]-a[1];dz=b[2]-a[2];l=Math.sqrt(dx*dx+dy*dy)
  next if l<0.05 || dz.abs>1e-4*[l,1].max
  t=Math.atan2(dy,dx)%Math::PI;bins[((t/Math::PI*360).round)%360]+=l;hz << [t,l]
 end
 raise 'Yatay kenar bulunamadı (eleman katı değil mi?)' if bins.empty?
 # kaba yön (0.5°) → aynı yöndeki kenarların uzunluk ağırlıklı ortalaması (tam açı)
 refine=lambda do |t0|
  sx=0.0;sy=0.0
  hz.each{|t,l|d=((t-t0+Math::PI/2)%Math::PI)-Math::PI/2;next if d.abs>Math::PI/180;sx+=l*Math.cos(2*t);sy+=l*Math.sin(2*t)}
  sx.abs+sy.abs<1e-12 ? t0 : Math.atan2(sy,sx)/2
 end
 cands=bins.sort_by{|_,l|-l}.first(2).map{|k,_|refine.(k*Math::PI/360)}
 cands << cands[0]+Math::PI/2
 dims=spec['dims'];best=nil
 cands.uniq.each do |t|
  ev=[Math.cos(t),Math.sin(t),0.0];eu=[ev[1],-ev[0],0.0]
  us=pts.map{|p|p[0]*eu[0]+p[1]*eu[1]};vs=pts.map{|p|p[0]*ev[0]+p[1]*ev[1]};zs=pts.map{|p|p[2]}
  w=us.max-us.min;l=vs.max-vs.min;h=zs.max-zs.min
  err=(w-dims['W'].to_f).abs+(l-dims['L'].to_f).abs+(h-dims['H'].to_f).abs
  fr={'eu'=>eu,'ev'=>ev,'o'=>[us.min,vs.min,zs.min],'W'=>w,'L'=>l,'H'=>h,'err'=>err}
  best=fr if best.nil? || err<best['err']
 end
 best
end
def mst_dr_dims_ok?(fr,spec)
 tol=(spec['dims']['tol'] || 0.08).to_f;h=spec['dims']['H'].to_f
 hok=(fr['H']-h).abs<=tol || (mst_dr_parapet_ext(spec).any? && fr['H']>h && fr['H']<=h+1.5)   # parapetli BK daha yüksek olabilir
 (fr['W']-spec['dims']['W'].to_f).abs<=tol && (fr['L']-spec['dims']['L'].to_f).abs<=tol && hok
end
# yerel (u,v,z) → eleman koordinatı (m); fu / fv: genişlik / boy ters
def mst_dr_mapper(fr,fu,fv)
 eu,ev=fr['eu'],fr['ev'];ou,ov,oz=fr['o'];w,l=fr['W'],fr['L']
 lambda do |q|
  u=ou+(fu ? w-q[0] : q[0]);v=ov+(fv ? l-q[1] : q[1])
  [u*eu[0]+v*ev[0],u*eu[1]+v*ev[1],oz+q[2]]
 end
end

# ---------------------------------------------------------------- içinde mi (düşey ışın, ızgara hızlandırma)
def mst_dr_index(tris,cell=0.5)
 items=[];grid=Hash.new{|h,k|h[k]=[]}
 tris.each do |t|
  a,b,c=t
  den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
  next if den.abs<1e-12
  i=items.length;items << [a,b,c,den]
  xs=[a[0],b[0],c[0]];ys=[a[1],b[1],c[1]]
  ((xs.min/cell).floor..(xs.max/cell).floor).each{|x|((ys.min/cell).floor..(ys.max/cell).floor).each{|y|grid[[x,y]] << i}}
 end
 {items:items,grid:grid,cell:cell}
end
def mst_dr_inside?(idx,q)
 x=q[0]+1.37e-6;y=q[1]+2.11e-6;z=q[2]
 n=0
 (idx[:grid].fetch([(x/idx[:cell]).floor,(y/idx[:cell]).floor],nil) || []).each do |i|
  a,b,c,den=idx[:items][i]
  l1=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/den
  next if l1<0 || l1>1
  l2=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/den
  next if l2<0 || l1+l2>1
  n+=1 if l1*a[2]+l2*b[2]+(1-l1-l2)*c[2]>z
 end
 n.odd?
end
# v0.50.3 BK2: noktanın üstünde katı yok, altında var (BK üst yüzü / kanal tabanı üstünde, BK'nın plan alanı içinde)
def mst_dr_above?(idx,q)
 x=q[0]+1.37e-6;y=q[1]+2.11e-6;z=q[2];up=0;down=0
 (idx[:grid].fetch([(x/idx[:cell]).floor,(y/idx[:cell]).floor],nil) || []).each do |i|
  a,b,c,den=idx[:items][i]
  l1=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/den
  next if l1<0 || l1>1
  l2=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/den
  next if l2<0 || l1+l2>1
  l1*a[2]+l2*b[2]+(1-l1-l2)*c[2]>z ? up+=1 : down+=1
 end
 up.zero? && down>0
end
# yön seçimi: çizimin dolu / boş kontrol noktaları
def mst_dr_orient(spec,fr,idx)
 res=[[false,false],[false,true],[true,false],[true,true]].map do |fu,fv|
  m=mst_dr_mapper(fr,fu,fv)
  hits=spec['probes'].map{|p|mst_dr_inside?(idx,m.([p['u'].to_f,p['v'].to_f,p['z'].to_f]))==(p['solid']==true)}
  {fu:fu,fv:fv,ok:hits.count(true),n:hits.length,hits:hits}
 end
 res.sort_by{|r|[-r[:ok],(r[:fu] ? 1 : 0)+(r[:fv] ? 1 : 0)]}
end
# her çubuk: köşeler + en çok 0.5 m arayla noktalar; merkez ve yanal (yarıçap + pas) noktalar betonda olmalı
# spec['stage2_top']: 2. kademe betonu üst kotu (yerel z, m). BK katısının üstünde, plan alanı içinde ve bu kotun altında kalan
# nokta da kabul edilir (filiz / etriye 2. kademe betonunda; metrajı BK'da). Yoksa eskisi gibi yalnız katı içi.
def mst_dr_check(bars,m,idx,step=0.5,spec=nil)
 z2=spec && spec['stage2_top'] ? spec['stage2_top'].to_f : nil
 ok_at=->(q){mst_dr_inside?(idx,m.(q)) || (z2 && q[2]<=z2+1e-9 && mst_dr_above?(idx,m.(q)))}
 bad=[]
 bars.each do |b|
  r=b[:d]/2000.0+MST_DR_MIN_COVER;ok=true
  b[:pts].each_cons(2) do |p,q|
   dv=[q[0]-p[0],q[1]-p[1],q[2]-p[2]];l=Math.sqrt(dv.sum{|x|x*x});next if l<1e-9
   ax=(0..2).max_by{|k|dv[k].abs}
   offs=[[0,0,0]];(0..2).each{|k|next if k==ax;o=[0,0,0];o[k]=r;offs << o;o2=[0,0,0];o2[k]=-r;offs << o2}
   k=[(l/step).ceil,1].max
   (0..k).each do |i|
    s=[p[0]+dv[0]*i/k,p[1]+dv[1]*i/k,p[2]+dv[2]*i/k]
    offs.each{|o|next if ok_at.([s[0]+o[0],s[1]+o[1],s[2]+o[2]]);ok=false;break}
    break unless ok
   end
   break unless ok
  end
  bad << b unless ok
 end
 bad
end

# tam plan (SketchUp'sız): çerçeve → yön → kontrol
def mst_dr_plan(spec,pts,edges,tris,batches=nil)
 fr=mst_dr_frame(pts,edges,spec)
 pk=mst_dr_parapet_kg(spec);pres=mst_dr_parapet_present?(fr,spec);ded=pk>0 && !pres
 idx=mst_dr_index(tris)
 ors=mst_dr_orient(spec,fr,idx);o=ors.first
 bars=mst_dr_expand(spec,batches)
 m=mst_dr_mapper(fr,o[:fu],o[:fv])
 bad=mst_dr_check(bars,m,idx,0.5,spec)
 qa=mst_dr_qa(spec,bars)
 h=spec['dims']['H'].to_f;st2=spec['stage2_top'] ? bars.count{|b|b[:pts].any?{|q|q[2]>h+1e-6}} : 0
 {frame:fr,orient:o,orients:ors,bars:bars,bad:bad,qa:qa,map:m,dims_ok:mst_dr_dims_ok?(fr,spec),stage2:st2,
  probes_ok:o[:ok]==o[:n],ambiguous:!spec['symmetric'] && ors.length>1 && ors[1][:ok]==o[:ok],sched_kg:mst_dr_sched_kg(spec)-(ded ? pk : 0.0),
  parapet:{present:pres,deduct:ded,kg:pk}}
end
def mst_dr_blockers(pl,spec)
 e=[]
 e << format('Ölçüler uymuyor: eleman %.2f × %.2f × %.2f m, çizim %.2f × %.2f × %.2f m.',pl[:frame]['L'],pl[:frame]['W'],pl[:frame]['H'],spec['dims']['L'],spec['dims']['W'],spec['dims']['H']) unless pl[:dims_ok]
 e << "Kanal / dolu kontrolü uymuyor (#{pl[:orient][:ok]}/#{pl[:orient][:n]} nokta): eleman bu çizimin kirişi değil ya da geometrisi farklı." unless pl[:probes_ok]
 e << 'Yön belirlenemedi (iki yön eşit uyuyor).' if pl[:ambiguous]
 unless pl[:bad].empty?
  e << "#{pl[:bad].length} çubuk betonun dışına / kanala taşıyor (paket #{pl[:bad].map{|b|b[:batch]}.uniq.sort.join(', ')} · poz #{pl[:bad].map{|b|b[:poz]}.uniq.sort.join(', ')})."
 end
 mst_dr_qa_errors(pl[:qa]).each{|r|e << "Poz #{r['poz']}: #{r['state']} (tablo #{r['n']} adet)"}
 e
end
def mst_dr_text(eid,spec,pl)
 o=pl[:orient]
 l=["#{eid} ← #{spec['drawing']} donatı çizimi (model değişmedi — önizleme)",
    format('Eleman: %.2f × %.2f × %.2f m · çizim: %.2f × %.2f × %.2f m',pl[:frame]['L'],pl[:frame]['W'],pl[:frame]['H'],spec['dims']['L'],spec['dims']['W'],spec['dims']['H']),
    "Yön: #{o[:fu] ? 'genişlik ters' : 'genişlik düz'}, #{o[:fv] ? 'boy ters' : 'boy düz'} · kanal / dolu kontrolü #{o[:ok]}/#{o[:n]}",
    "Betona / kanala taşan çubuk: #{pl[:bad].length}"]
 l << format('2. kademe: %d çubuk BK üstünden 2. kademe betonuna çıkıyor (üst kot +%.2f m; metrajı bu BK\'da).',pl[:stage2],spec['stage2_top'].to_f) if pl[:stage2].to_i>0
 l << 'Kiriş iki yönde simetrik: yön ilk uyan seçildi.' if spec['symmetric'] && pl[:orients].length>1 && pl[:orients][1][:ok]==o[:ok]
 l+=['',
    'Poz  Ø   Tablo adet × boy   3B çizilen   Durum']
 pl[:qa].each do |r|
  l << format('%-4s Ø%-3d %4d × %6.2f m   %4d        %s%s',r['poz'],r['d'].round,r['n'],r['len'],r['drawn'],r['state'],r['external']>0 && r['state']!='parapet çizimi' ? " (+#{r['external']} parapet)" : '')
 end
 done=pl[:qa].count{|r|r['state']=='tam'};part=pl[:qa].count{|r|r['state']=='kısmi'}
 l << ''
 par=pl[:qa].count{|r|r['state']=='parapet çizimi'}
 l << (spec['auto'] ? "3B: #{pl[:bars].length} çubuk · #{done} poz tam, #{part} poz kısmi, #{pl[:qa].length-done-part-par} poz yalnız metrajda (paftadan yerleştirilemedi)" :
  "3B: #{pl[:bars].length} çubuk · #{done} poz tam, #{part} poz kısmi, #{par} poz parapet çiziminde, #{pl[:qa].length-done-part-par} poz sonraki paketlerde")
 l << format('Metraj (donatı tablosu satırları): %.3f t — pursantaj kullanılmaz.',pl[:sched_kg]/1000.0)
 l << spec['note'].to_s unless spec['note'].to_s.empty?
 l << spec['placement_note'].to_s unless spec['placement_note'].to_s.empty?
 pp=pl[:parapet] || {}
 if pp[:kg].to_f>0
  l << (pp[:deduct] ? format('%s BK katısında parapet yok: parapet payı (%.0f kg) tonajdan düşüldü.',spec['external_note'],pp[:kg]) :
                      format('%s Parapet BK katısında var: parapet payı (%.0f kg) tonaja dahil.',spec['external_note'],pp[:kg]))
 end
 l.join("\n")
end

# ---------------------------------------------------------------- SketchUp
def mst_dr_ents(e);e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities;end
def mst_dr_skip?(x)
 [MST_DR_SET,'head_beam_rebar_set','deck_rebar_set','ext_rebar_set','bk_culvert'].include?(x.get_attribute(DICT,'element_type','').to_s) || !x.get_attribute('MAG_MST_Label','kind').nil?
end
# eleman koordinatında (m): noktalar, kenarlar, üçgenler
def mst_dr_geometry(e)
 pts=[];edges=[];tris=[];inm=0.0254
 cv=->(p){[p.x.to_f*inm,p.y.to_f*inm,p.z.to_f*inm]}
 walk=lambda do |ents,tr|
  ents.each do |x|
   if x.is_a?(Sketchup::Face)
    mesh=x.mesh(0);mesh.transform!(tr)
    mesh.polygons.each do |poly|
     q=poly.map{|i|cv.(mesh.point_at(i.abs))}
     (1..q.length-2).each{|k|tris << [q[0],q[k],q[k+1]]}
    end
   elsif x.is_a?(Sketchup::Edge)
    a=cv.(x.start.position.transform(tr));b=cv.(x.end.position.transform(tr))
    edges << [a,b];pts << a << b
   elsif (x.is_a?(Sketchup::Group) || x.is_a?(Sketchup::ComponentInstance)) && !mst_dr_skip?(x)
    walk.(mst_dr_ents(x),tr*x.transformation)
   end
  end
 end
 walk.(mst_dr_ents(e),Geom::Transformation.new)
 [pts,edges,tris]
end
def mst_dr_supported_reason(e)
 return 'yalnız Başlık Kirişi (BK)' unless e.get_attribute(DICT,'element_type','').to_s=='head_beam'
 return "Component #{e.definition.count_instances} yerde kullanılıyor; önce Make Unique" if e.is_a?(Sketchup::ComponentInstance) && e.definition.count_instances>1
 nil
end
def mst_dr_set_of(e)
 mst_dr_ents(e).to_a.select{|x|x.is_a?(Sketchup::Group) && x.get_attribute(DICT,'element_type','').to_s==MST_DR_SET}
end
# SketchUp'ta silinen grubun tanımı içindeki çubuklar hemen ayrılmaz (count_instances düşmez):
# önce poz gruplarındaki çubukları, sonra grupları açıkça sil.
def mst_dr_erase_set!(g)
 return unless g && g.valid?
 g.entities.to_a.select{|x|x.is_a?(Sketchup::Group)}.each do |pg|
  next unless pg.valid?
  xs=pg.entities.to_a;pg.entities.erase_entities(xs) unless xs.empty?
  pg.erase! if pg.valid?
 end
 xs=g.entities.to_a;g.entities.erase_entities(xs) unless xs.empty?
 g.erase! if g.valid?
end
def mst_dr_purge_defs!(model)
 return unless model.definitions.respond_to?(:remove)
 # eski sürümden kalan yetim grup tanımları (silinmiş donatı grubu): içindeki poz grupları / çubuklar boşaltılır
 3.times do
  hit=false
  model.definitions.to_a.each do |d|
   next unless d.respond_to?(:group?) && d.group? && d.count_instances==0
   xs=d.entities.to_a.select{|x|(x.is_a?(Sketchup::Group) && (!x.get_attribute(MST_DR_DICT,'poz').nil? || x.get_attribute(DICT,'element_type','').to_s==MST_DR_SET)) ||
                                (x.is_a?(Sketchup::ComponentInstance) && !x.definition.get_attribute(MST_DR_DICT,'drawing').nil?)}
   next if xs.empty?
   d.entities.erase_entities(xs);hit=true
  end
  break unless hit
 end
 model.definitions.to_a.select{|d|!d.get_attribute(MST_DR_DICT,'drawing').nil? && d.count_instances==0}.each{|d|model.definitions.remove(d) rescue nil}
end
# çizim donatısını sil, pursantaja dön (çağıranın işlemi içinde)
# v0.48.1: BK'da eklentinin kendi (BIM) donatısı varsa çizimden / otomatik donatı onun yerine geçer;
# eski donatı grubu silinir (çift donatı olmaz), önceki durum saklanır ve "Sil" ile geri gelir.
def mst_dr_stash_prev!(e)
 return unless e.get_attribute(DICT,'rebar_prev_json','').to_s.empty?
 return if mst_dr_set_of(e).any?
 old=mst_dr_ents(e).to_a.select{|x|x.is_a?(Sketchup::Group) && x.get_attribute(DICT,'element_type','').to_s=='head_beam_rebar_set'}
 mode=e.get_attribute(DICT,'rebar_mode','').to_s
 return if old.empty? && mode.empty?
 e.set_attribute(DICT,'rebar_prev_json',JSON.generate({'mode'=>mode,'hb'=>e.get_attribute(DICT,'hb_rebar_json','').to_s}))
 old.each{|g| next unless g.valid?
  g.entities.to_a.select{|x|x.is_a?(Sketchup::Group)}.each{|pg|pg.entities.erase_entities(pg.entities.to_a) unless pg.entities.to_a.empty?;pg.erase! if pg.valid?}
  g.entities.erase_entities(g.entities.to_a) unless g.entities.to_a.empty?
  g.erase! if g.valid?}
 %w[rebar_mode rebar_kg rebar_cover_mm rebar_bar_count rebar_kind rebar_pocket_count rebar_schedule_json hb_rebar_json].each{|k|e.delete_attribute(DICT,k)}
end
def mst_dr_clear!(e)
 mst_rt_history_push!(e) if respond_to?(:mst_rt_history_push!) && mst_dr_set_of(e).any?
 mst_dr_set_of(e).each{|g|mst_dr_erase_set!(g)}
 %w[rebar_mode rebar_kg rebar_bar_count rebar_kind rebar_schedule_json rebar_drawing rebar_drawing_batches rebar_drawing_orient rebar_source rebar_auto_json].each{|k|e.delete_attribute(DICT,k)}
 e.set_attribute(DICT,'rebar_t',qto3_quantity(e,:concrete_m3)*rebar_rate('head_beam')/1000.0)
 mst_dr_purge_defs!(e.model)
 # v0.51.5 K63: önceki BIM donatısı kaydı (rebar_prev_json) yalnız geri kurma başarılıysa silinir;
 # kurulamazsa kayıt korunur, donatı pursantajda kalır, neden rebar_restore_error'a yazılır (Model Kontrolü)
 raw_prev=e.get_attribute(DICT,'rebar_prev_json','').to_s
 prev=(raw_prev.strip.empty? ? {} : (JSON.parse(raw_prev) rescue nil))
 unless prev.is_a?(Hash)
  e.set_attribute(DICT,'rebar_restore_error','Önceki BIM donatısı kaydı (rebar_prev_json) okunamadı; kayıt korundu.')
  return true
 end
 unless prev['mode']=='bim_detail' && !prev['hb'].to_s.empty?
  e.delete_attribute(DICT,'rebar_prev_json')
  return true
 end
 why=if e.is_a?(Sketchup::ComponentInstance) then 'Component BK (tanım paylaşılabilir); donatı bu yoldan kurulmaz'
     elsif !respond_to?(:mst_hb_rebar_build!) then 'BIM donatı kurucusu yok'
     else mst_hb_rebar_unsupported_reason(e)
     end
 if why
  e.set_attribute(DICT,'rebar_restore_error',"Önceki BIM donatısı geri yüklenemedi: #{why}")
  return true
 end
 begin
  e.set_attribute(DICT,'hb_rebar_json',prev['hb']);mst_hb_rebar_build!(e,JSON.parse(prev['hb']))
  e.delete_attribute(DICT,'rebar_prev_json');e.delete_attribute(DICT,'rebar_restore_error')
 rescue => ex
  mst_hb_rebar_clear!(e) rescue nil
  e.set_attribute(DICT,'rebar_restore_error',"Önceki BIM donatısı geri yüklenemedi: #{ex.message}")
 end
 true
end
def mst_dr_bar_def(model,spec,poz,d,rel,cache,stir=false)
 key=[poz,stir ? 1 : 0,rel.map{|q|q.map{|c|(c*1000).round}}]
 return cache[key] if cache[key]
 inm=39.37007874015748
 r=mst_dr_bend_r(d,stir);path,dev=mst_dr_round(rel,r)
 df=model.definitions.add("MST DR #{spec['drawing']} P#{format('%02d',poz)} Ø#{d.round}")
 df.set_attribute(MST_DR_DICT,'drawing',spec['drawing'].to_s);df.set_attribute(MST_DR_DICT,'poz',poz)
 df.set_attribute(MST_DR_DICT,'diameter_mm',d);df.set_attribute(MST_DR_DICT,'length_m',mst_dr_len(rel))
 {'dev_length_m'=>dev,'bend_radius_m'=>(rel.length>2 ? r : 0.0),'stirrup'=>(stir ? 1 : 0),'bend_count'=>[rel.length-2,0].max,
  'path_json'=>JSON.generate(rel.map{|q|q.map{|c|c.round(5)}})}.each{|k,v|df.set_attribute(MST_DR_DICT,k,v)}
 ents=df.entities
 pp=path.map{|q|Geom::Point3d.new(q[0]*inm,q[1]*inm,q[2]*inm)}
 ax=pp[0].vector_to(pp[1])
 c=ents.add_circle(pp[0],ax,(d/2000.0)*inm,12);f=ents.add_face(c)
 if f
  if pp.length==2
   f.reverse! if f.normal.dot(ax)<0;f.pushpull(ax.length)
  else
   path=ents.add_edges(pp);f.followme(path)
   path.each{|x|x.erase! if x.valid? && x.faces.empty?}
  end
  ents.grep(Sketchup::Edge).each do |x|
   fs=x.faces;next unless fs.length==2
   (x.soft=true;x.smooth=true) if fs[0].normal.angle_between(fs[1].normal)<0.7
  end
 end
 cache[key]=df
end
# çiz (çağıranın işlemi içinde); pl: mst_dr_plan sonucu
def mst_dr_draw!(e,spec,pl)
 model=e.model;inm=39.37007874015748
 mst_rt_history_push!(e) if respond_to?(:mst_rt_history_push!)   # v0.49 RV1: revizyon karşılaştırması için önceki donatı
 mst_dr_stash_prev!(e)
 mst_dr_set_of(e).each{|g|mst_dr_erase_set!(g)}
 ents=mst_dr_ents(e)
 set=ents.add_group;set.name="#{element_visible_id(e)} DONATI (#{spec['drawing']} çizimi)"
 set.set_attribute(DICT,'element_type',MST_DR_SET);set.set_attribute(DICT,'parent_uid',e.get_attribute(DICT,'element_uid','').to_s)
 set.set_attribute(MST_DR_DICT,'drawing',spec['drawing'].to_s)
 mst_rebar_tag!(set,e) rescue nil
 cache={};m=pl[:map]
 pl[:bars].group_by{|b|b[:poz]}.sort.each do |poz,bs|
  s=mst_dr_sched(spec)[poz]
  pg=set.entities.add_group;pg.name=(spec['group_names'] || {})[poz] || format('Poz %02d — %d/%d Ø%d L=%.2f',poz,bs.length,s['n'].to_i,s['d'].to_f.round,s['len'].to_f)
  pg.set_attribute(MST_DR_DICT,'poz',poz)
  mat=(mst_rebar_dia_material(model,s['d']) rescue nil)
  bs.each do |b|
   w=b[:pts].map{|q|m.(q)};o=w[0]
   rel=w.map{|q|[q[0]-o[0],q[1]-o[1],q[2]-o[2]]}
   df=mst_dr_bar_def(model,spec,poz,b[:d],rel,cache,b[:stir])
   inst=pg.entities.add_instance(df,Geom::Transformation.translation(Geom::Vector3d.new(o[0]*inm,o[1]*inm,o[2]*inm)))
   inst.material=mat if mat
  end
 end
 kg=pl[:sched_kg]
 par=(pl[:parapet] || {})[:deduct] ? mst_dr_parapet_ext(spec) : {}
 sch=Hash[pl[:qa].map{|r|n=r['n']-par[r['poz']].to_i
  ["Poz #{r['poz']} Ø#{r['d'].round}",{'count'=>n,'length_m'=>r['len']*n,'kg'=>n*r['len']*mst_dr_kgm(r['d']),'drawn'=>r['drawn'],'shape'=>r['shape']}]}]
 {'rebar_mode'=>MST_DR_MODE,'rebar_t'=>kg/1000.0,'rebar_kg'=>kg,'rebar_kind'=>'DRAWING','rebar_drawing'=>spec['drawing'].to_s,
  'rebar_drawing_batches'=>pl[:bars].map{|b|b[:batch]}.uniq.sort.join(','),'rebar_bar_count'=>pl[:bars].length,
  'rebar_drawing_orient'=>JSON.generate({'fu'=>pl[:orient][:fu],'fv'=>pl[:orient][:fv]}),'rebar_schedule_json'=>JSON.generate(sch),
  'rebar_source'=>"#{spec['drawing']} donatı tablosu"}.each{|k,v|e.set_attribute(DICT,k,v)}
 e.delete_attribute(DICT,'hb_rebar_json')
 set.set_attribute(DICT,'weight_kg',kg);set.set_attribute(DICT,'rebar_schedule_json',JSON.generate(sch))
 mst_dr_purge_defs!(model)
 set
end

# taşan çubuklar yalnız bazı paketlerdeyse: bunlar dışındaki (temiz) paketler; ölçü / yön / tablo hatası varsa boş
def mst_dr_clean_batches(pl,spec)
 return [] unless pl[:dims_ok] && pl[:probes_ok] && !pl[:ambiguous] && mst_dr_qa_errors(pl[:qa]).empty?
 mst_dr_batches(spec)-pl[:bad].map{|b|b[:batch]}.uniq
end
# elemanın geometrisini (eleman koordinatı, m) JSON'a yazar: uymayan modeli eklenti dışında incelemek için
def mst_dr_dump_geometry(e,pts,edges,tris,dir=nil)
 dir ||= begin
  mp=Sketchup.active_model.path.to_s
  mp.empty? ? (Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : Dir.pwd) : File.dirname(mp)
 end
 id=element_visible_id(e).to_s.gsub(/[^0-9A-Za-z_.-]/,'_')
 f=File.join(dir,"MST_#{id}_geometri.json")
 r=->(q){q.map{|c|c.round(5)}}
 File.write(f,JSON.generate({'format'=>'mst-element-geometry/1','id'=>element_visible_id(e).to_s,'build'=>(MST_BUILD rescue ''),
  'tris'=>tris.map{|t|t.map(&r)},'edges'=>edges.map{|a,b|[r.(a),r.(b)]}}))
 f
rescue => ex
 puts "MST geometri dökümü: #{ex.message}"
 nil
end
# v0.50.3: ölçüsü elemana uyan paket önce gelir (BK-2, BK-9 …)
def mst_dr_rank(e,names)
 pts,edges,_=mst_dr_geometry(e)
 names.map{|n|sp=(mst_dr_load(n) rescue nil);fr=sp && (mst_dr_frame(pts,edges,sp) rescue nil);[n,fr ? fr['err'] : 1e9,fr && sp ? mst_dr_dims_ok?(fr,sp) : false]}.sort_by{|n,err,ok|[ok ? 0 : 1,err.round(3),mst_dr_model_specs.key?(n) ? 0 : 1]}   # eşit uyumda modelde kurulan (paftadan) paket önce
rescue
 names.map{|n|[n,0,false]}
end
def mst_dr_pick_drawing(e)
 names=mst_dr_list
 raise 'Donatı paketi yok (data/rebar_drawings).' if names.empty?
 cur=e.get_attribute(DICT,'rebar_drawing','').to_s
 return names.first if names.length==1
 rk=mst_dr_rank(e,names)
 fit=rk.select{|_,_,ok|ok}.map(&:first)
 return fit.first if fit.length==1 && (cur.empty? || cur==fit.first || !names.include?(cur))   # ölçüsü tek pakete uyuyor: sormadan
 dflt=names.include?(cur) ? cur : rk.first[0]
 r=UI.inputbox(['Donatı çizimi (ölçüsü uyan önce)'],[dflt],[rk.map(&:first).join('|')],'Çizimden Donatı')
 r ? r[0] : nil
end
def mst_dr_ui(e)
 model=Sketchup.active_model
 why=mst_dr_supported_reason(e);raise "#{element_visible_id(e)}: #{why}" if why
 name=mst_dr_pick_drawing(e);return 0 unless name
 spec=mst_dr_load(name)
 pts,edges,tris=mst_dr_geometry(e)
 raise "#{element_visible_id(e)}: yüzey bulunamadı." if tris.empty?
 spec,pl=spec['auto'] && respond_to?(:mst_dra_fit) ? mst_dra_fit(spec,pts,edges,tris) : [spec,mst_dr_plan(spec,pts,edges,tris)]   # otomatik pakette sığmayan poz yalnız metrajda
 txt=mst_dr_text(element_visible_id(e),spec,pl);puts txt
 blk=mst_dr_blockers(pl,spec)
 unless blk.empty?
  dump=mst_dr_dump_geometry(e,pts,edges,tris)
  clean=mst_dr_clean_batches(pl,spec)
  note="\n\nÇİZİLMEDİ:\n#{blk.join("\n")}#{dump ? "\n\nBK geometrisi kaydedildi (incelemek için gönderin):\n#{dump}" : ''}"
  if clean.empty?
   UI.messagebox("#{txt[0,2400]}#{note}")
   return 0
  end
  return 0 unless UI.messagebox("#{txt[0,2200]}#{note}\n\nYalnız sorunsuz paket(ler) #{clean.join(', ')} çizilsin mi? (tonaj yine donatı tablosundan; tek Geri Al)",MB_YESNO)==IDYES
  pl=mst_dr_plan(spec,pts,edges,tris,clean)
  raise 'Temiz paketlerde de taşan çubuk var.' unless pl[:bad].empty?
 else
  return 0 unless UI.messagebox("#{txt[0,3000]}\n\nDonatı bu çizimle 3B oluşturulsun mu? (tek Geri Al)",MB_YESNO)==IDYES
 end
 model.start_operation("MST Çizimden Donatı (#{spec['drawing']})",true)
 begin
  mst_dr_draw!(e,spec,pl)
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 UI.messagebox(format("%s: %d çubuk 3B çizildi.\nBOQ / hakediş donatısı: %.3f t (donatı tablosu, pursantaj değil).%s",element_visible_id(e),pl[:bars].length,pl[:sched_kg]/1000.0,(respond_to?(:mst_rt_visible_note) ? mst_rt_visible_note : '')))
 1
end
def mst_dr_selected_ui
 sel=Sketchup.active_model.selection.to_a.select{|x|x.respond_to?(:get_attribute) && x.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise 'Önce donatısı çizilecek tek bir Başlık Kirişi seçin.' unless sel.length==1
 n=mst_dr_ui(sel.first)
 send_boq(@d) if @d && n.to_i>0 rescue nil
 n
rescue => ex
 UI.messagebox("Çizimden donatı: #{ex.message}")
 0
end
def mst_dr_remove_ui
 model=Sketchup.active_model
 modes=[MST_DR_MODE,'auto_detail']
 sel=model.selection.to_a.select{|x|x.respond_to?(:get_attribute) && modes.include?(x.get_attribute(DICT,'rebar_mode','').to_s)}
 if sel.empty?
  all=[];collect_elements(model.entities,all);sel=all.select{|x|modes.include?(x.get_attribute(DICT,'rebar_mode','').to_s)}
 end
 # v0.51.5 K57: yalnız BK'nın çizimden / otomatik donatısı; paftadan metraj (PAFTA) ve prekast donatısı burada silinmez
 cand=sel.length
 sel=sel.select{|x|x.get_attribute(DICT,'element_type','').to_s=='head_beam' && x.get_attribute(DICT,'rebar_kind','').to_s!='PAFTA'}
 note=cand>sel.length ? "\n\nPaftadan metrajı olan #{cand-sel.length} BK ve prekast donatısı bu işlemle silinmez (Paftadan Donatı / Prekast Donatısı → SİL)." : ''
 return UI.messagebox("Çizimden / otomatik donatısı olan BK yok.#{note}") if sel.empty?
 return 0 unless UI.messagebox("#{sel.length} BK'nın çizimden donatısı silinsin mi? Donatı pursantaja döner. (tek Geri Al)\n#{sel.first(12).map{|x|element_visible_id(x)}.join(', ')}#{note}",MB_YESNO)==IDYES
 model.start_operation('MST Çizimden Donatıyı Sil',true)
 begin
  sel.each{|x|mst_dr_clear!(x)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 send_boq(@d) if @d rescue nil
 sel.length
end

end
end
