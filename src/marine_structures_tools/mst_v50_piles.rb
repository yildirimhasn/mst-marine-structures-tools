# frozen_string_literal: true
# v0.50 — Kazık yerleşimi
#  AF1 A-çerçeve eğik kazık çiftleri (Ege Gübre 1/6): aks, çift aralığı, kafa aralığı, eğim, enine / boyuna düzlem, A / V biçimi
#  KD1 kazık dispozisyonu DXF paftasından (İGSAŞ KYPL): daire = kazık, katman adındaki çap, kazık no yazısı, kazık açısı yazısı
#      (eğik kazığın yönü); birim kendiliğinden (kazık çapından); başlangıç noktası + dönme; elle yerleşim eskisi gibi kalır
#  KF1 kazık filizi BK'ya göre (BK üstü − BK pas payı − üst ağ payı)
# İkisi de eklentinin kendi kazık yerleşimi motoruyla (generate_layout, özel aks) çizilir: kimlik, iç beton, donatı, metraj aynı.
require 'json'
module MAG
module MarineStructuresTools

MST_KZ_DEFAULTS={'diameter_mm'=>1016.0,'thickness_mm'=>16.0,'length_m'=>30.0,'top_elevation_m'=>1.5,'steel_grade'=>'S355',
 'infill_enabled'=>'1','infill_bottom_normal_m'=>-3.0,'infill_concrete_class'=>'C30/37','prefix'=>'P-','pile_body_mode'=>'GROUP',
 'orientation_mode'=>'VERTICAL','batter_ratio'=>0,'azimuth_deg'=>0}.freeze
MST_KZ_FORM_KEY='mst_last_pile_form_json'

# son kazık formu (generate_layout her çalışmada saklar) yoksa varsayılanlar
def mst_kz_base_data(model=Sketchup.active_model)
 last=(JSON.parse(model.get_attribute(DICT,MST_KZ_FORM_KEY,'{}').to_s) rescue {})
 last={} unless last.is_a?(Hash)
 b=MST_KZ_DEFAULTS.merge(last.reject{|_,v|v.nil?})
 %w[layout_mode custom_axis_json count_x count_y start_low_count end_low_count].each{|k|b.delete(k)}
 b
end
def mst_kz_save_form!(data,model=Sketchup.active_model)
 keep=data.reject{|k,_|%w[custom_axis_json].include?(k)}
 model.set_attribute(DICT,MST_KZ_FORM_KEY,JSON.generate(keep))
rescue
 nil
end
def mst_kz_existing_ids(model=Sketchup.active_model)
 (collect_piles(model.entities) rescue []).map{|p,_|p.get_attribute(DICT,'pile_id','').to_s}.reject(&:empty?)
end
def mst_kz_next_no(prefix,ids)
 ns=ids.map{|i|i.start_with?(prefix) ? i[prefix.length..-1][/\A\d+/].to_i : 0}
 (ns.max || 0)+1
end

# kazık listesi → generate_layout özel aks verisi. piles: [{'x','y','id','batter','az'}] (yapı yerel, m)
# aynı x (± tol) = aynı aks; aks içinde y sırası
def mst_kz_layout_data(base,piles,axis_prefix='K',tol=0.25)
 xs=piles.sort_by{|p|[p['x'],p['y']]}
 axes=[]
 xs.each{|p|a=axes.find{|x|(x[:x]-p['x']).abs<=tol};a ? (a[:ps] << p;a[:x]=a[:ps].sum{|q|q['x']}/a[:ps].length) : axes << {x:p['x'],ps:[p]}}
 axes.sort_by!{|a|a[:x]}
 js=axes.each_with_index.map do |a,i|
  {'name'=>"#{axis_prefix}#{i+1}",'x'=>a[:x].round(4),'points'=>a[:ps].sort_by{|p|p['y']}.map do |p|
   bt=p['batter'].to_f>1e-9
   {'y'=>p['y'].round(4),'dx'=>(p['x']-a[:x]).round(4),'dy'=>0.0,'name'=>'','selected'=>true,'pile_id'=>p['id'].to_s,
    'orientation_mode'=>(bt ? 'BATTERED' : 'VERTICAL'),'batter_ratio'=>(bt ? p['batter'].to_f.round(6) : 0),'azimuth_deg'=>(bt ? (p['az'].to_f%360.0).round(3) : 0)}
  end}
 end
 base.merge('layout_mode'=>'CUSTOM','custom_axis_json'=>JSON.generate(js),'start_low_count'=>0,'end_low_count'=>0,'axis_prefix'=>axis_prefix)
end

# iki kazık ekseni arasındaki en kısa mesafe (m) — kafa (x,y,top) → uç
def mst_kz_axis_seg(p,len,top)
 r=p['batter'].to_f;az=p['az'].to_f*Math::PI/180.0;den=Math.sqrt(1.0+r*r)
 d=[r/den*Math.sin(az),r/den*Math.cos(az),-1.0/den]
 [[p['x'],p['y'],top],[p['x']+len*d[0],p['y']+len*d[1],top+len*d[2]]]
end
def mst_kz_segdist(p1,q1,p2,q2)
 return mst_rt_segdist(p1,q1,p2,q2)[0] if respond_to?(:mst_rt_segdist)
 sub=->(a,b){[a[0]-b[0],a[1]-b[1],a[2]-b[2]]};dot=->(a,b){a[0]*b[0]+a[1]*b[1]+a[2]*b[2]}
 d1=sub.(q1,p1);d2=sub.(q2,p2);r=sub.(p1,p2);a=dot.(d1,d1);e=dot.(d2,d2);f=dot.(d2,r)
 c=dot.(d1,r);b=dot.(d1,d2);dn=a*e-b*b
 s=dn>1e-12 ? [[(b*f-c*e)/dn,0.0].max,1.0].min : 0.0
 t=(b*s+f)/e;if t<0 then t=0.0;s=[[-c/a,0.0].max,1.0].min elsif t>1 then t=1.0;s=[[(b-c)/a,0.0].max,1.0].min end
 v=sub.([p1[0]+s*d1[0],p1[1]+s*d1[1],p1[2]+s*d1[2]],[p2[0]+t*d2[0],p2[1]+t*d2[1],p2[2]+t*d2[2]])
 Math.sqrt(dot.(v,v))
end
# çakışan kazık çifti sayısı ve en küçük açıklık (plan kutusu ön elemesiyle)
def mst_kz_clashes(piles,dia_m,len,top)
 segs=piles.map{|p|mst_kz_axis_seg(p,len,top)}
 box=segs.map{|a,b|[[a[0],b[0]].min-dia_m,[a[0],b[0]].max+dia_m,[a[1],b[1]].min-dia_m,[a[1],b[1]].max+dia_m]}
 n=0;mn=1e9;pairs=[]
 piles.each_index do |i|
  (i+1...piles.length).each do |j|
   a=box[i];b=box[j];next if a[1]<b[0] || b[1]<a[0] || a[3]<b[2] || b[3]<a[2]
   d=mst_kz_segdist(*segs[i],*segs[j])-dia_m
   mn=d if d<mn
   (n+=1;pairs << [i,j] if pairs.length<20) if d<0.0
  end
 end
 {'count'=>n,'min'=>mn,'pairs'=>pairs}
end

# ---------------------------------------------------------------- AF1 A-çerçeve
# p: x0, y0 (m), dir_deg (aks yönü: 0 = +Y, 90 = +X), pairs, pair_spacing_m, head_gap_m, batter (oran ya da "1/6"),
#    plane 'ENINE' (çiftin iki kazığı akso dik) | 'BOYUNA' (aks üzerinde), shape 'A' (uçlar açılır) | 'V' (uçlar birleşir)
def mst_af_plan(p)
 r=pile_batter_ratio(p['batter'])
 raise 'Eğim oranı 0 olamaz (ör. 1/6).' if r<=1e-9
 n=p['pairs'].to_i;raise 'Çift sayısı 1–200 olmalı.' unless n.between?(1,200)
 s=p['pair_spacing_m'].to_f;g=p['head_gap_m'].to_f
 raise 'Çift aralığı sıfırdan büyük olmalı.' if n>1 && s<=0
 raise 'Kafa aralığı negatif olamaz.' if g<0
 a=p['dir_deg'].to_f*Math::PI/180.0;ux=Math.sin(a);uy=Math.cos(a)   # aks yönü (0 = +Y)
 vx=uy;vy=-ux                                                         # akso dik (sağ)
 plane=p['plane'].to_s.upcase=='BOYUNA' ? 'BOYUNA' : 'ENINE';shape=p['shape'].to_s.upcase=='V' ? 'V' : 'A'
 out=[]
 n.times do |i|
  cx=p['x0'].to_f+ux*s*i;cy=p['y0'].to_f+uy*s*i
  ex,ey=plane=='ENINE' ? [vx,vy] : [ux,uy]
  [-1,1].each do |sg|
   hx=cx+sg*ex*g/2.0;hy=cy+sg*ey*g/2.0
   tx=sg*ex;ty=sg*ey;(tx=-tx;ty=-ty) if shape=='V'      # A: uç dışa doğru; V: içe
   az=(Math.atan2(tx,ty)*180.0/Math::PI)%360.0          # 0 = +Y, 90 = +X
   out << {'x'=>hx.round(4),'y'=>hy.round(4),'batter'=>r,'az'=>az.round(3),'pair'=>i+1,'side'=>sg}
  end
 end
 out
end

MST_AF_FIELDS=[['x0','Başlangıç X (m, yapı orijinine göre)'],['y0','Başlangıç Y (m)'],['dir_deg','Aks yönü (°; 0 = +Y, 90 = +X)'],
 ['pairs','Çift sayısı'],['pair_spacing_m','Çift aralığı aks boyunca (m)'],['head_gap_m','Çiftte iki kazık kafası arası (m)'],
 ['batter','Eğim (ör. 1/6)'],['plane','Çerçeve düzlemi (ENINE / BOYUNA)'],['shape','Biçim (A = uçlar açılır, V = uçlar birleşir)'],
 ['prefix','Kazık no öneki']].freeze
MST_KZ_PILE_FIELDS=[['diameter_mm','Kazık çapı (mm)'],['thickness_mm','Et kalınlığı (mm)'],['length_m','Kazık boyu (m, eğik boy)'],
 ['top_elevation_m','Kazık üst kotu (m)'],['infill_bottom_normal_m','İç beton alt kotu (m)'],['steel_grade','Çelik sınıfı']].freeze

def mst_kz_ask_pile(base,title)
 r=UI.inputbox(MST_KZ_PILE_FIELDS.map{|_,l|l},MST_KZ_PILE_FIELDS.map{|k,_|base[k].to_s},title)
 return nil unless r
 h=base.dup;MST_KZ_PILE_FIELDS.each_with_index{|(k,_),i|h[k]=r[i].to_s.strip}
 h
end

def mst_af_text(pl,base)
 d=base['diameter_mm'].to_f/1000.0;l=base['length_m'].to_f;top=base['top_elevation_m'].to_f
 c=mst_kz_clashes(pl,d,l,top);c=[c['min'],c['count']]
 l1=["A-ÇERÇEVE EĞİK KAZIK — #{pl.length} kazık (#{pl.length/2} çift) · model değişmedi (önizleme)",
     format('Eğim 1/%.2f · Ø%.1f/%.0f mm · boy %.2f m · üst kot %+.2f',1.0/pl[0]['batter'],base['diameter_mm'].to_f,base['thickness_mm'].to_f,l,top),'']
 pl.first(8).each{|p|l1 << format('  çift %d %s: X %.2f  Y %.2f  azimut %.0f°',p['pair'],p['side']<0 ? 'sol' : 'sağ',p['x'],p['y'],p['az'])}
 l1 << '  …' if pl.length>8
 l1 << format('En yakın iki kazık arası (yüzeyden yüzeye): %.2f m%s',c[0],c[0]<0.10 ? " — UYARI: kazıklar çakışıyor / çok yakın (#{c[1]} çift)!" : '')
 l1.join("\n")
end

def mst_af_ui
 model=Sketchup.active_model;base=mst_kz_base_data(model)
 last=(JSON.parse(model.get_attribute(DICT,'mst_af_last_json','{}').to_s) rescue {})
 dflt={'x0'=>'0','y0'=>'0','dir_deg'=>'0','pairs'=>'4','pair_spacing_m'=>'6.0','head_gap_m'=>'1.5','batter'=>'1/6','plane'=>'ENINE','shape'=>'A','prefix'=>base['prefix'].to_s}.merge(last)
 r=UI.inputbox(MST_AF_FIELDS.map{|_,l|l},MST_AF_FIELDS.map{|k,_|dflt[k].to_s},'A-Çerçeve Eğik Kazık Çiftleri')
 return 0 unless r
 p=Hash[MST_AF_FIELDS.each_with_index.map{|(k,_),i|[k,r[i].to_s.strip]}]
 %w[x0 y0 dir_deg pair_spacing_m head_gap_m].each{|k|p[k]=Float(p[k].tr(',','.')) rescue raise("#{k}: sayı olmalı.")}
 b=mst_kz_ask_pile(base,'A-Çerçeve — kazık özellikleri');return 0 unless b
 pl=mst_af_plan(p)
 ids=mst_kz_existing_ids(model);pre=p['prefix'].empty? ? 'P-' : p['prefix'];no=mst_kz_next_no(pre,ids)
 pl.each_with_index{|q,i|q['id']="#{pre}#{(no+i).to_s.rjust(3,'0')}"}
 txt=mst_af_text(pl,b.merge('diameter_mm'=>b['diameter_mm'].to_f,'thickness_mm'=>b['thickness_mm'].to_f));puts txt
 return 0 unless UI.messagebox("#{txt}\n\nKazıklar bu şekilde oluşturulsun mu? (tek Geri Al)",MB_YESNO)==IDYES
 model.set_attribute(DICT,'mst_af_last_json',JSON.generate(p))
 data=mst_kz_layout_data(b,pl,'AF')
 data['prefix']=pre;data['start_no']=no
 generate_layout(data)
 pl.length
rescue => ex
 UI.messagebox("A-çerçeve: #{ex.message}")
 0
end

# ---------------------------------------------------------------- KD1 DXF dispozisyon
MST_KD_PILE_LAYER=/kaz[ıi]k|pile/i
MST_KD_NOT_PILE=/aks|axis|yuvarla|g[öo]r[üu]n[üu][şs]|elevation|kesit|section/i
MST_KD_NO_LAYER=/kaz[ıi]k.?no|pile.?no|kaz[ıi]k.?numara/i
MST_KD_ANG_LAYER=/a[çc][ıi]|angle|y[öo]n|direction/i

# dx: mst_dxf_read; fl: mst_dxf_flatten. Kazık daireleri (katman), çap, birim, no, eğik açı.
def mst_kd_scan(dx,fl,layer_hint=nil)
 cs=fl.select{|e|e['t']=='CIRCLE' && e['r'].to_f>0}
 by=cs.group_by{|e|e['l'].to_s}
 cand=by.keys.select{|l|layer_hint.to_s.strip.empty? ? (l=~MST_KD_PILE_LAYER && !(l=~MST_KD_NOT_PILE)) : l.downcase.include?(layer_hint.to_s.strip.downcase)}
 raise "Kazık dairesi bulunamadı#{layer_hint.to_s.strip.empty? ? ' (katman adında "kazık" / "pile" geçen daire yok)' : " (\"#{layer_hint}\" katmanında daire yok)"}. Katmanlar: #{by.keys.first(12).join(', ')}" if cand.empty?
 lay=cand.max_by{|l|by[l].length}
 circ=by[lay]
 # eş merkezli (iç / dış) daireler: tek kazık, büyük yarıçap
 uniq=[]
 circ.sort_by{|e|-e['r']}.each{|e|uniq << e unless uniq.any?{|u|(u['x']-e['x']).abs<e['r']*0.05 && (u['y']-e['y']).abs<e['r']*0.05}}
 rads=uniq.map{|e|e['r'].round(4)}.group_by{|x|x}.map{|k,v|[k,v.length]}.sort_by{|_,v|-v}
 r0=rads[0][0]
 dia_mm=lay[/(\d{3,4}(?:[.,]\d+)?)/,1].to_s.tr(',','.').to_f
 dia_mm=0.0 unless dia_mm.between?(200.0,4000.0)
 known=dia_mm>0 ? [[2*r0,dia_mm/1000.0]] : []
 unit,src,_=mst_dxf_unit(dx,known)
 if known.empty?
  # çap bilinmiyor: kazık Ø 0.3–3 m aralığına düşen birim
  u2=[0.001,0.01,0.1,1.0].find{|u|(2*r0*u).between?(0.3,3.0)}
  (unit=u2;src='kazık dairesi boyutundan') if u2 && !MST_DXF_INSUNITS.key?(dx['insunits'].to_i)
 end
 dia_mm=(2*r0*unit*1000.0).round(1) if dia_mm<=0
 nos=fl.select{|e|%w[TEXT MTEXT].include?(e['t']) && e['l'].to_s=~MST_KD_NO_LAYER && e['text'].to_s=~/\S/}
 angs=fl.select{|e|%w[TEXT MTEXT].include?(e['t']) && e['text'].to_s=~/\A\s*-?\d+(?:[.,]\d+)?\s*°\s*\z/}
 angs=angs.select{|e|e['l'].to_s=~MST_KD_ANG_LAYER} if angs.any?{|e|e['l'].to_s=~MST_KD_ANG_LAYER}
 near=lambda do |list,e,lim|
  best=nil;bd=lim
  list.each{|t|d=Math.hypot(t['x'].to_f-e['x'],t['y'].to_f-e['y']);(best=t;bd=d) if d<bd}
  best
 end
 piles=uniq.map do |e|
  t=near.(nos,e,6.0*e['r']);a=near.(angs,e,4.0*e['r'])
  {'dx'=>e['x'],'dy'=>e['y'],'r'=>e['r'],'no'=>t ? t['text'].to_s.strip : nil,'no_ref'=>t,
   'no_d'=>t ? Math.hypot(t['x'].to_f-e['x'],t['y'].to_f-e['y']) : nil,'ang'=>a ? a['text'].to_s.tr(',','.').to_f : nil}
 end
 # aynı no yazısı iki kazığa bağlanmasın: yazıya en yakın kazık alır
 piles.select{|p|p['no_ref']}.group_by{|p|p['no_ref'].object_id}.each{|_,ps|ps.sort_by{|p|p['no_d']}.drop(1).each{|p|p['no']=nil}}
 piles.each{|p|p.delete('no_ref')}
 {'layer'=>lay,'unit'=>unit,'unit_src'=>src,'dia_mm'=>dia_mm,'radii'=>rads,'piles'=>piles,'no_count'=>piles.count{|p|p['no']},'ang_count'=>piles.count{|p|p['ang']},
  'other_layers'=>cand-[lay]}
end

# taranan kazıklar → yapı yerel kazık listesi. o: origin 'MIN' (sol alt köşe) | 'DXF' (çizim orijini) | 'NO' (en küçük nolu kazık),
#  ox, oy (m, sonra eklenen kaydırma), rot_deg (saat yönü tersine), batter (eğik oranı; 0 = hepsi düşey), prefix
# çizim noktası (çizim birimi) → döndürülmüş çerçeve (m)
def mst_kd_rot(o,u)
 th=o['rot_deg'].to_f*Math::PI/180.0;ct=Math.cos(th);st=Math.sin(th)
 ->(x,y){[(x*ct-y*st)*u,(x*st+y*ct)*u]}
end
# taranan kazıklar → yapı yerel kazık listesi. o: origin 'MIN' (sol alt kazık) | 'DXF' (çizim orijini) | 'NO' (en küçük nolu kazık) |
#  'AKS' (ilk X ve ilk Y aksının kesişimi; ax: mst_kd_axes), ox, oy (m, sonra eklenen kaydırma; AKS'ta kullanılmaz),
#  rot_deg (saat yönü tersine), batter (eğik oranı; 0 = hepsi düşey), prefix
def mst_kd_plan(sc,o={},ax=nil)
 u=sc['unit'].to_f;ps=sc['piles']
 raise 'Kazık yok.' if ps.empty?
 rf=mst_kd_rot(o,u)
 rp=ps.map{|p|rf.(p['dx'],p['dy'])}
 org=case o['origin'].to_s.upcase
  when 'DXF' then [0.0,0.0]
  when 'NO' then k=ps.each_index.select{|q|ps[q]['no']}.min_by{|q|[ps[q]['no'].to_s[/\d+/].to_i,ps[q]['no'].to_s]} || rp.each_index.min_by{|q|rp[q]};rp[k]
  when 'AKS' then raise 'Paftada aks bulunamadı (AKS başlangıcı için en az birer X ve Y aksı gerekli).' unless ax && !ax['x'].empty? && !ax['y'].empty?;[ax['x'][0]['raw'],ax['y'][0]['raw']]
  else [rp.map{|q|q[0]}.min,rp.map{|q|q[1]}.min]
 end
 off=o['origin'].to_s.upcase=='AKS' ? [0.0,0.0] : [o['ox'].to_f,o['oy'].to_f]
 r=pile_batter_ratio(o['batter'])
 pre=o['prefix'].to_s
 ps.each_with_index.map do |p,k|
  xx=rp[k][0]-org[0]+off[0];yy=rp[k][1]-org[1]+off[1]
  bt=(p['ang'] && r>1e-9) ? r : 0.0
  az=p['ang'] ? (90.0-(p['ang']+o['rot_deg'].to_f))%360.0 : 0.0   # çizim açısı (+X'ten saat tersine) → azimut (0 = +Y, saat yönü)
  az=(az+180.0)%360.0 if p['ang'] && o['arrow'].to_s.upcase=='HEAD'   # ok kafa yönünü gösteriyorsa uç ters yönde
  no=p['no'].to_s.strip
  {'x'=>xx.round(4),'y'=>yy.round(4),'batter'=>bt,'az'=>az.round(3),'id'=>(no.empty? ? '' : "#{pre}#{no}"),'dxf_no'=>no,'ang'=>p['ang']}
 end
end

# ---------------------------------------------------------------- KD2 aks çizgileri + aks adları (paftadan)
MST_KD_AX_LINE=/aks|axis|grid/i
MST_KD_AX_NOT=/isim|name|yuvarla|circle|kot|level|ölçü|olcu|dim/i
MST_KD_AX_NAME=/aks.?isim|axis.?name/i
# fl → döndürülmüş çerçevede (m) X aksları (sabit x, düşey çizgi) ve Y aksları (sabit y); ad: çizgi ucundaki balondaki yazı
#  dönüş: {'x'=>[{'name','raw','len'}...] (raw: döndürülmüş çerçeve, m), 'y'=>[...], 'angle'=>baskın açı (°), 'skipped'=>eğik çizgi}
def mst_kd_axes(fl,u,o={})
 rf=mst_kd_rot(o,u)
 ls=fl.select{|e|(e['t']=='LINE' && e['x2']) || (e['t']=='LWPOLYLINE' && e['pts'].to_a.length==2)}
 ls=ls.select{|e|e['l'].to_s=~MST_KD_AX_LINE && !(e['l'].to_s=~MST_KD_AX_NOT)}
 segs=ls.map{|e|a,b=e['t']=='LINE' ? [[e['x'],e['y']],[e['x2'],e['y2']]] : e['pts'];[rf.(*a),rf.(*b)]}.select{|a,b|Math.hypot(b[0]-a[0],b[1]-a[1])>1.0}
 ang=->(a,b){(Math.atan2(b[1]-a[1],b[0]-a[0])*180/Math::PI)%180.0}
 dom=segs.map{|a,b|x=ang.(a,b)%90.0;x>45 ? x-90 : x}
 dom_ang=dom.empty? ? 0.0 : dom.sort[dom.length/2]
 # adlar: balon (daire) merkezi + içindeki yazı; balon yoksa yazının kendisi
 txt=fl.select{|e|%w[TEXT MTEXT].include?(e['t']) && e['l'].to_s=~MST_KD_AX_NAME && e['text'].to_s.strip=~/\A[0-9A-Za-zÇĞİÖŞÜçğıöşü'\-.]{1,6}\z/}
 cir=fl.select{|e|e['t']=='CIRCLE' && e['l'].to_s=~/aks|axis/i && e['l'].to_s=~/yuvarla|circle|isim|name/i}
 lab=txt.map do |t|
  h=[t['h'].to_f,1e-6].max
  dd=->(q){[Math.hypot(q['x']-t['x'],q['y']-t['y']),Math.hypot(q['x']-t['x']-h/2,q['y']-t['y']-h/2)].min}
  c=cir.min_by{|q|dd.(q)}
  c=nil if c && dd.(c)>c['r']*1.6
  pt=c ? rf.(c['x'],c['y']) : rf.(t['x']+h/2,t['y']+h/2)
  {'name'=>t['text'].strip,'p'=>pt,'r'=>(c ? c['r']*u : 2*h*u)}
 end
 out={'x'=>[],'y'=>[],'angle'=>dom_ang,'skipped'=>0,'segs'=>segs.length}
 grp={'x'=>[],'y'=>[]}
 segs.each do |a,b|
  dx=(b[0]-a[0]).abs;dy=(b[1]-a[1]).abs;l=Math.hypot(dx,dy)
  if dx<=l*0.0349 then grp['x'] << [(a[0]+b[0])/2.0,[a[1],b[1]].min,[a[1],b[1]].max]
  elsif dy<=l*0.0349 then grp['y'] << [(a[1]+b[1])/2.0,[a[0],b[0]].min,[a[0],b[0]].max]
  else out['skipped']+=1 end
 end
 %w[x y].each do |k|
  m=[]
  grp[k].sort_by{|c,_,_|c}.each{|c,lo,hi|q=m.last;(q && (c-q[0]).abs<0.05) ? (q[1]=[q[1],lo].min;q[2]=[q[2],hi].max) : m << [c,lo,hi]}
  used={}
  m.each_with_index do |(c,lo,hi),i|
   cand=lab.select do |t|
    pc,pa=k=='x' ? [t['p'][0],t['p'][1]] : [t['p'][1],t['p'][0]]
    (pc-c).abs<[t['r'],0.3].max && (pa<lo+t['r']*3+0.5 || pa>hi-t['r']*3-0.5)
   end
   n=cand.map{|t|t['name']}.find{|x|!used[x.upcase]}
   n||="#{k.upcase}#{i+1}";used[n.upcase]=true
   out[k] << {'name'=>n,'raw'=>c,'len'=>hi-lo,'named'=>!cand.empty?}
  end
 end
 out
end
# kazık listesi + akslar → generate_layout özel aks verisi (gerçek aks adları; nokta = en yakın X / Y aks kesişimi + fark)
def mst_kz_layout_grid(base,piles,ax)
 xs=ax['x'].map{|a|[a['name'],a['c']]};ys=ax['y'].map{|a|[a['name'],a['c']]}
 by=Hash.new{|h,k|h[k]=[]}
 piles.each do |p|
  xn,xc=xs.min_by{|_,c|(p['x']-c).abs};yn,yc=ys.min_by{|_,c|(p['y']-c).abs}
  by[[xn,xc]] << p.merge('yn'=>yn,'yc'=>yc,'xc'=>xc)
 end
 js=by.sort_by{|(_,c),_|c}.map do |(xn,xc),ps|
  {'name'=>xn,'x'=>xc.round(4),'points'=>ps.sort_by{|q|q['y']}.map do |q|
   bt=q['batter'].to_f>1e-9
   {'y'=>q['yc'].round(4),'dx'=>(q['x']-xc).round(4),'dy'=>(q['y']-q['yc']).round(4),'name'=>q['yn'],'selected'=>true,'pile_id'=>q['id'].to_s,
    'orientation_mode'=>(bt ? 'BATTERED' : 'VERTICAL'),'batter_ratio'=>(bt ? q['batter'].to_f.round(6) : 0),'azimuth_deg'=>(bt ? (q['az'].to_f%360.0).round(3) : 0)}
  end}
 end
 base.merge('layout_mode'=>'CUSTOM','custom_axis_json'=>JSON.generate(js),'start_low_count'=>0,'end_low_count'=>0)
end
# aks satırları (aks yöneticisi biçimi): ilk aks 0, aralıklar
def mst_kd_grid_rows(list)
 prev=nil
 list.map{|a|g=prev ? (a['c']-prev).round(4) : 0.0;prev=a['c'];{'name'=>a['name'],'gap_m'=>g,'line_type'=>'AXIS','pattern'=>'DASHED','lineweight'=>'0.02','extent'=>'FINITE'}}
end
# aksların yerel koordinatı (ilk aks 0)
def mst_kd_axes_local!(ax)
 %w[x y].each{|k|o=ax[k].empty? ? 0.0 : ax[k][0]['raw'];ax[k].each{|a|a['c']=(a['raw']-o).round(4)}}
 ax
end
# kazığın en yakın aksa uzaklığı (rapor)
def mst_kd_axis_fit(pl,ax)
 return nil if ax['x'].empty? || ax['y'].empty?
 d=pl.map{|p|[ax['x'].map{|a|(p['x']-a['c']).abs}.min,ax['y'].map{|a|(p['y']-a['c']).abs}.min]}
 {'max_dx'=>d.map(&:first).max,'max_dy'=>d.map(&:last).max}
end

# ok yönü belirsiz (paftada eğim kesitte): AUTO → her iki yorum için çakışma sayısı, az olan seçilir
def mst_kd_plan_auto(sc,o,base,ax=nil)
 d=base['diameter_mm'].to_f/1000.0;l=base['length_m'].to_f;t=base['top_elevation_m'].to_f
 return [mst_kd_plan(sc,o,ax),nil] unless o['arrow'].to_s.upcase=='AUTO' || o['arrow'].to_s.strip.empty?
 a=mst_kd_plan(sc,o.merge('arrow'=>'TOE'),ax);b=mst_kd_plan(sc,o.merge('arrow'=>'HEAD'),ax)
 ca=mst_kz_clashes(a,d,l,t);cb=mst_kz_clashes(b,d,l,t)
 pick=cb['count']<ca['count'] ? 'HEAD' : 'TOE'
 [pick=='HEAD' ? b : a,{'pick'=>pick,'toe'=>ca,'head'=>cb}]
end

def mst_kd_text(sc,pl,base,file,auto=nil)
 bt=pl.count{|p|p['batter']>0}
 l=["KAZIK DİSPOZİSYONU — #{File.basename(file.to_s)} (model değişmedi — önizleme)",
    "Katman: #{sc['layer']}#{sc['other_layers'].empty? ? '' : " (diğer: #{sc['other_layers'].first(3).join(', ')})"}",
    "Birim: 1 çizim birimi = #{mst_dxf_unit_name(sc['unit'])} (#{sc['unit_src']}) · kazık çapı Ø#{format('%.1f',sc['dia_mm'])} mm",
    "Kazık: #{pl.length} · numaralı #{sc['no_count']} · açı yazılı (eğik) #{sc['ang_count']} → eğik #{bt}, düşey #{pl.length-bt}"]
 xs=pl.map{|p|p['x']};ys=pl.map{|p|p['y']}
 l << format('Yerleşim alanı: X %.2f … %.2f m · Y %.2f … %.2f m',xs.min,xs.max,ys.min,ys.max)
 angs=pl.select{|p|p['ang']}.map{|p|p['ang'].round}.group_by{|x|x}.map{|k,v|"#{k}° × #{v.length}"}
 l << "Eğik kazık çizim açıları: #{angs.first(8).join(', ')}" unless angs.empty?
 dup=pl.map{|p|p['id']}.reject(&:empty?).group_by{|x|x}.select{|_,v|v.length>1}.keys
 l << "UYARI: tekrarlanan kazık no: #{dup.first(6).join(', ')} — bunlara yeni no verilecek." unless dup.empty?
 if auto
  l << format('Eğik kazık oku: %s (çakışan çift: ok = alt uç → %d, ok = kafa → %d). Eğim paftada yok; kesitten kontrol edin.',
   auto['pick']=='HEAD' ? 'kazık kafasını gösteriyor, alt uç ters yönde' : 'alt ucun gittiği yön',auto['toe']['count'],auto['head']['count'])
 end
 c=mst_kz_clashes(pl,base['diameter_mm'].to_f/1000.0,base['length_m'].to_f,base['top_elevation_m'].to_f)
 l << format('En yakın iki kazık (yüzeyden yüzeye): %.2f m · çakışan çift: %d%s',c['min'],c['count'],c['count']>0 ? ' — UYARI: eğim / boy / yönü kontrol edin (kazıklar yine de oluşturulur, sonra düzenlenebilir)' : '') if c['min']<1e8
 c['pairs'].first(3).each{|i,j|l << "  çakışan: #{pl[i]['id']} ↔ #{pl[j]['id']}"}
 l << '' << 'İlk kazıklar:'
 pl.sort_by{|p|[p['x'],p['y']]}.first(6).each{|p|l << format('  %-10s X %9.3f  Y %9.3f  %s',p['id'].empty? ? '(yeni no)' : p['id'],p['x'],p['y'],p['batter']>0 ? format('eğik 1/%.1f azimut %.0f°',1.0/p['batter'],p['az']) : 'düşey')}
 l.join("\n")
end

MST_KD_FIELDS=[['layer','Kazık katmanı (boş = otomatik)'],['axes','Aksları da al: EVET / HAYIR (aks çizgisi + aks adı katmanları → Aks Yöneticisi)'],
 ['origin','Başlangıç: AKS (ilk X / ilk Y aksı) / MIN (sol alt kazık) / NO (en küçük nolu kazık) / DXF (çizim orijini)'],
 ['ox','Sonra kaydır X (m; AKS başlangıcında kullanılmaz)'],['oy','Sonra kaydır Y (m; AKS başlangıcında kullanılmaz)'],['rot_deg','Döndür: AUTO (akslar düz olacak şekilde) veya ° (saat yönü tersine)'],
 ['batter','Eğik kazık eğimi (ör. 1/6; 0 = hepsi düşey)'],['arrow','Eğik kazık oku: AUTO / TOE (alt uç yönü) / HEAD (kafa yönü)'],['prefix','Kazık no öneki (paftadaki no başına)']].freeze
MST_KD_TYPES=%w[CIRCLE TEXT MTEXT INSERT ATTRIB LINE LWPOLYLINE].freeze

def mst_kd_yes?(v)
 v.to_s.strip.upcase=~/\A(E|EVET|Y|YES|1|TRUE)\z/ ? true : false
end
# AUTO dönüş: baskın aks açısının tersi (akslar X / Y'ye paralel olur)
def mst_kd_auto_rot(ax0)
 (ax0 && ax0['segs'].to_i>0) ? (-ax0['angle'].to_f).round(4) : 0.0
end
# hedef: Aks Yöneticisi'nde açık olan sistem ve o sistemin aktif yapısı (ızgara anahtarı "yapı::yapı", yöneticinin okuduğu yer)
def mst_kd_grid_target(b=nil,model=Sketchup.active_model)
 sys=model.get_attribute(DICT,'project_system_type','ISKELE').to_s.upcase
 sys='ISKELE' unless %w[DOLFEN ISKELE RIHTIM].include?(sys)
 st=mst_active_structure_for_system(sys,model)
 {'ano'=>st,'zone'=>st,'sys'=>sys}
end
# aks ızgarasını kaydet + görselini çiz (çağıran işlem içinde)
def mst_kd_apply_grid!(ax,tg,model=Sketchup.active_model)
 mst_save_axis_grid({'ano'=>tg['ano'],'zone'=>tg['zone'],'x'=>mst_kd_grid_rows(ax['x']),'y'=>mst_kd_grid_rows(ax['y']),'x_dir'=>'+X','y_dir'=>'+Y'},model)
 mst_show_grid_visual(tg['ano'],model,tg['zone'],false,tg['sys'])
end
def mst_kd_axes_text(ax,pl,tg,model=Sketchup.active_model)
 nm=->(l){l.length<=8 ? l.map{|a|a['name']}.join(' ') : "#{l.first(4).map{|a|a['name']}.join(' ')} … #{l.last(3).map{|a|a['name']}.join(' ')}"}
 l=['',"AKSLAR (paftadan): X #{ax['x'].length} aks [#{nm.(ax['x'])}] · Y #{ax['y'].length} aks [#{nm.(ax['y'])}]"]
 un=ax['x'].count{|a|!a['named']}+ax['y'].count{|a|!a['named']}
 l << "  adı bulunamayan #{un} aksa ad verildi (X1… / Y1…); Aks Yöneticisi'nden değiştirebilirsiniz." if un>0
 l << format('  pafta %.3f° döndürüldü (akslar X / Y\'ye paralel)',ax['rot'].to_f) if ax['rot'].to_f.abs>1e-3
 l << format('  UYARI: akslar döndürmeden sonra %.2f° eğik kalıyor — Döndür = AUTO deneyin',ax['angle']) if ax['angle'].abs>0.05
 l << "  eğik / kısa çizgi atlandı: #{ax['skipped']}" if ax['skipped']>0
 f=mst_kd_axis_fit(pl,ax)
 l << format('  kazık → en yakın aks kesişimi: en büyük fark X %.2f m, Y %.2f m',f['max_dx'],f['max_dy']) if f
 l << "  UYARI: bazı kazıklar akslardan uzak (> 2 m) — aks katmanını kontrol edin." if f && (f['max_dx']>2 || f['max_dy']>2)
 dp=pl.group_by{|p|[ax['x'].min_by{|a|(p['x']-a['c']).abs}['name'],ax['y'].min_by{|a|(p['y']-a['c']).abs}['name']]}.select{|_,v|v.length>1}
 l << "  aynı aks kesişimine bağlanan kazık grubu: #{dp.length} (ör. #{dp.keys.first(3).map{|a,b|"#{a}/#{b}"}.join(', ')}) — farkla yerleşir" unless dp.empty?
 key=mst_axis_grid_key(tg['ano'],tg['zone'])
 l << "Aks ızgarası → Aks Yöneticisi: #{tg['sys']} / #{tg['ano']}#{mst_axis_grids(model).key?(key) ? ' — UYARI: bu yapının mevcut aks ızgarası DEĞİŞTİRİLECEK' : ' (yeni)'}; ızgara görseli de çizilir."
 l << "Kazıklar bu yapıya yerleşir (yapının konumu Aks Yöneticisi'ndeki yerleşimden). Başka yapı için önce Aks Yöneticisi'nde onu seçip kaydedin."
 l.join("\n")
end

def mst_kd_ui(path=nil)
 model=Sketchup.active_model
 path||=UI.openpanel('Kazık yerleşim paftası (DXF)',nil,'DXF|*.dxf||')
 return 0 unless path && File.file?(path)
 t0=Time.now
 dx=mst_dxf_read(path,MST_KD_TYPES)
 fl=mst_dxf_flatten(dx)
 last=(JSON.parse(model.get_attribute(DICT,'mst_kd_last_json','{}').to_s) rescue {})
 last={} unless last.is_a?(Hash)
 sc0=(mst_kd_scan(dx,fl,last['layer']) rescue nil)
 ax0=sc0 ? mst_kd_axes(fl,sc0['unit'].to_f,{'rot_deg'=>0}) : nil
 has_ax=ax0 && ax0['segs'].to_i>=2   # eğik paftada akslar AUTO dönmeden sonra ayrışır
 dflt={'layer'=>'','axes'=>(has_ax ? 'EVET' : 'HAYIR'),'origin'=>(has_ax ? 'AKS' : 'MIN'),'ox'=>'0','oy'=>'0','rot_deg'=>(has_ax ? 'AUTO' : '0'),'batter'=>'1/6','arrow'=>'AUTO','prefix'=>'P-'}
 keep=last.key?('axes') ? last : last.reject{|k,_|%w[origin rot_deg].include?(k)}   # v0.50 kaydı: aks varsayılanları geçerli
 dflt.merge!(keep.select{|k,_|dflt.key?(k)})
 unless has_ax
  dflt['axes']='HAYIR';dflt['origin']='MIN' if dflt['origin'].to_s.upcase=='AKS';dflt['rot_deg']='0' if dflt['rot_deg'].to_s.upcase=='AUTO'
 end
 r=UI.inputbox(MST_KD_FIELDS.map{|_,l|l},MST_KD_FIELDS.map{|k,_|dflt[k].to_s},'Kazık Dispozisyonu — DXF')
 return 0 unless r
 o=Hash[MST_KD_FIELDS.each_with_index.map{|(k,_),i|[k,r[i].to_s.strip]}]
 save=o.dup
 use_ax=mst_kd_yes?(o['axes'])
 %w[ox oy].each{|k|o[k]=Float(o[k].tr(',','.')) rescue raise("#{k}: sayı olmalı.")}
 sc=mst_kd_scan(dx,fl,o['layer'])
 if o['rot_deg'].upcase=='AUTO'
  o['rot_deg']=mst_kd_auto_rot(mst_kd_axes(fl,sc['unit'].to_f,{'rot_deg'=>0}))
 else
  o['rot_deg']=(Float(o['rot_deg'].tr(',','.')) rescue raise('Döndür: AUTO veya sayı olmalı.'))
 end
 ax=nil
 if use_ax
  ax=mst_kd_axes(fl,sc['unit'].to_f,o)
  raise "Paftada aks bulunamadı (X #{ax['x'].length}, Y #{ax['y'].length}). Aks çizgisi katmanı 'aks' / 'axis' / 'grid' içermeli; ya da 'Aksları da al' = HAYIR seçin." if ax['x'].empty? || ax['y'].empty?
  o['origin']='AKS';ax['rot']=o['rot_deg']
  mst_kd_axes_local!(ax)
 elsif o['origin'].upcase=='AKS'
  ax=mst_kd_axes(fl,sc['unit'].to_f,o)
 end
 base=mst_kz_base_data(model).merge('diameter_mm'=>sc['dia_mm'])
 b=mst_kz_ask_pile(base,'DXF kazıkları — özellikler (çap paftadan)');return 0 unless b
 pl,auto=mst_kd_plan_auto(sc,o,b,ax)
 ids=mst_kz_existing_ids(model);seen={}
 pre=o['prefix'].to_s;no=mst_kz_next_no(pre.empty? ? 'P-' : pre,ids+pl.map{|p|p['id']})
 pl.each{|p| if p['id'].empty? || ids.include?(p['id']) || seen[p['id']] then p['id']="#{pre.empty? ? 'P-' : pre}#{no.to_s.rjust(3,'0')}";no+=1 end;seen[p['id']]=true}
 tg=use_ax ? mst_kd_grid_target(b,model) : nil
 txt=mst_kd_text(sc,pl,b,path,auto)
 txt+=mst_kd_axes_text(ax,pl,tg,model) if use_ax
 txt+=format("\n(okuma %.1f s)",Time.now-t0);puts txt
 q=use_ax ? 'Aks ızgarası kurulsun ve kazıklar akslara bağlanarak oluşturulsun mu? (tek Geri Al)' : 'Kazıklar oluşturulsun mu? (tek Geri Al)'
 return 0 unless UI.messagebox("#{txt[0,3000]}\n\n#{q}",MB_YESNO)==IDYES
 model.set_attribute(DICT,'mst_kd_last_json',JSON.generate(save.merge('file'=>File.basename(path))))
 data=use_ax ? mst_kz_layout_grid(b,pl,ax) : mst_kz_layout_data(b,pl,'D')
 data['prefix']=pre.empty? ? 'P-' : pre
 data.merge!('placement_system'=>tg['sys'],'placement_structure'=>tg['ano'],'structure_zone'=>tg['ano']) if use_ax
 n0=mst_kz_existing_ids(model).length
 generate_layout(data)
 made=mst_kz_existing_ids(model).length-n0
 if use_ax && made>0
  # kazık yerleşimiyle aynı Geri Al adımı (saydam işlem önceki işleme eklenir)
  model.start_operation('MST Aks Izgarası (DXF)',true,false,true)
  begin
   mst_kd_apply_grid!(ax,tg,model)
   model.commit_operation
  rescue => ge
   # v0.51.5 K12: saydam işlem önceki (kazık) işlemine birleşir; abort onu da geri alabilir → commit + bildirim
   model.commit_operation
   UI.messagebox("Kazıklar oluşturuldu, ancak aks ızgarası kurulamadı: #{ge.message}\nIzgara kısmen yazılmış olabilir; Geri Al kazıklarla birlikte geri alır.")
  end
 end
 made
rescue => ex
 UI.messagebox("Kazık dispozisyonu (DXF): #{ex.message}")
 0
end

# ---------------------------------------------------------------- KF1 filiz boyu BK'dan
# kazığın üstündeki BK: kazık kafası BK'nın plan kutusunda ve kotları arasında
def mst_kf_beam_for(p,hbs)
 x=p.get_attribute(DICT,'global_x_m',p.get_attribute(DICT,'axis_x_m',0)).to_f
 top=p.get_attribute(DICT,'top_elevation_m',0).to_f
 c=p.respond_to?(:bounds) ? p.bounds.center : nil
 hbs.find do |b|
  bb=b.bounds
  inside=c ? (c.x>=bb.min.x-1 && c.x<=bb.max.x+1 && c.y>=bb.min.y-1 && c.y<=bb.max.y+1) : false
  bot=b.get_attribute(DICT,'bottom_elevation_m',0).to_f;tp=b.get_attribute(DICT,'top_elevation_m',bot+b.get_attribute(DICT,'height_m',0).to_f).to_f
  inside && top>=bot-0.5 && top<=tp
 end
end
# filiz = BK üstü − kazık üstü − BK pas payı − üst ağ payı (2 × üst Ø + 2 cm); kazık BK üstüne çok yakınsa 0 (en çok 5 m)
def mst_kf_anchor(bk_top,pile_top,cover_m,top_d_m=0.032)
 [[bk_top-pile_top-cover_m-2*top_d_m-0.02,0.0].max,5.0].min.round(3)
end
def mst_kf_fit_ui
 model=Sketchup.active_model
 ps=(selected_piles rescue []).map{|x|x[0]}.uniq.select{|p|p.valid? && mst_pile_rebar_active(p)}
 raise 'Donatı kafesi olan kazık(lar) seçin.' if ps.empty?
 all=[];collect_elements(model.entities,all);hbs=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 cov=mst_rs_get('cover_bk_mm',model).to_f/1000.0
 plan=ps.map do |p|
  b=mst_kf_beam_for(p,hbs);next [p,nil,nil] unless b
  bt=b.get_attribute(DICT,'top_elevation_m',0).to_f
  td=((JSON.parse(b.get_attribute(DICT,'hb_rebar_json','{}').to_s)['top'] || {})['dia_mm'] rescue nil).to_f/1000.0;td=0.032 if td<=0
  [p,b,mst_kf_anchor(bt,p.get_attribute(DICT,'top_elevation_m',0).to_f,cov,td)]
 end
 ok=plan.select{|_,b,_|b}
 raise 'Seçili kazıkların üstünde BK bulunamadı.' if ok.empty?
 txt=ok.first(10).map{|p,b,a|format('%s → %s: filiz %.2f m (önce %.2f)%s',p.get_attribute(DICT,'pile_id',''),element_visible_id(b),a,mst_pile_rebar_params_of(p)['anchor_m'],a<0.3 ? ' — kazık üstü BK üstüne çok yakın' : '')}.join("\n")
 txt+="\n… (#{ok.length} kazık)" if ok.length>10
 txt+="\nBK bulunamayan: #{plan.length-ok.length}" if plan.length>ok.length
 return 0 unless UI.messagebox("Kazık filizi BK'ya göre (BK üstü − pas payı #{(cov*1000).round} mm − üst ağ payı):\n\n#{txt}\n\nUygulansın mı? (tek Geri Al)",MB_YESNO)==IDYES
 model.start_operation('MST Kazık Filizi BK\'ya Göre',true)
 begin
  ok.each do |p,_,a|
   pr=mst_pile_rebar_params_of(p).merge('anchor_m'=>a)
   p.set_attribute(DICT,'pile_rebar_json',mst_pile_rebar_json(pr))
   p.is_a?(Sketchup::ComponentInstance) ? mst_pile_component_refresh!(p) : (mst_pile_rebar_refresh!(p);sync_pile_bim_qto(p))
  end
  commit_with_dependencies(model)
 rescue
  model.abort_operation;raise
 end
 ok.length
rescue => ex
 UI.messagebox("Kazık filizi: #{ex.message}")
 0
end

end
end
