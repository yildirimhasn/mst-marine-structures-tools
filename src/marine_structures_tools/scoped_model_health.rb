# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  def scoped_model_health_show(raw)
   request=JSON.parse(raw)
   calculate=lambda do
    model=Sketchup.active_model;entries=ProjectWorkspace.entries(model)
    targets=ProjectWorkspace.validate_request(model,request,entries)
    ModelHealth.analyze(model,keys:targets.map{|entry|entry[:key]})
   end
   data=calculate.call
   @scoped_health_dialog.close if @scoped_health_dialog&&@scoped_health_dialog.visible?
   d=UI::HtmlDialog.new(dialog_title:'MST — Kapsam Sağlık Kontrolü',width:1080,height:760,resizable:true)
   d.set_file(File.join(__dir__,'model_health.html'))
   watch=HealthFreshness.new(d);watch.capture(data);d.set_on_closed{watch.close} if d.respond_to?(:set_on_closed)
   show=lambda{|revision=nil|watch.publish(data,revision:revision)}
   failure=lambda{|error|d.execute_script("modelHealthError(#{JSON.generate(error.message)})")}
   valid_key=lambda do |key|
    raise 'Aktif model değişti; kapsamı çalışma alanından yeniden açın.' unless data[:model_token]==Sketchup.active_model.object_id.to_s
    raise 'Eleman bu kontrol kapsamında değil.' unless data[:records].any?{|record|record[:key]==key}
   end
   d.add_action_callback('health_ready'){|_|show.call}
   d.add_action_callback('health_refresh'){|_|
    begin;data=calculate.call;show.call;rescue=>error;failure.call(error);end
   }
   d.add_action_callback('health_select'){|_,key|
    begin
     valid_key.call(key);ProjectWorkspace.select(Sketchup.active_model,{'model_token'=>data[:model_token],'keys'=>[key],'zoom'=>true})
    rescue=>error;failure.call(error);end
   }
   d.add_action_callback('health_repair'){|_,key|
    begin;valid_key.call(key);record_repair_show(JSON.generate({'model_token'=>data[:model_token],'keys'=>[key]}));rescue=>error;failure.call(error);end
   }
   d.add_action_callback('health_batch_repair'){|_,raw|
    begin
     selected=BatchRecordRepair.health_request(Sketchup.active_model,data,raw)
     batch_record_repair_show(selected)
    rescue=>error;failure.call(error);end
   }
   d.add_action_callback('health_report'){|_|
    begin
     data=calculate.call
     revision=watch.revision
     result=HealthReport.export_snapshot(data,model_name:"KAPSAM KONTROLÜ · #{data[:scope][:selected]} / #{data[:scope][:model_elements]} eleman",filename:'MST_Kapsam_Kontrol_Raporu.html')
     show.call(revision);d.execute_script("modelHealthError(#{JSON.generate(result ? 'Kapsam raporu kaydedildi.' : 'Kaydetme iptal edildi.')})")
    rescue=>error;failure.call(error);end
   }
   d.add_action_callback('health_export'){|_|
    begin
     data=calculate.call;path=UI.savepanel('Kapsam Kontrolünü Kaydet','','MST_Kapsam_Kontrol.json')
     if path
      data=calculate.call;path+='.json' unless path.downcase.end_with?('.json');SafeReportFile.write(path,JSON.pretty_generate(data));show.call
      d.execute_script("modelHealthError(#{JSON.generate('Kapsam kontrolü kaydedildi.')})")
     else
      d.execute_script("modelHealthError(#{JSON.generate('Kaydetme iptal edildi.')})")
     end
    rescue=>error;failure.call(error);end
   }
   @scoped_health_dialog=d;d.show
  rescue=>error
   UI.messagebox("Kapsam kontrolü açılamadı: #{error.message}")
  end
 end
end
