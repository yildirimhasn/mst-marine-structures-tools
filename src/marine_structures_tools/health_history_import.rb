# frozen_string_literal: true
require_relative 'health_history'
require 'securerandom'
module MAG
 module MarineStructuresTools
  module HealthHistoryImport
   extend self
   H=HealthHistory
   MAX_FILE_BYTES=32*1024*1024
   def preview(model,path)
    current=H.load(model)
    raw=File.open(path,'rb'){|f|f.read(MAX_FILE_BYTES+1)}
    raise 'Arşiv dosyası 32 MB sınırını aşıyor.' if raw.bytesize>MAX_FILE_BYTES
    raw.force_encoding('UTF-8');raise 'Arşiv UTF-8 olmalı.' unless raw.valid_encoding?
    archive=JSON.parse(raw,symbolize_names:true)
    raise 'Desteklenmeyen kontrol arşivi.' unless archive.is_a?(Hash)&&archive[:schema]=='mst.health-history/1'&&archive[:snapshots].is_a?(Array)&&archive[:snapshots].size<=H::MAX_SNAPSHOTS
    numbers=[];seen=current[:snapshots].map{|i|i[:fingerprint]}
    entries=archive[:snapshots].map do |item|
     raise 'Arşiv kayıt bilgisi geçersiz.' unless item.is_a?(Hash)&&item[:number].is_a?(Integer)&&item[:number]>0&&item[:label].is_a?(String)&&!item[:label].strip.empty?&&item[:label].length<=80&&!item[:label].match?(/\p{Cc}/)
     numbers<<item[:number];H.validate_report(item[:report])
     raise 'Arşiv rapor üst bilgisi eksik.' unless item[:report][:created_at].is_a?(String)&&item[:report][:version].is_a?(String)&&item[:report][:summary].is_a?(Hash)
     source=item[:source_json]
     if source
      raise 'Arşiv kaynak verisi/parmak izi uyuşmuyor.' unless source.is_a?(String)&&Digest::SHA256.hexdigest(source.encode('UTF-8'))==item[:fingerprint]&&JSON.parse(source,symbolize_names:true)==item[:report]
     end
     raise 'Arşiv rapor parmak izi uyuşmuyor.' unless item[:fingerprint]==H.digest(item[:report])
     duplicate=seen.include?(item[:fingerprint]);seen<<item[:fingerprint]
     {source_number:item[:number],label:item[:label],report:item[:report],fingerprint:item[:fingerprint],duplicate:duplicate,number_conflict:current[:snapshots].any?{|s|s[:number]==item[:number]}}
    end
    raise 'Arşiv sıra numaraları geçersiz.' unless numbers.uniq==numbers&&numbers==numbers.sort&&archive[:next_number].is_a?(Integer)&&archive[:next_number]>(numbers.max||0)
    {token:SecureRandom.hex(16),model:model,previous:model.get_attribute(H::DICTIONARY,H::KEY,nil),entries:entries,filename:File.basename(path)}
   end
   def view(plan)
    {token:plan[:token],filename:plan[:filename],entries:plan[:entries].map{|i|i.reject{|k,_|%i[report fingerprint].include?(k)}},limitation:'Mevcut kayıtlar korunur. Eklenen kayıtlara yeni numara verilir. Aynı rapor verisi tekrar eklenmez. Arşivin bu modele ait olduğu otomatik doğrulanamaz; karşılaştırma için model kaynağını kontrol edin.'}
   end
   def apply(model,plan,token,numbers)
    raise 'İçe aktarma önizlemesi geçersiz; yeniden dosya seçin.' unless plan&&plan[:model].equal?(model)&&token==plan[:token]
    raise 'Kontrol geçmişi değişti; yeniden önizleyin.' unless plan[:previous]==model.get_attribute(H::DICTIONARY,H::KEY,nil)
    raise 'Seçili kayıt listesi geçersiz.' unless numbers.is_a?(Array)&&numbers.all?{|n|n.is_a?(Integer)}&&numbers.uniq==numbers
    entries=plan[:entries].select{|i|numbers.include?(i[:source_number])&&!i[:duplicate]}
    raise 'İçe aktarmak için yeni kayıt seçin.' if entries.empty?||entries.size!=numbers.size
    archive=H.load(model)
    raise 'Seçim 50 kayıt sınırını aşıyor; daha az kayıt seçin.' if archive[:snapshots].size+entries.size>H::MAX_SNAPSHOTS
    entries.each do |item|
     archive[:snapshots]<<{number:archive[:next_number],label:item[:label],report:item[:report],fingerprint:item[:fingerprint]}
     archive[:next_number]+=1
    end
    H.persist_edit(model,archive,'MST Kontrol Geçmişini İçe Aktar')
    {count:entries.size}
   end
  end
 end
end
