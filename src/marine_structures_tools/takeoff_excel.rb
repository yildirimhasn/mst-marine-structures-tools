# frozen_string_literal: true
# v0.38 UI8 — Detaylı Metraj Raporu → Excel (.xlsx).
# Rapor ekranındaki tabloların AYNISI: her disiplin bir sayfa, sayılar gerçek sayı (birim hücre
# biçiminde: 12,345 m³), ara toplam / toplam satırları vurgulu, ilk sayfada bütün toplamların özeti.
require 'json'
module MAG
module MarineStructuresTools

MST_XL_SHEETS=[['Kazık','pile'],['Başlık Kirişi','beam'],['Kazık İçi Beton','infill'],['Prekast','precast'],
 ['Döşeme','deck'],['Kronman','crown'],['Dolgu - Taş','rockfill'],['Fore Kazık','bored'],['Jet Grout','jet_grout'],['Aksesuarlar','accessories']].freeze

def mst_xl_text(h)
 t=h.to_s.gsub(/<br\s*\/?>/i,' ').gsub(/<script.*?<\/script>/m,'').gsub(/<[^>]+>/,'')
 t=t.gsub('&nbsp;',' ').gsub('&lt;','<').gsub('&gt;','>').gsub('&quot;','"').gsub('&#39;',"'").gsub('&apos;',"'").gsub('&amp;','&')
 t.gsub(/[[:space:]]+/,' ').strip
end

# HTML rapor → bloklar: [:h2,metin] [:h3,metin] [:note,metin] [:table,satırlar]
def mst_xl_blocks(html)
 out=[]
 html.to_s.scan(/<(h1|h2|h3)[^>]*>(.*?)<\/\1>|<div class='note'>(.*?)<\/div>|<table[^>]*>(.*?)<\/table>/m) do |tag,head,note,table|
  if head then out << [(tag=='h3' ? :h3 : :h2),mst_xl_text(head)]
  elsif note then t=mst_xl_text(note);out << [:note,t] unless t.empty?
  elsif table
   rows=[]
   table.scan(/<tr([^>]*)>(.*?)<\/tr>/m) do |attrs,body|
    next if attrs=~/display\s*:\s*none/ || attrs=~/id=['"][^'"]*Filtered/
    cls=attrs[/class=['"]([^'"]*)['"]/,1].to_s
    cells=[]
    body.scan(/<t([hd])([^>]*)>(.*?)<\/t[hd]>/m) do |k,ca,inner|
     span=(ca[/colspan=['"]?(\d+)/,1] || 1).to_i
     cells << {t:mst_xl_text(inner),th:(k=='h'),span:span}
    end
    next if cells.empty?
    rows << {cls:cls,cells:cells}
   end
   out << [:table,rows] unless rows.empty?
  end
 end
 out
end

# "12.345 m³ (BIM)" → [12.345, '#,##0.000" m³"', 'BIM']
def mst_xl_value(txt)
 t=txt.to_s.strip;note=nil
 if (m=t.match(/\A(.*?\d.*?)\s*\(([^()]*)\)\z/)) && m[1]=~/\A[+-]?\d/
  t=m[1].strip;note=m[2]
 end
 m=t.match(/\A([+-]?\d+(?:\.\d+)?)\s*(m³|m²|m|t|kg|kg\/m³|mm|adet|ad|ton|USD)?\z/)
 return [txt.to_s,nil,nil] unless m
 return [txt.to_s,nil,nil] if m[1]=~/\A0\d/          # 01, 02 … kimlik gibi
 dec=(m[1][/\.(\d+)/,1] || '').length
 fmt=dec.zero? ? '#,##0' : '#,##0.'+('0'*dec)
 fmt+="\" #{m[2]}\"" if m[2]
 [m[1].include?('.') ? m[1].to_f : m[1].to_i,fmt,note]
end

class MSTXLStyles
 attr_reader :fmts,:xfs
 FONTS=['<font><sz val="10"/><name val="Calibri"/></font>','<font><b/><sz val="10"/><name val="Calibri"/></font>',
  '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>','<font><b/><sz val="14"/><color rgb="FF073F73"/><name val="Calibri"/></font>',
  '<font><b/><sz val="11"/><color rgb="FF0B4F7A"/><name val="Calibri"/></font>','<font><i/><sz val="9"/><color rgb="FF5A7083"/><name val="Calibri"/></font>'].freeze
 FILLS=['<fill><patternFill patternType="none"/></fill>','<fill><patternFill patternType="gray125"/></fill>',
  '<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill>',
  '<fill><patternFill patternType="solid"><fgColor rgb="FFE8F1F8"/><bgColor indexed="64"/></patternFill></fill>',
  '<fill><patternFill patternType="solid"><fgColor rgb="FFCFE2F0"/><bgColor indexed="64"/></patternFill></fill>'].freeze
 BORDERS=['<border><left/><right/><top/><bottom/><diagonal/></border>',
  '<border><left style="thin"><color rgb="FFC9D7E2"/></left><right style="thin"><color rgb="FFC9D7E2"/></right><top style="thin"><color rgb="FFC9D7E2"/></top><bottom style="thin"><color rgb="FFC9D7E2"/></bottom><diagonal/></border>'].freeze
 def initialize;@fmts={};@xfs=[[0,0,0,0,false]];@ix={[0,0,0,0,false]=>0};end
 # role: :cell :header :sub :total :title :h3 :note
 def id(role,fmt=nil,num=false)
  nf=0
  if fmt
   @fmts[fmt]||=164+@fmts.length;nf=@fmts[fmt]
  end
  font,fill,border={cell:[0,0,1],header:[2,2,1],sub:[1,3,1],total:[1,4,1],title:[3,0,0],h3:[4,0,0],note:[5,0,0]}[role]
  key=[nf,font,fill,border,(role==:header)]
  @ix[key]||=(@xfs << key;@xfs.length-1)
 end
 def xml
  nf=@fmts.map{|f,i|"<numFmt numFmtId=\"#{i}\" formatCode=\"#{xml_esc(f)}\"/>"}.join
  xf=@xfs.map{|n,f,fi,b,wrap|"<xf numFmtId=\"#{n}\" fontId=\"#{f}\" fillId=\"#{fi}\" borderId=\"#{b}\" xfId=\"0\"#{n>0 ? ' applyNumberFormat="1"' : ''}#{f>0 ? ' applyFont="1"' : ''}#{fi>0 ? ' applyFill="1"' : ''}#{b>0 ? ' applyBorder="1"' : ''}#{wrap ? ' applyAlignment="1"><alignment wrapText="1" vertical="center"/></xf>' : '/>'}"}.join
  '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'+
  (@fmts.empty? ? '' : "<numFmts count=\"#{@fmts.length}\">#{nf}</numFmts>")+
  "<fonts count=\"#{FONTS.length}\">#{FONTS.join}</fonts><fills count=\"#{FILLS.length}\">#{FILLS.join}</fills><borders count=\"#{BORDERS.length}\">#{BORDERS.join}</borders>"+
  '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'+
  "<cellXfs count=\"#{@xfs.length}\">#{xf}</cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"
 end
 def xml_esc(s);s.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;');end
end

# bloklar → sayfa satırları [[{v:,s:},...],...] ; toplam satırları özet için ayrıca döner
def mst_xl_sheet_rows(title,blocks,st)
 rows=[[{v:title,s:st.id(:title)}],[]];totals=[];head=nil;sub=nil
 blocks.each do |kind,data|
  case kind
  when :h2 then rows << [{v:data,s:st.id(:title)}];head=data
  when :h3 then rows << [{v:data,s:st.id(:h3)}];sub=data
  when :note then rows << [{v:data,s:st.id(:note)}]
  when :table
   width=data.map{|r|r[:cells].sum{|c|c[:span]}}.max
   conv=data.map do |r|
    role=r[:cells].all?{|c|c[:th]} ? :header : (r[:cls]=~/\btotal\b/ ? :total : (r[:cls]=~/subtotal/ ? :sub : :cell))
    notes=[];cells=[]
    r[:cells].each do |c|
     if role==:header
      cells << {v:c[:t],s:st.id(:header)}
     else
      v,fmt,nt=mst_xl_value(c[:t]);notes << nt if nt
      cells << {v:v,s:st.id(role,fmt)}
     end
     (c[:span]-1).times{cells << {v:'',s:st.id(role)}}
    end
    cells << {v:'',s:st.id(role)} while cells.length<width
    {role:role,cells:cells,notes:notes}
   end
   has_notes=conv.any?{|r|!r[:notes].empty?}
   conv.each{|r|r[:cells] << {v:(r[:role]==:header ? 'Kaynak / Not' : r[:notes].join(' · ')),s:st.id(r[:role])} if has_notes}
   hdr=conv.select{|r|r[:role]==:header}.last
   conv.each{|r|rows << r[:cells]}
   rows << []
   conv.select{|r|r[:role]==:total}.each{|r|totals << {title:[title,head,sub].compact.uniq.join(' › '),header:hdr && hdr[:cells],row:r[:cells]}}
  end
 end
 [rows,totals]
end

def mst_xl_col(n);s='';while n>0;n,r=(n-1).divmod(26);s=(65+r).chr+s;end;s;end

def mst_xl_sheet_xml(rows)
 widths=Hash.new(0)
 rows.each{|r|next if r.length<2;r.each_with_index{|c,i|l=(c[:v].is_a?(Numeric) ? format('%.3f',c[:v]).length+5 : c[:v].to_s.length);widths[i]=[widths[i],l].max}}
 ncol=[rows.map(&:length).max.to_i,1].max
 cols=(0...ncol).map{|i|w=[[widths[i]+2,9].max,(i.zero? ? 48 : 62)].min;"<col min=\"#{i+1}\" max=\"#{i+1}\" width=\"#{w}\" customWidth=\"1\"/>"}.join
 body=rows.each_with_index.map do |r,ri|
  cells=r.each_with_index.map do |c,ci|
   ref="#{mst_xl_col(ci+1)}#{ri+1}"
   if c[:f] then "<c r=\"#{ref}\" s=\"#{c[:s]}\"><f>#{xml_escape(c[:f])}</f>#{c[:v].is_a?(Numeric) ? "<v>#{c[:v]}</v>" : ''}</c>"   # v0.47: formül
   elsif c[:v].is_a?(Numeric) then "<c r=\"#{ref}\" s=\"#{c[:s]}\"><v>#{c[:v]}</v></c>"
   elsif c[:v].to_s.empty? then "<c r=\"#{ref}\" s=\"#{c[:s]}\"/>"
   else "<c r=\"#{ref}\" s=\"#{c[:s]}\" t=\"inlineStr\"><is><t xml:space=\"preserve\">#{xml_escape(c[:v])}</t></is></c>"
   end
  end.join
  "<row r=\"#{ri+1}\">#{cells}</row>"
 end.join
 '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'+
 "<sheetViews><sheetView workbookViewId=\"0\" showGridLines=\"0\"/></sheetViews><cols>#{cols}</cols><sheetData>#{body}</sheetData>"+
 '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/><pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>'
end

def mst_xl_safe_name(s,used)
 n=s.to_s.gsub(/[\[\]\*\?\/\\:]/,'-')[0,31];n='Sayfa' if n.empty?
 b=n;k=2;while used.include?(n);n="#{b[0,28]} #{k}";k+=1;end;used << n;n
end

# Workbook dosyası (kaydetme penceresi yok — test ve kayıt yolu verildiğinde)
def mst_takeoff_xlsx_write(path)
 st=MSTXLStyles.new;sheets=[];all_totals=[];used=[]
 model=Sketchup.active_model
 MST_XL_SHEETS.each do |name,mode|
  r=takeoff(mode,:sections)
  next unless r.is_a?(Array)
  blocks=mst_xl_blocks(r[1])
  next unless blocks.any?{|k,_|k==:table}
  rows,totals=mst_xl_sheet_rows(r[0].to_s.empty? ? name : r[0],blocks,st)
  sheets << [mst_xl_safe_name(name,used),rows];all_totals.concat(totals)
 end
 raise 'Modelde metraja girecek eleman yok.' if sheets.empty?
 proj=model.get_attribute(DICT,'project_name','').to_s
 summary=[[{v:'Detaylı Metraj Raporu — Özet',s:st.id(:title)}],[],
  [{v:'Proje',s:st.id(:h3)},{v:(proj.empty? ? '—' : proj),s:st.id(:cell)}],
  [{v:'Model',s:st.id(:h3)},{v:(model.path.to_s.empty? ? '(kaydedilmemiş)' : File.basename(model.path.to_s)),s:st.id(:cell)}],
  [{v:'Tarih',s:st.id(:h3)},{v:Time.now.strftime('%d.%m.%Y %H:%M'),s:st.id(:cell)}],
  [{v:'Sürüm',s:st.id(:h3)},{v:(defined?(MST_BUILD) ? MST_BUILD : VERSION).to_s,s:st.id(:cell)}],
  [{v:'Donatı',s:st.id(:h3)},{v:'BIM çizilen elemanda modellenen tonaj, diğerlerinde beton × pursantaj (Kaynak / Not sütunu)',s:st.id(:note)}],[],
  [{v:'Bölüm toplamları (ayrıntı ilgili sayfada)',s:st.id(:title)}],[]]
 all_totals.each do |t|
  summary << [{v:t[:title],s:st.id(:h3)}]
  summary << t[:header] if t[:header]
  summary << t[:row] << []
 end
 sheets.unshift([mst_xl_safe_name('Özet',used),summary])
 ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+
  sheets.each_index.map{|i|"<Override PartName=\"/xl/worksheets/sheet#{i+1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"}.join+'</Types>'
 rels='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
 wb='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+
  sheets.each_with_index.map{|(n,_),i|"<sheet name=\"#{xml_escape(n)}\" sheetId=\"#{i+1}\" r:id=\"rId#{i+1}\"/>"}.join+'</sheets></workbook>'
 wbr='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+
  sheets.each_index.map{|i|"<Relationship Id=\"rId#{i+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet#{i+1}.xml\"/>"}.join+
  "<Relationship Id=\"rId#{sheets.length+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
 entries={'[Content_Types].xml'=>ct,'_rels/.rels'=>rels,'xl/workbook.xml'=>wb,'xl/_rels/workbook.xml.rels'=>wbr}
 sheets.each_with_index{|(_,rows),i|entries["xl/worksheets/sheet#{i+1}.xml"]=mst_xl_sheet_xml(rows)}
 entries['xl/styles.xml']=st.xml
 write_simple_zip(path,entries)
 sheets.map(&:first)
end

# Kullanıcı komutu: kaydet penceresi → .xlsx → açılsın mı?
def mst_takeoff_excel
 model=Sketchup.active_model
 proj=model.get_attribute(DICT,'project_name','').to_s.strip
 base="#{proj.empty? ? 'MST' : proj.gsub(/[^\p{Alnum}\-_ ]/,'').strip.tr(' ','_')}_Detayli_Metraj_#{Time.now.strftime('%Y%m%d')}.xlsx"
 path=UI.savepanel('Detaylı Metraj Raporu — Excel',(File.dirname(model.path) rescue ''),base)
 return unless path
 path+='.xlsx' unless path.downcase.end_with?('.xlsx')
 names=mst_takeoff_xlsx_write(path)
 if UI.messagebox("Detaylı metraj Excel'e aktarıldı (#{names.length} sayfa):\n#{names.join(' · ')}\n\n#{path}\n\nDosya açılsın mı?",MB_YESNO)==IDYES
  UI.openURL(mst_file_url(path))   # FIX-10: URL kodlu yol
 end
rescue => e
 UI.messagebox("Excel'e aktarılamadı:\n#{e.message}")
end
end
end
