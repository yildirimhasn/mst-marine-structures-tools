# Parti C statik kontrol — K41 tablo sutun sayilari (SketchUp disinda, kaynak yalniz okunur).
# qSummary (Ana Metraj Ozeti) 7: ui.html baslik/colgroup/colspan + main.rb qto_summary icindeki her <tr> dizgisi.
# qQTO3 (Eleman Bazinda Metraj) 8: ui.html baslik/colgroup/colspan + setQTO satir sablonu.
# Detailed QTO (Excel) 10: main.rb export_professional_excel baslik, genislik, grup satiri (8+2) ve "Kazik Ici Beton" yedek satiri.
# Kullanim: ruby tools/test/c_table_columns.rb <src/marine_structures_tools>
require_relative 'a1_helper'
ui = A1.src('ui.html')
main = A1.src('main.rb')

def table_for(html, body_id)
  e = html.index("id=\"#{body_id}\"") or abort("tablo yok: #{body_id}")
  a = html.rindex('<table', e)
  z = html.index('</table>', e)
  html[a...z]
end

{ 'qSummaryBody' => 7, 'qQTO3Body' => 8 }.each do |id, n|
  tb = table_for(ui, id)
  t("#{id}: <th> sayısı", tb.scan(/<th\b/).size, n)
  t("#{id}: <col> sayısı", tb.scan(/<col\b/).size, n)
  t("#{id}: yer tutucu colspan", tb[/colspan="(\d+)"/, 1].to_i, n)
end

qs = A1.grab(main, 'def qto_summary(')
trs = qs.scan(%r{<tr>(.*?)</tr>}m).flatten
obs('qto_summary <tr> dizgisi', trs.size)
bad = trs.each_with_index.reject { |r, _| r.scan(/<td\b/).size == 7 }.map { |r, i| "#{i + 1}:#{r.scan(/<td\b/).size}" }
t('qto_summary: 7 hücreli olmayan <tr>', bad, [])

st = ui[/function setQTO\(d\)\{.*?\n(?=function |\z)/m] or abort('setQTO yok')
row = st[/qb\.innerHTML=.*?\.join\(''\):[^;]*;/m] or abort('qQTO3 satır şablonu yok')
t('qQTO3 setQTO satır şablonu <td> sayısı', row.split("colspan").first.scan(/<td>/).size, 8)
t('qQTO3 boş liste colspan', row[/colspan="(\d+)"/, 1].to_i, 8)

ex = A1.grab(main, 'def export_professional_excel')
dq = ex.match(/\['Detailed QTO',\[(.*?)\],detail,\[(.*?)\]\]/m) or abort('Detailed QTO tanımı yok')
hdr = dq[1].scan(/'[^']*'/).size
wid = dq[2].split(',').size
t('Detailed QTO başlık sütunu', hdr, 10)
t('Detailed QTO sütun genişliği', wid, 10)
grp = ex[/detail<<\[type_names.*?\]\n/m].to_s
t('Detailed QTO grup satırı: 8 değer', grp.scan(/arr\.length|qto3_quantity|type_names\[|k\[1\]|k\[2\]/).size, 8)
t('Detailed QTO grup satırı: +2 (Boru Çeliği / Donatı)', ex.include?("detail.last.concat(k[0]=='steel_pipe_pile' ? [detail.last[7],0.0] : [0.0,detail.last[7]])"), true)
fb = ex[/detail<<\['Kazık İçi Beton',(.*?)\]\n/, 1].to_s
t('Detailed QTO yedek satır (Kazık İçi Beton) değer sayısı', fb.split(',').size + 1, 10)
a1_finish
