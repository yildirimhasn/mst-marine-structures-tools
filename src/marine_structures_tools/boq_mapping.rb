# frozen_string_literal: true
module MAG
  module MarineStructuresTools
    BOQ_MAPPING_KEY='boq_project_mapping_v1'.freeze

    def boq_mapping_templates
      BOQ_TEMPLATE + boq_auto_library_sources + (respond_to?(:rf_live_excavation_sources) ? rf_live_excavation_sources : []) + accessory_sources.map{|r|['—',r[:name],r[:unit],nil,r[:key]]} + jg_sources.map{|r|['—',r[:name],r[:unit],nil,r[:key]]} + bp_sources.map{|r|['—',r[:name],r[:unit],nil,r[:key]]} + rockfill_qto_data[:materials].map{|m|['—',m[:name],'ton',nil,"ROCKFILL:#{m[:code]}"]}
    end

    def rockfill_boq_name(name)
      name.to_s.tr('ıİ','iI').upcase.gsub(/[\s.,]/,'').tr('ŞĞÜÖÇ','SGUOC')
    end

    def rockfill_boq_base_rows(library,seeds,map)
      rockfill_qto_data[:materials].map do |material|
        key="ROCKFILL:#{material[:code]}"; quantity=material[:tonnage_t]
        next boq_mapped_row(key,'ton',quantity,map[key],library) if map.key?(key)
        match=rockfill_boq_name(material[:name])
        candidates=library.select{|r|r['unit']=='ton' && r['currency']=='USD' && rockfill_boq_name(r['name'])==match}
        if candidates.empty?
          candidates=seeds.select{|r|r['unit']=='ton' && r['currency']=='USD' && rockfill_boq_name(r['name'])==match}.map do |seed|
            library.find{|r|r['id']==seed['id'] || (!seed['catalog_key'].to_s.empty? && r['catalog_key']==seed['catalog_key'])} || seed
          end.uniq{|r|r['id']}
        end
        if candidates.length==1
          item=candidates.first
          row=boq_mapped_row(key,'ton',quantity,item,[item])
          row[:project_mapping]=false
          row
        else
          {code:'—',name:material[:name],unit:'ton',quantity:quantity,unit_price:nil,total:nil,
           source:key,status:'ÖBF EŞLEŞTİRİLMELİ',library_price:true,project_mapping:false}
        end
      end
    end

    def boq_automatic_drilling_row(quantity,library,seeds)
      all=[];collect_elements(Sketchup.active_model.entities,all)
      piles=all.select{|e|e.get_attribute(DICT,'element_type','')=='steel_pipe_pile' && e.get_attribute(DICT,'drilling_enabled','0').to_s=='1' && e.get_attribute(DICT,'drilling_length_m',0).to_f>0}
      dimensions=piles.map{|p|[p.get_attribute(DICT,'diameter_mm',0).to_f,p.get_attribute(DICT,'thickness_mm',0).to_f]}.uniq
      candidates=seeds.select{|r|r['name'].upcase.include?('FORAJ')}.map do |seed|
        library.find{|r|r['id']==seed['id'] || r['catalog_key']==seed['catalog_key']} || seed
      end.select{|r|r['unit']=='m' && r['currency']=='USD' && r['name'].upcase.include?('FORAJ')}
      exact=[];general=[]
      candidates.each do |r|
        name=r['name']
        dia=name.match(/[Øø⌀]\s*(\d+(?:[.,]\d+)?)(\s*[”″"])?/)
        thick=name.match(/(?:t\s*=\s*|\/\s*)(\d+(?:[.,]\d+)?)\s*mm/i)
        if dia && thick
          diameter=dia[1].tr(',','.').to_f*(dia[2] ? 25.4 : 1)
          thickness=thick[1].tr(',','.').to_f
          exact << r if !dimensions.empty? && dimensions.all?{|d,t|(d-diameter).abs<0.05 && (t-thickness).abs<0.05}
        elsif !dia && name.strip.upcase=='ÇELİK BORU KAZIKLARA FORAJ YAPILMASI'
          general << r
        end
      end
      item=exact.size==1 ? exact.first : (general.size==1 ? general.first : nil)
      unless item
        return {code:'—',name:'FORAJ — UYGUN KÜTÜPHANE POZU BULUNAMADI',unit:'m',quantity:quantity,
          unit_price:nil,total:nil,source:'PILE_DRILLING',status:'UYGUN POZ EKSİK',library_price:true,automatic_mapping:true,
          mapping_reason:'Kazık özelliklerine uygun tekil bir foraj pozu bulunamadı.'}
      end
      row=boq_mapped_row('PILE_DRILLING','m',quantity,item,[item])
      row[:project_mapping]=false;row[:automatic_mapping]=true
      row[:mapping_reason]=exact.size==1 ? 'Foraj yapılan kazıkların çap ve et kalınlığıyla eşleşti.' : 'Çap/et kalınlığına özel tekil poz bulunamadı; çap belirtmeyen genel foraj pozu seçildi.'
      row
    end

    # v0.51.5 (04.11.2026 kullanıcı talimatı): kütüphaneden ADI ile otomatik eşleşen model miktarları.
    #  PILE_PLUG                  → 'ÇEŞİTLİ DEMİR İMALATI VE YERİNE KONULMASI' (kg)
    #  PRECAST_CONCRETE#<sınıf>   → 'PREKAST BETONU (<sınıf>)' (m³); 'Sınıfsız' → 'PREKAST BETONU'
    # Ad karşılaştırması: Türkçe büyük harf, boşluksuz, birebir. Proje eşleştirmesi (ÖBF Eşleştirme) varsa o kullanılır.
    BOQ_PLUG_POZ_NAME='ÇEŞİTLİ DEMİR İMALATI VE YERİNE KONULMASI'.freeze
    BOQ_PRECAST_POZ_NAME='PREKAST BETONU'.freeze

    def boq_precast_poz_name(cls)
      cls.to_s=='Sınıfsız' ? BOQ_PRECAST_POZ_NAME : "#{BOQ_PRECAST_POZ_NAME} (#{cls.to_s.upcase.gsub(' ','')})"
    end

    # Modelde artık olmayan sınıfın (sınıfı değişmiş prekast) kayıtlı eşleştirmesi de listelenir: görülür ve sıfırlanabilir.
    def boq_auto_library_sources(q=nil,map=nil)
      q||=boq_quantities
      map||=(boq_project_mapping rescue {})
      keys=(q.keys+map.keys).select{|k|k.start_with?('PRECAST_CONCRETE#')}.uniq.sort
      [['—',"Kazık tapası → #{BOQ_PLUG_POZ_NAME}",'kg',nil,'PILE_PLUG']]+
        keys.map{|k|cls=k.split('#',2)[1];['—',"Prekast betonu — #{cls=='Sınıfsız' ? 'sınıf belirtilmemiş' : cls}",'m³',nil,k]}
    end

    def boq_library_name_key(s)
      s.to_s.tr('ıi','Iİ').upcase.gsub(/\s+/,'')
    end

    # Kullanıcı kütüphanesindeki aynı adlı/birimli kayıtlar önce; yoksa paketteki katalog (kütüphanedeki karşılığıyla).
    def boq_library_exact(name,unit,library,seeds)
      key=boq_library_name_key(name)
      hit=->(r){r['unit']==unit && boq_library_name_key(r['name'])==key}
      own=library.select(&hit)
      return own unless own.empty?
      seeds.select(&hit).map do |seed|
        library.find{|r|r['id']==seed['id'] || (!seed['catalog_key'].to_s.empty? && r['catalog_key']==seed['catalog_key'])} || seed
      end.uniq{|r|r['id']}
    end

    # auto_library: ad eşleşmesi; automatic_mapping (foraj) gibi ÖBF Eşleştirme'de kilitli DEĞİL — kullanıcı elle poz seçebilir.
    # used_ids: başka kaynağa proje eşleştirmesiyle bağlı pozlar otomatik seçilmez (aynı poz iki satırda olmaz).
    def boq_auto_library_row(key,unit,quantity,poz_name,label,library,seeds,used_ids=[])
      all=boq_library_exact(poz_name,unit,library,seeds)
      c=all.reject{|r|used_ids.include?(r['id'])}
      if c.length==1
        row=boq_mapped_row(key,unit,quantity,c.first,c)
        row[:project_mapping]=false;row[:auto_library]=true
        row[:mapping_reason]="Kütüphanedeki '#{c.first['name']}' (#{unit}) pozuyla adından eşleşti."
        return row
      end
      reason=if c.empty? && !all.empty?
        "Kütüphanedeki '#{poz_name}' pozu (#{all.map{|r|r['code']}.join(', ')}) başka bir model miktarına bağlı. ÖBF Eşleştirme'den bir poz seçin."
      elsif c.empty?
        "Kütüphanede '#{poz_name}' adlı, birimi #{unit} olan poz yok. Kütüphaneye bu adla poz ekleyin (otomatik eşleşir) ya da ÖBF Eşleştirme'den bir poz seçin."
      else
        "Kütüphanede '#{poz_name}' adlı #{c.length} poz var (#{c.map{|r|r['code']}.join(', ')}). ÖBF Eşleştirme'den birini seçin."
      end
      {code:'—',name:"#{label} — #{c.empty? ? 'KÜTÜPHANEDE POZ YOK' : 'POZ SEÇİLMELİ'}",unit:unit,quantity:quantity,
       unit_price:nil,total:nil,source:key,status:(c.empty? ? 'UYGUN POZ EKSİK' : 'BİRDEN ÇOK UYGUN POZ'),
       library_price:true,auto_library:true,missing_library:true,mapping_reason:reason}
    end

    def boq_auto_library_rows(q,library,seeds,map)
      used_ids=map.values.map{|v|v['id']}
      boq_auto_library_sources(q,map).map do |_,_,unit,_,key|
        qty=q[key].to_f
        next boq_mapped_row(key,unit,qty,map[key],library) if map.key?(key)
        if key=='PILE_PLUG'
          boq_auto_library_row(key,unit,qty,BOQ_PLUG_POZ_NAME,'KAZIK TAPASI',library,seeds,used_ids)
        else
          cls=key.split('#',2)[1]
          boq_auto_library_row(key,unit,qty,boq_precast_poz_name(cls),"PREKAST BETONU (#{cls})",library,seeds,used_ids)
        end
      end
    end

    def boq_project_mapping
      raw=Sketchup.active_model.get_attribute(DICT,BOQ_MAPPING_KEY,'{}')
      map=JSON.parse(raw)
      keys=BOQ_TEMPLATE.map{|r|r[4]}
      raise 'Proje ÖBF eşleştirme verisi okunamadı.' unless map.is_a?(Hash) && map.all?{|k,v|(keys.include?(k) || k=='LIVE_EXCAVATION' || k=='PILE_PLUG' || k.start_with?('PRECAST_CONCRETE#') || k.start_with?('ROCKFILL:') || k.start_with?('BORED:') || k.start_with?('JETGROUT:') || k.start_with?('ACCESSORY:')) && v.is_a?(Hash) && %w[id code name].all?{|f|v[f].is_a?(String) && !v[f].empty?}}
      map
    end

    def boq_mapped_row(key,unit,quantity,mapping,library)
      item=library.find{|r|r['id']==mapping['id']}
      status=if item.nil?
        'EŞLEŞEN POZ SİLİNMİŞ'
      elsif item['unit']!=unit
        'BİRİM UYUŞMUYOR'
      elsif item['currency']!='USD'
        'USD FİYAT GEREKLİ'
      elsif item['unit_price'].nil?
        quantity>0 ? 'KÜTÜPHANE FİYATI EKSİK' : 'YOK'
      else
        quantity>0 ? 'MODEL' : 'YOK'
      end
      valid=item && item['unit']==unit && item['currency']=='USD'
      price=valid ? item['unit_price'] : nil
      total=valid && quantity<=0 ? 0.0 : (price.nil? ? nil : quantity*price)
      {code:(item || mapping)['code'],name:(item || mapping)['name'],unit:unit,
       quantity:quantity,unit_price:price,total:total,source:key,status:status,
       library_price:true,project_mapping:true,library_id:mapping['id'],
       rate_description:item ? item['rate_description'] : ''}
    end

    def save_boq_mapping(data)
      key=data.fetch('source'); template=boq_mapping_templates.find{|r|r[4]==key}
      raise 'Model miktarı bulunamadı.' unless template
      raise 'Foraj pozu kazık özelliklerinden otomatik seçilir.' if key=='PILE_DRILLING' && data['reset']!=true
      map=boq_project_mapping
      if data['reset']==true
        return false unless map.key?(key)
        map.delete(key)
      else
        library=BOQLibrary.load
        item=library.find{|r|r['id']==data['id']}
        raise 'Kütüphane pozu bulunamadı. Listeyi yenileyin.' unless item
        raise 'Poz birimi model miktarının birimiyle aynı olmalı.' unless item['unit']==template[2]
        raise 'Pozun para birimi USD olmalı.' unless item['currency']=='USD'
        used=map.any?{|source,row|source!=key && row['id']==item['id'] && !(key.start_with?('ACCESSORY:') && source.start_with?('ACCESSORY:')) && !(key.start_with?('JETGROUT:') && source.start_with?('JETGROUT:') && key.split(':').last==source.split(':').last)}
        seeds=BOQLibrary.seeds   # FIX-09: önbellekli katalog
        used ||= seeds.any? do |seed|
          source=seed['source']
          source!=key && BOQ_TEMPLATE.any?{|r|r[4]==source} && !map.key?(source) && (seed['id']==item['id'] || (!item['catalog_key'].empty? && seed['catalog_key']==item['catalog_key']))
        end
        raise 'Bu poz başka bir model miktarına bağlı. Önce o eşleştirmeyi kaldırın.' if used
        value=item.slice('id','code','name')
        return false if map[key]==value
        map[key]=value
      end
      model=Sketchup.active_model
      model.start_operation('Proje ÖBF Eşleştirmesi',true)
      begin
        model.set_attribute(DICT,BOQ_MAPPING_KEY,JSON.generate(map))
        model.commit_operation
      rescue
        model.abort_operation
        raise
      end
      true
    end

    def send_boq_mapping(dialog,message='')
    mst_read_batch do   # v0.51.5 P4: salt okuma, tek model taraması (gömülü ÖBF eşleştirme sayfası)
      map=boq_project_mapping; rows=boq_rows(true)
      data={message:message,model_token:Sketchup.active_model.object_id.to_s,sources:boq_mapping_templates.map{|r|{key:r[4],name:r[1],unit:r[2]}},
        rows:rows,mappings:map,records:BOQLibrary.load.map{|r|r.slice('id','code','name','unit','currency','unit_price','rate_description')},
        project:Sketchup.active_model.get_attribute(DICT,'project_name','')}
      dialog.execute_script("setMapping(#{JSON.generate(data)});")
    end # mst_read_batch
    end

    def show_boq_mapping
      if @boq_mapping_dialog && @boq_mapping_dialog.visible?
        @boq_mapping_dialog.bring_to_front;send_boq_mapping(@boq_mapping_dialog);return
      end
      d=mst_html_dialog('boq_mapping',dialog_title:'ÖBF – Model Miktarı Eşleştirme',preferences_key:'MAG_MST_BOQ_Mapping',width:1250,height:850,resizable:true)
      @boq_mapping_dialog=d
      d.set_file(File.join(__dir__,'boq_mapping.html'))
      d.add_action_callback('mapping_action') do |_,action,json|
        begin
          message=''
          case action
          when 'refresh'
          when 'save'
            data=JSON.parse(json || '{}')
            raise 'Aktif model değişti. Önce Model ve Kütüphaneyi Yenile düğmesine basın.' unless data['model_token']==Sketchup.active_model.object_id.to_s
            changed=save_boq_mapping(data)
            message=changed ? 'Proje eşleştirmesi kaydedildi. Ctrl+Z ile geri alınabilir. Kalıcı saklamak için SKP dosyanızı kaydedin.' : 'Eşleştirme zaten güncel.'
            send_boq(@d) if @d && @d.visible?
          when 'library'
            show_boq_library;next
          else
            raise 'Bilinmeyen eşleştirme işlemi.'
          end
          send_boq_mapping(d,message)
        rescue=>ex
          d.execute_script("mappingError(#{JSON.generate(ex.message)});")
        end
      end
      d.show
    end
  end
end
