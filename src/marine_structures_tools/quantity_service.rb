# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  module QuantityService
   extend self
   class InvalidQuantity < StandardError; end
   UNITS={count:'adet',length_m:'m',steel_t:'t',concrete_m3:'m³',formwork_m2:'m²',area_m2:'m²',rebar_t:'t'}.freeze
   REBAR_RATES={'pile_infill_concrete'=>'pile','head_beam'=>'head_beam','flat_precast'=>'flat_precast','channel_precast'=>'channel_precast','crane_precast'=>'crane_precast','deck_slab'=>'deck','curb'=>'deck','crown_wall'=>'crown_wall','deck_topping'=>'topping'}.freeze
   def api;MarineStructuresTools;end
   def type(e);e.get_attribute(DICT,'element_type','').to_s;end
   def number(raw,key)
    n=Float(raw.to_s.tr(',','.'))
    raise InvalidQuantity,"#{key}: miktar sonlu ve negatif olmayan bir sayı olmalı." unless n.finite? && n>=0
    n
   rescue ArgumentError,TypeError
    raise InvalidQuantity,"#{key}: geçersiz miktar (#{raw.inspect})."
   end
   def attribute(e,keys)
    keys.each do |k|
     raw=e.get_attribute(DICT,k,nil)
     next if raw.nil?
     return {value:number(raw,k),state:'calculated',method:"attribute:#{k}"}
    end
    {value:0.0,state:'missing',method:"attribute:#{keys.join('|')}"}
   end
   def pile_owned_concrete(e)
    # v0.51.5 K36 (A2→B): "iç beton YOK" önce — Component kazığın paylaşılan çocuğu tanımda kalabilir
    return {value:0.0,state:'not_applicable',method:'infill_disabled'} if e.get_attribute(DICT,'infill_enabled',nil).to_s=='0'
    return {value:0.0,state:'not_applicable',method:'physical_child_owner'} unless api.pile_qto_infill_children(e).empty?
    raw=e.get_attribute(DICT,'infill_concrete_volume_m3',nil)
    return attribute(e,['infill_concrete_volume_m3']) unless raw.nil?
    return {value:0.0,state:'not_applicable',method:'no_infill'} if e.get_attribute(DICT,'infill_bottom_elevation_m',nil).nil?
    {value:number(api.pile_qto_concrete(e),'pile_concrete'),state:'estimated',method:'pile_geometry_fallback'}
   end
   def rebar(e)
    t=type(e)
    if t=='steel_pipe_pile' && api.respond_to?(:mst_pile_rebar_effective?) && api.mst_pile_rebar_effective?(e)   # v0.51.5 K59
     result=attribute(e,['pile_cage_rebar_kg']);return result.merge(value:result[:value]/1000.0,method:'bim:pile_cage_rebar_kg')
    end
    if api.respond_to?(:mst_element_rebar)
     if %w[bim_detail drawing_detail auto_detail].include?(e.get_attribute(DICT,'rebar_mode','').to_s)
      result=attribute(e,['rebar_t']);return result.merge(method:'bim:rebar_t')
     end
     if %w[flat_precast channel_precast].include?(t) && e.get_attribute(DICT,'rebar_mode','').to_s.empty? && e.get_attribute(DICT,'pc_rebar_error','').to_s.empty? && api.respond_to?(:mst_pc_def_rebar)   # v0.51.5 K60
      data=api.mst_pc_def_rebar(e)
      return {value:number(data.fetch('rebar_t'),'definition_rebar_t'),state:'calculated',method:'bim:component_definition'} if data
     end
    end
    if t=='bored_pile'
     result=attribute(e,['rebar_t'])
     raw=e.get_attribute(DICT,'bored_pile_data',nil)
     return result if result[:state]=='missing' || raw.to_s.empty?
     data=api.bp_validate(api.bp_data(e))
     if data['rebar_mode']=='rate'
      return result.merge(state:'estimated',method:'volume_rate:bored_pile',rate:data['rebar_rate'],rate_unit:'kg/m³')
     end
     return result.merge(method:'provided_rebar_kg:bored_pile')
    end
    return attribute(e,['rebar_t']) if t=='head_beam' && e.get_attribute(DICT,'rebar_mode','').to_s=='bim_detail'
    rate_key=t=='steel_pipe_pile' ? 'pile' : REBAR_RATES[t]
    return {value:0.0,state:'not_applicable',method:'no_rebar'} unless rate_key
    volume=t=='steel_pipe_pile' ? pile_owned_concrete(e) : calculate(e,:concrete_m3)
    return volume.merge(method:'no_concrete_rebar') if volume[:value]==0
    {value:number(volume[:value]*number(api.rebar_rate(rate_key),'rebar_rate')/1000.0,'rebar_t'),state:'estimated',method:"volume_rate:#{rate_key}"}
   end
   def calculate(e,key)
    t=type(e)
    case key.to_sym
    when :count;{value:1.0,state:'calculated',method:'physical_element'}
    when :length_m;attribute(e,%w[actual_length_m length_m])
    when :concrete_m3
     if t=='head_beam' && api.respond_to?(:head_beam_net_concrete)
      {value:number(api.head_beam_net_concrete(e),'net_head_beam_concrete'),state:'calculated',method:'net_head_beam_concrete'}
     else
      t=='steel_pipe_pile' ? {value:0.0,state:'not_applicable',method:'parent_concrete_summary'} : attribute(e,%w[concrete_volume_m3 volume_m3])
     end
    when :rebar_t;rebar(e)
    when :steel_t
     if t=='steel_pipe_pile' && api.respond_to?(:mst_pile_canonical_weight_kg)
      diameter=number(e.get_attribute(DICT,'diameter_mm',nil),'diameter_mm')
      thickness=number(e.get_attribute(DICT,'thickness_mm',nil),'thickness_mm')
      length=attribute(e,%w[actual_length_m length_m]);raise InvalidQuantity,'Kazık boyu eksik.' if length[:state]=='missing'
      raise InvalidQuantity,'Kazık kesiti veya boyu geçersiz (dış çap > 2 × et kalınlığı, et kalınlığı ve boy > 0 olmalı).' unless diameter>2*thickness && thickness>0 && length[:value]>0
      {value:number(api.pile_weight(diameter,thickness,length[:value]),'canonical_pipe_kg')/1000.0,state:'calculated',method:'canonical_pipe_mass'}
     else
      if t=='steel_pipe_pile'
       result=attribute(e,%w[weight_kg theoretical_weight_kg]);result.merge(value:result[:value]/1000.0)
      else
       rebar(e)
      end
     end
    when :formwork_m2
     return {value:0.0,state:'not_applicable',method:'steel_pipe_no_formwork'} if t=='steel_pipe_pile'   # 03.11.2026: çelik boru kazıkta kalıp yok (runner uyarısı; değer aynı 0)
    t=='head_beam' ? {value:number(api.head_beam_net_formwork_area(e),'formwork_m2'),state:'calculated',method:'net_faces'} : attribute(e,['formwork_area_m2'])
    when :area_m2;attribute(e,['net_area_m2'])
    else;{value:0.0,state:'not_applicable',method:'unsupported'}
    end
   end
   def record(e,key)
    result=calculate(e,key)
    result.merge(unit:UNITS[key.to_sym],source_uid:e.get_attribute(DICT,'element_uid','').to_s,source_pid:e.persistent_id,key:key.to_s,engine_version:'2-tb1')
   rescue StandardError=>error
    {value:nil,state:'invalid',message:error.message,unit:UNITS[key.to_sym],key:key.to_s,source_pid:e.persistent_id}
   end
   def value(e,key)
    r=record(e,key)
    raise InvalidQuantity,"#{e.get_attribute(DICT,'element_uid',"PID-#{e.persistent_id}")}: #{r[:message]}" if r[:state]=='invalid'
    r[:value]
   end
   def rebar_sources(elements)
    elements.select{|e|REBAR_RATES.key?(type(e)) || type(e)=='bored_pile' || (type(e)=='steel_pipe_pile' && api.pile_qto_infill_children(e).empty? && pile_owned_concrete(e)[:value]>0)}
   end
   def boq_rebar_total(elements)
    if api.respond_to?(:mst_boq_rebar_breakdown)
     return api.mst_boq_rebar_breakdown(elements).sum{|row|number(row.fetch(:kg),'boq_rebar_kg')}/1000.0
    end
    # ADR-0515 G4: curb rebar is in the BOQ REBAR scope; topping rebar is added below from the deck topping volume.
    sources=rebar_sources(elements).reject{|e|type(e)=='deck_topping'}
    total=sources.sum{|e|value(e,:rebar_t)}
    _area,volume=api.topping_quantities(elements)
    total+number(volume,'topping_volume')*number(api.rebar_rate('topping'),'topping_rate')/1000.0
   end
  end
 end
end
