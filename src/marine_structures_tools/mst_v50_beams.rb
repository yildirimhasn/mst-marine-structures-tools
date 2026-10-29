# frozen_string_literal: true
# v0.50 — Başlık kirişi ekleri (proje paftalarından: İGSAŞ, Ege Gübre, Likit, Efes)
#  VK1 Vinç kirişi (VK) / Boylama kirişi (BBK): iki BK arasında, BK'lara dik, BK yüzünde biter (alın kalıbı yok);
#      BK'ların o yüzdeki kalıbı VK / BBK temas alanı kadar düşülür; donatı BK motoruyla, boyuna çubuklar BK'ya ×Ø ankrajlı;
#      VK'da ray tipi (kg/m) + bağlantı klipsi metrajı. Eleman "başlık kirişi" ailesindedir (beton, kalıp, donatı pozu aynı).
#  KD2 Kademeli döküm (BK / dolfen başlığı): 1. kademe yüksekliği; beton / kalıp iki kademeye bölünür, iş programında iki adım.
#  TB1 Taban bölgesi: BK boyunca istenen aralıkta alçak taban (uç dişlerine ek); geometri, beton, kalıp, donatı.
#  MF1 Menfez sac kutusu: BK içinden geçen boşluk; beton ve yüz kalıbı düşülür, sac ağırlığı metraja; donatı kesilir + takviye.
require 'json'
module MAG
module MarineStructuresTools

MST_VK_RAILS={'A45'=>22.1,'A55'=>31.8,'A65'=>43.1,'A75'=>56.2,'A100'=>74.3,'A120'=>100.0,'A150'=>150.3,
 'MRS73'=>73.0,'MRS87A'=>87.0,'MRS125'=>125.0,'QU70'=>52.8,'QU80'=>63.7,'QU100'=>88.9,'QU120'=>118.1,'YOK'=>0.0}.freeze
MST_VK_ROLES={'VK'=>'Vinç kirişi','BBK'=>'Boylama kirişi'}.freeze

def mst_rs_lap_d
 v=(mst_rs_get('lap_d').to_f rescue 0.0)
 v>0 ? v : 50.0
end
def mst_v50_num(v,label,lo=nil,hi=nil)
 x=(Float(v.to_s.strip.tr(',','.')) rescue nil)
 raise "#{label}: sayı olmalı." unless x && x.finite?
 raise "#{label}: #{lo} – #{hi} arasında olmalı." if (lo && x<lo) || (hi && x>hi)
 x
end
def mst_v50_role(e);e.get_attribute(DICT,'beam_role','').to_s;end
def mst_v50_link?(e);%w[VK BBK].include?(mst_v50_role(e));end

# ---------------------------------------------------------------- TB1 bölgeler (BK yerel, m)
# uç dişleri + taban bölgeleri → düz alçak kısımlar: a0..a1 (eğim dahil), f0..f1 (düz), dz derinlik
def mst_hb_zones_list(h)
 z=(JSON.parse(h['bottom_zones_json'].to_s) rescue [])
 z.is_a?(Array) ? z.select{|q|q.is_a?(Hash)} : []
end
def mst_hb_zone_info(h,len)
 zs=[]
 if h['start_tooth_enabled'].to_s=='1'
  tl=[h['start_tooth_length_m'].to_f,len].min;sl=[[h['start_tooth_slope_m'].to_f,0.0].max,tl].min;dz=h['start_tooth_depth_m'].to_f
  zs << {'a0'=>0.0,'a1'=>tl,'f0'=>0.0,'f1'=>tl-sl,'dz'=>dz,'kind'=>'start'} if tl>0 && dz>0
 end
 if h['end_tooth_enabled'].to_s=='1'
  tl=[h['end_tooth_length_m'].to_f,len].min;sl=[[h['end_tooth_slope_m'].to_f,0.0].max,tl].min;dz=h['end_tooth_depth_m'].to_f
  zs << {'a0'=>len-tl,'a1'=>len,'f0'=>len-tl+sl,'f1'=>len,'dz'=>dz,'kind'=>'end'} if tl>0 && dz>0
 end
 mst_hb_zones_list(h).each do |q|
  a0=q['a0'].to_f;a1=q['a1'].to_f;dz=q['depth'].to_f;sl=[[q['slope'].to_f,0.0].max,(a1-a0)/2.0].min
  zs << {'a0'=>a0,'a1'=>a1,'f0'=>a0+sl,'f1'=>a1-sl,'dz'=>dz,'kind'=>'zone'} if a1>a0 && dz>0
 end
 {'base'=>(zs.map{|q|q['dz']}.max || 0.0),'zones'=>zs.select{|q|q['f1']-q['f0']>0.05}}
end
# recess_profile_points alt sınırına eklenecek bölgeler (inç; uçtan başa sıralı)
def mst_hb_zone_profile_pts(data,l,lo,hi)
 out=[]
 mst_hb_zones_list(data).map{|q|[m(q['a0'].to_f).to_f,m(q['a1'].to_f).to_f,m(q['depth'].to_f).to_f,m(q['slope'].to_f).to_f]}.sort_by{|a0,_,_,_|-a0}.each do |a0,a1,dz,sl|
  next unless a1>a0 && dz>0 && a0>=lo-1e-6 && a1<=hi+1e-6 && a1<=l+1e-6
  sl=[[sl,0.0].max,(a1-a0)/2.0].min
  out << [a1,0.0] << [a1-sl,-dz] << [a0+sl,-dz] << [a0,0.0]
 end
 out
end

# ---------------------------------------------------------------- MF1 menfez
def mst_hb_culvert_groups(hb)
 mst_hb_ents(hb).to_a.select{|x|x.is_a?(Sketchup::Group) && x.get_attribute(DICT,'element_type','').to_s=='bk_culvert'}
end
# menfez kutuları BK çerçevesinde: a (boy), c (en), z (ana gövde tabanından)
def mst_hb_culverts_local(hb,ox,oy,ozb,ax_y)
 mst_hb_culvert_groups(hb).map do |g|
  b=(JSON.parse(g.get_attribute(DICT,'cv_box_json','[]').to_s) rescue [])
  next nil unless b.length==6
  x0,y0,z0,x1,y1,z1=b
  a=ax_y ? [y0-oy,y1-oy] : [x0-ox,x1-ox];c=ax_y ? [x0-ox,x1-ox] : [y0-oy,y1-oy]
  {'a'=>a.sort,'c'=>c.sort,'z'=>[z0-ozb,z1-ozb].sort}
 end.compact
end
def mst_hb_culvert_void(hb);mst_hb_culvert_groups(hb).sum{|g|g.get_attribute(DICT,'cv_void_m3',0).to_f};end
def mst_hb_culvert_form_deduct(hb);mst_hb_culvert_groups(hb).sum{|g|g.get_attribute(DICT,'cv_form_deduct_m2',0).to_f};end
def mst_hb_culvert_steel(hb);mst_hb_culvert_groups(hb).sum{|g|g.get_attribute(DICT,'cv_steel_kg',0).to_f};end

# spec: a0 (BK başından, m), la (boy boyunca), c0 (BK kenarından), lc (en boyunca), z0 (BK tabanından), h, t_mm, axis 'C' (en boyunca geçer) | 'A'
# BK yerel (grup) koordinatında kutu [x0,y0,z0,x1,y1,z1]; hacim, sac, kalıp düşümü
def mst_cv_plan(spec,len,wid,hei)
 a0=spec['a0'].to_f;la=spec['la'].to_f;c0=spec['c0'].to_f;lc=spec['lc'].to_f;z0=spec['z0'].to_f;h=spec['h'].to_f;t=spec['t_mm'].to_f/1000.0
 raise 'Menfez ölçüleri sıfırdan büyük olmalı.' if la<=0 || lc<=0 || h<=0
 x0=[a0,0.0].max;x1=[a0+la,len].min;y0=[c0,0.0].max;y1=[c0+lc,wid].min;zb=[z0,0.0].max;zt=[z0+h,hei].min
 raise 'Menfez BK\'nın dışında.' if x1-x0<=0.01 || y1-y0<=0.01 || zt-zb<=0.01
 void=(x1-x0)*(y1-y0)*(zt-zb)
 axis=spec['axis'].to_s.upcase=='A' ? 'A' : 'C'
 # sac: kesit çevresi × geçiş boyu × t × 7850
 per,lgt=axis=='C' ? [2*((x1-x0)+(zt-zb)),y1-y0] : [2*((y1-y0)+(zt-zb)),x1-x0]
 steel=per*lgt*t*7850.0
 # delinen dış yüzler: kutu yüze değiyorsa o yüzün kalıbından açıklık düşülür
 fd=0.0
 fd+=(x1-x0)*(zt-zb) if y0<=1e-3
 fd+=(x1-x0)*(zt-zb) if y1>=wid-1e-3
 fd+=(y1-y0)*(zt-zb) if x0<=1e-3
 fd+=(y1-y0)*(zt-zb) if x1>=len-1e-3
 {'box'=>[x0,y0,zb,x1,y1,zt],'void'=>void,'steel_kg'=>steel,'form_deduct'=>fd,'axis'=>axis,'t_mm'=>spec['t_mm'].to_f}
end
# BK'nın yerel çerçevesi (grup koordinatı, m): x boy, y en, z: alçak taban varsa ana gövde tabanı z = 0 (diş z<0)
def mst_cv_bk_dims(hb)
 h=mst_attr_hash(hb)
 [h['length_m'].to_f,h['width_m'].to_f,h['height_m'].to_f]
end
def mst_cv_draw!(hb,spec)
 len,wid,hei=mst_cv_bk_dims(hb)
 pl=mst_cv_plan(spec,len,wid,hei)
 x0,y0,z0,x1,y1,z1=pl['box']
 g=mst_hb_ents(hb).add_group;g.name="MENFEZ #{format('%.2f×%.2f',(pl['axis']=='C' ? x1-x0 : y1-y0),z1-z0)} t=#{pl['t_mm'].round}"
 e=g.entities
 pts=->(*q){q.map{|x,y,z|Geom::Point3d.new(m(x),m(y),m(z))}}
 f=e.add_face(pts.([x0,y0,z0],[x1,y0,z0],[x1,y1,z0],[x0,y1,z0]));f.reverse! if f && f.normal.z>0
 f.pushpull(-m(z1-z0)) if f
 mat=(material_for(Sketchup.active_model,'MST Menfez Sacı','#7F8C8D') rescue nil)
 g.material=mat if mat
 {'element_type'=>'bk_culvert','cv_box_json'=>JSON.generate(pl['box'].map{|v|v.round(5)}),'cv_axis'=>pl['axis'],'cv_t_mm'=>pl['t_mm'],
  'cv_steel_kg'=>pl['steel_kg'],'cv_void_m3'=>pl['void'],'cv_form_deduct_m2'=>pl['form_deduct'],'cv_spec_json'=>JSON.generate(spec),
  'parent_uid'=>hb.get_attribute(DICT,'element_uid','').to_s}.each{|k,v|g.set_attribute(DICT,k,v)}
 g
end
def mst_cv_specs(hb);x=(JSON.parse(hb.get_attribute(DICT,'culverts_json','[]').to_s) rescue []);x.is_a?(Array) ? x : [];end
# BK yeniden kurulunca (entities.clear!) menfezler kayıtlı tanımdan yeniden çizilir
def mst_cv_redraw!(hb)
 mst_hb_culvert_groups(hb).each{|g|g.erase! if g.valid?}
 mst_cv_specs(hb).each{|s|mst_cv_draw!(hb,s) rescue nil}
end
MST_CV_FIELDS=[['a0','Menfez başlangıcı (m, BK başından boy boyunca)'],['la','Menfez boyu BK boyunca (m)'],
 ['c0','Menfez başlangıcı (m, BK yan yüzünden; 0 = yüzden)'],['lc','Menfez BK enine boyu (m; BK genişliği = boydan boya geçer)'],
 ['z0','Menfez alt kotu (m, BK tabanından)'],['h','Menfez yüksekliği (m)'],['t_mm','Sac kalınlığı (mm)'],['axis','Geçiş yönü: C (BK enine) / A (BK boyunca)']].freeze
def mst_cv_ui
 model=Sketchup.active_model
 sel=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise 'Bir Başlık Kirişi seçin.' unless sel.length==1
 hb=sel[0];len,wid,hei=mst_cv_bk_dims(hb)
 cur=mst_cv_specs(hb)
 act=UI.inputbox(['İşlem'],['EKLE'],[ 'EKLE|TEMİZLE' ],"Menfez — #{element_visible_id(hb)} (#{cur.length} menfez)")
 return 0 unless act
 if act[0]=='TEMİZLE'
  return 0 unless UI.messagebox("#{element_visible_id(hb)}: #{cur.length} menfez silinsin mi? (tek Geri Al)",MB_YESNO)==IDYES
  model.start_operation('MST Menfez Sil',true)
  begin
   hb.set_attribute(DICT,'culverts_json','[]');mst_cv_redraw!(hb);mst_v50_after_bk_change!(hb);commit_with_dependencies(model)
  rescue
   model.abort_operation;raise
  end
  return 1
 end
 d=['0.5','1.0','0',format('%.2f',wid),format('%.2f',hei*0.4),'0.60','10','C']
 r=UI.inputbox(MST_CV_FIELDS.map{|_,l|l},d,"Menfez Ekle — #{element_visible_id(hb)} (#{format('%.2f × %.2f × %.2f',len,wid,hei)} m)")
 return 0 unless r
 spec={};MST_CV_FIELDS.each_with_index{|(k,l),i|spec[k]=(k=='axis' ? r[i].to_s.strip.upcase : mst_v50_num(r[i],l))}
 pl=mst_cv_plan(spec,len,wid,hei)
 msg=format("%s menfez:\nBoşluk %.3f m³ (BK betonundan düşülür) · sac %.1f kg (t=%d mm) · yüz kalıbı düşümü %.2f m²\nBK donatısı yeniden çizilirse menfezden geçen çubuklar kesilir, iki yanına takviye konur.\nUygulansın mı? (tek Geri Al)",
  element_visible_id(hb),pl['void'],pl['steel_kg'],spec['t_mm'].round,pl['form_deduct'])
 return 0 unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation('MST Menfez Ekle',true)
 begin
  hb.set_attribute(DICT,'culverts_json',JSON.generate(cur+[spec]))
  mst_cv_draw!(hb,spec)
  mst_v50_after_bk_change!(hb)
  commit_with_dependencies(model)
 rescue
  model.abort_operation;raise
 end
 1
rescue => ex
 UI.messagebox("Menfez: #{ex.message}")
 0
end
# BK'da geometri / boşluk değişince: kalıp özeti, donatı (BIM ise) yeniden
def mst_v50_after_bk_change!(hb)
 gross=head_beam_formwork_area(hb) rescue 0.0
 hb.set_attribute(DICT,'formwork_net_area_m2',head_beam_net_formwork_area(hb)) rescue nil
 if hb.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail' && !hb.get_attribute(DICT,'hb_rebar_json','').to_s.empty?
  mst_hb_rebar_build!(hb,JSON.parse(hb.get_attribute(DICT,'hb_rebar_json','{}').to_s))
 end
 gross
end

# ---------------------------------------------------------------- TB1 taban bölgesi UI + yeniden kurma
def mst_bz_rebuild!(g)
 model=Sketchup.active_model
 h=mst_attr_hash(g)
 len=h['length_m'].to_f;hei=h['height_m'].to_f;wid=h['width_m'].to_f
 raise 'BK ölçüleri eksik.' if len<=0 || hei<=0 || wid<=0
 prof=recess_profile_points(m(len),m(hei),h)
 ov=bk_formwork_override_map(g,true)
 g.entities.clear!
 f=g.entities.add_face(prof.map{|x,z|Geom::Point3d.new(x,0,z)});raise 'BK profili oluşturulamadı.' unless f
 f.reverse! if f.normal.y<0;f.pushpull(m(wid))
 hx=h['formwork_color'].to_s;hx='#F4B183' if hx.empty?
 fm=material_for(model,"MAG Kalıp #{hx}",hx)
 bottom,long_side,end_face=classify_box_faces(g,fm,nil)
 bk_store_formwork_override_map(g,ov)
 gross=bk_apply_formwork_overrides(g,ov,fm)
 vol=polygon_area_xz(prof)/(1.m*1.m)*wid
 {'concrete_volume_m3'=>vol,'formwork_bottom_m2'=>bottom,'formwork_long_sides_m2'=>long_side,'formwork_end_faces_m2'=>end_face,
  'formwork_area_m2'=>gross,'formwork_gross_area_m2'=>gross}.each{|k,v|g.set_attribute(DICT,k,v)}
 mst_cv_redraw!(g)
 g.set_attribute(DICT,'formwork_net_area_m2',head_beam_net_formwork_area(g))
 g.set_attribute(DICT,'rebar_t',vol*rebar_rate('head_beam')/1000.0) unless g.get_attribute(DICT,'rebar_mode','').to_s=~/detail/
 mst_v50_after_bk_change!(g)
 vol
end
MST_BZ_FIELDS=[['a0','Bölge başlangıcı (m, BK başından)'],['a1','Bölge bitişi (m, BK başından)'],['depth','Ek derinlik (m, normal tabandan aşağı)'],
 ['slope','Geçiş (eğim) boyu her uçta (m; 0 = dik basamak)']].freeze
def mst_bz_ui
 model=Sketchup.active_model
 sel=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='head_beam' && e.is_a?(Sketchup::Group)}
 raise 'Eklentinin çizdiği bir Başlık Kirişi (Group) seçin.' unless sel.length==1
 g=sel[0];h=mst_attr_hash(g);len=h['length_m'].to_f
 raise mst_hb_rebar_unsupported_reason(g) if mst_hb_rebar_unsupported_reason(g)
 cur=mst_hb_zones_list(h)
 act=UI.inputbox(['İşlem'],['EKLE'],['EKLE|TEMİZLE'],"Taban Bölgesi — #{element_visible_id(g)} (#{cur.length} bölge; uç dişleri BK formundan)")
 return 0 unless act
 zones=cur
 if act[0]=='TEMİZLE'
  zones=[]
 else
  r=UI.inputbox(MST_BZ_FIELDS.map{|_,l|l},['1.0',format('%.2f',[len-1.0,2.0].max),'0.50','0.30'],"Taban Bölgesi Ekle — #{element_visible_id(g)} (boy #{format('%.2f',len)} m)")
  return 0 unless r
  q={};MST_BZ_FIELDS.each_with_index{|(k,l),i|q[k]=mst_v50_num(r[i],l)}
  raise 'Bölge BK boyu içinde olmalı (başlangıç < bitiş).' unless q['a0']>=0 && q['a1']<=len+1e-6 && q['a1']-q['a0']>0.2
  raise 'Ek derinlik 0.05 – 5 m olmalı.' unless q['depth'].between?(0.05,5.0)
  zi=mst_hb_zone_info(h,len)
  raise 'Bölge uç dişleriyle çakışıyor.' if zi['zones'].any?{|z|z['kind']!='zone' && q['a0']<z['a1'] && q['a1']>z['a0']}
  raise 'Bölge mevcut bir bölgeyle çakışıyor.' if cur.any?{|z|q['a0']<z['a1'].to_f && q['a1']>z['a0'].to_f}
  zones=cur+[q]
 end
 return 0 unless UI.messagebox("#{element_visible_id(g)}: #{zones.length} taban bölgesi ile BK yeniden kurulacak (beton, kalıp#{g.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail' ? ', donatı' : ''}). Tek Geri Al.",MB_YESNO)==IDYES
 model.start_operation('MST BK Taban Bölgesi',true)
 begin
  g.set_attribute(DICT,'bottom_zones_json',JSON.generate(zones))
  mst_bz_rebuild!(g)
  commit_with_dependencies(model)
 rescue
  model.abort_operation;raise
 end
 zones.length
rescue => ex
 UI.messagebox("Taban bölgesi: #{ex.message}")
 0
end

# ---------------------------------------------------------------- KD2 kademeli döküm
# 1. kademe: tabandan s m (alçak bölgeler dahil); 2. kademe: üst (len × wid × (h − s)). Kalıp: yan + uç yüzler yükseklik oranıyla.
def mst_hb_stage_q(b)
 s=b.get_attribute(DICT,'pour_stage_split_m',0).to_f
 h=b.get_attribute(DICT,'height_m',0).to_f;l=b.get_attribute(DICT,'length_m',0).to_f;w=b.get_attribute(DICT,'width_m',0).to_f
 return nil unless s>0.05 && s<h-0.05 && l>0 && w>0
 net=qto3_quantity(b,:concrete_m3);fw=qto3_quantity(b,:formwork_m2)
 v2=[[l*w*(h-s),net].min,0.0].max;v1=net-v2
 side=b.get_attribute(DICT,'formwork_long_sides_m2',2*l*h).to_f;ends=b.get_attribute(DICT,'formwork_end_faces_m2',0).to_f
 f2=[[(side+ends)*(h-s)/h,fw].min,0.0].max;f1=fw-f2
 {'split'=>s,'v1'=>v1,'v2'=>v2,'f1'=>f1,'f2'=>f2,'gap'=>b.get_attribute(DICT,'pour_stage_gap_d',3).to_f}
end
def mst_hb_stage_ui
 model=Sketchup.active_model
 sel=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise 'BK / dolfen başlığı seçin.' if sel.empty?
 s0=sel[0].get_attribute(DICT,'pour_stage_split_m',0).to_f
 r=UI.inputbox(['1. kademe yüksekliği (m, BK tabanından; 0 = tek döküm)','Kademeler arası bekleme (gün)'],[format('%.2f',s0),sel[0].get_attribute(DICT,'pour_stage_gap_d',3).to_s],"Kademeli Döküm — #{sel.length} eleman")
 return 0 unless r
 s=mst_v50_num(r[0],'1. kademe yüksekliği',0,30);gap=mst_v50_num(r[1],'Bekleme',0,60)
 bad=sel.select{|b|s>0 && s>=b.get_attribute(DICT,'height_m',0).to_f-0.05}
 raise "#{bad.length} elemanda 1. kademe yüksekliği eleman yüksekliğinden büyük (#{bad.first(4).map{|b|element_visible_id(b)}.join(', ')})." unless bad.empty?
 model.start_operation('MST Kademeli Döküm',true)
 begin
  sel.each{|b|b.set_attribute(DICT,'pour_stage_split_m',s);b.set_attribute(DICT,'pour_stage_gap_d',gap)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 l=sel.first(8).map{|b|q=mst_hb_stage_q(b);q ? format('%s: 1. kademe %.2f m³ / %.1f m² · 2. kademe %.2f m³ / %.1f m²',element_visible_id(b),q['v1'],q['f1'],q['v2'],q['f2']) : "#{element_visible_id(b)}: tek döküm"}
 UI.messagebox("Kademeli döküm kaydedildi (toplam beton / kalıp değişmez; metraj raporunda ve iş programında iki adım):\n#{l.join("\n")}")
 sel.length
rescue => ex
 UI.messagebox("Kademeli döküm: #{ex.message}")
 0
end

def mst_hb_stage_rows(all)
 all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam'}.map{|b|q=mst_hb_stage_q(b);q ? [b,q] : nil}.compact
end
def mst_hb_stage_report_ui(path=nil,open=true)
 all=[];collect_elements(Sketchup.active_model.entities,all)
 rows=mst_hb_stage_rows(all)
 raise 'Kademeli döküm tanımlı BK / dolfen başlığı yok (Kademeli Döküm aracıyla tanımlayın).' if rows.empty?
 tr=rows.map{|b,q|"<tr><td>#{mst_rt_h(element_visible_id(b))}</td><td>#{format('%.2f',q['split'])}</td><td class=n>#{format('%.3f',q['v1'])}</td><td class=n>#{format('%.2f',q['f1'])}</td><td class=n>#{format('%.3f',q['v2'])}</td><td class=n>#{format('%.2f',q['f2'])}</td><td class=n>#{format('%.0f',q['gap'])}</td></tr>"}.join
 t=rows.map{|_,q|q}
 tot="<tr><th>TOPLAM</th><th></th><th class=n>#{format('%.3f',t.sum{|q|q['v1']})}</th><th class=n>#{format('%.2f',t.sum{|q|q['f1']})}</th><th class=n>#{format('%.3f',t.sum{|q|q['v2']})}</th><th class=n>#{format('%.2f',t.sum{|q|q['f2']})}</th><th></th></tr>"
 body="<p>Toplam beton ve kalıp BK pozunda değişmez; tablo dökümü ve iş programı içindir.</p><table><tr><th>Eleman</th><th>1. kademe yük. (m)</th><th>1. kademe beton (m³)</th><th>1. kademe kalıp (m²)</th><th>2. kademe beton (m³)</th><th>2. kademe kalıp (m²)</th><th>bekleme (gün)</th></tr>#{tr}#{tot}</table>"
 path||=mst_rt_out_name('Kademeli_Dokum','html')
 File.write(path,mst_rt_html_page('Kademeli Döküm Metrajı',body))
 (UI.openURL("file:///#{path.tr('\\','/')}") rescue nil) if open
 path
rescue => ex
 UI.messagebox("Kademeli döküm metrajı: #{ex.message}")
 nil
end

# ---------------------------------------------------------------- VK1 vinç / boylama kirişi
# iki BK: eksenleri paralel (plan), VK ikisinin arasında BK'lara dik. pos_m: BK1 başından eksen boyunca VK ortası.
def mst_vk_axes(b)
 tr=b.transformation;u=tr.xaxis;u=Geom::Vector3d.new(u.x,u.y,0)
 u.normalize! if u.length>1e-9
 o=tr.origin
 [u,[o.x.to_f/39.37007874015748,o.y.to_f/39.37007874015748]]
end
def mst_vk_plan(b1,b2,p)
 u1,o1=mst_vk_axes(b1);u2,_=mst_vk_axes(b2)
 raise 'BK eksenleri paralel değil.' if (u1.x*u2.x+u1.y*u2.y).abs<0.995
 ux=u1.x;uy=u1.y;vx=-uy;vy=ux
 w1=b1.get_attribute(DICT,'width_m',0).to_f;w2=b2.get_attribute(DICT,'width_m',0).to_f
 c1=b1.bounds.center;c2=b2.bounds.center;f=39.37007874015748
 c1=[c1.x.to_f/f,c1.y.to_f/f];c2=[c2.x.to_f/f,c2.y.to_f/f]
 d=(c2[0]-c1[0])*vx+(c2[1]-c1[1])*vy
 (vx=-vx;vy=-vy;d=-d) if d<0
 span=d-w1/2.0-w2/2.0
 raise format('BK\'lar arası açıklık geçersiz (%.2f m).',span) if span<=0.05
 pos=p['pos_m'].to_f
 t1=(c1[0]-o1[0])*ux+(c1[1]-o1[1])*uy
 q=[c1[0]+ux*(pos-t1),c1[1]+uy*(pos-t1)]
 st=[q[0]+vx*w1/2.0,q[1]+vy*w1/2.0]
 top1=b1.get_attribute(DICT,'top_elevation_m',0).to_f;top2=b2.get_attribute(DICT,'top_elevation_m',0).to_f
 top=p['top_m'].to_s.strip.empty? ? [top1,top2].min : p['top_m'].to_f
 w=p['width_m'].to_f;h=p['height_m'].to_f
 raise 'VK genişliği ve yüksekliği sıfırdan büyük olmalı.' if w<=0 || h<=0
 l1=b1.get_attribute(DICT,'length_m',0).to_f
 raise format('Konum BK boyu dışında (0 – %.2f m).',l1) if pos-w/2<-1e-6 || pos+w/2>l1+1e-6
 bot=top-h
 cont=[b1,b2].map do |b|
  bb=b.get_attribute(DICT,'bottom_elevation_m',0).to_f;bt=b.get_attribute(DICT,'top_elevation_m',bb+b.get_attribute(DICT,'height_m',0).to_f).to_f
  [[[top,bt].min-[bot,bb].max,0.0].max*w,b]
 end
 {'start'=>st,'dir'=>[vx,vy],'along'=>[ux,uy],'span'=>span,'width'=>w,'height'=>h,'top'=>top,'bottom'=>bot,'pos'=>pos,
  'contact'=>cont.map{|a,b|[b.persistent_id,a]},'w1'=>w1,'w2'=>w2}
end
def mst_vk_next_id(role,model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 used=all.map{|e|e.get_attribute(DICT,'head_beam_id','').to_s}
 n=1;n+=1 while used.include?(format('%s-%02d',role,n));format('%s-%02d',role,n)
end
def mst_vk_create!(b1,b2,p,model=Sketchup.active_model)
 role=p['role'].to_s.upcase=='BBK' ? 'BBK' : 'VK'
 pl=mst_vk_plan(b1,b2,p)
 l=pl['span'];w=pl['width'];h=pl['height']
 par=b1.parent.respond_to?(:entities) ? b1.parent.entities : model.active_entities
 g=par.add_group
 e=g.entities
 f=e.add_face([0,m(-w/2),0],[m(l),m(-w/2),0],[m(l),m(w/2),0],[0,m(w/2),0]);f.reverse! if f.normal.z<0;f.pushpull(m(h))
 hx='#F4B183';fm=material_for(model,"MAG Kalıp #{hx}",hx)
 bottom=0.0;long=0.0
 e.grep(Sketchup::Face).each do |fc|
  n=fc.normal;a=fc.area.to_f/(1.m*1.m)
  if n.z>0.999 then fc.set_attribute(DICT,'formwork',false);fc.set_attribute(DICT,'formwork_type','TOP_OR_CONTACT');fc.material=nil
  elsif n.x.abs>0.999 then fc.set_attribute(DICT,'formwork',false);fc.set_attribute(DICT,'formwork_type','BK_CONTACT');fc.material=nil   # alın: BK yüzüne dayanır
  elsif n.y.abs>0.999 then fc.set_attribute(DICT,'formwork',true);fc.set_attribute(DICT,'formwork_type','LONG_SIDE');fc.material=fm;long+=a
  else fc.set_attribute(DICT,'formwork',true);fc.set_attribute(DICT,'formwork_type','BOTTOM');fc.material=fm;bottom+=a end
 end
 vx,vy=pl['dir'];sx,sy=pl['start']
 # yerel x = BK'lara dik (VK boyu), y = BK ekseni yönü, z yukarı
 tr=Geom::Transformation.axes(Geom::Point3d.new(m(sx),m(sy),m(pl['bottom'])),Geom::Vector3d.new(vx,vy,0),Geom::Vector3d.new(-vy,vx,0),Z_AXIS)
 g.transform!(tr)
 id=mst_vk_next_id(role,model)
 rail=p['rail_type'].to_s.strip.upcase;rail='YOK' if rail.empty? || role=='BBK'
 rkg=MST_VK_RAILS.key?(rail) ? MST_VK_RAILS[rail] : p['rail_kg_m'].to_f
 cc=p['concrete_class'].to_s.strip;cc=b1.get_attribute(DICT,'concrete_class','C35/45').to_s if cc.empty?
 fw=bottom+long
 {'element_type'=>'head_beam','beam_role'=>role,'head_beam_id'=>id,'beam_type'=>format('%s %.2f×%.2f',role,w,h),'head_beam_mode'=>'link',
  'length_m'=>l,'width_m'=>w,'height_m'=>h,'top_elevation_m'=>pl['top'],'bottom_elevation_m'=>pl['bottom'],'concrete_class'=>cc,
  'concrete_volume_m3'=>l*w*h,'formwork_area_m2'=>fw,'formwork_gross_area_m2'=>fw,'formwork_net_area_m2'=>fw,'formwork_bottom_m2'=>bottom,
  'formwork_long_sides_m2'=>long,'formwork_end_faces_m2'=>0.0,'formwork_color'=>hx,'connected_pile_ids'=>'','selected_pile_count'=>0,
  'support_left_pid'=>b1.persistent_id,'support_right_pid'=>b2.persistent_id,'link_pos_m'=>pl['pos'],
  'link_contact_json'=>JSON.generate(pl['contact']),'rail_type'=>rail,'rail_kg_m'=>rkg,'rail_length_m'=>(rkg>0 ? l+(pl['w1']+pl['w2'])/2.0 : 0.0),
  'rail_clip_spacing_m'=>p['clip_spacing_m'].to_f,'rail_clip_kg'=>p['clip_kg'].to_f,'axis'=>b1.get_attribute(DICT,'axis','').to_s,
  'rebar_t'=>l*w*h*rebar_rate('head_beam')/1000.0}.each{|k,v|g.set_attribute(DICT,k,v)}
 %w[project system structure ano zone qto_zone].each{|k|v=b1.get_attribute(DICT,k,'').to_s;g.set_attribute(DICT,k,v) unless v.empty?}
 finalize_bim_identity(g,model)
 g.set_attribute(DICT,'head_beam_id',id);g.name=id
 g
end
# BK'nın VK / BBK temasından düşülecek kalıp (m²) — 1.5 s önbellek
def mst_vk_contact_index(model=Sketchup.active_model)
 c=@mst_vk_idx;now=Time.now.to_f
 return c[:idx] if c && c[:m]==model.object_id && now-c[:t]<1.5
 all=[];collect_elements(model.entities,all)
 idx=Hash.new(0.0)
 all.each do |e|
  next unless e.get_attribute(DICT,'element_type','').to_s=='head_beam' && mst_v50_link?(e)
  (JSON.parse(e.get_attribute(DICT,'link_contact_json','[]').to_s) rescue []).each{|pid,a|idx[pid.to_i]+=a.to_f}
 end
 @mst_vk_idx={m:model.object_id,t:now,idx:idx}
 idx
end
def mst_vk_contact_m2(b)
 return 0.0 if mst_v50_link?(b)
 mst_vk_contact_index[b.persistent_id].to_f
rescue
 0.0
end
MST_VK_FIELDS=[['role','Eleman: VK (vinç kirişi) / BBK (boylama kirişi)'],['pos_m','Konum: 1. BK başından eksen boyunca VK ortası (m)'],
 ['width_m','Genişlik (m)'],['height_m','Yükseklik (m)'],['top_m','Üst kot (m; boş = BK üst kotu)'],['concrete_class','Beton sınıfı (boş = BK)'],
 ['rail_type',"Ray tipi (VK): #{MST_VK_RAILS.keys.join(' ')}"],['rail_kg_m','Ray (listede yoksa) kg/m'],['clip_spacing_m','Ray klipsi aralığı (m; 0 = yok)'],['clip_kg','Klips takımı ağırlığı (kg)']].freeze
def mst_vk_ui
 model=Sketchup.active_model
 hbs=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='head_beam' && !mst_v50_link?(e)}
 raise 'İki Başlık Kirişi seçin (VK / BBK ikisinin arasında, BK\'lara dik oluşur).' unless hbs.length==2
 last=(JSON.parse(model.get_attribute(DICT,'mst_vk_last_json','{}').to_s) rescue {})
 dflt={'role'=>'VK','pos_m'=>'2.0','width_m'=>'0.80','height_m'=>'1.20','top_m'=>'','concrete_class'=>'','rail_type'=>'A100','rail_kg_m'=>'0','clip_spacing_m'=>'0.60','clip_kg'=>'4.5'}.merge(last)
 r=UI.inputbox(MST_VK_FIELDS.map{|_,l|l},MST_VK_FIELDS.map{|k,_|dflt[k].to_s},'Vinç / Boylama Kirişi')
 return 0 unless r
 p=Hash[MST_VK_FIELDS.each_with_index.map{|(k,_),i|[k,r[i].to_s.strip]}]
 %w[pos_m width_m height_m].each{|k|p[k]=mst_v50_num(p[k],k)}
 p['top_m']=p['top_m'].empty? ? '' : mst_v50_num(p['top_m'],'Üst kot')
 p['rail_kg_m']=mst_v50_num(p['rail_kg_m'],'Ray kg/m',0);p['clip_spacing_m']=mst_v50_num(p['clip_spacing_m'],'Klips aralığı',0);p['clip_kg']=mst_v50_num(p['clip_kg'],'Klips ağırlığı',0)
 b1,b2=hbs
 pl=mst_vk_plan(b1,b2,p)
 role=p['role'].to_s.upcase=='BBK' ? 'BBK' : 'VK'
 msg=format("%s: %s ↔ %s arası, açıklık %.2f m · %.2f × %.2f m · üst kot %+.2f\nBeton %.3f m³ · kalıp (alt + 2 yan) %.2f m² · alın kalıbı yok\nBK kalıbından düşülecek: %s\n%sBoyuna donatı BK'ya %dØ ankrajlı çizilir (donatı panelinden).\nOluşturulsun mu? (tek Geri Al)",
  MST_VK_ROLES[role],element_visible_id(b1),element_visible_id(b2),pl['span'],pl['width'],pl['height'],pl['top'],pl['span']*pl['width']*pl['height'],
  pl['span']*(pl['width']+2*pl['height']),pl['contact'].map{|pid,a|format('%.2f m²',a)}.join(' + '),
  (role=='VK' && p['rail_type'].upcase!='YOK') ? "Ray #{p['rail_type']} (#{MST_VK_RAILS[p['rail_type'].upcase] || p['rail_kg_m']} kg/m)#{p['clip_spacing_m']>0 ? ", klips #{p['clip_spacing_m']} m aralıkla" : ''}\n" : '',mst_rs_lap_d.round)
 return 0 unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.set_attribute(DICT,'mst_vk_last_json',JSON.generate(p))
 model.start_operation("MST #{MST_VK_ROLES[role]}",true)
 begin
  g=mst_vk_create!(b1,b2,p,model)
  @mst_vk_idx=nil
  [b1,b2].each{|b|b.set_attribute(DICT,'formwork_net_area_m2',head_beam_net_formwork_area(b)) rescue nil}
  commit_with_dependencies(model)
  model.selection.clear;model.selection.add(g)
 rescue
  model.abort_operation;raise
 end
 1
rescue => ex
 UI.messagebox("Vinç / boylama kirişi: #{ex.message}")
 0
end
# VK donatı varsayılanı: kiriş, boyuna BK'ya 50Ø ankraj
def mst_vk_rebar_defaults
 {'kind'=>'BEAM','end_anchor_d'=>mst_rs_lap_d,'cover_mm'=>(mst_rs_get('cover_bk_mm') rescue 75.0)}
end

# ---------------------------------------------------------------- metraj ekleri (ray, klips, menfez sacı)
def mst_v50_steel_sources(all)
 out=[]
 vks=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam' && mst_v50_role(e)=='VK'}
 vks.group_by{|e|e.get_attribute(DICT,'rail_type','').to_s}.each do |rt,es|
  next if rt.empty? || rt=='YOK'
  kg=es.sum{|e|e.get_attribute(DICT,'rail_length_m',0).to_f*e.get_attribute(DICT,'rail_kg_m',0).to_f}
  ln=es.sum{|e|e.get_attribute(DICT,'rail_length_m',0).to_f}
  out << {key:"MST:RAIL:#{rt}",name:format('Vinç rayı %s (%.1f m, %s kg/m) temin + montaj',rt,ln,es[0].get_attribute(DICT,'rail_kg_m',0).to_f.round(1)),unit:'kg',quantity:kg,elems:es} if kg>0
 end
 clips=vks.sum{|e|s=e.get_attribute(DICT,'rail_clip_spacing_m',0).to_f;l=e.get_attribute(DICT,'rail_length_m',0).to_f;s>0 && l>0 ? 2*((l/s).floor+1) : 0}
 out << {key:'MST:RAIL_CLIP',name:'Ray bağlantı klipsi takımı (iki yan)',unit:'ad',quantity:clips.to_f,elems:vks} if clips>0
 hbs=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 cv=hbs.sum{|b|mst_hb_culvert_steel(b)}
 out << {key:'MST:CULVERT_STEEL',name:'Menfez sac kutusu (çelik, imalat + montaj)',unit:'kg',quantity:cv,elems:hbs.select{|b|mst_hb_culvert_steel(b)>0}} if cv>0
 out
end
def mst_v50_boq_rows(library,map)
 all=[];collect_elements(Sketchup.active_model.entities,all)
 mst_v50_steel_sources(all).map do |r|
  if map.key?(r[:key])
   boq_mapped_row(r[:key],r[:unit],r[:quantity],map[r[:key]],library)
  else
   {code:'—',name:r[:name],unit:r[:unit],quantity:r[:quantity],unit_price:nil,total:nil,source:r[:key],status:'ÖBF EŞLEŞTİRİLMELİ',library_price:true}
  end
 end
rescue
 []
end

end
end
