# frozen_string_literal: true
# v0.49 SP1 — İş programı (modelden): faaliyetler eleman eleman, miktarlar metrajdan, süre = miktar / verim,
# sıra kurallarla (kazık → kazık içi → BK → bekleme → prekast → döşeme → bitiş işleri), ekip / ekipman sayısıyla
# kaynak kısıtlı yerleşim, takvim (haftalık gün + hava / deniz kaybı). Çıktı: Gantt (HTML), Excel, haftalık malzeme +
# ekip, aylık hakediş tahmini (BOQ birim fiyatlarıyla), 4D renklendirme / hafta durumu.
# Verimlerin hepsi değiştirilebilir; yanında kaynağı yazar ("kaynak" / "tahmin").
require 'json'
require 'date'
module MAG
module MarineStructuresTools

# [anahtar, etiket, varsayılan, kaynak]
MST_SP_RATES=[
 ['pile_rate','Kazık çakımı (adet / gün, platform başına)',3.0,'tahmin — denizde çakma çelik boru 2–4/gün; karada 600 mm boru 22/gün (Methvin)'],
 ['pile_rigs','Kazık platformu / barç sayısı',1,'proje'],
 ['infill_rate','Kazık içi donatı + beton (kazık / gün, ekip başına)',4.0,'tahmin 3–6/gün'],
 ['infill_crews','Kazık içi ekip sayısı',1,'proje'],
 ['infill_lag','Çakımdan kazık içine geçme (gün)',2,'tahmin'],
 ['bk_cycle','BK döngüsü: kalıp + donatı + döküm (gün / BK, ekip başına)',6.0,'tahmin 5–7 gün'],
 ['bk_crews','BK ekip sayısı',1,'proje'],
 ['bk_cure','BK dökümünden prekast yüküne bekleme (gün)',7,'tahmin'],
 ['pc_rate','Prekast montajı (adet / gün, vinç başına)',8.0,'tahmin 6–12/gün, deniz durumuna bağlı'],
 ['pc_cranes','Montaj vinci sayısı',1,'proje'],
 ['pc_prod','Prekast üretimi (adet / gün)',6.0,'tahmin'],
 ['pc_cure','Prekast üretiminden montaja (gün)',14,'tahmin'],
 ['deck_rate','Döşeme betonu (m³ / gün, pompa başına)',150.0,'tahmin 100–250 m³/gün'],
 ['deck_crews','Döşeme ekibi / pompa sayısı',1,'proje'],
 ['fin_rate','Tretuvar / kronman / kaplama (m³ / gün)',40.0,'tahmin'],
 ['days_week','Haftalık çalışma günü',6,'proje'],
 ['weather','Hava / deniz kaybı (%)',15,'tahmin — Marmara / Ege 10–20, Karadeniz kışın 30–40'],
 ['crew_pile','Kazık ekibi (kişi / platform)',10,'tahmin'],
 ['crew_infill','Kazık içi ekibi (kişi)',6,'tahmin'],
 ['crew_bk','BK ekibi (kişi)',14,'tahmin'],
 ['crew_pc','Prekast montaj ekibi (kişi / vinç)',6,'tahmin'],
 ['crew_deck','Döşeme ekibi (kişi)',12,'tahmin'],
 ['crew_fin','Bitiş işleri ekibi (kişi)',8,'tahmin'],
 ['crew_site','Sabit saha kadrosu: şef, teknik, güvenlik (kişi)',8,'tahmin — ÇED örnekleri: 211 m iskele 30 kişi, 410 m iskele + rıhtım 80 kişi']
].freeze
MST_SP_KINDS=[['pile','Kazık çakımı'],['infill','Kazık içi donatı + beton'],['bk','Başlık kirişi'],['pcprod','Prekast üretimi'],['pc','Prekast montajı'],
 ['deck','Döşeme'],['fin','Tretuvar / kronman / kaplama']].freeze
MST_SP_TYPES={'steel_pipe_pile'=>'pile','bored_pile'=>'pile','pile_infill_concrete'=>'infill','head_beam'=>'bk','flat_precast'=>'pc','channel_precast'=>'pc',
 'crane_precast'=>'pc','deck_slab'=>'deck','curb'=>'fin','crown_wall'=>'fin','deck_topping'=>'fin'}.freeze
# BOQ kalemi → faaliyet türü (hakediş tahmini dağıtımı)
MST_SP_BOQ_MAP={'MOBILIZATION'=>:start,'FORMWORK_CAST'=>%w[bk deck],'FORMWORK_PRECAST'=>%w[pcprod],'REBAR'=>:rebar,'HB_DECK_CONCRETE'=>%w[bk deck],
 'CAST_C35_45_OTHER'=>%w[fin],'PRECAST_C35_45'=>%w[pcprod],'PRECAST_INSTALL'=>%w[pc],'TOPPING_AREA'=>%w[fin],'TOPPING_CONCRETE'=>%w[fin],
 'PILE_INFILL'=>%w[infill],'PILE_STEEL'=>%w[pile],'PILE_MANIP'=>%w[pile],'PILE_RINGS'=>%w[pile],'PILE_SPLICES'=>%w[pile],'PILE_DRIVING'=>%w[pile],
 'PILE_PE'=>%w[pile],'PILE_DRILLING'=>%w[pile],'CROWN_FORMWORK'=>%w[fin],'CROWN_CONCRETE'=>%w[fin]}.freeze

def mst_sp_defaults;Hash[MST_SP_RATES.map{|k,_,v,_|[k,v.to_f]}].merge('start'=>Date.today.strftime('%Y-%m-%d'),'reverse'=>0.0);end
def mst_sp_params(model=Sketchup.active_model)
 h=(JSON.parse(model.get_attribute(DICT,'sp_params_json','{}').to_s) rescue {})
 p=mst_sp_defaults;h.each{|k,v|p[k]=(k=='start' ? v.to_s : v.to_f) if p.key?(k)};p
end

# ---------------------------------------------------------------- takvim (iş günü → tarih)
# iş günü indeksi (0..) → takvim günü: haftanın çalışılmayan günleri (Pazar, 5 günde Cumartesi de) ve
# hava / deniz kaybı (düzenli dağıtılmış) atlanır
def mst_sp_calendar(start,days_week,weather,n)
 d=Date.parse(start.to_s) rescue Date.today
 out=[];k=0;lost=0.0;wf=[[weather.to_f/100.0,0.0].max,0.9].min;dw=[[days_week.to_i,1].max,7].min
 while out.length<n
  wd=d.cwday   # 1 = Pazartesi … 7 = Pazar
  if wd<=dw
   lost+=wf
   if lost>=1.0 then lost-=1.0 else out << d end
  end
  d+=1;k+=1
  raise 'Takvim hesaplanamadı.' if k>200000
 end
 out
end

# ---------------------------------------------------------------- faaliyetler
def mst_sp_center(e)
 b=e.bounds;c=b.center
 [c.x.to_f/39.37007874015748,c.y.to_f/39.37007874015748]
end
def mst_sp_box(e)
 b=e.bounds;f=39.37007874015748
 [b.min.x.to_f/f,b.min.y.to_f/f,b.max.x.to_f/f,b.max.y.to_f/f]
end
def mst_sp_overlap?(a,b,pad=0.3);a[0]-pad<b[2] && b[0]-pad<a[2] && a[1]-pad<b[3] && b[1]-pad<a[3];end
def mst_sp_items(all)
 all.map do |e|
  k=MST_SP_TYPES[e.get_attribute(DICT,'element_type','').to_s];next nil unless k
  vol=(qto3_quantity(e,:concrete_m3) rescue e.get_attribute(DICT,'concrete_volume_m3',0).to_f).to_f
  it={e:e,kind:k,id:element_visible_id(e),c:mst_sp_center(e),box:mst_sp_box(e),vol:vol,rebar_kg:(mst_element_rebar(e)['kg'] rescue 0.0).to_f}
  if k=='bk'   # v0.50: VK / BBK rolü, kademeli döküm
   it[:role]=e.get_attribute(DICT,'beam_role','').to_s
   it[:stage]=(respond_to?(:mst_hb_stage_q) ? mst_hb_stage_q(e) : nil) rescue nil
  end
  it
 end.compact
end
# ana ilerleme ekseni: elemanların plan dağılımının uzun yönü; reverse=1 ters yönden
def mst_sp_axis(items,reverse=false)
 return [1.0,0.0] if items.length<2
 xs=items.map{|i|i[:c][0]};ys=items.map{|i|i[:c][1]};mx=xs.sum/xs.length;my=ys.sum/ys.length
 sxx=xs.sum{|x|(x-mx)**2};syy=ys.sum{|y|(y-my)**2};sxy=xs.zip(ys).sum{|x,y|(x-mx)*(y-my)}
 t=0.5*Math.atan2(2*sxy,sxx-syy);a=[Math.cos(t),Math.sin(t)]
 reverse ? a.map{|x|-x} : a
end

# seri yerleşim: her türde elemanlar eksen sırasıyla; başlama = max(öncüller hazır, en erken boş ekip)
def mst_sp_schedule(items,prm)
 ax=mst_sp_axis(items,prm['reverse'].to_i==1)
 st=->(i){i[:c][0]*ax[0]+i[:c][1]*ax[1]}
 by=items.group_by{|i|i[:kind]};by.each_value{|a|a.sort_by!{|i|st.(i)}}
 pool=->(n){Array.new([n.to_i,1].max,0.0)}
 take=lambda do |pl,ready,dur|
  k=pl.each_index.min_by{|j|[[pl[j],ready].max,j]};s=[pl[k],ready].max;pl[k]=s+dur;[s,s+dur,k]
 end
 acts=[]
 put=->(i,kind,s,f,unit,qty,unit_name){a={id:i ? i[:id] : '',kind:kind,s:s,f:f,unit:unit,qty:qty,qty_unit:unit_name,item:i};acts << a;a}
 # kazık
 pl=pool.(prm['pile_rigs']);pdur=1.0/[prm['pile_rate'],0.01].max
 pfin={}
 (by['pile'] || []).each{|i|s,f,u=take.(pl,0.0,pdur);put.(i,'pile',s,f,u,1,'adet');pfin[i]=f}
 # kazık içi: kendi kazığı (plan konumu ile eşleşen) + bekleme
 pl=pool.(prm['infill_crews']);idur=1.0/[prm['infill_rate'],0.01].max
 ifin={}
 (by['infill'] || []).each do |i|
  near=(by['pile'] || []).min_by{|p|(p[:c][0]-i[:c][0])**2+(p[:c][1]-i[:c][1])**2}
  rd=near ? pfin[near].to_f+prm['infill_lag'] : 0.0
  s,f,u=take.(pl,rd,idur);put.(i,'infill',s,f,u,i[:vol].round(2),'m³');ifin[i]=f
 end
 piles_done=->(box){
  ps=(by['pile'] || []).select{|p|mst_sp_overlap?(box,p[:box])};is=(by['infill'] || []).select{|p|mst_sp_overlap?(box,p[:box])}
  (ps.map{|p|pfin[p]+(is.empty? ? prm['infill_lag']+idur : 0.0)}+is.map{|p|ifin[p]}).max || 0.0}
 # BK
 pl=pool.(prm['bk_crews']);bfin={}
 bks,links=(by['bk'] || []).partition{|i|!%w[VK BBK].include?(i[:role].to_s)}
 bk_one=lambda do |i,ready|
  st=i[:stage]
  if st   # v0.50 KD2: iki kademe (her biri döngünün %60'ı) + kademe arası bekleme
   d=prm['bk_cycle']*0.6;sh=i[:vol]>0 ? st['v1']/i[:vol] : 0.5
   i1=i.merge(id:"#{i[:id]} (1. kademe)",vol:st['v1'],rebar_kg:i[:rebar_kg]*sh);i2=i.merge(id:"#{i[:id]} (2. kademe)",vol:st['v2'],rebar_kg:i[:rebar_kg]*(1-sh))
   s,f,u=take.(pl,ready,d);put.(i1,'bk',s,f,u,st['v1'].round(2),'m³')
   s,f,u=take.(pl,f+st['gap'].to_f,d);put.(i2,'bk',s,f,u,st['v2'].round(2),'m³');bfin[i]=f
  else
   s,f,u=take.(pl,ready,prm['bk_cycle']);put.(i,'bk',s,f,u,i[:vol].round(2),'m³');bfin[i]=f
  end
 end
 bks.each{|i|bk_one.(i,piles_done.(i[:box]))}
 # v0.50 VK1: vinç / boylama kirişi dayandığı BK'lar bitince
 links.each{|i|bk_one.(i,bks.select{|b|mst_sp_overlap?(i[:box],b[:box])}.map{|b|bfin[b]}.max || piles_done.(i[:box]))}
 bk_done=->(box){(by['bk'] || []).select{|b|mst_sp_overlap?(box,b[:box])}.map{|b|bfin[b]}.max}
 # prekast üretimi (montaj sırasıyla) + montaj
 pcs=by['pc'] || [];prod=1.0/[prm['pc_prod'],0.01].max;pp=0.0;prdy={}
 pcs.each_with_index{|i,k|s=pp;f=s+prod;pp=f;put.(i,'pcprod',s,f,0,1,'adet');prdy[i]=f+prm['pc_cure']}
 pl=pool.(prm['pc_cranes']);cdur=1.0/[prm['pc_rate'],0.01].max;cfin={}
 pcs.each do |i|
  bd=bk_done.(i[:box]);rd=[(bd ? bd+prm['bk_cure'] : 0.0),prdy[i]].max
  s,f,u=take.(pl,rd,cdur);put.(i,'pc',s,f,u,1,'adet');cfin[i]=f
 end
 # döşeme: üstündeki / altındaki prekastlar ve BK'lar bittikten sonra
 pl=pool.(prm['deck_crews']);dfin={}
 (by['deck'] || []).each do |i|
  rd=([bk_done.(i[:box])]+pcs.select{|p|mst_sp_overlap?(i[:box],p[:box],0.0)}.map{|p|cfin[p]}).compact.max || 0.0
  dur=[i[:vol]/[prm['deck_rate'],0.1].max,1.0].max
  s,f,u=take.(pl,rd,dur);put.(i,'deck',s,f,u,i[:vol].round(2),'m³');dfin[i]=f
 end
 # bitiş işleri: döşemeden sonra
 pl=pool.(1)
 (by['fin'] || []).each do |i|
  rd=(by['deck'] || []).select{|d|mst_sp_overlap?(i[:box],d[:box],0.0)}.map{|d|dfin[d]}.max || (dfin.values.max || 0.0)
  dur=[i[:vol]/[prm['fin_rate'],0.1].max,0.5].max
  s,f,u=take.(pl,rd,dur);put.(i,'fin',s,f,u,i[:vol].round(2),'m³')
 end
 total=acts.map{|a|a[:f]}.max || 0.0
 cal=mst_sp_calendar(prm['start'],prm['days_week'],prm['weather'],total.ceil+2)
 acts.each{|a|a[:sd]=cal[a[:s].floor];a[:fd]=cal[[a[:f].ceil-1,a[:s].floor].max]}
 {acts:acts,days:total,cal:cal,axis:ax,finish:(acts.empty? ? nil : cal[[total.ceil-1,0].max]),start:cal[0]}
end

# ---------------------------------------------------------------- haftalık / aylık
def mst_sp_weekly(sch,prm)
 crew={'pile'=>prm['crew_pile'],'infill'=>prm['crew_infill'],'bk'=>prm['crew_bk'],'pcprod'=>0,'pc'=>prm['crew_pc'],'deck'=>prm['crew_deck'],'fin'=>prm['crew_fin']}
 wk=Hash.new{|h,k|h[k]={'concrete'=>0.0,'rebar_t'=>0.0,'piles'=>0,'precast'=>0,'crew'=>Hash.new{|x,y|x[y]=[]}}}
 sch[:acts].each do |a|
  w=a[:fd].strftime('%G-H%V')
  if a[:item] && %w[infill bk deck fin].include?(a[:kind])
   wk[w]['concrete']+=a[:item][:vol];wk[w]['rebar_t']+=a[:item][:rebar_kg]/1000.0
  end
  wk[w]['piles']+=1 if a[:kind]=='pile'
  wk[w]['precast']+=1 if a[:kind]=='pc'
  (a[:s].floor..[a[:f].ceil-1,a[:s].floor].max).each{|d|dd=sch[:cal][d];next unless dd;wk[dd.strftime('%G-H%V')]['crew'][[a[:kind],a[:unit]]] << 1} unless a[:kind]=='pcprod'
 end
 wk.keys.sort.map do |w|
  x=wk[w];men=x['crew'].keys.sum{|k,_|crew[k].to_f}+prm['crew_site']
  {'week'=>w,'concrete_m3'=>x['concrete'],'rebar_t'=>x['rebar_t'],'piles'=>x['piles'],'precast'=>x['precast'],'crews'=>x['crew'].keys.length,'workers'=>men.round}
 end
end
# BOQ satırları (tutarlı olanlar) faaliyetlere dağıtılır; ay = faaliyetin bittiği ay
def mst_sp_monthly(sch,boq)
 acts=sch[:acts];return [] if acts.empty?
 mon=Hash.new(0.0)
 wsum=->(list,f){s=list.sum{|a|f.(a)};s}
 boq.each do |r|
  tot=r[:total].to_f;next if tot<=0
  m=MST_SP_BOQ_MAP[r[:source].to_s]
  if m==:start then mon[sch[:start].strftime('%Y-%m')]+=tot;next end
  list,f=if m==:rebar then [acts.select{|a|a[:item] && a[:kind]!='pcprod'},->(a){a[:item][:rebar_kg]}]
   elsif m.is_a?(Array) then [acts.select{|a|m.include?(a[:kind])},->(a){a[:item] ? [a[:item][:vol],(a[:qty_unit]=='adet' ? 1.0 : 0.0)].max : 1.0}]
   else [acts,->(_){1.0}] end
  list=acts if list.empty?;ws=wsum.(list,f);ws=list.length.to_f if ws<=0
  list.each{|a|w=f.(a);w=1.0 if ws==list.length.to_f && w<=0;mon[a[:fd].strftime('%Y-%m')]+=tot*w/ws}
 end
 cum=0.0;all=mon.values.sum
 mon.keys.sort.map{|k|cum+=mon[k];{'month'=>k,'amount'=>mon[k],'cum'=>cum,'pct'=>all>0 ? 100.0*cum/all : 0.0}}
end

# ---------------------------------------------------------------- rapor
def mst_sp_label(k);(MST_SP_KINDS.find{|x,_|x==k} || [k,k])[1];end
def mst_sp_gantt_svg(sch)
 acts=sch[:acts];return '' if acts.empty?
 days=[sch[:days],1].max;w=1100.0;lw=230.0;rh=16.0;rm=170.0
 rows=MST_SP_KINDS.map{|k,l|as=acts.select{|a|a[:kind]==k};as.empty? ? nil : [k,l,as]}.compact
 h=40+rows.length*(rh*2+10)
 x=->(d){lw+(w-lw-rm)*d/days}
 col={'pile'=>'#6c757d','infill'=>'#8e5ea2','bk'=>'#073f73','pcprod'=>'#c9a227','pc'=>'#e07b00','deck'=>'#2e8b57','fin'=>'#b03a2e'}
 g=+"<svg xmlns='http://www.w3.org/2000/svg' width='#{w.round}' height='#{h.round}' style='background:#fff'>"
 # ay çizgileri
 last=nil
 sch[:cal].each_with_index do |d,i|
  break if i>days
  m=d.strftime('%Y-%m');next if m==last;last=m
  g << "<line x1='#{x.(i).round(1)}' y1='20' x2='#{x.(i).round(1)}' y2='#{h-4}' stroke='#e3e8ee'/><text x='#{(x.(i)+2).round(1)}' y='14'>#{d.strftime('%m.%Y')}</text>"
 end
 rows.each_with_index do |(k,l,as),ri|
  y=30+ri*(rh*2+10)
  s=as.map{|a|a[:s]}.min;f=as.map{|a|a[:f]}.max
  g << "<text x='4' y='#{(y+12).round}'>#{mst_rt_h(l)} (#{as.length})</text>"
  g << "<rect x='#{x.(s).round(1)}' y='#{y.round}' width='#{[x.(f)-x.(s),2].max.round(1)}' height='#{rh}' fill='#{col[k]}' opacity='0.35'/>"
  as.each{|a|g << "<rect x='#{x.(a[:s]).round(1)}' y='#{(y+rh+2).round}' width='#{[x.(a[:f])-x.(a[:s]),1].max.round(2)}' height='#{(rh-6).round}' fill='#{col[k]}'><title>#{mst_rt_h(a[:id])} #{a[:sd]} → #{a[:fd]}</title></rect>"}
  g << "<text x='#{(x.(f)+3).round(1)}' y='#{(y+12).round}'>#{sch[:cal][s.floor].strftime('%d.%m.%Y')} → #{sch[:cal][[f.ceil-1,s.floor].max].strftime('%d.%m.%Y')}</text>"
 end
 g << '</svg>'
end
def mst_sp_report(model=Sketchup.active_model,prm=nil,dir=nil)
 prm||=mst_sp_params(model)
 all=[];collect_elements(model.entities,all)
 items=mst_sp_items(all)
 raise 'Modelde iş programına girecek eleman yok (kazık, BK, prekast, döşeme…).' if items.empty?
 sch=mst_sp_schedule(items,prm)
 wk=mst_sp_weekly(sch,prm)
 boq=(boq_rows(false) rescue [])
 mon=mst_sp_monthly(sch,boq)
 cur=(respond_to?(:boq2_currency) ? (boq2_currency rescue 'USD') : 'USD')
 sum=MST_SP_KINDS.map do |k,l|
  as=sch[:acts].select{|a|a[:kind]==k};next nil if as.empty?
  s=as.map{|a|a[:s]}.min;f=as.map{|a|a[:f]}.max
  [l,as.length,sch[:cal][s.floor],sch[:cal][[f.ceil-1,s.floor].max],(f-s).round(1)]
 end.compact
 base=dir ? File.join(dir,'MST_Is_Programi') : mst_rt_out_name('Is_Programi','x').sub(/\.x\z/,'')
 # Excel
 sh1=[['Eleman','Faaliyet','Başlangıç','Bitiş','Süre (iş günü)','Miktar','Birim','Ekip no']]+
  sch[:acts].sort_by{|a|[a[:s],a[:kind]]}.map{|a|[a[:id],mst_sp_label(a[:kind]),a[:sd].strftime('%d.%m.%Y'),a[:fd].strftime('%d.%m.%Y'),(a[:f]-a[:s]).round(2),a[:qty],a[:qty_unit],a[:unit]+1]}
 sh2=[['Hafta','Beton (m³)','Donatı (t)','Kazık (adet)','Prekast (adet)','Aktif ekip','Tahmini kişi']]+wk.map{|r|[r['week'],r['concrete_m3'].round(1),r['rebar_t'].round(2),r['piles'],r['precast'],r['crews'],r['workers']]}
 sh3=[['Ay',"Hakediş tahmini (#{cur})","Kümülatif (#{cur})",'Kümülatif %']]+mon.map{|r|[r['month'],r['amount'].round(0),r['cum'].round(0),r['pct'].round(1)]}
 sh4=[['Parametre','Değer','Kaynak']]+MST_SP_RATES.map{|k,l,_,src|[l,prm[k],src]}+[['Başlangıç tarihi',prm['start'],'proje'],['İlerleme yönü',prm['reverse'].to_i==1 ? 'ters' : 'düz','proje']]
 mst_rt_write_xlsx("#{base}.xlsx",[['Faaliyetler',sh1],['Haftalık İhtiyaç',sh2],['Aylık Hakediş',sh3],['Parametreler',sh4]])
 peak=wk.map{|r|r['workers']}.max || 0
 html=mst_rt_html_page('İş Programı',
  "<p>Başlangıç <b>#{sch[:start].strftime('%d.%m.%Y')}</b> · bitiş <b>#{sch[:finish] ? sch[:finish].strftime('%d.%m.%Y') : '-'}</b> · #{sch[:days].ceil} iş günü · #{sch[:acts].count{|a|a[:kind]!='pcprod'}} faaliyet · en yoğun haftada ~#{peak} kişi.</p>"+
  "<p class='small'>Süre = miktar / verim; sıra: kazık → kazık içi → BK → #{prm['bk_cure'].round} gün bekleme → prekast → döşeme → bitiş işleri. Haftada #{prm['days_week'].round} gün, hava / deniz kaybı %#{prm['weather'].round}. Verimler varsayılan; Ayarlar'dan değiştirin (kaynakları en altta).</p>"+
  mst_sp_gantt_svg(sch)+
  "<h2>Özet</h2><table><tr><th class='l'>Faaliyet</th><th>Adet</th><th>Başlangıç</th><th>Bitiş</th><th>Süre (iş günü)</th></tr>"+sum.map{|l,n,s,f,d|"<tr><td class='l'>#{mst_rt_h(l)}</td><td>#{n}</td><td>#{s.strftime('%d.%m.%Y')}</td><td>#{f.strftime('%d.%m.%Y')}</td><td>#{d}</td></tr>"}.join+'</table>'+
  "<h2>Haftalık malzeme ve ekip</h2><table><tr><th class='l'>Hafta</th><th>Beton (m³)</th><th>Donatı (t)</th><th>Kazık</th><th>Prekast</th><th>Aktif ekip</th><th>Kişi</th></tr>"+wk.map{|r|"<tr><td class='l'>#{r['week']}</td><td>#{format('%.1f',r['concrete_m3'])}</td><td>#{format('%.2f',r['rebar_t'])}</td><td>#{r['piles']}</td><td>#{r['precast']}</td><td>#{r['crews']}</td><td>#{r['workers']}</td></tr>"}.join+'</table>'+
  (mon.empty? ? "<p class='small'>Hakediş tahmini için keşif birim fiyatları gerekli.</p>" :
   "<h2>Aylık hakediş tahmini (#{mst_rt_h(cur)})</h2><table><tr><th class='l'>Ay</th><th>Tutar</th><th>Kümülatif</th><th>%</th></tr>"+mon.map{|r|"<tr><td class='l'>#{r['month']}</td><td>#{format('%.0f',r['amount'])}</td><td>#{format('%.0f',r['cum'])}</td><td>#{format('%.1f',r['pct'])}</td></tr>"}.join+'</table>')+
  "<h2>Parametreler</h2><table><tr><th class='l'>Parametre</th><th>Değer</th><th class='l'>Kaynak</th></tr>"+MST_SP_RATES.map{|k,l,_,src|"<tr><td class='l'>#{mst_rt_h(l)}</td><td>#{prm[k]}</td><td class='l'>#{mst_rt_h(src)}</td></tr>"}.join+'</table>')
 File.write("#{base}.html",html)
 model.set_attribute(DICT,'sp_last_json',JSON.generate(sch[:acts].map{|a|[a[:item] ? (a[:item][:e].persistent_id rescue 0) : 0,a[:kind],a[:sd].to_s,a[:fd].to_s]}))
 {xlsx:"#{base}.xlsx",html:"#{base}.html",sch:sch,weekly:wk,monthly:mon,peak:peak}
end

# ---------------------------------------------------------------- arayüz
def mst_sp_settings_ui
 model=Sketchup.active_model;p=mst_sp_params(model)
 half=MST_SP_RATES.each_slice((MST_SP_RATES.length+1)/2).to_a
 newp=p.dup
 half.each_with_index do |grp,gi|
  labels=grp.map{|_,l,_,_|l};vals=grp.map{|k,_,_,_|v=p[k].to_f;v==v.round ? v.round.to_s : v.to_s}
  if gi==0 then labels+=['Başlangıç tarihi (YYYY-AA-GG)','İlerleme yönü (0 = düz, 1 = ters)'];vals+=[p['start'],p['reverse'].round.to_s] end
  r=UI.inputbox(labels,vals,"İş Programı Ayarları (#{gi+1}/#{half.length})")
  return 0 unless r
  grp.each_with_index do |(k,l,_,_),i|
   x=(Float(r[i].to_s.strip.tr(',','.')) rescue nil);raise "#{l}: sayı olmalı." unless x && x>=0
   newp[k]=x
  end
  if gi==0
   Date.parse(r[grp.length].to_s) rescue raise('Başlangıç tarihi YYYY-AA-GG olmalı.')
   newp['start']=r[grp.length].to_s.strip;newp['reverse']=r[grp.length+1].to_s.strip=='1' ? 1.0 : 0.0
  end
 end
 model.start_operation('MST İş Programı Ayarları',true);op=true
 model.set_attribute(DICT,'sp_params_json',JSON.generate(newp))
 model.commit_operation;op=false
 UI.messagebox('İş programı ayarları kaydedildi.')
 1
rescue => ex
 model.abort_operation if op   # v0.51.5 K13: açık kalan işlem kapatılır
 UI.messagebox("İş programı ayarları: #{ex.message}")
 0
end
def mst_sp_ui
 r=mst_sp_report
 UI.openURL("file:///#{r[:html].tr('\\','/')}") rescue nil
 s=r[:sch]
 UI.messagebox(format("İş programı hazır: %s → %s (%d iş günü), en yoğun hafta ~%d kişi.\n%s\n%s",s[:start].strftime('%d.%m.%Y'),s[:finish].strftime('%d.%m.%Y'),s[:days].ceil,r[:peak],r[:xlsx],r[:html]))
 1
rescue => ex
 UI.messagebox("İş programı: #{ex.message}")
 0
end
# 4D: ay ay renklendirme ya da seçilen haftadaki durum (biten renkli, süren sarı, başlamayan gizli). Tek Geri Al; "4D Temizle" eski hâline döndürür.
MST_SP_PALETTE=%w[#1f77b4 #2ca02c #ff7f0e #9467bd #8c564b #e377c2 #17becf #bcbd22 #d62728 #7f7f7f #393b79 #637939].freeze
def mst_sp_4d_apply!(model,sch,week=nil)
 n=0
 sch[:acts].each do |a|
  i=a[:item];next unless i && a[:kind]!='pcprod'
  e=i[:e];next unless e.valid?
  if e.get_attribute(DICT,'sp4d_saved').nil?
   e.set_attribute(DICT,'sp4d_saved',1);e.set_attribute(DICT,'sp4d_mat',e.material ? e.material.name : '');e.set_attribute(DICT,'sp4d_hidden',e.hidden? ? 1 : 0)
  end
  if week
   ws=a[:sd].strftime('%G-H%V');wf=a[:fd].strftime('%G-H%V')
   if ws>week then e.hidden=true
   elsif wf>week then e.hidden=false;e.material=material_for(model,'MST 4D Süren','#F2C200')
   else e.hidden=false;e.material=material_for(model,'MST 4D Biten','#2E8B57') end
  else
   mi=((a[:fd].year-sch[:start].year)*12+a[:fd].month-sch[:start].month)
   e.hidden=false;e.material=material_for(model,"MST 4D Ay #{mi+1}",MST_SP_PALETTE[mi%MST_SP_PALETTE.length])
  end
  n+=1
 end
 n
end
def mst_sp_4d_clear!(model)
 all=[];collect_elements(model.entities,all);n=0
 all.each do |e|
  next if e.get_attribute(DICT,'sp4d_saved').nil?
  mn=e.get_attribute(DICT,'sp4d_mat','').to_s;e.material=mn.empty? ? nil : model.materials[mn]
  e.hidden=e.get_attribute(DICT,'sp4d_hidden',0).to_i==1
  %w[sp4d_saved sp4d_mat sp4d_hidden].each{|k|e.delete_attribute(DICT,k)};n+=1
 end
 n
end
def mst_sp_4d_ui
 model=Sketchup.active_model
 all=[];collect_elements(model.entities,all)
 sch=mst_sp_schedule(mst_sp_items(all),mst_sp_params(model))
 raise 'İş programına girecek eleman yok.' if sch[:acts].empty?
 wks=sch[:acts].map{|a|a[:fd].strftime('%G-H%V')}.uniq.sort
 r=UI.inputbox(['4D görünüm'],['Aylara göre renklendir'],[(['Aylara göre renklendir']+wks.map{|w|"Hafta durumu: #{w}"}).join('|')],'İş Programı — 4D')
 return 0 unless r
 week=r[0].to_s[/Hafta durumu: (.+)\z/,1]
 model.start_operation('MST 4D Görünüm',true)
 n=mst_sp_4d_apply!(model,sch,week)
 model.commit_operation
 UI.messagebox(week ? "#{week} durumu: yeşil biten, sarı süren; başlamamış elemanlar gizli (#{n} eleman). '4D Temizle' ile geri döner." :
  "#{n} eleman bittiği aya göre renklendi (Ay 1, Ay 2 …). '4D Temizle' ile geri döner.")
 n
rescue => ex
 model.abort_operation rescue nil
 UI.messagebox("4D: #{ex.message}")
 0
end
def mst_sp_4d_clear_ui
 model=Sketchup.active_model
 model.start_operation('MST 4D Temizle',true);n=mst_sp_4d_clear!(model);model.commit_operation
 UI.messagebox("#{n} elemanın 4D rengi / görünürlüğü eski hâline döndü.")
 n
rescue => ex
 model.abort_operation rescue nil
 UI.messagebox("4D temizle: #{ex.message}")
 0
end

end
end
