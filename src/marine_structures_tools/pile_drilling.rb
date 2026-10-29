# frozen_string_literal: true
module MAG
  module MarineStructuresTools
    def drilling_edit_targets(scope)
      model=Sketchup.active_model
      case scope
      when 'all'
        elements=[];collect_elements(model.entities,elements)
      when 'selected'
        elements=model.selection.to_a
      else
        raise 'Kazık kapsamı geçersiz.'
      end
      elements.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','')=='steel_pipe_pile'}.uniq
    end

    def drilling_edit_state(scope)
      piles=drilling_edit_targets(scope)
      states=piles.map{|p|p.get_attribute(DICT,'drilling_enabled','0').to_s=='1' ? '1' : '0'}.uniq
      lengths=piles.map{|p|p.get_attribute(DICT,'drilling_length_m',0).to_f}.uniq
      {count:piles.size,enabled:states.size==1 ? states.first : '',length:lengths.size==1 ? lengths.first : nil,
       model_token:Sketchup.active_model.object_id.to_s}
    end

    def update_existing_pile_drilling(data)
      model=Sketchup.active_model
      raise 'Aktif model değişti; önce Kazıkları Oku düğmesine basın.' unless data['model_token']==model.object_id.to_s
      piles=drilling_edit_targets(data['scope'])
      raise 'Bu kapsamda kazık bulunamadı. Kazık gruplarını seçin veya tüm kazıkları seçeneğini kullanın.' if piles.empty?
      enabled=data['enabled']
      raise 'Foraj Var veya Yok seçin.' unless %w[0 1].include?(enabled)
      mode=data['length_mode']
      raise 'Foraj boyu seçimi geçersiz.' unless %w[keep set].include?(mode)
      length=nil
      if enabled=='1' && mode=='set'
        begin
          length=Float(data['length'].to_s.tr(',','.'))
        rescue ArgumentError,TypeError
          raise 'Kazık başına foraj boyunu metre olarak girin.'
        end
        raise 'Foraj boyu sıfırdan büyük ve sonlu olmalı.' unless length.finite? && length>0
      end
      if enabled=='1' && mode=='keep'
        missing=piles.count{|p|v=p.get_attribute(DICT,'drilling_length_m',0).to_f;!v.finite? || v<=0}
        raise "#{missing} kazıkta geçerli foraj boyu yok. Yeni boy gir seçeneğini kullanın." if missing>0
      end
      changed=piles.select{|p|p.get_attribute(DICT,'drilling_enabled','0').to_s!=enabled || (!length.nil? && p.get_attribute(DICT,'drilling_length_m',0).to_f!=length)}
      return 0 if changed.empty?
      model.start_operation('Mevcut Kazıklarda Forajı Düzenle',true)
      begin
        changed.each do |p|
          p.set_attribute(DICT,'drilling_enabled',enabled)
          p.set_attribute(DICT,'drilling_length_m',length) unless length.nil?
        end
        model.commit_operation
      rescue
        model.abort_operation
        raise
      end
      changed.size
    end

    def drilling_edit_action(action,json)
      data=JSON.parse(json || '{}');message=''
      case action
      when 'read'
      when 'save'
        count=update_existing_pile_drilling(data)
        message="#{count} kazık güncellendi. Foraj kapatıldığında kayıtlı boylar korunur. Ctrl+Z ile geri alabilirsiniz."
        qto_summary(@d);send_boq(@d)
      else
        raise 'Bilinmeyen foraj işlemi.'
      end
      @d.execute_script("setDrillingEditor(#{JSON.generate(drilling_edit_state(data['scope']).merge(message:message))});")
    rescue=>ex
      @d.execute_script("drillingEditError(#{JSON.generate(ex.message)});") if @d
    end
  end
end
