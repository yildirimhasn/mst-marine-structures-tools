# frozen_string_literal: true
require 'digest'
module MAG
 module MarineStructuresTools
  REVISION_PARAMETER_KEYS=%w[element_type diameter_mm thickness_mm length_m actual_length_m width_m height_m thickness_m bottom_elevation_m top_elevation_m seabed_elevation_m batter_ratio azimuth_deg start_tooth_enabled start_tooth_length_m start_tooth_depth_m start_tooth_slope_m end_tooth_enabled end_tooth_length_m end_tooth_depth_m end_tooth_slope_m start_seat_enabled start_seat_offset_m start_seat_length_m start_seat_depth_m end_seat_enabled end_seat_offset_m end_seat_length_m end_seat_depth_m steel_grade concrete_class infill_concrete_class infill_enabled infill_bottom_elevation_m rebar_mode rebar_t rebar_cover_mm splice_mode splice_count_per_pile drilling_enabled drilling_length_m pe_enabled pe_length_m system structure project ano axis].freeze
  REVISION_RELATION_KEYS=%w[parent_uid support_uids support_left_uid support_right_uid support_pids support_left_pid support_right_pid pile_ids parent_deck_id].freeze
  def revision_digest(value);Digest::SHA256.hexdigest(JSON.generate(value));end
  def revision_parameter_signature(e)
   revision_digest(REVISION_PARAMETER_KEYS.map{|k|[k,e.get_attribute(DICT,k,nil)]})
  end
  def revision_relationship_signature(e)
   revision_digest(REVISION_RELATION_KEYS.map{|k|[k,e.get_attribute(DICT,k,'').to_s.split(',').map(&:strip).reject(&:empty?).sort]})
  end
  def revision_occurrence_signatures(entities)
   return {} unless defined?(Geom::Transformation)
   paths=Hash.new{|h,k|h[k]=[]}
   walk=nil
   walk=lambda do |ents,parent,path|
    ents.each do |e|
     next unless e.respond_to?(:transformation)
     transform=parent*e.transformation
     chain=path+[e.persistent_id]
     paths[e.persistent_id]<<[chain,transform.to_a.map{|v|v.round(9)}]
     child=e.respond_to?(:entities) ? e.entities : (e.respond_to?(:definition) ? e.definition.entities : nil)
     walk.call(child,transform,chain) if child
    end
   end
   walk.call(entities,Geom::Transformation.new,[])
   paths.transform_values{|v|revision_digest(v.map{|r|r[1]}.sort)}
  end
  def revision_geometry_signature(e,occurrences={})
   shape=nil
   shape=lambda do |node|
    transform=node.respond_to?(:transformation) ? node.transformation.to_a.map{|v|v.round(9)} : []
    ents=node.respond_to?(:entities) ? node.entities : (node.respond_to?(:definition) ? node.definition.entities : [])
    shapes=[];children=[]
    ents.each do |part|
     if part.respond_to?(:transformation)
      children<<shape.call(part)
     elsif part.respond_to?(:loops)
      shapes<<['face',part.loops.map{|loop|loop.vertices.map{|v|v.position.to_a.map{|n|n.round(6)}}}]
     elsif part.respond_to?(:vertices)
      shapes<<['edge',part.vertices.map{|v|v.position.to_a.map{|n|n.round(6)}}.sort]
     end
    end
    [transform,shapes.sort_by{|v|JSON.generate(v)},children.sort_by{|v|JSON.generate(v)}]
   end
   revision_digest([occurrences[e.persistent_id],shape.call(e)])
  end
 end
end
