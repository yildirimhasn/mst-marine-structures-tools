# frozen_string_literal: true
require 'json'
require 'digest'
require_relative 'health_report'
module MAG
 module MarineStructuresTools
  module HealthHistory
   extend self
   DICTIONARY='MAG_MST_HealthHistory'.freeze
   KEY='archive_json'.freeze
   MAX_SNAPSHOTS=50
   MAX_BYTES=8*1024*1024
   def api;MarineStructuresTools;end
   def digest(report);Digest::SHA256.hexdigest(JSON.generate(report));end
   def validate_report(report)
    raise 'Geçmiş kontrol raporu biçimi geçersiz.' unless report.is_a?(Hash)&&report[:schema]=='mst.model-health/1'&&report[:records].is_a?(Array)
    records=report[:records]
    raise 'Geçmiş eleman kaydı geçersiz.' unless records.all?{|r|r.is_a?(Hash)}
    raise 'Geçmiş eleman anahtarları tekrarlanmış.' unless records.map{|r|r[:key]}.uniq.size==records.size
    records.each do |r|
     raise 'Geçmiş eleman kaydı eksik/geçersiz.' unless r[:key].is_a?(String)&&!r[:key].empty?&&r[:checks].is_a?(Array)&&r[:quantities].is_a?(Hash)&&%w[error warning limited checked].include?(r[:state])
     r[:checks].each{|c|raise 'Geçmiş bulgu kaydı geçersiz.' unless c.is_a?(Hash)&&%w[error warning info].include?(c[:severity])&&%i[category code message].all?{|k|c[k].is_a?(String)}}
     r[:quantities].each_value do |q|
      raise 'Geçmiş miktar kaydı geçersiz.' unless q.is_a?(Hash)&&%w[calculated estimated missing invalid not_applicable].include?(q[:state])
      next if %w[missing invalid].include?(q[:state])
      raise 'Geçmiş miktarı sonlu ve negatif olmayan sayı olmalı.' unless q[:value].is_a?(Numeric)&&q[:value].finite?&&q[:value]>=0
     end
    end
    report
   end
   def load(model)
    raw=model.get_attribute(DICTIONARY,KEY,nil)
    return {schema:'mst.health-history/1',next_number:1,snapshots:[]} if raw.nil?
    raise 'Kontrol geçmişi geçersiz/büyük; mevcut kayıt korunuyor.' unless raw.is_a?(String)&&raw.bytesize<=MAX_BYTES
    archive=JSON.parse(raw,symbolize_names:true)
    raise 'Kontrol geçmişi biçimi geçersiz; mevcut kayıt korunuyor.' unless archive.is_a?(Hash)&&archive[:schema]=='mst.health-history/1'&&archive[:snapshots].is_a?(Array)&&archive[:snapshots].size<=MAX_SNAPSHOTS
    numbers=archive[:snapshots].map do |item|
     raise 'Geçmiş sıra numarası geçersiz.' unless item.is_a?(Hash)&&item[:number].is_a?(Integer)&&item[:number]>0&&item[:label].is_a?(String)
     validate_report(item[:report])
     raise 'Geçmiş veri parmak izi uyuşmuyor; kayıt değiştirilmedi.' unless item[:fingerprint]==digest(item[:report])
     item[:number]
    end
    raise 'Geçmiş sıra numaraları uyuşmuyor.' unless numbers.uniq==numbers&&numbers==numbers.sort&&archive[:next_number].is_a?(Integer)&&archive[:next_number]>(numbers.max||0)
    archive
   rescue JSON::ParserError=>error
    raise 'Kontrol geçmişi okunamadı; mevcut kayıt korunuyor.'
   end
   def list(model)
    load(model)[:snapshots].reverse.map{|item|{number:item[:number],label:item[:label],created_at:item[:report][:created_at],version:item[:report][:version],summary:item[:report][:summary],fingerprint:item[:fingerprint]}}
   end
   def save(model,label)
    archive=load(model);name=label.to_s.strip
    raise 'Kontrol adı en fazla 80 karakter olmalı ve kontrol karakteri içermemeli.' if name.length>80||name.match?(/\p{Cc}/)
    raise '50 kayıt sınırına ulaşıldı; eski kayıtlar otomatik silinmedi.' if archive[:snapshots].size>=MAX_SNAPSHOTS
    number=archive[:next_number];name="Kontrol #{number}" if name.empty?
    report=ModelHealth.analyze(model);validate_report(report)
    item={number:number,label:name,report:report,fingerprint:digest(report)}
    archive[:snapshots]<<item;archive[:next_number]=number+1;serialized=JSON.generate(archive)
    raise 'Geçmiş 8 MB sınırını aşıyor; eski kayıtlar otomatik silinmedi.' if serialized.bytesize>MAX_BYTES
    opened=false
    begin
     model.start_operation('MST Model Kontrolünü Kaydet',true);opened=true
     model.set_attribute(DICTIONARY,KEY,serialized);model.commit_operation;opened=false
    rescue
     model.abort_operation if opened;raise
    end
    item
   end
   def persist_edit(model,archive,title)
    serialized=JSON.generate(archive)
    raise 'Geçmiş 8 MB sınırını aşıyor.' if serialized.bytesize>MAX_BYTES
    opened=false
    begin
     model.start_operation(title,true);opened=true
     model.set_attribute(DICTIONARY,KEY,serialized);model.commit_operation;opened=false
    rescue
     model.abort_operation if opened;raise
    end
   end
   def rename(model,number,label)
    archive=load(model);item=archive[:snapshots].find{|s|s[:number].to_s==number.to_s}
    raise 'Adını değiştirmek için kayıt seçin.' unless item
    name=label.to_s.strip
    raise 'Yeni ad 1–80 karakter olmalı ve kontrol karakteri içermemeli.' if name.empty?||name.length>80||name.match?(/\p{Cc}/)
    return item if name==item[:label]
    item[:label]=name;persist_edit(model,archive,'MST Kontrol Adını Değiştir');item
   end
   def delete(model,number)
    archive=load(model);item=archive[:snapshots].find{|s|s[:number].to_s==number.to_s}
    raise 'Silmek için kayıt seçin.' unless item
    archive[:snapshots].delete(item)
    persist_edit(model,archive,'MST Kayıtlı Kontrolü Sil');item
   end
   def bag_difference(left,right)
    result=left.dup
    right.each{|item|index=result.index(item);result.delete_at(index) if index}
    result
   end
   def finding_key(c);c.values_at(:severity,:category,:code,:message);end
   def quantity_changed?(a,b)
    return a!=b if a.nil?||b.nil?
    return true unless a.values_at(:state,:unit,:method,:engine_version)==b.values_at(:state,:unit,:method,:engine_version)
    return false if %w[missing invalid].include?(a[:state])
    av=a[:value];bv=b[:value]
    (av-bv).abs>[1e-6,[av.abs,bv.abs].max*1e-6].max
   end
   def compare_reports(before,after)
    validate_report(before);validate_report(after)
    old=before[:records];current=after[:records];old_uid=old.group_by{|r|r[:uid].to_s.strip};new_uid=current.group_by{|r|r[:uid].to_s.strip}
    reserved={}
    old_uid.each{|uid,rows|reserved[rows.first[:key]]=new_uid[uid].first[:key] if !uid.empty?&&rows.size==1&&new_uid[uid]&.size==1}
    used={};records=[]
    current.each do |r|
     uid=r[:uid].to_s.strip;mate=nil
     if !uid.empty?&&old_uid[uid]&.size==1&&new_uid[uid]&.size==1
      mate=old_uid[uid].first
     else
      mate=old.find{|o|o[:key]==r[:key]&&(!reserved[o[:key]]||reserved[o[:key]]==r[:key])}
     end
     mate=nil if mate&&used[mate[:key]]
     unless mate
      records<<{kind:'added',key:r[:key],id:r[:id],label:r[:label],message:'Kontrol kapsamına eklendi.',new_findings:r[:checks],resolved_findings:[],quantities:[]};next
     end
     used[mate[:key]]=true
     old_keys=mate[:checks].map{|c|finding_key(c)};new_keys=r[:checks].map{|c|finding_key(c)}
     added=bag_difference(new_keys,old_keys).map{|key|r[:checks].find{|c|finding_key(c)==key}}
     resolved=bag_difference(old_keys,new_keys).map{|key|mate[:checks].find{|c|finding_key(c)==key}}
     quantities=(mate[:quantities].keys|r[:quantities].keys).map do |key|
      a=mate[:quantities][key];b=r[:quantities][key]
      {key:key,before:a,after:b} if quantity_changed?(a,b)
     end.compact
     fields=%i[key uid id type state geometry].select{|key|mate[key]!=r[key]}
     next if fields.empty?&&added.empty?&&resolved.empty?&&quantities.empty?
     records<<{kind:'changed',key:r[:key],id:r[:id],label:r[:label],message:fields.include?(:key) ? 'Yerleşim anahtarı değişti; aynı tekil UID ile eşleştirildi.' : 'Kontrol sonucu veya miktar değişti.',fields:fields,new_findings:added,resolved_findings:resolved,quantities:quantities}
    end
    old.reject{|r|used[r[:key]]}.each{|r|records<<{kind:'removed',key:nil,id:r[:id],label:r[:label],message:'Güncel kontrol kapsamında bulunmuyor; silinmiş veya kapsam dışına çıkmış olabilir.',new_findings:[],resolved_findings:[],quantities:[]}}
    {before_at:before[:created_at],after_at:after[:created_at],before_version:before[:version],after_version:after[:version],records:records,
     summary:{added:records.count{|r|r[:kind]=='added'},removed:records.count{|r|r[:kind]=='removed'},changed:records.count{|r|r[:kind]=='changed'},new_findings:records.sum{|r|r[:new_findings].size},resolved_findings:records.sum{|r|r[:resolved_findings].size}},
     limitation:'Kontrol verileri karşılaştırılır; tam geometri revizyonu veya mühendislik onayı değildir. Sürüm/kapsam değişikliği de eski bulguların artık listelenmemesine neden olabilir; bu sonuç giderilme onayı değildir. Kapsamdan çıkan elemanın eski bulguları giderilmiş sayılmaz. Tekil UID yoksa yerleşim anahtarı kullanılır; taşınmış/kimliği değişmiş eleman ayrı eklenen ve çıkan kayıt olabilir.'}
   end
   def compare(model,number)
    item=load(model)[:snapshots].find{|s|s[:number].to_s==number.to_s}
    raise 'Karşılaştırma için kayıtlı kontrol seçin.' unless item
    compare_reports(item[:report],ModelHealth.analyze(model))
   end
   def export_baseline(model,number)
    item=load(model)[:snapshots].find{|s|s[:number].to_s==number.to_s}
    raise 'Dışa aktarmak için kayıtlı kontrol seçin.' unless item
    HealthReport.export_snapshot(item[:report],model_name:"KAYITLI KONTROL ##{item[:number]} — #{item[:label]} (güncel model denetimi değildir)",filename:"MST_Kayitli_Kontrol_#{item[:number]}.html")
   end
   def export_archive(model)
    archive=load(model)
    raise 'Dışa aktarılacak kayıtlı kontrol yok.' if archive[:snapshots].empty?
    # Preserve exact UTF-8 payloads so other tools need not reproduce Ruby JSON formatting.
    archive[:snapshots].each{|item|item[:source_json]=JSON.generate(item[:report])}
    content=JSON.pretty_generate(archive)
    path=UI.savepanel('Kontrol Geçmişini Arşivle','','MST_Kontrol_Gecmisi.json')
    return nil unless path
    path+='.json' unless path.downcase.end_with?('.json')
    SafeReportFile.write(path,content)
    {count:archive[:snapshots].size}
   end
  end
 end
end
