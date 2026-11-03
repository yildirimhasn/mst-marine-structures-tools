# frozen_string_literal: true
require 'json'
require 'date'
require 'securerandom'
require 'fileutils'
module MAG
  module MarineStructuresTools
    module BOQLibrary
      extend self
      SECTION = 'MAG_MST_BOQLibrary'.freeze
      LIMIT = 5000
      MAX_BYTES = 2_000_000
      UNITS = %w[LS ad m m² m³ kg ton pkt saat komp.].freeze
      FIELDS = %w[id project year date code name unit quantity unit_price currency source note source_file source_sheet source_row source_sha256 price_scope section raw_unit catalog_key rate_description archive_history model_project model_date].freeze

      def text(value, max=240)
        s=value.to_s.strip
        raise 'Metin alanı çok uzun.' if s.length>max
        s
      end

      def number(value)
        return nil if value.nil? || value.to_s.strip.empty?
        n=Float(value)
        raise 'Miktar/fiyat sıfır veya pozitif ve sonlu olmalı.' unless n.finite? && n>=0
        n
      rescue ArgumentError, TypeError
        raise 'Miktar ve fiyat geçerli sayı olmalı (ondalık ayıracı nokta).'
      end

      def record(data, generate_id=false)
        raise 'Geçersiz kayıt.' unless data.is_a?(Hash)
        r={}
        FIELDS.each { |k| r[k]=text(data[k], {'note'=>2000,'rate_description'=>20000,'archive_history'=>100000}.fetch(k,240)) }
        r['id']=SecureRandom.uuid if generate_id
        raise 'Kayıt kimliği eksik.' if r['id'].empty?
        %w[project code name].each { |k| raise "Zorunlu alan eksik: #{k}" if r[k].empty? }
        # Rename only generated catalogue codes; retain their numeric suffix.
        if !r['catalog_key'].empty? && r['code'].match?(/\AMST-P-\d+\z/)
          r['code']=r['code'].sub('MST-P-','ÖBF-')
        end
        if MarineStructuresTools.const_defined?(:BOQ_LIBRARY_IDS)
          key=MarineStructuresTools::BOQ_LIBRARY_IDS.key(r['id'])
          r['source']=key if key
        end
        raise 'Yıl 1900–2200 arasında olmalı.' unless r['year'].empty? || (r['year'].match?(/\A\d{4}\z/) && (1900..2200).include?(r['year'].to_i))
        r['year']=r['year'].empty? ? nil : r['year'].to_i
        Date.iso8601(r['date']) unless r['date'].empty?
        raise 'Birim desteklenmiyor.' unless UNITS.include?(r['unit'])
        r['currency']=r['currency'].upcase
        raise 'Para birimi 3 harf olmalı (USD, EUR, TRY vb.).' unless r['currency'].empty? || r['currency'].match?(/\A[A-Z]{3}\z/)
        r['quantity']=number(data['quantity']); r['unit_price']=number(data['unit_price'])
        if r['quantity'] && r['unit_price']
          raise 'Miktar × fiyat hesap sınırını aşıyor.' unless (r['quantity']*r['unit_price']).finite?
        end
        r
      end

      def decode(raw)
        raise 'Kütüphane verisi geçerli JSON metni olmalı.' unless raw.is_a?(String)
        raise 'Kütüphane dosyası 2 MB sınırını aşıyor.' if raw.bytesize>MAX_BYTES
        doc=JSON.parse(raw)
        raise 'Desteklenmeyen kütüphane biçimi.' unless doc.is_a?(Hash) && %w[mst.boq-library/1 mst.boq-library/2].include?(doc['schema']) && doc['records'].is_a?(Array)
        raise 'En fazla 5000 kayıt destekleniyor.' if doc['records'].length>LIMIT
        records=doc['records'].map { |r| record(r) }
        raise 'Tekrarlanan kayıt kimliği.' unless records.map { |r| r['id'] }.uniq.length==records.length
        records
      end

      def encode(records)
        JSON.generate({'schema'=>'mst.boq-library/2','records'=>records})
      end

      def load
        raw=stored_records
        rows=decode(raw)
        original=JSON.parse(raw)['records']
        if original.zip(rows).any? { |old,row| old['code']!=row['code'] }
          save(rows)
        end
        rows
      end

      def stored_records
        path=File.join(storage_directory,'records.json')
        return File.read(path,encoding:'UTF-8') if File.exist?(path)
        raw=Sketchup.read_default(SECTION,'records',nil)
        # Some SketchUp versions return nil even with a supplied default.
        # Only absent storage is empty; malformed nonempty data must surface.
        raw.nil? ? encode([]) : raw
      end

      def storage_directory
        base=ENV['APPDATA']
        base=File.join(Dir.home,'Library','Application Support') if base.nil? || base.empty?
        File.join(base,'MarineStructuresTools','BOQLibrary')
      end

      def write_storage(name,raw)
        decode(raw)
        FileUtils.mkdir_p(storage_directory)
        path=File.join(storage_directory,name+'.json')
        temporary=path+'.'+SecureRandom.uuid+'.tmp'
        begin
          File.open(temporary,'wb') { |f| f.write(raw); f.flush; f.fsync }
          raise 'Kütüphane dosyası yazılırken doğrulama başarısız.' unless File.binread(temporary)==raw.b
          File.rename(temporary,path)
          raise 'Kütüphane dosyası geri okunamadı.' unless File.binread(path)==raw.b
        ensure
          File.delete(temporary) if File.exist?(temporary)
        end
      end

      def save(records)
        raw=encode(records)
        decode(raw) # Validate everything before either write.
        previous=stored_records
        return if raw==previous && File.exist?(File.join(storage_directory,'records.json'))
        write_storage('previous',previous)
        write_storage('records',raw)
        raise 'Kayıt doğrulaması başarısız; başarı bildirimi verilmedi.' unless load==decode(raw)
      end

      def undo
        path=File.join(storage_directory,'previous.json')
        previous=File.exist?(path) ? File.read(path,encoding:'UTF-8') : Sketchup.read_default(SECTION,'previous',nil)
        raise 'Geri alınacak kütüphane değişikliği yok.' unless previous
        save(decode(previous))
      end

      def upsert(data)
        rows=load
        id=data['id'].to_s
        if id.empty?
          rows << record(data,true)
        else
          index=rows.index { |r| r['id']==id }
          raise 'Düzenlenecek kayıt bulunamadı; listeyi yenileyin.' unless index
          rows[index]=record(rows[index].merge(data))
        end
        save(rows)
      end

      def remove(id)
        rows=load
        raise 'Kayıt bulunamadı.' unless rows.any? { |r| r['id']==id }
        save(rows.reject { |r| r['id']==id })
      end

      def signature(r)
        FIELDS.reject { |k| k=='id' }.map { |k| r[k] }
      end

      def merge(incoming)
        rows=load; seen={}; ids={}; catalog_keys={}; added=0
        rows.each { |r| seen[signature(r)]=true; ids[r['id']]=true; catalog_keys[r['catalog_key']]=true unless r['catalog_key'].empty? }
        incoming.each do |item|
          r=record(item)
          next if !r['catalog_key'].empty? && catalog_keys[r['catalog_key']]
          next if seen[signature(r)]
          r=r.merge('id'=>SecureRandom.uuid) if ids[r['id']]
          rows << r; seen[signature(r)]=true; ids[r['id']]=true; added+=1
          catalog_keys[r['catalog_key']]=true unless r['catalog_key'].empty?
        end
        save(rows)
        added
      end

      def import_document(raw)
        incoming=decode(raw)
        doc=JSON.parse(raw)
        return "#{merge(incoming)} yeni kayıt içe aktarıldı. Mevcut kayıtlar korundu." unless doc.key?('catalog_replaces')
        replacements=doc['catalog_replaces']
        unless replacements.is_a?(Array) && replacements.length<=LIMIT && replacements.all? { |id| id.is_a?(String) && !id.empty? } &&
            !incoming.empty? && incoming.all? { |r| !r['catalog_key'].empty? } && incoming.map { |r| r['catalog_key'] }.uniq.length==incoming.length
          raise 'Geçersiz tekil katalog dönüşüm belgesi.'
        end
        rows=load
        before=rows.length
        rows=rows.reject { |r| replacements.include?(r['id']) }
        removed=before-rows.length
        keys={}; ids={}; added=0
        rows.each { |r| keys[r['catalog_key']]=true unless r['catalog_key'].empty?; ids[r['id']]=true }
        incoming.each do |r|
          next if keys[r['catalog_key']]
          r=r.merge('id'=>SecureRandom.uuid) if ids[r['id']]
          rows << r; keys[r['catalog_key']]=true; ids[r['id']]=true; added+=1
        end
        save(rows) # Single backed-up mutation; unrelated user records survive.
        "#{added} tekil poz eklendi; önceki arşivden #{removed} satır katalogla değiştirildi."
      end

      def capture(meta)
        rows=load
        project_ids=MarineStructuresTools.boq_project_mapping.values.map{|r|r['id']}
        before=encode(rows)
        seeds=decode(File.read(File.join(__dir__,'unified_catalog.json'),encoding:'UTF-8'))
        seeds.each do |seed|
          found=rows.find { |r| r['catalog_key']==seed['catalog_key'] || r['id']==seed['id'] }
          if found
            found['source']=seed['source'] unless seed['source'].empty?
          else
            seed=seed.merge('code'=>next_code(rows)) if rows.any? { |r| r['code']==seed['code'] }
            rows << seed
          end
        end
        # Fold older model snapshots into the matching definition, retaining
        # their entire content as history. Never match by reused ÖBF numbers.
        seeds.reject { |r| r['source'].empty? }.each do |seed|
          target=rows.find { |r| r['catalog_key']==seed['catalog_key'] }
          duplicates=rows.select { |r| r!=target && !project_ids.include?(r['id']) && r['catalog_key'].empty? && r['source']==seed['source'] && r['unit']==seed['unit'] }
          duplicates.each do |r|
            remember(target,r)
            target['rate_description']=r['rate_description'] if target['rate_description'].empty? && !r['rate_description'].empty?
          end
          rows-=duplicates
        end
        rows.each do |r|
          unless r['currency']=='USD'
            # No exchange rate was supplied. Preserve the original price in
            # history rather than mislabel an EUR/TRY/unknown price as USD.
            if !r['unit_price'].nil?
              remember(r,r.dup)
              r['unit_price']=nil
            end
            r['currency']='USD'
          end
        end
        MarineStructuresTools.boq_rows.each do |model_row|
          # v0.51.5: kütüphaneden adıyla eşleşen kaynaklar (PILE_PLUG, PRECAST_CONCRETE#sınıf) katalogda 'source' taşımaz;
          # poz bulunamamış satır arşivlenmez, eşleşmiş satır library_id ile yazılır.
          auto_src=model_row[:source].to_s=='PILE_PLUG' || model_row[:source].to_s.start_with?('PRECAST_CONCRETE#')
          next if auto_src && model_row[:missing_library]
          seed=seeds.find { |r| r['source']==model_row[:source] && r['unit']==model_row[:unit] }
          raise 'Keşif katalog eşleştirmesi bulunamadı.' unless seed || auto_src
          target=if model_row[:project_mapping] || model_row[:automatic_mapping]
            rows.find { |r| r['id']==model_row[:library_id] }
          else
            rows.find { |r| r['catalog_key']==seed['catalog_key'] }
          end
          raise 'Eşleşen poz silinmiş; arşivlemeden önce proje eşleştirmesini düzeltin.' unless target
          updated=target.merge('quantity'=>model_row[:quantity],'unit_price'=>model_row[:unit_price],
            'currency'=>'USD','model_project'=>meta['project'].to_s,'model_date'=>meta['date'].to_s)
          remember(updated,target) if target!=updated && (!target['quantity'].nil? || !target['unit_price'].nil?)
          target.replace(record(updated))
        end
        save(rows)
        before==encode(rows) ? 0 : MarineStructuresTools::BOQ_TEMPLATE.length
      end

      def next_code(rows)
        n=rows.map { |r| r['code'][/\AÖBF-(\d+)\z/,1].to_i }.max.to_i+1
        format('ÖBF-%03d',n)
      end

      def remember(target,source)
        history=target['archive_history'].to_s.empty? ? [] : JSON.parse(target['archive_history'])
        prior=source['archive_history'].to_s.empty? ? [] : JSON.parse(source['archive_history'])
        prior.each { |entry| history << entry unless history.include?(entry) }
        snapshot=source.reject { |key,_| key=='archive_history' }
        history << snapshot unless history.include?(snapshot)
        target['archive_history']=JSON.generate(history)
      end

      def target(row)
        return nil unless row['currency']=='USD' && !row['source'].empty? && !row['unit_price'].nil?
        return nil if MarineStructuresTools.boq_project_mapping.key?(row['source'])
        MarineStructuresTools::BOQ_TEMPLATE.find { |r| r[4]==row['source'] && r[2]==row['unit'] }
      end

      def apply(id)
        row=load.find { |r| r['id']==id }
        raise 'Kayıt bulunamadı.' unless row
        mapping=target(row)
        raise 'Bu kayıt aktif keşif ile aynı para birimi/birim/kaynak eşleşmesine sahip değil.' unless mapping
        model=Sketchup.active_model
        model.start_operation('Keşif Kütüphanesi Birim Fiyatı',true)
        begin
          model.set_attribute(MarineStructuresTools::DICT,"boq_price_#{mapping[0]}",row['unit_price'])
          model.commit_operation
        rescue
          model.abort_operation
          raise
        end
        mapping[0]
      end
    end

    def send_boq_library(message='')
      rows=BOQLibrary.load.map do |r|
        target=BOQLibrary.target(r)
        r.merge('target_code'=>target ? target[0] : nil)
      end
      data={'records'=>rows,'message'=>message,'project'=>Sketchup.active_model.get_attribute(DICT,'project_name',''),
            'year'=>Date.today.year,'date'=>Date.today.iso8601,
            'sources'=>BOQ_TEMPLATE.map { |r| {'key'=>r[4],'name'=>r[0]+' — '+r[1],'unit'=>r[2]} }}
      @boq_library_dialog.execute_script("setLibrary(#{JSON.generate(data)});")
    end

    def show_boq_library
      if @boq_library_dialog && @boq_library_dialog.visible?
        @boq_library_dialog.bring_to_front
        send_boq_library
        return
      end
      d=mst_html_dialog('boq_library',dialog_title:"Keşif Kütüphanesi v#{VERSION}",preferences_key:'MAG_MST_BOQ_Library',width:1250,height:820,resizable:true)
      @boq_library_dialog=d
      d.set_file(File.join(__dir__,'boq_library.html'))
      d.add_action_callback('library_action') do |_,action,json|
        begin
          data=JSON.parse(json || '{}'); message=''
          case action
          when 'tariffs'
            tariffs=JSON.parse(File.read(File.join(__dir__,'source_tariffs.json'),encoding:'UTF-8'))
            d.execute_script("setTariffs(#{JSON.generate(tariffs)});")
            next
          when 'refresh'
          when 'save'
            BOQLibrary.upsert(data); message='Kayıt saklandı.'
            send_boq(@d) if @d && @d.visible?
          when 'delete'; BOQLibrary.remove(data.fetch('id')); message='Kayıt silindi. Son değişikliği geri alabilirsiniz.'
          when 'undo'; BOQLibrary.undo; message='Önceki kütüphane geri yüklendi.'
          when 'capture'; BOQLibrary.capture(data); message='Tek USD arşivi hazır. Aktif keşif kalemlerinin miktar ve fiyatları güncellendi; aynı pozlar birleştirildi.'
          when 'apply'
            code=BOQLibrary.apply(data.fetch('id')); message="#{code} birim fiyatı uygulandı. Model miktarı korunur; Ctrl+Z ile geri alınır."
            send_boq(@d) if @d && @d.visible?
          when 'export'
            path=UI.savepanel('Keşif Kütüphanesini Dışa Aktar','','MST_Kesif_Kutuphanesi.json')
            if path
              path+='.json' unless path.downcase.end_with?('.json')
              File.open(path,'w:UTF-8') { |f| f.write(BOQLibrary.encode(BOQLibrary.load)) }
              message='Kütüphane JSON olarak dışa aktarıldı.'
            end
          when 'import'
            path=UI.openpanel('Keşif Kütüphanesi JSON Seç','','JSON|*.json||')
            if path
              raise 'Dosya 2 MB sınırını aşıyor.' if File.size(path)>BOQLibrary::MAX_BYTES
              raw=File.read(path,encoding:'UTF-8').sub(/\A\uFEFF/,'')
              message=BOQLibrary.import_document(raw)
            end
          else; raise 'Bilinmeyen işlem.'
          end
          send_boq_library(message)
        rescue => ex
          d.execute_script("libraryError(#{JSON.generate(ex.message)});")
        end
      end
      d.show
    end
  end
end
