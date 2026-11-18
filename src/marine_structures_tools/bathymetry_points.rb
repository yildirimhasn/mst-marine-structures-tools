# frozen_string_literal: true
require 'csv'
module MAG
module MarineStructuresTools
  module BathymetryPoints
    SCALE = {'m'=>1.0,'cm'=>0.01,'mm'=>0.001,'ft'=>0.3048}.freeze

    def self.read(path, unit, origin, depth)
      scale = SCALE.fetch(unit)
      points = []
      separator = nil
      first = true
      File.foreach(path, encoding:'bom|utf-8').with_index(1) do |line, i|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        separator ||= line.include?(';') ? ';' : (line.include?(',') ? ',' : :space)
        fields = separator == :space ? line.split : CSV.parse_line(line, col_sep:separator)
        if first && fields.map{|x|x.to_s.strip.downcase} == %w[x y z]
          first = false
          next
        end
        first = false
        begin
          raise ArgumentError unless fields.length == 3
          point = fields.map do |x|
            value = Float(separator == ';' ? x.to_s.tr(',','.') : x)
            raise ArgumentError unless value.finite?
            value*scale
          end
          point[2] = -point[2] if depth
          point = point.zip(origin).map{|v,o| v-o}
          raise ArgumentError unless point.all?(&:finite?)
        rescue ArgumentError, TypeError
          raise "Batimetri satırı #{i}: üç sonlu X, Y, Z değeri gerekli."
        end
        points << point
        raise 'Bir aktarımda en fazla 5000 nokta kullanılabilir.' if points.size>5000
      end
      RockfillTIN.triangulate(points.map{|point|[point,point]})
    rescue ArgumentError, EncodingError => e
      # 0.52.18 ADAY: ikili/yanlış kodlamalı dosyada (ör. DWG) ham Ruby iletisi yerine Türkçe ileti
      raise 'Batimetri dosyası okunamadı: metin (XYZ/CSV) biçiminde değil. DWG gibi ikili dosyaları DXF veya XYZ olarak dışa aktarın.' if e.message =~ /invalid byte sequence|incompatible character|UTF-8/i
      raise
    end
  end
end
end
