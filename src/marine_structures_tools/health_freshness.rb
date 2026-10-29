# frozen_string_literal: true
require 'json'
module MAG
 module MarineStructuresTools
  class HealthFreshness
   attr_reader :revision
   class ModelObserver < Sketchup::ModelObserver
    def initialize(owner);@owner=owner;end
    def onTransactionCommit(model);@owner.changed(model);end
    def onTransactionUndo(model);@owner.changed(model);end
    def onTransactionRedo(model);@owner.changed(model);end
    def onTransactionAbort(model);@owner.changed(model);end
   end
   class AppObserver < Sketchup::AppObserver
    def initialize(owner);@owner=owner;end
    def onNewModel(model);@owner.active_changed(model);end
    def onOpenModel(model);@owner.active_changed(model);end
   end
   def initialize(dialog)
    @dialog=dialog;@closed=false;@model=nil;@revision=0;@observer=ModelObserver.new(self)
    @app_observer=AppObserver.new(self)
    if Sketchup.respond_to?(:add_observer)&&Sketchup.respond_to?(:remove_observer)
     @app_attached=Sketchup.add_observer(@app_observer)!=false
    end
   rescue StandardError
    @app_attached=false
   end
   def attach(model)
    return if @model.equal?(model)
    detach_model
    if model.respond_to?(:add_observer)&&model.respond_to?(:remove_observer)
     @model=model unless model.add_observer(@observer)==false
    end
   rescue StandardError
    @model=nil
   end
   def capture(data)
    @captured=data;@reason=nil;@token=data[:model_token]
    active=Sketchup.active_model;attach(active) if active.object_id.to_s==@token
   end
   def publish(data,revision:nil)
    return if @closed
    capture(data) unless @captured.equal?(data)
    @reason='Model kontrolünden sonra değişti. Sonuç kontrol anına aittir; Yeniden Kontrol Et ile güncelleyin.' if revision&&revision!=@revision
    @dialog.execute_script("modelHealthObserved(#{!!@model})")
    @dialog.execute_script("loadModelHealth(#{JSON.generate(data)})")
    @dialog.execute_script("modelHealthStale(#{JSON.generate(@reason)})") if @reason
    active_changed(Sketchup.active_model)
   end
   def changed(model)
    return if @closed||!model.equal?(@model)
    @revision+=1
    message='Model işlemi değişti. Bu sonuç önceki kontrol anına aittir; Yeniden Kontrol Et ile güncelleyin.'
    @reason=message
    @dialog.execute_script("modelHealthStale(#{JSON.generate(message)})")
   end
   def active_changed(model)
    return if @closed||!@token||model.object_id.to_s==@token
    @revision+=1
    @reason='Aktif model değişti. Tüm-model kontrolünü yenileyin; seçili kapsamı çalışma alanından yeniden açın.'
    @dialog.execute_script("modelHealthStale(#{JSON.generate(@reason)})")
   end
   def detach_model
    model=@model;@model=nil;model.remove_observer(@observer) if model
   rescue StandardError
    nil
   end
   def close
    return if @closed
    @closed=true;detach_model
    Sketchup.remove_observer(@app_observer) if @app_attached
   rescue StandardError
    nil
   end
  end
 end
end
