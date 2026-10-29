# frozen_string_literal: true
module MAG
  module MarineStructuresTools
    PILE_MFG_KEYS={
      'drilling'=>'drilling_enabled',
      'plug'=>'plug_enabled',
      'pe'=>'pe_enabled',
      'upper'=>'upper_ring_enabled',
      'lower'=>'lower_ring_enabled'
    }.freeze

    def pile_mfg_targets(scope)
      model=Sketchup.active_model; elements=[]
      if scope=='all'
        collect_elements(model.entities,elements)
      elsif scope=='selected'
        model.selection.each do |e|
          if e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','')=='steel_pipe_pile'
            elements << e
          elsif e.respond_to?(:entities)
            collect_elements(e.entities,elements)
          end
        end
      else
        raise 'Kazık kapsamı geçersiz.'
      end
      elements.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','')=='steel_pipe_pile'}.uniq
    end

    def pile_mfg_state_label(piles,key)
      return '—' if piles.empty?
      vals=piles.map{|p|p.get_attribute(DICT,key,'0').to_s=='1' ? 'VAR' : 'YOK'}.uniq
      vals.length==1 ? vals.first : 'KARIŞIK'
    end

    def pile_infill_child(pile)
      mst_bim_children(pile,'pile_infill_concrete').first
    end

    def pile_infill_enabled?(pile); !!pile_infill_child(pile); end

    def pile_mfg_state(scope)
      piles=pile_mfg_targets(scope)
      h={count:piles.length,model_token:Sketchup.active_model.object_id.to_s}
      PILE_MFG_KEYS.each{|ui,key|h[ui.to_sym]=pile_mfg_state_label(piles,key)}
      h[:infill]=begin
        vals=piles.map{|p|pile_infill_enabled?(p) ? 'VAR':'YOK'}.uniq
        vals.empty? ? '—' : (vals.length==1 ? vals.first : 'KARIŞIK')
      end
      # v0.27.6: expose current parameter values. Equal values are shown directly;
      # mixed selections are marked KARIŞIK so the UI never silently overwrites them.
      param_fields=%w[drilling_length_m plug_thickness_mm plug_clearance_mm pe_length_m upper_ring_width_mm lower_ring_width_mm]
      param_fields.each do |field|
        vals=piles.map{|x|x.get_attribute(DICT,field,nil)}.compact.map{|v|v.to_f.round(6)}.uniq
        h[field.to_sym]=vals.empty? ? '' : (vals.length==1 ? vals.first : 'KARIŞIK')
      end
      inf=piles.map{|x|pile_infill_child(x)}.compact
      cls=inf.map{|g|g.get_attribute(DICT,'concrete_class','').to_s}.reject(&:empty?).uniq
      bot=inf.map{|g|g.get_attribute(DICT,'bottom_elevation_m',nil)}.compact.map{|v|v.to_f.round(6)}.uniq
      h[:infill_concrete_class]=cls.empty? ? '' : (cls.length==1 ? cls.first : 'KARIŞIK')
      h[:infill_bottom_elevation_m]=bot.empty? ? '' : (bot.length==1 ? bot.first : 'KARIŞIK')
      h
    end

    # v0.38 C6: axial cosine of the pile (1.0 for vertical). Infill height along the
    # pile axis = vertical height / vz — same rule as creation and the target service.
    def mst_pile_vz(p)
      pile_orientation({'orientation_mode'=>p.get_attribute(DICT,'orientation_mode','VERTICAL'),'batter_ratio'=>p.get_attribute(DICT,'batter_ratio',0),'azimuth_deg'=>p.get_attribute(DICT,'azimuth_deg',0)})[4]
    end

    def save_infill_recipe(pile,child)
      h=mst_attr_hash(child)
      %w[concrete_class internal_diameter_mm top_elevation_m bottom_elevation_m height_m concrete_volume_m3 elevation_zone].each{|k|pile.set_attribute(DICT,"saved_infill_#{k}",h[k]) if h.key?(k)}
      pile.set_attribute(DICT,'saved_infill_available','1')
    end

    # Existing-pile VAR/YOK engineering recipe standard (v0.27.4):
    # - previously active then YOK => restore that pile's own retained parameters
    # - never active => suggest the most common recipe already used by peer piles
    # - user may edit the suggested values once; apply to all genuinely new targets
    PILE_RECIPE_FIELDS={
      'drilling_enabled'=>[['drilling_length_m','Foraj Boyu / Kazık (m)']],
      'plug_enabled'=>[['plug_thickness_mm','Tapa Et Kalınlığı (mm)'],['plug_clearance_mm','Tapa Kenar Boşluğu (mm)']],
      'pe_enabled'=>[['pe_length_m','PE Kaplama Boyu / Kazık (m)']],
      'upper_ring_enabled'=>[['upper_ring_width_mm','Üst Çarık Şerit Genişliği (mm)']],
      'lower_ring_enabled'=>[['lower_ring_width_mm','Alt Çarık Şerit Genişliği (mm)']]
    }.freeze

    def pile_recipe_signature(pile,key)
      PILE_RECIPE_FIELDS.fetch(key).map{|field,_|pile.get_attribute(DICT,field,0).to_f}
    end

    def common_active_recipe(piles,key)
      active=piles.select{|p|p.get_attribute(DICT,key,'0').to_s=='1'}
      groups=active.group_by{|p|pile_recipe_signature(p,key)}
      groups.max_by{|sig,arr|arr.length}&.first
    end

    def mark_recipe_saved(pile,key)
      pile.set_attribute(DICT,"saved_#{key}_available",'1')
    end

    def prepare_new_aux_recipe(piles,key)
      # A pile switched off by this editor carries saved_*_available and must restore
      # its own values. Only piles that have never had the fabrication are 'new'.
      need=piles.select{|p|p.get_attribute(DICT,key,'0').to_s!='1' && p.get_attribute(DICT,"saved_#{key}_available",'0').to_s!='1'}
      return 0 if need.empty?
      fields=PILE_RECIPE_FIELDS.fetch(key)
      exemplar=common_active_recipe(pile_mfg_targets('all'),key)
      # If no peer exists, fall back to the values already carried by the first pile
      # (these originate from the pile creation panel and are only a last resort).
      defaults=exemplar || pile_recipe_signature(need.first,key)
      labels=fields.map{|_,label|label}
      title_names={'drilling_enabled'=>'Foraj','plug_enabled'=>'Tapa','pe_enabled'=>'PE Kaplama','upper_ring_enabled'=>'Üst Çarık','lower_ring_enabled'=>'Alt Çarık'}
      result=UI.inputbox(labels,defaults.map{|v|format('%.3f',v)},"#{need.length} Kazık — #{title_names[key]} Referans Değerleri")
      raise "#{title_names[key]} ekleme işlemi kullanıcı tarafından iptal edildi." unless result
      vals=result.map{|v|Float(v.to_s.tr(',','.')) rescue Float::NAN}
      raise "#{title_names[key]} değerleri sayısal ve sıfırdan büyük olmalı." unless vals.all?{|v|v.finite? && v>0}
      need.each do |pile|
        fields.each_with_index{|(field,_),i|pile.set_attribute(DICT,field,vals[i])}
        mark_recipe_saved(pile,key)
      end
      need.length
    end

    def prepare_bulk_infill_recipe(piles)
      need=piles.select{|p| !pile_infill_enabled?(p) && p.get_attribute(DICT,'saved_infill_available','0').to_s!='1'}
      return 0 if need.empty?
      # Prefer the most common concrete class + bottom elevation among existing infills.
      all=pile_mfg_targets('all')
      recipes=all.map{|p|pile_infill_child(p)}.compact.map do |g|
        [g.get_attribute(DICT,'concrete_class','C35/45').to_s,g.get_attribute(DICT,'bottom_elevation_m',0).to_f]
      end
      exemplar=recipes.group_by{|x|x}.max_by{|_,a|a.length}&.first
      first=need.first
      top=first.get_attribute(DICT,'top_elevation_m',0).to_f
      len=first.get_attribute(DICT,'length_m',0).to_f
      default_bottom=[top-3.0,top-len].max; default_bottom=top-0.50 if default_bottom>=top
      klass,bottom_default=exemplar || ['C35/45',default_bottom]
      result=UI.inputbox(['Beton Sınıfı','Kazık İçi Beton Alt Kotu (m)'],[klass,format('%.3f',bottom_default)],['C30/37|C35/45|C40/50|C45/55|C50/60',''],"#{need.length} Kazık — Kazık İçi Beton Referans Değerleri")
      raise 'Kazık içi beton ekleme işlemi kullanıcı tarafından iptal edildi.' unless result
      klass=result[0].to_s.strip; bottom=Float(result[1].to_s.tr(',','.')) rescue nil
      raise 'Kazık içi beton alt kotu sayısal olmalı.' unless bottom && bottom.finite?
      errors=[]
      need.each do |p|
        d=p.get_attribute(DICT,'diameter_mm',0).to_f; t=p.get_attribute(DICT,'thickness_mm',0).to_f; di=d-2.0*t
        ptop=p.get_attribute(DICT,'top_elevation_m',0).to_f; plen=p.get_attribute(DICT,'length_m',0).to_f; pbottom=ptop-plen*mst_pile_vz(p); id=element_visible_id(p)
        errors << "#{id}: iç çap hesaplanamadı" if di<=0
        errors << "#{id}: alt kot #{bottom} m, üst kot #{ptop} m altında olmalı" if bottom>=ptop
        errors << "#{id}: alt kot #{bottom} m, kazık alt kotu #{pbottom} m altında" if plen>0 && bottom<pbottom-0.0001
      end
      raise "Kazık içi beton referans değerleri bazı kazıklara uygun değil:\n#{errors.first(8).join("\n")}" unless errors.empty?
      need.each do |p|
        d=p.get_attribute(DICT,'diameter_mm',0).to_f; t=p.get_attribute(DICT,'thickness_mm',0).to_f; di=d-2.0*t
        ptop=p.get_attribute(DICT,'top_elevation_m',0).to_f; h=(ptop-bottom)/mst_pile_vz(p); vol=Math::PI/4.0*(di/1000.0)**2*h
        {'concrete_class'=>klass,'internal_diameter_mm'=>di,'top_elevation_m'=>ptop,'bottom_elevation_m'=>bottom,'height_m'=>h,'concrete_volume_m3'=>vol,'elevation_zone'=>p.get_attribute(DICT,'elevation_zone','NORMAL').to_s}.each{|k,v|p.set_attribute(DICT,"saved_infill_#{k}",v)}
        p.set_attribute(DICT,'saved_infill_available','1')
      end
      need.length
    end

    # v0.38 C6: Component pile — restore the saved infill as the pile's own values;
    # the definition with that infill is attached by mst_pile_component_refresh!.
    def mst_component_restore_saved_infill!(pile)
      raise "#{element_visible_id(pile)} için kayıtlı kazık içi beton ölçüsü yok." unless pile.get_attribute(DICT,'saved_infill_available','0').to_s=='1'
      bottom=pile.get_attribute(DICT,'saved_infill_bottom_elevation_m',nil)
      top=pile.get_attribute(DICT,'top_elevation_m',0).to_f
      raise "#{element_visible_id(pile)} için kayıtlı iç beton geometrisi geçersiz." if bottom.nil? || bottom.to_f>=top
      klass=pile.get_attribute(DICT,'saved_infill_concrete_class','').to_s
      pile.set_attribute(DICT,'infill_enabled','1')
      pile.set_attribute(DICT,'infill_bottom_elevation_m',bottom.to_f)
      pile.set_attribute(DICT,'infill_concrete_class',klass) unless klass.empty?
      pile
    end

    def rebuild_saved_infill(pile)
      return mst_component_restore_saved_infill!(pile) if mst_component_pile?(pile)
      mst_require_group_pile!(pile,'Kayıtlı iç betonu yeniden oluşturma')
      raise "#{element_visible_id(pile)} için kayıtlı kazık içi beton ölçüsü yok." unless pile.get_attribute(DICT,'saved_infill_available','0').to_s=='1'
      di=pile.get_attribute(DICT,'saved_infill_internal_diameter_mm',0).to_f
      top=pile.get_attribute(DICT,'top_elevation_m',pile.get_attribute(DICT,'saved_infill_top_elevation_m',0)).to_f
      bottom=pile.get_attribute(DICT,'saved_infill_bottom_elevation_m',nil); bottom=bottom.to_f if bottom
      raise "#{element_visible_id(pile)} için kayıtlı iç beton geometrisi geçersiz." if di<=0 || bottom.nil? || bottom>=top
      h=(top-bottom)/mst_pile_vz(pile)
      g=pile.entities.add_group; g.name='Pile Infill Concrete'
      c=g.entities.add_circle(ORIGIN,Z_AXIS,mm(di)/2.0,SEG); f=g.entities.add_face(c); raise 'Kazık içi beton yüzeyi oluşturulamadı.' unless f
      f.reverse! if f.normal.z<0; f.pushpull(-m(h))
      vol=Math::PI/4.0*(di/1000.0)**2*h
      attrs={'element_type'=>'pile_infill_concrete','pile_id'=>pile.get_attribute(DICT,'pile_id',''),'concrete_class'=>pile.get_attribute(DICT,'saved_infill_concrete_class','').to_s,'internal_diameter_mm'=>di,'top_elevation_m'=>top,'bottom_elevation_m'=>bottom,'height_m'=>h,'concrete_volume_m3'=>vol,'elevation_zone'=>pile.get_attribute(DICT,'saved_infill_elevation_zone','').to_s}
      attrs.each{|k,v|g.set_attribute(DICT,k,v)}
      pile.set_attribute(DICT,'infill_enabled','1'); pile.set_attribute(DICT,'infill_concrete_volume_m3',vol); pile.set_attribute(DICT,'infill_bottom_elevation_m',bottom)
      finalize_bim_identity(g,Sketchup.active_model); g
    end

    def set_pile_infill(pile,on)
      child=pile_infill_child(pile)
      if on
        return false if child
        rebuild_saved_infill(pile); true
      else
        return false unless child
        save_infill_recipe(pile,child)
        child.erase! unless mst_component_pile?(pile)   # shared child of a Component is never erased
        pile.set_attribute(DICT,'infill_enabled','0'); pile.set_attribute(DICT,'infill_concrete_volume_m3',0.0); true
      end
    end


    # v0.27.5 - Engineering change preview for bulk VAR/YOK operations.
    # Calculates the affected fabrication quantities before committing the model change.
    def pile_mfg_metrics(piles, requested, infill_mode)
      rho = defined?(RHO) ? RHO.to_f : 7850.0
      out={drilling_m:0.0, pe_m2:0.0, upper_kg:0.0, lower_kg:0.0, plug_count:0, plug_kg:0.0, infill_m3:0.0}
      piles.each do |p|
        state=lambda do |key|
          v=requested[key]
          v.nil? || v=='keep' ? (p.get_attribute(DICT,key,'0').to_s=='1') : (v=='1')
        end
        if state.call('drilling_enabled')
          out[:drilling_m]+=[p.get_attribute(DICT,'drilling_length_m',0).to_f,0.0].max
        end
        if state.call('pe_enabled')
          d=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0
          out[:pe_m2]+=Math::PI*d*[p.get_attribute(DICT,'pe_length_m',0).to_f,0.0].max
        end
        if state.call('plug_enabled')
          out[:plug_count]+=1
          dd=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0; tt=p.get_attribute(DICT,'thickness_mm',0).to_f/1000.0
          clr=p.get_attribute(DICT,'plug_clearance_mm',10).to_f/1000.0; dp=[dd-2.0*tt-2.0*clr,0.0].max
          th=p.get_attribute(DICT,'plug_thickness_mm',12).to_f/1000.0
          out[:plug_kg]+=Math::PI/4.0*dp*dp*th*rho
        end
        if state.call('upper_ring_enabled')
          dd=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0
          w=p.get_attribute(DICT,'upper_ring_width_mm',250).to_f/1000.0; th=p.get_attribute(DICT,'thickness_mm',0).to_f/1000.0
          out[:upper_kg]+=Math::PI*dd*w*th*rho
        end
        if state.call('lower_ring_enabled')
          dd=p.get_attribute(DICT,'diameter_mm',0).to_f/1000.0; tt=p.get_attribute(DICT,'thickness_mm',0).to_f/1000.0; ddi=[dd-2.0*tt,0.0].max
          w=p.get_attribute(DICT,'lower_ring_width_mm',300).to_f/1000.0; th=p.get_attribute(DICT,'thickness_mm',0).to_f/1000.0
          out[:lower_kg]+=Math::PI*ddi*w*th*rho
        end
        infill_on = infill_mode=='keep' ? pile_infill_enabled?(p) : infill_mode=='1'
        if infill_on
          if pile_infill_enabled?(p)
            out[:infill_m3]+=p.get_attribute(DICT,'infill_concrete_volume_m3',pile_infill_child(p).get_attribute(DICT,'concrete_volume_m3',0)).to_f
          else
            out[:infill_m3]+=p.get_attribute(DICT,'saved_infill_concrete_volume_m3',0).to_f
          end
        end
      end
      out
    end

    def pile_mfg_change_preview(piles, requested, infill, before)
      after=pile_mfg_metrics(piles,requested,infill)
      lines=["MÜHENDİSLİK DEĞİŞİKLİK ÖZETİ", "Kapsam: #{piles.length} kazık", '']
      names={'drilling_enabled'=>'FORAJ','plug_enabled'=>'TAPA','pe_enabled'=>'PE KAPLAMA','upper_ring_enabled'=>'ÜST ÇARIK','lower_ring_enabled'=>'ALT ÇARIK'}
      requested.each do |key,v|
        next if v=='keep'
        current=piles.count{|p|p.get_attribute(DICT,key,'0').to_s=='1'}
        target=(v=='1' ? piles.length : 0)
        newly=[target-current,0].max; removed=[current-target,0].max
        detail="#{names[key]} — #{v=='1' ? 'VAR' : 'YOK'}: mevcut #{current}/#{piles.length}"
        detail += ", yeni #{newly}" if newly>0
        detail += ", kaldırılacak #{removed}" if removed>0
        lines << detail
        case key
        when 'drilling_enabled'
          lines << format("  BOQ: %.3f m → %.3f m (%+.3f m)",before[:drilling_m],after[:drilling_m],after[:drilling_m]-before[:drilling_m])
        when 'pe_enabled'
          lines << format("  BOQ: %.2f m² → %.2f m² (%+.2f m²)",before[:pe_m2],after[:pe_m2],after[:pe_m2]-before[:pe_m2])
        when 'upper_ring_enabled'
          lines << format("  Miktar: %.3f kg → %.3f kg (%+.3f kg)",before[:upper_kg],after[:upper_kg],after[:upper_kg]-before[:upper_kg])
        when 'lower_ring_enabled'
          lines << format("  Miktar: %.3f kg → %.3f kg (%+.3f kg)",before[:lower_kg],after[:lower_kg],after[:lower_kg]-before[:lower_kg])
        when 'plug_enabled'
          lines << format("  Adet: %d → %d | Ağırlık: %.3f kg → %.3f kg",before[:plug_count],after[:plug_count],before[:plug_kg],after[:plug_kg])
        end
      end
      if infill!='keep'
        current=piles.count{|p|pile_infill_enabled?(p)}; target=(infill=='1' ? piles.length : 0)
        lines << "KAZIK İÇİ BETON — #{infill=='1' ? 'VAR' : 'YOK'}: mevcut #{current}/#{piles.length}, yeni #{[target-current,0].max}, kaldırılacak #{[current-target,0].max}"
        lines << format("  BOQ: %.3f m³ → %.3f m³ (%+.3f m³)",before[:infill_m3],after[:infill_m3],after[:infill_m3]-before[:infill_m3])
      end
      lines << '' << 'Bu değerlerle modele uygulanacak. Devam edilsin mi?'
      UI.messagebox(lines.join("\n"),MB_YESNO)==IDYES
    end

    # v0.27.6 - Bulk parameter editor. A parameter changes only when its
    # explicit *_update flag is true. KORU therefore means exactly "do not touch".
    # If fabrication status is KORU, parameter edits apply only to piles where that
    # fabrication is currently active. If status is VAR, they apply to all targets.
    def apply_pile_mfg_parameter_updates(piles,data,requested,infill)
      specs={
        'drilling_enabled'=>[['drilling_length_m','drilling_length_m']],
        'plug_enabled'=>[['plug_thickness_mm','plug_thickness_mm'],['plug_clearance_mm','plug_clearance_mm']],
        'pe_enabled'=>[['pe_length_m','pe_length_m']],
        'upper_ring_enabled'=>[['upper_ring_count_per_pile','upper_ring_count_per_pile'],['upper_ring_width_mm','upper_ring_width_mm']],
        'lower_ring_enabled'=>[['lower_ring_count_per_pile','lower_ring_count_per_pile'],['lower_ring_width_mm','lower_ring_width_mm']]
      }
      specs.each do |status_key,fields|
        mode=requested[status_key]
        targets=piles.select{|p| mode=='1' || (mode=='keep' && p.get_attribute(DICT,status_key,'0').to_s=='1')}
        fields.each do |data_key,attr|
          next unless data["#{data_key}_update"]==true
          val=Float(data[data_key].to_s.tr(',','.')) rescue nil
          raise "#{data_key} sayısal ve sıfırdan büyük olmalı." unless val && val.finite? && val>0
          targets.each{|p|p.set_attribute(DICT,attr,val); mark_recipe_saved(p,status_key)}
        end
      end
      # Ring rule: PIPE mode follows the pipe wall; MANUAL keeps the user value.
      piles.each{|p|mst_enforce_ring_rule!(p)}
      inf_targets=piles.select{|p| infill=='1' || (infill=='keep' && pile_infill_enabled?(p))}
      if data['infill_class_update']==true || data['infill_bottom_update']==true
        klass=data['infill_concrete_class'].to_s.strip
        bottom=Float(data['infill_bottom_elevation_m'].to_s.tr(',','.')) rescue nil
        inf_targets.each do |p|
          child=pile_infill_child(p)
          save_infill_recipe(p,child) if child
          p.set_attribute(DICT,'saved_infill_concrete_class',klass) if data['infill_class_update']==true && !klass.empty?
          if data['infill_bottom_update']==true
            raise 'Kazık içi beton alt kotu sayısal olmalı.' unless bottom && bottom.finite?
            top=p.get_attribute(DICT,'top_elevation_m',0).to_f; len=p.get_attribute(DICT,'length_m',0).to_f; low=top-len*mst_pile_vz(p)
            raise "#{element_visible_id(p)}: iç beton alt kotu kazık sınırları dışında." if bottom>=top || bottom<low-0.0001
            di=p.get_attribute(DICT,'diameter_mm',0).to_f-2*p.get_attribute(DICT,'thickness_mm',0).to_f
            h=(top-bottom)/mst_pile_vz(p); vol=Math::PI/4.0*(di/1000.0)**2*h
            p.set_attribute(DICT,'saved_infill_bottom_elevation_m',bottom); p.set_attribute(DICT,'saved_infill_top_elevation_m',top)
            p.set_attribute(DICT,'saved_infill_internal_diameter_mm',di); p.set_attribute(DICT,'saved_infill_height_m',h); p.set_attribute(DICT,'saved_infill_concrete_volume_m3',vol); p.set_attribute(DICT,'saved_infill_available','1')
          end
          if child && mst_component_pile?(p)
            mst_component_restore_saved_infill!(p)
          elsif child
            child.erase!; p.set_attribute(DICT,'infill_enabled','0'); p.set_attribute(DICT,'infill_concrete_volume_m3',0.0)
            rebuild_saved_infill(p)
          end
        end
      end
    end

    def update_existing_pile_manufacturing(data)
      model=Sketchup.active_model
      raise 'Aktif model değişti; önce Modelden Oku düğmesine basın.' unless data['model_token']==model.object_id.to_s
      piles=pile_mfg_targets(data['scope']); raise 'Bu kapsamda kazık bulunamadı.' if piles.empty?
      requested={}
      PILE_MFG_KEYS.each do |ui,key|
        v=data[ui].to_s; raise "#{ui} için geçersiz Var/Yok değeri." unless %w[keep 0 1].include?(v); requested[key]=v
      end
      infill=data['infill'].to_s; raise 'Kazık içi beton için geçersiz Var/Yok değeri.' unless %w[keep 0 1].include?(infill)
      before=pile_mfg_metrics(piles,{},'keep')
      changed=0
      model.start_operation('Mevcut Kazık İmalatlarını Güncelle',true)
      begin
        # First-time VAR: propose the most common peer recipe. Any user edit is included
        # in the preview below before the operation is committed.
        requested.each{|key,v|prepare_new_aux_recipe(piles,key) if v=='1'}
        prepare_bulk_infill_recipe(piles) if infill=='1'
        apply_pile_mfg_parameter_updates(piles,data,requested,infill)
        unless pile_mfg_change_preview(piles,requested,infill,before)
          model.abort_operation
          return 0
        end
        piles.each do |p|
          pile_changed=false
          requested.each do |key,v|
            next if v=='keep' || p.get_attribute(DICT,key,'0').to_s==v
            mark_recipe_saved(p,key) if v=='0' && p.get_attribute(DICT,key,'0').to_s=='1'
            p.set_attribute(DICT,key,v)
            p.set_attribute(DICT,'plug_count_per_pile',v=='1' ? 1 : 0) if key=='plug_enabled'
            pile_changed=true
          end
          pile_changed=true if infill!='keep' && set_pile_infill(p,infill=='1')
          changed+=1 if pile_changed
        end
        # v0.38 C6: Component piles get the definition that matches their new values.
        comps=piles.select{|p|p.valid? && mst_component_pile?(p)}
        mst_scan_batch(model){comps.each{|p|mst_pile_component_refresh!(p)}} unless comps.empty?
        model.commit_operation
      rescue
        model.abort_operation; raise
      end
      changed
    end

    def pile_mfg_edit_action(action,json)
      data=JSON.parse(json || '{}'); message=''
      case action
      when 'read'
      when 'save'
        n=update_existing_pile_manufacturing(data)
        message="#{n} kazık güncellendi. Var/Yok durumları, kazık içi beton geometrisi ve metraj birlikte güncellendi."
        qto_summary(@d);send_boq(@d)
      else
        raise 'Bilinmeyen imalat yönetimi işlemi.'
      end
      @d.execute_script("setPileMfg(#{JSON.generate(pile_mfg_state(data['scope']).merge(message:message))});")
    rescue=>ex
      msg="#{ex.class}: #{ex.message}"
      @d.execute_script("pileMfgError(#{JSON.generate(msg)});") if @d
    end
  end
end
