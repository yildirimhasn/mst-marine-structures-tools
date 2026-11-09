# frozen_string_literal: true
# ADR-0515-K2 (docs/duzeltme/37, kullanıcı kararları 0–10) — Kanal prekastı: tek parametrik kesit (saf Ruby, SketchUp çağrısı yok).
# Kesit (metre): {"v":1,"preset":"U|L|UU|K|OZEL","total_width_m","base_m",
#                 "left"|"mid"|"right":{"on","width_m","height_m","offset_m"}}
#  Yerel düzlem y-z: y soldan sağa 0..toplam genişlik, z taban altından yukarı. Sol ofset soldan, orta ofset soldan,
#  sağ ofset sağdan; çıkıntı yüksekliği taban üstünden. Pasif çıkıntının değerleri saklanır, geometriye girmez.
#  Eski kayıt (channel_section_json yok): toplam = wi + 2tw, taban = tb, sol / sağ açık tw × di ofset 0, orta kapalı.
#  U-eşdeğeri kesit (sol + sağ açık, ofset 0, eşit ölçü, orta kapalı) eski U formülleriyle (mst_ch_u_*) hesaplanır;
#  bu formüller main.rb / controlled_editor.rb'deki tekrarların tek kaynağıdır ve eski ifadelerle aynı kayan nokta sırasındadır.
require 'json'
module MAG
module MarineStructuresTools

MST_CH_PARTS=%w[left mid right].freeze
MST_CH_PART_LABELS={'left'=>'Sol','mid'=>'Orta','right'=>'Sağ'}.freeze
# Ön ayarlar yalnız açık / kapalı bayraklarını değiştirir; ölçüler korunur (K ile L farkı yalnız ad / etiket).
MST_CH_PRESETS={'U'=>%w[left right],'L'=>%w[right],'UU'=>%w[left mid right],'K'=>%w[right]}.freeze
MST_CH_EPS=1e-9
# P4 (ADR K6, kararlar 3, 11): döşemede sol / sağ taban üstü (en dış çıkıntının dış tarafı, "dış ledge") açık kalır ('open') ya da
# döşeme betonuyla dolar ('fill'). Seçim kesitte deck_ledge_left / deck_ledge_right; yoksa ön ayar varsayılanı:
# U, L, UU açık; K ve OZEL dolu (karar 3 genel kuralı). Geometri anahtarına / imzaya girmez.
MST_CH_DECK_KEYS=%w[deck_ledge_left deck_ledge_right].freeze
MST_CH_DECK_FILL_PRESETS=%w[K OZEL].freeze
# Kalıp rolleri: U'da 4 rol (eski); U dışı kesitte 5. rol taban üst ledge'i (karar 4: ayrı rol, varsayılan kalıplı).
MST_CH_FW_ROLES_U=[%w[OUTER_BOTTOM],%w[OUTER_SIDE],%w[INNER_FLOOR INNER_SIDE],%w[END_FACE]].freeze
MST_CH_FW_ROLES_X=[%w[OUTER_BOTTOM],%w[OUTER_SIDE],%w[INNER_FLOOR INNER_SIDE],%w[END_FACE],%w[BASE_LEDGE]].freeze
MST_CH_KIND_FLAG={'OUTER_BOTTOM'=>:bottom,'OUTER_SIDE'=>:sides,'INNER_FLOOR'=>:inner,'INNER_SIDE'=>:inner,'BASE_LEDGE'=>:ledge,'END_FACE'=>:ends}.freeze

# ---- eski U formülleri (tek kaynak; ifadeler eski satırlarla birebir aynı sırada) ----
def mst_ch_u_outer(wi,tw);wi+2*tw;end
def mst_ch_u_height(di,tb);tb+di;end
def mst_ch_u_area(wi,di,tb,tw);ow=wi+2*tw;ow*tb+2*tw*di;end
def mst_ch_u_profile(wi,di,tb,tw)
 ow=wi+2*tw;oh=tb+di
 [[0,0],[ow,0],[ow,oh],[ow-tw,oh],[ow-tw,tb],[tw,tb],[tw,oh],[0,oh]]
end
# Rol bazlı kalıp terimleri [alt, dış yanlar, iç (taban + iki iç yan), iki uç]; toplama biçimi çağıranda kalır.
def mst_ch_u_fw_terms(len,wi,di,tb,tw)
 ow=wi+2*tw;oh=tb+di
 [len*ow,2*len*oh,len*(wi+2*di),2*(ow*tb+2*tw*di)]
end

# ---- kesit verisi ----
def mst_ch_default
 {'v'=>1,'preset'=>'U','total_width_m'=>1.20,'base_m'=>0.20,
  'left'=>{'on'=>true,'width_m'=>0.20,'height_m'=>0.60,'offset_m'=>0.0},
  'mid'=>{'on'=>false,'width_m'=>0.15,'height_m'=>0.30,'offset_m'=>0.525},
  'right'=>{'on'=>true,'width_m'=>0.20,'height_m'=>0.60,'offset_m'=>0.0}}
end

def mst_ch_num(v)
 return v.to_f if v.is_a?(Numeric)
 s=v.to_s.strip.tr(',','.')
 return 0.0 if s.empty?
 x=(Float(s) rescue nil)
 x && x.finite? ? x : Float::NAN
end

def mst_ch_bool(v)
 v==true || %w[1 true on yes evet var].include?(v.to_s.strip.downcase)
end

# Ham kesit (Hash ya da JSON metni) → biçimlenmiş kesit; okunamazsa nil.
def mst_ch_parse(raw)
 h=raw
 if raw.is_a?(String)
  h=(JSON.parse(raw) rescue nil)
 end
 return nil unless h.is_a?(Hash)
 h=h.each_with_object({}){|(k,v),o|o[k.to_s]=v}
 return nil unless h.key?('total_width_m') || h.key?('base_m')
 return nil if h.key?('v') && h['v'].to_i>1   # bilinmeyen (yeni) biçim: tahmin edilmez
 pr=h['preset'].to_s.strip.upcase;pr='OZEL' unless MST_CH_PRESETS.key?(pr) || pr=='OZEL'
 out={'v'=>1,'preset'=>pr,'total_width_m'=>mst_ch_num(h['total_width_m']),'base_m'=>mst_ch_num(h['base_m'])}
 MST_CH_PARTS.each do |k|
  p=h[k].is_a?(Hash) ? h[k].each_with_object({}){|(a,b),o|o[a.to_s]=b} : {}
  out[k]={'on'=>mst_ch_bool(p['on']),'width_m'=>mst_ch_num(p['width_m']),'height_m'=>mst_ch_num(p['height_m']),'offset_m'=>mst_ch_num(p['offset_m'])}
 end
 MST_CH_DECK_KEYS.each{|k|v=mst_ch_deck_flag(h[k]);out[k]=v if v}   # P4: yalnız geçerli seçim taşınır
 out
end

# Eski U ölçülerinden kesit (eşleme kuralı ADR K1).
def mst_ch_from_u(wi,di,tb,tw)
 total=wi+2*tw
 {'v'=>1,'preset'=>'U','total_width_m'=>total,'base_m'=>tb,
  'left'=>{'on'=>true,'width_m'=>tw,'height_m'=>di,'offset_m'=>0.0},
  'mid'=>{'on'=>false,'width_m'=>0.15,'height_m'=>0.30,'offset_m'=>((total-0.15)/2.0).round(6)},
  'right'=>{'on'=>true,'width_m'=>tw,'height_m'=>di,'offset_m'=>0.0}}
end

# Eski U ölçüleri: öğe / öznitelik özeti (inner_width_m …) ya da tip kaydı (inner_width …). Yoksa nil.
def mst_ch_legacy_dims(x)
 get=if x.respond_to?(:get_attribute) then ->(k){x.get_attribute(DICT,k,nil)}
     elsif x.is_a?(Hash) then ->(k){x[k]}
     end
 return nil unless get
 a=%w[inner_width_m inner_depth_m base_thickness_m wall_thickness_m].map{|k|get.(k)}
 a=%w[inner_width inner_depth base wall].map{|k|get.(k)} if a.all?(&:nil?)
 return nil if a.all?(&:nil?)
 a.map(&:to_f)
end

# Açık kesit verisi: öğede channel_section_json, öznitelik özetinde aynısı, tip / form kaydında 'section',
# ya da doğrudan kesit Hash'i / JSON metni. Yoksa veya okunamazsa nil.
def mst_ch_explicit(x)
 raw=if x.respond_to?(:get_attribute) then x.get_attribute(DICT,'channel_section_json',nil)
     elsif x.is_a?(Hash) then (x.key?('total_width_m') || x.key?('base_m')) ? x : (x['channel_section_json'] || x['section'])
     else x
     end
 return nil if raw.nil? || (raw.respond_to?(:empty?) && raw.empty?)
 mst_ch_parse(raw)
end

# Kesit: açık veri varsa o, yoksa eski U eşlemesi. U-eşdeğeri açık veri eski anahtarlarla çelişirse
# (eski sürümle U ölçüsü değiştirilmiş) eski anahtarlar geçerlidir. Hiçbiri yoksa nil.
def mst_ch_section(x)
 ex=mst_ch_explicit(x)
 lg=mst_ch_legacy_dims(x)
 if ex
  return ex unless lg && lg.all?{|v|v>0} && mst_ch_u_equiv?(ex)
  return ex if mst_ch_u_dims(ex).zip(lg).all?{|a,b|(a-b).abs<=MST_CH_EPS}
  return mst_ch_from_u(*lg)
 end
 lg ? mst_ch_from_u(*lg) : nil
end

# U dışı açık kesit (yeni kesit yolu); eski kayıt ve U-eşdeğeri kesitte nil (eski U yolu).
def mst_ch_custom_section(x)
 s=mst_ch_explicit(x)
 s && !mst_ch_u_equiv?(s) ? s : nil
end

def mst_ch_preset(sec,name)
 n=name.to_s.strip.upcase
 raise "Bilinmeyen kesit ön ayarı: #{name}" unless MST_CH_PRESETS.key?(n) || n=='OZEL'
 s=mst_ch_parse(sec) || mst_ch_default
 s['preset']=n
 MST_CH_PARTS.each{|k|s[k]['on']=MST_CH_PRESETS[n].include?(k)} unless n=='OZEL'
 s
end

# Açık çıkıntılar soldan sağa: [{part, y0, y1, h}]
def mst_ch_active(sec)
 t=sec['total_width_m'].to_f
 MST_CH_PARTS.select{|k|sec[k] && sec[k]['on']}.map do |k|
  p=sec[k];w=p['width_m'].to_f;o=p['offset_m'].to_f
  y0,y1=k=='right' ? [t-o-w,t-o] : [o,o+w]
  {'part'=>k,'y0'=>y0,'y1'=>y1,'h'=>p['height_m'].to_f}
 end.sort_by{|a|a['y0']}
end

def mst_ch_bad_num?(v);!v.is_a?(Numeric) || !v.to_f.finite?;end

# Geometrik geçerlilik (tasarım tahkiki değildir) → Türkçe hata listesi (boş = geçerli).
def mst_ch_valid(sec)
 return ['Kesit verisi okunamadı.'] unless sec.is_a?(Hash)
 err=[];f3=->(v){format('%.3f',v.to_f).tr('.',',')}
 t=sec['total_width_m'];b=sec['base_m']
 err << 'Toplam genişlik sıfırdan büyük olmalıdır.' if mst_ch_bad_num?(t) || t<=0
 err << 'Taban kalınlığı sıfırdan büyük olmalıdır.' if mst_ch_bad_num?(b) || b<=0
 on=MST_CH_PARTS.select{|k|sec[k] && sec[k]['on']}
 err << 'En az bir çıkıntı açık olmalıdır (çıkıntısız düz plak kanal prekastı olarak oluşturulmaz).' if on.empty?
 on.each do |k|
  p=sec[k];lab=MST_CH_PART_LABELS[k]
  if %w[width_m height_m].any?{|q|mst_ch_bad_num?(p[q]) || p[q]<=0}
   err << "#{lab} çıkıntı: genişlik ve yükseklik sıfırdan büyük olmalıdır."
  end
  if mst_ch_bad_num?(p['offset_m']) || p['offset_m']<0
   err << "#{lab} çıkıntı: ofset negatif olamaz."
  elsif !mst_ch_bad_num?(t) && !mst_ch_bad_num?(p['width_m']) && p['offset_m']+p['width_m']>t+MST_CH_EPS
   err << "#{lab} çıkıntı: ofset + genişlik (#{f3[p['offset_m']+p['width_m']]} m) toplam genişliği (#{f3[t]} m) aşıyor."
  end
 end
 if err.empty?
  a=mst_ch_active(sec)
  a.each_cons(2) do |p,q|
   err << "#{MST_CH_PART_LABELS[p['part']]} ve #{MST_CH_PART_LABELS[q['part']]} çıkıntılar çakışıyor veya bitişik; aralarında boşluk olmalıdır." if q['y0']<=p['y1']+MST_CH_EPS
  end
 end
 err
end

# U-eşdeğeri: sol + sağ açık, orta kapalı, iki ofset 0, eşit genişlik ve yükseklik, iç genişlik > 0, taban > 0.
def mst_ch_u_equiv?(sec)
 return false unless sec.is_a?(Hash) && sec['left'] && sec['right'] && sec['mid']
 l=sec['left'];r=sec['right'];t=sec['total_width_m'];b=sec['base_m']
 return false unless l['on'] && r['on'] && !sec['mid']['on']
 return false if [t,b,l['width_m'],l['height_m'],r['width_m'],r['height_m'],l['offset_m'],r['offset_m']].any?{|v|mst_ch_bad_num?(v)}
 l['offset_m'].abs<=MST_CH_EPS && r['offset_m'].abs<=MST_CH_EPS && (l['width_m']-r['width_m']).abs<=MST_CH_EPS &&
  (l['height_m']-r['height_m']).abs<=MST_CH_EPS && l['width_m']>0 && l['height_m']>0 && b>0 && t-2*l['width_m']>MST_CH_EPS
end

# U-eşdeğeri kesitin eski ölçüleri [wi, di, tb, tw].
def mst_ch_u_dims(sec)
 tw=sec['left']['width_m'].to_f
 # P1b: toplam − 2 × duvar kayan nokta artığı (0,7999999999999999) eski U kaydı / tanım anahtarıyla ayrışmasın → 1e-9 yuvarlama
 [(sec['total_width_m'].to_f-2*tw).round(9),sec['left']['height_m'].to_f,sec['base_m'].to_f,tw]
end

# Dış kontur (y, z; metre), saat yönünün tersi: alt kenar soldan sağa, üst kenar sağdan sola. Eş doğrusal noktalar atılır.
# U-eşdeğerinde nokta sırası eski U profiliyle aynıdır.
def mst_ch_profile(sec)
 t=sec['total_width_m'].to_f;b=sec['base_m'].to_f
 raw=[[0.0,0.0],[t,0.0],[t,b]]
 mst_ch_active(sec).reverse_each{|a|top=b+a['h'];raw << [a['y1'],b] << [a['y1'],top] << [a['y0'],top] << [a['y0'],b]}
 raw << [0.0,b]
 pts=[];raw.each{|q|pts << q unless pts.last && (pts.last[0]-q[0]).abs<=MST_CH_EPS && (pts.last[1]-q[1]).abs<=MST_CH_EPS}
 pts.pop if pts.length>1 && (pts.first[0]-pts.last[0]).abs<=MST_CH_EPS && (pts.first[1]-pts.last[1]).abs<=MST_CH_EPS
 loop do
  i=(0...pts.length).find do |k|
   a=pts[k-1];c=pts[k];d=pts[(k+1)%pts.length]
   ((a[0]-c[0]).abs<=MST_CH_EPS && (c[0]-d[0]).abs<=MST_CH_EPS) || ((a[1]-c[1]).abs<=MST_CH_EPS && (c[1]-d[1]).abs<=MST_CH_EPS)
  end
  break unless i
  pts.delete_at(i)
 end
 pts
end

# Kesit alanı (m²) = toplam × taban + Σ açık çıkıntı genişlik × yükseklik.
def mst_ch_area(sec)
 sec['total_width_m'].to_f*sec['base_m'].to_f+mst_ch_active(sec).sum{|a|(a['y1']-a['y0'])*a['h']}
end

# Toplam yükseklik: taban + en yüksek açık çıkıntı (karar 2 varsayılan); ref = tipte seçilen çıkıntı (channel_top_ref).
def mst_ch_height(sec,ref=nil)
 a=mst_ch_active(sec)
 r=ref.to_s.strip.downcase
 sel=a.find{|x|x['part']==r}
 sec['base_m'].to_f+(sel ? sel['h'] : (a.map{|x|x['h']}.max || 0.0))
end

# Çıkıntılar arası açık göz aralıkları [[y0, y1, alt z]] (taban üstü; döşeme boşluğu P4 için yalnız hesap).
def mst_ch_open_gaps(sec)
 b=sec['base_m'].to_f
 mst_ch_active(sec).each_cons(2).map{|p,q|[p['y1'],q['y0'],b]}.select{|y0,y1,_|y1-y0>MST_CH_EPS}
end

# Dış taban ledge'leri [[y0, y1]]: en dış çıkıntıların dışında kalan taban üstü.
def mst_ch_ledges(sec)
 a=mst_ch_active(sec);t=sec['total_width_m'].to_f
 return [] if a.empty?
 [[0.0,a.first['y0']],[a.last['y1'],t]].select{|y0,y1|y1-y0>MST_CH_EPS}
end

# Rol bazlı kalıp alanları (m²), len boyunca. Dış yan: taban kenarı + en dış çıkıntının dışa bakan yüzü;
# iç yan: açık göze bakan çıkıntı yüzleri; iç taban: göz tabanları; ledge: dış taban üstü; uç: iki kesit yüzü.
def mst_ch_formwork_roles(sec,len)
 a=mst_ch_active(sec);b=sec['base_m'].to_f;l=len.to_f
 gaps=mst_ch_open_gaps(sec)
 inner_side=a.each_cons(2).sum{|p,q|p['h']+q['h']}
 {'OUTER_BOTTOM'=>l*sec['total_width_m'].to_f,
  'OUTER_SIDE'=>a.empty? ? l*2*b : l*(2*b+a.first['h']+a.last['h']),
  'INNER_FLOOR'=>l*gaps.sum{|y0,y1,_|y1-y0},
  'INNER_SIDE'=>l*inner_side,
  'BASE_LEDGE'=>l*mst_ch_ledges(sec).sum{|y0,y1|y1-y0},
  'END_FACE'=>2*mst_ch_area(sec)}
end

# Seçilen rollerin kalıp alanı. flags: {bottom:, sides:, inner:, ends:, ledge:} (ledge yoksa kalıplı).
def mst_ch_formwork(sec,len,flags)
 r=mst_ch_formwork_roles(sec,len)
 fl=mst_ch_flags(flags)
 r.sum{|k,v|fl[MST_CH_KIND_FLAG[k]] ? v : 0.0}
end

def mst_ch_flags(flags)
 f=flags.is_a?(Hash) ? flags : {}
 g=->(k){f.key?(k) ? f[k] : f[k.to_s]}
 {bottom:!!g.(:bottom),sides:!!g.(:sides),inner:!!g.(:inner),ends:!!g.(:ends),ledge:g.(:ledge).nil? ? true : !!g.(:ledge)}
end

# 5 rollü kalıp bayrak dizisi (fw metni sırası) ↔ Hash
def mst_ch_flags_from_list(a);a=a.to_a;{bottom:!!a[0],sides:!!a[1],inner:!!a[2],ends:!!a[3],ledge:a.length>4 ? !!a[4] : true};end

# Yüz rolü (U dışı kesit). n: yüz normali [x, y, z] (birim), cy / cz: yüz merkezinin yerel y / z'si (metre).
def mst_ch_face_kind(sec,n,cy,cz,tol=0.001)
 nx,ny,nz=n.to_a.map(&:to_f);b=sec['base_m'].to_f
 gaps=mst_ch_open_gaps(sec)
 in_gap=->(y){gaps.any?{|y0,y1,_|y>y0+MST_CH_EPS && y<y1-MST_CH_EPS}}
 if nz< -0.999 then 'OUTER_BOTTOM'
 elsif nz>0.999
  if (cz-b).abs<tol then in_gap.(cy) ? 'INNER_FLOOR' : 'BASE_LEDGE'
  else 'WALL_TOP'
  end
 elsif ny.abs>0.999
  (cz>b-tol && in_gap.(cy+(ny>0 ? tol/2.0 : -tol/2.0))) ? 'INNER_SIDE' : 'OUTER_SIDE'
 elsif nx.abs>0.999 then 'END_FACE'
 else 'NON_FORMWORK'
 end
end

# 5 rollü fw metni, kesitte yüzü olmayan rol 0 (L'de iç göz yok, U'da ledge yok): yüzlerden geri okunan (mst_precast_def_params) ile aynı.
def mst_ch_fw_norm(sec,fw)
 r=mst_ch_formwork_roles(sec,1.0);c=fw.to_s.ljust(5,'0').chars
 c[2]='0' unless r['INNER_FLOOR']+r['INNER_SIDE']>MST_CH_EPS
 c[4]='0' unless r['BASE_LEDGE']>MST_CH_EPS
 c.first(5).join
end

def mst_ch_fw_roles(x);mst_ch_custom_section(x) ? MST_CH_FW_ROLES_X : MST_CH_FW_ROLES_U;end

# Geometri anahtarı: yalnız geometriyi belirleyen değerler (ön ayar adı ve pasif çıkıntılar girmez).
# JSON (metre, 6 hane): tanım anahtarı / tanım parametresi; mst_ch_explicit ile geri okunur.
def mst_ch_geom_key(sec)
 h={'v'=>1,'total_width_m'=>sec['total_width_m'].to_f.round(6),'base_m'=>sec['base_m'].to_f.round(6)}
 MST_CH_PARTS.each{|k|p=sec[k];h[k]={'on'=>true,'width_m'=>p['width_m'].to_f.round(6),'height_m'=>p['height_m'].to_f.round(6),'offset_m'=>p['offset_m'].to_f.round(6)} if p && p['on']}
 JSON.generate(h)
end

# mm imzası (tip imzası / ölçü anahtarı; 1 mm toleransla aynı fiziksel kesit).
def mst_ch_geom_sig(sec)
 mmv=->(v){(v.to_f*1000.0).round}
 (["kesit:#{mmv[sec['total_width_m']]}/#{mmv[sec['base_m']]}"]+mst_ch_active(sec).map{|a|p=sec[a['part']];"#{a['part']}:#{mmv[p['width_m']]}x#{mmv[p['height_m']]}@#{mmv[p['offset_m']]}"}).join('/')
end

# Öğeye yazılacak JSON (tüm alanlar; pasif çıkıntı değerleri saklanır). P4: döşeme ledge seçimi yalnız varsa yazılır.
def mst_ch_json(sec)
 s=mst_ch_parse(sec) || sec
 JSON.generate({'v'=>1,'preset'=>s['preset'],'total_width_m'=>s['total_width_m'],'base_m'=>s['base_m']}.merge(Hash[MST_CH_PARTS.map{|k|[k,s[k]]}]).merge(s.select{|k,v|MST_CH_DECK_KEYS.include?(k) && v}))
end

# ---- P4 (ADR K6, kararlar 3, 11): döşeme boşluğu ----
def mst_ch_deck_flag(v)
 s=v.to_s.strip.downcase
 return 'open' if %w[open acik açık].include?(s)
 return 'fill' if %w[fill dolu].include?(s)
 nil
end

def mst_ch_deck_ledges(sec)
 dflt=MST_CH_DECK_FILL_PRESETS.include?(sec['preset'].to_s.upcase) ? 'fill' : 'open'
 {'left'=>mst_ch_deck_flag(sec['deck_ledge_left']) || dflt,'right'=>mst_ch_deck_flag(sec['deck_ledge_right']) || dflt}
end

# Kesit boyunca döşeme şeritleri (yerel metre, taban altı z = 0): [y0, y1, kesim üstü, katı üstü, tür]
#  'proj' — en dış çıkıntı: döşeme çıkıntı üstüne oturur (kesim = katı = çıkıntı üstü);
#  'open' — çıkıntılar arası göz(ler), aradaki çıkıntılar ve açık ledge: kesim PK üstüne (H; eski U'daki prekast kutusu anlamı),
#           üstü döşeme açıklığı; katı üstü taban (göz / ledge) ya da ara çıkıntı üstü;
#  'fill' — dolu ledge: kesim = katı = taban üstü, döşeme betonu taban üstüne iner.
# 'opens': bitişik açık şeritlerin birleşimi [[y0, y1]] — her biri bir döşeme açıklığı (taban üstünden döşeme üstüne).
def mst_ch_deck_strips(sec)
 a=mst_ch_active(sec);t=sec['total_width_m'].to_f;b=sec['base_m'].to_f;hh=mst_ch_height(sec)
 return {'strips'=>[],'opens'=>[],'base'=>b,'height'=>hh} if a.empty?
 lg=mst_ch_deck_ledges(sec);st=[]
 add=->(y0,y1,kind,top){st << (kind=='open' ? [y0,y1,hh,top,kind] : [y0,y1,top,top,kind]) if y1-y0>MST_CH_EPS}
 add.(0.0,a.first['y0'],lg['left'],b)
 a.each_with_index do |p,i|
  add.(a[i-1]['y1'],p['y0'],'open',b) if i>0
  add.(p['y0'],p['y1'],(i==0 || i==a.length-1) ? 'proj' : 'open',b+p['h'])
 end
 add.(a.last['y1'],t,lg['right'],b)
 opens=[]
 st.each{|y0,y1,_,_,k|next unless k=='open';(opens.last && (opens.last[1]-y0).abs<=MST_CH_EPS) ? opens.last[1]=y1 : opens << [y0,y1]}
 {'strips'=>st,'opens'=>opens,'base'=>b,'height'=>hh}
end

end
end
