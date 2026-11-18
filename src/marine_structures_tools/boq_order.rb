# frozen_string_literal: true
# encoding: utf-8
# ADAY10 — Keşif sıra numarası. Sıra = etkin poz listesinin (items_json dizi sırası) konumu; ayrı kayıtlı sıra anahtarı YOK.
# Kütüphane kayıt numarası (ÖBF-107 gibi) sıradan BAĞIMSIZDIR. Saf mantık; SketchUp API'si kullanmaz.
module MAG
  module MarineStructuresTools
    module BOQOrder
      extend self

      # Görünen poz numarası: sıra → "ÖBF-01", "ÖBF-02" … (en az 2 hane; 100 ve üstü 3 hane). Kütüphane kayıt no'sundan bağımsızdır.
      def poz_no(seq)
        format('ÖBF-%02d', seq.to_i)
      end

      # Sıralı kaynak anahtarları → {anahtar => 1..n} (yinelenen anahtar ilk konumunu korur, numara kesintisiz)
      def seq_map(order)
        h = {}
        n = 0
        Array(order).each { |k| key = k.to_s; h[key] = (n += 1) unless h.key?(key) }
        h
      end
    end
  end
end
