# frozen_string_literal: true
# ADR-0515-K3 P5 (docs/duzeltme/41, kullanıcı kararı 1) — kullanıcı düzeyi PK tip kütüphanesi dosyası, elle dışa ver / içe al.
# Esas kütüphane model kopyasındadır (precast_type_library_json); dosya %APPDATA%\MarineStructuresTools\PKLibrary\pk_types.json
# yalnız kullanıcı istediğinde okunur / yazılır, otomatik eşzamanlama yoktur. Aynı kod + farklı geom_sig birleşmez (atlanır, raporlanır).
# Dosya biçimi: {"format":"mst_pk_types","v":1,"tipler":[<model kütüphanesindeki PK kaydı, aynen>]}. Bilinmeyen üst düzey ve kayıt alanları
# korunur. v > 1: listelenir (salt okuma + uyarı), dışa ver / içe al yapılmaz. Bozuk / beklenmeyen içerikte dosyanın üzerine yazılmaz.
# Yazım atomik (boq_library.rb write_storage deseni: geçici dosya + fsync + doğrulama + rename); var olan dosya önce .bak'a kopyalanır.
# Dışa ver modeli değiştirmez (işlem açmaz). İçe al: tek normal işlem "MST PK Tiplerini İçe Al" (başarıda commit, hatada abort).
# Model tipini dosyadan güncellemek yoktur (yalnız bildirilir; güncelleme P4 tip düzenleme akışıyla).
require 'json'
require 'fileutils'
require 'securerandom'
module MAG
module MarineStructuresTools

MST_PKF_FORMAT='mst_pk_types'
MST_PKF_V=1

# Test için temel klasör enjeksiyonu (nil → APPDATA; boq_library.rb storage_directory ile aynı geri dönüş).
def mst_pkf_base=(v);@mst_pkf_base=v;end

def mst_pkf_path
  base=@mst_pkf_base
  if base.nil? || base.to_s.empty?
    base=ENV['APPDATA']
    base=File.join(Dir.home,'Library','Application Support') if base.nil? || base.empty?
  end
  File.join(base,'MarineStructuresTools','PKLibrary','pk_types.json')
end

# Dosya → {'durum'=>yok|bos|tamam|bozuk, 'neden', 'data' (Hash), 'tipler' (Array<Hash>), 'salt'=>true (v > 1)}. Salt okuma.
def mst_pkf_read(path=mst_pkf_path)
  return {'durum'=>'yok','neden'=>nil,'data'=>nil,'tipler'=>[],'salt'=>false} unless File.exist?(path)
  bad=->(msg){{'durum'=>'bozuk','neden'=>"PK kütüphanesi dosyası okunamadı (#{msg}); dosyaya dokunulmadı. Dosyayı yedekleyip düzeltin veya taşıyın.",'data'=>nil,'tipler'=>[],'salt'=>true}}
  raw=begin
    File.binread(path).force_encoding('UTF-8')
  rescue => e
    return bad.(e.message)
  end
  raw=raw.sub(/\A﻿/,'') if raw.valid_encoding?
  return bad.('geçersiz karakter kodlaması') unless raw.valid_encoding?
  return {'durum'=>'bos','neden'=>nil,'data'=>nil,'tipler'=>[],'salt'=>false} if raw.strip.empty?
  data=(JSON.parse(raw) rescue nil)
  return bad.('JSON değil') if data.nil?
  return bad.('beklenen biçim değil') unless data.is_a?(Hash) && data['format']==MST_PKF_FORMAT
  v=data['v']
  return bad.('sürüm alanı okunamadı') unless v.is_a?(Integer) && v>=1
  tl=data['tipler']
  return bad.('tip listesi okunamadı') unless tl.is_a?(Array) && tl.all?{|x|x.is_a?(Hash)}
  if v>MST_PKF_V
    return {'durum'=>tl.empty? ? 'bos' : 'tamam','neden'=>"PK kütüphanesi dosyası daha yeni bir MST sürümüyle yazılmış (biçim v#{v}); yalnız listelenir, dışa ver / içe al yapılmaz.",
            'data'=>data,'tipler'=>tl,'salt'=>true}
  end
  {'durum'=>tl.empty? ? 'bos' : 'tamam','neden'=>nil,'data'=>data,'tipler'=>tl,'salt'=>false}
end

# Kaydın geometri imzası: kesit + oturmadan yeniden hesaplanır (bayat saklı imzaya güvenilmez); hesaplanamazsa saklı geom_sig; yoksa nil.
def mst_pkf_sig(t)
  s=begin
    g=mst_pk_geom(t,true)
    if g && g['errors'].empty? && g['section']
      sl=t['seat_left_m'];sr=t['seat_right_m']
      mst_pk_geom_sig(g['section'],(sl.nil? || sl.to_s.strip.empty?) ? nil : sl,(sr.nil? || sr.to_s.strip.empty?) ? nil : sr)
    end
  rescue
    nil
  end
  s=t['geom_sig'].to_s.strip if s.nil? || s.to_s.empty?
  s.to_s.empty? ? nil : s
end

def mst_pkf_kod(t);t['name'].to_s.strip;end
def mst_pkf_same_kod?(a,b);!mst_pkf_kod(a).empty? && mst_pkf_kod(a).downcase==mst_pkf_kod(b).downcase;end
def mst_pkf_same_sig?(a,b);sa=mst_pkf_sig(a);!sa.nil? && sa==mst_pkf_sig(b);end
def mst_pkf_rev(t);t['pk_rev'].to_i;end

# Model kütüphanesi (tam liste) → Array<Hash> ya da nil (okunamıyor). Boş → [].
def mst_pkf_model_lib(model)
  cur=model.get_attribute(DICT,'precast_type_library_json','').to_s
  return [] if cur.strip.empty?
  lib=(JSON.parse(cur) rescue nil)
  lib.is_a?(Array) && lib.all?{|x|x.is_a?(Hash)} ? lib : nil
end

# Dosya kaydının modeldeki karşılığı: aynı uid ya da aynı kod + aynı geometri → ayni; aynı kod farklı geometri → kod_cakisma;
# farklı kod aynı geometri → geom_ayni_kod_farkli; yoksa yok. → [durum, eşleşen model kaydının kodu ya da nil]
def mst_pkf_model_state(t,mpk)
  u=t['uid'].to_s.strip
  m=u.empty? ? nil : mpk.find{|x|x['uid'].to_s.strip==u}
  return ['ayni',mst_pkf_kod(m)] if m
  sk=mpk.find{|x|mst_pkf_same_kod?(x,t)}
  return [mst_pkf_same_sig?(sk,t) ? 'ayni' : 'kod_cakisma',mst_pkf_kod(sk)] if sk
  sg=mpk.find{|x|mst_pkf_same_sig?(x,t)}
  return ['geom_ayni_kod_farkli',mst_pkf_kod(sg)] if sg
  ['yok',nil]
end

# pk_lib_file_list → yük (salt okuma; dosyaya ve modele dokunmaz).
def mst_pk_lib_file_list(model=Sketchup.active_model)
  path=mst_pkf_path;f=mst_pkf_read(path)
  mpk=(mst_pkf_model_lib(model) || []).select{|x|x['family'].to_s=='PK'}
  tl=f['tipler'].map do |t|
    st,mk=mst_pkf_model_state(t,mpk)
    {'uid'=>t['uid'],'kod'=>mst_pkf_kod(t),'ad'=>t['title'].to_s,'rev'=>t['pk_rev'],'geom_sig'=>mst_pkf_sig(t),
     'section'=>t['section'],'created_at'=>t['created_at'],'modelde'=>st,'modeldeki_kod'=>mk}
  end
  {'ok'=>f['durum']!='bozuk','neden'=>f['neden'],'yol'=>path,'durum'=>f['durum'],'tipler'=>tl}
end

# Atomik yazım: (1) var olan dosya .bak'a (geçici + rename), (2) yeni içerik geçici dosyaya + fsync + doğrulama, (3) rename.
# Herhangi bir adımda hata → istisna; ana dosya değişmemiş kalır, geçici dosyalar silinir.
def mst_pkf_atomic_write(path,raw)
  FileUtils.mkdir_p(File.dirname(path))
  put=lambda do |dst,bytes|
    tmp=dst+'.'+SecureRandom.uuid+'.tmp'
    begin
      File.open(tmp,'wb'){|f|f.write(bytes);f.flush;f.fsync}
      raise 'PK kütüphanesi dosyası yazılırken doğrulama başarısız.' unless File.binread(tmp)==bytes.b
      File.rename(tmp,dst)
      raise 'PK kütüphanesi dosyası geri okunamadı.' unless File.binread(dst)==bytes.b
    ensure
      File.delete(tmp) if File.exist?(tmp)
    end
  end
  put.(path+'.bak',File.binread(path)) if File.exist?(path)
  put.(path,raw)
end

# pk_lib_file_export: istek {uids:[…]} → modeldeki seçili PK kayıtları dosyaya eklenir / güncellenir. Model değişmez.
def mst_pk_lib_file_export(rq,model=Sketchup.active_model)
  path=mst_pkf_path
  out={'ok'=>true,'neden'=>nil,'eklenen'=>0,'guncellenen'=>0,'atlanan'=>[],'yol'=>path}
  fail=->(msg){out.merge('ok'=>false,'neden'=>msg)}
  rq={} unless rq.is_a?(Hash)
  uids=rq['uids'].is_a?(Array) ? rq['uids'].map{|x|x.to_s.strip}.reject(&:empty?).uniq : []
  return fail.('Dışa verilecek PK tipi seçilmedi.') if uids.empty?
  mlib=mst_pkf_model_lib(model)
  return fail.('Modeldeki prekast tip kütüphanesi okunamadı; dışa verme yapılmadı.') unless mlib
  f=mst_pkf_read(path)
  return fail.(f['neden']) if f['durum']=='bozuk' || f['salt']
  data=f['data'] || {'format'=>MST_PKF_FORMAT,'v'=>MST_PKF_V,'tipler'=>[]}
  list=f['tipler'].map(&:dup)
  skip=->(kod,why){out['atlanan'] << {'kod'=>kod,'neden'=>why}}
  uids.each do |u|
    r=mlib.find{|x|x['uid'].to_s.strip==u}
    next skip.(u,'Modeldeki kütüphanede bulunamadı.') unless r
    next skip.(mst_pkf_kod(r).empty? ? u : mst_pkf_kod(r),'PK tipi değil; yalnız PK tipleri dışa verilir.') unless r['family'].to_s=='PK'
    kod=mst_pkf_kod(r)
    next skip.(u,'PK kodu boş; dışa verilmedi.') if kod.empty?
    rc=JSON.parse(JSON.generate(mst_pk_json_safe(r)))
    i=list.index{|x|x['uid'].to_s.strip==u}
    other=list.find{|x|x['uid'].to_s.strip!=u && mst_pkf_same_kod?(x,r)}
    if other
      why=mst_pkf_same_sig?(other,r) ? "Dosyada aynı kod ve geometriyle başka bir kayıt var (#{other['uid']}); eklenmedi." :
                                       "Dosyada '#{mst_pkf_kod(other)}' kodu farklı geometride kullanılıyor; farklı geometriler birleştirilmez. Tipi modelde başka bir kodla kaydedip yeniden dışa verin."
      next skip.(kod,why)
    end
    if i
      fr=mst_pkf_rev(list[i]);mr=mst_pkf_rev(r)
      next skip.(kod,"Dosyadaki kayıt aynı ya da daha yeni revizyonda (dosya rev #{fr}, model rev #{mr}); güncellenmedi.") unless mr>fr
      list[i]=list[i].merge(rc);out['guncellenen']+=1
    else
      list << rc;out['eklenen']+=1
    end
  end
  return out if out['eklenen']+out['guncellenen']==0
  raw=JSON.pretty_generate(data.merge('tipler'=>list))
  begin
    mst_pkf_atomic_write(path,raw)
  rescue => e
    return fail.("PK kütüphanesi dosyası yazılamadı; önceki dosya korundu: #{e.message}").merge('eklenen'=>0,'guncellenen'=>0)
  end
  out
end

# pk_lib_file_import: istek {uids:[…], kutuphane:<JS tam liste>} → dosyadaki seçili kayıtlar model kütüphanesine eklenir.
def mst_pk_lib_file_import(rq,model=Sketchup.active_model,elems=nil)
  lj=->{model.get_attribute(DICT,'precast_type_library_json','').to_s}
  out={'ok'=>true,'neden'=>nil,'eklenen'=>0,'atlanan'=>[]}
  fail=->(msg){out.merge('ok'=>false,'neden'=>msg)}
  rq={} unless rq.is_a?(Hash)
  uids=rq['uids'].is_a?(Array) ? rq['uids'].map{|x|x.to_s.strip}.reject(&:empty?).uniq : []
  return fail.('İçe alınacak PK tipi seçilmedi.') if uids.empty?
  f=mst_pkf_read
  return fail.('PK kütüphanesi dosyası yok; önce tipleri dışa verin.') if f['durum']=='yok'
  return fail.(f['neden']) if f['durum']=='bozuk' || f['salt']
  return fail.('PK kütüphanesi dosyası boş.') if f['durum']=='bos'
  mlib=mst_pkf_model_lib(model)
  return fail.('Modeldeki prekast tip kütüphanesi okunamadı; üzerine yazılmadı.') unless mlib
  lib=rq.key?('kutuphane') && !rq['kutuphane'].nil? ? rq['kutuphane'] : mlib
  return fail.('Arayüzden gelen tip listesi okunamadı; içe alma yapılmadı.') unless lib.is_a?(Array) && lib.all?{|t|t.is_a?(Hash)}
  lib=lib.dup
  skip=->(kod,why){out['atlanan'] << {'kod'=>kod,'neden'=>why}}
  added=[]
  uids.each do |u|
    t=f['tipler'].find{|x|x['uid'].to_s.strip==u}
    next skip.(u,'Dosyada bulunamadı.') unless t
    kod=mst_pkf_kod(t)
    next skip.(kod.empty? ? u : kod,'PK tipi değil; içe alınmadı.') unless t['family'].to_s=='PK'
    begin
      k2=mst_code_validate(kod,MST_NAME_MAX_STRUCTURE,'PK kodu')
    rescue => ex
      next skip.(kod.empty? ? u : kod,ex.message)
    end
    next skip.(u,'PK kodu boş; içe alınmadı.') if k2.empty?
    g=(mst_pk_geom(t,true) rescue nil)
    next skip.(kod,'Kayıttaki kesit verisi okunamadı veya geçersiz; içe alınmadı.') unless g && g['errors'].empty? && g['section']
    m=lib.find{|x|x['uid'].to_s.strip==u}
    if m
      fr=mst_pkf_rev(t);mr=mst_pkf_rev(m)
      next skip.(kod,fr>mr ? "Modelde bu tip var; dosyadaki revizyon daha yeni (dosya rev #{fr}, model rev #{mr}). Model tipi içe almayla güncellenmez; Tip Düzenleme'yi kullanın." :
                             'Modelde bu tip zaten var.')
    end
    sk=lib.find{|x|mst_pkf_same_kod?(x,t)}
    if sk
      next skip.(kod,sk['family'].to_s=='PK' && mst_pkf_same_sig?(sk,t) ? "Modelde aynı kod ve geometriyle kayıtlı bir tip var (#{mst_pkf_kod(sk)}); içe alınmadı." :
                                                                           "'#{kod}' kodu modelde başka bir tipte kullanılıyor; farklı geometriler birleştirilmez.")
    end
    sg=lib.find{|x|x['family'].to_s=='PK' && mst_pkf_same_sig?(x,t)}
    next skip.(kod,"Aynı geometri modelde #{mst_pkf_kod(sg)} koduyla kayıtlı; mevcut tipi kullanın: #{mst_pkf_kod(sg)}") if sg
    # kod modelde kütüphane dışı bir prekastta farklı kesitle kullanılıyor mu (mst_pk_type_save ile aynı denetim)
    unless elems
      elems=[];collect_elements(model.entities,elems)
    end
    ssig=(mst_pk_section_sig(g['section']) rescue nil)
    clash=elems.find do |e|
      next false unless e.valid? && MST_PRECAST_TYPES.include?(e.get_attribute(DICT,'element_type','').to_s) && mst_precast_type_id(e).downcase==kod.downcase
      e.get_attribute(DICT,'element_type','').to_s!='channel_precast' || (mst_pk_section_sig(mst_pk_geom(e,false)['section']) rescue nil)!=ssig
    end
    next skip.(kod,"'#{kod}' kodu modelde farklı ölçülü/sınıflı bir prekastta kullanılıyor; içe alınmadı.") if clash
    rc=JSON.parse(JSON.generate(mst_pk_json_safe(t)))
    lib << rc;added << rc
  end
  return out.merge('kutuphane_json'=>lj.()) if added.empty?
  txt=JSON.generate(lib)
  model.start_operation('MST PK Tiplerini İçe Al',true)
  begin
    model.set_attribute(DICT,'precast_type_library_json',txt)
    model.commit_operation
  rescue => ex
    model.abort_operation
    return fail.("PK tipleri içe alınamadı; işlem geri alındı: #{ex.message}").merge('kutuphane_json'=>lj.())
  end
  out.merge('eklenen'=>added.size,'kutuphane_json'=>lj.())
end

# HtmlDialog callback'leri → window.mstPkLibFile / mstPkLibFileExported / mstPkLibFileImported; her durumda yanıt verilir.
def mst_pkf_send(dlg,fn,pl)
  dlg.execute_script("window.#{fn} && #{fn}(#{JSON.generate(mst_pk_json_safe(pl))})")
end

def mst_pk_send_lib_file_list(dlg)
  pl=begin
    mst_pk_lib_file_list(Sketchup.active_model)
  rescue => e
    {'ok'=>false,'neden'=>"PK kütüphanesi dosyası okunamadı: #{e.message}",'yol'=>(mst_pkf_path rescue ''),'durum'=>'bozuk','tipler'=>[]}
  end
  mst_pkf_send(dlg,'mstPkLibFile',pl)
end

def mst_pk_send_lib_file_export(dlg,raw)
  pl=begin
    rq=(JSON.parse(raw.to_s) rescue nil)
    rq.is_a?(Hash) ? mst_pk_lib_file_export(rq,Sketchup.active_model) : {'ok'=>false,'neden'=>'Arayüzden gelen veri okunamadı; dışa verme yapılmadı.','eklenen'=>0,'guncellenen'=>0,'atlanan'=>[]}
  rescue => e
    {'ok'=>false,'neden'=>"PK tipleri dışa verilemedi: #{e.message}",'eklenen'=>0,'guncellenen'=>0,'atlanan'=>[]}
  end
  pl['yol']||=(mst_pkf_path rescue '')
  mst_pkf_send(dlg,'mstPkLibFileExported',pl)
end

def mst_pk_send_lib_file_import(dlg,raw)
  model=Sketchup.active_model
  pl=begin
    rq=(JSON.parse(raw.to_s) rescue nil)
    rq.is_a?(Hash) ? mst_pk_lib_file_import(rq,model) : {'ok'=>false,'neden'=>'Arayüzden gelen veri okunamadı; içe alma yapılmadı.','eklenen'=>0,'atlanan'=>[]}
  rescue => e
    {'ok'=>false,'neden'=>"PK tipleri içe alınamadı: #{e.message}",'eklenen'=>0,'atlanan'=>[]}
  end
  pl['kutuphane_json']||=(model.get_attribute(DICT,'precast_type_library_json','').to_s rescue '')
  mst_pkf_send(dlg,'mstPkLibFileImported',pl)
end

end
end
