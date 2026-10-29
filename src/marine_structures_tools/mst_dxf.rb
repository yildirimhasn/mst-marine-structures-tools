# frozen_string_literal: true
# v0.50 DX0 — DXF okuyucu (ASCII DXF, AutoCAD R12 … 2018). Proje paftalarından kazık dispozisyonu ve donatı pozlarını okumak için.
#  · Yalnız istenen varlık türleri ayrıştırılır; gömülü resim (OLE2FRAME, 90 MB) gibi büyük kayıtlar satır satır okunmadan atlanır.
#  · Karakterler: AC1018 ve öncesi $DWGCODEPAGE (ANSI_1254 → Windows-1254), AC1021 ve sonrası UTF-8; \U+00D6 kaçışları çözülür.
#  · MTEXT biçim kodları (\P, {\f…;}, \A1; …) temizlenir; %%c → Ø, %%d → °, %%p → ±.
#  · Blok ekleri (INSERT) istenirse açılır: blok içeriği ölçek, dönme ve konumla dünya koordinatına taşınır (iç içe 4 kat).
module MAG
module MarineStructuresTools

MST_DXF_SEP=/\r?\n  0\r?\n/
MST_DXF_DEFAULT_TYPES=%w[TEXT MTEXT CIRCLE LINE LWPOLYLINE INSERT ATTRIB ARC].freeze

def mst_dxf_codepage(cp)
 n=cp.to_s[/\d+/].to_i
 n>0 ? "Windows-#{n}" : 'Windows-1254'
end

# satır dizisi → [[kod, değer], ...]
def mst_dxf_pairs(chunk)
 ls=chunk.split(/\r?\n/)
 out=[[0,ls[0].to_s]];i=1   # ilk satır: tür (grup kodu 0'ın değeri)
 while i+1<ls.length
  out << [ls[i].strip.to_i,ls[i+1]];i+=2
 end
 out
end

def mst_dxf_dec(s,enc)
 return '' if s.nil?
 x=s.dup.force_encoding(enc)
 x=x.encode('UTF-8',invalid: :replace,undef: :replace,replace: '?') unless enc=='UTF-8'
 x=x.dup.force_encoding('UTF-8') if enc=='UTF-8'
 x=x.scrub('?') unless x.valid_encoding?
 x.gsub(/\\U\+([0-9A-Fa-f]{4})/){[$1.to_i(16)].pack('U')}
end

# MTEXT / TEXT görünür metni
def mst_dxf_plain(s)
 t=s.to_s.dup
 t=t.gsub(/\\[Pp]/,"\n").gsub(/\\[ACcFfHhQTWp][^;\\{}]*;/,'').gsub(/\\[LlOoKk]/,'').gsub(/\\S([^;]*)[\^#\/]([^;]*);/){"#{$1}/#{$2}"}
 t=t.gsub(/[{}]/,'').gsub('\\~',' ').gsub('\\\\','\\')
 t=t.gsub(/%%[cC]/,'Ø').gsub(/%%[dD]/,'°').gsub(/%%[pP]/,'±').gsub(/%%[uUoO]/,'')
 t.strip
end

# bir varlık kaydı → hash
#  t: tür, l: katman, x/y/z: ilk nokta (10/20/30), x2/y2: ikinci nokta (11/21), r: yarıçap (40), h: yükseklik (40, metin),
#  rot: dönme (50, derece), text: metin, name: blok adı (2), sx/sy: ölçek (41/42), pts: LWPOLYLINE köşeleri, closed
def mst_dxf_entity(pairs,enc)
 e={'t'=>pairs[0][1].strip}
 xs=[];ys=[];txt=[]
 pairs.each_with_index do |(c,v),k|
  next if k==0
  case c
  when 8 then e['l']||=mst_dxf_dec(v.strip,enc)
  when 2 then e['name']||=mst_dxf_dec(v.strip,enc)
  when 10 then xs << v.to_f;e['x']||=v.to_f
  when 20 then ys << v.to_f;e['y']||=v.to_f
  when 30 then e['z']||=v.to_f
  when 11 then e['x2']||=v.to_f
  when 21 then e['y2']||=v.to_f
  when 40 then e['r']||=v.to_f
  when 41 then e['sx']||=v.to_f
  when 42 then e['sy']||=v.to_f
  when 50 then e['rot']||=v.to_f
  when 51 then e['rot2']||=v.to_f
  when 70 then e['flags']||=v.to_i
  when 1 then txt << v
  when 3 then txt << v if e['t']=='MTEXT'   # MTEXT: 250'lik parçalar (3, 3, …, 1) sırayla
  when 66 then e['attribs']=v.to_i==1
  end
 end
 if %w[TEXT MTEXT ATTRIB ATTDEF].include?(e['t'])
  raw=txt.join
  e['text']=mst_dxf_plain(mst_dxf_dec(raw,enc))
  e['h']=e['r'];e.delete('r')
 end
 if e['t']=='LWPOLYLINE'
  e['pts']=xs.zip(ys);e['closed']=(e['flags'].to_i & 1)==1
 end
 e['sx']||=1.0 if e['t']=='INSERT';e['sy']||=(e['sx'] || 1.0) if e['t']=='INSERT'
 e
end

# dosyayı oku: {'version','insunits','codepage','ents'=>[...],'blocks'=>{ad=>{'base'=>[x,y],'ents'=>[...]}},'skipped'=>{tür=>adet}}
def mst_dxf_read(path,types=MST_DXF_DEFAULT_TYPES)
 data=File.binread(path)
 raise 'DXF değil (ikili DXF ya da DWG olabilir; AutoCAD\'de "DXF olarak kaydet" — ASCII seçin).' unless data[0,2000].include?('SECTION')
 ver=data[/\$ACADVER\r?\n\s*1\r?\n([^\r\n]*)/,1].to_s.strip
 cp=data[/\$DWGCODEPAGE\r?\n\s*3\r?\n([^\r\n]*)/,1].to_s.strip
 ins=data[/\$INSUNITS\r?\n\s*70\r?\n\s*(-?\d+)/,1].to_i
 enc=ver>='AC1021' ? 'UTF-8' : mst_dxf_codepage(cp)
 want={};types.each{|t|want[t]=true}
 out={'version'=>ver,'insunits'=>ins,'codepage'=>cp,'encoding'=>enc,'ents'=>[],'blocks'=>{},'skipped'=>Hash.new(0)}
 sec=lambda do |name|
  i=data.index(/\r?\n  0\r?\nSECTION\r?\n  2\r?\n#{name}\r?\n/)
  return nil unless i
  j=data.index(/\r?\n  0\r?\nENDSEC/,i+10) || data.length
  [i,j]
 end
 each_chunk=lambda do |a,b,&blk|
  p=data.index(MST_DXF_SEP,a+8)   # bölümün ilk kaydı (SECTION / ad satırından sonra)
  while p && p<b
   m=MST_DXF_SEP.match(data,p);st=m.end(0)
   q=data.index(MST_DXF_SEP,st) || b;q=b if q>b
   eol=data.index(/\r?\n/,st) || q
   blk.call(data[st...eol].strip,st,q)
   p=q<b ? q : nil
  end
 end
 if (r=sec.('BLOCKS'))
  cur=nil
  each_chunk.(r[0],r[1]) do |t,st,q|
   if t=='BLOCK'
    pr=mst_dxf_pairs(data[st...q])
    nm=pr.find{|c,_|c==2};nm=mst_dxf_dec(nm ? nm[1].strip : '',enc)
    bx=(pr.find{|c,_|c==10} || [0,'0'])[1].to_f;by=(pr.find{|c,_|c==20} || [0,'0'])[1].to_f
    cur={'base'=>[bx,by],'ents'=>[]};out['blocks'][nm]=cur
   elsif t=='ENDBLK'
    cur=nil
   elsif cur && want[t]
    cur['ents'] << mst_dxf_entity(mst_dxf_pairs(data[st...q]),enc)
   end
  end
 end
 if (r=sec.('ENTITIES'))
  each_chunk.(r[0],r[1]) do |t,st,q|
   if want[t]
    out['ents'] << mst_dxf_entity(mst_dxf_pairs(data[st...q]),enc)
   else
    out['skipped'][t]+=1
   end
  end
 end
 # INSERT ardından gelen ATTRIB'ler INSERT'e bağlanır (sıralı kayıt)
 last=nil
 out['ents'].each{|e| if e['t']=='INSERT' then last=e elsif e['t']=='ATTRIB' && last then (last['attr']||=[]) << e elsif e['t']!='SEQEND' then last=nil end}
 out
end

# blok eklerini aç: dünya koordinatlı düz liste (INSERT'in kendisi de 'ins' olarak kalır)
#  her açılan varlık 'via' (dış blok adları) taşır
def mst_dxf_flatten(dx,max_depth=4)
 out=[]
 tf=lambda do |e,ins,base,via|
  sx=ins['sx'] || 1.0;sy=ins['sy'] || sx;a=(ins['rot'] || 0.0)*Math::PI/180.0;ca=Math.cos(a);sa=Math.sin(a)
  f=->(x,y){u=(x-base[0])*sx;v=(y-base[1])*sy;[ins['x'].to_f+u*ca-v*sa,ins['y'].to_f+u*sa+v*ca]}
  n=e.dup;n['via']=via
  if n['x'] && n['y'] then n['x'],n['y']=f.(n['x'],n['y']) end
  if n['x2'] && n['y2'] then n['x2'],n['y2']=f.(n['x2'],n['y2']) end
  n['pts']=n['pts'].map{|x,y|f.(x,y)} if n['pts']
  n['r']=n['r']*sx.abs if n['r'] && %w[CIRCLE ARC].include?(n['t'])
  n['h']=n['h']*sy.abs if n['h']
  n['rot']=(n['rot'] || 0.0)+(ins['rot'] || 0.0) if %w[TEXT MTEXT INSERT].include?(n['t'])
  n['l']=ins['l'] if n['l'].to_s=='0'   # katman 0: ekin katmanını alır
  n
 end
 walk=lambda do |es,depth,via,xf|
  es.each do |e|
   w=xf ? xf.(e) : e
   out << w
   next unless w['t']=='INSERT' && depth<max_depth
   b=dx['blocks'][w['name'].to_s];next unless b
   walk.(b['ents'],depth+1,via+[w['name'].to_s],->(x){tf.(x,w,b['base'],via+[w['name'].to_s])})
  end
 end
 walk.(dx['ents'],0,[],nil)
 out
end

# birim: dosyadaki 1 birim kaç metre? Önce bilinen ölçü (kazık çapı vb.) ile, yoksa $INSUNITS ile.
#  known: [[çizimdeki değer, metre cinsinden gerçek değer], ...] (ör. kazık dairesi yarıçapı ↔ katman adındaki çap)
MST_DXF_INSUNITS={1=>0.0254,2=>0.3048,4=>0.001,5=>0.01,6=>1.0,14=>0.1}.freeze
def mst_dxf_unit(dx,known=[])
 cands=[0.001,0.01,0.1,1.0]
 unless known.empty?
  best=cands.min_by{|u|known.sum{|v,real|((v*u)/real-1.0).abs}}
  err=known.sum{|v,real|((v*best)/real-1.0).abs}/known.length
  return [best,'ölçüden',err] if err<0.08
 end
 u=MST_DXF_INSUNITS[dx['insunits'].to_i]
 return [u,'$INSUNITS',nil] if u
 [1.0,'varsayılan (m)',nil]
end
def mst_dxf_unit_name(u)
 {0.001=>'mm',0.01=>'cm',0.1=>'dm',1.0=>'m',0.0254=>'inç',0.3048=>'ft'}[u] || format('%.4g m',u)
end

end
end
