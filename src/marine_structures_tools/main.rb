# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require_relative 'engineering_ui'
require_relative 'qto_workspace'
require_relative 'embed'
require_relative 'takeoff_excel'
require_relative 'quantity_service'
require_relative 'revision_signatures'
require_relative 'project_workspace'
require_relative 'controlled_editor'
require_relative 'relationship_audit'
require_relative 'material_change'
require_relative 'elevation_sync'
require_relative 'headbeam_editor'
require_relative 'model_health'
require_relative 'scoped_model_health'
require_relative 'record_repair'
require_relative 'health_report'
require_relative 'health_history'
module MAG
module MarineStructuresTools
extend self
DICT='MAG_MarineStructures'.freeze
RHO=7850.0
SEG=48
MST_BUILD = 'v0.51.5 TB1 FIX1'
# Features present in this build (test runners check these, not the build name).
MST_FEATURES=%w[BK6 KN1 KN1.1 KN1.2 KN2 BKR3 RB1 RB1.1 RB2 DS1 DS1.1 DS1.2 DS1.3 DS1.4 DS1.5 DS1.6 DS3 DS2 UI1 UI2 UI3 UI4 UI5 UI6 UI7 UI8 UI9 UI9.1 JG1 RF2X RB3 BQ1 BK1 GD1 LB1 LB2 PE1 VW2 BR4 DR1 DR2 DR3 AR1 RB5 PP1 LP1 RS1 VZ1 DM1 BL1 KS1 KV1 RV1 CK1 SH1 ET1 SP1 UP1 DX0 AF1 KD1 KF1 VK1 KD2 TB1 MF1 ET2 CZ1 BN1 DG1 PC2 DX1 TP1 SH2 AN1 MS1 RS2 AX1 AX1.1 BK2 DR5 CB1].freeze
def mm(v);v.to_f.mm;end
def m(v);v.to_f.m;end


# ===== v0.34.11 Central Grid Manager / Type-level Tags =====
# Geometry stays Untagged; only BIM Group/Component containers receive MST tags.
# Tag hierarchy is encoded in the tag name: MST | ANO | FAMILY | TYPE.
def mst_tag_code(entity)
  et=entity.get_attribute(DICT,'element_type','').to_s
  case et
  when 'steel_pipe_pile' then 'PILE'
  when 'pile_infill_concrete' then 'PILE-INFILL'
  when 'bored_pile' then 'BORED-PILE'
  when 'head_beam' then 'HEAD-BEAM'
  when 'flat_precast' then 'PD'
  when 'channel_precast' then 'PK'
  when 'crane_precast'
    fam=entity.get_attribute(DICT,'precast_family','PV').to_s.upcase
    fam=='PDÖ' || fam=='PDO' ? 'PDÖ' : 'PV'
  when 'deck_slab' then 'DECK'
  when 'deck_topping' then 'TOPPING'
  when 'curb' then 'CURB'
  when 'crown_wall' then 'CROWN'
  when 'accessory' then 'ACCESSORY'
  else nil
  end
end

def mst_clean_tag_part(value)
  value.to_s.strip.gsub(/[\\\/:*?"<>|]/,'-').gsub(/\s+/,' ')
end

def mst_tag_type(entity)
  et=entity.get_attribute(DICT,'element_type','').to_s
  # Prefer the user's engineering type name. Fall back to canonical BIM type_id.
  keys=case et
  when 'head_beam' then %w[beam_type type_id library_type_id]
  when 'flat_precast','channel_precast','crane_precast' then %w[precast_type_id precast_type library_type_id type_id]
  when 'accessory' then %w[accessory_type library_name model type_id library_type_id]
  when 'steel_pipe_pile','bored_pile','deck_slab','deck_topping','curb','crown_wall','pile_infill_concrete' then %w[type_id library_type_id]
  else %w[type_id library_type_id]
  end
  keys.each do |key|
    v=mst_clean_tag_part(entity.get_attribute(DICT,key,'').to_s)
    return v unless v.empty?
  end
  ''
end

def mst_tag_name(entity, model=Sketchup.active_model)
  code=mst_tag_code(entity); return nil if code.to_s.empty?
  ano=mst_clean_tag_part(entity.get_attribute(DICT,'ano',entity.get_attribute(DICT,'ano_id','')).to_s)
  ano=mst_clean_tag_part(model.get_attribute(DICT,'active_ano','ANO-01').to_s) if ano.empty? && code!='ACCESSORY'
  typ=mst_tag_type(entity)
  parts=['MST']
  parts << ano unless ano.empty?
  parts << code
  parts << typ unless typ.empty?
  parts.join(' | ')
end

def mst_assign_tag(entity, model=Sketchup.active_model)
  return entity unless entity && entity.respond_to?(:layer=)
  name=mst_tag_name(entity,model); return entity if name.to_s.empty?
  tags=model.layers
  tag=tags[name] || tags.add(name)
  entity.layer=tag
  entity.set_attribute(DICT,'mst_tag',name)
  entity
rescue => e
  puts "MST Tag assignment: #{e.message}"
  entity
end


# ===== v0.38 RB3 — Donatı Tag'leri yapıya (ANO) göre =====
# Her donatı grubu (BK / döşeme donatısı, kazık kafesi) "MST | DONATI | <ANO>" Tag'ine konur.
# Çubukların kendisi Untagged kalır; görünürlük grubun Tag'inden gelir (SketchUp kuralı).
def mst_rebar_ano(e)
 return '' unless e && e.respond_to?(:get_attribute)
 %w[ano ano_id structure placement_structure].each do |k|
  v=mst_clean_tag_part(e.get_attribute(DICT,k,'').to_s)
  return v unless v.empty?
 end
 ''
end
def mst_rebar_tag_name(ano)
 a=mst_clean_tag_part(ano.to_s);a='Yapı Atanmamış' if a.empty?
 "MST | DONATI | #{a}"
end
# set: donatı grubu, owner: ait olduğu eleman (BK / döşeme / kazık); Component içindeyse owner=nil
def mst_rebar_tag!(set,owner=nil,model=Sketchup.active_model)
 return unless set && set.valid? && set.respond_to?(:layer=)
 ano=mst_rebar_ano(owner)
 if ano.empty? && owner.nil?
  # paylaşılan tanım: tanımı kullanan bütün kazıklar aynı yapıdaysa o yapı, değilse ortak
  df=set.parent
  if df.respond_to?(:instances)
   anos=df.instances.map{|i|mst_rebar_ano(i)}.reject(&:empty?).uniq
   ano=anos.length==1 ? anos[0] : (anos.empty? ? '' : 'Ortak Tip')
  end
 end
 name=mst_rebar_tag_name(ano)
 tag=model.layers[name]
 unless tag
  tag=model.layers.add(name)
  tag.visible=(mst_rs_get('rebar_visible',model).to_i!=0) if respond_to?(:mst_rs_get) && tag.respond_to?(:visible=)   # v0.49 VZ1: varsayılan gizli
 end
 set.layer=tag unless set.layer==tag
 set.set_attribute(DICT,'mst_tag',name)
 name
rescue => e
 puts "MST donatı Tag: #{e.message}"
 nil
end
MST_REBAR_SET_TYPES=%w[head_beam_rebar_set deck_rebar_set pile_rebar_set drawing_rebar_set].freeze
# Modeldeki bütün donatı gruplarını (Component tanımları dahil) yeniden etiketler. Çağıran operasyon açar.
def mst_rebar_retag_all!(model=Sketchup.active_model)
 n=Hash.new(0)
 model.definitions.each do |df|
  next if df.image?
  df.entities.grep(Sketchup::Group).each do |g|
   next unless MST_REBAR_SET_TYPES.include?(g.get_attribute(DICT,'element_type','').to_s)
   owner=df.group? ? df.instances.first : nil
   name=mst_rebar_tag!(g,owner,model)
   n[name]+=1 if name
  end
 end
 n
end
def mst_retag_all(show_message=true)
  model=Sketchup.active_model; all=[]; collect_elements(model.entities,all)
  seen={}; all.each{|e|seen[e]=true}   # v0.38 BK3.3: hash lookup (large models)
  # collect_elements intentionally omits some newer/auxiliary types; add a safe recursive pass.
  walk=lambda do |ents|
    ents.each do |e|
      if e.respond_to?(:get_attribute) && !e.get_attribute(DICT,'element_type','').to_s.empty?
        (all << e;seen[e]=true) unless seen[e]
      end
      walk.call(e.entities) if e.is_a?(Sketchup::Group) && e.get_attribute('MAG_MST_Label','kind').nil?
    end
  end
  walk.call(model.entities)
  count=0
  model.start_operation('MST Otomatik Tip Tag Ataması',true)
  all.each do |e|
    next if mst_tag_code(e).nil?
    mst_assign_tag(e,model); count+=1
  end
  rt=mst_rebar_retag_all!(model)   # v0.38 RB3
  model.commit_operation
  UI.messagebox("MST Tag'leri hazırlandı.\n#{count} BIM elemanı ANO / aile / tip bazında ilgili Tag'e atandı.#{rt.empty? ? '' : "\n\nDonatı Tag'leri (yapıya göre):\n"+rt.sort.map{|k,v|"  #{k}: #{v} donatı grubu"}.join("\n")}") if show_message
  count
rescue => e
  model.abort_operation rescue nil
  UI.messagebox("MST Tag atama hatası: #{e.message}") if show_message
  0
end
# ===== end Automatic SketchUp Tags =====

def html_escape(v)
 v.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;')
end
# v0.51.5 K29: arayüz callback'inden gelen JSON okunamazsa Türkçe ileti, işlem yapılmaz (nil)
def mst_cb_json(j,label)
 JSON.parse(j.to_s)
rescue JSON::ParserError, TypeError => ex
 UI.messagebox("#{label}: arayüzden gelen veri okunamadı; işlem yapılmadı.\n(#{ex.message[0,200]})")
 nil
end

def color_from_hex(hex, fallback='#F4B183')
 h=hex.to_s.strip
 h=fallback unless h.match?(/\A#[0-9A-Fa-f]{6}\z/)
 Sketchup::Color.new(h[1,2].to_i(16),h[3,2].to_i(16),h[5,2].to_i(16))
end

def material_for(model,name,hex)
 mats=model.materials
 mat=mats[name] || mats.add(name)
 mat.color=color_from_hex(hex)
 mat
end

# Visual formwork control: only faces actually counted as formwork are colored.
# IMPORTANT: paint FRONT face only. Back/inner side is always left unpainted so
# SketchUp material-area reports do not double-count the same physical formwork face.
def mark_formwork_face(face, flag, form_mat=nil, concrete_mat=nil, kind='FORMWORK')
 face.set_attribute(DICT,'formwork',flag ? true : false)
 face.set_attribute(DICT,'formwork_type',flag ? kind : 'NON_FORMWORK')
 if flag && form_mat
  face.material=form_mat; face.back_material=nil
 elsif !flag
  face.material=nil; face.back_material=nil
 end
end

def paint_flat_precast_formwork(group, flags, form_mat, concrete_mat)
 group.entities.grep(Sketchup::Face).each do |face|
  n=face.normal
  flag=false; kind='NON_FORMWORK'
  if n.z < -0.999
   flag=flags[0]; kind='BOTTOM'
  elsif n.y < -0.999
   flag=flags[1]; kind='LONG_SIDE_1'
  elsif n.y > 0.999
   flag=flags[2]; kind='LONG_SIDE_2'
  elsif n.x < -0.999
   flag=flags[3]; kind='END_1'
  elsif n.x > 0.999
   flag=flags[4]; kind='END_2'
  else
   # Top horizontal surface is never formwork in visual control.
   flag=false; kind='TOP'
  end
  mark_formwork_face(face,flag,form_mat,concrete_mat,kind)
 end
end

def build_crane_precast_solid(entities, length_len, width_m, thickness_m, extra_depth_m, left_tooth_m=0.0, right_tooth_m=0.0)
 # Vinç prekastı: uç dişler BOY (X) doğrultusundadır.
 # Genişlik (Y) boyunca kesit daima tam prekast genişliğidir.
 l=length_len.to_f; w=width_m.to_f; t=thickness_m.to_f; ed=extra_depth_m.to_f
 lt=m(left_tooth_m).to_f; rt=m(right_tooth_m).to_f
 raise 'Vinç Prekastı boy/genişlik/kalınlık değerleri geçersiz.' if l<=0 || w<=0 || t<=0 || ed<0 || lt<0 || rt<0
 raise 'Sol + sağ uç diş boyu prekast boyundan küçük olmalıdır.' if lt+rt >= l-0.001
 if ed>0
  # X-Z profil: uçlarda yalnız ana kalınlık; orta bölgede ilave alt derinlik.
  profile=[[0,0],[lt,0],[lt,-m(ed)],[l-rt,-m(ed)],[l-rt,0],[l,0],[l,m(t)],[0,m(t)]]
 else
  profile=[[0,0],[l,0],[l,m(t)],[0,m(t)]]
 end
 pts=profile.map{|xx,zz| Geom::Point3d.new(xx,0,zz)}
 face=entities.add_face(pts);raise 'Vinç Prekastı tek parça kesiti oluşturulamadı.' unless face
 face.reverse! if face.normal.y<0
 face.pushpull(m(w))
 true
end

# v0.51.5 K54 (yalnız uyarı): ilave derinlikli vinç prekastında uç diş boyu oturma boyundan kısaysa derin orta bölüm
# BK gövdesine girer (prekast yerel X: 0 → boy; oturma 0..sol oturma ve boy−sağ oturma..boy). Geometri / metraj değişmez.
def mst_pv_tooth_seat_warnings(e)
 g=->(k){e.get_attribute(DICT,k,0).to_f}
 ed=g.('extra_depth_m');w=g.('width_m');return [] unless ed>0 && w>0
 sl=e.get_attribute(DICT,'seat_left_m',e.get_attribute(DICT,'seat_each_side_m',0)).to_f
 sr=e.get_attribute(DICT,'seat_right_m',e.get_attribute(DICT,'seat_each_side_m',0)).to_f
 [['sol',g.('left_tooth_m'),sl],['sağ',g.('right_tooth_m'),sr]].map do |yan,t,s|
  next nil unless s-t>1e-6
  format('%s: %s diş boyu (%.3f m) oturma boyundan (%.3f m) kısa; ilave derinlikli orta bölüm BK gövdesine %.3f m giriyor. Bu kesişim hacmi (%.3f m³) BK ve prekast betonunda iki kez sayılıyor olabilir.',
   element_visible_id(e),yan,t,s,s-t,w*ed*(s-t))
 end.compact
end

def paint_crane_precast_formwork(group, form_mat=nil)
 group.entities.grep(Sketchup::Face).each do |face|
  # Üst döküm yüzeyi kalıp değildir; birleşik kesitin tüm alt, kademe, yan ve uç yüzleri kalıptır.
  top=face.normal.z>0.999
  mark_formwork_face(face,!top,form_mat,nil,top ? 'TOP' : 'CRANE_PRECAST_FORMWORK')
 end
end

def paint_channel_precast_formwork(group, outer_width_m, wall_t_m, inner_depth_m, base_thickness_m, flags, form_mat, concrete_mat)
 # Kanal Prekastı kalıp kuralı:
 # - dış taban + dış yanlar: opsiyonel kalıp
 # - U kanalın İÇ TABANI + iki İÇ DÜŞEY YÜZEYİ: ayrı "inner" kalıp grubu
 # - iki duvarın ÜST YATAY ŞERİTLERİ: kalıp DEĞİL
 # - uç U kesitleri: opsiyonel uç kalıbı
 ow=m(outer_width_m).to_f; wt=m(wall_t_m).to_f
 di=m(inner_depth_m).to_f; bt=m(base_thickness_m).to_f
 top_z=bt+di; tol=1.mm.to_f
 group.entities.grep(Sketchup::Face).each do |face|
  n=face.normal; c=face.bounds.center; flag=false; kind='NON_FORMWORK'
  if n.z < -0.999
   flag=flags[:bottom]; kind='OUTER_BOTTOM'
  elsif n.z > 0.999
   # Upward faces must be split: channel inner floor IS formwork, wall tops are NOT.
   if (c.z-bt).abs < tol
    flag=flags[:inner]; kind='INNER_FLOOR'
   else
    flag=false; kind='WALL_TOP'
   end
  elsif n.y.abs > 0.999
   outer=(c.y.abs < tol || (c.y-ow).abs < tol)
   if outer
    flag=flags[:sides]; kind='OUTER_SIDE'
   else
    flag=flags[:inner]; kind='INNER_SIDE'
   end
  elsif n.x.abs > 0.999
   flag=flags[:ends]; kind='END_FACE'
  else
   flag=false; kind='NON_FORMWORK'
  end
  mark_formwork_face(face,flag,form_mat,concrete_mat,kind)
 end
end

def paint_deck_formwork(parent, form_mat, concrete_mat, u_axis=nil, gross_u0=nil, gross_u1=nil)
 # v0.34.10g - Single-group deck formwork visualisation.
 # Deck geometry now lives directly in parent.entities, therefore the old child-group
 # traversal no longer painted anything.  Paint only the actual exposed vertical faces:
 # free longitudinal sides + the two overall outer end faces.  Horizontal/contact faces
 # remain unpainted and are excluded from formwork QTO.
 tol=2.mm.to_f
 faces=[]
 parent.entities.grep(Sketchup::Face).each{|f| faces << [f,Geom::Transformation.new]}
 parent.entities.grep(Sketchup::Group).each do |piece|
  tr=piece.transformation
  piece.entities.grep(Sketchup::Face).each{|f| faces << [f,tr]}
 end
 faces.each do |face,tr|
  n=face.normal.transform(tr)
  flag=false; kind='CONTACT_OR_HORIZONTAL'
  if n.z.abs < 0.01 && u_axis
   # Longitudinal side normal is perpendicular to deck U axis in plan.
   along=(n.x*u_axis.x+n.y*u_axis.y).abs
   if along < 0.01
    flag=true; kind='FREE_OUTER_LONG_SIDE'
   elsif !gross_u0.nil? && !gross_u1.nil?
    wc=face.bounds.center.transform(tr)
    pu=wc.x*u_axis.x + wc.y*u_axis.y + wc.z*u_axis.z
    if (pu-gross_u0).abs <= tol || (pu-gross_u1).abs <= tol
     flag=true; kind='FREE_OUTER_END_FACE'
    end
   end
  end
  mark_formwork_face(face,flag,form_mat,concrete_mat,kind)
 end
end

# v0.34.10h - Visually clean redundant coplanar deck-top seams without
# risking the slab topology.  Internal coplanar top edges are hidden/softened;
# perimeter, openings and level-change edges remain visible.
def clean_deck_top_coplanar_edges(group)
 tol_n=1.0e-5
 tol_d=0.2.mm.to_f
 count=0
 group.entities.grep(Sketchup::Edge).each do |edge|
  fs=edge.faces
  next unless fs.length==2
  a,b=fs
  na=a.normal; nb=b.normal
  # accept either winding direction; both adjacent faces must be horizontal
  next unless na.z.abs>0.9999 && nb.z.abs>0.9999
  next unless (na.x.abs-nb.x.abs).abs<tol_n && (na.y.abs-nb.y.abs).abs<tol_n && (na.z.abs-nb.z.abs).abs<tol_n
  pa=a.vertices.first.position; pb=b.vertices.first.position
  za=pa.z; zb=pb.z
  next unless (za-zb).abs<=tol_d
  edge.soft=true if edge.respond_to?(:soft=)
  edge.smooth=true if edge.respond_to?(:smooth=)
  edge.hidden=true if edge.respond_to?(:hidden=)
  count+=1
 end
 count
end

def classify_box_faces(group, form_mat, concrete_mat)
 bottom=0.0; long_side=0.0; end_face=0.0
 group.entities.grep(Sketchup::Face).each do |face|
  n=face.normal
  a=face.area.to_f / (1.m * 1.m)
  if n.z > 0.999
   # Upward-facing surfaces are casting/contact/top surfaces, not external formwork.
   # This also excludes horizontal precast-seat/recess surfaces from coloring and QTO.
   face.material=concrete_mat; face.back_material=nil
   face.set_attribute(DICT,'formwork',false)
   face.set_attribute(DICT,'formwork_type','TOP_OR_CONTACT')
  elsif n.y.abs > 0.999
   face.material=form_mat; face.back_material=nil
   face.set_attribute(DICT,'formwork',true)
   face.set_attribute(DICT,'formwork_type','LONG_SIDE')
   long_side += a
  elsif n.z < -0.001
   face.material=form_mat; face.back_material=nil
   face.set_attribute(DICT,'formwork',true)
   face.set_attribute(DICT,'formwork_type', n.z < -0.999 ? 'BOTTOM' : 'RECESS_SLOPE')
   bottom += a
  else
   face.material=form_mat; face.back_material=nil
   face.set_attribute(DICT,'formwork',true)
   face.set_attribute(DICT,'formwork_type','END_FACE')
   end_face += a
  end
 end
 [bottom,long_side,end_face]
end

def recess_profile_points(len, hei, data)
 # Local X-Z side profile. z=0 normal HB bottom, z=hei normal HB top.
 # Profile supports independent START/END lower teeth and precast seats.
 l=len.to_f; h=hei.to_f
 son=data['end_seat_enabled'].to_s=='1'
 sos=data['start_seat_enabled'].to_s=='1'
 st_on=data['start_tooth_enabled'].to_s=='1'
 en_on=data['end_tooth_enabled'].to_s=='1'

 # TOP boundary: start -> end, with optional rectangular precast seats.
 pts=[[0.0,h]]
 if sos
  off=[m(data['start_seat_offset_m'].to_f).to_f,l].min
  sw=[m(data['start_seat_length_m'].to_f).to_f,[l-off,0].max].min
  sd=[m(data['start_seat_depth_m'].to_f).to_f,h].min
  if sw>0 && sd>0
   pts << [off,h] if off>0
   pts << [off,h-sd]
   pts << [off+sw,h-sd]
   pts << [off+sw,h]
  end
 end
 if son
  off=[m(data['end_seat_offset_m'].to_f).to_f,l].min
  sw=[m(data['end_seat_length_m'].to_f).to_f,[l-off,0].max].min
  sd=[m(data['end_seat_depth_m'].to_f).to_f,h].min
  x2=l-off
  x1=x2-sw
  # append end seat only if it does not reverse over an earlier start seat
  if sw>0 && sd>0 && x1 >= pts.last[0]
   pts << [x1,h] if x1>pts.last[0]
   pts << [x1,h-sd]
   pts << [x2,h-sd]
   pts << [x2,h]
  end
 end
 pts << [l,h] unless pts.last==[l,h]
 pts << [l,0.0]

 # BOTTOM boundary: end -> start, with independent lower teeth.
 if en_on
  tl=[m(data['end_tooth_length_m'].to_f).to_f,l].min
  sl=[m(data['end_tooth_slope_m'].to_f).to_f,tl].min
  dz=m(data['end_tooth_depth_m'].to_f).to_f
  if tl>0 && dz>0
   # End tooth: vertical drop at the outer beam end, lowered flat soffit,
   # then the user-defined slope length back up to the normal HB soffit.
   # Example tl=1.50, sl=0.30: 1.20 m flat lowered zone + 0.30 m transition.
   pts << [l,-dz]
   pts << [l-tl+sl,-dz] if (tl-sl)>0
   pts << [l-tl,0.0] if sl>0
   pts << [l-tl,-dz] if sl<=0
   pts << [l-tl,0.0] if sl<=0
  end
 end
 # v0.50 TB1: taban bölgeleri (uç dişleri arasında)
 if respond_to?(:mst_hb_zone_profile_pts)
  lo=st_on ? [m(data['start_tooth_length_m'].to_f).to_f,l].min : 0.0
  hi=en_on ? l-[m(data['end_tooth_length_m'].to_f).to_f,l].min : l
  mst_hb_zone_profile_pts(data,l,lo,hi).each{|q|pts << q}
 end
 if st_on
  tl=[m(data['start_tooth_length_m'].to_f).to_f,l].min
  sl=[m(data['start_tooth_slope_m'].to_f).to_f,tl].min
  dz=m(data['start_tooth_depth_m'].to_f).to_f
  if tl>0 && dz>0
   pts << [tl,0.0]
   pts << [tl-sl,-dz] if sl>0
   pts << [tl,-dz] if sl<=0
   pts << [0.0,-dz]
  else
   pts << [0.0,0.0]
  end
 else
  pts << [0.0,0.0]
 end

 out=[]
 pts.each{|q|out<<q if out.empty? || out.last!=q}
 out
end

def polygon_area_xz(points)
 0.5*points.each_with_index.sum{|p,i|q=points[(i+1)%points.length]; p[0]*q[1]-q[0]*p[1]}.abs
end

def pile_weight(dmm,tmm,lm)
 d=dmm.to_f/1000.0;t=tmm.to_f/1000.0;di=d-2*t
 raise 'Et kalınlığı dış çapa göre çok büyük.' if di<=0
 Math::PI/4.0*(d*d-di*di)*lm.to_f*RHO
end

# Canonical theoretical pipe mass; never trust stale cached weight_kg for QTO.
def mst_pile_canonical_weight_kg(p)
 d=p.get_attribute(DICT,'diameter_mm',0).to_f
 t=p.get_attribute(DICT,'thickness_mm',0).to_f
 l=p.get_attribute(DICT,'actual_length_m',p.get_attribute(DICT,'length_m',0)).to_f
 raise "Geçersiz kazık kesiti/boyu: #{p.get_attribute(DICT,'pile_id','?')}" unless d>2*t && t>0 && l>0
 pile_weight(d,t,l)
end

# Explicit model repair, in one undoable operation. Read-only QTO uses the
# canonical formula too, so even a pre-existing stale cache cannot distort reports.
def mst_reconcile_pile_weights!(model=Sketchup.active_model, notify=true)
 ps=collect_piles(model.entities).map{|item|item[0]}.uniq
 changes=[]
 ps.each do |p|
  next unless p.valid?
  expected=mst_pile_canonical_weight_kg(p)
  old=p.get_attribute(DICT,'weight_kg',nil)
  changes<<[p,expected,old] if old.nil? || (old.to_f-expected).abs>0.01 || (p.get_attribute(DICT,'theoretical_weight_kg',nil).to_f-expected).abs>0.01
 end
 unless changes.empty?
  model.start_operation('MST Kazık Boru Ağırlıklarını Düzelt',true)
  begin
   changes.each do |p,expected,_old|
    p.set_attribute(DICT,'weight_kg',expected)
    p.set_attribute(DICT,'theoretical_weight_kg',expected)
    p.set_attribute(DICT,'qto_steel_pipe_weight_kg',expected)
   end
   commit_with_dependencies(model)
  rescue => ex
   model.abort_operation rescue nil
   raise ex
  end
 end
 UI.messagebox("Kazık ağırlık kontrolü tamamlandı.\nToplam: #{ps.length}\nDüzeltilen: #{changes.length}\nTeorik hesap: Ø / t / gerçek eksen boyu / yoğunluk.\nModeli kaydedin.") if notify
 changes.length
end

def pipe(ents,d,t,l)
 g=ents.add_group
 e=g.entities
 o=e.add_circle(ORIGIN,Z_AXIS,mm(d)/2.0,SEG)
 i=e.add_circle(ORIGIN,Z_AXIS,mm(d-2*t)/2.0,SEG)
 f=e.add_face(o)
 fi=e.add_face(i)
 fi.erase! if fi && fi.valid?
 # Always force the annular face normal upward.
 f.reverse! if f.normal.z < 0
 # Local z=0 is pile TOP; extrude downward.
 f.pushpull(-m(l))
 g
end

def pile_batter_ratio(value)
 s=value.to_s.strip
 return 0.0 if s.empty?
 if s.include?('/')
  a,b=s.split('/',2).map(&:to_f)
  return 0.0 if b.abs<1.0e-12
  return (a/b).abs
 end
 s.to_f.abs
end

def pile_orientation(data)
 mode=data['orientation_mode'].to_s.upcase
 r=(mode=='BATTERED' ? pile_batter_ratio(data['batter_ratio']) : 0.0)
 az=data['azimuth_deg'].to_f % 360.0
 den=Math.sqrt(1.0+r*r)
 vz=1.0/den
 h=r/den
 rad=az*Math::PI/180.0
 # Convention: 0°=+Y, 90°=+X, 180°=-Y, 270°=-X.
 down=Geom::Vector3d.new(h*Math.sin(rad),h*Math.cos(rad),-vz)
 [mode,r,az,down,vz]
end


# v0.34.13e - Shared 3D rotation helper. Local pile geometry is extruded along -Z.
def pile_rotation_transform(data)
 mode,r,az,down,vz=pile_orientation(data)
 return [Geom::Transformation.new,mode,r,az,down,vz] if r<=1.0e-12
 # Rotate local +Z to the opposite of the requested downward pile vector;
 # therefore the pipe's local -Z axis follows +down exactly.
 target_up=Geom::Vector3d.new(-down.x,-down.y,-down.z)
 axis=Z_AXIS.cross(target_up)
 angle=Z_AXIS.angle_between(target_up)
 rot=axis.length>1.0e-12 ? Geom::Transformation.rotation(ORIGIN,axis,angle) : Geom::Transformation.new
 [rot,mode,r,az,down,vz]
end


# v0.34.13e - Apply pile orientation ONLY to steel pipe piles selected in SketchUp.
def apply_selected_pile_orientations(data)
 model=Sketchup.active_model
 selected=model.selection.to_a.select do |e|
  (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
    e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'
 end
 raise 'SketchUp modelinde en az bir çelik boru kazık seçin.' if selected.empty?

 mode=data['orientation_mode'].to_s.upcase
 mode='VERTICAL' unless mode=='BATTERED'
 pd={'orientation_mode'=>mode,'batter_ratio'=>data['batter_ratio'],'azimuth_deg'=>data['azimuth_deg']}
 rot,mode,r,az,down,vz=pile_rotation_transform(pd)

 op=false   # v0.51.5 H4b: abort yalnız açık işlemde (seçim hatası önceki işlemi geri almaz)
 model.start_operation('Seçili Kazıklara Yönlendirme Uygula',true);op=true
 selected.each do |pile|
  # Preserve the pile-head point exactly where it is in its parent coordinate system.
  head=pile.transformation.origin
  pile.transformation=Geom::Transformation.translation(head) * rot
  l=pile.get_attribute(DICT,'length_m',0).to_f
  top=pile.get_attribute(DICT,'top_elevation_m',0).to_f
  x=pile.get_attribute(DICT,'axis_x_m',0).to_f
  y=pile.get_attribute(DICT,'axis_y_m',0).to_f
  pile.set_attribute(DICT,'orientation_mode',mode)
  pile.set_attribute(DICT,'batter_ratio',r)
  pile.set_attribute(DICT,'azimuth_deg',az)
  pile.set_attribute(DICT,'vertical_length_m',l*vz)
  pile.set_attribute(DICT,'bottom_elevation_m',top-l*vz)
  pile.set_attribute(DICT,'toe_x_m',x+l*down.x)
  pile.set_attribute(DICT,'toe_y_m',y+l*down.y)
  pile.set_attribute(DICT,'toe_z_m',top-l*vz)
 end
 bk=mst_pile_orientation_bk_openings!(selected,model)   # v0.51.5 H4b: bağlı BK açıklığı + net kalıp aynı işlemde
 commit_with_dependencies(model);op=false
 model.active_view.invalidate
 UI.messagebox("Kazık doğrultusu uygulandı; bağlı BK kalıp kazık boşluğu güncellenemedi:\n#{bk['warnings'].first(10).join("\n")}") unless bk['warnings'].empty?
 selected.length
rescue => e
 (model.abort_operation rescue nil) if op
 raise e
end

# v0.51.5 H4b: kazık yönelimi değişince bağlı BK'ların kayıtlı kazık açıklığı BK oluşturmadaki formülle
# (mst_pile_opening_m2 × mst_pile_opening_ratio; eğik kazıkta elips) yeniden yazılır ve net kalıp güncellenir (H3a).
# Çağıranın işlemi içinde çalışır (kendi start/commit/abort yok). Kayıtlı açıklığı olmayan BK'ya yazılmaz (düşüm başlatılmaz);
# bağlı kazık listesi modelle eşleşmeyen BK yazılmaz, uyarı döner. Metrajı değiştirir (kalıp).
def mst_pile_orientation_bk_openings!(piles,model=Sketchup.active_model)
 sel=piles.map(&:persistent_id)
 all=[];collect_elements(model.entities,all)
 out={'updated'=>[],'warnings'=>[]}
 all.select{|b|b.get_attribute(DICT,'element_type','').to_s=='head_beam'}.uniq.each do |b|
  next if b.get_attribute(DICT,'pile_opening_area_m2',nil).nil?
  cp=mst_bk_connected_piles(b)
  next unless cp.any?{|p|sel.include?(p.persistent_id)}
  pids=b.get_attribute(DICT,'connected_pile_persistent_ids','').to_s.split(/[,\s]+/).map(&:to_i).reject{|x|x<=0}.uniq
  exp=pids.empty? ? mst_pile_ids_for_beam(b).uniq.length : pids.length
  if cp.length!=exp
   out['warnings'] << "#{element_visible_id(b)}: bağlı kazık listesi (#{exp}) modeldeki kazıklarla (#{cp.length}) eşleşmiyor."
   next
  end
  open_new=cp.sum{|p|mst_pile_opening_m2(p.get_attribute(DICT,'diameter_mm',0).to_f,mst_pile_opening_ratio(p))}
  next if (open_new-b.get_attribute(DICT,'pile_opening_area_m2',0).to_f).abs<1e-9
  b.set_attribute(DICT,'pile_opening_area_m2',open_new)
  mst_bk_set_net_formwork!(b)
  out['updated'] << b
 end
 out
end

def add_pile(ents,data,x,y,id)
 gm=mst_pile_geometry(data)
 g=mst_prof(:pipe_geometry){pipe(ents,gm['d'],gm['t'],gm['l'])}
 # Local pipe is extruded along -Z. Rotate it to the requested 3D pile axis,
 # then place the pile head at the entered XYZ coordinate.
 g.transform!(gm['rot']) if gm['r']>1.0e-12
 g.transform!(Geom::Transformation.translation([m(x),m(y),m(gm['top'])]))
 mst_pile_core_attrs(data,x,y,id,gm).each{|k,v|g.set_attribute(DICT,k,v)}
 g.name=id;mst_prof(:finalize_identity){finalize_bim_identity(g,Sketchup.active_model)};g
end

# v0.38 C1: pile dimensions/orientation and the creation attribute set, shared by
# the Group and the Component creators (one source of truth, unchanged values).
def mst_pile_geometry(data)
 validate_pile_section!(data)
 d=data['diameter_mm'].to_f;t=data['thickness_mm'].to_f;l=data['length_m'].to_f
 top=data['top_elevation_m'].to_f
 rot,mode,r,az,down,vz=pile_rotation_transform(data)
 {'d'=>d,'t'=>t,'l'=>l,'top'=>top,'rot'=>rot,'mode'=>mode,'r'=>r,'az'=>az,'down'=>down,'vz'=>vz,'bottom'=>top-l*vz}
end

def mst_pile_core_attrs(data,x,y,id,gm)
 d=gm['d'];t=gm['t'];l=gm['l'];top=gm['top'];mode=gm['mode'];r=gm['r'];az=gm['az'];down=gm['down'];vz=gm['vz'];bottom=gm['bottom']
 {'element_type'=>'steel_pipe_pile','pile_id'=>id,'diameter_mm'=>d,'thickness_mm'=>t,
  'length_m'=>l,'actual_length_m'=>l,'vertical_length_m'=>l*vz,'top_elevation_m'=>top,'bottom_elevation_m'=>bottom,'orientation_mode'=>mode,'batter_ratio'=>r,'azimuth_deg'=>az,'toe_x_m'=>x.to_f+l*down.x,'toe_y_m'=>y.to_f+l*down.y,'toe_z_m'=>bottom,
  'steel_grade'=>data['steel_grade'].to_s,'project'=>data['project'].to_s,'ano'=>data['ano'].to_s,'zone'=>data['ano'].to_s,'axis_x_m'=>x.to_f,'axis_y_m'=>y.to_f,
  'weight_kg'=>pile_weight(d,t,l),
  'qto_zone'=>data['qto_zone'].to_s,
  'seabed_elevation_m'=>data['seabed_elevation_m'].to_s.strip.empty? ? nil : data['seabed_elevation_m'].to_f,
  'driving_length_m'=>(data['seabed_elevation_m'].to_s.strip.empty? ? data['driving_length_m'].to_f : [data['seabed_elevation_m'].to_f-bottom,0.0].max/vz),
  'splice_mode'=>data['splice_mode'].to_s=='MANUAL' ? 'MANUAL' : 'AUTO',
  'splice_count_per_pile'=>(data['splice_mode'].to_s=='MANUAL' ? [data['splice_count_per_pile'].to_i,0].max : [((l/12.0).ceil-1),0].max),
  'plug_enabled'=>data['plug_enabled'].to_s,'plug_count_per_pile'=>(data['plug_enabled'].to_s=='1' ? [data['plug_count_per_pile'].to_i,1].max : 0),
  'plug_thickness_mm'=>data['plug_thickness_mm'].to_f,'plug_clearance_mm'=>data['plug_clearance_mm'].to_f,
  'upper_ring_enabled'=>data['upper_ring_enabled'].to_s,'upper_ring_count_per_pile'=>[data['upper_ring_count_per_pile'].to_i,1].max,
  'upper_ring_width_mm'=>(data['upper_ring_width_mm'].to_s.empty? ? 250.0 : data['upper_ring_width_mm'].to_f),'upper_ring_thickness_mm'=>t,
  'lower_ring_enabled'=>data['lower_ring_enabled'].to_s,'lower_ring_count_per_pile'=>[data['lower_ring_count_per_pile'].to_i,1].max,
  'lower_ring_width_mm'=>(data['lower_ring_width_mm'].to_s.empty? ? 300.0 : data['lower_ring_width_mm'].to_f),'lower_ring_thickness_mm'=>t,
  'pe_enabled'=>data['pe_enabled'].to_s,'pe_length_m'=>data['pe_length_m'].to_f,
  'drilling_enabled'=>data['drilling_enabled'].to_s,'drilling_length_m'=>data['drilling_length_m'].to_f}.merge(mst_pile_rebar_create_attrs(data))
end

# v0.38 PR1.1: rebar cage requested in the pile form is part of the new pile.
def mst_pile_rebar_create_attrs(data)
 return {} unless data['pile_rebar_on_create'].to_s=='1' && data['infill_enabled'].to_s=='1'
 p=mst_pile_rebar_params(JSON.parse(data['pile_rebar_create_json'].to_s)) rescue (raise "Kazık içi donatı: #{$!.message}")
 {'pile_rebar_mode'=>'bim_detail','pile_rebar_json'=>mst_pile_rebar_json(p)}
end

# v0.38 C1: infill numbers (same checks and messages as before), shared by Group and Component piles.
def mst_pile_infill_plan(pd,zone)
 d=pd['diameter_mm'].to_f;t=pd['thickness_mm'].to_f;di=d-2*t
 raise 'Kazık iç çapı geçersiz.' if di<=0
 top=pd['top_elevation_m'].to_f
 bottom=pd['infill_bottom_normal_m'].to_f
 bottom=pd['infill_bottom_start_m'].to_f if zone=='START_LOW' && pd['infill_start_override'].to_s=='1'
 bottom=pd['infill_bottom_end_m'].to_f if zone=='END_LOW' && pd['infill_end_override'].to_s=='1'
 _,_,_,_,vz=pile_orientation(pd)
 pile_bottom=top-pd['length_m'].to_f*vz
 raise "İç beton alt kotu #{bottom} m, kazık üst kotundan düşük olmalı." if bottom>=top
 raise "İç beton alt kotu #{bottom} m, kazık alt kotu #{pile_bottom} m'nin altında." if bottom<pile_bottom-0.0001
 h_vertical=top-bottom
 h=h_vertical/vz
 {'di'=>di,'top'=>top,'bottom'=>bottom,'h'=>h,'vol'=>Math::PI/4.0*(di/1000.0)**2*h,
  'class'=>(pd['infill_concrete_class'].to_s.strip.empty? ? 'C40/50' : pd['infill_concrete_class'].to_s)}
end

def add_pile_infill(pile,pd,zone,sync_types=true)
 mst_require_group_pile!(pile,'İç beton oluşturma')
 return unless pd['infill_enabled'].to_s=='1'
 ip=mst_pile_infill_plan(pd,zone)
 di=ip['di'];top=ip['top'];bottom=ip['bottom'];h=ip['h']
 g=pile.entities.add_group;g.name="Pile Infill Concrete"
 c=g.entities.add_circle(ORIGIN,Z_AXIS,mm(di)/2.0,SEG);f=g.entities.add_face(c);f.reverse! if f.normal.z<0;f.pushpull(-m(h))
 vol=ip['vol']
 {'element_type'=>'pile_infill_concrete','pile_id'=>pile.get_attribute(DICT,'pile_id',''),'concrete_class'=>ip['class'],
 'internal_diameter_mm'=>di,'top_elevation_m'=>top,'bottom_elevation_m'=>bottom,'height_m'=>h,'concrete_volume_m3'=>vol,'elevation_zone'=>zone}.each{|k,v|g.set_attribute(DICT,k,v)}
 pile.set_attribute(DICT,'infill_concrete_volume_m3',vol);pile.set_attribute(DICT,'infill_bottom_elevation_m',bottom)
 pile.set_attribute(DICT,'infill_enabled','1')
 pile.set_attribute(DICT,'infill_concrete_class',g.get_attribute(DICT,'concrete_class',''))
 %w[project system structure ano zone].each do |key|
  value=pile.get_attribute(DICT,key,'')
  g.set_attribute(DICT,key,value) unless value.to_s.strip.empty?
 end
 finalize_bim_identity(g,Sketchup.active_model)
 mst_pile_rebar_refresh!(pile)   # v0.38 PR1: cage follows every (re)built infill
 mst_prof(:type_sync){mst_request_pile_type_sync(Sketchup.active_model)} if sync_types
 g
end

# ===========================================================================
# v0.38 C1 — Definition Registry (generic; piles now, BK / döşeme / prekast later).
# A definition is identified by (kind, canonical parameter key). Same key =>
# same shared geometry. Everything that differs per element (IDs, UID, axis,
# global position, elevations used only for reporting, QTO cache) lives on the
# INSTANCE. A definition is never edited in place by element edits: a changed
# element gets the definition for its new key (C3), so sharing stays safe.
# ===========================================================================
MST_DEF_SCHEMA=1
def mst_def_value(v)
 case v
 when Float then (v.round(6)==v.round(6).to_i ? v.round(6).to_i.to_s : format('%.6f',v.round(6)).sub(/0+\z/,''))
 when Integer then v.to_s
 when nil then ''
 else v.to_s
 end
end

def mst_def_key(kind,params)
 "#{kind}|s#{MST_DEF_SCHEMA}|"+params.keys.map(&:to_s).sort.map{|k|v=params.key?(k) ? params[k] : params[k.to_sym];"#{k}=#{mst_def_value(v)}"}.join('|')
end

def mst_def_find(model,kind,key)
 if @mst_scan_batch_on && @mst_def_cache && (hit=@mst_def_cache[key]) && hit.valid?
  return hit
 end
 model.definitions.each do |d|
  next if d.image? || d.group?
  next unless d.get_attribute(DICT,'mst_def_kind','').to_s==kind.to_s && d.get_attribute(DICT,'mst_def_key','').to_s==key
  (@mst_def_cache||={})[key]=d if @mst_scan_batch_on
  return d
 end
 nil
end

def mst_def_register!(defn,kind,key,params,label)
 require 'zlib'
 defn.name="MST #{label} ##{format('%08x',Zlib.crc32(key))}"
 defn.set_attribute(DICT,'mst_def_kind',kind.to_s)
 defn.set_attribute(DICT,'mst_def_key',key)
 defn.set_attribute(DICT,'mst_def_schema',MST_DEF_SCHEMA)
 defn.set_attribute(DICT,'mst_def_params_json',JSON.generate(params))
 (@mst_def_cache||={})[key]=defn if @mst_scan_batch_on
 defn
end

# Returns [definition, created?]. The block builds and returns a new ComponentDefinition.
def mst_def_find_or_create(model,kind,params,label)
 key=mst_def_key(kind,params)
 d=mst_def_find(model,kind,key)
 return [d,false] if d
 [mst_def_register!(yield,kind,key,params,label),true]
end

def mst_scan_cache_remove(e)
 return unless @mst_scan_cache && e
 @mst_scan_cache.delete(e)
 @mst_scan_cache_ids.delete(e.persistent_id) if e.valid? && @mst_scan_cache_ids
end

# --- Piles ------------------------------------------------------------------
MST_PILE_DEF_KEYS=%w[diameter_mm thickness_mm length_m top_elevation_m
 upper_ring_enabled upper_ring_count_per_pile upper_ring_width_mm upper_ring_thickness_mm
 lower_ring_enabled lower_ring_count_per_pile lower_ring_width_mm lower_ring_thickness_mm
 plug_enabled plug_count_per_pile plug_thickness_mm plug_clearance_mm].freeze

# Everything the pile body geometry (and its shared infill child) depends on.
def mst_pile_def_params(core,infill_plan,colors)
 h={}
 MST_PILE_DEF_KEYS.each{|k|h[k]=core[k]}
 h['infill']=infill_plan ? '1' : '0'
 if infill_plan
  h['infill_di_mm']=infill_plan['di'];h['infill_h_m']=infill_plan['h']
  h['infill_bottom_m']=infill_plan['bottom'];h['infill_class']=infill_plan['class']
 end
 VIS_DEFAULTS.keys.each{|k|h["color_#{k}"]=colors[k]}
 h['seg']=SEG
 # v0.38 PR1: only piles WITH a cage get the extra key (existing definitions keep their keys)
 h['rebar']='bars-v3:'+core['pile_rebar_json'].to_s if core['pile_rebar_mode'].to_s=='bim_detail' && !core['pile_rebar_json'].to_s.empty?
 h
end

# Instance-only keys removed from the shared infill child (they live on each pile instance).
MST_SHARED_CHILD_STRIP=%w[pile_id project system structure ano zone].freeze

# Builds the definition with the SAME code the Group path uses (pipe, infill, rings,
# plugs, materials), at the identity transform, then turns it into a definition.
def mst_build_pile_definition(model,data,zone,core)
 g=pipe(model.entities,core['diameter_mm'],core['thickness_mm'],core['length_m'])
 core.each{|k,v|g.set_attribute(DICT,k,v)}
 g.set_attribute(DICT,'element_type','mst_pile_template')   # never a BIM element itself
 g.delete_attribute(DICT,'pile_id')
 inf=add_pile_infill(g,data,zone,false)
 mst_visual_refresh_pile(g,{})
 if inf
  mst_scan_cache_remove(inf)
  MST_SHARED_CHILD_STRIP.each{|k|inf.delete_attribute(DICT,k)}
  inf.set_attribute(DICT,'shared_definition_child','1')
 end
 inst=g.to_component
 defn=inst.definition
 inst.erase!
 defn
end

def mst_pile_body_mode(data)
 data['pile_body_mode'].to_s.upcase=='COMPONENT' ? 'COMPONENT' : 'GROUP'
end

# Component twin of add_pile: same attribute set on the instance, same placement transform.
def mst_add_pile_component(ents,data,x,y,id,zone)
 model=Sketchup.active_model
 gm=mst_pile_geometry(data)
 core=mst_pile_core_attrs(data,x,y,id,gm)
 ip=data['infill_enabled'].to_s=='1' ? mst_pile_infill_plan(data,zone) : nil
 colors={};VIS_DEFAULTS.each{|k,v|colors[k]=v}
 params=mst_pile_def_params(core,ip,colors)
 label=format('Kazık Ø%s×%s L%s',mst_def_value(gm['d']),mst_def_value(gm['t']),mst_def_value(gm['l']))
 defn,_created=mst_prof(:definition){mst_def_find_or_create(model,'steel_pipe_pile',params,label){mst_build_pile_definition(model,data,zone,core)}}
 tr=Geom::Transformation.translation([m(x),m(y),m(gm['top'])])
 tr=tr*gm['rot'] if gm['r']>1.0e-12
 inst=ents.add_instance(defn,tr)
 core.each{|k,v|inst.set_attribute(DICT,k,v)}
 inst.name=id;mst_prof(:finalize_identity){finalize_bim_identity(inst,model)}
 [inst,ip,colors]
end

# Pile-level results that the Group path writes in add_pile_infill / mst_visual_refresh_pile.
def mst_pile_component_finish!(inst,ip,colors)
 if ip
  inst.set_attribute(DICT,'infill_concrete_volume_m3',ip['vol'])
  inst.set_attribute(DICT,'infill_bottom_elevation_m',ip['bottom'])
  inst.set_attribute(DICT,'infill_enabled','1')
  inst.set_attribute(DICT,'infill_concrete_class',ip['class'])
  mst_prof(:type_sync){mst_request_pile_type_sync(Sketchup.active_model)}
 end
 VIS_DEFAULTS.keys.each{|k|inst.set_attribute(DICT,"visual_color_#{k}",colors[k])}
 inst.set_attribute(DICT,'mst_visual_initialized','1')
 sync_pile_bim_qto(inst)
 inst
end

# ===========================================================================
# v0.38 C3 — Component write layer for piles. A shared definition is NEVER
# edited. The instance's attributes are updated exactly as for a Group pile;
# then the instance is pointed at the definition that matches its new values
# (found, or built once with the Group drawing code). Other piles that shared
# the old definition are untouched.
# ===========================================================================
def mst_pile_body_data_from(p)
 g=->(k,d=nil){p.get_attribute(DICT,k,d)}
 data={}
 %w[diameter_mm thickness_mm length_m top_elevation_m steel_grade orientation_mode batter_ratio azimuth_deg].each{|k|data[k]=g.call(k)}
 data['infill_enabled']=g.call('infill_enabled','0').to_s=='1' ? '1' : '0'
 data['infill_bottom_normal_m']=g.call('infill_bottom_elevation_m')
 data['infill_concrete_class']=g.call('infill_concrete_class','C40/50')
 if data['infill_enabled']=='1' && data['infill_bottom_normal_m'].nil?
  raise "#{g.call('pile_id','?')}: iç beton alt kotu kayıtlı değil."
 end
 data
end

def mst_pile_body_attrs_from(p)
 h={}
 (MST_PILE_DEF_KEYS+%w[steel_grade]).each{|k|h[k]=p.get_attribute(DICT,k,nil)}
 VIS_DEFAULTS.each{|k,dv|h["visual_color_#{k}"]=p.get_attribute(DICT,"visual_color_#{k}",dv)}
 %w[pile_rebar_mode pile_rebar_json].each{|k|v=p.get_attribute(DICT,k,nil);h[k]=v unless v.nil?}   # v0.38 PR1
 h
end

# Returns [definition, infill_plan_or_nil].
def mst_pile_definition_for_instance(p,model=Sketchup.active_model)
 data=mst_pile_body_data_from(p)
 body=mst_pile_body_attrs_from(p)
 ip=data['infill_enabled']=='1' ? mst_pile_infill_plan(data,'NORMAL') : nil
 colors={};VIS_DEFAULTS.each_key{|k|colors[k]=body["visual_color_#{k}"]}
 params=mst_pile_def_params(body,ip,colors)
 label=format('Kazık Ø%s×%s L%s',mst_def_value(body['diameter_mm'].to_f),mst_def_value(body['thickness_mm'].to_f),mst_def_value(body['length_m'].to_f))
 defn,_=mst_prof(:definition){mst_def_find_or_create(model,'steel_pipe_pile',params,label){mst_build_pile_definition(model,data,'NORMAL',body)}}
 raise 'Kazık tanımı oluşturulamadı.' unless defn && defn.valid?
 [defn,ip]
end

# Component counterpart of the visual/detail refresh: swap to the matching definition.
def mst_pile_component_refresh!(p)
 model=Sketchup.active_model
 tr=p.transformation.to_a.dup;uid=p.get_attribute(DICT,'element_uid',nil)
 defn,ip=mst_pile_definition_for_instance(p,model)
 p.definition=defn unless p.definition==defn
 p.set_attribute(DICT,'infill_concrete_volume_m3',ip['vol']) if ip
 p.set_attribute(DICT,'mst_visual_initialized','1')
 sync_pile_bim_qto(p)
 raise 'Kazık konumu/eğimi güncelleme sırasında değişti.' unless p.transformation.to_a.each_with_index.all?{|v,i|(v-tr[i]).abs<1.0e-8}
 raise 'Kazık UID güncelleme sırasında değişti.' unless p.get_attribute(DICT,'element_uid',nil)==uid
 true
end

# Component counterpart of mst_rebuild_pile_section_dependencies (same attribute writes).
def mst_rebuild_pile_component!(p,d,t,grade)
 raise 'Geçersiz kazık kesiti.' unless d>0 && t>0 && d>2*t
 len=p.get_attribute(DICT,'length_m',0).to_f
 raise 'Kazık boyu geçersiz.' unless len>0
 p.set_attribute(DICT,'diameter_mm',d)
 p.set_attribute(DICT,'thickness_mm',t)
 p.set_attribute(DICT,'steel_grade',grade)
 axis_len=p.get_attribute(DICT,'actual_length_m',len).to_f
 axis_len=len unless axis_len>0
 wt=pile_weight(d,t,axis_len)
 %w[weight_kg theoretical_weight_kg qto_steel_pipe_weight_kg].each{|key|p.set_attribute(DICT,key,wt)}
 p.set_attribute(DICT,'type_signature',"steel_pipe_pile|#{d.round(1)}|#{t.round(1)}|#{grade}")
 mst_enforce_ring_rule!(p,t)
 mst_pile_component_refresh!(p)
end

# ===========================================================================
# v0.38 C4 — Convert existing Group piles to Component piles (preview + one Undo).
# Every BIM attribute is copied unchanged; the definition is built from those
# attributes with the same drawing code. A pile is skipped (left as Group) if
# its stored data and its drawn infill disagree, so QTO cannot change.
# ===========================================================================
def mst_pile_convert_check(g)
 id=g.get_attribute(DICT,'pile_id','?').to_s
 return "#{id}: zaten Component" if mst_component_pile?(g)
 return "#{id}: Group değil" unless g.is_a?(Sketchup::Group)
 data=mst_pile_body_data_from(g)
 ip=data['infill_enabled']=='1' ? mst_pile_infill_plan(data,'NORMAL') : nil
 infs=mst_bim_children(g,'pile_infill_concrete')
 return "#{id}: birden fazla iç beton grubu var" if infs.length>1
 inf=infs.first
 return "#{id}: iç beton VAR kayıtlı ama beton grubu yok" if ip && !inf
 return "#{id}: beton grubu var ama iç beton YOK kayıtlı" if inf && !ip
 if inf && ip
  v=inf.get_attribute(DICT,'concrete_volume_m3',0).to_f
  return format('%s: çizili beton hacmi %.4f m³, kayıtlı değerlerden hesap %.4f m³ (farklı)',id,v,ip['vol']) if (v-ip['vol']).abs>1.0e-9*[1.0,v.abs].max
  c=inf.get_attribute(DICT,'concrete_class','').to_s
  return "#{id}: beton sınıfı farklı (çizili #{c}, kayıtlı #{ip['class']})" if !c.empty? && c!=ip['class']
 end
 nil
rescue => e
 "#{g.get_attribute(DICT,'pile_id','?')}: #{e.message}"
end

def mst_pile_convert_plan(piles)
 ok=[];skip=[]
 piles.each{|g| (r=mst_pile_convert_check(g)) ? skip << r : ok << g}
 [ok,skip]
end

def mst_pile_convert_to_component!(g,model=Sketchup.active_model)
 defn,_ip=mst_pile_definition_for_instance(g,model)
 ents=g.parent.entities
 inst=ents.add_instance(defn,g.transformation)
 (g.attribute_dictionaries || []).each do |dict|
  dict.each_pair{|k,v|inst.set_attribute(dict.name,k,v)}
 end
 inst.name=g.name
 inst.layer=g.layer if g.layer
 inst.material=g.material if g.material
 g.erase!
 mst_scan_cache_add(inst)
 inst
end

def mst_pile_convert_targets(data)
 model=Sketchup.active_model
 targets=mst_resolve_pile_targets(data)
 ok,skip=mst_pile_convert_plan(targets)
 already=skip.count{|t|t.end_with?('zaten Component')}
 real_skip=skip.reject{|t|t.end_with?('zaten Component')}
 if ok.empty?
  UI.messagebox("Kazık Gövdesi → Component\n\nÇevrilecek kazık yok.#{already>0 ? "\n#{already} kazık zaten Component." : ''}#{real_skip.empty? ? '' : "\n\nAtlanan:\n"+real_skip.first(15).join("\n")}")
  return nil
 end
 keys=ok.map{|g|d=mst_pile_body_data_from(g);ip=d['infill_enabled']=='1' ? mst_pile_infill_plan(d,'NORMAL') : nil
   b=mst_pile_body_attrs_from(g);c={};VIS_DEFAULTS.each_key{|k|c[k]=b["visual_color_#{k}"]};mst_def_key('steel_pipe_pile',mst_pile_def_params(b,ip,c))}
 uniq=keys.uniq;existing=uniq.count{|k|mst_def_find(model,'steel_pipe_pile',k)}
 msg="Kazık Gövdesi → Component\n\n#{ok.length} Group kazık Component'e çevrilecek: #{mst_ring_ids(ok)}\n"+
     "Paylaşılan tanım: #{uniq.length} (#{existing} mevcut, #{uniq.length-existing} yeni)\n"+
     "Kazık ID, UID, aks, kot, metraj ve tüm BIM bilgileri aynen korunur; konum değişmez.\n"
 msg+="#{already} kazık zaten Component.\n" if already>0
 msg+="\nAtlanan (Group kalır):\n#{real_skip.first(12).join("\n")}#{real_skip.length>12 ? "\n…" : ''}\n" unless real_skip.empty?
 msg+="\nTek Geri Al ile geri alınabilir. Devam edilsin mi?"
 return nil unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation("MST Kazık Gövdesi → Component (#{ok.length} kazık)",true)
 out=[]
 begin
  mst_scan_batch(model) do
   ok.each{|g|out << mst_pile_convert_to_component!(g,model)}
   mst_sync_pile_type_library(model)
  end
  commit_with_dependencies(model);model.active_view.invalidate
 rescue Exception => e
  model.abort_operation
  UI.messagebox("Kazık Gövdesi → Component geri alındı: #{e.message}")
  return nil
 end
 out
end

# ===========================================================================
# v0.38 C5 — Component → Group (escape hatch). The Group pile is rebuilt with
# the ORIGINAL Group creation code (pipe, infill, rings, plugs, colours) from the
# pile's own attributes; every BIM attribute is copied unchanged. The infill
# child gets its own fresh identity (as at Group creation).
# ===========================================================================
def mst_pile_revert_check(c)
 id=c.get_attribute(DICT,'pile_id','?').to_s
 return "#{id}: zaten Group" unless mst_component_pile?(c)
 data=mst_pile_body_data_from(c)
 mst_pile_geometry(data)
 mst_pile_infill_plan(data,'NORMAL') if data['infill_enabled']=='1'
 nil
rescue => e
 "#{c.get_attribute(DICT,'pile_id','?')}: #{e.message}"
end

def mst_pile_convert_to_group!(c,model=Sketchup.active_model)
 data=mst_pile_body_data_from(c)
 shared=mst_bim_children(c,'pile_infill_concrete').first
 shared_tid=shared ? shared.get_attribute(DICT,'type_id','').to_s : ''
 shared_sig=shared ? shared.get_attribute(DICT,'type_signature','').to_s : ''
 ents=c.parent.entities
 g=pipe(ents,data['diameter_mm'].to_f,data['thickness_mm'].to_f,data['length_m'].to_f)
 g.transformation=c.transformation
 (c.attribute_dictionaries || []).each do |dict|
  dict.each_pair{|k,v|g.set_attribute(dict.name,k,v)}
 end
 g.name=c.name
 g.layer=c.layer if c.layer
 g.material=c.material if c.material
 c.erase!
 mst_scan_cache_add(g)
 zone=g.get_attribute(DICT,'elevation_zone','NORMAL').to_s
 zone='NORMAL' unless %w[NORMAL START_LOW END_LOW].include?(zone)
 inf=(data['infill_enabled']=='1' ? add_pile_infill(g,data,zone,false) : nil)   # recorded bottom is used for every zone
 # Keep the infill's library Type ID it had before (stored on the shared child).
 if inf && !shared_tid.empty? && inf.get_attribute(DICT,'type_signature','').to_s==shared_sig
  inf.set_attribute(DICT,'type_id',shared_tid);inf.set_attribute(DICT,'library_type_id',shared_tid)
 end
 mst_visual_refresh_pile(g,{})
 sync_pile_bim_qto(g)
 g
end

def mst_pile_revert_targets(data)
 model=Sketchup.active_model
 targets=mst_resolve_pile_targets(data)
 ok=[];skip=[]
 targets.each{|c|(r=mst_pile_revert_check(c)) ? skip << r : ok << c}
 already=skip.count{|t|t.end_with?('zaten Group')}
 real_skip=skip.reject{|t|t.end_with?('zaten Group')}
 if ok.empty?
  UI.messagebox("Kazık Gövdesi → Group\n\nÇevrilecek Component kazık yok.#{already>0 ? "\n#{already} kazık zaten Group." : ''}#{real_skip.empty? ? '' : "\n\nAtlanan:\n"+real_skip.first(15).join("\n")}")
  return nil
 end
 msg="Kazık Gövdesi → Group\n\n#{ok.length} Component kazık Group'a çevrilecek: #{mst_ring_ids(ok)}\n"+
     "Her kazık kendi geometrisini taşıyan ayrı bir Group olur (dosya büyür). Kazık ID, UID, aks, kot ve metraj aynen korunur; konum değişmez.\n"
 msg+="#{already} kazık zaten Group.\n" if already>0
 msg+="\nAtlanan:\n#{real_skip.first(12).join("\n")}\n" unless real_skip.empty?
 msg+="\nTek Geri Al ile geri alınabilir. Devam edilsin mi?"
 return nil unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation("MST Kazık Gövdesi → Group (#{ok.length} kazık)",true)
 out=[]
 begin
  mst_scan_batch(model) do
   ok.each{|c|out << mst_pile_convert_to_group!(c,model)}
   mst_sync_pile_type_library(model)
  end
  commit_with_dependencies(model);model.active_view.invalidate
 rescue Exception => e
  model.abort_operation
  UI.messagebox("Kazık Gövdesi → Group geri alındı: #{e.message}")
  return nil
 end
 out
end

# ===========================================================================
# v0.38 C7 — Remove MST pile definitions no pile uses any more (after edits,
# a pile moves to another definition; the old one stays until purged).
# Only definitions created by MST (mst_def_kind) are touched; one Undo.
# ===========================================================================
def mst_unused_pile_definitions(model=Sketchup.active_model)
 model.definitions.to_a.select{|d|d.valid? && !d.image? && !d.group? && d.get_attribute(DICT,'mst_def_kind','').to_s=='steel_pipe_pile' && d.instances.empty?}
end

def mst_remove_definitions!(model,defs)
 removed=0
 defs.each do |d|
  next unless d.valid? && d.instances.empty?
  kids=d.entities.grep(Sketchup::Group).map(&:definition).uniq
  model.definitions.remove(d);removed+=1
  kids.each{|k|model.definitions.remove(k) if k.valid? && k.instances.empty?}
 end
 @mst_def_cache=nil
 removed
end

def mst_purge_unused_pile_definitions
 model=Sketchup.active_model
 defs=mst_unused_pile_definitions(model)
 used=model.definitions.to_a.count{|d|d.valid? && !d.group? && d.get_attribute(DICT,'mst_def_kind','').to_s=='steel_pipe_pile' && !d.instances.empty?}
 if defs.empty?
  UI.messagebox("Kullanılmayan kazık tanımı yok.\nKullanımdaki kazık tanımı: #{used}")
  return 0
 end
 names=defs.map(&:name)
 msg="Kullanılmayan kazık tanımları temizlenecek: #{defs.length}\n#{names.first(12).join("\n")}#{names.length>12 ? "\n…" : ''}\n\n"+
     "Kullanımdaki #{used} tanım ve hiçbir kazık değişmez. Tek Geri Al ile geri alınabilir. Devam edilsin mi?"
 return 0 unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation('MST Kullanılmayan Kazık Tanımlarını Temizle',true)
 begin
  n=mst_remove_definitions!(model,defs)
  model.commit_operation
 rescue Exception => e
  model.abort_operation
  UI.messagebox("Temizleme geri alındı: #{e.message}")
  return 0
 end
 UI.messagebox("#{n} kullanılmayan kazık tanımı temizlendi.")
 n
end

def generate_layout(data)
 model=Sketchup.active_model;model.start_operation('Kazık Yerleşimi Oluştur',true)
 begin
  normalize_pile_inputs!(data)
  mst_kz_save_form!(data,model) if respond_to?(:mst_kz_save_form!)   # v0.50: A-çerçeve / DXF kazıkları bu formu kullanır
  # Multi-ANO v0.34.7: geometry is authored in ANO-local coordinates and the
  # whole layout is translated to the active ANO origin. Existing models default to ANO-01 / X=0.
  ano_ctx=mst_active_ano_context(model)
  data['project']=model.get_attribute(DICT,'project_name','').to_s
  pile_system=data['placement_system'].to_s.strip.upcase
  pile_structure=data['placement_structure'].to_s.strip
  use_structure=!pile_system.empty? && !pile_structure.empty?
  if use_structure
    raise 'Geçersiz kazık sistemi.' unless %w[DOLFEN ISKELE RIHTIM].include?(pile_system)
    raise "#{pile_structure} yapısı #{pile_system} sisteminde bulunamadı." unless mst_structures_for_system(pile_system,model).include?(pile_structure)
    structure_origin=mst_structure_origin(pile_system,pile_structure,model)
    data['ano']=pile_structure
    data['structure_zone']=pile_structure if data['structure_zone'].to_s.strip.empty?
  else
    structure_origin=[ano_ctx['origin_x_m'].to_f,0.0]
    data['ano']=ano_ctx['name'].to_s
  end
  nx=[data['count_x'].to_i,1].max;ny=[data['count_y'].to_i,1].max
  sx=data['spacing_x_m'].to_f;sy=data['spacing_y_m'].to_f
  pref=data['prefix'].to_s.strip;pref='P-' if pref.empty?;n=[data['start_no'].to_i,1].max
  normal_top=data['top_elevation_m'].to_f
  base_len=data['length_m'].to_f
  base_bottom=normal_top-base_len
  lock_mode=data['pile_elevation_lock'].to_s
  lock_mode='LENGTH' unless ['LENGTH','BOTTOM'].include?(lock_mode)
  sc=[data['start_low_count'].to_i,0].max;ec=[data['end_low_count'].to_i,0].max
  st=data['start_low_top_m'].to_f;et=data['end_low_top_m'].to_f
  custom=data['layout_mode'].to_s=='CUSTOM'
  axes=[]
  if custom
   raw=JSON.parse(data['custom_axis_json'].to_s)
   raise 'Özel aks yerleşiminde en az bir aks tanımlanmalıdır.' unless raw.is_a?(Array) && !raw.empty?
   raw.each_with_index do |a,i|
    pts=(a['points']||[]).select{|pt|pt['selected']!=false && pt['selected'].to_s!='0'}
    next if pts.empty?
    raise "#{a['name'].to_s.strip.empty? ? "X aksı #{i+1}" : a['name']}: başlangıç + son düşük kotlu kazık adedi, seçili kazık sayısını geçemez." if sc+ec>pts.length
    axes << {'name'=>a['name'].to_s.strip,'x'=>a['x'].to_f,'points'=>pts,'count'=>pts.length}
   end
   axes.reject!{|a|a['count'].to_i<=0}
   raise 'Özel yerleşimde en az bir grid noktası seçilmelidir.' if axes.empty?
  else
   raise 'Başlangıç + son düşük kotlu kazık adedi, Y kazık adedini geçemez.' if sc+ec>ny
   nx.times{|i|axes << {'name'=>"#{data['axis_prefix']}#{i+1}",'x'=>i*sx,'gaps'=>Array.new([ny-1,0].max,sy),'count'=>ny}}
  end
  total_piles=axes.sum{|a|a['count']}
  layout=model.active_entities.add_group
  layout.name=custom ? "Pile Layout #{total_piles} Piles" : "Pile Layout #{nx}x#{ny}"
  {'element_type'=>'pile_layout','layout_mode'=>(custom ? 'CUSTOM':'STANDARD'),'normal_pile_top_elevation_m'=>normal_top,
   'start_low_count'=>sc,'start_low_top_m'=>st,'end_low_count'=>ec,'end_low_top_m'=>et,
   'pile_elevation_lock'=>lock_mode,'axis_count'=>axes.length,'piles_per_axis'=>(custom ? 'VARIABLE':ny),
   'total_pile_count'=>total_piles,'custom_axis_json'=>(custom ? data['custom_axis_json'].to_s : ''),'structure_zone'=>data['structure_zone'].to_s,'pile_group'=>data['pile_group'].to_s,
   'axis_prefix'=>data['axis_prefix'].to_s,'project'=>data['project'].to_s,'ano'=>data['ano'].to_s,'zone'=>data['ano'].to_s,
   'system'=>pile_system,'structure'=>pile_structure,'placement_engine'=>(use_structure ? 'SYSTEM_STRUCTURE_GRID' : 'LEGACY_ANO'),
   'global_origin_x_m'=>structure_origin[0].to_f,'global_origin_y_m'=>structure_origin[1].to_f,
   'ano_origin_x_m'=>ano_ctx['origin_x_m'].to_f,'ano_length_m'=>ano_ctx['length_m'].to_f,'ano_gap_before_m'=>ano_ctx['gap_before_m'].to_f}.each{|k,v|layout.set_attribute(DICT,k,v)}

  used_pile_ids={}
  # v0.38 PR1.1: Pile IDs are unique in the whole model; a grid point keeps one pile.
  existing_ids={};existing_pts={}
  collect_piles(model.entities).each do |pp,_|
   existing_ids[pp.get_attribute(DICT,'pile_id','').to_s]=true
   ps_=pp.get_attribute(DICT,'structure','').to_s;ps_=pp.get_attribute(DICT,'ano','').to_s if ps_.empty?
   existing_pts[[ps_,pp.get_attribute(DICT,'grid_x_axis','').to_s,pp.get_attribute(DICT,'grid_y_axis','').to_s]]=pp.get_attribute(DICT,'pile_id','').to_s
  end
  mst_pile_rebar_create_attrs(data)   # validate before anything is drawn
  body_mode=mst_pile_body_mode(data)   # v0.38 C2: GROUP (default) | COMPONENT
  layout.set_attribute(DICT,'pile_body_mode',body_mode)
  mst_scan_batch(model) do   # v0.38 R9: one model scan for the whole layout
  axes.each_with_index do |ax,i|
   placements = if ax['points'].is_a?(Array) && !ax['points'].empty?
    ax['points'].map{|pt|{'y'=>pt['y'].to_f+pt['dy'].to_f,'x'=>ax['x'].to_f+pt['dx'].to_f,'y_axis'=>pt['name'].to_s,'dx'=>pt['dx'].to_f,'dy'=>pt['dy'].to_f,'orientation_mode'=>pt['orientation_mode'],'batter_ratio'=>pt['batter_ratio'],'azimuth_deg'=>pt['azimuth_deg'],'pile_id'=>pt['pile_id'].to_s,'pile_group'=>pt['pile_group'].to_s,'elevation_mode'=>pt['elevation_mode'].to_s,'elevation_reason'=>pt['elevation_reason'].to_s,'linked_element_id'=>pt['linked_element_id'].to_s,'diameter_mm'=>pt['diameter_mm'],'thickness_mm'=>pt['thickness_mm'],'length_m'=>pt['length_m'],'top_elevation_m'=>pt['top_elevation_m'],'steel_grade'=>pt['steel_grade'].to_s}}
   else
    yp=[0.0];(ax['gaps']||[]).each{|g|yp << yp[-1]+g};yp.map{|yy|{'y'=>yy,'x'=>ax['x'].to_f,'y_axis'=>'','dx'=>0.0,'dy'=>0.0}}
   end
   placements.each_with_index do |pl,j|
    y=pl['y']; x=pl['x']
    pd=data.dup;top=normal_top;zone='NORMAL'
    # Custom grid points may override the global orientation independently.
    unless pl['orientation_mode'].to_s.empty?
     pd['orientation_mode']=pl['orientation_mode'].to_s
     pd['batter_ratio']=pl['batter_ratio']
     pd['azimuth_deg']=pl['azimuth_deg'].to_f
    end
    # v0.35.3: per-pile BIM overrides inherited from the Axis-integrated Pile Manager. Blank means inherit the general pile value.
    %w[diameter_mm thickness_mm length_m top_elevation_m steel_grade].each do |key|
     val=pl[key]
     pd[key]=val unless val.nil? || val.to_s.strip.empty?
    end
    if j < sc;top=st;zone='START_LOW'
    elsif j >= ax['count']-ec;top=et;zone='END_LOW';end
    if pl['elevation_mode'].to_s=='SPECIAL' && !pl['top_elevation_m'].nil? && !pl['top_elevation_m'].to_s.strip.empty?
     top=pl['top_elevation_m'].to_f
    end
    pd['top_elevation_m']=top
    unless pl['length_m'] && !pl['length_m'].to_s.strip.empty?
     pd['length_m']=(lock_mode=='BOTTOM' ? top-base_bottom : base_len)
    end
    pile_id=pl['pile_id'].to_s.strip
    pile_id="#{pref}#{n.to_s.rjust(3,'0')}" if pile_id.empty?
    raise "Tekrarlanan Kazık ID: #{pile_id}" if used_pile_ids[pile_id]
    raise "#{pile_id} modelde zaten var. 'Başlangıç No' değerini artırın (grid yüklenince otomatik önerilir)." if existing_ids[pile_id]
    occ=existing_pts[[pile_structure.to_s,ax['name'].to_s.strip,pl['y_axis'].to_s]]
    raise "#{ax['name']} / #{pl['y_axis']} noktasında zaten kazık var (#{occ}). Bu nokta seçilmemeli." if occ && !ax['name'].to_s.strip.empty? && !pl['y_axis'].to_s.empty?
    used_pile_ids[pile_id]=true
    if body_mode=='COMPONENT'
     pile,comp_ip,comp_colors=mst_prof(:add_pile){mst_add_pile_component(layout.entities,pd,x,y,pile_id,zone)}
    else
     pile=mst_prof(:add_pile){add_pile(layout.entities,pd,x,y,pile_id)}
    end
    axis_no=i+1;pile_no_axis=j+1
    axis_name=ax['name'].to_s.strip;axis_name=axis_no.to_s if axis_name.empty?;pile.set_attribute(DICT,'axis',axis_name);pile.set_attribute(DICT,'axis_no',axis_no);pile.set_attribute(DICT,'grid_x_axis',axis_name)
    pile.set_attribute(DICT,'pile_no_in_axis',pile_no_axis);pile.set_attribute(DICT,'global_pile_id',pile_id)
    pile.set_attribute(DICT,'structure_zone',data['structure_zone'].to_s);pile_group_name=(pl['pile_group'].to_s.strip.empty? ? data['pile_group'].to_s : pl['pile_group'].to_s);pile.set_attribute(DICT,'pile_group',pile_group_name);pile.set_attribute(DICT,'pile_group_name',pile_group_name);pile.set_attribute(DICT,'pile_group_code',data['pile_group_code'].to_s);pile.set_attribute(DICT,'system',pile_system);pile.set_attribute(DICT,'structure',pile_structure);pile.set_attribute(DICT,'elevation_zone',zone);pile.set_attribute(DICT,'axis_x_m',x);pile.set_attribute(DICT,'axis_y_m',y);pile.set_attribute(DICT,'global_x_m',x+structure_origin[0].to_f);pile.set_attribute(DICT,'global_y_m',y+structure_origin[1].to_f);pile.set_attribute(DICT,'grid_y_axis',pl['y_axis']);pile.set_attribute(DICT,'grid_point',pl['y_axis'].to_s.empty? ? axis_name : "#{axis_name}/#{pl['y_axis']}");pile.set_attribute(DICT,'grid_offset_x_m',pl['dx']);pile.set_attribute(DICT,'grid_offset_y_m',pl['dy']);pile.set_attribute(DICT,'placement_method',custom ? 'REFERENCE_GRID' : 'STANDARD');pile.set_attribute(DICT,'batter_ratio',pile_batter_ratio(pd['batter_ratio']));pile.set_attribute(DICT,'azimuth_deg',pd['azimuth_deg'].to_f%360.0);pile.set_attribute(DICT,'orientation_mode',pd['orientation_mode'].to_s)
    elevation_mode=(pl['elevation_mode'].to_s=='SPECIAL' ? 'SPECIAL' : 'GENERAL')
    pile.set_attribute(DICT,'elevation_mode',elevation_mode)
    pile.set_attribute(DICT,'elevation_reason',elevation_mode=='SPECIAL' ? pl['elevation_reason'].to_s : '')
    pile.set_attribute(DICT,'linked_element_id',elevation_mode=='SPECIAL' ? pl['linked_element_id'].to_s : '')
    pile.set_attribute(DICT,'special_top_elevation_m',elevation_mode=='SPECIAL' ? top : nil)
    if body_mode=='COMPONENT'
     mst_pile_component_finish!(pile,comp_ip,comp_colors)
    else
     mst_prof(:add_infill){add_pile_infill(pile,pd,zone)}
     mst_prof(:visual_refresh){mst_visual_refresh_pile(pile,{})}
    end
    mst_prof(:qto_sync){sync_pile_bim_qto(pile)}
    pile.set_attribute(DICT,'individual_override',(%w[diameter_mm thickness_mm length_m top_elevation_m steel_grade orientation_mode batter_ratio azimuth_deg elevation_mode elevation_reason linked_element_id].any?{|k|v=pl[k]; !v.nil? && !v.to_s.strip.empty?}) ? '1' : '0')
    pile.set_attribute(DICT,'elevation_lock',lock_mode)
    pile.set_attribute(DICT,'reference_bottom_elevation_m',base_bottom) if lock_mode=='BOTTOM'
    n+=1
   end
  end
  end # mst_scan_batch
  # Translate once at parent level: pile grid coordinates remain structure-local metadata.
  ox=structure_origin[0].to_f; oy=structure_origin[1].to_f
  layout.transform!(Geom::Transformation.translation([m(ox),m(oy),0])) if ox.abs>1.0e-9 || oy.abs>1.0e-9
  commit_with_dependencies(model);model.active_view.zoom(layout)
  context_text=use_structure ? "#{pile_system} / #{pile_structure}" : "Legacy ANO / #{data['ano']}"
  msg="#{total_piles} kazık oluşturuldu.\nAktif Yapı: #{context_text} • Global Başlangıç X/Y: #{format('%.2f',ox)} / #{format('%.2f',oy)} m
\nAks sayısı: #{axes.length}#{custom ? ' (Gerçek Kazık Yerleşimi)' : ''}\nNormal kazık üst kotu: #{format('%+.2f',normal_top)} m"
  msg+="\nBaşlangıç düşük bölge: #{sc} kazık / aks, üst kot #{format('%+.2f',st)} m" if sc>0
  msg+="\nSon düşük bölge: #{ec} kazık / aks, üst kot #{format('%+.2f',et)} m" if ec>0
  msg+="\nKot kilidi: #{lock_mode=='BOTTOM' ? 'Alt Kot Sabit — Boy Değişir' : 'Boy Sabit — Alt Kot Değişir'}"
  msg+="\nKazık gövdesi: #{body_mode=='COMPONENT' ? 'Component (paylaşılan tanım; düzenleme sonraki sürümde)' : 'Group'}"
  UI.messagebox(msg)
 rescue=>e
  model.abort_operation;UI.messagebox("Hata:\n#{e.message}")
 end
end

# ---------------------------------------------------------------------------
# v0.38 R6 — Component Read Layer.
# READ paths accept a BIM element as Sketchup::Group OR Sketchup::ComponentInstance.
# WRITE paths (since v0.38 C3–C6): a ComponentInstance pile is never redrawn in
# place — its definition is shared. Every public write path dispatches first
# (mst_rebuild_pile_component!, mst_pile_component_refresh!, …) and attaches the
# definition matching the pile's new values. mst_require_group_pile! remains only
# as a safety net INSIDE Group-only drawing code, after that dispatch.
# QTO rule: a component pile's infill is counted PER INSTANCE through the pile
# (qto_reconcile_pile_infill!), never by enumerating the shared child entity.
# ---------------------------------------------------------------------------
def mst_container_entities(e)
  if e.is_a?(Sketchup::Group) then e.entities
  elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
  end
end

def mst_component_pile?(p)
  p.is_a?(Sketchup::ComponentInstance)
end

def mst_bim_children(e,type)
  ents=mst_container_entities(e)
  return [] unless ents
  ents.select{|x|(x.is_a?(Sketchup::Group) || x.is_a?(Sketchup::ComponentInstance)) && x.valid? && x.get_attribute(DICT,'element_type','').to_s==type}
end

def mst_require_group_pile!(p,action='Bu işlem')
  return true unless mst_component_pile?(p)
  n=p.definition.instances.length
  raise "#{p.get_attribute(DICT,'pile_id','?')}: #{action} Component kazıkta henüz desteklenmiyor (tanım (definition) '#{p.definition.name}' #{n} kazık tarafından paylaşılıyor; geometri değişikliği hepsini etkilerdi)."
end

def collect_piles(entities,parent_tr=Geom::Transformation.new,arr=[])
 entities.each do|e|
  next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
  tr=parent_tr*e.transformation
  if e.get_attribute(DICT,'element_type')=='steel_pipe_pile';arr<<[e,tr]
  else;collect_piles(mst_container_entities(e),tr,arr);end
 end
 arr
end

def contains?(g,target)
 return true if g.entities.to_a.include?(target)
 g.entities.grep(Sketchup::Group).any?{|x|contains?(x,target)}
end

def mst_entity_contains_selected?(entity, selection)
 return true if selection.include?(entity)
 ents = entity.is_a?(Sketchup::Group) ? entity.entities : (entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.entities : nil)
 return false unless ents
 ents.any? do |child|
  selection.include?(child) || ((child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)) && mst_entity_contains_selected?(child, selection))
 end
end

def selected_piles
 model=Sketchup.active_model
 sel=model.selection
 all=collect_piles(model.entities)
 chosen=[]
 # User-friendly resolver: selecting the pile itself OR any visible child geometry
 # inside that pile resolves to the owning BIM pile.
 all.each{|p|chosen << p if sel.include?(p[0]) || mst_entity_contains_selected?(p[0],sel)}
 # Selecting any parent/container that owns pile geometry must also resolve its
 # descendant BIM pile(s). Users should not need to know MST nesting internals.
 sel.to_a.each do |sg|
  next unless sg.is_a?(Sketchup::Group) || sg.is_a?(Sketchup::ComponentInstance)
  descendants = []
  begin
    root_entities = sg.is_a?(Sketchup::Group) ? sg.entities : sg.definition.entities
    collect_piles(root_entities, sg.transformation, descendants)
  rescue
    descendants = []
  end
  descendants.each do |dp|
    hit = all.find{|ap| ap[0].persistent_id == dp[0].persistent_id}
    chosen << (hit || dp)
  end
 end
 chosen.uniq{|p|p[0].persistent_id}
end

# BK Unified BIM 0.37.0: preflight before adding geometry.
def mst_bk_preflight!(model,piles,id)
 raise 'BK ID boş olamaz.' if id.to_s.strip.empty?
 raise 'BK için en az iki kazık gerekir.' if piles.length < 2
 # Legacy pile layouts can contain missing/reused visible Pile IDs. The actual
 # SketchUp persistent ID is the stable BIM connection key; do not block geometry.
 pids=piles.map{|p,tr|p.persistent_id}
 raise 'Aynı fiziksel kazık seçimde tekrarlanıyor.' if pids.uniq.length != pids.length
 existing=[]; collect_elements(model.entities,existing)
 if existing.any?{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam' && e.get_attribute(DICT,'head_beam_id','').to_s==id.to_s}
  raise "#{id} zaten modelde bulunuyor. Farklı BK ID giriniz veya mevcut BK'yi düzenleyiniz."
 end
 true
end

def mst_bk_connection_metadata(piles,mode)
 { 'connected_pile_persistent_ids'=>piles.map{|p,tr|p.persistent_id.to_s}.join(', '),
   'connected_pile_count'=>piles.length,
   'head_beam_mode'=>mode,
   'bk_schema_version'=>'0.37.0' }
end

def create_head_beam_for_piles(model,piles,data,id)
 mst_bk_preflight!(model,piles,id)
 anos=piles.map{|p,tr|p.get_attribute(DICT,'ano','').to_s}.reject(&:empty?).uniq
 raise 'Farklı ANO’lara ait kazıklar aynı Başlık Kirişinde kullanılamaz.' if anos.length>1
 centers=piles.map{|p,tr|tr.origin}
 maxd=-1;a=nil;b=nil
 centers.combination(2){|p1,p2|d=p1.distance(p2);if d>maxd;maxd=d;a=p1;b=p2;end}
 ux=b.x-a.x;uy=b.y-a.y;mag=Math.sqrt(ux*ux+uy*uy)
 raise 'Kazık merkezleri çakışıyor.' if mag<0.001
 ux/=mag;uy/=mag;vx=-uy;vy=ux
 lateral=centers.map{|pt|pt.x*vx+pt.y*vy}
 tol=m(data['row_tolerance_m'].to_f.abs)
 raise 'Kazıklar tek bir aks oluşturmuyor.' if lateral.max-lateral.min>tol
 along=centers.map{|pt|pt.x*ux+pt.y*uy};cl=lateral.sum/lateral.length.to_f
 legacy_over=m(data['overhang_m'].to_f)
 start_over=data['start_overhang_m'].to_s.empty? ? legacy_over : m(data['start_overhang_m'].to_f)
 end_over=data['end_overhang_m'].to_s.empty? ? legacy_over : m(data['end_overhang_m'].to_f)
 raise 'Başlangıç / son taşması negatif olamaz.' if start_over<0 || end_over<0
 s0=along.min-start_over;s1=along.max+end_over;len=s1-s0
 wid=m(data['hb_width_m'].to_f);hei=m(data['hb_height_m'].to_f)
 raise 'Kiriş genişliği ve yüksekliği sıfırdan büyük olmalı.' if wid<=0||hei<=0
 bottom_z=m(data['hb_bottom_elevation_m'].to_f);top_z=bottom_z+hei
 origin=Geom::Point3d.new(ux*s0+vx*(cl-wid/2.0),uy*s0+vy*(cl-wid/2.0),bottom_z)

 g=model.active_entities.add_group;e=g.entities
 profile=recess_profile_points(len,hei,data)
 face=e.add_face(profile.map{|x,z|Geom::Point3d.new(x,0,z)})
 raise 'Başlık kirişi/diş geometrisi oluşturulamadı.' unless face && face.valid?
 face.reverse! if face.normal.y < 0
 face.pushpull(wid)
 form_hex=data['formwork_color'].to_s;conc_hex=data['concrete_color'].to_s
 form_mat=material_for(model,"MAG Kalıp #{form_hex}",form_hex)
 conc_mat=nil
 fw_bottom,fw_long,fw_end=classify_box_faces(g,form_mat,conc_mat);fw_total=fw_bottom+fw_long+fw_end
 angle=Math.atan2(uy,ux)
 g.transform!(Geom::Transformation.translation(origin)*Geom::Transformation.rotation(ORIGIN,Z_AXIS,angle))
 vol=polygon_area_xz(profile)/(1.m*1.m) * wid.to_m

 pile_diameters=piles.map{|pi|pi[0].get_attribute(DICT,'diameter_mm',0).to_f}
 raise "Seçilen kazıklardan en az birinde çap metadata'sı bulunamadı." if pile_diameters.any?{|d|d<=0}
 pile_opening_area=piles.sum{|pi|mst_pile_opening_m2(pi[0].get_attribute(DICT,'diameter_mm',0).to_f,mst_pile_opening_ratio(pi[0]))}   # v0.51.5: eğik kazıkta elips
 diameter_counts=pile_diameters.group_by{|d|d.round(3)}.transform_values(&:length)
 diameter_breakdown=diameter_counts.sort.map{|d,c|"#{c} x Ø#{format('%.1f',d)}"}.join(' + ')
 pile_ids=piles.map{|pi|pi[0].get_attribute(DICT,'pile_id','').to_s}.reject(&:empty?).join(', ')

 {'element_type'=>'head_beam','head_beam_id'=>id,'beam_type'=>(data['beam_type'].to_s.strip.empty? ? 'BK-01' : data['beam_type'].to_s.strip),'axis'=>data['axis'].to_s,
  'project'=>piles.first[0].get_attribute(DICT,'project','').to_s,'ano'=>piles.first[0].get_attribute(DICT,'ano','').to_s,'zone'=>piles.first[0].get_attribute(DICT,'ano','').to_s,
  'length_m'=>len.to_m,'width_m'=>wid.to_m,'height_m'=>hei.to_m,
  'start_overhang_m'=>start_over.to_m,'end_overhang_m'=>end_over.to_m,
  'top_elevation_m'=>top_z.to_m,'bottom_elevation_m'=>bottom_z.to_m,
  'concrete_class'=>data['concrete_class'].to_s,'concrete_volume_m3'=>vol,
  'formwork_area_m2'=>fw_total,'formwork_gross_area_m2'=>fw_total,
  'pile_opening_area_m2'=>pile_opening_area,'formwork_net_area_m2'=>[fw_total-pile_opening_area,0.0].max,
  'connected_pile_ids'=>pile_ids,'connected_pile_diameters'=>diameter_breakdown,
  'formwork_bottom_m2'=>fw_bottom,'formwork_long_sides_m2'=>fw_long,'formwork_end_faces_m2'=>fw_end,
  'formwork_color'=>form_hex,'concrete_color'=>conc_hex,'selected_pile_count'=>piles.length,
  'start_tooth_enabled'=>data['start_tooth_enabled'].to_s,'start_tooth_length_m'=>data['start_tooth_length_m'].to_f,
  'start_tooth_depth_m'=>data['start_tooth_depth_m'].to_f,'start_tooth_slope_m'=>data['start_tooth_slope_m'].to_f,
  'end_tooth_enabled'=>data['end_tooth_enabled'].to_s,'end_tooth_length_m'=>data['end_tooth_length_m'].to_f,
  'end_tooth_depth_m'=>data['end_tooth_depth_m'].to_f,'end_tooth_slope_m'=>data['end_tooth_slope_m'].to_f,
  'start_seat_enabled'=>data['start_seat_enabled'].to_s,'start_seat_offset_m'=>data['start_seat_offset_m'].to_f,
  'start_seat_length_m'=>data['start_seat_length_m'].to_f,'start_seat_depth_m'=>data['start_seat_depth_m'].to_f,
  'end_seat_enabled'=>data['end_seat_enabled'].to_s,'end_seat_offset_m'=>data['end_seat_offset_m'].to_f,
  'end_seat_length_m'=>data['end_seat_length_m'].to_f,'end_seat_depth_m'=>data['end_seat_depth_m'].to_f,
  'placement'=>'selected_piles_real_elevation'}.merge(mst_bk_connection_metadata(piles,'single_axis')).each{|k,v|g.set_attribute(DICT,k,v)}
 g.name=id
 finalize_bim_identity(g,model)
 {group:g,id:element_visible_id(g),volume:vol,gross:fw_total,deduction:pile_opening_area,net:[fw_total-pile_opening_area,0.0].max,diameters:diameter_breakdown}
end

def create_multi_axis_head_beam_for_piles(model,piles,data,id)
 mst_bk_preflight!(model,piles,id)
 anos=piles.map{|p,tr|p.get_attribute(DICT,'ano','').to_s}.reject(&:empty?).uniq
 raise 'Farklı ANO’lara ait kazıklar aynı Başlık Kirişinde kullanılamaz.' if anos.length>1
 raise 'Çoklu Aks BK için en az 4 kazık seçmelisin.' if piles.length<4
 centers=piles.map{|p,tr|tr.origin}
 xs=centers.map(&:x); ys=centers.map(&:y)
 tol=m(data['row_tolerance_m'].to_f.abs)
 # Multi-axis means at least two distinct X stations. Cluster with the same tolerance used by the normal axis engine.
 xrows=[]
 xs.sort.each{|x| row=xrows.find{|v|(v-x).abs<=tol}; row ? nil : xrows<<x }
 raise 'Çoklu Aks BK için en az iki farklı kazık aksı seçmelisin.' if xrows.length<2
 wid=m(data['hb_width_m'].to_f); hei=m(data['hb_height_m'].to_f)
 raise 'Kiriş genişliği ve yüksekliği sıfırdan büyük olmalı.' if wid<=0||hei<=0
 legacy_over=m(data['overhang_m'].to_f)
 start_over=data['start_overhang_m'].to_s.empty? ? legacy_over : m(data['start_overhang_m'].to_f)
 end_over=data['end_overhang_m'].to_s.empty? ? legacy_over : m(data['end_overhang_m'].to_f)
 raise 'Başlangıç / son taşması negatif olamaz.' if start_over<0 || end_over<0
 # Marine convention: X = axis progression, Y = head-beam direction.
 # Outer X faces extend half the normal BK width beyond the first/last pile axis.
 xmin=xs.min-wid/2.0; xmax=xs.max+wid/2.0
 ymin=ys.min-start_over; ymax=ys.max+end_over
 xlen=xmax-xmin; ylen=ymax-ymin
 raise 'Çoklu Aks BK geometrisi oluşturulamadı.' if xlen<=0 || ylen<=0
 bottom_z=m(data['hb_bottom_elevation_m'].to_f); top_z=bottom_z+hei
 g=model.active_entities.add_group; e=g.entities
 pts=[Geom::Point3d.new(0,0,0),Geom::Point3d.new(xlen,0,0),Geom::Point3d.new(xlen,ylen,0),Geom::Point3d.new(0,ylen,0)]
 face=e.add_face(pts); raise 'Çoklu Aks BK taban yüzeyi oluşturulamadı.' unless face && face.valid?
 face.reverse! if face.normal.z<0; face.pushpull(hei)
 form_hex=data['formwork_color'].to_s; conc_hex=data['concrete_color'].to_s
 form_mat=material_for(model,"MAG Kalıp #{form_hex}",form_hex)
 fw_bottom,fw_long,fw_end=classify_box_faces(g,form_mat,nil); fw_total=fw_bottom+fw_long+fw_end
 g.transform!(Geom::Transformation.translation(Geom::Point3d.new(xmin,ymin,bottom_z)))
 vol=xlen.to_m*ylen.to_m*hei.to_m
 pile_diameters=piles.map{|pi|pi[0].get_attribute(DICT,'diameter_mm',0).to_f}
 raise "Seçilen kazıklardan en az birinde çap metadata'sı bulunamadı." if pile_diameters.any?{|d|d<=0}
 pile_opening_area=piles.sum{|pi|mst_pile_opening_m2(pi[0].get_attribute(DICT,'diameter_mm',0).to_f,mst_pile_opening_ratio(pi[0]))}   # v0.51.5: eğik kazıkta elips
 diameter_counts=pile_diameters.group_by{|d|d.round(3)}.transform_values(&:length)
 diameter_breakdown=diameter_counts.sort.map{|d,c|"#{c} x Ø#{format('%.1f',d)}"}.join(' + ')
 pile_ids=piles.map{|pi|pi[0].get_attribute(DICT,'pile_id','').to_s}.reject(&:empty?).join(', ')
 axes=piles.map{|pi|pi[0].get_attribute(DICT,'axis','').to_s}.reject(&:empty?).uniq
 axis_label=axes.empty? ? "MULTI-#{xrows.length}" : axes.join(' + ')
 {'element_type'=>'head_beam','head_beam_id'=>id,'beam_type'=>(data['beam_type'].to_s.strip.empty? ? 'BK-03' : data['beam_type'].to_s.strip),'axis'=>axis_label,
  'head_beam_mode'=>'multi_axis','axis_count'=>xrows.length,'project'=>piles.first[0].get_attribute(DICT,'project','').to_s,
  'ano'=>piles.first[0].get_attribute(DICT,'ano','').to_s,'zone'=>piles.first[0].get_attribute(DICT,'ano','').to_s,
  'length_m'=>ylen.to_m,'width_m'=>xlen.to_m,'height_m'=>hei.to_m,'multi_axis_span_m'=>(xs.max-xs.min).to_m,
  'start_overhang_m'=>start_over.to_m,'end_overhang_m'=>end_over.to_m,'top_elevation_m'=>top_z.to_m,'bottom_elevation_m'=>bottom_z.to_m,
  'concrete_class'=>data['concrete_class'].to_s,'concrete_volume_m3'=>vol,'formwork_area_m2'=>fw_total,'formwork_gross_area_m2'=>fw_total,
  'pile_opening_area_m2'=>pile_opening_area,'formwork_net_area_m2'=>[fw_total-pile_opening_area,0.0].max,'connected_pile_ids'=>pile_ids,
  'connected_pile_diameters'=>diameter_breakdown,'formwork_bottom_m2'=>fw_bottom,'formwork_long_sides_m2'=>fw_long,'formwork_end_faces_m2'=>fw_end,
  'formwork_color'=>form_hex,'concrete_color'=>data['concrete_color'].to_s,'selected_pile_count'=>piles.length,'placement'=>'selected_multi_axis_piles'}.merge(mst_bk_connection_metadata(piles,'multi_axis')).each{|k,v|g.set_attribute(DICT,k,v)}
 g.name=id; finalize_bim_identity(g,model)
 {group:g,id:element_visible_id(g),volume:vol,gross:fw_total,deduction:pile_opening_area,net:[fw_total-pile_opening_area,0.0].max,diameters:diameter_breakdown,axes:xrows.length}
end

def layout_selected?
 Sketchup.active_model.selection.grep(Sketchup::Group).any?{|g|g.get_attribute(DICT,'element_type')=='pile_layout'}
end

def group_piles_into_rows(piles,tol)
 # Marine Structures convention:
 # X = Ano length / axis progression.
 # Y = Ano width / Head Beam direction.
 # Therefore each Head Beam axis is a constant-X pile group.
 sorted=piles.sort_by{|p,tr|tr.origin.x}
 rows=[]
 sorted.each do |p|
  x=p[1].origin.x
  row=rows.find{|r|(r[:mean_x]-x).abs<=tol}
  if row
   row[:piles]<<p
   row[:mean_x]=row[:piles].sum{|q|q[1].origin.x}/row[:piles].length.to_f
  else
   rows<<{mean_x:x,piles:[p]}
  end
 end
 rows.sort_by{|r|r[:mean_x]}.map{|r|r[:piles].sort_by{|q|q[1].origin.y}}
end

def auto_head_beam(data)
 model=Sketchup.active_model;piles=selected_piles
 if piles.length<2
  UI.messagebox("En az 2 kazık veya bir kazık yerleşimi (Pile Layout) grubu seçmelisin.");return
 end

 # v0.34.10 — A selected Pile Layout is only an organisation container.
 # Never interpret selecting the container as "create BK on every axis".
 # Target only the axis / axis range explicitly requested in the Head Beam UI.
 if layout_selected?
  from_axis=[data['hb_target_axis_from'].to_i,1].max
  to_axis=[data['hb_target_axis_to'].to_i,from_axis].max
  from_axis,to_axis=to_axis,from_axis if to_axis<from_axis
  target=(from_axis..to_axis).to_a.map(&:to_s)
  piles=piles.select{|p,tr| target.include?(p.get_attribute(DICT,'axis','').to_s)}
  if piles.length<2
   UI.messagebox("Seçilen kazık yerleşimi (Pile Layout) içinde hedef Aks #{from_axis}#{to_axis==from_axis ? '' : "-#{to_axis}"} için yeterli kazık bulunamadı.");return
  end
  if data['hb_creation_mode'].to_s!='multi_axis' && from_axis!=to_axis
   UI.messagebox("Tek Aks / Standart BK için Başlangıç ve Bitiş Aksı aynı olmalıdır.");return
  end
  if data['hb_creation_mode'].to_s=='multi_axis' && from_axis==to_axis
   UI.messagebox("Çoklu Aks / Birleşik BK için en az iki aks seçmelisin.");return
  end
 end

 # BK3 / combined head beam: selected piles may belong to two or more X axes.
 if data['hb_creation_mode'].to_s=='multi_axis'
  id=data['hb_id'].to_s.strip; id='HB-MULTI-001' if id.empty? || id=='HB-001'
  data['beam_type']='BK-03' if data['beam_type'].to_s.strip.empty?
  model.start_operation('Çok Akslı Birleşik Başlık Kirişi (BK)',true)
  begin
   r=create_multi_axis_head_beam_for_piles(model,piles,data,id)
   commit_with_dependencies(model);model.selection.clear;model.selection.add(r[:group]);model.active_view.zoom(r[:group])
   UI.messagebox("#{id} Çoklu Aks BK oluşturuldu.\nAks Sayısı: #{r[:axes]}\nBağlı Kazıklar: #{r[:diameters]}\nKazık Kesintisi: -#{format('%.2f',r[:deduction])} m²\nNet Kalıp: #{format('%.2f',r[:net])} m²")
  rescue=>e
   model.abort_operation;UI.messagebox("Hata:\n#{e.message}")
  end
  return
 end

 # v0.34.10: legacy "selected layout => create BK on every axis" workflow removed.
 # A Pile Layout selection is now resolved to the explicit target axis/range above.

 # Existing manual workflow: select only the piles belonging to one Head Beam.
 centers=piles.map{|p,tr|tr.origin};maxd=-1;a=nil;b=nil
 centers.combination(2){|p1,p2|d=p1.distance(p2);if d>maxd;maxd=d;a=p1;b=p2;end}
 ux=b.x-a.x;uy=b.y-a.y;mag=Math.sqrt(ux*ux+uy*uy)
 raise 'Kazık merkezleri çakışıyor.' if mag<0.001
 ux/=mag;uy/=mag;vx=-uy;vy=ux
 lateral=centers.map{|pt|pt.x*vx+pt.y*vy};tol=m(data['row_tolerance_m'].to_f.abs)
 if lateral.max-lateral.min>tol
  UI.messagebox("Seçilen kazıklar tek bir aks oluşturmuyor.\nSadece aynı başlık kirişi altındaki kazıkları seç.");return
 end

 id=data['hb_id'].to_s.strip;id='HB-001' if id.empty?
 data['beam_type']='BK-01' if data['beam_type'].to_s.strip.empty?
 model.start_operation('Otomatik Başlık Kirişi (BK)',true)
 begin
  r=create_head_beam_for_piles(model,piles,data,id)
  commit_with_dependencies(model);model.selection.clear;model.selection.add(r[:group]);model.active_view.zoom(r[:group])
  UI.messagebox("#{id} oluşturuldu.\nBağlı Kazıklar: #{r[:diameters]}\nKazık Kesintisi: -#{format('%.2f',r[:deduction])} m²\nNet Kalıp: #{format('%.2f',r[:net])} m²")
 rescue=>e
  model.abort_operation;UI.messagebox("Hata:\n#{e.message}")
 end
end


def mst_hb_type_payload(type_hash, base={})
 t=type_hash || {}
 base.merge({
  'beam_type'=>t['name'].to_s,
  'hb_width_m'=>t['width'].to_s,'hb_height_m'=>t['height'].to_s,'hb_bottom_elevation_m'=>t['bottom'].to_s,
  'concrete_class'=>t['concrete'].to_s,'formwork_color'=>t['formcolor'].to_s,'concrete_color'=>t['conccolor'].to_s,
  'start_overhang_m'=>t['startOverhang'].to_s,'end_overhang_m'=>t['endOverhang'].to_s,
  'start_tooth_enabled'=>t['startOn'] ? '1':'0','start_tooth_length_m'=>t['startLen'].to_s,'start_tooth_depth_m'=>t['startDepth'].to_s,'start_tooth_slope_m'=>t['startSlope'].to_s,
  'end_tooth_enabled'=>t['endOn'] ? '1':'0','end_tooth_length_m'=>t['endLen'].to_s,'end_tooth_depth_m'=>t['endDepth'].to_s,'end_tooth_slope_m'=>t['endSlope'].to_s,
  'start_seat_enabled'=>t['startSeatOn'] ? '1':'0','start_seat_offset_m'=>t['startSeatOffset'].to_s,'start_seat_length_m'=>t['startSeatLen'].to_s,'start_seat_depth_m'=>t['startSeatDepth'].to_s,
  'end_seat_enabled'=>t['endSeatOn'] ? '1':'0','end_seat_offset_m'=>t['endSeatOffset'].to_s,'end_seat_length_m'=>t['endSeatLen'].to_s,'end_seat_depth_m'=>t['endSeatDepth'].to_s
 })
end

# v0.37.0c: live BIM axis inventory; never read the new-pile form counters.
def mst_bk_live_axes
 model=Sketchup.active_model
 all=collect_piles(model.entities)
 active=model.get_attribute(DICT,'active_ano','ANO-01').to_s
 piles=all.select{|p,tr|p.get_attribute(DICT,'ano','').to_s==active}
 if piles.empty?
  anos=all.map{|p,tr|p.get_attribute(DICT,'ano','').to_s}.uniq
  if anos.length==1 && !all.empty?
   active=anos.first;piles=all
  end
 end
 groups=piles.group_by{|p,tr| [p.get_attribute(DICT,'axis_no',0).to_i,p.get_attribute(DICT,'axis','').to_s]}
 amap=mst_axis_display_names(model)   # ADR-0515-I: label / imza kod kalır; display_label yalnız gösterim
 axes=groups.keys.sort_by{|no,label|[no>0 ? no : 999999,label]}.each_with_index.map do |key,i|
  members=groups[key]
  {'index'=>i+1,'axis_no'=>key[0],'label'=>key[1],'display_label'=>mst_axis_display(active,active,'x',key[1],amap),'count'=>members.length,
   'pile_ids'=>members.map{|p,tr|p.get_attribute(DICT,'pile_id','').to_s}}
 end
 {'ano'=>active,'ano_label'=>mst_structure_label(active,nil,model),'axes'=>axes,'pile_count'=>piles.length,'model_pile_count'=>all.length}
end

# v0.37.0g: selected BK is edited inside its own module (first stage: width).
def mst_bk_selected_edit_group
 model=Sketchup.active_model
 g=model.selection.to_a.find{|e|e.is_a?(Sketchup::Group) && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise 'SketchUp modelinden yalnızca bir fiziksel Başlık Kirişi seçin.' unless g && model.selection.to_a.count{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}==1
 g
end

def mst_bk_load_selected_edit
 g=mst_bk_selected_edit_group
 h=mst_attr_hash(g)
 t={'name'=>h['beam_type'].to_s,'width'=>h['width_m'].to_s,'height'=>h['height_m'].to_s,
 'bottom'=>h['bottom_elevation_m'].to_s,'concrete'=>h['concrete_class'].to_s,
 'formcolor'=>h['formwork_color'].to_s,'conccolor'=>h['concrete_color'].to_s,
 'startOverhang'=>h['start_overhang_m'].to_s,'endOverhang'=>h['end_overhang_m'].to_s}
 {'start'=>'start','end'=>'end'}.each do |prefix,js|
  t[js+'On']=h[prefix+'_tooth_enabled'].to_s=='1'
  t[js+'Len']=h[prefix+'_tooth_length_m'].to_s
  t[js+'Depth']=h[prefix+'_tooth_depth_m'].to_s
  t[js+'Slope']=h[prefix+'_tooth_slope_m'].to_s
  t[js+'SeatOn']=h[prefix+'_seat_enabled'].to_s=='1'
  t[js+'SeatOffset']=h[prefix+'_seat_offset_m'].to_s
  t[js+'SeatLen']=h[prefix+'_seat_length_m'].to_s
  t[js+'SeatDepth']=h[prefix+'_seat_depth_m'].to_s
 end
 {'persistent_id'=>g.persistent_id.to_s,'uid'=>h['element_uid'].to_s,
  'id'=>h['head_beam_id'].to_s,'ano'=>h['ano'].to_s,'axis'=>h['axis'].to_s,
  'pile_ids'=>h['connected_pile_ids'].to_s,'volume_m3'=>h['concrete_volume_m3'].to_f,
  'type'=>t,'mode'=>h['head_beam_mode'].to_s,'revision_no'=>h['bk_revision_no'].to_i,'revision_label'=>format('RV-%02d',h['bk_revision_no'].to_i)}
end

def mst_bk_update_selected_edit(data)
 g=mst_bk_selected_edit_group
 raise 'Seçim değişti; BK yeniden okunmalıdır.' unless g.persistent_id.to_s==data['persistent_id'].to_s && g.get_attribute(DICT,'element_uid','').to_s==data['uid'].to_s
 t=data['type']
 bp=mst_bk_single_plan(g,t,data['piles_follow'].to_s!='0')
 # nothing rests on / hangs from the changed levels: plain single edit, as before
 if bp.nil? || (bp['moves'].empty? && bp['piles'].empty? && bp['warnings'].empty?)
  r=mst_bk_apply_type!(g,t,true)
  mst_kn_after_edit([g])
  return r
 end
 title="BK Düzenleme — #{element_visible_id(g)} (bağlı elemanlarla birlikte)"
 unless UI.messagebox(mst_bk_bulk_preview_text(bp,title),MB_YESNO)==IDYES
  h=mst_attr_hash(g)
  return {'id'=>h['head_beam_id'].to_s,'width_m'=>h['width_m'].to_f,'height_m'=>h['height_m'].to_f,'bottom_m'=>h['bottom_elevation_m'].to_f,
   'volume_m3'=>h['concrete_volume_m3'].to_f,'net_m2'=>h['formwork_net_area_m2'].to_f,'revision_label'=>format('RV-%02d',h['bk_revision_no'].to_i),'cancelled'=>true}
 end
 r=mst_bk_bulk_apply(bp,Sketchup.active_model,'MST BK Ortak Form Revizyonu')
 mst_kn_after_edit([g])
 r['results'][0].merge('moved'=>r['moved'],'piles'=>r['piles'])
end

# v0.38 BK6: plan for ONE BK edited in the common form (all form fields, not only the
# bulk ones). nil when width / height / bottom do not change (nothing can follow).
def mst_bk_single_plan(g,t,follow,model=Sketchup.active_model)
 raise mst_bk_rebar_block_reason(g) if mst_bk_rebar_block_reason(g)
 raise 'BK parametreleri bulunamadı.' unless t.is_a?(Hash)
 h=mst_attr_hash(g)
 num=->(k,label){x=Float(t[k].to_s.tr(',','.')) rescue raise("#{label}: sayı değil.");raise "#{label}: geçersiz." unless x.finite?;x}
 nw=num.('width','Genişlik');nh=num.('height','Yükseklik');nb=num.('bottom','Alt kot')
 ow=h['width_m'].to_f;oh=h['height_m'].to_f;ob=h['bottom_elevation_m'].to_f
 return nil if (nw-ow).abs<1e-6 && (nh-oh).abs<1e-6 && (nb-ob).abs<1e-6
 pl={'beam'=>g,'id'=>element_visible_id(g),'type'=>t,'old'=>[ow,oh,ob,ob+oh],'new'=>[nw,nh,nb,nb+nh],
     'dz'=>(nb+nh)-(ob+oh),'cc'=>[h['concrete_class'].to_s,t['concrete'].to_s.strip.empty? ? h['concrete_class'].to_s : t['concrete'].to_s],'deps'=>[]}
 warnings=[]
 # v0.38 BK6.2: the form's bottom is absolute — flag a large jump (e.g. 0.20 typed for +0.20)
 if (nb-ob).abs>1.0
  warnings << "BÜYÜK KOT DEĞİŞİMİ: alt kot #{format('%.3f',ob)} → #{format('%.3f',nb)} m (Δ #{format('%+.3f',nb-ob)} m). Formdaki Alt Kot mutlak değerdir; fark girmek için 'Alt Kot Farkı Δ' alanını kullanın."
 end
 bp=mst_bk_plan_followers([pl],follow,warnings,model)
 bp['warnings']=bp['warnings'].reject{|w|w.include?('üzerindeki prekastların BK\'ya oturma')} if bp['moves'].empty? && bp['piles'].empty?
 bp
end

# v0.38 BK5: body of the single BK edit, reusable by the bulk editor.
# own_op=false: runs inside the caller's operation (no start/commit, no type sync).
# nil = editable. Rebar BKs are editable once their rebar parameters are stored (BKR1).
def mst_bk_rebar_block_reason(g)
 others=g.entities.grep(Sketchup::Group).reject{|x|%w[head_beam_rebar_set bk_culvert].include?(x.get_attribute(DICT,'element_type','').to_s)}   # v0.50: menfez kutusu BK'nın parçası
 return 'BK içinde tanımsız iç grup var; otomatik geometri revizyonu kapalı.' unless others.empty?
 if g.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail' && g.get_attribute(DICT,'hb_rebar_json','').to_s.empty?
  return 'Bu BK\'nın detaylı donatısı eski sürümde oluşturulmuş (donatı değerleri kayıtlı değil). BK\'yı seçip Donatı BIM\'i bir kez yeniden oluşturun; sonra ölçü değişikliğinde donatı otomatik yenilenir.'
 end
 nil
end

def mst_bk_apply_type!(g,t,own_op=true)
 model=Sketchup.active_model
 raise mst_bk_rebar_block_reason(g) if mst_bk_rebar_block_reason(g)
 h=mst_attr_hash(g)
 raise 'Çoklu aks BK revizyonu henüz desteklenmiyor.' if h['head_beam_mode'].to_s=='multi_axis'
 raise 'BK parametreleri bulunamadı.' unless t.is_a?(Hash)
 wid=Float(t['width'].to_s.tr(',','.'));hei=Float(t['height'].to_s.tr(',','.'))
 bot=Float(t['bottom'].to_s.tr(',','.'))
 so=Float(t['startOverhang'].to_s.tr(',','.'));eo=Float(t['endOverhang'].to_s.tr(',','.'))
 raise 'Genişlik/yükseklik 0 ile 20 m arasında olmalı.' unless wid.finite? && hei.finite? && wid>0 && hei>0 && wid<20 && hei<20
 raise 'Taşmalar 0 ile 20 m arasında olmalı.' unless so.finite? && eo.finite? && so>=0 && eo>=0 && so<20 && eo<20
 raise 'Alt kot geçersiz.' unless bot.finite?
 old_w=h['width_m'].to_f;old_h=h['height_m'].to_f;old_bot=h['bottom_elevation_m'].to_f
 old_so=h['start_overhang_m'].to_f;old_eo=h['end_overhang_m'].to_f
 len=h['length_m'].to_f+so+eo-old_so-old_eo
 raise 'BK boyu geçersiz.' unless len>0 && old_w>0 && old_h>0
  payload=mst_hb_type_payload(t)
  # v0.37.3e: compare the submitted values against this physical BK's stored BIM
  # metadata BEFORE clearing geometry or starting an undo operation.
  numeric_pairs={'width'=> 'width_m','height'=>'height_m','bottom'=>'bottom_elevation_m',
   'startOverhang'=>'start_overhang_m','endOverhang'=>'end_overhang_m'}
  unchanged=numeric_pairs.all? do |form_key,stored_key|
   (Float(t[form_key].to_s.tr(',','.'))-h[stored_key].to_f).abs<=0.000001
  end
  string_pairs={'name'=>'beam_type','concrete'=>'concrete_class',
   'formcolor'=>'formwork_color','conccolor'=>'concrete_color'}
  unchanged &&= string_pairs.all? do |form_key,stored_key|
   a=t[form_key].to_s.strip; b=h[stored_key].to_s.strip
   form_key.end_with?('color') ? a.downcase==b.downcase : a==b
  end
  {'start'=>'start','end'=>'end'}.each do |prefix,js|
   {'On'=>'tooth_enabled','SeatOn'=>'seat_enabled'}.each do |suffix,key|
    incoming=t[js+suffix] ? '1' : '0'
    unchanged &&= incoming==h[prefix+'_'+key].to_s
   end
   {'Len'=>'tooth_length_m','Depth'=>'tooth_depth_m','Slope'=>'tooth_slope_m',
    'SeatOffset'=>'seat_offset_m','SeatLen'=>'seat_length_m','SeatDepth'=>'seat_depth_m'}.each do |suffix,key|
    a=t[js+suffix].to_s.strip.tr(',','.'); b=h[prefix+'_'+key].to_s.strip.tr(',','.')
    unchanged &&= ((a.empty? ? 0.0 : Float(a))-(b.empty? ? 0.0 : Float(b))).abs<=0.000001
   end
  end
  if unchanged
   return {'id'=>h['head_beam_id'].to_s,'width_m'=>old_w,'height_m'=>old_h,
    'bottom_m'=>old_bot,'volume_m3'=>h['concrete_volume_m3'].to_f,
    'gross_m2'=>h['formwork_gross_area_m2'].to_f,
    'net_m2'=>h['formwork_net_area_m2'].to_f,
    'revision_label'=>format('RV-%02d',h['bk_revision_no'].to_i),'unchanged'=>true}
  end
  payload['bottom_zones_json']=h['bottom_zones_json'] if h['bottom_zones_json']   # v0.50 TB1
  profile=recess_profile_points(m(len),m(hei),payload)
 raise 'BK profili geçersiz.' unless profile.length>=4
 # Capture semantic face overrides BEFORE rebuild destroys transient Face objects.
 bk_overrides=bk_formwork_override_map(g,true)
 old_sig=element_signature(g)   # v0.38 KN1: type name follows a physical type change
 model.start_operation('MST BK Ortak Form Revizyonu',true) if own_op
 begin
  g.entities.clear!
  f=g.entities.add_face(profile.map{|x,z|Geom::Point3d.new(x,0,z)})
  raise 'BK yüzeyi oluşturulamadı.' unless f && f.valid?
  f.reverse! if f.normal.y<0;f.pushpull(m(wid))
  form_hex=t['formcolor'].to_s;form_hex='#F4B183' if form_hex.empty?
  fm=material_for(model,"MAG Kalıp #{form_hex}",form_hex)
  bottom,long_side,end_face=classify_box_faces(g,fm,nil)
  # Reapply per-face user intent to the newly generated semantic faces.
  bk_store_formwork_override_map(g,bk_overrides)
  gross=bk_apply_formwork_overrides(g,bk_overrides,fm)
  vol=polygon_area_xz(profile)/(1.m*1.m)*wid
  # Local X is beam length, Y is width and Z is elevation. Transform once in local coordinates.
  local=Geom::Transformation.translation([m(old_so-so),m((old_w-wid)/2.0),m(bot-old_bot)])
  g.transform!(g.transformation*local*g.transformation.inverse)
  {'length_m'=>len,'width_m'=>wid,'height_m'=>hei,'bottom_elevation_m'=>bot,'top_elevation_m'=>bot+hei,
   'start_overhang_m'=>so,'end_overhang_m'=>eo,'concrete_volume_m3'=>vol,
   'formwork_bottom_m2'=>bottom,'formwork_long_sides_m2'=>long_side,'formwork_end_faces_m2'=>end_face,
   'formwork_area_m2'=>gross,'formwork_gross_area_m2'=>gross,'formwork_color'=>form_hex,
   'concrete_color'=>t['conccolor'].to_s,'concrete_class'=>t['concrete'].to_s}.each{|k,v|g.set_attribute(DICT,k,v)}
  payload.each{|k,v|g.set_attribute(DICT,k,v) if k.end_with?('_enabled','_length_m','_depth_m','_slope_m','_offset_m')}
  old_name=h['beam_type'].to_s
  new_name=mst_bk_resolve_type_name(g,t['name'],old_name,old_sig,model)
  if new_name!=old_name
   g.set_attribute(DICT,'beam_base_type',old_name) if g.get_attribute(DICT,'beam_base_type','').to_s.empty?
   g.set_attribute(DICT,'beam_type',new_name);mst_assign_tag(g,model)
  end
  deduction=head_beam_pile_opening_area(g)
  g.set_attribute(DICT,'formwork_net_area_m2',[gross-deduction,0.0].max)
  g.set_attribute(DICT,'rebar_t',vol*rebar_rate('head_beam')/1000.0)
  g.set_attribute(DICT,'bk_individual_override','1')
  mst_cv_redraw!(g) if respond_to?(:mst_cv_redraw!)   # v0.50 MF1: menfezler kayıtlı tanımdan
  # v0.38 BKR1: the rebar set was cleared with the geometry; regenerate it for the new size
  if g.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'
   mst_hb_rebar_build!(g,JSON.parse(g.get_attribute(DICT,'hb_rebar_json','{}').to_s))
  end
  # Revision belongs to the physical BK, never to its stable ID or shared type.
  # The update operation is atomic: Undo restores both geometry and revision metadata.
  previous_revision=h['bk_revision_no'].to_i
  g.set_attribute(DICT,'bk_revision_no',previous_revision+1)
  g.set_attribute(DICT,'bk_revision_label',format('RV-%02d',previous_revision+1))
  if own_op
   mst_sync_bk_type_library(model)
   commit_with_dependencies(model)
  end
  {'id'=>h['head_beam_id'].to_s,'width_m'=>wid,'height_m'=>hei,'bottom_m'=>bot,
   'volume_m3'=>vol,'gross_m2'=>gross,'net_m2'=>[gross-deduction,0.0].max,'revision_label'=>format('RV-%02d',previous_revision+1),
   'beam_type'=>new_name,'renamed'=>(new_name!=old_name ? [old_name,new_name] : nil)}
 rescue=>e
  model.abort_operation if own_op;raise e
 end
end


# ---------------------------------------------------------------------------
# v0.38 BK5 — BK bulk edit. Common changes (width / height / bottom elevation or
# Δ / concrete class) applied to every selected BK with a preview and ONE Undo.
# Each BK is rebuilt by the same routine as the single edit (mst_bk_apply_type!).
# What sits on a BK (PD / kanal / döşeme / bordür) follows its top-elevation change
# when all BKs it rests on move by the same Δ (BK1 rule); otherwise it stays + warning.
# ---------------------------------------------------------------------------
def mst_bk_type_hash(h)
 t={'name'=>h['beam_type'].to_s,'width'=>h['width_m'].to_s,'height'=>h['height_m'].to_s,
 'bottom'=>h['bottom_elevation_m'].to_s,'concrete'=>h['concrete_class'].to_s,
 'formcolor'=>h['formwork_color'].to_s,'conccolor'=>h['concrete_color'].to_s,
 'startOverhang'=>h['start_overhang_m'].to_s,'endOverhang'=>h['end_overhang_m'].to_s}
 {'start'=>'start','end'=>'end'}.each do |prefix,js|
  t[js+'On']=h[prefix+'_tooth_enabled'].to_s=='1'
  t[js+'Len']=h[prefix+'_tooth_length_m'].to_s
  t[js+'Depth']=h[prefix+'_tooth_depth_m'].to_s
  t[js+'Slope']=h[prefix+'_tooth_slope_m'].to_s
  t[js+'SeatOn']=h[prefix+'_seat_enabled'].to_s=='1'
  t[js+'SeatOffset']=h[prefix+'_seat_offset_m'].to_s
  t[js+'SeatLen']=h[prefix+'_seat_length_m'].to_s
  t[js+'SeatDepth']=h[prefix+'_seat_depth_m'].to_s
 end
 t
end

def mst_bk_bulk_num(v,label)
 s=v.to_s.strip.tr(',','.')
 return nil if s.empty?
 x=Float(s) rescue raise("#{label}: sayı değil (#{v}).")
 raise "#{label}: geçersiz değer." unless x.finite?
 x
end

# ch: {'width','height','bottom','bottom_delta','concrete'} — blank = unchanged.
def mst_bk_bulk_plan(beams,ch,model=Sketchup.active_model)
 w=mst_bk_bulk_num(ch['width'],'Genişlik');hh=mst_bk_bulk_num(ch['height'],'Yükseklik')
 b_abs=mst_bk_bulk_num(ch['bottom'],'Alt kot');b_d=mst_bk_bulk_num(ch['bottom_delta'],'Kot farkı')
 cc=ch['concrete'].to_s.strip
 raise 'Alt kot ve kot farkından yalnız birini girin.' if b_abs && b_d
 raise 'Genişlik 0 ile 20 m arasında olmalı.' if w && !(w>0 && w<20)
 raise 'Yükseklik 0 ile 20 m arasında olmalı.' if hh && !(hh>0 && hh<20)
 raise 'Değiştirilecek bir değer girin.' if [w,hh,b_abs,b_d].all?(&:nil?) && cc.empty?
 plans=[];warnings=[]
 beams.uniq.each do |b|
  id=element_visible_id(b)
  if (why=mst_bk_rebar_block_reason(b))
   warnings << "#{id}: atlandı — #{why}";next
  end
  if b.get_attribute(DICT,'head_beam_mode','').to_s=='multi_axis'
   warnings << "#{id}: çoklu aks BK — toplu düzenleme henüz desteklenmiyor, atlandı.";next
  end
  h=mst_attr_hash(b);t=mst_bk_type_hash(h)
  ow=h['width_m'].to_f;oh=h['height_m'].to_f;ob=h['bottom_elevation_m'].to_f
  nw=w||ow;nh=hh||oh;nb=b_abs || (b_d ? ob+b_d : ob)
  t['width']=nw.to_s;t['height']=nh.to_s;t['bottom']=nb.to_s;t['concrete']=cc unless cc.empty?
  same=(nw-ow).abs<1e-6 && (nh-oh).abs<1e-6 && (nb-ob).abs<1e-6 && (cc.empty? || cc==h['concrete_class'].to_s)
  next if same
  plans << {'beam'=>b,'id'=>id,'type'=>t,'old'=>[ow,oh,ob,ob+oh],'new'=>[nw,nh,nb,nb+nh],'dz'=>(nb+nh)-(ob+oh),'cc'=>[h['concrete_class'].to_s,t['concrete'].to_s],'deps'=>[]}
 end
 return {'plans'=>[],'moves'=>[],'piles'=>[],'warnings'=>warnings} if plans.empty?
 mst_bk_plan_followers(plans,ch['piles_follow'].to_s=='1',warnings,model)
end

# v0.38 BK6: what follows a BK change — piles (head with the BK bottom, toe fixed) and
# the elements resting on it (by the top Δ, same-Δ rule). Shared by bulk and single edit.
def mst_bk_plan_followers(plans,follow,warnings,model=Sketchup.active_model)
 all_e,children,parents,_u=dependency_graph(model)
 pile_by={};all_e.each{|k|pile_by[element_visible_id(k)]=k if k.valid? && k.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
 dz_of={};plans.each{|pl|dz_of[pl['beam']]=pl['dz']}
 moves={};taken={};pile_moves={}
 plans.each do |pl|
  b=pl['beam']
  # piles: head must stay inside the new BK body. v0.38 BK5.1: with 'piles_follow',
  # a pile whose head was inside / touching the old BK is lengthened (or shortened) at
  # its head by the BK bottom change; the toe elevation stays fixed.
  db=pl['new'][2]-pl['old'][2]
  mst_pile_ids_for_beam(b).each do |pid|
   p=pile_by[pid]
   next unless p
   pt=p.get_attribute(DICT,'top_elevation_m',nil);next if pt.nil?
   if follow && db.abs>MST_BK_TOL && pt.to_f.between?(pl['old'][2]-MST_AUDIT_Z_TOL,pl['old'][3]+MST_AUDIT_Z_TOL)
    if pile_moves.key?(p) && (pile_moves[p]['dtop']-db).abs>MST_BK_TOL
     warnings << "#{pid}: birden fazla BK'ya farklı kot farkıyla bağlı; kazık uzatılmadı."
     pile_moves[p]['blocked']=true
    else
     r=p.get_attribute(DICT,'orientation_mode','VERTICAL').to_s.upcase=='BATTERED' ? p.get_attribute(DICT,'batter_ratio',0).to_f : 0.0
     vz=1.0/Math.sqrt(1.0+r*r);l0=p.get_attribute(DICT,'length_m',0).to_f
     pile_moves[p]||={'pile'=>p,'id'=>pid,'dtop'=>db,'top'=>[pt.to_f,pt.to_f+db],'length'=>[l0,l0+db/vz]}
    end
    pt=pt.to_f+db
   end
   if pt.to_f<pl['new'][2]-MST_AUDIT_Z_TOL
    warnings << "#{pl['id']}: #{pid} başı (#{format('%.3f',pt)} m) yeni BK altının (#{format('%.3f',pl['new'][2])} m) altında kalıyor."
   elsif pt.to_f>pl['new'][3]+MST_AUDIT_Z_TOL
    warnings << "#{pl['id']}: #{pid} başı (#{format('%.3f',pt)} m) yeni BK üstünü (#{format('%.3f',pl['new'][3])} m) aşıyor."
   end
  end
  next if pl['dz'].abs<=MST_BK_TOL
  mst_bk_dependents(b,children).each do |dep|
   next if taken[dep]
   anc=mst_bk_beam_ancestors(dep,parents)
   if anc.all?{|a|((dz_of[a]||0.0)-pl['dz']).abs<=MST_BK_TOL}
    taken[dep]=true;moves[dep]=pl['dz'];pl['deps'] << element_visible_id(dep)
   else
    msg="#{element_visible_id(dep)}: #{pl['id']} ile birlikte farklı kotta kalan bir BK'ya da oturuyor; yerinde kaldı, kontrol edin."
    warnings << msg unless warnings.include?(msg)
   end
  end
 end
 # width: precast on a narrowed BK may overhang it
 plans.each do |pl|
  next unless pl['new'][0]<pl['old'][0]-1e-6
  warnings << "#{pl['id']}: genişlik #{format('%.2f',pl['old'][0])} → #{format('%.2f',pl['new'][0])} m; üzerindeki prekastların BK'ya oturma genişliğini Tam Model Kontrolü ile denetleyin."
 end
 pm=pile_moves.values.reject{|x|x['blocked']}
 pm.each{|x|warnings << "#{x['id']}: yeni boy #{format('%.3f',x['length'][1])} m geçersiz; kazık uzatılmadı." if x['length'][1]<=0.5}
 pm.reject!{|x|x['length'][1]<=0.5}
 {'plans'=>plans,'moves'=>moves.map{|e,dz|{'element'=>e,'dz'=>dz}},'piles'=>pm,'warnings'=>warnings}
end

def mst_bk_bulk_preview_text(bp,title=nil)
 f=->(v){format('%.2f',v)}
 lines=[title || "BK Toplu Düzenleme — #{bp['plans'].length} BK",'']
 bp['plans'].first(20).each do |pl|
  o,n=pl['old'],pl['new'];parts=[]
  parts << "G #{f[o[0]]}→#{f[n[0]]}" if (o[0]-n[0]).abs>1e-6
  parts << "Y #{f[o[1]]}→#{f[n[1]]}" if (o[1]-n[1]).abs>1e-6
  parts << "alt #{f[o[2]]}→#{f[n[2]]}" if (o[2]-n[2]).abs>1e-6
  parts << "üst #{f[o[3]]}→#{f[n[3]]}" if (o[3]-n[3]).abs>1e-6
  parts << "beton #{pl['cc'][0]}→#{pl['cc'][1]}" if pl['cc'][0]!=pl['cc'][1]
  lines << "#{pl['id']}: #{parts.join(', ')}"
  lines << "   üzerindekiler #{format('%+.3f',pl['dz'])} m: #{mst_axis_fmt_list(pl['deps'],6)}" unless pl['deps'].empty?
 end
 lines << "… +#{bp['plans'].length-20} BK" if bp['plans'].length>20
 pm=bp['piles']||[]
 unless pm.empty?
  g=pm.group_by{|x|format('%+.3f',x['dtop'])}
  lines << '' << "Kazık başı BK ile birlikte (uç kotu sabit, boy değişir): #{pm.length} kazık"
  g.each{|d,a|lines << "   #{d} m: #{mst_axis_fmt_list(a.map{|x|x['id']},10)} (boy #{format('%.3f',a[0]['length'][0])} → #{format('%.3f',a[0]['length'][1])} m)"}
 end
 unless bp['warnings'].empty?
  lines << '' << 'Uyarılar:'
  bp['warnings'].first(10).each{|w|lines << "⚠ #{w}"}
  lines << "⚠ … #{bp['warnings'].length-10} uyarı daha" if bp['warnings'].length>10
 end
 lines << '' << 'BK geometrisi yeniden oluşturulur (BK UID, kazık bağlantıları ve kalıp yüz seçimleri korunur). Tek Geri Al.' << 'Uygulansın mı?'
 lines.join("\n")
end

def mst_bk_bulk_apply(bp,model=Sketchup.active_model,op_name='MST BK Toplu Düzenleme')
 pm=bp['piles']||[]
 specs=pm.map{|x|mst_pile_target_spec(x['pile'],{'top_elevation_m'=>x['top'][1],'length_m'=>x['length'][1]})}
 errs=specs.flat_map{|sp|sp['errors']}
 raise "Kazık güncellemesi başlatılamadı:\n#{errs.first(10).join("\n")}" unless errs.empty?
 model.start_operation(op_name,true)
 begin
  v0=0.0;v1=0.0;results=[]
  unless specs.empty?
   mst_scan_batch(model){specs.each{|sp|mst_apply_pile_target_spec!(sp)};mst_sync_pile_type_library(model)}
  end
  bp['plans'].each do |pl|
   v0+=pl['beam'].get_attribute(DICT,'concrete_volume_m3',0).to_f
   r=mst_bk_apply_type!(pl['beam'],pl['type'],false)
   results << r
   v1+=r['volume_m3'].to_f
  end
  bp['moves'].each do |mv|
   e=mv['element'];dz=mv['dz'];next unless e.valid?
   e.transform!(Geom::Transformation.translation([0,0,m(dz)]))
   MST_BK_ELEV_KEYS.each{|k|v=e.get_attribute(DICT,k,nil);e.set_attribute(DICT,k,v.to_f+dz) if v.is_a?(Numeric)}
  end
  mst_sync_bk_type_library(model)
  commit_with_dependencies(model)
  {'beams'=>bp['plans'].length,'moved'=>bp['moves'].length,'piles'=>specs.length,'volume'=>[v0,v1],'results'=>results}
 rescue Exception
  model.abort_operation;raise
 end
end

def mst_bk_bulk_edit(data)
 model=Sketchup.active_model
 beams=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise "Modelde düzenlenecek BK'ları seçin (Ctrl ile birden fazla)." if beams.empty?
 bp=mst_bk_bulk_plan(beams,data)
 if bp['plans'].empty?
  msg='Seçili BK’larda değişecek bir değer yok.'
  msg+="\n\n"+bp['warnings'].join("\n") unless bp['warnings'].empty?
  UI.messagebox(msg);return {'status'=>'Değişiklik yok.'}
 end
 return {'status'=>'İptal edildi; model değişmedi.'} unless UI.messagebox(mst_bk_bulk_preview_text(bp),MB_YESNO)==IDYES
 r=mst_bk_bulk_apply(bp,model)
 mst_kn_after_edit(bp['plans'].map{|pl|pl['beam']})
 {'status'=>format('%d BK güncellendi, %d üst eleman taşındı, %d kazık başı uyarlandı • BK betonu %.3f → %.3f m³ (tek Geri Al)',r['beams'],r['moved'],r['piles'],r['volume'][0],r['volume'][1])}
end

def mst_bk_send_live_axes
 @d.execute_script("mstBKLiveAxes(#{JSON.generate(mst_bk_live_axes)})")
rescue => e
 UI.messagebox("BK BIM aks okuma hatası: #{e.message}")
end

def auto_head_beams_bulk(data)
 model=Sketchup.active_model
 all=collect_piles(model.entities)
 active_ano=model.get_attribute(DICT,'active_ano','ANO-01').to_s
 piles=all.select{|p,tr| p.get_attribute(DICT,'ano','').to_s==active_ano}
 if piles.empty?
  available=all.map{|p,tr|p.get_attribute(DICT,'ano','').to_s}.uniq
  if available.length==1 && !all.empty?
   active_ano=available.first; piles=all
  else
   UI.messagebox("Aktif ANO (#{active_ano}) ile eşleşen kazık yok. Modeldeki ANO değerleri: #{available.join(', ')}. Önce aktif ANO'yu seçiniz.");return
  end
 end
 types=(data['bk_types']||[]).each_with_object({}){|t,h|h[t['name'].to_s]=t}
 assignments=data['assignments']||[]; placement=data['placement']||{}
 axis_type={}; assignments.each{|a| f=[a['from'].to_i,1].max;tt=[a['to'].to_i,f].max;(f..tt).each{|n|axis_type[n]=a['type'].to_s}}
 # Resolve the exact live axis inventory used by the UI (supports named axes).
 live=mst_bk_live_axes
 raise 'BK aks listesi değişti. BK panelinde Kazıkları Yeniden Oku düğmesine basınız.' unless data['axis_signature'].to_s==JSON.generate(live['axes'].map{|a|[a['axis_no'],a['label'],a['pile_ids']]})
 by_axis={}
 live['axes'].each do |a|
  by_axis[a['index']]=piles.select{|p,tr|p.get_attribute(DICT,'axis_no',0).to_i==a['axis_no'] && p.get_attribute(DICT,'axis','').to_s==a['label']}
 end
 created=[];skipped=[]; used={}
 model.start_operation('Aktif ANO Başlık Kirişleri - Yerleşim Planı',true)
 begin
  mst_scan_batch(model) do
  starts=by_axis.keys.select{|ax|placement[ax.to_s].to_s=='combined_start'}.sort
  starts.each do |sa|
   ea=by_axis.keys.select{|ax|ax>sa && placement[ax.to_s].to_s=='combined_end'}.min
   raise "Aks #{sa} için Birleşik BK Bitişi bulunamadı." unless ea
   typ=axis_type[sa]; raise "Birleşik BK Aks #{sa}-#{ea}: BK tipi atanmadı." if typ.to_s.empty?
   raise "Birleşik BK Aks #{sa}-#{ea}: başlangıç ve bitiş BK tipleri aynı olmalı." unless axis_type[ea].to_s==typ.to_s
   cp=(sa..ea).flat_map{|n|by_axis[n]||[]}; raise "Birleşik BK Aks #{sa}-#{ea}: yeterli kazık yok." if cp.length<4
   d=mst_hb_type_payload(types[typ],{'row_tolerance_m'=>data['row_tolerance_m'].to_s,'hb_creation_mode'=>'multi_axis'})
   id="HB-#{active_ano}-A#{sa}-#{ea}-#{typ}"; created<<create_multi_axis_head_beam_for_piles(model,cp,d,id)[:group]
   (sa..ea).each{|n|used[n]=true}
  end
  by_axis.keys.sort.each do |ax|
   next if used[ax]; next unless placement[ax.to_s].to_s=='single'
   typ=axis_type[ax]; ap=by_axis[ax]
   if typ.to_s.empty? || !types[typ] || ap.length<2; skipped<<ax;next;end
   d=mst_hb_type_payload(types[typ],{'row_tolerance_m'=>data['row_tolerance_m'].to_s,'hb_creation_mode'=>'single_axis','axis'=>ax.to_s})
   id="HB-#{active_ano}-A#{ax}-#{typ}";created<<create_head_beam_for_piles(model,ap,d,id)[:group]
  end
  end # mst_scan_batch
  commit_with_dependencies(model);model.selection.clear;created.each{|g|model.selection.add(g)};model.active_view.zoom(model.selection) unless created.empty?
  msg="#{active_ano}: #{created.length} Başlık Kirişi oluşturuldu.";msg+="\nAtlandı: Aks #{skipped.join(', ')}" unless skipped.empty?;UI.messagebox(msg)
 rescue=>e;model.abort_operation;UI.messagebox("Toplu BK oluşturma hatası:\n#{e.message}");end
end

def mst_collect_elements_raw(entities,out)
 entities.each do |e|
  if e.is_a?(Sketchup::Group)
   t=e.get_attribute(DICT,'element_type')
   next if t.nil? && !e.get_attribute('MAG_MST_Label','kind').nil?   # v0.47.4 LB2 / PE1: numara ve PE görünüm grupları taranmaz
   out << e if ['steel_pipe_pile','head_beam','pile_infill_concrete','flat_precast','channel_precast','crane_precast','deck_slab','curb','crown_wall','bored_pile'].include?(t)
   # Kazık içi beton, steel_pipe_pile grubunun içinde nested olduğu için
   # steel pile bulunduğunda recursion durdurulmamalı.
   mst_collect_elements_raw(e.entities,out) unless t=='head_beam' || t=='pile_infill_concrete'
  elsif e.is_a?(Sketchup::ComponentInstance)
   t=e.get_attribute(DICT,'element_type')
   if ['steel_pipe_pile','head_beam','pile_infill_concrete','flat_precast','channel_precast','crane_precast','deck_slab','curb','crown_wall','bored_pile'].include?(t)
    out << e
   else
    mst_collect_elements_raw(e.definition.entities,out)
   end
  end
 end
end

# v0.38 R9 — scan batch. Inside mst_scan_batch a whole-model element scan is done
# ONCE; later whole-model collects reuse that list (erased entities filtered out)
# and every element finalized during the batch is appended to it. Results are the
# same as a fresh scan; only the repeated traversal of raw pile geometry is gone.
MST_COLLECTED_TYPES=%w[steel_pipe_pile head_beam pile_infill_concrete flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile].freeze
def collect_elements(entities,out)
 if @mst_scan_batch_on && entities.respond_to?(:parent) && entities.parent.is_a?(Sketchup::Model)
  unless @mst_scan_cache
   c=[];mst_prof(:scan_full){mst_collect_elements_raw(entities,c)}
   @mst_scan_cache=c;@mst_scan_cache_ids={};c.each{|e|@mst_scan_cache_ids[e.persistent_id]=true}
  end
  @mst_scan_cache.select!(&:valid?)
  out.concat(@mst_scan_cache)
  return entities
 end
 mst_prof(:scan_full){mst_collect_elements_raw(entities,out)}
 entities
end

def mst_scan_cache_add(e)
 return unless @mst_scan_batch_on && @mst_scan_cache && e && e.valid?
 return unless MST_COLLECTED_TYPES.include?(e.get_attribute(DICT,'element_type','').to_s)
 return if @mst_scan_cache_ids[e.persistent_id]
 @mst_scan_cache << e;@mst_scan_cache_ids[e.persistent_id]=true
end

def mst_scan_batch_active?;!!@mst_scan_batch_on;end

# Runs the block as one scan batch (nested calls join the outer batch). Pile type
# library sync requested during the batch runs once for real (the first request,
# which makes pre-existing metadata consistent exactly as before) and once more at
# the end; the per-pile requests in between are provably no-ops and are skipped.
def mst_scan_batch(model=Sketchup.active_model)
 return yield if @mst_scan_batch_on
 @mst_scan_batch_on=true;@mst_scan_cache=nil;@mst_scan_cache_ids={};@mst_type_sync_state=nil;@mst_def_cache=nil
 begin
  r=yield
  if @mst_type_sync_state==:pending
   @mst_type_sync_state=:flushing
   mst_sync_pile_type_library(model)
  end
  r
 ensure
  @mst_scan_batch_on=false;@mst_scan_cache=nil;@mst_scan_cache_ids={};@mst_type_sync_state=nil;@mst_def_cache=nil
  @mst_infill_children_cache=nil;@mst_jg_elements_cache=nil   # P5: jg_elements; v0.51.5 P4: kazık iç beton çocukları önbelleği (yalnız okuma batch'inde kurulur)
 end
end

# v0.51.5 P2: salt okuma ekran yenilemesi (Keşif, Metraj, Hakediş, durum rozetleri, Donatı, Proje, Model Kontrolü) tek model
# taraması. Açık bir batch varsa (yazma ya da okuma) ona katılır, durumunu değiştirmez; yoksa mst_scan_batch'i açar (bitince
# mst_scan_batch'in ensure'u durumu sıfırlar). Okuma batch'i boyunca kazık dizini (mst_pile_index_cache) aynı taramadan kurulur ve
# 1,5 s süre sınırı yerine batch sonuna kadar geçerlidir. Öğe ekleyen / silen / element_type değiştiren yollar sarılmaz.
def mst_read_batch(model=Sketchup.active_model)
 return yield if @mst_scan_batch_on
 @mst_read_batch_seq=(@mst_read_batch_seq||0)+1
 seq=@mst_read_batch_seq
 mst_scan_batch(model) do
  @mst_read_batch_on=seq
  begin
   yield
  ensure
   @mst_read_batch_on=nil
   @mst_infill_children_cache=nil;@mst_jg_elements_cache=nil   # v0.51.5 P4, P5
  end
 end
end

# Creation-time type sync request (add_pile_infill). Outside a batch: immediate, as before.
def mst_request_pile_type_sync(model=Sketchup.active_model)
 return mst_sync_pile_type_library(model) unless @mst_scan_batch_on
 if @mst_type_sync_state.nil?
  @mst_type_sync_state=:done_once
  mst_sync_pile_type_library(model)
 else
  @mst_type_sync_state=:pending
  0
 end
end

# Optional timing probe (off by default; enabled by the scale benchmark).
def mst_prof(key)
 return yield unless @mst_prof
 t=Process.clock_gettime(Process::CLOCK_MONOTONIC)
 begin
  yield
 ensure
  h=(@mst_prof[key.to_s]||={'sec'=>0.0,'calls'=>0})
  h['sec']+=Process.clock_gettime(Process::CLOCK_MONOTONIC)-t;h['calls']+=1
 end
end
def mst_prof_start;@mst_prof={};end
def mst_prof_stop;r=@mst_prof||{};@mst_prof=nil;r.each_value{|h|h['sec']=h['sec'].round(4)};r;end

def face_area_m2(face); face.area.to_f/(1.m*1.m); end
def head_beam_formwork_area(group)
 mst_hb_ents(group).grep(Sketchup::Face).sum{|f|f.get_attribute(DICT,'formwork',false) ? face_area_m2(f) : 0.0}   # v0.51.1: Component BK (dışarıdan alınmış) da
end

# v0.37.6 - Persist interactive BK formwork overrides across parametric rebuilds.
# The key describes the semantic/local face, not SketchUp's transient Face object.
def bk_formwork_face_key(face)
 kind=face.get_attribute(DICT,'formwork_type','').to_s
 n=face.normal
 case kind
 when 'LONG_SIDE'
  "LONG_SIDE_#{n.y >= 0 ? 'POS' : 'NEG'}"
 when 'END_FACE'
  "END_FACE_#{n.x >= 0 ? 'POS' : 'NEG'}"
 when 'BOTTOM'
  'BOTTOM'
 when 'RECESS_SLOPE'
  # Teeth/recess slopes are normally unique per beam end; local X normal keeps
  # start/end overrides stable when width/height changes rebuild the faces.
  "RECESS_SLOPE_#{n.x >= 0 ? 'POS' : 'NEG'}"
 else
  # Future-proof fallback for classified BK faces.
  "#{kind.empty? ? 'FACE' : kind}_#{n.x.round(3)}_#{n.y.round(3)}_#{n.z.round(3)}"
 end
end
# v0.51.5 K51 (ADR-0515 §10): aynı eski anahtarı paylaşan yüzler (ör. ana taban + diş tabanı) konumla ayrılır.
# => {face=>[konumlu, eski]}; konumlu "#{eski}@#{i}/#{n}" — aynı eski anahtarlı n yüzün yerel bounds.min [x,z,y] (mm) sırası.
# Uygulamada önce konumlu, yoksa eski anahtar okunur; yüz sayısı (n) değişirse eski anahtara düşer.
def bk_formwork_face_keys(group)
 out={}
 mst_hb_ents(group).grep(Sketchup::Face).group_by{|f|bk_formwork_face_key(f)}.each do |k,fs|
  fs.sort_by{|f|b=f.bounds.min;[(b.x.to_f*25.4).round,(b.z.to_f*25.4).round,(b.y.to_f*25.4).round]}.each_with_index{|f,i|out[f]=["#{k}@#{i}/#{fs.length}",k]}
 end
 out
end

def bk_formwork_override_map(group, capture_legacy=true)
 raw=group.get_attribute(DICT,'formwork_face_overrides','').to_s
 map={}
 begin
  parsed=JSON.parse(raw) unless raw.empty?
  map=parsed if parsed.is_a?(Hash)
 rescue
  map={}
 end
 if capture_legacy
  # Migration from v0.37.4/v0.37.5: existing face-level manual overrides are
  # captured before geometry is cleared, so the user's saved model is preserved.
  bk_formwork_face_keys(group).each do |f,(pos,_legacy)|   # v0.51.5 K51: yalnız konumlu anahtar yazılır
   ov=f.get_attribute(DICT,'formwork_manual_override','').to_s
   next unless ['include','exclude'].include?(ov)
   map[pos]=ov
  end
 end
 map
end

def bk_store_formwork_override_map(group,map)
 group.set_attribute(DICT,'formwork_face_overrides',JSON.generate(map))
end

def bk_apply_formwork_overrides(group,map,form_mat=nil)
 return head_beam_formwork_area(group) unless map.is_a?(Hash) && !map.empty?
 bk_formwork_face_keys(group).each do |f,(pos,legacy)|
  ov=(map.key?(pos) ? map[pos] : map[legacy]).to_s   # v0.51.5 K51: önce konumlu, yoksa eski anahtar
  next unless ['include','exclude'].include?(ov)
  flag=(ov=='include')
  f.set_attribute(DICT,'formwork',flag)
  f.set_attribute(DICT,'formwork_manual_override',ov)
  f.material=flag ? form_mat : nil
  f.back_material=nil
 end
 head_beam_formwork_area(group)
end
def active_head_beam(model)
 path=model.active_path
 return nil if path.nil? || path.empty?
 inst=path.last
 return inst if inst.respond_to?(:get_attribute) && inst.get_attribute(DICT,'element_type')=='head_beam'
 nil
end
def set_selected_faces_formwork(flag)
 model=Sketchup.active_model
 hb=active_head_beam(model)
 unless hb
  UI.messagebox("Önce bir başlık kirişine (BK) çift tıklayıp grup düzenleme moduna girin."); return
 end
 faces=model.selection.grep(Sketchup::Face)
 if faces.empty?
  UI.messagebox("Başlık kirişi (BK) içindesiniz; şimdi bir veya daha fazla yüzey seçin."); return
 end
 model.start_operation(flag ? 'Kalıba Dahil Et' : 'Kalıptan Çıkar',true)
 begin   # v0.51.5 K13: hata yolunda işlem açık kalmaz
 faces.each do |face|
  face.set_attribute(DICT,'formwork',flag)
  hex=hb.get_attribute(DICT,flag ? 'formwork_color':'concrete_color',flag ? '#F4B183':'#D9D9D9')
  mat=flag ? material_for(model,"MAG Kalıp #{hex}",hex) : nil
  face.material=mat; face.back_material=nil
 end
 new_area=head_beam_formwork_area(hb)
 hb.set_attribute(DICT,'formwork_area_m2',new_area)
 hb.set_attribute(DICT,'formwork_gross_area_m2',new_area)
 hb.set_attribute(DICT,'formwork_net_area_m2',[new_area-head_beam_pile_opening_area(hb),0.0].max)
 commit_with_dependencies(model)
 rescue => ex
  model.abort_operation;UI.messagebox("Kalıp yüzeyi güncellenemedi: #{ex.message}");return
 end
 UI.messagebox("#{faces.length} yüzey #{flag ? 'kalıba dahil edildi':'kalıptan çıkarıldı'}.\\nYeni BK kalıp alanı: #{format('%.2f',new_area)} m²")
end

# ===== v0.37.4 BK Interactive Formwork Face Override =====
class MSTBKFormworkFaceTool
 def initialize
  @model=Sketchup.active_model
 end
 def activate
  Sketchup.status_text='BK Kalıp Yüzeyi: yüzeye tıklayın = dahil/hariç değiştir | ESC = çıkış'
 end
 def deactivate(view)
  Sketchup.status_text=''
  view.invalidate if view
 end
 def onCancel(reason,view)
  @model.select_tool(nil)
 end
 def onMouseMove(flags,x,y,view)
  ph=view.pick_helper
  ph.do_pick(x,y)
  face=nil
  ph.count.times do |i|
   e=ph.leaf_at(i) rescue nil
   if e.is_a?(Sketchup::Face); face=e; break; end
  end
  view.tooltip = face ? 'BK yüzeyi — tıklayın: kalıp dahil/hariç' : 'Bir BK yüzeyi seçin'
 end
 def onLButtonDown(flags,x,y,view)
  hb=MarineStructuresTools.active_head_beam(@model)
  unless hb
   UI.messagebox("Önce Başlık Kirişi grubuna çift tıklayıp düzenleme moduna girin.\nArdından 'BK Yüzeyi Seç / Kalıp Toggle' düğmesine basın.")
   @model.select_tool(nil); return
  end
  # v0.51.5 K29: Component BK'da yüzler tanımdadır (hb.entities yok); çok kopyalı tanıma tek parça için yazılmaz
  if hb.is_a?(Sketchup::ComponentInstance) && hb.definition.count_instances>1
   UI.messagebox("Bu BK Component (ortak tanım, #{hb.definition.count_instances} parça). Tek parçanın kalıp yüzünü değiştirmek için önce parçayı ayırın (Make Unique).")
   @model.select_tool(nil); return
  end
  ph=view.pick_helper; ph.do_pick(x,y)
  face=nil
  ph.count.times do |i|
   e=ph.leaf_at(i) rescue nil
   if e.is_a?(Sketchup::Face) && MarineStructuresTools.mst_hb_ents(hb).include?(e); face=e; break; end
  end
  unless face
   UI.beep; Sketchup.status_text='BK içinde bir yüzeye tıklayın.'; return
  end
  old=face.get_attribute(MarineStructuresTools::DICT,'formwork',false) ? true : false
  flag=!old
  pos_key=MarineStructuresTools.bk_formwork_face_keys(hb)[face]   # K51: işlemden önce (yüz konumu değişmeden)
  @model.start_operation(flag ? 'BK Yüzeyi Kalıba Dahil Et' : 'BK Yüzeyi Kalıptan Çıkar',true);op=true
  face.set_attribute(MarineStructuresTools::DICT,'formwork',flag)
  face.set_attribute(MarineStructuresTools::DICT,'formwork_manual_override',flag ? 'include' : 'exclude')
  ovmap=MarineStructuresTools.bk_formwork_override_map(hb,false)
  ovmap[pos_key ? pos_key[0] : MarineStructuresTools.bk_formwork_face_key(face)]=flag ? 'include' : 'exclude'   # v0.51.5 K51: konumlu anahtar
  MarineStructuresTools.bk_store_formwork_override_map(hb,ovmap)
  if flag
   hex=hb.get_attribute(MarineStructuresTools::DICT,'formwork_color','#66BB6A')
   face.material=MarineStructuresTools.material_for(@model,"MAG Kalıp #{hex}",hex)
  else
   face.material=nil
  end
  face.back_material=nil
  gross=MarineStructuresTools.head_beam_formwork_area(hb)
  opening=MarineStructuresTools.head_beam_pile_opening_area(hb)
  net=[gross-opening,0.0].max
  hb.set_attribute(MarineStructuresTools::DICT,'formwork_area_m2',gross)
  hb.set_attribute(MarineStructuresTools::DICT,'formwork_gross_area_m2',gross)
  hb.set_attribute(MarineStructuresTools::DICT,'formwork_net_area_m2',net)
  MarineStructuresTools.commit_with_dependencies(@model);op=false   # v0.51.5 K11: commit_with_dependencies kapatır (ikinci commit yok)
  state=flag ? 'KALIBA DAHİL' : 'KALIPTAN HARİÇ'
  Sketchup.status_text="#{state} • Yüzey #{format('%.2f',MarineStructuresTools.face_area_m2(face))} m² • Brüt #{format('%.2f',gross)} m² • Net #{format('%.2f',net)} m² • ESC=çıkış"
  view.invalidate
 rescue => e
  (@model.abort_operation if op) rescue nil
  UI.messagebox("BK yüzey yönetimi hatası:\n#{e.message}")
 end
end

def activate_bk_formwork_face_tool
 model=Sketchup.active_model
 unless active_head_beam(model)
  UI.messagebox("Önce düzenlemek istediğiniz Başlık Kirişi'ne çift tıklayıp grup içine girin.\nSonra bu düğmeye tekrar basın ve yüzeylere tıklayın.")
  return
 end
 model.select_tool(MSTBKFormworkFaceTool.new)
end


# ===== v0.37.5 Universal Interactive Formwork Face Toggle =====
def mst_formwork_owner(model)
  supported=%w[head_beam flat_precast channel_precast crane_precast deck_slab curb crown_wall]
  path=(model.active_path || []).reverse
  path.find{|e| e.respond_to?(:get_attribute) && supported.include?(e.get_attribute(DICT,'element_type','').to_s)}
end

def mst_formwork_label(type)
  {'head_beam'=>'BK','flat_precast'=>'Prekast','channel_precast'=>'Prekast','crane_precast'=>'Prekast','deck_slab'=>'Döşeme','curb'=>'Tretuvar','crown_wall'=>'Kronman'}[type] || 'Eleman'
end

def mst_marked_formwork_area(entities)
  total=0.0
  entities.each do |e|
    if e.is_a?(Sketchup::Face)
      total += face_area_m2(e) if e.get_attribute(DICT,'formwork',false) ? true : false
    elsif e.is_a?(Sketchup::Group)
      total += mst_marked_formwork_area(e.entities)
    elsif e.is_a?(Sketchup::ComponentInstance)
      total += mst_marked_formwork_area(e.definition.entities)
    end
  end
  total
end

class MSTUniversalFormworkFaceTool
 def initialize; @model=Sketchup.active_model; end
 def activate; Sketchup.status_text='Kalıp Yüzeyi Toggle: yüzeye tıklayın = dahil/hariç | ESC = çıkış'; end
 def deactivate(view); Sketchup.status_text=''; view.invalidate if view; end
 def onCancel(reason,view); @model.select_tool(nil); end
 def onMouseMove(flags,x,y,view)
  ph=view.pick_helper; ph.do_pick(x,y); face=nil
  ph.count.times{|i| e=ph.leaf_at(i) rescue nil; if e.is_a?(Sketchup::Face); face=e; break; end}
  view.tooltip=face ? 'Yüzeye tıklayın: kalıp dahil/hariç' : 'Bir BIM elemanı yüzeyi seçin'
 end
 def onLButtonDown(flags,x,y,view)
  owner=MarineStructuresTools.mst_formwork_owner(@model)
  unless owner
   UI.messagebox("Önce düzenlemek istediğiniz BK / Prekast / Döşeme / Tretuvar / Kronman elemanına çift tıklayıp düzenleme moduna girin.\nSonra 🎯 Yüzeyi Seç / Kalıp Toggle düğmesine basın.")
   @model.select_tool(nil); return
  end
  if owner.is_a?(Sketchup::ComponentInstance)
   UI.messagebox("Bu eleman Component (ortak tanım, #{owner.definition.instances.length} parça). Tek parçanın kalıp yüzünü değiştirmek için önce Prekast sayfasında 'Group'a Çevir' kullanın.")
   @model.select_tool(nil); return
  end
  ph=view.pick_helper; ph.do_pick(x,y); face=nil
  ph.count.times{|i| e=ph.leaf_at(i) rescue nil; if e.is_a?(Sketchup::Face); face=e; break; end}
  unless face; UI.beep; return; end
  type=owner.get_attribute(MarineStructuresTools::DICT,'element_type','').to_s
  old=face.get_attribute(MarineStructuresTools::DICT,'formwork',false) ? true : false; flag=!old
  @model.start_operation(flag ? 'Yüzeyi Kalıba Dahil Et' : 'Yüzeyi Kalıptan Çıkar',true);op=true
  face.set_attribute(MarineStructuresTools::DICT,'formwork',flag)
  face.set_attribute(MarineStructuresTools::DICT,'formwork_manual_override',flag ? 'include' : 'exclude')
  if flag
   hex=owner.get_attribute(MarineStructuresTools::DICT,'formwork_color','#66A9E8')
   face.material=MarineStructuresTools.material_for(@model,"MAG Kalıp #{hex}",hex)
  else
   face.material=nil
  end
  face.back_material=nil
  if type=='head_beam'
   gross=MarineStructuresTools.head_beam_formwork_area(owner); opening=MarineStructuresTools.head_beam_pile_opening_area(owner); net=[gross-opening,0.0].max
   owner.set_attribute(MarineStructuresTools::DICT,'formwork_area_m2',gross); owner.set_attribute(MarineStructuresTools::DICT,'formwork_gross_area_m2',gross); owner.set_attribute(MarineStructuresTools::DICT,'formwork_net_area_m2',net)
  else
   gross=MarineStructuresTools.mst_marked_formwork_area(owner.entities)
   owner.set_attribute(MarineStructuresTools::DICT,'formwork_area_m2',gross); owner.set_attribute(MarineStructuresTools::DICT,'formwork_gross_area_m2',gross); owner.set_attribute(MarineStructuresTools::DICT,'formwork_net_area_m2',gross)
  end
  MarineStructuresTools.commit_with_dependencies(@model);op=false   # v0.51.5 K11: tek commit
  Sketchup.status_text="#{MarineStructuresTools.mst_formwork_label(type)} • #{flag ? 'KALIBA DAHİL' : 'KALIPTAN HARİÇ'} • Kalıp #{format('%.2f',gross)} m² • ESC=çıkış"
  view.invalidate
 rescue => e
  (@model.abort_operation if op) rescue nil; UI.messagebox("Kalıp yüzey yönetimi hatası:\n#{e.message}")
 end
end

def activate_universal_formwork_face_tool
 model=Sketchup.active_model
 unless mst_formwork_owner(model)
  UI.messagebox("Önce düzenlemek istediğiniz BK / Prekast / Döşeme / Tretuvar / Kronman elemanına çift tıklayıp grup içine girin.\nSonra bu düğmeye tekrar basın ve yüzeylere tıklayın.")
  return
 end
 model.select_tool(MSTUniversalFormworkFaceTool.new)
end

def head_beam_pile_opening_area(group)
 stored=group.get_attribute(DICT,'pile_opening_area_m2',nil)
 return 0.0 if stored.nil?
 # v0.51.5 08-R6: açıklık alt yüzdedir; alt yüzlerin (BOTTOM) hiçbiri kalıpta değilse brütte yoktur, düşülmez.
 # Bir kısmı kalıptaysa eski kural (tamamı düşülür) — açıklığın hangi yüzde olduğu ayrıca belirlenmez.
 bot=mst_hb_ents(group).grep(Sketchup::Face).select{|f|f.get_attribute(DICT,'formwork_type','').to_s=='BOTTOM'}
 return 0.0 if !bot.empty? && bot.none?{|f|f.get_attribute(DICT,'formwork',false)}
 stored.to_f
end
# v0.51.5: eğik kazığın yatay düzlemdeki açıklığı elips: π/4·d·d/cosθ (cosθ = 1/√(1+r²)); düşey kazıkta daire
def mst_pile_opening_m2(d_mm,r=0.0)
 Math::PI*(d_mm.to_f/1000.0)**2/4.0*Math.sqrt(1.0+r.to_f**2)
end
def mst_pile_opening_ratio(p)
 p.get_attribute(DICT,'orientation_mode','').to_s.upcase=='BATTERED' ? pile_batter_ratio(p.get_attribute(DICT,'batter_ratio',0)) : 0.0
end
def head_beam_gross_formwork_area(group)
 head_beam_formwork_area(group)
end
def head_beam_net_formwork_area(group)
 # v0.50: VK / BBK alın teması ve menfez açıklıkları BK kalıbından düşülür
 ex=((respond_to?(:mst_vk_contact_m2) ? mst_vk_contact_m2(group) : 0.0)+(respond_to?(:mst_hb_culvert_form_deduct) ? mst_hb_culvert_form_deduct(group) : 0.0)) rescue 0.0
 [head_beam_gross_formwork_area(group)-head_beam_pile_opening_area(group)-ex,0.0].max
end

# ===== v0.47 BK1 — kazığın BK içine giren hacmi BK betonundan düşülür =====
# Kazık üst kotu BK alt kotunun üstündeyse: dış çap alanı × gömülme boyu (eğik kazıkta yatay kesit A·√(1+r²)).
# Değer saklanmaz; her okumada kazığın güncel kotundan hesaplanır. Kazık içi beton kazık pozunda kalır → çift sayım yok.
# BK geometrisi ve 'concrete_volume_m3' (brüt) değişmez; metraj / BOQ / hakediş / rapor net değeri okur.
def mst_pile_index_by_id
 mst_pile_index_cache[:idx]
end
# v0.51.5 P1: aynı taramadan persistent_id → kazık dizini (yalnız steel_pipe_pile). find_entity_by_persistent_id SketchUp'ta
# çağrı başına ≈25 ms ölçüldü; mst_bk_connected_piles önce bu dizinden çözer. Okuma işlevi; model yazımı yok.
def mst_pile_index_by_pid
 mst_pile_index_cache[:pidx]
end
def mst_pile_index_cache
 model=Sketchup.active_model
 c=@mst_pile_idx_cache
 now=Time.now.to_f
 rb=@mst_read_batch_on   # P2: okuma batch'inde dizin batch boyunca geçerli; dışında eski 1,5 s kuralı
 return c if c && c[:pidx] && c[:model]==model.object_id && (rb ? c[:rb]==rb : (c[:rb].nil? && now-c[:t]<1.5))
 all=[];collect_elements(model.entities,all)
 idx=Hash.new{|h,k|h[k]=[]};pidx={}
 all.each do |e|
  next unless e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'
  idx[e.get_attribute(DICT,'pile_id','').to_s] << e
  pidx[e.persistent_id] ||= e
 end
 @mst_pile_idx_cache={model:model.object_id,t:now,idx:idx,pidx:pidx,rb:rb}
end
def mst_bk_connected_piles(b)
 model=Sketchup.active_model
 pids=b.get_attribute(DICT,'connected_pile_persistent_ids','').to_s.split(/[,\s]+/).map(&:to_i).reject{|x|x<=0}.uniq
 if !pids.empty? && model.respond_to?(:find_entity_by_persistent_id)
  # P1: dizinde olmayan ya da dizindeki nesnesi geçersiz PID için eski arama (yeni / iç içe / Geri Al sonrası kazık); dizin
  # kurulamazsa tüm PID'ler eski aramaya düşer (sonuç eskisiyle aynı). Sonraki süzgeç ve ID yolu değişmedi.
  pidx=(mst_pile_index_by_pid rescue {})
  out=pids.map{|pid|e=pidx[pid];(e && e.valid?) ? e : (model.find_entity_by_persistent_id(pid) rescue nil)}.compact.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
  return out if out.length==pids.length
 end
 ids=b.get_attribute(DICT,'connected_pile_ids','').to_s.split(',').map(&:strip).reject(&:empty?).uniq
 return [] if ids.empty?
 ano=b.get_attribute(DICT,'ano','').to_s
 idx=mst_pile_index_by_id
 ids.map do |id|
  cs=idx.key?(id) ? idx[id] : []
  if cs.length>1 && !ano.empty?
   same=cs.select{|p|[p.get_attribute(DICT,'ano','').to_s,p.get_attribute(DICT,'structure','').to_s].include?(ano)}
   cs=same unless same.empty?
  end
  if cs.length>1 && b.respond_to?(:bounds)
   near=cs.select{|p|(p.bounds.intersect(b.bounds).valid? rescue false)}
   cs=near unless near.empty?
  end
  cs.first
 end.compact.uniq
end
def mst_bk_pile_embed(b)
 bot=b.get_attribute(DICT,'bottom_elevation_m',nil)
 return {volume_m3:0.0,items:[]} if bot.nil? || bot.to_s.strip.empty?
 bot=bot.to_f
 top=b.get_attribute(DICT,'top_elevation_m',nil);top=(top.nil? || top.to_s.strip.empty?) ? bot+b.get_attribute(DICT,'height_m',0).to_f : top.to_f
 items=[]
 # v0.51.5 K50 (ADR-0515 §5): gömülme kazık eksenindeki yerel taban kotundan (diş / taban bölgesi derinliği dahil).
 # Kazık konumu: kazık grubunun orijini (kazık başı merkezi) BK yerel çerçevesinde; x = BK başından boy (m).
 # Kazık BK ile aynı kapta değilse, BK Component ya da çok akslı (kutu) ise derinlik 0 (eski kural).
 zh=nil;zlen=0.0
 if b.is_a?(Sketchup::Group) && b.get_attribute(DICT,'head_beam_mode','').to_s!='multi_axis' && respond_to?(:mst_hb_bottom_depth)
  zh=mst_attr_hash(b);zlen=zh['length_m'].to_f
 end
 mst_bk_connected_piles(b).each do |p|
  pt=p.get_attribute(DICT,'top_elevation_m',nil);next if pt.nil? || pt.to_s.strip.empty?
  dep=0.0;ax=nil;ay=nil;oz=nil;derr=nil
  # ADR-0515 G3-#13: eklenti dışı (tanıtılmış) kazıkta orijin kazık başı merkezi sayılmaz → derinlik 0 (eski kural)
  ext=p.get_attribute(DICT,'registered_external',false);ext=(ext==true || ext.to_s=='true')
  if zh && zlen>0 && p.parent==b.parent && !ext
   begin   # derinlik hatası yalnız bu kazığı etkiler (dep=0, depth_error); BK'nın tüm düşümü sıfırlanmaz
    lp=p.transformation.origin.transform(b.transformation.inverse)
    ax=lp.x.to_m;ay=lp.y.to_m;oz=p.transformation.origin.z.to_m
    dep=mst_hb_bottom_depth(zh,zlen,ax)
   rescue => dex
    dep=0.0;derr=dex.message.to_s
   end
  end
  emb=[pt.to_f,top].min-(bot-dep);next if emb<=1e-6
  d=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0;next if d<=0
  r=p.get_attribute(DICT,'orientation_mode','').to_s.upcase=='BATTERED' ? pile_batter_ratio(p.get_attribute(DICT,'batter_ratio',0)) : 0.0
  v=Math::PI*d*d/4.0*emb*Math.sqrt(1.0+r*r)
  it={pile_id:p.get_attribute(DICT,'pile_id','').to_s,pid:p.persistent_id,embed_m:emb,diameter_mm:d*1000.0,batter:r,volume_m3:v,bottom_depth_m:dep,axis_a_m:(derr ? nil : ax)}
  it[:depth_error]=derr if derr
  if ay && !derr
   it[:axis_y_m]=ay;it[:origin_z_m]=oz;it[:width_m]=zh['width_m'].to_f;it[:pile_top_m]=pt.to_f
  end
  items << it
 end
 {volume_m3:items.sum{|x|x[:volume_m3]},items:items}
rescue => ex   # G3-#13: hata görünür (Model Kontrolü ERROR); BK betonu brüt alınır
 {volume_m3:0.0,items:[],error:ex.message.to_s}
end
def head_beam_gross_concrete(b)
 b.get_attribute(DICT,'concrete_volume_m3',b.get_attribute(DICT,'volume_m3',0)).to_f
end
def head_beam_pile_embed_volume(b);mst_bk_pile_embed(b)[:volume_m3].to_f;end
def head_beam_net_concrete(b)
 g=head_beam_gross_concrete(b)
 cv=(respond_to?(:mst_hb_culvert_void) ? mst_hb_culvert_void(b) : 0.0) rescue 0.0   # v0.50 MF1 menfez boşluğu
 [g-head_beam_pile_embed_volume(b)-cv,0.0].max
end
# rapor: BK betonu brüt / kazık gömülme düşümü / net (Excel'e de aynen geçer)
def mst_bk_embed_report_html(bs)
 return '' if bs.empty?
 rows=bs.map{|b|[b,mst_bk_pile_embed(b)]}.select{|_,x|x[:volume_m3]>1e-9}
 if rows.empty?
  return "<div class='note'>BK beton hacmi net: kazıklar BK alt kotunda bitiyor, BK içine giren kazık yok (gömülme düşümü 0).</div>"
 end
 tr=rows.sort_by{|b,_|b.get_attribute(DICT,'head_beam_id',b.name).to_s}.map do |b,x|
  g=head_beam_gross_concrete(b)
  "<tr><td>#{html_escape(b.get_attribute(DICT,'head_beam_id',b.name).to_s)}</td><td>#{x[:items].length}</td><td>#{html_escape(x[:items].map{|i|"#{i[:pile_id]} #{format('%.3f',i[:embed_m])} m"}.join(', '))}</td><td>#{format('%.3f',g)} m³</td><td>-#{format('%.3f',x[:volume_m3])} m³</td><td><b>#{format('%.3f',[g-x[:volume_m3],0].max)} m³</b></td></tr>"
 end.join
 tg=rows.sum{|b,_|head_beam_gross_concrete(b)};td=rows.sum{|_,x|x[:volume_m3]}
 "<h3 style='margin-top:18px'>BK Betonu — Kazık Gömülme Düşümü</h3><table><tr><th>BK</th><th>Gömülü Kazık</th><th>Kazık / Gömülme Boyu</th><th>Brüt Beton</th><th>Kazık Hacmi</th><th>Net Beton</th></tr>#{tr}<tr class='total'><td>TOPLAM</td><td>#{rows.sum{|_,x|x[:items].length}}</td><td>-</td><td>#{format('%.3f',tg)} m³</td><td>-#{format('%.3f',td)} m³</td><td>#{format('%.3f',[tg-td,0].max)} m³</td></tr></table>"+
 "<div class='note'>Kazığın BK içinde kalan hacmi (dış çap × gömülme boyu, eğik kazıkta eğim dahil) BK betonundan düşülür; kazık içi beton kazık pozunda kalır.</div>"
end



# ===== v0.33.0 Rebar BIM / Head Beam =====
def rebar_unit_kg_m(d_mm)
  d_mm.to_f * d_mm.to_f / 162.0
end

# v0.38 RB1 — reinforcement bending rules, applied automatically by bar type.
# Sources: TS 500:2000 (standard hooks: inside bend diameter ≥ 6Ø; 90° hook straight part ≥ 12Ø;
# stirrup hook inside diameter ≥ 4Øw, 135° hooks), TBDY 2018 (135° stirrup hooks; 10Øw / 100 mm
# straight end recommended) and TS EN 1992-1-1 Table 8.1N (mandrel 4Ø for Ø ≤ 16, 7Ø for Ø > 16).
# The larger value of the sources is used.
# v0.38 RB2 — every bar diameter has its own colour (BK bars, stirrups, pile cages):
# the material is named "MST Donatı Ø<d>", so bars of one diameter are easy to tell apart and pick.
MST_REBAR_DIA_COLORS={8=>'#8E44AD',10=>'#2E86C1',12=>'#17A589',14=>'#28B463',16=>'#F4D03F',18=>'#F39C12',
 20=>'#D35400',22=>'#C0392B',25=>'#E91E63',28=>'#795548',32=>'#1F3A93',36=>'#00ACC1',40=>'#212121'}.freeze
def mst_rebar_dia_hex(d)
 k=d.to_f.round
 return MST_REBAR_DIA_COLORS[k] if MST_REBAR_DIA_COLORS[k]
 # any other diameter: a stable hue from the diameter (never one of the table colours by name)
 h=(k*47)%360/60.0;c=0.75*0.9;x=c*(1-((h%2)-1).abs);m=0.9-c
 r,g,b=[[c,x,0],[x,c,0],[0,c,x],[0,x,c],[x,0,c],[c,0,x]][h.floor%6]
 format('#%02X%02X%02X',((r+m)*255).round,((g+m)*255).round,((b+m)*255).round)
end
def mst_rebar_dia_material(model,d)
 material_for(model,"MST Donatı Ø#{d.to_f.round}",mst_rebar_dia_hex(d))
end
# paints one bar / stirrup group (stirrups are wires: their edges get the material too)
def mst_rebar_paint!(g,d=nil)
 return unless g && g.valid?
 d||=g.get_attribute(DICT,'diameter_mm',0).to_f
 return unless d.to_f>0
 mat=mst_rebar_dia_material(g.model,d)
 g.material=mat
 g.entities.grep(Sketchup::Edge).each{|e|e.material=mat} if g.get_attribute(DICT,'element_type','').to_s=='rebar_stirrup'
 mat
end
def mst_pile_cage_dia(rg)
 d=rg.get_attribute(DICT,'long_dia_mm',nil)
 return d.to_f if d
 sig=(JSON.parse(rg.get_attribute(DICT,'pile_rebar_sig','[]').to_s) rescue [])
 (JSON.parse(sig[1].to_s)['long_dia_mm'].to_f rescue 0.0)
end
# recolours every existing BK bar / stirrup and pile cage in the model (no geometry change)
def mst_rebar_paint_all!(model)
 n=Hash.new(0)
 model.definitions.each do |df|
  df.entities.grep(Sketchup::Group).each do |g|
   case g.get_attribute(DICT,'element_type','').to_s
   when 'rebar_bar','rebar_stirrup'
    d=g.get_attribute(DICT,'diameter_mm',0).to_f;next unless d>0
    mst_rebar_paint!(g,d);n[d.round]+=1
   when 'pile_rebar_set'
    d=mst_pile_cage_dia(g);next unless d>0
    g.material=mst_rebar_dia_material(model,d);n[-d.round]+=1
   end
  end
 end
 n
end
def mst_rebar_paint_all_ui(dialog=@d)
 model=Sketchup.active_model
 model.start_operation('MST Donatıları Çapa Göre Renklendir',true)
 begin
  n=mst_rebar_paint_all!(model)
  model.commit_operation
 rescue=>ex
  model.abort_operation;UI.messagebox("Renklendirilemedi:\n#{ex.message}");return
 end
 bk=n.select{|k,_|k>0}.sort.map{|k,v|"Ø#{k}: #{v} çubuk/etriye"}
 pl=n.select{|k,_|k<0}.sort_by{|k,_|-k}.map{|k,v|"Ø#{-k}: #{v} kazık kafesi"}
 UI.messagebox((["Donatılar çapa göre renklendirildi (tek Geri Al)."]+bk+pl).join("\n")+"\n\nEtriye ve spiral tel çizgidir: rengini görmek için Pencere → Stiller → Düzenle → Kenar → Renk: Malzemeye göre.")
end

MST_REBAR_BEND_RULES={
 'standard'=>'TS 500:2000 + TBDY 2018 + TS EN 1992-1-1 Tablo 8.1N (büyük olan)',
 'main_small_max_mm'=>16.0,'main_mandrel_small'=>6.0,'main_mandrel_large'=>7.0,   # büküm iç çapı D = k × Ø (boyuna / U / gönye)
 'stirrup_mandrel'=>4.0,                                                         # etriye büküm iç çapı D = 4 × Øw
 'hook90_min_straight'=>12.0,                                                    # 90° kanca büküm sonrası düz boy ≥ 12Ø
 'stirrup_hook_angle_deg'=>135.0,'stirrup_hook_ext'=>10.0,'stirrup_hook_ext_min_m'=>0.10,  # 135°, max(10Øw, 100 mm)
 'shapes'=>[['BK uç gönyesi (alt/üst donatı)','90°','D = 6Ø (Ø≤16) / 7Ø (Ø>16); düz kol ≥ 12Ø'],
            ['Cep gönyesi (üst donatı, kanal altına)','90°','D = 6Ø / 7Ø'],
            ['Cebi saran U donatı','4 × 90°','D = 6Ø / 7Ø'],
            ['Etriye köşeleri','90°','D = 4Øw'],
            ['Etriye kancaları','2 × 135°','D = 4Øw; düz uç max(10Øw, 100 mm)'],
            ['Kanal altı düz çubuk, gövde donatısı','—','büküm yok']]
}.freeze

def mst_bend_inside_dia_m(dmm,stirrup=false)
 r=MST_REBAR_BEND_RULES
 k=stirrup ? r['stirrup_mandrel'] : (dmm.to_f<=r['main_small_max_mm'] ? r['main_mandrel_small'] : r['main_mandrel_large'])
 k*dmm.to_f/1000.0
end

# centre-line radius of a bend
def mst_bend_radius_m(dmm,stirrup=false)
 mst_bend_inside_dia_m(dmm,stirrup)/2.0+dmm.to_f/2000.0
end

# Developed (centre-line) length of a polyline with rounded corners: straight parts + arcs.
# pts: [[x,y,z],...] (m); r: bend radius. A corner on a short leg gets a smaller radius
# (tangent length ≤ half of each adjacent leg). Returns [length, arc_total, bends].
def mst_bent_path(pts,r)
 sub=->(p,q){[q[0]-p[0],q[1]-p[1],q[2]-p[2]]};nrm=->(v){Math.sqrt(v[0]**2+v[1]**2+v[2]**2)}
 segs=pts.each_cons(2).map{|p,q|nrm.(sub.(p,q))}
 tot=segs.sum;arcs=[]
 (1...pts.length-1).each do |i|
  a=sub.(pts[i-1],pts[i]);b=sub.(pts[i],pts[i+1]);la=nrm.(a);lb=nrm.(b)
  next if la<1e-9 || lb<1e-9
  cs=(a[0]*b[0]+a[1]*b[1]+a[2]*b[2])/(la*lb);th=Math.acos([[cs,1.0].min,-1.0].max)
  next if th<1e-6
  t=[r*Math.tan(th/2),la/2,lb/2].min;rr=t/Math.tan(th/2)
  tot-=2*t-rr*th;arcs << [i,t,rr,th]
 end
 [tot,arcs.sum{|_,_,rr,th|rr*th},arcs]
end

# RB1.1: centre line with the rounded bends sampled (≤ 15° per step) — used to draw one
# continuous swept bar and by the checks. pts in metres.
def mst_bent_polyline(pts,r,step=Math::PI/12)
 return pts.map(&:dup) if pts.length<3
 _,_,arcs=mst_bent_path(pts,r);by={};arcs.each{|i,t,rr,th|by[i]=[t,rr,th]}
 sub=->(p,q){[q[0]-p[0],q[1]-p[1],q[2]-p[2]]};nrm=->(v){l=Math.sqrt(v.sum{|x|x*x});v.map{|x|x/l}}
 out=[pts[0].dup]
 (1...pts.length-1).each do |i|
  unless by[i] then out << pts[i].dup;next end
  t,rr,th=by[i];ua=nrm.(sub.(pts[i-1],pts[i]));ub=nrm.(sub.(pts[i],pts[i+1]))
  p1=pts[i].zip(ua).map{|q,x|q-x*t}
  dt=ua.zip(ub).sum{|m,n|m*n};w=nrm.(ub.zip(ua).map{|x,y|x-y*dt})
  cen=p1.zip(w).map{|q,x|q+x*rr};n=[(th/step).ceil,2].max
  (0..n).each{|k|f=th*k/n;out << cen.each_index.map{|j|cen[j]-w[j]*rr*Math.cos(f)+ua[j]*rr*Math.sin(f)}}
 end
 out << pts[-1].dup
 out
end

# v0.38 BKR1 — BK rebar parameters are stored on the BK ('hb_rebar_json'), so the
# rebar can be regenerated whenever the BK geometry changes (single / bulk edit).
def mst_hb_local_frame(hb,len_attr)
 pts=hb.entities.grep(Sketchup::Face).flat_map{|f|f.vertices.map(&:position)}
 return nil if pts.empty?
 xs=pts.map{|q|q.x.to_f/39.37007874015748};ys=pts.map{|q|q.y.to_f/39.37007874015748};zs=pts.map{|q|q.z.to_f/39.37007874015748}
 dx=xs.max-xs.min;dy=ys.max-ys.min;dz=zs.max-zs.min
 ax=((dy-len_attr).abs+1e-6<(dx-len_attr).abs) ? :y : :x
 {'o'=>[xs.min,ys.min,zs.min],'ax'=>ax,'len'=>(ax==:x ? dx : dy),'wid'=>(ax==:x ? dy : dx),'hei'=>dz}
end

# v0.38 BKR2 — BK rebar: count OR spacing per layer, end hooks (gönye), and a
# two-way top+bottom mesh without stirrups for dolphin pile caps (auto-detected).
def mst_hb_rebar_params(data)
 num=->(k,d){v=data[k].to_s.strip.tr(',','.');v.empty? ? d : Float(v) rescue d}
 lay=->(pre,dflt_n){mode=data["#{pre}_mode"].to_s.upcase=='SPACING' ? 'SPACING' : 'COUNT'
  {'mode'=>mode,'count'=>[num.("#{pre}_count",dflt_n).to_i,0].max,'spacing_mm'=>[num.("#{pre}_spacing_mm",150.0),50.0].max,'dia_mm'=>num.("#{pre}_dia_mm",25.0)}}
 kind=data['kind'].to_s.upcase;kind='AUTO' unless %w[BEAM CAP].include?(kind)
 {'schema'=>2,'kind'=>kind,'cover_mm'=>[num.('cover_mm',50.0),20.0].max,
  'top'=>lay.('top',4),'bottom'=>lay.('bottom',4),
  'side_count_each'=>[num.('side_count_each',0).to_i,0].max,'side_dia_mm'=>num.('side_dia_mm',16.0),
  'side_mode'=>(data['side_mode'].to_s.upcase=='SPACING' ? 'SPACING' : 'COUNT'),'side_spacing_mm'=>[num.('side_spacing_mm',200.0),50.0].max,
  'stirrup_dia_mm'=>num.('stirrup_dia_mm',12.0),'stirrup_spacing_mm'=>[num.('stirrup_spacing_mm',150.0),50.0].max,
  'stirrup_legs'=>[[num.('stirrup_legs',2).to_i,2].max,12].min,   # v0.49 ET1: kol sayısı (2 = tek etriye, 4 = dış + 1 iç …)
  'chair_on'=>data['chair_on'].to_s!='0','chair_dia_mm'=>num.('chair_dia_mm',14.0),'chair_spacing_mm'=>[num.('chair_spacing_mm',1000.0),300.0].max,   # v0.49 SH1 dolfen sehpası
  'hook_cm'=>[num.('hook_cm',0.0),0.0].max}.merge(mst_hb_rebar_params_v50(data,num,lay))
end

# v0.50 — BK donatısı ekleri (hepsi varsayılan kapalı; eski BK'lar aynen çizilir)
#  ET2 yan yana dar etriye (Ege BK3), CZ1 çiroz (İGSAŞ Ø12/60), BN1 bant (2. kademe) üst donatısı + şapka etriye,
#  VK1 boyuna donatının BK'ya ankrajı (×Ø, VK / BBK), DG1 dolfen yan yüz gönyeli, MF1 menfez takviyesi, TB1 alçak taban bölgesi donatısı
def mst_hb_rebar_params_v50(data,num,lay)
 bt=lay.('band_top',6);bt['dia_mm']=num.('band_top_dia_mm',25.0)
 {'stirrup_layout'=>(data['stirrup_layout'].to_s.upcase=='SIDE' ? 'SIDE' : 'NESTED'),
  'side_n'=>[[num.('side_n',2).to_i,1].max,12].min,'side_w_mm'=>[num.('side_w_mm',0.0),0.0].max,'side_outer'=>data['side_outer'].to_s=='1',
  'ciroz_on'=>data['ciroz_on'].to_s=='1','ciroz_dia_mm'=>num.('ciroz_dia_mm',12.0),'ciroz_spacing_mm'=>[num.('ciroz_spacing_mm',600.0),100.0].max,
  'band_on'=>data['band_on'].to_s=='1','band_h_m'=>[num.('band_h_m',0.35),0.0].max,'band_w_m'=>[num.('band_w_m',0.0),0.0].max,'band_top'=>bt,
  'hat_dia_mm'=>num.('hat_dia_mm',16.0),'hat_spacing_mm'=>[num.('hat_spacing_mm',150.0),50.0].max,'hat_leg_m'=>[num.('hat_leg_m',0.0),0.0].max,
  'end_anchor_d'=>num.('end_anchor_d',-1.0),   # −1 = proje bindirme boyu (×Ø); yalnız VK / BBK'da
  'side_style'=>(data['side_style'].to_s.upcase=='GONYE' ? 'GONYE' : 'STRAIGHT'),
  'culvert_trim_dia_mm'=>num.('culvert_trim_dia_mm',16.0),'culvert_trim_n'=>[num.('culvert_trim_n',2).to_i,0].max,
  'zone_bars'=>data['zone_bars'].to_s!='0'}
end

# Old (BKR1) stored parameters -> schema 2.
def mst_hb_rebar_params_upgrade(p)
 return p if p['schema'].to_i==2
 mst_hb_rebar_params({'kind'=>'BEAM','cover_mm'=>p['cover_mm'],'top_mode'=>'COUNT','top_count'=>p['top_count'],'top_dia_mm'=>p['top_dia_mm'],
  'bottom_mode'=>'COUNT','bottom_count'=>p['bottom_count'],'bottom_dia_mm'=>p['bottom_dia_mm'],'side_count_each'=>p['side_count_each'],
  'side_dia_mm'=>p['side_dia_mm'],'stirrup_dia_mm'=>p['stirrup_dia_mm'],'stirrup_spacing_mm'=>p['stirrup_spacing_mm'],'hook_cm'=>0})
end

def mst_hb_system(hb,model=Sketchup.active_model)
 s=hb.get_attribute(DICT,'system','').to_s.upcase
 return s unless s.empty?
 name=hb.get_attribute(DICT,'structure','').to_s;name=hb.get_attribute(DICT,'ano','').to_s if name.empty?
 %w[DOLFEN ISKELE RIHTIM].find{|sys|(mst_structures_for_system(sys,model) rescue []).map(&:to_s).include?(name)}.to_s
end

# CAP = dolphin pile cap (plate-like, in a DOLFEN structure): two-way mesh, no stirrups.
def mst_hb_rebar_kind(hb,p,len,wid)
 return p['kind'] unless p['kind']=='AUTO'
 plate=wid>=3.0 || (len>0 && wid/len>=0.4)
 (mst_hb_system(hb)=='DOLFEN' && plate) ? 'CAP' : 'BEAM'
end

# Bar positions across a free width w (m) for a layer with bar dia d (mm).
def mst_hb_layer_positions(w,cover,lay)
 d=lay['dia_mm'].to_f/1000.0;a=cover+d/2.0;b=w-cover-d/2.0
 return [] if b<a || d<=0
 n=lay['mode']=='SPACING' ? ((b-a)/(lay['spacing_mm'].to_f/1000.0)).floor+1 : lay['count'].to_i
 return [] if n<=0
 n==1 ? [w/2.0] : (0...n).map{|i|a+(b-a)*i/(n-1).to_f}
end

# v0.49 SH1 — dolfen başlığı sehpaları (Π, BK köşesinden m: a = boy, c = en, z): alt hasırın üst katının üstüne oturur
# (ayaklar boyuna), üst hasırın alt katını taşır (üst kol boyuna). Ceplerin bandında konmaz. Kol 30 cm, ayak 15 cm.
def mst_hb_chair_points(len,wid,hei,cover,db,dt,prm,ex,bands=[])
 dc=prm['chair_dia_mm'].to_f/1000.0;s=prm['chair_spacing_mm'].to_f/1000.0
 zf=cover+2*db+dc/2;ztp=hei-cover-2*dt-dc/2
 return [] if ztp-zf<0.10 || s<=0
 lt=0.30;ft=0.15;m=cover+ex+lt/2+ft+0.05
 as=mst_deck_positions(m,len-m,s);cs=mst_deck_positions(cover+ex+0.20,wid-cover-ex-0.20,s)
 as.product(cs).reject{|a,_|bands.any?{|b0,b1|a+lt/2+ft>b0 && a-lt/2-ft<b1}}.map do |a,c|
  [[a-lt/2-ft,c,zf],[a-lt/2,c,zf],[a-lt/2,c,ztp],[a+lt/2,c,ztp],[a+lt/2,c,zf],[a+lt/2+ft,c,zf]]
 end
end

# v0.38 BKR2.3 — body (skin) bar heights: strictly between the bottom and top layers,
# by count per face or by a maximum vertical spacing.
def mst_hb_side_levels(z_lo,z_hi,prm)
 return [] if z_hi<=z_lo || prm['side_dia_mm'].to_f<=0
 n=if prm['side_mode']=='SPACING'
  ((z_hi-z_lo)/(prm['side_spacing_mm'].to_f/1000.0)).ceil-1
 else prm['side_count_each'].to_i end
 return [] if n<=0
 (1..n).map{|i|z_lo+(z_hi-z_lo)*i/(n+1).to_f}
end

# v0.47.7 BR4 — detaylı BK donatısı yalnız eklentinin çizdiği BK'da. "Mevcut Elemanı Tanıt" ile tanıtılan ya da
# içinde başka grup / component bulunan bir BK'nın kanal, boşluk ve gerçek eksenleri bilinmez: motor onu düz bir kutu
# sanar, kutunun tamamını (boşluklar dahil) donatıyla doldurur ve ölçüyü yanlış yerden okur. Böyle elemanlarda donatı
# pursantajla (Ayarlar → Donatı Pursantajları, Başlık Kirişi) hesaplanır.
def mst_hb_ents(hb)
 hb.is_a?(Sketchup::ComponentInstance) ? hb.definition.entities : hb.entities
end
# v0.51.5 K09 (ADR-0515 §2): çok örnekli Component'te örnek bazlı değişiklikten önce sorulur; yazmaz.
# => :not_shared (Group / tek örnek) | :unique (yalnız bu parça ayrılacak) | :cancel
def mst_shared_def_prompt(e,islem)
 return :not_shared unless e.is_a?(Sketchup::ComponentInstance)
 n=e.definition.count_instances
 return :not_shared unless n>1
 msg="#{element_visible_id(e)}: bu eleman Component; tanımı #{n} yerde kullanılıyor. #{islem} yalnız bu parçaya uygulanacaksa parça ayrılır (Make Unique), diğer #{n-1} parça değişmez.\n\nEvet: yalnız bu parçayı ayır ve devam et\nHayır: iptal"
 UI.messagebox(msg,MB_YESNO)==IDYES ? :unique : :cancel
end
# Parçayı ayırır, tanım verisini korur (çağıranın işlemi içinde). Örnek öznitelikleri ve element_uid örnekte kalır.
# Paylaşılan-tanım anahtarları (mst_def_kind/key/params) yeni tanıma yazılmaz: ayrılan tanım ortak tanım olarak bulunmaz.
def mst_make_unique_keep_data!(e)
 old=e.definition
 keep={};(d=old.attribute_dictionary(DICT,false)) && d.each_pair{|k,v|keep[k.to_s]=v}
 e.make_unique
 nd=e.definition
 return e if nd==old
 keep.each{|k,v|nd.set_attribute(DICT,k,v) if nd.get_attribute(DICT,k,nil).nil?}
 %w[mst_def_kind mst_def_key mst_def_params_json].each{|k|nd.delete_attribute(DICT,k)}
 nd.set_attribute(DICT,'mst_def_unique_of',keep['mst_def_key'].to_s)
 e
end
def mst_hb_rebar_unsupported_reason(hb)
 return 'eklenti dışında çizilmiş, "Mevcut Elemanı Tanıt" ile tanıtılmış eleman' if hb.get_attribute(DICT,'registered_external',false)==true || hb.get_attribute(DICT,'registered_external','').to_s=='true'
 inner=mst_hb_ents(hb).to_a.select{|x|(x.is_a?(Sketchup::Group) || x.is_a?(Sketchup::ComponentInstance)) && !%w[head_beam_rebar_set bk_culvert].include?(x.get_attribute(DICT,'element_type','').to_s)}
 return "içinde #{inner.length} tanımsız grup / component var (geometri eklentinin değil)" unless inner.empty?
 nil
end
def mst_hb_rebar_wrong?(hb)
 return false unless mst_hb_rebar_unsupported_reason(hb)
 hb.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail' ||
  mst_hb_ents(hb).to_a.any?{|x|x.is_a?(Sketchup::Group) && x.get_attribute(DICT,'element_type','').to_s=='head_beam_rebar_set'}
end
# yanlış oluşmuş BK donatısını sil, pursantaja dön (çağıranın işlemi içinde)
def mst_hb_rebar_clear!(hb)
 mst_hb_ents(hb).to_a.select{|x|x.is_a?(Sketchup::Group) && x.get_attribute(DICT,'element_type','').to_s=='head_beam_rebar_set'}.each{|g|g.erase! if g.valid?}
 %w[rebar_mode rebar_kg rebar_cover_mm rebar_bar_count rebar_kind rebar_pocket_count rebar_schedule_json hb_rebar_json].each{|k|hb.delete_attribute(DICT,k)}
 vol=qto3_quantity(hb,:concrete_m3)
 hb.set_attribute(DICT,'rebar_t',vol*rebar_rate('head_beam')/1000.0)
 true
end
def mst_hb_rebar_clean_external!(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 bad=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam' && mst_hb_rebar_wrong?(e)}
 return [] if bad.empty?
 model.start_operation('MST Eklenti Dışı BK Donatısını Temizle',true)
 begin
  bad.each{|hb|mst_hb_rebar_clear!(hb)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 bad.map{|e|element_visible_id(e)}
end
def mst_hb_rebar_clean_ui
 ids=mst_hb_rebar_clean_external!
 UI.messagebox(ids.empty? ? "Eklenti dışı BK'larda temizlenecek donatı yok." : "#{ids.length} BK'da yanlış oluşmuş donatı silindi, donatı pursantaja döndü (tek Geri Al):\n#{ids.first(12).join(', ')}")
 send_boq(@d) if @d rescue nil
 ids.length
end

def mst_hb_rebar_build!(hb,prm)
 why=mst_hb_rebar_unsupported_reason(hb)
 raise "#{element_visible_id(hb)}: detaylı donatı çizilemez — #{why}. Donatısı pursantajla hesaplanır." if why
 mst_rt_history_push!(hb) if respond_to?(:mst_rt_history_push!)   # v0.49 RV1
 prm=mst_hb_rebar_params_upgrade(prm)
 len=hb.get_attribute(DICT,'length_m',0).to_f;wid=hb.get_attribute(DICT,'width_m',0).to_f;hei=hb.get_attribute(DICT,'height_m',0).to_f
 raise "#{element_visible_id(hb)} geometrik eleman bilgisi eksik." if len<=0 || wid<=0 || hei<=0
 fr=mst_hb_local_frame(hb,len)
 len,wid,hei=fr['len'],fr['wid'],fr['hei'] if fr
 ax_y=fr && fr['ax']==:y
 ox,oy,oz=fr ? fr['o'] : [0.0,0.0,0.0]
 # v0.50 TB1: alçak taban (uç dişi / taban bölgesi) varsa ana gövde tabanı zb (çerçeve altından); bölge donatısı negatif z'de
 zi=ax_y ? {'base'=>0.0,'zones'=>[]} : mst_hb_zone_info(mst_attr_hash(hb),len)
 zb=[[zi['base'].to_f,0.0].max,[hei-0.2,0.0].max].min
 hei-=zb
 # a = along BK length, c = across (width), z = height; all metres from the min corner (z: ana gövde tabanından)
 pt=->(a,c,z){ax_y ? Geom::Point3d.new((ox+c).m,(oy+a).m,(oz+zb+z).m) : Geom::Point3d.new((ox+a).m,(oy+c).m,(oz+zb+z).m)}
 vec=->(along){(along ^ ax_y) ? X_AXIS : Y_AXIS}   # along=true: length direction
 hb.entities.grep(Sketchup::Group).select{|g|g.get_attribute(DICT,'element_type','').to_s=='head_beam_rebar_set'}.each(&:erase!)
 rg=hb.entities.add_group;rg.name="#{element_visible_id(hb)} REBAR BIM"
 rg.set_attribute(DICT,'element_type','head_beam_rebar_set');rg.set_attribute(DICT,'parent_uid',hb.get_attribute(DICT,'element_uid','').to_s)
 mst_rebar_tag!(rg,hb)   # v0.38 RB3
 cover=prm['cover_mm'].to_f/1000.0;hook=prm['hook_cm'].to_f/100.0
 kind=mst_hb_rebar_kind(hb,prm,len,wid)
 bars=[]
 # v0.38 BKR3 — channel pockets ('a' = along the BK). Top bars stop at the pocket with a hook
 # down to the channel-bottom level; a U bar wraps the pocket (top legs 50Ø each side) and a
 # straight bar of the same diameter runs under it (pocket + 2 × 50Ø); all kept inside the BK.
 pk=ax_y ? [] : mst_bk_pockets_local(mst_attr_hash(hb)).map{|p|{'a'=>[p['x'][0]-ox,p['x'][1]-ox],'zf'=>hei-p['depth']}}.sort_by{|p|p['a'][0]}
 cvs=mst_hb_culverts_local(hb,ox,oy,oz+zb,ax_y)   # v0.50 MF1: menfez kutuları (a, c, z — ana gövde tabanından)
 ea_d=(respond_to?(:mst_v50_link?) && mst_v50_link?(hb)) ? (prm['end_anchor_d'].to_f<0 ? mst_rs_lap_d : prm['end_anchor_d'].to_f) : 0.0   # v0.50 VK1: VK / BBK boyuna donatısı iki uçta BK'ya ankrajlı (×Ø)
 tdm=prm['top']['dia_mm'].to_f/1000.0
 # v0.38 BKR2.2 — hook legs must not run into each other:
 #  * top bars are shortened by one bottom-bar diameter at each end, so the top hooks
 #    sit just inside the bottom hooks (adjacent planes, not the same plane);
 #  * cross bars / side bars / stirrups start inside the hook zone;
 #  * up-hooks stop under the top mesh, down-hooks stop above the bottom mesh.
 zup=hei-cover;zdn=cover;gap=0.01
 cyl=lambda do |e,p0,axis,d,l|
  ed=e.add_circle(p0,axis,(d/2000.0).m,12);f=e.add_face(ed);return unless f
  f.reverse! if f.normal.dot(axis)<0;f.pushpull(l.m)
 end
 # RB1: a 90° end hook needs ≥ 12Ø straight after the bend (TS 500) -> leg ≥ 12Ø + bend radius
 hlen=->(z,d,dir){next 0.0 unless hook>0 && dir!=0;room=dir>0 ? zup-z : z-zdn
  hmin=MST_REBAR_BEND_RULES['hook90_min_straight']*d/1000.0+mst_bend_radius_m(d)
  [[[hook,hmin].max,hei-2*cover-d/1000.0,room].min,0.0].max}
 # RB1: bar along a centre-line polyline [[a,c,z],...] with rounded bends (radius by the rules).
 # The longest straight is the bar body; other straights are 'HOOK' sub-groups; the arcs are
 # drawn as short chords in 'BEND' sub-groups (4 chords per 90°).
 vecof=->(da,dc,dz){l=Math.sqrt(da*da+dc*dc+dz*dz);ax_y ? Geom::Vector3d.new(dc/l,da/l,dz/l) : Geom::Vector3d.new(da/l,dc/l,dz/l)}
 # RB1.1: one continuous bar — the circle is swept along the whole centre line (straights +
 # sampled bends) with Follow Me, the faceting edges are softened; the centre line is stored
 # on the bar ('path_json', model-local metres) for the checks.
 inm=39.37007874015748
 to_m=->(q){p=pt.(*q);[p.x.to_f/inm,p.y.to_f/inm,p.z.to_f/inm]}
 sweep=lambda do |ents,mp,d|
  v=[mp[1][0]-mp[0][0],mp[1][1]-mp[0][1],mp[1][2]-mp[0][2]];l=Math.sqrt(v.sum{|x|x*x})
  p0=Geom::Point3d.new(mp[0][0]*inm,mp[0][1]*inm,mp[0][2]*inm)
  ax=Geom::Vector3d.new(v[0]/l,v[1]/l,v[2]/l)
  if mp.length==2
   cyl.(ents,p0,ax,d,l);next
  end
  ed=ents.add_circle(p0,ax,(d/2000.0).m,16);f=ents.add_face(ed);next unless f
  path=ents.add_edges(mp.map{|q|Geom::Point3d.new(q[0]*inm,q[1]*inm,q[2]*inm)})
  f.followme(path)
  path.each{|e|e.erase! if e.valid? && e.faces.empty?}
  ents.grep(Sketchup::Edge).each do |e|
   fs=e.faces;next unless fs.length==2
   (e.soft=true;e.smooth=true) if fs[0].normal.angle_between(fs[1].normal)<40.degrees
  end
 end
 path_bar=lambda do |role,pts,d,attrs|
  r=mst_bend_radius_m(d)
  ln,arc,arcs=mst_bent_path(pts,r)
  bg=rg.entities.add_group;bg.name="#{role} Ø#{d.to_i}"
  mp=mst_bent_polyline(pts.map{|q|to_m.(q)},r)
  sweep.(bg.entities,mp,d)
  {'element_type'=>'rebar_bar','rebar_role'=>role,'diameter_mm'=>d,'length_m'=>ln,'hook_m'=>0.0,
   'bend_count'=>arcs.length,'bend_arc_m'=>arc,'bend_radius_m'=>r,'path_json'=>JSON.generate(pts.map{|q|to_m.(q).map{|v|v.round(6)}})}.merge(attrs).each{|k,v|bg.set_attribute(DICT,k,v)}
  bars << [d,ln,role]
 end
 # BKR3: one bar made of a horizontal body along the BK (a: xa..xb) + vertical legs [a,z0,z1]
 # + horizontal legs [a0,a1,z]; every leg is its own 'HOOK' sub-group.
 piece=lambda do |role,c,z,d,xa,xb,legs,hlegs,attrs|
  bg=rg.entities.add_group;bg.name="#{role} Ø#{d.to_i}"
  cyl.(bg.entities,pt.(xa,c,z),vec.(true),d,xb-xa) if xb-xa>1e-9
  tot=[xb-xa,0.0].max
  legs.each{|lx,z0,z1|next if (z1-z0).abs<=1e-9;lg=bg.entities.add_group;lg.name='HOOK';cyl.(lg.entities,pt.(lx,c,z0),(z1>z0 ? Z_AXIS : Z_AXIS.reverse),d,(z1-z0).abs);tot+=(z1-z0).abs}
  hlegs.each{|x0,x1,zz|next if x1-x0<=1e-9;lg=bg.entities.add_group;lg.name='HOOK';cyl.(lg.entities,pt.(x0,c,zz),vec.(true),d,x1-x0);tot+=x1-x0}
  {'element_type'=>'rebar_bar','rebar_role'=>role,'diameter_mm'=>d,'length_m'=>tot,'hook_m'=>0.0}.merge(attrs).each{|k,v|bg.set_attribute(DICT,k,v)}
  bg.set_attribute(DICT,'path_json',JSON.generate([[xa,c,z],[xb,c,z]].map{|q|to_m.(q).map{|v|v.round(6)}})) if legs.empty? && hlegs.empty? && xb-xa>1e-9
  bars << [d,tot,role]
 end
 # top bar (along) broken at every pocket: pocket ends hook down to the channel-bottom level
 top_split=lambda do |role,c,z,d,inset|
  dm=d/1000.0;a0=cover+inset;a1=len-cover-inset;hl=hlen.(z,d,-1)
  cur=a0;curp=nil;segs=[]
  pk.each{|p|segs << [cur,p['a'][0]-cover-1.5*dm,curp,p];cur=p['a'][1]+cover+1.5*dm;curp=p}
  segs << [cur,a1,curp,nil]
  segs.each do |xa,xb,pl,pr|
   next if xb-xa<=1e-6
   zl=pl ? pl['zf']-cover-dm/2 : (hl>0 ? z-hl : nil);zr=pr ? pr['zf']-cover-dm/2 : (hl>0 ? z-hl : nil)
   pts=[]
   if zl then pts << [xa+dm/2,c,zl] << [xa+dm/2,c,z] else pts << [xa,c,z] end
   if zr then pts << [xb-dm/2,c,z] << [xb-dm/2,c,zr] else pts << [xb,c,z] end
   path_bar.(role,pts,d,{'hook_m'=>((pl.nil? || pr.nil?) ? hl : 0.0),'pocket_split'=>1})
  end
 end
 # U bar around each pocket + straight bar under it, beside every top bar (lap: 50Ø).
 # Pockets closer than the two laps form one group: the U bars join over the gap (one bar
 # wrapping both pockets) and the straight bar runs continuously under all of them.
 pocket_extras=lambda do |tops,zt,d|
  dm=d/1000.0;lap=50*dm
  groups=[]
  pk.each{|p|(groups.last && p['a'][0]-groups.last.last['a'][1]<2*lap+2*(cover+dm)) ? groups.last << p : groups << [p]}
  groups.each do |grp|
   no=grp.map{|p|pk.index(p)+1}.join('+')
   xs=grp.map{|p|[p['a'][0]-cover-dm/2,p['a'][1]+cover+dm/2,p['zf']-cover-dm/2]}
   tops.each do |c|
    cu=c<wid/2.0 ? c+dm : c-dm   # beside the top bar, towards the BK centre (away from edge hook planes)
    l0=[cover,xs[0][0]-lap].max;l1=[len-cover,xs[-1][1]+lap].min
    pts=[]
    pts << [l0,cu,zt] if xs[0][0]-l0>1e-9
    xs.each{|u1,u2,z|pts << [u1,cu,zt] << [u1,cu,z] << [u2,cu,z] << [u2,cu,zt]}
    pts << [l1,cu,zt] if l1-xs[-1][1]>1e-9
    path_bar.('POCKET-U',pts,d,{'pocket_no'=>no,'lap_m'=>lap})
    piece.('POCKET-BAR',cu,grp.map{|p|p['zf']}.min-cover-1.5*dm,d,[cover,grp[0]['a'][0]-lap].max,[len-cover,grp[-1]['a'][1]+lap].min,[],[],{'pocket_no'=>no,'lap_m'=>lap})
   end
  end
 end
 # pocket band along the BK, widened by 'extra' (bars that must keep clear of the pocket detail)
 # RB1: widened by the bend radius of the top bar (the pocket hook bends inwards)
 band=->(p,extra){rt=mst_bend_radius_m(tdm*1000);[p['a'][0]-cover-2.5*tdm-rt-extra,p['a'][1]+cover+2.5*tdm+rt+extra]}
 # straight bar along 'along' (true=length dir) at cross position c and height z, with hooks (dir +1 up / -1 down)
 bar=lambda do |role,along,c,z,d,hook_dir,inset=0.0|
  span=along ? len : wid
  a0=cover+inset;bl=[span-2*a0,0.0].max;next if bl<=0
  if along && ea_d>0 && pk.empty?   # v0.50 VK1: kancasız, iki uçta ea_d × Ø BK'nın içine
   ext=ea_d*d/1000.0;a0=-ext;bl=span+2*ext;hook_dir=0
  end
  unless cvs.empty?   # v0.50 MF1: menfezden geçen boyuna çubuk iki parça (menfez + pas payı kadar ara); enine çubuk konmaz
   dm=d/1000.0
   cut=cvs.select{|v|r=along ? v['c'] : v['a'];c>r[0]-cover-dm/2 && c<r[1]+cover+dm/2 && z>v['z'][0]-cover-dm/2 && z<v['z'][1]+cover+dm/2}
   unless cut.empty?
    next unless along
    cur=a0;segs=[]
    cut.map{|v|[v['a'][0]-cover,v['a'][1]+cover]}.sort.each{|x1,x2|segs << [cur,x1] if x1-cur>0.2;cur=[cur,x2].max}
    segs << [cur,a0+bl] if a0+bl-cur>0.2
    segs.each{|xa,xb|piece.(role,c,z,d,xa,xb,[],[],{'culvert_split'=>1})}
    next
   end
  end
  if along && !pk.empty?
   if hook_dir<0
    top_split.(role,c,z,d,inset);next
   end
   if hook_dir==0
    dm=d/1000.0
    bs=pk.select{|p|z+dm/2>p['zf']-cover-1.5*tdm-tdm/2-1e-6}.map{|p|band.(p,dm/2)}
    unless bs.empty?
     cur=a0
     (bs+[[a0+bl,a0+bl]]).each{|x1,x2|piece.(role,c,z,d,cur,x1,[],[],{}) if x1-cur>1e-6;cur=[cur,x2].max}
     next
    end
   end
  end
  hl=0.0
  if hook>0 && hook_dir!=0
   room=hook_dir>0 ? zup-z : z-zdn
   # BKR3: an up-hook of a cross bar under a pocket stops below the pocket floor
   if !along && hook_dir>0
    pk.each{|p|room=[room,p['zf']-cover-z].min if c>p['a'][0]-cover-d/2000.0 && c<p['a'][1]+cover+d/2000.0}
   end
   hmin=MST_REBAR_BEND_RULES['hook90_min_straight']*d/1000.0+mst_bend_radius_m(d)
   hl=[[hook,hmin].max,hei-2*cover-d/1000.0,room].min
   if hl>0
    # RB1: hooked bar = one bent path (rounded 90° bends)
    dm=d/1000.0;q=->(a,zz){along ? [a,c,zz] : [c,a,zz]}
    pts=[q.(a0+dm/2,z+hook_dir*hl),q.(a0+dm/2,z),q.(a0+bl-dm/2,z),q.(a0+bl-dm/2,z+hook_dir*hl)]
    path_bar.(role,pts,d,{'hook_m'=>hl});next
   end
  end
  bg=rg.entities.add_group;bg.name="#{role} Ø#{d.to_i}"
  p0=along ? pt.(a0,c,z) : pt.(c,a0,z)
  cyl.(bg.entities,p0,vec.(along),d,bl)
  {'element_type'=>'rebar_bar','rebar_role'=>role,'diameter_mm'=>d,'length_m'=>bl,'hook_m'=>0.0}.each{|k,v|bg.set_attribute(DICT,k,v)}
  qq=along ? [[a0,c,z],[a0+bl,c,z]] : [[c,a0,z],[c,a0+bl,z]]
  bg.set_attribute(DICT,'path_json',JSON.generate(qq.map{|q|to_m.(q).map{|v|v.round(6)}}))
  bars << [d,bl,role]
 end
 tb=prm['top'];bt=prm['bottom']
 hk=hook>0
 if kind=='CAP'
  db=bt['dia_mm'].to_f/1000.0;dt=tb['dia_mm'].to_f/1000.0
  rb_=mst_bend_radius_m(db*1000);rt_=mst_bend_radius_m(dt*1000)
  ex=hk ? db+dt+[rb_,rt_].max : 0.0          # hook zone at every face (bottom leg + top leg + bend, RB1)
  pos=->(w,lay){mst_hb_layer_positions(w-2*ex,cover,lay).map{|v|v+ex}}
  zup=hei-cover-2*dt-gap-rt_;zdn=cover+2*db+gap+rb_   # legs stop clear of the opposite mesh and its bends
  pos.(wid,bt).each{|c|bar.('BOTTOM-L',true,c,cover+db/2,bt['dia_mm'].to_f,+1)}
  pos.(len,bt).each{|a|bar.('BOTTOM-T',false,a,cover+db*1.5,bt['dia_mm'].to_f,+1)}
  pk.each{|p|raise "#{element_visible_id(hb)}: cep çok derin — cep altına donatı sığmıyor (cep tabanı #{format('%.3f',p['zf'])} m)." if p['zf']-cover-2.5*dt<cover+2*db+gap}
  tops=pos.(wid,tb)
  tops.each{|c|bar.('TOP-L',true,c,hei-cover-dt/2,tb['dia_mm'].to_f,-1,(hk ? db : 0.0))}
  pos.(len,tb).each do |a|
   next if pk.any?{|p|b=band.(p,dt/2);a>b[0] && a<b[1]}   # BKR3: no cross bars across the pocket
   bar.('TOP-T',false,a,hei-cover-dt*1.5,tb['dia_mm'].to_f,-1,(hk ? db : 0.0))
  end
  pocket_extras.(tops,hei-cover-dt/2,tb['dia_mm'].to_f)
  # body (skin) bars on all four faces, between the meshes, inside the hook legs; no stirrups.
  # long-face bars stop one side-bar diameter short so they do not cross the end-face bars.
  sdd=prm['side_dia_mm'].to_f;ds=sdd/1000.0
  if prm['side_style']=='GONYE' && ds>0
   # v0.50 DG1 — yan yüz donatısı gönyeli: her kotta 4 köşe L çubuğu, bacaklar yüz ortasını bindirme/2 geçer;
   # komşu köşeler bir Ø içeride (aynı çizgide çakışmaz, yüz ortasında bindirme)
   lapm=mst_rs_lap_d*ds
   ca=[cover+ex+ds/2,len-cover-ex-ds/2];cc=[cover+ex+ds/2,wid-cover-ex-ds/2]
   mst_hb_side_levels(cover+2*db,hei-cover-2*dt,prm).each do |z|
    [[0,0,0.0],[1,0,ds],[1,1,0.0],[0,1,ds]].each do |ia,ic,off|
     a_c=ia==0 ? ca[0]+off : ca[1]-off;c_c=ic==0 ? cc[0]+off : cc[1]-off
     a_e=ia==0 ? [len/2.0+lapm/2,ca[1]-ds].min : [len/2.0-lapm/2,ca[0]+ds].max
     c_e=ic==0 ? [wid/2.0+lapm/2,cc[1]-ds].min : [wid/2.0-lapm/2,cc[0]+ds].max
     path_bar.('SIDE-G',[[a_e,c_c,z],[a_c,c_c,z],[a_c,c_e,z]],sdd,{'gonye'=>1})
    end
   end
  else
   mst_hb_side_levels(cover+2*db,hei-cover-2*dt,prm).each do |z|
    [cover+ex+ds/2,wid-cover-ex-ds/2].each{|c|bar.('SIDE-L',true,c,z,sdd,0,ex+ds)}
    [cover+ex+ds/2,len-cover-ex-ds/2].each{|a|bar.('SIDE-T',false,a,z,sdd,0,ex)}
   end
  end
  # v0.49 SH1 — sehpa (Π): alt hasırın üst katına (enine) oturur, üst hasırın alt katını (enine) taşır; kollar boyuna.
  if prm['chair_on'] && prm['chair_dia_mm'].to_f>0
   mst_hb_chair_points(len,wid,hei,cover,db,dt,prm,ex,pk.map{|p|band.(p,dt)}).each{|pts|path_bar.('CHAIR',pts,prm['chair_dia_mm'].to_f,{'chair'=>1})}
  end
 else
  sd=prm['stirrup_dia_mm'].to_f/1000.0
  db=bt['dia_mm'].to_f/1000.0;dt=tb['dia_mm'].to_f/1000.0
  rb_=mst_bend_radius_m(db*1000);rt_=mst_bend_radius_m(dt*1000)
  ex=hk ? db+dt+[rb_,rt_].max : 0.0           # RB1: hook zone includes the bend
  zup=hei-cover-sd-dt-gap-rt_;zdn=cover+sd+db+gap+rb_
  # longitudinal top / bottom bars sit inside the stirrups
  inner=->(lay){l=lay.merge({});w2=wid-2*sd;mst_hb_layer_positions(w2,cover,l).map{|c|c+sd}}
  inner.(bt).each{|c|bar.('BOTTOM',true,c,cover+sd+db/2,bt['dia_mm'].to_f,+1)}
  pk.each{|p|raise "#{element_visible_id(hb)}: cep çok derin — cep altına donatı sığmıyor (cep tabanı #{format('%.3f',p['zf'])} m)." if p['zf']-cover-2.5*dt-sd<cover+sd+db+gap}
  tops=inner.(tb)
  tops.each{|c|bar.('TOP',true,c,hei-cover-sd-dt/2,tb['dia_mm'].to_f,-1,(hk ? db : 0.0))}
  pocket_extras.(tops,hei-cover-sd-dt/2,tb['dia_mm'].to_f)
  sdd=prm['side_dia_mm'].to_f
  # v0.38 BKR2.3: side bars between the bottom and top bars (they no longer coincide with the corner bars)
  mst_hb_side_levels(cover+sd+db,hei-cover-sd-dt,prm).each{|z|[cover+sd+sdd/2000.0,wid-cover-sd-sdd/2000.0].each{|c|bar.('SIDE',true,c,z,sdd,0,ex)}}
  if sd>0
   ss=prm['stirrup_spacing_mm'].to_f/1000.0
   x0=cover+ex+sd/2;x1=len-cover-ex-sd/2
   count=x1>=x0 ? ((x1-x0)/ss).floor+1 : 0
   act=count>1 ? (x1-x0)/(count-1).to_f : 0.0
   c0=cover+sd/2;c1=wid-cover-sd/2;z0=cover+sd/2;z1=hei-cover-sd/2
   # RB1: rounded corners (D = 4Øw) and two 135° hooks at the top-left corner, max(10Øw, 100 mm)
   rs=mst_bend_radius_m(sd*1000,true)
   ext=[MST_REBAR_BEND_RULES['stirrup_hook_ext']*sd,MST_REBAR_BEND_RULES['stirrup_hook_ext_min_m']].max
   loop_pts=lambda do |x,zt|
    cs=[[c0+rs,z0+rs,Math::PI,1.5*Math::PI],[c1-rs,z0+rs,1.5*Math::PI,2*Math::PI],[c1-rs,zt-rs,0.0,0.5*Math::PI],[c0+rs,zt-rs,0.5*Math::PI,Math::PI]]
    q=cs.flat_map{|cc,cz,f0,f1|(0..4).map{|k|f=f0+(f1-f0)*k/4.0;[x,cc+rs*Math.cos(f),cz+rs*Math.sin(f)]}}
    q+[q[0]]
   end
   # v0.49 ET1 — iç içe etriyeler: n kol genişlik boyunca eşit aralıklı; i. etriye i. ve (n−1−i). kolda (dış etriye i = 0)
   nl=prm['stirrup_legs'].to_i;nl+=1 if nl.odd?;nl=2 if nl<2
   legc=(0...nl).map{|k|c0+(c1-c0)*k/(nl-1).to_f}
   inner=(1...nl/2).map{|k|[legc[k],legc[nl-1-k]]}.select{|a,b|b-a>2*rs+0.02}
   # v0.50 ET2 — yan yana dar etriyeler (Ege BK3): n adet, genişlik w (0 = otomatik: eşit pay + 10 cm binme), sol kenarları eşit aralıklı
   side=prm['stirrup_layout']=='SIDE'
   if side
    nw=prm['side_n'].to_i;w=prm['side_w_mm'].to_f/1000.0
    w=(c1-c0)/nw+0.10 if w<=0
    w=[[w,c1-c0].min,2*rs+0.05].max
    narrow=(0...nw).map{|k|ca=nw==1 ? c0 : c0+(c1-c0-w)*k/(nw-1).to_f;[ca,ca+w]}
   end
   # bir kapalı etriye (yuvarlak köşeler D = 4Øw, sol üstte iki 135° kanca): x düzleminde ca..cb, zb..zt
   stir=lambda do |x,ca,cb,zbt,zt,name,attrs|
    cs=[[ca+rs,zbt+rs,Math::PI,1.5*Math::PI],[cb-rs,zbt+rs,1.5*Math::PI,2*Math::PI],[cb-rs,zt-rs,0.0,0.5*Math::PI],[ca+rs,zt-rs,0.5*Math::PI,Math::PI]]
    q=cs.flat_map{|cc,cz,f0,f1|(0..4).map{|k|f=f0+(f1-f0)*k/4.0;[x,cc+rs*Math.cos(f),cz+rs*Math.sin(f)]}}
    pr=2.0*((cb-ca)+(zt-zbt))-8*rs+2*Math::PI*rs+2*(ext+rs*0.75*Math::PI)
    sg=rg.entities.add_group;sg.name="#{name} Ø#{(sd*1000).to_i}"
    sg.entities.add_edges((q+[q[0]]).map{|qq|pt.(*qq)})
    e=ext/Math.sqrt(2)
    sg.entities.add_edges([[x,ca+rs,zt],[x,ca+rs+e,zt-e]].map{|qq|pt.(*qq)})
    sg.entities.add_edges([[x,ca,zt-rs],[x,ca+e,zt-rs-e]].map{|qq|pt.(*qq)})
    {'element_type'=>'rebar_stirrup','diameter_mm'=>sd*1000,'length_m'=>pr,'hook_angle_deg'=>135.0,'hook_ext_m'=>ext,'bend_radius_m'=>rs,
     'path_json'=>JSON.generate([[x,ca,zt],[x,cb,zt],[x,cb,zbt],[x,ca,zbt],[x,ca,zt]].map{|qq|to_m.(qq).map{|v|v.round(6)}})}.merge(attrs).each{|k,v|sg.set_attribute(DICT,k,v)}
    bars << [sd*1000,pr,'STIRRUP']
   end
   zone_bot=lambda do |x|   # v0.50 TB1: alçak bölgede etriye bölge tabanına iner
    q=prm['zone_bars'] ? zi['zones'].find{|zz|x>zz['f0']+cover && x<zz['f1']-cover} : nil
    q ? -q['dz']+cover+sd/2 : z0
   end
   count.times do |i|
    x=count==1 ? x0 : x0+act*i
    # BKR3: stirrups at a pocket stop under the straight bars below the channel
    zt_s=z1;pp=pk.find{|p|b=band.(p,sd);x>b[0] && x<b[1]}
    zt_s=pp['zf']-cover-1.5*dt-dt/2-sd/2 if pp
    zb_s=zone_bot.(x)
    cv=cvs.find{|v|x>v['a'][0]-cover-sd && x<v['a'][1]+cover+sd && v['c'][0]<c1 && v['c'][1]>c0}
    if cv   # v0.50 MF1: menfez altında kalan etriye kısalır, sığmıyorsa konmaz
     next unless cv['z'][0]-cover-sd/2-zb_s>0.3
     zt_s=[zt_s,cv['z'][0]-cover-sd/2].min
    end
    next if zt_s-zb_s<0.05
    extra=(pp ? {'pocket_short'=>1} : {}).merge(cv ? {'culvert_short'=>1} : {}).merge(zb_s<z0-1e-9 ? {'zone_long'=>1} : {})
    if side
     stir.(x,c0,c1,zb_s,zt_s,"STIRRUP-#{i+1}",extra) if prm['side_outer']
     narrow.each_with_index do |(ca,cb),k|
      xi=i==count-1 && count>1 ? x-sd*(k+(prm['side_outer'] ? 1 : 0)) : x+sd*(k+(prm['side_outer'] ? 1 : 0))
      stir.(xi,ca,cb,zb_s,zt_s,"STIRRUP-#{i+1}.#{k+1}",extra.merge('side_stirrup'=>k+1))
     end
    else
     stir.(x,c0,c1,zb_s,zt_s,"STIRRUP-#{i+1}",extra)
     inner.each_with_index do |(ca,cb),k|
      xi=i==count-1 && count>1 ? x-sd*(k+1) : x+sd*(k+1)   # iç etriye dış etriyenin yanında (aynı düzlemde değil); sonuncuda içeri
      stir.(xi,ca,cb,zb_s,zt_s,"STIRRUP-#{i+1}.#{k+1}",extra.merge('inner_stirrup'=>k+1))
     end
    end
   end
   # v0.50 MF1: menfezin iki yanında 2'şer tam etriye (takviye)
   cvs.each do |v|
    [v['a'][0]-cover-sd/2,v['a'][0]-cover-sd/2-0.10,v['a'][1]+cover+sd/2,v['a'][1]+cover+sd/2+0.10].each do |x|
     next if x<x0-1e-9 || x>x1+1e-9 || cvs.any?{|w|x>w['a'][0]-cover && x<w['a'][1]+cover}
     zb_s=zone_bot.(x);stir.(x,c0,c1,zb_s,z1,'STIRRUP-MF',{'culvert_trim'=>1}) if z1-zb_s>0.05
    end
   end
   rg.set_attribute(DICT,'stirrup_count',count);rg.set_attribute(DICT,'stirrup_actual_spacing_mm',act*1000.0)
  end
 end
 # ---- v0.50 ekleri (TB1 alçak bölge alt donatısı, CZ1 çiroz, BN1 bant + şapka, MF1 menfez takviyesi)
 sdc=kind=='CAP' ? 0.0 : prm['stirrup_dia_mm'].to_f/1000.0
 dbc=bt['dia_mm'].to_f/1000.0;dtc=tb['dia_mm'].to_f/1000.0
 exc=hk ? dbc+dtc+[mst_bend_radius_m(dbc*1000),mst_bend_radius_m(dtc*1000)].max : 0.0
 if prm['zone_bars']
  zi['zones'].each do |q|
   za0=[q['f0'],0.0].max+cover+0.02;za1=[q['f1'],len].min-cover-0.02;next if za1-za0<0.3
   zz=-q['dz']+cover+sdc+dbc/2
   cs=kind=='CAP' ? mst_hb_layer_positions(wid,cover,bt) : mst_hb_layer_positions(wid-2*sdc,cover,bt).map{|c|c+sdc}
   cs.each{|c|piece.('ZONE-BOTTOM',c,zz,bt['dia_mm'].to_f,za0,za1,[],[],{'zone'=>1})}
  end
 end
 cuts=->(x,r){pk.any?{|p|b=band.(p,r);x>b[0] && x<b[1]} || cvs.any?{|v|x>v['a'][0]-cover-r && x<v['a'][1]+cover+r}}
 if prm['ciroz_on'] && kind!='CAP' && prm['ciroz_dia_mm'].to_f>0
  cd=prm['ciroz_dia_mm'].to_f/1000.0;csp=prm['ciroz_spacing_mm'].to_f/1000.0;hkc=[10*cd,0.10].max
  cA=cover+sdc+cd/2;cB=wid-cover-sdc-cd/2;ztt=hei-cover-sdc-dtc-cd/2;zbb=cover+sdc+dbc+cd/2
  ssp=prm['stirrup_spacing_mm'].to_f/1000.0
  mst_deck_positions(cover+exc+ssp/2,len-cover-exc-ssp/2,csp).each do |x|
   next if cuts.(x,cd) || ztt-hkc<zbb+hkc
   path_bar.('CIROZ',[[x,cA,ztt-hkc],[x,cA,ztt],[x,cB,ztt],[x,cB,ztt-hkc]],cd*1000,{'ciroz'=>1})
   path_bar.('CIROZ',[[x,cA,zbb+hkc],[x,cA,zbb],[x,cB,zbb],[x,cB,zbb+hkc]],cd*1000,{'ciroz'=>1})
  end
 end
 if prm['band_on'] && prm['band_h_m'].to_f>0.05
  bw=prm['band_w_m'].to_f>0 ? [prm['band_w_m'].to_f,wid].min : wid;bh=prm['band_h_m'].to_f
  hd=prm['hat_dia_mm'].to_f/1000.0;hs=prm['hat_spacing_mm'].to_f/1000.0
  cb0=(wid-bw)/2.0;cb1=(wid+bw)/2.0
  zt_h=hei+bh-cover-hd/2
  leg=prm['hat_leg_m'].to_f>0 ? prm['hat_leg_m'].to_f : 40*hd
  zl=[hei-leg,cover+sdc+dbc+0.05].max
  topc=kind=='CAP' ? mst_hb_layer_positions(wid,cover,tb) : mst_hb_layer_positions(wid-2*sdc,cover,tb).map{|c|c+sdc}
  fix=lambda do |cc,dir|
   12.times{hit=topc.find{|t|(t-cc).abs<(dtc+hd)/2+0.002};break unless hit;cc=hit+dir*((dtc+hd)/2+0.003)}
   cc
  end
  ch0=fix.(cb0+cover+hd/2,1);ch1=fix.(cb1-cover-hd/2,-1)
  if hd>0 && ch1-ch0>0.10 && zt_h-zl>0.10
   mst_deck_positions(cover+exc+hs/2,len-cover-exc-hs/2,hs).each do |x|
    next if cuts.(x,hd)
    path_bar.('HAT',[[x,ch0,zl],[x,ch0,zt_h],[x,ch1,zt_h],[x,ch1,zl]],hd*1000,{'hat'=>1})
   end
  end
  blay=prm['band_top'];dbt=blay['dia_mm'].to_f/1000.0
  zbt=zt_h-hd/2-dbt/2
  mst_hb_layer_positions(bw-2*hd,cover,blay).map{|c|c+cb0+hd}.each{|c|bar.('BAND-TOP',true,c,zbt,blay['dia_mm'].to_f,0)} if dbt>0
 end
 if prm['culvert_trim_n'].to_i>0 && prm['culvert_trim_dia_mm'].to_f>0
  td=prm['culvert_trim_dia_mm'].to_f/1000.0;n=prm['culvert_trim_n'].to_i;lapm=mst_rs_lap_d*td
  cvs.each do |v|
   xa=[v['a'][0]-lapm,cover].max;xb=[v['a'][1]+lapm,len-cover].min;next if xb-xa<0.3
   lo=[v['c'][0]+cover+td/2,cover+sdc+td/2].max;hi=[v['c'][1]-cover-td/2,wid-cover-sdc-td/2].min;next if hi<lo
   cs=n==1 ? [(lo+hi)/2.0] : (0...n).map{|k|lo+(hi-lo)*k/(n-1).to_f}
   zbel=v['z'][0]-cover-td/2;zab=v['z'][1]+cover+td/2
   cs.each do |c|
    piece.('CULVERT-TRIM',c,zbel,td*1000,xa,xb,[],[],{'culvert'=>1}) if zbel>cover+sdc+dbc+td
    piece.('CULVERT-TRIM',c,zab,td*1000,xa,xb,[],[],{'culvert'=>1}) if zab<hei-cover-sdc-dtc-td
   end
  end
 end
 # RB2: colour by diameter
 rg.entities.grep(Sketchup::Group).each{|g|mst_rebar_paint!(g) if %w[rebar_bar rebar_stirrup].include?(g.get_attribute(DICT,'element_type','').to_s)}
 kg=bars.sum{|d,l,_|rebar_unit_kg_m(d)*l}
 hb.set_attribute(DICT,'rebar_mode','bim_detail');hb.set_attribute(DICT,'rebar_t',kg/1000.0);hb.set_attribute(DICT,'rebar_kg',kg)
 hb.set_attribute(DICT,'rebar_cover_mm',cover*1000.0);hb.set_attribute(DICT,'rebar_bar_count',bars.length);hb.set_attribute(DICT,'rebar_kind',kind)
 hb.set_attribute(DICT,'rebar_pocket_count',pk.length)
 hb.set_attribute(DICT,'rebar_culvert_count',cvs.length);hb.set_attribute(DICT,'rebar_zone_count',zi['zones'].length)
 summary=bars.group_by{|d,_,r|"#{r.split('-').first} Ø#{d.to_i}"}.transform_values{|a|{'count'=>a.length,'length_m'=>a.sum{|x|x[1]},'kg'=>a.sum{|x|rebar_unit_kg_m(x[0])*x[1]}}}
 hb.set_attribute(DICT,'rebar_schedule_json',JSON.generate(summary));rg.set_attribute(DICT,'rebar_schedule_json',JSON.generate(summary));rg.set_attribute(DICT,'weight_kg',kg)
 rg.set_attribute(DICT,'rebar_kind',kind)
 hb.set_attribute(DICT,'hb_rebar_json',JSON.generate(prm))
 kg
end

def hb_rebar_selected(data, dialog=@d)
  model=Sketchup.active_model
  beams=model.selection.to_a.select{|e| e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
  if beams.empty?
    UI.messagebox('Önce en az bir Başlık Kirişi seçin.'); return
  end
  # v0.47.7 BR4: eklenti dışı / iç grubu olan BK'lara detaylı donatı çizilmez
  skip=beams.map{|hb|[hb,mst_hb_rebar_unsupported_reason(hb)]}.select{|_,w|w}
  unless skip.empty?
   wrong=skip.map(&:first).select{|hb|mst_hb_rebar_wrong?(hb)}
   msg="#{skip.length} BK'ya detaylı donatı çizilmez:\n"+skip.first(8).map{|hb,w|"  #{element_visible_id(hb)}: #{w}"}.join("\n")+
       "\n\nBu elemanların kanal / boşluk ve eksen bilgisi eklentide yok; donatı kutunun tamamını doldurur ve yanlış yere oturur. Donatıları pursantajla hesaplanır (Ayarlar → Donatı Pursantajları → Başlık Kirişi)."
   if wrong.empty?
    UI.messagebox(msg)
   elsif UI.messagebox(msg+"\n\n#{wrong.length} BK'da önceden yanlış oluşmuş donatı var. Silinip pursantaja dönülsün mü? (tek Geri Al)",MB_YESNO)==IDYES
    model.start_operation('MST Eklenti Dışı BK Donatısını Temizle',true)
    begin
     wrong.each{|hb|mst_hb_rebar_clear!(hb)}
     model.commit_operation
    rescue
     model.abort_operation;raise
    end
   end
   beams-=skip.map(&:first)
   if beams.empty?
    send_boq(dialog) if dialog
    return
   end
  end
  prm=mst_hb_rebar_params(data)
  model.start_operation('MST BK Donatı BIM',true)
  begin
    kinds=beams.map{|hb|p2=prm
     p2=prm.merge('cover_mm'=>mst_rs_cover_for(hb)) if data['cover_src'].to_s=='RS' && respond_to?(:mst_rs_cover_for)   # v0.50 RS2: eleman tipine göre pas payı
     mst_hb_rebar_build!(hb,p2);"#{element_visible_id(hb)}: #{hb.get_attribute(DICT,'rebar_kind')=='CAP' ? 'Dolfen başlığı — çift yönlü alt+üst ağ, etriyesiz' : 'Kiriş — boyuna + etriye'} (#{format('%.3f',hb.get_attribute(DICT,'rebar_t',0).to_f)} t)"}
    commit_with_dependencies(model)
    UI.messagebox("#{beams.length} Başlık Kirişi için Detaylı Donatı BIM oluşturuldu.\n#{kinds.first(10).join("\n")}\n\nKeşif artık bu elemanlarda gerçek modellenmiş donatı tonajını kullanır.\nBK ölçüsü / kotu değişince donatı bu değerlerle otomatik yeniden üretilir.")
    send_boq(dialog) if dialog
  rescue=>ex
    model.abort_operation; UI.messagebox("Donatı BIM oluşturulamadı:\n#{ex.message}")
  end
end

# ===== v0.22.0 QTO Engine 3.0 =====
# Canonical quantity access. Dashboard, detail reports, Excel and future BOQ
# must read the same normalized quantity keys from this layer.
def qto3_quantity(e,key)
 QuantityService.value(e,key)
end

def qto3_scope(e)
  {
    project:e.get_attribute(DICT,'project','').to_s,
    ano:e.get_attribute(DICT,'ano','').to_s,
    axis:e.get_attribute(DICT,'axis',e.get_attribute(DICT,'axis_span','')).to_s,
    zone:e.get_attribute(DICT,'qto_zone',e.get_attribute(DICT,'zone','')).to_s
  }
end

def qto3_snapshot
  all=[];collect_elements(Sketchup.active_model.entities,all)
  allowed=%w[steel_pipe_pile pile_infill_concrete head_beam flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile]
  elems=all.select{|e|allowed.include?(e.get_attribute(DICT,'element_type','').to_s)}
  types={
    'steel_pipe_pile'=>'Çelik Boru Kazık','pile_infill_concrete'=>'Kazık İçi Beton',
    'head_beam'=>'Başlık Kirişi','flat_precast'=>'Normal PD','channel_precast'=>'Kanal Prekastı','crane_precast'=>'Vinç Prekastı',
    'deck_slab'=>'Döşeme','curb'=>'Bordür / Tretuvar','crown_wall'=>'Kronman','bored_pile'=>'Fore Kazık'
  }
  rows=[]
  types.each do |typ,name|
    arr=elems.select{|e|e.get_attribute(DICT,'element_type','').to_s==typ}
    next if arr.empty?
    rows << {
      type:typ,name:name,count:arr.length,
      length_m:arr.sum{|e|qto3_quantity(e,:length_m)},
      steel_t:arr.sum{|e|qto3_quantity(e,:steel_t)},
      concrete_m3:arr.sum{|e|qto3_quantity(e,:concrete_m3)},
      formwork_m2:arr.sum{|e|qto3_quantity(e,:formwork_m2)}
    }
  end
  concrete_by_class={}
  elems.reject{|e|e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}.each do |e|
    cc=qto_material_class(e); next if cc=='-'
    concrete_by_class[cc]=(concrete_by_class[cc]||0.0)+qto3_quantity(e,:concrete_m3)
  end
  projects=elems.map{|e|qto3_scope(e)[:project]}.reject(&:empty?).uniq.sort
  anos=elems.map{|e|qto3_scope(e)[:ano]}.reject(&:empty?).uniq.sort
  axes=elems.map{|e|qto3_scope(e)[:axis]}.reject(&:empty?).uniq.sort
  zones=elems.map{|e|qto3_scope(e)[:zone]}.reject(&:empty?).uniq.sort
  snapshot = {
    elements:elems,rows:rows,
    totals:{count:elems.length,length_m:elems.sum{|e|qto3_quantity(e,:length_m)},steel_t:elems.sum{|e|qto3_quantity(e,:steel_t)},concrete_m3:elems.sum{|e|qto3_quantity(e,:concrete_m3)},formwork_m2:elems.sum{|e|qto3_quantity(e,:formwork_m2)}},
    concrete_by_class:concrete_by_class,
    scopes:{projects:projects,anos:anos,axes:axes,zones:zones}
  }
  qto_reconcile_pile_infill!(snapshot, elems.select{|e|e.get_attribute(DICT,'element_type','')=='steel_pipe_pile'})
end
# ===== end v0.22.0 =====

# ===== v0.23.2 BOQ / ÖBF Engine - Ruby compatibility hotfix =====
BOQ_TEMPLATE = [
  ['ÖBF-001','MOBİLİZASYON','LS',100000.0,'MOBILIZATION'],
  ['ÖBF-002','DÜZ YÜZEYLİ BETONARME KALIBI YAPILMASI','m²',110.0,'FORMWORK_CAST'],
  ['ÖBF-003','PREKAST ELEMAN KALIBI','m²',50.0,'FORMWORK_PRECAST'],
  ['ÖBF-004','HER ÇAPTA NERVÜRLÜ ÇELİĞİN BÜKÜLÜP YERİNE KONMASI','ton',1000.0,'REBAR'],
  ['ÖBF-005','A SINIFI BETONARME BETONU (BAŞLIK KİRİŞİ + DÖŞEME BETONU)','m³',140.0,'HB_DECK_CONCRETE'],
  ['ÖBF-006','A SINIFI BETONARME BETONU (C35/45)','m³',130.0,'CAST_C35_45_OTHER'],
  ['ÖBF-007','PREKAST BETONU (C35/45)','m³',125.0,'PRECAST_C35_45'],
  ['ÖBF-008','PREKAST ELEMANLARIN TAŞINMASI ve YERİNE KONULMASI','m³',40.0,'PRECAST_INSTALL'],
  ['ÖBF-009','KAPLAMA (TOPPİNG) BETONU İŞÇİLİĞİ','m²',30.0,'TOPPING_AREA'],
  ['ÖBF-010','ÇELİK BORU KAZIKLARIN İÇİNE BETONARME BETONU DOLDURULMASI','m³',140.0,'PILE_INFILL'],
  ['ÖBF-011','ÇELİK BORU KAZIKLARIN İMALİ','ton',1100.0,'PILE_STEEL'],
  ['ÖBF-012','ÇELİK BORU KAZIKLARIN MANİPÜLASYONU','ton',40.0,'PILE_MANIP'],
  ['ÖBF-013','ÇELİK BORU KAZIKLAR İÇİN ÇARIK YAPILMASI VE YERİNE KONMASI','kg',4.0,'PILE_RINGS'],
  ['ÖBF-014','ÇELİK BORU KAZIKLARIN EKLENMESİ','ad',300.0,'PILE_SPLICES'],
  ['ÖBF-015','ÇELİK BORU KAZIKLARIN ÇAKILMASI','m',200.0,'PILE_DRIVING'],
  ['ÖBF-016','ÇELİK BORU KAZIKLARIN POLİETİLEN İLE KAPLANMASI','m²',75.0,'PILE_PE'],
  ['ÖBF-091','ÇELİK BORU KAZIKLARA FORAJ YAPILMASI','m',nil,'PILE_DRILLING'],
  ['ÖBF-072','KAPLAMA (TOPPİNG) BETONU','m³',nil,'TOPPING_CONCRETE'],
  ['ÖBF-251','KRONMAN KALIBI','m²',nil,'CROWN_FORMWORK'],
  ['ÖBF-252','KRONMAN BETONU (C35/45)','m³',nil,'CROWN_CONCRETE']
].freeze
BOQ_LIBRARY_IDS={'PILE_DRILLING'=>'40549a68-e406-543a-b9c0-345445f7838e','TOPPING_CONCRETE'=>'8a4a56e1-6f0a-5d93-8149-80729020ce70','CROWN_FORMWORK'=>'97660795-16b5-5dc6-a6d4-edf482f30af9','CROWN_CONCRETE'=>'b4e49086-49b6-5ec4-9fd9-38b03d636110'}.freeze
REBAR_DEFAULTS={'pile'=>250.0,'deck'=>150.0,'head_beam'=>180.0,'flat_precast'=>120.0,'channel_precast'=>120.0,'crane_precast'=>120.0,'topping'=>20.0,'crown_wall'=>100.0,'site_concrete'=>80.0}.freeze

def boq_price(code, default_price)
  Sketchup.active_model.get_attribute(DICT,"boq_price_#{code}",default_price).to_f
end

def rebar_rate(key)
  Sketchup.active_model.get_attribute(DICT,"rebar_rate_#{key}",REBAR_DEFAULTS[key].to_f).to_f
end

# ===== v0.38 UI1 — Donatı tek kaynak =====
# Her elemanın donatısı TEK yerden: BIM çizilmişse modellenen tonaj, değilse beton × pursantaj.
# BOQ, QTO, Detaylı Metraj Raporu ve Hakediş aynı fonksiyonu kullanır.
MST_REBAR_RATE_KEYS={'pile_infill_concrete'=>'pile','head_beam'=>'head_beam','deck_slab'=>'deck','curb'=>'deck',
 'flat_precast'=>'flat_precast','channel_precast'=>'channel_precast','crane_precast'=>'crane_precast',
 'deck_topping'=>'topping','crown_wall'=>'crown_wall'}.freeze
MST_REBAR_BIM_TYPES=%w[head_beam deck_slab pile_infill_concrete flat_precast channel_precast crane_precast crown_wall].freeze   # v0.50 PC2: prekast donatısı

# => {'kg'=>Float,'source'=>'BIM'|'%'|'FORE'|'-','rate'=>kg/m³ veya nil}
def mst_element_rebar(e)
 typ=e.get_attribute(DICT,'element_type','').to_s
 if typ=='bored_pile'
  d=(JSON.parse(e.get_attribute(DICT,'bored_pile_data','{}').to_s) rescue {})
  kg=e.get_attribute(DICT,'rebar_t',0).to_f*1000.0
  return {'kg'=>kg,'source'=>(d['rebar_mode'].to_s=='rate' ? '%' : 'BIM'),'rate'=>(d['rebar_mode'].to_s=='rate' ? d['rebar_rate'].to_f : nil)}
 end
 if MST_REBAR_BIM_TYPES.include?(typ) && %w[bim_detail drawing_detail auto_detail].include?(e.get_attribute(DICT,'rebar_mode','').to_s)   # v0.47.8 DR1 çizimden (tablo) / v0.48 AR1 otomatik (çizilen)
  return {'kg'=>e.get_attribute(DICT,'rebar_t',0).to_f*1000.0,'source'=>'BIM','rate'=>nil}
 end
 if %w[flat_precast channel_precast].include?(typ) && e.get_attribute(DICT,'rebar_mode','').to_s.empty? && e.get_attribute(DICT,'pc_rebar_error','').to_s.empty? && respond_to?(:mst_pc_def_rebar) && (h=mst_pc_def_rebar(e))   # v0.50 PC2: tanımı donatılı Component; v0.51.5 K60: çizim hatasında tanım kaydı okunmaz
  return {'kg'=>h['rebar_t'].to_f*1000.0,'source'=>'BIM','rate'=>nil}
 end
 key=MST_REBAR_RATE_KEYS[typ]
 return {'kg'=>0.0,'source'=>'-','rate'=>nil} unless key
 r=rebar_rate(key)
 {'kg'=>qto3_quantity(e,:concrete_m3)*r,'source'=>'%','rate'=>r}   # v0.47 BK1: BK'da net beton
end

# eleman listesi toplamı: {'kg','bim_kg','rate_kg','label'}  label ör. "BIM" / "% 180" / "BIM 12.0 t + % 3.1 t"
def mst_rebar_sum(es)
 bim=0.0;rt=0.0;rates=[]
 es.each{|e|r=mst_element_rebar(e);r['source']=='%' ? (rt+=r['kg'];rates << r['rate']) : bim+=r['kg']}
 rates.uniq!
 lab=if rt<=0 && bim<=0 then '-'
  elsif rt<=0 then 'BIM'
  elsif bim<=0 then "% #{rates.length==1 ? format('%.0f',rates[0]) : 'karma'}"
  else "BIM #{format('%.3f',bim/1000.0)} t + % #{format('%.3f',rt/1000.0)} t"
  end
 {'kg'=>bim+rt,'bim_kg'=>bim,'rate_kg'=>rt,'label'=>lab}
end

# rapor hücresi: "12.345 t <small>BIM</small>"
def mst_rebar_cell(es,bold=false)
 s=mst_rebar_sum(es);v=format('%.3f',s['kg']/1000.0)
 "#{bold ? "<b>#{v} t</b>" : "#{v} t"} <small style='color:#5b6b7b'>(#{html_escape(s['label'])})</small>"
end

# BOQ ÖBF-004 donatısının satır satır dökümü — BOQ toplamı bu satırların toplamıdır.
def mst_boq_rebar_breakdown(all,pile_infill=nil,topping_vol=nil)
 by=->(t){all.select{|e|e.get_attribute(DICT,'element_type','').to_s==t}}
 piles=by.('steel_pipe_pile')
 if pile_infill.nil?
  pr=pile_fabrication_qto_row(piles,'TOPLAM',true)
  pile_infill=pr ? pr[13].to_f : by.('pile_infill_concrete').sum{|e|qto3_quantity(e,:concrete_m3)}
 end
 topping_vol=topping_quantities(all)[1] if topping_vol.nil?
 rows=[]
 if piles.any?{|p|mst_pile_rebar_active(p)}
  kg=piles.sum{|p|mst_pile_rebar_t(p)}*1000.0
  rows << {key:'pile',name:'Kazık içi',count:piles.length,kg:kg,label:(piles.all?{|p|mst_pile_rebar_effective?(p)} ? 'BIM' : 'BIM + %')}
 else
  rows << {key:'pile',name:'Kazık içi',count:[by.('pile_infill_concrete').length,piles.length].max,kg:pile_infill*rebar_rate('pile'),label:"% #{format('%.0f',rebar_rate('pile'))}"}
 end
 # ADR-0515 G4: ayrı bordür / tretuvar öğesinin donatısı (hacim × rebar_rate('deck')) Keşif ÖBF-004'e girer; kaplama satırı yine 3. sıraya eklenir
 [['head_beam','Başlık kirişi'],['deck_slab','Döşeme'],['curb','Bordür / Tretuvar'],['flat_precast','Normal prekast'],['channel_precast','Kanal prekastı'],
  ['crane_precast','Vinç prekastı'],['crown_wall','Kronman'],['bored_pile','Fore kazık']].each do |t,n|
  es=by.(t);s=mst_rebar_sum(es)
  rows << {key:t,name:n,count:es.length,kg:s['kg'],label:s['label']}
 end
 rows.insert(3,{key:'topping',name:'Kaplama betonu',count:0,kg:topping_vol*rebar_rate('topping'),label:"% #{format('%.0f',rebar_rate('topping'))}"})
 rows=mst_v50_breakdown_extras(rows,all) if respond_to?(:mst_v50_breakdown_extras)   # v0.50: sehpa ayrı satır, aksesuar ankrajı
 rows.reject{|r|r[:kg].abs<1e-12 && r[:count].zero?}
end

def mst_rebar_source_summary
 all=[];collect_elements(Sketchup.active_model.entities,all)
 mst_boq_rebar_breakdown(all).map{|r|r.merge(t:r[:kg]/1000.0)}
end

def boq_set_prices(payload)
  data=payload.is_a?(String) ? JSON.parse(payload) : payload
  model=Sketchup.active_model
  model.start_operation('Keşif Ayarlarını Güncelle',true)
  (data['prices']||{}).each do |code,val|
    next if boq_template.any? { |r| r[0]==code && BOQ_LIBRARY_IDS.key?(r[4]) }
    model.set_attribute(DICT,"boq_price_#{code}",val.to_f)
  end
  (data['rebar_rates']||{}).each{|key,val| model.set_attribute(DICT,"rebar_rate_#{key}",val.to_f)}
  pile_boq_codes_persist!(model)   # v0.51.5 K35: ayrı poz fiyatı kod-NN'ye bağlı; NN kalıcı
  commit_with_dependencies(model)
  send_boq(@d) if @d && @d.visible?
rescue=>e
  model.abort_operation rescue nil
  UI.messagebox("Keşif ayarı güncelleme hatası: #{e.message}")
end

def pile_driving_length(p)
  seabed=p.get_attribute(DICT,'seabed_elevation_m',nil)
  bottom=p.get_attribute(DICT,'bottom_elevation_m',nil)
  unless seabed.nil? || bottom.nil?
    ratio=p.get_attribute(DICT,'batter_ratio',0).to_f
    return [seabed.to_f-bottom.to_f,0.0].max*Math.sqrt(1.0+ratio*ratio)
  end
  stored=p.get_attribute(DICT,'driving_length_m',nil)
  return [stored.to_f,0.0].max unless stored.nil? || stored.to_s.strip.empty?
  [p.get_attribute(DICT,'actual_length_m',p.get_attribute(DICT,'length_m',0)).to_f,0.0].max
end

def topping_quantities(all)
  decks=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
  area=0.0; vol=0.0
  decks.each do |d|
    legacy=d.get_attribute(DICT,'topping_enabled',nil).nil?
    enabled=legacy || d.get_attribute(DICT,'topping_enabled','0').to_s=='1'
    next unless enabled
    a=d.get_attribute(DICT,'topping_area_m2',nil)
    if a.nil?
      did=d.get_attribute(DICT,'deck_id','').to_s
      curb_area=all.select{|x|x.get_attribute(DICT,'element_type','').to_s=='curb' && x.get_attribute(DICT,'parent_deck_id','').to_s==did}.sum{|c|c.get_attribute(DICT,'length_m',0).to_f*c.get_attribute(DICT,'width_m',0).to_f}
      a=[d.get_attribute(DICT,'gross_area_m2',0).to_f-curb_area,0.0].max
    else
      a=[a.to_f,0.0].max
    end
    th=d.get_attribute(DICT,'topping_thickness_m',0.10).to_f; th=0.10 if th<=0
    area+=a; vol+=a*th
  end
  [area,vol]
end

def boq_quantities
  all=[];collect_elements(Sketchup.active_model.entities,all)
  piles=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
  infills=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='pile_infill_concrete'}
  hbs=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
  decks=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
  curbs=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='curb'}
  crowns=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='crown_wall'}
  flat=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='flat_precast'}
  channels=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='channel_precast'}
  cranes=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='crane_precast'}
  precast=flat+channels+cranes; cast=hbs+decks+curbs
  pile_row=pile_fabrication_qto_row(piles,'TOPLAM',true)
  topping_area,topping_vol=topping_quantities(all)
  pile_infill = pile_row ? pile_row[13].to_f : infills.sum{|e|qto3_quantity(e,:concrete_m3)}
  rebar_kg = mst_boq_rebar_breakdown(all,pile_infill,topping_vol).sum{|r|r[:kg]}   # v0.38 UI1: tek kaynak (BIM / pursantaj)
  {
    'MOBILIZATION'=>1.0,
    'FORMWORK_CAST'=>cast.sum{|e|qto3_quantity(e,:formwork_m2)},
    'FORMWORK_PRECAST'=>precast.sum{|e|qto3_quantity(e,:formwork_m2)},
    'REBAR'=>rebar_kg/1000.0,
    'HB_DECK_CONCRETE'=>hbs.sum{|e|qto3_quantity(e,:concrete_m3)}+decks.sum{|e|qto3_quantity(e,:concrete_m3)},
    'CROWN_FORMWORK'=>crowns.sum{|e|qto3_quantity(e,:formwork_m2)},
    'CROWN_CONCRETE'=>crowns.sum{|e|qto3_quantity(e,:concrete_m3)},
    'CAST_C35_45_OTHER'=>curbs.select{|e|qto_material_class(e).to_s.upcase.gsub(' ','')=='C35/45'}.sum{|e|qto3_quantity(e,:concrete_m3)},
    'PRECAST_C35_45'=>precast.select{|e|qto_material_class(e).to_s.upcase.gsub(' ','')=='C35/45'}.sum{|e|qto3_quantity(e,:concrete_m3)},
    'PRECAST_INSTALL'=>precast.sum{|e|qto3_quantity(e,:concrete_m3)},
    'TOPPING_AREA'=>topping_area,
    'PILE_INFILL'=>pile_infill,
    'PILE_STEEL'=>pile_row ? pile_row[9].to_f : 0.0,
    'PILE_MANIP'=>pile_row ? pile_row[12].to_f : 0.0,
    'PILE_RINGS'=>pile_row ? pile_row[10].to_f+pile_row[11].to_f : 0.0,
    'PILE_SPLICES'=>pile_row ? pile_row[5].to_f : 0.0,
    'PILE_DRIVING'=>piles.sum{|p|pile_driving_length(p)},
    'PILE_PE'=>pile_row ? pile_row[14].to_f : 0.0,
    'PILE_DRILLING'=>pile_row ? pile_row[15].to_f : 0.0,
    'TOPPING_CONCRETE'=>topping_vol
  }
end

# v0.36.5n: BOQ presentation grouping never modifies BIM/QTO source quantities.
PILE_BOQ_GROUP_KEYS=%w[PILE_STEEL PILE_MANIP PILE_RINGS PILE_SPLICES PILE_DRIVING PILE_PE PILE_DRILLING PILE_INFILL].freeze

def pile_boq_mode(key)
 v=Sketchup.active_model.get_attribute(DICT,"pile_boq_mode_#{key}",'combined').to_s
 %w[combined separate].include?(v) ? v : 'combined'
end

def pile_boq_group_quantities(key)
 all=[];collect_elements(Sketchup.active_model.entities,all)
 piles=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
 groups=piles.group_by do |p|
  if key=='PILE_INFILL'
   pile_report_concrete_class(p)
  else
   [p.get_attribute(DICT,'diameter_mm',0).to_f.round(3),p.get_attribute(DICT,'thickness_mm',0).to_f.round(3)]
  end
 end
 groups.sort_by{|k,_|k.is_a?(Array) ? k : [k.to_s]}.map do |group,ps|
  r=pile_fabrication_qto_row(ps,'BOQ',true)
  next unless r
  qty=case key
  when 'PILE_STEEL' then r[9]
  when 'PILE_MANIP' then r[12]
  when 'PILE_RINGS' then r[10]+r[11]
  when 'PILE_SPLICES' then r[5]
  when 'PILE_DRIVING' then r[7]
  when 'PILE_PE' then r[14]
  when 'PILE_DRILLING' then r[15]
  when 'PILE_INFILL' then ps.sum{|p|pile_bim_qto_item(p)[:concrete_m3].to_f}
  end
  label=key=='PILE_INFILL' ? group.to_s : "Ø#{format('%.1f',group[0])} / #{format('%.1f',group[1])} mm"
  [label,qty.to_f,ps,group]
 end.compact.select{|label,qty,ps|qty>0.00000001}
end

# v0.51.5 K35 (ADR-0515 §4, karar B): ayrı poz numarası (NN) kesit grubuna kalıcı bağlanır; anahtar biçimi (kod-NN) değişmez.
# Model DICT pile_boq_group_codes_json = {kaynak:{grup_anahtarı:NN}}; kayıt yoksa son hakediş dönemindeki "(etiket)" ↔ NN,
# kalanlar bugünkü sırayla en büyük NN'den sonra. Silinen numara yeniden kullanılmaz. Okuma yazmaz.
PILE_BOQ_CODES_KEY='pile_boq_group_codes_json'.freeze
def pile_boq_group_key(key,group)
 key=='PILE_INFILL' ? group.to_s : format('d=%.3f|t=%.3f',group[0].to_f,group[1].to_f)
end
def pile_boq_codes_stored(model=Sketchup.active_model)
 h=(JSON.parse(model.get_attribute(DICT,PILE_BOQ_CODES_KEY,'{}').to_s) rescue nil)
 h.is_a?(Hash) ? h : {}
end
def pile_boq_codes_for(key,groups,stored=pile_boq_codes_stored)
 map={};reserved=[0]
 if stored[key].is_a?(Hash)
  stored[key].each{|gk,nn|map[gk.to_s]=nn.to_i if nn.to_i>0}
 else
  last=(respond_to?(:prog2_last_period) ? prog2_last_period : nil) rescue nil
  by_label=groups.group_by{|g|g[0].to_s}
  Array(last && last['rows']).each do |lr|
   k=(lr['key'] || '').to_s;next unless k.start_with?("#{key}@")
   nn=k[/-(\d+)\z/,1].to_i;next unless nn>0
   reserved << nn
   lab=lr['name'].to_s[/\(([^()]*)\)\s*\z/,1];gs=lab && by_label[lab]
   next unless gs && gs.length==1   # etiket iki gruba uyuyorsa tohumlanmaz
   gk=pile_boq_group_key(key,gs[0][3])
   map[gk]=nn unless map.key?(gk) || map.value?(nn)
  end
 end
 groups.each{|g|gk=pile_boq_group_key(key,g[3]);map[gk]||=(map.values+reserved).max+1}
 map
end
# Kalıcı yazım yalnız açık kullanıcı işlemlerinin içinde (çağıranın işlemi); değişiklik yoksa yazmaz.
def pile_boq_codes_persist!(model=Sketchup.active_model)
 # kod inceleme #7: kayıt yalnız AYRI POZ modunda kazık grubu varken okunur / yazılır; bozuksa düzeltme yolu söylenir
 sep=PILE_BOQ_GROUP_KEYS.select{|key|pile_boq_mode(key)=='separate'}.map{|key|[key,pile_boq_group_quantities(key)]}.reject{|_,groups|groups.empty?}
 return false if sep.empty?
 raise "Kazık ayrı poz numaraları kaydı (#{PILE_BOQ_CODES_KEY}) okunamadı; mevcut kaydın üzerine yazılmadı, değişiklik kaydedilmedi. Ayrı poz gerekmiyorsa Keşif → Kazık Keşif Pozu Birleştirme / Ayrıştırma bölümünde AYRI POZ seçili imalatları TEK POZ yapıp kaydedin; ayrı poz gerekiyorsa önce bu kayıt düzeltilmelidir." if mst_json_attr_bad?(model,PILE_BOQ_CODES_KEY,Hash)
 stored=pile_boq_codes_stored(model)
 out=JSON.parse(JSON.generate(stored))
 sep.each{|key,groups|out[key]=pile_boq_codes_for(key,groups,stored)}
 return false if out==stored
 model.set_attribute(DICT,PILE_BOQ_CODES_KEY,JSON.generate(out))
 true
end

def pile_boq_expand_rows(rows)
 rows.flat_map do |row|
  key=row[:source].to_s
  next [row] unless PILE_BOQ_GROUP_KEYS.include?(key) && pile_boq_mode(key)=='separate'
  groups=pile_boq_group_quantities(key)
  next [row] if groups.empty?
  # Grouped values must reconcile with the canonical BOQ source quantity.
  grouped_total=groups.sum{|g|g[1].to_f}
  source_total=row[:quantity].to_f
  tolerance=[0.002,source_total.abs*0.000001].max
  if (grouped_total-source_total).abs>tolerance
   rr=row.dup
   rr[:status]='GRUPLAMA KONTROLÜ GEREKLİ'
   rr[:mapping_reason]="Kaynak #{format('%.3f',source_total)} / kesit toplamı #{format('%.3f',grouped_total)}"
   next [rr]
  end
  # Use the authoritative grouped source for both row amounts and quantity reconciliation.
  codes=pile_boq_codes_for(key,groups)   # v0.51.5 K35: NN kesit grubuna bağlı (sıra numarası değil)
  groups.map do |label,qty,ps,grp|
   rr=row.dup
   rr[:code]="#{row[:code]}-#{format('%02d',codes[pile_boq_group_key(key,grp)])}"
   rr[:name]="#{row[:name]} (#{label})"
   rr[:quantity]=qty
   rr[:group_label]=label
   rr[:split_parent_code]=row[:code]
   rr[:split_mode]='separate'
   rr[:trace_pids]=ps.map(&:persistent_id).uniq
   rr[:library_price]=false if rr[:library_price]
   rr[:unit_price]=row[:unit_price].nil? ? nil : boq_price(rr[:code],row[:unit_price])
   
   rr[:total]=rr[:unit_price].nil? ? nil : qty*rr[:unit_price].to_f
   rr[:status]=rr[:unit_price].nil? ? 'FİYAT EKSİK' : 'MODEL'
   rr
  end
 end
end

def boq_set_pile_modes(payload)
 data=payload.is_a?(String) ? JSON.parse(payload) : payload
 model=Sketchup.active_model
 model.start_operation('Kazık Keşif Poz Gruplaması',true)
 data.each do |key,mode|
  next unless PILE_BOQ_GROUP_KEYS.include?(key.to_s) && %w[combined separate].include?(mode.to_s)
  model.set_attribute(DICT,"pile_boq_mode_#{key}",mode.to_s)
 end
 pile_boq_codes_persist!(model)   # v0.51.5 K35
 model.commit_operation
 send_boq(@d) if @d && @d.visible?
 @d.execute_script("pileBoqSaved(#{JSON.generate(Hash[PILE_BOQ_GROUP_KEYS.map{|k|[k,pile_boq_mode(k)]}])});") if @d && @d.visible?
rescue=>e
 model.abort_operation rescue nil
 UI.messagebox("Kazık keşif gruplama hatası: #{e.message}")
end

def boq_rows(include_inactive=false)
  q=boq_quantities
  library=BOQLibrary.load
  project_mapping=boq_project_mapping
  seeds=BOQLibrary.decode(File.read(File.join(__dir__,'unified_catalog.json'),encoding:'UTF-8'))
  rows=boq_template.map do |code,name,unit,default_price,key|   # v0.47 BQ1: proje poz listesi
    qty=q[key].to_f; mapped=!(key=='TOPPING_AREA' && qty<=0)
    next boq_automatic_drilling_row(qty,library,seeds) if key=='PILE_DRILLING'
    next boq_mapped_row(key,unit,qty,project_mapping[key],library) if project_mapping.key?(key)
    if BOQ_LIBRARY_IDS.key?(key)
      seed=seeds.find { |r| r['id']==BOQ_LIBRARY_IDS[key] }
      item=library.find { |r| r['id']==seed['id'] || r['catalog_key']==seed['catalog_key'] } || seed
      valid=item['unit']==unit && item['currency']=='USD'
      price=valid ? item['unit_price'] : nil
      status=qty<=0 ? 'YOK' : (price.nil? ? 'KÜTÜPHANE FİYATI EKSİK' : 'MODEL')
      next({code:item['code'],name:item['name'],unit:unit,quantity:qty,unit_price:price,
        total:qty<=0 ? 0.0 : (price.nil? ? nil : qty*price),source:key,status:status,
        library_price:true,rate_description:item['rate_description']})
    end
    price=boq_price(code,default_price)
    {code:code,name:name,unit:unit,quantity:qty,unit_price:price,total:qty*price,source:key,status:(mapped ? 'MODEL' : 'YOK')}
  end
  rows.concat(rockfill_boq_rows(library,seeds,project_mapping))
  rows.concat(bp_boq_rows(library,seeds,project_mapping))
  rows.concat(jg_boq_rows(library,project_mapping))
  rows.concat(accessory_boq_rows(library,project_mapping))
  rows.concat(mst_v50_boq_rows(library,project_mapping)) if respond_to?(:mst_v50_boq_rows)   # v0.50: ray, klips, menfez sacı
  rows=pile_boq_expand_rows(rows)
  include_inactive ? rows : rows.select{|r|r[:quantity]>0}
end

def bored_pile_boq_rebar_rate
  all=[]; collect_elements(Sketchup.active_model.entities,all)
  bored=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='bored_pile'}
  weighted=0.0; volume=0.0
  bored.each do |e|
    begin
      d=JSON.parse(e.get_attribute(DICT,'bored_pile_data','{}').to_s)
      next unless d['rebar_mode'].to_s=='rate'
      v=e.get_attribute(DICT,'concrete_volume_m3',0).to_f
      r=d['rebar_rate'].to_f
      next unless v>0 && r>=0
      weighted += v*r; volume += v
    rescue
    end
  end
  volume>0 ? weighted/volume : nil
end

# ===== v0.32.2d QTO <-> BOQ Traceability Source Panel =====
def boq_trace_entities(source)
  all=[]; collect_elements(Sketchup.active_model.entities,all)
  by_type=lambda{|*types| all.select{|e| types.include?(e.get_attribute(DICT,'element_type','').to_s)}}
  case source.to_s
  when 'FORMWORK_CAST' then by_type.call('head_beam','deck_slab','curb')
  when 'FORMWORK_PRECAST','PRECAST_C35_45','PRECAST_INSTALL' then by_type.call('flat_precast','channel_precast','crane_precast')
  when 'HB_DECK_CONCRETE' then by_type.call('head_beam','deck_slab')
  when 'CAST_C35_45_OTHER' then by_type.call('curb')
  when 'CROWN_FORMWORK','CROWN_CONCRETE' then by_type.call('crown_wall')
  when 'TOPPING_AREA','TOPPING_CONCRETE' then by_type.call('deck_topping','deck_slab')
  when 'PILE_INFILL' then by_type.call('steel_pipe_pile').select{|p| pile_bim_qto_item(p)[:concrete_m3].to_f>0}.uniq{|p|p.persistent_id}
  when 'PILE_STEEL','PILE_MANIP','PILE_RINGS','PILE_SPLICES','PILE_DRIVING','PILE_PE','PILE_DRILLING' then by_type.call('steel_pipe_pile')
  when 'REBAR' then QuantityService.rebar_sources(all)   # ADR-0515 G4: bordür donatısı Keşif REBAR'da; izleme de bordürü içerir
  else
    # Project mappings and future BOQ keys may carry their source key in metadata.
    all.select{|e| e.get_attribute(DICT,'boq_source','').to_s==source.to_s}
  end.uniq
end

def boq_trace_payload(source)
  es=boq_trace_entities(source)
  items=es.map do |e|
    et=e.get_attribute(DICT,'element_type','').to_s
    dims=case et
    when 'steel_pipe_pile' then "Ø#{e.get_attribute(DICT,'diameter_mm',0).to_f.round(1)} × t#{e.get_attribute(DICT,'thickness_mm',0).to_f.round(1)} mm · L #{e.get_attribute(DICT,'length_m',0).to_f.round(2)} m"
    when 'bored_pile' then "Ø#{e.get_attribute(DICT,'diameter_mm',0).to_f.round(0)} mm · L #{e.get_attribute(DICT,'length_m',e.get_attribute(DICT,'vertical_length_m',0)).to_f.round(2)} m"
    when 'head_beam','flat_precast','deck_slab','curb' then "#{e.get_attribute(DICT,'length_m',0).to_f.round(2)} × #{e.get_attribute(DICT,'width_m',0).to_f.round(2)} × #{e.get_attribute(DICT,'height_m',e.get_attribute(DICT,'thickness_m',0)).to_f.round(2)} m"
    when 'channel_precast' then "L #{e.get_attribute(DICT,'length_m',0).to_f.round(2)} m · iç #{e.get_attribute(DICT,'inner_width_m',0).to_f.round(2)} × #{e.get_attribute(DICT,'inner_depth_m',0).to_f.round(2)} m"
    else ''
    end
    {uid:ensure_uid(e), id:element_visible_id(e), type:et, pid:e.persistent_id,
     signature:e.get_attribute(DICT,'type_signature',element_signature(e)).to_s,
     concrete_class:(et=='steel_pipe_pile' ? pile_report_concrete_class(e) : e.get_attribute(DICT,'concrete_class','').to_s), dimensions:dims}
  end
  {source:source.to_s,count:items.length,physical_count:items.map{|it|it[:pid]}.uniq.length,items:items}
end

def boq_element_detail(pid, dialog=nil)
  pid=pid.to_i
  model=Sketchup.active_model
  all=[]; collect_elements(model.entities,all)
  e=all.find{|x| x.respond_to?(:persistent_id) && x.persistent_id==pid}
  unless e
    dialog.execute_script("boqElementDetailError(#{JSON.generate('Eleman bulunamadı: PID '+pid.to_s)});") if dialog
    return
  end
  a=lambda{|k| e.get_attribute(DICT,k,nil)}
  first=lambda{|*ks| ks.each{|k| v=a.call(k); return v unless v.nil? || v.to_s.strip==''}; nil}
  et=a.call('element_type').to_s
  conc_class= et=='steel_pipe_pile' ? pile_report_concrete_class(e) : first.call('concrete_class','concrete_grade','topping_concrete_class','saved_infill_concrete_class')
  conc_vol= et=='steel_pipe_pile' ? pile_bim_qto_item(e)[:concrete_m3].to_f : (et=='head_beam' ? head_beam_net_concrete(e) : first.call('concrete_volume_m3','volume_m3','topping_volume_m3','infill_concrete_volume_m3','saved_infill_concrete_volume_m3'))
  formwork=first.call('formwork_area_m2','formwork_net_area_m2')
  rebar_t=first.call('rebar_t')
  steel_kg=first.call('weight_kg','theoretical_weight_kg')
  steel_t=steel_kg.nil? ? nil : steel_kg.to_f/1000.0
  # Element detail must follow the same reinforcement rates used by QTO Engine 3.0.
  rate_key={
    'pile_infill_concrete'=>'pile', 'head_beam'=>'head_beam', 'deck_slab'=>'deck',
    'flat_precast'=>'flat_precast', 'channel_precast'=>'channel_precast','crane_precast'=>'crane_precast',
    'deck_topping'=>'topping', 'crown_wall'=>'crown_wall', 'curb'=>'site_concrete'
  }[et]
  rebar_rate=first.call('rebar_rate','rebar_ratio_kg_m3')
  rebar_rate=rebar_rate(rate_key) if rebar_rate.nil? && rate_key
  if et=='bored_pile'
    rebar_rate=rebar_t.to_f*1000.0/conc_vol.to_f if rebar_rate.nil? && conc_vol.to_f>0 && !rebar_t.nil?
  elsif rebar_t.nil? && !rebar_rate.nil? && conc_vol.to_f>0
    rebar_t=conc_vol.to_f*rebar_rate.to_f/1000.0
  end
  if rebar_rate.nil? && conc_vol.to_f>0 && !rebar_t.nil?
    rebar_rate=rebar_t.to_f*1000.0/conc_vol.to_f
  end
  data={
    pid:e.persistent_id, id:element_visible_id(e), type:et,
    concrete_class:conc_class, concrete_m3:(conc_vol.nil? ? nil : conc_vol.to_f),
    rebar_t:(rebar_t.nil? ? nil : rebar_t.to_f),
    rebar_rate:(rebar_rate.nil? ? nil : rebar_rate.to_f),
    formwork_m2:(formwork.nil? ? nil : formwork.to_f),
    steel_t:steel_t
  }
  er=mst_element_rebar(e)   # v0.38 UI1: tek kaynak
  unless er['source']=='-'
    data[:rebar_t]=er['kg']/1000.0;data[:rebar_rate]=er['rate'] || (conc_vol.to_f>0 ? er['kg']/conc_vol.to_f : nil);data[:rebar_source]=er['source']
  end
  dialog.execute_script("boqShowElementDetail(#{JSON.generate(data)});") if dialog
rescue=>ex
  dialog.execute_script("boqElementDetailError(#{JSON.generate('Detay okunamadı: '+ex.message)});") if dialog
end

def boq_group_detail(raw, dialog=nil)
  ids=raw.to_s.split(',').map(&:to_i).reject{|x|x<=0}.uniq
  model=Sketchup.active_model; all=[]; collect_elements(model.entities,all)
  es=all.select{|x|x.respond_to?(:persistent_id) && ids.include?(x.persistent_id)}
  return dialog.execute_script("boqElementDetailError(#{JSON.generate('Grup elemanı bulunamadı.')});") if es.empty? && dialog
  sum=lambda{|*ks| es.inject(0.0){|t,e| v=nil; ks.each{|k| q=e.get_attribute(DICT,k,nil); if !q.nil? && q.to_s.strip!=''; v=q; break; end}; t+(v.nil? ? 0.0 : v.to_f)}}
  et=es.first.get_attribute(DICT,'element_type','').to_s
  conc=sum.call('concrete_volume_m3','volume_m3','topping_volume_m3','infill_concrete_volume_m3')
  conc-=es.select{|x|x.get_attribute(DICT,'element_type','').to_s=='head_beam'}.sum{|x|head_beam_gross_concrete(x)-head_beam_net_concrete(x)}   # v0.47 BK1
  form=sum.call('formwork_area_m2','formwork_net_area_m2')
  steel=sum.call('weight_kg','theoretical_weight_kg')/1000.0
  rate_key={'pile_infill_concrete'=>'pile','head_beam'=>'head_beam','deck_slab'=>'deck','flat_precast'=>'flat_precast','channel_precast'=>'channel_precast','crane_precast'=>'crane_precast','deck_topping'=>'topping','crown_wall'=>'crown_wall','curb'=>'site_concrete'}[et]
  rate=es.first.get_attribute(DICT,'rebar_rate',es.first.get_attribute(DICT,'rebar_ratio_kg_m3',nil)); rate=rebar_rate(rate_key) if rate.nil? && rate_key
  rebar=sum.call('rebar_t')
  rebar=conc*rate.to_f/1000.0 if rebar<=0 && !rate.nil? && conc>0
  cls=es.map{|e|e.get_attribute(DICT,'concrete_class','').to_s}.reject(&:empty?).uniq.join(' / ')
  data={id:"#{bim_type_label(et)} · #{es.length} adet",type:et,count:es.length,concrete_class:cls,concrete_m3:conc,rebar_t:rebar,rebar_rate:(rate.nil? ? nil : rate.to_f),formwork_m2:form,steel_t:steel}
  if (MST_REBAR_RATE_KEYS.key?(et) || et=='bored_pile')   # v0.38 UI1
    rs=mst_rebar_sum(es);data[:rebar_t]=rs['kg']/1000.0;data[:rebar_source]=rs['label'];data[:rebar_rate]=(conc>0 ? rs['kg']/conc : data[:rebar_rate])
  end
  dialog.execute_script("boqShowElementDetail(#{JSON.generate(data)});") if dialog
rescue=>ex
  dialog.execute_script("boqElementDetailError(#{JSON.generate('Grup detayı okunamadı: '+ex.message)});") if dialog
end

def boq_select_sources(payload, dialog=nil)
  data=payload.is_a?(String) ? JSON.parse(payload) : payload
  source=data['source'].to_s; uid=data['uid'].to_s
  es=boq_trace_entities(source)
  es=es.select{|e|e.get_attribute(DICT,'element_uid','').to_s==uid} unless uid.empty?
  es=es.select{|e| e.respond_to?(:valid?) && e.valid?}
  model=Sketchup.active_model
  sel=model.selection
  sel.clear
  es.each{|e| begin; sel.add(e); rescue; end }
  model.active_view.zoom(sel) unless sel.empty?
  count=sel.length
  msg = count==0 ? "#{source} için kaynak bulundu ancak aktif model bağlamında seçilebilir eleman bulunamadı." : nil
  if dialog
    dialog.execute_script("boqTraceResult(#{JSON.generate(source)},#{count},#{JSON.generate(msg)});")
  end
  count
rescue=>e
  dialog.execute_script("boqTraceResult(#{JSON.generate(defined?(source) ? source.to_s : '')},0,#{JSON.generate('Keşif kaynak seçimi hatası: '+e.message)});") if dialog
  0
end
# ===== end v0.32.2 =====

def send_boq(dialog=@d)
mst_read_batch do   # v0.51.5 P2: salt okuma, tek model taraması
  rows=boq_rows
  rows.each do |r|
   r[:trace]=boq_trace_payload(r[:source])
   if r[:trace_pids]
    r[:trace][:items].select!{|it|r[:trace_pids].include?(it[:pid])}
    r[:trace][:items].uniq!{|it|it[:pid]}
    r[:trace][:count]=r[:trace][:items].length
    r[:trace][:physical_count]=r[:trace][:items].map{|it|it[:pid]}.uniq.length
   end
  end
  data={rows:rows,total:rows.sum{|r|r[:total].to_f},missing_prices:rows.count{|r|r[:total].nil?},currency:(respond_to?(:boq2_currency) ? boq2_currency : 'USD'),rebar_rates:Hash[REBAR_DEFAULTS.keys.map{|k| [k,rebar_rate(k)]}],fore_rebar_rate:bored_pile_boq_rebar_rate,project:(qto3_snapshot[:scopes][:projects].first || ''),pile_boq_modes:Hash[PILE_BOQ_GROUP_KEYS.map{|k|[k,pile_boq_mode(k)]}],rebar_sources:(mst_rebar_source_summary rescue [])}
  # v0.51.5 K33/K39/K40: bilgi satırları toplam ve eksik fiyat sayısı hesaplandıktan SONRA eklenir (tutara girmez)
  info=mst_boq_info_rows
  data[:info_rows]=info
  data[:rows]=rows+info
  dialog.execute_script("setBOQ(#{JSON.generate(data)});") if dialog
end # mst_read_batch
rescue=>e
  UI.messagebox("Keşif oluşturma hatası: #{e.message}")
end
# ===== end v0.23.1 =====


def pile_report_system(p)
 v=p.get_attribute(DICT,'system','').to_s.strip
 v.empty? ? 'SİSTEM BELİRTİLMEMİŞ' : v.upcase
end

def pile_report_structure(p)
 v=p.get_attribute(DICT,'structure','').to_s.strip
 v.empty? ? 'YAPI BELİRTİLMEMİŞ' : v
end

def pile_report_concrete_class(p)
 children=pile_qto_infill_children(p)
 enabled=p.get_attribute(DICT,'infill_enabled',nil)
 return 'BETON YOK' if enabled.to_s=='0' && children.empty?
 # Preserve the current editor's live class, then read legacy physical children.
 v=p.get_attribute(DICT,'infill_concrete_class','').to_s.strip
 if v.empty?
  classes=children.map{|g|g.get_attribute(DICT,'concrete_class','').to_s.strip}.reject(&:empty?).uniq
  return 'KARMA BETON SINIFI' if classes.length>1
  v=classes.first.to_s
 end
 v=p.get_attribute(DICT,'saved_infill_concrete_class','').to_s.strip if v.empty?
 v.empty? ? 'SINIF BELİRTİLMEMİŞ' : v
end

def pile_report_concrete_classes(piles)
 piles.map{|p|[p,pile_bim_qto_item(p)]}.select{|p,item|item[:concrete_m3].to_f>0.0000001}.group_by{|p,item|pile_report_concrete_class(p)}.sort.map{|klass,items|[klass,items.length,items.sum{|p,item|item[:concrete_m3].to_f}]}
end

def qto_summary(dialog)
mst_read_batch do   # v0.51.5 P2: salt okuma, tek model taraması
 a=[];collect_elements(Sketchup.active_model.entities,a)
 ps=a.select{|e|e.get_attribute(DICT,'element_type')=='steel_pipe_pile'}
 inf=a.select{|e|e.get_attribute(DICT,'element_type')=='pile_infill_concrete'}
 bs=a.select{|e|e.get_attribute(DICT,'element_type')=='head_beam'}
 pd=a.select{|e|e.get_attribute(DICT,'element_type')=='flat_precast'}
 ch=a.select{|e|e.get_attribute(DICT,'element_type')=='channel_precast'}
 cr=a.select{|e|e.get_attribute(DICT,'element_type')=='crane_precast'}
 dk=a.select{|e|e.get_attribute(DICT,'element_type')=='deck_slab'}
 cb=a.select{|e|e.get_attribute(DICT,'element_type')=='curb'}
 cw=a.select{|e|e.get_attribute(DICT,'element_type')=='crown_wall'}
 plen=ps.sum{|x|qto3_quantity(x,:length_m)};steel=ps.sum{|x|mst_pile_canonical_weight_kg(x)}/1000.0
 snap=qto3_snapshot
 infill_row=snap[:rows].find{|row|row[:type]=='pile_infill_concrete'}
 iv=infill_row ? infill_row[:concrete_m3] : 0.0
 infill_count=infill_row ? infill_row[:count] : 0
bv=bs.sum{|x|head_beam_net_concrete(x)};bf=bs.sum{|x|head_beam_net_formwork_area(x)}
 pv=pd.sum{|x|x.get_attribute(DICT,'concrete_volume_m3',0).to_f};pf=pd.sum{|x|x.get_attribute(DICT,'formwork_area_m2',0).to_f};cv=ch.sum{|x|x.get_attribute(DICT,'concrete_volume_m3',0).to_f};cf=ch.sum{|x|x.get_attribute(DICT,'formwork_area_m2',0).to_f};crv=cr.sum{|x|x.get_attribute(DICT,'concrete_volume_m3',0).to_f};crf=cr.sum{|x|x.get_attribute(DICT,'formwork_area_m2',0).to_f};dv=dk.sum{|x|x.get_attribute(DICT,'concrete_volume_m3',0).to_f};df=dk.sum{|x|x.get_attribute(DICT,'formwork_area_m2',0).to_f};cbv=cb.sum{|x|x.get_attribute(DICT,'concrete_volume_m3',0).to_f};cbf=cb.sum{|x|x.get_attribute(DICT,'formwork_area_m2',0).to_f};cwv=cw.sum{|x|x.get_attribute(DICT,'concrete_volume_m3',0).to_f};cwf=cw.sum{|x|x.get_attribute(DICT,'formwork_area_m2',0).to_f}
 topping_area,topping_vol=topping_quantities(a)
 deck_total_vol=dv+cbv+topping_vol
 deck_total_rebar_t=(mst_rebar_sum(dk)['kg'] + topping_vol*rebar_rate('topping'))/1000.0   # v0.38 UI1
 # v0.51.5 K08/K41 (yalnız gösterim): döşeme ve kaplama ayrı satır; tonaj hücresinde türü yazılır. BOQ değişmez.
 rows="<tr><td>Kazık</td><td>Çelik Boru Kazık</td><td>#{ps.length}</td><td>#{format('%.2f',plen)} m</td><td>-</td><td>-</td><td>#{format('%.3f',steel)} t <small style='color:#5b6b7b'>(boru çeliği)</small></td></tr>"+
 "<tr><td>Beton</td><td>Kazık İçi Beton</td><td>#{infill_count}</td><td>-</td><td>#{format('%.3f',iv)} m³</td><td>-</td><td>#{format('%.3f',(infill_row && infill_row[:steel_t]) ? infill_row[:steel_t].to_f : iv*rebar_rate('pile')/1000.0)} t <small style='color:#5b6b7b'>(donatı)</small></td></tr>"+
 "<tr><td>Betonarme</td><td>Başlık Kirişi</td><td>#{bs.length}</td><td>-</td><td>#{format('%.3f',bv)} m³</td><td>#{format('%.2f',bf)} m²</td><td>#{mst_rebar_cell(bs)}</td></tr>"+
 "<tr><td>Prekast</td><td>Normal PD</td><td>#{pd.length}</td><td>-</td><td>#{format('%.3f',pv)} m³</td><td>#{format('%.2f',pf)} m²</td><td>#{mst_rebar_cell(pd)}</td></tr>"+
 "<tr><td>Prekast</td><td>Kanal Prekastı</td><td>#{ch.length}</td><td>-</td><td>#{format('%.3f',cv)} m³</td><td>#{format('%.2f',cf)} m²</td><td>#{mst_rebar_cell(ch)}</td></tr>"+
 "<tr><td>Prekast</td><td>Vinç Prekastı</td><td>#{cr.length}</td><td>-</td><td>#{format('%.3f',crv)} m³</td><td>#{format('%.2f',crf)} m²</td><td>#{mst_rebar_cell(cr)}</td></tr>"+
 "<tr><td>Betonarme</td><td>Döşeme</td><td>#{dk.length}</td><td>-</td><td>#{format('%.3f',dv+cbv)} m³</td><td>#{format('%.2f',df+cbf)} m²</td><td>#{format('%.3f',mst_rebar_sum(dk)['kg']/1000.0)} t <small style='color:#5b6b7b'>(#{html_escape(mst_rebar_sum(dk)['label'])})</small></td></tr>"+
 (topping_vol>0 ? "<tr><td>Betonarme</td><td>Kaplama <small style='color:#5b6b7b'>(Toplam Beton'a dahil; keşifte ayrı kalem ÖBF-072)</small></td><td>-</td><td>-</td><td>#{format('%.3f',topping_vol)} m³</td><td>-</td><td>#{format('%.3f',topping_vol*rebar_rate('topping')/1000.0)} t <small style='color:#5b6b7b'>(donatı; hacim × #{format('%.0f',rebar_rate('topping'))} kg/m³ pursantaj)</small></td></tr>" : '')+
 "<tr><td>Betonarme</td><td>Kronman</td><td>#{cw.length}</td><td>-</td><td>#{format('%.3f',cwv)} m³</td><td>#{format('%.2f',cwf)} m²</td><td>#{mst_rebar_cell(cw)}</td></tr>"
 elems=snap[:elements].reject{|e|e.get_attribute(DICT,'element_type','')=='pile_infill_concrete'}
 status=qto_workspace_status(elems,ps)
 missing=status[:incomplete_count]
 pile_qto_rows=pile_qto_hierarchy(ps)
 pile_qto_total=pile_fabrication_qto_row(ps,'TOPLAM',true)
 pile_bim_qto_rows=ps.map{|p|pile_bim_qto_item(p)}.sort_by{|x|x[:pile_id]}
 infill_summary=iv
 concrete_summary=snap[:totals][:concrete_m3].to_f+topping_vol   # ADR-0515 G6: Toplam Beton kaplamayı içerir (qto3_snapshot değişmez)
 concrete_breakdown={
  'BK'=>bv, 'PD'=>pv+cv+crv, 'DOSP'=>dv+cbv,   # K08: kaplama ayrı satırda; G6: KAPLAMA kırılımı Toplam Beton'a dahil (DİĞER qto3_snapshot'tan, değişmez)
  'KAPLAMA'=>topping_vol,
  'KRONMAN'=>cwv, 'ÇBK'=>infill_summary,
  'DİĞER'=>snap[:totals][:concrete_m3].to_f-(bv+pv+cv+crv+dv+cbv+cwv+iv)
 }
 concrete_breakdown.delete_if{|_,v|v.abs<0.0000001}
 rfq=rockfill_qto_data
 if rfq[:materials].length > 0
  rows += "<tr><td>Dolgu</td><td>#{html_escape(rfq[:source_label] || 'Dolgu / Taş (AEA)')}</td><td>#{rfq[:sections].length}</td><td>-</td><td>#{format('%.3f',rfq[:total_volume_m3])} m³</td><td>-</td><td>#{format('%.3f',rfq[:total_tonnage_t])} t <small style='color:#5b6b7b'>(dolgu tonajı)</small></td></tr>"
 end
 qto3_rows_with_rockfill=snap[:rows].dup
 if rfq[:materials].length > 0
  qto3_rows_with_rockfill << {type:'rockfill',name:(rfq[:source_label] || 'Dolgu / Taş (AEA)'),count:(rfq[:solid_count] || rfq[:sections].length),length_m:0.0,concrete_m3:rfq[:total_volume_m3],formwork_m2:0.0,steel_t:rfq[:total_tonnage_t]}
 end
 data={jet_grout_html:jg_report_html,version:VERSION,qto_status:status,pile_count:ps.length,pile_length:plen,steel_ton:steel,pd_count:pd.length,pd_volume:pv,channel_count:ch.length,channel_volume:cv,total_concrete:concrete_summary,concrete_breakdown:concrete_breakdown,total_formwork:snap[:totals][:formwork_m2],element_count:elems.length,audit_missing:missing,audit_ok:elems.length-missing,rows:rows,pile_qto_rows:pile_qto_rows,pile_qto_total:pile_qto_total,pile_bim_qto_rows:pile_bim_qto_rows,qto3_rows:qto3_rows_with_rockfill,qto3_concrete:snap[:concrete_by_class],qto3_scopes:snap[:scopes],rockfill_material_count:rfq[:materials].length,rockfill_section_count:(rfq[:solid_count] || rfq[:sections].length),rockfill_volume_m3:rfq[:total_volume_m3],rockfill_tonnage_t:rfq[:total_tonnage_t]}
 dialog.execute_script("setQTO(#{JSON.generate(data)});")
end # mst_read_batch
rescue=>e
 dialog.execute_script("qtoError(#{JSON.generate(e.message)})") if dialog
 UI.messagebox("Metraj özet hatası: #{e.message}")
end

def takeoff(mode='all',want=nil)
 a=[];collect_elements(Sketchup.active_model.entities,a)
 ps=a.select{|e|e.get_attribute(DICT,'element_type')=='steel_pipe_pile'}
 infills=a.select{|e|e.get_attribute(DICT,'element_type')=='pile_infill_concrete'}
 bs=a.select{|e|e.get_attribute(DICT,'element_type')=='head_beam'}
 plen=ps.sum{|p|p.get_attribute(DICT,'length_m',0).to_f};ton=ps.sum{|p|mst_pile_canonical_weight_kg(p)}/1000.0

 pile_grouped=ps.group_by do |pile|
  d=pile.get_attribute(DICT,'diameter_mm',0).to_f
  t=pile.get_attribute(DICT,'thickness_mm',0).to_f
  steel=pile.get_attribute(DICT,'steel_grade','Belirsiz').to_s
  zone=pile.get_attribute(DICT,'elevation_zone','NORMAL').to_s
  [d,t,steel,zone]
 end
 pile_rows=String.new
 pile_sections=pile_grouped.keys.group_by{|k|[k[0],k[1],k[2]]}.keys.sort_by{|k|sprintf('%012.3f|%012.3f|%s',k[0].to_f,k[1].to_f,k[2].to_s)}
 pile_sections.each do |section|
  d,t,steel=section
  keys=pile_grouped.keys.select{|k|[k[0],k[1],k[2]]==section}.sort_by{|k|k[3].to_s}
  section_items=[]
  keys.each do |key|
   zone=key[3];items=pile_grouped[key];section_items.concat(items)
   len_sum=items.sum{|pile|pile.get_attribute(DICT,'length_m',0).to_f}
   wt=items.sum{|pile|mst_pile_canonical_weight_kg(pile)}/1000.0
   ids=items.map{|pile|pile.get_attribute(DICT,'pile_id','').to_s}.reject(&:empty?).join(', ')
   pile_rows << "<tr><td>Ø#{format('%.1f',d)} x #{format('%.1f',t)} mm</td><td>#{html_escape(steel)}</td><td>#{html_escape(zone)}</td><td>#{items.length}</td><td>#{html_escape(ids)}</td><td>#{format('%.2f',len_sum)} m</td><td><b>#{format('%.3f',wt)} t</b></td></tr>"
  end
  sl=section_items.sum{|pile|pile.get_attribute(DICT,'length_m',0).to_f}
  sw=section_items.sum{|pile|mst_pile_canonical_weight_kg(pile)}/1000.0
  pile_rows << "<tr class='subtotal'><td>Ø#{format('%.1f',d)} x #{format('%.1f',t)} mm ARA TOPLAM</td><td>#{html_escape(steel)}</td><td>-</td><td>#{section_items.length}</td><td>-</td><td>#{format('%.2f',sl)} m</td><td>#{format('%.3f',sw)} t</td></tr>"
 end
 # Detailed fabrication / installation QTO: this is the canonical pile detail report.
 pile_qto_detail_rows=String.new
 pile_detail_line=lambda do |label,items,kind|
  r=pile_fabrication_qto_row(items,label,true); next '' unless r
  klass_rows=pile_report_concrete_classes(items)
  cells=[html_escape(label), (kind==:section ? format('%.1f',items.first.get_attribute(DICT,'diameter_mm',0).to_f) : '—'),(kind==:section ? format('%.1f',items.first.get_attribute(DICT,'thickness_mm',0).to_f) : '—'),r[3],r[4],r[5],format('%.2f',r[6]),format('%.2f',r[7]),format('%.3f',r[8]),format('%.3f',r[9]),format('%.2f',r[10]),format('%.2f',r[11]),format('%.3f',r[12]),format('%.3f',r[13]),format('%.3f',r[13].to_f*rebar_rate('pile')/1000.0),format('%.2f',r[14]),format('%.2f',r[15])]
  css=kind==:project ? 'total' : (kind==:section ? '' : 'subtotal')
  out="<tr class='#{css}'>"+cells.map{|v|"<td>#{v}</td>"}.join+'</tr>'
  # Class breakdown is informational, not an additional quantity-bearing pile row.
  if kind==:section && klass_rows.length>0
   klass_rows.each do |klass,n,vol|
    kitems=items.select{|pp|pile_report_concrete_class(pp)==klass}
    kreb=kitems.any?{|pp|mst_pile_rebar_active(pp)} ? kitems.sum{|pp|mst_pile_rebar_t(pp)} : vol*rebar_rate('pile')/1000.0   # v0.38 PR1
    out << "<tr class='concrete-class-row'><td>↳ Beton #{html_escape(klass)} (#{n} kazık)</td>"+('<td></td>'*12)+"<td>#{format('%.3f',vol)}</td><td>#{format('%.3f',kreb)}</td><td></td><td></td></tr>"
   end
  end
  out
 end
 sn=mst_structure_display_names(Sketchup.active_model)   # ADR-0515-I: ara toplam etiketi görünen ad; gruplama kodla
 ps.group_by{|p|pile_report_system(p)}.sort.each do |system,sys_piles|
  pile_qto_detail_rows << pile_detail_line.call("#{system} — GENEL TOPLAM",sys_piles,:system)
  sys_piles.group_by{|p|pile_report_structure(p)}.sort.each do |structure,structure_piles|
   pile_qto_detail_rows << pile_detail_line.call("↳ #{mst_structure_display(structure,sn)} — ARA TOPLAM",structure_piles,:structure)
   structure_piles.group_by{|p|[p.get_attribute(DICT,'diameter_mm',0).to_f.round(3),p.get_attribute(DICT,'thickness_mm',0).to_f.round(3)]}.sort.each do |sec,sp|
    pile_qto_detail_rows << pile_detail_line.call("↳ #{mst_structure_display(structure,sn)} / Ø#{format('%.1f',sec[0])} × #{format('%.1f',sec[1])}",sp,:section)
   end
  end
 end
 pile_qto_detail_rows << pile_detail_line.call('PROJE GENEL TOPLAMI',ps,:project) unless ps.empty?
 # v0.36.3: full per-pile BIM detail belongs only to the dedicated pile report.
 pile_items=ps.map{|pile|pile_bim_qto_item(pile)}.sort_by{|x|x[:pile_id].to_s}
 detail_cols=[['pile_id','Kazık ID'],['system','Sistem'],['structure','Yapı'],['grid_point','Aks Noktası'],['diameter_mm','Ø (mm)'],['thickness_mm','t (mm)'],['length_m','L (m)'],['steel_grade','Çelik'],['concrete_class','Beton Sınıfı'],['steel_t','Boru (t)'],['concrete_m3','Beton (m³)'],['pe_m2','PE (m²)'],['drilling_m','Foraj (m)'],['plug_count','Tapa (adet)'],['plug_kg','Tapa (kg)'],['lower_ring_kg','Alt/İç (kg)'],['upper_ring_kg','Üst/Dış (kg)']]
 numeric_cols=%w[length_m steel_t concrete_m3 pe_m2 drilling_m plug_count plug_kg lower_ring_kg upper_ring_kg]
 sum_keys=%w[length_m steel_t concrete_m3 pe_m2 drilling_m plug_count plug_kg lower_ring_kg upper_ring_kg]
 section_row=lambda do |label,items,kind|
  sums=sum_keys.map{|k|items.sum{|x|x[k.to_sym].to_f}}
  css=kind==:project ? 'total' : (kind==:section ? '' : 'subtotal')
  "<tr class='#{css}'><td>#{html_escape(label)}</td><td>#{items.size}</td>"+sums.each_with_index.map{|v,i|"<td>#{i==5 ? v.to_i : format('%.3f',v)}</td>"}.join+'</tr>'
 end
 section_rows=String.new
 pile_items.group_by{|x|x[:system].to_s.strip.empty? ? 'SİSTEM BELİRTİLMEMİŞ' : x[:system].to_s.upcase}.sort.each do |system,sys_items|
  section_rows << section_row.call("#{system} — GENEL TOPLAM",sys_items,:system)
  sys_items.group_by{|x|x[:structure].to_s.strip.empty? ? 'YAPI BELİRTİLMEMİŞ' : x[:structure].to_s}.sort.each do |structure,st_items|
   section_rows << section_row.call("↳ #{mst_structure_display(structure,sn)} — ARA TOPLAM",st_items,:structure)
   st_items.group_by{|x|[x[:diameter_mm].to_f.round(3),x[:thickness_mm].to_f.round(3)]}.sort.each do |sec,items|
    section_rows << section_row.call("↳ #{mst_structure_display(structure,sn)} / Ø#{format('%.1f',sec[0])} × #{format('%.1f',sec[1])}",items,:section)
   end
  end
 end
 section_rows << section_row.call('PROJE GENEL TOPLAMI',pile_items,:project)
 detail_rows=pile_items.map do |item|
  attrs=detail_cols.map do |key,title|
   val=item[key.to_sym]
   val= key=='plug_count' ? val.to_i : format('%.3f',val.to_f) if numeric_cols.include?(key)
   val=mst_structure_label(val,sn) if key=='structure' && !val.to_s.strip.empty?   # G5c ADR-0515-I: "Ad (kod)"; süzgeç değeri (data-structure) kod
   "<td>#{html_escape(val.to_s)}</td>"
  end.join
  "<tr class='bim-pile-row' data-search='#{html_escape([item[:pile_id],item[:system],item[:structure],*((item[:structure].to_s.strip.empty? || (dn_=mst_structure_display(item[:structure],sn))==item[:structure].to_s) ? [] : [dn_]),item[:grid_point],item[:diameter_mm],item[:thickness_mm]].join(' ').downcase)}' data-section='#{html_escape("#{item[:diameter_mm].to_f.round(3)}x#{item[:thickness_mm].to_f.round(3)}")}' data-structure='#{html_escape(item[:structure].to_s)}' data-values='#{sum_keys.map{|k|item[k.to_sym].to_f}.join(',')}'>#{attrs}</tr>"
 end.join
 options=pile_items.map{|x|x[:structure].to_s}.uniq.sort.map{|x|"<option value='#{html_escape(x)}'>#{html_escape(x.strip.empty? ? x : mst_structure_label(x,sn))}</option>"}.join   # G5c: value kod, metin "Ad (kod)"
 sections_opts=pile_items.map{|x|"#{x[:diameter_mm].to_f.round(3)}x#{x[:thickness_mm].to_f.round(3)}"}.uniq.sort.map{|x|"<option value='#{html_escape(x)}'>#{html_escape(x.tr('x',' × '))} mm</option>"}.join
 summary_heads=['Kesit','Adet','Boy (m)','Boru (t)','Beton (m³)','PE (m²)','Foraj (m)','Tapa (adet)','Tapa (kg)','Alt/İç (kg)','Üst/Dış (kg)'].map{|h|"<th>#{h}</th>"}.join
 pile_bim_html="<h3>Kesit Bazlı BIM / Metraj Özeti</h3><div class='note'>Sistem → yapı → Ø × t ara toplamları ve proje genel toplamı; alt satırlar toplama tekrar eklenmez.</div><div class='table-scroll'><table class='pile-detail'><thead><tr>#{summary_heads}</tr></thead><tbody>#{section_rows}</tbody></table></div><h3>Kazık ID Bazlı Detaylı Metraj</h3><div class='pile-filters'><input id='pileSearch' placeholder='Kazık ID, aks veya kesit ara...' oninput='filterPileRows()'><select id='pileStructure' onchange='filterPileRows()'><option value=''>Tüm yapılar</option>#{options}</select><select id='pileSection' onchange='filterPileRows()'><option value=''>Tüm kesitler</option>#{sections_opts}</select><span id='pileFilterCount'></span></div><div class='table-scroll'><table class='pile-detail'><thead><tr>#{detail_cols.map{|c|"<th>#{c[1]}</th>"}.join}</tr></thead><tbody>#{detail_rows}</tbody><tfoot><tr class='subtotal' id='pileFilteredTotal'><td>FİLTRELENEN ARA TOPLAM</td>#{'<td></td>' * 5}<td>—</td>#{'<td></td>' * 2}#{'<td>—</td>' * 8}</tr></tfoot></table></div>"
 pile_filter_script=%q{<script>function filterPileRows(){var q=document.getElementById('pileSearch').value.toLocaleLowerCase('tr-TR').trim(),st=document.getElementById('pileStructure').value,sec=document.getElementById('pileSection').value,rows=document.querySelectorAll('.bim-pile-row'),sums=Array(9).fill(0),count=0;rows.forEach(function(r){var ok=(!q||r.dataset.search.toLocaleLowerCase('tr-TR').includes(q))&&(!st||r.dataset.structure===st)&&(!sec||r.dataset.section===sec);r.style.display=ok?'':'none';if(ok){count++;r.dataset.values.split(',').forEach(function(v,i){sums[i]+=Number(v)||0})}});document.getElementById('pileFilterCount').textContent=count+' / '+rows.length+' kazık';document.getElementById('pileFilteredTotal').innerHTML=(function(){var cells=Array(17).fill('');cells[0]='FİLTRELENEN ARA TOPLAM ('+count+' kazık)';var cols=[6,9,10,11,12,13,14,15,16];sums.forEach(function(v,i){cells[cols[i]]=i===5?String(Math.round(v)):v.toFixed(3)});return cells.map(function(v){return '<td>'+v+'</td>'}).join('')})();};filterPileRows();</script>}
 pile_html="<h3>Çelik Boru Kazık Detay Metrajı</h3><div class='note'>İmalat + çakım + tapa + ek + üst/alt çarık + manipülasyon + kazık içi beton + PE kaplama + foraj</div><div class='table-scroll'><table class='pile-detail'><thead><tr class='group-head'><th colspan='4'>KAZIK BİLGİLERİ</th><th colspan='4'>İMALAT / MONTAJ</th><th colspan='5'>AĞIRLIKLAR</th><th colspan='4'>DİĞER İMALATLAR</th></tr><tr><th>Sistem / Yapı / Kesit</th><th>Ø (mm)</th><th>t (mm)</th><th>Kazık Ad.</th><th>Tapa Ad.</th><th>Ek Ad.</th><th>İmal Boyu (m)</th><th>Çakım Boyu (m)</th><th>Tapa (t)</th><th>Kazık İmal (t)</th><th>Üst Çarık (kg)</th><th>Alt Çarık (kg)</th><th>Manipülasyon (t)</th><th>Beton (m³)</th><th>Kazık İçi Donatı (t)</th><th>PE Kaplama (m²)</th><th>Foraj (m)</th></tr></thead><tbody>#{pile_qto_detail_rows}</tbody></table></div>"


 grouped=bs.group_by do |b|
  type=b.get_attribute(DICT,'beam_type','BK-?').to_s
  conc=b.get_attribute(DICT,'concrete_class','Belirsiz').to_s
  [type,conc]
 end
 rows=String.new
 grouped.keys.group_by{|k|k[1]}.keys.sort_by{|x|x.to_s}.each do |klass|
  class_items=[]
  grouped.keys.select{|k|k[1]==klass}.sort_by{|k|k[0].to_s}.each do |key|
   type,_=key;items=grouped[key];class_items.concat(items)
   vol=items.sum{|beam|head_beam_net_concrete(beam)}
   gross=items.sum{|beam|head_beam_gross_formwork_area(beam)}
   deduct=items.sum{|beam|head_beam_pile_opening_area(beam)}
   net=[gross-deduct,0.0].max
   axes=items.map{|beam|beam.get_attribute(DICT,'axis','').to_s}.reject(&:empty?).join(', ')
   rows << "<tr><td>#{html_escape(type)}</td><td>#{html_escape(klass)}</td><td>#{items.length}</td><td>#{html_escape(axes)}</td><td>#{format('%.3f',vol)} m³</td><td>#{format('%.2f',gross)} m²</td><td>-#{format('%.2f',deduct)} m²</td><td><b>#{format('%.2f',net)} m²</b></td><td>#{mst_rebar_cell(items,true)}</td></tr>"
  end
  cv=class_items.sum{|beam|head_beam_net_concrete(beam)}
  cg=class_items.sum{|beam|head_beam_gross_formwork_area(beam)}
  cd=class_items.sum{|beam|head_beam_pile_opening_area(beam)}
  cn=[cg-cd,0.0].max
  rows << "<tr class='subtotal'><td>#{html_escape(klass)} ARA TOPLAM</td><td>#{html_escape(klass)}</td><td>#{class_items.length}</td><td>-</td><td>#{format('%.3f',cv)} m³</td><td>#{format('%.2f',cg)} m²</td><td>-#{format('%.2f',cd)} m²</td><td>#{format('%.2f',cn)} m²</td><td>#{mst_rebar_cell(class_items)}</td></tr>"
 end
 total_vol=bs.sum{|b|head_beam_net_concrete(b)}
 total_gross=bs.sum{|b|head_beam_gross_formwork_area(b)};total_deduct=bs.sum{|b|head_beam_pile_opening_area(b)}
 total_net=[total_gross-total_deduct,0.0].max

 infill_grouped=infills.group_by{|c|[c.get_attribute(DICT,'concrete_class','Belirsiz').to_s,c.get_attribute(DICT,'elevation_zone','NORMAL').to_s]}
 infill_rows=String.new
 infill_grouped.keys.group_by{|k|k[0]}.keys.sort_by{|x|x.to_s}.each do |klass|
  class_items=[]
  infill_grouped.keys.select{|k|k[0]==klass}.sort_by{|k|k[1].to_s}.each do |key|
   _,zone=key;items=infill_grouped[key];class_items.concat(items)
   vol=items.sum{|c|c.get_attribute(DICT,'concrete_volume_m3',0).to_f}
   h=items.sum{|c|c.get_attribute(DICT,'height_m',0).to_f}
   ids=items.map{|c|c.get_attribute(DICT,'pile_id','').to_s}.reject(&:empty?).join(', ')
   bim=items.any?{|c|c.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'}
   rt=items.sum{|c|qto3_quantity(c,:steel_t)}   # v0.38 PR1: BIM cage or rate, per infill
   infill_rows << "<tr><td>#{html_escape(klass)}</td><td>#{html_escape(zone)}</td><td>#{items.length}</td><td>#{html_escape(ids)}</td><td>#{format('%.2f',h)} m</td><td><b>#{format('%.3f',vol)} m³</b></td><td>#{bim ? 'BIM kafes' : format('%.0f kg/m³',rebar_rate('pile'))}</td><td><b>#{format('%.3f',rt)} t</b></td></tr>"
  end
  ch=class_items.sum{|c|c.get_attribute(DICT,'height_m',0).to_f}
  cv=class_items.sum{|c|c.get_attribute(DICT,'concrete_volume_m3',0).to_f}
  infill_rows << "<tr class='subtotal'><td>#{html_escape(klass)} ARA TOPLAM</td><td>-</td><td>#{class_items.length}</td><td>-</td><td>#{format('%.2f',ch)} m</td><td>#{format('%.3f',cv)} m³</td><td>#{class_items.any?{|c|c.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'} ? 'BIM kafes' : format('%.0f kg/m³',rebar_rate('pile'))}</td><td>#{format('%.3f',class_items.sum{|c|qto3_quantity(c,:steel_t)})} t</td></tr>"
 end
 infill_total=infills.sum{|c|c.get_attribute(DICT,'concrete_volume_m3',0).to_f}
 infill_h=infills.sum{|c|c.get_attribute(DICT,'height_m',0).to_f}
 infill_html="<h3 style='margin-top:24px'>Kazık İçi Beton</h3><table><tr><th>Beton Sınıfı</th><th>Bölge</th><th>Adet</th><th>Kazık ID</th><th>Toplam Beton Yüksekliği</th><th>Beton Hacmi</th><th>Donatı Pursantajı</th><th>Donatı</th></tr>#{infill_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>#{infills.length}</td><td>-</td><td>#{format('%.2f',infill_h)} m</td><td>#{format('%.3f',infill_total)} m³</td><td>#{format('%.0f',rebar_rate('pile'))} kg/m³</td><td>#{format('%.3f',infill_total*rebar_rate('pile')/1000.0)} t</td></tr></table>"

 pd_all=[];collect_elements(Sketchup.active_model.entities,pd_all)
 pd=pd_all.select{|e|e.get_attribute(DICT,'element_type')=='flat_precast'};pd_rows=String.new
 pd.group_by{|g|[g.get_attribute(DICT,'precast_type','PD'),g.get_attribute(DICT,'concrete_class','-'),g.get_attribute(DICT,'width_m',0).to_f,g.get_attribute(DICT,'height_m',0).to_f]}.each do |k,arr|
  vv=arr.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};ff=arr.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f};pd_rows<<"<tr><td>#{k[0]}</td><td>#{k[1]}</td><td>#{format('%.3f',k[2])}</td><td>#{format('%.3f',k[3])}</td><td>#{arr.length}</td><td>#{format('%.3f',vv)} m³</td><td>#{format('%.2f',ff)} m²</td><td>#{format('%.3f',mst_rebar_sum(arr)['kg']/1000.0)} t</td></tr>"
 end
 pd_vol=pd.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};pd_fw=pd.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f}
 pd_html=pd.empty? ? "" : "<h3 style='margin-top:24px'>Prekast (PD)</h3><table><tr><th>PD Tipi</th><th>Beton Sınıfı</th><th>Genişlik</th><th>Yükseklik</th><th>Adet</th><th>Beton</th><th>Kalıp</th><th>Donatı</th></tr>#{pd_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>-</td><td>-</td><td>#{pd.length}</td><td>#{format('%.3f',pd_vol)} m³</td><td>#{format('%.2f',pd_fw)} m²</td><td>#{format('%.3f',mst_rebar_sum(pd)['kg']/1000.0)} t</td></tr></table>"
 ch=a.select{|e|e.get_attribute(DICT,'element_type')=='channel_precast'};ch_rows=String.new
 ch.group_by{|g|[g.get_attribute(DICT,'precast_type_id',g.get_attribute(DICT,'precast_id','PK')).to_s,g.get_attribute(DICT,'concrete_class','-'),g.get_attribute(DICT,'inner_width_m',0).to_f,g.get_attribute(DICT,'inner_depth_m',0).to_f,g.get_attribute(DICT,'base_thickness_m',0).to_f,g.get_attribute(DICT,'wall_thickness_m',0).to_f]}.each do |k,arr|
  vv=arr.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};ff=arr.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f};ll=arr.sum{|g|g.get_attribute(DICT,'length_m',0).to_f};ch_rows<<"<tr><td>#{html_escape(k[0])}</td><td>#{k[1]}</td><td>#{format('%.2f',k[2])}</td><td>#{format('%.2f',k[3])}</td><td>#{format('%.2f',k[4])}</td><td>#{format('%.2f',k[5])}</td><td>#{arr.length}</td><td>#{format('%.2f',ll)} m</td><td>#{format('%.3f',vv)} m³</td><td>#{format('%.2f',ff)} m²</td><td>#{format('%.3f',mst_rebar_sum(arr)['kg']/1000.0)} t</td></tr>"
 end
 ch_vol=ch.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};ch_fw=ch.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f};ch_len=ch.sum{|g|g.get_attribute(DICT,'length_m',0).to_f}
 ch_html=ch.empty? ? "" : "<h3 style='margin-top:24px'>PK — Kanal Prekastı</h3><table><tr><th>Tip</th><th>Beton</th><th>İç Genişlik</th><th>İç Derinlik</th><th>Taban</th><th>Duvar</th><th>Adet</th><th>Toplam Boy</th><th>Beton</th><th>Kalıp</th><th>Donatı</th></tr>#{ch_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>#{ch.length}</td><td>#{format('%.2f',ch_len)} m</td><td>#{format('%.3f',ch_vol)} m³</td><td>#{format('%.2f',ch_fw)} m²</td><td>#{format('%.3f',mst_rebar_sum(ch)['kg']/1000.0)} t</td></tr></table>"

 cr=a.select{|e|e.get_attribute(DICT,'element_type')=='crane_precast'};cr_rows=String.new
 cr.group_by{|g|[g.get_attribute(DICT,'precast_family','PV').to_s,g.get_attribute(DICT,'precast_type_id',g.get_attribute(DICT,'precast_id','PV')).to_s,g.get_attribute(DICT,'concrete_class','-').to_s,g.get_attribute(DICT,'width_m',0).to_f,g.get_attribute(DICT,'thickness_m',g.get_attribute(DICT,'height_m',0)).to_f,g.get_attribute(DICT,'extra_depth_m',0).to_f,g.get_attribute(DICT,'left_tooth_m',0).to_f,g.get_attribute(DICT,'right_tooth_m',0).to_f]}.each do |k,arr|
  vv=arr.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};ff=arr.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f};ll=arr.sum{|g|g.get_attribute(DICT,'length_m',0).to_f}
  cr_rows << "<tr><td>#{html_escape(k[0]=='PDO' ? 'PDÖ' : k[0])}</td><td>#{html_escape(k[1])}</td><td>#{html_escape(k[2])}</td><td>#{format('%.3f',k[3])}</td><td>#{format('%.3f',k[4])}</td><td>#{format('%.3f',k[5])}</td><td>#{format('%.3f',k[6])}</td><td>#{format('%.3f',k[7])}</td><td>#{arr.length}</td><td>#{format('%.2f',ll)} m</td><td>#{format('%.3f',vv)} m³</td><td>#{format('%.2f',ff)} m²</td><td>#{format('%.3f',mst_rebar_sum(arr)['kg']/1000.0)} t</td></tr>"
 end
 cr_vol=cr.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};cr_fw=cr.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f};cr_len=cr.sum{|g|g.get_attribute(DICT,'length_m',0).to_f}
 cr_html=cr.empty? ? "" : "<h3 style='margin-top:24px'>PDÖ / PV — Dişli ve Vinç Prekastları</h3><table><tr><th>Sınıf</th><th>Tip</th><th>Beton</th><th>Genişlik</th><th>Ana Kalınlık</th><th>Diş Derinliği</th><th>Sol Diş</th><th>Sağ Diş</th><th>Adet</th><th>Toplam Boy</th><th>Beton</th><th>Kalıp</th><th>Donatı</th></tr>#{cr_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>#{cr.length}</td><td>#{format('%.2f',cr_len)} m</td><td>#{format('%.3f',cr_vol)} m³</td><td>#{format('%.2f',cr_fw)} m²</td><td>#{format('%.3f',mst_rebar_sum(cr)['kg']/1000.0)} t</td></tr></table>"

 precast_total_count=pd.length+ch.length+cr.length;precast_total_vol=pd_vol+ch_vol+cr_vol;precast_total_fw=pd_fw+ch_fw+cr_fw
 precast_total_rebar=mst_rebar_sum(pd)['kg']/1000.0+mst_rebar_sum(ch)['kg']/1000.0+mst_rebar_sum(cr)['kg']/1000.0
 precast_total_html=(precast_total_count==0 ? "" : "<h3 style='margin-top:28px'>Genel Prekast Toplamı</h3><table><tr><th>Grup</th><th>Adet</th><th>Beton</th><th>Kalıp</th><th>Donatı</th></tr><tr class='total'><td>PD + PDÖ + PV + PK</td><td>#{precast_total_count}</td><td>#{format('%.3f',precast_total_vol)} m³</td><td>#{format('%.2f',precast_total_fw)} m²</td><td>#{format('%.3f',precast_total_rebar)} t</td></tr></table>")
 precast_all_html="<h2 style='color:#073f73;margin:2px 0 8px'>Prekast Metrajları</h2><div class='note'>PD, PDÖ, PV ve PK sınıfları kullanıcı tip adlarıyla aynı metraj sayfasında gösterilir.</div>"+pd_html+ch_html+cr_html+precast_total_html

 dk=a.select{|e|e.get_attribute(DICT,'element_type')=='deck_slab'};dk_rows=String.new
 dk.each do |g|
  id=g.get_attribute(DICT,'deck_id','D-?').to_s;cc=g.get_attribute(DICT,'concrete_class','-').to_s
  sc=g.get_attribute(DICT,'span_count',1).to_i;ar=g.get_attribute(DICT,'net_area_m2',0).to_f;thk=g.get_attribute(DICT,'thickness_m',0).to_f
  vv=g.get_attribute(DICT,'concrete_volume_m3',0).to_f;ff=g.get_attribute(DICT,'formwork_area_m2',0).to_f
  dk_rows<<"<tr><td>#{html_escape(id)}</td><td>#{html_escape(cc)}</td><td>#{sc}</td><td>#{format('%.2f',ar)} m²</td><td>#{format('%.2f',thk)} m</td><td>#{format('%.3f',vv)} m³</td><td>#{format('%.2f',ff)} m²</td><td>#{g.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail' ? 'BIM (çizili)' : format('%.0f kg/m³',rebar_rate('deck'))}</td><td><b>#{format('%.3f',mst_element_rebar(g)['kg']/1000.0)} t</b></td></tr>"
 end
 dk_vol=dk.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};dk_fw=dk.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f};dk_area=dk.sum{|g|g.get_attribute(DICT,'net_area_m2',0).to_f}
 dk_html=dk.empty? ? "" : "<h3 style='margin-top:24px'>Döşeme</h3><table><tr><th>Döşeme ID</th><th>Beton</th><th>BK Aralığı</th><th>Net Alan</th><th>Kalınlık</th><th>Beton</th><th>Yan Kalıp</th><th>Donatı Kaynağı</th><th>Donatı</th></tr>#{dk_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>-</td><td>#{format('%.2f',dk_area)} m²</td><td>-</td><td>#{format('%.3f',dk_vol)} m³</td><td>#{format('%.2f',dk_fw)} m²</td><td>#{html_escape(mst_rebar_sum(dk)['label'])}</td><td>#{format('%.3f',mst_rebar_sum(dk)['kg']/1000.0)} t</td></tr></table>"
 cb=a.select{|e|e.get_attribute(DICT,'element_type')=='curb'};cb_rows=String.new
 cb.each{|g| cb_rows<<"<tr><td>#{html_escape(g.get_attribute(DICT,'curb_id','B-?').to_s)}</td><td>#{html_escape(g.get_attribute(DICT,'parent_deck_id','-').to_s)}</td><td>#{g.get_attribute(DICT,'side','-')}</td><td>#{html_escape(g.get_attribute(DICT,'concrete_class','-').to_s)}</td><td>#{format('%.2f',g.get_attribute(DICT,'length_m',0).to_f)} m</td><td>#{format('%.2f',g.get_attribute(DICT,'width_m',0).to_f)} m</td><td>#{format('%.2f',g.get_attribute(DICT,'height_m',0).to_f)} m</td><td>#{format('%.3f',g.get_attribute(DICT,'concrete_volume_m3',0).to_f)} m³</td><td>#{format('%.2f',g.get_attribute(DICT,'formwork_area_m2',0).to_f)} m²</td></tr>"}
 cb_vol=cb.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};cb_fw=cb.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f}
 cb_html=cb.empty? ? "" : "<h3 style='margin-top:24px'>Bordür / Tretuvar</h3><table><tr><th>ID</th><th>Döşeme</th><th>Taraf</th><th>Beton</th><th>Boy</th><th>Genişlik</th><th>Yükseklik</th><th>Beton</th><th>Kalıp</th></tr>#{cb_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td><td>#{format('%.3f',cb_vol)} m³</td><td>#{format('%.2f',cb_fw)} m²</td></tr></table>"

 # Kaplama / topping: physical child or legacy deck metadata uses the same canonical deck attributes.
 top_rows=String.new; top_area=0.0; top_vol=0.0
 dk.each do |g|
  next unless g.get_attribute(DICT,'topping_enabled','0').to_s=='1'
  id=g.get_attribute(DICT,'deck_id','D-?').to_s
  cc=g.get_attribute(DICT,'topping_concrete_class','C35/45').to_s
  ar=[g.get_attribute(DICT,'topping_area_m2',0).to_f,0.0].max
  th=g.get_attribute(DICT,'topping_thickness_m',0.10).to_f; th=0.10 if th<=0
  vv=g.get_attribute(DICT,'topping_volume_m3',ar*th).to_f; vv=ar*th if vv<=0 && ar>0
  top_area+=ar; top_vol+=vv
  top_rows << "<tr><td>#{html_escape(id)}</td><td>#{html_escape(cc)}</td><td>#{format('%.2f',ar)} m²</td><td>#{format('%.3f',th)} m</td><td>#{format('%.3f',vv)} m³</td><td>#{format('%.0f',rebar_rate('topping'))} kg/m³</td><td>#{format('%.3f',vv*rebar_rate('topping')/1000.0)} t</td></tr>"
 end
 top_html=top_rows.empty? ? "" : "<h3 style='margin-top:24px'>Kaplama Betonu</h3><table><tr><th>Döşeme ID</th><th>Beton Sınıfı</th><th>Alan</th><th>Kalınlık</th><th>Beton</th><th>Donatı Pursantajı</th><th>Donatı</th></tr>#{top_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>#{format('%.2f',top_area)} m²</td><td>-</td><td>#{format('%.3f',top_vol)} m³</td><td>#{format('%.0f',rebar_rate('topping'))} kg/m³</td><td>#{format('%.3f',top_vol*rebar_rate('topping')/1000.0)} t</td></tr></table>"

 cw=a.select{|e|e.get_attribute(DICT,'element_type')=='crown_wall'};cw_rows=String.new
 cw.each do |g|
  ints=JSON.parse(g.get_attribute(DICT,'crown_intervals_json','[]')) rescue []
  desc=ints.map{|r| "#{format('%.3f',r['start_m'].to_f)}–#{format('%.3f',r['end_m'].to_f)} #{r['type']}"}.join(', ')
  cw_rows << "<tr><td>#{html_escape(g.get_attribute(DICT,'id',g.name).to_s)}</td><td>#{html_escape(g.get_attribute(DICT,'concrete_class','-').to_s)}</td><td>#{format('%.3f',g.get_attribute(DICT,'length_m',0).to_f)} m</td><td>#{html_escape(desc)}</td><td>#{format('%.3f',g.get_attribute(DICT,'concrete_volume_m3',0).to_f)} m³</td><td>#{format('%.2f',g.get_attribute(DICT,'formwork_area_m2',0).to_f)} m²</td><td>#{format('%.3f',g.get_attribute(DICT,'concrete_volume_m3',0).to_f*rebar_rate('crown_wall')/1000.0)} t</td></tr>"
 end
 cw_vol=cw.sum{|g|g.get_attribute(DICT,'concrete_volume_m3',0).to_f};cw_fw=cw.sum{|g|g.get_attribute(DICT,'formwork_area_m2',0).to_f};cw_len=cw.sum{|g|g.get_attribute(DICT,'length_m',0).to_f}
 cw_html=cw.empty? ? "" : "<h3 style='margin-top:24px'>Kronman</h3><table><tr><th>Kronman ID</th><th>Beton Sınıfı</th><th>Toplam Boy</th><th>İstasyon / Tip</th><th>Kronman Betonu</th><th>Kronman Kalıbı</th><th>Donatı</th></tr>#{cw_rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>#{format('%.3f',cw_len)} m</td><td>-</td><td>#{format('%.3f',cw_vol)} m³</td><td>#{format('%.2f',cw_fw)} m²</td><td>#{format('%.3f',cw_vol*rebar_rate('crown_wall')/1000.0)} t</td></tr></table>"

 rockfill_html=rockfill_takeoff_html
 bored_html=bp_report_html
 jet_html=jg_report_html
 accessories_html=accessory_report_html

 # BK element-level detail uses the same stored BIM quantities as the existing summary.
 bk_detail_rows=String.new
 bk_groups=bs.group_by{|b| [b.get_attribute(DICT,'ano','-').to_s,b.get_attribute(DICT,'beam_type','BK-?').to_s]}
 bk_groups.keys.sort.each do |ano_type|
  items=bk_groups[ano_type].sort_by{|b| [b.get_attribute(DICT,'axis','').to_s,b.get_attribute(DICT,'head_beam_id',b.name).to_s]}
  items.each do |b|
   attr=lambda{|key,default=0| b.get_attribute(DICT,key,default)}
   v=head_beam_net_concrete(b); gross=head_beam_gross_formwork_area(b);ded=head_beam_pile_opening_area(b)
   net=[gross-ded,0.0].max
   rebar=mst_element_rebar(b)['kg']/1000.0   # v0.38 UI1
   cells=[ano_type[0],attr.call('head_beam_id',b.name),format('RV-%02d',attr.call('bk_revision_no',0).to_i),attr.call('axis','-'),ano_type[1],attr.call('concrete_class','-'),attr.call('selected_pile_count','-'),attr.call('connected_pile_ids','-'),format('%.3f',attr.call('length_m').to_f),format('%.3f',attr.call('width_m').to_f),format('%.3f',attr.call('height_m').to_f),format('%.3f',attr.call('bottom_elevation_m').to_f),format('%.3f',attr.call('top_elevation_m').to_f),format('%.3f',attr.call('start_overhang_m').to_f),format('%.3f',attr.call('end_overhang_m').to_f),format('%.3f',v),format('%.2f',gross),format('%.2f',ded),format('%.2f',net),format('%.3f',rebar)]
   bk_search=html_escape([cells[0],cells[1],cells[2],cells[3],cells[4],cells[6]].join(' ').downcase)
   bk_values=[v,gross,ded,net,rebar].map{|n|format('%.9f',n)}.join(',')
   bk_detail_rows << "<tr class='bim-bk-row' data-ano='#{html_escape(ano_type[0])}' data-type='#{html_escape(ano_type[1])}' data-search='#{bk_search}' data-values='#{bk_values}'>"+cells.map{|x|'<td>'+html_escape(x.to_s)+'</td>'}.join+'</tr>'
  end
  gv=items.sum{|b|head_beam_net_concrete(b)}
  gg=items.sum{|b|head_beam_gross_formwork_area(b)};gd=items.sum{|b|head_beam_pile_opening_area(b)}
  gr=mst_rebar_sum(items)['kg']/1000.0
  bk_detail_rows << "<tr class='subtotal bk-static-total'><td colspan='6'>#{html_escape(ano_type.join(' / '))} ARA TOPLAM</td><td>#{items.length} BK</td><td colspan='8'>—</td><td>#{format('%.3f',gv)}</td><td>#{format('%.2f',gg)}</td><td>#{format('%.2f',gd)}</td><td>#{format('%.2f',[gg-gd,0].max)}</td><td>#{format('%.3f',gr)}</td></tr>"
 end
 bk_total_rebar=mst_rebar_sum(bs)['kg']/1000.0
 bk_detail_rows << "<tr class='total bk-static-total'><td colspan='6'>PROJE GENEL TOPLAMI</td><td>#{bs.length} BK</td><td colspan='8'>—</td><td>#{format('%.3f',total_vol)}</td><td>#{format('%.2f',total_gross)}</td><td>#{format('%.2f',total_deduct)}</td><td>#{format('%.2f',total_net)}</td><td>#{format('%.3f',bk_total_rebar)}</td></tr>"
 bk_heads=['ANO','BK ID','REV.','Aks','BK Tipi','Beton Sınıfı','Kazık Ad.','Bağlı Kazık ID','Boy (m)','Genişlik (m)','Yükseklik (m)','Alt Kot (m)','Üst Kot (m)','Baş. Taşma (m)','Son Taşma (m)','Beton (m³)','Brüt Kalıp (m²)','Kazık Kesintisi (m²)','Net Kalıp (m²)','Donatı (t)']
 bk_ano_options=bs.map{|b|b.get_attribute(DICT,'ano','-').to_s}.uniq.sort.map{|x|"<option value='#{html_escape(x)}'>#{html_escape(x)}</option>"}.join
 bk_type_options=bs.map{|b|b.get_attribute(DICT,'beam_type','BK-?').to_s}.uniq.sort.map{|x|"<option value='#{html_escape(x)}'>#{html_escape(x)}</option>"}.join
 bk_detail_html="<h3 style='margin-top:25px'>BK ID Bazlı Detaylı BIM / Metraj</h3><div class='note'>ANO ve BK tipine göre eleman satırları, ara toplamlar ve genel toplam. Miktarlar kayıtlı BIM eleman bilgisinden okunur.</div><div class='pile-filters'><input id='bkSearch' placeholder='BK ID, aks veya Kazık ID ara...' oninput='filterBkRows()'><select id='bkAno' onchange='filterBkRows()'><option value=''>Tüm yapılar / ANO</option>#{bk_ano_options}</select><select id='bkType' onchange='filterBkRows()'><option value=''>Tüm BK tipleri</option>#{bk_type_options}</select><span id='bkFilterCount'></span></div><div class='table-scroll'><table class='pile-detail' style='min-width:2350px'><thead><tr>#{bk_heads.map{|h|'<th>'+h+'</th>'}.join}</tr></thead><tbody>#{bk_detail_rows}<tr class='subtotal' id='bkFilteredTotal' style='display:none'><td colspan='15'>FİLTRELENEN ARA TOPLAM</td><td>0.000</td><td>0.00</td><td>0.00</td><td>0.00</td><td>0.000</td></tr></tbody></table></div>"
 bk_filter_script=%q{<script>function filterBkRows(){var q=document.getElementById('bkSearch').value.toLocaleLowerCase('tr-TR').trim(),ano=document.getElementById('bkAno').value,typ=document.getElementById('bkType').value,rows=document.querySelectorAll('.bim-bk-row'),filtered=!!(q||ano||typ),sums=[0,0,0,0,0],n=0;Array.prototype.forEach.call(rows,function(r){var ok=(!q||r.getAttribute('data-search').toLocaleLowerCase('tr-TR').indexOf(q)>=0)&&(!ano||r.getAttribute('data-ano')===ano)&&(!typ||r.getAttribute('data-type')===typ);r.style.display=ok?'':'none';if(ok){n++;r.getAttribute('data-values').split(',').forEach(function(v,i){sums[i]+=Number(v)||0;});}});Array.prototype.forEach.call(document.querySelectorAll('.bk-static-total'),function(r){r.style.display=filtered?'none':'';});var ft=document.getElementById('bkFilteredTotal');ft.style.display=filtered?'':'none';ft.innerHTML='<td colspan="15">FİLTRELENEN ARA TOPLAM ('+n+' BK)</td>'+sums.map(function(v,i){return '<td>'+v.toFixed(i===0||i===4?3:2)+'</td>';}).join('');document.getElementById('bkFilterCount').textContent=n+' / '+rows.length+' BK';};filterBkRows();</script>}
 beam_html="<h3>Başlık Kirişi</h3><table><tr><th>BK Tipi</th><th>Beton Sınıfı</th><th>Adet</th><th>Akslar</th><th>Beton</th><th>Brüt Kalıp</th><th>Kazık Kesintisi</th><th>Net Kalıp</th><th>Donatı</th></tr>#{rows}<tr class='total'><td>TOPLAM</td><td>-</td><td>#{bs.length}</td><td>-</td><td>#{format('%.3f',total_vol)} m³</td><td>#{format('%.2f',total_gross)} m²</td><td>-#{format('%.2f',total_deduct)} m²</td><td>#{format('%.2f',total_net)} m²</td><td>#{mst_rebar_cell(bs)}</td></tr></table>"+mst_bk_embed_report_html(bs)
 sections=case mode.to_s
 when 'pile' then pile_bim_html+pile_html
 when 'beam' then beam_html+bk_detail_html
 when 'infill' then infill_html
 when 'precast' then precast_all_html
 when 'channel' then precast_all_html
 when 'crane' then precast_all_html
 when 'deck' then dk_html+cb_html+top_html
 when 'curb' then cb_html
 when 'crown' then cw_html
 when 'rockfill' then rockfill_html
 when 'jet_grout' then jet_html
 when 'bored' then bored_html   # v0.38 UI8
 when 'accessories' then accessories_html
 else pile_html+beam_html+bk_detail_html+infill_html+precast_all_html+dk_html+cb_html+top_html+cw_html+rockfill_html+bored_html+jet_html+accessories_html
 end
 titles={'pile'=>'Çelik Boru Kazık Metrajı','beam'=>'Başlık Kirişi Metrajı','infill'=>'Kazık İçi Beton Metrajı','precast'=>'Prekast Metrajları','channel'=>'Prekast Metrajları','crane'=>'Prekast Metrajları','deck'=>'Döşeme Metrajı','curb'=>'Bordür / Tretuvar Metrajı','crown'=>'Kronman Metrajı','rockfill'=>'Dolgu / Taş Metrajı','all'=>'Detaylı Metraj Raporu'}
 report_title=titles[mode.to_s]||titles['all']
 report_title={'jet_grout'=>'Jet Grout Metrajı','bored'=>'Fore Kazık Metrajı','accessories'=>'Aksesuar Metrajı'}[mode.to_s] || report_title
 return [report_title,sections] if want==:sections   # v0.38 UI8: Excel aktarımı aynı tabloları kullanır
 css="body{font-family:Arial,sans-serif;margin:0;background:#f3f7fa;color:#18364a}.top{background:#fff;border-bottom:1px solid #cbdde8;padding:18px 24px;display:flex;justify-content:space-between;align-items:center}.top h1{margin:0;color:#073f73;font-size:22px}.top p{margin:4px 0 0;color:#78909f;font-size:12px}.badge{background:#e9f5ff;color:#0875bb;border:1px solid #c7e3f7;border-radius:18px;padding:7px 12px;font-size:11px;font-weight:bold}.wrap{padding:18px 24px}.panel{background:#fff;border:1px solid #cadce7;border-radius:9px;padding:18px;box-shadow:0 2px 8px rgba(22,65,92,.06)}h3{color:#073f73;margin:4px 0 14px;font-size:17px}table{border-collapse:separate;border-spacing:0;width:100%;font-size:12px;margin-bottom:24px;border:1px solid #d6e2ea;border-radius:7px;overflow:hidden}th,td{padding:10px 9px;text-align:right;border-bottom:1px solid #e7eef3}th{background:#eaf3f8;color:#42677f;font-size:11px;text-transform:uppercase}th:first-child,td:first-child,th:nth-child(2),td:nth-child(2),th:nth-child(4),td:nth-child(4){text-align:left}tr:last-child td{border-bottom:0}.subtotal{font-weight:bold;background:#f0f6fa}.total{font-weight:bold;background:#dfeaf1;color:#123e5c}.note{color:#78909f;font-size:11px;margin:-7px 0 14px}.table-scroll{overflow-x:auto}.pile-detail{min-width:1880px;table-layout:fixed}.pile-detail th,.pile-detail td{white-space:nowrap;vertical-align:middle;border-right:1px solid #dfe8ee}.pile-detail th{position:sticky;top:0;z-index:2;text-align:center}.pile-detail td{text-align:right}.pile-detail th:first-child,.pile-detail td:first-child{position:sticky;left:0;z-index:3;background:#fff;text-align:left;min-width:125px}.pile-detail th:first-child{background:#eaf3f8;z-index:5}.pile-detail .group-head th{position:sticky;top:0;background:#dcecf6;color:#0b4c78;font-size:10px;letter-spacing:.4px;border-bottom:1px solid #bdd4e2}.pile-detail thead tr:nth-child(2) th{top:31px}.pile-detail .total td:first-child,.pile-detail .subtotal td:first-child{background:inherit}.pile-detail th:nth-child(1){width:125px}.pile-detail th:nth-child(2),.pile-detail th:nth-child(3){width:75px}.pile-detail th:nth-child(4),.pile-detail th:nth-child(5),.pile-detail th:nth-child(6){width:82px}.pile-detail th:nth-child(7),.pile-detail th:nth-child(8){width:110px}.pile-detail th:nth-child(n+9){width:112px}.foot{color:#78909f;font-size:10px;padding-top:3px;border-top:1px solid #e4edf2}"
 css += %q{.table-scroll>table{border-collapse:collapse;table-layout:fixed;width:max-content;min-width:100%}.table-scroll>table th,.table-scroll>table td{box-sizing:border-box;min-width:95px;text-align:right;vertical-align:middle;border-bottom:1px solid #dce6ed}.table-scroll>table th:first-child,.table-scroll>table td:first-child{text-align:left;min-width:145px}.table-scroll>table .total td,.table-scroll>table .subtotal td{font-weight:700;white-space:nowrap}.table-scroll>table.pile-detail{min-width:max(100%,1880px)}}
  css += %q{.pile-filters{display:flex;gap:10px;align-items:center;margin:12px 0;flex-wrap:wrap}.pile-filters input,.pile-filters select{padding:9px;border:1px solid #cadce7;border-radius:5px;min-width:170px}.bim-pile-row:hover{background:#edf6ff}.pile-detail tfoot td{background:#e3edf5;font-weight:bold}}
 html="<html><head><meta charset='utf-8'><style>#{css}</style></head><body><div class='top'><div><h1>#{report_title}</h1><p>Deniz Yapıları Araçları (MST) v#{VERSION} • Model tabanlı otomatik metraj</p></div><div style='display:flex;gap:10px;align-items:center'><button onclick='sketchup.takeoff_excel()' style='padding:9px 16px;border:0;border-radius:7px;background:#1d6f42;color:#fff;font-weight:700;cursor:pointer'>⇩ Excel'e Aktar</button><div class='badge'>MODEL VERİSİ</div></div></div><div class='wrap'><div class='panel'>#{sections}#{mode.to_s=='pile' ? pile_filter_script : (['beam','all'].include?(mode.to_s) ? bk_filter_script : '')}<div class='foot'>Miktarlar model eleman bilgilerinden otomatik hesaplanmıştır.</div></div></div></body></html>"
 d=mst_html_dialog('takeoff',dialog_title:'Metraj',width:1500,height:720,resizable:true);d.set_html(EngineeringUI.decorate(html));d.add_action_callback('takeoff_excel'){|_|mst_takeoff_excel};d.show;@q=d
rescue => e
 UI.messagebox("Metraj oluşturma hatası:\n#{e.class}: #{e.message}\n\n#{e.backtrace ? e.backtrace.first(5).join("\n") : ''}")

end

def element_info
 model=Sketchup.active_model; e=model.selection.first
 unless e && e.respond_to?(:get_attribute)
  UI.messagebox("Eleman bilgisi için bir kazık, başlık kirişi (BK) veya kazık içi betonu seç."); return
 end
 t=e.get_attribute(DICT,'element_type').to_s
 if t=='steel_pipe_pile'
  d=e.get_attribute(DICT,'diameter_mm',0).to_f; th=e.get_attribute(DICT,'thickness_mm',0).to_f
  msg="KAZIK ELEMAN BİLGİSİ\n\nKazık ID: #{e.get_attribute(DICT,'pile_id','-')}\nAks: #{e.get_attribute(DICT,'axis','-')}\nAks İçindeki Kazık No: #{e.get_attribute(DICT,'pile_no_in_axis','-')}\nBölge: #{e.get_attribute(DICT,'elevation_zone','-')}\nKesit: Ø#{format('%.1f',d)} x #{format('%.1f',th)} mm\nÇelik: #{e.get_attribute(DICT,'steel_grade','-')}\nÜst Kot: #{format('%+.3f',e.get_attribute(DICT,'top_elevation_m',0).to_f)} m\nAlt Kot: #{format('%+.3f',e.get_attribute(DICT,'bottom_elevation_m',0).to_f)} m\nBoy: #{format('%.3f',e.get_attribute(DICT,'length_m',0).to_f)} m\nTeorik Ağırlık: #{format('%.3f',e.get_attribute(DICT,'theoretical_weight_kg',0).to_f/1000.0)} ton"
 elsif t=='head_beam'
  msg="BAŞLIK KİRİŞİ (BK) ELEMAN BİLGİSİ\n\nID: #{e.get_attribute(DICT,'head_beam_id','-')}\nTip: #{e.get_attribute(DICT,'beam_type','-')}\nAks: #{e.get_attribute(DICT,'axis','-')}\nBeton: #{e.get_attribute(DICT,'concrete_class','-')}\nBoy: #{format('%.3f',e.get_attribute(DICT,'length_m',0).to_f)} m\nGenişlik: #{format('%.3f',e.get_attribute(DICT,'width_m',0).to_f)} m\nYükseklik: #{format('%.3f',e.get_attribute(DICT,'height_m',0).to_f)} m\nAlt/Üst Kot: #{format('%+.3f',e.get_attribute(DICT,'bottom_elevation_m',0).to_f)} / #{format('%+.3f',e.get_attribute(DICT,'top_elevation_m',0).to_f)} m\nBaşlangıç/Son Taşması: #{format('%.3f',e.get_attribute(DICT,'start_overhang_m',0).to_f)} / #{format('%.3f',e.get_attribute(DICT,'end_overhang_m',0).to_f)} m\nBeton: #{format('%.3f',head_beam_net_concrete(e))} m³#{(em=head_beam_pile_embed_volume(e))>1e-9 ? " (brüt #{format('%.3f',head_beam_gross_concrete(e))} − kazık gömülü #{format('%.3f',em)})" : ''}\nNet Kalıp: #{format('%.2f',e.get_attribute(DICT,'formwork_net_area_m2',0).to_f)} m²\nBağlı Kazıklar: #{e.get_attribute(DICT,'connected_pile_ids','-')}"
 elsif t=='pile_infill_concrete'
  msg="KAZIK İÇİ BETONU ELEMAN BİLGİSİ\n\nKazık: #{e.get_attribute(DICT,'pile_id','-')}\nBeton: #{e.get_attribute(DICT,'concrete_class','-')}\nBölge: #{e.get_attribute(DICT,'elevation_zone','-')}\nÜst/Alt Kot: #{format('%+.3f',e.get_attribute(DICT,'top_elevation_m',0).to_f)} / #{format('%+.3f',e.get_attribute(DICT,'bottom_elevation_m',0).to_f)} m\nHacim: #{format('%.3f',e.get_attribute(DICT,'volume_m3',e.get_attribute(DICT,'concrete_volume_m3',0)).to_f)} m³"
 else
  msg="Seçilen nesnede desteklenen MST eleman bilgisi bulunamadı."
 end
 UI.messagebox(msg)
end

def selected_head_beams
 Sketchup.active_model.selection.grep(Sketchup::Group).select do |g|
  g.get_attribute(DICT,'element_type')=='head_beam'
 end
end


def pd_bk_length_info
 sel=selected_head_beams
 if sel.length!=2
  @d.execute_script("setPDBeamLengths(NaN,NaN,NaN)") if @d
  return
 end
 a,b=sel
 conv=39.37007874015748
 alen=(a.bounds.max.y-a.bounds.min.y).to_f/conv
 blen=(b.bounds.max.y-b.bounds.min.y).to_f/conv
 common_min=[a.bounds.min.y,b.bounds.min.y].max
 common_max=[a.bounds.max.y,b.bounds.max.y].min
 usable=[(common_max-common_min).to_f/conv,0.0].max
 @d.execute_script("setPDBeamLengths(#{alen},#{blen},#{usable})") if @d
rescue=>e
 @d.execute_script("setPDBeamLengths(NaN,NaN,NaN)") if @d
end

def precast_type_registry(model)
 all=[]; collect_elements(model.entities,all)
 reg={}; max_pd=0; max_kp=0
 all.each do |e|
  et=e.get_attribute(DICT,'element_type').to_s
  next unless ['flat_precast','channel_precast','crane_precast'].include?(et)
  sig=e.get_attribute(DICT,'type_signature',nil).to_s
  tid=e.get_attribute(DICT,'precast_type_id',nil).to_s
  # Backward compatibility: use the old visible id as a seed only when a signature exists.
  tid=e.get_attribute(DICT,'precast_id','').to_s if tid.empty? && !sig.empty?
  reg[sig]=tid unless sig.empty? || tid.empty?
  if tid =~ /^PD-(\d+)$/i; max_pd=[max_pd,$1.to_i].max; end
  if tid =~ /^KP-(\d+)$/i; max_kp=[max_kp,$1.to_i].max; end
 end
 [reg,max_pd,max_kp]
end

def precast_signature(kind,length_m,width_m,height_m,extra='')
 # 1 mm dimensional tolerance keeps physically identical pieces in the same type.
 vals=[length_m,width_m,height_m].map{|v| (v.to_f*1000.0).round }
 ([kind]+vals+[extra.to_s]).join('|')
end

def next_precast_type_id(kind,registry,counters,signature)
 return registry[signature] if registry.key?(signature)
 if kind=='KP'
  counters[:kp]+=1; id=format('KP-%03d',counters[:kp])
 else
  counters[:pd]+=1; id=format('PD-%03d',counters[:pd])
 end
 registry[signature]=id
 id
end

def next_element_uid(model,prefix)
 # Persistent engineering identity, independent from the reusable visible TYPE id.
 seq=model.get_attribute(DICT,"#{prefix.downcase}_element_seq",0).to_i+1
 model.set_attribute(DICT,"#{prefix.downcase}_element_seq",seq)
 format("%s-E%05d",prefix,seq)
end

# v0.51.5 K22 aşama 1 (ADR-0515 §3): prekast açıklığı / boyu BK'ların model X sınır kutusundan ölçülür; bu yalnız
# BK ekseni model Y'ye paralel (ya da eksene dik, 90°'nin katı) iken doğrudur. Eksen 90°'nin katı değilse ve sınır kutusunun
# X genişliği BK genişliğini 5 mm'den fazla aşıyorsa Türkçe hata döner (nil = ölçülebilir; döndürülmemiş yapıda 0.51.4 ile aynı).
# Salt okuma. Aşama 2 (BK yerel ekseninde ölçüm) açık.
def mst_bk_span_frame_error(b)
 return nil unless b && b.respond_to?(:transformation)
 xa=b.transformation.xaxis
 ang=Math.atan2(xa.x.to_f,xa.y.to_f).abs*180.0/Math::PI   # model Y'ye göre, 0..180
 off=ang%90.0;off=[off,90.0-off].min
 return nil if off<=0.01
 w=b.get_attribute(DICT,'width_m',0).to_f
 return nil if w>0 && b.bounds.width.to_f/39.37007874015748-w<=0.005
 a=ang>90.0 ? 180.0-ang : ang
 "#{element_visible_id(b)}: başlık kirişi model eksenine göre #{format('%.1f',a)}° döndürülmüş. Prekast boyu yalnız model Y eksenine paralel BK'lar arasında ölçülebiliyor; bu yapıda boy yanlış çıkar. Prekast oluşturulmadı."
end

def create_flat_precast(data=nil)
 model=Sketchup.active_model;sel=selected_head_beams
 if sel.length<2;UI.messagebox("Prekast yerleşimi için en az iki komşu başlık kirişi (BK) seçiniz.");return;end
 data||={}
 if sel.length>2
  ordered=sel.sort_by{|g|g.bounds.center.x};original=sel.dup;completed=0;ok=false
  # v0.51.5 K15: bütün aralıklar tek işlem (tek Geri Al); aralık işlevleri çağıranın işlemi içinde çalışır.
  # Bir aralık durursa işlem geri alınır: model değişmez (yarım toplu yerleşim kalmaz).
  model.start_operation('Prekast Yerleşimi - Toplu',true)
  begin
   @precast_batch_mode=true
   ordered.each_cons(2){|a,b|model.selection.clear;model.selection.add(a);model.selection.add(b);break unless create_flat_precast(data)==true;completed+=1}
   ok=completed==ordered.length-1
  rescue => bex   # kod inceleme #10: aralık işlevinden kaçan istisna Türkçe iletiyle bildirilir (işlem ensure'da geri alınır)
   ok=false;berr=bex.message.to_s
  ensure
   @precast_batch_mode=false
   ok ? commit_with_dependencies(model) : model.abort_operation
   model.selection.clear;original.each{|g|model.selection.add(g) if g&&g.valid?}
  end
  UI.messagebox(ok ? "Toplu prekast yerleşimi tamamlandı.\nOluşturulan BK aralığı: #{completed} / #{ordered.length-1}" :
   "Toplu prekast yerleşimi durduruldu (#{completed+1}. BK aralığı oluşturulamadı#{berr ? ": #{berr}" : ''}).\nÖnceki #{completed} aralık da geri alındı; model değişmedi.")
  return ok
 end
 lb,rb=sel.sort_by{|g|g.bounds.center.x}
 # v0.51.5 K22 (aşama 1): açıklık model X'inde ölçülüyor; döndürülmüş BK'da boy yanlış çıkacağı için oluşturulmaz
 if (er=mst_bk_span_frame_error(lb) || mst_bk_span_frame_error(rb));UI.messagebox(er);return;end
 clear=rb.bounds.min.x-lb.bounds.max.x
 z1=lb.get_attribute(DICT,'top_elevation_m',nil);z2=rb.get_attribute(DICT,'top_elevation_m',nil)
 if clear<=0||z1.nil?||z2.nil?||(z1.to_f-z2.to_f).abs>0.005;UI.messagebox('BK açıklığı veya üst kot bilgisi geçersiz/farklı.');return;end
 z=z1.to_f;seat=data['pd_seat_m'].to_s.empty? ? 0.15:data['pd_seat_m'].to_f;joint=data['pd_joint_m'].to_s.empty? ? 0.02:data['pd_joint_m'].to_f;yoff=data['pd_y_offset_m'].to_f
 layout=JSON.parse(data['pd_layout_rows'].to_s) rescue []
 lib=JSON.parse(data['precast_type_library'].to_s) rescue []
 by_uid={};lib.each{|t|by_uid[t['uid'].to_s]=t}
 pieces=[]
 layout.each do |r|
  t=by_uid[r['type_uid'].to_s];next unless t
  [r['count'].to_i,1].max.times{pieces<<t}
 end
 if seat<0||joint<0||pieces.empty?;UI.messagebox('Prekast tip kütüphanesi / yerleşim bilgileri geçersiz.');return;end
 names=lib.map{|t|t['name'].to_s.strip};if names.any?(&:empty?)||names.map(&:downcase).uniq.length!=names.length;UI.messagebox('Prekast tip adları boş olamaz ve benzersiz olmalıdır.');return;end
 plen=clear+2*m(seat);lm=plen.to_f/39.37007874015748;x0=lb.bounds.max.x-m(seat);support_y0=[lb.bounds.min.y,rb.bounds.min.y].max;y=support_y0+m(yoff)
 fl=%w[pd_fw_bottom pd_fw_long1 pd_fw_long2 pd_fw_end1 pd_fw_end2 pd_fw_top].map{|k|data[k]=='1'}
 pd_form_hex=data['pd_formwork_color'].to_s.strip;pd_form_hex='#66A9E8' if pd_form_hex.empty?;pd_form_mat=material_for(model,"MAG PD Kalıp #{pd_form_hex}",pd_form_hex)
 ch_form_hex=data['channel_formwork_color'].to_s.strip;ch_form_hex='#6DBE73' if ch_form_hex.empty?;ch_form_mat=material_for(model,"MAG Kanal Kalıp #{ch_form_hex}",ch_form_hex)
 tooth_form_mat=material_for(model,'MAG Dişli Prekast Kalıp #FFD966','#FFD966')
 model.start_operation('Prekast Yerleşimi - Çoklu Tip',true) unless @precast_batch_mode   # K15: toplu yerleşimde çağıranın işlemi
 begin
  c=model.active_entities.add_group;c.name='Prekast Layout';c.set_attribute(DICT,'element_type','precast_layout')
  counts={'PD'=>0,'PDO'=>0,'PV'=>0,'PK'=>0}
  pieces.each do |tdef|
   fam=tdef['family'].to_s;fam='PDO' if fam=='PDÖ';name=tdef['name'].to_s.strip;cc=tdef['concrete'].to_s.strip;cc='C30/37' if cc.empty?;counts[fam]=counts.fetch(fam,0)+1
   case fam
   when 'PD'
    wm=tdef['width'].to_f;h=tdef['height'].to_f;raise "#{name}: genişlik/kalınlık geçersiz." if wm<=0||h<=0
    uid=next_element_uid(model,'PD');g=c.entities.add_group;g.name="#{name} [#{uid}]";w=m(wm);f=g.entities.add_face([0,0,0],[plen,0,0],[plen,w,0],[0,w,0]);f.reverse! if f.normal.z<0;f.pushpull(m(h));g.transform!(Geom::Transformation.translation([x0,y,m(z)]));paint_flat_precast_formwork(g,fl,pd_form_mat,nil)
    fw=0.0;fw+=lm*wm if fl[0];fw+=lm*h if fl[1];fw+=lm*h if fl[2];fw+=wm*h if fl[3];fw+=wm*h if fl[4]
    sig=precast_signature('PD',lm,wm,h,name);{'element_type'=>'flat_precast','precast_family'=>'PD','precast_id'=>name,'precast_type_id'=>name,'library_type_id'=>name,'element_uid'=>uid,'type_signature'=>sig,'precast_type'=>name,'length_m'=>lm,'width_m'=>wm,'layout_width_m'=>wm,'height_m'=>h,'bottom_elevation_m'=>z,'top_elevation_m'=>z+h,'joint_m'=>joint,'seat_each_side_m'=>seat,'concrete_class'=>cc,'concrete_volume_m3'=>lm*wm*h,'formwork_area_m2'=>fw,'formwork_color'=>pd_form_hex,'support_left_pid'=>lb.persistent_id,'support_right_pid'=>rb.persistent_id}.each{|k,v|g.set_attribute(DICT,k,v)};finalize_bim_identity(g,model);y+=m(wm)+m(joint)
   when 'PDO','PV'
    wm=tdef['width'].to_f;h=tdef['height'].to_f;ed=tdef['extra'].to_f;lt=tdef['left'].to_f;rt=tdef['right'].to_f;raise "#{name}: dişli prekast geometrisi geçersiz." if wm<=0||h<=0||ed<0||lt<0||rt<0||lt+rt>=lm
    prefix=fam=='PV' ? 'PV':'PDO';uid=next_element_uid(model,prefix);g=c.entities.add_group;g.name="#{name} [#{uid}]";build_crane_precast_solid(g.entities,plen,wm,h,ed,lt,rt);g.transform!(Geom::Transformation.translation([x0,y,m(z)]));paint_crane_precast_formwork(g,tooth_form_mat);central=[lm-lt-rt,0].max;vol=wm*(h*lm+ed*central);fw=head_beam_formwork_area(g);sig=precast_signature(fam,lm,wm,h,[name,ed,lt,rt].join(':'))
    {'element_type'=>'crane_precast','precast_family'=>fam,'precast_id'=>name,'precast_type_id'=>name,'library_type_id'=>name,'element_uid'=>uid,'type_signature'=>sig,'precast_type'=>name,'length_m'=>lm,'width_m'=>wm,'layout_width_m'=>wm,'height_m'=>h,'thickness_m'=>h,'extra_depth_m'=>ed,'left_tooth_m'=>lt,'right_tooth_m'=>rt,'bottom_elevation_m'=>z-ed,'main_bottom_elevation_m'=>z,'top_elevation_m'=>z+h,'joint_m'=>joint,'seat_each_side_m'=>seat,'concrete_class'=>cc,'rebar_rate_kg_m3'=>120.0,'concrete_volume_m3'=>vol,'formwork_area_m2'=>fw,'formwork_rule'=>'ALL_EXPOSED_EXCEPT_TOP','support_left_pid'=>lb.persistent_id,'support_right_pid'=>rb.persistent_id}.each{|k,v|g.set_attribute(DICT,k,v)};finalize_bim_identity(g,model);y+=m(wm)+m(joint)
   when 'PK'
    wi=tdef['inner_width'].to_f;di=tdef['inner_depth'].to_f;tb=tdef['base'].to_f;tw=tdef['wall'].to_f;raise "#{name}: kanal geometrisi geçersiz." if [wi,di,tb,tw].any?{|v|v<=0};ow=wi+2*tw;oh=tb+di;uid=next_element_uid(model,'PK');g=c.entities.add_group;g.name="#{name} [#{uid}]";profile=[[0,0],[ow,0],[ow,oh],[ow-tw,oh],[ow-tw,tb],[tw,tb],[tw,oh],[0,oh]];uf=g.entities.add_face(profile.map{|yy,zz|Geom::Point3d.new(0,m(yy),m(zz))});raise "#{name}: U kesiti oluşturulamadı." unless uf;uf.reverse! if uf.normal.x<0;uf.pushpull(plen)
    # PK üst kotunu yerleşimdeki en yüksek normal/dişli ana kalınlığına hizala.
    ref_h=pieces.reject{|x|x['family'].to_s=='PK'}.map{|x|x['height'].to_f}.max||0.30;topz=z+ref_h;bottomz=topz-oh;g.transform!(Geom::Transformation.translation([x0,y,m(bottomz)]));flags={bottom:data['channel_fw_bottom']=='1',sides:data['channel_fw_sides']=='1',inner:data['channel_fw_inner']!='0',ends:data['channel_fw_ends']=='1'};paint_channel_precast_formwork(g,ow,tw,di,tb,flags,ch_form_mat,nil);area=ow*tb+2*tw*di;vol=area*lm;fw=0.0;fw+=lm*ow if flags[:bottom];fw+=2*lm*oh if flags[:sides];fw+=lm*(wi+2*di) if flags[:inner];fw+=2*area if flags[:ends];sig=precast_signature('PK',lm,ow,oh,[name,wi,di,tb,tw].join(':'))
    {'element_type'=>'channel_precast','precast_family'=>'PK','precast_id'=>name,'precast_type_id'=>name,'library_type_id'=>name,'element_uid'=>uid,'type_signature'=>sig,'precast_type'=>name,'length_m'=>lm,'width_m'=>ow,'layout_width_m'=>ow,'inner_width_m'=>wi,'inner_depth_m'=>di,'base_thickness_m'=>tb,'wall_thickness_m'=>tw,'bottom_elevation_m'=>bottomz,'top_elevation_m'=>topz,'joint_m'=>joint,'seat_each_side_m'=>seat,'concrete_class'=>cc,'concrete_volume_m3'=>vol,'formwork_area_m2'=>fw,'support_left_pid'=>lb.persistent_id,'support_right_pid'=>rb.persistent_id}.each{|k,v|g.set_attribute(DICT,k,v)};finalize_bim_identity(g,model);y+=m(ow)+m(joint)
   else
    raise "Bilinmeyen prekast sınıfı: #{fam}"
   end
  end
  # v0.38 PC1: Component body (default) — identical pieces share one definition.
  if data['pd_body_mode'].to_s!='GROUP'
   c.entities.grep(Sketchup::Group).select{|g|MST_PRECAST_TYPES.include?(g.get_attribute(DICT,'element_type','').to_s)}.each do |g|
    mst_precast_to_component!(g,model) if mst_precast_convert_check(g,model).nil?
   end
  end
  # Save the editable type library in the SketchUp model for traceability / future migration.
  model.set_attribute(DICT,'precast_type_library_json',JSON.generate(lib));commit_with_dependencies(model) unless @precast_batch_mode
  unless @precast_batch_mode;UI.messagebox("Prekast yerleşimi oluşturuldu.\nPD: #{counts['PD']}\nPDÖ: #{counts['PDO']}\nPV: #{counts['PV']}\nPK: #{counts['PK']}\nBoy: #{format('%.3f',lm)} m");end
  true
 rescue=>e
  model.abort_operation unless @precast_batch_mode   # K15: toplu yerleşimde çağıran geri alır
  UI.messagebox("Prekast oluşturma hatası: #{e.message}");false
 end
end

def sync_precast_to_head_beams
 model=Sketchup.active_model;all=[];collect_elements(model.entities,all);map={};all.select{|e|e.get_attribute(DICT,'element_type')=='head_beam'}.each{|g|map[g.persistent_id]=g};moved=0;skip=0
 model.start_operation("PD Kotlarını BK ile Güncelle",true)
 begin
  all.select{|e|['flat_precast','channel_precast','crane_precast'].include?(e.get_attribute(DICT,'element_type'))}.each do |g|
   l=map[g.get_attribute(DICT,'support_left_pid',0).to_i];r=map[g.get_attribute(DICT,'support_right_pid',0).to_i]
   unless l&&r;skip+=1;next;end;z1=l.get_attribute(DICT,'top_elevation_m',nil);z2=r.get_attribute(DICT,'top_elevation_m',nil)
   if z1.nil?||z2.nil?||(z1.to_f-z2.to_f).abs>0.005;skip+=1;next;end
   et=g.get_attribute(DICT,'element_type').to_s
   if et=='channel_precast'
    u_h=g.get_attribute(DICT,'base_thickness_m',0).to_f+g.get_attribute(DICT,'inner_depth_m',0).to_f
    # Use the normal PD height from the same layout/support pair when available.
    mate=all.find{|p|p.get_attribute(DICT,'element_type')=='flat_precast' && p.get_attribute(DICT,'support_left_pid',0).to_i==g.get_attribute(DICT,'support_left_pid',0).to_i && p.get_attribute(DICT,'support_right_pid',0).to_i==g.get_attribute(DICT,'support_right_pid',0).to_i}
    pd_h=mate ? mate.get_attribute(DICT,'height_m',0).to_f : 0.0
    target_top=z1.to_f+pd_h;target_bottom=target_top-u_h
    old=g.get_attribute(DICT,'bottom_elevation_m',target_bottom).to_f;dz=target_bottom-old
    if dz.abs>0.0005;g.transform!(Geom::Transformation.translation([0,0,m(dz)]));g.set_attribute(DICT,'bottom_elevation_m',target_bottom);g.set_attribute(DICT,'top_elevation_m',target_top);moved+=1;end
   else
    old=g.get_attribute(DICT,'bottom_elevation_m',z1.to_f).to_f;dz=z1.to_f-old
    if dz.abs>0.0005;g.transform!(Geom::Transformation.translation([0,0,m(dz)]));hh=g.get_attribute(DICT,'height_m',0).to_f;g.set_attribute(DICT,'bottom_elevation_m',z1.to_f);g.set_attribute(DICT,'top_elevation_m',z1.to_f+hh);moved+=1;end
   end
  end
  commit_with_dependencies(model);UI.messagebox("PD kot güncellemesi: #{moved} güncellendi, #{skip} atlandı.")
 rescue=>e;model.abort_operation;UI.messagebox("PD kot güncelleme hatası: #{e.message}");end
end

def read_channel_bk(dialog)
 sel=Sketchup.active_model.selection
 hb=sel.find{|e|e.respond_to?(:get_attribute)&&e.get_attribute(DICT,'element_type').to_s=='head_beam'}
 unless hb
  dialog.execute_script("document.getElementById('channelLinkStatus').textContent='Bir Başlık Kirişi seçiniz.';");return
 end
 b=hb.get_attribute(DICT,'bottom_elevation_m').to_f;hh=hb.get_attribute(DICT,'height_m').to_f
 top=hb.get_attribute(DICT,'top_elevation_m');top=top.nil? ? b+hh : top.to_f
 len=hb.get_attribute(DICT,'length_m');len=len.nil? ? hb.bounds.width.to_f/39.37007874015748 : len.to_f
 name=(hb.name.to_s.empty? ? 'BK' : hb.name.to_s)
 dialog.execute_script("chText('channelSelectedBK',#{name.inspect});chText('channelBKLength',#{format('%.2f m',len).inspect});chText('channelBKTop',#{format('%.2f m',top).inspect});chText('channelLinkStatus','Seçili BK okundu.');updateChannelPrecastUI();")
end

def create_channel_precast(d)
 model=Sketchup.active_model
 hb=model.selection.find{|e|e.respond_to?(:get_attribute)&&e.get_attribute(DICT,'element_type').to_s=='head_beam'}
 raise 'Önce bir Başlık Kirişi seçiniz.' unless hb
 wi=d['inner_width_m'].to_f;di=d['inner_depth_m'].to_f;tb=d['base_thickness_m'].to_f;tw=d['wall_thickness_m'].to_f
 raise 'Kanal ölçüleri sıfırdan büyük olmalıdır.' if [wi,di,tb,tw].any?{|x|x<=0}
 sl=d['seat_left_m'].to_f;sr=d['seat_right_m'].to_f
 hb_len=hb.get_attribute(DICT,'length_m');hb_len=hb.bounds.width.to_f/39.37007874015748 if hb_len.nil?
 len=d['length_mode'].to_s=='AUTO' ? hb_len.to_f+sl+sr : d['manual_length_m'].to_f
 raise 'Eleman boyu sıfırdan büyük olmalıdır.' if len<=0
 b=hb.get_attribute(DICT,'bottom_elevation_m').to_f;hh=hb.get_attribute(DICT,'height_m').to_f;top=hb.get_attribute(DICT,'top_elevation_m');bk_top=top.nil? ? b+hh : top.to_f
 # Channel bottom/base bottom: U-section sits with its bottom at BK top in this first geometric implementation.
 z=bk_top
 outer=wi+2.0*tw
 model.start_operation('U Kanal Prekastı Oluştur',true)
 g=model.active_entities.add_group;g.name='Kanal Prekastı (U)'
 cx=hb.bounds.center.x;cy=hb.bounds.center.y
 # Length follows model X, section across Y; three solids = base + left/right walls.
 x0=cx-len.m/2.0;y0=cy-outer.m/2.0
 base=g.entities.add_group;base.name='Taban'
 f=base.entities.add_face([x0,y0,z.m],[x0+len.m,y0,z.m],[x0+len.m,y0+outer.m,z.m],[x0,y0+outer.m,z.m]);f.pushpull(tb.m)
 [['Sol Yan Duvar',y0],['Sağ Yan Duvar',y0+(tw+wi).m]].each do |nm,yy|
  wg=g.entities.add_group;wg.name=nm
  wf=wg.entities.add_face([x0,yy,(z+tb).m],[x0+len.m,yy,(z+tb).m],[x0+len.m,yy+tw.m,(z+tb).m],[x0,yy+tw.m,(z+tb).m]);wf.pushpull(di.m)
 end
 area=(outer*tb)+(2.0*tw*di);vol=area*len
 {'element_type'=>'channel_precast','precast_type'=>'KANAL_PREKASTI_U','inner_width_m'=>wi,'inner_depth_m'=>di,'base_thickness_m'=>tb,'wall_thickness_m'=>tw,'outer_width_m'=>outer,'length_m'=>len,'seat_left_m'=>sl,'seat_right_m'=>sr,'concrete_class'=>d['concrete_class'].to_s,'bottom_elevation_m'=>z,'top_elevation_m'=>z+tb+di,'concrete_volume_m3'=>vol,'formwork_area_m2'=>((d['fw_bottom'] ? len*outer : 0.0)+(d['fw_sides'] ? 2.0*len*(tb+di) : 0.0)+(d['fw_inner'] ? len*(wi+2.0*di) : 0.0)+(d['fw_ends'] ? 2.0*area : 0.0)),'formwork_inner_m2'=>(d['fw_inner'] ? len*(wi+2.0*di) : 0.0),'formwork_wall_top_m2'=>0.0,'formwork_bottom'=>d['fw_bottom'],'formwork_sides'=>d['fw_sides'],'formwork_inner'=>d['fw_inner'],'formwork_ends'=>d['fw_ends'],'formwork_top'=>false}.each{|k,v|g.set_attribute(DICT,k,v)}
 finalize_bim_identity(g,model)
 commit_with_dependencies(model)
 model.selection.clear;model.selection.add(g)
rescue=>e
 model.abort_operation rescue nil;UI.messagebox("Kanal Prekastı oluşturma hatası: #{e.message}")
end


def create_crane_precast(d)
 model=Sketchup.active_model
 hbs=selected_head_beams
 if hbs.length!=2
  UI.messagebox('Vinç Prekastı için iki komşu Başlık Kirişi seçiniz.');return false
 end
 lb,rb=hbs.sort_by{|g|g.bounds.center.x}
 if (er=mst_bk_span_frame_error(lb) || mst_bk_span_frame_error(rb));UI.messagebox(er);return false;end   # v0.51.5 K22 aşama 1
 clear=rb.bounds.min.x-lb.bounds.max.x
 if clear<=0;UI.messagebox('Seçilen BK açıklığı geçersiz.');return false;end
 z1=lb.get_attribute(DICT,'top_elevation_m',nil);z2=rb.get_attribute(DICT,'top_elevation_m',nil)
 if d['elevation_mode'].to_s=='BK_TOP'
  if z1.nil?||z2.nil?||(z1.to_f-z2.to_f).abs>0.005;UI.messagebox('BK üst kotları eksik veya farklı.');return false;end
  bottom=z1.to_f
 else
  bottom=d['bottom_elevation_m'].to_f
 end
 w=d['width_m'].to_f;t=d['thickness_m'].to_f;sl=d['seat_left_m'].to_f;sr=d['seat_right_m'].to_f
 len=d['length_mode'].to_s=='AUTO' ? clear.to_f/39.37007874015748+sl+sr : d['manual_length_m'].to_f
 ed=d['extra_depth_m'].to_f;lt=d['left_tooth_m'].to_f;rt=d['right_tooth_m'].to_f
 if [w,t,len].any?{|x|x<=0}||[sl,sr,ed,lt,rt].any?{|x|x<0};UI.messagebox('Vinç Prekastı ölçüleri geçersiz.');return false;end
 if lt+rt>=len;UI.messagebox('Sol + sağ uç diş boyu prekast boyundan küçük olmalıdır.');return false;end
 cc=d['concrete_class'].to_s.strip;cc='C35/45' if cc.empty?
 id=d['type_id'].to_s.strip;id='PV-01' if id.empty?
 x0=lb.bounds.max.x-m(sl);support_y0=[lb.bounds.min.y,rb.bounds.min.y].max;y0=support_y0
 model.start_operation('Vinç Prekastı Oluştur',true)
 begin
  g=model.active_entities.add_group;uid=next_element_uid(model,'PV');g.name="#{id} [#{uid}]"
  build_crane_precast_solid(g.entities,m(len),w,t,ed,lt,rt)
  g.transform!(Geom::Transformation.translation([x0,y0,m(bottom)]))
  crane_form_mat=material_for(model,'MAG Vinç Prekastı Kalıp #FFD966','#FFD966')
  paint_crane_precast_formwork(g,crane_form_mat)
  central_len=[len-lt-rt,0.0].max;vol=w*(t*len+ed*central_len)
  fw=head_beam_formwork_area(g)
  sig=precast_signature('CRANE',len,w,t,[ed,lt,rt].map{|x|(x*1000).round}.join(':'))
  {'element_type'=>'crane_precast','precast_id'=>id,'precast_type_id'=>id,'element_uid'=>uid,'library_type_id'=>id,'type_signature'=>sig,'precast_family'=>'PV','precast_type'=>id,'length_m'=>len,'width_m'=>w,'layout_width_m'=>w,'height_m'=>t,'thickness_m'=>t,'extra_depth_m'=>ed,'left_tooth_m'=>lt,'right_tooth_m'=>rt,'bottom_elevation_m'=>bottom-ed,'main_bottom_elevation_m'=>bottom,'top_elevation_m'=>bottom+t,'seat_left_m'=>sl,'seat_right_m'=>sr,'concrete_class'=>cc,'cover_cm'=>d['cover_cm'].to_f,'rebar_rate_kg_m3'=>d['rebar_rate'].to_f,'concrete_volume_m3'=>vol,'formwork_area_m2'=>fw,'support_left_pid'=>lb.persistent_id,'support_right_pid'=>rb.persistent_id}.each{|k,v|g.set_attribute(DICT,k,v)}
  finalize_bim_identity(g,model);commit_with_dependencies(model);model.selection.clear;model.selection.add(g)
  k54=(mst_pv_tooth_seat_warnings(g) rescue [])   # v0.51.5 K54: yalnız uyarı (commit sonrası; hata işlemi etkilemez)
  UI.messagebox("Vinç Prekastı oluşturuldu.\nTip: #{id}\nBoy: #{format('%.3f',len)} m\nGenişlik: #{format('%.3f',w)} m\nBeton: #{format('%.3f',vol)} m³#{k54.empty? ? '' : "\n\nUYARI:\n#{k54.join("\n")}"}")
  true
 rescue=>e
  model.abort_operation;UI.messagebox("Vinç Prekastı oluşturma hatası: #{e.message}");false
 end
end

def create_deck_curbs(model,data,did,u,v,zz,gross_u0,gross_u1,gross_v0,gross_v1,deck_top_z)
 enabled=[data['curb_side_1'],data['curb_side_2'],data['curb_side_3'],data['curb_side_4']].map{|x| x==true || x.to_s=='true' || x.to_s=='1'}
 return [] unless enabled.any?
 w=data['curb_width_m'].to_f; h=data['curb_height_m'].to_f
 raise 'Bordür / Tretuvar genişliği ve yüksekliği sıfırdan büyük olmalıdır.' if w<=0 || h<=0
 cc=data['curb_concrete_class'].to_s.strip; cc=data['concrete_class'].to_s.strip if cc.empty?; cc='C35/45' if cc.empty?
 form_hex=data['curb_formwork_color'].to_s.strip; form_hex='#F4B183' if form_hex.empty?
 conc_hex=data['curb_concrete_color'].to_s.strip; conc_hex='#D9D9D9' if conc_hex.empty?
 form_mat=material_for(model,"MAG Bordür Kalıp #{form_hex}",form_hex); conc_mat=nil
 os=data['curb_start_offset_m'].to_f; oe=data['curb_end_offset_m'].to_f; os=0 if os<0; oe=0 if oe<0
 du=(gross_u1-gross_u0)/1.m; dv=(gross_v1-gross_v0)/1.m
 out=[]
 # Side 1/2 = long sides (V-min / V-max); Side 3/4 = end sides (U-min / U-max)
 specs=[]
 specs << ['1',gross_u0+m(os),gross_u1-m(oe),gross_v0,gross_v0+m(w)] if enabled[0]
 specs << ['2',gross_u0+m(os),gross_u1-m(oe),gross_v1-m(w),gross_v1] if enabled[1]
 specs << ['3',gross_u0,gross_u0+m(w),gross_v0+m(os),gross_v1-m(oe)] if enabled[2]
 specs << ['4',gross_u1-m(w),gross_u1,gross_v0+m(os),gross_v1-m(oe)] if enabled[3]
 specs.each do |sid,u0,u1,v0,v1|
  next if u1<=u0 || v1<=v0
  li=u1-u0; wi=v1-v0
  g=model.entities.add_group; g.name="#{did}-BORDUR-#{sid}"   # DS1.1: world coordinates → model root, never the open edit context
  f=g.entities.add_face([0,0,0],[li,0,0],[li,wi,0],[0,wi,0]); raise "Bordür #{sid} yüzeyi oluşturulamadı." unless f
  f.reverse! if f.normal.z<0; f.pushpull(m(h))
  origin=Geom::Point3d.new(u.x*u0+v.x*v0,u.y*u0+v.y*v0,deck_top_z)
  g.transform!(Geom::Transformation.axes(origin,u,v,zz))
  # Bottom is deck contact, top is not formwork; only vertical faces are formwork.
  g.entities.grep(Sketchup::Face).each do |face|
   if face.normal.z.abs < 0.25
    mark_formwork_face(face,true,form_mat,conc_mat)
   else
    face.set_attribute(DICT,'formwork',false); face.material=conc_mat; face.back_material=nil
   end
  end
  lm=li/1.m; wm=wi/1.m; vol=lm*wm*h; fw=2.0*(lm+wm)*h
  {'element_type'=>'curb','curb_id'=>"B-#{did}-#{sid}",'parent_deck_id'=>did,'side'=>sid,'length_m'=>lm,'width_m'=>wm,'height_m'=>h,'bottom_elevation_m'=>deck_top_z/1.m,'top_elevation_m'=>deck_top_z/1.m+h,'concrete_class'=>cc,'concrete_volume_m3'=>vol,'formwork_area_m2'=>fw,'formwork_color'=>form_hex,'concrete_color'=>conc_hex,'start_offset_m'=>os,'end_offset_m'=>oe}.each{|k,val|g.set_attribute(DICT,k,val)}
  finalize_bim_identity(g,model)
  out << g
 end
 out
end

# ===== v0.38 DS1 — Döşeme planı (saf hesap, SketchUp'a dokunmaz) =====
# Kurallar (kullanıcı kararı 2026-10-10):
#  * Döşeme ilk BK dış yüzünden son BK dış yüzüne; alt kot = en yüksek BK üst kotu (z0), üst = z0 + kalınlık.
#  * PD / kanal / vinç prekastının gerçek hacmi döşemeden çıkar (oturma payı sabit 0.15 değil, prekastın kendi boyu).
#  * İki BK arasındaki açıklıkta, prekast üst kotuna kadar olan katman hiç dökülmez (altında taşıyıcı yok);
#    kalınlık prekasttan fazlaysa üstteki kabuk prekastların üstüne dökülür.
#  * Açıklıkta PD olmayan şerit: döşeme oluşmaz + uyarı. PD aralarındaki ≤ 5 cm derzler boşluk sayılmaz.
#  * Kanal: kanalın iç genişliği kanal boyunca kanal tabanından döşeme üstüne kadar açık kalır;
#    BK üzerinde döşeme kanalı kapatır (kanalın kendi hacmi dışında).
# Girdi (metre, döşeme düzlemi u = boyuna, v = enine):
#  bks  : [{'id','u0','u1','v0','v1','ztop'}]
#  pcs  : [{'id','type','u0','u1','v0','v1','z0','z1','iw','base'}]
#  curbs: [{'kind'=>'curb'|'bollard','side','id','u0','u1','v0','v1','h'}] — DS1.5: tretuvar ve baba kaideleri
#         döşemenin üstüne (alt kot = döşeme üstü) döşemeyle AYNI gövdede, monolitik eklenir
# Çıktı: kutular (döşeme betonu = kutuların birleşimi, kutular ayrık), çizilecek yüzler, metraj, uyarılar.
MST_DECK_JOINT_MAX=0.05
MST_DECK_TOL=1.0e-4

def mst_iv_sub(ivs,a,b)
 return ivs if b<=a
 out=[]
 ivs.each do |x,y|
  if b<=x || a>=y then out << [x,y]
  else
   out << [x,a] if a-x>MST_DECK_TOL
   out << [b,y] if y-b>MST_DECK_TOL
  end
 end
 out
end

def mst_iv_len(ivs)
 ivs.inject(0.0){|s,(a,b)|s+(b-a)}
end

def mst_iv_union(ivs)
 out=[]
 ivs.sort.each{|a,b|next if b-a<=0;if out.empty? || a>out[-1][1]+MST_DECK_TOL then out << [a,b] else out[-1][1]=[out[-1][1],b].max end}
 out
end

def mst_breaks(vals,lo,hi)
 out=[]
 (vals+[lo,hi]).map(&:to_f).select{|x|x>=lo-MST_DECK_TOL && x<=hi+MST_DECK_TOL}.map{|x|[[x,lo].max,hi].min}.sort.each{|x|out << x if out.empty? || x-out[-1]>MST_DECK_TOL}
 out[-1]=hi if out.length>1 && (out[-1]-hi).abs<=MST_DECK_TOL
 out
end

# boolean hücre maskesini dikdörtgenlere birleştirir: [[u0,u1,v0,v1],...]
def mst_merge_mask(mask,ub,vb)
 out=[];openr={}
 nu=ub.length-1;nv=vb.length-1
 (0..nu).each do |i|
  keys=[]
  if i<nu
   j=0
   while j<nv
    if mask[i][j]
     k=j;k+=1 while k+1<nv && mask[i][k+1]
     keys << [vb[j].round(6),vb[k+1].round(6)];j=k+1
    else
     j+=1
    end
   end
  end
  openr.keys.each{|k|next if keys.include?(k);out << [openr.delete(k),ub[i],k[0],k[1]]}
  keys.each{|k|openr[k]||=ub[i]}
 end
 out.sort
end

def mst_deck_plan(bks,pcs,th,curbs=[])
 th=th.to_f
 err=[];warn=[]
 raise 'Döşeme kalınlığı sıfırdan büyük olmalıdır.' if th<=0
 raise 'Döşeme için en az iki Başlık Kirişi gerekir.' if bks.length<2
 bks=bks.sort_by{|b|(b['u0']+b['u1'])/2.0}
 z0=bks.map{|b|b['ztop'].to_f}.max;zt=z0+th
 zspread=z0-bks.map{|b|b['ztop'].to_f}.min
 warn << "BK üst kotları arasında #{format('%.3f',zspread)} m fark var; en yüksek kot (#{format('%+.3f',z0)}) kullanıldı." if zspread>0.005
 gu0=bks.first['u0'];gu1=bks.last['u1'];gv0=bks.map{|b|b['v0']}.min;gv1=bks.map{|b|b['v1']}.max
 bks.each{|b|warn << "#{b['id']}: BK eni döşeme eninden kısa (#{format('%.3f',b['v0'])}–#{format('%.3f',b['v1'])}); BK dışında kalan şerit taşıyıcısız." if b['v0']>gv0+0.005 || b['v1']<gv1-0.005}
 inside=->(p){p['u1']>gu0+MST_DECK_TOL && p['u0']<gu1-MST_DECK_TOL && p['v1']>gv0+MST_DECK_TOL && p['v0']<gv1-MST_DECK_TOL}
 pcs=pcs.select{|p|inside.(p) && p['z1']>z0+MST_DECK_TOL && p['z0']<zt-MST_DECK_TOL}
 # açıklıklar
 spans=[]
 bks.each_cons(2).with_index(1) do |(a,b),i|
  next if b['u0']-a['u1']<=MST_DECK_TOL
  mates=pcs.select{|p|p['u0']<b['u0']-MST_DECK_TOL && p['u1']>a['u1']+MST_DECK_TOL}
  s={'index'=>i,'a'=>a['id'],'b'=>b['id'],'u0'=>a['u1'],'u1'=>b['u0'],'count'=>mates.length}
  if mates.empty?
   err << "Aks aralığı #{i} (#{a['id']} – #{b['id']}): prekast yok; döşeme oluşturulamaz."
   s['hs']=th;s['ph']=0.0;s['gaps']=[[gv0,gv1]];s['joints']=[];s['pu']=[a['u1'],b['u0']];s['cov']=[]
  else
   ph=mates.map{|p|p['z1']}.max-z0
   warn << "Aks aralığı #{i}: prekast üstü (#{format('%+.3f',z0+ph)}) döşeme üstünden (#{format('%+.3f',zt)}) yüksek; prekast döşemeden taşar." if ph>th+0.001
   s['ph']=ph;s['hs']=[ph,th].min
   cov=mst_iv_union(mates.map{|p|[[p['v0'],gv0].max,[p['v1'],gv1].min]})
   holes=[];cur=gv0
   cov.each{|a0,a1|holes << [cur,a0] if a0-cur>MST_DECK_TOL;cur=[cur,a1].max}
   holes << [cur,gv1] if gv1-cur>MST_DECK_TOL
   s['joints']=holes.select{|a0,a1|a1-a0<=MST_DECK_JOINT_MAX+MST_DECK_TOL && a0>gv0+MST_DECK_TOL && a1<gv1-MST_DECK_TOL}
   s['gaps']=holes-s['joints']
   # DS1.3: prekast cebi düz hat — açıklığın prekast boyu (oturma payları dahil) × PD'lerin kapladığı
   # enine aralık (derzler dahil) tek dikdörtgen bölge olarak kesilir; BK üzerinde derz dişi kalmaz.
   s['pu']=[[mates.map{|p|p['u0']}.min,gu0].max,[mates.map{|p|p['u1']}.max,gu1].min]
   s['cov']=mst_iv_union(cov+s['joints'])
   s['gaps'].each{|a0,a1|warn << "Aks aralığı #{i} (#{a['id']} – #{b['id']}): enine #{format('%.3f',a0)}–#{format('%.3f',a1)} arasında PD yok (#{format('%.2f',a1-a0)} m); PD olmayan şeritte yerinde döküm (#{format('%+.2f',z0)} – #{format('%+.2f',zt)}); alt kalıp gerekir."}
  end
  spans << s
 end
 # kanal iç açıklıkları
 opens=pcs.select{|p|p['type']=='channel_precast' && p['iw'].to_f>0}.map do |p|
  vc=(p['v0']+p['v1'])/2.0
  # DS1.4: kanal prekastının üstü kanalın tüm boyunca açık (kullanıcının çizdiği döşemeyle aynı)
  ou0=[p['u0'],gu0].max;ou1=[p['u1'],gu1].min
  {'id'=>p['id'],'u0'=>ou0,'u1'=>ou1,'v0'=>[vc-p['iw']/2.0,gv0].max,'v1'=>[vc+p['iw']/2.0,gv1].min,'zf'=>p['z0']+p['base'].to_f}
 end.select{|o|o['u1']>o['u0'] && o['v1']>o['v0']}
 ub=mst_breaks(spans.flat_map{|s|s['pu']}+bks.flat_map{|b|[b['u0'],b['u1']]}+pcs.flat_map{|p|[p['u0'],p['u1']]}+opens.flat_map{|o|[o['u0'],o['u1']]}+curbs.flat_map{|c|[c['u0'],c['u1']]},gu0,gu1)
 vb=mst_breaks(bks.flat_map{|b|[b['v0'],b['v1']]}+pcs.flat_map{|p|[p['v0'],p['v1']]}+opens.flat_map{|o|[o['v0'],o['v1']]}+curbs.flat_map{|c|[c['v0'],c['v1']]}+spans.flat_map{|s|(s['gaps']+s['joints']).flatten},gv0,gv1)
 nu=ub.length-1;nv=vb.length-1
 cov2=->(r,um,vm){um>r['u0'] && um<r['u1'] && vm>r['v0'] && vm<r['v1']}
 cells=Array.new(nu){Array.new(nv)}
 state=Array.new(nu){Array.new(nv)}
 open_vol=0.0;span_area=0.0;open_area=0.0;gap_area=0.0;add_vol=Hash.new(0.0);add_skip=[]
 nu.times do |i|
  um=(ub[i]+ub[i+1])/2.0
  nv.times do |j|
   vm=(vb[j]+vb[j+1])/2.0;ar=(ub[i+1]-ub[i])*(vb[j+1]-vb[j])
   ivs=[[z0,zt]]
   onbk=bks.any?{|b|cov2.(b,um,vm)}
   sp=nil
   gap=false
   # DS1.3: prekast cebi (açıklık + oturma payları, derzler dahil) prekast üstüne kadar dökülmez
   pk=spans.find{|s|um>s['pu'][0] && um<s['pu'][1] && s['cov'].any?{|a0,a1|vm>a0 && vm<a1}}
   ivs=mst_iv_sub(ivs,z0,z0+pk['hs']) if pk
   unless onbk
    sp=spans.find{|s|um>s['u0'] && um<s['u1']}
    # DS1.2: PD olmayan şerit (derz değil) tam kalınlıkta yerinde dökülür
    gap=sp && !sp['count'].zero? && sp['gaps'].any?{|a0,a1|vm>a0 && vm<a1}
    ivs=[] if sp.nil?
    ivs=mst_iv_sub(ivs,z0,z0+sp['hs']) if sp && !gap && pk.nil?
    span_area+=ar
    gap_area+=ar if gap
   end
   hit=pcs.select{|p|cov2.(p,um,vm)}
   hit.each{|p|ivs=mst_iv_sub(ivs,p['z0'],p['z1'])}
   op=opens.select{|o|cov2.(o,um,vm)}
   unless op.empty?
    b0=mst_iv_len(ivs);op.each{|o|ivs=mst_iv_sub(ivs,o['zf'],zt)};open_vol+=(b0-mst_iv_len(ivs))*ar;open_area+=ar
   end
   joint=pk && hit.empty? && pk['joints'].any?{|a0,a1|vm>a0 && vm<a1}
   top=!ivs.empty? && (ivs[-1][1]-zt).abs<=MST_DECK_TOL
   pctop=hit.any?{|p|p['z1']>=zt-0.001}
   st=if !op.empty? then 'open' elsif top || pctop || joint then 'surface' else 'hole' end
   st='surface' if st=='hole' && !ivs.empty? && sp.nil?   # BK üstünde alçak kalan döşeme (prekast taşması) — yüzey sayılır
   # DS1.5: tretuvar / baba kaidesi — döşeme üstüne monolitik (en yüksek olan geçerli)
   ad=curbs.select{|c|c['h'].to_f>0 && cov2.(c,um,vm)}
   unless ad.empty?
    if op.empty?
     hmax=ad.map{|c|c['h'].to_f}.max
     if !ivs.empty? && (ivs[-1][1]-zt).abs<=MST_DECK_TOL then ivs[-1][1]=zt+hmax else ivs << [zt,zt+hmax] end
     k=ad.any?{|c|c['kind']=='bollard'} ? 'bollard' : 'curb'
     add_vol[k]+=hmax*ar
    else
     add_skip << ad.map{|c|c['id'] || "#{c['kind']} #{c['side']}"}.join(', ')
    end
   end
   cells[i][j]=ivs.map{|a,b|[a.round(6),b.round(6)]}
   state[i][j]={'st'=>st,'joint'=>joint,'span'=>sp,'pk'=>pk,'hit'=>hit}
  end
 end
 # hücreleri kutulara birleştir (önce v boyunca, sonra u boyunca)
 cols=(0...nu).map do |i|
  runs=[];j=0
  while j<nv
   k=j;k+=1 while k+1<nv && cells[i][k+1]==cells[i][j]
   runs << [vb[j],vb[k+1],cells[i][j]] unless cells[i][j].empty?
   j=k+1
  end
  runs
 end
 boxes=[];openr={}
 (0..nu).each do |i|
  cur=i<nu ? cols[i] : []
  keys=cur.map{|v0,v1,iv|[v0.round(6),v1.round(6),iv]}
  openr.keys.each{|k|next if keys.include?(k);u0=openr.delete(k);k[2].each{|a,b|boxes << [u0,ub[i],k[0],k[1],a,b]}}
  keys.each{|k|openr[k]||=ub[i]}
 end
 boxes.sort!
 vol=boxes.inject(0.0){|s,b|s+(b[1]-b[0])*(b[3]-b[2])*(b[5]-b[4])}
 # yüzler: kutuların birleşiminin sınırı; yan yüzler komşu döşeme kutusuyla örtüşen kısımlardan arındırılır,
 # kalan parçalar prekast / derz harcı / BK ile temas eden (kalıp değil) ve açık (kalıp) olarak ayrılır.
 grout=[]
 nu.times{|i|nv.times{|j|s=state[i][j];next unless s['joint'];grout << [ub[i],ub[i+1],vb[j],vb[j+1],z0,z0+s['pk']['hs']]}}
 solids=pcs.map{|p|[p['u0'],p['u1'],p['v0'],p['v1'],p['z0'],p['z1']]}+grout+bks.map{|b|[b['u0'],b['u1'],b['v0'],b['v1'],-1.0e9,b['ztop']]}
 faces=[];fw_out=0.0;fw_in=0.0;fw_bot=0.0
 boxes.each_with_index do |b,bi|
  faces << {'kind'=>'top','u'=>[b[0],b[1]],'v'=>[b[2],b[3]],'z'=>b[5]}
  # alt yüz: altında BK / prekast / derz harcı varsa temas, yoksa alt kalıp (PD boşluğundaki yerinde döküm)
  under=solids.select{|o|(o[5]-b[4]).abs<=MST_DECK_TOL && o[0]<b[1]-MST_DECK_TOL && o[1]>b[0]+MST_DECK_TOL && o[2]<b[3]-MST_DECK_TOL && o[3]>b[2]+MST_DECK_TOL}
  if under.empty?
   faces << {'kind'=>'bottom_form','u'=>[b[0],b[1]],'v'=>[b[2],b[3]],'z'=>b[4]};fw_bot+=(b[1]-b[0])*(b[3]-b[2])
  else
   bu=mst_breaks(under.flat_map{|o|[o[0],o[1]]},b[0],b[1]);bv=mst_breaks(under.flat_map{|o|[o[2],o[3]]},b[2],b[3])
   cm=Array.new(bu.length-1){|i|um=(bu[i]+bu[i+1])/2.0;Array.new(bv.length-1){|j|vm=(bv[j]+bv[j+1])/2.0;under.any?{|o|o[0]<um && o[1]>um && o[2]<vm && o[3]>vm}}}
   mst_merge_mask(cm,bu,bv).each{|u0,u1,v0,v1|faces << {'kind'=>'bottom','u'=>[u0,u1],'v'=>[v0,v1],'z'=>b[4]}}
   mst_merge_mask(cm.map{|r|r.map{|x|!x}},bu,bv).each{|u0,u1,v0,v1|faces << {'kind'=>'bottom_form','u'=>[u0,u1],'v'=>[v0,v1],'z'=>b[4]};fw_bot+=(u1-u0)*(v1-v0)}
  end
  [[0,0,-1],[0,1,1],[1,2,-1],[1,3,1]].each do |ax,ci,dir|
   pl=b[ci];lo,hi=ax==0 ? [b[2],b[3]] : [b[0],b[1]]
   oth=ax==0 ? [2,3] : [0,1];nci=dir>0 ? (ax==0 ? 0 : 2) : (ax==0 ? 1 : 3)
   touch=->(o){(o[nci]-pl).abs<=MST_DECK_TOL && o[oth[0]]<hi-MST_DECK_TOL && o[oth[1]]>lo+MST_DECK_TOL && o[4]<b[5]-MST_DECK_TOL && o[5]>b[4]+MST_DECK_TOL}
   dn=boxes.each_with_index.select{|o,k|k!=bi && touch.(o)}.map(&:first)
   sn=solids.select{|o|touch.(o)}
   tb=mst_breaks((dn+sn).flat_map{|o|[o[oth[0]],o[oth[1]]]},lo,hi)
   zb=mst_breaks((dn+sn).flat_map{|o|[o[4],o[5]]},b[4],b[5])
   outer=(ax==0 && ((pl-gu0).abs<=MST_DECK_TOL || (pl-gu1).abs<=MST_DECK_TOL)) || (ax==1 && ((pl-gv0).abs<=MST_DECK_TOL || (pl-gv1).abs<=MST_DECK_TOL))
   (tb.length-1).times do |a|
    tm=(tb[a]+tb[a+1])/2.0;piece=[]
    (zb.length-1).times do |c|
     zm=(zb[c]+zb[c+1])/2.0
     inn=->(o){o[oth[0]]<tm && o[oth[1]]>tm && o[4]<zm && o[5]>zm}
     k=dn.any?(&inn) ? nil : (sn.any?(&inn) ? 'contact' : 'form')
     piece << [zb[c],zb[c+1],k]
    end
    # aynı türdeki ardışık z parçalarını birleştir
    mz=[];piece.each{|z_0,z_1,k|next unless k;if !mz.empty? && mz[-1][2]==k && (mz[-1][1]-z_0).abs<=MST_DECK_TOL then mz[-1][1]=z_1 else mz << [z_0,z_1,k] end}
    mz.each do |z_0,z_1,k|
     f={'kind'=>k=='form' ? 'side_form' : 'side_contact','ax'=>ax,'pl'=>pl,'t'=>[tb[a],tb[a+1]],'z'=>[z_0,z_1],'n'=>dir,'outer'=>outer}
     faces << f
     ar=(tb[a+1]-tb[a])*(z_1-z_0)
     if k=='form' then outer ? fw_out+=ar : fw_in+=ar end
    end
   end
  end
 end
 # üst yüzey / kaplama alanı
 gross_area=(gu1-gu0)*(gv1-gv0)
 surf=0.0;hole_area=0.0;curb_on_hole=Hash.new(0.0)
 nu.times do |i|
  um=(ub[i]+ub[i+1])/2.0
  nv.times do |j|
   vm=(vb[j]+vb[j+1])/2.0;ar=(ub[i+1]-ub[i])*(vb[j+1]-vb[j]);st=state[i][j]['st']
   cb=curbs.find{|c|cov2.(c,um,vm)}
   hole_area+=ar if st=='hole'
   curb_on_hole[cb['side']]+=ar if cb && st!='surface'
   surf+=ar if st=='surface' && !cb
  end
 end
 # kaplama yüzeyi dikdörtgenleri (hücreler birleştirilmiş)
 smask=Array.new(nu){|i|um=(ub[i]+ub[i+1])/2.0;Array.new(nv){|j|vm=(vb[j]+vb[j+1])/2.0;state[i][j]['st']=='surface' && curbs.none?{|c|cov2.(c,um,vm)}}}
 srects=mst_merge_mask(smask,ub,vb)
 add_skip.uniq.each{|x|warn << "#{x}: kanal açıklığı üzerine gelen kısım oluşturulmadı."}
 curb_on_hole.each{|sd,a|warn << "Bordür taraf #{sd}: #{format('%.2f',a)} m² taşıyıcısız / açık alan üzerinde (PD boşluğu veya kanal)."}
 err.uniq!;warn.uniq!
 {'z0'=>z0,'zt'=>zt,'th'=>th,'gross'=>[gu0,gu1,gv0,gv1],'spans'=>spans.map{|s|s.reject{|k,_|k=='mates'}},
  'openings'=>opens,'boxes'=>boxes,'faces'=>faces,'volume'=>vol,'gross_area'=>gross_area,'gross_volume'=>gross_area*th,
  'opening_volume'=>open_vol,'precast_cut_volume'=>gross_area*th-(vol-add_vol['curb']-add_vol['bollard'])-open_vol,'curb_volume'=>add_vol['curb'],'bollard_volume'=>add_vol['bollard'],'slab_volume'=>vol-add_vol['curb']-add_vol['bollard'],'span_plan_area'=>span_area,'opening_area'=>open_area,
  'hole_area'=>hole_area,'topping_area'=>surf,'surface_rects'=>srects,'formwork_outer'=>fw_out,'formwork_inner'=>fw_in,'formwork_bottom'=>fw_bot,'formwork'=>fw_out+fw_in+fw_bot,'gap_pour_area'=>gap_area,
  'errors'=>err,'warnings'=>warn}
end

# Önizleme metni (oluşturmadan önce gösterilir)
def mst_deck_plan_text(pl,did='D-001')
 g=pl['gross']
 l=["Döşeme #{did} — önizleme (model değişmedi)",
    "Brüt plaka: #{format('%.2f',g[1]-g[0])} × #{format('%.2f',g[3]-g[2])} m, alt #{format('%+.2f',pl['z0'])}, üst #{format('%+.2f',pl['zt'])} (kalınlık #{format('%.2f',pl['th'])} m)",
    "Aks aralıkları:"]
 pl['spans'].each{|s|l << "  #{s['index']}. #{s['a']} – #{s['b']}: net açıklık #{format('%.2f',s['u1']-s['u0'])} m, #{s['count']} prekast, kesilen katman #{format('%.2f',s['hs'])} m#{s['gaps'].empty? ? '' : ", PD boşluğu #{s['gaps'].length}"}#{s['joints'].empty? ? '' : ", derz #{s['joints'].length}"}"}
 l << "Kanal açıklığı: #{pl['openings'].length} (#{pl['openings'].map{|o|o['id']}.join(', ')})" unless pl['openings'].empty?
 ex=pl['curb_volume'].to_f+pl['bollard_volume'].to_f
 l << "Brüt beton #{format('%.3f',pl['gross_volume'])} m³ − prekast/açıklık kesintisi #{format('%.3f',pl['precast_cut_volume'])} − kanal açıklığı #{format('%.3f',pl['opening_volume'])}#{ex>0 ? " + tretuvar/kaide #{format('%.3f',ex)}" : ''} = NET #{format('%.3f',pl['volume'])} m³"
 l << "Kalıp #{format('%.2f',pl['formwork'])} m² (dış kenar #{format('%.2f',pl['formwork_outer'])}, iç kenar #{format('%.2f',pl['formwork_inner'])}, alt kalıp #{format('%.2f',pl['formwork_bottom'])})"
 ph=pl['spans'].map{|s|s['ph'].to_f}.max.to_f
 l << "Kesit: prekast #{format('%.2f',ph)} m + prekast üstü plak #{format('%.2f',[pl['th']-ph,0].max)} m = toplam #{format('%.2f',pl['th'])} m (BK üstünden)" if ph>0
 l << "PD olmayan şeritte yerinde döküm: #{format('%.2f',pl['gap_pour_area'])} m² plan" if pl['gap_pour_area']>0
 l << "Üst yüzey (kaplama alanı) #{format('%.2f',pl['topping_area'])} m²#{pl['hole_area']>0 ? ", taşıyıcısız boşluk #{format('%.2f',pl['hole_area'])} m²" : ''}"
 l << "Tretuvar #{format('%.3f',pl['curb_volume'])} m³ + baba kaideleri #{format('%.3f',pl['bollard_volume'])} m³ döşemeyle aynı gövdede (toplam betona dahil)" if pl['curb_volume']+pl['bollard_volume']>0
 l << "Kutu sayısı #{pl['boxes'].length}"
 unless pl['errors'].empty?
  l << '' << 'HATA (döşeme oluşturulmaz):';pl['errors'].each{|e|l << "  ✗ #{e}"}
 end
 unless pl['warnings'].empty?
  l << '' << 'UYARILAR:';pl['warnings'].each{|w|l << "  ⚠ #{w}"}
 end
 l.join("\n")
end

# v0.38 DS1 — plan inputs from the model: selected BKs + every precast (PD / KN / vinç) in the
# deck plane frame (u = BK dizisi yönü, v = Z × u), metres. Precasts are found geometrically
# (not only by support pids) so a channel placed by KN or a hand-placed PD is cut too.
def mst_deck_frame(hbs)
 centers=hbs.map{|g|mst_world_box_center(g)}
 maxd=-1.0;ca=nil;cb=nil
 centers.combination(2){|a,b|d=Math.hypot(a[0]-b[0],a[1]-b[1]);if d>maxd then maxd=d;ca=a;cb=b end}
 ux=cb[0]-ca[0];uy=cb[1]-ca[1];l=Math.hypot(ux,uy)
 raise 'Seçili BK merkezleri çakışıyor.' if l<0.001
 ux/=l;uy/=l
 # snap to the model axes when the BK row is (nearly) axis-aligned: avoids 1e-12 skew in every box
 if ux.abs>0.999999 then ux=ux<=>0;uy=0.0 elsif uy.abs>0.999999 then uy=uy<=>0;ux=0.0 end
 [ux.to_f,uy.to_f]
end

def mst_world_box_center(e)
 b=mst_world_box(e)
 [(b['x'][0]+b['x'][1])/2.0,(b['y'][0]+b['y'][1])/2.0]
end

def mst_deck_uv(box,ux,uy)
 vx=-uy;vy=ux
 cs=box['x'].product(box['y'])
 us=cs.map{|x,y|x*ux+y*uy};vs=cs.map{|x,y|x*vx+y*vy}
 [us.min,us.max,vs.min,vs.max]
end

def mst_deck_inputs(model,hbs,data)
 ux,uy=mst_deck_frame(hbs)
 bks=hbs.map do |g|
  b=mst_world_box(g);r=mst_deck_uv(b,ux,uy)
  {'id'=>element_visible_id(g).to_s,'axis'=>g.get_attribute(DICT,'axis','').to_s,'u0'=>r[0],'u1'=>r[1],'v0'=>r[2],'v1'=>r[3],'ztop'=>b['z'][1]}
 end
 all=[];collect_elements(model.entities,all)
 pcs=all.select{|e|e.valid? && %w[flat_precast channel_precast crane_precast].include?(e.get_attribute(DICT,'element_type','').to_s)}.map do |e|
  b=mst_world_box(e);r=mst_deck_uv(b,ux,uy)
  {'id'=>(e.get_attribute(DICT,'precast_id','').to_s.empty? ? element_visible_id(e).to_s : e.get_attribute(DICT,'precast_id').to_s),
   'type'=>e.get_attribute(DICT,'element_type','').to_s,'u0'=>r[0],'u1'=>r[1],'v0'=>r[2],'v1'=>r[3],'z0'=>b['z'][0],'z1'=>b['z'][1],
   'iw'=>e.get_attribute(DICT,'inner_width_m',0).to_f,'base'=>e.get_attribute(DICT,'base_thickness_m',0).to_f}
 end
 gu0=bks.map{|b|b['u0']}.min;gu1=bks.map{|b|b['u1']}.max;gv0=bks.map{|b|b['v0']}.min;gv1=bks.map{|b|b['v1']}.max
 curbs=mst_deck_curb_rects(data,gu0,gu1,gv0,gv1)+mst_deck_bollard_rects(data,bks,gv0,gv1)
 [ux,uy,bks,pcs,curbs]
end

# Same rectangles as create_deck_curbs (side 1/2 long, 3/4 ends), metres in u/v.
def mst_deck_curb_rects(data,gu0,gu1,gv0,gv1)
 en=[data['curb_side_1'],data['curb_side_2'],data['curb_side_3'],data['curb_side_4']].map{|x|x==true || x.to_s=='true' || x.to_s=='1'}
 return [] unless en.any?
 w=data['curb_width_m'].to_f;return [] if w<=0 || data['curb_height_m'].to_f<=0
 os=[data['curb_start_offset_m'].to_f,0.0].max;oe=[data['curb_end_offset_m'].to_f,0.0].max
 out=[]
 h=data['curb_height_m'].to_f
 out << {'side'=>'1','u0'=>gu0+os,'u1'=>gu1-oe,'v0'=>gv0,'v1'=>gv0+w} if en[0]
 out << {'side'=>'2','u0'=>gu0+os,'u1'=>gu1-oe,'v0'=>gv1-w,'v1'=>gv1} if en[1]
 out << {'side'=>'3','u0'=>gu0,'u1'=>gu0+w,'v0'=>gv0+os,'v1'=>gv1-oe} if en[2]
 out << {'side'=>'4','u0'=>gu1-w,'u1'=>gu1,'v0'=>gv0+os,'v1'=>gv1-oe} if en[3]
 out.select{|c|c['u1']>c['u0'] && c['v1']>c['v0']}.each{|c|c['kind']='curb';c['h']=h;c['id']="Tretuvar taraf #{c['side']}"}
end

# DS1.5 — baba kaideleri. 'bollard_axes': virgülle aks listesi; "3" = 3. aks BK'sının ortası,
# "3-4" = 3–4 aks aralığının ortası, "*" = bütün BK'lar. Aks adı BK'nın 'axis' bilgisinden, yoksa sırasından.
# Kaide döşeme kenarına (taraf 1 = enine min, taraf 2 = enine max) kenar mesafesiyle yerleşir.
def mst_deck_bollard_rects(data,bks,gv0,gv1)
 return [] unless data['bollard_enabled'].to_s=='1' || data['bollard_enabled']==true
 l=data['bollard_length_m'].to_f;w=data['bollard_width_m'].to_f;h=data['bollard_height_m'].to_f
 return [] if l<=0 || w<=0 || h<=0
 off=[data['bollard_edge_offset_m'].to_f,0.0].max
 # DS1.6: taraf 1, taraf 2 veya iki taraf (varsayılan: iki taraf — kaideler genelde iki kenarda)
 sides=case data['bollard_side'].to_s when '1' then ['1'] when '2' then ['2'] else ['1','2'] end
 sb=bks.sort_by{|b|(b['u0']+b['u1'])/2.0}
 name=->(b,i){b['axis'].to_s.strip.empty? ? (i+1).to_s : b['axis'].to_s.strip}
 cen=->(tok){
  t=tok.strip
  if t=='*'
   sb.each_with_index.map{|b,i|[name.(b,i),(b['u0']+b['u1'])/2.0]}
  elsif t.include?('-')
   a,c=t.split('-',2).map(&:strip)
   ia=sb.each_with_index.find{|b,i|name.(b,i)==a};ic=sb.each_with_index.find{|b,i|name.(b,i)==c}
   (ia && ic) ? [["#{a}-#{c}",((ia[0]['u0']+ia[0]['u1'])/2.0+(ic[0]['u0']+ic[0]['u1'])/2.0)/2.0]] : [[t,nil]]
  else
   ib=sb.each_with_index.find{|b,i|name.(b,i)==t}
   [[t,ib ? (ib[0]['u0']+ib[0]['u1'])/2.0 : nil]]
  end}
 out=[]
 data['bollard_axes'].to_s.split(/[,;\s]+/).reject(&:empty?).each do |tok|
  cen.(tok).each do |nm,uc|
   raise "Baba kaidesi: '#{nm}' aksı seçili BK'lar arasında bulunamadı." if uc.nil?
   sides.each do |side|
    v0=side=='1' ? gv0+off : gv1-off-w
    out << {'kind'=>'bollard','side'=>side,'id'=>"Baba kaidesi aks #{nm} taraf #{side}",'u0'=>uc-l/2.0,'u1'=>uc+l/2.0,'v0'=>v0,'v1'=>v0+w,'h'=>h}
   end
  end
 end
 out.uniq{|c|[c['u0'].round(4),c['v0'].round(4)]}
end

def mst_deck_selected_hbs(model)
 model.selection.to_a.select{|e|(e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.get_attribute(DICT,'element_type')=='head_beam'}
end

# 👁 Önizle: computes the plan and shows it; never changes the model.
def deck_preview(data)
 model=Sketchup.active_model
 hbs=mst_deck_selected_hbs(model)
 if hbs.length<2
  UI.messagebox('Döşeme önizlemesi için en az iki Başlık Kirişi seçiniz.');return
 end
 ux,uy,bks,pcs,curbs=mst_deck_inputs(model,hbs,data)
 pl=mst_deck_plan(bks,pcs,data['thickness_m'].to_f,curbs)
 txt=mst_deck_plan_text(pl,data['deck_id'].to_s.strip.empty? ? 'D-001' : data['deck_id'].to_s.strip)
 puts txt
 UI.messagebox(txt[0,3800])
 pl
rescue => e
 UI.messagebox("Döşeme önizleme hatası: #{e.message}")
 nil
end

# ===== v0.38 DS1.4 — döşemeyi en az yüzle çiz =====
# Aynı düzlemde ve aynı türdeki (üst / alt temas / alt kalıp / yan temas / yan kalıp) dikdörtgen parçalar
# önce birleştirilir, birleşimin sınırı çokgen olarak izlenir; delikler (kanal yarıkları) iç halka olur.
# Böylece üst yüz tek plak, alt yüz düz hatlı olur ve SketchUp'ın yüz birleştirmesine güvenilmez.

# rects: [[x0,x1,y0,y1],...] (örtüşmez) -> [[[x,y],...] halka, ...]; dış halkalar CCW, delikler CW
def mst_rect_union_loops(rects)
 xs=mst_breaks(rects.flat_map{|r|[r[0],r[1]]},rects.map{|r|r[0]}.min,rects.map{|r|r[1]}.max)
 ys=mst_breaks(rects.flat_map{|r|[r[2],r[3]]},rects.map{|r|r[2]}.min,rects.map{|r|r[3]}.max)
 nx=xs.length-1;ny=ys.length-1
 fill=Array.new(nx){|i|xm=(xs[i]+xs[i+1])/2.0;Array.new(ny){|j|ym=(ys[j]+ys[j+1])/2.0;rects.any?{|r|xm>r[0] && xm<r[1] && ym>r[2] && ym<r[3]}}}
 on=->(i,j){i>=0 && j>=0 && i<nx && j<ny && fill[i][j]}
 # yönlü sınır kenarları (dolu hücre solda): grid köşe indeksleriyle
 out=Hash.new{|h,k|h[k]=[]}
 nx.times do |i|
  ny.times do |j|
   next unless fill[i][j]
   out[[i,j]] << [i+1,j] unless on.(i,j-1)          # alt kenar → +x
   out[[i+1,j]] << [i+1,j+1] unless on.(i+1,j)      # sağ kenar → +y
   out[[i+1,j+1]] << [i,j+1] unless on.(i,j+1)      # üst kenar → −x
   out[[i,j+1]] << [i,j] unless on.(i-1,j)          # sol kenar → −y
  end
 end
 loops=[]
 until out.values.all?(&:empty?)
  st=out.keys.find{|k|!out[k].empty?}
  lp=[st];cur=st;prev_d=nil
  loop do
   cands=out[cur]
   nxt=if cands.length==1 || prev_d.nil?
    cands[0]
   else
    # köşegen temas: sola dönüşü tercih et (halkalar basit kalır)
    cands.max_by{|c|d=[c[0]-cur[0],c[1]-cur[1]];prev_d[0]*d[1]-prev_d[1]*d[0]}
   end
   cands.delete(nxt)
   prev_d=[nxt[0]-cur[0],nxt[1]-cur[1]]
   cur=nxt
   break if cur==st
   lp << cur
  end
  pts=lp.map{|i,j|[xs[i],ys[j]]}
  # doğrusal ara noktaları at
  simp=[]
  pts.each_with_index do |p,k|
   a=pts[k-1];b=pts[(k+1)%pts.length]
   cr=(p[0]-a[0])*(b[1]-p[1])-(p[1]-a[1])*(b[0]-p[0])
   simp << p if cr.abs>1e-12
  end
  loops << simp if simp.length>=3
 end
 loops
end

def mst_loop_area(lp)
 a=0.0
 lp.each_with_index{|p,k|q=lp[(k+1)%lp.length];a+=p[0]*q[1]-q[0]*p[1]}
 a/2.0
end

def mst_point_in_loop?(x,y,lp)
 ins=false;j=lp.length-1
 lp.each_with_index{|p,i|q=lp[j];ins=!ins if ((p[1]>y)!=(q[1]>y)) && (x<(q[0]-p[0])*(y-p[1])/(q[1]-p[1])+p[0]);j=i}
 ins
end

# loops -> [[outer, [holes...]], ...]
def mst_loops_nest(loops)
 outers=loops.select{|l|mst_loop_area(l)>0};holes=loops.select{|l|mst_loop_area(l)<0}
 outers.map do |o|
  hs=holes.select do |h|
   x=(h[0][0]+h[1][0])/2.0;y=(h[0][1]+h[1][1])/2.0
   # deliğin bir kenarının hemen dışındaki nokta dış halkanın içinde mi
   mst_point_in_loop?(h[0][0],h[0][1],o) || mst_point_in_loop?(x,y,o)
  end
  [o,hs]
 end
end

# Plan yüzlerini gruplayıp çizer. Dönüş: [çizilen yüz, atlanan]
def mst_deck_draw!(ents,pl,ux,uy,form_mat)
 vx=-uy;vy=ux
 pt=->(u,v,z){Geom::Point3d.new((u*ux+v*vx).m,(u*uy+v*vy).m,z.m)}
 groups=Hash.new{|h,k|h[k]=[]}
 pl['faces'].each do |f|
  if %w[top bottom bottom_form].include?(f['kind'])
   groups[[f['kind'],'h',f['z'].round(6),0,false]] << [f['u'][0],f['u'][1],f['v'][0],f['v'][1]]
  else
   groups[[f['kind'],f['ax'],f['pl'].round(6),f['n'],f['outer']]] << [f['t'][0],f['t'][1],f['z'][0],f['z'][1]]
  end
 end
 made=0;skipped=0
 groups.each do |(kind,ax,c,n,outer),rects|
  form=(kind=='side_form' || kind=='bottom_form')
  if ax=='h'
   to3=->(a,b){pt.(a,b,c)}
   want=Geom::Vector3d.new(0,0,kind=='top' ? 1 : -1)
  elsif ax==0
   to3=->(a,b){pt.(c,a,b)}
   want=Geom::Vector3d.new(ux*n,uy*n,0)
  else
   to3=->(a,b){pt.(a,c,b)}
   want=Geom::Vector3d.new(vx*n,vy*n,0)
  end
  mst_loops_nest(mst_rect_union_loops(rects)).each do |outer_lp,holes|
   face=(ents.add_face(outer_lp.map{|a,b|to3.(a,b)}) rescue nil)
   unless face
    skipped+=1;next
   end
   holes.each do |h|
    hf=(ents.add_face(h.map{|a,b|to3.(a,b)}) rescue nil)
    hf.erase! if hf && hf.valid?
   end
   face.reverse! if face.normal.dot(want)<0
   if form
    mark_formwork_face(face,true,form_mat,nil,kind=='bottom_form' ? 'BOTTOM_FORM' : (outer ? 'FREE_OUTER_EDGE' : 'FREE_INNER_EDGE'))
   else
    mark_formwork_face(face,false,nil,nil)
   end
   made+=1
  end
 end
 [made,skipped]
end


# Core builder (no dialogs): plan → one deck group (+ curbs) in ONE undo step. Raises on plan errors.
# DS2: everything a deck is made of, drawn into an EMPTY deck group (creation and regeneration share it).
def mst_deck_fill!(parent,model,hbs,data,pl,ins)
 th=data['thickness_m'].to_f
 conc=data['concrete_class'].to_s.strip;conc='C35/45' if conc.empty?
 deck_form_hex=data['formwork_color'].to_s.strip;deck_form_hex='#66A9E8' if deck_form_hex.empty?
 deck_conc_hex=data['concrete_color'].to_s.strip;deck_conc_hex='#D9D9D9' if deck_conc_hex.empty?
 did=data['deck_id'].to_s.strip;did='D-001' if did.empty?
 ux,uy,bks,pcs,curb_rects=ins
 deck_form_mat=material_for(model,"MAG Döşeme Kalıp #{deck_form_hex}",deck_form_hex)
 made,skipped=mst_deck_draw!(parent.entities,pl,ux,uy,deck_form_mat)
 raise "Döşeme yüzeyleri çizilemedi (#{skipped} yüz)." if made==0
 merged=mst_deck_merge_coplanar!(parent.entities)
 clean_deck_top_coplanar_edges(parent)
 zt_i=pl['zt'].m
 parent.set_attribute(DICT,'deck_merged_edges',merged)
 parent.set_attribute(DICT,'deck_top_face_count',parent.entities.grep(Sketchup::Face).count{|f|f.normal.z>0.999 && (f.vertices[0].position.z-zt_i).abs<0.01})
 g=pl['gross'];gross_len=g[1]-g[0];gross_w=g[3]-g[2]
 vx=-uy;vy=ux
 zz=Geom::Vector3d.new(0,0,1);u=Geom::Vector3d.new(ux,uy,0);v=Geom::Vector3d.new(vx,vy,0)
 parent.set_attribute(DICT,'element_type','deck_slab');parent.set_attribute(DICT,'deck_id',did)
 parent.set_attribute(DICT,'geometry_structure','ds1_union_boundary_faces')
 parent.set_attribute(DICT,'deck_schema','DS2')
 parent.set_attribute(DICT,'deck_drawn_faces',made);parent.set_attribute(DICT,'deck_skipped_faces',skipped)
 support_pids=hbs.map{|b|b.persistent_id};support_uids=hbs.map{|b|ensure_uid(b)}
 {'support_pids'=>support_pids.join(','),'support_uids'=>support_uids.join(','),'support_hb_ids'=>bks.map{|b|b['id']}.join(','),
  'support_count'=>hbs.length,'cut_count'=>pl['spans'].length,'thickness_m'=>th,'bottom_elevation_m'=>pl['z0'],'top_elevation_m'=>pl['zt'],
  'concrete_class'=>conc,'gross_area_m2'=>pl['gross_area'],'precast_cut_area_m2'=>pl['span_plan_area'],
  'gross_concrete_volume_m3'=>pl['gross_volume'],'precast_cut_volume_m3'=>pl['precast_cut_volume'],'channel_opening_volume_m3'=>pl['opening_volume'],
  'concrete_volume_m3'=>pl['volume'],'channel_opening_count'=>pl['openings'].length,'gross_length_m'=>gross_len,'width_m'=>gross_w,
  'precast_seat_m'=>data['precast_seat_m'].to_f,'formwork_area_m2'=>pl['formwork'],'formwork_long_sides_m2'=>pl['formwork_outer'],
  'formwork_end_faces_m2'=>0.0,'deck_formwork_outer_m2'=>pl['formwork_outer'],'deck_formwork_inner_m2'=>pl['formwork_inner'],'formwork_bottom_m2'=>pl['formwork_bottom'],'deck_gap_pour_area_m2'=>pl['gap_pour_area'],
  'formwork_color'=>deck_form_hex,'concrete_color'=>deck_conc_hex,
  'formwork_rule'=>'DS1.2: exposed vertical faces (outer edges, channel openings) + bottom faces over open air (cast-in-place strip where no PD); contact with BK, precast and joint grout excluded',
  'precast_cut_heights_m'=>pl['spans'].map{|s|format('%.3f',s['hs'])}.join(','),
  'deck_gap_count'=>pl['spans'].inject(0){|a,s|a+s['gaps'].length},'deck_hole_area_m2'=>pl['hole_area'],
  'deck_warning_count'=>pl['warnings'].length,'deck_warnings'=>pl['warnings'].join("\n"),
  'deck_u_axis'=>JSON.generate([ux,uy]),
  'deck_plan_json'=>JSON.generate({'boxes'=>pl['boxes'].map{|b|b.map{|x|x.round(6)}},'surface_rects'=>pl['surface_rects'].map{|b|b.map{|x|x.round(6)}},
    'openings'=>pl['openings'],'spans'=>pl['spans'].map{|s|{'index'=>s['index'],'a'=>s['a'],'b'=>s['b'],'u0'=>s['u0'],'u1'=>s['u1'],'hs'=>s['hs'],'gaps'=>s['gaps'],'joints'=>s['joints'].length}}})}.each{|k,val|parent.set_attribute(DICT,k,val)}
 # DS1.5: tretuvar ve baba kaideleri döşemeyle aynı gövdede (ayrı grup yok); metraj tek beton kalemi
 curbs=curb_rects.select{|c|c['kind']=='curb'}
 parent.set_attribute(DICT,'curb_count',curbs.length)
 parent.set_attribute(DICT,'bollard_count',curb_rects.count{|c|c['kind']=='bollard'})
 parent.set_attribute(DICT,'deck_slab_volume_m3',pl['slab_volume'])
 parent.set_attribute(DICT,'curb_volume_m3',pl['curb_volume'])
 parent.set_attribute(DICT,'bollard_volume_m3',pl['bollard_volume'])
 parent.set_attribute(DICT,'deck_curb_json',JSON.generate(%w[curb_side_1 curb_side_2 curb_side_3 curb_side_4 curb_width_m curb_height_m curb_start_offset_m curb_end_offset_m].map{|k|[k,data[k].to_s]}.to_h))
 parent.set_attribute(DICT,'deck_bollard_json',JSON.generate(%w[bollard_enabled bollard_axes bollard_side bollard_length_m bollard_width_m bollard_height_m bollard_edge_offset_m].map{|k|[k,data[k].to_s]}.to_h))
 parent.set_attribute(DICT,'deck_additions_json',JSON.generate(curb_rects.map{|c|c.merge('u0'=>c['u0'].round(6),'u1'=>c['u1'].round(6),'v0'=>c['v0'].round(6),'v1'=>c['v1'].round(6))}))
 topping_on=data['topping_enabled'].to_s=='1'
 topping_th=data['topping_thickness_m'].to_f;topping_th=0.10 if topping_th<=0
 topping_area=topping_on ? pl['topping_area'] : 0.0
 parent.set_attribute(DICT,'topping_enabled',topping_on ? '1' : '0');parent.set_attribute(DICT,'topping_thickness_m',topping_th)
 parent.set_attribute(DICT,'topping_concrete_class',data['topping_concrete_class'].to_s);parent.set_attribute(DICT,'topping_area_m2',topping_area);parent.set_attribute(DICT,'topping_volume_m3',topping_area*topping_th)
 # DS2: creation inputs are kept so the deck can rebuild itself after a BK / PD / channel change
 parent.set_attribute(DICT,'deck_input_json',JSON.generate(data.reject{|k,_|k.to_s.start_with?('_')}))
 curbs
end

# Core builder (no dialogs): plan → one deck group (+ curbs, bollards) in ONE undo step. Raises on plan errors.
def mst_deck_build!(model,hbs,data,pl=nil,ins=nil)
 th=data['thickness_m'].to_f
 raise 'Döşeme kalınlığı sıfırdan büyük olmalıdır.' if th<=0
 did=data['deck_id'].to_s.strip;did='D-001' if did.empty?
 ins||=mst_deck_inputs(model,hbs,data)
 pl||=mst_deck_plan(ins[2],ins[3],th,ins[4])
 raise "Döşeme planı hatalı:\n#{pl['errors'].join("\n")}" unless pl['errors'].empty?
 model.start_operation('MST Döşeme Oluştur',true)
 begin
  # DS1.1: the plan is in world coordinates -> draw in the model root
  parent=model.entities.add_group;parent.name="Döşeme #{did}"
  curbs=mst_deck_fill!(parent,model,hbs,data,pl,ins)
  finalize_bim_identity(parent,model)
  commit_with_dependencies(model)   # dependency metadata + commit (one undo step)
 rescue Exception
  model.abort_operation
  raise
 end
 [parent,pl,curbs]
end

# DS1.3: the deck reads as ONE slab — an edge between two coplanar faces with the same role
# (both formwork or both not) is erased, so SketchUp merges them into a single face
# (top = one plate with the channel slots as holes; flat bottom; straight sides).
def mst_deck_merge_coplanar!(ents)
 merged=0
 4.times do
  changed=false
  ents.grep(Sketchup::Edge).each do |e|
   next unless e.valid?
   fs=e.faces
   next unless fs.length==2
   a,b=fs
   next unless a.normal.dot(b.normal)>0.999999
   pl=a.plane
   next unless b.vertices.all?{|v|v.position.distance_to_plane(pl)<0.001}
   next unless a.get_attribute(DICT,'formwork',false)==b.get_attribute(DICT,'formwork',false) && a.material==b.material
   e.erase!;merged+=1;changed=true
  end
  break unless changed
 end
 ents.grep(Sketchup::Edge).each{|e|e.erase! if e.valid? && e.faces.empty?}
 merged
end

def create_deck_slab(data)
 model=Sketchup.active_model
 hbs=mst_deck_selected_hbs(model)
 if hbs.length<2
  UI.messagebox('Döşeme için en az iki Başlık Kirişi seçiniz.');return
 end
 raise 'Döşeme kalınlığı sıfırdan büyük olmalıdır.' if data['thickness_m'].to_f<=0
 did=data['deck_id'].to_s.strip;did='D-001' if did.empty?
 ins=mst_deck_inputs(model,hbs,data)
 pl=mst_deck_plan(ins[2],ins[3],data['thickness_m'].to_f,ins[4])
 txt=mst_deck_plan_text(pl,did)
 puts txt
 unless pl['errors'].empty?
  UI.messagebox(txt[0,3800]);return
 end
 # preview before mutation
 return unless UI.messagebox("#{txt[0,3500]}\n\nDöşeme bu planla oluşturulsun mu? (tek Geri Al)",MB_YESNO)==IDYES
 parent,pl,curbs=mst_deck_build!(model,hbs,data,pl,ins)
 model.selection.clear;model.selection.add(parent);model.active_view.zoom(parent)
 UI.messagebox("Döşeme #{did} oluşturuldu.\nNet beton #{format('%.3f',pl['volume'])} m³ • yan kalıp #{format('%.2f',pl['formwork'])} m² • kaplama alanı #{format('%.2f',pl['topping_area'])} m²\nTretuvar: #{curbs.length} taraf • Baba kaidesi: #{parent.get_attribute(DICT,'bollard_count').to_i} (döşemeyle aynı grupta)#{pl['warnings'].empty? ? '' : "\n#{pl['warnings'].length} uyarı (Ruby Console'da ve döşemenin bilgisinde)."}")
 parent
rescue => e
 UI.messagebox("Döşeme oluşturma hatası: #{e.message}")
 nil
end

# ===== v0.38 DS3 — Döşeme Donatı BIM (saf hesap) =====
# Girdi: döşeme planı (kutular, kanal açıklıkları, aralıklar), tretuvar/kaide dikdörtgenleri, parametreler.
# Çıktı: çubuklar [{role,d,pts=[[u,v,z],...]}] ve etriyeler/çemberler [{role,d,pts=[...] kapalı}] (metre, u/v/z).
# Katmanlar (yukarıdan aşağı):
#   DECK-TOP-L  üst hasır, boyuna (u)      — döşeme dış kenarında aşağı gönyeli
#   DECK-TOP-T  üst hasır, enine (v)       — döşeme dış kenarında aşağı gönyeli
#   DECK-BOT-T / DECK-BOT-L  plak alt hasırı (PD üstü plak)
#   DECK-FILL-L / DECK-FILL-T  dolgu alt hasırı (BK üstü +0,30 bölgesi ve PD olmayan şerit, BK üst kotundan)
#   CURB-L + CURB-STIRRUP  tretuvar: 4 boyuna + kapalı etriye
#   BOLLARD-V + BOLLARD-HOOP  baba kaidesi: plağa inen düşey filizler + yatay çember
MST_DECK_REBAR_STOCK_M=12.0

def mst_deck_rebar_params(data)
 f=->(k,dflt){v=data[k].to_s.strip.tr(',','.');v.empty? ? dflt : v.to_f}
 {'cover_mm'=>f.('cover_mm',50.0),
  'top_l'=>{'d'=>f.('top_l_dia_mm',16.0),'s'=>f.('top_l_sp_cm',15.0)/100.0},'top_t'=>{'d'=>f.('top_t_dia_mm',16.0),'s'=>f.('top_t_sp_cm',15.0)/100.0},
  'bot_l'=>{'d'=>f.('bot_l_dia_mm',14.0),'s'=>f.('bot_l_sp_cm',15.0)/100.0},'bot_t'=>{'d'=>f.('bot_t_dia_mm',14.0),'s'=>f.('bot_t_sp_cm',15.0)/100.0},
  'fill_l'=>{'d'=>f.('fill_l_dia_mm',16.0),'s'=>f.('fill_l_sp_cm',15.0)/100.0},'fill_t'=>{'d'=>f.('fill_t_dia_mm',16.0),'s'=>f.('fill_t_sp_cm',15.0)/100.0},
  'edge_hooks'=>data['edge_hooks'].to_s!='0',
  'curb_l_d'=>f.('curb_l_dia_mm',12.0),'curb_st_d'=>f.('curb_st_dia_mm',8.0),'curb_st_s'=>f.('curb_st_sp_cm',20.0)/100.0,
  'bol_v_d'=>f.('bol_v_dia_mm',16.0),'bol_h_d'=>f.('bol_h_dia_mm',10.0),'bol_h_s'=>f.('bol_h_sp_cm',15.0)/100.0,
  'lap_d'=>f.('lap_d',50.0),'stock_m'=>f.('stock_m',MST_DECK_REBAR_STOCK_M),
  'stagger'=>data['stagger'].to_s!='0',   # v0.49 LP1: bindirmeler şaşırtmalı
  'chair_on'=>data['chair_on'].to_s!='0','chair_d'=>f.('chair_dia_mm',14.0),'chair_s'=>[f.('chair_sp_cm',100.0),30.0].max/100.0}   # v0.49 SH1 sehpa
end

# eşit aralıklı konumlar (BK donatısındaki SPACING modu gibi): a..b arası, aralık ≤ s
def mst_deck_positions(a,b,s)
 return [] if b<a-1e-9 || s<=0
 return [(a+b)/2.0] if b-a<1e-6
 n=((b-a)/s+1e-9).floor+1
 n=2 if n<2
 (0...n).map{|i|a+(b-a)*i/(n-1).to_f}
end

def mst_deck_rebar_plan(pl,adds,prm)
 boxes=pl['boxes'];g=pl['gross'];z0=pl['z0'];zt=pl['zt'];th=pl['th']
 c=prm['cover_mm']/1000.0
 warn=[];bars=[];loops=[]
 r_=->(dmm){mst_bend_radius_m(dmm)}
 # nokta katı mı (kutuların içi)
 ins=->(u,v,z){boxes.any?{|b|u>b[0]-1e-9 && u<b[1]+1e-9 && v>b[2]-1e-9 && v<b[3]+1e-9 && z>b[4]-1e-9 && z<b[5]+1e-9}}
 # (ax=0: u boyunca, sabit v; ax=1: v boyunca, sabit u) z yüksekliğindeki katı aralıklar
 ivs=->(ax,fix,z){
  rs=boxes.select{|b|z>b[4]+1e-9 && z<b[5]-1e-9 && (ax==0 ? (fix>b[2]+1e-9 && fix<b[3]-1e-9) : (fix>b[0]+1e-9 && fix<b[1]-1e-9))}.map{|b|ax==0 ? [b[0],b[1]] : [b[2],b[3]]}
  mst_iv_union(rs)}
 isect=->(a,b){out=[];a.each{|x0,x1|b.each{|y0,y1|lo=[x0,y0].max;hi=[x1,y1].min;out << [lo,hi] if hi-lo>1e-6}};out}
 # paspayı korunarak çubuğun geçebildiği aralıklar (merkez + iki yan + alt/üst çizgilerin kesişimi)
 clear=->(ax,fix,z,d){e=c+d/2000.0-0.001;[[fix,z],[fix-e,z],[fix+e,z],[fix,z-e],[fix,z+e]].map{|f,zz|ivs.(ax,f,zz)}.inject{|a,b|isect.(a,b)}}
 gu0,gu1,gv0,gv1=g
 dTl=prm['top_l']['d'];dTt=prm['top_t']['d'];hook=prm['edge_hooks']
 # gönye bölgeleri: dış kenardaki gönye düzlemine dik çubuklar girmesin (BK donatısındaki gibi)
 ex_u=c+dTl/1000.0+(hook ? r_.(dTl) : 0.0)+dTt/2000.0
 ex_v=c+dTt/1000.0+(hook ? r_.(dTt) : 0.0)+dTl/2000.0
 near=->(x,y){(x-y).abs<1e-4}
 lapd=prm['lap_d'];stock=prm['stock_m'];stag=Hash.new(0)
 # bir çizgi boyunca çubuk(lar): parçalar, kenar gönyeleri, 12 m'den uzunsa 50Ø bindirme (yan yana)
 lay=lambda do |role,ax,fix,z,d,hooks_ok,lo_lim,hi_lim,shift_dir|
  dm=d/1000.0
  clear.(ax,fix,z,d).each do |a,b|
   at_lo=near.(a,ax==0 ? gu0 : gv0);at_hi=near.(b,ax==0 ? gu1 : gv1)
   a2=at_lo ? lo_lim : a+c;b2=at_hi ? hi_lim : b-c
   next if b2-a2<0.30
   # gönye: dış kenarda, aşağı (üst hasır)
   legs=[nil,nil]
   if hooks_ok
    [[at_lo,a2,0],[at_hi,b2,1]].each do |on,x,k|
     next unless on
     uu,vv=ax==0 ? [x,fix] : [fix,x]
     # aşağı doğru katı derinlik
     e=c+dm/2-0.001
     okz=->(zz){[[0,0],[e,0],[-e,0],[0,e],[0,-e]].all?{|du,dv|ins.(uu+du,vv+dv,zz)}}
     zb=z;zb-=0.01 while zb>z0-1e-6 && okz.(zb-0.01)
     need=12*dm+r_.(d)
     leg=[need,z-(zb+c+dm/2)].min
     legs[k]=leg if leg>=0.10
    end
   end
   # parçalara böl (stok boyu, bindirme lapd·Ø)
   lap=lapd*dm;tot=b2-a2+(legs[0]||0)+(legs[1]||0)
   n=tot<=stock+1e-9 ? 1 : ((tot-lap)/(stock-lap)).ceil
   step=(b2-a2+lap*(n-1))/n
   pcs=n.times.map{|k|s0=a2+k*(step-lap);[s0,k==n-1 ? b2 : s0+step]}
   # v0.49 LP1 şaşırtma: aynı roldeki komşu çizgilerde ekler yarım parça kaydırılır (bir kesitte en çok yarısı eklenir)
   if n>=2 && prm['stagger']!=false && (stag[role]+=1).even?
    pcs=[];cur=a2;e1=a2+[step/2.0,lap+0.5].max
    loop do
     e1=b2 if e1>=b2
     pcs << [cur,e1];break if e1>=b2
     cur=e1-lap;e1=cur+step
    end
   end
   pcs.each_with_index do |(s0,s1),k|
    n=pcs.length
    off=0.0
    if k.odd?
     # bindirme parçası yan yana: paspayını bozmayan tarafa kaydır
     cand=[shift_dir*dm,-shift_dir*dm].find{|o|clear.(ax,fix+o,z,d).any?{|x0,x1|x0<=s0-c+1e-6 && x1>=s1+c-1e-6}}
     if cand.nil?
      warn << "#{role}: bindirme parçası için yer yok (#{format('%.2f',fix)}); parça kaydırılmadı."
      cand=shift_dir*dm
     end
     off=cand
    end
    q=->(x,zz){ax==0 ? [x,fix+off,zz] : [fix+off,x,zz]}
    pts=[q.(s0,z),q.(s1,z)]
    pts.unshift(q.(s0,z-legs[0])) if k==0 && legs[0]
    pts.push(q.(s1,z-legs[1])) if k==n-1 && legs[1]
    bars << {'role'=>role,'d'=>d,'pts'=>pts}
   end
  end
 end
 # --- üst hasır
 zT1=zt-c-dTl/2000.0;zT2=zT1-dTl/2000.0-dTt/2000.0
 vposT=mst_deck_positions(gv0+ex_v,gv1-ex_v,prm['top_l']['s'])
 uposT=mst_deck_positions(gu0+ex_u,gu1-ex_u,prm['top_t']['s'])
 vc=(gv0+gv1)/2.0;uc=(gu0+gu1)/2.0
 vposT.each{|v|lay.('DECK-TOP-L',0,v,zT1,dTl,hook,gu0+c+dTl/2000.0,gu1-c-dTl/2000.0,v<vc ? 1 : -1)}
 uposT.each{|u|lay.('DECK-TOP-T',1,u,zT2,dTt,hook,gv0+c+dTt/2000.0,gv1-c-dTt/2000.0,u<uc ? 1 : -1)}
 # --- plak alt hasırı (prekast üstü)
 ph=(pl['spans'].map{|s|s['hs'].to_f}.max || 0.0)
 zp=z0+ph
 dBl=prm['bot_l']['d'];dBt=prm['bot_t']['d']
 zB1=zp+c+dBl/2000.0;zB2=zB1+dBl/2000.0+dBt/2000.0
 plak_ok=false;fill_ok=false
 if zB2+dBt/2000.0+0.01<zT2-dTt/2000.0
  plak_ok=true
  mst_deck_positions(gv0+ex_v,gv1-ex_v,prm['bot_l']['s']).each{|v|lay.('DECK-BOT-L',0,v,zB1,dBl,false,gu0+ex_u,gu1-ex_u,v<vc ? 1 : -1)}
  mst_deck_positions(gu0+ex_u,gu1-ex_u,prm['bot_t']['s']).each{|u|lay.('DECK-BOT-T',1,u,zB2,dBt,false,gv0+ex_v,gv1-ex_v,u<uc ? 1 : -1)}
 else
  warn << 'Prekast üstü plak alt hasır için ince; plak alt hasırı konmadı.'
 end
 # --- dolgu alt hasırı (BK üstü +0,30 bölgesi, PD olmayan şerit): BK üst kotundan
 dFl=prm['fill_l']['d'];dFt=prm['fill_t']['d']
 zF1=z0+c+dFt/2000.0;zF2=zF1+dFt/2000.0+dFl/2000.0
 if ph>2*c+(dFt+dFl)/1000.0
  fill_ok=true
  fb=boxes.select{|b|b[4]<z0+1e-6}
  fu=mst_iv_union(fb.map{|b|[b[0],b[1]]});fv=mst_iv_union(fb.map{|b|[b[2],b[3]]})
  fu.each{|a,b|mst_deck_positions([a,gu0+ex_u].max+c*0+(near.(a,gu0) ? 0 : c+dFt/2000.0),[b,gu1-ex_u].min-(near.(b,gu1) ? 0 : c+dFt/2000.0),prm['fill_t']['s']).each{|u|lay.('DECK-FILL-T',1,u,zF1,dFt,false,gv0+ex_v,gv1-ex_v,u<uc ? 1 : -1)}}
  fv.each{|a,b|mst_deck_positions([a,gv0+ex_v].max+(near.(a,gv0) ? 0 : c+dFl/2000.0),[b,gv1-ex_v].min-(near.(b,gv1) ? 0 : c+dFl/2000.0),prm['fill_l']['s']).each{|v|lay.('DECK-FILL-L',0,v,zF2,dFl,false,gu0+ex_u,gu1-ex_u,v<vc ? 1 : -1)}}
 end
 # --- v0.49 SH1 sehpa (Π): üst hasırın alt katını (enine) taşır; prekast üstü plak alt hasırına ya da BK üstü dolgu hasırının
 # alt katına oturur. Kol 30 cm (boyuna), ayaklar 15 cm. Kenarlarda / boşlukta / kaidelerde konmaz.
 if prm['chair_on'] && prm['chair_d'].to_f>0 && prm['chair_s'].to_f>0
  dch=prm['chair_d'].to_f;dc=dch/1000.0;ztp=zT2-dTt/2000.0-dc/2;lt=0.30;ft=0.15;ec=c+dc/2-0.001
  fl_v=bars.select{|b|b['role']=='DECK-FILL-L'}.map{|b|b['pts'][0][1]}.uniq.sort
  cus=mst_deck_positions(gu0+ex_u+lt/2+ft+0.05,gu1-ex_u-lt/2-ft-0.05,prm['chair_s'])
  cvs=mst_deck_positions(gv0+ex_v+0.10,gv1-ex_v-0.10,prm['chair_s'])
  bol_adds=adds.select{|a|a['kind']=='bollard'}
  cvs.each do |v0|
   cus.each do |u|
    next if bol_adds.any?{|bo|u+lt/2+ft>bo['u0']-0.05 && u-lt/2-ft<bo['u1']+0.05 && v0>bo['v0']-0.05 && v0<bo['v1']+0.05}
    zz=ztp;zz-=0.01 while zz>z0-0.02 && ins.(u,v0,zz-0.01)
    v=v0;zf=nil
    if plak_ok && ins.(u,v0,zB2) then zf=zB2+dBt/2000.0+dc/2   # plak alt hasırı (BK üstü şeritte de geçer): en üstteki alt hasır
    elsif fill_ok && (zz-z0).abs<0.03
     zf=zF1+dFt/2000.0+dc/2
     nl=fl_v.min_by{|x|(x-v0).abs}
     v=nl+prm['fill_l']['s']/2.0 if nl && (nl-v0).abs<(dFl+dch)/2000.0+0.02   # dolgu üst katının çizgisinde olmasın
    end
    next unless zf && ztp-zf>=0.04
    pts=[[u-lt/2-ft,v,zf],[u-lt/2,v,zf],[u-lt/2,v,ztp],[u+lt/2,v,ztp],[u+lt/2,v,zf],[u+lt/2+ft,v,zf]]
    next unless pts.all?{|x,y,zq|[[0,0],[ec,0],[-ec,0],[0,ec],[0,-ec]].all?{|du,dv|ins.(x+du,y+dv,zq)}}
    bars << {'role'=>'DECK-CHAIR','d'=>dch,'pts'=>pts}
   end
  end
 end
 # --- tretuvar ve baba kaideleri
 dCl=prm['curb_l_d'];dCs=prm['curb_st_d'];dBv=prm['bol_v_d'];dBh=prm['bol_h_d']
 curbs=adds.select{|a|a['kind']=='curb'};bols=adds.select{|a|a['kind']=='bollard'}
 inset=c+[dCs,dBh].max/1000.0+dCl/2000.0
 curb_bars=[]
 curbs.each do |cb|
  alu=(cb['u1']-cb['u0'])>=(cb['v1']-cb['v0'])
  w0,w1=alu ? [cb['v0'],cb['v1']] : [cb['u0'],cb['u1']]
  h=cb['h'].to_f
  zl=[zt+c+[dCs,dBh].max/1000.0+dCl/2000.0,zt+h-c-dCs/1000.0-dCl/2000.0]
  if zl[1]-zl[0]<dCl/1000.0 || (w1-w0)<2*inset+dCl/1000.0
   warn << "#{cb['id']}: kesit donatı için küçük; tretuvar donatısı konmadı.";next
  end
  [w0+inset,w1-inset].each do |w|
   zl.each do |z|
    a0,a1=alu ? [cb['u0']+c,cb['u1']-c] : [cb['v0']+c,cb['v1']-c]
    lap=lapd*dCl/1000.0;tot=a1-a0;n=tot<=stock ? 1 : ((tot-lap)/(stock-lap)).ceil;step=(tot+lap*(n-1))/n
    n.times do |k|
     s0=a0+k*(step-lap);s1=k==n-1 ? a1 : s0+step
     dz=k.odd? ? (z<zt+h/2 ? 1 : -1)*dCl/1000.0 : 0.0
     p0=alu ? [s0,w,z+dz] : [w,s0,z+dz];p1=alu ? [s1,w,z+dz] : [w,s1,z+dz]
     bars << {'role'=>'CURB-L','d'=>dCl,'pts'=>[p0,p1]};curb_bars << [alu,w,z+dz]
    end
   end
  end
  # kapalı etriyeler (kaide içinde atlanır)
  a0,a1=alu ? [cb['u0']+c+dCs/2000.0,cb['u1']-c-dCs/2000.0] : [cb['v0']+c+dCs/2000.0,cb['v1']-c-dCs/2000.0]
  e0=w0+c+dCs/2000.0;e1=w1-c-dCs/2000.0;za=zt+c+dCs/2000.0;zb=zt+h-c-dCs/2000.0
  mst_deck_positions(a0,a1,prm['curb_st_s']).each do |x|
   next if bols.any?{|bo|alu ? (x>bo['u0']-0.02 && x<bo['u1']+0.02) : (x>bo['v0']-0.02 && x<bo['v1']+0.02)}
   pts=alu ? [[x,e0,za],[x,e1,za],[x,e1,zb],[x,e0,zb]] : [[e0,x,za],[e1,x,za],[e1,x,zb],[e0,x,zb]]
   loops << {'role'=>'CURB-STIRRUP','d'=>dCs,'pts'=>pts}
  end
 end
 bols.each do |bo|
  h=bo['h'].to_f
  # yatay çemberler
  hz=mst_deck_positions(zt+c+dBh/2000.0,zt+h-c-dBh/2000.0,prm['bol_h_s'])
  ovc=curbs.any?{|cb|cb['u0']<bo['u1'] && cb['u1']>bo['u0'] && cb['v0']<bo['v1'] && cb['v1']>bo['v0']}
  hz=hz.reject{|z|ovc && curb_bars.any?{|_,_,zc|(z-zc).abs<(dBh+dCl)/2000.0+0.002}}
  hu0=bo['u0']+c+dBh/2000.0;hu1=bo['u1']-c-dBh/2000.0;hv0=bo['v0']+c+dBh/2000.0;hv1=bo['v1']-c-dBh/2000.0
  hz.each{|z|loops << {'role'=>'BOLLARD-HOOP','d'=>dBh,'pts'=>[[hu0,hv0,z],[hu1,hv0,z],[hu1,hv1,z],[hu0,hv1,z]]}}
  # düşey filizler: üst hasır gözlerinin ortası, çember içinde; plağın alt hasırının üstünden kaide üstüne
  gi=c+dBh/1000.0+dBv/2000.0
  vlines=vposT.each_cons(2).map{|a,b|(a+b)/2.0}.select{|v|v>bo['v0']+gi && v<bo['v1']-gi}
  ulines=uposT.each_cons(2).map{|a,b|(a+b)/2.0}.select{|u|u>bo['u0']+gi && u<bo['u1']-gi}
  zs=[zB2+dBt/2000.0,zF2+dFl/2000.0].max+dBv/2000.0+0.01
  zs=zT2-0.15 if zs>zT2-0.15
  ze=zt+h-c-dBh/1000.0
  ulines.product(vlines).each do |u,v|
   next if curb_bars.any?{|alu,w,_|(alu ? (v-w) : (u-w)).abs<(dBv+dCl)/2000.0+0.003}
   next unless ins.(u,v,zs)
   bars << {'role'=>'BOLLARD-V','d'=>dBv,'pts'=>[[u,v,zs],[u,v,ze]]}
  end
  warn << "#{bo['id']}: düşey filiz yerleşmedi (kaide küçük / aralık büyük)." if ulines.empty? || vlines.empty?
 end
 # boylar
 bars.each{|b|b['len']=mst_bent_path(b['pts'],mst_bend_radius_m(b['d']))[0]}
 loops.each do |l|
  p=l['pts'];per=p.each_with_index.map{|a,i|q=p[(i+1)%p.length];Math.sqrt((0..2).map{|j|(q[j]-a[j])**2}.inject(:+))}.inject(:+)
  rs=mst_bend_radius_m(l['d'],true);ext=[10*l['d']/1000.0,0.10].max
  l['len']=per-8*rs+2*Math::PI*rs+2*(ext+rs*0.75*Math::PI)
 end
 kg=bars.inject(0.0){|s,b|s+b['len']*rebar_unit_kg_m(b['d'])}+loops.inject(0.0){|s,l|s+l['len']*rebar_unit_kg_m(l['d'])}
 {'bars'=>bars,'loops'=>loops,'kg'=>kg,'warnings'=>warn,'levels'=>{'top'=>[zT1,zT2],'bot'=>[zB1,zB2],'fill'=>[zF1,zF2]},'ex'=>[ex_u,ex_v]}
end


# ===== v0.38 DS3 — Döşeme Donatı BIM (çizim + arayüz) =====
# Döşeme planı döşemenin kendisinden okunur (deck_plan_json, deck_additions_json, deck_u_axis).
def mst_deck_rebar_inputs(deck)
 pj=JSON.parse(deck.get_attribute(DICT,'deck_plan_json','').to_s) rescue nil
 raise "#{element_visible_id(deck)}: DS1 öncesi döşeme — önce döşemeyi yeniden oluşturun." unless pj.is_a?(Hash) && pj['boxes'].is_a?(Array) && !pj['boxes'].empty?
 ux,uy=JSON.parse(deck.get_attribute(DICT,'deck_u_axis','[1,0]').to_s)
 bx=pj['boxes']
 z0=deck.get_attribute(DICT,'bottom_elevation_m').to_f;th=deck.get_attribute(DICT,'thickness_m').to_f
 pl={'boxes'=>bx,'gross'=>[bx.map{|b|b[0]}.min,bx.map{|b|b[1]}.max,bx.map{|b|b[2]}.min,bx.map{|b|b[3]}.max],
     'z0'=>z0,'zt'=>z0+th,'th'=>th,'spans'=>(pj['spans']||[])}
 adds=(JSON.parse(deck.get_attribute(DICT,'deck_additions_json','[]').to_s) rescue [])
 [ux.to_f,uy.to_f,pl,adds]
end

def mst_deck_rebar_text(deck,rp)
 l=["#{element_visible_id(deck)} — Döşeme Donatı BIM önizleme (model değişmedi)"]
 rp['bars'].group_by{|b|[b['role'],b['d']]}.sort.each{|(r,d),a|l << "  #{r} Ø#{d.to_i}: #{a.length} çubuk, #{format('%.1f',a.inject(0.0){|s,b|s+b['len']})} m, #{a.count{|b|b['pts'].length>2}} gönyeli"}
 rp['loops'].group_by{|b|[b['role'],b['d']]}.sort.each{|(r,d),a|l << "  #{r} Ø#{d.to_i}: #{a.length} adet, #{format('%.1f',a.inject(0.0){|s,b|s+b['len']})} m"}
 l << "Toplam #{format('%.1f',rp['kg'])} kg (#{format('%.3f',rp['kg']/1000.0)} t)"
 l << '' << 'UYARILAR:' unless rp['warnings'].empty?
 rp['warnings'].each{|w|l << "  ⚠ #{w}"}
 l.join("\n")
end

# çubuk çizimi (BK RB1.1 ile aynı: tek parça, bükümler yuvarlak, çapa göre renk)
def mst_deck_rebar_draw!(rg,rp,ux,uy)
 vx=-uy;vy=ux
 w=->(q){[q[0]*ux+q[1]*vx,q[0]*uy+q[1]*vy,q[2]]}   # u/v/z (m) -> dünya (m)
 pt=->(q){Geom::Point3d.new(q[0].m,q[1].m,q[2].m)}
 rp['bars'].each do |b|
  d=b['d'];wp=b['pts'].map{|q|w.(q)}
  bg=rg.entities.add_group;bg.name="#{b['role']} Ø#{d.to_i}"
  if wp.length==2
   p0=pt.(wp[0]);v=Geom::Vector3d.new(wp[1][0]-wp[0][0],wp[1][1]-wp[0][1],wp[1][2]-wp[0][2]);l=v.length.to_f;v.normalize!
   ed=bg.entities.add_circle(p0,v,(d/2000.0).m,12);f=bg.entities.add_face(ed)
   if f
    f.reverse! if f.normal.dot(v)<0
    f.pushpull(l.m)
   end
  else
   r=mst_bend_radius_m(d);mp=mst_bent_polyline(wp,r)
   v=Geom::Vector3d.new(mp[1][0]-mp[0][0],mp[1][1]-mp[0][1],mp[1][2]-mp[0][2]);v.normalize!
   ed=bg.entities.add_circle(pt.(mp[0]),v,(d/2000.0).m,16);f=bg.entities.add_face(ed)
   if f
    path=bg.entities.add_edges(mp.map{|q|pt.(q)})
    f.followme(path)
    path.each{|e|e.erase! if e.valid? && e.faces.empty?}
    bg.entities.grep(Sketchup::Edge).each{|e|fs=e.faces;next unless fs.length==2;(e.soft=true;e.smooth=true) if fs[0].normal.angle_between(fs[1].normal)<40.degrees}
   end
  end
  {'element_type'=>'rebar_bar','rebar_role'=>b['role'],'diameter_mm'=>d,'length_m'=>b['len'],'hook_m'=>0.0,
   'bend_count'=>[wp.length-2,0].max,'bend_radius_m'=>mst_bend_radius_m(d),
   'path_json'=>JSON.generate(wp.map{|q|q.map{|x|x.round(6)}})}.each{|k,val|bg.set_attribute(DICT,k,val)}
  mst_rebar_paint!(bg,d)
 end
 rp['loops'].each do |lp|
  d=lp['d'];wp=lp['pts'].map{|q|w.(q)}
  sg=rg.entities.add_group;sg.name="#{lp['role']} Ø#{d.to_i}"
  sg.entities.add_edges((wp+[wp[0]]).map{|q|pt.(q)})
  {'element_type'=>'rebar_stirrup','rebar_role'=>lp['role'],'diameter_mm'=>d,'length_m'=>lp['len'],'hook_angle_deg'=>135.0,
   'hook_ext_m'=>[10*d/1000.0,0.10].max,'bend_radius_m'=>mst_bend_radius_m(d,true),
   'path_json'=>JSON.generate(wp.map{|q|q.map{|x|x.round(6)}})}.each{|k,val|sg.set_attribute(DICT,k,val)}
  mst_rebar_paint!(sg,d)
 end
end

# Tek Geri Al: eski döşeme donatısını sil, yenisini çiz, tonajı döşemeye yaz.
def mst_deck_rebar_build!(deck,prm,rp=nil)
 model=deck.model
 model.start_operation('MST Döşeme Donatı BIM',true)
 begin
  rp=mst_deck_rebar_fill!(deck,prm,rp)
  commit_with_dependencies(model)
 rescue Exception
  model.abort_operation
  raise
 end
 rp
end

# DS2: rebar drawn into the deck without an own undo step (creation + regeneration share it)
def mst_deck_rebar_fill!(deck,prm,rp=nil)
 mst_rt_history_push!(deck) if respond_to?(:mst_rt_history_push!)   # v0.49 RV1
 ux,uy,pl,adds=mst_deck_rebar_inputs(deck)
 rp||=mst_deck_rebar_plan(pl,adds,prm)
 begin
  deck.entities.grep(Sketchup::Group).select{|g|g.get_attribute(DICT,'element_type','').to_s=='deck_rebar_set'}.each(&:erase!)
  rg=deck.entities.add_group;rg.name="#{element_visible_id(deck)} DÖŞEME DONATI BIM"
  rg.set_attribute(DICT,'element_type','deck_rebar_set');rg.set_attribute(DICT,'parent_uid',deck.get_attribute(DICT,'element_uid','').to_s)
  mst_rebar_tag!(rg,deck)   # v0.38 RB3
  mst_deck_rebar_draw!(rg,rp,ux,uy)
  kg=rp['kg']
  sched=(rp['bars']+rp['loops']).group_by{|b|"#{b['role']} Ø#{b['d'].to_i}"}.map{|k,a|[k,{'count'=>a.length,'length_m'=>a.inject(0.0){|s,b|s+b['len']},'kg'=>a.inject(0.0){|s,b|s+b['len']*rebar_unit_kg_m(b['d'])}}]}.to_h
  {'rebar_mode'=>'bim_detail','rebar_kg'=>kg,'rebar_t'=>kg/1000.0,'rebar_bar_count'=>rp['bars'].length,'rebar_stirrup_count'=>rp['loops'].length,
   'rebar_cover_mm'=>prm['cover_mm'],'deck_rebar_json'=>JSON.generate(prm),'rebar_schedule_json'=>JSON.generate(sched),
   'deck_rebar_warnings'=>rp['warnings'].join("\n")}.each{|k,val|deck.set_attribute(DICT,k,val)}
  rg.set_attribute(DICT,'weight_kg',kg)
 end
 rp
end

def deck_rebar_selected(data,dialog=@d)
 model=Sketchup.active_model
 decks=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
 if decks.empty?
  UI.messagebox('Önce bir Döşeme seçin (döşeme ana grubu).');return
 end
 prm=mst_deck_rebar_params(data)
 decks.each do |deck|
  ux,uy,pl,adds=mst_deck_rebar_inputs(deck)
  rp=mst_deck_rebar_plan(pl,adds,prm)
  txt=mst_deck_rebar_text(deck,rp);puts txt
  next unless UI.messagebox("#{txt[0,3400]}\n\nDonatı bu planla çizilsin mi? (tek Geri Al)",MB_YESNO)==IDYES
  mst_deck_rebar_build!(deck,prm,rp)
  UI.messagebox("#{element_visible_id(deck)}: döşeme donatısı çizildi — #{format('%.3f',rp['kg']/1000.0)} t. Keşif bu tonajı kullanır.")
 end
 send_boq(dialog) if dialog rescue nil
rescue => e
 UI.messagebox("Döşeme donatısı oluşturulamadı:\n#{e.message}")
end


# ===== v0.38 DS2 — döşeme kendini yeniler =====
# BK (ölçü / kot / taşma / cep), PD veya kanal değişince döşeme, kayıtlı oluşturma verisiyle
# (kalınlık, tretuvar, baba kaideleri, kaplama, donatı) yeniden üretilir. Kimlik (element_uid,
# deck_id, tip) korunur. BK düzenlemesinin ardından AYNI Geri Al adımında çalışır.

# oluşturma verisi: DS2 sonrası kayıtlı; önceki döşemelerde öznitelikten kurulur
def mst_deck_input_data(deck)
 d=(JSON.parse(deck.get_attribute(DICT,'deck_input_json','').to_s) rescue nil)
 return d if d.is_a?(Hash) && !d.empty?
 g=->(k){deck.get_attribute(DICT,k,nil)}
 d={'deck_id'=>g.('deck_id').to_s,'thickness_m'=>g.('thickness_m').to_s,'concrete_class'=>g.('concrete_class').to_s,
    'formwork_color'=>g.('formwork_color').to_s,'concrete_color'=>g.('concrete_color').to_s,'precast_seat_m'=>g.('precast_seat_m').to_s,
    'topping_enabled'=>g.('topping_enabled').to_s,'topping_thickness_m'=>g.('topping_thickness_m').to_s,'topping_concrete_class'=>g.('topping_concrete_class').to_s}
 [g.('deck_curb_json'),g.('deck_bollard_json')].each{|j|h=(JSON.parse(j.to_s) rescue nil);d.merge!(h) if h.is_a?(Hash)}
 d
end

def mst_deck_support_beams(deck,model=Sketchup.active_model,all=nil)
 pids=deck.get_attribute(DICT,'support_pids','').to_s.split(',').map(&:to_i).reject(&:zero?)
 unless all
  all=[];collect_elements(model.entities,all)
 end
 bs=all.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='head_beam' && pids.include?(e.persistent_id)}
 if bs.length<pids.length
  # persistent_id değişmişse element_uid ile eşle
  uids=deck.get_attribute(DICT,'support_uids','').to_s.split(',')
  bs=all.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='head_beam' && uids.include?(e.get_attribute(DICT,'element_uid','').to_s)}
 end
 bs
end

# Döşemeyi yerinde yeniden üretir (çağıranın operasyonu içinde). Dönüş: {'old','new','rebar_kg','warnings'}
def mst_deck_regenerate!(deck,model=Sketchup.active_model,skip_same=false)
 raise 'Döşeme geçersiz.' unless deck && deck.valid?
 did=element_visible_id(deck)
 data=mst_deck_input_data(deck)
 # v0.51.5 K53 (ADR-0515 §9): oluşturmadan sonra değişen kaplama durumu (Kaplama Ekle / Kaplama Eğimi) korunur;
 # mst_deck_fill! bunu deck_input_json'a da yazar. Eğim genişliği yeniden hesaplanmaz; fiziksel kaplama yeniden kurulmaz.
 %w[topping_enabled topping_thickness_m topping_concrete_class].each{|k|v=deck.get_attribute(DICT,k,nil);data[k]=v.to_s unless v.nil?}
 hbs=mst_deck_support_beams(deck,model)
 raise "#{did}: dayandığı BK'lar bulunamadı (#{hbs.length})." if hbs.length<2
 ins=mst_deck_inputs(model,hbs,data)
 pl=mst_deck_plan(ins[2],ins[3],data['thickness_m'].to_f,ins[4])
 raise "#{did}: #{pl['errors'].join(' ')}" unless pl['errors'].empty?
 old=[deck.get_attribute(DICT,'concrete_volume_m3').to_f,deck.get_attribute(DICT,'rebar_kg').to_f]
 if skip_same
  # plan ve konum aynıysa dokunma (ağır donatı çizimini boşuna tekrarlama)
  pj=(JSON.parse(deck.get_attribute(DICT,'deck_plan_json','').to_s) rescue {})
  same=pj['boxes']==pl['boxes'].map{|b|b.map{|x|x.round(6)}} && deck.transformation.identity? &&
       (JSON.parse(deck.get_attribute(DICT,'deck_additions_json','[]').to_s) rescue nil)==ins[4].map{|c|c.merge('u0'=>c['u0'].round(6),'u1'=>c['u1'].round(6),'v0'=>c['v0'].round(6),'v1'=>c['v1'].round(6))}
  return nil if same
 end
 rprm=nil
 if deck.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'
  rprm=(JSON.parse(deck.get_attribute(DICT,'deck_rebar_json','').to_s) rescue nil)
 end
 deck.entities.clear!
 deck.transformation=Geom::Transformation.new   # plan dünya koordinatında
 mst_deck_fill!(deck,model,hbs,data,pl,ins)
 rk=0.0
 if rprm.is_a?(Hash)
  rp=mst_deck_rebar_fill!(deck,rprm)
  rk=rp['kg']
 elsif deck.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'
  %w[rebar_mode rebar_kg rebar_t].each{|k|deck.delete_attribute(DICT,k)}
 end
 rev=deck.get_attribute(DICT,'deck_revision_no',0).to_i+1
 deck.set_attribute(DICT,'deck_revision_no',rev)
 {'id'=>did,'old'=>old,'new'=>[pl['volume'],rk],'warnings'=>pl['warnings'],'rev'=>rev}
end

# BK düzenlemesinden / kanal yerleşiminden sonra: o BK'lara dayanan döşemeler.
# Önceki operasyona bağlanır (transparent) → kullanıcı için TEK Geri Al.
def mst_deck_after_edit(beams,model=Sketchup.active_model,quiet=false)
 all=[];collect_elements(model.entities,all)
 pids=beams ? beams.select(&:valid?).map(&:persistent_id) : nil
 decks=all.select do |e|
  next false unless e.valid? && e.get_attribute(DICT,'element_type','').to_s=='deck_slab'
  next false if e.get_attribute(DICT,'deck_plan_json','').to_s.empty?   # DS1 öncesi döşeme: elle yeniden oluşturulur
  pids.nil? || !(e.get_attribute(DICT,'support_pids','').to_s.split(',').map(&:to_i) & pids).empty?
 end
 return [] if decks.empty?
 res=[];errs=[]
 model.start_operation('MST Döşeme Güncelle',true,false,true)   # önceki adıma bağlı (tek Geri Al)
 begin
  decks.each do |dk|
   begin
    r=mst_deck_regenerate!(dk,model,true)
    res << r if r
   rescue => e
    errs << e.message
   end
  end
  commit_with_dependencies(model)
 rescue Exception => e
  # v0.51.5 K12 kuralı: saydam işlem abort edilmez (kullanıcının BK işlemini de geri alabilir); kapatılır, hata bildirilir
  (model.commit_operation rescue nil)
  errs << e.message
 end
 unless quiet && errs.empty? && res.all?{|r|(r['old'][0]-r['new'][0]).abs<1e-6}
  msg=res.map{|r|"#{r['id']} güncellendi (RV-#{format('%02d',r['rev'])}): beton #{format('%.3f',r['old'][0])} → #{format('%.3f',r['new'][0])} m³#{r['new'][1]>0 ? ", donatı #{format('%.1f',r['old'][1])} → #{format('%.1f',r['new'][1])} kg" : ''}"}
  msg+=errs.map{|e|"⚠ #{e}"}
  UI.messagebox("Döşeme otomatik güncellemesi:\n"+msg.join("\n")) unless msg.empty?
 end
 res
end

# 🔄 Seçili döşemeyi güncelle (elle): PD silindi / taşındı vb. — önizleme + tek Geri Al
def deck_refresh_selected
 model=Sketchup.active_model
 decks=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
 if decks.empty?
  UI.messagebox('Güncellenecek döşemeyi seçin.');return
 end
 txt=decks.map do |dk|
  data=mst_deck_input_data(dk);hbs=mst_deck_support_beams(dk,model)
  next "#{element_visible_id(dk)}: dayandığı BK'lar bulunamadı." if hbs.length<2
  ins=mst_deck_inputs(model,hbs,data);pl=mst_deck_plan(ins[2],ins[3],data['thickness_m'].to_f,ins[4])
  "#{mst_deck_plan_text(pl,element_visible_id(dk))}\nŞu anki beton: #{format('%.3f',dk.get_attribute(DICT,'concrete_volume_m3').to_f)} m³ → yeni: #{format('%.3f',pl['volume'])} m³#{dk.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail' ? "\nDonatı aynı değerlerle yeniden çizilecek." : ''}"
 end.join("\n\n")
 return unless UI.messagebox("#{txt[0,3400]}\n\nDöşeme(ler) bu planla yenilensin mi? (tek Geri Al)",MB_YESNO)==IDYES
 res=[];errs=[]
 model.start_operation('MST Döşeme Güncelle',true)
 begin
  decks.each{|dk|res << mst_deck_regenerate!(dk,model)}
  commit_with_dependencies(model)
 rescue => e
  model.abort_operation;errs << e.message
 end
 UI.messagebox((res.map{|r|"#{r['id']}: #{format('%.3f',r['old'][0])} → #{format('%.3f',r['new'][0])} m³ (RV-#{format('%02d',r['rev'])})"}+errs.map{|e|"⚠ #{e}"}).join("\n"))
end

# v0.34 deck builder kept for reference only (not called since DS1).
def create_deck_slab_legacy_v034(data)
 model=Sketchup.active_model
 hbs=model.selection.to_a.select{|e| (e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)) && e.get_attribute(DICT,'element_type')=='head_beam'}
 if hbs.length < 2
  UI.messagebox("Döşeme için en az iki Başlık Kirişi seçiniz."); return
 end
 th=data['thickness_m'].to_f
 conc=data['concrete_class'].to_s.strip; conc='C35/45' if conc.empty?
 deck_form_hex=data['formwork_color'].to_s.strip; deck_form_hex='#66A9E8' if deck_form_hex.empty?
 deck_conc_hex=data['concrete_color'].to_s.strip; deck_conc_hex='#D9D9D9' if deck_conc_hex.empty?
 deck_form_mat=material_for(model,"MAG Döşeme Kalıp #{deck_form_hex}",deck_form_hex); deck_conc_mat=nil
 seat=data['precast_seat_m'].to_f; seat=0.15 if seat<=0
 raise 'Döşeme kalınlığı sıfırdan büyük olmalıdır.' if th<=0

 centers=hbs.map{|g|g.bounds.center}; maxd=-1.0; ca=nil; cb=nil
 centers.combination(2){|a,b| d=Geom::Point3d.new(a.x,a.y,0).distance(Geom::Point3d.new(b.x,b.y,0)); if d>maxd;maxd=d;ca=a;cb=b;end}
 u=Geom::Vector3d.new(cb.x-ca.x,cb.y-ca.y,0); raise 'Seçili BK merkezleri çakışıyor.' if u.length<0.001; u.normalize!
 zz=Geom::Vector3d.new(0,0,1); v=zz.cross(u); v.normalize!
 proj=lambda{|pt,ax|pt.x*ax.x+pt.y*ax.y+pt.z*ax.z}
 info=hbs.map do |g|
  cs=(0..7).map{|i|g.bounds.corner(i)}
  {g:g,cu:proj.call(g.bounds.center,u),u0:cs.map{|q|proj.call(q,u)}.min,u1:cs.map{|q|proj.call(q,u)}.max,
   v0:cs.map{|q|proj.call(q,v)}.min,v1:cs.map{|q|proj.call(q,v)}.max,ztop:cs.map(&:z).max}
 end.sort_by{|x|x[:cu]}
 gross_u0=info.first[:u0]; gross_u1=info.last[:u1]
 gross_v0=info.map{|x|x[:v0]}.min; gross_v1=info.map{|x|x[:v1]}.max
 gross_len=(gross_u1-gross_u0)/1.m; gross_w=(gross_v1-gross_v0)/1.m
 raise 'Brüt döşeme ölçüleri oluşturulamadı.' if gross_len<=0 || gross_w<=0
 ztops=info.map{|x|x[:ztop]}; z0=ztops.max; zspread=(ztops.max-ztops.min)/1.m

 all=[]; collect_elements(model.entities,all)
 precasts=all.select{|e| ['flat_precast','channel_precast','crane_precast'].include?(e.get_attribute(DICT,'element_type'))}
 cuts=[]
 info.each_cons(2).with_index(1) do |(a,b),idx|
  clear0=a[:u1]; clear1=b[:u0]; next if clear1<=clear0
  lp=a[:g].persistent_id; rp=b[:g].persistent_id
  mates=precasts.select do |p|
   x=p.get_attribute(DICT,'support_left_pid',0).to_i; y=p.get_attribute(DICT,'support_right_pid',0).to_i
   (x==lp && y==rp)||(x==rp && y==lp)
  end
  if mates.empty?
   UI.messagebox("Aks aralığı #{idx}: Bu iki BK arasında tanımlı prekast bulunamadı. Döşeme oluşturulmadı."); return
  end
  # Kesici yüksekliği gerçek prekast yüksekliğidir. Kot aramıyoruz: kesici döşeme alt kotundan yukarı doğru çalışır.
  # Deck cut depth is governed by the PRECAST TOP LEVEL relative to the
  # deck/BK top, not by the total physical height of a U-channel.
  # A channel may extend below BK top while its wall top is flush with the
  # normal PD top. Using base_thickness+inner_depth here would therefore
  # over-cut the deck whenever a Kanal Prekastı exists in the span.
  deck_bottom_m=z0/1.m
  heights=mates.map do |p|
   top=p.get_attribute(DICT,'top_elevation_m',nil)
   effective = top.nil? ? nil : top.to_f-deck_bottom_m
   if effective.nil? || effective<=0
    h=p.get_attribute(DICT,'height_m',nil)
    h=p.get_attribute(DICT,'thickness_m',nil) if h.nil?
    if h.nil?
     bt=p.get_attribute(DICT,'base_thickness_m',nil); id=p.get_attribute(DICT,'inner_depth_m',nil)
     h=bt.to_f+id.to_f unless bt.nil? || id.nil?
    end
    h=(p.bounds.max.z-p.bounds.min.z)/1.m if h.nil? || h.to_f<=0
    effective=h.to_f
   end
   effective.to_f
  end
  ph=heights.max
  raise "Aks aralığı #{idx}: Prekast yüksekliği geçersiz." if ph<=0
  c0=[clear0-m(seat),gross_u0].max; c1=[clear1+m(seat),gross_u1].min
  # Kanal Prekastı iç boşlukları: döşeme, kanalın NET İÇ GENİŞLİĞİ boyunca
  # ve kanalın gerçek boyu kadar tamamen açık bırakılır. Dış duvarlar/tavan temasları korunur.
  channel_openings=mates.select{|p| p.get_attribute(DICT,'element_type')=='channel_precast'}.map do |p|
   cs=(0..7).map{|ii|p.bounds.corner(ii)}
   pu0=cs.map{|q|proj.call(q,u)}.min; pu1=cs.map{|q|proj.call(q,u)}.max
   pv0=cs.map{|q|proj.call(q,v)}.min; pv1=cs.map{|q|proj.call(q,v)}.max
   iw=p.get_attribute(DICT,'inner_width_m',0).to_f
   next nil if iw<=0
   vc=(pv0+pv1)*0.5
   {u0:[pu0,gross_u0].max,u1:[pu1,gross_u1].min,
    v0:[vc-m(iw/2.0),gross_v0].max,v1:[vc+m(iw/2.0),gross_v1].min,
    inner_width_m:iw}
  end.compact.select{|o|o[:u1]>o[:u0] && o[:v1]>o[:v0]}
  cuts << {index:idx,u0:c0,u1:c1,clear_m:(clear1-clear0)/1.m,cut_m:(c1-c0)/1.m,precast_height_m:ph,precast_count:mates.length,channel_openings:channel_openings}
 end
 raise 'BK aralıklarında prekast kesintisi oluşturulamadı.' if cuts.empty?
 cuts.sort_by!{|c|c[:u0]}

 model.start_operation('Döşeme - Tek Grup Geometri',true)
 did=data['deck_id'].to_s.strip; did='D-001' if did.empty?
 parent=model.active_entities.add_group; parent.name="Döşeme #{did}"
 width_i=gross_v1-gross_v0
 base_origin=lambda{|uu,zzm| Geom::Point3d.new(u.x*uu+v.x*gross_v0,u.y*uu+v.y*gross_v0,z0+m(zzm))}
 add_box=lambda do |name,uu0,uu1,zoff_m,height_m,vv0=gross_v0,vv1=gross_v1|
  # SketchUp add_face rejects zero/nearly-zero rectangles as duplicate points.
  # Use a modelling tolerance before creating any deck fragment.
  geom_tol = 0.5.mm
  li=uu1-uu0
  local_w=vv1-vv0
  next if li.to_f <= geom_tol || local_w.to_f <= geom_tol || m(height_m).to_f <= geom_tol
  # v0.34.10d: Deck geometry is written DIRECTLY into the main deck group.
  # No child groups are created for full/cut/shell fragments.  The parent is
  # therefore the only SketchUp Group representing the structural deck.
  zbase=z0+m(zoff_m)
  p0=Geom::Point3d.new(u.x*uu0+v.x*vv0,u.y*uu0+v.y*vv0,zbase)
  p1=Geom::Point3d.new(u.x*uu1+v.x*vv0,u.y*uu1+v.y*vv0,zbase)
  p2=Geom::Point3d.new(u.x*uu1+v.x*vv1,u.y*uu1+v.y*vv1,zbase)
  p3=Geom::Point3d.new(u.x*uu0+v.x*vv1,u.y*uu0+v.y*vv1,zbase)
  f=parent.entities.add_face(p0,p1,p2,p3)
  raise "#{name} yüzeyi oluşturulamadı." unless f
  f.reverse! if f.normal.z<0
  f.pushpull(m(height_m))
  f
 end

 # Brüt plaka - tüm parçalar doğrudan ana Döşeme grubunun entities koleksiyonuna yazılır.
 # Kesinti olmayan bölgeler tam kalınlıkta; kesinti bölgelerinde prekast yüksekliği kadar alt hacim yoktur.
 cursor=gross_u0
 cuts.each do |c|
  add_box.call("#{did}-DOLU-#{format('%02d',c[:index])}",cursor,c[:u0],0.0,th) if c[:u0]>cursor
  removed_h=[c[:precast_height_m],th].min
  remain_h=th-removed_h
  if remain_h>0.000001
   openings=c[:channel_openings]||[]
   if openings.empty?
    add_box.call("#{did}-UST-KABUK-#{format('%02d',c[:index])}",c[:u0],c[:u1],removed_h,remain_h)
   else
    # Kanal açıklığı sadece kanalın gerçek U-boyunda geçerlidir. U eksenini
    # kanal başlangıç/bitişlerinde böl; her dilimde net iç genişliği dışarıda bırak.
    ubreaks=[c[:u0],c[:u1]]
    openings.each{|o| ubreaks << [o[:u0],c[:u0]].max << [o[:u1],c[:u1]].min}
    # Merge coincident/nearly-coincident channel ends. Exact Array#uniq is
    # insufficient because projected SketchUp coordinates may differ by tiny
    # floating point amounts, producing zero-width faces.
    break_tol=0.5.mm
    raw_breaks=ubreaks.select{|x|x>=c[:u0]-break_tol && x<=c[:u1]+break_tol}.sort
    ubreaks=[]
    raw_breaks.each do |x|
     x=c[:u0] if (x-c[:u0]).abs<break_tol
     x=c[:u1] if (x-c[:u1]).abs<break_tol
     ubreaks << x if ubreaks.empty? || (x-ubreaks[-1]).abs>=break_tol
    end
    ubreaks.each_cons(2).with_index(1) do |(su0,su1),si|
     next if (su1-su0).to_f < break_tol
     mid=(su0+su1)*0.5
     active=openings.select{|o|mid>o[:u0] && mid<o[:u1]}.sort_by{|o|o[:v0]}
     vcursor=gross_v0
     active.each_with_index do |o,oi|
      add_box.call("#{did}-UST-KABUK-#{format('%02d',c[:index])}-#{si}-#{oi}A",su0,su1,removed_h,remain_h,vcursor,o[:v0]) if (o[:v0]-vcursor).to_f>=break_tol
      vcursor=[vcursor,o[:v1]].max
     end
     add_box.call("#{did}-UST-KABUK-#{format('%02d',c[:index])}-#{si}-Z",su0,su1,removed_h,remain_h,vcursor,gross_v1) if (gross_v1-vcursor).to_f>=break_tol
    end
   end
  end
  cursor=[cursor,c[:u1]].max
 end
 add_box.call("#{did}-DOLU-SON",cursor,gross_u1,0.0,th) if gross_u1>cursor

 gross_area=gross_len*gross_w; gross_vol=gross_area*th
 cut_vol=cuts.sum{|c| c[:cut_m]*gross_w*[c[:precast_height_m],th].min}
 cut_plan_area=cuts.sum{|c| c[:cut_m]*gross_w}
 # Kanal iç açıklığı, mevcut prekast alt-kesintisinin ÜSTÜNDE kalan döşeme
 # kabuğunu da kaldırır. Böylece kanal yukarıdan gerçekten açık olur.
 channel_opening_vol=cuts.sum do |c|
  remain_h=[th-[c[:precast_height_m],th].min,0.0].max
  (c[:channel_openings]||[]).sum{|o| ((o[:u1]-o[:u0])/1.m)*((o[:v1]-o[:v0])/1.m)*remain_h}
 end
 net_vol=[gross_vol-cut_vol-channel_opening_vol,0.0].max
 # Kalıp: alt/üst yok; prekast/BK temasındaki enine yüzler yok. Yalnız açık iki dış boyuna kenar.
 remaining_full_u=gross_len-cuts.sum{|c|c[:cut_m]}
 cap_u=cuts.sum{|c| c[:precast_height_m] < th ? c[:cut_m] : 0.0}
 side_vertical_height = remaining_full_u*th + cuts.sum{|c| c[:cut_m]*[th-c[:precast_height_m],0.0].max}
 # Free longitudinal sides + the two OUTER end faces beyond first/last HB.
 # Internal transverse faces at precast cut boundaries remain excluded.
 fw_long=2.0*side_vertical_height
 fw_ends=2.0*gross_w*th
 fw=fw_long+fw_ends
 clean_deck_top_coplanar_edges(parent)
 paint_deck_formwork(parent,deck_form_mat,deck_conc_mat,u,gross_u0,gross_u1)

 parent.set_attribute(DICT,'element_type','deck_slab'); parent.set_attribute(DICT,'deck_id',did)
 parent.set_attribute(DICT,'geometry_structure','single_group_direct_faces_hidden_top_seams_formwork_v03410h')
 # BIM relationship metadata is written at creation time. This is metadata-only;
 # physical deck/cut geometry remains unchanged.
 support_pids=hbs.map{|b|b.persistent_id}
 support_uids=hbs.map{|b|ensure_uid(b)}
 parent.set_attribute(DICT,'support_pids',support_pids.join(','))
 parent.set_attribute(DICT,'support_uids',support_uids.join(','))
 parent.set_attribute(DICT,'support_count',hbs.length); parent.set_attribute(DICT,'cut_count',cuts.length)
 parent.set_attribute(DICT,'thickness_m',th); parent.set_attribute(DICT,'bottom_elevation_m',z0/1.m); parent.set_attribute(DICT,'top_elevation_m',z0/1.m+th)
 parent.set_attribute(DICT,'concrete_class',conc); parent.set_attribute(DICT,'gross_area_m2',gross_area); parent.set_attribute(DICT,'precast_cut_area_m2',cut_plan_area)
 parent.set_attribute(DICT,'gross_concrete_volume_m3',gross_vol); parent.set_attribute(DICT,'precast_cut_volume_m3',cut_vol); parent.set_attribute(DICT,'channel_opening_volume_m3',channel_opening_vol); parent.set_attribute(DICT,'concrete_volume_m3',net_vol)
 parent.set_attribute(DICT,'channel_opening_count',cuts.sum{|c|(c[:channel_openings]||[]).length})
 parent.set_attribute(DICT,'gross_length_m',gross_len); parent.set_attribute(DICT,'width_m',gross_w); parent.set_attribute(DICT,'precast_seat_m',seat)
 parent.set_attribute(DICT,'formwork_area_m2',fw); parent.set_attribute(DICT,'formwork_long_sides_m2',fw_long); parent.set_attribute(DICT,'formwork_end_faces_m2',fw_ends); parent.set_attribute(DICT,'formwork_color',deck_form_hex); parent.set_attribute(DICT,'concrete_color',deck_conc_hex); parent.set_attribute(DICT,'formwork_rule','free_longitudinal_vertical_edges_plus_two_outer_end_faces; internal_precast_and_headbeam_contacts_excluded')
 parent.set_attribute(DICT,'precast_cut_heights_m',cuts.map{|c|format('%.3f',c[:precast_height_m])}.join(','))
 curbs=create_deck_curbs(model,data,did,u,v,zz,gross_u0,gross_u1,gross_v0,gross_v1,z0+m(th))
 parent.set_attribute(DICT,'curb_count',curbs.length)
 # Topping is a separate QTO layer; it does not alter structural deck geometry.
 topping_on=data['topping_enabled'].to_s=='1'
 topping_th=data['topping_thickness_m'].to_f; topping_th=0.10 if topping_th<=0
 channel_open_area=cuts.sum{|c|(c[:channel_openings]||[]).sum{|o|((o[:u1]-o[:u0])/1.m)*((o[:v1]-o[:v0])/1.m)}}
 deck_top_area=[gross_area-channel_open_area,0.0].max
 curb_footprint=curbs.sum{|c|c.get_attribute(DICT,'length_m',0).to_f*c.get_attribute(DICT,'width_m',0).to_f}
 topping_area=topping_on ? [deck_top_area-curb_footprint,0.0].max : 0.0
 parent.set_attribute(DICT,'topping_enabled',topping_on ? '1':'0'); parent.set_attribute(DICT,'topping_thickness_m',topping_th)
 parent.set_attribute(DICT,'topping_concrete_class',data['topping_concrete_class'].to_s); parent.set_attribute(DICT,'topping_area_m2',topping_area); parent.set_attribute(DICT,'topping_volume_m3',topping_area*topping_th)
 finalize_bim_identity(parent,model)
 commit_with_dependencies(model); model.selection.clear; model.selection.add(parent); model.active_view.zoom(parent)
 warn_txt=zspread>0.005 ? "\nUYARI: BK üst kotları arasında #{format('%.3f',zspread)} m fark var; en yüksek kot kullanıldı." : ''
 UI.messagebox("Döşeme oluşturuldu.\nBrüt Plaka: #{format('%.2f',gross_len)} x #{format('%.2f',gross_w)} x #{format('%.2f',th)} m\nFiziksel Prekast Kesintisi: #{cuts.length} aralık\nKanal İç Açıklığı: #{cuts.sum{|c|(c[:channel_openings]||[]).length}} adet\nKesici Yükseklikleri: #{cuts.map{|c|format('%.2f',c[:precast_height_m])}.join(' / ')} m\nBrüt Beton: #{format('%.3f',gross_vol)} m³\nPrekast Hacim Kesintisi: -#{format('%.3f',cut_vol)} m³\nKanal Açıklık Kesintisi: -#{format('%.3f',channel_opening_vol)} m³\nNet Beton: #{format('%.3f',net_vol)} m³\nNet Yan Kalıp: #{format('%.2f',fw)} m²\nBordür / Tretuvar: #{curbs.length} taraf#{warn_txt}")
rescue=>e
 model.abort_operation rescue nil; UI.messagebox("Döşeme oluşturma hatası: #{e.message}")
end


# v0.34.10g - Topping / sidewalk coordination helpers.
def point_in_plan_polygon?(pt, poly)
 return false if poly.nil? || poly.length < 3
 x=pt.x.to_f; y=pt.y.to_f; inside=false; j=poly.length-1
 (0...poly.length).each do |i|
  xi=poly[i].x.to_f; yi=poly[i].y.to_f; xj=poly[j].x.to_f; yj=poly[j].y.to_f
  hit=((yi>y)!=(yj>y)) && (x < (xj-xi)*(y-yi)/((yj-yi).abs<1.0e-12 ? 1.0e-12 : (yj-yi))+xi)
  inside=!inside if hit
  j=i
 end
 inside
end

def deck_curb_footprints(deck_id, top_z)
 tol=2.mm.to_f
 out=[]
 mst_all_elements.each do |e|
  next unless e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='curb'
  next unless e.get_attribute(DICT,'parent_deck_id','').to_s==deck_id.to_s
  tr=e.transformation
  ents=e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
  f=ents.grep(Sketchup::Face).select do |fc|
   n=fc.normal.transform(tr); pts=fc.outer_loop.vertices.map{|v|v.position.transform(tr)}
   avg=pts.sum{|q|q.z}/pts.length.to_f
   n.z.abs>0.90 && (avg-top_z).abs<=tol
  end.first
  next unless f
  out << f.outer_loop.vertices.map{|v|v.position.transform(tr)}
 end
 out
end

# v0.31.8 - Add physical topping to an existing MST deck without rebuilding deck geometry.
def create_existing_deck_topping(data)
 model=Sketchup.active_model
 deck=model.selection.to_a.find{|e| e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
 unless deck
  UI.messagebox('Önce mevcut MST döşeme ana grubunu seçin.')
  return
 end
 th=data['topping_thickness_m'].to_f
 th=0.10 if th<=0
 cc=data['topping_concrete_class'].to_s.strip; cc='C35/45' if cc.empty?
 did=deck.get_attribute(DICT,'deck_id','D-001').to_s
 top_m=deck.get_attribute(DICT,'top_elevation_m',nil)
 unless top_m
  UI.messagebox('Seçilen döşemede üst kot metadata bilgisi bulunamadı.')
  return
 end
 top_z=m(top_m.to_f)
 tol=1.0.mm
 # Prevent accidental duplicate physical topping.
 # v0.51.5 K07: kaplama collect_elements'e girmez; ayrı toplayıcı (önceden kontrol hiç eşleşmiyordu)
 old=mst_collect_toppings(model.entities).find{|e| e.get_attribute(DICT,'parent_deck_id','').to_s==did}
 if old && old.valid?
  UI.messagebox("#{did} için fiziksel kaplama zaten mevcut. Önce mevcut kaplamayı silin veya düzenleyin.")
  return
 end
 faces=[]
 walk=nil
 walk=lambda do |ents,tr|
  ents.each do |e|
   if e.is_a?(Sketchup::Face)
    n=e.normal.transform(tr)
    pts=e.outer_loop.vertices.map{|v|v.position.transform(tr)}
    next if pts.length<3 || n.z<0.90
    avg=pts.sum{|q|q.z}/pts.length.to_f
    faces << pts if (avg-top_z).abs<=tol
   elsif e.is_a?(Sketchup::Group)
    walk.call(e.entities,tr*e.transformation)
   elsif e.is_a?(Sketchup::ComponentInstance)
    walk.call(e.definition.entities,tr*e.transformation)
   end
  end
 end
 walk.call(deck.entities,deck.transformation)
 # DS1: the topping covers the deck's real top surface (deck top + PD/KN tops, joints), not the
 # deck faces alone; channel openings, PD gaps and curbs are already left out of these rectangles.
 pj=(JSON.parse(deck.get_attribute(DICT,'deck_plan_json','').to_s) rescue nil)
 if pj.is_a?(Hash) && pj['surface_rects'].is_a?(Array) && !pj['surface_rects'].empty? && deck.get_attribute(DICT,'deck_u_axis',nil)
  ux,uy=JSON.parse(deck.get_attribute(DICT,'deck_u_axis').to_s);vx=-uy;vy=ux
  faces=pj['surface_rects'].map{|u0,u1,v0,v1|[[u0,v0],[u1,v0],[u1,v1],[u0,v1]].map{|a,b|Geom::Point3d.new((a*ux+b*vx).m,(a*uy+b*vy).m,top_z)}}
 end
 if faces.empty?
  UI.messagebox('Döşemenin üst yüzey geometrisi okunamadı. Kaplama oluşturulmadı.')
  return
 end
 model.start_operation('Mevcut Döşemeye Kaplama',true)
 g=model.entities.add_group; g.name="Kaplama #{did}"
 mat=material_for(model,"MAG Kaplama Betonu #{cc}",'#C9C9C9')
 # Recreate the structural deck top first.  Existing deck-top fragments are allowed,
 # but coincident internal seams are hidden later.  Sidewalk footprints are then drawn
 # on the SAME plane before extrusion so topping is never created below a sidewalk.
 faces.each{|pts| g.entities.add_face(pts)}
 curb_polys=deck_curb_footprints(did,top_z)
 curb_polys.each do |poly|
  flat=poly.map{|q|Geom::Point3d.new(q.x,q.y,top_z)}
  flat.each_with_index do |a,i|
   b=flat[(i+1)%flat.length]
   g.entities.add_line(a,b) unless a.distance(b)<0.1.mm
  end
 end
 # Classify the resulting planar regions with a point guaranteed to lie on the face
 # (the average of outer-loop vertices is reliable for these rectangular deck/sidewalk
 # regions and avoids Bounds#center falling into a neighbouring L-shaped zone).
 base_faces=g.entities.grep(Sketchup::Face).select{|f| f.normal.z.abs>0.90 && (f.vertices.first.position.z-top_z).abs<=2.mm.to_f}
 keep=[]
 base_faces.each do |f|
  pts=f.outer_loop.vertices.map{|vv|vv.position}
  c=Geom::Point3d.new(pts.sum{|q|q.x}/pts.length.to_f,pts.sum{|q|q.y}/pts.length.to_f,top_z)
  if curb_polys.any?{|poly|point_in_plan_polygon?(c,poly)}
   g.entities.erase_entities(f) if f.valid?
  else
   keep << f
  end
 end
 area=0.0; made=0
 keep.each do |f|
  next unless f.valid?
  f.reverse! if f.normal.z<0
  area += f.area/(1.m*1.m)
  f.material=mat; f.back_material=mat
  f.pushpull(m(th))
  made+=1
 end
 raise 'Kaplama yüzeyi oluşturulamadı.' if made==0
 g.entities.grep(Sketchup::Face).each{|f| f.material=mat if f.material.nil?; f.back_material=mat if f.back_material.nil?}
 vol=area*th
 g.set_attribute(DICT,'excluded_curb_count',curb_polys.length)
 g.set_attribute(DICT,'topping_rule',curb_polys.empty? ? 'FULL_DECK_TOP' : 'DECK_TOP_MINUS_CURB_TRETUVAR')
 g.set_attribute(DICT,'element_type','deck_topping')
 g.set_attribute(DICT,'topping_id',"TOP-#{did}")
 g.set_attribute(DICT,'parent_deck_id',did)
 g.set_attribute(DICT,'parent_uid',ensure_uid(deck))
 g.set_attribute(DICT,'parent_deck_revision_no',deck.get_attribute(DICT,'deck_revision_no',0).to_i)   # v0.51.5 K53 (yeni anahtar, Integer)
 g.set_attribute(DICT,'thickness_m',th)
 g.set_attribute(DICT,'concrete_class',cc)
 g.set_attribute(DICT,'concrete_volume_m3',vol)
 g.set_attribute(DICT,'plan_area_m2',area)
 %w[project_name ano_id axis_id axis_span].each{|k| g.set_attribute(DICT,k,deck.get_attribute(DICT,k,''))}
 ensure_uid(g)
 kids=deck.get_attribute(DICT,'dependency_child_uids','').to_s.split(',').map(&:strip).reject(&:empty?)
 kids << ensure_uid(g); deck.set_attribute(DICT,'dependency_child_uids',kids.uniq.join(','))
 deck.set_attribute(DICT,'topping_enabled','1')
 deck.set_attribute(DICT,'topping_thickness_m',th)
 deck.set_attribute(DICT,'topping_concrete_class',cc)
 deck.set_attribute(DICT,'topping_area_m2',area)
 deck.set_attribute(DICT,'topping_volume_m3',vol)
 mst_assign_tag(g,model)
 model.commit_operation
 model.selection.clear; model.selection.add(g); model.active_view.zoom(g)
 UI.messagebox("Mevcut döşemeye kaplama oluşturuldu.\nDöşeme: #{did}\nAlan: #{format('%.2f',area)} m²\nKalınlık: #{format('%.3f',th)} m\nBeton: #{format('%.3f',vol)} m³\nSınıf: #{cc}\nTretuvar Kesintisi: #{curb_polys.length} alan")
rescue=>e
 model.abort_operation rescue nil
 UI.messagebox("Kaplama oluşturma hatası: #{e.message}")
end

def registered_entity_faces(entity)
 ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
 ents.grep(Sketchup::Face)
end

def entity_volume_m3(entity)
 v = entity.respond_to?(:volume) ? entity.volume.to_f : 0.0
 v / (1.m * 1.m * 1.m)
rescue
 0.0
end

def entity_face_area_m2(entity, face)
 tr = entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
 face.area(tr).to_f / (1.m * 1.m)
rescue
 face.area.to_f / (1.m * 1.m)
end

def registered_geometry_dimensions(entity)
 # Ölçüler entity'nin kendi lokal geometrisinden okunur; modelde döndürülmüş olması sonucu bozmaz.
 bb = entity.is_a?(Sketchup::Group) ? entity.entities.bounds : entity.definition.bounds
 tr = entity.transformation
 sx = Geom::Vector3d.new(tr.xaxis.x,tr.xaxis.y,tr.xaxis.z).length
 sy = Geom::Vector3d.new(tr.yaxis.x,tr.yaxis.y,tr.yaxis.z).length
 sz = Geom::Vector3d.new(tr.zaxis.x,tr.zaxis.y,tr.zaxis.z).length
 dims = [bb.width.to_f*sx/1.m, bb.height.to_f*sy/1.m, bb.depth.to_f*sz/1.m]
 sorted=dims.sort
 {raw:dims, min:sorted[0], mid:sorted[1], max:sorted[2]}
rescue
 b=entity.bounds; dims=[b.width.to_f/1.m,b.height.to_f/1.m,b.depth.to_f/1.m]; sorted=dims.sort
 {raw:dims,min:sorted[0],mid:sorted[1],max:sorted[2]}
end

def auto_registered_formwork(entity, type)
 faces=registered_entity_faces(entity)
 tr=entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
 sum=0.0
 faces.each do |f|
  n=f.normal.transform(tr); n.normalize! if n.length>0
  # Döşeme: yalnız düşey yan yüzler. BK/PD/Kanal: üst yüz hariç gerçek dış yüzler.
  include_face = type=='deck_slab' ? (n.z.abs < 0.25) : (n.z < 0.75)
  sum += entity_face_area_m2(entity,f) if include_face
 end
 sum
rescue
 0.0
end

def next_registered_id(prefix)
 all=[];collect_elements(Sketchup.active_model.entities,all)
 "#{prefix}-EXT-#{format('%03d',all.length+1)}"
end

def concrete_class_options
 'C20/25|C25/30|C30/37|C32/40|C35/45|C40/50|C45/55|C50/60|C55/67|C60/75|ÖZEL'
end

def steel_grade_options
 'S235JR|S275JR|S355JR|S355J0|S355J2|S355J2H|S420MH|S460MH|ÖZEL'
end

def register_selected_element
 model=Sketchup.active_model
 sel=model.selection.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
 if sel.length!=1
  UI.messagebox('Tanıtmak için tek bir Group veya Component seçin.'); return
 end
 e=sel.first
 types='Başlık Kirişi|Normal Prekast (PD)|Kanal Prekastı|Döşeme|Çelik Boru Kazık'
 # 1. adım: eleman tipi. Geometrik ölçüler kullanıcıdan istenmez.
 t=UI.inputbox(['Eleman Tipi'],['Başlık Kirişi'],[types],'Mevcut Elemanı Tanıt — Eleman Tipi'); return unless t
 type_map={'Başlık Kirişi'=>'head_beam','Normal Prekast (PD)'=>'flat_precast','Kanal Prekastı'=>'channel_precast','Döşeme'=>'deck_slab','Çelik Boru Kazık'=>'steel_pipe_pile'}
 type=type_map[t[0]]
 prefix={'head_beam'=>'BK','flat_precast'=>'PD','channel_precast'=>'KP','crane_precast'=>'VP','deck_slab'=>'D','steel_pipe_pile'=>'P'}[type]
 material_list = type=='steel_pipe_pile' ? steel_grade_options : concrete_class_options
 default_mat = type=='steel_pipe_pile' ? 'S355J2H' : 'C40/50'
 r=UI.inputbox(['ID / Tip','Malzeme Sınıfı','Aks / Bölge'],[next_registered_id(prefix),default_mat,''],['',material_list,''],'Mevcut Elemanı Tanıt — Kimlik Bilgileri'); return unless r
 id=r[0].to_s.strip; mat=r[1].to_s.strip; axis=r[2].to_s.strip
 if mat=='ÖZEL'
  x=UI.inputbox(['Özel Malzeme / Beton Sınıfı'],[''],nil,'Özel Sınıf'); return unless x
  mat=x[0].to_s.strip
 end
 dims=registered_geometry_dimensions(e); vol=entity_volume_m3(e)
 if vol<=0
  UI.messagebox('Seçili eleman kapalı bir Solid değil. Güvenilir otomatik beton/çelik hacmi ve kalıp için önce Solid Group/Component haline getirin.'); return
 end
 fw=auto_registered_formwork(e,type)
 model.start_operation('MST Eleman Tanıt',true)
 e.set_attribute(DICT,'element_type',type);e.set_attribute(DICT,'registered_external',true);e.set_attribute(DICT,'registration_source','existing_model_geometry_auto')
 e.set_attribute(DICT,'axis',axis) unless axis.empty?
 e.set_attribute(DICT,'geometry_dim_1_m',dims[:raw][0]);e.set_attribute(DICT,'geometry_dim_2_m',dims[:raw][1]);e.set_attribute(DICT,'geometry_dim_3_m',dims[:raw][2])
 case type
 when 'head_beam'
  e.set_attribute(DICT,'head_beam_id',id);e.set_attribute(DICT,'beam_type',id);e.set_attribute(DICT,'concrete_class',mat)
  e.set_attribute(DICT,'length_m',dims[:max]);e.set_attribute(DICT,'width_m',dims[:mid]);e.set_attribute(DICT,'height_m',dims[:min])
  e.set_attribute(DICT,'concrete_volume_m3',vol);e.set_attribute(DICT,'formwork_area_m2',fw);e.set_attribute(DICT,'formwork_gross_area_m2',fw);e.set_attribute(DICT,'formwork_net_area_m2',fw);e.set_attribute(DICT,'pile_opening_area_m2',0.0)
 when 'flat_precast'
  e.set_attribute(DICT,'precast_id',id);e.set_attribute(DICT,'precast_type',id);e.set_attribute(DICT,'concrete_class',mat)
  e.set_attribute(DICT,'length_m',dims[:max]);e.set_attribute(DICT,'width_m',dims[:mid]);e.set_attribute(DICT,'height_m',dims[:min]);e.set_attribute(DICT,'concrete_volume_m3',vol);e.set_attribute(DICT,'formwork_area_m2',fw)
 when 'channel_precast'
  e.set_attribute(DICT,'precast_id',id);e.set_attribute(DICT,'precast_type','KANAL_PREKASTI_U');e.set_attribute(DICT,'concrete_class',mat)
  e.set_attribute(DICT,'length_m',dims[:max]);e.set_attribute(DICT,'width_m',dims[:mid]);e.set_attribute(DICT,'height_m',dims[:min]);e.set_attribute(DICT,'concrete_volume_m3',vol);e.set_attribute(DICT,'formwork_area_m2',fw)
 when 'deck_slab'
  e.set_attribute(DICT,'deck_id',id);e.set_attribute(DICT,'concrete_class',mat);e.set_attribute(DICT,'thickness_m',dims[:min])
  e.set_attribute(DICT,'length_m',dims[:max]);e.set_attribute(DICT,'width_m',dims[:mid]);e.set_attribute(DICT,'net_area_m2',vol/dims[:min]) if dims[:min]>0
  e.set_attribute(DICT,'concrete_volume_m3',vol);e.set_attribute(DICT,'formwork_area_m2',fw)
 when 'steel_pipe_pile'
  l=dims[:max]; d=(dims[:min]+dims[:mid])/2.0; steel_area=vol/l; inner_sq=d*d-4.0*steel_area/Math::PI
  di=inner_sq>0 ? Math.sqrt(inner_sq) : 0.0; tt=(d-di)/2.0; dmm=d*1000.0; tmm=tt*1000.0
  kgpm=0.02466*(dmm-tmm)*tmm; w=kgpm*l
  e.set_attribute(DICT,'pile_id',id);e.set_attribute(DICT,'diameter_mm',dmm);e.set_attribute(DICT,'thickness_mm',tmm);e.set_attribute(DICT,'length_m',l);e.set_attribute(DICT,'steel_grade',mat);e.set_attribute(DICT,'weight_kg',w);e.set_attribute(DICT,'theoretical_weight_kg',w);e.set_attribute(DICT,'zone',axis.empty? ? 'NORMAL':axis)
 end
 e.name=id if e.respond_to?(:name=); commit_with_dependencies(model)
 msg="Eleman tanıtıldı.\nTip: #{t[0]}\nID: #{id}\nSınıf: #{mat}\nGeometriden: #{format('%.3f',dims[:max])} x #{format('%.3f',dims[:mid])} x #{format('%.3f',dims[:min])} m"
 msg += type=='steel_pipe_pile' ? "\nAğırlık: #{format('%.3f',e.get_attribute(DICT,'weight_kg',0)/1000.0)} t" : "\nBeton: #{format('%.3f',vol)} m³\nOtomatik Kalıp: #{format('%.2f',fw)} m²"
 UI.messagebox(msg); qto_summary(@d) if @d && @d.visible?
rescue=>ex
 model.abort_operation rescue nil; UI.messagebox("Eleman tanıtma hatası: #{ex.message}")
end

def unregister_selected_element
 model=Sketchup.active_model;e=model.selection.to_a.find{|x|x.respond_to?(:get_attribute)&&x.get_attribute(DICT,'element_type')}
 unless e;UI.messagebox('Tanımı kaldırmak için bir MST elemanı seçin.');return;end
 return unless UI.messagebox('Seçili elemanın MST tanımı kaldırılsın mı? Geometri silinmez.',MB_YESNO)==IDYES
 model.start_operation('MST Tanımını Kaldır',true)
 begin   # v0.51.5 K13: hata yolunda işlem açık kalmaz
  e.attribute_dictionaries.delete(DICT) if e.attribute_dictionaries && e.attribute_dictionaries[DICT]
  commit_with_dependencies(model)
 rescue => ex
  model.abort_operation;UI.messagebox("Tanım kaldırılamadı: #{ex.message}");return
 end
 UI.messagebox('MST tanımı kaldırıldı. Geometri korunmuştur.')
 qto_summary(@d) if @d && @d.visible?
end

def edit_registered_element
 model=Sketchup.active_model
 e=model.selection.to_a.find{|x|x.respond_to?(:get_attribute)&&x.get_attribute(DICT,'element_type')}
 unless e;UI.messagebox('Önce tanımlı bir MST elemanı seçin.');return;end
 type=e.get_attribute(DICT,'element_type').to_s
 id=e.get_attribute(DICT,'head_beam_id',e.get_attribute(DICT,'precast_id',e.get_attribute(DICT,'deck_id',e.get_attribute(DICT,'pile_id','')))).to_s
 mat=e.get_attribute(DICT,'concrete_class',e.get_attribute(DICT,'steel_grade','')).to_s
 axis=e.get_attribute(DICT,'axis',e.get_attribute(DICT,'zone','')).to_s
 material_list=type=='steel_pipe_pile' ? steel_grade_options : concrete_class_options
 # Mevcut özel sınıf listede yoksa dropdown'a ekle.
 material_list = mat+'|'+material_list unless mat.empty? || material_list.split('|').include?(mat)
 r=UI.inputbox(['ID / Tip','Malzeme Sınıfı','Aks / Bölge'],[id,mat,axis],['',material_list,''],'MST Eleman Bilgisi Düzenle');return unless r
 newmat=r[1].to_s.strip
 if newmat=='ÖZEL'
  x=UI.inputbox(['Özel Malzeme / Beton Sınıfı'],[mat],nil,'Özel Sınıf'); return unless x
  newmat=x[0].to_s.strip
 end
 # Geometrik metraj salt-okunurdur; düzenleme anında modelden tekrar hesaplanır.
 dims=registered_geometry_dimensions(e); vol=entity_volume_m3(e)
 fw=vol>0 ? auto_registered_formwork(e,type) : e.get_attribute(DICT,'formwork_area_m2',0).to_f
 model.start_operation('MST Eleman Bilgisi Düzenle',true)
 e.set_attribute(DICT,'axis',r[2].to_s);e.set_attribute(DICT,'zone',r[2].to_s) if type=='steel_pipe_pile'
 e.set_attribute(DICT,type=='steel_pipe_pile' ? 'steel_grade':'concrete_class',newmat)
 key={'head_beam'=>'head_beam_id','flat_precast'=>'precast_id','channel_precast'=>'precast_id','crane_precast'=>'precast_id','deck_slab'=>'deck_id','steel_pipe_pile'=>'pile_id'}[type]
 e.set_attribute(DICT,key,r[0].to_s) if key
 if vol>0 && type!='steel_pipe_pile'
  e.set_attribute(DICT,'concrete_volume_m3',vol);e.set_attribute(DICT,'formwork_area_m2',fw)
  e.set_attribute(DICT,'formwork_gross_area_m2',fw);e.set_attribute(DICT,'formwork_net_area_m2',fw) if type=='head_beam'
  e.set_attribute(DICT,'length_m',dims[:max]);e.set_attribute(DICT,'width_m',dims[:mid])
  e.set_attribute(DICT,type=='deck_slab' ? 'thickness_m':'height_m',dims[:min])
  e.set_attribute(DICT,'net_area_m2',vol/dims[:min]) if type=='deck_slab' && dims[:min]>0
 elsif vol>0 && type=='steel_pipe_pile'
  l=dims[:max]; d=(dims[:min]+dims[:mid])/2.0; steel_area=vol/l; inner_sq=d*d-4.0*steel_area/Math::PI; di=inner_sq>0 ? Math.sqrt(inner_sq) : 0.0; tt=(d-di)/2.0
  dmm=d*1000.0;tmm=tt*1000.0;kgpm=0.02466*(dmm-tmm)*tmm;w=kgpm*l
  e.set_attribute(DICT,'diameter_mm',dmm);e.set_attribute(DICT,'thickness_mm',tmm);e.set_attribute(DICT,'length_m',l);e.set_attribute(DICT,'weight_kg',w);e.set_attribute(DICT,'theoretical_weight_kg',w)
 end
 e.name=r[0].to_s if e.respond_to?(:name=);commit_with_dependencies(model)
 UI.messagebox("Metadata güncellendi.\nSınıf: #{newmat}\nGeometrik ölçü ve metraj modelden yeniden okundu.")
 qto_summary(@d) if @d && @d.visible?
rescue=>ex
 model.abort_operation rescue nil;UI.messagebox("Metadata düzenleme hatası: #{ex.message}")
end

# ===== v0.13.0 Engineering Intelligence Suite =====
def ensure_uid(entity)
 uid=entity.get_attribute(DICT,'element_uid','').to_s
 if uid.empty?
  uid="MST-#{entity.persistent_id}-#{Time.now.to_i}"
  entity.set_attribute(DICT,'element_uid',uid)
  entity.set_attribute(DICT,'uid_owner_pid',entity.persistent_id) if entity.get_attribute(DICT,'uid_owner_pid',nil).nil?   # ADR-0515 §1
 end
 uid
end

def element_visible_id(e)
 t=e.get_attribute(DICT,'element_type','').to_s
 keys={'steel_pipe_pile'=>'pile_id','head_beam'=>'head_beam_id','flat_precast'=>'precast_id','channel_precast'=>'precast_id','crane_precast'=>'precast_id','deck_slab'=>'deck_id','curb'=>'curb_id'}
 (e.get_attribute(DICT,keys[t]||'id','').to_s.strip.empty? ? "PID-#{e.persistent_id}" : e.get_attribute(DICT,keys[t]||'id','').to_s)
end

# v0.51.5 H3f: yalnız önizleme / listeleme gösterimi. Kaplama (deck_topping) "PID-n" yerine topping_id ile görünür.
# element_visible_id değişmez (eşleme, imza, iz ve kayıtlar onu kullanır).
def mst_display_id(e)
 if e.get_attribute(DICT,'element_type','').to_s=='deck_topping'
  tid=e.get_attribute(DICT,'topping_id','').to_s.strip
  return tid unless tid.empty?
 end
 element_visible_id(e)
end

def bim_type_prefix(t)
 {'steel_pipe_pile'=>'P','head_beam'=>'BK','flat_precast'=>'PD','channel_precast'=>'KP','crane_precast'=>'VP','deck_slab'=>'D','curb'=>'TR','pile_infill_concrete'=>'PB','crown_wall'=>'KR'}[t] || 'EL'
end

def bim_type_label(t)
 {'steel_pipe_pile'=>'Kazık','head_beam'=>'Başlık Kirişi','flat_precast'=>'Normal PD','channel_precast'=>'Kanal Prekastı','crane_precast'=>'Vinç Prekastı','deck_slab'=>'Döşeme','curb'=>'Bordür / Tretuvar','pile_infill_concrete'=>'Kazık İçi Beton','crown_wall'=>'Kronman'}[t] || t
end

def element_signature(e)
 t=e.get_attribute(DICT,'element_type','').to_s
 vals=case t
 when 'steel_pipe_pile' then [e.get_attribute(DICT,'diameter_mm',0).to_f.round(1),e.get_attribute(DICT,'thickness_mm',0).to_f.round(1),e.get_attribute(DICT,'length_m',0).to_f.round(3),e.get_attribute(DICT,'steel_grade','').to_s]
 when 'head_beam'
  v=[e.get_attribute(DICT,'length_m',0).to_f.round(3),e.get_attribute(DICT,'width_m',0).to_f.round(3),e.get_attribute(DICT,'height_m',0).to_f.round(3),e.get_attribute(DICT,'concrete_class','').to_s]
  # v0.38 KN1: channel pockets and lower teeth change the physical BK type
  %w[start end].each do |s|
   v << "#{s}-cep:"+%w[offset length depth].map{|k|e.get_attribute(DICT,"#{s}_seat_#{k}_m",0).to_f.round(3)}.join('/') if e.get_attribute(DICT,"#{s}_seat_enabled",'').to_s=='1'
   v << "#{s}-dis:"+%w[length depth slope].map{|k|e.get_attribute(DICT,"#{s}_tooth_#{k}_m",0).to_f.round(3)}.join('/') if e.get_attribute(DICT,"#{s}_tooth_enabled",'').to_s=='1'
  end
  v << JSON.generate(HeadBeamEditor.signature_data(e))
  v
 when 'flat_precast' then [e.get_attribute(DICT,'length_m',0).to_f.round(3),e.get_attribute(DICT,'width_m',0).to_f.round(3),e.get_attribute(DICT,'height_m',0).to_f.round(3),e.get_attribute(DICT,'concrete_class','').to_s]
 when 'channel_precast' then [e.get_attribute(DICT,'length_m',0).to_f.round(3),e.get_attribute(DICT,'inner_width_m',0).to_f.round(3),e.get_attribute(DICT,'inner_depth_m',0).to_f.round(3),e.get_attribute(DICT,'base_thickness_m',0).to_f.round(3),e.get_attribute(DICT,'wall_thickness_m',0).to_f.round(3),e.get_attribute(DICT,'concrete_class','').to_s]
 when 'crane_precast' then [e.get_attribute(DICT,'length_m',0).to_f.round(3),e.get_attribute(DICT,'width_m',0).to_f.round(3),e.get_attribute(DICT,'thickness_m',0).to_f.round(3),e.get_attribute(DICT,'extra_depth_m',0).to_f.round(3),e.get_attribute(DICT,'left_tooth_m',0).to_f.round(3),e.get_attribute(DICT,'right_tooth_m',0).to_f.round(3),e.get_attribute(DICT,'concrete_class','').to_s]
 when 'deck_slab' then [e.get_attribute(DICT,'length_m',0).to_f.round(3),e.get_attribute(DICT,'width_m',0).to_f.round(3),e.get_attribute(DICT,'thickness_m',0).to_f.round(3),e.get_attribute(DICT,'concrete_class','').to_s]
 when 'curb' then [e.get_attribute(DICT,'length_m',0).to_f.round(3),e.get_attribute(DICT,'width_m',0).to_f.round(3),e.get_attribute(DICT,'height_m',0).to_f.round(3),e.get_attribute(DICT,'concrete_class','').to_s]
 when 'crown_wall' then [e.get_attribute(DICT,'crown_type_a_json','').to_s,e.get_attribute(DICT,'crown_type_b_json','').to_s,e.get_attribute(DICT,'concrete_class','').to_s]
 when 'pile_infill_concrete' then [e.get_attribute(DICT,'internal_diameter_mm',0).to_f.round(1),e.get_attribute(DICT,'height_m',0).to_f.round(3),e.get_attribute(DICT,'concrete_class','').to_s]
 else [t]
 end
 "#{t}|#{vals.join('|')}"
end

def next_library_type_id(model,prefix)
 key="type_counter_#{prefix}"
 n=model.get_attribute(DICT,key,0).to_i+1
 model.set_attribute(DICT,key,n)
 "#{prefix}-T#{n.to_s.rjust(2,'0')}"
end

# v0.23.3 — BIM-Complete Creation
# Every newly created physical BIM element leaves its creator with a unique
# Element ID/UID and a stable Type ID derived from the canonical type signature.
# v0.23.4 — creation-time relationship / organization inheritance.
# Uses relationships already known by the creator; it does not invent geometry links.
def inherit_bim_relationships(entity, model=Sketchup.active_model)
 return entity unless entity && entity.respond_to?(:get_attribute)
 t=entity.get_attribute(DICT,'element_type','').to_s
 # v0.38 R9: only these types read other elements; others skip the model scan.
 return entity unless %w[flat_precast channel_precast crane_precast deck_slab curb].include?(t)
 all=[]; collect_elements(model.entities,all)
 beams=all.select{|x| x.respond_to?(:get_attribute) && x.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 case t
 when 'flat_precast','channel_precast','crane_precast'
  lp=entity.get_attribute(DICT,'support_left_pid',0).to_i
  rp=entity.get_attribute(DICT,'support_right_pid',0).to_i
  l=beams.find{|b| b.persistent_id==lp}; r=beams.find{|b| b.persistent_id==rp}
  if l && r
   # Supports are authoritative for a newly created PD/Kanal.
   project=l.get_attribute(DICT,'project','').to_s.strip
   project=r.get_attribute(DICT,'project','').to_s.strip if project.empty?
   ano=l.get_attribute(DICT,'ano','').to_s.strip
   ano=r.get_attribute(DICT,'ano','').to_s.strip if ano.empty?
   la=l.get_attribute(DICT,'axis','').to_s.strip
   ra=r.get_attribute(DICT,'axis','').to_s.strip
   entity.set_attribute(DICT,'project',project) unless project.empty?
   entity.set_attribute(DICT,'ano',ano) unless ano.empty?
   entity.set_attribute(DICT,'zone',ano) unless ano.empty?
   unless la.empty? || ra.empty?
    span="#{la} ↔ #{ra}"
    entity.set_attribute(DICT,'axis_span',span)
    entity.set_attribute(DICT,'axis',"#{la}↔#{ra}")
   end
   entity.set_attribute(DICT,'support_left_uid',ensure_uid(l))
   entity.set_attribute(DICT,'support_right_uid',ensure_uid(r))
   entity.set_attribute(DICT,'support_uids',[ensure_uid(l),ensure_uid(r)].join(','))
   entity.set_attribute(DICT,'support_pids',[lp,rp].join(','))
  end
 when 'deck_slab'
  pids=entity.get_attribute(DICT,'support_pids','').to_s.split(',').map(&:to_i).reject{|x|x==0}
  bs=beams.select{|b|pids.include?(b.persistent_id)}
  unless bs.empty?
   project=bs.map{|b|b.get_attribute(DICT,'project','').to_s.strip}.find{|v|!v.empty?}
   ano=bs.map{|b|b.get_attribute(DICT,'ano','').to_s.strip}.find{|v|!v.empty?}
   axs=bs.map{|b|b.get_attribute(DICT,'axis','').to_s.strip}.reject{|v|v.empty?}
   entity.set_attribute(DICT,'project',project) if project && !project.empty?
   entity.set_attribute(DICT,'ano',ano) if ano && !ano.empty?
   entity.set_attribute(DICT,'zone',ano) if ano && !ano.empty?
   unless axs.empty?
    entity.set_attribute(DICT,'axis',axs.join(','))
    entity.set_attribute(DICT,'axis_span',"#{axs.first} ↔ #{axs.last}")
   end
   entity.set_attribute(DICT,'support_uids',bs.map{|b|ensure_uid(b)}.join(','))
  end
 when 'curb'
  pu=entity.get_attribute(DICT,'parent_uid','').to_s.strip
  unless pu.empty?
   parent=all.find{|x|x.respond_to?(:get_attribute) && x.get_attribute(DICT,'element_uid','').to_s==pu}
   if parent
    %w[project ano zone axis axis_span].each do |k|
     v=parent.get_attribute(DICT,k,'').to_s
     entity.set_attribute(DICT,k,v) unless v.empty?
    end
   end
  end
 end
 entity
end

def finalize_bim_identity(entity, model=Sketchup.active_model)
 return entity unless entity && entity.respond_to?(:get_attribute)
 t=entity.get_attribute(DICT,'element_type','').to_s
 return entity if t.empty?
 ensure_uid(entity)
 entity.set_attribute(DICT,'uid_owner_pid',entity.persistent_id) if entity.get_attribute(DICT,'uid_owner_pid',nil).nil?   # ADR-0515 §1
 # Multi-ANO default organization: every newly finalized physical BIM element
 # inherits the current project/active ANO only when those fields are blank.
 prj=model.get_attribute(DICT,'project_name','').to_s
 ano=model.get_attribute(DICT,'active_ano','ANO-01').to_s
 entity.set_attribute(DICT,'project',prj) if entity.get_attribute(DICT,'project','').to_s.strip.empty? && !prj.empty?
 if entity.get_attribute(DICT,'ano','').to_s.strip.empty?
  entity.set_attribute(DICT,'ano',ano);entity.set_attribute(DICT,'zone',ano)
 end
 inherit_bim_relationships(entity,model)
 sig=t=='pile_infill_concrete' ? mst_pile_infill_signature(entity) : element_signature(entity)
 all=[]; collect_elements(model.entities,all)
 peers=all.select{|x| x!=entity && x.respond_to?(:get_attribute) && x.get_attribute(DICT,'element_type','').to_s==t}
 # Physical IDs must be unique even when the elements share one Type ID.
 key=mst_identity_id_key(t)
 if key
  current=entity.get_attribute(DICT,key,'').to_s.strip
  used={}
  peers.each do |x|
   xid=x.get_attribute(DICT,key,'').to_s.strip
   used[xid]=true unless xid.empty?
  end
  if current.empty? || used[current]
   current=mst_next_unique_physical_id(bim_type_prefix(t),used)
   entity.set_attribute(DICT,key,current)
  end
  entity.name=current if entity.respond_to?(:name=)
 end
 # Same canonical signature => same Type ID. New signature => new Type ID.
 mate=peers.find{|x| element_signature(x)==sig && !x.get_attribute(DICT,'type_id',x.get_attribute(DICT,'library_type_id','')).to_s.strip.empty?}
 tid=mate ? mate.get_attribute(DICT,'type_id',mate.get_attribute(DICT,'library_type_id','')).to_s : next_library_type_id(model,bim_type_prefix(t))
 entity.set_attribute(DICT,'type_signature',sig)
 entity.set_attribute(DICT,'library_type_id',tid)
 entity.set_attribute(DICT,'type_id',tid)
 entity.set_attribute(DICT,'project',model.get_attribute(DICT,'project_name','').to_s) if entity.get_attribute(DICT,'project','').to_s.empty?
 entity.set_attribute(DICT,'ano',model.get_attribute(DICT,'active_ano','').to_s) if entity.get_attribute(DICT,'ano','').to_s.empty?
 entity.set_attribute(DICT,'zone',entity.get_attribute(DICT,'ano','').to_s) if entity.get_attribute(DICT,'zone','').to_s.empty?
 entity.set_attribute(DICT,'schema_version','2.1')
 entity.set_attribute(DICT,'revision','v0.23.4')
 model.set_attribute(DICT,'bim_schema_version','2.1')
 model.set_attribute(DICT,'bim_complete_creation_revision','v0.23.4')
 mst_assign_tag(entity,model)
 mst_scan_cache_add(entity)
 entity
end

# R-2 / K04: saf — yazmaz; yalnız eksik anahtarlar için [[varlık,anahtar,değer]] döner (mevcut değer, revision ve boş yer tutucular yazılmaz)
def mst_standardize_changes(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all);ch=[]
 elems=all.select{|e|%w[steel_pipe_pile head_beam flat_precast channel_precast crane_precast deck_slab curb pile_infill_concrete crown_wall bored_pile].include?(e.get_attribute(DICT,'element_type','').to_s)}.sort_by(&:persistent_id)
 blank=lambda{|e,k|e.get_attribute(DICT,k,'').to_s.strip.empty?}
 # Preserve existing type IDs by signature (first owner by persistent_id); a new stable ID only for unseen signatures.
 registry={};sigs={};ctr={}
 elems.each do |e|
  sig=sigs[e]=element_signature(e);tid=e.get_attribute(DICT,'library_type_id','').to_s.strip;tid=e.get_attribute(DICT,'type_id','').to_s.strip if tid.empty?
  registry[sig]||=tid unless tid.empty?
 end
 elems.each do |e|
  t=e.get_attribute(DICT,'element_type','').to_s;sig=sigs[e]
  ch << [e,'element_uid',"MST-#{e.persistent_id}-#{Time.now.to_i}"] << [e,'uid_owner_pid',e.persistent_id] if blank.call(e,'element_uid')
  ch << [e,'type_signature',sig] if blank.call(e,'type_signature')
  lt=e.get_attribute(DICT,'library_type_id','').to_s.strip;ti=e.get_attribute(DICT,'type_id','').to_s.strip
  if lt.empty? && ti.empty?
   tid=registry[sig]
   if tid.to_s.empty?
    pf=bim_type_prefix(t);key="type_counter_#{pf}";ctr[key]=(ctr[key] || model.get_attribute(DICT,key,0).to_i)+1
    tid="#{pf}-T#{ctr[key].to_s.rjust(2,'0')}";registry[sig]=tid
   end
   ch << [e,'library_type_id',tid] << [e,'type_id',tid]
  elsif lt.empty?
   ch << [e,'library_type_id',ti]
  elsif ti.empty?
   ch << [e,'type_id',lt]
  end
  ch << [e,'schema_version','2.0'] if blank.call(e,'schema_version')
 end
 ctr.each{|k,v|ch << [model,k,v]}
 ch << [model,'bim_schema_version','2.0'] if model.get_attribute(DICT,'bim_schema_version','').to_s.strip.empty?
 ch << [model,'bim_core_revision','v0.20.0'] if model.get_attribute(DICT,'bim_core_revision','').to_s.strip.empty?
 ch
end

# R-2 / K04, K28: değişiklik yoksa işlem açmaz ve 0 döner; own_op=false → çağıranın işlemi içinde (start/commit yok)
def standardize_model_metadata(own_op=true)
 model=Sketchup.active_model;op=false
 ch=mst_standardize_changes(model)
 return 0 if ch.empty?
 if own_op
  model.start_operation('MST BIM Veri Çekirdeği Standartlaştır',true);op=true
 end
 ch.each{|e,k,v|e.set_attribute(DICT,k,v)}
 if own_op
  commit_with_dependencies(model);op=false
 end
 ch.map{|e,_,_|e}.uniq.count{|e|e!=model}
rescue=>ex
 model.abort_operation if op;raise ex
end

def element_library(changed=nil)
 all=[];collect_elements(Sketchup.active_model.entities,all)
 elems=all.select{|e|%w[steel_pipe_pile head_beam flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile].include?(e.get_attribute(DICT,'element_type').to_s)}
 groups=elems.group_by{|e|e.get_attribute(DICT,'library_type_id','').to_s}
 rows=String.new
 groups.sort_by{|tid,arr|tid}.each do |tid,arr|
  e=arr.first;t=e.get_attribute(DICT,'element_type','').to_s
  ids=arr.map{|x|element_visible_id(x)}.join(', ')
  sig=e.get_attribute(DICT,'type_signature',element_signature(e)).to_s
  mat=e.get_attribute(DICT,'steel_grade',e.get_attribute(DICT,'concrete_class','-')).to_s
  rows<<"<tr><td><b>#{html_escape(tid.empty? ? '(Tip ID yok)' : tid)}</b></td><td>#{html_escape(bim_type_label(t))}</td><td>#{html_escape(mat)}</td><td class='num'>#{arr.length}</td><td>#{html_escape(ids)}</td><td class='sig'>#{html_escape(sig)}</td></tr>"
 end
 rfq=rockfill_qto_data
 rfq[:materials].each_with_index do |r,i|
  rows<<"<tr><td><b>RF-T#{(i+1).to_s.rjust(2,'0')}</b></td><td>Dolgu / Taş</td><td>#{html_escape(r[:name])}</td><td class='num'>#{rfq[:sections].length}</td><td>Kesit zinciri</td><td class='sig'>rockfill|#{html_escape(r[:code])}|#{format('%.3f',r[:density])}t/m³ • #{format('%.3f',r[:volume_m3])}m³ • #{format('%.3f',r[:tonnage_t])}t</td></tr>"
 end
 library_type_count=groups.length + rfq[:materials].length
 html="<html><head><meta charset='utf-8'><style>body{font-family:Arial;background:#f3f7fa;color:#18364a;margin:0}.top{padding:18px 22px;background:#fff;border-bottom:1px solid #cadce7;display:flex;justify-content:space-between}.badge{background:#e6f4ff;color:#0874c9;border:1px solid #b9ddf5;border-radius:18px;padding:7px 12px;font-size:11px;font-weight:700}h2{margin:0;color:#073f73}.wrap{padding:18px}.kpis{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-bottom:14px}.kpi{background:#fff;border:1px solid #cadce7;border-radius:8px;padding:12px}.kpi small{color:#6b8799}.kpi b{display:block;font-size:20px;color:#074a7c;margin-top:4px}table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #cadce7}th,td{padding:9px;border-bottom:1px solid #e7eef3;text-align:left;font-size:12px}th{background:#eaf3f8;color:#42677f;position:sticky;top:0}.num{text-align:right}.sig{font-size:10px;color:#6d8798}.note{margin-top:10px;font-size:11px;color:#607d8b}</style></head><body><div class='top'><div><h2>BIM Eleman Kütüphanesi</h2><div>Fiziksel eleman ≠ eleman tipi • kalıcı UID + sabit Tip ID</div></div><div class='badge'>BIM VERİ ÇEKİRDEĞİ v#{VERSION}</div></div><div class='wrap'><div class='kpis'><div class='kpi'><small>Fiziksel Eleman</small><b>#{elems.length}</b></div><div class='kpi'><small>Eleman Tipi</small><b>#{library_type_count}</b></div><div class='kpi'><small>Standardize Edilen</small><b>#{changed.nil? ? '—' : changed}</b></div></div><table><tr><th>Tip ID</th><th>Eleman</th><th>Malzeme</th><th>Adet</th><th>Fiziksel ID'ler</th><th>Tip İmzası</th></tr>#{rows}</table><div class='note'>Tip ID artık pencere her açıldığında yeniden numaralanmaz. Aynı tip imzası aynı Tip ID'yi korur. Fiziksel element_uid değerleri revizyonlarda korunur.</div></div></body></html>"
 d=mst_html_dialog('element_library',dialog_title:"BIM Eleman Kütüphanesi v#{VERSION}",width:1180,height:680,resizable:true);d.set_html(EngineeringUI.decorate(html));d.show;@library_dialog=d
end

def bim_data_core_report
 changed=standardize_model_metadata
 # v0.51.5 K48: ileti, artık yalnız eksik alanları dolduran standardize davranışını anlatır (Project/Ano/Axis/Zone yazılmaz)
 UI.messagebox("BIM Veri Çekirdeği tamamlandı.\n\n#{changed} MST elemanında eksik kimlik alanı tamamlandı.\n• Eksikse kalıcı element_uid\n• Eksikse type_id / library_type_id ve tip imzası\n• Eksikse şema sürümü 2.0\n\nDolu alanlar değiştirilmez; proje / yapı / aks / bölge bilgisi bu işlemde yazılmaz.")
 element_library(changed)   # K28: kütüphane yazmaz; tek işlem standardize'da
end

def rebuild_pile_geometry(g,dmm,tmm,vertical_len,rx,ry)
 ents=g.entities;ents.clear!
 ro=mm(dmm)/2.0;ri=mm(dmm-2*tmm)/2.0;dz=-m(vertical_len);dx=m(vertical_len*rx);dy=m(vertical_len*ry)
 n=SEG;ot=[];ob=[];it=[];ib=[]
 n.times do |i|
  a=2.0*Math::PI*i/n;c=Math.cos(a);s=Math.sin(a)
  ot<<Geom::Point3d.new(ro*c,ro*s,0);ob<<Geom::Point3d.new(dx+ro*c,dy+ro*s,dz)
  it<<Geom::Point3d.new(ri*c,ri*s,0);ib<<Geom::Point3d.new(dx+ri*c,dy+ri*s,dz)
 end
 n.times do |i|;j=(i+1)%n;ents.add_face(ot[i],ot[j],ob[j],ob[i]);ents.add_face(it[j],it[i],ib[i],ib[j]);end
 # horizontal annular top/bottom caps, preserving project-elevation cuts
 ft=ents.add_face(ot);hit=ents.add_face(it);hit.erase! if hit&&hit.valid?
 fb=ents.add_face(ob.reverse);hib=ents.add_face(ib.reverse);hib.erase! if hib&&hib.valid?
end

# Alt04h: guarded physical accessory update and BIM/QTO transaction.
def mst_apply_pile_detail_changes(pile,changes)
 raise 'Geçersiz BIM kazığı' unless pile && pile.valid? && pile.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'
 changes.each{|key,value|pile.set_attribute(DICT,key,value) unless %w[upper_ring_thickness_mm lower_ring_thickness_mm].include?(key)}
 # Ring rule (PIPE mode default; MANUAL only via the ring thickness command).
 mst_enforce_ring_rule!(pile)
 return mst_pile_component_refresh!(pile) if mst_component_pile?(pile)   # v0.38 C3
 # All creation and editing routes use the same physical BIM representation.
 mst_visual_refresh_pile(pile,{})
 sync_pile_bim_qto(pile)
 issues=mst_visual_audit_pile(pile)
 raise "#{pile.get_attribute(DICT,'pile_id','?')}: #{issues.join('; ')}" unless issues.empty?
end

# Resolve the same BIM pile used by the legacy technical editor. A pile may be
# nested in a selected pile_layout, so a top-level selection-only lookup fails.
def mst_selected_bim_pile
 piles=selected_piles.map{|entry| entry.is_a?(Array) ? entry[0] : entry}.select{|g|
  g.valid? && g.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'
 }.uniq{|g|g.persistent_id}
 return piles.first if piles.length==1
 nil
end

def mst_selected_bim_pile_payload
 g=mst_selected_bim_pile
 raise 'SketchUp modelinde tek bir MST çelik boru kazık seçin.' unless g
 mst_bim_pile_payload(g)
end

# v0.38 R2: payload for any pile entity (also used to refresh the form after an update).
def mst_bim_pile_payload(g)
 keys=%w[pile_id system structure grid_x_axis grid_y_axis global_x_m global_y_m diameter_mm thickness_mm length_m actual_length_m top_elevation_m steel_grade orientation_mode batter_ratio azimuth_deg bottom_elevation_m seabed_elevation_m driving_length_m splice_mode splice_count_per_pile drilling_enabled drilling_length_m pe_enabled pe_length_m plug_enabled plug_count_per_pile plug_clearance_mm plug_thickness_mm lower_ring_enabled lower_ring_width_mm lower_ring_thickness_mm lower_ring_count_per_pile upper_ring_enabled upper_ring_width_mm upper_ring_thickness_mm upper_ring_count_per_pile elevation_mode elevation_reason linked_element_id special_top_elevation_m infill_enabled infill_concrete_class infill_bottom_elevation_m]
 h=keys.each_with_object({}){|k,h2|h2[k]=g.get_attribute(DICT,k,'')}
 h['persistent_id']=g.persistent_id.to_s
 h['ring_thickness_mode']=g.get_attribute(DICT,'ring_thickness_mode','PIPE').to_s
 h['element_uid']=g.get_attribute(DICT,'element_uid','').to_s
 h['entity_class']=g.is_a?(Sketchup::ComponentInstance) ? 'ComponentInstance' : 'Group'
 h['definition_instances']=g.is_a?(Sketchup::ComponentInstance) ? g.definition.instances.length : 1
 h
end

# v0.38: one atomic boundary for section-only instance / TYPE / inline TYPE edits.
# Caller validates scope and input before entering; any failure aborts the whole batch.
def mst_apply_pile_sections_atomic(piles, specs, label, sync_type=false)
  model=Sketchup.active_model
  raise 'Boş kazık seçimi.' if piles.empty?
  raise 'Tekrarlanan fiziksel kazık.' unless piles.map(&:persistent_id).uniq.length==piles.length
  piles.each do |pile|
    raise 'Geçersiz BIM kazığı.' unless pile.valid? && pile.get_attribute(DICT,'element_type','')=='steel_pipe_pile'
    d,t,grade=specs.fetch(pile)
    raise 'Geçersiz kesit.' unless d.to_f>0 && t.to_f>0 && 2*t.to_f<d.to_f && !grade.to_s.strip.empty?
  end
  model.start_operation(label,true)
  begin
    piles.each do |pile|
      d,t,grade=specs.fetch(pile)
      mst_rebuild_pile_section_dependencies(pile,d.to_f,t.to_f,grade.to_s)
      ensure_uid(pile)
    end
    mst_sync_pile_type_library(model) if sync_type
    commit_with_dependencies(model)
    model.active_view.invalidate
  rescue Exception
    model.abort_operation
    raise
  end
  true
end

# v0.38 Target Set + safe pile length service.
# Keeps pile head/transform fixed; length is the physical axis length.
def mst_rebuild_pile_length_dependencies(p, new_len)
  new_len=new_len.to_f
  raise 'Kazık boyu 0 m’den büyük olmalı.' unless new_len>0
  old_len=p.get_attribute(DICT,'length_m',0).to_f
  return true if (new_len-old_len).abs<1.0e-9
  top=p.get_attribute(DICT,'top_elevation_m',0).to_f
  mode=p.get_attribute(DICT,'orientation_mode','VERTICAL').to_s
  ratio=p.get_attribute(DICT,'batter_ratio',0).to_f
  az=p.get_attribute(DICT,'azimuth_deg',0).to_f
  pd={'orientation_mode'=>mode,'batter_ratio'=>ratio,'azimuth_deg'=>az}
  _,r,azn,down,vz=pile_orientation(pd)
  bottom=top-new_len*vz
  inf_bottom=p.get_attribute(DICT,'infill_bottom_elevation_m',nil)
  if p.get_attribute(DICT,'infill_enabled','0').to_s=='1' && !inf_bottom.nil? && inf_bottom.to_f < bottom-0.0001
    raise "#{p.get_attribute(DICT,'pile_id','?')}: iç beton alt kotu #{inf_bottom.to_f.round(3)} m, yeni kazık alt kotu #{bottom.round(3)} m'nin altında kalıyor."
  end
  seabed=p.get_attribute(DICT,'seabed_elevation_m',nil)
  driving=nil
  unless seabed.nil?
    driving=[seabed.to_f-bottom,0.0].max/vz
  end
  p.set_attribute(DICT,'length_m',new_len)
  p.set_attribute(DICT,'actual_length_m',new_len)
  p.set_attribute(DICT,'vertical_length_m',new_len*vz)
  p.set_attribute(DICT,'bottom_elevation_m',bottom)
  x=p.get_attribute(DICT,'axis_x_m',0).to_f; y=p.get_attribute(DICT,'axis_y_m',0).to_f
  p.set_attribute(DICT,'toe_x_m',x+new_len*down.x)
  p.set_attribute(DICT,'toe_y_m',y+new_len*down.y)
  p.set_attribute(DICT,'toe_z_m',bottom)
  p.set_attribute(DICT,'driving_length_m',driving) unless driving.nil?
  if p.get_attribute(DICT,'splice_mode','AUTO').to_s!='MANUAL'
    p.set_attribute(DICT,'splice_mode','AUTO')
    p.set_attribute(DICT,'splice_count_per_pile',[(new_len/12.0).ceil-1,0].max)
  end
  d=p.get_attribute(DICT,'diameter_mm',0).to_f; t=p.get_attribute(DICT,'thickness_mm',0).to_f
  grade=p.get_attribute(DICT,'steel_grade','S355J2H').to_s
  mst_rebuild_pile_section_dependencies(p,d,t,grade)
  true
end

def mst_parse_pile_id_expression(expr)
  out=[]
  expr.to_s.split(',').each do |part|
    x=part.strip
    next if x.empty?
    if x =~ /\A([^0-9]*)(\d+)\s*[-–—]\s*([^0-9]*)(\d+)\z/
      p1=$1; a=$2.to_i; p2=$3; b=$4.to_i; pref=p2.to_s.empty? ? p1 : p2
      raise "Kazık ID aralığı önekleri uyuşmuyor: #{x}" unless p1.to_s==pref.to_s
      width=[$2.length,$4.length].max
      lo,hi=[a,b].minmax
      (lo..hi).each{|n|out << "#{pref}#{n.to_s.rjust(width,'0')}"}
    else
      out << x
    end
  end
  out.uniq
end

# ---------------------------------------------------------------------------
# v0.38 R4 — Ring wall thickness mode.
#   PIPE   (default): upper/lower ring wall thickness follows the pipe wall.
#   MANUAL (explicit): a user-entered value is kept even if the pipe wall changes.
# Only the two menu commands below switch the mode; every other path obeys it.
# ---------------------------------------------------------------------------
def mst_ring_manual?(p)
  p.get_attribute(DICT,'ring_thickness_mode','PIPE').to_s=='MANUAL'
end

def mst_enforce_ring_rule!(p,t=nil)
  return if mst_ring_manual?(p)
  t=(t || p.get_attribute(DICT,'thickness_mm',0)).to_f
  p.set_attribute(DICT,'upper_ring_thickness_mm',t)
  p.set_attribute(DICT,'lower_ring_thickness_mm',t)
end

# Same formula as pile_fabrication_qto_row (upper_kg / lower_kg), for previews only.
def mst_ring_mass_kg(p,side,th_mm)
  return 0.0 unless p.get_attribute(DICT,"#{side}_ring_enabled",'0').to_s=='1'
  dd=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0
  th=th_mm.to_f/1000.0
  if side=='upper'
    w=p.get_attribute(DICT,'upper_ring_width_mm',250).to_f/1000.0
    n=[p.get_attribute(DICT,'upper_ring_count_per_pile',1).to_i,1].max
    Math::PI*(dd+th)*w*th*RHO*n
  else
    tt=p.get_attribute(DICT,'thickness_mm',0).to_f/1000.0;ddi=[dd-2.0*tt,0.0].max
    w=p.get_attribute(DICT,'lower_ring_width_mm',300).to_f/1000.0
    n=[p.get_attribute(DICT,'lower_ring_count_per_pile',1).to_i,1].max
    Math::PI*[ddi-th,0.0].max*w*th*RHO*n
  end
end

def mst_ring_stored(p,side)
  p.get_attribute(DICT,"#{side}_ring_thickness_mm",p.get_attribute(DICT,'thickness_mm',0)).to_f
end

def mst_ring_ids(piles,max=12)
  ids=piles.map{|p|p.get_attribute(DICT,'pile_id','?').to_s}
  ids.first(max).join(', ')+(ids.length>max ? " … (+#{ids.length-max})" : '')
end

# Plan + apply for both commands. new_values: ->(pile){[upper_mm, lower_mm]}
def mst_ring_apply_plan(piles,mode,title,new_values,extra_note='')
  model=Sketchup.active_model
  bad=[];before=0.0;after=0.0;changed=[]
  piles.each do |p|
    up,lo=new_values.call(p)
    d=p.get_attribute(DICT,'diameter_mm',0).to_f;t=p.get_attribute(DICT,'thickness_mm',0).to_f
    pid=p.get_attribute(DICT,'pile_id','?').to_s
    bad << "#{pid}: çember et kalınlığı 0'dan büyük olmalı." unless up>0 && lo>0
    bad << "#{pid}: alt/iç çember (et #{lo} mm) borunun içine sığmıyor (Ø#{d}/t#{t})." if p.get_attribute(DICT,'lower_ring_enabled','0').to_s=='1' && !(d-2*t-2*lo>0)
    b=mst_ring_mass_kg(p,'upper',mst_ring_stored(p,'upper'))+mst_ring_mass_kg(p,'lower',mst_ring_stored(p,'lower'))
    a=mst_ring_mass_kg(p,'upper',up)+mst_ring_mass_kg(p,'lower',lo)
    before+=b;after+=a
    mode_now=mst_ring_manual?(p) ? 'MANUAL' : 'PIPE'
    changed << p if mode_now!=mode || (mst_ring_stored(p,'upper')-up).abs>1.0e-9 || (mst_ring_stored(p,'lower')-lo).abs>1.0e-9
  end
  unless bad.empty?
    UI.messagebox("#{title}\n\nİşlem başlatılmadı:\n#{bad.first(15).join("\n")}#{bad.length>15 ? "\n…" : ''}")
    return 0
  end
  if changed.empty?
    UI.messagebox("#{title}\n\nDeğişecek kazık yok; tüm değerler zaten istenen durumda.")
    return 0
  end
  msg="#{title}\n\n#{changed.length} kazık: #{mst_ring_ids(changed)}\n\n"+
      format("Çember metrajı (bu kazıklar): %.2f kg → %.2f kg (%+.2f kg)\n",before,after,after-before)+
      "Mod: #{mode=='MANUAL' ? 'MANUEL (boru et kalınlığı değişse de korunur)' : 'BORU ET (boru et kalınlığını takip eder)'}"+
      "#{extra_note}\n\nTek Geri Al ile geri alınabilir. Devam edilsin mi?"
  return 0 unless UI.messagebox(msg,MB_YESNO)==IDYES
  model.start_operation("MST Çember Et Kalınlığı (#{changed.length} kazık)",true)
  begin
    changed.each do |p|
      up,lo=new_values.call(p)
      p.set_attribute(DICT,'ring_thickness_mode',mode)
      p.set_attribute(DICT,'upper_ring_thickness_mm',up)
      p.set_attribute(DICT,'lower_ring_thickness_mm',lo)
      # Rule-aware refresh: rings redrawn, QTO cache and visual audit updated.
      mst_apply_pile_detail_changes(p,{})
    end
    mst_sync_pile_type_library(model)
    commit_with_dependencies(model);model.active_view.invalidate
  rescue Exception => e
    model.abort_operation
    UI.messagebox("#{title}\n\nGüncelleme geri alındı: #{e.message}")
    return 0
  end
  changed.length
end

# Command 1: bring every pile (optionally also MANUAL ones) back to ring = pipe wall.
def mst_ring_rule_normalize_all
  piles=mst_all_bim_piles(Sketchup.active_model)
  manual=piles.select{|p|mst_ring_manual?(p)}
  off_rule=piles.reject{|p|mst_ring_manual?(p)}.select do |p|
    t=p.get_attribute(DICT,'thickness_mm',0).to_f
    %w[upper lower].any?{|s|(mst_ring_stored(p,s)-t).abs>1.0e-9}
  end
  include_manual=false
  unless manual.empty?
    r=UI.messagebox("#{manual.length} kazıkta MANUEL çember et kalınlığı var:\n#{mst_ring_ids(manual)}\n\nBunlar da boru et kalınlığına çekilsin mi?\n\nEvet: manuel değerler de kurala çekilir\nHayır: manuel kazıklar korunur",MB_YESNOCANCEL)
    return if r==IDCANCEL
    include_manual=(r==IDYES)
  end
  targets=off_rule+(include_manual ? manual : [])
  if targets.empty?
    UI.messagebox("Çember Et Kalınlığı — Kurala Çek\n\nTüm kazıklar kurala uygun (çember et = boru et).#{manual.empty? ? '' : "\n#{manual.length} MANUEL kazık korunuyor."}")
    return
  end
  n=mst_ring_apply_plan(targets,'PIPE','Çember Et Kalınlığı — Kurala Çek',
    ->(p){t=p.get_attribute(DICT,'thickness_mm',0).to_f;[t,t]})
  UI.messagebox("#{n} kazığın çember et kalınlığı boru et kalınlığına çekildi.") if n>0
end

# Command 2: explicit user value for the selected piles (MANUAL mode).
def mst_ring_set_manual_for_selection
  piles=selected_piles.map{|entry|entry.is_a?(Array) ? entry[0] : entry}.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}.uniq{|e|e.persistent_id}
  if piles.empty?
    UI.messagebox("Önce modelde bir veya daha fazla çelik boru kazık seçin.\n\nİpucu: Kazık yerleşim grubuna çift tıklayıp içine girin, sonra kazıkları seçin.")
    return
  end
  ref=piles.first
  fmt=->(v){x=v.to_f.round(2);x==x.to_i ? x.to_i.to_s : x.to_s}
  res=UI.inputbox(['Üst / Dış çember et kalınlığı (mm)','Alt / İç çember et kalınlığı (mm)'],
                  [fmt.call(mst_ring_stored(ref,'upper')),fmt.call(mst_ring_stored(ref,'lower'))],
                  "Özel Çember Et Kalınlığı — #{piles.length} kazık")
  return unless res
  up=(Float(res[0].to_s.strip.tr(',','.')) rescue nil)
  lo=(Float(res[1].to_s.strip.tr(',','.')) rescue nil)
  unless up && lo && up.finite? && lo.finite?
    UI.messagebox('Çember et kalınlıkları sayısal olmalı.')
    return
  end
  n=mst_ring_apply_plan(piles,'MANUAL','Özel Çember Et Kalınlığı',->(_p){[up,lo]},
    "\n\nKuralı geri getirmek için: ÇBK sayfası → Kazık Detayları → Çember Et Kalınlığı: Otomatik")
  UI.messagebox("#{n} kazığa özel çember et kalınlığı uygulandı (MANUEL).") if n>0
end

# ---------------------------------------------------------------------------
# v0.38 R3 — Target Set service. Section, length, orientation, top elevation
# (length fixed), seabed/splice, plug/rings/PE/drilling and pile infill are
# planned read-only, validated for every target, then applied in ONE SketchUp
# operation with ONE canonical rebuild per pile.
# Identity = persistent_id (element_uid may be copied by copy/paste and Pile ID
# is not guaranteed unique across structures).
# Rule (project standard): upper/lower ring thickness == pipe wall thickness.
# ---------------------------------------------------------------------------
MST_TARGET_FIELDS=%w[diameter_mm thickness_mm steel_grade length_m orientation_mode batter_ratio azimuth_deg
  top_elevation_m seabed_elevation_m splice_mode splice_count_per_pile
  plug_enabled plug_count_per_pile plug_thickness_mm plug_clearance_mm
  lower_ring_enabled lower_ring_width_mm lower_ring_count_per_pile
  upper_ring_enabled upper_ring_width_mm upper_ring_count_per_pile
  pe_enabled pe_length_m drilling_enabled drilling_length_m
  infill_enabled infill_concrete_class infill_bottom_elevation_m ring_thickness_follow_pipe
  ring_thickness_mode upper_ring_thickness_mm lower_ring_thickness_mm].freeze
MST_PILE_FLAGS=%w[plug_enabled lower_ring_enabled upper_ring_enabled pe_enabled drilling_enabled].freeze
# key => [kind, label, default]
MST_PILE_DETAIL_NUMS={
  'plug_count_per_pile'=>[:count,'Tapa adedi',1],'plug_thickness_mm'=>[:pos,'Tapa kalınlığı',12.0],'plug_clearance_mm'=>[:nonneg,'Tapa boşluğu',10.0],
  'lower_ring_width_mm'=>[:pos,'Alt çember genişliği',300.0],'lower_ring_count_per_pile'=>[:count,'Alt çember adedi',1],
  'upper_ring_width_mm'=>[:pos,'Üst çember genişliği',250.0],'upper_ring_count_per_pile'=>[:count,'Üst çember adedi',1],
  'pe_length_m'=>[:nonneg,'PE boyu',0.0],'drilling_length_m'=>[:nonneg,'Foraj boyu',0.0],'splice_count_per_pile'=>[:int0,'Ek adedi',0]
}.freeze

def mst_all_bim_piles(model=Sketchup.active_model)
  all=[];collect_elements(model.entities,all)
  all.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
end

def mst_target_num(value,label)
  v=Float(value.to_s.strip.tr(',','.'))
  raise ArgumentError unless v.finite?
  v
rescue ArgumentError,TypeError
  raise "#{label}: sayısal değer geçersiz (#{value})."
end

def mst_find_reference_pile(data,piles)
  pid=data['reference_pid'].to_s.strip
  unless pid.empty?
    hit=piles.find{|e|e.persistent_id.to_s==pid}
    return hit if hit
  end
  ref_id=data['reference_id'].to_s.strip
  hits=piles.select{|e|e.get_attribute(DICT,'pile_id','').to_s==ref_id}
  raise 'Referans kazık modelde bulunamadı. Kazığı yeniden yükleyin.' if hits.empty?
  raise "Kazık ID #{ref_id} modelde #{hits.length} kazıkta kullanılıyor; referans belirsiz. Kazığı modelden yeniden yükleyin." if hits.length>1
  hits.first
end

def mst_resolve_pile_targets(data)
  model=Sketchup.active_model
  piles=mst_all_bim_piles(model)
  ref=mst_find_reference_pile(data,piles)
  targets=case data['scope'].to_s
  when 'SELECTED'
    selected_piles.map{|entry|entry.is_a?(Array) ? entry[0] : entry}.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
  when 'TYPE'
    mst_type_peers(ref,model)
  when 'IDS'
    ids=mst_parse_pile_id_expression(data['id_expression'])
    raise 'Kazık ID hedefi girilmedi.' if ids.empty?
    by_id=Hash.new{|h,k|h[k]=[]}
    piles.each{|e|by_id[e.get_attribute(DICT,'pile_id','').to_s] << e}
    missing=ids.select{|id|by_id[id].empty?}
    raise "Bulunamayan Kazık ID:#{missing.first(12).join(', ')}#{missing.length>12 ? ' …' : ''}" unless missing.empty?
    dup=ids.select{|id|by_id[id].length>1}
    raise "Bu Kazık ID'ler modelde birden fazla kazıkta kullanılıyor: #{dup.first(12).map{|id|"#{id} (#{by_id[id].length})"}.join(', ')}. ID ile hedefleme belirsiz; 'Modelde seçili kazıklar' seçeneğini kullanın." unless dup.empty?
    ids.map{|id|by_id[id].first}
  when 'ALL'   # 0.51.5 G-b: yalnız açıkça "Projedeki tüm kazıklar" seçilince; önizleme sayıyı gösterir
    piles
  else
    [ref]
  end
  targets=targets.uniq{|e|e.persistent_id}
  raise 'Hedef kazık bulunamadı.' if targets.empty?
  targets
end

def mst_target_changes(data)
  changes=data['changes'].is_a?(Hash) ? data['changes'] : {}
  bad=changes.keys.reject{|k|MST_TARGET_FIELDS.include?(k)}
  raise "Desteklenmeyen güncelleme alanı: #{bad.join(', ')}" unless bad.empty?
  changes
end

def mst_target_orientation_change?(changes)
  changes.key?('orientation_mode') || changes.key?('batter_ratio') || changes.key?('azimuth_deg')
end

def mst_pile_infill_child(p)
  mst_bim_children(p,'pile_infill_concrete').first
end

def mst_fmt_num(v,n=3)
  x=v.to_f.round(n)
  x==x.to_i ? x.to_i.to_s : x.to_s
end

# Pure planning step: computes the final state of one pile, never mutates it.
def mst_pile_target_spec(p,changes,beam_links={})
  pid=p.get_attribute(DICT,'pile_id','?').to_s
  errors=[];warnings=[];diff=[]
  get=->(k,dflt){p.get_attribute(DICT,k,dflt)}
  flag=->(k){(changes.key?(k) ? changes[k] : get.call(k,'0')).to_s=='1' ? '1' : '0'}
  inf=mst_pile_infill_child(p)
  b_t=get.call('thickness_mm',0).to_f
  before={'d'=>get.call('diameter_mm',0).to_f,'t'=>b_t,'l'=>get.call('length_m',0).to_f,
          'grade'=>get.call('steel_grade','').to_s,'mode'=>get.call('orientation_mode','VERTICAL').to_s.upcase,
          'r'=>get.call('batter_ratio',0).to_f,'az'=>get.call('azimuth_deg',0).to_f,
          'top'=>get.call('top_elevation_m',0).to_f,'bottom'=>get.call('bottom_elevation_m',0).to_f,
          'upper_ring_t'=>get.call('upper_ring_thickness_mm',b_t).to_f,'lower_ring_t'=>get.call('lower_ring_thickness_mm',b_t).to_f,
          'infill'=>(inf ? '1' : '0'),'infill_class'=>(inf ? inf.get_attribute(DICT,'concrete_class',get.call('infill_concrete_class','C40/50')) : get.call('infill_concrete_class','C40/50')).to_s,
          'infill_bottom'=>(inf ? inf.get_attribute(DICT,'bottom_elevation_m',get.call('infill_bottom_elevation_m',nil)) : get.call('infill_bottom_elevation_m',nil)),
          'infill_m3'=>(inf ? inf.get_attribute(DICT,'concrete_volume_m3',0).to_f : 0.0)}
  MST_PILE_FLAGS.each{|k|before[k]=get.call(k,'0').to_s=='1' ? '1' : '0'}
  MST_PILE_DETAIL_NUMS.each{|k,(_,_,dflt)|before[k]=get.call(k,dflt)}
  before['splice_mode']=get.call('splice_mode','AUTO').to_s.upcase
  before['seabed']=get.call('seabed_elevation_m',nil)
  before['seabed']=nil if before['seabed'].to_s.strip.empty?
  begin
    d=changes.key?('diameter_mm') ? mst_target_num(changes['diameter_mm'],'Ø') : before['d']
    t=changes.key?('thickness_mm') ? mst_target_num(changes['thickness_mm'],'Et kalınlığı') : before['t']
    l=changes.key?('length_m') ? mst_target_num(changes['length_m'],'Boy') : before['l']
    top=changes.key?('top_elevation_m') ? mst_target_num(changes['top_elevation_m'],'Üst kot') : before['top']
    grade=changes.key?('steel_grade') ? changes['steel_grade'].to_s.strip : before['grade']
    mode=(changes.key?('orientation_mode') ? changes['orientation_mode'] : before['mode']).to_s.upcase
    mode='VERTICAL' unless mode=='BATTERED'
    ratio_raw=changes.key?('batter_ratio') ? changes['batter_ratio'] : get.call('batter_ratio',0)
    az_raw=changes.key?('azimuth_deg') ? mst_target_num(changes['azimuth_deg'],'Azimut') : get.call('azimuth_deg',0).to_f
    seabed=if changes.key?('seabed_elevation_m')
      changes['seabed_elevation_m'].to_s.strip.empty? ? nil : mst_target_num(changes['seabed_elevation_m'],'Deniz tabanı kotu')
    else
      before['seabed'].nil? ? nil : before['seabed'].to_f
    end
    flags={};MST_PILE_FLAGS.each{|k|flags[k]=flag.call(k)}
    splice_mode=(changes.key?('splice_mode') ? changes['splice_mode'] : before['splice_mode']).to_s.upcase
    splice_mode='AUTO' unless splice_mode=='MANUAL'
    # A detail value is validated only when its feature is active (YOK keeps the stored value untouched).
    feature={'plug_count_per_pile'=>'plug_enabled','plug_thickness_mm'=>'plug_enabled','plug_clearance_mm'=>'plug_enabled',
      'lower_ring_width_mm'=>'lower_ring_enabled','lower_ring_count_per_pile'=>'lower_ring_enabled',
      'upper_ring_width_mm'=>'upper_ring_enabled','upper_ring_count_per_pile'=>'upper_ring_enabled',
      'pe_length_m'=>'pe_enabled','drilling_length_m'=>'drilling_enabled'}
    nums={}
    MST_PILE_DETAIL_NUMS.each do |k,(kind,label,dflt)|
      active=k=='splice_count_per_pile' ? splice_mode=='MANUAL' : flags[feature[k]]=='1'
      raw=changes.key?(k) ? changes[k] : before[k]
      if raw.nil? || raw.to_s.strip.empty? || (!changes.key?(k) && kind==:count && raw.to_f<1)
        raw=dflt   # e.g. feature switched YOK→VAR with a stored count of 0
      end
      v=active || changes.key?(k) ? mst_target_num(raw,label) : (Float(raw.to_s.tr(',','.')) rescue dflt.to_f)
      if active
        case kind
        when :count then errors << "#{pid}: #{label} 1 veya daha büyük tam sayı olmalı." unless v>=1 && v==v.round
        when :int0 then errors << "#{pid}: #{label} 0 veya daha büyük tam sayı olmalı." unless v>=0 && v==v.round
        when :pos then errors << "#{pid}: #{label} 0'dan büyük olmalı." unless v>0
        when :nonneg then errors << "#{pid}: #{label} negatif olamaz." unless v>=0
        end
      end
      nums[k]=([:count,:int0].include?(kind) ? v.round : v)
    end
    infill_on=(changes.key?('infill_enabled') ? changes['infill_enabled'] : before['infill']).to_s=='1'
    klass=(changes.key?('infill_concrete_class') ? changes['infill_concrete_class'] : before['infill_class']).to_s.strip
    klass='C40/50' if klass.empty?
    ib=changes.key?('infill_bottom_elevation_m') ? mst_target_num(changes['infill_bottom_elevation_m'],'Beton alt kotu') : before['infill_bottom']
    ib=ib.nil? || ib.to_s.strip.empty? ? nil : ib.to_f
    rot,mode,r,az,down,vz=pile_rotation_transform({'orientation_mode'=>mode,'batter_ratio'=>ratio_raw,'azimuth_deg'=>az_raw})
  rescue => e
    return {'pile'=>p,'id'=>pid,'errors'=>errors+["#{pid}: #{e.message}"],'warnings'=>[],'diff'=>[],'before'=>before,'after'=>before}
  end
  # --- validation (every target, before any operation is opened) ---
  errors << "#{pid}: Ø/t kesiti geçersiz (Ø#{mst_fmt_num(d,1)} / t#{mst_fmt_num(t,1)})." unless d>0 && t>0 && d>2*t
  errors << "#{pid}: kazık boyu 0'dan büyük olmalı." unless l>0
  errors << "#{pid}: çelik sınıfı boş olamaz." if grade.empty?
  errors << "#{pid}: Batarlı kazıkta H/V 0'dan büyük olmalı." if mode=='BATTERED' && r<=1.0e-12
  # Ring wall thickness: PIPE (default) follows the pipe wall; MANUAL keeps/accepts a user value.
  ring_mode_before=mst_ring_manual?(p) ? 'MANUAL' : 'PIPE'
  ring_mode=(changes.key?('ring_thickness_mode') ? changes['ring_thickness_mode'] : ring_mode_before).to_s.upcase
  ring_mode='PIPE' unless ring_mode=='MANUAL'
  ring_manual=ring_mode=='MANUAL'
  if ring_manual
    begin
      up_ring_t=changes.key?('upper_ring_thickness_mm') ? mst_target_num(changes['upper_ring_thickness_mm'],'Üst çember et kalınlığı') : before['upper_ring_t']
      lo_ring_t=changes.key?('lower_ring_thickness_mm') ? mst_target_num(changes['lower_ring_thickness_mm'],'Alt çember et kalınlığı') : before['lower_ring_t']
    rescue => e
      errors << "#{pid}: #{e.message}"
      up_ring_t=before['upper_ring_t'];lo_ring_t=before['lower_ring_t']
    end
    errors << "#{pid}: üst çember et kalınlığı 0'dan büyük olmalı." unless up_ring_t>0
    errors << "#{pid}: alt çember et kalınlığı 0'dan büyük olmalı." unless lo_ring_t>0
  else
    errors << "#{pid}: otomatik modda çember et kalınlığı elle girilemez; önce 'Manuel' seçin." if changes.key?('upper_ring_thickness_mm') || changes.key?('lower_ring_thickness_mm')
    up_ring_t=t;lo_ring_t=t
  end
  if flags['lower_ring_enabled']=='1'
    errors << "#{pid}: alt/iç çember (et #{mst_fmt_num(lo_ring_t,1)} mm#{ring_manual ? ', MANUEL' : ''}) borunun içine sığmıyor." unless d-2*t-2*lo_ring_t>0
    errors << "#{pid}: alt çemberler (#{nums['lower_ring_count_per_pile']} × #{mst_fmt_num(nums['lower_ring_width_mm'])} mm) kazık boyunu aşıyor." if nums['lower_ring_count_per_pile']*nums['lower_ring_width_mm']/1000.0>l
  end
  if flags['upper_ring_enabled']=='1' && nums['upper_ring_count_per_pile']*nums['upper_ring_width_mm']/1000.0>l
    errors << "#{pid}: üst çemberler (#{nums['upper_ring_count_per_pile']} × #{mst_fmt_num(nums['upper_ring_width_mm'])} mm) kazık boyunu aşıyor."
  end
  if flags['plug_enabled']=='1' && !(d-2*t-2*nums['plug_clearance_mm']>0)
    errors << "#{pid}: tapa çapı sıfır veya negatif (boşluk #{mst_fmt_num(nums['plug_clearance_mm'])} mm çok büyük)."
  end
  errors << "#{pid}: PE boyu (#{mst_fmt_num(nums['pe_length_m'])} m) kazık boyunu aşıyor." if flags['pe_enabled']=='1' && nums['pe_length_m']>l+1.0e-9
  bottom=top-l*vz
  inf_h=nil
  if infill_on
    if ib.nil?
      errors << "#{pid}: kazık içi beton için beton alt kotu girilmeli."
    else
      errors << "#{pid}: beton alt kotu (#{mst_fmt_num(ib)} m) kazık üst kotunun (#{mst_fmt_num(top)} m) altında olmalı." unless ib<top
      errors << "#{pid}: beton alt kotu #{mst_fmt_num(ib)} m, kazık alt kotu #{mst_fmt_num(bottom)} m'nin altında kalıyor." if ib<bottom-1.0e-4
      inf_h=(top-ib)/vz
    end
  end
  orient_change=mst_target_orientation_change?(changes)
  top_moved=(top-before['top']).abs>1.0e-9
  axis_change=changes.key?('length_m') || orient_change || top_moved
  driving=nil
  if axis_change || changes.key?('seabed_elevation_m')
    if seabed.nil?
      warnings << "#{pid}: deniz tabanı kotu yok; çakım boyu güncellenmeyecek."
    else
      driving=[seabed-bottom,0.0].max/vz
      warnings << "#{pid}: kazık ucu (#{mst_fmt_num(bottom,2)} m) deniz tabanının (#{mst_fmt_num(seabed,2)} m) üstünde; çakım boyu 0 olur." if bottom>seabed
    end
  end
  if changes.key?('length_m') && splice_mode=='MANUAL' && !changes.key?('splice_count_per_pile')
    warnings << "#{pid}: ek adedi MANUAL (#{nums['splice_count_per_pile']}); boy değişse de değişmeyecek."
  end
  # --- human-readable before → after (computed here so UI and Ruby agree) ---
  diff << "Ø#{mst_fmt_num(before['d'],1)}→#{mst_fmt_num(d,1)}" if (d-before['d']).abs>1.0e-9
  diff << "t#{mst_fmt_num(before['t'],1)}→#{mst_fmt_num(t,1)}" if (t-before['t']).abs>1.0e-9
  diff << "L#{mst_fmt_num(before['l'],2)}→#{mst_fmt_num(l,2)} m" if (l-before['l']).abs>1.0e-9
  diff << "#{before['grade']}→#{grade}" if grade!=before['grade']
  ot=->(m_,r_,a_){m_=='BATTERED' ? "Eğik H/V #{mst_fmt_num(r_,4)}/#{mst_fmt_num(a_,1)}°" : 'Düşey'}
  ob=ot.call(before['mode'],before['r'],before['az']);oa=ot.call(mode,r,az)
  diff << "#{ob}→#{oa}" if ob!=oa
  diff << "üst kot #{mst_fmt_num(before['top'],3)}→#{mst_fmt_num(top,3)} (boy sabit)" if top_moved
  diff << "alt kot #{mst_fmt_num(before['bottom'],2)}→#{mst_fmt_num(bottom,2)}" if (bottom-before['bottom']).abs>1.0e-4
  diff << "deniz tabanı #{before['seabed'].nil? ? '—' : mst_fmt_num(before['seabed'])}→#{seabed.nil? ? '—' : mst_fmt_num(seabed)}" if changes.key?('seabed_elevation_m') && seabed!=(before['seabed'].nil? ? nil : before['seabed'].to_f)
  labels={'plug_enabled'=>'tapa','lower_ring_enabled'=>'alt çember','upper_ring_enabled'=>'üst çember','pe_enabled'=>'PE','drilling_enabled'=>'foraj'}
  MST_PILE_FLAGS.each{|k|diff << "#{labels[k]} #{before[k]=='1' ? 'VAR' : 'YOK'}→#{flags[k]=='1' ? 'VAR' : 'YOK'}" if flags[k]!=before[k]}
  MST_PILE_DETAIL_NUMS.each do |k,(_,label,_)|
    next unless changes.key?(k)
    bv=before[k].nil? || before[k].to_s.strip.empty? ? nil : before[k].to_f
    diff << "#{label.downcase} #{bv.nil? ? '—' : mst_fmt_num(bv)}→#{mst_fmt_num(nums[k])}" if bv.nil? || (bv-nums[k]).abs>1.0e-9
  end
  diff << "ek hesabı #{before['splice_mode']}→#{splice_mode}" if splice_mode!=before['splice_mode']
  mode_txt={'PIPE'=>'OTOMATİK','MANUAL'=>'MANUEL'}
  diff << "çember modu #{mode_txt[ring_mode_before]}→#{mode_txt[ring_mode]}" if ring_mode!=ring_mode_before
  %w[upper lower].each do |side|
    en=flags["#{side}_ring_enabled"]=='1'
    bt=before["#{side}_ring_t"];nt=side=='upper' ? up_ring_t : lo_ring_t
    diff << "#{side=='upper' ? 'üst' : 'alt'} çember et #{mst_fmt_num(bt,1)}→#{mst_fmt_num(nt,1)} mm (#{ring_manual ? 'MANUEL' : 'kural: = boru et'})" if en && (bt-nt).abs>1.0e-9
  end
  di=(d-2*t)/1000.0
  new_m3=infill_on && inf_h && inf_h>0 ? Math::PI/4.0*di*di*inf_h : 0.0
  if before['infill']=='1' && !infill_on
    diff << "iç beton VAR→YOK"
    warnings << "#{pid}: kazık içi beton silinecek; #{mst_fmt_num(before['infill_m3'])} m³ metrajdan düşer."
  elsif before['infill']!='1' && infill_on
    diff << "iç beton YOK→VAR (#{mst_fmt_num(new_m3)} m³)"
  elsif infill_on
    bb=before['infill_bottom'].nil? ? nil : before['infill_bottom'].to_f
    diff << "beton alt kotu #{bb.nil? ? '—' : mst_fmt_num(bb)}→#{mst_fmt_num(ib)}" if bb.nil? || (bb-ib).abs>1.0e-9
    diff << "beton sınıfı #{before['infill_class']}→#{klass}" if klass!=before['infill_class']
    diff << "iç beton #{mst_fmt_num(before['infill_m3'])}→#{mst_fmt_num(new_m3)} m³" if (new_m3-before['infill_m3']).abs>5.0e-4
  end
  after={'d'=>d,'t'=>t,'l'=>l,'grade'=>grade,'mode'=>mode,'r'=>r,'az'=>az,'top'=>top,'bottom'=>bottom,'seabed'=>seabed,
         'upper_ring_t'=>up_ring_t,'lower_ring_t'=>lo_ring_t,'ring_mode'=>ring_mode,'ring_mode_changed'=>ring_mode!=ring_mode_before,'flags'=>flags,'nums'=>nums,'splice_mode'=>splice_mode,
         'write_flags'=>MST_PILE_FLAGS.select{|k|changes.key?(k)},
         'splice_mode_changed'=>splice_mode!=before['splice_mode'],'splice_count_changed'=>changes.key?('splice_count_per_pile'),
         # switching a feature on also writes the values it now relies on (count/width/length)
         'write_nums'=>nums.keys.select{|k|k!='splice_count_per_pile' && (changes.key?(k) || (feature[k] && changes.key?(feature[k]) && flags[feature[k]]=='1'))},
         'infill'=>infill_on,'infill_class'=>klass,'infill_bottom'=>ib,'infill_h'=>inf_h,'infill_m3'=>new_m3}
  {'pile'=>p,'id'=>pid,'errors'=>errors,'warnings'=>warnings,'diff'=>diff,'before'=>before,'after'=>after,
   'rot'=>rot,'down'=>down,'vz'=>vz,'inf'=>inf,'driving'=>driving,'axis_change'=>axis_change,
   'orient_change'=>orient_change,'top_moved'=>top_moved}
end

def mst_apply_pile_target_spec!(s)
  p=s['pile'];a=s['after'];vz=s['vz'];down=s['down'];l=a['l'];top=a['top']
  # 1) axis / elevations (head stays unless top elevation itself changed; length is kept)
  p.set_attribute(DICT,'length_m',l)
  p.set_attribute(DICT,'actual_length_m',l)
  p.set_attribute(DICT,'vertical_length_m',l*vz)
  p.set_attribute(DICT,'top_elevation_m',top)
  p.set_attribute(DICT,'bottom_elevation_m',a['bottom'])
  x=p.get_attribute(DICT,'axis_x_m',0).to_f;y=p.get_attribute(DICT,'axis_y_m',0).to_f
  p.set_attribute(DICT,'toe_x_m',x+l*down.x)
  p.set_attribute(DICT,'toe_y_m',y+l*down.y)
  p.set_attribute(DICT,'toe_z_m',a['bottom'])
  p.set_attribute(DICT,'orientation_mode',a['mode'])
  p.set_attribute(DICT,'batter_ratio',a['r'])
  p.set_attribute(DICT,'azimuth_deg',a['az'])
  p.set_attribute(DICT,'seabed_elevation_m',a['seabed'])
  p.set_attribute(DICT,'driving_length_m',s['driving']) unless s['driving'].nil?
  if s['top_moved']
    p.set_attribute(DICT,'elevation_mode','SPECIAL')
    p.set_attribute(DICT,'special_top_elevation_m',top)
  end
  # Splice data is written only when it really changes (mode/count edited, or AUTO count after a length change).
  p.set_attribute(DICT,'splice_mode',a['splice_mode']) if a['splice_mode_changed']
  if a['splice_mode']=='MANUAL'
    p.set_attribute(DICT,'splice_count_per_pile',a['nums']['splice_count_per_pile']) if a['splice_mode_changed'] || a['splice_count_changed']
  elsif a['splice_mode_changed'] || s['axis_change']
    p.set_attribute(DICT,'splice_count_per_pile',[(l/12.0).ceil-1,0].max)
  end
  # 2) fabrication details (ring thickness always equals pipe wall thickness)
  a['write_flags'].each{|k|p.set_attribute(DICT,k,a['flags'][k])}
  a['write_nums'].each{|k|p.set_attribute(DICT,k,a['nums'][k])}
  # YOK keeps the stored engineering value (QTO and drawing use the *_enabled flag);
  # switching back to VAR therefore restores the previous plug count.
  if a['flags']['plug_enabled']=='1' && (a['write_flags'].include?('plug_enabled') || a['write_nums'].include?('plug_count_per_pile'))
    p.set_attribute(DICT,'plug_count_per_pile',[a['nums']['plug_count_per_pile'],1].max)
  end
  p.set_attribute(DICT,'ring_thickness_mode',a['ring_mode']) if a['ring_mode_changed']
  p.set_attribute(DICT,'upper_ring_thickness_mm',a['upper_ring_t'])
  p.set_attribute(DICT,'lower_ring_thickness_mm',a['lower_ring_t'])
  # 3) pile infill — existing child is updated IN PLACE (identity kept)
  inf=s['inf']
  if mst_component_pile?(p)
    # v0.38 C3: the infill child is shared; only the instance's own values change.
    # The matching definition (with the right infill) is attached in step 4.
    if a['infill']
      p.set_attribute(DICT,'infill_enabled','1')
      p.set_attribute(DICT,'infill_bottom_elevation_m',a['infill_bottom'])
      p.set_attribute(DICT,'infill_concrete_class',a['infill_class'])
    else
      p.set_attribute(DICT,'infill_enabled','0')
      p.set_attribute(DICT,'infill_concrete_volume_m3',0.0)
      p.set_attribute(DICT,'infill_bottom_elevation_m',nil)
    end
  elsif a['infill']
    if inf
      inf.set_attribute(DICT,'top_elevation_m',top)
      inf.set_attribute(DICT,'bottom_elevation_m',a['infill_bottom'])
      inf.set_attribute(DICT,'height_m',a['infill_h'])
      inf.set_attribute(DICT,'concrete_class',a['infill_class'])
      p.set_attribute(DICT,'infill_enabled','1')
      p.set_attribute(DICT,'infill_bottom_elevation_m',a['infill_bottom'])
      p.set_attribute(DICT,'infill_concrete_class',a['infill_class'])
    else
      pd={'diameter_mm'=>a['d'],'thickness_mm'=>a['t'],'top_elevation_m'=>top,'length_m'=>l,'orientation_mode'=>a['mode'],
          'batter_ratio'=>a['r'],'azimuth_deg'=>a['az'],'infill_enabled'=>'1','infill_bottom_normal_m'=>a['infill_bottom'],
          'infill_concrete_class'=>a['infill_class']}
      add_pile_infill(p,pd,'NORMAL',false)
    end
  else
    inf.erase! if inf && inf.valid?
    p.set_attribute(DICT,'infill_enabled','0')
    p.set_attribute(DICT,'infill_concrete_volume_m3',0.0)
    p.set_attribute(DICT,'infill_bottom_elevation_m',nil)
  end
  # 4) one canonical rebuild: pipe, infill geometry/volume, plugs, rings, weight, QTO cache, audits
  mst_prof(:section_rebuild){mst_rebuild_pile_section_dependencies(p,a['d'],a['t'],a['grade'])}
  # 5) placement: head moves only by the top-elevation delta; axis follows orientation
  tr=p.transformation;o=tr.origin
  dz=s['top_moved'] ? m(top-s['before']['top']).to_f : 0.0
  target=[o.x.to_f,o.y.to_f,o.z.to_f+dz]
  if s['orient_change']
    p.transformation=Geom::Transformation.translation(Geom::Point3d.new(*target))*s['rot']
  elsif dz.abs>0.0
    p.transformation=Geom::Transformation.translation(Geom::Vector3d.new(0,0,dz))*tr
  end
  # Plain Float comparison: SketchUp Length comparisons apply model tolerance.
  now=p.transformation.origin
  moved=[now.x.to_f,now.y.to_f,now.z.to_f].each_with_index.map{|v,i|(v-target[i]).abs}.max
  raise "#{s['id']}: kazık başı beklenen konumdan #{moved} inç saptı." if moved>1.0e-6
  ensure_uid(p);sync_pile_bim_qto(p)
end

# ===========================================================================
# v0.38 BK1 — Head beams follow their piles (target update).
#  • Ø change  → BK pile-opening deduction, net formwork and Ø list are
#                recomputed from the connected piles' new diameters.
#  • top change → if EVERY connected pile moves by the same Δ, the BK and what
#                sits on it (PD / kanal / döşeme / bordür) move by Δ together;
#                otherwise nothing moves and the preview says why.
# Pure planning first (preview); applied in the same single operation.
# ===========================================================================
MST_BK_ELEV_KEYS=%w[top_elevation_m bottom_elevation_m main_bottom_elevation_m base_top_elevation_m base_bottom_elevation_m hb_bottom_elevation_m].freeze
MST_BK_TOL=1.0e-6

def mst_bk_type?(e,t);e && e.valid? && e.get_attribute(DICT,'element_type','').to_s==t;end

def mst_bk_follow_plan(specs,model=Sketchup.active_model)
 by_pile={};specs.each{|s|by_pile[s['pile']]=s if s['after'] && s['after'].key?('top')}
 return {'beams'=>[],'moves'=>[],'lines'=>[],'warnings'=>[]} if by_pile.empty?
 _all,children,parents,_=dependency_graph(model)
 beams=by_pile.keys.flat_map{|p|children[p].select{|e|mst_bk_type?(e,'head_beam')}}.uniq
 plans=beams.map do |b|
  piles=parents[b].select{|e|mst_bk_type?(e,'steel_pipe_pile')}
  ids=mst_pile_ids_for_beam(b)
  pl={'beam'=>b,'id'=>element_visible_id(b),'dz'=>nil,'warnings'=>[],'lines'=>[]}
  deltas=piles.map{|p|s=by_pile[p];s ? s['after']['top'].to_f-s['before']['top'].to_f : 0.0}
  diam_changed=piles.any?{|p|s=by_pile[p];s && (s['after']['d'].to_f-s['before']['d'].to_f).abs>MST_BK_TOL}
  unresolved=ids.length!=piles.length
  if diam_changed
   if unresolved
    pl['warnings'] << "#{pl['id']}: bağlı kazık listesi (#{ids.length}) modeldeki kazıklarla (#{piles.length}) eşleşmiyor; kalıp kazık boşluğu güncellenmedi."
   else
    d_after=piles.map{|p|s=by_pile[p];s ? s['after']['d'].to_f : p.get_attribute(DICT,'diameter_mm',0).to_f}
    r_after=piles.map{|p|s=by_pile[p];s ? (s['after']['mode'].to_s.upcase=='BATTERED' ? s['after']['r'].to_f.abs : 0.0) : mst_pile_opening_ratio(p)}
    open_new=d_after.each_with_index.sum{|dmm,i|mst_pile_opening_m2(dmm,r_after[i])}   # v0.51.5: eğik kazıkta elips
    open_old=b.get_attribute(DICT,'pile_opening_area_m2',0).to_f
    gross=b.get_attribute(DICT,'formwork_gross_area_m2',b.get_attribute(DICT,'formwork_area_m2',0)).to_f
    pl['opening']=[open_old,open_new];pl['net_new']=[gross-open_new,0.0].max
    pl['diam_text']=d_after.group_by{|d|d.round(3)}.transform_values(&:length).sort.map{|d,c|"#{c} x Ø#{format('%.1f',d)}"}.join(' + ')
    pl['lines'] << format('%s: kalıp kazık boşluğu %.3f → %.3f m² (%s)',pl['id'],open_old,open_new,pl['diam_text'])
   end
  end
  if deltas.any?{|d|d.abs>MST_BK_TOL}
   if unresolved
    pl['warnings'] << "#{pl['id']}: bağlı kazıklardan bazıları modelde bulunamadı; BK kotu değiştirilmedi."
   elsif deltas.max-deltas.min>MST_BK_TOL
    pl['warnings'] << "#{pl['id']}: bağlı #{piles.length} kazığın kot değişimi farklı (#{deltas.map{|d|format('%+.2f',d)}.uniq.join(' / ')} m); BK yerinde kalır, kontrol edin."
   else
    pl['dz']=deltas.first
   end
  end
  pl
 end
 # Everything that sits on a moving BK moves with it — only if all of its BKs move by the same Δ.
 bk_ancestors=lambda do |e,seen={}|
  parents[e].flat_map{|p| next [] if seen[p];seen[p]=true;mst_bk_type?(p,'head_beam') ? [p] : (mst_bk_type?(p,'steel_pipe_pile') ? [] : bk_ancestors.call(p,seen))}.uniq
 end
 closure=lambda do |b|
  out=[];queue=children[b].dup
  until queue.empty?
   c=queue.shift
   next if out.include?(c) || !c.valid? || mst_bk_type?(c,'steel_pipe_pile') || mst_bk_type?(c,'head_beam')
   out << c;queue.concat(children[c])
  end
  out
 end
 loop do
  dz_of={};plans.each{|pl|dz_of[pl['beam']]=pl['dz'] if pl['dz']}
  changed=false
  plans.each do |pl|
   next unless pl['dz']
   pl['dependents']=closure.call(pl['beam'])
   blocker=pl['dependents'].find{|d|bk_ancestors.call(d).any?{|a|dz_of[a].nil? || (dz_of[a]-pl['dz']).abs>MST_BK_TOL}}
   next unless blocker
   pl['warnings'] << "#{pl['id']}: üzerindeki #{element_visible_id(blocker)} aynı kotta taşınmayan başka bir BK'ya da oturuyor; BK yerinde kalır, kontrol edin."
   pl['dz']=nil;pl['dependents']=[];changed=true
  end
  break unless changed
 end
 moves={}
 plans.each do |pl|
  next unless pl['dz']
  ([pl['beam']]+pl['dependents']).each{|e|moves[e]=pl['dz']}
  dep=pl['dependents'].map{|d|element_visible_id(d)}
  pl['lines'] << format('%s: %+.3f m taşınacak%s',pl['id'],pl['dz'],dep.empty? ? '' : " (üzerindekiler: #{mst_axis_fmt_list(dep,6)})")
 end
 {'beams'=>plans,'moves'=>moves.map{|e,dz|{'element'=>e,'dz'=>dz}},'lines'=>plans.flat_map{|pl|pl['lines']},'warnings'=>plans.flat_map{|pl|pl['warnings']}}
end

def mst_apply_bk_follow_plan(bp)
 bp['beams'].each do |pl|
  next unless pl['opening'] && pl['beam'].valid?
  b=pl['beam']
  b.set_attribute(DICT,'pile_opening_area_m2',pl['opening'][1])
  b.set_attribute(DICT,'formwork_net_area_m2',pl['net_new'])
  b.set_attribute(DICT,'connected_pile_diameters',pl['diam_text'])
 end
 bp['moves'].each do |mv|
  e=mv['element'];dz=mv['dz'];next unless e.valid?
  e.transform!(Geom::Transformation.translation([0,0,m(dz)]))
  MST_BK_ELEV_KEYS.each do |k|
   v=e.get_attribute(DICT,k,nil)
   e.set_attribute(DICT,k,v.to_f+dz) if v.is_a?(Numeric)
  end
 end
 [bp['beams'].count{|pl|pl['opening']},bp['moves'].length]
end

def mst_pile_beam_links(targets,model)
  _all,children,_parents,_by_uid=dependency_graph(model)
  targets.each_with_object({}) do |p,h|
    h[p]=children[p].select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}.map{|e|element_visible_id(e)}
  end
rescue => e
  warn("MST beam link lookup: #{e.message}")
  {}
end

def mst_pile_target_plan(data)
  changes=mst_target_changes(data)
  targets=mst_resolve_pile_targets(data)
  links={}   # v0.38 BK1: BK effects are planned by mst_bk_follow_plan
  specs=targets.map{|p|mst_pile_target_spec(p,changes,links)}
  [changes,targets,specs]
end

def mst_pile_target_preview_payload(data)
  changes,targets,specs=mst_pile_target_plan(data)
  rows=specs.map{|s|{'key'=>s['pile'].persistent_id.to_s,'id'=>s['id'],'diff'=>s['diff'],'warnings'=>s['warnings'],'errors'=>s['errors']}}
  bp=(specs.any?{|s|!s['errors'].to_a.empty?} ? nil : (mst_bk_follow_plan(specs) rescue nil))
  {'count'=>targets.length,'rows'=>rows,'has_changes'=>!changes.empty?,
   'bk_lines'=>(bp ? bp['lines'] : []),'bk_warnings'=>(bp ? bp['warnings'] : [])}
end

def mst_apply_pile_target_update(data)
  model=Sketchup.active_model
  changes,targets,specs=mst_pile_target_plan(data)
  raise 'Değişiklik bulunamadı.' if changes.empty?
  expected=Array(data['expected_keys']).map(&:to_s).sort
  actual=targets.map{|p|p.persistent_id.to_s}.sort
  if expected.empty? || expected!=actual
    raise "Hedef kümesi önizlemeden sonra değişti (önizleme #{expected.length}, şimdi #{actual.length} kazık). Seçim değişmiş olabilir; 'Hedefleri Önizle' ile yeniden kontrol edin."
  end
  errors=specs.map{|s|s['errors']}.flatten
  raise "Güncelleme başlatılmadı:\n#{errors.first(15).join("\n")}#{errors.length>15 ? "\n…" : ''}" unless errors.empty?
  ref=mst_find_reference_pile(data,mst_all_bim_piles(model)) rescue nil
  bp=mst_bk_follow_plan(specs,model)   # v0.38 BK1: planned on the unchanged model
  bk_done=[0,0]
  model.start_operation("MST #{targets.length} Kazık Hedef Güncelleme",true)
  begin
    mst_scan_batch(model) do
      specs.each{|s|mst_prof(:target_spec){mst_apply_pile_target_spec!(s)}}
      bk_done=mst_apply_bk_follow_plan(bp)
      # Always resync after a single or bulk engineering change; prevents stale type_id.
      mst_prof(:type_sync){mst_sync_pile_type_library(model)}
    end
    mst_prof(:commit){commit_with_dependencies(model)};model.active_view.invalidate
  rescue Exception
    model.abort_operation
    raise
  end
  bk_note=''
  bk_note+="\nBK kalıp boşluğu güncellendi: #{bk_done[0]}" if bk_done[0]>0
  bk_note+="\nKazıkla birlikte taşınan BK / üzerindeki eleman: #{bk_done[1]}" if bk_done[1]>0
  {'count'=>targets.length,'ids'=>specs.map{|s|s['id']},'warnings'=>(specs.map{|s|s['warnings']}.flatten+bp['warnings']).first(20),
   'reference'=>(ref && ref.valid?) ? mst_bim_pile_payload(ref) : nil,
   'message'=>"#{targets.length} kazık güncellendi. Geometri + kot + detaylar + iç beton + TİP + metraj eşitlendi; tek Geri Al ile geri alınabilir.#{bk_note}"}
end

def edit_selected_pile_v2
 model=Sketchup.active_model
 g=model.selection.to_a.find{|e|e.respond_to?(:get_attribute)&&e.get_attribute(DICT,'element_type')=='steel_pipe_pile'}
 unless g;UI.messagebox('Kazık Yerleşimi: bir çelik boru kazık seçiniz.');return;end
 d=g.get_attribute(DICT,'diameter_mm',0).to_f;t=g.get_attribute(DICT,'thickness_mm',0).to_f;l=g.get_attribute(DICT,'length_m',0).to_f;top=g.get_attribute(DICT,'top_elevation_m',0).to_f;steel=g.get_attribute(DICT,'steel_grade','S355J2H').to_s
 rx=g.get_attribute(DICT,'rake_x_hv',0).to_f;ry=g.get_attribute(DICT,'rake_y_hv',0).to_f
 prompts=['Dış Çap (mm)','Et Kalınlığı (mm)','Düşey Boy / Kot Farkı (m)','Üst Kot (m)','Çelik Sınıfı','Eğim X (yatay/düşey; 1:6 için 0.1667)','Eğim Y (yatay/düşey)']
 vals=UI.inputbox(prompts,[d,t,l,top,steel,rx,ry],'Kazık Yerleşimi — Seçili Kazığı Düzenle');return unless vals
 d,t,l,top,steel,rx,ry=vals;d=d.to_f;t=t.to_f;l=l.to_f;top=top.to_f;rx=rx.to_f;ry=ry.to_f
 raise 'Geçersiz kazık ölçüsü.' if d<=0||t<=0||2*t>=d||l<=0
 model.start_operation('Kazık Düzenle',true);rebuild_pile_geometry(g,d,t,l,rx,ry)
 bot=top-l;actual=l*Math.sqrt(1.0+rx*rx+ry*ry)
 {'diameter_mm'=>d,'thickness_mm'=>t,'length_m'=>l,'vertical_length_m'=>l,'actual_length_m'=>actual,'top_elevation_m'=>top,'bottom_elevation_m'=>bot,'steel_grade'=>steel.to_s,'rake_x_hv'=>rx,'rake_y_hv'=>ry,'weight_kg'=>pile_weight(d,t,actual),'type_signature'=>"steel_pipe_pile|#{d.round(1)}|#{t.round(1)}|#{steel}"}.each{|k,v|g.set_attribute(DICT,k,v)}
 ensure_uid(g);commit_with_dependencies(model);model.active_view.invalidate
 UI.messagebox("Kazık güncellendi.\nRake X=#{format('%.4f',rx)} H/V, Rake Y=#{format('%.4f',ry)} H/V\nGerçek eksen boyu=#{format('%.3f',actual)} m\nÜst ve alt kesimler yatay proje kotunda tutuldu.")
rescue=>ex
 model.abort_operation rescue nil;UI.messagebox("Kazık Yerleşimi hatası: #{ex.message}")
end


# v0.37.7: BIM Type / Instance Engine foundation.
# Physical elements remain independent Groups so UID, placement and face overrides stay instance-safe.
# Shared TYPE parameters are propagated deliberately to all instances carrying the same stable Type ID.
def mst_type_peers(entity, model=Sketchup.active_model)
  return [] unless entity && entity.valid?
  tid=entity.get_attribute(DICT,'type_id',entity.get_attribute(DICT,'library_type_id','')).to_s.strip
  et=entity.get_attribute(DICT,'element_type','').to_s
  return [entity] if tid.empty? || et.empty?
  all=[];collect_elements(model.entities,all)
  all.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s==et && e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s==tid}
end

def mst_selected_type_summary
  model=Sketchup.active_model
  e=model.selection.to_a.find{|x|x.respond_to?(:get_attribute) && !x.get_attribute(DICT,'element_type','').to_s.empty?}
  return UI.messagebox('Önce bir MST BIM elemanı seçin.') unless e
  peers=mst_type_peers(e,model)
  tid=e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s
  UI.messagebox("MST Tip / Örnek Motoru\n\nTip ID: #{tid}\nEleman: #{bim_type_label(e.get_attribute(DICT,'element_type','').to_s)}\nBu tipi kullanan fiziksel eleman: #{peers.length}\n\nTİP = ortak teknik tanım\nÖRNEK (instance) = UID / konum / aks / kot / yüzeye özel değer\n\nFiziksel elemanlar bağımsız tutulur; tip değişiklikleri kontrollü olarak tüm eş tip elemanlara yayılır.")
end

# Read-only physical pipe section check. Uses raw vertices only (never accessory groups).
# SketchUp internal lengths are inches; mm() converts the BIM dimensions accordingly.
def mst_audit_raw_pile_section(p)
  d=p.get_attribute(DICT,'diameter_mm',0).to_f
  t=p.get_attribute(DICT,'thickness_mm',0).to_f
  len=p.get_attribute(DICT,'length_m',0).to_f
  return ['BIM boru kesit ölçüleri geçersiz.'] unless d>0 && t>0 && d>2*t && len>0
  vertices=mst_container_entities(p).grep(Sketchup::Face).flat_map{|f|f.vertices}.uniq   # v0.38 BK4.1: Group or Component pile
  return ['Fiziksel boru yüzeyleri bulunamadı.'] if vertices.empty?
  top=vertices.select{|v|v.position.z.abs < mm(0.1)}
  radii=top.map{|v|Math.sqrt(v.position.x**2+v.position.y**2)}.select{|r|r>mm(1)}
  return ['Fiziksel boru üst kesiti okunamadı.'] if radii.empty?
  ro=mm(d)/2.0;ri=mm(d-2*t)/2.0
  errors=[]
  errors << "Fiziksel dış çap / BIM uyuşmazlığı (BIM Ø#{d} mm)." unless radii.any?{|r|(r-ro).abs<=mm(0.5)}
  errors << "Fiziksel iç çap / BIM uyuşmazlığı (BIM Ø#{d-2*t} mm)." unless radii.any?{|r|(r-ri).abs<=mm(0.5)}
  zmin=vertices.map{|v|v.position.z}.min
  errors << "Fiziksel boru eksen boyu / BIM uyuşmazlığı (BIM #{len} m)." if (zmin+m(len)).abs>mm(1)
  axis_len=p.get_attribute(DICT,'actual_length_m',len).to_f
  expected=pile_weight(d,t,axis_len>0 ? axis_len : len)
  stored=p.get_attribute(DICT,'weight_kg',nil)
  errors << 'Boru BIM ağırlığı / teorik metraj uyuşmazlığı.' if stored && (stored.to_f-expected).abs>[0.5,expected*0.0001].max
  errors
rescue => ex
  ["Fiziksel boru kesiti okunamadı: #{ex.message}"]
end

# Rebuild a pile section and all section-dependent physical children in place.
# Keep the parent and infill Group objects (UID, transforms and instance links survive).
def mst_rebuild_pile_section_dependencies(p, d, t, grade)
  return mst_rebuild_pile_component!(p,d,t,grade) if mst_component_pile?(p)   # v0.38 C3
  mst_require_group_pile!(p,'Kesit/geometri güncellemesi')
  raise 'Geçersiz kazık kesiti.' unless d>0 && t>0 && d>2*t
  len=p.get_attribute(DICT,'length_m',0).to_f
  raise 'Kazık boyu geçersiz.' unless len>0
  original_transform=p.transformation.to_a.dup
  original_uid=p.get_attribute(DICT,'element_uid',nil)
  inf=p.entities.grep(Sketchup::Group).find{|g|g.valid? && g.get_attribute(DICT,'element_type','').to_s=='pile_infill_concrete'}
  # Preserve the concrete's own axis height, identity, concrete class and elevations.
  inf_h=inf ? inf.get_attribute(DICT,'height_m',0).to_f : 0.0
  if inf && inf_h<=0
    raise "#{p.get_attribute(DICT,'pile_id','?')}: iç beton yüksekliği geçersiz."
  end
  # Erase only the RAW steel pipe, not child groups or their BIM identities.
  # v0.38 R9: one erase call (same set: every raw face, then every raw edge — after the
  # faces are gone no raw edge of this group can still bound a face).
  mst_prof(:rebuild_erase){raw=p.entities.grep(Sketchup::Face).to_a+p.entities.grep(Sketchup::Edge).to_a;p.entities.erase_entities(raw) unless raw.empty?}
  shell=mst_prof(:pipe_geometry){pipe(p.entities,d,t,len)}
  raise 'Yeni boru geometrisi oluşturulamadı.' unless shell && shell.valid?
  shell.explode
  p.set_attribute(DICT,'diameter_mm',d)
  p.set_attribute(DICT,'thickness_mm',t)
  p.set_attribute(DICT,'steel_grade',grade)
  axis_len=p.get_attribute(DICT,'actual_length_m',len).to_f
  axis_len=len unless axis_len>0
  wt=pile_weight(d,t,axis_len)
  %w[weight_kg theoretical_weight_kg qto_steel_pipe_weight_kg].each{|key|p.set_attribute(DICT,key,wt)}
  p.set_attribute(DICT,'type_signature',"steel_pipe_pile|#{d.round(1)}|#{t.round(1)}|#{grade}")
  if inf
    di=d-2.0*t
    inf.entities.clear!
    circle=inf.entities.add_circle(ORIGIN,Z_AXIS,mm(di)/2.0,SEG)
    face=inf.entities.add_face(circle)
    raise 'Yeni kazık içi beton yüzeyi oluşturulamadı.' unless face && face.valid?
    face.reverse! if face.normal.z<0
    face.pushpull(-m(inf_h))
    vol=Math::PI/4.0*(di/1000.0)**2*inf_h
    inf.set_attribute(DICT,'internal_diameter_mm',di)
    inf.set_attribute(DICT,'concrete_volume_m3',vol)
    p.set_attribute(DICT,'infill_concrete_volume_m3',vol)
  end
  # Ring rule (PIPE mode): ring wall thickness follows the pipe wall; MANUAL keeps the user value.
  mst_enforce_ring_rule!(p,t)
  # Regenerates plugs and inner/outer rings from new D/t, respecting saved
  # per-pile Var/Yok, widths, thicknesses, counts and assembly clearance.
  mst_prof(:visual_refresh){mst_visual_refresh_pile(p,{})}
  mst_prof(:qto_sync){sync_pile_bim_qto(p)}
  raise 'Kazık konumu/eğimi güncelleme sırasında değişti.' unless p.transformation.to_a.each_with_index.all?{|v,i|(v-original_transform[i]).abs<1.0e-8}
  raise 'Kazık UID güncelleme sırasında değişti.' unless p.get_attribute(DICT,'element_uid',nil)==original_uid
  physical_issues=mst_prof(:audit){mst_audit_raw_pile_section(p)}
  raise physical_issues.join('; ') unless physical_issues.empty?
  if p.get_attribute(DICT,'mst_visual_initialized','0').to_s=='1'
    issues=mst_visual_audit_pile(p)
    raise "#{p.get_attribute(DICT,'pile_id','?')}: #{issues.join('; ')}" unless issues.empty?
  end
  true
end

def mst_edit_selected_pile_type
  model=Sketchup.active_model
  e=mst_selected_bim_pile
  return UI.messagebox('Önce bir MST çelik boru kazık seçin.') unless e
  peers=mst_type_peers(e,model)
  tid=e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s
  d=e.get_attribute(DICT,'diameter_mm',0).to_f;t=e.get_attribute(DICT,'thickness_mm',0).to_f;grade=e.get_attribute(DICT,'steel_grade','S355J2H').to_s
  vals=UI.inputbox(['Dış Çap (mm)','Et Kalınlığı (mm)','Çelik Sınıfı'],[d,t,grade],"#{tid} — TYPE Parametreleri (#{peers.length} adet)")
  return unless vals
  nd,nt,ng=vals[0].to_f,vals[1].to_f,vals[2].to_s.strip
  raise 'Geçersiz kazık ölçüsü.' if nd<=0 || nt<=0 || 2*nt>=nd
  msg="#{tid} tipini kullanan #{peers.length} fiziksel kazık var.\n\nØ#{format('%.1f',d)} / t#{format('%.1f',t)} / #{grade}\n→ Ø#{format('%.1f',nd)} / t#{format('%.1f',nt)} / #{ng}\n\nTüm bu kazıklara uygulansın mı?\n\nKazık ID, UID, boy, kot, aks, konum ve örneğe (instance) özel detaylar korunacaktır."
  return unless UI.messagebox(msg,MB_YESNO)==IDYES
  specs=peers.each_with_object({}){|p,h|h[p]=[nd,nt,ng]}
  mst_apply_pile_sections_atomic(peers,specs,"MST #{tid} Type Update",true)
  UI.messagebox("#{tid}: #{peers.length} kazık TİP parametreleri güncellendi.\n\nÖrnek (instance) kimlikleri/konumları korunmuştur. Metraj ve Tip Kütüphanesi eşitlendi.")
rescue=>ex
  model.abort_operation rescue nil
  UI.messagebox("MST Tip Güncelleme hatası: #{ex.message}")
end

def mst_identity_id_key(t)
 {'steel_pipe_pile'=>'pile_id','head_beam'=>'head_beam_id','flat_precast'=>'precast_id','channel_precast'=>'precast_id','crane_precast'=>'precast_id','deck_slab'=>'deck_id','curb'=>'curb_id'}[t]
end

def mst_next_unique_physical_id(prefix,used)
 n=1
 loop do
  id="#{prefix}-#{n.to_s.rjust(3,'0')}"
  return id unless used[id]
  n+=1
 end
end

def repair_bim_identity
 model=Sketchup.active_model; all=[];collect_elements(model.entities,all)
 elems=all.select{|e|%w[steel_pipe_pile pile_infill_concrete head_beam flat_precast channel_precast crane_precast deck_slab deck_topping curb crown_wall bored_pile accessory].include?(e.get_attribute(DICT,'element_type','').to_s)}
 return UI.messagebox('Onarılacak MST elemanı bulunamadı.') if elems.empty?
 # Preview counts before touching the model.
 missing_uids=elems.select{|e|e.get_attribute(DICT,'element_uid','').to_s.strip.empty?}
 uid_groups=elems.group_by{|e|e.get_attribute(DICT,'element_uid','').to_s.strip}.reject{|k,a|k.empty?||a.length<2}
 id_groups=elems.group_by{|e|[e.get_attribute(DICT,'element_type','').to_s,element_visible_id(e)]}.reject{|k,a|k[1].start_with?('PID-')||a.length<2}
 id_owner={};id_groups.each{|k,arr|id_owner[k]=mst_uid_owner(arr)[0]}   # A2→B: fiziksel ID'yi asıl öğe korur (yazmadan önce karar)
 # ADR-0515 §1 / K06: asıl öğe mst_uid_owner ile (kayıtlı sahip / UID içindeki PID / en eski PID); öbürleri kopya
 uid_plan=uid_groups.map{|u,arr|own,why=mst_uid_owner(arr);[u,own,arr-[own],why]}
 pairs=uid_plan.flat_map{|u,own,cps,why|cps.map{|c|"#{element_visible_id(own)} (PID #{own.persistent_id}) → #{element_visible_id(c)} (PID #{c.persistent_id}) · #{why}"}}
 # Tretuvar: yalnız kopya tretuvar, XY merkezi (model uzayı) tam bir kopya döşemenin sınır kutusu içindeyse kopya döşemeye bağlanır
 deck_copies=Hash.new{|h,k|h[k]=[]};uid_plan.each{|u,own,cps,why|cps.each{|c|deck_copies[u] << c if c.get_attribute(DICT,'element_type','').to_s=='deck_slab'}}
 curb_moves=[];curb_check=[]
 uid_plan.each do |u,own,cps,why|
  cps.each do |c|
   next unless c.get_attribute(DICT,'element_type','').to_s=='curb'
   ds=deck_copies.fetch(c.get_attribute(DICT,'parent_uid','').to_s,[]);next if ds.empty?
   x,y=mst_world_box_center(c)
   hit=ds.select{|d|b=mst_world_box(d);x>=b['x'][0] && x<=b['x'][1] && y>=b['y'][0] && y<=b['y'][1]}
   hit.length==1 ? curb_moves << [c,hit.first] : curb_check << c
  end
 end
 msg="BIM Kimlik Onarımı\n\n#{missing_uids.length} eksik UID, #{id_groups.length} mükerrer fiziksel ID grubu, #{uid_groups.length} mükerrer UID grubu bulundu.\n\nTip ID'lere ve geometriye dokunulmaz. Fiziksel ID/UID benzersizleştirilir ve bağımlılık bilgisi aynı işlem içinde yenilenir."
 unless pairs.empty?
  msg+="\n\nAsıl → kopya (karar yolu):\n"+pairs.first(10).join("\n")+(pairs.length>10 ? "\n… #{pairs.length-10} kopya daha" : '')
  msg+="\nKopyaya yeni UID verilir; asıl UID copied_from_uid olarak saklanır. Kopyanın ilerleme kaydı devralınmış (onaysız) olarak saklanır, durumu 'Planlandı' olur."
  msg+="\nÖnceki devralma kaydı olan kopyada yeni devralma geçmişe eklenir; eski kayıt değişmez."
  msg+="\n#{curb_moves.length} kopya tretuvar kopya döşemeye bağlanacak." unless curb_moves.empty?
  msg+="\nDoğrulanmalı (tretuvar bağı değiştirilmez): "+curb_check.first(10).map{|c|element_visible_id(c)}.join(', ') unless curb_check.empty?
 end
 # ADR-0515 G1: devralınmış ilerleme geçmişi (JSON dizisi) işlem açılmadan doğrulanır; bozuk kayıt ezilmez
 uid_plan.each do |u,own,cps,why|
  cps.each do |c|
   hraw=c.get_attribute(DICT,'progress_inherited_history_json',nil)
   next if hraw.nil? || hraw.to_s.strip.empty?
   hv=(JSON.parse(hraw.to_s) rescue nil)
   return UI.messagebox("#{element_visible_id(c)}: devralınmış ilerleme geçmişi (progress_inherited_history_json) okunamadı; üzerine yazılmadı, onarım yapılmadı.") unless hv.is_a?(Array)
  end
 end
 msg+="\n\nDevam edilsin mi?"
 return unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation('MST BIM Kimlik Onarımı',true)
 renamed=0;uid_fixed=0
 missing_uids.each do |e|
  ensure_uid(e)
  uid_fixed+=1
 end
 # Repair duplicate UIDs: the owner keeps the UID; copies get a stable unique UID and keep the source UID.
 uid_plan.each do |u,own,cps,why|
  cps.each do |e|
   prev_cf=e.get_attribute(DICT,'copied_from_uid',nil);prev_own=e.get_attribute(DICT,'uid_owner_pid',nil)
   nu="MST-#{e.persistent_id}-#{Time.now.to_i}-R"
   e.set_attribute(DICT,'element_uid',nu)
   e.set_attribute(DICT,'copied_from_uid',u);e.set_attribute(DICT,'uid_owner_pid',e.persistent_id)
   pj=e.get_attribute(DICT,'progress_items_json','').to_s
   ps=e.get_attribute(DICT,'progress_status','').to_s
   ps='' if ps=='Planlandı'
   # ADR-0515 G1: önceki devralma kaydı doluysa olayın tamamı geçmişe tek kayıt olarak eklenir; eski tekil alanlar değişmez
   if (!pj.empty? && !e.get_attribute(DICT,'progress_inherited_json',nil).nil?) || (!ps.empty? && !e.get_attribute(DICT,'progress_inherited_status',nil).nil?)
    hraw=e.get_attribute(DICT,'progress_inherited_history_json',nil)
    hist=(hraw.nil? || hraw.to_s.strip.empty?) ? [] : JSON.parse(hraw.to_s)   # ön doğrulamada dizi olduğu denetlendi
    hist << {'v'=>1,'at'=>Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),'source'=>'repair_bim_identity','from_uid'=>u,'new_uid'=>nu,
             'items_json'=>(pj.empty? ? nil : pj),'status'=>(ps.empty? ? nil : ps),'prev_copied_from_uid'=>prev_cf,'prev_uid_owner_pid'=>prev_own}
    e.set_attribute(DICT,'progress_inherited_history_json',JSON.generate(hist))
    e.delete_attribute(DICT,'progress_items_json') unless pj.empty?
    e.set_attribute(DICT,'progress_status','Planlandı') unless ps.empty?
   else
    if !pj.empty? && e.get_attribute(DICT,'progress_inherited_json',nil).nil?
     e.set_attribute(DICT,'progress_inherited_json',pj);e.delete_attribute(DICT,'progress_items_json')
    end
    if !ps.empty? && e.get_attribute(DICT,'progress_inherited_status',nil).nil?
     e.set_attribute(DICT,'progress_inherited_status',ps);e.set_attribute(DICT,'progress_status','Planlandı')
    end
   end
   uid_fixed+=1
  end
 end
 curb_moves.each{|c,d|c.set_attribute(DICT,'parent_uid',d.get_attribute(DICT,'element_uid','').to_s)}
 # Physical IDs are unique per element type. Keep the first occurrence and renumber only duplicates.
 used_by_type=Hash.new{|h,k|h[k]={}}
 elems.each{|e|id=element_visible_id(e);used_by_type[e.get_attribute(DICT,'element_type','').to_s][id]=true unless id.start_with?('PID-')}
 id_groups.each do |(t,old_id),arr|
  key=mst_identity_id_key(t);next unless key
  prefix=bim_type_prefix(t)
  (arr-[id_owner[[t,old_id]] || arr.first]).each do |e|   # asıl öğe (mst_uid_owner) kendi ID'sini korur
   nid=mst_next_unique_physical_id(prefix,used_by_type[t]);used_by_type[t][nid]=true
   e.set_attribute(DICT,key,nid);e.name=nid if e.respond_to?(:name=)
   renamed+=1
  end
 end
 # Refresh dependency UID/ID metadata without opening a nested SketchUp operation.
 if respond_to?(:mst_all_elements)
  dep_all=mst_all_elements
  _ga,gch,gpa,_gu=dependency_graph(Sketchup.active_model,dep_all)   # ADR-0515 G7: grafik kimlik yazımlarından sonra bir kez (döngüdeki yazımlar grafik girdisi değil)
  # ADR-0515 G7 ayrı öneri: ara dependency_* / '2.1' yazımı kaldırıldı — commit_with_dependencies (aşağıda) aynı işlemde son değerleri
  # ('2.2') yazar. Bağlı öğelerde eksik UID üretimi (ensure_uid) aynı sırayla korunur; işlem sonundaki öznitelikler aynıdır.
  dep_all.each do |e|
   gch[e].each{|x|ensure_uid(x)};gpa[e].each{|x|ensure_uid(x)}
  end
 end
 model.set_attribute(DICT,'identity_repair_revision','v0.21.1');commit_with_dependencies(model)
 UI.messagebox("BIM Kimlik Onarımı tamamlandı.\n\n#{renamed} fiziksel Eleman ID yeniden numaralandırıldı.\n#{uid_fixed} eksik/mükerrer UID onarıldı.#{curb_moves.empty? ? '' : "\n#{curb_moves.length} kopya tretuvar kopya döşemeye bağlandı."}\nTip ID ve geometri korunmuştur.\n\nİşlemin tamamı tek Ctrl+Z ile geri alınabilir.")
 model_audit
rescue=>ex
 model.abort_operation rescue nil;UI.messagebox("BIM Kimlik Onarımı hatası: #{ex.message}")
end

def repair_deck_bim_relationships(show_message=true)
  model=Sketchup.active_model
  all=[]; collect_elements(model.entities,all)
  beams=all.select{|e|e.respond_to?(:get_attribute)&&e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
  decks=all.select{|e|e.respond_to?(:get_attribute)&&e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
  project=model.get_attribute(DICT,'project_name','').to_s
  ano=model.get_attribute(DICT,'active_ano','').to_s
  tol=5.mm
  repaired=0; unresolved=[]
  model.start_operation('MST Döşeme BIM İlişki Onarımı',true)
  decks.each do |d|
    db=d.bounds
    bottom=d.get_attribute(DICT,'bottom_elevation_m',db.min.z/1.m).to_f.m
    # A supporting HB must overlap the deck footprint and have its top at deck bottom.
    supports=beams.select do |b|
      bb=b.bounds
      xy=(bb.max.x>=db.min.x-tol && bb.min.x<=db.max.x+tol && bb.max.y>=db.min.y-tol && bb.min.y<=db.max.y+tol)
      zclose=(bb.max.z-bottom).abs <= 25.mm
      xy && zclose
    end
    # Fallback for legacy models: use precast support PIDs found physically inside deck footprint.
    if supports.empty?
      prec=all.select{|e|%w[flat_precast channel_precast crane_precast].include?(e.get_attribute(DICT,'element_type','').to_s)}
      pids=[]
      prec.each do |p|
        pb=p.bounds
        inside=(pb.max.x>=db.min.x-tol && pb.min.x<=db.max.x+tol && pb.max.y>=db.min.y-tol && pb.min.y<=db.max.y+tol)
        if inside
          pids << p.get_attribute(DICT,'support_left_pid',0).to_i << p.get_attribute(DICT,'support_right_pid',0).to_i
        end
      end
      pids=pids.reject{|x|x==0}.uniq
      supports=beams.select{|b|pids.include?(b.persistent_id)}
    end
    if supports.empty?
      unresolved << element_visible_id(d); next
    end
    # Sort by existing axis number when available; otherwise by dominant XY position.
    supports.sort_by! do |b|
      ax=b.get_attribute(DICT,'axis','').to_s[/\d+/].to_i
      ax>0 ? [0,ax] : [1,b.bounds.center.x.to_f+b.bounds.center.y.to_f]
    end
    pids=supports.map{|b|b.persistent_id}; uids=supports.map{|b|ensure_uid(b)}
    d.set_attribute(DICT,'support_pids',pids.join(',')); d.set_attribute(DICT,'support_uids',uids.join(',')); d.set_attribute(DICT,'support_count',supports.length)
    axs=supports.map{|b|b.get_attribute(DICT,'axis','').to_s}.reject(&:empty?)
    unless axs.empty?
      d.set_attribute(DICT,'first_axis',axs.first); d.set_attribute(DICT,'last_axis',axs.last)
      d.set_attribute(DICT,'axis_span',"#{axs.first} ↔ #{axs.last}"); d.set_attribute(DICT,'axis',axs.join(','))
    end
    d.set_attribute(DICT,'project',project) unless project.empty?
    d.set_attribute(DICT,'ano',ano) unless ano.empty?
    d.set_attribute(DICT,'zone',ano) unless ano.empty?
    repaired+=1
  end
  # v0.32.7: also repair curb/trottoir -> parent deck links. Prefer explicit parent_deck_id;
  # otherwise accept only a unique geometric deck match to avoid inventing dependencies.
  curbs=all.select{|e|e.respond_to?(:get_attribute)&&e.get_attribute(DICT,'element_type','').to_s=='curb'}
  curb_repaired=0; curb_unresolved=[]
  curbs.each do |c|
    next unless c.get_attribute(DICT,'parent_uid','').to_s.strip.empty?
    parent_id=c.get_attribute(DICT,'parent_deck_id','').to_s.strip
    candidates=parent_id.empty? ? [] : decks.select{|d| d.get_attribute(DICT,'deck_id','').to_s==parent_id || element_visible_id(d).to_s==parent_id}
    if candidates.empty?
      cb=c.bounds
      candidates=decks.select do |d|
        db=d.bounds
        xy=(cb.center.x>=db.min.x-tol && cb.center.x<=db.max.x+tol && cb.center.y>=db.min.y-tol && cb.center.y<=db.max.y+tol)
        zclose=(cb.min.z-db.max.z).abs<=150.mm || (cb.max.z-db.max.z).abs<=150.mm
        xy && zclose
      end
    end
    if candidates.length==1
      d=candidates.first; uid=ensure_uid(d)
      c.set_attribute(DICT,'parent_uid',uid); c.set_attribute(DICT,'parent_deck_uid',uid)
      c.set_attribute(DICT,'parent_deck_id',element_visible_id(d)) if parent_id.empty?
      c.set_attribute(DICT,'dependency_parent_uids',uid); c.set_attribute(DICT,'dependency_parent_ids',element_visible_id(d))
      curb_repaired+=1
    else
      curb_unresolved << element_visible_id(c)
    end
  end
  refresh_dependency_metadata_inline
  model.set_attribute(DICT,'deck_relationship_revision','v0.32.7')
  commit_with_dependencies(model)
  if show_message
    msg="Döşeme BIM İlişki Onarımı tamamlandı.\n\n#{repaired} döşeme ilişkilendirildi.\n#{curb_repaired} tretuvar/bordür ana döşemeye bağlandı."
    msg+="\n#{unresolved.length} döşeme çözülemedi: #{unresolved.join(', ')}" unless unresolved.empty?
    msg+="\n#{curb_unresolved.length} tretuvar/bordür güvenilir tek parent ile eşleşmedi: #{curb_unresolved.join(', ')}" unless curb_unresolved.empty?
    msg+="\n\nGeometri değiştirilmedi. İşlem tek Ctrl+Z ile geri alınabilir."
    UI.messagebox(msg)
  end
  {repaired:repaired,unresolved:unresolved}
rescue=>ex
  model.abort_operation rescue nil
  UI.messagebox("Döşeme BIM İlişki Onarımı hatası: #{ex.message}") if show_message
  {repaired:0,unresolved:decks ? decks.map{|d|element_visible_id(d)} : []}
end

# v0.37.0j: reconcile BK Type IDs against current physical geometry signatures.
def mst_sync_bk_type_library(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 beams=all.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 groups=beams.group_by{|e|element_signature(e)}
 used=all.map{|e|e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s}.reject(&:empty?).uniq
 reserved={}
 # Assign the old Type ID to the largest unchanged geometry group first.
 groups.sort_by{|sig,items|[-items.length,sig]}.each do |sig,items|
  candidate=items.find{|e|e.get_attribute(DICT,'type_signature','').to_s==sig && !e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s.empty? && !reserved.value?(e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s)}
  reserved[sig]=candidate.get_attribute(DICT,'type_id',candidate.get_attribute(DICT,'library_type_id','')).to_s if candidate
 end
 groups.sort_by{|sig,items|[-items.length,sig]}.each do |sig,items|
  next if reserved[sig]
  candidate=items.map{|e|e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s}.find{|tid|!tid.empty? && !reserved.value?(tid)}
  unless candidate
   begin
    candidate=next_library_type_id(model,'BK')
   end while used.include?(candidate) || reserved.value?(candidate)
   used<<candidate
  end
  reserved[sig]=candidate
 end
 changed=0
 groups.each do |sig,items|
  tid=reserved[sig]
  items.each do |e|
   next if e.get_attribute(DICT,'type_signature','').to_s==sig && e.get_attribute(DICT,'type_id','').to_s==tid && e.get_attribute(DICT,'library_type_id','').to_s==tid
   e.set_attribute(DICT,'type_signature',sig);e.set_attribute(DICT,'type_id',tid);e.set_attribute(DICT,'library_type_id',tid);changed+=1
  end
 end
 changed
end

def mst_repair_bk_type_library
 model=Sketchup.active_model;model.start_operation('MST BK Tip Kütüphanesi Otomatik Eşitleme',true)
 begin
  count=mst_sync_bk_type_library(model);model.commit_operation
  UI.messagebox("BK Tip Otomatik Eşitleme: #{count} kayıt güncellendi. Geometri, metraj ve fiziksel kimlikler korunmuştur.")
 rescue=>e
  model.abort_operation;UI.messagebox("BK Tip Otomatik Eşitleme hatası: #{e.message}")
 end
end

# v0.36.5s: repair only pile and infill Type Library metadata; preserve physical IDs and geometry.
def mst_sync_pile_type_library(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 targets=all.select{|e|e.valid? && %w[steel_pipe_pile pile_infill_concrete].include?(e.get_attribute(DICT,'element_type','').to_s)}
 registry={}
 # Trust a stored Type ID only when the stored signature agrees with current geometry/material.
 targets.each do |e|
  sig=element_signature(e)
  old=e.get_attribute(DICT,'type_signature','').to_s
  tid=e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s.strip
  registry[sig]=tid if old==sig && !tid.empty? && !registry.key?(sig)
 end
 # Infill signatures include concrete class and internal geometry, not only element type.
 targets.each do |e|
  next unless e.get_attribute(DICT,'element_type','').to_s=='pile_infill_concrete'
  sig=mst_pile_infill_signature(e)
  old=e.get_attribute(DICT,'type_signature','').to_s
  tid=e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s.strip
  registry[sig]=tid if old==sig && !tid.empty? && !registry.key?(sig)
 end
 changed=0
 targets.each do |e|
  t=e.get_attribute(DICT,'element_type','').to_s
  sig=t=='pile_infill_concrete' ? mst_pile_infill_signature(e) : element_signature(e)
  tid=registry[sig]
  if tid.to_s.empty?
   tid=next_library_type_id(model,bim_type_prefix(t));registry[sig]=tid
  end
  if e.get_attribute(DICT,'type_signature','').to_s!=sig || e.get_attribute(DICT,'type_id','').to_s!=tid || e.get_attribute(DICT,'library_type_id','').to_s!=tid
   e.set_attribute(DICT,'type_signature',sig)
   e.set_attribute(DICT,'type_id',tid)
   e.set_attribute(DICT,'library_type_id',tid)
   changed+=1
  end
 end
 changed
end

# v0.38 BK4.2: precast canonical type sync (type_id / library_type_id / type_signature).
# Same rule as the pile sync: a stored Type ID is trusted only when its stored signature
# matches current geometry; physical IDs, engineering type names and geometry are untouched.
def mst_sync_precast_type_library(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 targets=all.select{|e|e.valid? && %w[flat_precast channel_precast crane_precast].include?(e.get_attribute(DICT,'element_type','').to_s)}
 registry={}
 targets.each do |e|
  sig=element_signature(e);tid=e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s.strip
  registry[sig]=tid if e.get_attribute(DICT,'type_signature','').to_s==sig && !tid.empty? && !registry.key?(sig)
 end
 changed=0
 targets.each do |e|
  sig=element_signature(e);tid=registry[sig]
  (tid=next_library_type_id(model,bim_type_prefix(e.get_attribute(DICT,'element_type','').to_s));registry[sig]=tid) if tid.to_s.empty?
  next if e.get_attribute(DICT,'type_signature','').to_s==sig && e.get_attribute(DICT,'type_id','').to_s==tid && e.get_attribute(DICT,'library_type_id','').to_s==tid
  e.set_attribute(DICT,'type_signature',sig);e.set_attribute(DICT,'type_id',tid);e.set_attribute(DICT,'library_type_id',tid)
  changed+=1
 end
 changed
end

# v0.38 BK4.3 — "Güvenli Onarım": every metadata-only repair in one step.
# Pile / BK / precast Type Library sync + pipe weights. Geometry, physical IDs and
# engineering type names are never touched. A dry run (rolled back) gives the preview.
def mst_safe_repair_run(model)
  w=0
  collect_piles(model.entities).map{|i|i[0]}.uniq.each do |p|
    next unless p.valid?
    ex=mst_pile_canonical_weight_kg(p);old=p.get_attribute(DICT,'weight_kg',nil)
    next unless old.nil? || (old.to_f-ex).abs>0.01 || (p.get_attribute(DICT,'theoretical_weight_kg',nil).to_f-ex).abs>0.01
    %w[weight_kg theoretical_weight_kg qto_steel_pipe_weight_kg].each{|k|p.set_attribute(DICT,k,ex)};w+=1
  end
  {'pile'=>mst_sync_pile_type_library(model),'bk'=>mst_sync_bk_type_library(model),'precast'=>mst_sync_precast_type_library(model),'weights'=>w}
end

def mst_safe_repair_lines(c)
  ["Kazık / kazık içi beton tip kaydı: #{c['pile']}","BK tip kaydı: #{c['bk']}","Prekast tip kaydı: #{c['precast']}","Kazık boru ağırlığı: #{c['weights']}"]
end

def mst_safe_repair
  model=Sketchup.active_model
  model.start_operation('MST Güvenli Onarım (önizleme)',true)
  begin
    c=mst_safe_repair_run(model)
  ensure
    model.abort_operation
  end
  if c.values.sum==0
    return UI.messagebox("Güvenli Onarım: düzeltilecek kayıt yok.\nKazık, BK ve prekast tip kayıtları ile boru ağırlıkları güncel.")
  end
  msg="Güvenli Onarım — önizleme\n\n"+mst_safe_repair_lines(c).join("\n")+"\n\nYalnız tip kaydı (Tip ID / imza) ve boru ağırlığı düzeltilir.\nGeometri, metraj ölçüleri, fiziksel ID'ler ve tip adları değişmez. Tek Geri Al.\n\nUygulansın mı?"
  return unless UI.messagebox(msg,MB_YESNO)==IDYES
  model.start_operation('MST Güvenli Onarım',true)
  begin
    c=mst_safe_repair_run(model);commit_with_dependencies(model)
  rescue Exception
    model.abort_operation;raise
  end
  UI.messagebox("Güvenli Onarım tamamlandı.\n\n"+mst_safe_repair_lines(c).join("\n"))
rescue=>e
  UI.messagebox("Güvenli Onarım hatası: #{e.message}")
end

def mst_repair_precast_type_library
 model=Sketchup.active_model;model.start_operation('MST Prekast Tip Otomatik Eşitleme',true)
 begin
  count=mst_sync_precast_type_library(model);model.commit_operation
  UI.messagebox("Prekast Tip Otomatik Eşitleme: #{count} prekast güncellendi. Geometri, metraj, fiziksel ID ve tip adları korunmuştur.")
 rescue=>e
  model.abort_operation;UI.messagebox("Prekast Tip Otomatik Eşitleme hatası: #{e.message}")
 end
end

def mst_pile_infill_signature(e)
 ['pile_infill_concrete',e.get_attribute(DICT,'internal_diameter_mm',0).to_f.round(1),
 e.get_attribute(DICT,'height_m',0).to_f.round(3),
 e.get_attribute(DICT,'concrete_class','').to_s].join('|')
end

def mst_repair_pile_type_library
 model=Sketchup.active_model
 model.start_operation('MST Kazık Tip Kütüphanesi Otomatik Eşitleme',true)
 begin
  count=mst_sync_pile_type_library(model)
  model.commit_operation
  UI.messagebox("Kazık Tip Kütüphanesi: #{count} kayıt güncellendi. Geometri ve Kazık ID değiştirilmedi.")
 rescue=>e
  model.abort_operation
  UI.messagebox("Kazık Tip Kütüphanesi eşitleme hatası: #{e.message}")
 end
 model_audit
end

def mst_repair_pile_organization
 model=Sketchup.active_model
 project=model.get_attribute(DICT,'project_name','').to_s.strip
 all=[];collect_elements(model.entities,all)
 piles=all.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
 by_id=piles.each_with_object({}){|e,h|h[e.get_attribute(DICT,'pile_id','').to_s]=e}
 changed=0
 model.start_operation('MST Kazık Düzeni Eşitleme',true)
 begin
  piles.each do |e|
   if !project.empty? && e.get_attribute(DICT,'project','').to_s.strip.empty?
    e.set_attribute(DICT,'project',project);changed+=1
   end
   if e.get_attribute(DICT,'ano','').to_s.strip.empty?
    structure=e.get_attribute(DICT,'structure','').to_s.strip
    e.set_attribute(DICT,'ano',structure) unless structure.empty?
   end
  end
  all.each do |e|
   next unless e.valid? && e.get_attribute(DICT,'element_type','').to_s=='pile_infill_concrete'
   parent=by_id[e.get_attribute(DICT,'pile_id','').to_s]
   next unless parent
   %w[project ano structure system pile_id].each do |key|
    value=parent.get_attribute(DICT,key,'').to_s.strip
    next if value.empty? || e.get_attribute(DICT,key,'').to_s==value
    e.set_attribute(DICT,key,value);changed+=1
   end
  end
  model.commit_operation
  UI.messagebox("Kazık organizasyonu eşlendi: #{changed} metadata alanı güncellendi. BK bağlantıları ve geometri değiştirilmedi.")
 rescue=>e
  model.abort_operation
  UI.messagebox("Organizasyon eşleme hatası: #{e.message}")
 end
 model_audit
end

# ---------------------------------------------------------------------------
# v0.38 BK4 — Geometric BK ↔ pile ↔ precast link audit (read-only; feeds model_audit).
# ---------------------------------------------------------------------------
MST_AUDIT_Z_TOL=0.005
MST_AUDIT_XY_TOL=0.01
MST_IN_PER_M=39.37007874015748

# World X/Y range (m) of a group, following single-instance container parents.
def mst_world_xy_range(e)
  t=Geom::Transformation.new;p=(e.respond_to?(:parent) ? e.parent : nil);guard=0
  while defined?(Sketchup::ComponentDefinition) && p.is_a?(Sketchup::ComponentDefinition) && p.instances.length==1 && (guard+=1)<20
    inst=p.instances[0];t=inst.transformation*t;p=inst.parent
  end
  b=e.bounds;pts=[b.min,b.max].map{|q|q.transform(t)}
  [pts.map{|q|q.x.to_f/MST_IN_PER_M}.minmax,pts.map{|q|q.y.to_f/MST_IN_PER_M}.minmax]
end

# Returns [issues, checks]; issue = [sev, entity, check, message, fix, pids].
def mst_audit_bk_links(elems)
  out=[];checks=0;f3=->(v){format('%.3f',v.to_f)}
  add=->(sev,e,check,msg,fix,pids){out << [sev,e,check,msg,fix,pids]}
  typ=->(e){e.get_attribute(DICT,'element_type','').to_s}
  beams=elems.select{|e|typ[e]=='head_beam'}
  piles={};elems.each{|e|piles[element_visible_id(e)]=e if typ[e]=='steel_pipe_pile'}
  rng={};wr=->(e){rng[e]||=mst_world_xy_range(e)}
  owners=Hash.new{|h,k|h[k]=[]}
  beams.each do |b|
    bid=element_visible_id(b);top=b.get_attribute(DICT,'top_elevation_m',nil);bot=b.get_attribute(DICT,'bottom_elevation_m',nil)
    b.get_attribute(DICT,'connected_pile_ids','').to_s.split(',').map(&:strip).reject(&:empty?).uniq.each do |pid|
      p=piles[pid];next unless p   # missing pile: reported by the existing 'Kazık → BK' check
      owners[pid] << bid
      pt=p.get_attribute(DICT,'top_elevation_m',nil)
      if pt && top && bot
        checks+=1
        if pt.to_f<bot.to_f-MST_AUDIT_Z_TOL
          add.('WARNING',p,'Kazık → BK',"#{pid} başı (#{f3[pt]} m) #{bid} altında kalıyor (BK alt #{f3[bot]} m); kazık BK'ya girmiyor.",'Kazık üst kotunu veya BK kotunu düzeltin (Kazık sayfası › hedef güncelleme BK\'yı birlikte taşır).',[p.persistent_id,b.persistent_id])
        elsif pt.to_f>top.to_f+MST_AUDIT_Z_TOL
          add.('WARNING',p,'Kazık → BK',"#{pid} başı (#{f3[pt]} m) #{bid} üstünden çıkıyor (BK üst #{f3[top]} m).",'Kazık üst kotunu veya BK kotunu düzeltin.',[p.persistent_id,b.persistent_id])
        end
      end
      gx=p.get_attribute(DICT,'global_x_m',nil);gy=p.get_attribute(DICT,'global_y_m',nil)
      next if gx.nil? || gy.nil?
      checks+=1
      bx,by=wr[b]
      tol=p.get_attribute(DICT,'orientation_mode','').to_s=='BATTERED' ? [MST_AUDIT_XY_TOL,p.get_attribute(DICT,'diameter_mm',0).to_f/2000.0].max : MST_AUDIT_XY_TOL
      unless gx.to_f.between?(bx[0]-tol,bx[1]+tol) && gy.to_f.between?(by[0]-tol,by[1]+tol)
        add.('WARNING',p,'Kazık → BK',"#{pid} plan konumu (X #{f3[gx]}, Y #{f3[gy]}) #{bid} izdüşümünün dışında (BK X #{f3[bx[0]]}–#{f3[bx[1]]}, Y #{f3[by[0]]}–#{f3[by[1]]}).",'Kazık veya BK konumunu kontrol edin; kazık taşındıysa BK yeniden oluşturulmalı ya da aks taşıması ile birlikte kaydırılmalı.',[p.persistent_id,b.persistent_id])
      end
    end
  end
  checks+=owners.length
  owners.each do |pid,bs|
    next if bs.uniq.length<=1
    add.('WARNING',piles[pid],'Kazık → BK',"#{pid} birden fazla BK'ya bağlı: #{bs.uniq.join(', ')}.",'BK bağlı kazık listelerini kontrol edin; mükerrer bağ metrajı etkileyebilir.',[piles[pid].persistent_id])
  end
  bpid={};beams.each{|b|bpid[b.persistent_id]=b}
  pre=elems.select{|e|MST_PRECAST_TYPES.include?(typ[e])}
  pre.group_by{|e|[e.get_attribute(DICT,'support_left_pid',0).to_i,e.get_attribute(DICT,'support_right_pid',0).to_i,typ[e]]}.each do |(lp,rp,t),grp|
    l=bpid[lp];r=bpid[rp];next unless l && r && l!=r   # missing support: reported by 'PD/Kanal → BK'
    l,r=[l,r].sort_by{|b|wr[b][0].sum}
    lx,ly=wr[l];rx,ry=wr[r];clear=rx[0]-lx[1];zl=l.get_attribute(DICT,'top_elevation_m',nil)
    span="#{element_visible_id(l)} → #{element_visible_id(r)}"
    bad={len:[],x:[],y:[],z:[]};sample={}
    grp.each do |e|
      seat=e.get_attribute(DICT,'seat_each_side_m',0.15).to_f;len=e.get_attribute(DICT,'length_m',0).to_f
      ex,ey=wr[e];checks+=3
      if (len-(clear+2*seat)).abs>MST_AUDIT_Z_TOL
        bad[:len] << e;sample[:len]||=[len,clear+2*seat]
      elsif (ex[0]-(lx[1]-seat)).abs>MST_AUDIT_Z_TOL || (ex[1]-(rx[0]+seat)).abs>MST_AUDIT_Z_TOL
        bad[:x] << e;sample[:x]||=[ex[0],lx[1]-seat]
      end
      bad[:y] << e if ey[0]<[ly[0],ry[0]].max-MST_AUDIT_XY_TOL || ey[1]>[ly[1],ry[1]].min+MST_AUDIT_XY_TOL
      next if t=='channel_precast' || zl.nil?
      bz=e.get_attribute(DICT,t=='crane_precast' ? 'main_bottom_elevation_m' : 'bottom_elevation_m',nil)
      next if bz.nil?
      checks+=1
      (bad[:z] << e;sample[:z]||=[bz,zl]) if (bz.to_f-zl.to_f).abs>MST_AUDIT_Z_TOL
    end
    pids=->(a){a.map(&:persistent_id)}
    add.('WARNING',bad[:len][0],'PD/Kanal → BK',"#{span}: #{bad[:len].length} prekastın boyu açıklığa uymuyor (boy #{f3[sample[:len][0]]} m, beklenen #{f3[sample[:len][1]]} m = net açıklık + 2 × oturma).","Açıklık aks taşımasıyla değiştiyse Aks Yöneticisi'nde yeniden kaydedin (BK3 otomatik boyutlandırır); değilse bu PD'leri silip yeniden yerleştirin.",pids[bad[:len]]) unless bad[:len].empty?
    add.('WARNING',bad[:x][0],'PD/Kanal → BK',"#{span}: #{bad[:x].length} prekast X yönünde kaymış; oturma payı tutmuyor (başlangıç #{f3[sample[:x][0]]} m, beklenen #{f3[sample[:x][1]]} m).",'PD\'leri iki BK\'ya eşit oturacak şekilde yeniden yerleştirin.',pids[bad[:x]]) unless bad[:x].empty?
    add.('WARNING',bad[:y][0],'PD/Kanal → BK',"#{span}: #{bad[:y].length} prekast BK genişliğinin dışına taşıyor (Y).",'PD yerleşim başlangıcını / genişliklerini kontrol edin.',pids[bad[:y]]) unless bad[:y].empty?
    add.('WARNING',bad[:z][0],'PD/Kanal → BK',"#{span}: #{bad[:z].length} prekastın alt kotu BK üst kotundan farklı (PD alt #{f3[sample[:z][0]]} m, BK üst #{f3[sample[:z][1]]} m).","Prekast sayfasında 'PD Kotlarını BK ile Güncelle' çalıştırın.",pids[bad[:z]]) unless bad[:z].empty?
  end
  pre.group_by{|e|[typ[e],mst_precast_type_id(e)]}.each do |(t,tid),grp|
    next if tid.empty?
    checks+=1
    dims=grp.group_by{|e|mst_precast_dims_key(e)}
    next if dims.length<=1
    lens=dims.keys.map{|k|format('%.3f',k[0]/1000.0)}.uniq
    add.('WARNING',grp.first,'Tip Kütüphanesi',"#{tid}: aynı prekast tip adı #{dims.length} farklı ölçüde kullanılıyor (boy #{lens.join(' / ')} m; #{grp.length} parça).","Prekast sayfasında 'Seçili Prekast Tip Adını Değiştir' ile farklı ölçüleri ayrı adlandırın.",grp.map(&:persistent_id))
  end
  [out,checks]
end

# ===== v0.51.5 — pozsuz bilgi satırları (K33, K39, K40) =====
# Yalnız BOQ ekranında (send_boq) ve Model Kontrolü'nde gösterilir: birim fiyat yok, toplam tutara girmez,
# boq_rows'a eklenmez (hakediş, iş programı, Excel/CSV satırları değişmez). Mühendislik/poz kuralı değiştirmez.
def mst_boq_info_rows(all=nil)
 unless all
  all=[];collect_elements(Sketchup.active_model.entities,all)
 end
 by=->(t){all.select{|e|e.get_attribute(DICT,'element_type','').to_s==t}}
 out=[]
 info=->(name,unit,qty,src,note){out << {code:'BİLGİ',name:name,unit:unit,quantity:qty,unit_price:nil,total:nil,source:src,
  status:'BİLGİ · POZSUZ (toplama girmez)',library_price:true,info_only:true,mapping_reason:note,trace:{count:0,items:[]}}}
 # K33: PRECAST_C35_45 / CAST_C35_45_OTHER yalnız C35/45 alır (boq_quantities); diğer sınıflar hiçbir beton pozunda yok
 [['Prekast',by.('flat_precast')+by.('channel_precast')+by.('crane_precast'),' Montaj pozunda (PRECAST_INSTALL) var.'],['Bordür',by.('curb'),'']].each do |grp,es,extra|
  es.reject{|e|qto_material_class(e).to_s.upcase.gsub(' ','')=='C35/45'}.group_by{|e|c=qto_material_class(e).to_s.strip;(c.empty? || c=='-') ? 'belirtilmemiş' : c}.sort.each do |cls,xs|
   q=xs.sum{|e|qto3_quantity(e,:concrete_m3)};next if q<=1e-9
   info.("Poz eşlenmemiş beton: #{format('%.3f',q)} m³ (#{grp}, sınıf #{cls}; #{xs.length} eleman)",'m³',q,"INFO:UNMAPPED_CONCRETE##{grp}##{cls}",
    "C35/45 beton pozu yalnız C35/45 sınıfını alır; bu hacim hiçbir beton pozunda yok.#{extra} Poz/sınıf eşlemesi için proje poz listesi gerekli.")
  end
 end
 # K39: tapa ağırlığı hesaplanıyor (pile_fabrication_qto_row) ama hiçbir pozda değil
 pr=pile_fabrication_qto_row(by.('steel_pipe_pile'),'TOPLAM',true)
 if pr && pr[8].to_f>1e-9
  info.("Kazık tapası (pozsuz): #{pr[4].to_i} adet, #{format('%.1f',pr[8].to_f*1000.0)} kg",'kg',pr[8].to_f*1000.0,'INFO:PILE_PLUG',
   'Tapa ağırlığı hiçbir keşif pozuna girmiyor (kazık çeliği ve manipülasyon dahil değil). Tarif/poz belgesi gerekli.')
 end
 # K40: paftadan / çizimden 3B donatıda yerleştirilemeyen pozlar — tonajı pafta tablosundan REBAR'a girer
 n_el=0;n_poz=0;kg=0.0
 all.each do |e|
  next unless e.get_attribute(DICT,'rebar_mode','').to_s=='drawing_detail' && e.get_attribute(DICT,'rebar_kind','').to_s=='DRAWING'
  sch=(JSON.parse(e.get_attribute(DICT,'rebar_schedule_json','{}').to_s) rescue {})
  next unless sch.is_a?(Hash)
  miss=sch.values.select{|v|v.is_a?(Hash) && v.key?('drawn') && v['drawn'].to_i<=0 && v['count'].to_i>0}
  next if miss.empty?
  n_el+=1;n_poz+=miss.length;kg+=miss.sum{|v|v['kg'].to_f}
 end
 if kg>1e-9
  info.("Donatı — 3B'ye yerleştirilemeyen pozlar: #{n_poz} poz / #{n_el} eleman, #{format('%.3f',kg/1000.0)} t",'t',kg/1000.0,'INFO:REBAR_UNPLACED',
   'Bu tonaj pafta donatı tablosundan ÖBF-004 donatı miktarına DAHİLDİR; modelde 3B çubuğu yoktur (bilgi, ek miktar değil).')
 end
 out
rescue => ex
 [{code:'BİLGİ',name:"Bilgi satırları hesaplanamadı: #{ex.message}",unit:'',quantity:0.0,unit_price:nil,total:nil,source:'INFO:ERROR',
   status:'BİLGİ · HATA',library_price:true,info_only:true,trace:{count:0,items:[]}}]
end

# ===== v0.51.5 G3 (ADR-0515 §11) — yazılıp okunmayan hata bayrakları ve hesap sınırları Model Kontrolü'nde =====
# {anahtar => [seviye, ileti, öneri]}; B partisi (K22, K23, K53) bu sabite / işleve ekler.
MST_AUDIT_ERROR_FLAGS={
 'pile_rebar_error'=>['ERROR','Kazık donatı kafesi hesaplanamadı (%s). Kazık donatısı iç beton × pursantaj ile sayılıyor.','Kazık İçi Donatı parametrelerini ve iç beton kotlarını kontrol edip kafesi yeniden uygulayın.'],
 'pc_rebar_error'=>['ERROR','Prekast donatısı çizilemedi (%s). Donatı pursantajla sayılıyor.','Prekast Donatısı → ÇİZ ile yeniden çizin (Component ise önce parçayı ayırın).'],
 'rebar_restore_error'=>['WARNING','%s — BK donatısı pursantajla sayılıyor; önceki kayıt korundu.','BK donatısını yeniden oluşturun (BIM Donatı / Çizimden Donatı).'],
 'culvert_error'=>['ERROR','Menfez: %s','Menfez → EKLE / TEMİZLE ile yeniden uygulayın.'],
 'formwork_net_error'=>['WARNING','Net kalıp alanı güncellenemedi (%s); kayıtlı net kalıp eski değerde kalmış olabilir.','BK kalıp yüzlerini kontrol edip BK\'yı yeniden oluşturun / revize edin.']   # v0.51.5 K18
}.freeze
# v0.51.5 K23: dönüşümün eksen ölçekleri ve aynalama (SketchUp Transformation#to_a: 16 değer, sütun sıralı). Salt okuma.
def mst_tr_scale_info(t)
 a=t.to_a.map(&:to_f);w=a[15].abs<1e-12 ? 1.0 : a[15]
 s=[a[0..2],a[4..6],a[8..10]].map{|v|Math.sqrt(v.sum{|x|x*x})/w}
 det=a[0]*(a[5]*a[10]-a[6]*a[9])-a[4]*(a[1]*a[10]-a[2]*a[9])+a[8]*(a[1]*a[6]-a[2]*a[5])
 [s,det<0]
end
# v0.51.5 H7: BK yerel çerçevesinde (m; x boy, y en, z ana gövde tabanı = 0, diş z<0 — mst_cv_plan ve K50 ile aynı) kazık gömülme
# zarfı ile menfez kutusu (cv_box_json) örtüşmesi. Zarf: plan kare ± d/2·√(1+r²) (eğik kazıkta elipsin büyük ekseni; temkinli),
# düşey [−taban derinliği, −taban derinliği + gömülme]. Salt okuma.
def mst_cv_embed_overlap?(b,it)
 return false unless it[:axis_a_m] && it[:axis_y_m]
 boxes=mst_hb_culvert_groups(b).map{|g|(JSON.parse(g.get_attribute(DICT,'cv_box_json','[]').to_s) rescue [])}.select{|x|x.is_a?(Array) && x.length==6}
 return false if boxes.empty?
 rr=it[:diameter_mm].to_f/2000.0*Math.sqrt(1.0+it[:batter].to_f**2)
 z0=-it[:bottom_depth_m].to_f;z1=z0+it[:embed_m].to_f
 a=it[:axis_a_m].to_f;c=it[:axis_y_m].to_f
 boxes.any?{|x0,y0,bz0,x1,y1,bz1|[x0,x1].min.to_f<a+rr-1e-6 && [x0,x1].max.to_f>a-rr+1e-6 && [y0,y1].min.to_f<c+rr-1e-6 && [y0,y1].max.to_f>c-rr+1e-6 && [bz0,bz1].min.to_f<z1-1e-6 && [bz0,bz1].max.to_f>z0+1e-6}
end
# v0.51.5 H8: eski (v0.34, create_deck_curbs) tretuvarlarda köşe bindirmesi — uzun kenar (taraf 1/2: u boyunca, ofsetli) ile uç
# (taraf 3/4: tam genişlik) tretuvarları köşede üst üste. by: taraf => tretuvar. Tahmini hacim (m³) ve bindiren taraf çiftleri.
# Ofset 0'da 4·w²·h. Kayıtlı değer düzeltilmez (kullanıcı kararı); salt okuma.
def mst_curb_corner_overlap(by)
 v=0.0;pairs=[]
 [['1','3'],['1','4'],['2','3'],['2','4']].each do |s,t|
  a=by[s];b=by[t];next unless a && b
  os=a.get_attribute(DICT,'start_offset_m',0).to_f;oe=a.get_attribute(DICT,'end_offset_m',0).to_f
  du=b.get_attribute(DICT,'length_m',0).to_f-(t=='3' ? os : oe)    # uç tretuvarın u genişliği − uzun kenarın o uçtaki ofseti
  dv=a.get_attribute(DICT,'width_m',0).to_f-(s=='1' ? os : oe)     # uzun kenarın v genişliği − uç tretuvarın o kenardaki ofseti
  h=[a.get_attribute(DICT,'height_m',0).to_f,b.get_attribute(DICT,'height_m',0).to_f].min
  next unless du>1e-9 && dv>1e-9 && h>0
  v+=du*dv*h;pairs << "#{s}/#{t}"
 end
 [v,pairs]
end
# => [[sev,e,check,msg,fix,pids], ...]  Salt okuma.
def mst_audit_v0515(elems,all=elems)
 out=[]
 elems.each do |e|
  MST_AUDIT_ERROR_FLAGS.each do |key,(sev,msg,fix)|
   v=e.get_attribute(DICT,key,'').to_s.strip
   next if v.empty?
   next if key=='pile_rebar_error' && !mst_pile_rebar_active(e)
   out << [sev,e,'Hesap Hatası',"#{element_visible_id(e)}: #{format(msg,v)}",fix,[e.persistent_id]]
  end
 end
 # K50: kazık ayak izi taban derinliği değişimini kesiyorsa (diş / bölge sınırı ya da eğimli geçiş)
 elems.select{|b|b.get_attribute(DICT,'element_type','').to_s=='head_beam'}.each do |b|
  h=nil
  emb=mst_bk_pile_embed(b)
  # ADR-0515 G3-#13: hesap hatası sessiz 0 değil; derinlik hatası ve kazık orijini kuşkusu uyarı
  out << ['ERROR',b,'Hesap Hatası',"#{element_visible_id(b)}: BK gömülme düşümü hesaplanamadı (#{emb[:error]}); BK betonu brüt alındı.",'BK ve bağlı kazıkların kot / çap / konum bilgisini kontrol edip Model Kontrolü\'nü yeniden çalıştırın.',[b.persistent_id]] if emb[:error]
  next unless b.is_a?(Sketchup::Group)
  emb[:items].each do |it|
   if it[:depth_error]
    out << ['WARNING',b,'Hesap Hatası',"#{element_visible_id(b)}: #{it[:pile_id]} kazığında taban derinliği hesaplanamadı (#{it[:depth_error]}); gömülme ana taban kotundan alındı.",'Diş / taban bölgesi kaydını kontrol edin; gerekirse gömülme düşümünü elle doğrulayın.',[b.persistent_id,it[:pid]]]
   end
   if it[:axis_y_m] && (it[:axis_y_m]< -1e-6 || it[:axis_y_m]>it[:width_m].to_f+1e-6 || (it[:origin_z_m].to_f-it[:pile_top_m].to_f).abs>0.01)
    out << ['WARNING',b,'Hesap Hatası',"#{element_visible_id(b)}: #{it[:pile_id]} kazık orijini kazık başı merkezi olmayabilir; gömülme derinliği doğrulanmalı.",'Kazığın konumunu ve üst kotunu kontrol edin; gerekirse gömülme düşümünü elle doğrulayın.',[b.persistent_id,it[:pid]]]
   end
   # v0.51.5 H7: menfez kutusu ile kazık gömülme zarfı planda ve düşeyde örtüşüyor (yalnız uyarı; hacim düzeltmesi belge gerekli)
   if mst_cv_embed_overlap?(b,it)
    out << ['WARNING',b,'Hesap Hatası',"#{element_visible_id(b)}: menfez ile #{it[:pile_id]} kazığının gömülmesi kesişiyor; kesişim hacmi BK betonundan iki kez düşülmüş olabilir (menfez boşluğu ve kazık gömülmesi).",'Kesişim hacmini elle doğrulayın; hacim otomatik düzeltilmez (belge gerekli).',[b.persistent_id,it[:pid]]]
   end
   a=it[:axis_a_m];next if a.nil?
   h||=mst_attr_hash(b);len=h['length_m'].to_f;rad=it[:diameter_mm].to_f/2000.0
   pts=[a-rad,a,a+rad]+mst_hb_zone_segments(h,len).flat_map{|q|[q['a0'],q['f0'],q['f1'],q['a1']]}.select{|x|x>a-rad && x<a+rad}
   ds=pts.map{|x|mst_hb_bottom_depth(h,len,x)}
   next unless ds.max-ds.min>1e-6
   out << ['WARNING',b,'Hesap Hatası',"#{element_visible_id(b)}: #{it[:pile_id]} kazığının ayak izi taban derinliği değişimini (diş / taban bölgesi sınırı) kesiyor; gömülme kazık eksenindeki taban kotundan hesaplandı.",'Kazık konumunu ve diş / bölge sınırını kontrol edin; gerekirse gömülme düşümünü elle doğrulayın.',[b.persistent_id,it[:pid]]]
  end
 end
 # ---- v0.51.5 Parti B (yalnız uyarı / hata satırı; metraj ve model değişmez)
 typ=->(e){e.get_attribute(DICT,'element_type','').to_s}
 by_pid={};all.each{|e|by_pid[e.persistent_id]=e if e.respond_to?(:persistent_id)}
 # K22 aşama 1: döndürülmüş BK'lar arasındaki mevcut prekastın boyu model X'inde ölçülmüştü
 elems.select{|e|%w[flat_precast channel_precast crane_precast].include?(typ[e])}.each do |p|
  bs=%w[support_left_pid support_right_pid].map{|k|by_pid[p.get_attribute(DICT,k,0).to_i]}.compact.select{|b|typ[b]=='head_beam'}.uniq
  er=bs.map{|b|mst_bk_span_frame_error(b)}.compact.first;next unless er
  out << ['WARNING',p,'PD/Kanal → BK',"#{element_visible_id(p)}: dayandığı #{er.sub(/ Prekast oluşturulmadı\.\z/,'')} Bu prekastın boyu ve metrajı yanlış olabilir.",'Prekast boyunu elle doğrulayın; BK yerel ekseninde ölçüm (aşama 2) henüz yok.',[p.persistent_id]+bs.map(&:persistent_id)]
 end
 # K23: ölçekli / aynalı dönüşüm zinciri — metraj öznitelikten okunur, ölçek uygulanmaz
 elems.each do |e|
  next unless e.respond_to?(:transformation) && e.transformation
  s,mir=mst_tr_scale_info(mst_rt_world_tr(e))
  next unless mir || s.any?{|v|(v-1.0).abs>1e-4}
  out << ['WARNING',e,'Hesap Hatası',format('%s: dönüşüm zincirinde ölçek (X×%.4f, Y×%.4f, Z×%.4f)%s var. Metraj öznitelikten okunur, ölçek uygulanmaz; geometri ile metraj uyuşmayabilir.',element_visible_id(e),s[0],s[1],s[2],mir ? ', aynalama' : ''),'Ölçeği / aynalamayı geri alın veya elemanı MST araçlarıyla yeniden oluşturun.',[e.persistent_id]]
 end
 # K10 ara çözüm: VK / BBK oluşturulduktan sonra dayandığı BK değişti (revizyon / üst kot / konum)
 elems.select{|v|typ[v]=='head_beam' && %w[VK BBK].include?(v.get_attribute(DICT,'beam_role','').to_s)}.each do |v|
  st=(JSON.parse(v.get_attribute(DICT,'link_support_state_json','').to_s) rescue nil);next unless st.is_a?(Array)
  st.each do |pid,rev,top,ox,oy|
   b=by_pid[pid.to_i]
   unless b && b.valid?
    out << ['WARNING',v,'Bağımlılık Ağı',"#{element_visible_id(v)}: dayandığı BK (PID #{pid}) modelde bulunamadı; vinç / boylama kirişi güncel olmayabilir.",'VK / BBK\'yı yeniden oluşturun.',[v.persistent_id]];next
   end
   cur=mst_vk_support_state(b);why=[]
   why << format('revizyon RV-%02d → RV-%02d',rev.to_i,cur[1]) if cur[1]>rev.to_i
   why << format('üst kot %.3f → %.3f m',top.to_f,cur[2]) if (cur[2]-top.to_f).abs>0.001
   why << format('konum %.3f m kaydı',Math.hypot(cur[3]-ox.to_f,cur[4]-oy.to_f)) if Math.hypot(cur[3]-ox.to_f,cur[4]-oy.to_f)>0.001
   next if why.empty?
   out << ['WARNING',v,'Bağımlılık Ağı',"#{element_visible_id(v)}: dayandığı #{element_visible_id(b)} oluşturulduktan sonra değişti (#{why.join(', ')}); VK / BBK BK'yı izlemez, geometri ve metrajı eski olabilir.",'VK / BBK\'yı silip yeniden oluşturun veya ölçülerini elle doğrulayın.',[v.persistent_id,b.persistent_id]]
  end
 end
 # K53: kaplama, döşeme revizyonundan eski (fiziksel kaplama yeniden kurulmaz); K52: kaplama durumu kayıtlı olmayan eski döşeme
 decks=all.select{|e|typ[e]=='deck_slab'}
 (mst_collect_toppings(Sketchup.active_model.entities) rescue []).each do |t|
  r0=t.get_attribute(DICT,'parent_deck_revision_no',nil);next if r0.nil?
  d=mst_topping_parent_deck(t,decks);next unless d
  r1=d.get_attribute(DICT,'deck_revision_no',0).to_i;next unless r1>r0.to_i
  out << ['WARNING',t,'Döşeme Metrajı',format('%s kaplaması döşeme RV-%02d için oluşturuldu; döşeme şimdi RV-%02d. Fiziksel kaplama yeniden kurulmaz; geometrisi eski olabilir (metraj döşemenin kaplama alanından).',element_visible_id(d),r0.to_i,r1),'Kaplamayı silip Kaplama Ekle ile yeniden oluşturun.',[t.persistent_id,d.persistent_id]]
 end
 decks.select{|d|d.get_attribute(DICT,'topping_enabled',nil).nil?}.each do |d|
  out << ['WARNING',d,'Döşeme Metrajı',"#{element_visible_id(d)}: kaplama durumu kayıtlı değil (eski döşeme). Keşif kaplamayı bu döşemede 0,10 m ile sayıyor; metraj raporu kaplama satırı göstermiyor.",'Kaplama varsa Kaplama Ekle / Kaplama Eğimi ile kaydedin; yoksa döşemeyi yeniden oluşturun. (Belge: kaplama niyeti)',[d.persistent_id]]
 end
 # ADR-0515 G4: gövdesinde bordür betonu olan döşemeye ayrıca ayrı bordür öğesi bağlı → bordür betonu ve donatısı iki kez sayılır (yalnız uyarı)
 curbs=all.select{|e|typ[e]=='curb'}
 decks.select{|d|d.get_attribute(DICT,'curb_volume_m3',0).to_f>0}.each do |d|
  du=d.get_attribute(DICT,'element_uid','').to_s;did=element_visible_id(d)
  cs=curbs.select{|c|pu=c.get_attribute(DICT,'parent_uid','').to_s;pu.empty? ? c.get_attribute(DICT,'parent_deck_id','').to_s==did : (!du.empty? && pu==du)}
  next if cs.empty?
  out << ['WARNING',d,'Döşeme Metrajı',format('%s: döşeme gövdesinde bordür betonu var (%.3f m³) ve döşemeye ayrıca %d ayrı bordür / tretuvar öğesi bağlı (%s). Bordür betonu ve donatısı iki kez sayılıyor olabilir.',did,d.get_attribute(DICT,'curb_volume_m3',0).to_f,cs.length,cs.first(10).map{|c|element_visible_id(c)}.join(', ')),'Ayrı bordür öğelerinin döşeme gövdesindeki bordürle aynı olup olmadığını kontrol edin; aynıysa birini kaldırın.',[d.persistent_id]+cs.map(&:persistent_id)]
 end
 # v0.51.5 H8: eski (v0.34) tretuvar köşe bindirmesi (yalnız uyarı; kayıtlı değer düzeltilmez)
 curbs.uniq.select{|c|%w[1 2 3 4].include?(c.get_attribute(DICT,'side','').to_s)}.group_by{|c|c.get_attribute(DICT,'parent_deck_id','').to_s}.each do |did,cs|
  next if did.empty?
  v,pairs=mst_curb_corner_overlap(cs.group_by{|c|c.get_attribute(DICT,'side','').to_s}.transform_values(&:first))
  next unless v>1e-9
  out << ['WARNING',cs.first,'Tretuvar Metrajı',format('%s: eski (v0.34) tretuvarlar köşelerde üst üste biniyor (taraf %s); tahmini bindirme hacmi %.3f m³. Bu beton (ve hacimden hesaplanan donatısı) iki kez sayılıyor olabilir; kayıtlı değer düzeltilmez.',did,pairs.join(', '),v),'Bindirme hacmini metrajda elle doğrulayın (köşe başına uç tretuvar genişliği × uzun kenar genişliği × yükseklik, ofset düşülerek).',cs.map(&:persistent_id)]
 end
 # v0.51.5 H8: çok kopyalı sarmalayıcı Component içindeki MST öğesi taramada N kez görünür → Keşif N kez, iz / hakediş (.uniq) 1 kez sayar
 all.group_by(&:itself).select{|_,v|v.length>1}.group_by{|_,v|v.length}.each do |n,grp|
  es=grp.map(&:first)
  out << ['WARNING',es.first,'Keşif → Hakediş',"#{es.length} MST öğesi çok kopyalı bir sarmalayıcı Component içinde #{n} kez yer alıyor (#{es.first(8).map{|e|element_visible_id(e)}.join(', ')}#{es.length>8 ? ' …' : ''}). Keşif bu öğeleri #{n} kez, hakediş 1 kez sayar.",'Sarmalayıcıyı patlatın veya benzersiz yapın (Make Unique).',es.map(&:persistent_id)]
 end
 # v0.51.5 H9 (BİLGİ; kural belge gerekli, metraj değişmez)
 elems.select{|e|typ[e]=='head_beam'}.uniq.each do |b|
  next if b.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'
  sch=(JSON.parse(b.get_attribute(DICT,'rebar_schedule_json','').to_s) rescue nil)
  next unless sch.is_a?(Hash) && sch.keys.any?{|k|k.to_s=~/CHAIR|SEHPA/i}
  out << ['WARNING',b,'BK Metrajı',"Bilgi: #{element_visible_id(b)} donatı çizelgesinde sehpa (CHAIR / SEHPA) satırı var, ancak donatı BIM detay değil; sehpa ayrı satıra taşınmaz ve BK donatısından düşülmez.",'Bilgi: sehpanın BK donatısı içinde mi ayrıca mı sayılacağı belgeyle doğrulanmalı.',[b.persistent_id]]
 end
 decks.uniq.select{|d|%w[drawing_detail auto_detail].include?(d.get_attribute(DICT,'rebar_mode','').to_s) && %w[1 true].include?(d.get_attribute(DICT,'topping_enabled','').to_s)}.each do |d|
  out << ['WARNING',d,'Döşeme Metrajı',"Bilgi: #{element_visible_id(d)} donatısı paftadan / otomatik ve döşemede kaplama var; çizelge kaplama hasırını içeriyorsa kaplama donatısı ayrıca sayılıyor olabilir.",'Bilgi: pafta çizelgesinde kaplama hasırı olup olmadığını kontrol edin (kural belge gerekli).',[d.persistent_id]]
 end
 # K54: PV diş < oturma (yalnız uyarı)
 elems.select{|e|typ[e]=='crane_precast'}.each{|e|mst_pv_tooth_seat_warnings(e).each{|w|out << ['WARNING',e,'Prekast Metrajı',w,'Diş boyunu oturma boyuna eşit / büyük seçin ya da kesişimi elle düşün.',[e.persistent_id]]}}
 # K21 (S7 / S8): sessiz 0 yerine görünür hata
 elems.select{|e|typ[e]=='steel_pipe_pile'}.each do |p|
  begin
   pile_bim_qto_item(p)
  rescue => ex
   out << ['ERROR',p,'Hesap Hatası',"#{element_visible_id(p)}: kazık imalat / iç beton metrajı hesaplanamadı (#{ex.message}); hakediş ilerleme miktarı 0 sayılıyor.",'Kazık kesit ve iç beton kotlarını kontrol edin.',[p.persistent_id]]
  end
 end
 begin
  accessory_rows if respond_to?(:accessory_rows)
 rescue => ex
  out << ['ERROR',nil,'Hesap Hatası',"Aksesuar listesi okunamadı (#{ex.message}); aksesuar ankraj donatısı 0 kg sayılıyor.",'Aksesuar kayıtlarını / kütüphanesini kontrol edin.',[]]
 end
 # K33 / K39 / K40: pozsuz bilgi satırları
 mst_boq_info_rows(all).each do |r|
  out << ['WARNING',nil,'Metraj → Keşif',"#{r[:name]} — #{r[:mapping_reason]}",'Bilgi: keşif toplamına girmez; poz eşlemesi için proje poz listesi gerekli.',[]]
 end
 out
end

def model_audit
mst_read_batch do   # v0.51.5 P2: salt okuma, tek model taraması
 model=Sketchup.active_model
 all=[];collect_elements(model.entities,all)
 elems=all.select{|e|%w[steel_pipe_pile pile_infill_concrete head_beam flat_precast channel_precast crane_precast deck_slab deck_topping curb crown_wall bored_pile accessory].include?(e.get_attribute(DICT,'element_type','').to_s)}
 issues=[]; checks=0
 model_project=model.get_attribute(DICT,'project_name','').to_s.strip
 add_issue=lambda{|sev,e,check,msg,fix,pids=nil| issues << {sev:sev,e:e,check:check,msg:msg,fix:fix,pids:pids}}
 by_uid={}; by_pid={}; by_type_id=Hash.new{|h,k|h[k]=[]}; by_visible=Hash.new{|h,k|h[k]=[]}
 elems.each do |e|
  if e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'
   checks+=4
   mst_audit_raw_pile_section(e).each do |message|
    add_issue.call('ERROR',e,'Fiziksel Boru / BIM / Metraj',message,'Boru kesitini ve metraj verisini kontrollü güncelleyin; önce model yedeği alın.')
   end
  end
  if e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile' && e.get_attribute(DICT,'mst_visual_initialized','0').to_s=='1'
   mst_visual_audit_pile(e).each do |message|
    checks+=1
    add_issue.call('WARNING',e,'Fiziksel Detay / Metraj',message,'Kazık fiziksel detaylarını yeniden eşitleyin.')
   end
  end
  checks+=1;uid=e.get_attribute(DICT,'element_uid','').to_s.strip
  add_issue.call('ERROR',e,'BIM Kimliği','Eleman UID eksik.','BIM Veri Çekirdeği ile kimlik bilgilerini standartlaştırın.') if uid.empty?
  if !uid.empty? && by_uid[uid]; own,_why=mst_uid_owner(elems.select{|x|x.get_attribute(DICT,'element_uid','').to_s.strip==uid}); add_issue.call('ERROR',e,'BIM Kimliği',"Mükerrer UID: #{uid} (kopya olası: #{element_visible_id(own==e ? by_uid[uid] : e)})",'BIM Kimlik Onarımı çalıştırın.'); else by_uid[uid]=e unless uid.empty?;end
  by_pid[e.persistent_id]=e
  id=element_visible_id(e);key=[e.get_attribute(DICT,'element_type','').to_s,id];by_visible[key]<<e
  tid=e.get_attribute(DICT,'type_id',e.get_attribute(DICT,'library_type_id','')).to_s.strip;by_type_id[tid]<<e unless tid.empty?
  checks+=1;add_issue.call('WARNING',e,'Tip Kütüphanesi','Tip ID eksik.','Eleman Kütüphanesi ile Tip ID atayın.') if tid.empty?
  # Child organization rule (Audit 4.1d): pile infill concrete inherits Project/Ano from its parent steel pile.
  # It is not an independently organized BIM object. A missing parent is a Dependency issue, not two false Organization warnings.
  et_org=e.get_attribute(DICT,'element_type','').to_s
  if et_org=='pile_infill_concrete'
   parent_pile_id=e.get_attribute(DICT,'pile_id','').to_s.strip
   parent_pile=elems.find do |x|
    x.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile' &&
      (x.get_attribute(DICT,'pile_id','').to_s.strip==parent_pile_id || element_visible_id(x).to_s==parent_pile_id)
   end
   checks+=1
   if parent_pile.nil?
    add_issue.call('WARNING',e,'Bağımlılık Ağı','Kazık içi betonun bağlı olduğu (üst) çelik boru kazığı bulunamadı.','Kazık içi betonu ilgili çelik boru kazığa yeniden bağlayın.')
   else
    checks+=1
    add_issue.call('WARNING',e,'Proje Organizasyonu','Üst kazığın Proje bilgisi eksik.','Model Bakımı → Kazık Organizasyonunu Eşitle ile üst kazığın proje bilgisini model proje adından doldurun.') if !model_project.empty? && parent_pile.get_attribute(DICT,'project','').to_s.strip.empty? && parent_pile.get_attribute(DICT,'project_name','').to_s.strip.empty?
    checks+=1
    add_issue.call('WARNING',e,'Proje Organizasyonu','Üst kazığın Yapı/Ano bilgisi eksik.','Üst kazığın yapı (structure) veya ano bilgisini kontrol edin.') if parent_pile.get_attribute(DICT,'ano','').to_s.strip.empty? && parent_pile.get_attribute(DICT,'structure','').to_s.strip.empty?
   end
  else
   checks+=1;add_issue.call('WARNING',e,'Proje Organizasyonu','Proje bilgisi eksik.','Elemanı seçip Uzantılar → Deniz Yapıları Araçları (MST) → Tüm araçlar (eski menü) → Seçili Elemana Elle Aks Ata… ile proje adını yazın (proje yalnız boşsa yazılır).') if !model_project.empty? && e.get_attribute(DICT,'project','').to_s.strip.empty? && e.get_attribute(DICT,'project_name','').to_s.strip.empty?
   checks+=1;add_issue.call('WARNING',e,'Proje Organizasyonu','Ano bilgisi eksik.','Elemanın yapı (structure) veya ano bilgisini kontrol edin; elle aks ataması ano yazmaz.') if e.get_attribute(DICT,'ano','').to_s.strip.empty? && e.get_attribute(DICT,'structure','').to_s.strip.empty?
  end
  # Axis/Span is mandatory only for elements whose engineering identity depends on an axis/span.
  # Independent crown walls may live outside the pile/head-beam grid; Project + Ano is sufficient.
  et=e.get_attribute(DICT,'element_type','').to_s
  axis_required=%w[steel_pipe_pile head_beam flat_precast channel_precast crane_precast deck_slab bored_pile].include?(et)
  checks+=1
  if axis_required && e.get_attribute(DICT,'axis','').to_s.strip.empty?
    add_issue.call('WARNING',e,'Proje Organizasyonu','Aks/Açıklık bilgisi eksik.','Elemanı seçip Uzantılar → Deniz Yapıları Araçları (MST) → Tüm araçlar (eski menü) → Seçili Elemana Elle Aks Ata… ile aks atayın.')
  end
  sig=e.get_attribute(DICT,'type_signature','').to_s
  checks+=1;add_issue.call('WARNING',e,'Tip Kütüphanesi','Tip imzası mevcut geometri/malzeme ile uyuşmuyor.','Güvenli Onarım ile tip kaydını güncelleyin.') if !sig.empty? && sig!=element_signature(e)
 end
 # One root-cause row per duplicate physical ID group; clicking selects all affected elements.
 by_visible.each do |k,a|
  next if a.length<=1 || k[1].start_with?('PID-')
  add_issue.call('ERROR',a.first,'Fiziksel Kimlik',"Mükerrer Eleman ID: #{k[1]} (#{a.length} eleman)",'BIM Kimlik Onarımı ile fiziksel ID değerlerini benzersiz yapın.',a.map(&:persistent_id))
 end
 by_type_id.each do |tid,a|
  sigs=a.map{|e|element_signature(e)}.uniq;next if sigs.length<=1
  a.each{|e|add_issue.call('WARNING',e,'Tip Kütüphanesi',"#{tid} altında #{sigs.length} farklı geometri/malzeme imzası var.",'Güvenli Onarım farklı geometrileri ayrı Tip ID\'lere ayırır.')}
 end
 beams=elems.select{|e|e.get_attribute(DICT,'element_type')=='head_beam'};beam_pids=beams.map(&:persistent_id)
 piles=elems.select{|e|e.get_attribute(DICT,'element_type')=='steel_pipe_pile'};pile_ids=piles.each_with_object({}){|p,h|h[element_visible_id(p)]=p}
 elems.each do |e|
  t=e.get_attribute(DICT,'element_type','').to_s;id=element_visible_id(e)
  case t
  when 'steel_pipe_pile'
   d=e.get_attribute(DICT,'diameter_mm',0).to_f;th=e.get_attribute(DICT,'thickness_mm',0).to_f;l=e.get_attribute(DICT,'length_m',0).to_f
   checks+=1;add_issue.call('ERROR',e,'Kazık Geometrisi','D/t/L geçersiz.','Kazık ölçülerini Proje Çalışma Alanı → Elemanı Düzenle ile Kazık sayfasında düzeltin.') if d<=0||th<=0||2*th>=d||l<=0
   checks+=1;add_issue.call('WARNING',e,'Malzeme','Çelik sınıfı eksik.','Çelik sınıfı atayın.') if e.get_attribute(DICT,'steel_grade','').to_s.strip.empty?
   # A pile may legitimately exist before its head beam is modeled.
   # Audit references declared by existing BK elements, not construction completeness.
   # Missing pile references on a BK are checked in the head_beam branch below.
  when 'head_beam'
   checks+=1;add_issue.call('ERROR',e,'BK Metrajı','Beton hacmi sıfır veya negatif.','BK geometrisi/metraj metadata bilgisini kontrol edin.') if e.get_attribute(DICT,'concrete_volume_m3',0).to_f<=0
   checks+=1;add_issue.call('WARNING',e,'Malzeme','Beton sınıfı eksik.','Beton sınıfı atayın.') if e.get_attribute(DICT,'concrete_class','').to_s.strip.empty?
   e.get_attribute(DICT,'connected_pile_ids','').to_s.split(',').map(&:strip).reject(&:empty?).each{|pid|checks+=1;add_issue.call('ERROR',e,'Kazık → BK',"Bağlı kazık #{pid} modelde bulunamadı.",'BK bağlı kazık listesini düzeltin.') unless pile_ids[pid]}
  when 'flat_precast','channel_precast','crane_precast'
   lp=e.get_attribute(DICT,'support_left_pid',0).to_i;rp=e.get_attribute(DICT,'support_right_pid',0).to_i;checks+=2
   add_issue.call('ERROR',e,'PD/Kanal → BK','Sol destek BK bulunamadı.','Sol mesnet bağlantısını yeniden eşleyin.') unless beam_pids.include?(lp)
   add_issue.call('ERROR',e,'PD/Kanal → BK','Sağ destek BK bulunamadı.','Sağ mesnet bağlantısını yeniden eşleyin.') unless beam_pids.include?(rp)
   checks+=1;add_issue.call('ERROR',e,'Prekast Metrajı','Beton hacmi sıfır veya negatif.','Prekast geometrisi/metrajını kontrol edin.') if e.get_attribute(DICT,'concrete_volume_m3',0).to_f<=0
   if t=='channel_precast';iw=e.get_attribute(DICT,'inner_width_m',0).to_f;idep=e.get_attribute(DICT,'inner_depth_m',0).to_f;checks+=1;add_issue.call('ERROR',e,'Kanal Geometrisi','Kanal iç genişlik/derinliği geçersiz.','Kanal kesit ölçülerini düzeltin.') if iw<=0||idep<=0;end
  when 'deck_slab'
   checks+=1;add_issue.call('ERROR',e,'Döşeme Metrajı','Beton hacmi sıfır veya negatif.','Döşeme geometrisi/metrajını kontrol edin.') if e.get_attribute(DICT,'concrete_volume_m3',0).to_f<=0
   sp=e.get_attribute(DICT,'support_pids','').to_s.split(',').map(&:to_i).reject{|x|x==0};checks+=1
   add_issue.call('WARNING',e,'Döşeme → BK/PD','Döşeme mesnet listesi (support_pids) eksik.','Döşemeyi bağlı BK aralığı ile yeniden ilişkilendirin.') if sp.empty?
   missing=sp.reject{|pid|beam_pids.include?(pid)};add_issue.call('ERROR',e,'Döşeme → BK/PD',"Döşemede modelde olmayan mesnet PID: #{missing.join(', ')}",'Döşeme mesnet listesini düzeltin.') unless missing.empty?
  when 'curb'
   checks+=1;add_issue.call('ERROR',e,'Tretuvar Metrajı','Boy/hacim sıfır veya negatif.','Tretuvar geometrisini kontrol edin.') if e.get_attribute(DICT,'length_m',0).to_f<=0||e.get_attribute(DICT,'concrete_volume_m3',0).to_f<=0
   pu=e.get_attribute(DICT,'parent_uid','').to_s;checks+=1;add_issue.call('WARNING',e,'Tretuvar → Döşeme','Bağlı döşeme UID eksik.','Tretuvarı ilgili döşemeye bağlayın.') if pu.empty?
  end
  %w[dependency_parent_uids dependency_child_uids].each do |key|
   e.get_attribute(DICT,key,'').to_s.split(',').map(&:strip).reject(&:empty?).each do |u|;checks+=1;add_issue.call('ERROR',e,'Bağımlılık Ağı',"#{key}: modelde bulunmayan UID #{u}",'Bağımlılık bilgisini yenileyin (Bağımlılık Motoru).') unless by_uid[u];end
  end
 end
 # v0.38 BK4: geometric BK ↔ pile ↔ precast checks.
 begin
  bk_out,bk_checks=mst_audit_bk_links(elems);checks+=bk_checks
  bk_out.each{|a|add_issue.call(*a)}
  kn_out,kn_checks=mst_kn_audit(elems);checks+=kn_checks   # v0.38 KN1
  kn_out.each{|a|add_issue.call(*a)}
 rescue => bk_ex
  add_issue.call('WARNING',nil,'Bağımlılık Ağı',"BK / prekast geometri denetimi tamamlanamadı: #{bk_ex.message}",'Modeli kaydedip denetimi yeniden çalıştırın; sorun sürerse bildirin.',[])
 end
 # Audit 4.1 — Engineering QA: Model -> QTO -> BOQ -> Hakediş consistency.
 concrete_types=%w[head_beam flat_precast channel_precast crane_precast deck_slab deck_topping curb crown_wall bored_pile pile_infill_concrete]
 elems.each do |e|
  et=e.get_attribute(DICT,'element_type','').to_s
  if concrete_types.include?(et)
   vol=qto3_quantity(e,:concrete_m3).to_f rescue e.get_attribute(DICT,'concrete_volume_m3',0).to_f
   checks+=1
   if vol>0 && qto_material_class(e).to_s.strip.empty?
    add_issue.call('WARNING',e,'Metraj Malzeme','Beton hacmi mevcut ancak beton sınıfı tanımlı değil.','Beton sınıfını Proje Çalışma Alanı → Bağlı Beton Sınıfı ile tanımlayın.')
   end
   rate_key={'pile_infill_concrete'=>'pile','head_beam'=>'head_beam','deck_slab'=>'deck','flat_precast'=>'flat_precast','channel_precast'=>'channel_precast','crane_precast'=>'crane_precast','deck_topping'=>'topping','crown_wall'=>'crown_wall'}[et]
   if vol>0 && rate_key
    expected=vol*rebar_rate(rate_key).to_f/1000.0
    checks+=1
    add_issue.call('WARNING',e,'Metraj Donatı',"Beton hacmi #{format('%.3f',vol)} m³ ancak hesaplanan donatı tonajı sıfır.",'Donatı pursantajını / metraj metadata bilgisini kontrol edin.') if expected<=0
   elsif et=='bored_pile' && vol>0
    checks+=1
    add_issue.call('WARNING',e,'Metraj Donatı','Fore kazık beton hacmi mevcut ancak donatı tonajı sıfır.','Fore Kazık donatı yöntemi/pursantajını kontrol edin.') if e.get_attribute(DICT,'rebar_t',0).to_f<=0
   end
  end
 end
 # v0.47 BK1: kazık BK içinde — gömülme düşümü bilgisi; kazık BK üstünü delerse hata
 begin
  hbs_a=[];collect_elements(Sketchup.active_model.entities,hbs_a);hbs_a=hbs_a.select{|x|x.get_attribute(DICT,'element_type','').to_s=='head_beam'}
  hbs_a.each do |b|
   if mst_hb_rebar_wrong?(b)   # v0.47.7 BR4
    add_issue.call('ERROR',b,'BK Donatı BIM',"#{element_visible_id(b)}: detaylı donatı bu elemana uymuyor (#{mst_hb_rebar_unsupported_reason(b)}); donatı kanal / boşlukları da dolduruyor ve tonajı yanlış.",'Model Bakımı → Eklenti Dışı BK Donatısını Temizle (donatı pursantaja döner).',[b.persistent_id])
   end
   x=mst_bk_pile_embed(b);checks+=1
   next if x[:items].empty?
   btop=b.get_attribute(DICT,'top_elevation_m',0).to_f
   over=mst_bk_connected_piles(b).select{|p|p.get_attribute(DICT,'top_elevation_m',-1e9).to_f>btop+1e-6}
   unless over.empty?
    add_issue.call('ERROR',b,'BK ↔ Kazık',"#{element_visible_id(b)}: #{over.length} kazığın üst kotu BK üst kotunun (#{format('%.3f',btop)}) üstünde.",'Kazık üst kotunu BK içinde kalacak şekilde düzeltin.',over.map(&:persistent_id))
   end
  end
 rescue => bk1_ex
  add_issue.call('WARNING',nil,'BK ↔ Kazık',"Kazık gömülme kontrolü tamamlanamadı: #{bk1_ex.message}",'Modeli yeniden tarayın.',[])
 end
 begin   # v0.51.5 G3 (ADR-0515 §11)
  mst_audit_v0515(elems,all).each{|sev,e,check,msg,fix,pids|checks+=1;add_issue.call(sev,e,check,msg,fix,pids)}
 rescue => v0515_ex
  add_issue.call('WARNING',nil,'Hesap Hatası',"0.51.5 hesap kontrolleri tamamlanamadı: #{v0515_ex.message}",'Modeli yeniden tarayın.',[])
 end
 begin
  audit_boq=boq_rows(false)
  central=%w[FORMWORK_CAST FORMWORK_PRECAST REBAR HB_DECK_CONCRETE CROWN_FORMWORK CROWN_CONCRETE CAST_C35_45_OTHER PRECAST_C35_45 PRECAST_INSTALL TOPPING_AREA PILE_INFILL PILE_STEEL PILE_MANIP PILE_RINGS PILE_SPLICES PILE_DRIVING PILE_PE PILE_DRILLING TOPPING_CONCRETE]
  audit_boq.each do |r|
   src=r[:source].to_s; next unless central.include?(src.split('#',2)[0])   # v0.47 BQ1: sınıf satırı 'KAYNAK#sınıf'
   traced=(respond_to?(:prog2_row_entities) ? prog2_row_entities(r) : boq_trace_entities(src))
   checks+=1
   if r[:quantity].to_f>0 && traced.empty?
    add_issue.call('ERROR',nil,'Metraj → Keşif',"#{r[:code]} / #{src}: keşif miktarı #{format('%.3f',r[:quantity].to_f)} #{r[:unit]} fakat kaynak BIM elemanı bulunamadı.",'Keşif kaynak eşleştirmesini ve metraj bilgisini kontrol edin.',[])
    next
   end
   approved=traced.select{|e|e.get_attribute(DICT,'progress_status','Planlandı').to_s=='Onaylandı'}
   next if approved.empty?
   aq=progress_approved_quantity(r).to_f
   checks+=1
   if aq<=0 && r[:quantity].to_f>0
    add_issue.call('ERROR',approved.first,'Keşif → Hakediş',"#{r[:code]} / #{src}: Onaylandı durumunda #{approved.length} BIM elemanı var ancak hakediş miktarı üretilmiyor.",'Metraj kaynağı, keşif kaynak eşleştirmesi ve hakediş bağlantısını kontrol edin.',approved.map(&:persistent_id))
   elsif aq-r[:quantity].to_f>0.0001
    add_issue.call('ERROR',approved.first,'Keşif → Hakediş',"#{r[:code]}: onaylı miktar sözleşme/keşif miktarını aşıyor.",'Keşif miktarı ile onaylı BIM kapsamını kontrol edin.',approved.map(&:persistent_id))
   end
  end
 rescue => audit_ex
  add_issue.call('WARNING',nil,'Mühendislik Kalite Kontrolü',"Metraj/Keşif/Hakediş zinciri kontrolü tamamlanamadı: #{audit_ex.message}",'Keşif ve hakediş verisini kontrol edip yeniden tarayın.',[])
 end
 seen={};issues=issues.select{|x|k=[x[:pids] ? x[:pids].sort.join(',') : (x[:e] ? x[:e].persistent_id : 0),x[:sev],x[:check],x[:msg]];!seen[k]&&(seen[k]=true)}
 errors=issues.count{|x|x[:sev]=='ERROR'};warnings=issues.count{|x|x[:sev]=='WARNING'};passed=[checks-errors-warnings,0].max
 @mst_last_audit={'errors'=>errors,'warnings'=>warnings,'at'=>Time.now.strftime('%H:%M'),'model'=>Sketchup.active_model.object_id}   # v0.38 UI4
 # Audit 4.0 health chain: summarize existing engineering checks without changing model data.
 health_groups={
  'BIM Kimliği'=>['BIM Kimliği','Fiziksel Kimlik'],
  'Organizasyon'=>['Proje Organizasyonu'],
  'Tip Kütüphanesi'=>['Tip Kütüphanesi'],
  'Bağımlılık'=>['Bağımlılık Ağı','Kazık → BK','PD/Kanal → BK','Döşeme → BK/PD','Tretuvar → Döşeme','BK ↔ Kazık'],
  # kod inceleme #8: bağlı olmayan kontrol adları (Fiziksel Boru / Detay, BK Donatı BIM, Kanal Cebi) eklendi
  'Metraj'=>['Fiziksel Boru / BIM / Metraj','Fiziksel Detay / Metraj','BK Donatı BIM','Kanal Cebi',
             'Kazık Geometrisi','BK Metrajı','Prekast Metrajı','Kanal Geometrisi','Döşeme Metrajı','Tretuvar Metrajı','Malzeme','Metraj Malzeme','Metraj Donatı','Hesap Hatası'],
  'Metraj → Keşif'=>['Metraj → Keşif'],
  'Hakediş'=>['Keşif → Hakediş','Mühendislik Kalite Kontrolü']
 }
 health=health_groups.map do |label,names|
  rel=issues.select{|x|names.include?(x[:check])}
  state=rel.any?{|x|x[:sev]=='ERROR'} ? 'bad' : (rel.any?{|x|x[:sev]=='WARNING'} ? 'warn' : 'ok')
  [label,state,rel.length]
 end
 boq_state='ok';boq_count=0
 begin
  br=boq_rows(false);boq_count=br.length
  boq_state='warn' if br.empty? && !elems.empty?
 rescue
  boq_state='warn'
 end
 health << ['Keşif',boq_state,boq_count]
 health_html=health.map do |label,state,count|
  icon=state=='ok' ? '✓' : (state=='bad' ? '✕' : '⚠')
  note=(label=='Keşif' ? "#{count} satır" : (count==0 ? 'Temiz' : "#{count} bulgu"))
  "<div class='health #{state}'><b>#{icon} #{html_escape(label)}</b><span>#{html_escape(note)}</span></div>"
 end.join
 # Audit 4.1a: collapse repetitive organization warnings into selectable groups.
 # The underlying issue count is preserved; only presentation is grouped.
 display_issues=[]
 org_groups=issues.select{|x|x[:check]=='Proje Organizasyonu'}.group_by{|x|[x[:sev],x[:msg],x[:fix]]}
 issues.reject{|x|x[:check]=='Proje Organizasyonu'}.each{|x|display_issues << x}
 org_groups.each do |(sev,msg,fix),grp|
  pids=grp.flat_map{|x|x[:pids] || (x[:e] ? [x[:e].persistent_id] : [])}.compact.uniq
  sample=grp.map{|x|x[:e]}.compact.first
  type_counts=Hash.new(0)
  grp.each do |x|
    ge=x[:e]
    next unless ge
    gt=ge.get_attribute(DICT,'element_type','').to_s
    type_counts[gt.empty? ? 'unknown' : gt]+=1
  end
  display_issues << {sev:sev,e:sample,check:'Proje Organizasyonu',msg:msg,fix:fix,pids:pids,group_count:grp.length,type_counts:type_counts}
 end
 display_issues.sort_by!{|x|[x[:sev]=='ERROR' ? 0 : 1,x[:check].to_s,x[:msg].to_s]}
 rows=String.new
 display_issues.each do |x|
  e=x[:e];pids=(x[:pids]||[e ? e.persistent_id : 0]).join(',');count=x[:group_count].to_i
  id=count>1 ? "#{count} eleman" : (e ? element_visible_id(e) : '-')
  msg=count>1 ? "#{x[:msg]} (#{count} eleman)" : x[:msg]
  tc=x[:type_counts] || {}
  types=tc.empty? ? (e ? e.get_attribute(DICT,'element_type','').to_s : '—') : tc.sort_by{|k,v|[-v,k]}.map{|k,v|"#{k}: #{v}"}.join(' · ')
  cls=x[:sev]=='ERROR'?'err':'warn';lab=x[:sev]=='ERROR'?'HATA':'UYARI'
  rows << "<tr class='#{cls}' onclick=\"sketchup.audit_select('#{pids}')\"><td><span class='sev #{cls}'>#{lab}</span></td><td><b>#{html_escape(id)}</b></td><td>#{html_escape(x[:check])}</td><td>#{html_escape(types)}</td><td>#{html_escape(msg)}</td><td>#{html_escape(x[:fix])}</td><td><button onclick=\"event.stopPropagation();sketchup.audit_group_detail('#{pids}')\">Detay</button></td></tr>"
 end
 rows="<tr><td colspan='7' class='empty'>Aktif hata veya uyarı bulunmadı.</td></tr>" if rows.empty?
 show_identity=issues.any?{|x|['BIM Kimliği','Fiziksel Kimlik'].include?(x[:check])};show_deck=issues.any?{|x|x[:check].to_s.start_with?('Döşeme →')}   # v0.38 BK4.3
 html=%Q{<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:Arial;margin:0;background:#f3f7fa;color:#18364a}.top{background:#fff;border-bottom:1px solid #cadce7;padding:18px 22px}.top h2{margin:0;color:#073f73}.kpis{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-top:14px}.k{border:1px solid #d4e2eb;border-radius:8px;padding:12px;background:#fff}.k small{display:block;color:#718999}.k b{font-size:26px}.red{color:#b42318}.orange{color:#b66a00}.green{color:#16834f}.health-title{font-size:11px;font-weight:700;color:#607d8b;margin:14px 0 7px}.health-grid{display:grid;grid-template-columns:repeat(8,1fr);gap:7px}.health{border:1px solid #d4e2eb;border-radius:7px;padding:9px 10px;background:#fff}.health b{display:block;font-size:11px}.health span{display:block;font-size:9px;color:#718999;margin-top:3px}.health.ok b{color:#16834f}.health.warn b{color:#a66400}.health.bad b{color:#b42318}.wrap{padding:16px 22px}.card{background:#fff;border:1px solid #cadce7;border-radius:9px;overflow:hidden}.bar{padding:12px 14px;border-bottom:1px solid #dce8ef;display:flex;gap:10px;align-items:center}.bar b{margin-right:auto}.bar span{font-size:11px;color:#607d8b}button{border:0;border-radius:6px;background:#087fd1;color:#fff;padding:9px 13px;font-weight:700;cursor:pointer}.repair{background:#16834f}table{width:100%;border-collapse:collapse}th{background:#eaf3f8;color:#42677f;text-align:left;font-size:11px;padding:9px;position:sticky;top:0}td{font-size:11px;padding:9px;border-bottom:1px solid #e7eef3}tbody tr{cursor:pointer}tbody tr:hover{background:#eef8fe}.sev{display:inline-block;padding:4px 7px;border-radius:12px;font-size:9px;font-weight:700}.sev.err{background:#fde8e7;color:#b42318}.sev.warn{background:#fff1d6;color:#9a5a00}.empty{text-align:center;color:#607d8b;padding:28px}.note{font-size:10px;color:#607d8b;margin-top:9px}</style></head><body><div class='top'><h2>Model Kontrolü — Mühendislik Kalite Kontrolü <small style='font-weight:normal;color:#607d8b'>v#{VERSION}</small></h2><div>Deniz Yapıları BIM — model kalite ve izlenebilirlik kontrolü</div><div class='kpis'><div class='k'><small>HATA</small><b class='red'>#{errors}</b></div><div class='k'><small>UYARI</small><b class='orange'>#{warnings}</b></div><div class='k'><small>KONTROL EDİLEN</small><b class='green'>#{checks}</b></div></div><div class='health-title'>MODEL SAĞLIĞI</div><div class='health-grid'>#{health_html}</div></div><div class='wrap'><div class='card'><div class='bar'><b>Aktif Bulgular</b><span>Satıra tıklayın → ilgili eleman(lar) seçilir ve zoom yapılır</span><button class='repair' title='Kazık / BK / prekast tip kayıtları + boru ağırlıkları. Geometri, fiziksel ID ve tip adlarına dokunmaz. Önce önizleme gösterir.' onclick='sketchup.audit_safe_repair()'>Güvenli Onarım</button>#{show_identity ? "<button class='repair' title='Mükerrer fiziksel ID / UID numaralarını yeniden numaralandırır.' onclick='sketchup.audit_repair_identity()'>BIM Kimlik Onarımı</button>" : ''}#{show_deck ? "<button class='repair' onclick='sketchup.audit_repair_deck()'>Döşeme İlişki Onarımı</button>" : ''}<button onclick='sketchup.audit_refresh()'>Yeniden Tara</button></div><table><thead><tr><th>Seviye</th><th>Eleman / Grup</th><th>Kontrol</th><th>Eleman Tipleri</th><th>Açıklama</th><th>Önerilen İşlem</th><th>Detay</th></tr></thead><tbody>#{rows}</tbody></table></div><div class='note'>Model Kontrolü MODEL → BIM → METRAJ → KEŞİF → HAKEDİŞ zincirini kontrol eder ve mevcut model verisini değiştirmez. Kimlik Onarımı yalnız fiziksel ID/UID çakışmalarını düzeltir; Tip ID ve geometriyi değiştirmez. Geçen kontrol: #{passed}.</div></div></body></html>}
 d=mst_html_dialog('model_audit',dialog_title:'Model Kontrolü / Mühendislik Kalite Kontrolü',width:1250,height:720,resizable:true);d.set_html(EngineeringUI.decorate(html))
 d.add_action_callback('audit_select') do |_,raw|
  ids=raw.to_s.split(',').map(&:to_i);collect=[];collect_elements(model.entities,collect);found=collect.select{|x|x.respond_to?(:persistent_id)&&ids.include?(x.persistent_id)}
  unless found.empty?;model.selection.clear;found.each{|x|model.selection.add(x)};model.active_view.zoom(model.selection);end
 end
 d.add_action_callback('audit_group_detail') do |_,raw|
  ids=raw.to_s.split(',').map(&:to_i).reject{|x|x<=0}.uniq
  collect=[];collect_elements(model.entities,collect)
  found=collect.select{|x|x.respond_to?(:persistent_id)&&ids.include?(x.persistent_id)}
  grouped=found.group_by{|x|x.get_attribute(DICT,'element_type','').to_s}
  lines=grouped.sort_by{|k,v|[-v.length,k]}.map{|k,v|"#{k.empty? ? 'unknown' : k}: #{v.length} eleman"}
  ids_txt=found.first(40).map{|x|"PID-#{x.persistent_id} / #{element_visible_id(x)}"}
  more=found.length>40 ? "\n... +#{found.length-40} eleman daha" : ''
  UI.messagebox("Organizasyon Uyarısı Detayı\n\n#{lines.join("\n")}\n\nİlk elemanlar:\n#{ids_txt.join("\n")}#{more}")
 end
 d.add_action_callback('audit_refresh'){|_|d.close;model_audit}
 d.add_action_callback('audit_safe_repair'){|_|d.close;mst_safe_repair;model_audit}
 d.add_action_callback('audit_repair_identity'){|_|d.close;repair_bim_identity}
 d.add_action_callback('audit_repair_deck'){|_|d.close;repair_deck_bim_relationships;model_audit}
 d.show;@audit_dialog=d
 model.set_attribute(DICT,'last_model_audit_error_count',errors);model.set_attribute(DICT,'last_model_audit_warning_count',warnings);model.set_attribute(DICT,'last_model_audit_check_count',checks)
end # mst_read_batch
end

def export_boq_csv
 all=[];collect_elements(Sketchup.active_model.entities,all)
 path=UI.savepanel('Keşif / Metraj CSV Kaydet','','MST_Kesif_Metraj.csv');return unless path
 path+='.csv' unless path.downcase.end_with?('.csv')
 require 'csv';rows=[['Kategori','Tip','Malzeme/Sinif','Adet','Boy_m','Beton_m3','Kalip_m2','Celik_t','Donati_t']]
 rows.concat(mst_boq_csv_rows(all))   # ADR-0515 G5: Keşif ile aynı kaynak (net BK betonu, tüm iç beton, boru çeliği, donatı)
 CSV.open(path,'w',write_headers:false,encoding:'UTF-8') do |csv|
 rows.each_with_index do |r,index|
  output=r.dup
  if index>0
   output[5]=format('%.3f',r[5])
   output[6]=format('%.2f',r[6])
  end
  csv<<output
 end
end
 UI.messagebox("Keşif / Metraj CSV oluşturuldu:\n#{path}")
rescue=>ex;UI.messagebox("Keşif / Metraj CSV dışa aktarma hatası: #{ex.message}");end
# ===== end v0.13.0 =====



# ===== v0.18.0 Dependency Engine 2.0 =====
def mst_all_elements
  a=[]; collect_elements(Sketchup.active_model.entities,a)
  a.select{|e| e.respond_to?(:get_attribute) && %w[steel_pipe_pile head_beam flat_precast channel_precast crane_precast deck_slab curb pile_infill_concrete crown_wall bored_pile].include?(e.get_attribute(DICT,'element_type','').to_s) }
end

def mst_element_by_pid(pid, all=mst_all_elements)
  all.find{|e| e.respond_to?(:persistent_id) && e.persistent_id.to_i==pid.to_i }
end

def mst_element_by_uid(uid, all=mst_all_elements)
  u=uid.to_s; all.find{|e| e.get_attribute(DICT,'element_uid','').to_s==u }
end

def mst_pile_ids_for_beam(b)
  b.get_attribute(DICT,'connected_pile_ids','').to_s.split(',').map{|x|x.strip}.reject(&:empty?)
end

def mst_dependency_impacts(root)
  types=mst_dependency_tree(root).map{|x,d|x.get_attribute(DICT,'element_type','').to_s}
  impacts=[]
  impacts << 'Çelik ağırlığı / kazık imal metrajı' if root.get_attribute(DICT,'element_type','')=='steel_pipe_pile'
  impacts << 'Beton hacmi' if types.any?{|t|%w[head_beam flat_precast channel_precast crane_precast deck_slab curb].include?(t)}
  impacts << 'Kalıp alanı' if types.any?{|t|%w[head_beam flat_precast channel_precast crane_precast deck_slab curb].include?(t)}
  impacts << 'Prekast yerleşimi' if types.any?{|t|%w[flat_precast channel_precast crane_precast].include?(t)}
  impacts << 'Döşeme boşluğu / kesimleri' if types.include?('deck_slab')
  impacts << 'Keşif / Metraj miktarları'
  impacts.uniq
end

def mst_dependency_payload(e)
  # R-2: görüntüleme salt okur (UID üretmez)
  return {'ok'=>false,'message'=>'Önce bir MST elemanı seçin.'} unless e
  rows=mst_dependency_tree(e); parents=mst_direct_parents(e)
  counts=Hash.new(0); items=rows.map do |x,depth|
    t=x.get_attribute(DICT,'element_type','').to_s; counts[t]+=1
    {'id'=>mst_display_id(x),'type'=>t,'depth'=>depth,'uid'=>x.get_attribute(DICT,'element_uid','').to_s}   # v0.51.5 H3f: yalnız gösterim
  end
  {'ok'=>true,'root_id'=>element_visible_id(e),'root_type'=>e.get_attribute(DICT,'element_type','').to_s,'root_uid'=>e.get_attribute(DICT,'element_uid','').to_s,'affected_count'=>items.length,'counts'=>counts,'items'=>items,'parents'=>parents.map{|x|{'id'=>element_visible_id(x),'type'=>x.get_attribute(DICT,'element_type','').to_s,'uid'=>x.get_attribute(DICT,'element_uid','').to_s}},'impacts'=>mst_dependency_impacts(e),'schema'=>'2.0'}
end

def send_dependency_analysis(dialog=@d)
  return unless dialog && dialog.visible?
  dialog.execute_script("setDependencyAnalysis(#{JSON.generate(mst_dependency_payload(selected_mst_element))});")
end

def stamp_dependency_metadata
  all=mst_all_elements; model=Sketchup.active_model; op=false
  # R-2 / K05, K28: önce değişiklik listesi (yazmaz); tek işlem; parent_uid / support_*_uid yalnız boşsa; dependency_* ve revision commit_with_dependencies'e bırakılır
  ch=mst_standardize_changes(model);pend={};ch.each{|e,k,v|pend[e]=v if k=='element_uid'}
  uid_of=lambda do |x|
    u=x.get_attribute(DICT,'element_uid','').to_s;u=pend[x].to_s if u.empty?
    if u.empty?;u="MST-#{x.persistent_id}-#{Time.now.to_i}";pend[x]=u;ch << [x,'element_uid',u];ch << [x,'uid_owner_pid',x.persistent_id] if x.get_attribute(DICT,'uid_owner_pid',nil).nil?;end
    u
  end
  blank=lambda{|e,k|e.get_attribute(DICT,k,'').to_s.strip.empty?}
  pgraph=dependency_graph(model,all)[2]   # ADR-0515 G7: grafik bir kez (döngü modele yazmaz; mst_direct_parents ile aynı sonuç)
  all.each do |e|
    uid_of.call(e); parents=pgraph[e]
    ch << [e,'parent_uid',uid_of.call(parents.first)] if parents.length==1 && blank.call(e,'parent_uid')
    if %w[flat_precast channel_precast crane_precast].include?(e.get_attribute(DICT,'element_type','').to_s)
      l=mst_element_by_pid(e.get_attribute(DICT,'support_left_pid',0),all); r=mst_element_by_pid(e.get_attribute(DICT,'support_right_pid',0),all)
      ch << [e,'support_left_uid',uid_of.call(l)] if l && blank.call(e,'support_left_uid')
      ch << [e,'support_right_uid',uid_of.call(r)] if r && blank.call(e,'support_right_uid')
    end
  end
  if ch.empty? && dependency_changes(model).empty?
    send_dependency_analysis
    UI.messagebox("Bağımlılık Motoru: değişiklik gerekmedi.\n\n#{all.length} eleman tarandı; kayıtlı UID, ilişki ve revizyon bilgileri zaten güncel.")
    return
  end
  model.start_operation('MST Bağımlılık Motoru',true);op=true
  ch.each{|e,k,v|e.set_attribute(DICT,k,v)}
  commit_with_dependencies(model);op=false; send_dependency_analysis
  linked=all.count{|e|!e.get_attribute(DICT,'dependency_child_uids','').to_s.empty? || !e.get_attribute(DICT,'dependency_parent_uids','').to_s.empty?}
  UI.messagebox("Bağımlılık Motoru tamamlandı.\n\n#{all.length} eleman tarandı.\n#{linked} elemanda ilişki bulundu.\n\nZincir: Kazık → BK → PD/Kanal → Döşeme → Tretuvar\nUID tabanlı üst/alt eleman ve mesnet ilişkileri yazıldı.\n\nBu sürüm etki analizi yapar; bağlı geometriyi otomatik değiştirmez.")
rescue=>ex
  (model.abort_operation if op) rescue nil; UI.messagebox("Bağımlılık Motoru hatası: #{ex.message}")
end
# ===== end v0.18.0 =====

# ===== v0.15.0 Parametric Universal Editor =====
def mst_attr_hash(e)
  h={}; d=e.attribute_dictionary(DICT,false); d.each_pair{|k,v|h[k.to_s]=v} if d; h
end

def mst_restore_attrs(e,h)
  h.each{|k,v| e.set_attribute(DICT,k,v) }
end

def rebuild_head_beam_parametric(g,o)
  h=mst_attr_hash(g); len=(o['length_m']||h['length_m']).to_f; wid=(o['width_m']||h['width_m']).to_f; hei=(o['height_m']||h['height_m']).to_f
  raise 'BK boy/genişlik/yükseklik değeri geçersiz.' if [len,wid,hei].any?{|x|x<=0}
  d={}; h.each{|k,v|d[k]=v}; d['hb_height_m']=hei
  prof=recess_profile_points(m(len),m(hei),d)
  g.entities.clear!; f=g.entities.add_face(prof.map{|x,z|Geom::Point3d.new(x,0,z)}); raise 'BK profili oluşturulamadı.' unless f
  f.reverse! if f.normal.y<0; f.pushpull(m(wid))
  vol=polygon_area_xz(prof)/(1.m*1.m)*wid
  h['length_m']=len;h['width_m']=wid;h['height_m']=hei;h['concrete_volume_m3']=vol
  h['concrete_class']=o['concrete_class'].to_s unless o['concrete_class'].to_s.empty?
  %w[start_tooth_length_m start_tooth_depth_m start_tooth_slope_m end_tooth_length_m end_tooth_depth_m end_tooth_slope_m].each{|k|h[k]=o[k].to_f if o.key?(k)}
  mst_restore_attrs(g,h); ensure_uid(g)
  mst_cv_redraw!(g) if respond_to?(:mst_cv_redraw!)   # v0.50 MF1
end

def editor_precast_formwork(g,h,channel=false)
  faces=g.entities.grep(Sketchup::Face)
  roles=channel ? [%w[OUTER_BOTTOM],%w[OUTER_SIDE],%w[INNER_FLOOR INNER_SIDE],%w[END_FACE]] : [%w[BOTTOM],%w[LONG_SIDE_1],%w[LONG_SIDE_2],%w[END_1],%w[END_2]]
  flags=h['editor_formwork_flags']
  valid=lambda{|a|a.is_a?(Array) && a.size==roles.size && a.all?{|v|v==true || v==false}}
  unless valid.call(flags)
    if !faces.empty? && faces.all?{|f|[true,false].include?(f.get_attribute(DICT,'formwork',nil))}
      flags=roles.map{|names|faces.any?{|f|f.get_attribute(DICT,'formwork',false)==true && names.include?(f.get_attribute(DICT,'formwork_type',''))}}
    elsif channel && %w[bottom sides inner ends].all?{|k|[true,false].include?(h["formwork_#{k}"])}
      flags=%w[bottom sides inner ends].map{|k|h["formwork_#{k}"]}
    else
      raise 'Kalıp yüzü seçimleri okunamadı. Eski düzenlemeyi geri alın veya elemanı kalıp seçimleriyle yeniden oluşturun.'
    end
  end
  form=faces.find{|f|f.get_attribute(DICT,'formwork',false)==true && f.material}
  concrete=faces.find{|f|f.get_attribute(DICT,'formwork',nil)==false && f.material}
  form_mat=form ? form.material : material_for(Sketchup.active_model,"MAG Edit Kalıp #{h['formwork_color']}",h['formwork_color'])
  conc_mat=concrete ? concrete.material : material_for(Sketchup.active_model,"MAG Edit Beton #{h['concrete_color']}",h['concrete_color'])
  h['editor_formwork_flags']=flags.dup
  [flags,form_mat,conc_mat]
end

def rebuild_flat_precast_parametric(g,o)
  h=mst_attr_hash(g); l=(o['length_m']||h['length_m']).to_f;w=(o['width_m']||h['width_m']).to_f;hh=(o['height_m']||h['height_m']).to_f
  raise 'PD boy/en/kalınlık değeri geçersiz.' if [l,w,hh].any?{|x|x<=0}
  flags,form_mat,conc_mat=editor_precast_formwork(g,h)
  g.entities.clear!;f=g.entities.add_face([0,0,0],[m(l),0,0],[m(l),m(w),0],[0,m(w),0]);f.reverse! if f.normal.z<0;f.pushpull(m(hh))
  paint_flat_precast_formwork(g,flags,form_mat,conc_mat)
  h['formwork_area_m2']=[l*w,l*hh,l*hh,w*hh,w*hh].each_with_index.sum{|area,i|flags[i] ? area : 0.0}
  h['length_m']=l;h['width_m']=w;h['height_m']=hh;h['concrete_volume_m3']=l*w*hh;h['top_elevation_m']=h['bottom_elevation_m'].to_f+hh
  h['concrete_class']=o['concrete_class'].to_s unless o['concrete_class'].to_s.empty?;mst_restore_attrs(g,h);ensure_uid(g)
  mst_pc_after_rebuild!(g) if respond_to?(:mst_pc_after_rebuild!)   # v0.50 PC2
end

def rebuild_channel_parametric(g,o)
  h=mst_attr_hash(g);l=(o['length_m']||h['length_m']).to_f;wi=(o['inner_width_m']||h['inner_width_m']).to_f;di=(o['inner_depth_m']||h['inner_depth_m']).to_f;tb=(o['base_thickness_m']||h['base_thickness_m']).to_f;tw=(o['wall_thickness_m']||h['wall_thickness_m']).to_f
  raise 'Kanal ölçüleri geçersiz.' if [l,wi,di,tb,tw].any?{|x|x<=0}
  selected,form_mat,conc_mat=editor_precast_formwork(g,h,true)
  flags=[:bottom,:sides,:inner,:ends].zip(selected).to_h
  ow=wi+2*tw;oh=tb+di; prof=[[0,0],[ow,0],[ow,oh],[ow-tw,oh],[ow-tw,tb],[tw,tb],[tw,oh],[0,oh]]
  g.entities.clear!;f=g.entities.add_face(prof.map{|yy,zz|Geom::Point3d.new(0,m(yy),m(zz))});raise 'Kanal U kesiti oluşturulamadı.' unless f;f.reverse! if f.normal.x<0;f.pushpull(m(l))
  paint_channel_precast_formwork(g,ow,tw,di,tb,flags,form_mat,conc_mat)
  h['formwork_area_m2']=[l*ow,2*l*oh,l*(wi+2*di),2*(ow*tb+2*tw*di)].each_with_index.sum{|area,i|selected[i] ? area : 0.0}
  h['formwork_inner_m2']=flags[:inner] ? l*(wi+2*di) : 0.0
  h['formwork_wall_top_m2']=0.0
  flags.each{|k,v|h["formwork_#{k}"]=v};h['formwork_top']=false
  h['length_m']=l;h['inner_width_m']=wi;h['inner_depth_m']=di;h['base_thickness_m']=tb;h['wall_thickness_m']=tw;h['outer_width_m']=ow;h['width_m']=ow;h['concrete_volume_m3']=(ow*tb+2*tw*di)*l;h['top_elevation_m']=h['bottom_elevation_m'].to_f+oh
  h['concrete_class']=o['concrete_class'].to_s unless o['concrete_class'].to_s.empty?;mst_restore_attrs(g,h);ensure_uid(g)
  mst_pc_after_rebuild!(g) if respond_to?(:mst_pc_after_rebuild!)   # v0.50 PC2
end

def rebuild_curb_parametric(g,o)
  h=mst_attr_hash(g);l=(o['length_m']||h['length_m']).to_f;w=(o['width_m']||h['width_m']).to_f;hh=(o['height_m']||h['height_m']).to_f
  raise 'Bordür boy/genişlik/yükseklik değeri geçersiz.' if [l,w,hh].any?{|x|x<=0}
  g.entities.clear!;f=g.entities.add_face([0,0,0],[m(l),0,0],[m(l),m(w),0],[0,m(w),0]);f.reverse! if f.normal.z<0;f.pushpull(m(hh))
  h['length_m']=l;h['width_m']=w;h['height_m']=hh;h['concrete_volume_m3']=l*w*hh;h['formwork_area_m2']=2*(l+w)*hh;h['top_elevation_m']=h['bottom_elevation_m'].to_f+hh
  h['concrete_class']=o['concrete_class'].to_s unless o['concrete_class'].to_s.empty?;mst_restore_attrs(g,h);ensure_uid(g)
end

def dependent_elements_for(e)
  all=[];collect_elements(Sketchup.active_model.entities,all);pid=e.persistent_id;t=e.get_attribute(DICT,'element_type').to_s
  case t
  when 'head_beam' then all.select{|x|%w[flat_precast channel_precast crane_precast].include?(x.get_attribute(DICT,'element_type').to_s) && [x.get_attribute(DICT,'support_left_pid',0).to_i,x.get_attribute(DICT,'support_right_pid',0).to_i].include?(pid)}
  when 'channel_precast','flat_precast' then all.select{|x|x.get_attribute(DICT,'element_type').to_s=='deck_slab'}
  when 'deck_slab' then all.select{|x|x.get_attribute(DICT,'element_type').to_s=='curb' && x.get_attribute(DICT,'parent_deck_id','').to_s==element_visible_id(e)}
  else [] end
end
# ===== end v0.15.0 =====

# ===== v0.14.0 Universal Element Editor + Professional Excel XML =====
def selected_mst_element
  Sketchup.active_model.selection.to_a.find{|e| e.respond_to?(:get_attribute) && !e.get_attribute(DICT,'element_type','').to_s.empty? }
end

def send_editor_selection(dialog=@d)
  return unless dialog && dialog.visible?
  dialog.execute_script("setEditorSelection(#{JSON.generate(editor_payload(selected_mst_element))});")
end

def xml_escape(s);s.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;').gsub("'",'&apos;');end

def qto_material_class(e)
  t=e.get_attribute(DICT,'element_type','').to_s
  if t=='steel_pipe_pile'
    e.get_attribute(DICT,'steel_grade','-').to_s
  else
    cc=e.get_attribute(DICT,'concrete_class','').to_s
    if cc.empty? && t=='pile_infill_concrete'
      # Older models may have the class on the parent pile or legacy material key.
      cc=e.get_attribute(DICT,'material_class',e.get_attribute(DICT,'concrete_grade','')).to_s
      if cc.empty? && e.respond_to?(:parent) && e.parent.respond_to?(:get_attribute)
        cc=e.parent.get_attribute(DICT,'concrete_class','').to_s
      end
    end
    cc.empty? ? '-' : cc
  end
end

def xlsx_col_name(n)
  s='';while n>0;n-=1;s=(65+n%26).chr+s;n/=26;end;s
end

def xlsx_sheet_xml(headers,rows,widths=nil)
  all=[headers]+rows
  cols=''
  if widths
    cols='<cols>'+widths.each_with_index.map{|w,i|"<col min=\"#{i+1}\" max=\"#{i+1}\" width=\"#{w}\" customWidth=\"1\"/>"}.join+'</cols>'
  end
  body=all.each_with_index.map do |row,ri|
    cells=row.each_with_index.map do |v,ci|
      ref="#{xlsx_col_name(ci+1)}#{ri+1}"
      if v.is_a?(Numeric)
style=ri==0 ? 1 : (ci>=4 ? 2 : 0)
if ri>0
  unit=headers[ci].to_s
  unit=row[2].to_s if ci==1 && headers[2].to_s=='Birim'
  style=3 if unit.include?('m³')
  style=2 if unit.include?('m²')
end
"<c r=\"#{ref}\" s=\"#{style}\"><v>#{v}</v></c>"
      else
        style=ri==0 ? ' s="1"' : ''
        "<c r=\"#{ref}\" t=\"inlineStr\"#{style}><is><t>#{xml_escape(v)}</t></is></c>"
      end
    end.join
    "<row r=\"#{ri+1}\">#{cells}</row>"
  end.join
  dim="A1:#{xlsx_col_name(headers.length)}#{all.length}"
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><dimension ref=\"#{dim}\"/><sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>#{cols}<sheetData>#{body}</sheetData><autoFilter ref=\"A1:#{xlsx_col_name(headers.length)}#{all.length}\"/></worksheet>"
end

def write_simple_zip(path,entries)
  require 'zlib'
  local=String.new.b;central=String.new.b;offset=0
  entries.each do |name,data|
    n=name.to_s.b;d=data.to_s.b;crc=Zlib.crc32(d);size=d.bytesize
    lh=[0x04034b50,20,0,0,0,0,crc,size,size,n.bytesize,0].pack('VvvvvvVVVvv')+n+d
    local<<lh
    central<<[0x02014b50,20,20,0,0,0,0,crc,size,size,n.bytesize,0,0,0,0,0,offset].pack('VvvvvvvVVVvvvvvVV')+n
    offset+=lh.bytesize
  end
  eocd=[0x06054b50,0,0,entries.length,entries.length,central.bytesize,local.bytesize,0].pack('VvvvvVVv')
  File.open(path,'wb'){|f|f.write(local);f.write(central);f.write(eocd)}
end


# ===== v0.36.1 Pile Detail QTO Parameters & Calculation Fix =====
def sync_pile_bim_qto(p)
 return unless p && p.valid? && p.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'
 mst_pile_rebar_refresh!(p) if p.is_a?(Sketchup::Group)   # v0.38 PR1: Ø / boy / kot / iç beton değişince
 mst_pile_rebar_qto!(p)
 r=pile_fabrication_qto_row([p],p.get_attribute(DICT,'pile_id','').to_s,true)
 return unless r
 attrs={
  'qto_fabrication_length_m'=>r[6].to_f, 'qto_driving_length_m'=>r[7].to_f,
  'qto_plug_count'=>r[4].to_i, 'qto_plug_weight_kg'=>r[8].to_f*1000.0,
  'qto_steel_pipe_weight_kg'=>r[9].to_f*1000.0,
  'qto_upper_ring_weight_kg'=>r[10].to_f, 'qto_lower_ring_weight_kg'=>r[11].to_f,
  'qto_manipulation_t'=>r[12].to_f, 'qto_infill_concrete_m3'=>r[13].to_f,
  'qto_pe_area_m2'=>r[14].to_f, 'qto_drilling_m'=>r[15].to_f,
  'qto_engine_version'=>'0.36.1'
 }
 attrs.each{|k,v|p.set_attribute(DICT,k,v) if p.get_attribute(DICT,k,nil)!=v}
 attrs
end

def pile_bim_qto_item(p)
 r=pile_fabrication_qto_row([p],p.get_attribute(DICT,'pile_id','').to_s,true)
 {pile_id:p.get_attribute(DICT,'pile_id','').to_s, system:pile_report_system(p), structure:pile_report_structure(p),
  grid_point:p.get_attribute(DICT,'grid_point','').to_s, diameter_mm:p.get_attribute(DICT,'diameter_mm',0).to_f, thickness_mm:p.get_attribute(DICT,'thickness_mm',0).to_f,
  length_m:qto3_quantity(p,:length_m), steel_grade:p.get_attribute(DICT,'steel_grade','').to_s, concrete_class:pile_report_concrete_class(p),
  steel_t:r[9], concrete_m3:r[13], pe_m2:r[14], drilling_m:r[15],
  plug_count:r[4], plug_kg:r[8]*1000.0, lower_ring_kg:r[11], upper_ring_kg:r[10]}
end

def select_pile_qto_id(pile_id)
 all=[];collect_elements(Sketchup.active_model.entities,all)
 p=all.find{|e|e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile' && e.get_attribute(DICT,'pile_id','').to_s==pile_id.to_s}
 return unless p
 sel=Sketchup.active_model.selection;sel.clear;sel.add(p);Sketchup.active_model.active_view.zoom(sel)
end

def pile_fabrication_qto_row(piles, label, raw_quantities=false)
 return nil if piles.empty?
 e=piles.first
 d=e.get_attribute(DICT,'diameter_mm',0).to_f/1000.0
 t=e.get_attribute(DICT,'thickness_mm',0).to_f/1000.0
 di=d-2.0*t
 count=piles.length
 fab_len=piles.sum{|p|p.get_attribute(DICT,'actual_length_m',p.get_attribute(DICT,'length_m',0)).to_f}
 driving=piles.sum{|p| pile_driving_length(p)}
 pile_kg=piles.sum{|p|mst_pile_canonical_weight_kg(p)}
 plug_count=piles.sum{|p|p.get_attribute(DICT,'plug_enabled','0').to_s=='1' ? [p.get_attribute(DICT,'plug_count_per_pile',1).to_i,1].max : 0}
 plug_kg=piles.sum do |p|
  next 0.0 unless p.get_attribute(DICT,'plug_enabled','0').to_s=='1'
  dd=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0; tt=p.get_attribute(DICT,'thickness_mm',0).to_f/1000.0
  clr=p.get_attribute(DICT,'plug_clearance_mm',10).to_f/1000.0
  dp=[dd-2.0*tt-2.0*clr,0.0].max
  th=p.get_attribute(DICT,'plug_thickness_mm',12).to_f/1000.0
  n=[p.get_attribute(DICT,'plug_count_per_pile',1).to_i,1].max
  Math::PI/4.0*dp*dp*th*RHO*n
 end
 upper_kg=piles.sum do |p|
  next 0.0 unless p.get_attribute(DICT,'upper_ring_enabled','0').to_s=='1'
  dd=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0
  w=p.get_attribute(DICT,'upper_ring_width_mm',250).to_f/1000.0; th=p.get_attribute(DICT,'upper_ring_thickness_mm',p.get_attribute(DICT,'thickness_mm',0)).to_f/1000.0
  n=[p.get_attribute(DICT,'upper_ring_count_per_pile',1).to_i,1].max
  Math::PI*(dd+th)*w*th*RHO*n
 end
 lower_kg=piles.sum do |p|
  next 0.0 unless p.get_attribute(DICT,'lower_ring_enabled','0').to_s=='1'
  dd=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0; tt=p.get_attribute(DICT,'thickness_mm',0).to_f/1000.0; ddi=[dd-2.0*tt,0.0].max
  w=p.get_attribute(DICT,'lower_ring_width_mm',300).to_f/1000.0; th=p.get_attribute(DICT,'lower_ring_thickness_mm',p.get_attribute(DICT,'thickness_mm',0)).to_f/1000.0
  n=[p.get_attribute(DICT,'lower_ring_count_per_pile',1).to_i,1].max
  Math::PI*[ddi-th,0.0].max*w*th*RHO*n
 end
 splice_count=piles.sum{|p|pile_splice_count(p)}
 concrete=piles.sum{|p|pile_qto_concrete(p)}
 pe_area=piles.sum do |p|
  next 0.0 unless p.get_attribute(DICT,'pe_enabled','0').to_s=='1'
  Math::PI*(p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0)*[p.get_attribute(DICT,'pe_length_m',0).to_f,0.0].max
 end
 drilling=piles.sum{|p|p.get_attribute(DICT,'drilling_enabled','0').to_s=='1' ? [p.get_attribute(DICT,'drilling_length_m',0).to_f,0.0].max : 0.0}
 manipulation_t=(pile_kg+upper_kg+lower_kg)/1000.0
 # BOQ calculations consume full precision; presentation rounding stays below.
 return [label,d,t,count,plug_count,splice_count,fab_len,driving,plug_kg/1000.0,pile_kg/1000.0,upper_kg,lower_kg,manipulation_t,concrete,pe_area,drilling] if raw_quantities
 [label,(d).round(4),(t).round(4),count,plug_count,splice_count,fab_len.round(2),driving.round(2),(plug_kg/1000.0).round(3),(pile_kg/1000.0).round(3),upper_kg.round(2),lower_kg.round(2),manipulation_t.round(3),concrete.round(3),pe_area.round(2),drilling.round(2)]
end

def select_pile_qto_group(payload)
 data=payload.is_a?(String) ? JSON.parse(payload) : payload
 all=[];collect_elements(Sketchup.active_model.entities,all)
 hits=all.select{|p|pile_qto_match?(p,data)}
 sel=Sketchup.active_model.selection;sel.clear;hits.each{|e|sel.add(e)}
 Sketchup.active_model.active_view.zoom(sel) unless hits.empty?
rescue => e
 UI.messagebox("Kazık metraj grubu seçim hatası: #{e.message}")
end

MST_QTO_DETAIL_TYPE_NAMES={'steel_pipe_pile'=>'Çelik Boru Kazık','pile_infill_concrete'=>'Kazık İçi Beton','head_beam'=>'Başlık Kirişi','flat_precast'=>'Normal Prekast','channel_precast'=>'Kanal Prekastı','crane_precast'=>'Vinç Prekastı','deck_slab'=>'Döşeme','curb'=>'Bordür / Tretuvar','crown_wall'=>'Kronman','bored_pile'=>'Fore Kazık'}.freeze

# ADR-0515 G5 (salt okuma): Ayrıntılı Metraj satırları — Excel 'Ayrıntılı Metraj' sayfası ve Keşif / Metraj CSV ortak kaynağı.
# Satır: [Eleman, Tip, Malzeme / Sınıf, Adet, Boy, Beton, Kalıp, Çelik (birleşik), Boru Çeliği, Donatı]; rounded=false → yuvarlanmamış (CSV).
def mst_qto_detail_rows(all,snapshot,rounded=true)
  allowed=%w[steel_pipe_pile pile_infill_concrete head_beam flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile]
  elems=all.select{|e|allowed.include?(e.get_attribute(DICT,'element_type','').to_s)}
  type_names=MST_QTO_DETAIL_TYPE_NAMES
  rd=rounded ? ->(v,n){v.round(n)} : ->(v,_n){v}
  groups=elems.group_by{|e|[e.get_attribute(DICT,'element_type','').to_s,e.get_attribute(DICT,'library_type_id',element_signature(e)).to_s,qto_material_class(e)]}
  detail=[]
  groups.sort_by{|k,a|k.join('|')}.each do |k,arr|
    detail<<[type_names[k[0]]||k[0],k[1],k[2],arr.length,
      rd.(arr.sum{|e|qto3_quantity(e,:length_m)},2),
      rd.(arr.sum{|e|qto3_quantity(e,:concrete_m3)},3),
      rd.(arr.sum{|e|qto3_quantity(e,:formwork_m2)},2),
      rd.(arr.sum{|e|qto3_quantity(e,:steel_t)},3)]
    detail.last.concat(k[0]=='steel_pipe_pile' ? [detail.last[7],0.0] : [0.0,detail.last[7]])   # v0.51.5 K41: Boru Çeliği / Donatı ayrı (birleşik sütun uyumluluk için kalır)
  end
  fallback=snapshot[:rows].find{|row|row[:type]=='pile_infill_concrete'}
  if fallback
    detail.reject!{|row|row[0]==type_names['pile_infill_concrete']}   # v0.51.5 F1: fiziksel iç beton satırları Özet satırında zaten var
    detail<<['Kazık İçi Beton','Tüm kaynaklar','Sınıf bazında Özet',fallback[:count],fallback[:length_m],fallback[:concrete_m3],fallback[:formwork_m2],fallback[:steel_t],0.0,fallback[:steel_t]]
  end
  detail
end

# ADR-0515 G6 (salt okuma): kaplama betonu sınıf bazında {sınıf=>hacim}; toplam = topping_quantities(all)[1]. Sınıfsız kaplama C35/45 (kaplama formu varsayılanı).
def mst_topping_by_class(all)
  decks=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='deck_slab'};rest=all-decks
  decks.group_by{|d|c=d.get_attribute(DICT,'topping_concrete_class','').to_s.strip;c.empty? ? 'C35/45' : c}.map{|cc,ds|[cc,topping_quantities(rest+ds)[1]]}.to_h
end

# ADR-0515 G5 (salt okuma): Keşif / Metraj CSV satırları = Ayrıntılı Metraj satırları + 'Keşif ek kalemi' satırları (yuvarlanmamış).
# Sütunlar: Kategori, Tip, Malzeme/Sinif, Adet, Boy_m, Beton_m3, Kalip_m2, Celik_t (boru çeliği), Donati_t (Keşif ÖBF-004 dökümüyle aynı kaynak).
def mst_boq_csv_rows(all)
  snapshot=qto3_snapshot
  bd=mst_boq_rebar_breakdown(all)
  kg=->(key){bd.select{|r|r[:key].to_s==key}.sum{|r|r[:kg].to_f}}
  chair=bd.any?{|r|r[:key].to_s=='chair'}   # sehpa ayrı satırdaysa BK / döşeme satırından düşülür (mst_v50_breakdown_extras kuralı)
  typ=->(e){e.get_attribute(DICT,'element_type','').to_s}
  allowed=%w[steel_pipe_pile pile_infill_concrete head_beam flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile]
  groups=all.select{|e|allowed.include?(typ.(e))}.group_by{|e|[typ.(e),e.get_attribute(DICT,'library_type_id',element_signature(e)).to_s,qto_material_class(e)]}
  rebar_of={}
  groups.each do |k,arr|
   next if %w[steel_pipe_pile pile_infill_concrete].include?(k[0])
   r=mst_rebar_sum(arr)['kg']
   r-=arr.sum{|e|mst_v50_chair_kg(e)} if chair && %w[head_beam deck_slab].include?(k[0])
   rebar_of[[MST_QTO_DETAIL_TYPE_NAMES[k[0]]||k[0],k[1],k[2]]]=r/1000.0
  end
  infill_row=false
  rows=mst_qto_detail_rows(all,snapshot,false).map do |d|
   cat=MST_QTO_DETAIL_TYPE_NAMES.key(d[0]) || d[0]
   if d[1]=='Tüm kaynaklar' && cat=='pile_infill_concrete'
    infill_row=true;don=kg.('pile')/1000.0
   else
    don=cat=='pile_infill_concrete' ? 0.0 : rebar_of.fetch([d[0],d[1],d[2]],0.0)
   end
   [cat,d[1],d[2],d[3],d[4],d[5],d[6],d[8],don]
  end
  ek='Keşif ek kalemi'
  rows << [ek,'Kazık içi donatı','-',0,0.0,0.0,0.0,0.0,kg.('pile')/1000.0] if !infill_row && kg.('pile').abs>1e-12
  decks=all.select{|e|typ.(e)=='deck_slab'}
  mst_topping_by_class(all).sort.each{|cc,vol|rows << [ek,'Kaplama Betonu',cc,decks.count{|d|(d.get_attribute(DICT,'topping_concrete_class','').to_s.strip.empty? ? 'C35/45' : d.get_attribute(DICT,'topping_concrete_class','').to_s.strip)==cc},0.0,vol,0.0,0.0,vol*rebar_rate('topping')/1000.0] if vol>0}
  rows << [ek,'Sehpa','-',0,0.0,0.0,0.0,0.0,kg.('chair')/1000.0] if chair
  rows << [ek,'Aksesuar ankrajı','-',0,0.0,0.0,0.0,0.0,kg.('acc_anchor')/1000.0] if bd.any?{|r|r[:key].to_s=='acc_anchor'}
  rows
end

def export_professional_excel
  all=[];collect_elements(Sketchup.active_model.entities,all)
  allowed=%w[steel_pipe_pile pile_infill_concrete head_beam flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile]
  elems=all.select{|e|allowed.include?(e.get_attribute(DICT,'element_type','').to_s)}
  path=UI.savepanel('Ayrıntılı Metraj (Excel) Raporu','','MST_Ayrintili_Metraj.xlsx');return unless path
  path+='.xlsx' unless path.downcase.end_with?('.xlsx')
  type_names=MST_QTO_DETAIL_TYPE_NAMES
  snapshot=qto3_snapshot
  detail=mst_qto_detail_rows(all,snapshot)   # ADR-0515 G5: Keşif / Metraj CSV ile ortak satırlar
  piles=elems.select{|e|e.get_attribute(DICT,'element_type')=='steel_pipe_pile'}
  topping_vol=topping_quantities(all)[1]
  summary=[
    ['Toplam Çelik Boru Kazık',piles.length,'adet'],
    ['Toplam Kazık Boyu',piles.sum{|e|qto3_quantity(e,:length_m)}.round(2),'m'],
    ['Toplam Kazık Çeliği',piles.sum{|e|qto3_quantity(e,:steel_t)}.round(3),'t'],
    ['Toplam Beton',snapshot[:totals][:concrete_m3]+topping_vol,'m³'],   # ADR-0515 G6: kaplama dahil (qto3_snapshot değişmez)
    ['Toplam Kalıp',elems.sum{|e|qto3_quantity(e,:formwork_m2)}.round(2),'m²']]
  # Concrete-class subtotals make the summary directly usable for BOQ checks.
  snapshot[:concrete_by_class].sort.each{|cc,vol|summary<<["Beton #{cc}",vol,'m³']}
  mst_topping_by_class(all).sort.each{|cc,vol|summary<<["Beton Kaplama (#{cc})",vol,'m³'] if vol>0}   # G6: sınıf satırları + kaplama = Toplam Beton
  library=elems.group_by{|e|e.get_attribute(DICT,'library_type_id',element_signature(e)).to_s}.sort.map do |typ,arr|
    [typ,type_names[arr.first.get_attribute(DICT,'element_type').to_s]||arr.first.get_attribute(DICT,'element_type').to_s,qto_material_class(arr.first),arr.length,arr.map{|e|element_visible_id(e)}.join(', '),arr.first.get_attribute(DICT,'type_signature',element_signature(arr.first)).to_s]
  end
  pile_headers=['Sistem / Yapı / Kesit','Kazık Çapı (mm)','Et Kalınlığı (mm)','Kazık Adedi','Tapa Adedi','Ek Adedi','Kazık İmal Boyu (m)','Çakım Boyu (m)','Tapa (t)','Kazık İmal (t)','Üst Çember (kg)','Alt Çember (kg)','Manipülasyon (t)','Beton (m³)','PE Kaplama (m²)','Foraj (m)']
  pile_rows=pile_qto_hierarchy(piles).map do |item|
    row=item[:values].dup
    row[0]=item[:level]=='system' ? "#{item[:zone]} — GENEL TOPLAM" :
      (item[:level]=='structure' ? "  #{item[:structure_label] || item[:structure]} — ARA TOPLAM" : "    #{item[:zone]} / #{item[:structure_label] || item[:structure]} / #{item[:label]}")
    row[1]=item[:diameter_mm] || '—';row[2]=item[:thickness_mm] || '—'
    row
  end
  total_row=pile_fabrication_qto_row(piles,'PROJE GENEL TOPLAMI',true)
  if total_row;total_row[1]='—';total_row[2]='—';pile_rows<<total_row;end
  status=qto_workspace_status(elems.reject{|e|e.get_attribute(DICT,'element_type','')=='pile_infill_concrete'},piles)
  status[:messages].each{|message|summary<<['Kontrol notu',message,'']}
  summary<<['Ek hesabı','AUTO: 12 m boydan hesaplanır; MANUAL: kayıtlı adet','']
  summary<<['Sürüm',VERSION,'']
  sheets=[
    ['Özet',['Kalem','Miktar','Birim'],summary,[34,16,12]],
    ['Ayrıntılı Metraj',['Eleman','Tip','Malzeme / Sınıf','Adet','Boy (m)','Beton (m³)','Kalıp (m²)','Çelik (t)','Boru Çeliği (t)','Donatı (t)'],detail,[24,20,20,10,14,16,16,14,16,14]],
    ['Eleman Kütüphanesi',['Tip ID','Eleman','Malzeme / Sınıf','Adet','Fiziksel ID','Tip İmzası'],library,[20,24,20,10,45,65]],
    ['Kazık Metrajı',pile_headers,pile_rows,[22,16,16,13,12,14,18,16,13,15,20,20,18,18,24,14]]]
  sheets.concat(system_export_sheets)
  content_types='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+sheets.each_index.map{|i|"<Override PartName=\"/xl/worksheets/sheet#{i+1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"}.join+'</Types>'
  root_rels='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
  workbook='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+sheets.each_with_index.map{|s,i|"<sheet name=\"#{xml_escape(s[0])}\" sheetId=\"#{i+1}\" r:id=\"rId#{i+1}\"/>"}.join+'</sheets></workbook>'
  wb_rels='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+sheets.each_with_index.map{|s,i|"<Relationship Id=\"rId#{i+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet#{i+1}.xml\"/>"}.join+"<Relationship Id=\"rId#{sheets.length+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
  styles='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.000"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>'
  entries={'[Content_Types].xml'=>content_types,'_rels/.rels'=>root_rels,'xl/workbook.xml'=>workbook,'xl/_rels/workbook.xml.rels'=>wb_rels,'xl/styles.xml'=>styles}
  sheets.each_with_index{|s,i|entries["xl/worksheets/sheet#{i+1}.xml"]=xlsx_sheet_xml(s[1],s[2],s[3])}
  write_simple_zip(path,entries)
  # Sanity check: an XLSX must start with the ZIP signature and contain three worksheets.
  raise 'XLSX dosyası oluşturulamadı.' unless File.exist?(path) && File.size(path)>1000
  UI.messagebox("Ayrıntılı Metraj (Excel) oluşturuldu.\nGerçek Excel XLSX • #{sheets.length} çalışma sayfası\nÖzet / Ayrıntılı Metraj / Eleman Kütüphanesi / Kazık Metrajı\n#{path}")
rescue=>ex;UI.messagebox("Ayrıntılı Metraj (Excel) dışa aktarma hatası: #{ex.message}");end
# ===== end v0.14.0 =====


# ===== v0.20.0 Universal Element Editor 2.0 =====
def mst_unique_elements(arr)
  seen={}
  arr.select do |e|
    key=e.get_attribute(DICT,'element_uid','').to_s
    key="pid:#{e.persistent_id}" if key.empty?
    next false if seen[key]
    seen[key]=true
  end
end

def mst_editor_changes(e,o)
  pairs=[['Eleman ID',element_visible_id(e),o['id']],['Proje',e.get_attribute(DICT,'project',''),o['project']],['Ano',e.get_attribute(DICT,'ano',''),o['ano']],['Aks',e.get_attribute(DICT,'axis',''),o['axis']],['Bölge',e.get_attribute(DICT,'zone',''),o['zone']]]
  t=e.get_attribute(DICT,'element_type','').to_s
  if t=='steel_pipe_pile'
    pairs += [['Ø mm',e.get_attribute(DICT,'diameter_mm',0),o['diameter_mm']],['t mm',e.get_attribute(DICT,'thickness_mm',0),o['thickness_mm']],['Boy m',e.get_attribute(DICT,'length_m',0),o['length_m']],['Üst Kot',e.get_attribute(DICT,'top_elevation_m',0),o['top_elevation_m']],['Rake X',e.get_attribute(DICT,'rake_x_hv',0),o['rake_x_hv']],['Rake Y',e.get_attribute(DICT,'rake_y_hv',0),o['rake_y_hv']],['Çelik',e.get_attribute(DICT,'steel_grade',''),o['steel_grade']]]
  else
    pairs += [['Boy m',e.get_attribute(DICT,'length_m',0),o['length_m']],['Genişlik m',e.get_attribute(DICT,'width_m',0),o['width_m']],['Yükseklik m',e.get_attribute(DICT,'height_m',0),o['height_m']],['Beton',e.get_attribute(DICT,'concrete_class',''),o['concrete_class']]]
    if t=='channel_precast'; pairs += [['İç Genişlik m',e.get_attribute(DICT,'inner_width_m',0),o['inner_width_m']],['İç Derinlik m',e.get_attribute(DICT,'inner_depth_m',0),o['inner_depth_m']],['Taban t m',e.get_attribute(DICT,'base_thickness_m',0),o['base_thickness_m']],['Duvar t m',e.get_attribute(DICT,'wall_thickness_m',0),o['wall_thickness_m']]]; end
  end
  pairs.select{|_,a,b| !b.nil? && a.to_s!=b.to_s && (a.is_a?(Numeric) ? (a.to_f-b.to_f).abs>0.000001 : a.to_s!=b.to_s)}.map{|name,a,b|"• #{name}: #{a} → #{b}"}
end

def preview_editor_change(json,dialog=@d)
  e=selected_mst_element; return dialog.execute_script("showEditorChangePreview(#{JSON.generate({'ok'=>false,'message'=>'Önce bir MST elemanı seçin.'})},#{JSON.generate(json)})") unless e
  o=JSON.parse(json); scope=o['scope'].to_s; type_id=e.get_attribute(DICT,'library_type_id',e.get_attribute(DICT,'type_id','')).to_s
  targets=[e]
  if scope=='type'
    targets=mst_all_elements.select{|x|x.get_attribute(DICT,'library_type_id',x.get_attribute(DICT,'type_id','')).to_s==type_id && x.get_attribute(DICT,'element_type','').to_s==e.get_attribute(DICT,'element_type','').to_s}
  end
  deps=[]; targets.each{|x|deps.concat(mst_dependency_tree(x).map{|r|r[0]})};deps=mst_unique_elements(deps)
  impacts=targets.flat_map{|x|mst_dependency_impacts(x)}.uniq
  p={'ok'=>true,'scope_label'=>(scope=='type' ? 'Bu Tipteki Tüm Elemanlar' : 'Yalnız Seçili Eleman'),'target_count'=>targets.length,'type_id'=>type_id,'changes'=>mst_editor_changes(e,o),'affected_count'=>deps.length,'impacts'=>impacts}
  dialog.execute_script("showEditorChangePreview(#{JSON.generate(p)},#{JSON.generate(json)})")
rescue=>ex
  dialog.execute_script("showEditorChangePreview(#{JSON.generate({'ok'=>false,'message'=>ex.message})},#{JSON.generate(json)})") rescue nil
end

def stamp_dependency_metadata_silent
  all=mst_all_elements; model=Sketchup.active_model
  model.start_operation('MST Bağımlılık Bilgisi Yenile',true)
  all.each do |e|
    deps=mst_direct_dependencies(e,all);parents=mst_direct_parents(e,all)
    e.set_attribute(DICT,'dependency_child_uids',deps.map{|x|ensure_uid(x)}.uniq.join(','));e.set_attribute(DICT,'dependency_child_ids',deps.map{|x|element_visible_id(x)}.uniq.join(','));e.set_attribute(DICT,'dependency_parent_uids',parents.map{|x|ensure_uid(x)}.uniq.join(','));e.set_attribute(DICT,'dependency_parent_ids',parents.map{|x|element_visible_id(x)}.uniq.join(','));e.set_attribute(DICT,'dependency_schema','2.1')
  end
  model.set_attribute(DICT,'dependency_schema_version','2.1');model.set_attribute(DICT,'dependency_revision','v0.20.0');commit_with_dependencies(model)
rescue
  model.abort_operation rescue nil
end
# ===== end v0.20.0 =====



# ===== v0.20.0 Project / Ano / Axis Manager =====
def mst_project_elements
  mst_all_elements.select{|e| %w[steel_pipe_pile head_beam flat_precast channel_precast crane_precast deck_slab curb crown_wall bored_pile].include?(e.get_attribute(DICT,'element_type','').to_s)}
end

def mst_axis_label(v)
  x=v.to_s.strip
  return '' if x.empty?
  return x if x.upcase.start_with?('AKS-')
  n=x.to_i
  n>0 ? "AKS-#{n.to_s.rjust(2,'0')}" : x
end

def mst_project_structure_rows
  elems=mst_project_elements
  elems.group_by{|e| [e.get_attribute(DICT,'project','').to_s,e.get_attribute(DICT,'ano','').to_s]}.sort_by{|k,v|k.join('|')}.map do |key,arr|
    project=key[0].empty? ? '(Proje Atanmamış)' : key[0]
    ano=key[1].empty? ? '(Ano Atanmamış)' : key[1]
    axes=arr.map{|e|mst_axis_label(e.get_attribute(DICT,'axis',''))}.reject(&:empty?).uniq.sort
    counts=arr.group_by{|e|e.get_attribute(DICT,'element_type','').to_s}.transform_values(&:length)
    {project:project,ano:ano,axes:axes,count:arr.length,counts:counts}
  end
end

def auto_organize_project(data)
  model=Sketchup.active_model; elems=mst_project_elements
  project=data['project'].to_s.strip; ano=data['ano'].to_s.strip
  raise 'Proje adı boş olamaz.' if project.empty?
  raise 'Ano adı boş olamaz.' if ano.empty?
  op=false   # v0.51.5 H1: doğrulama hatası işlem açılmadan abort çağırmaz (önceki işlemi geri almaz)
  model.start_operation('MST Proje / Ano / Aks Düzenle',true);op=true
  # First standardize identity/type metadata without opening another operation.
  elems.each{|e| ensure_uid(e)}
  beams=elems.select{|e|e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
  beams.sort_by!{|b| a=b.get_attribute(DICT,'axis','').to_s; n=a.to_i; n>0 ? n : b.persistent_id}
  beams.each_with_index do |b,i|
    ax=mst_axis_label(b.get_attribute(DICT,'axis',''))
    ax="AKS-#{(i+1).to_s.rjust(2,'0')}" if ax.empty?
    b.set_attribute(DICT,'project',project);b.set_attribute(DICT,'ano',ano);b.set_attribute(DICT,'axis',ax);b.set_attribute(DICT,'zone',ano)
  end
  # Piles inherit Project/Ano/Axis from the HB that contains their visible pile ID.
  piles=elems.select{|e|e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
  piles.each do |p|
    pid=element_visible_id(p); b=beams.find{|x|mst_pile_ids_for_beam(x).include?(pid)}
    p.set_attribute(DICT,'project',project);p.set_attribute(DICT,'ano',ano)
    p.set_attribute(DICT,'axis',b ? b.get_attribute(DICT,'axis','').to_s : mst_axis_label(p.get_attribute(DICT,'axis','')))
    p.set_attribute(DICT,'zone',ano)
  end
  # Bored piles are independent of the steel-pile/head-beam chain. Preserve a manually
  # assigned axis; Project/Ano are still organized centrally. If axis is blank, Audit asks
  # for a manual axis instead of inventing one from an unrelated head beam.
  bored=elems.select{|e|e.get_attribute(DICT,'element_type','').to_s=='bored_pile'}
  bored.each do |p|
    p.set_attribute(DICT,'project',project);p.set_attribute(DICT,'ano',ano);p.set_attribute(DICT,'zone',ano)
    ax=mst_axis_label(p.get_attribute(DICT,'axis',''))
    p.set_attribute(DICT,'axis',ax) unless ax.empty?
  end
  # Crown walls can be spatially independent from the pier grid. Project/Ano are assigned,
  # but an empty axis is valid. A manual axis can still be assigned when the project needs it.
  crowns=elems.select{|e|e.get_attribute(DICT,'element_type','').to_s=='crown_wall'}
  crowns.each do |c|
    c.set_attribute(DICT,'project',project);c.set_attribute(DICT,'ano',ano);c.set_attribute(DICT,'zone',ano)
    ax=mst_axis_label(c.get_attribute(DICT,'axis',''))
    c.set_attribute(DICT,'axis',ax) unless ax.empty?
  end

  # PD / Kanal inherit both supports and store a span label.
  prec=elems.select{|e|%w[flat_precast channel_precast crane_precast].include?(e.get_attribute(DICT,'element_type','').to_s)}
  prec.each do |p|
    lp=p.get_attribute(DICT,'support_left_pid',0).to_i; rp=p.get_attribute(DICT,'support_right_pid',0).to_i
    l=beams.find{|b|b.persistent_id==lp}; r=beams.find{|b|b.persistent_id==rp}
    p.set_attribute(DICT,'project',project);p.set_attribute(DICT,'ano',ano);p.set_attribute(DICT,'zone',ano)
    if l&&r
      la=l.get_attribute(DICT,'axis','').to_s;ra=r.get_attribute(DICT,'axis','').to_s
      p.set_attribute(DICT,'axis_span',"#{la} ↔ #{ra}");p.set_attribute(DICT,'axis',"#{la}↔#{ra}")
      p.set_attribute(DICT,'support_left_uid',ensure_uid(l));p.set_attribute(DICT,'support_right_uid',ensure_uid(r))
    end
  end
  # Decks derive their axis range from support_pids. Curbs inherit from parent deck when possible.
  decks=elems.select{|e|e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
  decks.each do |d|
    pids=d.get_attribute(DICT,'support_pids','').to_s.split(',').map(&:to_i)
    bs=beams.select{|b|pids.include?(b.persistent_id)}
    d.set_attribute(DICT,'project',project);d.set_attribute(DICT,'ano',ano);d.set_attribute(DICT,'zone',ano)
    unless bs.empty?
      axs=bs.map{|b|b.get_attribute(DICT,'axis','').to_s}.reject(&:empty?)
      d.set_attribute(DICT,'axis_span',"#{axs.first} ↔ #{axs.last}") unless axs.empty?
      d.set_attribute(DICT,'axis',axs.join(','))
    end
  end
  curbs=elems.select{|e|e.get_attribute(DICT,'element_type','').to_s=='curb'}
  curbs.each do |c|
    c.set_attribute(DICT,'project',project);c.set_attribute(DICT,'ano',ano);c.set_attribute(DICT,'zone',ano)
    pu=c.get_attribute(DICT,'parent_uid','').to_s; d=decks.find{|x|ensure_uid(x)==pu}
    if d;c.set_attribute(DICT,'axis',d.get_attribute(DICT,'axis','').to_s);c.set_attribute(DICT,'axis_span',d.get_attribute(DICT,'axis_span','').to_s);end
  end
  refresh_dependency_metadata_inline
  model.set_attribute(DICT,'project_name',project);model.set_attribute(DICT,'active_ano',ano);model.set_attribute(DICT,'project_structure_revision','v0.20.0')
  commit_with_dependencies(model);op=false
  {elements:elems.length,beams:beams.length,piles:piles.length,bored:bored.length,crowns:crowns.length,precast:prec.length,decks:decks.length,curbs:curbs.length}
rescue=>ex
  (model.abort_operation rescue nil) if op; raise ex
end

def assign_manual_axis_to_selection(data)
  model=Sketchup.active_model
  project=data['project'].to_s.strip
  ano=data['ano'].to_s.strip
  axis=mst_axis_label(data['axis'].to_s.strip)
  raise 'Proje adı boş olamaz.' if project.empty?
  raise 'Ano adı boş olamaz.' if ano.empty?
  raise 'Manuel aks adı boş olamaz.' if axis.empty?
  selected=model.selection.to_a.select{|e| e.respond_to?(:get_attribute) && mst_project_elements.include?(e)}
  raise 'Önce MST elemanı/elemanları seçin.' if selected.empty?
  op=false   # v0.51.5 H1: doğrulama hatası işlem açılmadan abort çağırmaz
  model.start_operation('MST Elle Aks Ataması',true);op=true
  selected.each do |e|
    ensure_uid(e)
    e.set_attribute(DICT,'project',project)
    e.set_attribute(DICT,'ano',ano)
    e.set_attribute(DICT,'zone',ano)
    e.set_attribute(DICT,'axis',axis)
    e.set_attribute(DICT,'axis_assignment','manual')
  end
  model.set_attribute(DICT,'project_name',project)
  model.set_attribute(DICT,'active_ano',ano)
  refresh_dependency_metadata_inline
  commit_with_dependencies(model);op=false
  {count:selected.length,axis:axis}
rescue=>ex
  (model.abort_operation rescue nil) if op
  raise ex
end

# v0.51.5 H1 (K43): Uzantılar → Deniz Yapıları Araçları (MST) → Tüm araçlar (eski menü) → "Seçili Elemana Elle Aks Ata…".
# Daraltılmış yazım: yalnız axis ve axis_assignment='manual'; project yalnız elemanda boşsa yazılır.
# ano / zone / active_ano yazılmaz (yapı üyeliği ano'ya dayanır). Doğrulamalar işlemden önce; normal işlem, tek Geri Al.
def mst_manual_axis_targets(model=Sketchup.active_model)
  elems=mst_project_elements
  model.selection.to_a.select{|e| e.respond_to?(:get_attribute) && elems.include?(e)}
end

def mst_manual_axis_assign!(selected,axis,project,model=Sketchup.active_model)
  axis=mst_axis_label(axis.to_s.strip);project=project.to_s.strip
  raise 'Aks adı boş olamaz.' if axis.empty?
  raise 'Önce MST elemanı/elemanları seçin.' if selected.empty?
  op=false
  model.start_operation('MST Elle Aks Ataması',true);op=true
  filled=0
  selected.each do |e|
    e.set_attribute(DICT,'axis',axis)
    e.set_attribute(DICT,'axis_assignment','manual')
    next if project.empty? || !e.get_attribute(DICT,'project','').to_s.strip.empty?
    e.set_attribute(DICT,'project',project);filled+=1
  end
  commit_with_dependencies(model);op=false
  {count:selected.length,axis:axis,project_filled:filled}
rescue=>ex
  (model.abort_operation rescue nil) if op
  raise ex
end

def mst_manual_axis_ui
  model=Sketchup.active_model
  selected=mst_manual_axis_targets(model)
  if selected.empty?
    UI.messagebox('Önce modelde bir veya birden fazla MST elemanı seçin (kazık, BK, prekast, döşeme, tretuvar, kronman, fore kazık).')
    return 0
  end
  project=model.get_attribute(DICT,'project_name','').to_s
  r=UI.inputbox(['Aks adı (ör. AKS-03 veya 3)','Proje adı (yalnız proje bilgisi boş elemanlara yazılır)'],['',project],"Seçili Elemana Elle Aks Ata (#{selected.length} eleman)")
  return 0 unless r
  res=mst_manual_axis_assign!(selected,r[0],r[1],model)
  UI.messagebox("Elle aks atandı: #{res[:count]} eleman → #{res[:axis]}.#{res[:project_filled]>0 ? "\nProje adı boş olan #{res[:project_filled]} elemana proje adı yazıldı." : ''}\nAno / yapı bilgisi değiştirilmedi. Geometri değişmedi; tek Geri Al ile geri alınır.")
  res[:count]
rescue=>ex
  UI.messagebox("Elle aks ataması yapılamadı: #{ex.message}")
  0
end

def project_ano_axis_manager
  model=Sketchup.active_model
  project=model.get_attribute(DICT,'project_name','').to_s
  ano=model.get_attribute(DICT,'active_ano','ANO-01').to_s
  rows=mst_project_structure_rows
  body=String.new
  rows.each do |r|
    c=r[:counts]
    body << "<tr><td><b>#{html_escape(r[:project])}</b></td><td><b>#{html_escape(r[:ano])}</b></td><td>#{html_escape(r[:axes].join(', '))}</td><td class='n'>#{r[:count]}</td><td class='n'>#{c['steel_pipe_pile'].to_i}</td><td class='n'>#{c['bored_pile'].to_i}</td><td class='n'>#{c['head_beam'].to_i}</td><td class='n'>#{c['flat_precast'].to_i+c['channel_precast'].to_i}</td><td class='n'>#{c['deck_slab'].to_i}</td><td class='n'>#{c['crown_wall'].to_i}</td><td class='n'>#{c['curb'].to_i}</td></tr>"
  end
  html=%Q{<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:Arial;margin:0;background:#f3f7fa;color:#18364a}.top{background:#fff;border-bottom:1px solid #cadce7;padding:18px 22px;display:flex;justify-content:space-between}.top h2{margin:0;color:#073f73}.badge{background:#e7f4ff;color:#0874c9;border:1px solid #b9ddf5;border-radius:18px;padding:7px 12px;font-weight:700;font-size:11px}.wrap{padding:18px}.card{background:#fff;border:1px solid #cadce7;border-radius:9px;padding:15px;margin-bottom:14px}.grid{display:grid;grid-template-columns:1fr 1fr auto;gap:10px;align-items:end}label{font-size:11px;font-weight:700;color:#42677f}input{display:block;width:100%;box-sizing:border-box;margin-top:5px;padding:9px;border:1px solid #bfd2df;border-radius:6px}button{padding:10px 16px;border:0;border-radius:6px;background:#087fd1;color:#fff;font-weight:700;cursor:pointer}table{width:100%;border-collapse:collapse}th,td{font-size:11px;padding:8px;border-bottom:1px solid #e3edf3;text-align:left}th{background:#eaf3f8;color:#42677f}.n{text-align:right}.note{font-size:11px;color:#607d8b;line-height:1.5}.status{margin-top:10px;font-size:11px;color:#16834f;font-weight:700}</style></head><body><div class='top'><div><h2>Proje / Ano / Aks Yöneticisi</h2><div>MST BIM model organizasyonu</div></div><span class='badge'>v#{VERSION}</span></div><div class='wrap'><div class='card'><div class='grid'><label>Proje Adı<input id='project' value='#{html_escape(project)}' placeholder='Örn. EGE GÜBRE İSKELE TEVSİİ'></label><label>Aktif Ano<input id='ano' value='#{html_escape(ano)}' placeholder='ANO-01'></label><button onclick='organize()'>Projeyi / Ano'yu Organize Et</button></div><div class='note' style='margin-top:10px'>Otomatik organizasyon: BK aksları korunur; çelik boru kazıklar bağlı BK'dan, PD/Kanal destek BK'lardan, döşeme mesnet listesinden aks/açıklık devralır. Fore Kazık ve Kronman bağımsız eleman olabilir; bunlara ilgisiz BK aksı uydurulmaz.</div><div style='margin-top:14px;padding-top:14px;border-top:1px solid #e3edf3' class='grid'><label>Bağımsız / Elle Aks<input id='manual_axis' placeholder='Örn. AKS-KR-01 veya AKS-FK-01'></label><div class='note'>Modelde bir veya birden fazla MST elemanı seçin. Bu aks doğrudan seçili elemanlara atanır.</div><button onclick='manualAxis()'>Seçili Elemana Aks Ata</button></div><div id='status' class='status'></div></div><div class='card'><h3>Model Hiyerarşisi</h3><table><thead><tr><th>Proje</th><th>Ano</th><th>Aks / Açıklık</th><th>Toplam</th><th>Çelik Kazık</th><th>Fore Kazık</th><th>BK</th><th>PD/Kanal</th><th>Döşeme</th><th>Kronman</th><th>Tretuvar</th></tr></thead><tbody>#{body}</tbody></table></div></div><script>function base(){return {project:document.getElementById('project').value,ano:document.getElementById('ano').value}}function organize(){document.getElementById('status').textContent='Model organize ediliyor...';sketchup.project_organize(JSON.stringify(base()));}function manualAxis(){var d=base();d.axis=document.getElementById('manual_axis').value;document.getElementById('status').textContent='Seçili elemanlara elle aks atanıyor...';sketchup.project_manual_axis(JSON.stringify(d));}</script></body></html>}
  d=mst_html_dialog('project_manager',dialog_title:'Proje / Ano / Aks Yöneticisi',width:1120,height:650,resizable:true)
  d.set_html(EngineeringUI.decorate(html))
  d.add_action_callback('project_organize') do |dlg,json|
    begin
      r=auto_organize_project(JSON.parse(json)); UI.messagebox("Proje / Ano / Aks organizasyonu tamamlandı.\n\n#{r[:elements]} eleman işlendi.\n#{r[:beams]} BK • #{r[:piles]} çelik kazık • #{r[:bored]} fore kazık • #{r[:precast]} PD/Kanal • #{r[:decks]} döşeme • #{r[:crowns]} kronman • #{r[:curbs]} tretuvar\n\nBağımsız elemanların mevcut elle verilmiş aksları korunur.")
    rescue=>ex; UI.messagebox("Proje Yöneticisi hatası: #{ex.message}"); end
  end
  d.add_action_callback('project_manual_axis') do |dlg,json|
    begin
      r=assign_manual_axis_to_selection(JSON.parse(json)); UI.messagebox("Manuel aks atandı.\n\n#{r[:count]} eleman → #{r[:axis]}\n\nGeometri değiştirilmedi; işlem Ctrl+Z ile geri alınabilir.")
    rescue=>ex; UI.messagebox("Manuel Aks hatası: #{ex.message}"); end
  end
  d.show; @project_manager_dialog=d
end
# ===== end v0.20.0 =====


# ===== Crown Wall / Kronman v2.0 =====
def crown_selected_edge
  Sketchup.active_model.selection.grep(Sketchup::Edge).first
end

def crown_section_points(d)
  top=d['top_elevation_m'].to_f; slab_top=d['base_top_elevation_m'].to_f; slab_bot=d['base_bottom_elevation_m'].to_f
  base_w=d['base_width_m'].to_f; wall_top=d['wall_top_width_m'].to_f; wall_bot=d['wall_bottom_width_m'].to_f; left_over=d['left_projection_m'].to_f
  raise 'Kot sırası Üst Kot > Taban Üst Kotu > Taban Alt Kotu olmalıdır.' unless top>slab_top && slab_top>slab_bot
  raise 'Genişlikler sıfırdan büyük olmalıdır.' unless base_w>0 && wall_top>0 && wall_bot>0
  raise 'Duvar taban genişliği toplam taban genişliğinden büyük olamaz.' if wall_bot>base_w
  raise 'Sol çıkma negatif olamaz.' if left_over<0
  vertical=(d['vertical_face']||'left').to_s
  if vertical=='right'
    xr=base_w-left_over; xl=xr-wall_bot
    pts=[[0,slab_bot],[base_w,slab_bot],[base_w,slab_top],[xr,slab_top],[xr,top],[xr-wall_top,top],[xl,slab_top],[0,slab_top]]
  else
    xl=left_over; xr=xl+wall_bot
    pts=[[0,slab_bot],[base_w,slab_bot],[base_w,slab_top],[xr,slab_top],[xl+wall_top,top],[xl,top],[xl,slab_top],[0,slab_top]]
  end
  if d['tooth_enabled'].to_s=='1'
    ts=d['tooth_start_m'].to_f; tw=d['tooth_width_m'].to_f; td=d['tooth_depth_m'].to_f
    raise 'Diş genişliği ve derinliği sıfırdan büyük olmalıdır.' unless tw>0 && td>0
    raise 'Diş taban sınırları içinde olmalıdır.' if ts<0 || ts+tw>base_w
    # integrate downward tooth into bottom polygon
    pts=[[0,slab_bot],[ts,slab_bot],[ts,slab_bot-td],[ts+tw,slab_bot-td],[ts+tw,slab_bot],[base_w,slab_bot]] + pts[2..-1]
  end
  crown_clean_section_points(pts)
end

def crown_clean_section_points(pts, tol=1.0e-8)
  clean=[]
  pts.each do |p|
    q=[p[0].to_f,p[1].to_f]
    next if clean.any? && (clean[-1][0]-q[0]).abs<=tol && (clean[-1][1]-q[1]).abs<=tol
    clean << q
  end
  if clean.length>1 && (clean[0][0]-clean[-1][0]).abs<=tol && (clean[0][1]-clean[-1][1]).abs<=tol
    clean.pop
  end
  changed=true
  while changed && clean.length>=3
    changed=false
    out=[]
    n=clean.length
    clean.each_with_index do |b,i|
      a=clean[(i-1)%n]; c=clean[(i+1)%n]
      cross=(b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0])
      if cross.abs<=tol && ((b[0]-a[0])*(c[0]-b[0])+(b[1]-a[1])*(c[1]-b[1]))>=-tol
        changed=true
      else
        out << b
      end
    end
    clean=out if out.length>=3
  end
  raise 'Kronman kesiti için yeterli benzersiz köşe oluşmadı. Kesit ölçülerini kontrol edin.' if clean.length<3
  clean
end

def crown_polygon_area(pts)
  pts.each_with_index.sum{|(x,z),i| x*pts[(i+1)%pts.length][1]-pts[(i+1)%pts.length][0]*z}.abs*0.5
end

def crown_extrude_section(parent, pts, origin, u, v, length_m, mat)
  pts=crown_clean_section_points(pts)
  world_pts=pts.map{|x,z| origin.offset(v,m(x)).offset(Z_AXIS,m(z))}
  face=parent.entities.add_face(world_pts)
  raise 'Kronman kesiti oluşturulamadı.' unless face
  # Extrude from station start toward increasing chainage (+u).
  # Previous condition forced the face normal to -u, so every interval was
  # generated backwards from its own start station and visible gaps appeared.
  face.reverse! if face.normal.dot(u)<0
  face.material=nil; face.back_material=nil; face.pushpull(m(length_m),true)
end

def crown_normalize_type(h)
  h=h||{}; {
    'top_elevation_m'=>h['top_elevation_m'].to_f,'base_top_elevation_m'=>h['base_top_elevation_m'].to_f,'base_bottom_elevation_m'=>h['base_bottom_elevation_m'].to_f,
    'base_width_m'=>h['base_width_m'].to_f,'wall_top_width_m'=>h['wall_top_width_m'].to_f,'wall_bottom_width_m'=>h['wall_bottom_width_m'].to_f,'left_projection_m'=>h['left_projection_m'].to_f,
    'vertical_face'=>(h['vertical_face']||'left'),'tooth_enabled'=>h['tooth_enabled'].to_s=='1'?'1':'0','tooth_start_m'=>h['tooth_start_m'].to_f,'tooth_width_m'=>h['tooth_width_m'].to_f,'tooth_depth_m'=>h['tooth_depth_m'].to_f
  }
end

def crown_formwork_flags(data)
  {
    'sea'=>data.fetch('formwork_sea','1').to_s=='1',
    'land'=>data.fetch('formwork_land','1').to_s=='1',
    'ends'=>data.fetch('formwork_ends','1').to_s=='1'
  }
end

def crown_formwork_edges(t,pts)
  # Kronman kalıbı yalnız boyuna DIŞ düşey/eğimli yüzlerdir.
  # Yatay taban/üst yüzleri ve taban dişinin TÜM yüzleri kalıp değildir.
  slab_bot=t['base_bottom_elevation_m'].to_f
  vertical=(t['vertical_face']||'left').to_s
  tol=1.0e-7
  edges=[]
  pts.each_with_index do |a,i|
    b=pts[(i+1)%pts.length]
    dx=b[0]-a[0]; dz=b[1]-a[1]
    next if dz.abs<=tol                         # yatay yüz: kalıp değil
    next if [a[1],b[1]].min < slab_bot-tol     # diş yüzü: kalıp değil
    len=Math.hypot(dx,dz)
    midx=(a[0]+b[0])*0.5
    edges << {len:len,midx:midx,a:a,b:b}
  end
  return {'sea'=>0.0,'land'=>0.0,'all'=>[]} if edges.empty?
  # Kesitin iki dış tarafını x konumuna göre ayır. Aynı taraftaki kısa taban
  # düşeyi de ilgili deniz/kara yüzüne eklenir; diş asla eklenmez.
  xmin=edges.map{|e|e[:midx]}.min; xmax=edges.map{|e|e[:midx]}.max
  sea_is_max = (vertical=='left')
  sea=0.0; land=0.0
  edges.each do |e|
    dmin=(e[:midx]-xmin).abs; dmax=(e[:midx]-xmax).abs
    is_max=dmax<dmin
    is_sea=sea_is_max ? is_max : !is_max
    e[:side]=is_sea ? 'sea' : 'land'
    is_sea ? sea+=e[:len] : land+=e[:len]
  end
  {'sea'=>sea,'land'=>land,'all'=>edges}
end

def crown_wall_edge_lengths(t,pts)
  x=crown_formwork_edges(t,pts)
  {'sea'=>x['sea'],'land'=>x['land']}
end

def crown_preview_quantities(data, axis_len=nil)
  types={'A'=>crown_normalize_type(data['type_a']),'B'=>crown_normalize_type(data['type_b'])}
  flags=crown_formwork_flags(data); intervals=data['intervals']||[]; total_v=0.0; total_fw=0.0
  intervals.each do |r|
    s=r['start_m'].to_f; e=r['end_m'].to_f; raise 'İstasyon bitişi başlangıçtan büyük olmalıdır.' unless e>s
    raise 'İstasyon aralığı seçili aks boyunu aşıyor.' if axis_len && e>axis_len+1e-6
    t=types[(r['type']||'A').to_s]||types['A']; pts=crown_section_points(t); area=crown_polygon_area(pts); l=e-s; total_v+=area*l
    wl=crown_wall_edge_lengths(t,pts)
    total_fw += wl['sea']*l if flags['sea']
    total_fw += wl['land']*l if flags['land']
  end
  if flags['ends'] && !intervals.empty?
    first_t=types[(intervals.first['type']||'A').to_s]||types['A']
    last_t=types[(intervals.last['type']||'A').to_s]||types['A']
    total_fw += crown_polygon_area(crown_section_points(first_t))
    total_fw += crown_polygon_area(crown_section_points(last_t))
  end
  [total_v,total_fw]
end

def crown_paint_formwork(seg,t,u,flags,form_mat,concrete_mat,paint_start=false,paint_end=false)
  # Uçlar yalnız gerçek hattın ilk/son kesitidir. Ara istasyon yüzleri kalıp değildir.
  # Boyuna kalıp: yatay olmayan, taban dişi altında kalmayan dış yüzler.
  slab_bot=t['base_bottom_elevation_m'].to_f
  vertical=(t['vertical_face']||'left').to_s
  longitudinal=[]
  seg.entities.grep(Sketchup::Face).each do |face|
    n=face.normal
    next if n.dot(u).abs > 0.999
    next if n.z.abs > 0.999 # yatay yüz
    bb=face.bounds; zmin=bb.min.z.to_m; zmax=bb.max.z.to_m
    next if zmin < slab_bot-0.002 # dişin tüm düşey/eğimli yüzleri hariç
    c=bb.center
    longitudinal << [face,c]
  end
  unless longitudinal.empty?
    vals=longitudinal.map{|fc| fc[1].x*(-u.y)+fc[1].y*u.x }
    vmin=vals.min; vmax=vals.max
    sea_is_max=(vertical=='left')
    longitudinal.each_with_index do |(face,c),i|
      val=vals[i]; is_max=(vmax-val).abs < (val-vmin).abs
      sea=sea_is_max ? is_max : !is_max
      flag=sea ? flags['sea'] : flags['land']
      mark_formwork_face(face,flag,form_mat,concrete_mat,sea ? 'CROWN_SEA' : 'CROWN_LAND')
    end
  end
  seg.entities.grep(Sketchup::Face).each do |face|
    n=face.normal
    next unless n.dot(u).abs > 0.999
    is_end=n.dot(u)>0
    flag=flags['ends'] && ((is_end && paint_end) || (!is_end && paint_start))
    mark_formwork_face(face,flag,form_mat,concrete_mat,flag ? (is_end ? 'CROWN_END' : 'CROWN_START') : 'INTERNAL_STATION_FACE')
  end
end

def crown_build_v2(data, existing=nil)
  model=Sketchup.active_model
  if existing
    sp=Geom::Point3d.new(existing.get_attribute(DICT,'axis_start_x'),existing.get_attribute(DICT,'axis_start_y'),existing.get_attribute(DICT,'axis_start_z'))
    ep=Geom::Point3d.new(existing.get_attribute(DICT,'axis_end_x'),existing.get_attribute(DICT,'axis_end_y'),existing.get_attribute(DICT,'axis_end_z'))
  else
    edge=crown_selected_edge; raise 'Önce Kronman/mendirek aksını temsil eden tek bir kenar seçiniz.' unless edge
    sp=edge.start.position; ep=edge.end.position
  end
  vec=ep-sp; axis_len=vec.length.to_m; raise 'Aks boyu sıfır.' if axis_len<=0
  u=vec.normalize; raise 'Aks yatay olmalıdır.' if u.z.abs>0.001
  left=Geom::Vector3d.new(-u.y,u.x,0).normalize
  side=(data['axis_side']||'left').to_s; v=side=='right' ? left.reverse : left
  offset=data['axis_offset_m'].to_f
  intervals=(data['intervals']||[]).sort_by{|r|r['start_m'].to_f}; raise 'En az bir istasyon aralığı tanımlayın.' if intervals.empty?
  intervals.each_cons(2){|a,b| raise 'İstasyon aralıkları çakışmamalıdır.' if a['end_m'].to_f>b['start_m'].to_f+1e-6}
  vol,fw=crown_preview_quantities(data,axis_len)
  types={'A'=>crown_normalize_type(data['type_a']),'B'=>crown_normalize_type(data['type_b'])}
  model.start_operation(existing ? 'Kronman Güncelle' : 'Kronman Oluştur',true)
  begin
    parent=model.entities.add_group; parent.name=(data['id'].to_s.empty? ? 'KR-001' : data['id'].to_s)
    form_hex=(data['formwork_color']||'#6DBE73').to_s
    mat=nil; form_mat=material_for(model,'MST_Kronman_Formwork',form_hex); fw_flags=crown_formwork_flags(data)
    intervals.each_with_index do |r,i|
      s=r['start_m'].to_f; e=r['end_m'].to_f; typ=(r['type']||'A').to_s; t=types[typ]||types['A']; pts=crown_section_points(t)
      origin=sp.offset(u,m(s)).offset(v,m(offset)); seg=parent.entities.add_group; seg.name="#{parent.name}_#{typ}_#{format('%03d',i+1)}"; crown_extrude_section(seg,pts,origin,u,v,e-s,mat); crown_paint_formwork(seg,t,u,fw_flags,form_mat,nil,(i==0),(i==intervals.length-1))
      seg.set_attribute(DICT,'station_start_m',s); seg.set_attribute(DICT,'station_end_m',e); seg.set_attribute(DICT,'section_type',typ); seg.set_attribute(DICT,'element_type','crown_wall_segment'); seg.set_attribute(DICT,'parent_crown_id',parent.name)
    end
    attrs={'element_type'=>'crown_wall','id'=>parent.name,'length_m'=>intervals.sum{|r|r['end_m'].to_f-r['start_m'].to_f},'concrete_volume_m3'=>vol,'formwork_area_m2'=>fw,'concrete_class'=>(data['concrete_class']||'C35/45'),'axis_side'=>side,'axis_offset_m'=>offset,'axis_start_x'=>sp.x,'axis_start_y'=>sp.y,'axis_start_z'=>sp.z,'axis_end_x'=>ep.x,'axis_end_y'=>ep.y,'axis_end_z'=>ep.z,'crown_type_a_json'=>JSON.generate(types['A']),'crown_type_b_json'=>JSON.generate(types['B']),'crown_intervals_json'=>JSON.generate(intervals),'formwork_color'=>form_hex,'formwork_sea'=>(fw_flags['sea'] ? '1':'0'),'formwork_land'=>(fw_flags['land'] ? '1':'0'),'formwork_ends'=>(fw_flags['ends'] ? '1':'0'),'crown_schema'=>'2.1'}
    attrs.each{|k,val|parent.set_attribute(DICT,k,val)}
    finalize_bim_identity(parent,model)
    existing.erase! if existing && existing.valid?; model.commit_operation; parent
  rescue=>e; model.abort_operation; raise e; end
end

def crown_axis_info(dialog)
  edge=crown_selected_edge
  return dialog.execute_script("crownAxisError(#{JSON.generate("Önce SketchUp'ta Kronman aksını temsil eden tek bir kenar seçin.")})") unless edge
  len=edge.length.to_m
  dialog.execute_script("crownAxisLoaded(#{JSON.generate({'length_m'=>len})})")
rescue=>e
  dialog.execute_script("crownAxisError(#{e.message.to_json})")
end

def crown_create_action(json)
  d=JSON.parse(json); crown_build_v2(d); UI.messagebox('Kronman oluşturuldu. İstasyon tipleri, geometri, beton ve kalıp metrajı kaydedildi.')
rescue=>e; UI.messagebox("Kronman hatası: #{e.message}"); end

def crown_load_selected(dialog)
  g=Sketchup.active_model.selection.grep(Sketchup::Group).find{|x|x.get_attribute(DICT,'element_type')=='crown_wall'}
  return dialog.execute_script("crownLoadError('Revize etmek için bir Kronman seçiniz.')") unless g
  d={'id'=>g.get_attribute(DICT,'id',g.name),'concrete_class'=>g.get_attribute(DICT,'concrete_class','C35/45'),'axis_side'=>g.get_attribute(DICT,'axis_side','left'),'axis_offset_m'=>g.get_attribute(DICT,'axis_offset_m',0).to_f,
     'type_a'=>JSON.parse(g.get_attribute(DICT,'crown_type_a_json','{}')),'type_b'=>JSON.parse(g.get_attribute(DICT,'crown_type_b_json','{}')),'intervals'=>JSON.parse(g.get_attribute(DICT,'crown_intervals_json','[]')),
     'old_volume_m3'=>g.get_attribute(DICT,'concrete_volume_m3',0).to_f,'old_formwork_m2'=>g.get_attribute(DICT,'formwork_area_m2',0).to_f,'formwork_color'=>g.get_attribute(DICT,'formwork_color','#6DBE73'),'formwork_sea'=>g.get_attribute(DICT,'formwork_sea','1'),'formwork_land'=>g.get_attribute(DICT,'formwork_land','1'),'formwork_ends'=>g.get_attribute(DICT,'formwork_ends','1')}
  @crown_edit_pid=g.persistent_id; dialog.execute_script("crownLoaded(#{JSON.generate(d)})")
rescue=>e; dialog.execute_script("crownLoadError(#{e.message.to_json})"); end

def crown_update_action(json)
  model=Sketchup.active_model; g=model.find_entity_by_persistent_id(@crown_edit_pid.to_i) rescue nil; raise 'Revize edilecek Kronman bulunamadı. Tekrar Modelden Oku yapın.' unless g&&g.valid?
  d=JSON.parse(json); axis_len=(Geom::Point3d.new(g.get_attribute(DICT,'axis_start_x'),g.get_attribute(DICT,'axis_start_y'),g.get_attribute(DICT,'axis_start_z')).distance(Geom::Point3d.new(g.get_attribute(DICT,'axis_end_x'),g.get_attribute(DICT,'axis_end_y'),g.get_attribute(DICT,'axis_end_z')))).to_m
  nv,nf=crown_preview_quantities(d,axis_len); ov=g.get_attribute(DICT,'concrete_volume_m3',0).to_f; of=g.get_attribute(DICT,'formwork_area_m2',0).to_f
  ok=UI.messagebox("KRONMAN DEĞİŞİKLİK ÖNİZLEMESİ\n\n#{g.name}\nBeton: #{format('%.3f',ov)} → #{format('%.3f',nv)} m³\nKalıp: #{format('%.3f',of)} → #{format('%.3f',nf)} m²\n\nGeometri, metraj ve keşif birlikte güncellenecek. Devam?",MB_YESNO)
  return unless ok==IDYES; crown_build_v2(d,g)
rescue=>e; UI.messagebox("Kronman revizyon hatası: #{e.message}"); end
# ===== end Crown Wall =====

# ===== Rockfill / Earthworks QTO Engine v1.0 =====
ROCKFILL_LIBRARY_KEY='rockfill_material_library_json'.freeze
ROCKFILL_DEFAULTS=[
 {'code'=>'CORE-01','name'=>'(1 - 29) Ton Çekirdek Malzeme','density'=>1.80,'area'=>46.53},
 {'code'=>'FILTER-01','name'=>'(10-300) Kg Filtre Tabakası','density'=>1.80,'area'=>0.00},
 {'code'=>'FILTER-02','name'=>'(30-670) Kg Filtre Tabakası','density'=>1.80,'area'=>9.20},
 {'code'=>'ARMOUR-01','name'=>'(0.4 - 2) Ton Anroşman','density'=>1.80,'area'=>0.00},
 {'code'=>'ARMOUR-02','name'=>'(2 - 4) Ton Anroşman','density'=>1.80,'area'=>26.05},
 {'code'=>'PLUG-01','name'=>'Tıkama Tabakası','density'=>1.80,'area'=>2.38},
 {'code'=>'FILTER-03','name'=>'(70-1050) Kg Filtre Tabakası','density'=>1.80,'area'=>68.01},
 {'code'=>'ARMOUR-03','name'=>'(6 - 8) Ton Anroşman','density'=>1.80,'area'=>0.00},
 {'code'=>'FILTER-04','name'=>'(220-2100) Kg Filtre Tabakası','density'=>1.80,'area'=>12.60},
 {'code'=>'ARMOUR-04','name'=>'(10 - 12) Ton Anroşman','density'=>1.80,'area'=>0.00}
].freeze

def rockfill_library
 raw=Sketchup.active_model.get_attribute(DICT,ROCKFILL_LIBRARY_KEY,'').to_s
 return ROCKFILL_DEFAULTS.map(&:dup) if raw.empty?
 JSON.parse(raw) rescue ROCKFILL_DEFAULTS.map(&:dup)
end

# R-4 / K20: kayıtlı JSON (model DICT) boş değil ve okunamıyor/tipi yanlışsa true; okuyucular varsayılana döner, yazıcılar bunu kullanır
def mst_json_attr_bad?(model,key,klass)
 raw=model.get_attribute(DICT,key,'').to_s
 return false if raw.strip.empty?
 !(JSON.parse(raw) rescue nil).is_a?(klass)
end
def mst_json_attr_guard!(model,key,klass,label)
 raise "#{label} kaydı (#{key}) okunamadı; mevcut kaydın üzerine yazılmadı, değişiklik kaydedilmedi." if mst_json_attr_bad?(model,key,klass)
 true
end

# v0.51.5 K14: dolgu kayıtları işlem içinde (tek Geri Al); değişmeyen değer yazılmaz, değişiklik yoksa işlem açılmaz.
# pairs: [[anahtar, değer], ...] (model DICT). => true (yazıldı) / false (değişiklik yok)
def mst_rf_write!(name,pairs)
 model=Sketchup.active_model
 ch=pairs.reject{|k,v|model.get_attribute(DICT,k,nil)==v}
 return false if ch.empty?
 model.start_operation(name,true)
 begin
  ch.each{|k,v|model.set_attribute(DICT,k,v)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 true
end
# v0.51.5 K21 (S9): otomatik kayıt hatası yalnız konsolda kalmaz; aynı ileti oturumda bir kez kullanıcıya gösterilir
def mst_rf_autosave_warn(msg)
 @mst_rf_autosave_warned||={}
 return if @mst_rf_autosave_warned[msg]
 @mst_rf_autosave_warned[msg]=true
 UI.messagebox("Dolgu otomatik kaydı yapılamadı: #{msg}\n(Bu ileti oturumda bir kez gösterilir; değişikliği Kaydet düğmesiyle kaydedin.)")
end

def rockfill_save_library(json,dialog)
 a=JSON.parse(json); raise 'Malzeme kütüphanesi boş olamaz.' unless a.is_a?(Array)&&!a.empty?
 mst_json_attr_guard!(Sketchup.active_model,ROCKFILL_LIBRARY_KEY,Array,'Dolgu malzeme kütüphanesi')
 a.each{|x| raise 'Malzeme kodu ve adı boş olamaz.' if x['code'].to_s.strip.empty?||x['name'].to_s.strip.empty?; raise 'Yoğunluk sıfırdan büyük olmalıdır.' unless x['density'].to_f>0}
 mst_rf_write!('MST Dolgu Kütüphanesi',[[ROCKFILL_LIBRARY_KEY,JSON.generate(a)]]); dialog.execute_script("rockfillLibraryLoaded(#{JSON.generate(a)})")
rescue=>e; UI.messagebox("Dolgu kütüphanesi hatası: #{e.message}"); end

def rockfill_load_library(dialog)
 dialog.execute_script("rockfillLibraryLoaded(#{JSON.generate(rockfill_library)})")
end

def rockfill_axis_info(dialog)
 edge=Sketchup.active_model.selection.grep(Sketchup::Edge).first
 return dialog.execute_script("rockfillAxisError('Önce metraj hattını temsil eden tek bir kenar seçin.')") unless edge && Sketchup.active_model.selection.grep(Sketchup::Edge).length==1
 dialog.execute_script("rockfillAxisLoaded(#{JSON.generate({'length_m'=>edge.length.to_m})})")
rescue=>e; dialog.execute_script("rockfillAxisError(#{e.message.to_json})"); end

ROCKFILL_PROJECT_KEY='rockfill_section_chain_json'.freeze
ROCKFILL_PROJECT_KEY_ALT2='rockfill_section_chain_alt02_json'.freeze
ROCKFILL_ACTIVE_ALT_KEY='rockfill_active_alternative'.freeze

def rockfill_project_key(alt=nil)
 a=(alt||Sketchup.active_model.get_attribute(DICT,ROCKFILL_ACTIVE_ALT_KEY,'01')).to_s
 a=='02' ? ROCKFILL_PROJECT_KEY_ALT2 : ROCKFILL_PROJECT_KEY
end

def rockfill_save_project(json,dialog)
 d=JSON.parse(json); alt=(d['alternative']||'01').to_s; sections=d['sections']; raise 'En az iki kesit gereklidir.' unless sections.is_a?(Array)&&sections.length>=2
 stations=sections.map{|x|x['station'].to_f}; raise 'Kesit istasyonları aynı olamaz.' unless stations.uniq.length==stations.length
 mst_json_attr_guard!(Sketchup.active_model,rockfill_project_key(alt),Hash,'Dolgu kesit zinciri')   # kod inceleme #1 (R-4)
 mst_rf_write!('MST Dolgu Kesit Zinciri',[[ROCKFILL_ACTIVE_ALT_KEY,alt],[rockfill_project_key(alt),JSON.generate({'sections'=>sections})]])   # K14
 dialog.execute_script("rockfillProjectLoaded(#{JSON.generate({'sections'=>sections,'alternative'=>alt})})")
rescue=>e; UI.messagebox("Dolgu kesit zinciri hatası: #{e.message}"); end


def rockfill_autosave_library(json)
 a=JSON.parse(json); raise 'Kütüphane verisi geçersiz.' unless a.is_a?(Array)
 mst_json_attr_guard!(Sketchup.active_model,ROCKFILL_LIBRARY_KEY,Array,'Dolgu malzeme kütüphanesi')
 mst_rf_write!('MST Dolgu Kütüphanesi (otomatik kayıt)',[[ROCKFILL_LIBRARY_KEY,JSON.generate(a)]])   # K14
rescue=>e
 puts "Marine Structures rockfill library autosave: #{e.message}"
 mst_rf_autosave_warn(e.message)
end

def rockfill_autosave_project(json)
 d=JSON.parse(json); alt=(d['alternative']||'01').to_s; sections=d['sections']; return unless sections.is_a?(Array) && sections.length>=2
 mst_json_attr_guard!(Sketchup.active_model,rockfill_project_key(alt),Hash,'Dolgu kesit zinciri')   # kod inceleme #1 (R-4)
 mst_rf_write!('MST Dolgu Kesit Zinciri (otomatik kayıt)',[[ROCKFILL_ACTIVE_ALT_KEY,alt],[rockfill_project_key(alt),JSON.generate({'sections'=>sections})]])   # K14
rescue=>e
 puts "Marine Structures rockfill project autosave: #{e.message}"
 mst_rf_autosave_warn(e.message)
end

def rockfill_load_project(dialog,alt=nil)
 alt=(alt||Sketchup.active_model.get_attribute(DICT,ROCKFILL_ACTIVE_ALT_KEY,'01')).to_s
 # v0.51.5 K14: salt yüklemede yazma yok; yalnız kullanıcı başka alternatifi seçtiyse etkin alternatif işlem içinde değişir
 mst_rf_write!('MST Dolgu Alternatifi',[[ROCKFILL_ACTIVE_ALT_KEY,alt]]) unless alt==Sketchup.active_model.get_attribute(DICT,ROCKFILL_ACTIVE_ALT_KEY,'01').to_s
 raw=Sketchup.active_model.get_attribute(DICT,rockfill_project_key(alt),'').to_s
 d=raw.strip.empty? ? {'sections'=>[]} : (JSON.parse(raw) rescue nil)
 # kod inceleme #1 (R-4): bozuk kayıt boş liste sayılmaz; kayıt korunur, JS'e bozuk durumu bildirilir (otomatik kayıt yapılmaz)
 unless d.is_a?(Hash)
  UI.messagebox("Dolgu kesit zinciri kaydı (#{rockfill_project_key(alt)}) okunamadı; kesitler gösterilemiyor. Mevcut kayıt korundu, üzerine yazılmaz; bu alternatifte otomatik kayıt yapılmaz.")
  d={'sections'=>[],'bad'=>true}
 end
 d['alternative']=alt
 dialog.execute_script("rockfillProjectLoaded(#{JSON.generate(d)})")
end



# Current area maps take precedence, including explicitly selected zero areas.
def rockfill_section_areas(section)
  if section['areas'].is_a?(Hash)
    section['areas'].each_with_object({}){|(code,area),out|out[code.to_s]=area.to_f}
  else
    (section['materials']||[]).each_with_object({}){|mat,out|out[mat['code'].to_s]=mat['area'].to_f}
  end
end

def rockfill_qto_alt1_data
  raw=Sketchup.active_model.get_attribute(DICT,rockfill_project_key,'').to_s
  d=raw.empty? ? {'sections'=>[]} : (JSON.parse(raw) rescue {'sections'=>[]})
  sections=(d['sections']||[]).each_with_index.sort_by{|x,i|[x['station'].to_f,i]}.map(&:first)   # v0.51.5 K56: aynı istasyonda kayıt sırası korunur (kararlı sıralama)
  lib=rockfill_library
  by_code={}; lib.each{|m|by_code[m['code'].to_s]=m}
  mats={}; intervals=[]
  sections.each_cons(2) do |s1,s2|
    x1=s1['station'].to_f; x2=s2['station'].to_f; len=x2-x1
    next unless len>0
    a1=rockfill_section_areas(s1)
    a2=rockfill_section_areas(s2)
    codes=(a1.keys+a2.keys).uniq
    rows=[]
    codes.each do |code|
      mat=by_code[code]||{'code'=>code,'name'=>code,'density'=>0}
      aa1=a1[code]||0.0; aa2=a2[code]||0.0
      vol=(aa1+aa2)*0.5*len; den=mat['density'].to_f; ton=vol*den
      next if aa1==0.0 && aa2==0.0
      # v0.51.5 K55: kütüphanede olmayan / yoğunluğu geçersiz malzeme sessizce 0 t sayılmaz (Alternatif-02 ile aynı kural)
      raise "#{code}: malzeme kütüphanesinde kayıt yok; yoğunluk bilinmediği için tonaj hesaplanamadı. Dolgu malzeme kütüphanesine ekleyin." unless by_code.key?(code)
      raise "#{code}: yoğunluk sonlu ve sıfırdan büyük olmalı (t/m³)." unless den.finite? && den>0
      rows << {code:code,name:mat['name'].to_s,density:den,a1:aa1,a2:aa2,volume_m3:vol,tonnage_t:ton}
      z=(mats[code]||={code:code,name:mat['name'].to_s,density:den,volume_m3:0.0,tonnage_t:0.0})
      z[:volume_m3]+=vol; z[:tonnage_t]+=ton
    end
    intervals << {from_id:s1['id'].to_s,to_id:s2['id'].to_s,from_station:x1,to_station:x2,length_m:len,rows:rows,volume_m3:rows.sum{|r|r[:volume_m3]},tonnage_t:rows.sum{|r|r[:tonnage_t]}}
  end
  {sections:sections,intervals:intervals,materials:mats.values.sort_by{|x|x[:code]},total_volume_m3:mats.values.sum{|x|x[:volume_m3]},total_tonnage_t:mats.values.sum{|x|x[:tonnage_t]}}
end

def rockfill_alt1_takeoff_html
  q=rockfill_qto_data
  return "<h3>Dolgu / Taş Metrajı</h3><div class='note'>Kayıtlı kesit zinciri bulunamadı.</div>" if q[:sections].length<2
  mat_rows=q[:materials].map{|r|"<tr><td>#{html_escape(r[:code])}</td><td>#{html_escape(r[:name])}</td><td>#{format('%.3f',r[:density])}</td><td><b>#{format('%.3f',r[:volume_m3])} m³</b></td><td><b>#{format('%.3f',r[:tonnage_t])} t</b></td></tr>"}.join
  int_rows=q[:intervals].map{|r|"<tr><td>#{html_escape(r[:from_id])} → #{html_escape(r[:to_id])}</td><td>#{format('%.3f',r[:from_station])}–#{format('%.3f',r[:to_station])}</td><td>#{format('%.3f',r[:length_m])} m</td><td>#{format('%.3f',r[:volume_m3])} m³</td><td>#{format('%.3f',r[:tonnage_t])} t</td></tr>"}.join
  detail=q[:intervals].map do |iv|
    rr=iv[:rows].map{|r|"<tr><td>#{html_escape(r[:code])}</td><td>#{html_escape(r[:name])}</td><td>#{format('%.2f',r[:a1])}</td><td>#{format('%.2f',r[:a2])}</td><td>#{format('%.3f',iv[:length_m])}</td><td>#{format('%.3f',r[:volume_m3])}</td><td>#{format('%.3f',r[:tonnage_t])}</td></tr>"}.join
    "<h4 style='color:#315f7c;margin:18px 0 8px'>#{html_escape(iv[:from_id])} → #{html_escape(iv[:to_id])} &nbsp; (#{format('%.3f',iv[:from_station])}–#{format('%.3f',iv[:to_station])} m)</h4><table><tr><th>Kod</th><th>Malzeme / Taş Cinsi</th><th>A₁ (m²)</th><th>A₂ (m²)</th><th>L (m)</th><th>Hacim (m³)</th><th>Tonaj (t)</th></tr>#{rr}<tr class='subtotal'><td>ARA TOPLAM</td><td>-</td><td>-</td><td>-</td><td>#{format('%.3f',iv[:length_m])}</td><td>#{format('%.3f',iv[:volume_m3])}</td><td>#{format('%.3f',iv[:tonnage_t])}</td></tr></table>"
  end.join
  "<h3>Dolgu / Taş Metrajı</h3><div class='note'>Ortalama uç alan (AEA): V = (A₁ + A₂) / 2 × L • Tonaj = Hacim × Kütüphane Yoğunluğu</div><h4 style='color:#315f7c'>Malzeme Bazında Toplam</h4><table><tr><th>Kod</th><th>Malzeme / Taş Cinsi</th><th>Yoğunluk (t/m³)</th><th>Hacim</th><th>Tonaj</th></tr>#{mat_rows}<tr class='total'><td>GENEL TOPLAM</td><td>-</td><td>-</td><td>#{format('%.3f',q[:total_volume_m3])} m³</td><td>#{format('%.3f',q[:total_tonnage_t])} t</td></tr></table><h4 style='color:#315f7c'>Kesit Aralıkları Özeti</h4><table><tr><th>Kesit Aralığı</th><th>İstasyon</th><th>Uzunluk</th><th>Hacim</th><th>Tonaj</th></tr>#{int_rows}</table>#{detail}"
end

# ===== end Rockfill / Earthworks =====


# ===== v0.32.5 Revision & Change Log =====
REVISION_DICT='MAG_MST_RevisionLog'.freeze

def revision_metric_value(e,*keys)
  keys.each do |k|
    v=e.get_attribute(DICT,k,nil)
    return v.to_f unless v.nil? || v.to_s.strip==''
  end
  0.0
end

def revision_element_record(e,occurrences={})
 et=e.get_attribute(DICT,'element_type','').to_s
 uid=e.get_attribute(DICT,'element_uid','').to_s
 uid="UNASSIGNED-#{e.persistent_id}" if uid.empty?
 concrete=et=='steel_pipe_pile' ? QuantityService.pile_owned_concrete(e)[:value] : QuantityService.value(e,:concrete_m3)
 steel=et=='steel_pipe_pile' ? QuantityService.value(e,:steel_t) : 0.0
 {uid:uid,pid:e.persistent_id,id:element_visible_id(e),type:et,signature:e.get_attribute(DICT,'type_signature','').to_s,
  concrete_m3:concrete,rebar_t:QuantityService.value(e,:rebar_t),formwork_m2:QuantityService.value(e,:formwork_m2),steel_t:steel,
  concrete_class:(et=='steel_pipe_pile' ? pile_report_concrete_class(e) : e.get_attribute(DICT,'concrete_class','').to_s),
  project:e.get_attribute(DICT,'project','').to_s,ano:e.get_attribute(DICT,'ano','').to_s,axis:e.get_attribute(DICT,'axis','').to_s,
  quantity_schema:'1',geometry_signature:revision_geometry_signature(e,occurrences),parameter_signature:revision_parameter_signature(e),
  relationship_signature:revision_relationship_signature(e)}
end

def revision_current_snapshot
  return @mst_revision_curr_reuse if @mst_revision_curr_reuse   # v0.51.5 P5: revision_create_snapshot az önce hesapladığı kaydı yeniden kullanır
revision_shape_memo do   # v0.51.5 P5: imza alt ağaçları bu hesap süresince bir kez
  a=[]; collect_elements(Sketchup.active_model.entities,a)
  elems=a.select{|e| e.respond_to?(:get_attribute) && !e.get_attribute(DICT,'element_type','').to_s.empty? }
  # Child/internal geometry without BIM identity is not a revision item.
  elems=elems.select{|e| !e.get_attribute(DICT,'element_uid','').to_s.empty? || %w[steel_pipe_pile bored_pile head_beam flat_precast channel_precast crane_precast deck_slab curb pile_infill_concrete deck_topping crown_wall accessory].include?(e.get_attribute(DICT,'element_type','').to_s)}
  occurrences=revision_occurrence_signatures(Sketchup.active_model.entities)
  elems.map{|e|revision_element_record(e,occurrences)}
end # revision_shape_memo
end

def revision_snapshots
 raw=Sketchup.active_model.get_attribute(REVISION_DICT,'snapshots','[]').to_s
 memo=@mst_rev_snaps_memo
 return memo[:data] if memo && memo[:data] && memo[:raw]==raw   # G3: aynı kayıtlı metin kapsam içinde bir kez ayrıştırılır
 data=JSON.parse(raw)
 raise 'Revizyon arşivi geçersiz; mevcut kayıtların üzerine yazılmadı.' unless data.is_a?(Array) && data.all?{|r|r.is_a?(Hash) && r['elements'].is_a?(Array)}
 (memo[:raw]=raw;memo[:data]=data) if memo
 data
rescue JSON::ParserError
 raise 'Revizyon arşivi okunamadı; mevcut kayıtların üzerine yazılmadı.'
end
# G3 (03.11.2026): revizyon ekranı / anlık kayıt süresince arşiv (MB düzeyinde JSON) kayıtlı metin değişmedikçe yeniden
# ayrıştırılmaz. Önbellek kayıtlı metinle eşleşmeli (kayıttan sonra metin değişir → yeniden ayrıştırılır). Dönen dizi salt
# okunur; değiştiren çağıran (revision_create_snapshot) revision_snapshots_forget çağırır. Kapsam dışında önbellek yok.
def revision_snapshots_memo
 return yield if @mst_rev_snaps_memo
 @mst_rev_snaps_memo={raw:nil,data:nil}
 begin
  yield
 ensure
  @mst_rev_snaps_memo=nil
 end
end
def revision_snapshots_forget
 @mst_rev_snaps_memo[:raw]=nil if @mst_rev_snaps_memo
 @mst_rev_snaps_memo[:data]=nil if @mst_rev_snaps_memo
end

def revision_save_snapshots(arr)
  # R-1 / K02: arşiv kırpılmaz (revizyon yalnız ileri yazılır)
  Sketchup.active_model.set_attribute(REVISION_DICT,'snapshots',JSON.generate(arr))
end

def revision_diff(prev,curr)
  pl=Array(prev);cl=Array(curr);pg=pl.group_by{|x|x['uid'].to_s};cg=cl.group_by{|x|x[:uid].to_s}
  # ADR-0515 §1 / K06: tekrarlanan UID'de (kopya) eşleşme PID ile; iki tarafta ortak en küçük PID UID'yi taşır, öbürleri "UID~PID-n"
  anchor={};one_prev={}
  (pg.keys|cg.keys).each do |u|
    next if Array(pg[u]).length<=1 && Array(cg[u]).length<=1
    anchor[u]=(Array(pg[u]).map{|x|x['pid'].to_i}&Array(cg[u]).map{|x|x[:pid].to_i}).min
    # ADR-0515 G3-#12: ortak PID yok (PID'siz eski kayıt) ve önceki tarafta tek kayıt → o kayıt UID'ye eşlenir;
    # güncelde UID içindeki PID'e eşit tek kayıt, yoksa en küçük PID UID'yi taşır
    next unless anchor[u].nil? && Array(pg[u]).length==1 && Array(cg[u]).any?
    up=u[/\AMST-(\d+)-/,1];hit=up ? cg[u].select{|x|x[:pid].to_i==up.to_i} : []
    anchor[u]=(hit.length==1 ? hit.first : cg[u].min_by{|x|x[:pid].to_i})[:pid].to_i;one_prev[u]=true
  end
  dk=lambda{|u,pid|!anchor.key?(u) || anchor[u]==pid.to_i ? u : "#{u}~PID-#{pid}"}
  # önceki tarafta çok kayıt: PID'li kayıt "UID~PID-n", PID'siz kayıt "UID~REC-sıra" (anahtar çakışması olmaz)
  seq=Hash.new(0)
  pk=lambda do |x|
    u=x['uid'].to_s;seq[u]+=1
    if one_prev[u] then u
    elsif anchor.key?(u) && x['pid'].to_i<=0 then "#{u}~REC-#{seq[u]}"
    else dk.call(u,x['pid'])
    end
  end
  pm=Hash[pl.map{|x|[pk.call(x),x]}]; cm=Hash[cl.map{|x|[dk.call(x[:uid].to_s,x[:pid]),x]}]
  added=[];deleted=[];changed=[];same=[]
  cm.each do |uid,n|
    o=pm[uid]
    if o.nil?; added << (uid==n[:uid].to_s ? n : n.merge(uid:uid)); next; end
    fields=%w[concrete_m3 rebar_t formwork_m2 steel_t]
    diffs={}
    fields.each do |k|
      ov=o[k].to_f; nv=n[k.to_sym].to_f; d=nv-ov
      diffs[k]={old:ov,new:nv,delta:d} if d.abs>0.0005
    end
    %w[concrete_class signature project ano axis].each do |k|
      ov=o[k].to_s; nv=n[k.to_sym].to_s
      diffs[k]={old:ov,new:nv} if ov!=nv
    end
    %w[geometry_signature parameter_signature relationship_signature].each do |key|
      next unless o.key?(key)
      diffs[key]={old:o[key],new:n[key.to_sym]} if o[key]!=n[key.to_sym]
    end
    if diffs.empty?; same << n; else changed << {uid:uid,pid:n[:pid],id:n[:id],type:n[:type],diffs:diffs}; end
  end
  pm.each{|uid,o|deleted << o unless cm.key?(uid)}
  totals=lambda do |list, sign=1.0|
    {concrete_m3:list.sum{|x|x[:concrete_m3].to_f}*sign,rebar_t:list.sum{|x|x[:rebar_t].to_f}*sign,formwork_m2:list.sum{|x|x[:formwork_m2].to_f}*sign,steel_t:list.sum{|x|x[:steel_t].to_f}*sign}
  end
  delta={concrete_m3:0.0,rebar_t:0.0,formwork_m2:0.0,steel_t:0.0}
  changed.each{|x| %w[concrete_m3 rebar_t formwork_m2 steel_t].each{|k|delta[k.to_sym]+=x[:diffs][k][:delta].to_f if x[:diffs][k]}}
  totals.call(added).each{|k,v|delta[k]+=v}; deleted.each{|x|delta[:concrete_m3]-=x['concrete_m3'].to_f;delta[:rebar_t]-=x['rebar_t'].to_f;delta[:formwork_m2]-=x['formwork_m2'].to_f;delta[:steel_t]-=x['steel_t'].to_f}
  {added:added,deleted:deleted,changed:changed,same:same,delta:delta}
end

def revision_discipline(type)
  case type.to_s
  when 'steel_pipe_pile','pile_infill_concrete' then 'Kazık'
  when 'bored_pile' then 'Fore Kazık'
  when 'head_beam' then 'Başlık Kirişi'
  when 'flat_precast','channel_precast','crane_precast' then 'Prekast'
  when 'deck_slab','deck_topping','curb' then 'Döşeme'
  when 'crown_wall' then 'Kronman'
  when 'accessory' then 'Aksesuarlar'
  else 'Diğer'
  end
end

def revision_summary(elements)
  overall={count:0,concrete_m3:0.0,rebar_t:0.0,formwork_m2:0.0,steel_t:0.0}
  groups={}
  Array(elements).each do |e|
    get=lambda{|k| e.is_a?(Hash) ? (e[k] || e[k.to_s]) : nil}
    g=revision_discipline(get.call(:type))
    groups[g]||={count:0,concrete_m3:0.0,rebar_t:0.0,formwork_m2:0.0,steel_t:0.0,pids:[]}
    [overall,groups[g]].each do |h|
      h[:count]+=1
      h[:concrete_m3]+=get.call(:concrete_m3).to_f
      h[:rebar_t]+=get.call(:rebar_t).to_f
      h[:formwork_m2]+=get.call(:formwork_m2).to_f
      h[:steel_t]+=get.call(:steel_t).to_f
    end
    pid=get.call(:pid).to_i
    groups[g][:pids] << pid if pid>0
  end
  {overall:overall,groups:groups}
end

def revision_comparison(prev_elements,curr_elements)
  a=revision_summary(prev_elements); b=revision_summary(curr_elements)
  metric=[:count,:concrete_m3,:rebar_t,:formwork_m2,:steel_t]
  make=lambda do |oldv,newv|
    h={}
    metric.each{|k|h[k]={previous:oldv[k].to_f,current:newv[k].to_f,delta:newv[k].to_f-oldv[k].to_f}}
    h
  end
  groups={}
  (a[:groups].keys|b[:groups].keys).each do |g|
    oldv=a[:groups][g]||{count:0,concrete_m3:0,rebar_t:0,formwork_m2:0,steel_t:0,pids:[]}
    newv=b[:groups][g]||{count:0,concrete_m3:0,rebar_t:0,formwork_m2:0,steel_t:0,pids:[]}
    groups[g]=make.call(oldv,newv).merge(pids:newv[:pids])
  end
  {overall:make.call(a[:overall],b[:overall]),groups:groups}
end

def revision_payload
  snaps=revision_snapshots; curr=revision_current_snapshot; prev=snaps.last
  diff=prev ? revision_diff(prev['elements'],curr) : {added:[],deleted:[],changed:[],same:curr,delta:{concrete_m3:0,rebar_t:0,formwork_m2:0,steel_t:0}}
  comparison=prev ? revision_comparison(prev['elements'],curr) : revision_comparison([],curr)
  {legacy_baseline:prev && Array(prev['elements']).any?{|e|!e.key?('quantity_schema')},has_baseline:!prev.nil?,snapshot_count:snaps.length,last_snapshot:(prev ? prev['created_at'] : nil),current_count:curr.length,diff:diff,comparison:comparison}
end

def revision_send(dialog=@d)
mst_read_batch do   # v0.51.5 P4: salt okuma, tek model taraması
revision_snapshots_memo do   # G3: revision_payload ve boq_pro sarmalayıcısı arşivi bir kez ayrıştırır
  dialog.execute_script("revisionLoaded(#{JSON.generate(revision_payload)});") if dialog
end # revision_snapshots_memo
end # mst_read_batch
rescue=>error
  dialog.execute_script("revisionError(#{JSON.generate(error.message)})") if dialog
end

# R-1 / K02, K03: saf kurucu (yazmaz); numara = kayıtlı en büyük Rev.NN + 1. Kaydı boq_pro.rb sarmalayıcısı tek işlemde yapar.
def revision_create_snapshot(snaps=revision_snapshots,curr=revision_current_snapshot)
  n=snaps.map{|s|s.is_a?(Hash) ? s['revision'].to_s[/Rev\.(\d+)/,1].to_i : 0}.max.to_i+1
  {'revision'=>format('Rev.%02d',n),'created_at'=>Time.now.strftime('%d.%m.%Y %H:%M'),'elements'=>curr.map{|x|Hash[x.map{|k,v|[k.to_s,v]}]}}
end

def revision_select(raw,dialog=@d)
  ids=raw.to_s.split(',').map(&:to_i).reject{|x|x<=0}.uniq; model=Sketchup.active_model; all=[];collect_elements(model.entities,all)
  es=all.select{|e|e.respond_to?(:persistent_id)&&ids.include?(e.persistent_id)}
  model.selection.clear;es.each{|e|model.selection.add(e) rescue nil};model.active_view.zoom(model.selection) unless model.selection.empty?
end
# ===== end v0.32.5 =====

# ===== v0.32.7a Hakediş / İlerleme — Onaylı QTO Bağlantısı =====
PROGRESS_DICT='MAG_MST_Progress'.freeze

def progress_entity_quantity(e, source)
  source=source.to_s
  et=e.get_attribute(DICT,'element_type','').to_s
  case source
  when 'FORMWORK_CAST','FORMWORK_PRECAST','CROWN_FORMWORK'
    qto3_quantity(e,:formwork_m2)
  when 'TOPPING_CONCRETE'
    topping_quantities([e])[1]
  when 'HB_DECK_CONCRETE','CAST_C35_45_OTHER','PRECAST_C35_45','PRECAST_INSTALL','CROWN_CONCRETE'
    qto3_quantity(e,:concrete_m3)
  when 'TOPPING_AREA'
    topping_quantities([e])[0]
  when 'REBAR'
    QuantityService.number(mst_element_rebar(e).fetch('kg'),'progress_rebar_kg')/1000.0
  when 'PILE_INFILL'
    et=='steel_pipe_pile' ? pile_qto_concrete(e) : (et=='pile_infill_concrete' ? qto3_quantity(e,:concrete_m3) : 0.0)
  when 'PILE_STEEL','PILE_MANIP','PILE_RINGS','PILE_SPLICES','PILE_DRIVING','PILE_PE','PILE_DRILLING'
    return 0.0 unless et=='steel_pipe_pile'
    row=pile_fabrication_qto_row([e],'PROGRESS',true)
    return 0.0 unless row
    case source
    when 'PILE_RINGS' then row[10].to_f + row[11].to_f
    when 'PILE_DRIVING' then pile_driving_length(e).to_f
    when 'PILE_STEEL' then row[9].to_f
    when 'PILE_MANIP' then row[12].to_f
    when 'PILE_SPLICES' then row[5].to_f
    when 'PILE_PE' then row[14].to_f
    when 'PILE_DRILLING' then row[15].to_f
    else 0.0
    end
  else
    0.0
  end
rescue=>error
  raise QuantityService::InvalidQuantity,"Hakediş kaynağı #{source}: #{error.message}"
end

def progress_approved_quantity(row)
  source=row[:source].to_s
  qty=row[:quantity].to_f
  es=boq_trace_entities(source)
  es=es.select{|e|Array(row[:trace_pids]).include?(e.persistent_id)} if row[:trace_pids].is_a?(Array)
  return 0.0 if es.empty?
  approved=es.select{|e|e.get_attribute(DICT,'progress_status','Planlandı').to_s=='Onaylandı'}
  return 0.0 if approved.empty?
  # Exact per-element QTO for the central BOQ sources.
  exact=approved.sum{|e|progress_entity_quantity(e,source)}
  central=%w[FORMWORK_CAST FORMWORK_PRECAST CROWN_FORMWORK HB_DECK_CONCRETE CAST_C35_45_OTHER PRECAST_C35_45 PRECAST_INSTALL CROWN_CONCRETE TOPPING_CONCRETE TOPPING_AREA REBAR PILE_INFILL PILE_STEEL PILE_MANIP PILE_RINGS PILE_SPLICES PILE_DRIVING PILE_PE PILE_DRILLING]
  if central.include?(source) || exact>0.0
    [exact,qty].min
  else
    # Generic mapped/accessory BOQ fallback: same source population, proportional count.
    qty * approved.length.to_f / es.length.to_f
  end
end

PROGRESS_HISTORY_KEY='payment_history_json'.freeze

def progress_history
 raw=Sketchup.active_model.get_attribute(PROGRESS_DICT,PROGRESS_HISTORY_KEY,'').to_s
 data=raw.empty? ? [] : JSON.parse(raw)
 raise 'Hakediş arşivi geçersiz; mevcut kayıtların üzerine yazılmadı.' unless data.is_a?(Array) && data.all?{|r|r.is_a?(Hash) && r['rows'].is_a?(Array)}
 data
rescue JSON::ParserError
 raise 'Hakediş arşivi okunamadı; mevcut kayıtların üzerine yazılmadı.'
end

def progress_status_summary
  all=[];collect_elements(Sketchup.active_model.entities,all);ss=Hash.new(0)
  all.each do |e|
    next unless e.respond_to?(:get_attribute) && !e.get_attribute(DICT,'element_type','').to_s.empty?
    ss[e.get_attribute(DICT,'progress_status','Planlandı').to_s]+=1
  end
  ss
end

def progress_source_key(row)
 source=row[:source].to_s
 row[:split_mode]=='separate' ? "#{source}::#{row[:group_label]}" : source
end

def progress_live_rows
  model=Sketchup.active_model
  boq_rows.map do |r|
    src=progress_source_key(r)
    mode=r[:split_mode]=='separate' ? 'separate' : 'combined'
    saved_mode=model.get_attribute(PROGRESS_DICT,"saved_group_mode_#{r[:source]}",nil)
    if saved_mode && saved_mode!=mode
      raise 'Hakediş geçmişi farklı poz gruplamasıyla kaydedilmiş. Bu dönem için keşif gruplamasını eski düzenine döndürün; geçmiş miktarlar otomatik paylaştırılmaz.'
    end
    stored=model.get_attribute(PROGRESS_DICT,"previous_#{src}",nil)
    if r[:split_mode]=='separate' && stored.nil? && model.get_attribute(PROGRESS_DICT,"previous_#{r[:source]}",0).to_f>0
      raise 'Bu imalatın eski hakedişi birleşik pozla kaydedilmiş. Mevcut hakediş için keşif gruplamasını Birleşik seçin; geçmiş miktarlar otomatik paylaştırılmaz.'
    end
    previous=stored.nil? ? 0.0 : QuantityService.number(stored,'previous_quantity')
    approved=progress_approved_quantity(r)
    current=[approved-previous,0.0].max
    {code:r[:code],name:r[:name],source:src,unit:r[:unit],quantity:r[:quantity].to_f,unit_price:r[:unit_price].to_f,
     previous:previous,current_period:current,approved_quantity:approved}
  end
end

def progress_payload(period_no=nil)
  hist=progress_history
  if period_no && period_no.to_i>0
    rec=hist.find{|h|h['no'].to_i==period_no.to_i}
    return {rows:(rec ? rec['rows'] : []),status_summary:(rec ? rec['status_summary'] : {}),history:hist.map{|h|{'no'=>h['no'],'saved_at'=>h['saved_at']}},selected_period:period_no.to_i,archived:true} if rec
  end
  {rows:progress_live_rows,status_summary:progress_status_summary,history:hist.map{|h|{'no'=>h['no'],'saved_at'=>h['saved_at']}},selected_period:0,archived:false}
end

def progress_send(dialog=@d,period_no=nil)
mst_read_batch do   # v0.51.5 P2: salt okuma, tek model taraması
  dialog.execute_script("progressLoaded(#{JSON.generate(progress_payload(period_no))});") if dialog
end # mst_read_batch
rescue=>error
  dialog.execute_script("progressError(#{JSON.generate(error.message)})") if dialog
end

def progress_save(_raw=nil,dialog=@d)
  model=Sketchup.active_model
  model.start_operation('MST Hakediş Dönemini Kaydet',true)
  rows=progress_live_rows
  hist=progress_history
  no=(hist.map{|h|h['no'].to_i}.max||0)+1
  saved_at=Time.now.strftime('%d.%m.%Y %H:%M')
  frozen_rows=rows.map do |r|
    rr={};r.each{|k,v|rr[k.to_s]=v};rr
  end
  rec={'no'=>no,'saved_at'=>saved_at,'rows'=>frozen_rows,'status_summary'=>progress_status_summary}
  hist << rec
  model.set_attribute(PROGRESS_DICT,PROGRESS_HISTORY_KEY,JSON.generate(hist))
  boq_rows.each do |r|
    src=progress_source_key(r); approved=progress_approved_quantity(r)
    model.set_attribute(PROGRESS_DICT,"saved_group_mode_#{r[:source]}",r[:split_mode]=='separate' ? 'separate' : 'combined')
    model.set_attribute(PROGRESS_DICT,"previous_#{src}",approved)
    model.set_attribute(PROGRESS_DICT,"cumulative_#{src}",approved)
  end
  model.set_attribute(PROGRESS_DICT,'last_saved_at',saved_at)
  commit_with_dependencies(model);progress_send(dialog,no)
rescue=>ex
  model.abort_operation rescue nil;UI.messagebox("Hakediş kaydedilemedi: #{ex.message}")
end

def progress_load_period(period_no,dialog=@d)
  n=period_no.to_i
  progress_send(dialog,n>0 ? n : nil)
rescue=>ex
  UI.messagebox("Hakediş geçmişi okunamadı: #{ex.message}")
end

def progress_delete_period(period_no,dialog=@d)
  n=period_no.to_i
  return if n<=0
  model=Sketchup.active_model
  hist=progress_history
  rec=hist.find{|h|h['no'].to_i==n}
  unless rec
    UI.messagebox("Hakediş #{format('%02d',n)} bulunamadı.")
    progress_send(dialog)
    return
  end
  answer=UI.messagebox("Hakediş #{format('%02d',n)} arşiv kaydı kalıcı olarak silinsin mi?\n\nBu işlem model geometrisini veya BIM imalat durumlarını değiştirmez.",MB_YESNO)
  return unless answer==IDYES
  model.start_operation('MST Hakediş Kaydını Sil',true)
  hist.reject!{|h|h['no'].to_i==n}
  model.set_attribute(PROGRESS_DICT,PROGRESS_HISTORY_KEY,JSON.generate(hist))
  # If the latest saved period was deleted, restore the live baseline from the new latest archive record.
  latest=hist.max_by{|h|h['no'].to_i}
  sources=boq_rows.map{|r|r[:source].to_s}.uniq
  latest_rows=latest ? (latest['rows']||[]) : []
  sources.each do |src|
    rr=latest_rows.find{|x|x['source'].to_s==src}
    approved=rr ? (rr['approved_quantity'] || rr['previous'].to_f + rr['current_period'].to_f).to_f : 0.0
    model.set_attribute(PROGRESS_DICT,"previous_#{src}",approved)
    model.set_attribute(PROGRESS_DICT,"cumulative_#{src}",approved)
  end
  model.set_attribute(PROGRESS_DICT,'last_saved_at',latest ? latest['saved_at'].to_s : '')
  commit_with_dependencies(model)
  progress_send(dialog)
rescue=>ex
  model.abort_operation rescue nil
  UI.messagebox("Hakediş silinemedi: #{ex.message}")
end

def progress_set_status(status,dialog=@d)
  allowed=%w[Planlandı İmalatta Tamamlandı Onaylandı]
  return unless allowed.include?(status.to_s)
  model=Sketchup.active_model; targets=model.selection.to_a.select{|e|e.respond_to?(:get_attribute)&&!e.get_attribute(DICT,'element_type','').to_s.empty?}
  if targets.empty?;UI.messagebox('Önce MST elemanlarını seçin.');return;end
  model.start_operation('MST İmalat Durumu',true)
  targets.each{|e|e.set_attribute(DICT,'progress_status',status.to_s)}
  commit_with_dependencies(model);progress_send(dialog)
rescue=>ex
  model.abort_operation rescue nil;UI.messagebox("İlerleme durumu atanamadı: #{ex.message}")
end
# ===== end v0.32.7a =====

def show_boq_engine
  show_dialog
  UI.start_timer(0.15, false) do
    begin
      # v0.51.5 K31: sekme metnine bağlı arama yerine sayfa kimliğiyle geçiş
      # 25/4: T('boq') Keşif verisini zaten ister; ikinci istek gönderilmez (tek boq_refresh)
      @d.execute_script("if(window.mstShowPage){mstShowPage('boq');}else{T('boq',document.createElement('button'));}") if @d && @d.visible?
    rescue => ex
      puts "MST BOQ navigation: #{ex.message}"
    end
  end
end

# ===== v0.38 UI4 — İş akışı (adım durumları) + UI5 Model Bakımı =====
# Durum: ok (tamam) · missing (eksik) · stale (güncel değil / kısmi) · optional (isteğe bağlı) · info
def mst_workflow_status(model=Sketchup.active_model)
mst_read_batch(model) do   # v0.51.5 P2: salt okuma, tek model taraması
 all=[];collect_elements(model.entities,all)
 by=Hash.new{|h,k|h[k]=[]};all.each{|e|by[e.get_attribute(DICT,'element_type','').to_s] << e}
 n=->(*ts){ts.sum{|t|by[t].length}}
 st={}
 pname=model.get_attribute(DICT,'project_name','').to_s.strip
 grid_ok=begin
  sys=model.get_attribute(DICT,'project_system_type','ISKELE').to_s.upcase
  s=mst_active_structure_for_system(sys,model);g=mst_axis_grid_for(s,model,s)
  [(g['x']||[]).length,(g['y']||[]).length,s]
 rescue
  [0,0,'']
 end
 st['project']=if grid_ok[0]>0 && grid_ok[1]>0
  {'state'=>'ok','text'=>"#{pname.empty? ? 'Proje adı yok' : pname} · #{grid_ok[2]} · #{grid_ok[0]}×#{grid_ok[1]} aks"}
 else
  {'state'=>'missing','text'=>'Aktif yapının aks gridi tanımlı değil'}
 end
 st['pile']=n.('steel_pipe_pile','bored_pile')>0 ? {'state'=>'ok','text'=>"#{by['steel_pipe_pile'].length} çelik + #{by['bored_pile'].length} fore kazık"} : {'state'=>'missing','text'=>'Kazık yok'}
 st['beam']=by['head_beam'].empty? ? {'state'=>'missing','text'=>'Başlık kirişi yok'} : {'state'=>'ok','text'=>"#{by['head_beam'].length} BK"}
 pc=n.('flat_precast','channel_precast','crane_precast')
 st['precast']=pc>0 ? {'state'=>'ok','text'=>"#{by['flat_precast'].length} PD · #{by['channel_precast'].length} kanal · #{by['crane_precast'].length} vinç"} : {'state'=>'missing','text'=>'Prekast yok'}
 old=by['deck_slab'].count{|d|d.get_attribute(DICT,'deck_plan_json','').to_s.empty?}
 st['deck']=if by['deck_slab'].empty? then {'state'=>'missing','text'=>'Döşeme yok'}
  elsif old>0 then {'state'=>'stale','text'=>"#{old} döşeme eski sürüm — yeniden oluşturun"}
  else {'state'=>'ok','text'=>"#{by['deck_slab'].length} döşeme"} end
 rf=(model.get_attribute(DICT,'rockfill_source','').to_s rescue '')
 st['crown']=n.('crown_wall')>0 ? {'state'=>'ok','text'=>"#{by['crown_wall'].length} kronman#{rf.empty? ? '' : ' · dolgu kaynağı '+rf}"} : {'state'=>'optional','text'=>'İsteğe bağlı'}
 bk=by['head_beam'];dk=by['deck_slab'].reject{|d|d.get_attribute(DICT,'deck_plan_json','').to_s.empty?}
 bim=->(es){es.count{|e|e.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'}}
 tot=bk.length+dk.length
 st['rebar']=if tot==0 then {'state'=>'optional','text'=>'Donatılı eleman yok'}
  elsif bim.(bk)+bim.(dk)==tot then {'state'=>'ok','text'=>"BK #{bim.(bk)}/#{bk.length} · döşeme #{bim.(dk)}/#{dk.length} BIM"}
  else {'state'=>'stale','text'=>"BK #{bim.(bk)}/#{bk.length} · döşeme #{bim.(dk)}/#{dk.length} BIM — kalanlar pursantaj"} end
 la=@mst_last_audit
 st['audit']=if la && la['model']==model.object_id
  {'state'=>(la['errors'].to_i>0 ? 'missing' : (la['warnings'].to_i>0 ? 'stale' : 'ok')),'text'=>"#{la['errors']} hata · #{la['warnings']} uyarı (#{la['at']})"}
 else {'state'=>'info','text'=>'Bu oturumda çalıştırılmadı'} end
 st['qto']=all.empty? ? {'state'=>'missing','text'=>'Modelde MST elemanı yok'} : {'state'=>'ok','text'=>"#{all.length} eleman"}
 prices=model.attribute_dictionary(DICT) ? model.attribute_dictionary(DICT).keys.count{|k|k.to_s.start_with?('boq_price_')} : 0
 st['boq']=prices>0 ? {'state'=>'ok','text'=>"#{prices} birim fiyat girildi"} : {'state'=>(all.empty? ? 'missing' : 'stale'),'text'=>'Birim fiyat girilmedi'}
 st
end # mst_read_batch
end

def mst_send_workflow_status(dialog=@d)
 return unless dialog
 dialog.execute_script("mstFlowStatus(#{JSON.generate(mst_workflow_status)})")
rescue => e
 puts "MST iş akışı durumu: #{e.message}"
end

# ---- UI5: Model Bakımı (eski Eklentiler menüsünün tamamı tek sayfada) ----
MST_MAINT_ACTIONS=[
 ['Kontrol','model_audit','Model Kontrolü','Hata / uyarı listesi, seçerek modele git.'],
 ['Kontrol','dependency','Bağımlılık Motoru / Etki Analizi','Elemanlar arası ilişki bilgisini yeniler.'],
 ['Kontrol','bim_core','BIM Veri Çekirdeği Raporu','Eleman bilgisi standartlaştırma ve tip kütüphanesi.'],
 ['Onarım','safe_repair','Güvenli Onarım','Model Kontrolü\'nün otomatik düzeltebildiği sorunlar.'],
 ['Onarım','deck_repair','Döşeme BIM İlişkilerini Onar','Döşeme ↔ BK / kaplama bağları.'],
 ['Onarım','identity_repair','BIM Kimlik Onarımı','Eksik / çift element_uid.'],
 ['Onarım','pile_types','Kazık Tip Kütüphanesini Eşitle','Kazık tiplerini modelle eşitler.'],
 ['Onarım','ring_rule','Çember Et Kalınlığı — Kurala Çek','Model geneli çember t kuralı.'],
 ['Onarım','pipe_weights','Kazık Boru Ağırlıklarını Doğrula','Teorik ağırlıkları düzeltir.'],
 ['Onarım','pile_org','Kazık Organizasyonunu Eşitle','Sistem / yapı / aks atamaları.'],
 ['Onarım','retag','MST Tag\'lerini Oluştur / Güncelle','Tüm elemanların Tag\'i (tek Geri Al).'],
 ['Onarım','ext_rebar','Eklenti Dışı BK Donatısını Temizle','Tanıtılan BK\'larda yanlış oluşmuş donatıyı siler, pursantaja döner.'],
 ['Donatı','dwg_rebar','Çizimden Donatı (seçili BK)','Proje donatı çizimindeki pozları tek tek 3B çizer; kanala girmez, metraj donatı tablosundan.'],
 ['Donatı','auto_rebar','Otomatik Donatı (seçili BK)','Kanalları / duvarları kendisi tanır, çap-aralık sorar; tonaj çizilen çubuklardan.'],
 ['Donatı','dwg_rebar_off','Çizimden / Otomatik Donatıyı Sil','Seçili (yoksa bütün) BK\'larda çizimden ya da otomatik donatıyı siler, pursantaja döner.'],
 ['Donatı','rebar_upgrade','Eski Donatıyı Yeni Kurallarla Yeniden Çiz','v0.48 ile çizilen çizimden / otomatik donatıyı kayıtlı parametreleriyle yeniden çizer (oval büküm, 50Ø şaşırtmalı, parapet).'],
 ['Donatı','rebar_settings','Donatı Ayarları (proje)','Pas payı BK / döşeme / prekast (50 / 75 mm), bindirme ×Ø, şaşırtma.'],
 ['Donatı','rebar_toggle','Donatıyı Göster / Gizle','Bütün MST | DONATI tag\'leri (varsayılan gizli; metraj etkilenmez).'],
 ['Donatı','bending','Bükme Listesi + Kesim Planı','Çizilmiş 3B donatıdan Excel + krokili liste; 12 m stoktan kesim, fire %.'],
 ['Donatı','section','Donatı Kesiti (seçili BK)','İstenen noktada 2B kesit: beton, kesilen çubuklar, düzlemdeki etriyeler.'],
 ['Donatı','revision','Donatı Revizyon Karşılaştırması','Seçili elemanın önceki ↔ şimdiki donatısı poz poz, Ø özeti.'],
 ['Donatı','clash','Elemanlar Arası Donatı Çakışması','BK / döşeme / prekast donatıları birbirine giriyor mu; çakışanları kırmızı boyar.'],
 ['Donatı','clash_clear','Çakışma Renklerini Temizle','Kırmızı boyanan çubuklar çap rengine döner.'],
 ['Proje','af_piles','A-Çerçeve Eğik Kazık Çiftleri','Aks, çift aralığı, kafa aralığı, eğim (1/6), enine / boyuna, A / V; çakışma kontrolü; kazık formu değerleriyle.'],
 ['Proje','kd_dxf','Kazık Dispozisyonu — DXF Paftasından','Kazık daireleri, çap (katman adından), kazık no, eğik kazık açısı; aks çizgileri + aks adları → Aks Yöneticisi, kazıklar aks kesişimlerine (ör. 75/A); birim ve dönme kendiliğinden.'],
 ['Proje','kf_fit','Kazık Filizini BK\'ya Göre Ayarla','Seçili kazıkların donatı filizi: BK üstü − pas payı − üst ağ payı.'],
 ['Proje','vk','Vinç / Boylama Kirişi (iki BK arası)','VK / BBK BK\'lara dik, BK yüzünde biter; alın kalıbı yok, BK kalıbından temas düşülür; ray tipi + klips metrajı.'],
 ['Proje','culvert','Menfez Sac Kutusu (seçili BK)','BK içinden geçen menfez: beton + yüz kalıbı düşülür, sac kg metraja; donatı kesilir, takviye konur.'],
 ['Proje','bottom_zone','BK Taban Bölgesi (alçak taban)','BK boyunca aralıkta derin taban (uç dişlerine ek); beton, kalıp, donatı.'],
 ['Proje','stage','Kademeli Döküm (BK / dolfen)','1. kademe yüksekliği; beton ve kalıp iki kademeye bölünür, iş programında iki adım.'],
 ['Proje','stage_report','Kademeli Döküm Metrajı','Kademeli elemanların 1. / 2. kademe beton ve kalıbı (HTML).'],
 ['Proje','pc_rebar','Prekast Donatısı (PD / PK)','Alt / üst boyuna (BK\'ya giriş boyu), enine U, taşan etriye şeritleri, kaldırma kancaları; kanal prekastında sarma U, duvar şapkası.'],
 ['Proje','dr_auto','Paftadan 3B Donatı (otomatik, DXF)','Seçili BK(lar)a donatı paftasından 3B donatı: tablo + krokiler + kesitler + boy görünüşü okunur; yerleştirilemeyen poz yalnız metrajda kalır. Paket modele kaydedilir.'],
 ['Proje','dxf_rebar','Paftadan Donatı Metrajı (DXF)','Donatı paftasındaki krokilerden poz tablosu (adet × Ø × L); seçili elemanın metrajı paftadan ya da karşılaştırma.'],
 ['Proje','dxf_rebar_off','Paftadan Donatı Metrajını Kaldır','Seçili elemanlar önceki (3B / pursantaj) donatısına döner.'],
 ['Proje','topping_slope','Kaplama Eğimi','En ince kalınlık + eğim % → ortalama kalınlık; tek yöne / sırttan iki yana.'],
 ['Proje','materials','Malzeme Sınıfları (beton / donatı çeliği)','Proje donatı çeliği (B420C / B500C …), seçili elemanlara beton sınıfı ve çelik.'],
 ['İş Programı','schedule','İş Programı Oluştur','Modelden faaliyetler, Gantt, haftalık malzeme / ekip, aylık hakediş tahmini (Excel + HTML).'],
 ['İş Programı','schedule_settings','İş Programı Ayarları','Verimler (varsayılan, kaynaklı), ekip sayıları, takvim, başlangıç tarihi.'],
 ['İş Programı','schedule_4d','4D Görünüm','Elemanları bittiği aya göre renklendir ya da bir haftadaki durumu göster.'],
 ['İş Programı','schedule_4d_clear','4D Temizle','4D renk / gizleme eski hâline döner.'],
 ['Görünüm','labels_on','Kazık Numaralarını Göster / Güncelle','Numaralar plan konumunda yazı olarak (metraj değişmez).'],
 ['Görünüm','labels_off','Kazık Numaralarını Kaldır','Bütün numara yazılarını siler.'],
 ['Görünüm','find','Numarayla Bul','Kazık / eleman numarasını yaz, modelde seç ve göster.'],
 ['Görünüm','pe_on','PE Kaplama Görünümünü Göster / Güncelle','PE kaplamalı kazık bölümü farklı renkte (metraj değişmez).'],
 ['Görünüm','pe_off','PE Kaplama Görünümünü Kaldır','PE renk kılıflarını siler.'],
 ['Görünüm','pe_top','PE Üst Kotunu Ayarla','PE kaplamanın başladığı kot (seçili / bütün kazıklar); metraj değişmez.'],
 ['Kütüphane','element_library','Eleman Kütüphanesi','Modeldeki tip imzaları.'],
 ['Kütüphane','boq_library','Keşif Kütüphanesi','Birim fiyat arşivi.'],
 ['Kütüphane','boq_mapping','ÖBF – Model Miktarı Eşleştirme','Keşif satırı ↔ model miktarı.'],
 ['Kazık','pile_edit_v2','Seçili Kazığı Düzenle (Kazık Yerleşimi)','Eski tekli kazık düzenleyici.'],
 ['Kazık','pile_batch','Toplu Kazık Detay Güncelle','Seçili kazıklara toplu detay.'],
 ['Dışa Aktarım','takeoff','Detaylı Metraj Raporu','Tüm metraj tabloları.'],
 ['Dışa Aktarım','excel','Ayrıntılı Metraj (Excel)','Excel dosyası.'],
 ['Dışa Aktarım','csv','Keşif / Metraj CSV Dışa Aktar','CSV dosyası.'],
 ['Eski','boq_engine','Keşif Motoru (eski)','Eski keşif ekranı.'],
 ['Eski','flat_precast','Düz Prekast (PD) Yerleşimi (eski)','Eski PD aracı; yeni araç Prekast sayfasındadır.']
].freeze

def mst_maint_run(key)
 case key.to_s
 when 'model_audit' then model_audit
 when 'dependency' then stamp_dependency_metadata
 when 'bim_core' then bim_data_core_report
 when 'safe_repair' then mst_safe_repair
 when 'deck_repair' then repair_deck_bim_relationships
 when 'identity_repair' then repair_bim_identity
 when 'pile_types' then mst_repair_pile_type_library
 when 'ring_rule' then mst_ring_rule_normalize_all
 when 'pipe_weights' then mst_reconcile_pile_weights!
 when 'pile_org' then mst_repair_pile_organization
 when 'retag' then mst_retag_all(true)
 when 'ext_rebar' then mst_hb_rebar_clean_ui
 when 'dwg_rebar' then mst_dr_selected_ui
 when 'auto_rebar' then mst_ar_selected_ui
 when 'dwg_rebar_off' then mst_dr_remove_ui
 when 'rebar_upgrade' then mst_rt_upgrade_ui
 when 'rebar_settings' then mst_rs_ui
 when 'rebar_toggle' then mst_rt_toggle_ui
 when 'bending' then mst_rt_bending_ui
 when 'section' then mst_rt_section_ui
 when 'revision' then mst_rt_revision_ui
 when 'clash' then mst_rt_clash_ui
 when 'clash_clear' then mst_rt_clash_clear_ui
 when 'af_piles' then mst_af_ui
 when 'kd_dxf' then mst_kd_ui
 when 'kf_fit' then mst_kf_fit_ui
 when 'vk' then mst_vk_ui
 when 'culvert' then mst_cv_ui
 when 'bottom_zone' then mst_bz_ui
 when 'stage' then mst_hb_stage_ui
 when 'stage_report' then mst_hb_stage_report_ui
 when 'pc_rebar' then mst_pc_ui
 when 'dr_auto' then mst_dra_ui
 when 'dxf_rebar' then mst_dxr_ui
 when 'dxf_rebar_off' then mst_dxr_remove_ui
 when 'topping_slope' then mst_tp_ui
 when 'materials' then mst_ms_ui
 when 'schedule' then mst_sp_ui
 when 'schedule_settings' then mst_sp_settings_ui
 when 'schedule_4d' then mst_sp_4d_ui
 when 'schedule_4d_clear' then mst_sp_4d_clear_ui
 when 'labels_on' then mst_labels_ui(true)
 when 'labels_off' then mst_labels_ui(false)
 when 'find' then mst_find_ui
 when 'pe_on' then mst_pe_ui(true)
 when 'pe_off' then mst_pe_ui(false)
 when 'pe_top' then mst_pe_top_ui
 when 'element_library' then element_library
 when 'boq_library' then show_boq_library
 when 'boq_mapping' then show_boq_mapping
 when 'pile_edit_v2' then edit_selected_pile_v2
 when 'pile_batch' then batch_update_selected_pile_details
 when 'takeoff' then takeoff
 when 'excel' then export_professional_excel
 when 'csv' then export_boq_csv
 when 'boq_engine' then show_boq_engine
 when 'flat_precast' then create_flat_precast
 else raise "Bilinmeyen bakım işlemi: #{key}"
 end
 mst_send_workflow_status
rescue => e
 UI.messagebox("Model Bakımı: #{e.message}")
end

def mst_send_maint(dialog=@d)
 return unless dialog
 dialog.execute_script("mstMaintRender(#{JSON.generate(MST_MAINT_ACTIONS.map{|g,k,t,d|{group:g,key:k,title:t,desc:d}})})")
end

def mst_send_rebar_page(dialog=@d)
mst_read_batch do   # v0.51.5 P2: salt okuma, tek model taraması
 return unless dialog
 rows=mst_rebar_source_summary
 all=[];collect_elements(Sketchup.active_model.entities,all)
 dia=(mst_rt_dia_rows(all) rescue nil)   # v0.49 DM1: çap çap
 dialog.execute_script("mstRebarPage(#{JSON.generate({rows:rows,rates:Hash[REBAR_DEFAULTS.keys.map{|k|[k,rebar_rate(k)]}],dia:dia,settings:(mst_rs_all rescue {})})})")
end # mst_read_batch
rescue => e
 puts "MST donatı sayfası: #{e.message}"
end

def mst_register_flow_callbacks(d)
 d.add_action_callback('workflow_status'){|_,page=nil|mst_ui_page_note(page);mst_send_workflow_status(d)}   # G1: sayfa kimliği (varsa) Çalışma Alanı yenilemesi için
 d.add_action_callback('maint_list'){|_|mst_send_maint(d)}
 d.add_action_callback('maint_action'){|_,k|mst_maint_run(k)}
 d.add_action_callback('rebar_sources_get'){|_|mst_send_rebar_page(d)}
 d.add_action_callback('rebar_tool'){|_,k|mst_maint_run(k);mst_send_rebar_page(d)}   # v0.49 RT1 Donatı sayfası düğmeleri
end

def show_dialog
 if @d&&@d.visible?;@d.bring_to_front;return;end
 @d=UI::HtmlDialog.new(dialog_title:"Deniz Yapıları Araçları (MST) v#{VERSION}",preferences_key:'MAG_MST_Main',width:1440,height:920,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
 @d.set_file(File.join(__dir__,'ui.html'))
 mst_host_reset!;mst_register_embed_callbacks(@d)   # v0.38 UI2: tek pencere
 mst_register_flow_callbacks(@d)   # v0.38 UI4/UI5
 boq2_register_callbacks(@d)   # v0.47 BQ1
 @d.add_action_callback('elevation_sync'){|_,raw|elevation_sync_show(raw)}
 @d.add_action_callback('material_change'){|_,raw|material_change_show(raw)}
 @d.add_action_callback('model_health'){|_|model_health_show}
 @d.add_action_callback('scoped_model_health'){|_,raw|scoped_model_health_show(raw)}
 @d.add_action_callback('relationship_audit'){|_|relationship_audit_show}
 @d.add_action_callback('project_workspace_refresh'){|_|project_workspace_refresh(@d)}
 @d.add_action_callback('project_workspace_action'){|_,raw|project_workspace_action(raw,@d)}
 @d.set_on_closed{project_workspace_detach;@mst_ui_page=nil}   # G1: açık sayfa kaydı pencereyle biter
 @d.add_action_callback('generatePileLayout'){|_,j|generate_layout(JSON.parse(j))}
 @d.add_action_callback('pile_load_central_grid'){|_|begin
   model=Sketchup.active_model
   system=model.get_attribute(DICT,'project_system_type','ISKELE').to_s.upcase
   system='ISKELE' unless %w[DOLFEN ISKELE RIHTIM].include?(system)
   structure=mst_active_structure_for_system(system,model)
   grid=mst_axis_grid_for(structure,model,structure)
   ys=grid['y']; xsign=(grid['x_dir'].to_s=='-X' ? -1.0 : 1.0); ysign=(grid['y_dir'].to_s=='-Y' ? -1.0 : 1.0)
   # v0.38 PR1.1: points that already carry a pile of this structure are shown as existing (not selected)
   occ={};maxno=0
   collect_piles(model.entities).each do |pp,_|
    pid=pp.get_attribute(DICT,'pile_id','').to_s;maxno=[maxno,pid[/(\d+)\s*\z/,1].to_i].max
    ps_=pp.get_attribute(DICT,'structure','').to_s;ps_=pp.get_attribute(DICT,'ano','').to_s if ps_.empty?
    occ[[pp.get_attribute(DICT,'grid_x_axis','').to_s,pp.get_attribute(DICT,'grid_y_axis','').to_s]]=pid if ps_==structure.to_s
   end
   amap=mst_axis_display_names(model)   # ADR-0515-I: name = kod (kimlik / imza), display_label = görünen ad
   axes=grid['x'].map{|xr| {'name'=>xr['name'].to_s,'display_label'=>mst_axis_display(structure,structure,'x',xr['name'],amap),'x'=>xr['coord_m'].to_f*xsign,'points'=>ys.map{|yr| ex=occ[[xr['name'].to_s,yr['name'].to_s]];{'name'=>yr['name'].to_s,'display_label'=>mst_axis_display(structure,structure,'y',yr['name'],amap),'y'=>yr['coord_m'].to_f*ysign,'selected'=>ex.nil?,'existing'=>ex.to_s,'dx'=>0.0,'dy'=>0.0}}} }
   origin=mst_structure_origin(system,structure,model)
   payload={'system'=>system,'structure'=>structure,'structure_label'=>mst_structure_label(structure,nil,model),'origin_x_m'=>origin[0].to_f,'origin_y_m'=>origin[1].to_f,'next_start_no'=>maxno+1,'existing_count'=>occ.length}
   @d.execute_script("loadCentralGridIntoPile(#{JSON.generate(axes)},#{JSON.generate(system)},#{JSON.generate(structure)},#{JSON.generate(payload)})") if @d
  rescue=>e;UI.messagebox("Aktif Sistem / Yapı gridi yüklenemedi: #{e.message}");end}
 @d.add_action_callback('pile_open_override'){|_,raw|begin
   payload=JSON.parse(raw); points=payload['points']||[]; raise 'Seçili kazık noktası yok.' if points.empty?
   lbl=mst_pile_override_labels(payload)   # G5c ADR-0515-I: başlık / nokta listesi görünen ad; payload ve geri gönderilen değerler kod
   html = <<~HTML
   <!doctype html><html><head><meta charset="utf-8"><style>
   *{box-sizing:border-box}body{font-family:Arial,sans-serif;margin:0;color:#29495d;background:#f7fafc;font-size:12px}.head{display:flex;justify-content:space-between;align-items:center;padding:13px 16px;background:#eaf4fa;border-bottom:1px solid #cbdde8}.head b{font-size:15px;color:#12608f}.body{padding:15px}.note{background:#eef7fc;border-left:3px solid #2c8abd;padding:8px 10px;margin-bottom:12px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}label{font-size:11px;color:#587184}input,select{display:block;width:100%;min-width:0;height:34px;margin-top:4px;border:1px solid #b9cbd7;border-radius:4px;padding:5px 7px;background:white}.readonly{background:#eef3f6!important;color:#496879;font-weight:600}.section{grid-column:1/-1;border-top:1px solid #dce7ed;margin-top:5px;padding-top:10px;font-weight:bold;color:#1b668f}.actions{display:flex;justify-content:flex-end;gap:8px;padding:12px 15px;border-top:1px solid #dce7ed;background:white}button{padding:8px 18px;border:1px solid #8eb4cb;border-radius:4px;background:#1674a8;color:white;cursor:pointer}.ghost{background:white;color:#42677d}.span2{grid-column:span 2}@media(max-width:620px){.grid{grid-template-columns:1fr 1fr}}
   </style></head><body><div class="head"><b>⚙ Kazık Özel Ayarları</b><span>#{html_escape(lbl['axis'])}</span></div><div class="body"><div class="note">Boş bırakılan alanlar genel kazık ayarını kullanır.</div><div class="grid">
   <label>Kazık Noktası<select id="pt"></select></label><label>Kazık ID<input id="pile_id" class="readonly" readonly title="Otomatik Kazık ID"></label><label>Kazık Grubu<input id="pile_group" class="readonly" readonly title="Sistem / Yapıdan otomatik"></label>
   <div class="section">Konuma Özel Değer</div><label>ΔX (m)<input id="dx" type="number" step="0.01"></label><label>ΔY (m)<input id="dy" type="number" step="0.01"></label><div></div>
   <div class="section">Geometri / Doğrultu</div><label>Doğrultu<select id="orientation_mode"><option value="">Genel</option><option value="VERTICAL">Düşey</option><option value="BATTERED">Batarlı</option></select></label><label>H/V<input id="batter_ratio"></label><label>Azimut (°)<input id="azimuth_deg" type="number" step="0.1"></label><label>Ø (mm)<input id="diameter_mm" type="number" step="0.1"></label><label>t (mm)<input id="thickness_mm" type="number" step="0.1"></label><label>L (m)<input id="length_m" type="number" step="0.01"></label><label>Çelik Sınıfı<input id="steel_grade"></label><div></div><div></div>
   <div class="section">Özel Kazık Üst Kotu / BIM Bağlantısı</div><label>Kot Tipi<select id="elevation_mode"><option value="GENERAL">Genel</option><option value="SPECIAL">Özel</option></select></label><label>Özel Üst Kot (m)<input id="top_elevation_m" type="number" step="0.01"></label><label>Kot Sebebi<select id="elevation_reason"><option value="">—</option><option value="UTILITY_CHANNEL">Tesisat Kanalı</option><option value="CRANE_BEAM">Vinç Kirişi</option><option value="HEAD_BEAM">Başlık Kirişi</option><option value="OTHER">Diğer</option></select></label><label>Bağlı Eleman ID<input id="linked_element_id" placeholder="örn. BK-03 / VK-01"></label><div class="note span2">BK / Vinç Kirişi modülleri geldiğinde Bağlı Eleman alanı BIM ID açılır listesi olacaktır.</div>
   </div></div><div class="actions"><button class="ghost" onclick="resetVals()">Genel Değerlere Dön</button><button onclick="save()">Kaydet</button></div>
   <script>const payload=#{JSON.generate(payload).gsub('</','<\/')};const mstLbl=#{JSON.generate(lbl).gsub('</','<\/')};let cur=0;const ids=['pile_id','pile_group','dx','dy','orientation_mode','batter_ratio','azimuth_deg','diameter_mm','thickness_mm','length_m','steel_grade','elevation_mode','top_elevation_m','elevation_reason','linked_element_id'];const pt=document.getElementById('pt');payload.points.forEach((p,i)=>{let o=document.createElement('option');o.value=i;o.textContent=mstLbl.axis+'/'+(mstLbl.points[i]||p.point_name);pt.appendChild(o)});function load(){cur=+pt.value||0;let d=payload.points[cur].data||{};ids.forEach(id=>{document.getElementById(id).value=(d[id]===undefined||d[id]===null)?'':d[id]});document.getElementById('dx').value=d.dx||0;document.getElementById('dy').value=d.dy||0;toggle()}function toggle(){let sp=document.getElementById('elevation_mode').value==='SPECIAL';['top_elevation_m','elevation_reason','linked_element_id'].forEach(id=>document.getElementById(id).disabled=!sp)}document.getElementById('elevation_mode').onchange=toggle;pt.onchange=load;function data(){let d={};ids.forEach(id=>d[id]=document.getElementById(id).value);d.dx=parseFloat(d.dx)||0;d.dy=parseFloat(d.dy)||0;if(d.elevation_mode!=='SPECIAL'){d.top_elevation_m='';d.elevation_reason='';d.linked_element_id=''}return d}function save(){sketchup.pile_override_save(JSON.stringify({axis_index:payload.axis_index,point_index:payload.points[cur].point_index,data:data()}))}function resetVals(){ids.filter(id=>!['pile_id','pile_group'].includes(id)).forEach(id=>document.getElementById(id).value='');let d=payload.points[cur].data||{};document.getElementById('pile_id').value=d.pile_id||'';document.getElementById('pile_group').value=d.pile_group||'';document.getElementById('dx').value=0;document.getElementById('dy').value=0;document.getElementById('elevation_mode').value='GENERAL';toggle()}pt.value='0';load();</script></body></html>
   HTML
   @pile_override_dialog.close if @pile_override_dialog && @pile_override_dialog.visible?
   @pile_override_dialog=mst_html_dialog('pile_override',dialog_title:'Kazık Özel Ayarları',preferences_key:'MAG_MST_PileOverride',width:900,height:650,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
   @pile_override_dialog.set_html(html)
   @pile_override_dialog.add_action_callback('pile_override_save'){|dlg,j|begin; obj=JSON.parse(j); @d.execute_script("applyPileOverrideFromDialog(#{JSON.generate(obj)})") if @d; dlg.close; rescue=>e; UI.messagebox("Kazık özel ayarı kaydedilemedi: #{e.message}");end}
   @pile_override_dialog.show
 rescue=>e;UI.messagebox("Kazık Özel Ayarları açılamadı: #{e.message}");end}
 @d.add_action_callback('pile_apply_selected_orientation'){|_,j|begin;n=apply_selected_pile_orientations(JSON.parse(j));@d.execute_script("pileLiveApplyDone(#{n})") if @d;rescue=>e;UI.messagebox("Seçili kazık doğrultuları uygulanamadı: #{e.message}");end}
 @d.add_action_callback('pile_load_selected_for_edit'){|_|begin
  piles=selected_piles.map{|entry|entry.is_a?(Array) ? entry[0] : entry}.select{|g|g.valid? && g.get_attribute(DICT,'element_type','')=='steel_pipe_pile'}.uniq
  payload={'count'=>piles.length,'ids'=>piles.map{|g|g.get_attribute(DICT,'pile_id','?').to_s},'points'=>piles.map{|g|{'id'=>g.get_attribute(DICT,'pile_id','?').to_s,'label'=>g.get_attribute(DICT,'grid_point','').to_s}}}
  payload['pile']=mst_selected_bim_pile_payload if piles.length==1
  @d.execute_script("mstPileSelectionLoaded(#{JSON.generate(payload)})") if @d
 rescue=>e;UI.messagebox("Seçili kazıklar yüklenemedi: #{e.message}");end}
 @d.add_action_callback('pile_technical_report'){|_,ids_json|begin

  piles=selected_piles.map{|entry|entry.is_a?(Array) ? entry[0] : entry}.select{|g|g.valid? && g.get_attribute(DICT,'element_type','')=='steel_pipe_pile'}.uniq
  requested=begin;Array(JSON.parse(ids_json.to_s)).map(&:to_s).reject(&:empty?);rescue;[];end
  if piles.empty? && !requested.empty?
    all=[];collect_elements(Sketchup.active_model.entities,all)
    piles=all.select{|g|g.valid? && g.get_attribute(DICT,'element_type','')=='steel_pipe_pile' && requested.include?(g.get_attribute(DICT,'pile_id','').to_s)}.uniq
  end
  raise 'Önce modelde bir BIM kazığı seçin.' if piles.empty?

  report=piles.map do |p|
   v=lambda{|key,default|p.get_attribute(DICT,key,default)}
   d=v.call('diameter_mm',0).to_f; t=v.call('thickness_mm',0).to_f; di=d-2*t
   clr=v.call('plug_clearance_mm',10).to_f; thick=v.call('plug_thickness_mm',12).to_f
   pc=v.call('plug_enabled','0').to_s=='1' ? [v.call('plug_count_per_pile',1).to_i,1].max : 0
   lc=v.call('lower_ring_enabled','0').to_s=='1' ? [v.call('lower_ring_count_per_pile',1).to_i,1].max : 0
   uc=v.call('upper_ring_enabled','0').to_s=='1' ? [v.call('upper_ring_count_per_pile',1).to_i,1].max : 0
   lw=v.call('lower_ring_width_mm',300).to_f; lt=v.call('lower_ring_thickness_mm',t).to_f
   uw=v.call('upper_ring_width_mm',250).to_f; ut=v.call('upper_ring_thickness_mm',t).to_f
   dp=[di-2*clr,0].max
   pk=Math::PI/4.0*(dp/1000.0)**2*(thick/1000.0)*RHO*pc
   lk=Math::PI*([di-lt,0].max/1000.0)*(lw/1000.0)*(lt/1000.0)*RHO*lc
   uk=Math::PI*((d+ut)/1000.0)*(uw/1000.0)*(ut/1000.0)*RHO*uc

   # Technical detail must not invoke the complete project QTO pipeline.
   # Report raw BIM dimensions and independent geometry formulas only.
   # Compare with the main QTO screen as a separate acceptance check.
   {'id'=>v.call('pile_id','?').to_s,'diameter'=>d,'wall'=>t,'inner'=>di,'clearance'=>clr,'plug_thickness'=>thick,'plug_diameter'=>dp,'plug_count'=>pc,'plug_kg'=>pk,'lower_width'=>lw,'lower_thickness'=>lt,'lower_count'=>lc,'lower_kg'=>lk,'upper_width'=>uw,'upper_thickness'=>ut,'upper_count'=>uc,'upper_kg'=>uk,'qto_plug_kg'=>nil,'qto_lower_kg'=>nil,'qto_upper_kg'=>nil}
  end
  json=JSON.generate(report)
  @d.execute_script("mstTechnicalReportLoaded(#{json})") if @d
 rescue Exception=>e
  msg="#{e.class}: #{e.message} (#{Array(e.backtrace).first})"
  puts "[MST Technical Report] #{msg}"
  @d.execute_script("mstTechnicalReportError(#{JSON.generate(msg)})") if @d
 end}
 @d.add_action_callback('pile_batch_inline_apply'){|_,json|begin
  data=JSON.parse(json); ids=Array(data['ids']).map(&:to_s); changes=data['changes']||{}
  allowed=%w[drilling_enabled drilling_length_m pe_enabled pe_length_m plug_enabled plug_count_per_pile lower_ring_enabled lower_ring_count_per_pile upper_ring_enabled upper_ring_count_per_pile infill_enabled infill_bottom_elevation_m infill_concrete_class diameter_mm thickness_mm plug_thickness_mm plug_clearance_mm lower_ring_width_mm lower_ring_thickness_mm upper_ring_width_mm upper_ring_thickness_mm]
  raise 'Geçersiz toplu işlem alanı.' unless changes.keys.all?{|k|allowed.include?(k)}
  raise 'Güncelleme alanı seçilmedi.' if changes.empty?
  piles=selected_piles.map{|entry|entry.is_a?(Array) ? entry[0] : entry}.select{|g|g.valid? && g.get_attribute(DICT,'element_type','')=='steel_pipe_pile'}.uniq
  actual=piles.map{|g|g.get_attribute(DICT,'pile_id','').to_s}
  raise 'Model seçimi değişti; kazıkları yeniden yükleyin.' unless actual.sort==ids.sort && !ids.empty?
  changes.each{|k,v| if k=='infill_concrete_class';raise 'Geçersiz beton sınıfı' unless %w[C30/37 C35/45 C40/50 C45/55 C50/60].include?(v.to_s);elsif k.end_with?('_enabled');raise 'Geçersiz durum' unless %w[0 1].include?(v.to_s);else;n=Float(v.to_s.tr(',','.'));raise 'Geçersiz sayısal değer' unless n.finite?;raise 'Pozitif miktar gerekli' if !%w[infill_bottom_elevation_m plug_clearance_mm].include?(k) && n<=0;raise 'Tam sayı gerekli' if k.include?('count_per_pile') && n!=n.to_i;end}
  # v0.51.5 K29 (N8): JS sayıyı JSON number gönderir (tam sayı → Integer); kayıtta oluşturma ile aynı tip: adet Integer, ölçü Float
  changes=changes.map{|k,v|[k,(k=='infill_concrete_class' || k.end_with?('_enabled')) ? v : (k.include?('count_per_pile') ? Float(v.to_s.tr(',','.')).to_i : Float(v.to_s.tr(',','.')))]}.to_h
  piles.each do |pile|
   d=changes.key?('diameter_mm') ? changes['diameter_mm'].to_f : pile.get_attribute(DICT,'diameter_mm',0).to_f
   t=changes.key?('thickness_mm') ? changes['thickness_mm'].to_f : pile.get_attribute(DICT,'thickness_mm',0).to_f
   raise "#{pile.get_attribute(DICT,'pile_id','?')}: Ø/t kesiti geçersiz." unless d>0 && t>0 && 2*t<d
  end
  model=Sketchup.active_model;model.start_operation('MST Seçili BIM Kazıkları Toplu Güncelle',true)
  begin
   mst_scan_batch(model) do
   piles.each do |pile|
    if changes.key?('diameter_mm') || changes.key?('thickness_mm')
     d=changes.key?('diameter_mm') ? changes['diameter_mm'].to_f : pile.get_attribute(DICT,'diameter_mm',0).to_f
     t=changes.key?('thickness_mm') ? changes['thickness_mm'].to_f : pile.get_attribute(DICT,'thickness_mm',0).to_f
     grade=pile.get_attribute(DICT,'steel_grade','S355J2H').to_s
     # One canonical section rebuild for single, TYPE and batch editors.
     # This preserves the parent transform, BIM identities and physical infill child.
     mst_rebuild_pile_section_dependencies(pile,d,t,grade)
    end
    if changes.key?('infill_enabled')
      enabled=changes['infill_enabled'].to_s=='1'
      if enabled
        d=pile.get_attribute(DICT,'diameter_mm',0).to_f
        t=pile.get_attribute(DICT,'thickness_mm',0).to_f
        top=pile.get_attribute(DICT,'top_elevation_m',0).to_f
        len=pile.get_attribute(DICT,'length_m',0).to_f
        mode=pile.get_attribute(DICT,'orientation_mode','VERTICAL')
        ratio=pile.get_attribute(DICT,'batter_ratio',0)
        az=pile.get_attribute(DICT,'azimuth_deg',0)
        pd={'diameter_mm'=>d,'thickness_mm'=>t,'top_elevation_m'=>top,'length_m'=>len,'orientation_mode'=>mode,'batter_ratio'=>ratio,'azimuth_deg'=>az,'infill_enabled'=>'1','infill_bottom_normal_m'=>changes['infill_bottom_elevation_m'],'infill_concrete_class'=>changes['infill_concrete_class']}
        _,_,_,_,vz=pile_orientation(pd)
        bottom=changes['infill_bottom_elevation_m'].to_f
        raise "#{pile.get_attribute(DICT,'pile_id','?')}: beton alt kotu kazık sınırları dışında." unless bottom<top && bottom>=top-len*vz-0.0001
      end
      if mst_component_pile?(pile)
        # v0.38 C6: shared infill child is never touched; the matching definition is
        # attached by the detail refresh below (mst_apply_pile_detail_changes).
        if enabled
          pile.set_attribute(DICT,'infill_enabled','1')
          pile.set_attribute(DICT,'infill_bottom_elevation_m',changes['infill_bottom_elevation_m'].to_f)
          pile.set_attribute(DICT,'infill_concrete_class',changes['infill_concrete_class']) if changes['infill_concrete_class']
        else
          pile.set_attribute(DICT,'infill_enabled','0')
          pile.set_attribute(DICT,'infill_concrete_volume_m3',0.0)
          pile.set_attribute(DICT,'infill_bottom_elevation_m',nil)
        end
      else
      pile.entities.grep(Sketchup::Group).select{|g|g.get_attribute(DICT,'element_type','')=='pile_infill_concrete'}.each(&:erase!)
      if enabled
        add_pile_infill(pile,pd,'NORMAL')
        pile.set_attribute(DICT,'infill_enabled','1')
        pile.set_attribute(DICT,'infill_concrete_class',changes['infill_concrete_class'])
      else
        pile.set_attribute(DICT,'infill_enabled','0')
        pile.set_attribute(DICT,'infill_concrete_volume_m3',0.0)
        pile.set_attribute(DICT,'infill_bottom_elevation_m',nil)
      end
      end
    end
    detail_changes=changes.reject{|k,_|%w[infill_enabled infill_bottom_elevation_m infill_concrete_class diameter_mm thickness_mm].include?(k)}
    mst_apply_pile_detail_changes(pile,detail_changes)
   end
   end # mst_scan_batch
   mst_sync_pile_type_library(model) if changes.key?('diameter_mm') || changes.key?('thickness_mm') || changes.key?('infill_concrete_class') || changes.key?('infill_enabled')
   commit_with_dependencies(model)
  rescue=>e;model.abort_operation;raise e;end
  @d.execute_script("mstBatchApplied(#{JSON.generate(piles.length.to_s+' kazık güncellendi. Metraj yenilendi; tek Geri Al ile geri alınabilir.')})") if @d
 rescue=>e;UI.messagebox("Toplu BIM güncelleme başarısız: #{e.message}");end}
 @d.add_action_callback('pile_inline_same_type_apply'){|_,json|begin
  data=JSON.parse(json); id=data['id'].to_s; changes=data['changes']||{}
  raise 'TYPE güncellemesi için yalnız Ø / et kalınlığı kullanılabilir.' unless !changes.empty? && changes.keys.all?{|k|%w[diameter_mm thickness_mm].include?(k)}
  all=[];collect_elements(Sketchup.active_model.entities,all)
  seed=all.find{|g|g.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile' && g.get_attribute(DICT,'pile_id','').to_s==id}
  raise 'Referans kazık bulunamadı; modeli yeniden yükleyin.' unless seed
  peers=mst_type_peers(seed); tid=seed.get_attribute(DICT,'type_id',seed.get_attribute(DICT,'library_type_id','')).to_s
  nd=changes.key?('diameter_mm') ? changes['diameter_mm'].to_f : seed.get_attribute(DICT,'diameter_mm',0).to_f
  nt=changes.key?('thickness_mm') ? changes['thickness_mm'].to_f : seed.get_attribute(DICT,'thickness_mm',0).to_f
  raise 'Ø/t kesiti geçersiz.' unless nd>0 && nt>0 && 2*nt<nd
  msg="#{tid} tipindeki #{peers.length} kazık güncellenecek.\n\nYeni kesit: Ø#{format('%.1f',nd)} / t#{format('%.1f',nt)}\n\nKazık ID, UID, boy, kot, aks, konum ve tekil detaylar korunur. Devam edilsin mi?"
  next unless UI.messagebox(msg,MB_YESNO)==IDYES
  specs=peers.each_with_object({}){|pile,h|h[pile]=[nd,nt,pile.get_attribute(DICT,'steel_grade','S355J2H').to_s]}
  mst_apply_pile_sections_atomic(peers,specs,"MST #{tid} Inline Type Update",true)
  @d.execute_script("mstBatchApplied(#{JSON.generate(tid+' • '+peers.length.to_s+' benzer kazık güncellendi. TİP + fiziksel geometri + metraj yenilendi.')})") if @d
 rescue=>e;Sketchup.active_model.abort_operation rescue nil;UI.messagebox("Aynı tip kazık güncellemesi başarısız: #{e.message}");end}
 @d.add_action_callback('pile_load_selected_bim'){|_|begin;p=mst_selected_bim_pile_payload;@d.execute_script("if(typeof loadSelectedBimPile==='function'){loadSelectedBimPile(#{JSON.generate(p)})}else{alert(#{JSON.generate('Bu işlem bu sürümde Kazık sayfasındaki “✎ Mevcut Kazığı Düzenle / Güncelle” → “↻ Modelden Seçili Kazığı Yükle” düğmesiyle yapılır.')})}") if @d;rescue=>e;UI.messagebox("BIM kazığı yüklenemedi: #{e.message}");end}
 @d.add_action_callback('pile_target_preview'){|_,j|begin
  @d.execute_script("mstPileTargetPreviewLoaded(#{JSON.generate(mst_pile_target_preview_payload(JSON.parse(j)))})") if @d
 rescue=>e;@d.execute_script("mstPileTargetPreviewError(#{JSON.generate(e.message)})") if @d;end}
 @d.add_action_callback('pile_body_convert_component'){|_,j|begin
  data=(JSON.parse(j.to_s) rescue {})
  uid=(mst_find_reference_pile(data,mst_all_bim_piles(Sketchup.active_model)).get_attribute(DICT,'element_uid','').to_s rescue '')
  done=mst_pile_convert_targets(data)
  ref=(mst_all_bim_piles(Sketchup.active_model).find{|e|!uid.empty? && e.get_attribute(DICT,'element_uid','').to_s==uid} rescue nil)
  @d.execute_script("mstPileRingNormalizeDone(#{JSON.generate(ref && ref.valid? ? mst_bim_pile_payload(ref) : nil)})") if @d && done
 rescue=>e;UI.messagebox("Kazık gövdesi dönüşümü başarısız: #{e.message}");end}
 @d.add_action_callback('pile_body_convert_group'){|_,j|begin
  data=(JSON.parse(j.to_s) rescue {})
  uid=(mst_find_reference_pile(data,mst_all_bim_piles(Sketchup.active_model)).get_attribute(DICT,'element_uid','').to_s rescue '')
  done=mst_pile_revert_targets(data)
  ref=(mst_all_bim_piles(Sketchup.active_model).find{|e|!uid.empty? && e.get_attribute(DICT,'element_uid','').to_s==uid} rescue nil)
  @d.execute_script("mstPileRingNormalizeDone(#{JSON.generate(ref && ref.valid? ? mst_bim_pile_payload(ref) : nil)})") if @d && done
 rescue=>e;UI.messagebox("Kazık gövdesi dönüşümü başarısız: #{e.message}");end}
 @d.add_action_callback('pile_definitions_purge'){|_,_j|begin
  mst_purge_unused_pile_definitions
 rescue=>e;UI.messagebox("Tanım temizleme başarısız: #{e.message}");end}
 @d.add_action_callback('pile_ring_rule_normalize_all'){|_,j|begin
  mst_ring_rule_normalize_all
  data=(JSON.parse(j.to_s) rescue {})
  ref=(mst_find_reference_pile(data,mst_all_bim_piles(Sketchup.active_model)) rescue nil)
  @d.execute_script("mstPileRingNormalizeDone(#{JSON.generate(ref && ref.valid? ? mst_bim_pile_payload(ref) : nil)})") if @d
 rescue=>e;UI.messagebox("Çember kurala çekme başarısız: #{e.message}");end}
 @d.add_action_callback('pile_target_apply'){|_,j|begin
  result=mst_apply_pile_target_update(JSON.parse(j));@d.execute_script("mstPileTargetApplied(#{JSON.generate(result)})") if @d
 rescue=>e;UI.messagebox("Hedef kazık güncellemesi başarısız: #{e.message}");end}
 @d.add_action_callback('crown_axis_info'){|_|crown_axis_info(@d)}
 @d.add_action_callback('rockfill_source'){|_,action|rockfill_source_action(action,@d)}
 @d.add_action_callback('rf_live'){|_,action,json|rf_live_action(action,json,@d)}
 @d.add_action_callback('rf02_cubage'){|_,action|rf02_cubage(action,@d)}
 @d.add_action_callback('rf02_action'){|_,action,json|rf02_setup(action,json,@d)}
 @d.add_action_callback('rockfill_axis_info'){|_|rockfill_axis_info(@d)}
 @d.add_action_callback('rockfill_load_library'){|_|rockfill_load_library(@d)}
 @d.add_action_callback('rockfill_save_library'){|_,j|rockfill_save_library(j,@d)}
 @d.add_action_callback('rockfill_save_project'){|_,j|rockfill_save_project(j,@d)}
 @d.add_action_callback('rockfill_autosave_project'){|_,j|rockfill_autosave_project(j)}
 @d.add_action_callback('rockfill_autosave_library'){|_,j|rockfill_autosave_library(j)}
 @d.add_action_callback('rockfill_load_project'){|_,alt|rockfill_load_project(@d,alt)}
 @d.add_action_callback('create_crown_wall'){|_,j|crown_create_action(j)}
 @d.add_action_callback('load_crown_wall'){|_|crown_load_selected(@d)}
 @d.add_action_callback('update_crown_wall'){|_,j|crown_update_action(j)}
 @d.add_action_callback('autoHeadBeam'){|_,j|(cbj=mst_cb_json(j,'Otomatik BK')) && auto_head_beam(cbj)}
 @d.add_action_callback('autoHeadBeamsBulk'){|_,j|(cbj=mst_cb_json(j,'Toplu otomatik BK')) && auto_head_beams_bulk(cbj)}
 @d.add_action_callback('mstBKProjectContext'){|_|begin
  model=Sketchup.active_model;sys=model.get_attribute(DICT,'project_system_type','ISKELE').to_s.upcase;sys='ISKELE' unless %w[DOLFEN ISKELE RIHTIM].include?(sys)
  systems={};active={};%w[DOLFEN ISKELE RIHTIM].each{|x|systems[x]=mst_structures_for_system(x,model);active[x]=mst_active_structure_for_system(x,model)}
  payload={'project'=>model.get_attribute(DICT,'project_name','').to_s,'system'=>sys,'structure'=>active[sys],'systems'=>systems,'active'=>active}
  @d.execute_script("mstBKProjectLoaded(#{JSON.generate(payload.merge(mst_structure_label_maps(systems,model)))})")
 rescue=>e;UI.messagebox("BK proje bilgisi: #{e.message}");end}
 @d.add_action_callback('mstBKSetProjectContext'){|_,raw|begin
  d=JSON.parse(raw);model=Sketchup.active_model;sys=d['system'].to_s.upcase;raise 'Geçersiz sistem' unless %w[DOLFEN ISKELE RIHTIM].include?(sys)
  name=d['structure'].to_s;raise 'Seçilen yapı bulunamadı' unless mst_structures_for_system(sys,model).include?(name)
  model.set_attribute(DICT,'project_name',d['project'].to_s.strip);model.set_attribute(DICT,'project_system_type',sys)
  mst_set_active_system_structure(sys,name,model)
  systems={};active={};%w[DOLFEN ISKELE RIHTIM].each{|x|systems[x]=mst_structures_for_system(x,model);active[x]=mst_active_structure_for_system(x,model)}
  @d.execute_script("mstBKProjectSaved(#{JSON.generate({'project'=>d['project'].to_s.strip,'system'=>sys,'structure'=>name,'systems'=>systems,'active'=>active}.merge(mst_structure_label_maps(systems,model)))})")
 rescue=>e;UI.messagebox("BK yapı seçimi: #{e.message}");end}
 @d.add_action_callback('mstBKAddProjectStructure'){|_,raw|begin
  d=JSON.parse(raw);model=Sketchup.active_model;sys=d['system'].to_s.upcase;raise 'Geçersiz sistem' unless %w[DOLFEN ISKELE RIHTIM].include?(sys)
  name=mst_code_validate(d['name'],MST_NAME_MAX_STRUCTURE,'Yapı kodu');raise 'Yapı adı boş olamaz' if name.empty?   # 25/11: Aks Yöneticisi ile aynı kod kuralı
  raise "Yapı kodu #{name} bu sistemde kullanılamaz (biçim başka sisteme ait)." unless mst_code_allowed_in_system?(sys,name)
  rows=mst_structures_for_system(sys,model);raise 'Bu yapı zaten mevcut' if rows.include?(name)
  hit=mst_system_structures(model).values.flatten.map(&:to_s).find{|c|mst_name_key(c)==mst_name_key(name)}
  raise "Yapı kodu #{name}, #{hit} koduyla çakışıyor (büyük / küçük harf ve I / İ ayrımı yapılmaz)." if hit
  src=d['source'].to_s;raise 'Kopyalanacak yapı bulunamadı' if !src.empty? && !rows.include?(src)
  mst_json_attr_guard!(model,'axis_grids_json',Hash,'Aks ağı') unless src.empty?
  mst_json_attr_guard!(model,'structure_zones_json',Hash,'Yapı / bölge listesi')
  mst_save_structures_for_system(sys,rows+[name],model)
  if !src.empty?
    grids=mst_axis_grids(model);old=grids[mst_axis_grid_key(src,src)];old=mst_axis_grid_for(src,model,src) unless old.is_a?(Hash);grids[mst_axis_grid_key(name,name)]=JSON.parse(JSON.generate(old)) if old.is_a?(Hash)
    model.set_attribute(DICT,'axis_grids_json',JSON.generate(grids))
  end
  model.set_attribute(DICT,'project_system_type',sys);mst_set_active_system_structure(sys,name,model)
  systems={};active={};%w[DOLFEN ISKELE RIHTIM].each{|x|systems[x]=mst_structures_for_system(x,model);active[x]=mst_active_structure_for_system(x,model)}
  @d.execute_script("mstBKProjectSaved(#{JSON.generate({'project'=>model.get_attribute(DICT,'project_name','').to_s,'system'=>sys,'structure'=>name,'systems'=>systems,'active'=>active}.merge(mst_structure_label_maps(systems,model)))})")
 rescue=>e;UI.messagebox("BK yeni yapı: #{e.message}");end}
 @d.add_action_callback('mstBKDeleteProjectStructure'){|_,raw|begin
  d=JSON.parse(raw);model=Sketchup.active_model;sys=d['system'].to_s.upcase;name=d['name'].to_s.strip
  raise 'Geçersiz sistem' unless %w[DOLFEN ISKELE RIHTIM].include?(sys)
  rows=mst_structures_for_system(sys,model)
  raise 'Yapı bulunamadı' unless rows.include?(name)
  raise 'Sistemdeki son yapı silinemez' if rows.length<=1
  used=mst_all_elements.any?{|e|e.respond_to?(:valid?) && e.valid? && e.respond_to?(:get_attribute) && e.get_attribute(DICT,'ano','').to_s==name}
  raise 'Bu yapıda BIM elemanları mevcut; önce ilgili elemanları taşıyın veya silin.' if used
  model.start_operation('MST Boş Yapıyı Sil',true)
  begin
    mst_save_structures_for_system(sys,rows.reject{|x|x==name},model)
    mst_json_attr_guard!(model,'axis_grids_json',Hash,'Aks ağı')
    grids=mst_axis_grids(model);grids.delete(mst_axis_grid_key(name,name));model.set_attribute(DICT,'axis_grids_json',JSON.generate(grids))
    mst_display_names_forget!(model,name) unless mst_system_structures(model).any?{|_s,a|a.is_a?(Array) && a.map(&:to_s).include?(name)}   # ADR-0515-I
    mst_set_active_system_structure(sys,mst_structures_for_system(sys,model).first,model)
    model.set_attribute(DICT,'project_system_type',sys)
    model.commit_operation
  rescue=>e;model.abort_operation;raise e;end
  systems={};active={};%w[DOLFEN ISKELE RIHTIM].each{|x|systems[x]=mst_structures_for_system(x,model);active[x]=mst_active_structure_for_system(x,model)}
  @d.execute_script("mstBKProjectSaved(#{JSON.generate({'project'=>model.get_attribute(DICT,'project_name','').to_s,'system'=>sys,'structure'=>active[sys],'systems'=>systems,'active'=>active}.merge(mst_structure_label_maps(systems,model)))})")
 rescue=>e;UI.messagebox("BK yapı silme: #{e.message}");end}
 @d.add_action_callback('mstBKReadLiveAxes'){|_|mst_bk_send_live_axes}
 @d.add_action_callback('mstBKLoadSelectedEdit'){|_|begin;@d.execute_script("mstBKEditLoaded(#{JSON.generate(mst_bk_load_selected_edit)})");rescue=>e;UI.messagebox("BK okuma: #{e.message}");end}
 @d.add_action_callback('mstBKBulkEdit'){|_,j|begin;r=mst_bk_bulk_edit(JSON.parse(j));@d.execute_script("mstBKBulkDone(#{JSON.generate(r)})");rescue=>e;UI.messagebox("BK toplu düzenleme: #{e.message}");end}
 @d.add_action_callback('mstBKUpdateSelectedEdit'){|_,j|begin;@d.execute_script("mstBKEditUpdated(#{JSON.generate(mst_bk_update_selected_edit(JSON.parse(j)))})");rescue=>e;UI.messagebox("BK revizyonu: #{e.message}");end}
 @d.add_action_callback('hb_rebar_bim'){|_,j|hb_rebar_selected(JSON.parse(j),@d)}
 @d.add_action_callback('rebar_paint_all'){|_|mst_rebar_paint_all_ui(@d)}
 @d.add_action_callback('takeoff'){|_|takeoff}
 @d.add_action_callback('takeoff_excel'){|_|mst_takeoff_excel}   # v0.38 UI8
 @d.add_action_callback('rebar_retag'){|_|begin   # v0.38 RB3
   model=Sketchup.active_model;model.start_operation("MST Donatı Tag'leri",true)
   n=mst_rebar_retag_all!(model);model.commit_operation
   UI.messagebox(n.empty? ? 'Modelde donatı grubu yok.' : "Donatı grupları yapıya göre Tag'lendi (tek Geri Al):\n"+n.sort.map{|k,v|"  #{k}: #{v}"}.join("\n")+"\n\nTags panelinde bir yapının donatısını tek tıkla gizleyip gösterebilirsin.")
  rescue=>e;model.abort_operation rescue nil;UI.messagebox("Donatı Tag'leri: #{e.message}");end}
 @d.add_action_callback('takeoff_detail'){|_,mode|takeoff(mode)}
 @d.add_action_callback('qto_summary'){|_|qto_summary(@d)}
 @d.add_action_callback('workspace_ready'){|_|@d.execute_script("setWorkspaceVersion(#{JSON.generate(VERSION)})")}

 @d.add_action_callback('boq_library'){|_|show_boq_library}
 @d.add_action_callback('boq_mapping'){|_|show_boq_mapping}
 @d.add_action_callback('drilling_edit'){|_,action,json|drilling_edit_action(action,json)}
 @d.add_action_callback('pile_mfg_edit'){|_,action,json|pile_mfg_edit_action(action,json)}
 @d.add_action_callback('boq_refresh'){|_|send_boq(@d)}
 @d.add_action_callback('boq_save_prices'){|_,j|boq_set_prices(j)}
 @d.add_action_callback('rebar_rates_get'){|_,_x|@d.execute_script("setRebarRates(#{JSON.generate({rebar_rates:Hash[REBAR_DEFAULTS.keys.map{|k|[k,rebar_rate(k)]}],fore_rebar_rate:bored_pile_boq_rebar_rate})})") rescue nil}   # v0.38 UI1
 @d.add_action_callback('boq_pile_modes'){|_,j|boq_set_pile_modes(j)}
 @d.add_action_callback('boq_select_sources'){|_,j|boq_select_sources(j,@d)}
 @d.add_action_callback('boq_element_detail'){|_,pid|boq_element_detail(pid,@d)}
 @d.add_action_callback('boq_group_detail'){|_,raw|boq_group_detail(raw,@d)}
 # v0.32.2f: use the same direct PID selection bridge proven by Model Audit.
 @d.add_action_callback('boq_trace_select') do |_,raw|
  ids=raw.to_s.split(',').map(&:to_i).reject{|x|x<=0}.uniq
  model=Sketchup.active_model
  collect=[];collect_elements(model.entities,collect)
  found=collect.select{|x|x.respond_to?(:persistent_id) && ids.include?(x.persistent_id) && x.valid?}.uniq{|x|x.persistent_id}
  unless found.empty?
   model.selection.clear
   found.each{|x|model.selection.add(x)}
   model.active_view.zoom(model.selection)
  end
  @d.execute_script("boqTraceDirectResult(#{model.selection.length},#{ids.length});") if @d
 end
 @d.add_action_callback('select_pile_qto_group'){|_,j|select_pile_qto_group(j)}
 @d.add_action_callback('element_info'){|_|element_info}
 @d.add_action_callback('model_audit'){|_|model_audit}
 @d.add_action_callback('bored_pile'){|_|show_bored_pile}
 @d.add_action_callback('jet_grout'){|_|show_jet_grout}
 @d.add_action_callback('special_solids'){|_|show_special_solids}
 @d.add_action_callback('accessories'){|_|show_accessories}
 @d.add_action_callback('revision_refresh'){|_|revision_send(@d)}
 @d.add_action_callback('revision_snapshot'){|_|revision_create_snapshot(@d)}
 @d.add_action_callback('revision_select'){|_,raw|revision_select(raw,@d)}
 @d.add_action_callback('progress_refresh'){|_|progress_send(@d)}
 @d.add_action_callback('progress_save'){|_,raw|progress_save(raw,@d)}
 @d.add_action_callback('progress_load_period'){|_,n|progress_load_period(n,@d)}
 @d.add_action_callback('progress_delete_period'){|_,n|progress_delete_period(n,@d)}
 @d.add_action_callback('progress_set_status'){|_,status|progress_set_status(status,@d)}
 @d.add_action_callback('element_library'){|_|element_library}
 @d.add_action_callback('project_manager'){|_|project_ano_axis_manager}
 @d.add_action_callback('export_boq_csv'){|_|export_boq_csv}
 @d.add_action_callback('editor_selection'){|_|send_editor_selection(@d);send_dependency_analysis(@d)}
 @d.add_action_callback('dependency_analysis'){|_|send_dependency_analysis(@d)}
 @d.add_action_callback('dependency_stamp'){|_|stamp_dependency_metadata}
 @d.add_action_callback('editor_preview'){|_,j|preview_editor_change(j,@d)}
 @d.add_action_callback('controlled_editor_cancel'){|_|@controlled_editor_pending=nil}
 @d.add_action_callback('controlled_editor_preview'){|_,raw|controlled_editor_preview(raw,@d)}
 @d.add_action_callback('controlled_editor_apply'){|_,raw|controlled_editor_apply(raw,@d)}
 # v0.51.5 K01: update_selected_element tanımlı değil; sessiz NameError yerine açıklayıcı ileti (model değişmez)
 @d.add_action_callback('universal_edit'){|_,j|UI.messagebox('Bu düzenleme yolu bu sürümde desteklenmiyor; seçili eleman için Kontrollü Düzenleme panelini kullanın.')}
 @d.add_action_callback('export_professional_excel'){|_|export_professional_excel}
 @d.add_action_callback('pd_bk_length_info'){|_|pd_bk_length_info}
 @d.add_action_callback('create_flat_precast'){|_,json| cbj=mst_cb_json(json,'Prekast yerleşimi');r=cbj ? create_flat_precast(cbj) : nil;mst_kn_open_pockets(true) if r==true}   # v0.38 KN2
 @d.add_action_callback('load_precast_type_library'){|_| raw=Sketchup.active_model.get_attribute(DICT,'precast_type_library_json','').to_s; @d.execute_script("loadPrecastTypeLibrary(#{raw.inspect})") unless raw.empty? }
 @d.add_action_callback('sync_precast'){|_|sync_precast_to_head_beams}
 @d.add_action_callback('precast_type_rename'){|_|mst_precast_type_rename}
 @d.add_action_callback('pile_rebar_apply'){|_,j|begin;r=mst_pile_rebar_apply(JSON.parse(j));@d.execute_script("mstPileRebarDone(#{JSON.generate(r)})");rescue=>e;UI.messagebox("Kazık donatısı: #{e.message}");end}
 @d.add_action_callback('precast_to_component'){|_|mst_precast_convert(true)}
 @d.add_action_callback('kn_place'){|_|mst_kn_place(nil,false)}
 @d.add_action_callback('kn_pockets'){|_|mst_kn_open_pockets(false)}
 @d.add_action_callback('precast_to_group'){|_|mst_precast_convert(false)}
 @d.add_action_callback('precast_purge_defs'){|_|mst_purge_unused_precast_definitions}
 @d.add_action_callback('universal_formwork_face_tool'){|_|activate_universal_formwork_face_tool}
 @d.add_action_callback('read_channel_bk'){|_|read_channel_bk(@d)}
 @d.add_action_callback('create_channel_precast'){|_,j|(cbj=mst_cb_json(j,'Kanal prekastı')) && create_channel_precast(cbj)}
 @d.add_action_callback('create_crane_precast'){|_,j|(cbj=mst_cb_json(j,'Vinç prekastı')) && create_crane_precast(cbj)}
 @d.add_action_callback('create_deck_slab'){|_,j|(cbj=mst_cb_json(j,'Döşeme')) && create_deck_slab(cbj)}
 @d.add_action_callback('deck_preview'){|_,j|(cbj=mst_cb_json(j,'Döşeme önizleme')) && deck_preview(cbj)}
 @d.add_action_callback('deck_rebar_bim'){|_,j|(cbj=mst_cb_json(j,'Döşeme donatısı')) && deck_rebar_selected(cbj,@d)}
 @d.add_action_callback('deck_refresh'){|_|deck_refresh_selected}
 @d.add_action_callback('create_existing_deck_topping'){|_,j|(cbj=mst_cb_json(j,'Kaplama')) && create_existing_deck_topping(cbj)}
 @d.add_action_callback('register_element'){|_|register_selected_element}
 @d.add_action_callback('edit_registered_element'){|_|edit_registered_element}
 @d.add_action_callback('unregister_element'){|_|unregister_selected_element}
 @d.show
end

require_relative 'dependency_rebuild'
require_relative 'boq_library'
require_relative 'boq_mapping'
require_relative 'pile_drilling'
require_relative 'pile_manufacturing'
require_relative 'bored_pile'
require_relative 'jet_grout'
require_relative 'system_exports'
require_relative 'accessories'
require_relative 'rockfill_alternatives'
require_relative 'rockfill_reference_cubage'
require_relative 'rockfill_head_reference'
require_relative 'rockfill_boq_source'
require_relative 'rockfill_live'
require_relative 'special_solids'

# v0.36.5 — Selected Pile BIM Detail Batch Update
# Selection is the scope. KORU leaves the corresponding attributes untouched.
def batch_update_selected_pile_details
 model=Sketchup.active_model
 piles=selected_piles.map{|entry|entry.is_a?(Array) ? entry[0] : entry}.select{|g|g.valid? && g.get_attribute(DICT,'element_type','')=='steel_pipe_pile'}.uniq
 if piles.empty?
  UI.messagebox('Önce SketchUp modelinde güncellenecek çelik boru kazıkları veya kazık yerleşim grubunu seçin.')
  return
 end
 names=piles.map{|p|p.get_attribute(DICT,'pile_id','?').to_s}
 labels=['Foraj','Foraj boyu / kazık (m)','PE kaplama','PE boyu / kazık (m)','Alt tapa','Tapa adedi / kazık','Alt/İç çember','Alt/İç çember adedi','Üst/Dış çember','Üst/Dış çember adedi']
 defaults=['KORU','8.00','KORU','0.00','KORU','1','KORU','1','KORU','1']
 choices=['KORU|VAR|YOK',nil,'KORU|VAR|YOK',nil,'KORU|VAR|YOK',nil,'KORU|VAR|YOK',nil,'KORU|VAR|YOK',nil]
 values=UI.inputbox(labels,defaults,choices,"Toplu Kazık Detay Güncelle — #{piles.length} kazık")
 return unless values
 changes={}; spec=[['drilling_enabled','drilling_length_m',0,1],['pe_enabled','pe_length_m',2,3],['plug_enabled','plug_count_per_pile',4,5],['lower_ring_enabled','lower_ring_count_per_pile',6,7],['upper_ring_enabled','upper_ring_count_per_pile',8,9]]
 spec.each do |flag,quantity,i,j|
  state=values[i].to_s.upcase
  next if state=='KORU'
  changes[flag]=(state=='VAR' ? '1' : '0')
  if state=='VAR'
   raw=values[j].to_s.strip.tr(',','.')
   unless raw.match?(/\A(?:\d+(?:\.\d*)?|\.\d+)\z/)
    UI.messagebox("Geçersiz değer: #{labels[j]}");return
   end
   number=raw.to_f
   if number<=0 || (quantity.end_with?('count_per_pile') && number!=number.to_i)
    UI.messagebox("Pozitif #{quantity.end_with?('count_per_pile') ? 'tam sayı' : 'uzunluk'} gerekli: #{labels[j]}");return
   end
   changes[quantity]=quantity.end_with?('count_per_pile') ? number.to_i : number
  end
 end
 if changes.empty?
  UI.messagebox('Değişiklik seçilmedi (tüm alanlar KORU).');return
 end
 before=piles.sum{|p|p.get_attribute(DICT,'drilling_enabled','0').to_s=='1' ? p.get_attribute(DICT,'drilling_length_m',0).to_f : 0.0}
 after=piles.sum{|p|changes.fetch('drilling_enabled',p.get_attribute(DICT,'drilling_enabled','0')).to_s=='1' ? changes.fetch('drilling_length_m',p.get_attribute(DICT,'drilling_length_m',0)).to_f : 0.0}
 summary=changes.map{|k,v|"#{k}: #{v}"}.join("\n")
 result=UI.messagebox("#{piles.length} kazık güncellenecek.\n#{names.first(12).join(', ')}#{names.length>12 ? ' ...' : ''}\n\n#{summary}\n\nSeçili kazıklar için foraj: #{format('%.2f',before)} → #{format('%.2f',after)} m\n\nDevam edilsin mi?",MB_YESNO)
 return unless result==IDYES
 model.start_operation('MST Toplu Kazık Detay Güncelle',true)
 begin
  piles.each do |pile|
   mst_apply_pile_detail_changes(pile,changes)
  end
  model.commit_operation
  UI.messagebox("#{piles.length} kazık güncellendi. Tek Geri Al ile geri alınabilir.\nSeçili kazıkların yeni toplam forajı: #{format('%.2f',after)} m")
 rescue => e
  model.abort_operation
  UI.messagebox("Toplu işlem geri alındı: #{e.message}")
 end
end

unless file_loaded?(__FILE__)
 install_dependency_observers
 menu=UI.menu('Extensions').add_submenu('Deniz Yapıları Araçları (MST)')
 # v0.38 UI5: sade menü — her şey ana pencerede; eski öğelerin tamamı alt menüde korunur
 menu.add_item('MST Aç'){show_dialog};menu.add_item('Model Kontrolü'){model_audit};menu.add_item('Model Bakımı'){show_dialog;mst_host_exec("mstShowPage('maint')")}
 menu.add_separator;menu.add_item('Kazık Numaralarını Göster / Güncelle'){mst_labels_ui(true)};menu.add_item('Kazık Numaralarını Kaldır'){mst_labels_ui(false)};menu.add_item('Numarayla Bul…'){mst_find_ui};menu.add_item('PE Kaplama Görünümünü Göster / Güncelle'){mst_pe_ui(true)};menu.add_item('PE Kaplama Görünümünü Kaldır'){mst_pe_ui(false)};menu.add_item('PE Üst Kotunu Ayarla…'){mst_pe_top_ui};menu.add_separator;menu.add_item('Otomatik Donatı (seçili BK)…'){mst_ar_selected_ui};menu.add_item('Çizimden Donatı (seçili BK)…'){mst_dr_selected_ui};menu.add_item('Çizimden / Otomatik Donatıyı Sil'){mst_dr_remove_ui};menu.add_item('Eski Donatıyı Yeni Kurallarla Yeniden Çiz'){mst_rt_upgrade_ui};menu.add_item('Donatı Ayarları…'){mst_rs_ui};menu.add_item('Donatıyı Göster / Gizle'){mst_rt_toggle_ui};menu.add_item('Bükme Listesi + Kesim Planı'){mst_rt_bending_ui};menu.add_item('Donatı Kesiti (seçili BK)…'){mst_rt_section_ui};menu.add_item('Donatı Revizyon Karşılaştırması…'){mst_rt_revision_ui};menu.add_item('Elemanlar Arası Donatı Çakışması'){mst_rt_clash_ui};menu.add_separator;pj=menu.add_submenu('Proje Paftaları');pj.add_item('A-Çerçeve Eğik Kazık Çiftleri…'){mst_af_ui};pj.add_item('Kazık Dispozisyonu — DXF…'){mst_kd_ui};pj.add_item('Kazık Filizini BK\'ya Göre Ayarla'){mst_kf_fit_ui};pj.add_separator;pj.add_item('Vinç / Boylama Kirişi (iki BK arası)…'){mst_vk_ui};pj.add_item('Menfez Sac Kutusu (seçili BK)…'){mst_cv_ui};pj.add_item('BK Taban Bölgesi…'){mst_bz_ui};pj.add_item('Kademeli Döküm…'){mst_hb_stage_ui};pj.add_item('Kademeli Döküm Metrajı'){mst_hb_stage_report_ui};pj.add_separator;pj.add_item('Prekast Donatısı (PD / PK)…'){mst_pc_ui};pj.add_item('Paftadan 3B Donatı (otomatik)…'){mst_dra_ui};pj.add_item('Paftadan Donatı Metrajı (DXF)…'){mst_dxr_ui};pj.add_item('Paftadan Donatı Metrajını Kaldır'){mst_dxr_remove_ui};pj.add_separator;pj.add_item('Kaplama Eğimi…'){mst_tp_ui};pj.add_item('Malzeme Sınıfları…'){mst_ms_ui};menu.add_separator;menu.add_item('İş Programı Oluştur'){mst_sp_ui};menu.add_item('İş Programı Ayarları…'){mst_sp_settings_ui};menu.add_item('İş Programı — 4D Görünüm…'){mst_sp_4d_ui};menu.add_item('İş Programı — 4D Temizle'){mst_sp_4d_clear_ui}
 menu.add_separator
 old_menu=menu.add_submenu('Tüm araçlar (eski menü)')
 old_menu.add_item('Deniz Yapıları Araçları (MST)'){show_dialog};old_menu.add_item("MST Tag'lerini Oluştur / Güncelle"){mst_retag_all(true)};old_menu.add_item('Keşif Kütüphanesi'){show_boq_library};old_menu.add_item('ÖBF – Model Miktarı Eşleştirme'){show_boq_mapping};old_menu.add_item('Proje / Ano / Aks Yöneticisi'){project_ano_axis_manager};old_menu.add_item('Seçili Elemana Elle Aks Ata…'){mst_manual_axis_ui};old_menu.add_item('BIM Veri Çekirdeği / Eleman Kütüphanesi'){bim_data_core_report};old_menu.add_item('Bağımlılık Motoru / Etki Analizi'){stamp_dependency_metadata};old_menu.add_item('Metraj Motoru'){takeoff};old_menu.add_item('Keşif Motoru'){show_boq_engine};old_menu.add_item('Model Kontrolü / Mühendislik Kalite Kontrolü'){model_audit};old_menu.add_item('Döşeme BIM İlişki Onarımı'){repair_deck_bim_relationships};old_menu.add_item('BIM Kimlik Onarımı'){repair_bim_identity};old_menu.add_item('Kazık Tip Kütüphanesi Otomatik Eşitleme'){mst_repair_pile_type_library};old_menu.add_item('Çember Et Kalınlığı — Kurala Çek (Model Geneli)'){mst_ring_rule_normalize_all};old_menu.add_item('Kazık Boru Ağırlıklarını Doğrula / Düzelt'){mst_reconcile_pile_weights!};old_menu.add_item('Kazık Düzeni Eşitleme'){mst_repair_pile_organization};old_menu.add_item('Eleman Kütüphanesi'){element_library};old_menu.add_item('Kazık Yerleşimi - Seçili Kazığı Düzenle'){edit_selected_pile_v2};old_menu.add_item('Toplu Kazık Detay Güncelle'){batch_update_selected_pile_details};old_menu.add_item('Ayrıntılı Metraj (Excel)'){export_professional_excel};old_menu.add_item('Keşif / Metraj CSV Dışa Aktar'){export_boq_csv};old_menu.add_item('Düz Prekast (PD) Yerleşimi'){create_flat_precast}
 # v0.51.2 TB1: gruplu araç çubukları (Genel / Kazık / Donatı / Proje) — Extensions menüsündeki araçların tamamı
 mst_tb_defs=[
  ['Marine Structures',[
   ['tb_open','MST Aç','Deniz Yapıları Araçları (MST) penceresini açar',proc{show_dialog}],
   ['tb_audit','Model Kontrolü','Model kontrolü / mühendislik kalite kontrolü raporu',proc{model_audit}],
   ['tb_maint','Model Bakımı','MST penceresinde Model Bakımı sayfasını açar',proc{show_dialog;mst_host_exec("mstShowPage('maint')")}],
   ['tb_tags',"MST Tag'lerini Güncelle",'Tüm MST elemanlarının Tag\'ini yapı / aile / tip adına göre yeniden atar (tek Geri Al)',proc{mst_retag_all(true)}]]],
  ['MST Kazık',[
   ['tb_labels','Kazık Numaraları','Kazık numaralarını modelde göster / güncelle (metraj değişmez)',proc{mst_labels_ui(true)}],
   ['tb_find','Numarayla Bul','Kazık / eleman numarasıyla bul ve seç',proc{mst_find_ui}],
   ['tb_pe','PE Kaplama Görünümü','PE kaplamalı kazık bölümünü renkli göster / güncelle',proc{mst_pe_ui(true)}],
   ['tb_kd','Kazık Dispozisyonu — DXF','DXF paftasından aks + kazık yerleşimi',proc{mst_kd_ui}],
   ['tb_af','A-Çerçeve Eğik Kazık Çiftleri','A-çerçeve eğik kazık çiftleri',proc{mst_af_ui}],
   ['tb_kf','Kazık Filizini BK\'ya Göre Ayarla','Kazık filizini başlık kirişine göre ayarlar',proc{mst_kf_fit_ui}]]],
  ['MST Donatı',[
   ['tb_ar','Otomatik Donatı (seçili BK)','Seçili başlık kirişine otomatik donatı',proc{mst_ar_selected_ui}],
   ['tb_dr','Çizimden Donatı (seçili BK)','Kayıtlı pafta paketinden donatı',proc{mst_dr_selected_ui}],
   ['tb_dra','Paftadan 3B Donatı (otomatik)','DXF paftasından otomatik 3B donatı',proc{mst_dra_ui}],
   ['tb_vis','Donatıyı Göster / Gizle','Donatı Tag\'lerini göster / gizle',proc{mst_rt_toggle_ui}],
   ['tb_sec','Donatı Kesiti (seçili BK)','Seçili BK için donatı kesiti',proc{mst_rt_section_ui}],
   ['tb_bend','Bükme Listesi + Kesim Planı','Bükme listesi ve kesim planı',proc{mst_rt_bending_ui}],
   ['tb_rs','Donatı Ayarları','Donatı kuralları ve ayarları',proc{mst_rs_ui}],
   ['tb_clash','Donatı Çakışması','Elemanlar arası donatı çakışma kontrolü',proc{mst_rt_clash_ui}],
   ['tb_rev','Donatı Revizyon Karşılaştırması','Donatı revizyonlarını karşılaştırır',proc{mst_rt_revision_ui}],
   ['tb_del','Çizimden / Otomatik Donatıyı Sil','Çizimden / otomatik donatıyı siler',proc{mst_dr_remove_ui}]]],
  ['MST Proje',[
   ['tb_vk','Vinç / Boylama Kirişi','İki BK arası vinç / boylama kirişi',proc{mst_vk_ui}],
   ['tb_cv','Menfez Sac Kutusu','Seçili BK için menfez sac kutusu',proc{mst_cv_ui}],
   ['tb_bz','BK Taban Bölgesi','BK taban bölgesi',proc{mst_bz_ui}],
   ['tb_stage','Kademeli Döküm','Kademeli döküm',proc{mst_hb_stage_ui}],
   ['tb_stage_q','Kademeli Döküm Metrajı','Kademeli döküm metrajı',proc{mst_hb_stage_report_ui}],
   ['tb_pc','Prekast Donatısı (PD / PK)','Prekast donatısı',proc{mst_pc_ui}],
   ['tb_tp','Kaplama Eğimi','Kaplama eğimi',proc{mst_tp_ui}],
   ['tb_dxr','Paftadan Donatı Metrajı (DXF)','Paftadan donatı metrajı (3B çizmez)',proc{mst_dxr_ui}],
   ['tb_ms','Malzeme Sınıfları','Malzeme sınıfları',proc{mst_ms_ui}],
   ['tb_sp','İş Programı Oluştur','İş programı oluştur',proc{mst_sp_ui}],
   ['tb_4d','İş Programı — 4D Görünüm','İş programı 4D görünüm',proc{mst_sp_4d_ui}]]]
 ]
 mst_tb_defs.each do |tname,items|
  tb=UI::Toolbar.new(tname)
  items.each do |ic,tip,st,blk|
   c=UI::Command.new(tip,&blk)
   c.tooltip=tip;c.status_bar_text=st
   c.small_icon=File.join(__dir__,'icons',ic+'_24.png');c.large_icon=File.join(__dir__,'icons',ic+'_32.png')
   tb.add_item(c)
  end
  # v0.51.5 K45: kullanıcının kapattığı araç çubuğu yeniden açılışta geri gelmez (TB_HIDDEN: SketchUp UI::Toolbar sabiti)
  tb.show unless defined?(TB_HIDDEN) && tb.get_last_state==TB_HIDDEN
 end
 file_loaded(__FILE__)
end

# ===== v0.34.7 Multi-ANO Layout Engine =====
def mst_ano_layouts(model=Sketchup.active_model)
  raw=model.get_attribute(DICT,'ano_layout_json','').to_s
  rows=[]
  begin
    rows=JSON.parse(raw) unless raw.empty?
  rescue
    rows=[]
  end
  unless rows.is_a?(Array) && !rows.empty?
    rows=[{'name'=>'ANO-01','length_m'=>0.0,'gap_before_m'=>0.0,'origin_x_m'=>0.0}]
  end
  rows
end

def mst_save_ano_layouts(rows,model=Sketchup.active_model)
  model.set_attribute(DICT,'ano_layout_json',JSON.generate(rows))
end

def mst_recalculate_ano_origins(rows)
  x=0.0
  rows.each_with_index do |r,i|
    r['name']=(r['name'].to_s.strip.empty? ? "ANO-#{(i+1).to_s.rjust(2,'0')}" : r['name'].to_s.strip)
    r['length_m']=r['length_m'].to_f
    r['gap_before_m']=(i==0 ? 0.0 : r['gap_before_m'].to_f)
    x += r['gap_before_m'] if i>0
    r['origin_x_m']=x
    x += r['length_m']
  end
  rows
end

def mst_active_ano_context(model=Sketchup.active_model)
  rows=mst_recalculate_ano_origins(mst_ano_layouts(model))
  active=model.get_attribute(DICT,'active_ano','ANO-01').to_s
  row=rows.find{|r|r['name'].to_s==active} || rows.first
  model.set_attribute(DICT,'active_ano',row['name']) unless model.get_attribute(DICT,'active_ano',nil)==row['name']   # v0.51.5 H3e/U6: yalnız değer farklıysa
  row
end

def mst_add_ano(data)
  model=Sketchup.active_model
  rows=mst_ano_layouts(model)
  name=data['name'].to_s.strip
  name="ANO-#{(rows.length+1).to_s.rjust(2,'0')}" if name.empty?
  raise 'Bu Ano adı zaten mevcut.' if rows.any?{|r|r['name'].to_s.casecmp(name).zero?}
  length=data['length_m'].to_f; gap=data['gap_before_m'].to_f
  raise 'Ano uzunluğu 0 m’den büyük olmalıdır.' unless length>0
  raise 'Ano boşluğu negatif olamaz.' if gap<0
  rows << {'name'=>name,'length_m'=>length,'gap_before_m'=>gap,'origin_x_m'=>0.0}
  rows=mst_recalculate_ano_origins(rows);mst_save_ano_layouts(rows,model)
  model.set_attribute(DICT,'active_ano',name)
  rows.last
end

def mst_update_ano(data)
  model=Sketchup.active_model;rows=mst_ano_layouts(model)
  name=data['name'].to_s; r=rows.find{|x|x['name'].to_s==name};raise 'Ano bulunamadı.' unless r
  length=data['length_m'].to_f;gap=data['gap_before_m'].to_f
  raise 'Ano uzunluğu negatif olamaz.' if length<0
  raise 'Ano boşluğu negatif olamaz.' if gap<0
  r['length_m']=length;r['gap_before_m']=gap
  rows=mst_recalculate_ano_origins(rows);mst_save_ano_layouts(rows,model);r
end

def mst_set_active_ano(name)
  model=Sketchup.active_model;rows=mst_recalculate_ano_origins(mst_ano_layouts(model))
  r=rows.find{|x|x['name'].to_s==name.to_s};raise 'Ano bulunamadı.' unless r
  model.set_attribute(DICT,'active_ano',r['name']);r
end

def mst_delete_ano(name)
  model=Sketchup.active_model;rows=mst_ano_layouts(model)
  raise 'ANO-01 silinemez.' if rows.first && rows.first['name'].to_s==name.to_s
  used=mst_all_elements.any?{|e|e.respond_to?(:get_attribute)&&e.get_attribute(DICT,'ano','').to_s==name.to_s}
  raise 'Bu Ano’ya bağlı BIM elemanları var. Önce elemanları başka Ano’ya taşıyın veya silin.' if used
  rows.reject!{|r|r['name'].to_s==name.to_s};rows=mst_recalculate_ano_origins(rows);mst_save_ano_layouts(rows,model)
  model.set_attribute(DICT,'active_ano',rows.first['name']) if model.get_attribute(DICT,'active_ano','').to_s==name.to_s
  true
end

# ===== v0.34.28 Structure / Zone scoped grids =====
def mst_structure_zones(model=Sketchup.active_model)
  raw=model.get_attribute(DICT,'structure_zones_json','').to_s
  h=raw.empty? ? {} : (JSON.parse(raw) rescue {})
  h.is_a?(Hash) ? h : {}
end

def mst_structure_zones_for(ano,model=Sketchup.active_model)
  h=mst_structure_zones(model); a=h[ano.to_s]
  a=(a.is_a?(Array) ? a.map{|x|x.to_s.strip}.reject(&:empty?) : [])
  a=['ANA YAPI'] if a.empty?
  a.uniq
end

def mst_active_structure_zone(ano,model=Sketchup.active_model)
  key="active_structure_zone__#{ano}"
  cur=model.get_attribute(DICT,key,'').to_s.strip
  rows=mst_structure_zones_for(ano,model)
  cur=rows.first if cur.empty? || !rows.include?(cur)
  model.set_attribute(DICT,key,cur) unless model.get_attribute(DICT,key,nil)==cur   # v0.51.5 H3e/U6: yalnız değer farklıysa
  cur
end

def mst_add_structure_zone(ano,name,model=Sketchup.active_model)
  name=name.to_s.strip;raise 'Yapı / Bölge adı boş olamaz.' if name.empty?
  mst_json_attr_guard!(model,'structure_zones_json',Hash,'Yapı / bölge listesi')
  h=mst_structure_zones(model);a=mst_structure_zones_for(ano,model)
  raise "#{name} zaten mevcut." if a.any?{|x|x.casecmp(name)==0}
  a << name;h[ano.to_s]=a;model.set_attribute(DICT,'structure_zones_json',JSON.generate(h))
  model.set_attribute(DICT,"active_structure_zone__#{ano}",name);name
end

def mst_set_active_structure_zone(ano,name,model=Sketchup.active_model)
  rows=mst_structure_zones_for(ano,model);raise 'Yapı / Bölge bulunamadı.' unless rows.include?(name.to_s)
  model.set_attribute(DICT,"active_structure_zone__#{ano}",name.to_s);name.to_s
end


def mst_copy_structure_zone(ano,source,name,model=Sketchup.active_model)
  source=source.to_s.strip; name=name.to_s.strip
  raise 'Kaynak Yapı / Bölge seçilmedi.' if source.empty?
  raise 'Yeni Yapı / Bölge adı boş olamaz.' if name.empty?
  mst_json_attr_guard!(model,'axis_grids_json',Hash,'Aks ağı')
  mst_add_structure_zone(ano,name,model)
  h=mst_axis_grids(model)
  src=h[mst_axis_grid_key(ano,source)]
  src=mst_axis_grid_for(ano,model,source) unless src.is_a?(Hash)
  h[mst_axis_grid_key(ano,name)]=JSON.parse(JSON.generate(src))
  model.set_attribute(DICT,'axis_grids_json',JSON.generate(h))
  model.set_attribute(DICT,"active_structure_zone__#{ano}",name)
  name
end

def mst_delete_structure_zone(ano,name,model=Sketchup.active_model)
  name=name.to_s.strip
  raise 'Yapı / Bölge seçilmedi.' if name.empty?
  mst_json_attr_guard!(model,'structure_zones_json',Hash,'Yapı / bölge listesi');mst_json_attr_guard!(model,'axis_grids_json',Hash,'Aks ağı')
  rows=mst_structure_zones_for(ano,model)
  raise 'ANA YAPI silinemez.' if name=='ANA YAPI'
  used=mst_all_elements.any?{|e| e.respond_to?(:get_attribute) && e.get_attribute(DICT,'ano','').to_s==ano.to_s && e.get_attribute(DICT,'structure_zone','').to_s==name}
  raise "#{name} yapısına bağlı BIM elemanları var. Önce bu elemanları taşıyın veya silin." if used
  h=mst_structure_zones(model); arr=(h[ano.to_s].is_a?(Array) ? h[ano.to_s].map(&:to_s) : rows)
  arr.reject!{|z|z==name}; arr=['ANA YAPI'] if arr.empty?; h[ano.to_s]=arr
  model.set_attribute(DICT,'structure_zones_json',JSON.generate(h))
  grids=mst_axis_grids(model);grids.delete(mst_axis_grid_key(ano,name));model.set_attribute(DICT,'axis_grids_json',JSON.generate(grids))
  model.entities.grep(Sketchup::Group).select{|g|g.valid? && g.get_attribute(DICT,'element_type','').to_s=='axis_grid_visual' && g.get_attribute(DICT,'ano','').to_s==ano.to_s && g.get_attribute(DICT,'zone','ANA YAPI').to_s==name}.each(&:erase!)
  active=arr.first;model.set_attribute(DICT,"active_structure_zone__#{ano}",active);active
end

def mst_axis_grid_key(ano,zone)
  "#{ano}::#{zone}"
end
# ===== end v0.34.20 =====

# ===== v0.34.11 Central Grid / Axis Manager =====
def mst_axis_grids(model=Sketchup.active_model)
  raw=model.get_attribute(DICT,'axis_grids_json','').to_s
  h=raw.empty? ? {} : (JSON.parse(raw) rescue {})
  h.is_a?(Hash) ? h : {}
end

def mst_default_axis_grid
  {'x'=>[{'name'=>'X-01','gap_m'=>0.0,'coord_m'=>0.0,'line_type'=>'AXIS','pattern'=>'DASHED','lineweight'=>'0.02','extent'=>'FINITE'}], 'y'=>[{'name'=>'A','gap_m'=>0.0,'coord_m'=>0.0,'line_type'=>'AXIS','pattern'=>'DASHED','lineweight'=>'0.02','extent'=>'FINITE'}], 'system_axis_x'=>'', 'system_axis_y'=>'', 'x_dir'=>'+X', 'y_dir'=>'+Y'}
end

def mst_normalize_axis_rows(rows,dir)
  arr=rows.is_a?(Array) ? rows : []
  raise "#{dir} aks sisteminde en az bir aks bulunmalıdır." if arr.empty?
  seen={}; total=0.0
  arr.each_with_index.map do |r,i|
    name=r['name'].to_s.strip
    raise "#{dir} aksı #{i+1}: aks adı boş olamaz." if name.empty?
    key=name.upcase
    raise "#{dir} aksı: '#{name}' adı birden fazla kullanılamaz." if seen[key]
    seen[key]=true
    gap=i==0 ? 0.0 : r['gap_m'].to_f
    raise "#{dir} aksı #{name}: önceki akstan mesafe negatif olamaz." if gap<0
    total+=gap
    {'name'=>name,'gap_m'=>gap,'coord_m'=>total.round(6),'line_type'=>(r['line_type'].to_s=='SYSTEM' ? 'SYSTEM' : 'AXIS'),'pattern'=>(%w[CONTINUOUS SOLID DASHED CENTER DASHDOT SHORTDASH].include?(r['pattern'].to_s.upcase) ? (r['pattern'].to_s.upcase=='SOLID' ? 'CONTINUOUS' : r['pattern'].to_s.upcase) : 'DASHED'),'lineweight'=>(begin; lw=r['lineweight'].to_s; lw=(r['weight'].to_s=='THICK' ? '0.20' : '0.10') if lw.empty?; %w[0.005 0.01 0.02 0.03 0.05 0.07 0.10 0.13 0.15 0.18 0.20 0.25 0.30 0.35 0.50].include?(lw) ? lw : '0.005'; end),'extent'=>(r['extent'].to_s=='INFINITE' ? 'INFINITE' : 'FINITE')}
  end
end

def mst_axis_grid_for(ano,model=Sketchup.active_model,zone=nil)
  zone=(zone.to_s.strip.empty? ? mst_active_structure_zone(ano,model) : zone.to_s)
  h=mst_axis_grids(model); g=h[mst_axis_grid_key(ano,zone)]
  g=h[ano.to_s] if !g.is_a?(Hash) && zone=='ANA YAPI' # legacy grid
  return mst_default_axis_grid unless g.is_a?(Hash)
  xx=mst_normalize_axis_rows(g['x'],'X'); yy=mst_normalize_axis_rows(g['y'],'Y')
  # v0.34.48: per-axis manual visual type. Legacy system-axis selections are migrated.
  legacy_x=g['system_axis_x'].to_s.strip; legacy_y=g['system_axis_y'].to_s.strip
  xx.each{|r| r['line_type']='SYSTEM' if !legacy_x.empty? && r['name'].to_s==legacy_x && !g['x'].any?{|q| q.is_a?(Hash) && q.key?('line_type')}}
  yy.each{|r| r['line_type']='SYSTEM' if !legacy_y.empty? && r['name'].to_s==legacy_y && !g['y'].any?{|q| q.is_a?(Hash) && q.key?('line_type')}}
  {'x'=>xx,'y'=>yy,'system_axis_x'=>'','system_axis_y'=>'','x_dir'=>(g['x_dir'].to_s=='-X' ? '-X' : '+X'),'y_dir'=>(g['y_dir'].to_s=='-Y' ? '-Y' : '+Y')}
rescue
  mst_default_axis_grid
end

def mst_save_axis_grid(data,model=Sketchup.active_model)
  ano=data['ano'].to_s.strip
  mst_json_attr_guard!(model,'axis_grids_json',Hash,'Aks ağı')
  zone=data['zone'].to_s.strip; zone=mst_active_structure_zone(ano,model) if zone.empty?
  raise 'ANO seçimi boş olamaz.' if ano.empty?
  valid=mst_ano_layouts(model).any?{|r|r['name'].to_s==ano}
  unless valid
    valid=['DOLFEN','ISKELE','RIHTIM'].any?{|sys| mst_structures_for_system(sys,model).any?{|n| n.to_s==ano }} rescue false
  end
  raise "#{ano} bulunamadı." unless valid
  grid={'x'=>mst_normalize_axis_rows(data['x'],'X'),'y'=>mst_normalize_axis_rows(data['y'],'Y'),'system_axis_x'=>'','system_axis_y'=>'','x_dir'=>(data['x_dir'].to_s=='-X' ? '-X' : '+X'),'y_dir'=>(data['y_dir'].to_s=='-Y' ? '-Y' : '+Y')}
  h=mst_axis_grids(model);h[mst_axis_grid_key(ano,zone)]=grid
  model.set_attribute(DICT,'axis_grids_json',JSON.generate(h))
  model.set_attribute(DICT,'axis_grid_revision','v0.34.55')
  grid
end

# ===== v0.34.11d Grid Model Visualization + Pile Bridge =====
def mst_grid_tag(model=Sketchup.active_model)
  tag=model.layers['MST | GRID'] rescue nil
  tag ||= model.layers.add('MST | GRID')
  tag
end

def mst_delete_grid_visual(ano,model=Sketchup.active_model,zone=nil)
  zone=(zone.to_s.strip.empty? ? mst_active_structure_zone(ano,model) : zone.to_s)
  model.entities.grep(Sketchup::Group).select{|g| g.valid? && g.get_attribute(DICT,'element_type','').to_s=='axis_grid_visual' && g.get_attribute(DICT,'ano','').to_s==ano.to_s && g.get_attribute(DICT,'zone','ANA YAPI').to_s==zone}.each(&:erase!)
end

def mst_add_dashed_axis(entities,p1,p2,dash_m=0.55,gap_m=0.28)
  v=p2-p1; len=v.length
  return if len<=0
  dir=v.clone; dir.length=1.0
  dash=m(dash_m); gap=m(gap_m); pos=0.0
  while pos < len
    a=p1.offset(dir,pos); b=p1.offset(dir,[pos+dash,len].min)
    entities.add_line(a,b) if a.distance(b)>0.001
    pos += dash+gap
  end
end


def mst_add_dashed_axis_band(entities,p1,p2,width_m=0.30,dash_m=2.20,gap_m=0.75,model=Sketchup.active_model)
  # v0.34.46: persistent system-axis ribbon made from REAL SketchUp Edges.
  # ConstructionLines have no per-entity line-width. A filled face can also
  # disappear/flatten depending on the active face style. Therefore the datum
  # is rendered as several closely spaced dashed Edges. This remains visible
  # in Wireframe/Hidden Line/Monochrome/Shaded styles.
  v=p2-p1; len=v.length
  return if len<=0
  dir=v.clone; dir.length=1.0
  perp=Geom::Vector3d.new(-dir.y,dir.x,0)
  perp.length=1.0
  dash=m(dash_m); gap=m(gap_m)
  half=width_m.to_f*0.5
  offsets=[-half,-half*0.50,0.0,half*0.50,half]
  offsets.each do |off_m|
    off=perp.clone; off.length=m(off_m.abs)
    off.reverse! if off_m < 0
    a0=p1.offset(off); b0=p2.offset(off)
    vv=b0-a0; ll=vv.length; dd=vv.clone; dd.length=1.0
    pos=0.0
    while pos < ll
      a=a0.offset(dd,pos); b=a0.offset(dd,[pos+dash,ll].min)
      if a.distance(b)>0.001
        edge=entities.add_line(a,b)
        edge.set_attribute(DICT,'element_type','system_axis_emphasis') if edge
      end
      pos += dash+gap
    end
  end
end

def mst_add_solid_axis_band(entities,p1,p2,width_m=0.10)
  v=p2-p1; len=v.length
  return if len<=0
  dir=v.clone; dir.length=1.0
  perp=Geom::Vector3d.new(-dir.y,dir.x,0); perp.length=1.0
  half=width_m.to_f*0.5
  [-half,-half*0.5,0.0,half*0.5,half].each do |off_m|
    off=perp.clone; off.length=m(off_m.abs); off.reverse! if off_m<0
    edge=entities.add_line(p1.offset(off),p2.offset(off))
    edge.set_attribute(DICT,'element_type','axis_emphasis') if edge
  end
end

def mst_add_pattern_axis(entities,p1,p2,pattern='DASHED')
  v=p2-p1; len=v.length
  return if len<=0
  dir=v.clone; dir.length=1.0
  pat=pattern.to_s.upcase
  if pat=='CONTINUOUS'
    entities.add_line(p1,p2); return
  end
  # metres: professional CAD-like visual patterns
  seq = case pat
        when 'CENTER'  then [[1.20,true],[0.28,false],[0.18,true],[0.28,false]]
        when 'DASHDOT' then [[0.80,true],[0.22,false],[0.08,true],[0.22,false]]
        when 'SHORTDASH' then [[0.12,true],[0.12,false]]
        else                 [[0.48,true],[0.30,false]]
        end
  pos=0.0; idx=0
  while pos < len
    seg=m(seq[idx % seq.length][0]); draw=seq[idx % seq.length][1]
    nxt=[pos+seg,len].min
    if draw
      a=p1.offset(dir,pos); b=p1.offset(dir,nxt)
      entities.add_line(a,b) if a.distance(b)>0.001
    end
    pos=nxt; idx+=1
  end
end

def mst_draw_manual_axis(entities,p1,p2,row,infinite_p=nil,infinite_v=nil)
  pattern=row['pattern'].to_s.upcase
  pattern='CONTINUOUS' if pattern=='SOLID'
  pattern='DASHED' unless %w[CONTINUOUS DASHED CENTER DASHDOT SHORTDASH].include?(pattern)
  lw=row['lineweight'].to_s
  lw=(row['weight'].to_s=='THICK' ? '0.20' : '0.10') if lw.empty?
  extent=row['extent'].to_s=='INFINITE' ? 'INFINITE' : 'FINITE'
  if extent=='INFINITE' && infinite_p && infinite_v
    cl=entities.add_cline(infinite_p,infinite_v)
    cl.set_attribute(DICT,'element_type','infinite_axis_reference') if cl
  end
  # v0.34.54 Lineweight renderer.
  # SketchUp persistent Edges have a one-pixel-ish minimum and no AutoCAD per-edge mm width.
  # Therefore 0.02 mm is the true MST minimum (one Edge). Larger values progressively
  # add symmetric parallel Edges so every useful step changes the rendered geometry.
  # This fixes v0.34.54 where 0.02..0.10 were all mapped to exactly the same geometry.
  weight_steps={
    # 0.005 / 0.010 / 0.020 are intentionally single-edge minimum tiers.
    # SketchUp has no sub-pixel persistent Edge width; keeping them as named CAD/BIM
    # weights preserves project data while avoiding fake geometry that enlarges bounds.
    '0.005'=>[1,0.000], '0.01'=>[1,0.000], '0.02'=>[1,0.000],
    '0.03'=>[2,0.004], '0.05'=>[3,0.006],
    '0.07'=>[3,0.010], '0.10'=>[3,0.014], '0.13'=>[3,0.018],
    '0.15'=>[3,0.022], '0.18'=>[5,0.026], '0.20'=>[5,0.030],
    '0.25'=>[5,0.038], '0.30'=>[5,0.046], '0.35'=>[5,0.056],
    '0.50'=>[7,0.072]
  }
  count,width=weight_steps[lw] || weight_steps['0.005']
  if count<=1 || width<=0.0
    mst_add_pattern_axis(entities,p1,p2,pattern)
  else
    v=p2-p1; dir=v.clone; dir.length=1.0
    perp=Geom::Vector3d.new(-dir.y,dir.x,0); perp.length=1.0
    offsets = if count==2
      [-0.5,0.5]
    else
      (0...count).map{|i| -0.5 + i.to_f/(count-1)}
    end
    offsets.each do |f|
      off=perp.clone; off.length=m((width*f).abs); off.reverse! if f<0
      mst_add_pattern_axis(entities,p1.offset(off),p2.offset(off),pattern)
    end
  end
end

def mst_system_grid_span(system,model=Sketchup.active_model)
  xmin=nil; xmax=nil
  mst_structures_for_system(system,model).each do |name|
    begin
      gg=mst_axis_grid_for(name,model,name); oo=mst_structure_origin(system,name,model)
      vals=(gg['x']||[]).map{|r|oo[0].to_f+r['coord_m'].to_f}
      next if vals.empty?
      xmin=xmin.nil? ? vals.min : [xmin,vals.min].min
      xmax=xmax.nil? ? vals.max : [xmax,vals.max].max
    rescue
    end
  end
  [xmin,xmax]
end

def mst_system_axis_label_owner(system,axis_name,model=Sketchup.active_model)
  mst_structures_for_system(system,model).find do |name|
    begin
      mst_axis_grid_for(name,model,name)['system_axis_y'].to_s.strip==axis_name.to_s.strip
    rescue
      false
    end
  end
end


# v0.34.51 — model-scaled labels + automatic axis spacing annotations.
def mst_add_model_text(entities,text,point,height_m=0.42,center=false,rotation_deg=0.0)
  grp=entities.add_group
  grp.name='MST Model Text'
  ok=grp.entities.add_3d_text(text.to_s, center ? TextAlignCenter : TextAlignLeft, 'Arial', false, false, m(height_m), 0.0, 0.0, false, 0.0)
  unless ok
    grp.erase! rescue nil
    return nil
  end
  bb=grp.bounds
  dx=center ? -bb.width/2.0 : 0.0
  dy=-bb.height/2.0
  grp.transform!(Geom::Transformation.translation(Geom::Vector3d.new(point.x+dx,point.y+dy,point.z)))
  if rotation_deg.to_f.abs>0.001
    grp.transform!(Geom::Transformation.rotation(point,Z_AXIS,rotation_deg.to_f.degrees))
  end
  grp.set_attribute(DICT,'element_type','model_scaled_text')
  grp
end

def mst_add_axis_dimension_chain(entities,vals,names,family,margin)
  return if vals.length<2
  z=m(0.035)
  if family=='X'
    y=yield
    vals.each{|x| entities.add_line(Geom::Point3d.new(m(x),m(y-0.22),z),Geom::Point3d.new(m(x),m(y+0.22),z))}
    (0...(vals.length-1)).each do |i|
      a,b=vals[i],vals[i+1]; entities.add_line(Geom::Point3d.new(m(a),m(y),z),Geom::Point3d.new(m(b),m(y),z))
      mst_add_model_text(entities,format('%.2f m',(b-a).abs),Geom::Point3d.new(m((a+b)/2.0),m(y+0.38),z),0.34,true)
    end
  else
    x=yield
    vals.each{|y| entities.add_line(Geom::Point3d.new(m(x-0.22),m(y),z),Geom::Point3d.new(m(x+0.22),m(y),z))}
    (0...(vals.length-1)).each do |i|
      a,b=vals[i],vals[i+1]; entities.add_line(Geom::Point3d.new(m(x),m(a),z),Geom::Point3d.new(m(x),m(b),z))
      mst_add_model_text(entities,format('%.2f m',(b-a).abs),Geom::Point3d.new(m(x-0.40),m((a+b)/2.0),z),0.34,true,90.0)
    end
  end
end

# v0.38 BK2.3: own_op=false lets the axis-manager save redraw the grid inside its single operation.
def mst_show_grid_visual(ano=nil,model=Sketchup.active_model,zone=nil,own_op=true,sys=nil)
  ctx=mst_active_ano_context(model); ano=(ano.to_s.strip.empty? ? ctx['name'].to_s : ano.to_s)
  zone=(zone.to_s.strip.empty? ? mst_active_structure_zone(ano,model) : zone.to_s)
  grid=mst_axis_grid_for(ano,model,zone); xs=grid['x']; ys=grid['y']
  raise 'Aks sistemi boş.' if xs.empty? || ys.empty?
  sys=(sys.to_s.strip.empty? ? model.get_attribute(DICT,'project_system_type','ISKELE').to_s.upcase : sys.to_s.upcase)
  begin; org=mst_structure_origin(sys,ano,model); ox=org[0].to_f; oy=org[1].to_f; rescue; ox=0.0; oy=0.0; end
  xsgn=(grid['x_dir'].to_s=='-X' ? -1.0 : 1.0); ysgn=(grid['y_dir'].to_s=='-Y' ? -1.0 : 1.0)
  xvals=xs.map{|r|ox+xsgn*r['coord_m'].to_f}; yvals=ys.map{|r|oy+ysgn*r['coord_m'].to_f}
  margin=1.50; system_axis_x=''; system_axis_y='' # v0.34.48 legacy selectors retired
  amap=mst_axis_display_names(model)   # ADR-0515-I: metinde görünen ad; axis_name / x_axis / y_axis kod kalır
  model.start_operation('MST Grid Görseli',true) if own_op
  mst_delete_grid_visual(ano,model,zone)
  g=model.entities.add_group;g.name="MST GRID — #{ano} — #{zone}";g.layer=mst_grid_tag(model)
  {'element_type'=>'axis_grid_visual','ano'=>ano,'zone'=>zone,'project'=>model.get_attribute(DICT,'project_name',''),'x_axis_count'=>xs.length,'y_axis_count'=>ys.length,'system_axis_x'=>xs.select{|r|r['line_type'].to_s=='SYSTEM'}.map{|r|r['name']}.join(','),'system_axis_y'=>ys.select{|r|r['line_type'].to_s=='SYSTEM'}.map{|r|r['name']}.join(',')}.each{|k,v|g.set_attribute(DICT,k,v)}
  e=g.entities

  # v0.34.55: bounded renderer; Infinite uses ConstructionLine without +/-500 m physical Edges.
  xs.each_with_index do |r,i|
    x=xvals[i]
    infinite=(r['extent'].to_s=='INFINITE')
    y0=yvals.min-margin
    y1=yvals.max+margin
    p1=Geom::Point3d.new(m(x),m(y0),m(0.020)); p2=Geom::Point3d.new(m(x),m(y1),m(0.020))
    mst_draw_manual_axis(e,p1,p2,r,Geom::Point3d.new(m(x),m(yvals.min),0),Geom::Vector3d.new(0,1,0))
    stagger=(i%2)*0.55
    t=mst_add_model_text(e,mst_axis_display(ano,zone,'x',r['name'],amap),Geom::Point3d.new(m(x),m(yvals.max+margin+0.72+stagger),m(0.03)),0.40,true)
    t.set_attribute(DICT,'axis_name',r['name'].to_s) if t
  end

  ys.each_with_index do |r,j|
    y=yvals[j]
    infinite=(r['extent'].to_s=='INFINITE')
    x0=xvals.min-margin
    x1=xvals.max+margin
    p1=Geom::Point3d.new(m(x0),m(y),m(0.020)); p2=Geom::Point3d.new(m(x1),m(y),m(0.020))
    mst_draw_manual_axis(e,p1,p2,r,Geom::Point3d.new(m(xvals.min),m(y),0),Geom::Vector3d.new(1,0,0))
    t=mst_add_model_text(e,mst_axis_display(ano,zone,'y',r['name'],amap),Geom::Point3d.new(m(xvals.min-margin-0.55),m(y),m(0.03)),0.40,true)
    t.set_attribute(DICT,'axis_name',r['name'].to_s) if t
  end

  xs.each_with_index do |xr,i|
    ys.each_with_index do |yr,j|
      cp=e.add_cpoint(Geom::Point3d.new(m(xvals[i]),m(yvals[j]),0))
      {'element_type'=>'axis_intersection','ano'=>ano,'x_axis'=>xr['name'].to_s,'y_axis'=>yr['name'].to_s,'x_m'=>xvals[i],'y_m'=>yvals[j]}.each{|k,v|cp.set_attribute(DICT,k,v)}
    end
  end

  # Structure title: two separately centred text objects below the structure.
  code=ano.to_s.strip
  kind=case code.upcase
  when /^BD/ then 'BAĞLAMA DOLFENİ'
  when /^YD/ then 'YANAŞMA DOLFENİ'
  when /^YP/ then 'YÜKLEME PLATFORMU'
  when /^KY/ then 'KEDİYOLU'
  else ''
  end
  cx=(xvals.min+xvals.max)/2.0; base_y=yvals.min-margin-1.55
  code_text="(#{code})"
  disp=mst_structure_display(code,nil,model)   # ADR-0515-I: görünen ad varsa üstte ad, altta (kod); tür satırı yazılmaz
  if disp!=code
    code_text=disp;kind="(#{code})"
  end
  code_x=cx-[code_text.length*0.105,0.45].max
  st=mst_add_model_text(e,code_text,Geom::Point3d.new(m(cx),m(base_y),m(0.03)),0.42,true); st.set_attribute(DICT,'element_type','structure_label') if st
  unless kind.empty?
    st2=mst_add_model_text(e,kind,Geom::Point3d.new(m(cx),m(base_y-0.62),m(0.03)),0.38,true); st2.set_attribute(DICT,'element_type','structure_label') if st2
  end

  # Automatic spacing dimensions use the same saved grid coordinates.
  mst_add_axis_dimension_chain(e,xvals,xs.map{|r|r['name']},'X',margin){ yvals.max+margin+1.55 }
  mst_add_axis_dimension_chain(e,yvals,ys.map{|r|r['name']},'Y',margin){ xvals.min-margin-1.55 }

  model.commit_operation if own_op
  model.active_view.invalidate
  g
rescue=>ex
  (model.abort_operation rescue nil) if own_op;raise ex
end

# v0.38 BK2.3 — after an axis-manager save, redraw the grid visuals that already exist
# in the model and whose grid (or structure origin) changed. Runs inside the caller's operation.
def mst_grid_visual_signature(sys,name,model)
  g=mst_axis_grid_for(name,model,name)
  o=(mst_structure_origin(sys,name,model) rescue [0.0,0.0])
  JSON.generate([g,o.map{|v|v.to_f.round(6)},mst_structure_display(name,nil,model),mst_axis_display_names(model)[mst_axis_grid_key(name,name)]])   # ADR-0515-I: ad değişince görsel yenilenir
rescue
  ''
end

def mst_grid_visual_snapshot(x,model)
  out={}
  (x['grids']||{}).each_key do |k|
    next unless k.to_s.include?('::')
    sys,name=k.to_s.split('::',2)
    out[k.to_s]=[sys,name,mst_grid_visual_signature(sys,name,model)]
  end
  out
end

def mst_refresh_changed_grid_visuals(before,model)
  vis=model.entities.grep(Sketchup::Group).select{|g|g.valid? && g.get_attribute(DICT,'element_type','').to_s=='axis_grid_visual'}
  done=[]
  before.each_value do |sys,name,sig|
    next unless vis.any?{|g|g.valid? && g.get_attribute(DICT,'ano','').to_s==name && g.get_attribute(DICT,'zone','ANA YAPI').to_s==name}
    next if mst_grid_visual_signature(sys,name,model)==sig
    mst_show_grid_visual(name,model,name,false,sys)
    done << name
  end
  done
end

def mst_grid_to_pile_axes(ano=nil,model=Sketchup.active_model,zone=nil)
  ctx=mst_active_ano_context(model);ano=(ano.to_s.strip.empty? ? ctx['name'].to_s : ano.to_s)
  zone=(zone.to_s.strip.empty? ? mst_active_structure_zone(ano,model) : zone.to_s)
  grid=mst_axis_grid_for(ano,model,zone); ys=grid['y']; gaps=ys.each_with_index.map{|r,i|i==0 ? nil : r['gap_m'].to_f}.compact
  grid['x'].map{|r|{'name'=>r['name'].to_s,'x'=>r['coord_m'].to_f*(grid['x_dir'].to_s=='-X' ? -1.0 : 1.0),'gaps'=>gaps.dup,'points'=>ys.map{|yr|{'name'=>yr['name'].to_s,'y'=>yr['coord_m'].to_f*(grid['y_dir'].to_s=='-Y' ? -1.0 : 1.0),'selected'=>true,'dx'=>0.0,'dy'=>0.0}}}}
end
# ===== end v0.34.11d =====

# ===== v0.34.28 Project / System / Structure Placement Engine =====
def mst_system_structures(model=Sketchup.active_model)
  raw=model.get_attribute(DICT,'system_structures_json','').to_s
  h=raw.empty? ? {} : (JSON.parse(raw) rescue {})
  h={} unless h.is_a?(Hash)
  # v0.34.38: System/Structure manager is fully isolated from legacy ANO storage.
  # Do not import ano_layout_json here; each system owns its own structure list.
  h
end

def mst_default_structure_name(system,index=1)
  system=system.to_s.upcase
  return "RIHTIM-#{index.to_i.to_s.rjust(2,'0')}" if system=='RIHTIM'
  return "BD-#{index.to_i.to_s.rjust(2,'0')}" if system=='DOLFEN'
  "ANO-#{index.to_i.to_s.rjust(2,'0')}"
end

# ===== ADR-0515-I — yapı / aks görünen adı (kimlik = teknik kod; eleman öznitelikleri değişmez) =====
# Model DICT, yalnız eklenen iki anahtar: structure_display_names_json {kod: ad} (sistemsiz) ve
# axis_display_names_json {"<ano>::<zone>": {"x":{kod:ad},"y":{kod:ad}}}. Boş ya da koda eşit ad kaydedilmez.
# Eski model: anahtar yok / bozuk → boş harita, okumada yazım yok. Eski sürüm bu anahtarları yok sayar.
MST_NAME_MAX_STRUCTURE=40
MST_NAME_MAX_AXIS=20
MST_NAME_CHAR=/[\p{L}\p{M}\p{N} \-_.()#+&]/
MST_CODE_CHAR=/[\p{L}\p{M}\p{N} \-_.]/   # yeni / değişen yapı ve aks kodu (03.11.2026 kullanıcı kararı)
MST_TURKIC_UPCASE=(('i'.upcase(:turkic)=="İ") rescue false)   # SketchUp 2020 Ruby 2.5.5: var; yoksa elle eşleme

# NFC + çoklu boşluk teke + kırpma
def mst_name_clean(s)
  x=s.to_s.dup
  x=x.force_encoding('UTF-8') unless x.encoding==Encoding::UTF_8
  x=x.scrub('')
  x=(x.unicode_normalize(:nfc) rescue x)
  x.gsub(/[[:space:]]+/,' ').strip
end

# Türkçe karşılaştırma anahtarı: temizle + upcase(:turkic) + İ→I (i, ı, I, İ aynı sayılır)
def mst_name_key(s)
  x=mst_name_clean(s)
  x=MST_TURKIC_UPCASE ? x.upcase(:turkic) : x.tr("iı","İI").upcase
  x.tr("İ",'I')
end

# => temizlenmiş ad ('' = ad yok); kural dışı → Türkçe hata (çağıran işlem açmadan önce çağırır)
def mst_name_validate(name,max,what)
  n=mst_name_clean(name)
  return '' if n.empty?
  raise "#{what}: en fazla #{max} karakter olabilir (#{n.length} karakter)." if n.length>max
  bad=n.each_char.reject{|c|c=~MST_NAME_CHAR}.uniq
  unless bad.empty?
    shown=bad.map{|c|c=~/[[:cntrl:]]/ ? 'denetim karakteri' : "'#{c}'"}.join(', ')
    raise "#{what}: izin verilmeyen karakter (#{shown}). Kullanılabilir: harf, rakam, boşluk ve - _ . ( ) # + &"
  end
  n
end

# Yeni / değişen yapı ve aks KODU (03.11.2026 kullanıcı kararı): harf, rakam, boşluk, - _ . (görünen ad kuralı ayrı, değişmez).
# Kayıtlı eski kodlar denetlenmez. Aks Yöneticisi JS checkCode ile aynı küme (MST_CODE_CHAR yukarıda).
def mst_code_validate(code,max,what)
  n=mst_name_clean(code)
  return '' if n.empty?
  raise "#{what}: en fazla #{max} karakter olabilir (#{n.length} karakter)." if n.length>max
  bad=n.each_char.reject{|c|c=~MST_CODE_CHAR}.uniq
  unless bad.empty?
    shown=bad.map{|c|c=~/[[:cntrl:]]/ ? 'denetim karakteri' : "'#{c}'"}.join(', ')
    raise "#{what}: izin verilmeyen karakter (#{shown}). Kod için kullanılabilir: harf, rakam, boşluk ve - _ ."
  end
  n
end

def mst_structure_display_names(model=Sketchup.active_model)
  raw=model.get_attribute(DICT,'structure_display_names_json','').to_s
  h=raw.strip.empty? ? {} : (JSON.parse(raw) rescue {})
  return {} unless h.is_a?(Hash)
  h.each_with_object({}){|(k,v),o|o[k.to_s]=v if v.is_a?(String) && !v.strip.empty? && v!=k.to_s}
end

def mst_axis_display_names(model=Sketchup.active_model)
  raw=model.get_attribute(DICT,'axis_display_names_json','').to_s
  h=raw.strip.empty? ? {} : (JSON.parse(raw) rescue {})
  return {} unless h.is_a?(Hash)
  h.each_with_object({}) do |(k,v),o|
    next unless v.is_a?(Hash)
    e={}
    %w[x y].each{|d|m_=v[d];e[d]=m_.is_a?(Hash) ? m_.each_with_object({}){|(c,n),q|q[c.to_s]=n if n.is_a?(String) && !n.strip.empty? && n!=c.to_s} : {}}
    o[k.to_s]=e
  end
end

def mst_structure_display(code,names=nil,model=Sketchup.active_model)
  c=code.to_s;n=(names || mst_structure_display_names(model))[c].to_s
  n.strip.empty? ? c : n
end

# Seçici etiketi: "Görünen Ad (kod)"; görünen ad koda eşitse yalnız kod
def mst_structure_label(code,names=nil,model=Sketchup.active_model)
  d=mst_structure_display(code,names,model)
  d==code.to_s ? code.to_s : "#{d} (#{code})"
end

def mst_axis_display(ano,zone,dir,code,amap=nil,model=Sketchup.active_model)
  z=zone.to_s.strip.empty? ? ano.to_s : zone.to_s
  n=(((amap || mst_axis_display_names(model))[mst_axis_grid_key(ano,z)] || {})[dir.to_s.downcase] || {})[code.to_s].to_s
  n.strip.empty? ? code.to_s : n
end

# G5c (03.11.2026): Kazık Özel Ayarları penceresi başlığı ve nokta listesi metni. Aks / nokta kodu (payload axis_name, point_name)
# değişmez; görünen ad varsa "Ad (kod)". Yapı: yükte 'structure' varsa o, yoksa kazık sayfasının ızgarasını yükleyen etkin yapı
# (pile_load_central_grid ile aynı kural; salt okuma, yazım yok). X aksı → 'x', nokta (Y aksı) → 'y'.
def mst_pile_override_labels(payload,model=Sketchup.active_model)
  st=payload['structure'].to_s.strip
  if st.empty?
    sys=model.get_attribute(DICT,'project_system_type','ISKELE').to_s.upcase
    sys='ISKELE' unless %w[DOLFEN ISKELE RIHTIM].include?(sys)
    st=model.get_attribute(DICT,"active_structure__#{sys}",'').to_s
  end
  amap=mst_axis_display_names(model)
  lab=lambda do |dir,code|
    c=code.to_s
    return c if c.empty? || st.empty?
    d=mst_axis_display(st,st,dir,c,amap)
    d==c ? c : "#{d} (#{c})"
  end
  {'axis'=>lab.call('x',payload['axis_name']),'points'=>Array(payload['points']).map{|p|lab.call('y',(p.is_a?(Hash) ? p['point_name'] : nil))}}
end

# Sonraki boş kod: aynı ön ekli kodların en büyük numarası + 1 (görünen adlar okunmaz). Aks Yöneticisi JS nextCode ile aynı kural.
def mst_next_structure_code(system,codes)
  pre=mst_default_structure_name(system,1).sub(/\d+\z/,'')
  rx=/\A#{Regexp.escape(pre)}(\d+)\z/i
  mx=Array(codes).map{|c|c.to_s.strip[rx,1].to_i}.max.to_i
  mst_default_structure_name(system,mx+1)
end

# mst_structures_for_system süzgecinin (değiştirilmez) kabul ettiği kod biçimi; yeni / değişen kod için ön denetim
def mst_code_allowed_in_system?(system,code)
  n=code.to_s
  case system.to_s.upcase
  when 'DOLFEN' then !(n =~ /\AANO-\d+\z/i || n =~ /\ARIHTIM-\d+\z/i)
  when 'RIHTIM' then !(n =~ /\AANO-\d+\z/i || n =~ /\A(?:BD|YD|YP|KY)-?\d*\z/i)
  when 'ISKELE' then !(n =~ /\ARIHTIM-\d+\z/i || n =~ /\A(?:BD|YD|YP|KY)-?\d*\z/i)
  else true
  end
end

# Yerleşim bağlantıları: [['x'|'y', bağlantı], ...] (eski tek bağlantı biçimi dahil)
def mst_placement_links(raw)
  return [] unless raw.is_a?(Hash)
  out=[]
  out << ['x',raw['x_link']] if raw['x_link'].is_a?(Hash)
  out << ['y',raw['y_link']] if raw['y_link'].is_a?(Hash)
  if !raw.key?('x_link') && !raw.key?('y_link') && !raw['mode'].to_s.empty? && raw['mode'].to_s!='INDEPENDENT'
    out << [(raw['axis_family'].to_s.upcase=='Y' ? 'y' : 'x'),raw]
  end
  out
end

# C seçeneği — kod kullanımı (salt okuma, tek tarama). elements: kod → eleman sayısı (structure / ano / zone),
# visuals: kod → aks görseli, axes: [yapı, 'x'|'y', aks] → eleman sayısı (grid_x_axis / grid_y_axis; axis / first_axis / last_axis iki yönde sayılır, eleman başına bir kez)
def mst_code_usage(model=Sketchup.active_model)
  el=Hash.new(0);vis=Hash.new(0);ax=Hash.new(0)
  list=[];collect_elements(model.entities,list)
  list=(list+mst_find_pile_layouts(model.entities)).uniq
  seen={};list.each{|e|seen[e]=true}
  mst_code_usage_extra(model.entities,seen,list,vis,{})   # 25/3: diğer MST öğeleri (jet grout vb.) + iç içe aks görseli
  list.each do |e|
    next unless e.valid?
    s=e.get_attribute(DICT,'structure','').to_s.strip;a=e.get_attribute(DICT,'ano','').to_s.strip;z=e.get_attribute(DICT,'zone','').to_s.strip
    [s,a,z].reject(&:empty?).uniq.each{|c|el[c]+=1}
    own=s.empty? ? a : s
    next if own.empty?
    star=(e.get_attribute(DICT,'axis','').to_s.split(/[,↔]/)+[e.get_attribute(DICT,'first_axis','').to_s,e.get_attribute(DICT,'last_axis','').to_s])   # prekast "X-01↔X-02"
    ([e.get_attribute(DICT,'grid_x_axis','').to_s]+star).map(&:strip).reject(&:empty?).uniq.each{|v|ax[[own,'x',v]]+=1}
    ([e.get_attribute(DICT,'grid_y_axis','').to_s]+star).map(&:strip).reject(&:empty?).uniq.each{|v|ax[[own,'y',v]]+=1}
  end
  {'elements'=>el,'visuals'=>vis,'axes'=>ax}
end

# Salt okuma. collect_elements'in toplamadığı element_type'lı öğeler out'a eklenir (içine inilmez); aks görselleri her düzeyde sayılır;
# element_type'sız grup / bileşen içine inilir (bileşen tanımı bir kez). Etiket grupları taranmaz.
def mst_code_usage_extra(ents,seen,out,vis,defs)
  ents.each do |e|
    next unless (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid?
    t=e.get_attribute(DICT,'element_type','').to_s
    if t=='axis_grid_visual'
      vis[e.get_attribute(DICT,'ano','').to_s]+=1
    elsif !t.empty?
      out << e unless seen[e]
      seen[e]=true
    elsif e.get_attribute('MAG_MST_Label','kind').nil?
      if e.is_a?(Sketchup::Group)
        mst_code_usage_extra(e.entities,seen,out,vis,defs)
      else
        d=e.definition
        next if defs[d]
        defs[d]=true;mst_code_usage_extra(d.entities,seen,out,vis,defs)
      end
    end
  end
end

# => nil (kod değiştirilebilir) / Türkçe kilit açıklaması
def mst_structure_code_lock(sys,code,usage,model=Sketchup.active_model,placements=nil)
  c=code.to_s;sys=sys.to_s.upcase;why=[]
  n=usage['elements'][c].to_i;why << "#{n} eleman" if n>0
  why << 'aks görseli' if usage['visuals'][c].to_i>0
  zones=mst_structure_zones(model)[c]
  why << 'bölge kaydı' if zones.is_a?(Array) && zones.map(&:to_s).any?{|z|z!=c && z!='ANA YAPI'}
  grids=mst_axis_grids(model)
  why << 'bölge aks ızgarası' if grids.key?(c) || grids.keys.any?{|k|k.to_s.start_with?("#{c}::") && k.to_s!=mst_axis_grid_key(c,c)}
  legacy=(JSON.parse(model.get_attribute(DICT,'ano_layout_json','').to_s) rescue nil)
  why << 'eski ANO kaydı' if legacy.is_a?(Array) && legacy.any?{|r|r.is_a?(Hash) && r['name'].to_s==c}
  pl=placements || mst_structure_placements(model)
  refs=pl.select{|k,v|k.to_s!=mst_placement_key(sys,c) && mst_placement_links(v).any?{|_f,l|l['mode'].to_s!='ABSOLUTE' && l['ref_structure'].to_s==c}}.keys.map{|k|k.to_s.split('::',2).last}
  why << "yerleşim bağlantısı (#{refs.uniq.join(', ')})" unless refs.empty?
  ss=mst_system_structures(model)
  other=%w[DOLFEN ISKELE RIHTIM].reject{|s|s==sys}.select{|s|ss[s].is_a?(Array) && ss[s].map{|q|q.to_s.strip}.include?(c)}
  why << "başka sistemde de kayıtlı (#{other.join(', ')})" unless other.empty?
  why.empty? ? nil : "Kod değiştirilemez: #{why.join(', ')} bu koda bağlı."
end

# => {'x'=>{aks=>açıklama},'y'=>{...}} yalnız kullanılan akslar (kod salt okunur)
def mst_axis_code_locks(sys,name,grid,usage,placements)
  sys=sys.to_s.upcase;out={'x'=>{},'y'=>{}}
  %w[x y].each do |d|
    (grid.is_a?(Hash) ? Array(grid[d]) : []).each do |r|
      a=r['name'].to_s;why=[]
      n=usage['axes'][[name.to_s,d,a]].to_i
      why << "#{n} eleman" if n>0
      refs=[]
      placements.each do |k,v|
        ks,kn=k.to_s.split('::',2)
        mst_placement_links(v).each do |fam,l|
          next unless fam==d && l['mode'].to_s!='ABSOLUTE'
          refs << kn.to_s if ks.to_s.upcase==sys && kn.to_s==name.to_s && l['target_axis'].to_s==a
          refs << kn.to_s if l['ref_structure'].to_s==name.to_s && l['ref_axis'].to_s==a
        end
      end
      why << "yerleşim bağlantısı (#{refs.uniq.join(', ')})" unless refs.empty?
      out[d][a]="Aks kodu değiştirilemez: #{why.join(', ')} bu aksa bağlı." unless why.empty?
    end
  end
  out
end

# Global üst bar / seçiciler için ek alanlar (mevcut alanlar değişmez)
def mst_structure_label_maps(systems,model=Sketchup.active_model)
  sn=mst_structure_display_names(model);labels={};names={}
  systems.each_value{|rows|Array(rows).each{|c|labels[c.to_s]=mst_structure_label(c,sn);names[c.to_s]=mst_structure_display(c,sn)}}
  {'structure_labels'=>labels,'structure_names'=>names}
end

# Silinen yapının görünen ad kayıtları (çağıranın işlemi içinde; bozuk kaydın üzerine yazılmaz)
def mst_display_names_forget!(model,code)
  c=code.to_s
  unless mst_json_attr_bad?(model,'structure_display_names_json',Hash)
    sn=mst_structure_display_names(model)
    model.set_attribute(DICT,'structure_display_names_json',JSON.generate(sn.reject{|k,_|k==c})) if sn.key?(c)
  end
  unless mst_json_attr_bad?(model,'axis_display_names_json',Hash)
    an=mst_axis_display_names(model);gk=mst_axis_grid_key(c,c)
    model.set_attribute(DICT,'axis_display_names_json',JSON.generate(an.reject{|k,_|k==gk})) if an.key?(gk)
  end
end

# Aks Yöneticisi kaydı — görünen adlar ve C seçeneği kod değişikliği. Yalnız okur ve doğrular (işlem açılmadan);
# x['placements'] / x['active'] içinde eski kod kaldıysa yeni koda taşır (yük, model değil).
# => {'writes'=>{anahtar=>JSON},'changes'=>[{'system','from','to'}]}
def mst_axis_manager_names_plan(x,model)
  sh=x['systems'].is_a?(Hash) ? x['systems'] : {}
  clean={}
  %w[DOLFEN ISKELE RIHTIM].each do |s|
    rows=(sh[s].is_a?(Array) ? sh[s] : []).map{|n|n.to_s.strip}.reject(&:empty?).uniq
    rows=[mst_default_structure_name(s,1)] if rows.empty?
    clean[s]=rows
  end
  all_new=clean.values.flatten.uniq
  ss=mst_system_structures(model)
  old_by={};%w[DOLFEN ISKELE RIHTIM].each{|s|old_by[s]=ss[s].is_a?(Array) ? ss[s].map{|n|n.to_s.strip}.reject(&:empty?) : []}
  old_codes=old_by.values.flatten.uniq
  # C seçeneği: kod değişikliği
  changes=[]
  (x['code_changes'].is_a?(Array) ? x['code_changes'] : []).each do |c|
    next unless c.is_a?(Hash)
    s=c['system'].to_s.upcase;f=c['from'].to_s.strip;t=c['to'].to_s.strip
    next if f.empty? || f==t
    raise 'Kod değişikliği: geçersiz sistem.' unless %w[DOLFEN ISKELE RIHTIM].include?(s)
    raise "Kod değişikliği: #{t} yapısı #{s} listesinde yok." unless clean[s].include?(t)
    raise "Kod değişikliği: eski kod #{f} aynı kayıtta başka bir yapıda kullanılamaz." if all_new.include?(f)
    changes << {'system'=>s,'from'=>f,'to'=>t}
  end
  raise 'Kod değişikliği: aynı yapı için birden fazla değişiklik var.' if changes.map{|c|c['from']}.uniq.length!=changes.length || changes.map{|c|c['to']}.uniq.length!=changes.length
  pp=x['placements'].is_a?(Hash) ? x['placements'] : {}
  unless changes.empty?
    usage=mst_code_usage(model);pl_model=mst_structure_placements(model)
    changes.each do |c|
      lock=mst_structure_code_lock(c['system'],c['from'],usage,model,pl_model)
      raise "#{c['from']}: #{lock}" if lock
      refs=pp.select{|k,v|k.to_s!=mst_placement_key(c['system'],c['from']) && mst_placement_links(v).any?{|_f,l|l['mode'].to_s!='ABSOLUTE' && l['ref_structure'].to_s==c['from']}}.keys
      raise "#{c['from']}: Kod değiştirilemez: yerleşim bağlantısı (#{refs.map{|k|k.to_s.split('::',2).last}.join(', ')}) bu koda bağlı." unless refs.empty?
      # 25/1: hedef kod kayıtlı (bu kayıtta silinmiş olsa da) bir yapının ya da sahipsiz elemanların kodu olamaz (sessiz yapı birleşmesi)
      raise "#{c['to']}: hedef kod kullanılamaz — bu kod modelde kayıtlı bir yapıya ait (bu kayıtta silinmiş olsa da bağlı verisi kalır). Başka bir kod seçin." if old_codes.include?(c['to'])
      tl=mst_structure_code_lock(c['system'],c['to'],usage,model,pl_model)
      raise "#{c['to']}: hedef kod kullanılamaz — #{tl.sub(/\AKod değiştirilemez: /,'')}" if tl
      ok=mst_placement_key(c['system'],c['from']);nk=mst_placement_key(c['system'],c['to'])
      pp[nk]=pp.delete(ok) if pp.key?(ok) && !pp.key?(nk)
      x['active'][c['system']]=c['to'] if x['active'].is_a?(Hash) && x['active'][c['system']].to_s==c['from']
    end
    mst_json_attr_guard!(model,'structure_zones_json',Hash,'Yapı / bölge listesi')
  end
  # 25/2: kullanılan yapı yalnız Aks Yöneticisi önizlemesinde onaylanmışsa silinir (yük: removed_used_structures "SİSTEM::kod")
  froms=changes.map{|c|[c['system'],c['from']]}
  removed=old_by.flat_map{|s,rows|(rows-clean[s]).reject{|c|froms.include?([s,c])}.map{|c|[s,c]}}
  unless removed.empty?
    okd=x['removed_used_structures'].is_a?(Array) ? x['removed_used_structures'].map(&:to_s) : []
    usage||=mst_code_usage(model);pl_model||=mst_structure_placements(model)
    bad=removed.map do |s,c|
      lk=mst_structure_code_lock(s,c,usage,model,pl_model)
      (lk && !okd.include?("#{s}::#{c}")) ? "#{mst_structure_label(c,nil,model)}: #{lk.sub(/\AKod değiştirilemez: /,'')}" : nil
    end.compact
    raise "Kullanılan yapı onaysız silinemez; Aks Yöneticisi'nde silme uyarısını onaylayarak yeniden kaydedin.\n#{bad.join("\n")}" unless bad.empty?
  end
  # yeni / değişen kodlar: karakter, uzunluk, sistem biçimi, benzersizlik (eski kodlara dokunulmaz)
  fresh=clean.flat_map{|s,rows|(rows-old_by[s]).map{|c|[s,c]}}   # bu sistemde yeni olan kodlar
  pairs=clean.flat_map{|s,rows|rows.map{|c|[s,c]}}
  fresh.each do |s,c|
    v=mst_code_validate(c,MST_NAME_MAX_STRUCTURE,"Yapı kodu #{c}")
    raise "Yapı kodu '#{c}': baştaki / sondaki ya da çoklu boşlukları düzeltin." unless v==c
    raise "Yapı kodu #{c} #{s == 'ISKELE' ? 'İSKELE' : s} sisteminde kullanılamaz (bu biçim başka sisteme ait). Önerilen: #{mst_next_structure_code(s,all_new+old_codes)}" unless mst_code_allowed_in_system?(s,c)
    o=pairs.find{|s2,q|!(s2==s && q==c) && mst_name_key(q)==mst_name_key(c)}
    raise "Yapı kodu #{c}, #{o[0] == 'ISKELE' ? 'İSKELE' : o[0]} / #{o[1]} koduyla çakışıyor (büyük / küçük harf ve I / İ ayrımı yapılmaz). Önerilen: #{mst_next_structure_code(s,all_new+old_codes)}" if o
  end
  # yapı görünen adları
  old_sn=mst_structure_display_names(model)
  src=x['structure_names'].is_a?(Hash) ? x['structure_names'] : old_sn
  sn={}
  all_new.each do |c|
    chg=changes.find{|q|q['to']==c}
    v=src.key?(c) ? src[c] : (chg ? src[chg['from']] : nil)
    n=mst_name_validate(v,MST_NAME_MAX_STRUCTURE,"#{c} görünen adı")
    next if n.empty? || mst_name_key(n)==mst_name_key(c)
    sn[c]=n
  end
  owner={};all_new.each{|c|owner[mst_name_key(c)] ||= c}
  sn.each do |c,n|
    o=owner[mst_name_key(n)]
    raise "#{c} görünen adı '#{n}' #{o} yapısının koduyla çakışıyor." if o && o!=c
  end
  sn.group_by{|_c,n|mst_name_key(n)}.each_value{|a|raise "'#{a.first[1]}' görünen adı birden fazla yapıda kullanılamaz (#{a.map(&:first).join(', ')})." if a.length>1}
  fresh.each do |_s,c|
    o=sn.find{|q,n|q!=c && mst_name_key(n)==mst_name_key(c)}
    raise "Yapı kodu #{c}, #{o[0]} yapısının görünen adıyla ('#{o[1]}') çakışıyor." if o
  end
  # aks görünen adları (anahtar "<yapı>::<yapı>", aynı yapı + aynı yön içinde benzersiz)
  old_an=mst_axis_display_names(model)
  an=old_an.reject{|k,_|s_,z_=k.split('::',2);s_==z_ && !all_new.include?(s_)}
  old_gr=mst_axis_grids(model)
  (x['grids'].is_a?(Hash) ? x['grids'] : {}).each do |k,g|
    next unless k.to_s.include?('::') && g.is_a?(Hash)
    s,name=k.to_s.split('::',2)
    next unless clean[s] && clean[s].include?(name)
    gk=mst_axis_grid_key(name,name)
    chg=changes.find{|q|q['to']==name}
    prev=old_an[gk] || (chg ? old_an[mst_axis_grid_key(chg['from'],chg['from'])] : nil) || {}
    entry={'x'=>{},'y'=>{}}
    %w[x y].each do |d|
      rows=(g[d].is_a?(Array) ? g[d] : []).select{|r|r.is_a?(Hash)}
      codes=rows.map{|r|r['name'].to_s.strip}
      # yeni aks kodu: kod karakter kümesi (kayıtlı eski kodlar denetlenmez)
      og=old_gr[gk] || (chg ? old_gr[mst_axis_grid_key(chg['from'],chg['from'])] : nil)
      oc=og.is_a?(Hash) ? Array(og[d]).map{|r|r.is_a?(Hash) ? r['name'].to_s.strip : ''} : []
      (codes-oc).reject(&:empty?).each do |c|
        raise "#{name} / aks kodu '#{c}': baştaki / sondaki ya da çoklu boşlukları düzeltin." unless mst_code_validate(c,MST_NAME_MAX_AXIS,"#{name} / aks kodu #{c}")==c
      end
      rows.each do |r|
        c=r['name'].to_s.strip;next if c.empty?
        v=r.key?('display') ? r['display'] : (prev[d] || {})[c]
        n=mst_name_validate(v,MST_NAME_MAX_AXIS,"#{name} / #{c} aksı görünen adı")
        next if n.empty? || mst_name_key(n)==mst_name_key(c)
        o=codes.find{|q|q!=c && mst_name_key(q)==mst_name_key(n)}
        raise "#{name} / #{c}: görünen ad '#{n}' aynı yöndeki #{o} aksının koduyla çakışıyor." if o
        entry[d][c]=n
      end
      entry[d].group_by{|_c,n|mst_name_key(n)}.each_value{|a|raise "#{name}: '#{a.first[1]}' görünen adı aynı yönde birden fazla aksta kullanılamaz (#{a.map(&:first).join(', ')})." if a.length>1}
    end
    if entry['x'].empty? && entry['y'].empty? then an.delete(gk) else an[gk]=entry end
  end
  w={}
  w['structure_display_names_json']=JSON.generate(sn) unless sn==old_sn
  w['axis_display_names_json']=JSON.generate(an) unless an==old_an
  w.each_key{|k|mst_json_attr_guard!(model,k,Hash,k=='structure_display_names_json' ? 'Yapı görünen adları' : 'Aks görünen adları')}
  {'writes'=>w,'changes'=>changes}
end

# Çağıranın işlemi içinde (Aks Yöneticisi 'MST Aks Kaydı'); mst_axis_manager_save_payload'dan sonra çağrılır.
def mst_axis_manager_apply_names!(plan,model)
  plan['writes'].each{|k,v|model.set_attribute(DICT,k,v)}
  plan['changes'].each do |c|
    f=c['from'];t=c['to']
    h=mst_structure_zones(model)
    if h.key?(f)
      h[t]=Array(h.delete(f)).map{|z|z.to_s==f ? t : z}
      model.set_attribute(DICT,'structure_zones_json',JSON.generate(h))
    end
    g=mst_axis_grids(model)
    if g.key?(mst_axis_grid_key(f,f))
      g.delete(mst_axis_grid_key(f,f))
      model.set_attribute(DICT,'axis_grids_json',JSON.generate(g))
    end
    z=model.get_attribute(DICT,"active_structure_zone__#{f}",nil)
    model.set_attribute(DICT,"active_structure_zone__#{t}",(z.to_s==f ? t : z.to_s)) unless z.nil?
    model.set_attribute(DICT,'active_ano',t) if model.get_attribute(DICT,'active_ano','').to_s==f
    %w[DOLFEN ISKELE RIHTIM].each{|s|model.set_attribute(DICT,"active_structure__#{s}",t) if model.get_attribute(DICT,"active_structure__#{s}",'').to_s==f}
  end
  plan
end
# ===== end ADR-0515-I yardımcıları =====

def mst_structures_for_system(system,model=Sketchup.active_model)
  system=system.to_s.upcase; h=mst_system_structures(model)
  a=h[system]; a=a.is_a?(Array) ? a.map{|x|x.to_s.strip}.reject(&:empty?) : []
  # v0.34.28 migration: eski ANO varsayilanlari DOLFEN/RIHTIM listesine sizmis olabilir.
  # ANO yapilari artik yalniz ISKELE sistemine aittir.
  # v0.34.30 hard separation: system lists cannot leak into each other.
  case system
  when 'DOLFEN'
    a=a.reject{|n| n =~ /\AANO-\d+\z/i || n =~ /\ARIHTIM-\d+\z/i }
  when 'RIHTIM'
    a=a.reject{|n| n =~ /\AANO-\d+\z/i || n =~ /\A(?:BD|YD|YP|KY)-?\d*\z/i }
  when 'ISKELE'
    a=a.reject{|n| n =~ /\ARIHTIM-\d+\z/i || n =~ /\A(?:BD|YD|YP|KY)-?\d*\z/i }
  end
  if a.empty?
    a=[mst_default_structure_name(system,1)]
  end
  a=a.uniq
  h[system]=a
  # K20: okuma yolu; kayıt bozuksa varsayılan liste yalnız bellekte döner, kayıt ezilmez
  # v0.51.5 P3: yalnız değer farklıysa yazılır (H3e deseni; kayıtlı değer aynı) — her sayfa geçişinde işlem dışı yazım olmasın
  js=JSON.generate(h)
  model.set_attribute(DICT,'system_structures_json',js) unless mst_json_attr_bad?(model,'system_structures_json',Hash) || model.get_attribute(DICT,'system_structures_json',nil)==js
  key="active_structure__#{system}"
  cur=model.get_attribute(DICT,key,'').to_s
  model.set_attribute(DICT,key,a.first) unless a.include?(cur)
  a
end

def mst_save_structures_for_system(system,rows,model=Sketchup.active_model)
  mst_json_attr_guard!(model,'system_structures_json',Hash,'Sistem / yapı listesi')
  system=system.to_s.upcase; h=mst_system_structures(model)
  h[system]=rows.map{|x|x.to_s.strip}.reject(&:empty?).uniq
  model.set_attribute(DICT,'system_structures_json',JSON.generate(h))
end

def mst_active_structure_for_system(system,model=Sketchup.active_model)
  rows=mst_structures_for_system(system,model); key="active_structure__#{system}"
  cur=model.get_attribute(DICT,key,'').to_s
  cur=rows.first unless rows.include?(cur)
  model.set_attribute(DICT,key,cur) unless model.get_attribute(DICT,key,nil)==cur   # v0.51.5 P3: yalnız değer farklıysa (H3e deseni)
  cur
end

def mst_set_active_system_structure(system,name,model=Sketchup.active_model)
  rows=mst_structures_for_system(system,model); raise 'Yapı bulunamadı.' unless rows.include?(name.to_s)
  model.set_attribute(DICT,"active_structure__#{system}",name.to_s)
  model.set_attribute(DICT,'active_ano',name.to_s)
  mst_add_structure_zone(name,name,model) unless mst_structure_zones_for(name,model).include?(name)
  model.set_attribute(DICT,"active_structure_zone__#{name}",name.to_s)
  name.to_s
end

def mst_structure_placements(model=Sketchup.active_model)
  raw=model.get_attribute(DICT,'structure_placements_json','').to_s
  h=raw.empty? ? {} : (JSON.parse(raw) rescue {})
  h.is_a?(Hash) ? h : {}
end

def mst_placement_key(system,name); "#{system.to_s.upcase}::#{name}"; end

def mst_structure_placement(system,name,model=Sketchup.active_model)
  h=mst_structure_placements(model); raw=h[mst_placement_key(system,name)]
  p=raw.is_a?(Hash) ? raw.dup : {}
  # v0.34.38 migration: preserve the proven v0.34.38 single-axis link as X or Y link.
  unless p.key?('x_link') || p.key?('y_link')
    if p['mode'].to_s!='' && p['mode'].to_s!='INDEPENDENT'
      fam=p['axis_family'].to_s.upcase=='Y' ? 'Y' : 'X'
      link={'mode'=>p['mode'],'ref_system'=>p['ref_system'].to_s,'ref_structure'=>p['ref_structure'].to_s,'ref_axis'=>p['ref_axis'].to_s,'target_axis'=>p['target_axis'].to_s,'distance_m'=>p['distance_m'].to_f,'direction'=>p['direction'].to_s}
      p[fam=='X' ? 'x_link' : 'y_link']=link
    end
  end
  p['x_link']=nil unless p['x_link'].is_a?(Hash)
  p['y_link']=nil unless p['y_link'].is_a?(Hash)
  p
end

def mst_axis_local_coord(structure,family,axis_name,model=Sketchup.active_model)
  g=mst_axis_grid_for(structure,model,structure)
  rows=g[family.to_s.downcase] || []
  r=rows.find{|x| x['name'].to_s==axis_name.to_s}
  raise "#{structure} / #{axis_name} aksı bulunamadı." unless r
  sign=(family.to_s.upcase=='X' ? (g['x_dir'].to_s=='-X' ? -1.0 : 1.0) : (g['y_dir'].to_s=='-Y' ? -1.0 : 1.0))
  r['coord_m'].to_f*sign
end

def mst_axis_link_origin_component(system,name,family,model,trail)
  key=mst_placement_key(system,name); token="#{key}::#{family}"
  raise "Yapı bağlantı döngüsü bulundu: #{name} / #{family}" if trail.include?(token)
  p=mst_structure_placement(system,name,model); link=p[family=='X' ? 'x_link' : 'y_link']
  return 0.0 unless link.is_a?(Hash)
  return link['coord_m'].to_f if link['mode'].to_s=='ABSOLUTE'   # v0.38 R8: Bağımsız (koordinat)
  rs=link['mode'].to_s=='SAME_SYSTEM' ? system.to_s.upcase : link['ref_system'].to_s.upcase
  rs=system.to_s.upcase if rs.empty?; rn=link['ref_structure'].to_s
  raise "#{name} / #{family}: referans yapı seçilmedi." if rn.empty?
  ref_origin=mst_axis_link_origin_component(rs,rn,family,model,trail+[token])
  rc=mst_axis_local_coord(rn,family,link['ref_axis'],model)
  tc=mst_axis_local_coord(name,family,link['target_axis'],model)
  dist=link['distance_m'].to_f; dir=link['direction'].to_s
  sign=(dir=="-#{family}" ? -1.0 : 1.0)
  ref_origin+rc+sign*dist-tc
end

def mst_structure_origin(system,name,model=Sketchup.active_model,trail=[])
  [mst_axis_link_origin_component(system,name,'X',model,trail), mst_axis_link_origin_component(system,name,'Y',model,trail)]
end

def mst_structure_chain_rows(system,model=Sketchup.active_model)
  mst_structures_for_system(system,model).map.with_index do |n,i|
    p=mst_structure_placement(system,n,model); o=(mst_structure_origin(system,n,model) rescue [0.0,0.0])
    {'order'=>i+1,'name'=>n,'placement'=>p,'origin_x'=>o[0],'origin_y'=>o[1]}
  end
end

# ---------------------------------------------------------------------------
# v0.38 R7 — Axis move: when an axis coordinate changes in the Axis Manager,
# the piles placed on that axis (and rigidly carried head beams) can be moved
# with it, after a preview, in ONE SketchUp operation together with the grid save.
# Planning is read-only. Nothing is moved that cannot be moved safely; such
# elements are listed instead (diverged piles, missing axes, distorted BKs).
# ---------------------------------------------------------------------------
MST_AXIS_TOL=1.0e-6

# name => signed position (coord × direction) for each family.
def mst_axis_positions(grid)
  sx=grid['x_dir'].to_s=='-X' ? -1.0 : 1.0
  sy=grid['y_dir'].to_s=='-Y' ? -1.0 : 1.0
  {'x'=>grid['x'].each_with_object({}){|r,h|h[r['name'].to_s]=r['coord_m'].to_f*sx},
   'y'=>grid['y'].each_with_object({}){|r,h|h[r['name'].to_s]=r['coord_m'].to_f*sy}}
end

def mst_pile_in_structure?(p,name)
  s=p.get_attribute(DICT,'structure','').to_s
  s.empty? ? p.get_attribute(DICT,'ano','').to_s==name : s==name
end

# Pure planning for one structure. old_grid/new_grid are normalized grids.
def mst_axis_move_plan(name,old_grid,new_grid,elements)
  op=mst_axis_positions(old_grid);np=mst_axis_positions(new_grid)
  changes=[]
  %w[x y].each do |fam|
    op[fam].each do |ax,pos|
      if np[fam].key?(ax)
        d=np[fam][ax]-pos
        changes << {'family'=>fam,'axis'=>ax,'delta'=>d} if d.abs>MST_AXIS_TOL
      end
    end
  end
  piles=elements.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile' && mst_pile_in_structure?(e,name)}
  moves=[];warnings=[];delta_by_pile_id={}
  piles.each do |p|
    pid=p.get_attribute(DICT,'pile_id','?').to_s
    dv=[0.0,0.0];skip=false
    [['x','grid_x_axis','axis_x_m','grid_offset_x_m',0],['y','grid_y_axis','axis_y_m','grid_offset_y_m',1]].each do |fam,akey,poskey,offkey,i|
      ax=p.get_attribute(DICT,akey,'').to_s
      next if ax.empty?
      unless np[fam].key?(ax)
        warnings << "#{pid}: #{fam.upcase} aksı '#{ax}' yeni aks sisteminde yok (silinmiş veya adı değişmiş); kazık taşınmadı." if op[fam].key?(ax)
        skip=true if op[fam].key?(ax)
        next
      end
      next unless op[fam].key?(ax)
      expected=op[fam][ax]+p.get_attribute(DICT,offkey,0).to_f
      actual=p.get_attribute(DICT,poskey,nil)
      if actual.nil? || (actual.to_f-expected).abs>1.0e-3
        d=np[fam][ax]-op[fam][ax]
        if d.abs>MST_AXIS_TOL
          warnings << "#{pid}: konumu #{fam.upcase} aksı '#{ax}' ile uyumsuz (kayıtlı #{actual.nil? ? '—' : actual.to_f.round(3)} m, beklenen #{expected.round(3)} m); elle taşınmış olabilir, kazık taşınmadı."
          skip=true
        end
        next
      end
      dv[i]=np[fam][ax]-op[fam][ax]
    end
    next if skip
    delta_by_pile_id[pid]=dv
    moves << {'pile'=>p,'id'=>pid,'dx'=>dv[0],'dy'=>dv[1]} if dv[0].abs>MST_AXIS_TOL || dv[1].abs>MST_AXIS_TOL
  end
  moved_ids={};moves.each{|mv|moved_ids[mv['id']]=true}
  beams=[];beam_warnings=[]
  elements.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='head_beam' && e.get_attribute(DICT,'ano','').to_s==name}.each do |b|
    ids=b.get_attribute(DICT,'connected_pile_ids','').to_s.split(',').map(&:strip).reject(&:empty?)
    next if ids.none?{|i|moved_ids[i]}
    bid=b.get_attribute(DICT,'head_beam_id','BK').to_s
    vecs=ids.map{|i|delta_by_pile_id[i] || [0.0,0.0]}
    if vecs.all?{|v|(v[0]-vecs[0][0]).abs<=MST_AXIS_TOL && (v[1]-vecs[0][1]).abs<=MST_AXIS_TOL}
      beams << {'beam'=>b,'id'=>bid,'dx'=>vecs[0][0],'dy'=>vecs[0][1]}
    else
      beam_warnings << "#{bid}: bağlı kazıkları farklı miktarlarda kayıyor (aks kirişin içinden geçiyor); BK taşınmadı — BK panelinden yeniden oluşturun."
    end
  end
  {'structure'=>name,'changes'=>changes,'moves'=>moves,'beams'=>beams,'warnings'=>warnings+beam_warnings}
end

# v0.38 BK2 — shared helpers: elements resting on a head beam, and the head beams an element rests on.
def mst_bk_dependents(b,children)
 out=[];queue=children[b].to_a.dup
 until queue.empty?
  c=queue.shift
  next if out.include?(c) || !c.valid?
  t=c.get_attribute(DICT,'element_type','').to_s
  next if t=='steel_pipe_pile' || t=='head_beam'
  out << c;queue.concat(children[c].to_a)
 end
 out
end

def mst_bk_beam_ancestors(e,parents,seen={})
 parents[e].to_a.flat_map do |p|
  next [] if seen[p];seen[p]=true
  t=p.get_attribute(DICT,'element_type','').to_s
  t=='head_beam' ? [p] : (t=='steel_pipe_pile' ? [] : mst_bk_beam_ancestors(p,parents,seen))
 end.uniq
end


# ---------------------------------------------------------------------------
# v0.38 BK3 — Precast follows the span. When the two head beams a precast rests
# on move by different X amounts (axis spacing changed), the precast is moved
# with its left support and rebuilt to the new span length (clear + 2 × seat).
# Identity (element_uid), Y, elevation and section are kept; a new length gets a
# new type name (PD-01 → PD-01-B), reusing an existing name when a piece of the
# same base type and same dimensions already exists. The user can rename a type
# afterwards (mst_precast_type_rename).
# ---------------------------------------------------------------------------
MST_PRECAST_TYPES=%w[flat_precast channel_precast crane_precast].freeze
MST_PRECAST_LEN_TOL=0.005

def mst_precast_type_id(e)
  t=e.get_attribute(DICT,'precast_type_id','').to_s
  t=e.get_attribute(DICT,'precast_id','').to_s if t.empty?
  t
end

def mst_precast_base_type(e)
  b=e.get_attribute(DICT,'precast_base_type_id','').to_s
  b.empty? ? mst_precast_type_id(e) : b
end

def mst_precast_dims_key(e,len=nil)
  a=->(k){(e.get_attribute(DICT,k,0).to_f*1000.0).round}
  l=((len.nil? ? e.get_attribute(DICT,'length_m',0) : len).to_f*1000.0).round
  case e.get_attribute(DICT,'element_type','').to_s
  when 'channel_precast' then [l,a['inner_width_m'],a['inner_depth_m'],a['base_thickness_m'],a['wall_thickness_m']]
  when 'crane_precast' then [l,a['width_m'],a['height_m'],a['extra_depth_m'],a['left_tooth_m'],a['right_tooth_m']]
  else [l,a['width_m'],a['height_m']]
  end
end

def mst_precast_type_registry(elements,model)
  reg={};used={}
  elements.each do |e|
    next unless e.valid?
    t=e.get_attribute(DICT,'element_type','').to_s
    next unless MST_PRECAST_TYPES.include?(t)
    tid=mst_precast_type_id(e);next if tid.empty?
    used[tid.upcase]=true
    reg[[t,mst_precast_base_type(e).upcase,mst_precast_dims_key(e)]]||=tid
  end
  lib=(JSON.parse(model.get_attribute(DICT,'precast_type_library_json','[]').to_s) rescue [])
  (lib.is_a?(Array) ? lib : []).each{|t|n=(t.is_a?(Hash) ? t['name'].to_s.strip : '');used[n.upcase]=true unless n.empty?}
  {'reg'=>reg,'used'=>used}
end

# dims: hazır ölçü anahtarı (Kontrollü Düzenleme yeni ölçüleri; verilmezse e'nin ölçüleri + new_len). Kural iki yolda aynı.
def mst_precast_new_type_name(e,new_len,registry,dims=nil)
  base=mst_precast_base_type(e)
  key=[e.get_attribute(DICT,'element_type','').to_s,base.upcase,dims || mst_precast_dims_key(e,new_len)]
  return registry['reg'][key] if registry['reg'][key]
  name=(('B'..'Z').to_a+(27..9999).map(&:to_s)).map{|s|"#{base}-#{s}"}.find{|n|!registry['used'][n.upcase]}
  registry['used'][name.upcase]=true;registry['reg'][key]=name
  name
end


# Returns [resize_hash, nil] or [nil, warning]. vec: beam => [dx,dy] (missing = not moving).
def mst_precast_resize_plan(dep,beam_by_pid,vec,registry)
  t=dep.get_attribute(DICT,'element_type','').to_s
  return [nil,nil] unless MST_PRECAST_TYPES.include?(t)
  id=element_visible_id(dep)
  l=beam_by_pid[dep.get_attribute(DICT,'support_left_pid',0).to_i];r=beam_by_pid[dep.get_attribute(DICT,'support_right_pid',0).to_i]
  return [nil,nil] unless l && r && l!=r && l.valid? && r.valid?   # no support link: caller keeps the generic warning
  l,r=[l,r].sort_by{|b|b.bounds.center.x.to_f}
  er=mst_bk_span_frame_error(l) || mst_bk_span_frame_error(r);return [nil,er] if er   # v0.51.5 K22 aşama 1
  vl=vec[l]||[0.0,0.0];vr=vec[r]||[0.0,0.0]
  return [nil,"#{id}: dayandığı BK'lar Y yönünde farklı kayıyor; prekast yerinde kaldı, kontrol edin."] if (vl[1]-vr[1]).abs>MST_AXIS_TOL
  z1=l.get_attribute(DICT,'top_elevation_m',nil);z2=r.get_attribute(DICT,'top_elevation_m',nil)
  return [nil,"#{id}: dayandığı BK üst kotları farklı; prekast yerinde kaldı, kontrol edin."] if z1.nil? || z2.nil? || (z1.to_f-z2.to_f).abs>0.005
  tr=dep.transformation
  return [nil,"#{id}: prekast döndürülmüş; otomatik boyutlandırılamadı, yerinde kaldı."] unless (tr.xaxis.x-1.0).abs<1e-6 && (tr.yaxis.y-1.0).abs<1e-6 && (tr.zaxis.z-1.0).abs<1e-6
  faces=mst_container_entities(dep).grep(Sketchup::Face)
  return [nil,"#{id}: kalıp yüzü bilgisi okunamadı (eski eleman); yerinde kaldı, prekast panelinden yeniden oluşturun."] if faces.empty? || !faces.all?{|f|[true,false].include?(f.get_attribute(DICT,'formwork',nil))}
  seat=dep.get_attribute(DICT,'seat_each_side_m',0.15).to_f
  old_len=dep.get_attribute(DICT,'length_m',0).to_f
  clear=(r.bounds.min.x.to_f-l.bounds.max.x.to_f)/39.37007874015748
  return [nil,"#{id}: boyu #{format('%.3f',old_len)} m, BK açıklığı + oturma ile uyuşmuyor (#{format('%.3f',clear+2*seat)} m); elle değiştirilmiş olabilir, yerinde kaldı."] if (old_len-(clear+2*seat)).abs>MST_PRECAST_LEN_TOL
  new_len=clear+(vr[0]-vl[0])+2*seat
  return [nil,"#{id}: yeni BK açıklığı geçersiz (#{format('%.3f',new_len-2*seat)} m); prekast yerinde kaldı."] if new_len-2*seat<=0.01
  if t=='crane_precast' && dep.get_attribute(DICT,'left_tooth_m',0).to_f+dep.get_attribute(DICT,'right_tooth_m',0).to_f>=new_len-0.001
    return [nil,"#{id}: diş boyları yeni boydan (#{format('%.3f',new_len)} m) büyük; yerinde kaldı."]
  end
  [{'element'=>dep,'id'=>id,'dx'=>vl[0],'dy'=>vl[1],'old_len'=>old_len,'new_len'=>new_len,
    'old_type'=>mst_precast_type_id(dep),'new_type'=>mst_precast_new_type_name(dep,new_len,registry),'base_type'=>mst_precast_base_type(dep)},nil]
end

# Formwork choices are read back from the tagged faces (mark_formwork_face), so a
# rebuild keeps exactly what the user chose at creation / with the face tool.
def mst_precast_face_flags(g,roles)
  faces=mst_container_entities(g).grep(Sketchup::Face)   # v0.38 PC1: Group or Component
  flags=roles.map{|names|faces.any?{|f|f.get_attribute(DICT,'formwork',false)==true && names.include?(f.get_attribute(DICT,'formwork_type','').to_s)}}
  form=faces.find{|f|f.get_attribute(DICT,'formwork',false)==true && f.material}
  [flags,form ? form.material : nil]
end

def mst_rebuild_flat_precast_length(g,len)
  h=mst_attr_hash(g);w=h['width_m'].to_f;hh=h['height_m'].to_f
  flags,form_mat=mst_precast_face_flags(g,[%w[BOTTOM],%w[LONG_SIDE_1],%w[LONG_SIDE_2],%w[END_1],%w[END_2]])
  form_mat||=material_for(Sketchup.active_model,"MAG PD Kalıp #{h['formwork_color'].to_s.empty? ? '#66A9E8' : h['formwork_color']}",h['formwork_color'].to_s.empty? ? '#66A9E8' : h['formwork_color']) if flags.any?
  g.entities.clear!
  f=g.entities.add_face([0,0,0],[m(len),0,0],[m(len),m(w),0],[0,m(w),0]);f.reverse! if f.normal.z<0;f.pushpull(m(hh))
  paint_flat_precast_formwork(g,flags,form_mat,nil)
  h['length_m']=len;h['concrete_volume_m3']=len*w*hh
  h['formwork_area_m2']=[len*w,len*hh,len*hh,w*hh,w*hh].each_with_index.sum{|a,i|flags[i] ? a : 0.0}
  mst_restore_attrs(g,h)
end

def mst_rebuild_channel_precast_length(g,len)
  h=mst_attr_hash(g);wi=h['inner_width_m'].to_f;di=h['inner_depth_m'].to_f;tb=h['base_thickness_m'].to_f;tw=h['wall_thickness_m'].to_f
  ow=wi+2*tw;oh=tb+di
  sel,form_mat=mst_precast_face_flags(g,[%w[OUTER_BOTTOM],%w[OUTER_SIDE],%w[INNER_FLOOR INNER_SIDE],%w[END_FACE]])
  form_mat||=material_for(Sketchup.active_model,'MAG Kanal Kalıp #6DBE73','#6DBE73') if sel.any?
  flags={bottom:sel[0],sides:sel[1],inner:sel[2],ends:sel[3]}
  g.entities.clear!
  prof=[[0,0],[ow,0],[ow,oh],[ow-tw,oh],[ow-tw,tb],[tw,tb],[tw,oh],[0,oh]]
  f=g.entities.add_face(prof.map{|yy,zz|Geom::Point3d.new(0,m(yy),m(zz))});raise 'Kanal U kesiti oluşturulamadı.' unless f;f.reverse! if f.normal.x<0;f.pushpull(m(len))
  paint_channel_precast_formwork(g,ow,tw,di,tb,flags,form_mat,nil)
  area=ow*tb+2*tw*di
  h['length_m']=len;h['concrete_volume_m3']=area*len
  h['formwork_area_m2']=(flags[:bottom] ? len*ow : 0.0)+(flags[:sides] ? 2*len*oh : 0.0)+(flags[:inner] ? len*(wi+2*di) : 0.0)+(flags[:ends] ? 2*area : 0.0)
  mst_restore_attrs(g,h)
end

def mst_rebuild_crane_precast_length(g,len)
  h=mst_attr_hash(g)
  form=g.entities.grep(Sketchup::Face).find{|f|f.get_attribute(DICT,'formwork',false)==true && f.material}
  form_mat=form ? form.material : nil
  w=h['width_m'].to_f;t=h['height_m'].to_f;ed=h['extra_depth_m'].to_f;lt=h['left_tooth_m'].to_f;rt=h['right_tooth_m'].to_f
  g.entities.clear!
  build_crane_precast_solid(g.entities,m(len),w,t,ed,lt,rt)
  paint_crane_precast_formwork(g,form_mat)
  h['length_m']=len;h['concrete_volume_m3']=w*(t*len+ed*[len-lt-rt,0.0].max);h['formwork_area_m2']=head_beam_formwork_area(g)
  mst_restore_attrs(g,h)
end

# v0.38 BK4.1: only the engineering TYPE name changes. precast_id is the unique
# physical ID (finalize_bim_identity / BIM Identity Repair) and the group name
# follows it — both are left untouched.
def mst_set_precast_type!(e,name)
  %w[precast_type_id precast_type].each{|k|e.set_attribute(DICT,k,name)}
  mst_assign_tag(e)   # tag follows the type name (MST | YD-02 | PD | PD-01-B)
end

# Canonical BIM type after a geometry change: same element_signature => same type_id
# (as finalize_bim_identity does); otherwise a new library type id.
def mst_precast_canonical_type!(e,ctx)
  t=e.get_attribute(DICT,'element_type','').to_s
  ctx[t]||=begin;a=[];collect_elements(Sketchup.active_model.entities,a);a.select{|x|x.valid? && x.get_attribute(DICT,'element_type','').to_s==t};end
  sig=element_signature(e)
  mate=ctx[t].find{|x|x!=e && element_signature(x)==sig && !x.get_attribute(DICT,'type_id','').to_s.strip.empty?}
  tid=mate ? mate.get_attribute(DICT,'type_id','').to_s : next_library_type_id(Sketchup.active_model,bim_type_prefix(t))
  e.set_attribute(DICT,'type_signature',sig);e.set_attribute(DICT,'type_id',tid);e.set_attribute(DICT,'library_type_id',tid)
  tid
end

def mst_apply_precast_resize!(rs,ctx={})
  e=rs['element'];return false unless e && e.valid?
  e.transform!(Geom::Transformation.translation([m(rs['dx']),m(rs['dy']),0]))
  case (e.is_a?(Sketchup::ComponentInstance) ? 'component' : e.get_attribute(DICT,'element_type','').to_s)
  when 'component' then mst_precast_component_set_length!(e,rs['new_len'])   # v0.38 PC1: switch definition, never edit it
  when 'flat_precast' then mst_rebuild_flat_precast_length(e,rs['new_len'])
  when 'channel_precast' then mst_rebuild_channel_precast_length(e,rs['new_len'])
  else mst_rebuild_crane_precast_length(e,rs['new_len'])
  end
  e.set_attribute(DICT,'precast_base_type_id',rs['base_type'])
  mst_precast_canonical_type!(e,ctx)
  mst_set_precast_type!(e,rs['new_type'])
  mst_pc_after_rebuild!(e) if respond_to?(:mst_pc_after_rebuild!)   # v0.50 PC2: yeni boyla donatı
  true
end

# --- user rename of a precast type (all pieces with the same type name, kind and dimensions)
def mst_precast_rename_plan(e,new_name,elements)
  new_name=new_name.to_s.strip
  t=e.get_attribute(DICT,'element_type','').to_s;tid=mst_precast_type_id(e);dk=mst_precast_dims_key(e)
  return {'error'=>'Tip adı boş olamaz.'} if new_name.empty?
  return {'error'=>'Ad değişmedi.'} if new_name==tid
  pre=elements.select{|x|x.valid? && MST_PRECAST_TYPES.include?(x.get_attribute(DICT,'element_type','').to_s)}
  targets=pre.select{|x|x.get_attribute(DICT,'element_type','').to_s==t && mst_precast_type_id(x)==tid && mst_precast_dims_key(x)==dk}
  others=pre.reject{|x|targets.include?(x)}.select{|x|mst_precast_type_id(x).upcase==new_name.upcase}
  clash=others.find{|x|x.get_attribute(DICT,'element_type','').to_s!=t || mst_precast_dims_key(x)!=dk}
  return {'error'=>"'#{new_name}' adı farklı ölçülü/sınıflı bir prekast tipinde kullanılıyor (#{format('%.3f',clash.get_attribute(DICT,'length_m',0).to_f)} m). Başka bir ad seçin."} if clash
  {'targets'=>targets,'old'=>tid,'new'=>new_name,'merge'=>others.length,'length_m'=>e.get_attribute(DICT,'length_m',0).to_f}
end

def mst_precast_type_rename
  model=Sketchup.active_model
  e=model.selection.to_a.find{|x|x.respond_to?(:get_attribute) && MST_PRECAST_TYPES.include?(x.get_attribute(DICT,'element_type','').to_s)}
  return UI.messagebox('Önce modelde bir prekast (PD / PDÖ / PV / PK) seçin. Aynı tip adı ve ölçüdeki tüm parçalar birlikte yeniden adlandırılır.') unless e
  elements=[];collect_elements(model.entities,elements)
  tid=mst_precast_type_id(e)
  cnt=elements.count{|x|x.valid? && x.get_attribute(DICT,'element_type','').to_s==e.get_attribute(DICT,'element_type','').to_s && mst_precast_type_id(x)==tid && mst_precast_dims_key(x)==mst_precast_dims_key(e)}
  r=UI.inputbox(["Yeni tip adı  (şimdiki: #{tid} · boy #{format('%.3f',e.get_attribute(DICT,'length_m',0).to_f)} m · #{cnt} adet)"],[tid],'Prekast Tip Adı')
  return unless r
  plan=mst_precast_rename_plan(e,r[0],elements)
  return UI.messagebox(plan['error']) if plan['error']
  msg="#{plan['old']} → #{plan['new']}\n#{plan['targets'].length} adet prekast yeniden adlandırılacak (boy #{format('%.3f',plan['length_m'])} m).\nÖlçü, konum ve metraj değişmez."
  msg+="\n\n'#{plan['new']}' adında aynı ölçüde #{plan['merge']} parça zaten var; birlikte aynı tip olarak listelenecek." if plan['merge']>0
  return unless UI.messagebox(msg,MB_YESNO)==IDYES
  model.start_operation('MST Prekast Tip Adı Değiştir',true)
  begin
    plan['targets'].each{|x|mst_set_precast_type!(x,plan['new'])}
    commit_with_dependencies(model)
  rescue Exception
    model.abort_operation;raise
  end
  UI.messagebox("Tip adı değiştirildi: #{plan['old']} → #{plan['new']} (#{plan['targets'].length} adet).")
rescue=>ex
  UI.messagebox("Prekast tip adı hatası: #{ex.message}")
end

# ===========================================================================
# v0.38 PC1 — Precast as Component. Same rules as the pile Component (C1–C7):
# geometry lives in a shared, registered definition (key = type + section +
# length + formwork face choices + formwork material); identity, position and
# QTO live on the instance; a shared definition is never edited — a changed
# piece is switched to the definition of its new key.
# ===========================================================================
MST_PRECAST_DEF_DIMS={'flat_precast'=>%w[length_m width_m height_m],
 'crane_precast'=>%w[length_m width_m height_m extra_depth_m left_tooth_m right_tooth_m],
 'channel_precast'=>%w[length_m inner_width_m inner_depth_m base_thickness_m wall_thickness_m]}.freeze
MST_PRECAST_FW_ROLES={'flat_precast'=>[%w[BOTTOM],%w[LONG_SIDE_1],%w[LONG_SIDE_2],%w[END_1],%w[END_2]],
 'channel_precast'=>[%w[OUTER_BOTTOM],%w[OUTER_SIDE],%w[INNER_FLOOR INNER_SIDE],%w[END_FACE]],
 'crane_precast'=>[%w[CRANE_PRECAST_FORMWORK]]}.freeze

def mst_precast_formula_volume(t,h,len=nil)
 g=->(k){h[k].to_f};l=(len || h['length_m']).to_f
 case t
 when 'channel_precast' then ((g['inner_width_m']+2*g['wall_thickness_m'])*g['base_thickness_m']+2*g['wall_thickness_m']*g['inner_depth_m'])*l
 when 'crane_precast' then g['width_m']*(g['height_m']*l+g['extra_depth_m']*[l-g['left_tooth_m']-g['right_tooth_m'],0.0].max)
 else l*g['width_m']*g['height_m']
 end
end

def mst_marked_area_m2(ents)
 ents.grep(Sketchup::Face).select{|f|f.get_attribute(DICT,'formwork',false)==true}.sum{|f|f.area.to_f}/(39.37007874015748**2)
end

# Definition params of an existing precast (Group or Component). len overrides the length.
def mst_precast_def_params(e,len=nil)
 t=e.get_attribute(DICT,'element_type','').to_s
 raise "#{t}: prekast değil." unless MST_PRECAST_DEF_DIMS.key?(t)
 h={'type'=>t,'family'=>e.get_attribute(DICT,'precast_family','').to_s}
 MST_PRECAST_DEF_DIMS[t].each{|k|h[k]=e.get_attribute(DICT,k,0).to_f.round(6)}
 h['length_m']=len.to_f.round(6) if len
 flags,mat=mst_precast_face_flags(e,MST_PRECAST_FW_ROLES[t])
 h['fw']=flags.map{|f|f ? '1' : '0'}.join
 h['form_mat']=mat ? mat.name : ''
 h['seg']=1
 # v0.51.5 K58: donatılı parça donatısız / farklı donatılı parçalarla aynı tanıma geçmez (donatısızların anahtarı değişmez)
 pj=e.get_attribute(DICT,'pc_rebar_json','').to_s
 h['rebar']='pc-v1:'+pj unless pj.empty?
 h
end

def mst_precast_def_label(p)
 l=format('%.3f',p['length_m'])
 case p['type']
 when 'channel_precast' then "Prekast PK #{l} × #{format('%.2f',p['inner_width_m'])}/#{format('%.2f',p['inner_depth_m'])}"
 when 'crane_precast' then "Prekast #{p['family'].empty? ? 'PV' : p['family']} #{l} × #{format('%.2f',p['width_m'])} × #{format('%.2f',p['height_m'])}"
 else "Prekast PD #{l} × #{format('%.2f',p['width_m'])} × #{format('%.2f',p['height_m'])}"
 end
end

# Builds precast geometry into anything with #entities (a Group or a ComponentDefinition).
def mst_precast_build_geometry!(c,p,model=Sketchup.active_model)
 t=p['type'];l=p['length_m'].to_f;ents=c.entities
 mat=p['form_mat'].to_s.empty? ? nil : model.materials[p['form_mat'].to_s]
 fl=p['fw'].to_s.chars.map{|x|x=='1'}
 case t
 when 'flat_precast'
  w=p['width_m'].to_f;hh=p['height_m'].to_f
  f=ents.add_face([0,0,0],[m(l),0,0],[m(l),m(w),0],[0,m(w),0]);f.reverse! if f.normal.z<0;f.pushpull(m(hh))
  paint_flat_precast_formwork(c,fl,mat,nil)
 when 'channel_precast'
  wi=p['inner_width_m'].to_f;di=p['inner_depth_m'].to_f;tb=p['base_thickness_m'].to_f;tw=p['wall_thickness_m'].to_f;ow=wi+2*tw;oh=tb+di
  prof=[[0,0],[ow,0],[ow,oh],[ow-tw,oh],[ow-tw,tb],[tw,tb],[tw,oh],[0,oh]]
  f=ents.add_face(prof.map{|yy,zz|Geom::Point3d.new(0,m(yy),m(zz))});raise 'Kanal U kesiti oluşturulamadı.' unless f;f.reverse! if f.normal.x<0;f.pushpull(m(l))
  paint_channel_precast_formwork(c,ow,tw,di,tb,{bottom:fl[0],sides:fl[1],inner:fl[2],ends:fl[3]},mat,nil)
 when 'crane_precast'
  build_crane_precast_solid(ents,m(l),p['width_m'].to_f,p['height_m'].to_f,p['extra_depth_m'].to_f,p['left_tooth_m'].to_f,p['right_tooth_m'].to_f)
  paint_crane_precast_formwork(c,mat)
 end
 c
end

def mst_precast_definition(model,p)
 d,_=mst_def_find_or_create(model,'precast',p,mst_precast_def_label(p)){mst_precast_build_geometry!(model.definitions.add('MST Prekast (yeni)'),p,model)}
 d
end

def mst_copy_dicts!(from,to)
 (from.attribute_dictionaries || []).each{|dict|dict.each_pair{|k,v|to.set_attribute(dict.name,k,v)}}
 # ADR-0515 §1 / G2: öğe yeni varlıkla değiştirildi; sahiplik yalnız kaynak asıl sahipse yeni varlığa geçer
 # (kayıt varsa kayıtlı PID = kaynak PID; kayıt yoksa UID içindeki PID = kaynak PID; ayrıştırılamıyorsa yazılmaz)
 own=from.get_attribute(DICT,'uid_owner_pid',nil);fu=from.get_attribute(DICT,'element_uid','').to_s
 to.set_attribute(DICT,'uid_owner_pid',to.persistent_id) if !fu.empty? && (own.nil? ? (fu[/\AMST-(\d+)-/,1] || -1).to_i==from.persistent_id : own.to_i==from.persistent_id)
 to.name=from.name if to.respond_to?(:name=)
 to.layer=from.layer if from.layer
 to.material=from.material if from.material
end

# Read-only check: can this Group precast become a Component without changing geometry/QTO?
def mst_precast_convert_check(g,model=Sketchup.active_model)
 return 'zaten Component' unless g.is_a?(Sketchup::Group)
 return 'iç grup içeriyor' if g.entities.grep(Sketchup::Group).any? || g.entities.grep(Sketchup::ComponentInstance).any?
 p=mst_precast_def_params(g)
 t=p['type']
 return 'ölçüler eksik' if MST_PRECAST_DEF_DIMS[t].any?{|k|p[k].to_f<=0 && !%w[extra_depth_m left_tooth_m right_tooth_m].include?(k)}
 vol=g.get_attribute(DICT,'concrete_volume_m3',0).to_f
 return format('kayıtlı hacim (%.4f) ölçülerle uyuşmuyor (%.4f)',vol,mst_precast_formula_volume(t,mst_attr_hash(g))) if (vol-mst_precast_formula_volume(t,mst_attr_hash(g))).abs>1e-4
 fw=mst_marked_area_m2(g.entities);st=g.get_attribute(DICT,'formwork_area_m2',fw).to_f
 return format('kalıp yüzleri elle değiştirilmiş (%.3f / %.3f m²)',fw,st) if (fw-st).abs>1e-3
 # the regenerated faces must give the same formwork area (face choices are kept per role)
 exp=mst_precast_role_formwork(p)
 return format('kalıp yüzleri parça bazında değiştirilmiş (%.3f / %.3f m²)',st,exp) if exp && (exp-st).abs>1e-3
 if t=='crane_precast'
  return 'dişli prekastta kalıp yüzleri elle değiştirilmiş' unless g.entities.grep(Sketchup::Face).all?{|f|(f.normal.z>0.999)==(f.get_attribute(DICT,'formwork',false)!=true)}
 end
 nil
end

# Formwork area the regenerated (role-based) geometry will have; nil = geometry based (crane).
def mst_precast_role_formwork(p)
 l=p['length_m'].to_f;f=p['fw'].to_s.chars.map{|x|x=='1'}
 case p['type']
 when 'flat_precast'
  w=p['width_m'].to_f;h=p['height_m'].to_f
  [l*w,l*h,l*h,w*h,w*h].each_with_index.sum{|a,i|f[i] ? a : 0.0}
 when 'channel_precast'
  wi=p['inner_width_m'].to_f;di=p['inner_depth_m'].to_f;tb=p['base_thickness_m'].to_f;tw=p['wall_thickness_m'].to_f;ow=wi+2*tw;oh=tb+di
  [l*ow,2*l*oh,l*(wi+2*di),2*(ow*tb+2*tw*di)].each_with_index.sum{|a,i|f[i] ? a : 0.0}
 end
end

def mst_precast_to_component!(g,model=Sketchup.active_model)
 d=mst_precast_definition(model,mst_precast_def_params(g))
 fw_def=mst_marked_area_m2(d.entities);st=g.get_attribute(DICT,'formwork_area_m2',fw_def).to_f
 raise format('%s: yeni tanımın kalıp alanı farklı (%.3f / %.3f m²)',element_visible_id(g),fw_def,st) if (fw_def-st).abs>1e-3
 inst=g.parent.entities.add_instance(d,g.transformation)
 mst_copy_dicts!(g,inst)
 mst_scan_cache_remove(g);g.erase!
 mst_scan_cache_add(inst)
 inst
end

def mst_precast_to_group!(c,model=Sketchup.active_model)
 raise 'Component değil.' unless c.is_a?(Sketchup::ComponentInstance)
 p=mst_precast_def_params(c)
 g=c.parent.entities.add_group
 mst_precast_build_geometry!(g,p,model)
 g.transformation=c.transformation
 mst_copy_dicts!(c,g)
 mst_scan_cache_remove(c);c.erase!
 mst_scan_cache_add(g)
 g
end

# Switch a Component precast to the definition of a new length (BK3 resize path).
def mst_precast_component_set_length!(c,len,model=Sketchup.active_model)
 d=mst_precast_definition(model,mst_precast_def_params(c,len))
 c.definition=d unless c.definition==d
 t=c.get_attribute(DICT,'element_type','').to_s
 c.set_attribute(DICT,'length_m',len)
 c.set_attribute(DICT,'concrete_volume_m3',mst_precast_formula_volume(t,mst_attr_hash(c),len))
 c.set_attribute(DICT,'formwork_area_m2',mst_marked_area_m2(d.entities))
 c
end

def mst_precast_targets(model=Sketchup.active_model)
 out=[];mst_collect_elements_raw(model.selection,out)
 out.select{|e|e.valid? && MST_PRECAST_TYPES.include?(e.get_attribute(DICT,'element_type','').to_s)}.uniq
end

def mst_precast_convert(to_component)
 model=Sketchup.active_model
 tg=mst_precast_targets(model)
 return UI.messagebox("Modelde prekast(lar) ya da bir 'Prekast Layout' grubu seçin.") if tg.empty?
 todo=tg.select{|e|to_component ? e.is_a?(Sketchup::Group) : e.is_a?(Sketchup::ComponentInstance)}
 skipped=[]
 if to_component
  todo=todo.reject{|e|(why=mst_precast_convert_check(e,model)) && skipped << "#{element_visible_id(e)}: #{why}"}
 end
 return UI.messagebox("Çevrilecek prekast yok (#{tg.length} seçili; zaten #{to_component ? 'Component' : 'Group'}).#{skipped.empty? ? '' : "\n\n"+skipped.first(10).join("\n")}") if todo.empty?
 msg="#{todo.length} prekast #{to_component ? 'Component' : 'Group'} yapılacak.\nKonum, kimlik (element_uid), tip ve metraj değişmez; tek Geri Al."
 msg+="\n\nAtlanacak #{skipped.length}:\n#{skipped.first(8).join("\n")}" unless skipped.empty?
 return unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation(to_component ? 'MST Prekast → Component' : 'MST Prekast → Group',true)
 begin
  n=0;todo.each{|e|to_component ? mst_precast_to_component!(e,model) : mst_precast_to_group!(e,model);n+=1}
  commit_with_dependencies(model)
 rescue Exception
  model.abort_operation;raise
 end
 defs=model.definitions.to_a.count{|d|d.valid? && !d.group? && d.get_attribute(DICT,'mst_def_kind','').to_s=='precast' && !d.instances.empty?}
 UI.messagebox("#{n} prekast #{to_component ? 'Component' : 'Group'} yapıldı. Kullanımdaki prekast tanımı: #{defs}.")
rescue=>e
 UI.messagebox("Prekast dönüştürme hatası: #{e.message}")
end

def mst_purge_unused_precast_definitions
 model=Sketchup.active_model
 defs=model.definitions.to_a.select{|d|d.valid? && !d.image? && !d.group? && d.get_attribute(DICT,'mst_def_kind','').to_s=='precast' && d.instances.empty?}
 used=model.definitions.to_a.count{|d|d.valid? && !d.group? && d.get_attribute(DICT,'mst_def_kind','').to_s=='precast' && !d.instances.empty?}
 return UI.messagebox("Kullanılmayan prekast tanımı yok.\nKullanımdaki prekast tanımı: #{used}") if defs.empty?
 return unless UI.messagebox("Kullanılmayan prekast tanımları temizlenecek: #{defs.length}\n#{defs.map(&:name).first(12).join("\n")}\n\nKullanımdaki #{used} tanım değişmez. Tek Geri Al. Devam?",MB_YESNO)==IDYES
 model.start_operation('MST Kullanılmayan Prekast Tanımlarını Temizle',true)
 begin
  n=mst_remove_definitions!(model,defs);model.commit_operation
  UI.messagebox("#{n} kullanılmayan prekast tanımı temizlendi.")
 rescue Exception
  model.abort_operation;raise
 end
end


# ===========================================================================
# v0.38 KN1 — BK channel pocket (cep) ↔ channel precast (PK / kanal prekastı).
# Engineering rules (agreed with the user):
#  * PK top = PD top  → pocket depth = PK height − PD thickness (PK sits on the pocket floor);
#  * pocket length (along the BK) = PK outer width + 2 × precast joint (derz, read from the model);
#  * a pocket with no PK on it → warning AND automatic placement (preview, single Undo).
# Pockets are the BK form's "Başlangıç / Son Cebi" (BK local frame: X = length, Y = width).
# ===========================================================================
MST_KN_TOL=0.005

def mst_world_tr(e)
  t=Geom::Transformation.new;p=(e.respond_to?(:parent) ? e.parent : nil);guard=0
  while p.is_a?(Sketchup::ComponentDefinition) && p.instances.length==1 && (guard+=1)<20
    inst=p.instances[0];t=inst.transformation*t;p=inst.parent
  end
  t
end

def mst_box_of_pts(pts)
  i=MST_IN_PER_M
  {'x'=>pts.map{|q|q.x.to_f/i}.minmax,'y'=>pts.map{|q|q.y.to_f/i}.minmax,'z'=>pts.map{|q|q.z.to_f/i}.minmax}
end

def mst_world_box(e)
  b=e.bounds;t=mst_world_tr(e)
  mst_box_of_pts((0..7).map{|k|b.corner(k).transform(t)})
end

def mst_kn_ov(a,b,k)
  [a[k][1],b[k][1]].min-[a[k][0],b[k][0]].max
end

def mst_kn_plan_overlap?(a,b)
  mst_kn_ov(a,b,'x')>0.01 && mst_kn_ov(a,b,'y')>0.01
end

# Pockets in the BK local frame (metres), mirroring recess_profile_points.
def mst_bk_pockets_local(h)
  return [] if h['head_beam_mode'].to_s=='multi_axis'
  l=h['length_m'].to_f;hei=h['height_m'].to_f;out=[]
  if h['start_seat_enabled'].to_s=='1'
    off=[h['start_seat_offset_m'].to_f,l].min;sw=[h['start_seat_length_m'].to_f,[l-off,0.0].max].min;sd=[h['start_seat_depth_m'].to_f,hei].min
    out << {'side'=>'start','x'=>[off,off+sw],'depth'=>sd} if sw>0 && sd>0
  end
  if h['end_seat_enabled'].to_s=='1'
    off=[h['end_seat_offset_m'].to_f,l].min;sw=[h['end_seat_length_m'].to_f,[l-off,0.0].max].min;sd=[h['end_seat_depth_m'].to_f,hei].min
    x2=l-off;x1=x2-sw;last=out.empty? ? 0.0 : out[0]['x'][1]
    out << {'side'=>'end','x'=>[x1,x2],'depth'=>sd} if sw>0 && sd>0 && x1>=last-1e-9
  end
  out
end

# Pockets in world coordinates: box (m), BK length axis ('x'/'y'), length, floor z.
def mst_bk_pockets(b)
  h=mst_attr_hash(b);wid=h['width_m'].to_f;hei=h['height_m'].to_f
  t=mst_world_tr(b)*b.transformation;ax=t.xaxis;ai=ax.x.abs>=ax.y.abs ? 'x' : 'y'
  mst_bk_pockets_local(h).map do |p|
    pts=[p['x'][0],p['x'][1]].product([0.0,wid],[hei-p['depth'],hei]).map{|x,y,z|Geom::Point3d.new(m(x),m(y),m(z)).transform(t)}
    bx=mst_box_of_pts(pts)
    p.merge('bk'=>b,'box'=>bx,'axis'=>ai,'len'=>p['x'][1]-p['x'][0],'floor_z'=>bx['z'][0])
  end
end

def mst_kn_side_label(p)
  p['side']=='start' ? 'başlangıç' : 'son'
end

# Audit: [issues, checks]; issue = [sev, entity, check, message, fix, pids]
def mst_kn_audit(elems,pockets_of=nil)
  typ=->(e){e.get_attribute(DICT,'element_type','').to_s}
  f3=->(v){format('%.3f',v.to_f)}
  beams=elems.select{|e|e.valid? && typ[e]=='head_beam'}
  pre=elems.select{|e|e.valid? && MST_PRECAST_TYPES.include?(typ[e])}
  box={};wb=->(e){box[e]||=mst_world_box(e)}
  pockets_of||=->(b){mst_bk_pockets(b)}
  pockets=beams.flat_map{|b|pockets_of.(b)}
  out=[];checks=0
  pockets.each do |pk|
    b=pk['bk'];bid=element_visible_id(b);ai=pk['axis'];pb=pk['box']
    over=pre.select{|e|mst_kn_plan_overlap?(wb[e],pb)}
    chs=over.select{|e|typ[e]=='channel_precast'};pds=over-chs
    where="#{bid} #{mst_kn_side_label(pk)} cebi"
    checks+=2
    if chs.empty?
      out << ['WARNING',b,'Kanal Cebi',"#{where} boş: üstünde kanal prekastı yok (cep #{f3[pb[ai][0]]}–#{f3[pb[ai][1]]} m, uzunluk #{f3[pk['len']]} m, derinlik #{f3[pk['depth']]} m).",
              "Prekast sayfasında 'Ceplere Kanal Prekastı Yerleştir' — cebe uyan kanalı önizlemeyle otomatik yerleştirir.",[b.persistent_id]]
    end
    unless pds.empty?
      out << ['WARNING',pds[0],'Kanal Cebi',"#{where} üstünde #{pds.length} PD var (#{pds.first(4).map{|e|element_visible_id(e)}.join(', ')}); PD cebin üstünde boşlukta kalıyor.",
              'PD yerleşimini kanal satırı cebe gelecek şekilde düzenleyin veya cebi kaldırın.',[b.persistent_id]+pds.map(&:persistent_id)]
    end
    chs.each do |c|
      cb=wb[c];cid=element_visible_id(c);j=c.get_attribute(DICT,'joint_m',0.02).to_f
      ow=cb[ai][1]-cb[ai][0];exp=ow+2*j;checks+=4
      if (pk['len']-exp).abs>MST_KN_TOL
        out << ['WARNING',c,'Kanal Cebi',"#{where} uzunluğu #{f3[pk['len']]} m; #{cid} için beklenen #{f3[exp]} m (kanal dış genişliği #{f3[ow]} + 2 × derz #{f3[j]}).",
                "BK formunda cep uzunluğunu #{f3[exp]} m yapın.",[b.persistent_id,c.persistent_id]]
      end
      d=(cb[ai][0]+cb[ai][1])/2.0-(pb[ai][0]+pb[ai][1])/2.0
      if d.abs>MST_KN_TOL
        out << ['WARNING',c,'Kanal Cebi',"#{cid} #{where} ortasında değil (kayma #{format('%+.3f',d)} m).",'Cep uçtan mesafesini veya PD yerleşimini kontrol edin.',[b.persistent_id,c.persistent_id]]
      end
      if (cb['z'][0]-pk['floor_z']).abs>MST_KN_TOL
        out << ['WARNING',c,'Kanal Cebi',"#{cid} alt kotu #{f3[cb['z'][0]]} m, #{where} tabanı #{f3[pk['floor_z']]} m (kanal cebe oturmuyor).",
                "Cep derinliği = kanal yüksekliği − PD kalınlığı olmalı; 'PD Kotlarını BK ile Güncelle' kanalı PD üstüne hizalar.",[b.persistent_id,c.persistent_id]]
      end
      mates=pre.select{|e|typ[e]!='channel_precast' && e.get_attribute(DICT,'support_left_pid',0).to_i==c.get_attribute(DICT,'support_left_pid',-1).to_i && e.get_attribute(DICT,'support_right_pid',0).to_i==c.get_attribute(DICT,'support_right_pid',-1).to_i}
      next if mates.empty?
      pdt=mates.map{|e|wb[e]['z'][1]}.max
      if (cb['z'][1]-pdt).abs>MST_KN_TOL
        out << ['WARNING',c,'Kanal Cebi',"#{cid} üst kotu #{f3[cb['z'][1]]} m, PD üstü #{f3[pdt]} m (eşit olmalı).","'PD Kotlarını BK ile Güncelle' kanalı PD üstüne hizalar.",[c.persistent_id]]
      end
    end
  end
  # channel precast pushed into a BK where the BK has no pocket
  pre.select{|e|typ[e]=='channel_precast'}.each do |c|
    cb=wb[c]
    beams.each do |b|
      bb=wb[b];next unless mst_kn_plan_overlap?(cb,bb)
      checks+=1
      next unless cb['z'][0]<bb['z'][1]-MST_KN_TOL
      next if pockets.any?{|pk|pk['bk']==b && mst_kn_plan_overlap?(cb,pk['box'])}
      out << ['WARNING',c,'Kanal Cebi',"#{element_visible_id(c)} #{element_visible_id(b)} betonuna gömülü (kanal altı #{f3[cb['z'][0]]} m < BK üstü #{f3[bb['z'][1]]} m) ama BK'da bu konumda cep yok.",
              "Prekast sayfasında 'Kanal Prekastlarına BK Cebi Aç' — cebi kanalın altına otomatik açar (önizlemeli). Elle: BK formu › 3. Kanal Prekastı.",[c.persistent_id,b.persistent_id]]
    end
  end
  [out,checks]
end

# PK type whose outer width / height fit the pocket: model type library first, then existing PKs.
def mst_kn_find_pk_type(model,elems,ow,oh)
  fits=->(wi,di,tb,tw){(wi+2*tw-ow).abs<=MST_KN_TOL && (tb+di-oh).abs<=MST_KN_TOL}
  roles=MST_PRECAST_FW_ROLES['channel_precast']
  existing=elems.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='channel_precast'}
  flags_of=lambda do |name|
    ex=existing.find{|e|mst_precast_type_id(e)==name} || existing.first
    if ex
      fl,mat=mst_precast_face_flags(ex,roles);[fl.map{|f|f ? '1' : '0'}.join,mat ? mat.name : '']
    else
      ['0010',material_for(model,'MAG Kanal Kalıp #6DBE73','#6DBE73').name]
    end
  end
  lib=(JSON.parse(model.get_attribute(DICT,'precast_type_library_json','[]').to_s) rescue [])
  (lib.is_a?(Array) ? lib : []).each do |t|
    next unless t.is_a?(Hash) && t['family'].to_s=='PK'
    wi,di,tb,tw=%w[inner_width inner_depth base wall].map{|k|t[k].to_f}
    next unless [wi,di,tb,tw].all?{|v|v>0} && fits.(wi,di,tb,tw)
    fw,mat=flags_of.(t['name'].to_s.strip)
    cc=t['concrete'].to_s.strip;cc='C30/37' if cc.empty?
    return {'name'=>t['name'].to_s.strip,'wi'=>wi,'di'=>di,'tb'=>tb,'tw'=>tw,'concrete'=>cc,'fw'=>fw,'form_mat'=>mat,'source'=>'kütüphane'}
  end
  existing.each do |e|
    wi,di,tb,tw=%w[inner_width_m inner_depth_m base_thickness_m wall_thickness_m].map{|k|e.get_attribute(DICT,k,0).to_f}
    next unless fits.(wi,di,tb,tw)
    fl,mat=mst_precast_face_flags(e,roles)
    return {'name'=>mst_precast_type_id(e),'wi'=>wi,'di'=>di,'tb'=>tb,'tw'=>tw,'concrete'=>e.get_attribute(DICT,'concrete_class','C30/37').to_s,
            'fw'=>fl.map{|f|f ? '1' : '0'}.join,'form_mat'=>mat ? mat.name : '','source'=>'modeldeki kanal'}
  end
  nil
end

# Candidates for automatic placement. only_beams: limit to spans touching these BKs.
def mst_kn_place_plan(model=Sketchup.active_model,only_beams=nil,elems=nil,pockets_of=nil)
  unless elems
    elems=[];collect_elements(model.entities,elems)
  end
  pockets_of||=->(b){mst_bk_pockets(b)}
  f3=->(v){format('%.3f',v.to_f)}
  typ=->(e){e.get_attribute(DICT,'element_type','').to_s}
  beams=elems.select{|e|e.valid? && typ[e]=='head_beam'};bpid={};beams.each{|b|bpid[b.persistent_id]=b}
  pre=elems.select{|e|e.valid? && MST_PRECAST_TYPES.include?(typ[e])}
  box={};wb=->(e){box[e]||=mst_world_box(e)}
  cands=[];warns=[]
  pre.group_by{|e|[e.get_attribute(DICT,'support_left_pid',0).to_i,e.get_attribute(DICT,'support_right_pid',0).to_i]}.each do |(lp,rp),grp|
    l=bpid[lp];r=bpid[rp];next unless l && r && l!=r
    next if only_beams && !(only_beams.include?(l) || only_beams.include?(r))
    l,r=[l,r].sort_by{|b|wb[b]['x'].sum}
    pl=pockets_of.(l);pr=pockets_of.(r)
    next if pl.empty? && pr.empty?
    span="#{element_visible_id(l)} → #{element_visible_id(r)}"
    if (pl+pr).any?{|p|p['axis']!='y'}
      warns << "#{span}: BK'lar Y yönünde değil; kanal otomatik yerleştirme yalnız Y yönündeki BK'larda (PD yerleşimi ile aynı kural).";next
    end
    used_r={}
    pl.each do |p|
      q=pr.find{|x|mst_kn_ov(p['box'],x['box'],'y')>0.01}
      unless q
        warns << "#{span}: #{element_visible_id(l)} #{mst_kn_side_label(p)} cebinin karşısında #{element_visible_id(r)}'de cep yok; kanal iki ucundan oturamaz.";next
      end
      used_r[q]=true
      if (p['box']['y'][0]-q['box']['y'][0]).abs>MST_KN_TOL || (p['box']['y'][1]-q['box']['y'][1]).abs>MST_KN_TOL
        warns << "#{span}: iki BK'daki cepler hizalı değil (Y #{f3[p['box']['y'][0]]}–#{f3[p['box']['y'][1]]} / #{f3[q['box']['y'][0]]}–#{f3[q['box']['y'][1]]} m).";next
      end
      if (p['floor_z']-q['floor_z']).abs>MST_KN_TOL
        warns << "#{span}: iki cebin taban kotu farklı (#{f3[p['floor_z']]} / #{f3[q['floor_z']]} m).";next
      end
      a0,a1=p['box']['y']
      chs=grp.select{|e|typ[e]=='channel_precast' && mst_kn_ov(wb[e],p['box'],'y')>0.01}
      next unless chs.empty?   # already there: the audit checks the fit
      mates=grp.reject{|e|typ[e]=='channel_precast'}
      if mates.empty?
        warns << "#{span}: açıklıkta PD yok; kanal üst kotu (PD üstü) belirlenemedi.";next
      end
      on=mates.select{|e|mst_kn_ov(wb[e],p['box'],'y')>0.01}
      unless on.empty?
        warns << "#{span}: cebin üstünde PD var (#{on.first(4).map{|e|element_visible_id(e)}.join(', ')}); kanal yerleştirilmedi — PD yerleşimini düzenleyin.";next
      end
      m0=mates.first;joint=m0.get_attribute(DICT,'joint_m',0.02).to_f;seat=m0.get_attribute(DICT,'seat_each_side_m',0.15).to_f
      pdt=mates.map{|e|wb[e]['z'][1]}.max
      ow=(a1-a0)-2*joint;oh=pdt-p['floor_z']
      if ow<=0 || oh<=0
        warns << "#{span}: cep ölçüsü geçersiz (kanal dış genişliği #{f3[ow]} m, yükseklik #{f3[oh]} m).";next
      end
      ty=mst_kn_find_pk_type(model,elems,ow,oh)
      unless ty
        warns << "#{span}: cebe uyan kanal tipi yok — dış genişlik #{f3[ow]} m (cep #{f3[a1-a0]} − 2 × derz #{f3[joint]}), yükseklik #{f3[oh]} m (PD üstü − cep tabanı). Prekast tip kütüphanesine bu ölçüde PK tipi ekleyin.";next
      end
      if (er=mst_bk_span_frame_error(l) || mst_bk_span_frame_error(r))   # v0.51.5 K22 aşama 1
        warns << "#{span}: #{er}";next
      end
      lb=wb[l];rb=wb[r];clear=rb['x'][0]-lb['x'][1]
      cands << {'l'=>l,'r'=>r,'span'=>span,'pocket'=>p,'type'=>ty,'x0'=>lb['x'][1]-seat,'length'=>clear+2*seat,'y0'=>a0+joint,
                'z0'=>p['floor_z'],'ow'=>ow,'oh'=>oh,'joint'=>joint,'seat'=>seat,'mate'=>m0,'top'=>pdt}
    end
    pr.each{|q|next if used_r[q];warns << "#{span}: #{element_visible_id(r)} #{mst_kn_side_label(q)} cebinin karşısında #{element_visible_id(l)}'de cep yok; kanal iki ucundan oturamaz."}
  end
  {'cands'=>cands,'warnings'=>warns.uniq}
end

def mst_kn_preview_text(kp,title='Ceplere Kanal Prekastı Yerleştir')
  f3=->(v){format('%.3f',v.to_f)}
  lines=["#{title} — #{kp['cands'].length} kanal",'']
  kp['cands'].first(20).each do |c|
    t=c['type']
    lines << "#{c['span']}: #{t['name']} (#{t['source']}) boy #{f3[c['length']]} m, dış #{f3[c['ow']]} × #{f3[c['oh']]} m, iç #{f3[t['wi']]} × #{f3[t['di']]} m"
    lines << "   cep #{mst_kn_side_label(c['pocket'])}: Y #{f3[c['y0']]}–#{f3[c['y0']+c['ow']]} m, alt #{f3[c['z0']]} m, üst #{f3[c['z0']+c['oh']]} m (= PD üstü)"
  end
  unless kp['warnings'].empty?
    lines << '' << 'Uyarılar:'
    kp['warnings'].first(10).each{|w|lines << "⚠ #{w}"}
  end
  lines << '' << 'Kanallar Component olarak, PD ile aynı prekast grubuna eklenir. Tek Geri Al.' << 'Yerleştirilsin mi?' unless kp['cands'].empty?
  lines.join("\n")
end

# v0.38 KN1.1: one engineering type name = one geometry (same rule as the PD resize):
# a PK of another length gets base-B, base-C… (an existing same-geometry name is reused).
def mst_kn_type_name(base,lm,t,ctx)
  dims=[(lm*1000.0).round]+%w[wi di tb tw].map{|k|(t[k].to_f*1000.0).round}
  key=['channel_precast',base.upcase,dims]
  return ctx['reg'][key] if ctx['reg'][key]
  name=if ctx['pk_names'][base.upcase]
    (('B'..'Z').to_a+(27..9999).map(&:to_s)).map{|x|"#{base}-#{x}"}.find{|n|!ctx['used'][n.upcase]}
  else base end
  ctx['used'][name.upcase]=true;ctx['pk_names'][name.upcase]=true;ctx['pk_names'][base.upcase]=true;ctx['reg'][key]=name
  name
end

def mst_kn_name_ctx(model)
  all=[];collect_elements(model.entities,all)
  r=mst_precast_type_registry(all,model)
  r['pk_names']={}
  all.each{|e|r['pk_names'][mst_precast_type_id(e).upcase]=true if e.valid? && e.get_attribute(DICT,'element_type','').to_s=='channel_precast'}
  r
end

def mst_kn_create_pk!(c,model=Sketchup.active_model,ctx=nil)
  t=c['type'];lm=c['length']
  p={'type'=>'channel_precast','family'=>'PK','length_m'=>lm.round(6),'inner_width_m'=>t['wi'].round(6),'inner_depth_m'=>t['di'].round(6),
     'base_thickness_m'=>t['tb'].round(6),'wall_thickness_m'=>t['tw'].round(6),'fw'=>t['fw'],'form_mat'=>t['form_mat'].to_s,'seg'=>1}
  d=mst_precast_definition(model,p)
  mate=c['mate'];par=mate.parent
  ents=par.respond_to?(:entities) ? par.entities : model.entities
  ct=par.is_a?(Sketchup::ComponentDefinition) && par.instances.length==1 ? mst_world_tr(par.instances[0])*par.instances[0].transformation : Geom::Transformation.new
  tw=Geom::Transformation.translation(Geom::Point3d.new(m(c['x0']),m(c['y0']),m(c['z0'])))
  inst=ents.add_instance(d,ct.inverse*tw)
  base=t['name'];name=ctx ? mst_kn_type_name(base,lm,t,ctx) : base;uid=next_element_uid(model,'PK')
  ow=t['wi']+2*t['tw'];oh=t['tb']+t['di'];vol=(ow*t['tb']+2*t['tw']*t['di'])*lm
  {'element_type'=>'channel_precast','precast_family'=>'PK','precast_id'=>name,'precast_type_id'=>name,'library_type_id'=>name,'precast_type'=>name,
   'element_uid'=>uid,'type_signature'=>precast_signature('PK',lm,ow,oh,[name,t['wi'],t['di'],t['tb'],t['tw']].join(':')),
   'length_m'=>lm,'width_m'=>ow,'layout_width_m'=>ow,'inner_width_m'=>t['wi'],'inner_depth_m'=>t['di'],'base_thickness_m'=>t['tb'],'wall_thickness_m'=>t['tw'],
   'bottom_elevation_m'=>c['z0'],'top_elevation_m'=>c['z0']+oh,'joint_m'=>c['joint'],'seat_each_side_m'=>c['seat'],'concrete_class'=>t['concrete'],
   'concrete_volume_m3'=>vol,'formwork_area_m2'=>mst_marked_area_m2(d.entities),'support_left_pid'=>c['l'].persistent_id,'support_right_pid'=>c['r'].persistent_id,
   'kn_from_pocket'=>"#{element_visible_id(c['pocket']['bk'])}:#{c['pocket']['side']}"}.each{|k,v|inst.set_attribute(DICT,k,v)}
  inst.set_attribute(DICT,'precast_base_type_id',base) if name!=base
  %w[project ano zone structure].each{|k|v=mate.get_attribute(DICT,k,nil);inst.set_attribute(DICT,k,v) unless v.nil? || v.to_s.empty?}
  finalize_bim_identity(inst,model)
  inst
end

def mst_kn_place_apply(kp,model=Sketchup.active_model,op='MST Ceplere Kanal Prekastı Yerleştir')
  model.start_operation(op,true)
  begin
    ctx=mst_kn_name_ctx(model)
    made=kp['cands'].map{|c|mst_kn_create_pk!(c,model,ctx)}
    mst_sync_precast_type_library(model)
    commit_with_dependencies(model)
    made
  rescue Exception
    model.abort_operation;raise
  end
end

# Button / after-edit entry point. only_beams=nil: whole model. quiet: no message when nothing to do.
# After a BK edit: only when an edited BK has a pocket (cheap check first).
def mst_kn_after_edit(beams)
  bs=beams.select{|b|b.valid? && !mst_bk_pockets_local(mst_attr_hash(b)).empty?}
  mst_kn_place(bs,true) unless bs.empty?
  # v0.38 DS2: decks resting on the edited BKs rebuild themselves (same undo step)
  mst_deck_after_edit(beams,Sketchup.active_model,true) rescue puts("DS2 döşeme güncelleme: #{$!.message}")
end

def mst_kn_place(only_beams=nil,quiet=false)
  model=Sketchup.active_model
  kp=mst_kn_place_plan(model,only_beams)
  if kp['cands'].empty?
    return if quiet && kp['warnings'].empty?
    msg=kp['warnings'].empty? ? 'Boş BK cebi yok; yerleştirilecek kanal prekastı bulunmadı.' : "Kanal prekastı yerleştirilemedi:\n\n"+kp['warnings'].first(12).map{|w|"⚠ #{w}"}.join("\n")
    UI.messagebox(msg);return
  end
  return unless UI.messagebox(mst_kn_preview_text(kp),MB_YESNO)==IDYES
  made=mst_kn_place_apply(kp,model)
  sup=made.flat_map{|e|[e.get_attribute(DICT,'support_left_pid',0).to_i,e.get_attribute(DICT,'support_right_pid',0).to_i]}
  allb=[];collect_elements(model.entities,allb)
  mst_deck_after_edit(allb.select{|b|b.get_attribute(DICT,'element_type','').to_s=='head_beam' && sup.include?(b.persistent_id)},model,true) rescue nil   # DS2
  UI.messagebox("#{made.length} kanal prekastı ceplere yerleştirildi:\n#{made.first(12).map{|e|element_visible_id(e)}.join(', ')}")
rescue=>e
  UI.messagebox("Kanal yerleştirme hatası: #{e.message}")
end

# ---------------------------------------------------------------------------
# v0.38 KN2 — the other direction: a channel precast pushed into a BK without a pocket
# (typically a PK row of the PD layout) opens the pocket in that BK automatically.
# Pocket under the PK: length = PK outer width + 2 × joint, depth = BK top − PK bottom.
# A BK has two pocket slots (start / end seat); pockets are sorted along the BK.
# ---------------------------------------------------------------------------
def mst_kn_pocket_needs(model=Sketchup.active_model,elems=nil,pockets_of=nil)
  unless elems
    elems=[];collect_elements(model.entities,elems)
  end
  pockets_of||=->(b){mst_bk_pockets(b)}
  typ=->(e){e.get_attribute(DICT,'element_type','').to_s}
  f3=->(v){format('%.3f',v.to_f)}
  beams=elems.select{|e|e.valid? && typ[e]=='head_beam'}
  chs=elems.select{|e|e.valid? && typ[e]=='channel_precast'}
  box={};wb=->(e){box[e]||=mst_world_box(e)}
  needs=Hash.new{|h,k|h[k]=[]};warns=[]
  chs.each do |c|
    cb=wb[c];j=c.get_attribute(DICT,'joint_m',0.02).to_f
    beams.each do |b|
      bb=wb[b];next unless mst_kn_plan_overlap?(cb,bb)
      next unless cb['z'][0]<bb['z'][1]-MST_KN_TOL
      next if pockets_of.(b).any?{|pk|mst_kn_plan_overlap?(cb,pk['box'])}
      bid=element_visible_id(b);cid=element_visible_id(c)
      if b.get_attribute(DICT,'head_beam_mode','').to_s=='multi_axis'
        warns << "#{cid}: #{bid} çoklu aks BK — cep bu BK tipinde desteklenmiyor.";next
      end
      h=mst_attr_hash(b);len=h['length_m'].to_f;hei=h['height_m'].to_f
      t=mst_world_tr(b)*b.transformation;ax=t.xaxis;ai=ax.x.abs>=ax.y.abs ? 'x' : 'y'
      cx=(bb['x'][0]+bb['x'][1])/2.0;cy=(bb['y'][0]+bb['y'][1])/2.0
      inv=t.inverse
      lx=[cb[ai][0]-j,cb[ai][1]+j].map do |v|
        q=ai=='x' ? [v,cy] : [cx,v]
        Geom::Point3d.new(m(q[0]),m(q[1]),0).transform(inv).x.to_f/MST_IN_PER_M
      end
      x1,x2=lx.minmax;dep=bb['z'][1]-cb['z'][0]
      if x1< -MST_KN_TOL || x2>len+MST_KN_TOL || dep>=hei
        warns << "#{cid}: #{bid} içinde cep açılamıyor (cep #{f3[x1]}–#{f3[x2]} m, BK boyu #{f3[len]} m, derinlik #{f3[dep]} m).";next
      end
      n={'x'=>[[x1,0.0].max,[x2,len].min],'depth'=>dep,'pk'=>c}
      dup=needs[b].find{|o|(o['x'][0]-n['x'][0]).abs<=MST_KN_TOL && (o['x'][1]-n['x'][1]).abs<=MST_KN_TOL}
      if dup
        warns << "#{bid}: aynı yerdeki iki kanal farklı derinlik istiyor (#{f3[dup['depth']]} / #{f3[dep]} m)." if (dup['depth']-dep).abs>MST_KN_TOL
        dup['pks'] << c
      else
        n['pks']=[c];needs[b] << n
      end
    end
  end
  plans=[]
  needs.each do |b,list|
    h=mst_attr_hash(b);len=h['length_m'].to_f
    have=mst_bk_pockets_local(h).map{|p|{'x'=>p['x'],'depth'=>p['depth'],'pks'=>[]}}
    all=(have+list).sort_by{|p|p['x'][0]}
    bid=element_visible_id(b)
    if all.length>2
      warns << "#{bid}: #{all.length} cep gerekiyor; BK'da en fazla 2 cep (başlangıç + son) tanımlanabilir.";next
    end
    if all.length==2 && all[1]['x'][0]<all[0]['x'][1]-1e-9
      warns << "#{bid}: iki cep üst üste biniyor (#{mst_kn_f3x(all)}).";next
    end
    t=mst_bk_type_hash(h)
    t['startSeatOn']=false;t['endSeatOn']=false
    s0=all[0]
    t.merge!('startSeatOn'=>true,'startSeatOffset'=>s0['x'][0].round(4).to_s,'startSeatLen'=>(s0['x'][1]-s0['x'][0]).round(4).to_s,'startSeatDepth'=>s0['depth'].round(4).to_s)
    if (s1=all[1])
      t.merge!('endSeatOn'=>true,'endSeatOffset'=>(len-s1['x'][1]).round(4).to_s,'endSeatLen'=>(s1['x'][1]-s1['x'][0]).round(4).to_s,'endSeatDepth'=>s1['depth'].round(4).to_s)
    end
    plans << {'bk'=>b,'type'=>t,'new'=>list,'pockets'=>all}
  end
  {'plans'=>plans,'warnings'=>warns.uniq}
end

def mst_kn_f3x(all)
  all.map{|p|"#{format('%.3f',p['x'][0])}–#{format('%.3f',p['x'][1])}"}.join(' / ')
end

def mst_kn_pockets_preview_text(np)
  f3=->(v){format('%.3f',v.to_f)}
  lines=["Kanal Prekastlarına BK Cebi Aç — #{np['plans'].length} BK",'']
  np['plans'].first(20).each do |pl|
    pl['new'].each do |n|
      lines << "#{element_visible_id(pl['bk'])}: uçtan #{f3[n['x'][0]]} m, uzunluk #{f3[n['x'][1]-n['x'][0]]} m, derinlik #{f3[n['depth']]} m  ← #{n['pks'].map{|c|element_visible_id(c)}.join(', ')}"
    end
  end
  unless np['warnings'].empty?
    lines << '' << 'Uyarılar:'
    np['warnings'].first(10).each{|w|lines << "⚠ #{w}"}
  end
  lines << '' << 'BK geometrisi cep ile yeniden oluşturulur (UID, kazık bağlantıları, kalıp seçimleri ve donatı korunur); cepli BK yeni tip adı alabilir. Tek Geri Al.' << 'Uygulansın mı?' unless np['plans'].empty?
  lines.join("\n")
end

def mst_kn_pockets_apply(np,model=Sketchup.active_model)
  model.start_operation('MST Kanal Prekastlarına BK Cebi Aç',true)
  begin
    res=np['plans'].map{|pl|mst_bk_apply_type!(pl['bk'],pl['type'],false)}
    mst_sync_bk_type_library(model)
    commit_with_dependencies(model)
    res
  rescue Exception
    model.abort_operation;raise
  end
end

# Button / after PD layout. quiet: no message when nothing needs a pocket.
def mst_kn_open_pockets(quiet=false)
  model=Sketchup.active_model
  np=mst_kn_pocket_needs(model)
  if np['plans'].empty?
    return if quiet && np['warnings'].empty?
    UI.messagebox(np['warnings'].empty? ? 'Cepsiz BK\'ya gömülü kanal prekastı yok.' : "BK cebi açılamadı:\n\n"+np['warnings'].first(12).map{|w|"⚠ #{w}"}.join("\n"));return
  end
  return unless UI.messagebox(mst_kn_pockets_preview_text(np),MB_YESNO)==IDYES
  res=mst_kn_pockets_apply(np,model)
  ren=res.map{|r|r['renamed']}.compact.map{|a|a.join(' → ')}.uniq
  UI.messagebox("#{res.length} BK'ya kanal cebi açıldı.#{ren.empty? ? '' : "\nTip adı: #{ren.join(', ')}"}")
rescue=>e
  UI.messagebox("BK cebi açma hatası: #{e.message}")
end

# v0.38 KN1: BK type name after an edit. A BK whose physical type changed while other BKs
# keep its old name gets a new name (BK-01 → BK-01-B…), reusing an existing name for the
# same geometry. A name typed by the user in the form always wins.
def mst_bk_resolve_type_name(g,form_name,old_name,old_sig,model=Sketchup.active_model,all=nil)
  form_name=form_name.to_s.strip;old_name=old_name.to_s.strip
  return form_name if !form_name.empty? && form_name!=old_name
  new_sig=element_signature(g)
  return old_name if new_sig==old_sig || old_name.empty?
  unless all
    all=[];collect_elements(model.entities,all)
  end
  others=all.select{|e|e!=g && e.valid? && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}
  same_name=others.select{|e|e.get_attribute(DICT,'beam_type','').to_s==old_name}
  return old_name if same_name.any?{|e|element_signature(e)==new_sig}
  # v0.38 KN1.2: same lineage + same geometry -> same name (one geometry, one name)
  base=g.get_attribute(DICT,'beam_base_type','').to_s;base=old_name if base.empty?
  mate=others.find{|e|n=e.get_attribute(DICT,'beam_type','').to_s;(n==base || n.start_with?("#{base}-") || e.get_attribute(DICT,'beam_base_type','').to_s==base) && element_signature(e)==new_sig}
  return mate.get_attribute(DICT,'beam_type','').to_s if mate
  return old_name if same_name.empty?
  used={};others.each{|e|used[e.get_attribute(DICT,'beam_type','').to_s.upcase]=true}
  (('B'..'Z').to_a+(27..9999).map(&:to_s)).map{|s|"#{base}-#{s}"}.find{|n|!used[n.upcase]}
end


# ===========================================================================
# v0.38 PR1 — Pile rebar cage (BIM). Parameters live on the pile
# ('pile_rebar_json'); geometry is regenerated from them whenever the pile or
# its infill changes (Group: own child 'pile_rebar_set'; Component: inside the
# shared definition, whose key includes the rebar parameters). Quantity comes
# from the same analytic calculation, never from counting drawn edges.
# ===========================================================================
MST_PILE_REBAR_DEFAULTS={'long_dia_mm'=>25.0,'long_mode'=>'COUNT','long_count'=>16,'long_spacing_mm'=>150.0,
 'cover_mm'=>50.0,'tr_type'=>'SPIRAL','tr_dia_mm'=>12.0,'tr_spacing_mm'=>150.0,'anchor_m'=>1.0}.freeze

def mst_pile_rebar_params(raw)
 r=MST_PILE_REBAR_DEFAULTS.merge(raw.is_a?(Hash) ? raw.reject{|_,v|v.to_s.strip.empty?} : {})
 num=->(k,label){v=Float(r[k].to_s.strip.tr(',','.')) rescue raise("#{label}: sayı değil.");raise "#{label}: geçersiz." unless v.finite?;v}
 p={'long_dia_mm'=>num.('long_dia_mm','Boyuna donatı çapı'),'long_mode'=>(r['long_mode'].to_s.upcase=='SPACING' ? 'SPACING' : 'COUNT'),
    'cover_mm'=>num.('cover_mm','Pas payı'),'tr_type'=>(r['tr_type'].to_s.upcase=='HOOP' ? 'HOOP' : 'SPIRAL'),
    'tr_dia_mm'=>num.('tr_dia_mm','Sargı çapı'),'tr_spacing_mm'=>num.('tr_spacing_mm','Sargı aralığı'),'anchor_m'=>num.('anchor_m','Filiz boyu')}
 if p['long_mode']=='COUNT'
  p['long_count']=num.('long_count','Boyuna donatı adedi').round
  raise 'Boyuna donatı adedi 4 ile 200 arasında olmalı.' unless p['long_count'].between?(4,200)
 else
  p['long_spacing_mm']=num.('long_spacing_mm','Boyuna donatı aralığı')
  raise 'Boyuna donatı aralığı 50 ile 1000 mm arasında olmalı.' unless p['long_spacing_mm'].between?(50,1000)
 end
 raise 'Boyuna donatı çapı 8 ile 50 mm arasında olmalı.' unless p['long_dia_mm'].between?(8,50)
 raise 'Sargı çapı 6 ile 32 mm arasında olmalı.' unless p['tr_dia_mm'].between?(6,32)
 raise 'Sargı aralığı 50 ile 500 mm arasında olmalı.' unless p['tr_spacing_mm'].between?(50,500)
 raise 'Pas payı 0 ile 200 mm arasında olmalı.' unless p['cover_mm'].between?(0,200)
 raise 'Filiz boyu 0 ile 5 m arasında olmalı.' unless p['anchor_m'].between?(0,5)
 p
end

def mst_pile_rebar_json(p)
 JSON.generate(p.keys.sort.each_with_object({}){|k,h|h[k]=p[k]})
end

# Pure: geometry + quantity from pile values (getter k->value) and parameters.
def mst_pile_rebar_calc(get,p,h_override=nil)
 d=get.call('diameter_mm').to_f;t=get.call('thickness_mm').to_f;di=d-2*t
 top=get.call('top_elevation_m').to_f;ib=get.call('infill_bottom_elevation_m')
 raise 'Kazık içi beton yok; donatı kafesi iç beton içinde tanımlanır.' if ib.nil? || get.call('infill_enabled').to_s!='1'
 r=get.call('orientation_mode').to_s.upcase=='BATTERED' ? get.call('batter_ratio').to_f : 0.0
 vz=1.0/Math.sqrt(1.0+r*r);h=(h_override && h_override.to_f>0) ? h_override.to_f : (top-ib.to_f)/vz
 dl=p['long_dia_mm'];dt=p['tr_dia_mm'];cov=p['cover_mm']
 rl=di/2.0-cov-dt-dl/2.0
 raise format('Donatı kafesi kazığa sığmıyor (iç çap %.0f mm, pas payı %.0f mm).',di,cov) unless rl>dl
 circ=2*Math::PI*rl/1000.0
 n=p['long_mode']=='COUNT' ? p['long_count'] : [(circ*1000.0/p['long_spacing_mm']).floor,4].max
 lc=h-cov/1000.0
 raise 'İç beton yüksekliği donatı için yetersiz.' unless lc>0.1
 l_long=p['anchor_m']+lc
 rt=rl+dl/2.0+dt/2.0;s=p['tr_spacing_mm']/1000.0
 if p['tr_type']=='SPIRAL'
  turns=lc/s;l_tr=turns*Math.sqrt((2*Math::PI*rt/1000.0)**2+s*s);tr_n=turns
 else
  tr_n=(lc/s).floor+1;l_tr=tr_n*2*Math::PI*rt/1000.0
 end
 kg_l=n*l_long*rebar_unit_kg_m(dl);kg_t=l_tr*rebar_unit_kg_m(dt)
 {'n'=>n,'rl_mm'=>rl,'rt_mm'=>rt,'spacing_mm'=>circ*1000.0/n,'l_long'=>l_long,'lc'=>lc,'h'=>h,'z_top'=>p['anchor_m'],'z_bot'=>-lc,
  'tr_n'=>tr_n,'l_tr'=>l_tr,'kg_long'=>kg_l,'kg_tr'=>kg_t,'kg'=>kg_l+kg_t}
end

def mst_pile_rebar_active(e)
 e.get_attribute(DICT,'pile_rebar_mode','').to_s=='bim_detail' && !e.get_attribute(DICT,'pile_rebar_json','').to_s.empty?
end

def mst_pile_rebar_params_of(e)
 mst_pile_rebar_params(JSON.parse(e.get_attribute(DICT,'pile_rebar_json','{}').to_s))
end

# v0.51.5 K59: kafes hesabı hata verdiyse (pile_rebar_error) metraj pursantaj kuralına döner; parametreler korunur
def mst_pile_rebar_effective?(p)
 mst_pile_rebar_active(p) && p.get_attribute(DICT,'pile_rebar_error','').to_s.empty?
end

# Cage rebar tonnage of a pile for QTO (BIM cage, else the infill concrete × rate rule).
def mst_pile_rebar_t(p)
 return p.get_attribute(DICT,'pile_cage_rebar_kg',0).to_f/1000.0 if mst_pile_rebar_effective?(p)
 pile_qto_concrete(p)*rebar_rate('pile')/1000.0
end

def mst_pile_rebar_sig(calc,p)
 JSON.generate(['bars-v3',mst_pile_rebar_json(p),calc['n'],calc['rl_mm'].round(3),calc['z_bot'].round(6),calc['z_top'].round(6)])
end

# Draws (or removes) the cage inside a Group pile (or a pile template). Idempotent.
def mst_pile_rebar_refresh!(pile)
 return unless pile && pile.valid? && pile.is_a?(Sketchup::Group)
 old=pile.entities.grep(Sketchup::Group).select{|g|g.get_attribute(DICT,'element_type','').to_s=='pile_rebar_set'}
 inf=pile.entities.grep(Sketchup::Group).find{|g|g.get_attribute(DICT,'element_type','').to_s=='pile_infill_concrete'}
 unless mst_pile_rebar_active(pile) && inf
  old.each{|g|g.erase! if g.valid?}
  %w[pile_cage_rebar_kg pile_cage_rebar_bar_count].each{|k|pile.delete_attribute(DICT,k)} unless mst_pile_rebar_active(pile)
  pile.set_attribute(DICT,'pile_cage_rebar_kg',0.0) if mst_pile_rebar_active(pile)
  return
 end
 begin
  p=mst_pile_rebar_params_of(pile)
  c=mst_pile_rebar_calc(->(k){pile.get_attribute(DICT,k,nil)},p,inf.get_attribute(DICT,'height_m',nil))
 rescue => ex
  # never block a pile edit: drop the drawn cage, keep the parameters, report the reason
  # v0.51.5 K59: tonaj 0 yazılmaz; kafes tanımsız duruma döner (iç beton × pursantaj), hata Model Kontrolü'nde
  old.each{|g|g.erase! if g.valid?}
  %w[pile_cage_rebar_kg pile_cage_rebar_bar_count].each{|k|pile.delete_attribute(DICT,k)};pile.set_attribute(DICT,'pile_rebar_error',ex.message)
  inf.delete_attribute(DICT,'rebar_mode');inf.delete_attribute(DICT,'rebar_t')
  return
 end
 pile.delete_attribute(DICT,'pile_rebar_error')
 sig=mst_pile_rebar_sig(c,p)
 if old.length==1 && old[0].get_attribute(DICT,'pile_rebar_sig','')==sig
  begin;old[0].material=mst_rebar_dia_material(Sketchup.active_model,p['long_dia_mm']) if p['long_dia_mm'].to_f>0;rescue;end   # RB2
  mst_rebar_tag!(old[0],pile)   # v0.38 RB3
  mst_pile_rebar_store!(pile,inf,c);return
 end
 old.each{|g|g.erase! if g.valid?}
 rg=pile.entities.add_group;rg.name='Pile Rebar Cage'
 {'element_type'=>'pile_rebar_set','pile_rebar_sig'=>sig,'weight_kg'=>c['kg'],'bar_count'=>c['n'],'long_dia_mm'=>p['long_dia_mm'].to_f}.each{|k,v|rg.set_attribute(DICT,k,v)}
 mst_rebar_tag!(rg,pile)   # v0.38 RB3 (önceden: 'MST | KAZIK DONATI'); paylaşılan Component tanımı 'MST Tags' ile kullanıcı yapısına göre düzeltilir
 begin;rg.material=(p['long_dia_mm'].to_f>0 ? mst_rebar_dia_material(Sketchup.active_model,p['long_dia_mm']) : material_for(Sketchup.active_model,'MAG Kazık Donatı #C0392B','#C0392B'));rescue;end   # RB2: colour by bar diameter
 mst_pile_rebar_draw!(rg.entities,c,p)
 mst_pile_rebar_store!(pile,inf,c)
end

# v0.38 PR1.2: bars are drawn as real round solids of their diameter.
# Longitudinal bars: circle + push/pull. Spiral / hoops: a tube mesh swept along the
# helix or circle (one add_faces_from_mesh call per transverse bar = fast).
MST_REBAR_SIDES=8      # sides of a bar cross-section
MST_REBAR_PATH_SEG=16  # path segments per turn / per hoop
def mst_pile_rebar_draw!(e,c,p)
 rl=mm(c['rl_mm']);rt=mm(c['rt_mm']);zt=m(c['z_top']);zb=m(c['z_bot'])
 rb=mm(p['long_dia_mm'])/2.0;rtb=mm(p['tr_dia_mm'])/2.0
 c['n'].times do |i|
  a=2*Math::PI*i/c['n']
  ed=e.add_circle(Geom::Point3d.new(rl*Math.cos(a),rl*Math.sin(a),zb),Z_AXIS,rb,MST_REBAR_SIDES)
  f=e.add_face(ed);next unless f
  f.reverse! if f.normal.z<0;f.pushpull(zt-zb)
 end
 # v0.38 PR1.3: spiral / hoops stay a light wire (centre line) — a swept tube costs ~6 000 faces per pile.
 s=p['tr_spacing_mm']/1000.0;seg=MST_REBAR_PATH_SEG
 if p['tr_type']=='SPIRAL'
  steps=(c['tr_n']*seg).ceil
  pts=(0..steps).map{|j|a=2*Math::PI*j/seg;Geom::Point3d.new(rt*Math.cos(a),rt*Math.sin(a),m([c['z_bot']+s*j/seg,0.0].min))}
  e.add_edges(pts) if pts.length>1
 else
  c['tr_n'].times do |j|
   z=c['z_bot']+s*j;next if z>0.0
   e.add_circle(Geom::Point3d.new(0,0,m(z)),Z_AXIS,rt,seg)
  end
 end
end

# path: [[angle, z_m], ...] on a cylinder of radius rad (inches); tube radius r (inches).
def mst_rebar_tube!(e,path,rad,r,closed)
 return if path.length<2
 sides=MST_REBAR_SIDES
 mesh=Geom::PolygonMesh.new(path.length*sides,path.length*sides)
 rings=path.each_with_index.map do |(a,z),i|
  ca=Math.cos(a);sa=Math.sin(a)
  nx,ny=ca,sa                      # radial (outward)
  # tangent of helix/circle at this point, then binormal = tangent × radial
  pa,pz=path[[i-1,0].max];qa,qz=path[[i+1,path.length-1].min]
  if closed
   pa,pz=path[(i-1)%path.length];qa,qz=path[(i+1)%path.length]
  end
  tx=-sa*rad;ty=ca*rad;tz=(m(qz)-m(pz))/([(qa-pa),1e-9].max)
  tl=Math.sqrt(tx*tx+ty*ty+tz*tz);tx/=tl;ty/=tl;tz/=tl
  bx=ty*0-tz*ny;by=tz*nx-tx*0;bz=tx*ny-ty*nx
  bl=Math.sqrt(bx*bx+by*by+bz*bz);bx/=bl;by/=bl;bz/=bl
  cx=rad*ca;cy=rad*sa;cz=m(z)
  (0...sides).map{|k|t=2*Math::PI*k/sides;mesh.add_point(Geom::Point3d.new(cx+r*(Math.cos(t)*nx+Math.sin(t)*bx),cy+r*(Math.cos(t)*ny+Math.sin(t)*by),cz+r*Math.sin(t)*bz))}
 end
 last=closed ? rings.length : rings.length-1
 (0...last).each do |i|
  r0=rings[i];r1=rings[(i+1)%rings.length]
  (0...sides).each{|k|k1=(k+1)%sides;mesh.add_polygon(r0[k],r0[k1],r1[k1],r1[k])}
 end
 unless closed
  mesh.add_polygon(*rings.first.reverse);mesh.add_polygon(*rings.last)
 end
 e.add_faces_from_mesh(mesh,12)   # 4 = soften, 8 = smooth: a round bar look
end

def mst_pile_rebar_store!(pile,inf,c)
 pile.set_attribute(DICT,'pile_cage_rebar_kg',c['kg']);pile.set_attribute(DICT,'pile_cage_rebar_bar_count',c['n'])
 if inf
  inf.set_attribute(DICT,'rebar_mode','bim_detail');inf.set_attribute(DICT,'rebar_t',c['kg']/1000.0)
 end
end

# QTO attributes for any pile (Group or Component); Component geometry lives in its definition.
def mst_pile_rebar_qto!(p)
 return unless p && p.valid?
 if mst_pile_rebar_active(p)
  begin
   c=mst_pile_rebar_calc(->(k){p.get_attribute(DICT,k,nil)},mst_pile_rebar_params_of(p))
   p.set_attribute(DICT,'pile_cage_rebar_kg',c['kg']);p.set_attribute(DICT,'pile_cage_rebar_bar_count',c['n'])
   p.delete_attribute(DICT,'pile_rebar_error')
  rescue => ex
   # v0.51.5 K59: sessiz 0 yok — tonaj silinir (pursantaja döner), neden kaydedilir
   %w[pile_cage_rebar_kg pile_cage_rebar_bar_count].each{|k|p.delete_attribute(DICT,k)};p.set_attribute(DICT,'pile_rebar_error',ex.message)
  end
 elsif !p.get_attribute(DICT,'pile_cage_rebar_kg',nil).nil?
  p.delete_attribute(DICT,'pile_cage_rebar_kg');p.delete_attribute(DICT,'pile_cage_rebar_bar_count')
 end
end

def mst_pile_rebar_apply(raw)
 model=Sketchup.active_model
 targets=selected_piles.map{|x|x[0]}.uniq.select(&:valid?)
 raise 'Modelde kazık(lar) ya da bir kazık grubu seçin.' if targets.empty?
 remove=raw['mode'].to_s=='NONE'
 params=remove ? nil : mst_pile_rebar_params(raw)
 lines=[];errs=[];total=0.0
 unless remove
  targets.each do |p|
   begin
    c=mst_pile_rebar_calc(->(k){p.get_attribute(DICT,k,nil)},params)
    total+=c['kg'];lines << [p.get_attribute(DICT,'pile_id','?').to_s,c] if lines.length<6
   rescue => ex
    errs << "#{p.get_attribute(DICT,'pile_id','?')}: #{ex.message}"
   end
  end
  raise "Donatı uygulanamadı:\n#{errs.first(10).join("\n")}" unless errs.empty?
 end
 msg=if remove
  "#{targets.length} kazıktan donatı kafesi kaldırılacak (metraj pursantaj kuralına döner). Tek Geri Al."
 else
  c0=lines[0][1]
  l=["Kazık İçi Donatı (BIM) — #{targets.length} kazık",'',
     format('Boyuna: %d × Ø%.0f (çevre aralığı %.0f mm), boy %.2f m (filiz %.2f m)',c0['n'],params['long_dia_mm'],c0['spacing_mm'],c0['l_long'],params['anchor_m']),
     format('%s: Ø%.0f / %.0f mm, kafes boyu %.2f m',params['tr_type']=='SPIRAL' ? 'Spiral' : 'Etriye',params['tr_dia_mm'],params['tr_spacing_mm'],c0['lc']),
     format('İlk kazık (%s): %.1f kg  •  Toplam: %.3f t',lines[0][0],c0['kg'],total/1000.0)]
  l << '' << 'Kazık değişince (Ø, boy, kot, iç beton) kafes otomatik yeniden üretilir. Tek Geri Al.'
  l.join("\n")
 end
 return {'status'=>'İptal edildi; model değişmedi.'} unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation(remove ? 'MST Kazık Donatısı Kaldır' : 'MST Kazık İçi Donatı BIM',true)
 begin
  mst_scan_batch(model) do
   targets.each do |p|
    if remove
     p.delete_attribute(DICT,'pile_rebar_mode');p.delete_attribute(DICT,'pile_rebar_json')
    else
     p.set_attribute(DICT,'pile_rebar_mode','bim_detail');p.set_attribute(DICT,'pile_rebar_json',mst_pile_rebar_json(params))
    end
    if p.is_a?(Sketchup::ComponentInstance)
     mst_pile_component_refresh!(p)
    else
     mst_pile_rebar_refresh!(p)
     if remove
      inf=mst_pile_infill_child(p);if inf;inf.delete_attribute(DICT,'rebar_mode');inf.delete_attribute(DICT,'rebar_t');end
     end
     sync_pile_bim_qto(p)
    end
   end
  end
  commit_with_dependencies(model)
 rescue Exception
  model.abort_operation;raise
 end
 {'status'=>remove ? "#{targets.length} kazıktan donatı kafesi kaldırıldı." : format('%d kazığa donatı kafesi uygulandı • toplam %.3f t (tek Geri Al)',targets.length,total/1000.0)}
end


def mst_axis_move_plan_for_payload(x,model)
  raw=mst_axis_grids(model)
  elements=[];collect_elements(model.entities,elements)
  plans=[]
  (x['grids']||{}).each do |k,g|
    next unless k.to_s.include?('::') && g.is_a?(Hash)
    _sys,name=k.to_s.split('::',2)
    old=raw[mst_axis_grid_key(name,name)]
    next unless old.is_a?(Hash)
    old_grid=(mst_axis_grid_for(name,model,name) rescue nil)
    next unless old_grid
    new_grid={'x'=>mst_normalize_axis_rows(g['x'],'X'),'y'=>mst_normalize_axis_rows(g['y'],'Y'),
              'x_dir'=>(g['x_dir'].to_s=='-X' ? '-X' : '+X'),'y_dir'=>(g['y_dir'].to_s=='-Y' ? '-Y' : '+Y')}
    plan=mst_axis_move_plan(name,old_grid,new_grid,elements)
    plans << plan unless plan['changes'].empty?
  end
  # v0.38 BK2: what sits on a moving BK (PD / kanal / döşeme / bordür) moves with it,
  # but only if every BK it rests on moves by the same vector; otherwise it stays (warning).
  if plans.any?{|pl|!pl['beams'].empty?}
    _all,children,parents,_u=dependency_graph(model)
    vec={};plans.each{|pl|pl['beams'].each{|bm|vec[bm['beam']]=[bm['dx'],bm['dy']]}}
    taken={}
    beam_by_pid=nil;registry=nil   # v0.38 BK3 (built on first precast that needs a resize)
    plans.each do |pl|
      pl['deps']=[];pl['resizes']=[]
      pl['beams'].each do |bm|
        mst_bk_dependents(bm['beam'],children).each do |dep|
          next if taken[dep]
          anc=mst_bk_beam_ancestors(dep,parents)
          ok=anc.all?{|a|(v=vec[a]) && (v[0]-bm['dx']).abs<=MST_AXIS_TOL && (v[1]-bm['dy']).abs<=MST_AXIS_TOL}
          if ok
            taken[dep]=true;pl['deps'] << {'element'=>dep,'id'=>element_visible_id(dep),'dx'=>bm['dx'],'dy'=>bm['dy']}
          else
            why=nil
            if MST_PRECAST_TYPES.include?(dep.get_attribute(DICT,'element_type','').to_s) && anc.length<=2 && anc.all?{|a|a.get_attribute(DICT,'element_type','').to_s=='head_beam'}
              beam_by_pid||=elements.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='head_beam'}.each_with_object({}){|e,h|h[e.persistent_id]=e}
              registry||=mst_precast_type_registry(elements,model)
              rs,why=mst_precast_resize_plan(dep,beam_by_pid,vec,registry)
              if rs
                taken[dep]=true;pl['resizes'] << rs
                next
              end
            end
            others=anc.reject{|a|a==bm['beam']}.map{|a|element_visible_id(a)}
            pl['warnings'] << (why || "#{element_visible_id(dep)}: #{bm['id']} ile birlikte #{others.join(', ')} kirişine de oturuyor ve o kiriş aynı miktarda kaymıyor; yerinde kaldı, kontrol edin.") unless pl['warnings'].any?{|w|w.start_with?("#{element_visible_id(dep)}:")}
          end
        end
      end
    end
  end
  plans
end

def mst_axis_fmt_list(items,max=10)
  items.first(max).join(', ')+(items.length>max ? " … (+#{items.length-max})" : '')
end

# :move, :axes_only, :cancel
def mst_axis_move_confirm(plans,splans=[])
  affected=plans.any?{|pl|!pl['moves'].empty? || !pl['beams'].empty? || !pl['warnings'].empty?} || !splans.empty?
  return :axes_only unless affected
  lines=['Aks / yapı konumu değişikliği bağlı elemanları etkiliyor.','']
  splans.each do |sp|
    lines << format('%s / %s: başlangıç X %.2f→%.2f, Y %.2f→%.2f m (ΔX %+.2f, ΔY %+.2f)',sp['system'],mst_structure_label(sp['structure']),sp['old'][0],sp['new'][0],sp['old'][1],sp['new'][1],sp['dx'],sp['dy'])
    lines << "  Taşınacak: #{sp['layouts'].length} kazık grubu (#{sp['pile_count']} kazık)#{sp['element_kinds'].empty? ? '' : ', '+sp['element_kinds'].join(', ')}#{sp['visuals'].empty? ? '' : ', aks çizgileri'}"
  end
  lines << '' unless splans.empty?
  plans.each do |pl|
    ch=pl['changes'].map{|c|format('%s %+.3f m',c['axis'],c['delta'])}
    lines << "#{mst_structure_label(pl['structure'])}: #{mst_axis_fmt_list(ch,8)}"
    lines << "  Taşınacak kazık: #{pl['moves'].length}#{pl['moves'].empty? ? '' : ' ('+mst_axis_fmt_list(pl['moves'].map{|m_|m_['id']})+')'}"
    lines << "  Taşınacak BK: #{pl['beams'].length}#{pl['beams'].empty? ? '' : ' ('+mst_axis_fmt_list(pl['beams'].map{|b|b['id']})+')'}"
    deps=pl['deps']||[]
    lines << "  BK ile birlikte taşınacak (PD / kanal / döşeme / bordür): #{deps.length} (#{mst_axis_fmt_list(deps.map{|d|d['id']})})" unless deps.empty?
    rz=pl['resizes']||[]
    unless rz.empty?
      lines << "  Açıklığa göre yeniden boyutlanacak prekast: #{rz.length}"
      grp=rz.group_by{|r|[r['old_type'],format('%.3f',r['old_len']),r['new_type'],format('%.3f',r['new_len'])]}
      grp.first(6).each{|(ot,ol,nt,nl),a|lines << "    #{ot} #{ol} m → #{nt} #{nl} m  (#{a.length} adet)"}
      lines << "    … #{grp.length-6} grup daha" if grp.length>6
    end
    pl['warnings'].first(8).each{|w|lines << "  ⚠ #{w}"}
    lines << "  ⚠ … #{pl['warnings'].length-8} uyarı daha" if pl['warnings'].length>8
  end
  lines << '' << 'Evet: aksları kaydet + bağlı kazık/BK\'ları taşı (tek Geri Al)' << 'Hayır: yalnız aksları kaydet (elemanlar yerinde kalır)' << 'İptal: hiçbir şey kaydetme'
  case UI.messagebox(lines.join("\n"),MB_YESNOCANCEL)
  when IDYES then :move
  when IDNO then :axes_only
  else :cancel
  end
end

# Moves are translations in the layout's (structure-local) frame; layouts are translation-only.
def mst_apply_axis_move_plans(plans)
  n_p=0;n_b=0;n_d=0;rz_ctx={}
  plans.each do |pl|
    pl['moves'].each do |mv|
      p=mv['pile'];dx=mv['dx'];dy=mv['dy']
      p.transform!(Geom::Transformation.translation([m(dx),m(dy),0]))
      %w[axis_x_m global_x_m toe_x_m].each{|k|v=p.get_attribute(DICT,k,nil);p.set_attribute(DICT,k,v.to_f+dx) unless v.nil?}
      %w[axis_y_m global_y_m toe_y_m].each{|k|v=p.get_attribute(DICT,k,nil);p.set_attribute(DICT,k,v.to_f+dy) unless v.nil?}
      n_p+=1
    end
    pl['beams'].each do |bm|
      bm['beam'].transform!(Geom::Transformation.translation([m(bm['dx']),m(bm['dy']),0]))
      n_b+=1
    end
    (pl['deps']||[]).each do |dp|
      e=dp['element'];next unless e.valid?
      e.transform!(Geom::Transformation.translation([m(dp['dx']),m(dp['dy']),0]))
      n_d+=1
    end
    (pl['resizes']||[]).each{|rs|mst_apply_precast_resize!(rs,rz_ctx)}   # v0.38 BK3
  end
  [n_p,n_b,n_d]
end

# Original grid/project save, unchanged in behaviour (extracted for reuse).
# G5a (03.11.2026): kayıt yükünün model özniteliklerine yazacağı değerler — mst_axis_manager_save_payload kayıt nesnesiyle kuru
# çalıştırılır (okuma: önce bekleyen yazım, yoksa model; yazım yalnız kayda). Aynı kod yolu → aynı değerler; modelde yazım yok.
class MstAttrRecorder
  attr_reader :writes
  def initialize(model);@model=model;@writes={};end
  def get_attribute(d,k,dflt=nil)
    key=[d.to_s,k.to_s]
    return (@writes[key].nil? ? dflt : @writes[key]) if @writes.key?(key)
    @model.get_attribute(d,k,dflt)
  end
  def set_attribute(d,k,v);@writes[[d.to_s,k.to_s]]=v;v;end
  def delete_attribute(d,k=nil);@writes[[d.to_s,k.to_s]]=nil;true;end
  def method_missing(n,*a,&b);@model.send(n,*a,&b);end
  def respond_to_missing?(n,p=false);@model.respond_to?(n,p);end
end
# => {[sözlük, anahtar] => yeni değer} yalnız mevcut değerden farklı olanlar (boş = değişiklik yok)
def mst_axis_manager_payload_changes(x,model)
  rec=MstAttrRecorder.new(model)
  mst_axis_manager_save_payload(JSON.parse(JSON.generate(x)),rec)
  rec.writes.reject{|(d,k),v|model.get_attribute(d,k,nil)==v}
end

# G5b (03.11.2026): kayıt yükünde, modelde kayıtlı ızgarası olan bir yapının kullanılan aks kodu (eleman ya da yerleşim bağlantısı;
# mst_axis_code_locks ile aynı kural) yoksa — silme ya da kod değişikliği — Aks Yöneticisi önizlemesinde onaylanmış olmalı
# (yükteki removed_used_axes, "SİSTEM::yapı::yön::kod"). Onaysız kayıt işlem açılmadan Türkçe hatayla durur. Kullanılan aksın
# kodu arayüzde kilitli; silme önizleme + onayla yapılır (ADR-0515-I). Eleman verisi değişmez.
def mst_axis_manager_check_removed_axes!(x,model)
  old_grids=mst_axis_grids(model);usage=nil;pl=nil;bad=[]
  ok=x['removed_used_axes'].is_a?(Array) ? x['removed_used_axes'].map(&:to_s) : []
  (x['grids'].is_a?(Hash) ? x['grids'] : {}).each do |k,g|
    next unless k.to_s.include?('::') && g.is_a?(Hash)
    sys,name=k.to_s.split('::',2)
    old=old_grids[mst_axis_grid_key(name,name)]
    next unless old.is_a?(Hash)
    %w[x y].each do |dd|
      codes=lambda{|rows|Array(rows).map{|r|r.is_a?(Hash) ? r['name'].to_s.strip : ''}.reject(&:empty?)}
      gone=codes.call(old[dd])-codes.call(g[dd])
      next if gone.empty?
      usage||=mst_code_usage(model);pl||=mst_structure_placements(model)
      mst_axis_code_locks(sys,name,{dd=>gone.map{|c|{'name'=>c}}},usage,pl)[dd].each do |c,why|
        bad << "#{mst_structure_label(name,nil,model)} / #{dd.upcase} #{c}: #{why.sub(/\AAks kodu değiştirilemez: /,'')}" unless ok.include?("#{sys}::#{name}::#{dd}::#{c}")
      end
    end
  end
  return true if bad.empty?
  raise "Kullanılan aks kaydı onaysız kaldırılamaz ya da kodu değiştirilemez:\n#{bad.first(10).join("\n")}#{bad.length>10 ? "\n… #{bad.length-10} aks daha" : ''}\nAksı geri ekleyin ya da Aks Yöneticisi kayıt önizlemesinde onaylayın. Hiçbir şey kaydedilmedi."
end

def mst_axis_manager_save_payload(x,model)
  [['system_structures_json','Sistem / yapı listesi'],['axis_grids_json','Aks ağı'],['structure_placements_json','Yapı yerleşimleri']].each{|k,l|mst_json_attr_guard!(model,k,Hash,l)}   # K20
  model.set_attribute(DICT,'project_name',x['project'].to_s.strip)
  sys=x['system'].to_s.upcase
  model.set_attribute(DICT,'project_system_type',sys)
  sh=x['systems'].is_a?(Hash) ? x['systems'] : {}
  clean={}
  %w[DOLFEN ISKELE RIHTIM].each do |sname|
    rows=(sh[sname].is_a?(Array) ? sh[sname] : []).map{|n|n.to_s.strip}.reject(&:empty?).uniq
    rows=[mst_default_structure_name(sname,1)] if rows.empty?
    clean[sname]=rows
    model.set_attribute(DICT,"active_structure__#{sname}",(x.dig('active',sname).to_s.strip.empty? ? rows.first : x.dig('active',sname).to_s))
  end
  model.set_attribute(DICT,'system_structures_json',JSON.generate(clean))
  (x['grids']||{}).each do |k,g|
    next unless k.include?('::') && g.is_a?(Hash)
    ss,name=k.split('::',2)
    next unless clean[ss]&.include?(name)
    mst_save_axis_grid({'ano'=>name,'zone'=>name,'x'=>g['x'],'y'=>g['y'],'system_axis_x'=>'','system_axis_y'=>'','x_dir'=>g['x_dir'],'y_dir'=>g['y_dir']},model)
  end
  model.set_attribute(DICT,'structure_placements_json',JSON.generate(x['placements'].is_a?(Hash) ? x['placements'] : {}))
  cur=(x.dig('active',sys).to_s.strip.empty? ? clean[sys].first : x.dig('active',sys).to_s)
  model.set_attribute(DICT,"active_structure__#{sys}",cur)
  model.set_attribute(DICT,'active_ano',cur) # downstream legacy bridge only; UI never reads this value
  [sys,cur]
end

# ---------------------------------------------------------------------------
# v0.38 R8 — Structure move. A structure can be placed at an absolute global
# coordinate ("Bağımsız (koordinat)", link mode ABSOLUTE) or linked to another
# structure. When its global origin changes (directly or through the chain),
# its pile layouts, root-level BIM elements and axis-grid visual are translated
# with it — after a preview, in the same single operation as the grid save.
# ---------------------------------------------------------------------------
def mst_axis_local_from(grid,family,axis_name,structure='')
  rows=grid[family.to_s.downcase] || []
  r=rows.find{|x|x['name'].to_s==axis_name.to_s}
  raise "#{structure} / #{axis_name} aksı bulunamadı." unless r
  sign=(family.to_s.upcase=='X' ? (grid['x_dir'].to_s=='-X' ? -1.0 : 1.0) : (grid['y_dir'].to_s=='-Y' ? -1.0 : 1.0))
  r['coord_m'].to_f*sign
end

# Pure origin: same rules as mst_axis_link_origin_component, but on given data.
def mst_origin_pure(sys,name,fam,placements,grid_for,trail=[])
  token="#{mst_placement_key(sys,name)}::#{fam}"
  raise "Yapı bağlantı döngüsü bulundu: #{name} / #{fam}" if trail.include?(token)
  raw=placements[mst_placement_key(sys,name)]
  link=raw.is_a?(Hash) ? raw[fam=='X' ? 'x_link' : 'y_link'] : nil
  if raw.is_a?(Hash) && !raw.key?('x_link') && !raw.key?('y_link') && !raw['mode'].to_s.empty? && raw['mode'].to_s!='INDEPENDENT'
    link=((raw['axis_family'].to_s.upcase=='Y' ? 'Y' : 'X')==fam) ? raw : nil   # legacy single link
  end
  return 0.0 unless link.is_a?(Hash)
  return link['coord_m'].to_f if link['mode'].to_s=='ABSOLUTE'
  rs=link['mode'].to_s=='SAME_SYSTEM' ? sys.to_s.upcase : link['ref_system'].to_s.upcase
  rs=sys.to_s.upcase if rs.empty?
  rn=link['ref_structure'].to_s
  raise "#{name} / #{fam}: referans yapı seçilmedi." if rn.empty?
  ro=mst_origin_pure(rs,rn,fam,placements,grid_for,trail+[token])
  rc=mst_axis_local_from(grid_for.call(rn),fam,link['ref_axis'],rn)
  tc=mst_axis_local_from(grid_for.call(name),fam,link['target_axis'],name)
  sign=(link['direction'].to_s=="-#{fam}" ? -1.0 : 1.0)
  ro+rc+sign*link['distance_m'].to_f-tc
end

def mst_element_in_structure?(e,sys,name)
  es=e.get_attribute(DICT,'system','').to_s.upcase
  return false if !es.empty? && es!=sys.to_s.upcase
  st=e.get_attribute(DICT,'structure','').to_s
  st.empty? ? e.get_attribute(DICT,'ano','').to_s==name : st==name
end

def mst_find_pile_layouts(entities,out=[])
  entities.grep(Sketchup::Group).each do |g|
    next unless g.valid?
    t=g.get_attribute(DICT,'element_type','').to_s
    if t=='pile_layout' then out << g
    elsif t.empty? then mst_find_pile_layouts(g.entities,out)
    end
  end
  out
end

# Piles directly inside a pile layout — Group OR ComponentInstance (v0.38 C7.2).
def mst_layout_piles(l)
 l.entities.to_a.select{|e|(e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}
end

def mst_structure_move_plans(x,model)
  old_pl=mst_structure_placements(model)
  new_pl=x['placements'].is_a?(Hash) ? x['placements'] : old_pl
  pay_grids={}
  (x['grids']||{}).each do |k,g|
    next unless k.to_s.include?('::') && g.is_a?(Hash)
    _s,n=k.to_s.split('::',2)
    pay_grids[n]={'x'=>mst_normalize_axis_rows(g['x'],'X'),'y'=>mst_normalize_axis_rows(g['y'],'Y'),'x_dir'=>(g['x_dir'].to_s=='-X' ? '-X' : '+X'),'y_dir'=>(g['y_dir'].to_s=='-Y' ? '-Y' : '+Y')}
  end
  old_grid=->(n){mst_axis_grid_for(n,model,n)}
  new_grid=->(n){pay_grids[n] || old_grid.call(n)}
  systems=x['systems'].is_a?(Hash) ? x['systems'] : {}
  layouts=mst_find_pile_layouts(model.entities)
  elements=[];collect_elements(model.entities,elements)
  root=elements.select{|e|e.valid? && e.parent.is_a?(Sketchup::Model)}
  visuals=model.entities.grep(Sketchup::Group).select{|g|g.valid? && g.get_attribute(DICT,'element_type','').to_s=='axis_grid_visual'}
  # v0.38 BK2.2: root-level containers (e.g. 'Prekast Layout') holding BIM elements.
  # A container moves with a structure when ALL BIM elements inside it belong to it.
  containers=model.entities.to_a.select{|g|(g.is_a?(Sketchup::Group) || g.is_a?(Sketchup::ComponentInstance)) && g.valid? &&
    !%w[pile_layout axis_grid_visual].include?(g.get_attribute(DICT,'element_type','').to_s) && !MST_COLLECTED_TYPES.include?(g.get_attribute(DICT,'element_type','').to_s)}
  container_elems={}
  containers.each{|g|inner=[];collect_elements(mst_container_entities(g),inner);container_elems[g]=inner.select(&:valid?) unless inner.empty?}
  plans=[]
  %w[DOLFEN ISKELE RIHTIM].each do |sys|
    names=((systems[sys].is_a?(Array) ? systems[sys] : [])+(mst_structures_for_system(sys,model) rescue [])).map(&:to_s).uniq
    names.each do |name|
      old_o=([mst_origin_pure(sys,name,'X',old_pl,old_grid),mst_origin_pure(sys,name,'Y',old_pl,old_grid)] rescue nil)
      next unless old_o
      new_o=[mst_origin_pure(sys,name,'X',new_pl,new_grid),mst_origin_pure(sys,name,'Y',new_pl,new_grid)]
      dx=new_o[0]-old_o[0];dy=new_o[1]-old_o[1]
      next if dx.abs<=MST_AXIS_TOL && dy.abs<=MST_AXIS_TOL
      lays=layouts.select{|l|l.get_attribute(DICT,'system','').to_s.upcase==sys && l.get_attribute(DICT,'structure','').to_s==name}
      elems=root.select{|e|mst_element_in_structure?(e,sys,name)}
      vis=visuals.select{|g|g.get_attribute(DICT,'ano','').to_s==name}
      conts=container_elems.select{|_g,inner|inner.all?{|e|mst_element_in_structure?(e,sys,name)}}.keys
      piles=lays.map{|l|mst_layout_piles(l).length}.inject(0,:+)
      next if lays.empty? && elems.empty? && vis.empty? && conts.empty?
      kinds=(elems+conts.flat_map{|g|container_elems[g]}).group_by{|e|e.get_attribute(DICT,'element_type','').to_s}.map{|k,v|"#{v.length} #{k}"}
      plans << {'system'=>sys,'structure'=>name,'old'=>old_o,'new'=>new_o,'dx'=>dx,'dy'=>dy,
                'layouts'=>lays,'elements'=>elems,'visuals'=>vis,'containers'=>conts,'pile_count'=>piles,'element_kinds'=>kinds}
    end
  end
  plans
end

def mst_apply_structure_move_plans(splans)
  moved=0
  splans.each do |sp|
    tr=Geom::Transformation.translation([m(sp['dx']),m(sp['dy']),0])
    sp['layouts'].each do |l|
      l.transform!(tr)
      %w[global_origin_x_m global_origin_y_m].each_with_index{|k,i|v=l.get_attribute(DICT,k,nil);l.set_attribute(DICT,k,v.to_f+(i==0 ? sp['dx'] : sp['dy'])) unless v.nil?}
      mst_layout_piles(l).each do |p|
        v=p.get_attribute(DICT,'global_x_m',nil);p.set_attribute(DICT,'global_x_m',v.to_f+sp['dx']) unless v.nil?
        v=p.get_attribute(DICT,'global_y_m',nil);p.set_attribute(DICT,'global_y_m',v.to_f+sp['dy']) unless v.nil?
        moved+=1
      end
    end
    sp['elements'].each do |e|
      e.transform!(tr)
      v=e.get_attribute(DICT,'global_x_m',nil);e.set_attribute(DICT,'global_x_m',v.to_f+sp['dx']) unless v.nil?
      v=e.get_attribute(DICT,'global_y_m',nil);e.set_attribute(DICT,'global_y_m',v.to_f+sp['dy']) unless v.nil?
    end
    sp['visuals'].each{|g|g.transform!(tr)}
    (sp['containers']||[]).each{|g|g.transform!(tr) if g.valid?}
  end
  moved
end

def project_ano_axis_manager
  model=Sketchup.active_model
  project=model.get_attribute(DICT,'project_name','').to_s
  system=model.get_attribute(DICT,'project_system_type','ISKELE').to_s.upcase
  system='ISKELE' unless %w[RIHTIM DOLFEN ISKELE].include?(system)

  systems={}
  grids={}
  %w[DOLFEN ISKELE RIHTIM].each do |sys|
    rows=mst_structures_for_system(sys,model)
    rows=[mst_default_structure_name(sys,1)] if rows.empty?
    systems[sys]=rows
    rows.each do |name|
      g=mst_axis_grid_for(name,model,name)
      grids["#{sys}::#{name}"]=g
    end
  end
  active={}
  %w[DOLFEN ISKELE RIHTIM].each do |sys|
    cur=model.get_attribute(DICT,"active_structure__#{sys}",'').to_s
    cur=systems[sys].first unless systems[sys].include?(cur)
    active[sys]=cur
  end
  active[system]=systems[system].first unless systems[system].include?(active[system])

  placements=mst_structure_placements(model)
  # ADR-0515-I: görünen adlar (aks satırında 'display'; kayıtta mst_normalize_axis_rows bu alanı atar) ve C seçeneği kilitleri
  snames=mst_structure_display_names(model);anames=mst_axis_display_names(model);usage=mst_code_usage(model)
  locks={'structures'=>{},'axes'=>{}}
  systems.each do |sys,rows|
    rows.each do |name|
      k="#{sys}::#{name}";g=grids[k]
      %w[x y].each{|dd|Array(g[dd]).each{|r|dv=mst_axis_display(name,name,dd,r['name'],anames);r['display']=(dv==r['name'].to_s ? '' : dv)}}
      msg=mst_structure_code_lock(sys,name,usage,model,placements);locks['structures'][k]=msg if msg
      locks['axes'][k]=mst_axis_code_locks(sys,name,g,usage,placements)
    end
  end
  js_names=JSON.generate(snames).gsub('</','<\\/')
  js_locks=JSON.generate(locks).gsub('</','<\\/')
  js_systems=JSON.generate(systems).gsub('</','<\\/')
  js_grids=JSON.generate(grids).gsub('</','<\\/')
  js_active=JSON.generate(active).gsub('</','<\\/')
  js_places=JSON.generate(placements).gsub('</','<\\/')

  html=%Q{<!doctype html><html><head><meta charset='utf-8'><style>
*{box-sizing:border-box}body{font-family:Arial,sans-serif;margin:0;background:#f3f7fa;color:#17384d}.top{background:#fff;border-bottom:1px solid #cbdde8;padding:15px 20px;display:flex;justify-content:space-between;align-items:center}.top h2{margin:0;color:#073f73}.badge{padding:7px 12px;border-radius:18px;background:#e7f4ff;color:#0874c9;font-weight:700;font-size:11px}.wrap{padding:14px}.card{background:#fff;border:1px solid #cbdde8;border-radius:9px;padding:13px;margin-bottom:12px}.row{display:grid;grid-template-columns:1.4fr .8fr 1fr auto;gap:9px;align-items:end}.row2{display:grid;grid-template-columns:1fr 1fr;gap:12px}.axisbox{border:1px solid #d7e5ed;border-radius:8px;padding:10px;background:#fbfdfe;overflow-x:auto}.axisbox table{min-width:910px}.axisbox th:nth-child(1){min-width:90px}.axisbox th:nth-child(2){min-width:120px}.axisbox th:nth-child(3){min-width:145px}.axisbox th:nth-child(4){min-width:145px}.axisbox th:nth-child(5){min-width:112px}.axisbox th:nth-child(6){min-width:120px}.axisbox th:nth-child(7){min-width:105px}.axisbox th:nth-child(8){min-width:105px}.axisbox td:nth-child(5) select{min-width:105px}.axisbox td:nth-child(6) select{min-width:112px}.axisbox td:nth-child(7) select{min-width:98px}.axisbox td:nth-child(8) select{min-width:98px}label{font-size:11px;font-weight:700;color:#42677f}input,select{width:100%;padding:8px;border:1px solid #bfd2df;border-radius:6px;margin-top:5px;background:#fff}button{padding:9px 13px;border:0;border-radius:6px;background:#087fd1;color:#fff;font-weight:700;cursor:pointer}.secondary{background:#5c7485}.danger{background:#b94a48}.green{background:#16834f}.sm{padding:6px 8px;font-size:10px}.actions{display:flex;gap:6px;flex-wrap:wrap}table{width:100%;border-collapse:collapse}th,td{font-size:11px;padding:7px;border-bottom:1px solid #e3edf3;text-align:left}th{background:#eaf3f8;color:#42677f}.toolbar{display:grid;grid-template-columns:1fr 90px 110px auto;gap:6px;align-items:end;margin-top:10px}.readonly{background:#eef4f7;font-weight:700}.status{margin-top:8px;font-size:11px;color:#16834f;font-weight:700}.chain{font-weight:700;color:#075d91;padding:9px;background:#eef8fe;border-radius:7px}.placement{display:grid;grid-template-columns:1fr 1fr 1fr 1fr 1fr 110px 90px;gap:7px;align-items:end;margin-top:9px}.muted{font-size:10px;color:#6c8494}.titleline{display:flex;justify-content:space-between;align-items:center}.titleline h3{margin:0}.warn{color:#a04a00}
</style></head><body>
<div class='top'><div><h2>Proje / Sistem / Yapı — Aks Yöneticisi</h2><div>Temiz aks motoru: Sistemler birbirinden bağımsızdır.</div></div><span class='badge'>v#{VERSION}</span></div>
<div class='wrap'>
<div class='card'><div class='row'><label>Proje Adı<input id='project' value='#{html_escape(project)}'></label><label>Sistem<select id='system'><option value='DOLFEN'>DOLFEN</option><option value='ISKELE'>İSKELE</option><option value='RIHTIM'>RIHTIM</option></select></label><label>Aktif Yapı<select id='structure'></select></label><button id='saveAll'>Projeyi Kaydet</button></div><div class='row' style='grid-template-columns:1.4fr 1fr 2fr;margin-top:9px'><label>Görünen Ad (aktif yapı)<input id='structName' maxlength='40' placeholder='Boş bırakılırsa kod gösterilir'></label><label>Kod<input id='structCode' maxlength='40' class='readonly' readonly></label><div id='codeNote' class='muted' style='align-self:center'></div></div><div class='row' style='grid-template-columns:1fr 1.4fr auto auto;margin-top:9px'><label>Yeni Yapı Kodu<input id='newStructure' maxlength='40'></label><label>Yeni Yapı Görünen Ad<input id='newStructureName' maxlength='40' placeholder='İsteğe bağlı'></label><button id='addStructure'>+ Yeni Yapı</button><div class='actions'><button id='copyStructure' class='secondary'>Yapıyı Kopyala</button><button id='deleteStructure' class='danger'>Yapıyı Sil</button></div></div><div id='status' class='status'></div></div>
<div class='card'><div class='titleline'><h3>Yapı Yerleşim Zinciri</h3></div><div id='chain' class='chain'></div><table><thead><tr><th>Sıra</th><th>Yapı</th><th>X Konumu</th><th>Y Konumu</th><th>Global Başlangıç</th><th>Düzenle</th></tr></thead><tbody id='chainbody'></tbody></table>
<div style='display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px'>
<div class='axisbox'><h3>X KONUMU</h3><div class='placement' style='grid-template-columns:1fr 1fr 1fr 1fr 1fr 120px'><label>Konumlandırma<select id='xMode'><option value='INDEPENDENT'>Bağımsız (koordinat)</option><option value='SAME_SYSTEM'>Aynı sistemde bağla</option><option value='OTHER_SYSTEM'>Başka sisteme bağla</option></select></label><label>Referans Sistem<select id='xRefSystem'><option>DOLFEN</option><option value='ISKELE'>İSKELE</option><option>RIHTIM</option></select></label><label>Referans Yapı<select id='xRefStructure'></select></label><label>Referans X Aksı<select id='xRefAxis'></select></label><label>Bu Yapının X Aksı<select id='xTargetAxis'></select></label><label>Mesafe / Yön<div style='display:flex;gap:5px'><input id='xDistance' inputmode='decimal' value='0.00'><select id='xDirection' style='width:72px'><option>+X</option><option>-X</option></select></div></label></div><div class='muted' style='margin-top:6px'>Örnek: BD-01 / X-03 → +40.50 m → BD-02 / X-04</div></div>
<div class='axisbox'><h3>Y KONUMU</h3><div class='placement' style='grid-template-columns:1fr 1fr 1fr 1fr 1fr 120px'><label>Konumlandırma<select id='yMode'><option value='INDEPENDENT'>Bağımsız (koordinat)</option><option value='SAME_SYSTEM'>Aynı sistemde bağla</option><option value='OTHER_SYSTEM'>Başka sisteme bağla</option></select></label><label>Referans Sistem<select id='yRefSystem'><option>DOLFEN</option><option value='ISKELE'>İSKELE</option><option>RIHTIM</option></select></label><label>Referans Yapı<select id='yRefStructure'></select></label><label>Referans Y Aksı<select id='yRefAxis'></select></label><label>Bu Yapının Y Aksı<select id='yTargetAxis'></select></label><label>Mesafe / Yön<div style='display:flex;gap:5px'><input id='yDistance' inputmode='decimal' value='0.00'><select id='yDirection' style='width:72px'><option>+Y</option><option>-Y</option></select></div></label></div><div class='muted' style='margin-top:6px'>Aynı hat için mesafe 0.00 olabilir: BD-02 / F → 0.00 m → YD-01 / F.</div></div>
</div><div class='actions' style='margin-top:9px'><button id='savePlacement' class='green'>X + Y Konumunu Kaydet</button><button id='independent' class='secondary' title='Bağlantıyı kopar, yapı bulunduğu yerde kalır; sonra Mesafe ile yeni koordinatı girin'>X + Y Bağımsız Yap (yerinde)</button></div></div>
<div class='card'><div class='titleline'><h3 id='axisTitle'>AKS SİSTEMİ</h3><div class='actions'><button id='showGrid' class='secondary'>Aksları Modelde Göster / Güncelle</button><button id='saveGrid'>Aks Sistemini Kaydet</button></div></div><div class='row2' style='margin-top:10px'>
<div class='axisbox'><h3>X Aksları</h3><table><thead><tr><th>Aks Kodu</th><th>Görünen Ad</th><th>Önceki Akstan Mesafe (m)</th><th>İlk Akstan Toplam (m)</th><th>Sınıf</th><th>Çizgi Tipi</th><th>Çizgi Kalınlığı</th><th>Uzanım</th><th></th></tr></thead><tbody id='xbody'></tbody></table><div style='display:grid;grid-template-columns:auto 170px;gap:8px;align-items:end;margin-top:7px'><button id='addX' class='sm'>+ X Aksı Ekle</button><label>Yerel X Yönü<select id='xLocalDir'><option value='+X'>+X</option><option value='-X'>-X</option></select></label></div><div class='toolbar'><label>Önek<input id='xprefix' value='X-'></label><label>Adet<input id='xcount' value='6'></label><label>Aralık (m)<input id='xspacing' value='5.60'></label><button id='genX' class='sm secondary'>Düzenli Oluştur</button></div></div>
<div class='axisbox'><h3>Y Aksları</h3><table><thead><tr><th>Aks Kodu</th><th>Görünen Ad</th><th>Önceki Akstan Mesafe (m)</th><th>İlk Akstan Toplam (m)</th><th>Sınıf</th><th>Çizgi Tipi</th><th>Çizgi Kalınlığı</th><th>Uzanım</th><th></th></tr></thead><tbody id='ybody'></tbody></table><div style='display:grid;grid-template-columns:auto 170px;gap:8px;align-items:end;margin-top:7px'><button id='addY' class='sm'>+ Y Aksı Ekle</button><label>Yerel Y Yönü<select id='yLocalDir'><option value='+Y'>+Y</option><option value='-Y'>-Y</option></select></label></div><div class='toolbar'><label>Önek<input id='yprefix' value=''></label><label>Adet<input id='ycount' value='3'></label><label>Aralık (m)<input id='yspacing' value='2.50'></label><button id='genY' class='sm secondary'>Düzenli Oluştur</button></div></div>
</div></div></div>
<script>
(function(){
'use strict';
var systems=#{js_systems};
var grids=#{js_grids};
var active=#{js_active};
var placements=#{js_places};
var currentSystem=#{JSON.generate(system)};
var currentStructure=active[currentSystem]||systems[currentSystem][0];
var names=#{js_names};
var locks=#{js_locks};
var codeChanges={};
var removedOk={};
var origCodes={},snap=null;
function el(id){return document.getElementById(id)}
function clean(s){s=String(s==null?'':s);if(s.normalize)s=s.normalize('NFC');return s.replace(/\\s+/g,' ').trim()}
function nkey(s){var u=clean(s);try{u=u.toLocaleUpperCase('tr-TR')}catch(e){u=u.toUpperCase()}return u.split(String.fromCharCode(304)).join('I')}
var BADCH=String.fromCharCode(92)+'/:*?"<>|';
function checkName(v,max,what){v=clean(v);if(!v)return '';if(v.length>max)throw new Error(what+': en fazla '+max+' karakter olabilir ('+v.length+' karakter).');for(var i=0;i<v.length;i++){var c=v.charCodeAt(i);if(c<32||c===127||BADCH.indexOf(v.charAt(i))>=0)throw new Error(what+': '+BADCH+' ve denetim karakterleri kullanılamaz. Kullanılabilir: harf, rakam, boşluk ve - _ . ( ) # + &')}return v}
var CODECH=' -_.';
function checkCode(v,max,what){v=clean(v);if(!v)return '';if(v.length>max)throw new Error(what+': en fazla '+max+' karakter olabilir ('+v.length+' karakter).');for(var i=0;i<v.length;i++){var ch=v.charAt(i);if(!(CODECH.indexOf(ch)>=0||(ch>='0'&&ch<='9')||ch.toLowerCase()!==ch.toUpperCase()))throw new Error(what+': izin verilmeyen karakter ("'+ch+'"). Kod için kullanılabilir: harf, rakam, boşluk ve - _ .')}return v}
function disp(n){var v=names[n];return (v&&clean(v))?v:n}
function label(n){var d=disp(n);return d===n?n:d+' ('+n+')'}
function axLabel(r){return (r.display&&clean(r.display)&&r.display!==r.name)?r.display+' ('+r.name+')':r.name}
function allCodes(){var a=[];Object.keys(systems).forEach(function(s){systems[s].forEach(function(c){a.push(c)})});return a}
function nextCode(sys){var pre=defaultStructure(sys,1).replace(/\\d+$/,''),mx=0;allCodes().forEach(function(c){var t=String(c).trim();if(t.toUpperCase().indexOf(pre.toUpperCase())===0){var rest=t.slice(pre.length);if(/^\\d+$/.test(rest))mx=Math.max(mx,parseInt(rest,10))}});return defaultStructure(sys,mx+1)}
function origOf(sys,code){var ks=Object.keys(codeChanges);for(var i=0;i<ks.length;i++){if(ks[i].indexOf(sys+'::')===0&&codeChanges[ks[i]]===code)return ks[i].slice(sys.length+2)}return code}
function placementRefs(sys,code){var out=[];Object.keys(placements).forEach(function(k){if(k===key(sys,code))return;var p=placements[k]||{};[p.x_link,p.y_link].forEach(function(ln){if(ln&&ln.mode!=='ABSOLUTE'&&ln.ref_structure===code)out.push(k.split('::').slice(1).join('::'))})});return out}
function structLock(sys,code){var m=locks.structures[key(sys,origOf(sys,code))];if(m)return m;var r=placementRefs(sys,code);return r.length?'Kod değiştirilemez: yerleşim bağlantısı ('+r.join(', ')+') bu koda bağlı.':''}
function axisLock(d,code){var a=locks.axes[key(currentSystem,currentStructure)]||{},m=(a[d]||{})[code];if(m)return m;var F=d.toUpperCase(),refs=[];Object.keys(placements).forEach(function(k){var p=placements[k]||{},ln=F==='X'?p.x_link:p.y_link;if(!ln||ln.mode==='ABSOLUTE')return;if((k===key(currentSystem,currentStructure)&&ln.target_axis===code)||(ln.ref_structure===currentStructure&&ln.ref_axis===code))refs.push(k.split('::').slice(1).join('::'))});return refs.length?'Aks kodu değiştirilemez: yerleşim bağlantısı ('+refs.join(', ')+') bu aksa bağlı.':''}
function nameClash(v,own){var k=nkey(v),hit='';allCodes().forEach(function(c){if(c!==own&&nkey(c)===k)hit=c+' kodu'});Object.keys(names).forEach(function(c){if(c!==own&&names[c]&&nkey(names[c])===k)hit=c+' yapısının görünen adı'});return hit}
function axisDisplaySnap(){var o={};Object.keys(grids).forEach(function(k){var g=grids[k]||{};o[k]={x:{},y:{}};['x','y'].forEach(function(d){(g[d]||[]).forEach(function(r){if(r.display)o[k][d][r.name]=r.display})})});return o}
function takeSnap(){snap={names:JSON.parse(JSON.stringify(names)),axes:axisDisplaySnap()};origCodes={};Object.keys(systems).forEach(function(s){origCodes[s]=systems[s].slice()})}
window.mstNamesSaved=function(){codeChanges={};removedOk={};takeSnap();renderIdentity()};
function dec(v){var n=parseFloat(String(v==null?'':v).replace(',','.'));return isFinite(n)?n:0}
function z2(n){return String(n).padStart(2,'0')}
function defaultStructure(sys,i){if(sys==='DOLFEN')return 'BD-'+z2(i);if(sys==='RIHTIM')return 'RIHTIM-'+z2(i);return 'ANO-'+z2(i)}
function key(sys,name){return sys+'::'+name}
function emptyGrid(){return {x:[{name:'X-01',gap_m:0,coord_m:0,line_type:'AXIS',pattern:'DASHED',lineweight:'0.005',extent:'FINITE'}],y:[{name:'A',gap_m:0,coord_m:0,line_type:'AXIS',pattern:'DASHED',lineweight:'0.005',extent:'FINITE'}],system_axis_x:'',system_axis_y:'',x_dir:'+X',y_dir:'+Y'}}
function grid(){var k=key(currentSystem,currentStructure);if(!grids[k])grids[k]=emptyGrid();return grids[k]}
function axisName(d,i){if(d==='x')return 'X-'+z2(i+1);var n=i+1,s='';while(n){n--;s=String.fromCharCode(65+n%26)+s;n=Math.floor(n/26)}return s}
function normalize(d){var a=grid()[d],t=0;a.forEach(function(r,i){r.gap_m=i?Math.max(0,dec(r.gap_m)):0;t+=r.gap_m;r.coord_m=t})}
function renderAxis(d){normalize(d);var b=el(d+'body');b.innerHTML='';grid()[d].forEach(function(r,i){
if(!r.line_type)r.line_type='AXIS';if(!r.pattern)r.pattern='DASHED';if(!r.lineweight)r.lineweight=(r.weight==='THICK'?'0.20':'0.005');if(!r.extent)r.extent='FINITE';
var tr=document.createElement('tr'),cells=[];for(var k=0;k<9;k++){cells[k]=document.createElement('td')}
var n=document.createElement('input'),lk=axisLock(d,r.name);n.value=r.name;if(lk){n.readOnly=true;n.className='readonly';n.title=lk}else{n.title='Kullanılmayan aks: kod değiştirilebilir.';n.addEventListener('change',function(){var v=clean(this.value),self=this;try{var l2=axisLock(d,r.name);if(l2)throw new Error(l2);v=checkCode(v,20,'Aks kodu');if(!v)throw new Error('Aks kodu boş olamaz.');grid()[d].forEach(function(q){if(q!==r&&(nkey(q.name)===nkey(v)||(q.display&&nkey(q.display)===nkey(v))))throw new Error(v+': aynı yönde başka bir aksın kodu / görünen adıyla çakışıyor.')})}catch(e){alert(e.message);self.value=r.name;return}r.name=v;if(r.display&&nkey(r.display)===nkey(v))r.display='';renderAxis(d);renderPlacementSelectors()})}cells[0].appendChild(n);
var dn=document.createElement('input');dn.maxLength=20;dn.value=r.display||'';dn.placeholder=r.name;dn.addEventListener('change',function(){var v,self=this;try{v=checkName(this.value,20,r.name+' aksı görünen adı');if(v)grid()[d].forEach(function(q){if(q!==r&&(nkey(q.name)===nkey(v)||(q.display&&nkey(q.display)===nkey(v))))throw new Error(r.name+': görünen ad aynı yöndeki '+q.name+' aksıyla çakışıyor.')})}catch(e){alert(e.message);self.value=r.display||'';return}if(v&&nkey(v)===nkey(r.name))v='';r.display=v;self.value=v;renderPlacementSelectors()});cells[1].appendChild(dn);
var gap=document.createElement('input');if(i===0){gap.value='—';gap.disabled=true;gap.className='readonly'}else{gap.value=Number(r.gap_m).toFixed(2);gap.inputMode='decimal';gap.addEventListener('change',function(){r.gap_m=Math.max(0,dec(this.value));renderAxis(d);renderPlacementSelectors()})}cells[2].appendChild(gap);
var c=document.createElement('input');c.value=Number(r.coord_m).toFixed(2);c.disabled=true;c.className='readonly';cells[3].appendChild(c);
function sel(opts,val,cb){var q=document.createElement('select');q.innerHTML=opts;q.value=val;q.addEventListener('change',cb);return q}
cells[4].appendChild(sel('<option value="AXIS">Aks</option><option value="SYSTEM">Sistem Aksı</option>',r.line_type,function(){r.line_type=this.value}));
cells[5].appendChild(sel('<option value="CONTINUOUS">Sürekli</option><option value="DASHED">Kesikli</option><option value="CENTER">Eksen</option><option value="DASHDOT">Kesik-Nokta</option><option value="SHORTDASH">Kısa Kesikli</option>',r.pattern,function(){r.pattern=this.value}));
cells[6].appendChild(sel('<option value="0.005">0.005 mm</option><option value="0.01">0.01 mm</option><option value="0.02">0.02 mm</option><option value="0.03">0.03 mm</option><option value="0.05">0.05 mm</option><option value="0.07">0.07 mm</option><option value="0.10">0.10 mm</option><option value="0.13">0.13 mm</option><option value="0.15">0.15 mm</option><option value="0.18">0.18 mm</option><option value="0.20">0.20 mm</option><option value="0.25">0.25 mm</option><option value="0.30">0.30 mm</option><option value="0.35">0.35 mm</option><option value="0.50">0.50 mm</option>',r.lineweight,function(){r.lineweight=this.value}));
cells[7].appendChild(sel('<option value="FINITE">Sonlu</option><option value="INFINITE">Sonsuz</option>',r.extent,function(){r.extent=this.value}));
if(i>0){var rm=document.createElement('button');rm.textContent='Sil';rm.className='sm danger';rm.addEventListener('click',function(){if(lk&&!confirm(lk+'\\n\\n'+r.name+' aksı yine de silinsin mi? Bağlı elemanların aks bağlantısı kopar (eleman verisi değişmez).'))return;grid()[d].splice(i,1);renderAxis(d);renderPlacementSelectors()});cells[8].appendChild(rm)}
cells.forEach(function(td){tr.appendChild(td)});b.appendChild(tr)})}
function renderPlacementSelectors(){renderAxisSelectors('X');renderAxisSelectors('Y');renderChain()}
function renderAxes(){el('axisTitle').textContent='AKS SİSTEMİ — '+label(currentStructure);renderAxis('x');renderAxis('y');el('xLocalDir').value=grid().x_dir||'+X';el('yLocalDir').value=grid().y_dir||'+Y'}
function axisTaken(d,v){return grid()[d].some(function(q){return nkey(q.name)===nkey(v)||(q.display&&nkey(q.display)===nkey(v))})}
function addAxis(d){var i=grid()[d].length;while(axisTaken(d,axisName(d,i)))i++;grid()[d].push({name:axisName(d,i),display:'',gap_m:0,coord_m:0,line_type:'AXIS',pattern:'DASHED',lineweight:'0.005',extent:'FINITE'});renderAxis(d);renderPlacementSelectors();status('+ '+d.toUpperCase()+' aksı eklendi: '+axisName(d,i))}
function generate(d){var count=Math.max(1,parseInt(el(d+'count').value,10)||1),sp=Math.max(0,dec(el(d+'spacing').value)),pre=el(d+'prefix').value,a=[],old=grid()[d];for(var i=0;i<count;i++){var nm=(d==='y'&&!pre)?axisName('y',i):pre+z2(i+1),prev=old.filter(function(q){return q.name===nm})[0];a.push({name:nm,display:prev?(prev.display||''):'',gap_m:i?sp:0,coord_m:i*sp,line_type:'AXIS',pattern:'DASHED',lineweight:'0.005',extent:'FINITE'})}
var used=old.filter(function(q){return axisLock(d,q.name)}),lost=used.filter(function(q){return !a.some(function(z){return z.name===q.name})});
if(used.length){var t='Düzenli Oluştur — önizleme\\n\\n'+label(currentStructure)+' / '+d.toUpperCase()+' aksları: '+old.length+' aks → '+a.length+' aks ('+a.map(function(q){return q.name}).join(', ')+').\\nKullanılan akslar: '+used.map(function(q){return q.name}).join(', ')+'.\\n'+(lost.length?'Kaldırılacak kullanılan akslar: '+lost.map(function(q){return q.name}).join(', ')+' — bağlı elemanların aks bağlantısı kopar (eleman verisi değişmez).\\n':'Kullanılan aks kodları korunur; koordinat değişirse kayıtta bağlı elemanlar için ayrıca önizleme gösterilir.\\n')+'Aynı koddaki görünen adlar korunur.\\n\\nDevam edilsin mi?';if(!confirm(t)){status('Düzenli Oluştur iptal edildi.');return}}
grid()[d]=a;renderAxis(d);renderPlacementSelectors()}
function renderIdentity(){var c=currentStructure,isNew=(origCodes[currentSystem]||[]).indexOf(origOf(currentSystem,c))<0,lk=structLock(currentSystem,c),code=el('structCode');el('structName').value=names[c]||'';code.value=c;code.readOnly=!!lk;code.className=lk?'readonly':'';code.title=lk||'';el('codeNote').textContent=lk?lk:(isNew?'Yeni yapı: kod kayıttan önce değiştirilebilir.':'Kod değiştirilebilir: bu yapıya bağlı eleman, aks görseli, bölge verisi veya yerleşim bağlantısı yok.')}
function renderStructureSelect(){var s=el('structure');s.innerHTML='';systems[currentSystem].forEach(function(n){var o=document.createElement('option');o.value=n;o.textContent=label(n);s.appendChild(o)});if(!systems[currentSystem].includes(currentStructure))currentStructure=systems[currentSystem][0];s.value=currentStructure;active[currentSystem]=currentStructure;el('newStructure').value=nextCode(currentSystem);el('newStructureName').value='';renderIdentity();renderAxes();renderChain();loadPlacement()}
function switchSystem(){currentSystem=el('system').value;currentStructure=active[currentSystem]||systems[currentSystem][0];renderStructureSelect();status(currentSystem+' sistemi aktif.')}
function switchStructure(){currentStructure=el('structure').value;active[currentSystem]=currentStructure;renderIdentity();renderAxes();renderChain();loadPlacement()}
function setStructName(){var c=currentStructure,v;try{v=checkName(el('structName').value,40,'Görünen ad');var h=v?nameClash(v,c):'';if(h)throw new Error('"'+v+'" görünen adı '+h+' ile çakışıyor (büyük / küçük harf ve I / İ ayrımı yapılmaz).')}catch(e){alert(e.message);el('structName').value=names[c]||'';return}if(!v||nkey(v)===nkey(c))delete names[c];else names[c]=v;renderStructureSelect();status(names[c]?c+' görünen adı: '+v+' (Projeyi Kaydet ile modele yazılır).':c+' görünen adı temizlendi; kod gösterilir.')}
function setStructCode(){var o=currentStructure,v,sys=currentSystem;if(el('structCode').readOnly)return;try{v=checkCode(el('structCode').value,40,'Yapı kodu');if(!v)throw new Error('Yapı kodu boş olamaz.');if(v===o)return;var h=nameClash(v,o);if(h)throw new Error(v+': '+h+' ile çakışıyor (büyük / küçük harf ve I / İ ayrımı yapılmaz).');var org0=origOf(sys,o);Object.keys(origCodes).forEach(function(s){(origCodes[s]||[]).forEach(function(c){if(c!==org0&&nkey(c)===nkey(v))throw new Error(v+': hedef kod kullanılamaz — bu kod modelde kayıtlı bir yapıya ait (bu kayıtta silinmiş olsa da bağlı verisi kalır).')})});var lk=structLock(sys,o);if(lk)throw new Error(lk)}catch(e){alert(e.message);el('structCode').value=o;return}
var a=systems[sys];a[a.indexOf(o)]=v;grids[key(sys,v)]=grids[key(sys,o)];delete grids[key(sys,o)];if(placements[key(sys,o)]){placements[key(sys,v)]=placements[key(sys,o)];delete placements[key(sys,o)]}if(locks.axes[key(sys,o)]){locks.axes[key(sys,v)]=locks.axes[key(sys,o)];delete locks.axes[key(sys,o)]}if(names[o]){names[v]=names[o];delete names[o]}if(names[v]&&nkey(names[v])===nkey(v))delete names[v];
var org=origOf(sys,o);if((origCodes[sys]||[]).indexOf(org)>=0){if(v===org)delete codeChanges[key(sys,org)];else codeChanges[key(sys,org)]=v}currentStructure=v;active[sys]=v;renderStructureSelect();status('Kod '+o+' → '+v+' (Projeyi Kaydet ile modele yazılır; eleman verisi değişmez).')}
function addStructure(copy){var n,nm,h;try{n=checkCode(el('newStructure').value,40,'Yeni yapı kodu');if(!n)throw new Error('Yeni yapı kodunu girin.');h=nameClash(n,null);if(h)throw new Error(n+': '+h+' ile çakışıyor (büyük / küçük harf ve I / İ ayrımı yapılmaz).');nm=checkName(el('newStructureName').value,40,'Yeni yapı görünen adı');h=nm?nameClash(nm,null):'';if(h)throw new Error('"'+nm+'" görünen adı '+h+' ile çakışıyor.')}catch(e){alert(e.message);return}systems[currentSystem].push(n);if(nm&&nkey(nm)!==nkey(n))names[n]=nm;grids[key(currentSystem,n)]=copy?JSON.parse(JSON.stringify(grid())):emptyGrid();currentStructure=n;active[currentSystem]=n;renderStructureSelect();status(label(n)+' oluşturuldu.')}
function deleteStructure(){if(systems[currentSystem].length<=1){alert('En az bir yapı kalmalıdır.');return}var lk=locks.structures[key(currentSystem,origOf(currentSystem,currentStructure))];if(!confirm(label(currentStructure)+' silinsin mi?'+(lk?'\\n\\nUyarı — '+lk:'')))return;if(lk)removedOk[key(currentSystem,origOf(currentSystem,currentStructure))]=true;var i=systems[currentSystem].indexOf(currentStructure);systems[currentSystem].splice(i,1);delete grids[key(currentSystem,currentStructure)];delete placements[key(currentSystem,currentStructure)];delete names[currentStructure];delete codeChanges[key(currentSystem,origOf(currentSystem,currentStructure))];currentStructure=systems[currentSystem][Math.max(0,i-1)];active[currentSystem]=currentStructure;renderStructureSelect()}
function placement(){var k=key(currentSystem,currentStructure),p=placements[k];if(!p)p={};if(!('x_link' in p)&&!('y_link' in p)&&p.mode&&p.mode!=='INDEPENDENT'){var fam=(p.axis_family||'X').toUpperCase(),ln={mode:p.mode,ref_system:p.ref_system||'',ref_structure:p.ref_structure||'',ref_axis:p.ref_axis||'',target_axis:p.target_axis||'',distance_m:Number(p.distance_m||0),direction:p.direction||(fam==='X'?'+X':'+Y')};p={x_link:fam==='X'?ln:null,y_link:fam==='Y'?ln:null};placements[k]=p}if(!('x_link' in p))p.x_link=null;if(!('y_link' in p))p.y_link=null;return p}
function localAxisCoord(sys,name,fam,axis){var g=grids[key(sys,name)]||emptyGrid(),a=g[String(fam||'X').toLowerCase()]||[];for(var i=0;i<a.length;i++){if(a[i].name===axis){var sg=fam==='X'?(g.x_dir==='-X'?-1:1):(g.y_dir==='-Y'?-1:1);return sg*Number(a[i].coord_m||0)}}throw new Error(name+' / '+axis+' aksı bulunamadı.')}
function originComponent(sys,name,fam,trail){trail=trail||[];var token=key(sys,name)+'::'+fam;if(trail.indexOf(token)>=0)throw new Error('Yapı bağlantı döngüsü: '+name+' / '+fam);var p=placements[key(sys,name)]||{},ln=fam==='X'?p.x_link:p.y_link;if(!ln)return 0;if(ln.mode==='ABSOLUTE')return Number(ln.coord_m||0);var rs=ln.mode==='SAME_SYSTEM'?sys:(ln.ref_system||sys),rn=ln.ref_structure;if(!rn)throw new Error(name+' / '+fam+' için referans yapı seçilmedi.');var ro=originComponent(rs,rn,fam,trail.concat([token])),rc=localAxisCoord(rs,rn,fam,ln.ref_axis),tc=localAxisCoord(sys,name,fam,ln.target_axis),dist=Number(ln.distance_m||0),sgn=ln.direction==='-'+fam?-1:1;return ro+rc+sgn*dist-tc}
function structureOrigin(sys,name){return [originComponent(sys,name,'X',[]),originComponent(sys,name,'Y',[])]}
function moveStructure(i,delta){var a=systems[currentSystem],j=i+delta;if(j<0||j>=a.length)return;var t=a[i];a[i]=a[j];a[j]=t;renderChain();status('Görünüm sırası değiştirildi. Geometrik bağlantı değişmedi.')}
function editStructure(n){currentStructure=n;active[currentSystem]=n;el('structure').value=n;renderIdentity();renderAxes();loadPlacement();status(n+' düzenleniyor.')}
function linkText(ln,fam){if(!ln)return 'Bağımsız '+fam+'=0';if(ln.mode==='ABSOLUTE')return 'Bağımsız '+fam+'='+Number(ln.coord_m||0).toFixed(2);var rs=ln.mode==='SAME_SYSTEM'?currentSystem:(ln.ref_system||currentSystem);return rs+' / '+label(ln.ref_structure||'')+' / '+(ln.ref_axis||'')+' → '+Number(ln.distance_m||0).toFixed(2)+' m '+(ln.direction||'')+' → '+(ln.target_axis||'')}
function renderChain(){el('chain').textContent=systems[currentSystem].map(label).join('  →  ');var b=el('chainbody');b.innerHTML='';systems[currentSystem].forEach(function(n,i){var p=placements[key(currentSystem,n)]||{},tr=document.createElement('tr'),origin='—';try{var o=structureOrigin(currentSystem,n);origin='X='+o[0].toFixed(2)+' / Y='+o[1].toFixed(2)+' m'}catch(e){origin='HATA: '+e.message}tr.innerHTML='<td>'+(i+1)+'</td><td><b></b></td><td>'+linkText(p.x_link,'X')+'</td><td>'+linkText(p.y_link,'Y')+'</td><td>'+origin+'</td><td><button class="sm secondary" data-act="up">↑</button> <button class="sm secondary" data-act="down">↓</button> <button class="sm" data-act="edit">⚙</button></td>';tr.querySelector('b').textContent=label(n);tr.querySelector('[data-act=up]').onclick=function(){moveStructure(i,-1)};tr.querySelector('[data-act=down]').onclick=function(){moveStructure(i,1)};tr.querySelector('[data-act=edit]').onclick=function(){editStructure(n)};b.appendChild(tr)})}
function mstIndependentAtCurrent(fam){var f=fam.toLowerCase(),o=[0,0];try{o=structureOrigin(currentSystem,currentStructure)}catch(e){}var v=fam==='X'?o[0]:o[1];el(f+'Distance').value=Math.abs(v).toFixed(2);el(f+'Direction').value=(v<0?'-':'+')+fam}
function mstIndependentUi(fam){var f=fam.toLowerCase(),ind=el(f+'Mode').value==='INDEPENDENT';[f+'RefStructure',f+'RefAxis',f+'TargetAxis'].forEach(function(id){var e=el(id);if(e)e.disabled=ind});var d=el(f+'Distance');if(d)d.title=ind?'Bağımsız: yapının global başlangıç '+fam+' koordinatı (m); yön işareti uygulanır':'Referans akstan mesafe (m)'}
function renderLinkSelectors(fam){var f=fam.toLowerCase(),mode=el(f+'Mode').value,rs=mode==='SAME_SYSTEM'?currentSystem:el(f+'RefSystem').value;el(f+'RefSystem').disabled=mode!=='OTHER_SYSTEM';if(mode==='SAME_SYSTEM')el(f+'RefSystem').value=currentSystem;var s=el(f+'RefStructure'),old=s.value;s.innerHTML='';(systems[rs]||[]).forEach(function(n){if(!(rs===currentSystem&&n===currentStructure)){var o=document.createElement('option');o.value=n;o.textContent=label(n);s.appendChild(o)}});if([].some.call(s.options,function(o){return o.value===old}))s.value=old;renderAxisSelectors(fam);mstIndependentUi(fam)}
function renderAxisSelectors(fam){var f=fam.toLowerCase(),mode=el(f+'Mode').value,rs=mode==='SAME_SYSTEM'?currentSystem:el(f+'RefSystem').value,rn=el(f+'RefStructure').value,rg=grids[key(rs,rn)]||emptyGrid(),tg=grid(),ra=el(f+'RefAxis'),ta=el(f+'TargetAxis'),oldr=ra.value,oldt=ta.value;ra.innerHTML='';ta.innerHTML='';(rg[f]||[]).forEach(function(r){var o=document.createElement('option');o.value=r.name;o.textContent=axLabel(r);ra.appendChild(o)});(tg[f]||[]).forEach(function(r){var o=document.createElement('option');o.value=r.name;o.textContent=axLabel(r);ta.appendChild(o)});if([].some.call(ra.options,function(o){return o.value===oldr}))ra.value=oldr;if([].some.call(ta.options,function(o){return o.value===oldt}))ta.value=oldt}
function loadOneLink(fam,ln){var f=fam.toLowerCase(),abs=!!(ln&&ln.mode==='ABSOLUTE');el(f+'Mode').value=(ln&&!abs)?ln.mode:'INDEPENDENT';el(f+'RefSystem').value=(ln&&!abs)?(ln.ref_system||currentSystem):currentSystem;el(f+'Distance').value=abs?Math.abs(Number(ln.coord_m||0)).toFixed(2):(ln?Number(ln.distance_m||0).toFixed(2):'0.00');el(f+'Direction').value=abs?(Number(ln.coord_m)<0?'-'+fam:'+'+fam):(ln?(ln.direction||('+'+fam)):('+'+fam));renderLinkSelectors(fam);if(ln&&ln.ref_structure)el(f+'RefStructure').value=ln.ref_structure;renderAxisSelectors(fam);if(ln&&ln.ref_axis)el(f+'RefAxis').value=ln.ref_axis;if(ln&&ln.target_axis)el(f+'TargetAxis').value=ln.target_axis}
function loadPlacement(){var p=placement();loadOneLink('X',p.x_link);loadOneLink('Y',p.y_link)}
function readLink(fam){var f=fam.toLowerCase(),mode=el(f+'Mode').value;if(mode==='INDEPENDENT'){var cv=dec(el(f+'Distance').value)*(el(f+'Direction').value==='-'+fam?-1:1);return Math.abs(cv)<1e-9?null:{mode:'ABSOLUTE',coord_m:cv};}var rs=mode==='SAME_SYSTEM'?currentSystem:el(f+'RefSystem').value,ln={mode:mode,ref_system:rs,ref_structure:el(f+'RefStructure').value,ref_axis:el(f+'RefAxis').value,target_axis:el(f+'TargetAxis').value,distance_m:Math.max(0,dec(el(f+'Distance').value)),direction:el(f+'Direction').value};if(!ln.ref_structure||!ln.ref_axis||!ln.target_axis)throw new Error(fam+' konumu için referans yapı ve aksları seçin.');return ln}
function savePlacement(){var old=placements[key(currentSystem,currentStructure)];try{placements[key(currentSystem,currentStructure)]={x_link:readLink('X'),y_link:readLink('Y')};structureOrigin(currentSystem,currentStructure);renderChain();status('X + Y konumu kaydedildi. Projeyi Kaydet ile modele yazın.')}catch(e){if(old)placements[key(currentSystem,currentStructure)]=old;else delete placements[key(currentSystem,currentStructure)];alert(e.message)}}
function codeChangeList(){return Object.keys(codeChanges).map(function(k){var p=k.split('::');return {system:p[0],from:p.slice(1).join('::'),to:codeChanges[k]}})}
function removedUsed(){var o=[];Object.keys(systems).forEach(function(s){systems[s].forEach(function(c){var la=locks.axes[key(s,c)]||{},g=grids[key(s,c)]||{};['x','y'].forEach(function(d){Object.keys(la[d]||{}).forEach(function(q){if(!(g[d]||[]).some(function(r){return r.name===q}))o.push(key(s,c)+'::'+d+'::'+q)})})})});return o}
function payload(){return {project:el('project').value,system:currentSystem,systems:systems,active:active,grids:grids,placements:placements,structure_names:names,code_changes:codeChangeList(),removed_used_axes:removedUsed(),removed_used_structures:Object.keys(removedOk)}}
function previewText(){var L=[],cur=axisDisplaySnap(),seen={},sh=function(v){return v?'"'+v+'"':'(ad yok)'};codeChangeList().forEach(function(c){L.push('Kod: '+c.from+' → '+c.to+' ('+c.system+'; bağlı eleman yok)')});
Object.keys(systems).forEach(function(s){systems[s].forEach(function(c){var o=origOf(s,c),b=snap.names[o]||'',a=names[c]||'';seen[o]=true;if(b!==a)L.push('Yapı '+c+': '+sh(b)+' → '+sh(a));var bk=snap.axes[key(s,o)]||{x:{},y:{}},ak=cur[key(s,c)]||{x:{},y:{}};['x','y'].forEach(function(d){var u={};Object.keys(bk[d]||{}).concat(Object.keys(ak[d]||{})).forEach(function(q){if(u[q])return;u[q]=true;var x1=(bk[d]||{})[q]||'',x2=(ak[d]||{})[q]||'';if(x1!==x2)L.push('Aks '+c+' / '+q+': '+sh(x1)+' → '+sh(x2))})});var la=locks.axes[key(s,c)]||{},g=grids[key(s,c)]||{};['x','y'].forEach(function(d){Object.keys(la[d]||{}).forEach(function(q){if(!(g[d]||[]).some(function(r){return r.name===q}))L.push('Kaldırılan kullanılan aks: '+c+' / '+q+' — '+la[d][q])})})})});
Object.keys(snap.names).forEach(function(o){if(!seen[o])L.push('Yapı '+o+' silindi: görünen ad kaydı '+sh(snap.names[o])+' de silinir.')});
if(!L.length)return '';var more=L.length>25?'\\n… '+(L.length-25)+' satır daha':'';return 'Kayıt önizlemesi — görünen ad / kod\\n\\n'+L.slice(0,25).join('\\n')+more+'\\n\\nEleman verisi değişmez: kod, ano, aks ve kimlik öznitelikleri aynı kalır; görünen ad değişikliği revizyon kaydı oluşturmaz.\\n\\nKaydedilsin mi?'}
function saveAll(show){var t=previewText();if(t&&!confirm(t)){status('Kaydetme iptal edildi; hiçbir şey değişmedi.');return false}sketchup.axis_manager_v2_save(JSON.stringify(payload()));if(show)status('Kaydediliyor...');return true}
function showGrid(){if(saveAll(false)===false)return;sketchup.axis_manager_v2_show(JSON.stringify({system:currentSystem,structure:currentStructure}))}
function status(t){el('status').textContent=t}
function bind(){takeSnap();el('system').value=currentSystem;el('system').addEventListener('change',switchSystem);el('structName').addEventListener('change',setStructName);el('structCode').addEventListener('change',setStructCode);el('structure').addEventListener('change',switchStructure);el('addStructure').addEventListener('click',function(){addStructure(false)});el('copyStructure').addEventListener('click',function(){addStructure(true)});el('deleteStructure').addEventListener('click',deleteStructure);el('addX').addEventListener('click',function(){addAxis('x')});el('addY').addEventListener('click',function(){addAxis('y')});el('xLocalDir').addEventListener('change',function(){grid().x_dir=this.value;renderChain();status('Yerel X yönü: '+this.value)});el('yLocalDir').addEventListener('change',function(){grid().y_dir=this.value;renderChain();status('Yerel Y yönü: '+this.value)});el('genX').addEventListener('click',function(){generate('x')});el('genY').addEventListener('click',function(){generate('y')});el('saveGrid').addEventListener('click',function(){saveAll(true)});el('saveAll').addEventListener('click',function(){saveAll(true)});el('showGrid').addEventListener('click',showGrid);['X','Y'].forEach(function(fam){var f=fam.toLowerCase();el(f+'Mode').addEventListener('change',function(){if(this.value==='INDEPENDENT')mstIndependentAtCurrent(fam);renderLinkSelectors(fam)});el(f+'RefSystem').addEventListener('change',function(){renderLinkSelectors(fam)});el(f+'RefStructure').addEventListener('change',function(){renderAxisSelectors(fam)})});el('savePlacement').addEventListener('click',savePlacement);el('independent').addEventListener('click',function(){['X','Y'].forEach(function(fam){el(fam.toLowerCase()+'Mode').value='INDEPENDENT';mstIndependentAtCurrent(fam);renderLinkSelectors(fam)});savePlacement()});renderStructureSelect();status('Hazır — '+currentSystem+' / '+label(currentStructure))}
window.addEventListener('error',function(e){status('JS HATASI: '+e.message)});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',bind);else bind();
})();
</script></body></html>}

  d=mst_html_dialog('project_manager',dialog_title:'Proje / ANO / Aks Sistemi',width:1420,height:900,resizable:true)
  d.set_html(html)
  d.add_action_callback('axis_manager_v2_save') do |_ctx,json|
    begin
      x=JSON.parse(json)
      nplan=mst_axis_manager_names_plan(x,model)   # ADR-0515-I: görünen ad / kod doğrulaması işlem açılmadan
      mst_axis_manager_check_removed_axes!(x,model)   # G5b: kullanılan aks kodu onaysız kalkmaz (işlem açılmadan)
      # v0.38 R7: preview elements on moved axes before anything is saved.
      plans=mst_axis_move_plan_for_payload(x,model)
      splans=mst_structure_move_plans(x,model)   # v0.38 R8
      # G5a (NCR-003): değişiklik yoksa işlem açılmaz, yazım olmaz (boş Geri Al adımı yok)
      if plans.empty? && splans.empty? && nplan['writes'].empty? && nplan['changes'].empty? && mst_axis_manager_payload_changes(x,model).empty?
        d.execute_script("document.getElementById('status').textContent=#{JSON.generate('Değişiklik yok — model değişmedi, Geri Al adımı oluşmadı.')};if(window.mstNamesSaved)mstNamesSaved();") rescue nil
        next
      end
      decision=mst_axis_move_confirm(plans,splans)
      if decision==:cancel
        d.execute_script("document.getElementById('status').textContent='Kaydetme iptal edildi; hiçbir şey değişmedi.'") rescue nil
        next
      end
      moved=[0,0];moved_struct=0;redrawn=[]
      before=mst_grid_visual_snapshot(x,model)   # v0.38 BK2.3
      if decision==:move
        model.start_operation('MST Aks Değişikliği + Bağlı Kazık/BK',true)
        begin
          sys,cur=mst_axis_manager_save_payload(x,model)
          mst_axis_manager_apply_names!(nplan,model)
          moved=mst_apply_axis_move_plans(plans)
          moved_struct=mst_apply_structure_move_plans(splans)
          redrawn=mst_refresh_changed_grid_visuals(before,model)
          commit_with_dependencies(model);model.active_view.invalidate
        rescue Exception
          model.abort_operation
          raise
        end
      else
        model.start_operation('MST Aks Kaydı',true)
        begin
          sys,cur=mst_axis_manager_save_payload(x,model)
          mst_axis_manager_apply_names!(nplan,model)
          redrawn=mst_refresh_changed_grid_visuals(before,model)
          model.commit_operation;model.active_view.invalidate
        rescue Exception
          model.abort_operation
          raise
        end
      end
      note=moved[0]+moved[1]>0 ? " • #{moved[0]} kazık, #{moved[1]} BK#{moved[2].to_i>0 ? ", #{moved[2]} BK üstü eleman" : ''} taşındı (tek Geri Al)." : ''
      note+=" • Yapı taşındı: #{moved_struct} kazık (tek Geri Al)." if moved_struct>0
      nrz=decision==:move ? plans.sum{|pl|(pl['resizes']||[]).length} : 0
      note+=" • #{nrz} prekast yeni açıklığa göre boyutlandı." if nrz>0
      note+=" • Aks çizgileri güncellendi: #{redrawn.join(', ')}." unless redrawn.empty?
      d.execute_script("document.getElementById('status').textContent=#{JSON.generate("Kaydedildi — #{sys} / #{mst_structure_label(cur,nil,model)}#{note}")};if(window.mstNamesSaved)mstNamesSaved();") rescue nil
    rescue=>e
      UI.messagebox("Aks Yöneticisi kayıt hatası: #{e.message}")
    end
  end
  d.add_action_callback('axis_manager_v2_show') do |_ctx,json|
    begin
      x=JSON.parse(json); mst_show_grid_visual(x['structure'].to_s,model,x['structure'].to_s)
    rescue=>e
      UI.messagebox("Aks görseli hatası: #{e.message}")
    end
  end
  d.show
  @project_manager_dialog=d
end
# ===== end v0.34.28 =====

# ===== end v0.34.11 =====

require_relative 'pile_visual_geometry'
require_relative 'boq_pro'   # v0.47 BQ1 — en sonda: BOQ/hakediş fonksiyonlarını genişletir
require_relative 'mst_labels'   # v0.47.3 LB1 — kazık numaraları + numarayla bul
require_relative 'mst_dwg_rebar'   # v0.47.8 DR1 — proje çiziminden donatı (pozlar tek tek 3B)
require_relative 'mst_auto_rebar'   # v0.48 AR1 — otomatik donatı (kanal / duvar tanıma + kurallar)
require_relative 'mst_rebar_tools'  # v0.49 RT1 — donatı ayarları, göster / gizle, çap metrajı, bükme listesi, kesim, kesit, revizyon, çakışma
require_relative 'mst_schedule'     # v0.49 SP1 — iş programı
require_relative 'mst_dxf'          # v0.50 DX0 — DXF okuyucu
require_relative 'mst_v50_piles'    # v0.50 AF1 / KD1 / KF1 — A-çerçeve, DXF dispozisyon, filiz
require_relative 'mst_v50_beams'    # v0.50 VK1 / KD2 / TB1 / MF1 — VK-BBK, kademeli döküm, taban bölgesi, menfez
require_relative 'mst_pc_rebar'     # v0.50 PC2 — prekast donatısı
require_relative 'mst_dx_rebar'     # v0.50 DX1 — paftadan donatı metrajı
require_relative 'mst_dr_auto'      # v0.51 DR5 — paftadan 3B donatı (otomatik)
require_relative 'mst_v50_misc'     # v0.50 TP1 / SH2 / AN1 / MS1 / RS2

end
end
