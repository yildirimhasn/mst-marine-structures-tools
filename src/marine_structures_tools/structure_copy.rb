# frozen_string_literal: true
# ADR-0515-K1 (docs/duzeltme/31, 04.11.2026) — Aks Yöneticisi "Yapıyı Kopyala": aktif sistemdeki kaynak yapının tüm MST elemanları,
# aks ağı ve model düzeyi yapı kayıtları TEK işlemde (tek Geri Al) N kopya.
#  - Ön kontrol (mst_structure_copy_plan) salt okumadır (mst_plan_readonly); başarısızsa işlem açılmaz, "yapı / eleman / neden" listesi döner.
#  - Uygulama (mst_structure_copy_apply!) tek start_operation → N kopya → kayıtlar → son doğrulama (mst_structure_copy_verify) →
#    commit_with_dependencies. Herhangi bir hata / doğrulama hatasında abort_operation ve kaynak imzası yeniden okunur. Transparent işlem yok.
#  - Kopyalanmaz: aksesuar (bildirilir), dolgu, etiketler, aks görselleri (yeni ızgaradan mevcut işlevle yeniden çizilir), dependency_* kayıtları,
#    ilerleme kayıtları (progress_items_json, progress_inherited_*; durum 'Planlandı'). Tip anahtarları ve revizyon sayaçları aynen taşınır.
#  - Kimlik: yeni UID MST-<yeni pid>-<zaman>-C, uid_owner_pid = yeni PID, copied_from_uid = kaynak UID, copy_origin = 'structure_copy'
#    (yeni anahtar; eski modellerde yok, okuyan yok). Fiziksel ID mst_next_unique_physical_id ile model genelinde.
#  - Group kopyası Group#copy ile; iç öğelere yazmadan önce ayrılır (make_unique); MST sözlükleri açıkça kopyalanır. Component BK ayrılır
#    (mst_make_unique_keep_data!); diğer Component tanımları (kazık gövdesi, prekast) paylaşılır.
require 'json'
module MAG
module MarineStructuresTools

MST_SC_MAX=50
MST_SC_EXTRA_TYPES=%w[jet_grout].freeze   # collect_elements dışında kalan, yapıya ait kopyalanan kök öğe
MST_SC_SKIP_TYPES=%w[accessory axis_grid_visual structure_label model_scaled_text axis_emphasis system_axis_emphasis infinite_axis_reference axis_intersection mst_pile_template].freeze
MST_SC_PID_KEYS=%w[support_left_pid support_right_pid support_pids connected_pile_persistent_ids reference_pid].freeze
MST_SC_UID_KEYS=%w[support_left_uid support_right_uid support_uids parent_uid parent_deck_uid root_uid fill_uid].freeze
# fiziksel / görünen ID bağları → hedef türler (nil: herhangi bir tür). linked_element_id ADR listesinde yok; kazık "özel kot" bağı (main.rb:1305).
MST_SC_ID_KEYS={'connected_pile_ids'=>%w[steel_pipe_pile bored_pile],'pile_ids'=>%w[steel_pipe_pile bored_pile],'parent_deck_id'=>%w[deck_slab],
                'parent_crown_id'=>%w[crown_wall],'support_hb_ids'=>%w[head_beam],'linked_element_id'=>nil}.freeze
MST_SC_NOCOPY_KEYS=%w[element_uid uid_owner_pid copied_from_uid copy_origin progress_items_json progress_inherited_json progress_inherited_status progress_inherited_history_json].freeze
MST_SC_QTY_KEYS=%i[concrete_m3 formwork_m2 rebar_t steel_t].freeze

# Test için hata enjeksiyon noktası (üretimde hiçbir şey yapmaz). stage: 'copy' (kopya i bitti) / 'verify' (doğrulamadan hemen önce)
def mst_structure_copy_fault!(_stage,_index);end

def mst_sc_type(e);e.get_attribute(DICT,'element_type','').to_s;end
def mst_sc_inst?(e);(e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid?;end
def mst_sc_owned?(e);%w[system structure ano].any?{|k|!e.get_attribute(DICT,k,'').to_s.strip.empty?};end
def mst_sc_vid(e)
  t=mst_sc_type(e)
  "#{(element_visible_id(e) rescue "PID-#{e.persistent_id}")} (#{t.empty? ? 'grup' : t})"
end
def mst_sc_kids(e)
  ents=mst_container_entities(e)
  ents ? ents.to_a.select{|x|mst_sc_inst?(x)} : []
end
# İç öğelere inilir mi: Group her zaman; Component yalnız BK ve kökteki tipsiz / kapsayıcı Component (kopyada ayrılır).
# Diğer Component tanımları (kazık gövdesi, prekast, donatı pozu) paylaşılır; içlerine yazılmaz.
def mst_sc_descend?(e,root)
  return true if e.is_a?(Sketchup::Group)
  return false unless e.is_a?(Sketchup::ComponentInstance)
  t=mst_sc_type(e)
  t=='head_beam' || (e.equal?(root) && !MST_COLLECTED_TYPES.include?(t) && !MST_SC_EXTRA_TYPES.include?(t))
end
# 32/4: aksesuar (ağacın her düzeyinde) kopyalanmaz; sayılır
def mst_sc_acc?(e);mst_sc_type(e)=='accessory';end
# Kök öğenin kopyalanan alt ağacı (kök dahil; derinlik öncelikli, kaynak sırası). acc verilirse atlanan aksesuarlar eklenir.
def mst_sc_tree(root,e=root,out=[],acc=nil)
  out << e
  if mst_sc_descend?(e,root)
    mst_sc_kids(e).each{|c|mst_sc_acc?(c) ? (acc << c if acc) : mst_sc_tree(root,c,out,acc)}
  end
  out
end
# Kapsayıcının ilk tipli düzeyi (tipsiz grup / bileşen içine inilir; etiket grupları atlanır)
def mst_sc_first_typed(ents,out=[],defs={})
  ents.to_a.each do |e|
    next unless mst_sc_inst?(e)
    t=mst_sc_type(e)
    if !t.empty?
      out << e unless MST_SC_SKIP_TYPES.include?(t)
    elsif e.get_attribute('MAG_MST_Label','kind').nil?
      if e.is_a?(Sketchup::Group) then mst_sc_first_typed(e.entities,out,defs)
      elsif !defs[e.definition] then defs[e.definition]=true;mst_sc_first_typed(e.definition.entities,out,defs)
      end
    end
  end
  out
end
def mst_sc_tokens(v,sep=/[^,\s]+/)
  return [] if v.nil?
  return [v.to_i.to_s] if v.is_a?(Numeric)
  v.to_s.scan(sep).map(&:strip).reject(&:empty?)
end
def mst_sc_num(v)
  n=Float(v.to_s.strip.tr(',','.'))
  n.finite? ? n : nil
rescue ArgumentError,TypeError
  nil
end
def mst_sc_signature(roots)
  Array(roots).flat_map{|r|mst_sc_tree(r)}.map do |e|
    at=[];(e.attribute_dictionaries || []).to_a.compact.each{|dd|dd.each_pair{|k,v|at << [dd.name.to_s,k.to_s,v.inspect]}}
    dfn=nil
    if e.is_a?(Sketchup::ComponentInstance)
      da=[];(e.definition.attribute_dictionaries || []).to_a.compact.each{|dd|dd.each_pair{|k,v|da << [dd.name.to_s,k.to_s,v.inspect]}}
      dfn=[e.definition.object_id,da.sort]
    end
    [e.persistent_id,e.class.name,e.valid?,at.sort,(e.transformation.to_a.map{|v|v.to_f.round(9)} rescue []),dfn]
  end
end

# Kod / görünen ad çakışma tablosu (mst_name_key; I/İ, büyük / küçük harf ayrımı yok). Salt okuma.
def mst_sc_taken(model)
  taken={}
  mst_system_structures(model).each{|s,rows|Array(rows).each{|c|taken[mst_name_key(c)] ||= "#{s} sistemindeki #{c} kodu"}}
  %w[DOLFEN ISKELE RIHTIM].each{|s|mst_structures_for_system(s,model).each{|c|taken[mst_name_key(c)] ||= "#{s} sistemindeki #{c} kodu"}}
  mst_structure_display_names(model).each{|c,nm|taken[mst_name_key(nm)] ||= "#{c} yapısının görünen adı"}
  mst_code_usage(model)['elements'].each{|c,k|taken[mst_name_key(c)] ||= "#{k} elemanda kullanılan #{c} kodu" if k.to_i>0 && !c.to_s.strip.empty?}
  mst_axis_grids(model).each_key{|k|c=k.to_s.split('::',2).first.to_s;taken[mst_name_key(c)] ||= "kayıtlı #{c} aks ağı" unless c.empty?}
  mst_structure_placements(model).each_key{|k|c=k.to_s.split('::',2).last.to_s;taken[mst_name_key(c)] ||= "kayıtlı #{c} yerleşimi" unless c.empty?}
  taken
end

# Önerilen yeni kodlar: kaynak kodun son sayısı artırılır (basamak sayısı korunur), kullanılan / sisteme uymayan kod atlanır.
def mst_structure_copy_suggest_codes(sys,src,n,model=Sketchup.active_model)
  taken=mst_plan_readonly{mst_sc_taken(model)}
  m=src.to_s.match(/\A(.*?)(\d+)\z/)
  pre,num,w=m ? [m[1],m[2].to_i,m[2].length] : ["#{src}-",1,2]
  out=[];k=num;guard=0
  while out.length<n.to_i && guard<10_000
    k+=1;guard+=1
    c="#{pre}#{k.to_s.rjust(w,'0')}"
    next if taken[mst_name_key(c)] || !mst_code_allowed_in_system?(sys,c) || c.length>MST_NAME_MAX_STRUCTURE
    out << c;taken[mst_name_key(c)]='öneri'
  end
  out
end

# => plan; plan['errors'] boşsa uygulanabilir. Salt okuma (işlem açmaz, yazmaz).
def mst_structure_copy_plan(req,model=Sketchup.active_model)
  mst_plan_readonly{mst_sc_plan(req.is_a?(Hash) ? req : {},model)}
end

def mst_sc_plan(req,model)
  err=[]
  sys=req['system'].to_s.upcase;src=req['structure'].to_s
  pl={'system'=>sys,'source'=>src,'errors'=>err,'roots'=>[],'items'=>[],'owners'=>{}.compare_by_identity,'accessories'=>0,'visual'=>false}
  bad=->(el,why){err << "#{src.empty? ? '—' : src} / #{el} / #{why}"}
  return (bad.('—','Aks Yöneticisinde kaydedilmemiş değişiklik var; önce "Projeyi Kaydet" ile kaydedin.');pl) if req['dirty']
  rot=req['rotation_deg']
  if !rot.nil? && !rot.to_s.strip.empty? && (mst_sc_num(rot).nil? || mst_sc_num(rot).abs>1e-9)
    bad.('—','Dönüş ilk sürümde desteklenmiyor; yalnız X / Y ofseti (dx / dy) kullanılabilir.')
  end
  bad.('—','Model taraması sırasında çalıştırılamaz.') if @mst_scan_batch_on || @mst_read_batch_on
  bad.('—',"Geçersiz sistem: #{sys}") unless %w[DOLFEN ISKELE RIHTIM].include?(sys)
  n=(Integer(req['count'].to_s.strip,10) rescue nil)
  bad.('—',"Kopya sayısı 1–#{MST_SC_MAX} arasında tam sayı olmalı (girilen: #{req['count'].inspect}).") unless n && n>=1 && n<=MST_SC_MAX
  off=%w[dx dy dz].map{|k|v=req[k];(v.nil? || v.to_s.strip.empty?) ? 0.0 : mst_sc_num(v)}
  %w[dx dy dz].each_with_index{|k,i|bad.('—',"#{k} ofseti sayı olmalı (girilen: #{req[k].inspect}).") if off[i].nil?}
  # Kot öznitelikleri (top/bottom_elevation_m vb.) Z ile taşınmaz → geometri ile kayıt uyuşmaz; ilk sürümde reddedilir
  bad.('—','Z ofseti (dz) ilk sürümde desteklenmiyor: kot kayıtları geometriyle birlikte taşınmaz. Yalnız X / Y ofseti kullanın.') if off[2] && off[2].abs>1e-9
  %w[system_structures_json axis_grids_json structure_placements_json structure_display_names_json].each do |k|
    bad.('—',"#{k} kaydı okunamadı (bozuk JSON); üzerine yazılmaz.") if mst_json_attr_bad?(model,k,Hash)
  end
  return pl unless err.empty?
  pl['count']=n;pl['dx'],pl['dy'],pl['dz']=off
  bad.('—',"Kaynak yapı #{sys} sisteminde yok.") unless mst_structures_for_system(sys,model).include?(src)
  # yeni kodlar ve görünen adlar
  codes=Array(req['codes']).map{|c|c.to_s.strip}
  codes=mst_structure_copy_suggest_codes(sys,src,n,model) if codes.all?(&:empty?)
  names=Array(req['names']).map{|c|c.to_s}
  bad.('—',"#{n} kopya için #{codes.length} kod verildi.") unless codes.length==n
  taken=mst_sc_taken(model);out_c=[];out_n=[]
  codes.first(n).each_with_index do |raw,i|
    c=(mst_code_validate(raw,MST_NAME_MAX_STRUCTURE,"Kopya #{i+1} kodu") rescue (bad.('—',$!.message);nil))
    next if c.nil?
    if c.empty? then bad.('—',"Kopya #{i+1} kodu boş.");next;end
    unless mst_code_allowed_in_system?(sys,c) then bad.('—',"#{c} kodu #{sys} sisteminde kullanılamaz (biçim başka sisteme ait).");next;end
    if (h=taken[mst_name_key(c)]) then bad.('—',"#{c} kodu #{h} ile çakışıyor (büyük / küçük harf ve I / İ ayrımı yapılmaz).");next;end
    taken[mst_name_key(c)]="kopya #{i+1} kodu";out_c << c
    nm=(mst_name_validate(names[i].to_s,MST_NAME_MAX_STRUCTURE,"Kopya #{i+1} görünen adı") rescue (bad.('—',$!.message);''))
    nm='' if mst_name_key(nm)==mst_name_key(c)
    if !nm.empty? && (h=taken[mst_name_key(nm)]) then bad.('—',"\"#{nm}\" görünen adı #{h} ile çakışıyor.");nm='';end
    taken[mst_name_key(nm)]="kopya #{i+1} görünen adı" unless nm.empty?
    out_n << nm
  end
  pl['codes']=out_c;pl['names']=out_n
  # kaynak başlangıcı ve ızgara
  pls=mst_structure_placements(model);grid_for=->(nm){mst_axis_grid_for(nm,model,nm)}
  pl['origin']=([mst_origin_pure(sys,src,'X',pls,grid_for),mst_origin_pure(sys,src,'Y',pls,grid_for)] rescue (bad.('—',"kaynak yapı başlangıcı hesaplanamadı: #{$!.message}");[0.0,0.0]))
  pl['grid']=JSON.parse(JSON.generate(mst_axis_grid_for(src,model,src)))
  mst_sc_collect!(pl,model,bad)
  pl['source_sig']=mst_sc_signature(pl['roots'])
  pl['kinds']=pl['items'].map{|e|mst_sc_type(e)}.group_by{|x|x}.map{|k,v|[k,v.length]}.sort
  pl
end

# Kaynak kümesi (mst_structure_move_plans kuralı + mst_code_usage_extra tipli öğeleri), aidiyet ve bağ denetimi
def mst_sc_collect!(pl,model,bad)
  sys=pl['system'];src=pl['source']
  all=[];collect_elements(model.entities,all);all=all.select(&:valid?)
  seen={}.compare_by_identity;all.each{|e|seen[e]=true}
  ex=[];mst_code_usage_extra(model.entities,seen,ex,Hash.new(0),{})
  pool=(all+ex).uniq
  by_uid=Hash.new{|h,k|h[k]=[]};pool.each{|e|u=e.get_attribute(DICT,'element_uid','').to_s;by_uid[u] << e unless u.empty?}
  ins=->(e){mst_element_in_structure?(e,sys,src)}
  # aidiyet: :yes / :no / :unknown — sahiplik alanı yoksa üst öğe bağı (parent_uid) izlenir (ör. kökteki kaplama)
  belongs=lambda do |e,depth=0|
    if mst_sc_type(e)=='pile_layout'
      next :unknown if e.get_attribute(DICT,'system','').to_s.strip.empty? || e.get_attribute(DICT,'structure','').to_s.strip.empty?
      next (e.get_attribute(DICT,'system','').to_s.upcase==sys && e.get_attribute(DICT,'structure','').to_s==src) ? :yes : :no
    end
    next(ins.(e) ? :yes : :no) if mst_sc_owned?(e)
    pu=e.get_attribute(DICT,'parent_uid','').to_s
    par=by_uid[pu].reject{|x|x.equal?(e)}
    next :unknown unless par.length==1 && depth<3
    belongs.(par.first,depth+1)
  end
  roots=[];owners=pl['owners']
  model.entities.to_a.each do |e|
    next unless mst_sc_inst?(e)
    t=mst_sc_type(e)
    next if t.empty? && !e.get_attribute('MAG_MST_Label','kind').nil?
    if t=='axis_grid_visual'
      pl['visual']=true if e.get_attribute(DICT,'ano','').to_s==src
    elsif t=='accessory'
      pl['accessories']+=1 if mst_sc_owned?(e) && ins.(e)
    elsif MST_SC_SKIP_TYPES.include?(t)
      next
    elsif t=='pile_layout' || MST_COLLECTED_TYPES.include?(t) || (!t.empty? && mst_sc_first_typed(mst_container_entities(e) || []).empty?)
      case belongs.(e)
      when :yes
        roots << e
        if t=='pile_layout' then mst_layout_piles(e).each{|p|owners[p]=true}
        elsif mst_sc_owned?(e) then owners[e]=true
        end
      when :unknown then bad.(mst_sc_vid(e),'sistem / yapı / ano boş; hangi yapıya ait olduğu belirsiz (belirsiz aidiyet).')
      end
    else
      inner=mst_sc_first_typed(mst_container_entities(e) || [])
      next if inner.empty?
      st=inner.map{|x|belongs.(x)}
      yes=st.count(:yes)
      if yes==inner.length
        roots << e
        inner.each{|x|if mst_sc_type(x)=='pile_layout' then mst_layout_piles(x).each{|p|owners[p]=true};elsif mst_sc_owned?(x) then owners[x]=true;end}
      elsif yes>0
        bad.(mst_sc_vid(e),"karışık kapsayıcı: #{yes} eleman bu yapıya, #{inner.length-yes} eleman başka yapıya ait / belirsiz.")
      elsif st.include?(:unknown)
        inner.each_with_index{|x,i|bad.(mst_sc_vid(x),'sistem / yapı / ano boş; hangi yapıya ait olduğu belirsiz (belirsiz aidiyet).') if st[i]==:unknown}
      end
    end
  end
  pl['roots']=roots
  nacc=[];items=roots.flat_map{|r|mst_sc_tree(r,r,[],nacc)}.reject{|e|mst_sc_type(e).empty?}
  pl['accessories']+=nacc.length
  pl['items']=items
  inset={}.compare_by_identity;items.each{|e|inset[e]=true}
  # 32/1: bu yapıya ait olup kopya öğe listesine girmeyen tipli eleman (ör. kapsayıcı → tipsiz iç içe Component → prekast) → ret.
  # Paylaşılan tanımlı Component öğelerin (kazık gövdesi, prekast) tanım içi öğeleri bilerek paylaşılır; onlar kapsanmış sayılır.
  covered={}.compare_by_identity;defs={}.compare_by_identity
  walk=lambda do |ents|
    ents.to_a.each do |x|
      next unless mst_sc_inst?(x)
      covered[x]=true
      if x.is_a?(Sketchup::Group) then walk.(x.entities)
      elsif !defs[x.definition] then defs[x.definition]=true;walk.(x.definition.entities)
      end
    end
  end
  roots.each do |r|
    mst_sc_tree(r).each do |x|
      next unless x.is_a?(Sketchup::ComponentInstance) && !mst_sc_type(x).empty? && !mst_sc_descend?(x,r) && !defs[x.definition]
      defs[x.definition]=true;walk.(x.definition.entities)
    end
  end
  pool.each do |e|
    t=mst_sc_type(e)
    next if inset[e] || covered[e] || t.empty? || t=='accessory' || MST_SC_SKIP_TYPES.include?(t)
    next unless belongs.(e)==:yes
    bad.(mst_sc_vid(e),'bu yapıya ait ama kopya kapsamına girmiyor (tipsiz iç içe Component içinde olabilir; paylaşılan tanım ayrılmadan kopyalanamaz). Component\'i Group yapın ya da patlatın.')
  end
  # karar 8: jet grout satırında elle girilmiş ilerleme (manual_progress_json; okuma, PROGRESS_DICT'e yazılmaz) → ret
  jg=items.select{|e|mst_sc_type(e)=='jet_grout'}
  if !jg.empty? && respond_to?(:prog2_manual)
    pre=jg.map{|e|d=(jg_validate(JSON.parse(e.get_attribute(DICT,'jet_grout_data','{}').to_s)) rescue nil);d ? "JETGROUT:#{d['type_id']}:#{d['diameter']}:#{d['system']}:" : nil}.compact.uniq
    hit=prog2_manual.select do |k,rec|
      next false unless pre.any?{|p|prog2_base(k).start_with?(p)}
      m=prog2_norm(rec);m && [prog2_clamp(m['claim']),prog2_rec_frac(m)].max>0
    end
    bad.(hit.keys.first(3).join(', '),'Jet grout satırında elle girilmiş ilerleme var; kopya onaylı miktarı çoğaltır. Jet grout eleman bazlı ilerlemesi ayrı iş.') unless hit.empty?
  end
  pl['component_precast']=items.any?{|e|e.is_a?(Sketchup::ComponentInstance) && %w[flat_precast channel_precast crane_precast].include?(mst_sc_type(e))}
  # iç öğe başka yapıda mı
  items.each do |e|
    next if mst_sc_type(e)=='pile_layout' || MST_SC_SKIP_TYPES.include?(mst_sc_type(e))
    bad.(mst_sc_vid(e),"iç eleman başka yapıya ait (#{e.get_attribute(DICT,'system','')} / #{e.get_attribute(DICT,'structure','')} / #{e.get_attribute(DICT,'ano','')}).") if mst_sc_owned?(e) && !ins.(e)
  end
  # kaynak içinde mükerrer UID (eşlem belirsiz olur)
  items.group_by{|e|e.get_attribute(DICT,'element_uid','').to_s}.each{|u,v|bad.(v.map{|x|mst_sc_vid(x)}.join(', '),"aynı UID (#{u}); önce BIM Kimlik Onarımı.") if !u.empty? && v.uniq.length>1}
  # bağlar: hedef aynı yapının kopya kümesinde olmalı
  i_pid={};items.each{|e|i_pid[e.persistent_id]=e}
  i_uid={};items.each{|e|u=e.get_attribute(DICT,'element_uid','').to_s;i_uid[u]=e unless u.empty?}
  o_pid={};pool.each{|e|o_pid[e.persistent_id] ||= e}
  i_vid=Hash.new{|h,k|h[k]=[]};items.each{|x|i_vid[mst_sc_ident(x)] << x}
  o_vid=Hash.new{|h,k|h[k]=[]};pool.each{|x|o_vid[mst_sc_ident(x)] << x}
  outside=->(x){x.nil? ? 'modelde bulunamadı (karşılıksız bağ)' : "başka yapıdaki #{mst_sc_vid(x)} öğesini gösteriyor (#{x.get_attribute(DICT,'system','')} / #{x.get_attribute(DICT,'structure','')} / #{x.get_attribute(DICT,'ano','')})"}
  items.each do |e|
    MST_SC_PID_KEYS.each do |k|
      mst_sc_tokens(e.get_attribute(DICT,k,nil)).each do |tok|
        unless tok=~/\A\d+\z/ then bad.(mst_sc_vid(e),"#{k}: '#{tok}' PID değil.");next;end
        i=tok.to_i;next if i<=0 || i_pid[i]
        x=o_pid[i] || (model.find_entity_by_persistent_id(i) rescue nil)
        bad.(mst_sc_vid(e),"#{k}: PID #{i} #{outside.(x)}")
      end
    end
    MST_SC_UID_KEYS.each do |k|
      mst_sc_tokens(e.get_attribute(DICT,k,nil)).each do |tok|
        next if i_uid[tok]
        bad.(mst_sc_vid(e),"#{k}: UID #{tok} #{outside.(by_uid[tok].first)}")
      end
    end
    MST_SC_ID_KEYS.each do |k,types|
      mst_sc_tokens(e.get_attribute(DICT,k,nil),/[^,]+/).each do |tok|
        hit=i_vid[tok].select{|x|types.nil? || types.include?(mst_sc_type(x))}
        next if hit.length==1
        if hit.length>1 then bad.(mst_sc_vid(e),"#{k}: '#{tok}' kopya kümesinde birden fazla öğeye karşılık geliyor.");next;end
        x=o_vid[tok].find{|q|types.nil? || types.include?(mst_sc_type(q))}
        bad.(mst_sc_vid(e),"#{k}: '#{tok}' #{outside.(x)}")
      end
    end
    %w[jet_grout_data bored_pile_data].each do |k|
      raw=e.get_attribute(DICT,k,nil)
      bad.(mst_sc_vid(e),"#{k} okunamadı (bozuk JSON).") if !raw.nil? && !raw.to_s.strip.empty? && !(JSON.parse(raw.to_s) rescue nil).is_a?(Hash)
    end
  end
  pl
end
# Görünen ID (element_visible_id; kronmanda 'id' = grup adı, parent_crown_id bunu gösterir)
def mst_sc_ident(e);(element_visible_id(e) rescue "PID-#{e.persistent_id}");end
# Kopyada yeniden numaralanan görünür kimlik anahtarı: mst_identity_id_key + kronman 'id' (Model Kontrolü ID_KEYS, model_health.rb:11/41)
def mst_sc_id_key(t);mst_identity_id_key(t) || (t=='crown_wall' ? 'id' : nil);end

# ---- uygulama
def mst_sc_copy_root(r,tr,model)
  if r.is_a?(Sketchup::Group)
    c=r.copy
    c.transform!(tr)
  else
    c=model.entities.add_instance(r.definition,tr*r.transformation)
    c.name=r.name.to_s unless r.name.to_s.empty?
    c.layer=r.layer if r.layer
    c.material=r.material if r.material
    c.hidden=true if r.respond_to?(:hidden?) && r.hidden?
  end
  c
end
# Kopya iç öğeye yazılmadan önce kaynağın tanımından ayrılır
def mst_sc_separate!(s,d)
  shared=->{d.respond_to?(:definition) && s.respond_to?(:definition) && d.definition==s.definition}
  if d.is_a?(Sketchup::Group)
    d.make_unique if shared.call && d.respond_to?(:make_unique)
  elsif shared.call
    mst_make_unique_keep_data!(d)   # Component BK / kapsayıcı Component (çağıranın işlemi içinde)
  end
  raise "#{mst_sc_vid(s)}: kopya kaynakla aynı tanımı paylaşıyor; ayrılamadı (kaynağa yazılmaması için durduruldu)." if shared.call
end
def mst_sc_pair!(s,d,root,out)
  out << [s,d]
  return unless mst_sc_descend?(s,root)
  mst_sc_separate!(s,d)
  a=mst_sc_kids(s);b=mst_sc_kids(d)
  same=a.length==b.length && a.zip(b).all?{|x,y|x.class==y.class && (mst_sc_type(y).empty? || mst_sc_type(x)==mst_sc_type(y))}
  raise "#{mst_sc_vid(s)}: kopyanın iç öğeleri kaynakla eşleşmedi (#{a.length} ↔ #{b.length})." unless same
  # 32/2: kardeşler sırayla eşlenir; SketchUp'ın kopya / make_unique sırası doğrulanmadığından yerel konum (transformation) da aynı olmalı
  a.zip(b).each do |x,y|
    next if mst_sc_tr_key(x)==mst_sc_tr_key(y)
    raise "#{mst_sc_vid(x)}: kopyadaki eşi farklı yerel konumda (iç öğe sırası değişmiş olabilir); öznitelik yanlış geometriye yazılmasın diye durduruldu."
  end
  # 32/4 (karar 2): eleman grubu içindeki aksesuar kopyalanmaz; kopyaya geçen eşi (ayrılmış kopya içinde) silinir
  a.zip(b).each{|x,y|mst_sc_acc?(x) ? y.erase! : mst_sc_pair!(x,y,root,out)}
end
def mst_sc_tr_key(e);(e.transformation.to_a.map{|v|v.to_f.round(6)} rescue nil);end
def mst_sc_nocopy?(k);MST_SC_NOCOPY_KEYS.include?(k) || k.start_with?('dependency_');end
# MST sözlükleri (MAG_*; PROGRESS_DICT hariç) açıkça kopyalanır; ilerleme / bağımlılık / kimlik kayıtları kopyaya geçmez
def mst_sc_copy_attrs!(s,d)
  (s.attribute_dictionaries || []).to_a.compact.each do |dict|
    dn=dict.name.to_s
    next unless dn.start_with?('MAG_') && dn!=PROGRESS_DICT
    dict.each_pair do |k,v|
      ks=k.to_s
      next if dn==DICT && mst_sc_nocopy?(ks)
      d.set_attribute(dn,ks,v) unless d.get_attribute(dn,ks,nil)==v
    end
  end
  dd=d.attribute_dictionary(DICT,false)
  (dd ? dd.keys.map(&:to_s) : []).select{|k|mst_sc_nocopy?(k)}.each{|k|d.delete_attribute(DICT,k)}
end
def mst_sc_used_ids(model)
  used=Hash.new{|h,k|h[k]={}}
  all=[];collect_elements(model.entities,all)
  all.each{|e|next unless e.valid?;v=mst_sc_ident(e);used[mst_sc_type(e)][v]=true unless v.start_with?('PID-')}
  used
end
# 32/6: mst_next_unique_physical_id ile aynı sonuç (ilk boş numara); işlem içinde used yalnız büyüdüğünden arama son verilen numaradan sürer
def mst_sc_next_id(t,used,st)
  pre=bim_type_prefix(t);h=(st[:id_hint] ||= {});n=h[t] || 1
  n+=1 while used[t]["#{pre}-#{n.to_s.rjust(3,'0')}"]
  h[t]=n+1
  "#{pre}-#{n.to_s.rjust(3,'0')}"
end
def mst_sc_vid_map(mp,types,tok)
  # 32/6: ters indeks (görünen ID → {tür → yeni ID}, :vid ile aynı içerik); tüm eşlem taranmaz
  hit=(mp[:vtok][tok] || {}).select{|t,_|types.nil? || types.include?(t)}.values.uniq
  hit.length==1 ? hit.first : nil
end
def mst_sc_rewrite_links!(s,d,mp)
  MST_SC_PID_KEYS.each do |k|
    v=s.get_attribute(DICT,k,nil);next if v.nil?
    f=->(i){mp[:pid].fetch(i){raise "#{k}: PID #{i} eşlemde yok"}}
    nv=v.is_a?(Numeric) ? (v.to_i<=0 ? v : f.(v.to_i)) : v.to_s.gsub(/[^,\s]+/){|tok|tok.to_i<=0 ? tok : f.(tok.to_i).to_s}
    d.set_attribute(DICT,k,nv) unless nv==v
  end
  MST_SC_UID_KEYS.each do |k|
    v=s.get_attribute(DICT,k,nil);next if v.nil?
    nv=v.to_s.gsub(/[^,\s]+/){|tok|mp[:uid].fetch(tok){raise "#{k}: UID #{tok} eşlemde yok"}}
    d.set_attribute(DICT,k,nv) unless nv==v.to_s
  end
  MST_SC_ID_KEYS.each do |k,types|
    v=s.get_attribute(DICT,k,nil);next if v.nil?
    nv=v.to_s.gsub(/[^,]+/) do |seg|
      tok=seg.strip
      next seg if tok.empty?
      seg.sub(tok,mst_sc_vid_map(mp,types,tok) || raise("#{k}: '#{tok}' eşlemde yok"))
    end
    d.set_attribute(DICT,k,nv) unless nv==v.to_s
  end
  t=mst_sc_type(s)
  if t=='steel_pipe_pile' && !s.get_attribute(DICT,'global_pile_id',nil).nil? && s.get_attribute(DICT,'global_pile_id','').to_s==s.get_attribute(DICT,'pile_id','').to_s
    d.set_attribute(DICT,'global_pile_id',d.get_attribute(DICT,'pile_id','').to_s)
  end
  od=s.get_attribute(DICT,'parent_deck_id','').to_s
  if t=='deck_topping' && !od.empty? && s.get_attribute(DICT,'topping_id','').to_s=="TOP-#{od}"
    d.set_attribute(DICT,'topping_id',"TOP-#{d.get_attribute(DICT,'parent_deck_id','')}")
  end
end
def mst_sc_set_structure!(s,d,src,code,owner)
  %w[ano structure zone].each do |k|
    v=s.get_attribute(DICT,k,nil)
    d.set_attribute(DICT,k,code) if owner || (!v.nil? && !v.to_s.strip.empty?)
  end
  # 33/5: qto_zone kaynak koduna eşitse yeni kod
  %w[structure_zone ano_id qto_zone].each{|k|d.set_attribute(DICT,k,code) if s.get_attribute(DICT,k,'').to_s==src && !src.empty?}
  # 32/5 + 33/6: veri içindeki ano, üst düzey ano ile birlikte yazılır (sahip öğe) ya da kaynak koduna eşitse
  %w[jet_grout_data bored_pile_data].each do |k|
    raw=s.get_attribute(DICT,k,nil)
    next if raw.nil? || raw.to_s.strip.empty?
    h=JSON.parse(raw.to_s)
    next unless h.is_a?(Hash) && (owner || h['ano'].to_s==src)
    h['ano']=code;d.set_attribute(DICT,k,JSON.generate(h))
  end
end
def mst_sc_add_global!(e,keys,dx,dy)
  keys.each_with_index{|k,i|v=e.get_attribute(DICT,k,nil);e.set_attribute(DICT,k,v.to_f+(i==0 ? dx : dy)) unless v.nil?}
end
def mst_sc_build_copy!(plan,model,i,code,used,st)
  src=plan['source'];dx=plan['dx']*i;dy=plan['dy']*i;dz=plan['dz']*i
  tr=Geom::Transformation.translation([dx.m,dy.m,dz.m])
  pairs=[]
  plan['roots'].each do |r|
    st[:elem]=mst_sc_vid(r)
    mst_sc_pair!(r,mst_sc_copy_root(r,tr,model),r,pairs)
  end
  pairs.each{|s,d|st[:elem]=mst_sc_vid(s);mst_sc_copy_attrs!(s,d)}
  mp={pid:{},uid:{},vid:{},vtok:{}}
  now=Time.now.to_i
  pairs.each do |s,d|
    t=mst_sc_type(s);next if t.empty?
    st[:elem]=mst_sc_vid(s)
    mp[:pid][s.persistent_id]=d.persistent_id
    u=s.get_attribute(DICT,'element_uid','').to_s
    unless u.empty?
      nu="MST-#{d.persistent_id}-#{now}-C"
      d.set_attribute(DICT,'element_uid',nu);d.set_attribute(DICT,'uid_owner_pid',d.persistent_id)
      d.set_attribute(DICT,'copied_from_uid',u);d.set_attribute(DICT,'copy_origin','structure_copy')
      mp[:uid][u]=nu
    end
    key=mst_sc_id_key(t)
    if key
      nid=mst_sc_next_id(t,used,st);used[t][nid]=true
      d.set_attribute(DICT,key,nid);d.name=nid if d.respond_to?(:name=)
    end
    sv=mst_sc_ident(s);dv=mst_sc_ident(d);mp[:vid][[t,sv]]=dv;(mp[:vtok][sv] ||= {})[t]=dv
  end
  pairs.each do |s,d|
    next if mst_sc_type(s).empty?
    st[:elem]=mst_sc_vid(s)
    mst_sc_rewrite_links!(s,d,mp)
    mst_sc_set_structure!(s,d,src,code,plan['owners'][s])
    d.set_attribute(DICT,'progress_status','Planlandı') unless s.get_attribute(DICT,'progress_status',nil).nil?
  end
  # global koordinatlar: mst_apply_structure_move_plans kuralı (yerleşim başlangıcı + yerleşim kazıkları, kök elemanlar)
  rmap={}.compare_by_identity;pairs.each{|s,d|rmap[s]=d}
  plan['roots'].each do |r|
    c=rmap[r];t=mst_sc_type(r)
    if t=='pile_layout'
      mst_sc_add_global!(c,%w[global_origin_x_m global_origin_y_m],dx,dy)
      mst_layout_piles(r).each{|p|mst_sc_add_global!(rmap[p],%w[global_x_m global_y_m],dx,dy) if rmap[p]}
    elsif !t.empty?
      mst_sc_add_global!(c,%w[global_x_m global_y_m],dx,dy)
    end
  end
  # 32/3: kronman aks uçları mutlak model koordinatı (inç, main.rb:9698/9723/9754); kopyada ofset eklenir, Z aynı
  pairs.each do |s,d|
    next unless mst_sc_type(s)=='crown_wall'
    %w[axis_start_x axis_end_x].each{|k|v=s.get_attribute(DICT,k,nil);d.set_attribute(DICT,k,v.to_f+dx.m) unless v.nil?}
    %w[axis_start_y axis_end_y].each{|k|v=s.get_attribute(DICT,k,nil);d.set_attribute(DICT,k,v.to_f+dy.m) unless v.nil?}
  end
  {'index'=>i,'code'=>code,'pairs'=>pairs,'map'=>mp}
end

def mst_sc_write_records!(plan,model)
  sys=plan['system'];codes=plan['codes']
  [['system_structures_json','Sistem / yapı listesi'],['axis_grids_json','Aks ağı'],['structure_placements_json','Yapı yerleşimleri'],
   ['structure_display_names_json','Yapı görünen adları']].each{|k,l|mst_json_attr_guard!(model,k,Hash,l)}
  mst_save_structures_for_system(sys,mst_structures_for_system(sys,model)+codes,model)
  g=mst_axis_grids(model);codes.each{|c|g[mst_axis_grid_key(c,c)]=JSON.parse(JSON.generate(plan['grid']))}
  model.set_attribute(DICT,'axis_grids_json',JSON.generate(g))
  p=mst_structure_placements(model);ox,oy=plan['origin']
  codes.each_with_index{|c,i|k=i+1;p[mst_placement_key(sys,c)]={'x_link'=>{'mode'=>'ABSOLUTE','coord_m'=>ox+k*plan['dx']},'y_link'=>{'mode'=>'ABSOLUTE','coord_m'=>oy+k*plan['dy']}}}
  model.set_attribute(DICT,'structure_placements_json',JSON.generate(p))
  nm=plan['names'].each_with_index.reject{|v,_|v.to_s.empty?}
  return if nm.empty?
  raw=model.get_attribute(DICT,'structure_display_names_json','').to_s
  h=raw.strip.empty? ? {} : JSON.parse(raw)
  nm.each{|v,i|h[codes[i]]=v}
  model.set_attribute(DICT,'structure_display_names_json',JSON.generate(h))
end

# => hata listesi (boş = doğrulandı). İşlem içinde, commit'ten önce; yazmaz.
def mst_structure_copy_verify(plan,model,built)
  errs=[]
  src_kinds=plan['kinds']
  all=[];collect_elements(model.entities,all)
  seen={}.compare_by_identity;all.each{|e|seen[e]=true}
  ex=[];mst_code_usage_extra(model.entities,seen,ex,Hash.new(0),{})
  pool=(all+ex+plan['items']+built.flat_map{|b|b['pairs'].map(&:last)}).select{|e|e.valid? && !mst_sc_type(e).empty?}.uniq
  by_uid=Hash.new{|h,k|h[k]=[]};pool.each{|e|u=e.get_attribute(DICT,'element_uid','').to_s;by_uid[u] << e unless u.empty?}
  by_id=Hash.new{|h,k|h[k]=[]};all.uniq.each{|e|next unless e.valid?;t=mst_sc_type(e);by_id[[t,mst_sc_ident(e)]] << e if mst_sc_id_key(t)}
  built.each do |b|
    i=b['index'];c=b['code'];tag="kopya #{i} (#{c})"
    ds=b['pairs'].map(&:last).reject{|d|mst_sc_type(d).empty?}
    kinds=ds.map{|d|mst_sc_type(d)}.group_by{|x|x}.map{|k,v|[k,v.length]}.sort
    errs << "#{tag}: tür bazında sayı kaynakla aynı değil (#{kinds.inspect} ↔ #{src_kinds.inspect})" unless kinds==src_kinds
    d_pid={};d_uid={};ds.each{|d|d_pid[d.persistent_id]=d;u=d.get_attribute(DICT,'element_uid','').to_s;d_uid[u]=d unless u.empty?}
    d_vid=Hash.new{|h,k|h[k]=[]};ds.each{|d|d_vid[mst_sc_ident(d)] << d}
    ds.each do |d|
      el=mst_sc_vid(d);u=d.get_attribute(DICT,'element_uid','').to_s
      errs << "#{tag} / #{el}: UID #{u} benzersiz değil" if !u.empty? && by_uid[u].uniq.length!=1
      errs << "#{tag} / #{el}: fiziksel ID benzersiz değil" if mst_sc_id_key(mst_sc_type(d)) && by_id[[mst_sc_type(d),mst_sc_ident(d)]].uniq.length>1
      MST_SC_PID_KEYS.each{|k|mst_sc_tokens(d.get_attribute(DICT,k,nil)).each{|tok|errs << "#{tag} / #{el}: #{k} PID #{tok} kopya dışı" unless tok.to_i<=0 || d_pid[tok.to_i]}}
      MST_SC_UID_KEYS.each{|k|mst_sc_tokens(d.get_attribute(DICT,k,nil)).each{|tok|errs << "#{tag} / #{el}: #{k} UID #{tok} kopya dışı" unless d_uid[tok]}}
      MST_SC_ID_KEYS.each do |k,types|
        mst_sc_tokens(d.get_attribute(DICT,k,nil),/[^,]+/).each do |tok|
          errs << "#{tag} / #{el}: #{k} '#{tok}' kopya dışı" unless d_vid[tok].count{|x|types.nil? || types.include?(mst_sc_type(x))}==1
        end
      end
    end
    b['pairs'].each do |s,d|
      next unless plan['owners'][s]
      got=%w[ano structure zone].map{|k|d.get_attribute(DICT,k,'').to_s}
      errs << "#{tag} / #{mst_sc_vid(d)}: ano / structure / zone #{got.join(' / ')}" unless got==[c,c,c]
      errs << "#{tag} / #{mst_sc_vid(d)}: system değişti" unless d.get_attribute(DICT,'system','').to_s==s.get_attribute(DICT,'system','').to_s
    end
    b['pairs'].each do |s,d|
      next unless d.is_a?(Sketchup::ComponentInstance) && mst_sc_type(s)=='head_beam'
      errs << "#{tag} / #{mst_sc_vid(d)}: Component BK tanımı kaynakla paylaşılıyor" if d.definition==s.definition
    end
    b['pairs'].each do |s,d|
      next unless MST_COLLECTED_TYPES.include?(mst_sc_type(s))
      MST_SC_QTY_KEYS.each do |k|
        rs=QuantityService.record(s,k);rd=QuantityService.record(d,k)
        a1=[rs[:state],rs[:value].nil? ? nil : rs[:value].to_f.round(9)];a2=[rd[:state],rd[:value].nil? ? nil : rd[:value].to_f.round(9)]
        errs << "#{tag} / #{mst_sc_vid(d)}: metraj #{k} kaynakla aynı değil (#{a2.inspect} ↔ #{a1.inspect})" unless a1==a2
      end
    end
  end
  errs << 'kaynak yapı imzası değişti' unless mst_sc_signature(plan['roots'])==plan['source_sig']
  errs
end

def mst_structure_copy_apply!(plan,model=Sketchup.active_model)
  raise 'Yapıyı Kopyala: ön kontrol başarısız; işlem açılmadı.' unless plan.is_a?(Hash) && plan['errors'].is_a?(Array) && plan['errors'].empty?
  raise 'Yapıyı Kopyala: model taraması sırasında çalıştırılamaz; işlem açılmadı.' if @mst_scan_batch_on || @mst_read_batch_on
  n=plan['count'];src=plan['source'];stage='başlangıç';ci=0;st={}
  model.start_operation("MST Yapı Kopyala ×#{n}",true)
  begin
    used=mst_sc_used_ids(model);built=[]
    stage='kopya'
    plan['codes'].each_with_index do |code,k|
      ci=k+1
      built << mst_sc_build_copy!(plan,model,ci,code,used,st)
      mst_structure_copy_fault!('copy',ci)
    end
    ci=0;st[:elem]=nil
    stage='kayıtlar';mst_sc_write_records!(plan,model)
    stage='aks görseli';plan['codes'].each{|c|mst_show_grid_visual(c,model,c,false,plan['system'])} if plan['visual']
    stage='doğrulama'
    @mst_pile_idx_cache=nil;@mst_def_cache=nil
    mst_structure_copy_fault!('verify',0)
    errs=mst_structure_copy_verify(plan,model,built)
    raise errs.first(10).join('; ')+(errs.length>10 ? " … #{errs.length-10} hata daha" : '') unless errs.empty?
    stage='kapanış'
    commit_with_dependencies(model)
  rescue Exception=>ex
    model.abort_operation
    @mst_pile_idx_cache=nil;@mst_def_cache=nil
    ok=(mst_sc_signature(plan['roots'])==plan['source_sig'] rescue false)
    raise unless ex.is_a?(StandardError)
    code=ci>0 ? plan['codes'][ci-1] : nil
    msg="Yapıyı Kopyala yapılamadı — yapı #{src}#{ci>0 ? ", kopya #{ci} (#{code})" : ''}, aşama: #{stage}#{st[:elem] ? ", eleman: #{st[:elem]}" : ''}.\nNeden: #{ex.message}\n\n"+
        (ok ? 'İşlem geri alındı; kaynak yapı imzası işlem öncesiyle aynı (doğrulandı). Kopyaların hiçbiri modelde kalmadı.' :
              'İşlem geri alındı (abort) ancak kaynak yapı imzası doğrulanamadı; modeli kontrol edin, güvenli olduğu varsayılmamalı.')
    return {'ok'=>false,'stage'=>stage,'copy_index'=>ci,'element'=>st[:elem],'error'=>ex.message,'rollback_verified'=>ok,'message'=>msg}
  end
  kinds=plan['kinds'].map{|k,v|"#{v} #{k}"}.join(', ')
  msg="Yapıyı Kopyala tamamlandı — #{src} → #{plan['codes'].join(', ')} (tek Geri Al).\nHer kopyada: #{kinds.empty? ? 'eleman yok (yalnız aks ağı ve yapı kayıtları)' : kinds}."
  msg+="\nYapıda yerleştirilmiş #{plan['accessories']} aksesuar kopyalanmadı, çizelgeye elle ekleyin." if plan['accessories'].to_i>0
  msg+="\n"+mst_sc_notes(plan)
  {'ok'=>true,'message'=>msg,'codes'=>plan['codes']}
end
MST_SC_PRECAST_SHARED='Component prekast tipleri yapılar arasında ortak; tipe yapılan donatı / geometri değişikliği tüm yapılardaki aynı tip prekastlara uygulanır.'
# Onay sorusu ve sonuç iletisinde ortak notlar (33/2 aksesuar çizelgesi, 33/4 dolgu, karar 9 Component prekast)
def mst_sc_notes(plan)
  n=['Aksesuar çizelgesi ve aksesuar ankraj donatısı çoğalmaz (model düzeyi kayıt); kopya yapılar için gerekiyorsa çizelgeye elle ekleyin.',
     'Dolgu (kaya dolgu) kopyalanmadı; ortak proje verisidir, miktarı değişmez.']
  n << MST_SC_PRECAST_SHARED if plan['component_precast']
  n.join("\n")
end

# Aks Yöneticisi "Yapıyı Kopyala" (axis_manager_structure_copy). json: {system, structure, dirty}
def mst_structure_copy_ui(dlg,json)
  model=Sketchup.active_model
  x=(JSON.parse(json.to_s) rescue nil);x={} unless x.is_a?(Hash)
  sys=x['system'].to_s.upcase;src=x['structure'].to_s
  if x['dirty']
    UI.messagebox('Yapıyı Kopyala: Aks Yöneticisinde kaydedilmemiş değişiklik var. Önce "Projeyi Kaydet" ile kaydedin; hiçbir şey değişmedi.')
    return
  end
  a=UI.inputbox(['Kopya sayısı (1–50)','X ofseti dx (m; kopya i için i × dx)','Y ofseti dy (m)'],['1','0.00','0.00'],"Yapıyı Kopyala — #{src}")
  return unless a
  n=(Integer(a[0].to_s.strip,10) rescue 0)
  sugg=(n>=1 && n<=MST_SC_MAX) ? mst_structure_copy_suggest_codes(sys,src,n,model) : []
  b=UI.inputbox(['Yeni yapı kodları (virgülle, sırayla)','Görünen adlar (isteğe bağlı; ; ile ayrılır)'],[sugg.join(', '),''],"Yapıyı Kopyala — #{src} → #{a[0]} kopya")
  return unless b
  req={'system'=>sys,'structure'=>src,'count'=>a[0],'dx'=>a[1],'dy'=>a[2],'codes'=>b[0].to_s.split(','),'names'=>b[1].to_s.split(';')}
  plan=mst_structure_copy_plan(req,model)
  unless plan['errors'].empty?
    e=plan['errors']
    UI.messagebox("Yapıyı Kopyala yapılmadı (işlem açılmadı, model değişmedi).\nYapı / eleman / neden:\n#{e.first(20).join("\n")}#{e.length>20 ? "\n… #{e.length-20} satır daha" : ''}")
    return
  end
  kinds=plan['kinds'].map{|k,v|"#{v} #{k}"}.join(', ')
  q="Yapıyı Kopyala — #{sys} / #{src} → #{plan['codes'].join(', ')}\n\nHer kopyada: #{kinds.empty? ? 'eleman yok (yalnız aks ağı ve yapı kayıtları)' : kinds}\n"+
    "Ofset (kopya i için i ×): dx #{format('%.2f',plan['dx'])} m, dy #{format('%.2f',plan['dy'])} m\n"+
    "Kopyalanmaz: aksesuar (#{plan['accessories']}), dolgu, etiketler; aks görseli yeni ızgaradan yeniden çizilir.\n"+
    "İlerleme 'Planlandı'; hakediş / ilerleme geçmişi aktarılmaz. Tip ve revizyon numaraları aynen taşınır.\n"+
    (plan['component_precast'] ? "#{MST_SC_PRECAST_SHARED}\n" : '')+"Tek işlem, tek Geri Al.\n\nDevam edilsin mi?"
  return unless UI.messagebox(q,MB_YESNO)==IDYES
  r=mst_structure_copy_apply!(plan,model)
  # 32/8: pencere yenilenemese bile eski durum kaydedilmesin / kopyalanmasın (kayıtlı kodlar ve yerleşimler silinmesin)
  (dlg.execute_script('window.mstStructureCopied&&window.mstStructureCopied()') rescue nil) if r['ok'] && dlg
  UI.messagebox(r['message'])
  UI.start_timer(0,false){project_ano_axis_manager rescue nil} if r['ok']
end

end
end
