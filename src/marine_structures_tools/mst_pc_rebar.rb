# frozen_string_literal: true
# v0.50 PC2 — Prekast donatısı (İGSAŞ PD1 / PD2 / PD3, Efes PDDT): parametrik, 3B çubuk, metraj çizilen çubuktan.
#  Düz prekast (PD): alt boyuna (iki uçta BK'ya giriş boyu kadar taşar), üst boyuna (uçları Ü kıvrık), enine alt / üst U,
#   2. kademeye taşan kapalı etriye şeritleri (35'lik şerit, kenarlardan eşit dağılmış), kaldırma kancaları.
#  Kanal prekastı (PK): taban boyuna (BK'ya taşar), dış sarma U + iç U etriye, taban enine alt / üst, duvar boyuna,
#   duvar üstünden taşan şapkalar, duvar üstü boyuna, kaldırma kancaları (duvar ekseninde).
#  Çizim çizimden-donatı motoruyla (poz başına bileşen tanımı, tek Geri Al); Component prekastta tanım paylaşılır:
#   aynı tipteki bütün parçalar aynı donatıyı taşır, tonaj her parçaya yazılır.
#  Prekast boyu / ölçüsü değişince donatı kayıtlı parametrelerle yeniden çizilir.
require 'json'
module MAG
module MarineStructuresTools

MST_PC_DRAWING='PREKAST'
MST_PC_TYPES=%w[flat_precast channel_precast].freeze
# [anahtar, etiket, varsayılan, alt, üst]; tür: :pd / :pk / :both
MST_PC_FIELDS={
 'PD'=>[['cover_mm','Pas payı (mm)',50,20,120],['embed_m','BK\'ya giriş boyu, alt boyuna (m, prekast ucundan)',0.90,0,3],
  ['bot_n','Alt boyuna adet',11,0,80],['bot_d','Alt boyuna Ø (mm)',32,8,40],['top_n','Üst boyuna adet (uçları Ü)',9,0,80],['top_d','Üst boyuna Ø',12,8,40],
  ['top_hook_m','Üst boyuna uç kıvrımı (m)',0.15,0,1],['tr_d','Enine alt / üst U Ø',12,8,32],['tr_s','Enine aralık (mm)',200,50,500],['tr_leg_m','Enine U bacağı (m)',0.22,0,1],
  ['st_strips','Taşan etriye şerit sayısı (0 = yok)',2,0,10],['st_d','Taşan etriye Ø',12,8,25],['st_s','Taşan etriye aralığı (mm)',200,50,500],
  ['st_w_m','Şerit (etriye) genişliği (m)',0.35,0.1,1.5],['st_h_m','Etriye boyu (m, prekast tabanından)',0.55,0.1,3],['st_edge_m','Şeridin kenardan uzaklığı (m)',0.05,0,1],
  ['hook_n','Kaldırma kancası adedi (0 / 2 / 4)',4,0,8],['hook_d','Kanca Ø',25,12,40],['hook_end_m','Kanca: uçtan (m)',1.02,0.1,10],['hook_edge_m','Kanca: kenardan (m)',0.29,0.05,5],
  ['hook_leg_m','Kanca bacağı (m, üst yüzden aşağı)',0.30,0.05,3],['hook_foot_m','Kanca ayağı (m)',0.57,0,2],['hook_loop_m','Kanca halkası üst yüzden yüksekliği (m)',0.16,0.05,0.6]],
 'PK'=>[['cover_mm','Pas payı (mm)',50,20,120],['embed_m','BK\'ya giriş boyu, taban boyuna (m)',0.90,0,3],
  ['bot_n','Taban boyuna adet',13,0,80],['bot_d','Taban boyuna Ø (mm)',32,8,40],['top_n','Duvar üstü boyuna adet (iki duvar toplam)',4,0,40],['top_d','Duvar üstü boyuna Ø',12,8,40],
  ['wall_n','Duvar yüz boyuna (her yüz)',2,0,20],['wall_d','Duvar yüz boyuna Ø',12,8,32],['st_d','Sarma U etriye Ø (dış + iç)',12,8,25],['st_s','Sarma U aralığı (mm)',200,50,500],
  ['tr_d','Taban enine alt / üst Ø',12,8,32],['tr_s','Taban enine aralığı (mm)',200,50,500],
  ['hat_d','Duvar şapkası Ø (0 = yok)',12,0,25],['hat_s','Şapka aralığı (mm)',200,50,500],['hat_up_m','Şapka duvar üstünden taşma (m)',0.15,0,1],['hat_down_m','Şapka duvara gömülme (m)',0.13,0,1],
  ['hook_n','Kaldırma kancası adedi (0 / 2 / 4)',4,0,8],['hook_d','Kanca Ø',32,12,40],['hook_end_m','Kanca: uçtan (m)',1.02,0.1,10],
  ['hook_leg_m','Kanca bacağı (m, duvar üstünden aşağı)',1.15,0.05,4],['hook_foot_m','Kanca ayağı (m)',0.27,0,2],['hook_loop_m','Kanca halkası üst yüzden yüksekliği (m)',0.16,0.05,0.6]]
}.freeze

def mst_pc_family(e);e.get_attribute(DICT,'element_type','').to_s=='channel_precast' ? 'PK' : 'PD';end
def mst_pc_defaults(fam,model=Sketchup.active_model)
 h=Hash[MST_PC_FIELDS[fam].map{|k,_,v,_,_|[k,v.to_f]}]
 c=(mst_rs_get(fam=='PK' ? 'cover_pk_mm' : 'cover_precast_mm',model).to_f rescue 0.0);h['cover_mm']=c if c>0   # v0.50 RS2
 h
end
def mst_pc_params(fam,raw={})
 h=mst_pc_defaults(fam)
 MST_PC_FIELDS[fam].each do |k,lab,_,lo,hi|
  next unless raw.key?(k) && !raw[k].to_s.strip.empty?
  x=(Float(raw[k].to_s.strip.tr(',','.')) rescue nil)
  raise "#{lab}: #{lo}–#{hi} arasında sayı olmalı." unless x && x>=lo && x<=hi
  h[k]=x
 end
 h
end
# elemanın ölçüleri (yerel: x boy 0..L, y en 0..W, z 0..H)
def mst_pc_dims(e)
 h=Hash.new{|_,k|e.get_attribute(DICT,k,nil)};t=h['element_type'].to_s
 if t=='channel_precast'
  wi=h['inner_width_m'].to_f;di=h['inner_depth_m'].to_f;tb=h['base_thickness_m'].to_f;tw=h['wall_thickness_m'].to_f
  {'L'=>h['length_m'].to_f,'W'=>wi+2*tw,'H'=>tb+di,'wi'=>wi,'di'=>di,'tb'=>tb,'tw'=>tw}
 else
  {'L'=>h['length_m'].to_f,'W'=>h['width_m'].to_f,'H'=>h['height_m'].to_f}
 end
end

# aralıkla dağıtım: adet = ⌈açıklık / aralık⌉ + 1 (paftalardaki gibi; gerçek aralık ≤ verilen)
def mst_pc_pos(a,b,s)
 return [] if b<a-1e-9 || s<=0
 return [(a+b)/2.0] if b-a<1e-6
 n=((b-a)/s-1e-9).ceil+1
 (0...n).map{|i|a+(b-a)*i/(n-1).to_f}
end
# eşit dağıtım (uçlar dahil)
def mst_pc_spread(a,b,n)
 return [] if n<=0
 return [(a+b)/2.0] if n==1
 (0...n).map{|i|a+(b-a)*i/(n-1).to_f}
end
def mst_pc_hook(x,y,top,p,d)
 lp=p['hook_loop_m'];g=[0.10,2.5*d].max/2.0;leg=p['hook_leg_m'];ft=p['hook_foot_m']
 zb=top-leg
 pts=[]
 pts << [x-g-ft,y,zb] if ft>0
 pts << [x-g,y,zb] << [x-g,y,top+lp] << [x+g,y,top+lp] << [x+g,y,zb]
 pts << [x+g+ft,y,zb] if ft>0
 pts
end

# donatı planı (SketchUp'sız): [{label, d, pts (yerel m), stir}]
def mst_pc_plan_bars(fam,dm,p)
 cv=p['cover_mm']/1000.0;l=dm['L'];w=dm['W'];hh=dm['H']
 raise 'Prekast ölçüleri eksik.' if l<=0 || w<=0 || hh<=0
 b=[]
 add=->(lab,d,pts,stir=false){b << {label:lab,d:d.to_f,pts:pts.map{|q|q.map{|v|v.round(5)}},stir:stir}}
 if fam=='PD'
  trd=p['tr_d']/1000.0;bd=p['bot_d']/1000.0;td=p['top_d']/1000.0
  zt_b=cv+trd/2;zt_t=hh-cv-trd/2
  zb=cv+trd+bd/2;ztop=hh-cv-trd-td/2
  raise format('Prekast kalınlığı (%.2f m) donatıya yetmiyor.',hh) if ztop-zb<(bd+td)/2
  # alt boyuna: iki uçta BK'ya taşar
  mst_pc_spread(cv+trd+bd/2,w-cv-trd-bd/2,p['bot_n'].to_i).each{|y|add.('Alt boyuna',p['bot_d'],[[-p['embed_m'],y,zb],[l+p['embed_m'],y,zb]])}
  # üst boyuna Ü
  hk=[p['top_hook_m'],ztop-zb-0.02].min
  mst_pc_spread(cv+trd+td/2,w-cv-trd-td/2,p['top_n'].to_i).each do |y|
   pts=hk>0.02 ? [[cv+td/2,y,ztop-hk],[cv+td/2,y,ztop],[l-cv-td/2,y,ztop],[l-cv-td/2,y,ztop-hk]] : [[cv,y,ztop],[l-cv,y,ztop]]
   add.('Üst boyuna (Ü)',p['top_d'],pts)
  end
  # enine U (alt yukarı, üst aşağı bacaklı)
  leg=[p['tr_leg_m'],(hh-2*cv)/2.0-trd].min
  xs=mst_pc_pos(cv+trd/2+0.02,l-cv-trd/2-0.02,p['tr_s']/1000.0)
  xs.each do |x|
   add.('Enine alt U',p['tr_d'],leg>0.03 ? [[x,cv+trd/2,zt_b+leg],[x,cv+trd/2,zt_b],[x,w-cv-trd/2,zt_b],[x,w-cv-trd/2,zt_b+leg]] : [[x,cv,zt_b],[x,w-cv,zt_b]])
   add.('Enine üst U',p['tr_d'],leg>0.03 ? [[x,cv+trd/2,zt_t-leg],[x,cv+trd/2,zt_t],[x,w-cv-trd/2,zt_t],[x,w-cv-trd/2,zt_t-leg]] : [[x,cv,zt_t],[x,w-cv,zt_t]])
  end
  # taşan etriye şeritleri: kapalı dikdörtgen st_w × st_h, x'te enine U'ların arasında
  n=p['st_strips'].to_i
  if n>0 && p['st_d']>0
   sd=p['st_d']/1000.0;sw=p['st_w_m'];e0=p['st_edge_m']
   lefts=mst_pc_spread(e0,w-e0-sw,n)
   z0=cv+sd/2;z1=[p['st_h_m'],hh-cv+0.05].max-sd/2
   mst_pc_pos(cv+0.05+p['st_s']/2000.0,l-cv-0.05-p['st_s']/2000.0,p['st_s']/1000.0).each do |x|
    lefts.each{|ya|yb=ya+sw;add.('Taşan etriye',p['st_d'],[[x,ya+sd/2,z1],[x,yb-sd/2,z1],[x,yb-sd/2,z0],[x,ya+sd/2,z0],[x,ya+sd/2,z1]],true)}
   end
  end
  # kaldırma kancaları
  hn=p['hook_n'].to_i
  if hn>0
   xh=[p['hook_end_m'],l-p['hook_end_m']];yh=[p['hook_edge_m'],w-p['hook_edge_m']]
   pos=hn>=4 ? xh.product(yh) : xh.map{|x|[x,w/2.0]}
   pos.first(hn).each{|x,y|add.('Kaldırma kancası',p['hook_d'],mst_pc_hook(x,y,hh,p.merge('hook_leg_m'=>[p['hook_leg_m'],hh-cv].min),p['hook_d']/1000.0))}
  end
 else
  tb=dm['tb'];tw=dm['tw'];di=dm['di']
  bd=p['bot_d']/1000.0;sd=p['st_d']/1000.0;trd=p['tr_d']/1000.0
  zt_h=hh-cv-sd/2
  # dış sarma U (duvar dış yüzleri + taban altı) ve iç U (iç yüzler + taban üstü)
  xs=mst_pc_pos(cv+sd/2+0.02,l-cv-sd/2-0.02,p['st_s']/1000.0)
  yo=cv+sd/2;yi=tw-cv-sd/2;zb_o=cv+sd/2;zb_i=tb-cv-sd/2
  xs.each do |x|
   add.('Sarma U dış',p['st_d'],[[x,yo,zt_h],[x,yo,zb_o],[x,w-yo,zb_o],[x,w-yo,zt_h]],true)
   add.('Sarma U iç',p['st_d'],[[x,yi,zt_h],[x,yi,zb_i],[x,w-yi,zb_i],[x,w-yi,zt_h]],true) if yi-yo>sd+0.01 && zb_i-zb_o>sd+0.01
  end
  # taban enine (alt / üst), sarma U'ların arasında
  if trd>0
   mst_pc_pos(cv+0.05+p['tr_s']/2000.0,l-cv-0.05-p['tr_s']/2000.0,p['tr_s']/1000.0).each do |x|
    add.('Taban enine alt',p['tr_d'],[[x,yo+sd,zb_o+sd/2+trd/2],[x,w-yo-sd,zb_o+sd/2+trd/2]])
    add.('Taban enine üst',p['tr_d'],[[x,yo+sd,zb_i-sd/2-trd/2],[x,w-yo-sd,zb_i-sd/2-trd/2]]) if zb_i-zb_o>2*trd+sd
   end
  end
  # taban boyuna (BK'ya taşar), enine alt çubukların üstünde
  zbl=zb_o+sd/2+trd+bd/2
  mst_pc_spread(yo+sd/2+bd/2,w-yo-sd/2-bd/2,p['bot_n'].to_i).each{|y|add.('Taban boyuna',p['bot_d'],[[-p['embed_m'],y,zbl],[l+p['embed_m'],y,zbl]])}
  # duvar yüz boyuna (iki duvar, iki yüz), duvar üstü boyuna
  wd=p['wall_d']/1000.0
  if p['wall_n'].to_i>0 && wd>0
   mst_pc_spread(tb+0.10,hh-cv-sd-0.10,p['wall_n'].to_i).each do |z|
    [yo+sd/2+wd/2,yi-sd/2-wd/2,w-yi+sd/2+wd/2,w-yo-sd/2-wd/2].each{|y|add.('Duvar boyuna',p['wall_d'],[[cv,y,z],[l-cv,y,z]])}
   end
  end
  td=p['top_d']/1000.0
  if p['top_n'].to_i>0 && td>0
   per=[(p['top_n'].to_i/2.0).ceil,1].max
   [[yo+sd/2+td/2,yi-sd/2-td/2],[w-yi+sd/2+td/2,w-yo-sd/2-td/2]].each{|a,c|mst_pc_spread(a,c,per).each{|y|add.('Duvar üstü boyuna',p['top_d'],[[cv,y,zt_h-sd/2-td/2],[l-cv,y,zt_h-sd/2-td/2]])}}
  end
  # duvar şapkaları (2. kademeye taşar)
  hd=p['hat_d']/1000.0
  if hd>0
   mst_pc_pos(cv+0.05+p['hat_s']/2000.0,l-cv-0.05-p['hat_s']/2000.0,p['hat_s']/1000.0).each do |x|
    [[yo+sd+hd/2,yi-sd-hd/2],[w-yi+sd+hd/2,w-yo-sd-hd/2]].each do |ya,yb|
     next if yb-ya<0.04
     add.('Duvar şapkası',p['hat_d'],[[x,ya,hh-p['hat_down_m']],[x,ya,hh+p['hat_up_m']],[x,yb,hh+p['hat_up_m']],[x,yb,hh-p['hat_down_m']]])
    end
   end
  end
  hn=p['hook_n'].to_i
  if hn>0
   xh=[p['hook_end_m'],l-p['hook_end_m']];yh=[tw/2.0,w-tw/2.0]
   pos=hn>=4 ? xh.product(yh) : xh.map{|x|[x,tw/2.0]}
   pos.first(hn).each{|x,y|add.('Kaldırma kancası',p['hook_d'],mst_pc_hook(x,y,hh,p.merge('hook_leg_m'=>[p['hook_leg_m'],hh-cv].min),p['hook_d']/1000.0))}
  end
 end
 b
end

# DR motoru biçiminde tam plan
def mst_pc_plan(fam,dm,p)
 bars=mst_pc_plan_bars(fam,dm,p)
 bars.each{|x|x[:len]=mst_dr_round(x[:pts],mst_dr_bend_r(x[:d],x[:stir]))[1]}
 grp=bars.group_by{|x|[x[:label],x[:d].round]}
 sched=[];names={};qa=[]
 grp.each_with_index do |((lab,d),v),i|
  v.each{|x|x[:poz]=i+1;x[:batch]=1}
  ms=v.sum{|x|x[:len]};kg=ms*mst_dr_kgm(d)
  sched << {'poz'=>i+1,'d'=>d.to_f,'n'=>v.length,'len'=>(ms/v.length).round(3),'shape'=>lab}
  names[i+1]=format('Poz %02d — %s Ø%d · %d çubuk · %.1f m · %.1f kg',i+1,lab,d,v.length,ms,kg)
  qa << {'poz'=>i+1,'d'=>d.to_f,'n'=>v.length,'len'=>ms/v.length,'shape'=>lab,'external'=>0,'kg'=>kg,'drawn'=>v.length,'drawn_kg'=>kg,'state'=>'tam'}
 end
 kg=bars.sum{|x|x[:len]*mst_dr_kgm(x[:d])}
 spec={'format'=>'mst-drawing-rebar/1','drawing'=>MST_PC_DRAWING,'schedule'=>sched,'group_names'=>names,'dims'=>{'W'=>dm['W'],'L'=>dm['L'],'H'=>dm['H']},'probes'=>[],'groups'=>[]}
 {bars:bars,spec:spec,qa:qa,sched_kg:kg,kg:kg,map:->(q){q},orient:{fu:false,fv:false},
  by_label:grp.map{|(lab,d),v|[lab,d,v.length,v.sum{|x|x[:len]*mst_dr_kgm(d)}]}}
end
def mst_pc_text(e,fam,dm,p,pl)
 vol=qto3_quantity(e,:concrete_m3) rescue 0.0
 l=["#{element_visible_id(e)} — PREKAST DONATISI (#{fam}) — önizleme",
    format('Ölçü: %.2f × %.2f × %.2f m%s · pas payı %d mm · BK\'ya giriş %.2f m',dm['L'],dm['W'],dm['H'],fam=='PK' ? format(' (iç %.2f × %.2f, taban %.2f, duvar %.2f)',dm['wi'],dm['di'],dm['tb'],dm['tw']) : '',p['cover_mm'].round,p['embed_m']),'']
 pl[:by_label].each{|lab,d,n,kg|l << format('  %-22s Ø%-3d %4d ad  %8.1f kg',lab,d,n,kg)}
 l << format('Toplam %.1f kg%s',pl[:kg],vol>0 ? format(' · %.0f kg/m³ (beton %.3f m³)',pl[:kg]/vol,vol) : '')
 l.join("\n")
end
# aynı Component tanımını kullanan bütün parçalar (Group ise yalnız kendisi)
def mst_pc_peers(e)
 e.is_a?(Sketchup::ComponentInstance) ? e.definition.instances.to_a.select(&:valid?) : [e]
end
MST_PC_ATTRS=%w[rebar_mode rebar_t rebar_kg rebar_kind rebar_drawing rebar_drawing_batches rebar_bar_count rebar_schedule_json rebar_source pc_rebar_json].freeze
# çiz (çağıranın işlemi içinde)
def mst_pc_draw!(e,p=nil)
 fam=mst_pc_family(e)
 p||=mst_pc_params(fam,(JSON.parse(e.get_attribute(DICT,'pc_rebar_json','{}').to_s) rescue {}))
 dm=mst_pc_dims(e)
 pl=mst_pc_plan(fam,dm,p)
 # yerel çerçeve: geometrinin en küçük köşesi (eski kanal prekastı mutlak koordinatlı çizilmiş olabilir)
 pts,_,tris=mst_dr_geometry(e)
 qs=tris.flatten(1);qs=pts if qs.empty?
 o=qs.empty? ? [0.0,0.0,0.0] : [qs.map{|q|q[0]}.min,qs.map{|q|q[1]}.min,qs.map{|q|q[2]}.min]
 pl[:map]=->(q){[q[0]+o[0],q[1]+o[1],q[2]+o[2]]}
 mst_dr_draw!(e,pl[:spec],pl)
 {'rebar_mode'=>'auto_detail','rebar_kind'=>"PREKAST-#{fam}",'rebar_source'=>"Prekast parametrik donatı (#{fam})",'rebar_drawing_batches'=>'pc',
  'pc_rebar_json'=>JSON.generate(p)}.each{|k,v|e.set_attribute(DICT,k,v)}
 e.delete_attribute(DICT,'rebar_drawing_orient')
 h=Hash[MST_PC_ATTRS.map{|k|[k,e.get_attribute(DICT,k)]}]
 mst_pc_peers(e).each{|x|next if x==e;h.each{|k,v|v.nil? ? x.delete_attribute(DICT,k) : x.set_attribute(DICT,k,v)}}
 e.definition.set_attribute(DICT,'pc_rebar_attrs_json',JSON.generate(h)) if e.is_a?(Sketchup::ComponentInstance)
 pl
end
def mst_pc_clear!(e)
 mst_dr_set_of(e).each{|g|mst_dr_erase_set!(g)}
 mst_pc_peers(e).each{|x|MST_PC_ATTRS.each{|k|x.delete_attribute(DICT,k)}}
 e.definition.delete_attribute(DICT,'pc_rebar_attrs_json') if e.is_a?(Sketchup::ComponentInstance)
 mst_dr_purge_defs!(e.model) rescue nil
end
# tanımında donatı olan ama kendisinde kayıt olmayan Component parça (yeni yerleşim): tanımın kaydı
def mst_pc_def_rebar(e)
 return nil unless e.is_a?(Sketchup::ComponentInstance)
 h=(JSON.parse(e.definition.get_attribute(DICT,'pc_rebar_attrs_json','').to_s) rescue nil)
 h.is_a?(Hash) ? h : nil
end
# boy / ölçü değişince (Group yeniden kuruldu ya da Component tanımı değişti) donatıyı yeniden çiz
def mst_pc_after_rebuild!(e)
 return unless e && e.valid? && !e.get_attribute(DICT,'pc_rebar_json','').to_s.empty?
 mst_pc_draw!(e)
rescue => ex
 e.set_attribute(DICT,'pc_rebar_error',ex.message) rescue nil
end

def mst_pc_ui
 model=Sketchup.active_model
 sel=[];mst_collect_elements_raw(model.selection,sel)
 es=sel.select{|x|x.valid? && MST_PC_TYPES.include?(x.get_attribute(DICT,'element_type','').to_s)}.uniq
 raise 'Düz prekast (PD) ya da kanal prekastı (PK) seçin.' if es.empty?
 fams=es.map{|x|mst_pc_family(x)}.uniq
 raise 'Bir seferde tek tür seçin (PD ya da PK).' unless fams.length==1
 fam=fams[0];e0=es[0]
 act=UI.inputbox(['İşlem'],['ÇİZ'],['ÇİZ|SİL'],"Prekast Donatısı — #{es.length} parça (#{fam})")
 return 0 unless act
 if act[0]=='SİL'
  return 0 unless UI.messagebox("#{es.length} prekasttan donatı silinsin mi? (pursantaja döner, tek Geri Al)",MB_YESNO)==IDYES
  model.start_operation('MST Prekast Donatısı Sil',true)
  begin;es.each{|e|mst_pc_clear!(e) if e.valid?};model.commit_operation;rescue;model.abort_operation;raise;end
  return es.length
 end
 last=(JSON.parse(e0.get_attribute(DICT,'pc_rebar_json','').to_s) rescue nil) || (JSON.parse(model.get_attribute(DICT,"mst_pc_last_#{fam}",'{}').to_s) rescue {})
 cur=mst_pc_params(fam,last)
 flds=MST_PC_FIELDS[fam]
 half=(flds.length+1)/2
 vals={}
 [flds.first(half),flds.drop(half)].each_with_index do |fs,k|
  r=UI.inputbox(fs.map{|_,l,_,_,_|l},fs.map{|kk,_,_,_,_|v=cur[kk];v==v.round ? v.round.to_s : v.to_s},"Prekast Donatısı (#{fam}) — #{k+1}/2")
  return 0 unless r
  fs.each_with_index{|(kk,_,_,_,_),i|vals[kk]=r[i]}
 end
 p=mst_pc_params(fam,vals)
 txt=mst_pc_text(e0,fam,mst_pc_dims(e0),p,mst_pc_plan(fam,mst_pc_dims(e0),p))
 defs=es.map{|x|x.is_a?(Sketchup::ComponentInstance) ? x.definition : x}.uniq
 return 0 unless UI.messagebox("#{txt}\n\n#{es.length} parça (#{defs.length} ayrı tanım / grup). Donatı çizilsin mi? (tek Geri Al)",MB_YESNO)==IDYES
 model.set_attribute(DICT,"mst_pc_last_#{fam}",JSON.generate(p))
 model.start_operation('MST Prekast Donatısı',true)
 begin
  done={}
  es.each do |e|
   k=e.is_a?(Sketchup::ComponentInstance) ? e.definition : e
   next if done[k]
   mst_pc_draw!(e,p);done[k]=true
  end
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 send_boq(@d) if @d rescue nil
 UI.messagebox(format("%d prekast parçasına donatı çizildi (%d tanım). BOQ / hakediş donatısı çizilen çubuklardan.%s",es.length,defs.length,(respond_to?(:mst_rt_visible_note) ? mst_rt_visible_note : '')))
 es.length
rescue => ex
 UI.messagebox("Prekast donatısı: #{ex.message}")
 0
end

end
end
