# frozen_string_literal: true
module MAG
  module MarineStructuresTools
    VERSION = '0.51.5'.freeze unless const_defined?(:VERSION)

    def normalize_pile_inputs!(data)
      numeric = %w[diameter_mm thickness_mm length_m top_elevation_m seabed_elevation_m driving_length_m
        splice_count_per_pile plug_count_per_pile plug_thickness_mm plug_clearance_mm
        upper_ring_width_mm upper_ring_thickness_mm upper_ring_count_per_pile
        lower_ring_width_mm lower_ring_thickness_mm lower_ring_count_per_pile
        pe_length_m drilling_length_m batter_ratio azimuth_deg count_x count_y spacing_x_m spacing_y_m
        start_no start_low_count start_low_top_m end_low_count end_low_top_m
        infill_bottom_normal_m infill_bottom_start_m infill_bottom_end_m
        placement_origin_x_m placement_origin_y_m x y dx dy]
      normalize = lambda do |record|
        record.each do |key, value|
          next unless numeric.include?(key) && !value.nil? && !value.to_s.strip.empty?
          begin
            s = value.to_s.strip.tr(',', '.')
            if key == 'batter_ratio' && s.include?('/')
              parts = s.split('/', -1)
              raise ArgumentError unless parts.length == 2
              denominator = Float(parts[1])
              raise ArgumentError if denominator <= 0
              n = Float(parts[0]) / denominator
            else
              n = Float(s)
            end
            raise ArgumentError unless n.finite?
          rescue ArgumentError, TypeError
            raise "Geçersiz sayısal değer: #{key} (#{value}). Ondalık ayırıcı olarak virgül veya nokta kullanın."
          end
          if key.include?('count') || key == 'start_no'
            raise "Tam sayı gerekli: #{key}" unless n == n.to_i && n >= 0
          end
          record[key] = n
        end
      end
      normalize.call(data)
      validate_pile_section!(data)
      if data['custom_axis_json'].is_a?(String) && !data['custom_axis_json'].strip.empty?
        axes = JSON.parse(data['custom_axis_json'])
        raise 'Kazık aks listesi geçersiz.' unless axes.is_a?(Array)
        axes.each do |axis|
          normalize.call(axis)
          (axis['points'] || []).each do |point|
            normalize.call(point)
            next if point['selected'] == false
            overrides = point.reject { |_, value| value.nil? || value.to_s.strip.empty? }
            validate_pile_section!(data.merge(overrides))
          end
        end
        data['custom_axis_json'] = JSON.generate(axes)
      end
      data
    end

    def validate_pile_section!(data)
      d = data['diameter_mm'].to_f
      t = data['thickness_mm'].to_f
      length = data['length_m'].to_f
      raise 'Çap ve et kalınlığı pozitif olmalı; çap, et kalınlığının iki katından büyük olmalı.' unless d > 0 && t > 0 && d > 2 * t
      raise 'Kazık boyu sıfırdan büyük olmalı.' unless length > 0
      raise 'Eğim oranı negatif olamaz.' if data['batter_ratio'].to_f < 0
      true
    end

    # Pure reads: reports never stamp cached attributes onto the model.
    # v0.51.5 P4: yalnız okuma batch'inde (mst_read_batch; yazma batch'inde ve batch dışında değil) sonuç kazık başına bir kez
    # taranır — anahtar Group'ta kazığın persistent_id'si, Component'te tanımın persistent_id'si (aynı tanımı paylaşan kazıklar
    # aynı çocukları görür). Önbellek donmuş kopyadır; her çağrı yeni dizi alır, geçersizleşen öğeler süzülür. Batch bitince silinir.
    def pile_qto_infill_children(pile)
      rb = @mst_read_batch_on
      key = nil
      if rb
        key = if pile.respond_to?(:entities)
          [:e, pile.persistent_id]
        elsif pile.respond_to?(:definition)
          [:d, (pile.definition.persistent_id rescue nil)]
        end
        key = nil if key && key[1].to_i <= 0
        if key
          @mst_infill_children_cache = {rb: rb, map: {}} unless @mst_infill_children_cache && @mst_infill_children_cache[:rb] == rb
          hit = @mst_infill_children_cache[:map][key]
          return hit.select(&:valid?) if hit
        end
      end
      ents = if pile.respond_to?(:entities)
        pile.entities
      elsif pile.respond_to?(:definition)
        pile.definition.entities
      end
      return [] unless ents
      out = ents.select { |e| e.respond_to?(:get_attribute) && e.get_attribute(DICT, 'element_type', '') == 'pile_infill_concrete' }
      @mst_infill_children_cache[:map][key] = out.dup.freeze if key
      out
    end

    def pile_qto_concrete(pile)
      # v0.51.5 K36: "iç beton YOK" önce okunur — Component kazığın paylaşılan çocuğu silinmez, sayılmamalı
      return 0.0 if pile.get_attribute(DICT, 'infill_enabled', nil).to_s == '0'
      children = pile_qto_infill_children(pile)
      return children.sum { |e| qto3_quantity(e, :concrete_m3) } unless children.empty?
      v = pile.get_attribute(DICT, 'infill_concrete_volume_m3', nil)
      return QuantityService.number(v,'infill_concrete_volume_m3') unless v.nil?
      bottom = pile.get_attribute(DICT, 'infill_bottom_elevation_m', nil)
      return 0.0 if bottom.nil?
      od = pile.get_attribute(DICT, 'diameter_mm', 0).to_f / 1000.0
      wt = pile.get_attribute(DICT, 'thickness_mm', 0).to_f / 1000.0
      top = pile.get_attribute(DICT, 'top_elevation_m', 0).to_f
      ratio = pile.get_attribute(DICT, 'batter_ratio', 0).to_f
      Math::PI / 4.0 * [od - 2.0 * wt, 0.0].max**2 * [top - bottom.to_f, 0.0].max * Math.sqrt(1.0 + ratio**2)
    end

    def pile_splice_count(pile)
      if pile.get_attribute(DICT, 'splice_mode', 'AUTO') == 'MANUAL'
        return [pile.get_attribute(DICT, 'splice_count_per_pile', 0).to_i, 0].max
      end
      length = pile.get_attribute(DICT, 'actual_length_m', pile.get_attribute(DICT, 'length_m', 0)).to_f
      [((length / 12.0).ceil - 1), 0].max
    end

    def pile_driving_source(pile)
      seabed = pile.get_attribute(DICT, 'seabed_elevation_m', nil)
      bottom = pile.get_attribute(DICT, 'bottom_elevation_m', nil)
      return 'KOT' unless seabed.nil? || bottom.nil?
      stored = pile.get_attribute(DICT, 'driving_length_m', nil)
      return 'GIRILEN' unless stored.nil? || stored.to_s.strip.empty?
      'VARSAYIM'
    end

    def pile_qto_match?(pile, data)
      return false unless pile.get_attribute(DICT, 'element_type', '') == 'steel_pipe_pile'
      return false if data.key?('zone') && pile_report_system(pile) != data['zone'].to_s
      if data.key?('structure') && !data['structure'].nil?
        return false unless pile_report_structure(pile) == data['structure'].to_s
      end
      %w[diameter_mm thickness_mm].all? do |key|
        !data.key?(key) || data[key].nil? || pile.get_attribute(DICT, key, 0).to_f.round(3) == data[key].to_f.round(3)
      end
    end

    # Shared hierarchy and full-precision values for dashboard and Excel.
    def pile_qto_hierarchy(piles)
      rows = []
      sn = mst_structure_display_names(Sketchup.active_model)   # ADR-0515-I: label = görünen ad; key / structure = kod
      add = lambda do |items, level, label, system, structure, section|
        key = JSON.generate([level, system, structure, section])
        parent = level == 'structure' ? JSON.generate(['system', system, nil, nil]) :
          (level == 'section' ? JSON.generate(['structure', system, structure, nil]) : nil)
        rows << {level: level, key: key, parent: parent, label: label, zone: system, structure: structure,
          structure_label: structure && mst_structure_display(structure, sn),
          diameter_mm: section && section[0], thickness_mm: section && section[1],
          values: pile_fabrication_qto_row(items, label, true),
          concrete_classes: pile_report_concrete_classes(items)}
      end
      piles.group_by { |p| pile_report_system(p) }.sort.each do |system, sys_piles|
        add.call(sys_piles, 'system', system, system, nil, nil)
        sys_piles.group_by { |p| pile_report_structure(p) }.sort.each do |structure, structure_piles|
          add.call(structure_piles, 'structure', mst_structure_display(structure, sn), system, structure, nil)
          structure_piles.group_by { |p| [p.get_attribute(DICT, 'diameter_mm', 0).to_f.round(3), p.get_attribute(DICT, 'thickness_mm', 0).to_f.round(3)] }.sort.each do |section, items|
            add.call(items, 'section', "Ø#{format('%.1f', section[0])} × #{format('%.1f', section[1])}", system, structure, section)
          end
        end
      end
      rows
    end

    def qto_reconcile_pile_infill!(snapshot, piles)
      # Component piles: their infill child lives in a SHARED definition and is not enumerated
      # as an element, so it is counted here once per pile instance (owner = pile).
      fallback = piles.select { |p| (p.is_a?(Sketchup::ComponentInstance) || pile_qto_infill_children(p).empty?) && pile_qto_concrete(p) > 0.0 }
      volume = fallback.sum { |p| pile_qto_concrete(p) }
      return snapshot if fallback.empty?
      row = snapshot[:rows].find { |r| r[:type] == 'pile_infill_concrete' }
      unless row
        row = {type: 'pile_infill_concrete', name: 'Kazık İçi Beton', count: 0, length_m: 0.0, concrete_m3: 0.0, formwork_m2: 0.0, steel_t: 0.0}
        snapshot[:rows] << row
      end
      row[:count] += fallback.length
      row[:concrete_m3] += volume
      reb = fallback.any? { |p| mst_pile_rebar_active(p) } ? fallback.sum { |p| mst_pile_rebar_t(p) } : volume * rebar_rate('pile') / 1000.0   # v0.38 PR1
      row[:steel_t] += reb
      snapshot[:totals][:concrete_m3] += volume
      snapshot[:totals][:steel_t] += reb
      fallback.each do |p|
        klass = pile_report_concrete_class(p)
        snapshot[:concrete_by_class][klass] = snapshot[:concrete_by_class].fetch(klass, 0.0) + pile_qto_concrete(p)
      end
      snapshot
    end

    def qto_workspace_status(elements, piles)
      incomplete = elements.count do |e|
        missing = %w[element_uid project ano].any? { |k| e.get_attribute(DICT, k, '').to_s.strip.empty? }
        missing ||= e.get_attribute(DICT, 'type_id', e.get_attribute(DICT, 'library_type_id', '')).to_s.strip.empty?
        if e.get_attribute(DICT, 'element_type', '') == 'steel_pipe_pile'
          missing ||= %w[system structure].any? { |k| e.get_attribute(DICT, k, '').to_s.strip.empty? }
          d = e.get_attribute(DICT, 'diameter_mm', 0).to_f
          t = e.get_attribute(DICT, 'thickness_mm', 0).to_f
          length = e.get_attribute(DICT, 'actual_length_m', e.get_attribute(DICT, 'length_m', 0)).to_f
          missing ||= !(d > 0 && t > 0 && d > 2 * t && length > 0)
        end
        missing
      end
      messages = []
      assumed = piles.count { |p| pile_driving_source(p) == 'VARSAYIM' }
      no_kot = piles.count { |p| pile_driving_source(p) != 'KOT' }
      messages << "#{assumed} kazıkta çakım boyu kazık boyundan varsayıldı." if assumed > 0
      messages << "#{no_kot} kazıkta deniz tabanı / uç kotu eksik; girilmiş boyu kontrol edin." if no_kot > 0
      fallback = piles.count { |p| pile_qto_infill_children(p).empty? && pile_qto_concrete(p) > 0 }
      messages << "#{fallback} kazıkta iç beton, geometri yerine kayıtlı parametrelerden hesaplandı." if fallback > 0
      {incomplete_count: incomplete, messages: messages}
    end
  end
end
