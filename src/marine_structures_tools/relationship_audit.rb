# frozen_string_literal: true
require 'time'
module MAG
 module MarineStructuresTools
  module RelationshipAudit
   extend self
   def api;MarineStructuresTools;end
   def tokens(value);value.to_s.split(',').map(&:strip).reject(&:empty?);end
   def analyze(model)
    entries=ProjectWorkspace.entries(model)
    pid=entries.group_by{|r|r[:entity].persistent_id.to_s}
    uid=entries.group_by{|r|r[:entity].get_attribute(DICT,'element_uid','').to_s}
    ids=entries.group_by{|r|api.element_visible_id(r[:entity]).to_s}
    records=[]
    entries.each do |entry|
     e=entry[:entity];type=e.get_attribute(DICT,'element_type','');checks=[]
     add=lambda{|code,message|checks<<{code:code,message:message}}
     own_uid=e.get_attribute(DICT,'element_uid','').to_s
     add.call('MISSING_UID','Eleman UID kimliği eksik.') if own_uid.empty?
     add.call('DUPLICATE_UID','UID birden fazla fiziksel yerleşimde kullanılıyor.') if !own_uid.empty?&&uid[own_uid].size>1
     refs=[]
     case type
     when 'flat_precast','channel_precast','crane_precast'
      left=e.get_attribute(DICT,'support_left_pid',nil);right=e.get_attribute(DICT,'support_right_pid',nil)
      refs=[['Sol mesnet',pid,left,'head_beam',e.get_attribute(DICT,'support_left_uid','')],['Sağ mesnet',pid,right,'head_beam',e.get_attribute(DICT,'support_right_uid','')]]
      add.call('SAME_SUPPORT','Sol ve sağ mesnet aynı elemanı gösteriyor.') if !left.nil?&&left.to_s==right.to_s&&left.to_s!='0'
     when 'deck_slab'
      values=tokens(e.get_attribute(DICT,'support_pids',''))
      add.call('TOO_FEW_SUPPORTS','Döşeme için en az iki farklı başlık kirişi kaydı gerekli.') if values.uniq.size<2
      add.call('DUPLICATE_SUPPORT','Mesnet listesi yinelenen kayıt içeriyor.') if values.size!=values.uniq.size
      refs=values.uniq.map{|value|['Döşeme mesnedi',pid,value,'head_beam','']}
     when 'head_beam'
      values=tokens(e.get_attribute(DICT,'connected_pile_ids',''))
      add.call('NO_PILE_SUPPORT','Başlık kirişi için bağlı kazık kaydı bulunamadı.') if values.empty?
      add.call('DUPLICATE_SUPPORT','Kazık listesi yinelenen kayıt içeriyor.') if values.size!=values.uniq.size
      refs=values.uniq.map{|value|['Kazık mesnedi',ids,value,'steel_pipe_pile','']}
     when 'curb'
      parent=e.get_attribute(DICT,'parent_uid','').to_s
      refs=parent.empty? ? [['Ana döşeme',ids,e.get_attribute(DICT,'parent_deck_id',''),'deck_slab','']] : [['Ana döşeme',uid,parent,'deck_slab','']]
     end
     resolved=[]
     refs.each do |label,index,value,expected,expected_uid|
      key=value.to_s.strip
      if key.empty?||key=='0'
       add.call('MISSING_REFERENCE',"#{label}: bağlantı kaydı eksik.");next
      end
      candidates=index[key]||[]
      if candidates.empty?
       add.call('DANGLING_REFERENCE',"#{label}: #{key} modelde bulunamadı.");next
      end
      if candidates.size>1
       add.call('AMBIGUOUS_REFERENCE',"#{label}: #{key} birden fazla fiziksel yerleşime karşılık geliyor.");next
      end
      target=candidates.first;parent=target[:entity]
      if parent.get_attribute(DICT,'element_type','')!=expected
       add.call('WRONG_TYPE',"#{label}: beklenen eleman türü #{ProjectWorkspace::TYPES[expected]}.");next
      end
      actual_uid=parent.get_attribute(DICT,'element_uid','').to_s
      add.call('TARGET_UID_MISSING',"#{label}: mesnet UID kimliği eksik.") if actual_uid.empty?
      add.call('TARGET_UID_AMBIGUOUS',"#{label}: mesnet UID kimliği başka yerleşimde de kullanılıyor.") if !actual_uid.empty?&&uid[actual_uid].size>1
      add.call('UID_PID_CONFLICT',"#{label}: PID ve UID farklı elemanları gösteriyor.") if !expected_uid.to_s.empty?&&expected_uid.to_s!=actual_uid
      %w[project structure].each do |field|
       a=e.get_attribute(DICT,field,'').to_s.strip;b=parent.get_attribute(DICT,field,'').to_s.strip
       if field=='structure'
        a=e.get_attribute(DICT,'ano','').to_s.strip if a.empty?
        b=parent.get_attribute(DICT,'ano','').to_s.strip if b.empty?
       end
       add.call('ORGANIZATION_INCOMPLETE',"#{label}: #{field=='project' ? 'proje' : 'yapı'} bilgisi eksik.") if a.empty?||b.empty?
       add.call('ORGANIZATION_CONFLICT',"#{label}: #{field=='project' ? 'proje' : 'yapı'} bilgileri uyuşmuyor (#{a} / #{b}).") if !a.empty?&&!b.empty?&&a!=b
      end
      source_ano=e.get_attribute(DICT,'ano','').to_s.strip;target_ano=parent.get_attribute(DICT,'ano','').to_s.strip
      add.call('ANO_CONFLICT',"#{label}: ANO kayıtları uyuşmuyor.") if !source_ano.empty?&&!target_ano.empty?&&source_ano!=target_ano
      resolved<<{key:target[:key],id:api.element_visible_id(parent),uid:actual_uid}
     end
     declared=tokens(e.get_attribute(DICT,'support_uids','')).sort
     if %w[deck_slab flat_precast channel_precast crane_precast].include?(type)&&!declared.empty?&&refs.size==resolved.size
      add.call('SUPPORT_SET_CONFLICT','Mesnet PID listesi ile UID listesi uyuşmuyor.') unless declared==resolved.map{|r|r[:uid]}.sort
     end
     structural=%w[flat_precast channel_precast crane_precast deck_slab head_beam curb].include?(type)
     state=checks.empty? ? (structural ? 'consistent' : 'identity_only') : 'needs_review'
     records<<{key:entry[:key],id:api.element_visible_id(e),type:type,label:ProjectWorkspace::TYPES[type],state:state,checks:checks,supports:resolved}
    end
    {schema:'mst.relationship-audit/1',version:VERSION,created_at:Time.now.utc.iso8601,model_token:model.object_id.to_s,
     summary:{elements:records.size,needs_review:records.count{|r|r[:state]=='needs_review'},consistent:records.count{|r|r[:state]=='consistent'},identity_only:records.count{|r|r[:state]=='identity_only'}},records:records,
     limitation:'Metadata bağlantı tutarlılığı kontrolüdür. Geometrik temas, taşıma kapasitesi ve otomatik yeniden oluşturma uygunluğu onayı değildir.'}
   end
  end
  def relationship_audit_show
   data=RelationshipAudit.analyze(Sketchup.active_model);@relationship_audit_data=data
   @relationship_audit_dialog.close if @relationship_audit_dialog&&@relationship_audit_dialog.visible?
   d=UI::HtmlDialog.new(dialog_title:'MST — Mesnet ve Bağlantı Kontrolü',width:1050,height:730,resizable:true)
   d.set_file(File.join(__dir__,'relationship_audit.html'))
   d.add_action_callback('audit_ready'){|_|d.execute_script("loadRelationshipAudit(#{JSON.generate(data)})")}
   d.add_action_callback('audit_refresh'){|_|
    begin
     data=RelationshipAudit.analyze(Sketchup.active_model);@relationship_audit_data=data
     d.execute_script("loadRelationshipAudit(#{JSON.generate(data)})")
    rescue=>error;d.execute_script("relationshipAuditError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('audit_select'){|_,key|
    begin
     ProjectWorkspace.select(Sketchup.active_model,{'model_token'=>data[:model_token],'keys'=>[key],'zoom'=>true})
    rescue=>error;d.execute_script("relationshipAuditError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('audit_export'){|_|
    begin
     # Export a fresh snapshot, not the potentially stale visible report.
     fresh=RelationshipAudit.analyze(Sketchup.active_model)
     path=UI.savepanel('Bağlantı Kontrol Raporunu Kaydet','','MST_Baglanti_Kontrolu.json')
     if path
      path+='.json' unless path.downcase.end_with?('.json')
      File.write(path,JSON.pretty_generate(fresh),mode:'w',encoding:'UTF-8')
      data=fresh;@relationship_audit_data=fresh;d.execute_script("loadRelationshipAudit(#{JSON.generate(fresh)})")
      d.execute_script("relationshipAuditError(#{JSON.generate('Güncel rapor kaydedildi.')})")
     end
    rescue=>error;d.execute_script("relationshipAuditError(#{JSON.generate(error.message)})");end
   }
   @relationship_audit_dialog=d;d.show
  rescue=>error;UI.messagebox("Bağlantı kontrolü açılamadı: #{error.message}");end
 end
end
