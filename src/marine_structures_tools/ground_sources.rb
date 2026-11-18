# frozen_string_literal: true
require 'json'
module MAG
module MarineStructuresTools
def mst_ground_progress_source?(source)
 source.to_s.start_with?('BORED:','JETGROUT:')
end

# One physical-source map shared by schedule, BOQ tracing and progress.
# Quantities come from existing validated metrics, never a second formula.
def mst_ground_source_quantities(entity,data=nil,metrics=nil)
 case entity.get_attribute(DICT,'element_type','')
 when 'bored_pile'
  d=data || bp_validate(bp_data(entity));q=metrics || bp_metrics(d)
  result={"BORED:DRILL:#{d['diameter']}"=>q[:drilling],"BORED:CONCRETE:#{d['diameter']}:#{d['concrete']}"=>q[:volume]}
  result["BORED:CASING:#{d['casing']}"]=q[:casing] if q[:casing]>0
  result
 when 'jet_grout'
  d=data || jg_validate(JSON.parse(entity.get_attribute(DICT,'jet_grout_data')))
  return {} unless d['enabled']
  q=metrics || jg_metrics(d);prefix="JETGROUT:#{d['type_id']}:#{d['diameter']}:#{d['system']}"
  %i[length drilling cement grout steel].each_with_object({}){|k,h|h["#{prefix}:#{k}"]=q[k] if q[k] && q[k]>0}
 else
  {}
 end
end

# Called only inside prog2_apply's undoable transaction, after confirming that
# the selection contains an entity belonging to this source. Reading a project
# never migrates it. A source-wide legacy percentage remains authoritative until
# the user deliberately begins physical-element editing for that source.
def mst_ground_materialize_progress!(key,base,entities,expected_quantity=nil)
 manual=prog2_manual;record=prog2_norm(manual[key]);return unless record
 if expected_quantity
  actual=entities.sum{|e|mst_ground_source_quantities(e)[base].to_f};expected=Float(expected_quantity)
  raise 'Elle ilerlemenin miktarı fiziksel toplamla uyuşmuyor; geçiş yapılmadı. Önce BOQ miktarını uzlaştırın.' if (actual-expected).abs>[1e-6,expected.abs*1e-9].max
 end
 records=entities.map{|entity|[entity,prog2_items_for_write(entity)]}
 backup={source:key,manual:manual[key],entities:records.map{|entity,items|{pid:entity.persistent_id,previous:items[base]}}}
 raw=Sketchup.active_model.get_attribute(PROGRESS_DICT,'ground_progress_migrations_json','[]')
 history=JSON.parse(raw)
 raise 'Zemin ilerleme geçiş arşivi okunamadı; kayıtlar değiştirilmedi.' unless history.is_a?(Array)
 records.each do |entity,h|
  h[base]=JSON.parse(JSON.generate(record))
  entity.set_attribute(DICT,PROG2_KEY,JSON.generate(h))
 end
 history<<backup;manual.delete(key)
 model=Sketchup.active_model
 model.set_attribute(PROGRESS_DICT,'ground_progress_migrations_json',JSON.generate(history))
 model.set_attribute(PROGRESS_DICT,'manual_progress_json',JSON.generate(manual))
end
end
end
