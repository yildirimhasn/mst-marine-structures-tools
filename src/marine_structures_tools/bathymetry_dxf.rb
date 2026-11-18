# frozen_string_literal: true
module MAG
module MarineStructuresTools
  module BathymetryDXF
    def self.read(path, scale, origin, depth)
      faces = []
      contours = []
      section = nil
      record = nil
      finish = lambda do
        next unless section == 'ENTITIES' && record
        kind, fields = record
        count = kind == '3DFACE' ? 4 : 2
        points = count.times.map do |i|
          point = [10,20,30].each_with_index.map do |code, axis|
            raw = fields.fetch(code+i, axis == 2 && kind == 'LINE' ? '0' : nil)
            value = Float(raw)*scale
            value = -value if axis == 2 && depth
            value-origin[axis]
          end
          raise 'DXF koordinatı sonlu olmalı.' unless point.all?(&:finite?)
          point
        end
        if kind == 'LINE'
          contours << points
        else
          faces << points.first(3)
          faces << [points[0],points[2],points[3]] if points[2] != points[3]
        end
      end
      awaiting_section = false
      unsupported = []
      File.foreach(path, encoding:'bom|utf-8').each_slice(2) do |key,value|
        raise 'Eksik DXF kod/değer çifti.' unless value
        code = Integer(key.strip, 10)
        value = value.strip
        if code == 0
          finish.call
          record = %w[LINE 3DFACE].include?(value) ? [value,{}] : nil
          if section == 'ENTITIES' && %w[INSERT POLYLINE LWPOLYLINE SPLINE ARC].include?(value)
            unsupported << value unless unsupported.include?(value)
          end
          section = nil if value == 'ENDSEC'
          awaiting_section = value == 'SECTION'
        elsif awaiting_section && code == 2
          section = value
          awaiting_section = false
        elsif record && ((10..13).cover?(code) || (20..23).cover?(code) || (30..33).cover?(code))
          record.last[code] = value
        end
      end
      finish.call
      raise "DXF eğrilerini LINE veya 3DFACE olarak dışa aktarın: #{unsupported.join(', ')}." unless unsupported.empty?
      raise 'DXF tabanı için LINE veya 3DFACE bulunamadı.' if faces.empty? && contours.empty?
      raise 'Bir aktarımda en fazla 100000 yüzey üçgeni kullanılabilir.' if faces.size>100000
      faces.empty? ? RockfillTIN.triangulate(contours) : faces
    rescue ArgumentError, TypeError, EncodingError => e
      raise "ASCII DXF koordinatları okunamadı: #{e.message}"
    end
  end
end
end
