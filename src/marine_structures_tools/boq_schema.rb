# frozen_string_literal: true
# encoding: utf-8
# ADAY10 — Keşif düzeni ayrımı. KURAL: bayrak (boq_schema_v2='1') YOKSA model ESKİ (legacy) = ADAY9 davranışı birebir.
# Yeni (kütüphane) düzen yalnız bayrakla: (a) tamamen boş yeni projede Keşif sayfası ilk açıldığında otomatik (fresh?),
# (b) kullanıcının açık kararıyla ("Kütüphane düzenine geç"). Böylece hiçbir model sessizce düzen değiştirmez.
module MAG
  module MarineStructuresTools
    module BOQSchema
      extend self
      BOQ2_DICT_NAME = 'MAG_MST_BOQ2'
      MAIN_DICT_NAME = 'MAG_MarineStructures'
      FLAG = 'boq_schema_v2'

      def flagged?(model)
        model.get_attribute(BOQ2_DICT_NAME, FLAG, nil).to_s == '1'
      end

      def legacy?(model)
        !flagged?(model)
      end

      # Otomatik geçişe uygun mu: bayraksız, hiç MST elemanı yok, poz listesi/hakediş geçmişi/boq_price_* yok.
      # Okunamayan hakediş arşivi güvenli tarafta "uygun değil" sayılır.
      def fresh?(model, history_count:, has_elements:)
        return false if flagged?(model)
        return false unless model.get_attribute(BOQ2_DICT_NAME, 'items_json', nil).to_s.strip.empty?
        begin
          return false if history_count.call.to_i > 0
          return false if has_elements.call
        rescue StandardError
          return false
        end
        d = model.attribute_dictionary(MAIN_DICT_NAME)
        return false if d && d.keys.any? { |k| k.to_s.start_with?('boq_price_') }
        true
      end

      # Yeni düzene alır (bayrak yazar). ÇAĞIRAN işlemi (start_operation) açmış olmalıdır.
      def adopt!(model)
        model.set_attribute(BOQ2_DICT_NAME, FLAG, '1') unless flagged?(model)
        true
      end
    end
  end
end
