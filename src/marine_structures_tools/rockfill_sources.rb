# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  module RockfillSources
   class SectionAreas
    def quantities(api,selection)
     api.rockfill_qto_alt1_data.merge(source_mode:'alt1',source_label:'Dolgu / Taş — Alternatif-01 (kesit alanları)')
    end
   end
   class Reference
    def quantities(api,selection)
     data=api.rf02_quantity_data
     raise 'Aktif Alternatif-02 referansı değişmiş; keşif kaynağını yeniden etkinleştirin.' unless selection['fingerprint']==data[:reference_result]['fingerprint']
     data.merge(source_mode:'alt2')
    end
   end
   class LiveGeometry
    def quantities(api,selection);api.rf_live_qto.merge(source_mode:'geometry');end
   end
   class SpecialSolids
    def quantities(api,selection);api.rf_special_qto.merge(source_mode:'special');end
   end
   PROVIDERS={'alt1'=>SectionAreas.new,'alt2'=>Reference.new,'geometry'=>LiveGeometry.new,'special'=>SpecialSolids.new}.freeze
   def self.provider(mode)
    PROVIDERS.fetch(mode){raise 'Geçersiz dolgu miktar kaynağı.'}
   end
  end
 end
end
