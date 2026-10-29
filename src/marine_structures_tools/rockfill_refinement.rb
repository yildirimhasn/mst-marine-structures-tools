# frozen_string_literal: true
module MAG
module MarineStructuresTools
module RockfillGeometry
 def refinement(input)
  step=number(input.fetch('step'));raise 'Kesit aralığı pozitif olmalı.' unless step>0
  coarse=calculate(input)
  fine=calculate(input.merge('step'=>step/2.0))
  rows=(coarse['totals'].keys+fine['totals'].keys).uniq.sort.map do |code|
   refinement_row(code,coarse['totals'][code]||0,fine['totals'][code]||0)
  end
  rows<<refinement_row('TOPLAM TAŞ',coarse['total'],fine['total'])
  rows<<refinement_row('KAZI — AYRI',coarse['excavation_m3']||0,fine['excavation_m3']||0)
  {'coarse_step'=>step,'fine_step'=>step/2.0,'coarse_sections'=>coarse['sections'].size,'fine_sections'=>fine['sections'].size,'rows'=>rows,'head_included'=>!!coarse['head'],'assumptions'=>coarse['assumptions'],'note'=>'Anlık karşılaştırma. Fark, kesin hata sınırı değildir; iki ağın da kaçırdığı ara taban değişimleri olabilir. Baş açısal aralığı sabit tutulur. Aktif hesap ve BOQ değiştirilmedi.'}
 end
 def refinement_row(code,coarse,fine)
  delta=fine-coarse
  {'code'=>code,'coarse_m3'=>coarse,'fine_m3'=>fine,'difference_m3'=>delta,'difference_percent'=>fine.abs>1e-9 ? delta*100.0/fine.abs : nil}
 end
end
end
end
