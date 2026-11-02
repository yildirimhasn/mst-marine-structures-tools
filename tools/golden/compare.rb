# Golden-master karsilastirmasi: eski (taban) CSV ↔ yeni CSV. Her farki 07 surum notundaki bir kaleme eslemeye calisir;
# sayisal farkin beklenen degere (fikstur sabitleri ve RATE bolumu ile hesaplanan) esit olmasi da sinanir (tol 1e-6).
# Eslenemeyen ya da sayisi tutmayan fark = BEKLENMEYEN; cikis kodu 1.
# Kullanim: ruby tools/golden/compare.rb <eski.csv> <yeni.csv> <fark.csv> [kural seti: 0514 (varsayilan) | Gb]
#   0514 = 0.51.4 (872d3a3) ↔ 0.51.5 esleme; Gb = Parti G-b (taban 7e2e9c7) esleme: G4, G5, G6
# Kategoriler: "METRAJ §2.1 <bulgu>" | "GÖSTERİM §2.4 K08" | "BİLGİ §2.2 K33/K39" | "BEKLENMEYEN"
old_f, new_f, out_f, profile = ARGV
profile ||= '0514'
abort 'kullanim: ruby tools/golden/compare.rb <eski.csv> <yeni.csv> <fark.csv>' unless out_f
rd = lambda do |f|
  h = {}
  File.readlines(f, encoding: 'UTF-8').drop(1).each { |l| s, k, v = l.chomp.split(';', 3); h["#{s};#{k}"] = v }
  h
end
o = rd.(old_f)
n = rd.(new_f)
num = ->(v) { Float(v) rescue nil }
rate = ->(k) { num.(n["RATE;#{k}"]) || abort("RATE;#{k} yok") }
abort 'pursantaj oranlari iki surumde farkli' unless %w[pile head_beam].all? { |k| o["RATE;#{k}"] == n["RATE;#{k}"] }

# fikstur sabitleri (tools/golden/fixture.rb)
A = Math::PI / 4 * 1.016**2                   # Ø1016 daire alani
V = Math::PI / 4 * 0.984**2 * 12.0            # P2 ic beton (paylasilan cocuk)
K36_C = -V                                    # P2 "ic beton YOK" artik sayilmaz
K36_R = -V * rate.('pile') / 1000.0           # ve pursantaj donatisi (t)
K50_C = -A * 0.5                              # BK1: P1 son dis bolgesinde (derinlik 0.5) gomulme +0.5 m
K50_R = K50_C * rate.('head_beam') / 1000.0   # BK1 net betonu × pursantaj (t)
R6_F = 2 * A                                  # BK2: alt yuz kalipta degil → 2 daire acikligi dusulmez
TOP = 6.0                                     # D1 kaplama 50 × 0.12 (K08 gosterim)

M21 = 'METRAJ §2.1'.freeze
RULES = [
  [/\ABOQ_(QTY|ROW);(ÖBF-\d+\|)?FORMWORK_CAST/, "#{M21} 08-R6", R6_F],
  [/\ABOQ_(QTY|ROW);(ÖBF-\d+\|)?HB_DECK_CONCRETE/, "#{M21} K50", K50_C],
  [/\ABOQ_(QTY|ROW);(ÖBF-\d+\|)?PILE_INFILL/, "#{M21} K36", K36_C],
  [/\ABOQ_(QTY|ROW);(ÖBF-\d+\|)?REBAR/, "#{M21} K36 + K50 (türev donatı)", K36_R + K50_R],
  [/\AREBAR_BREAKDOWN;pile\z/, "#{M21} K36", K36_R * 1000],
  [/\AREBAR_BREAKDOWN;head_beam\z/, "#{M21} K50 (türev donatı)", K50_R * 1000],
  [/\AQTO3_ROW;pile_infill_concrete\|count/, "#{M21} K36 (adet)", -1.0],
  [/\AQTO3_ROW;pile_infill_concrete\|concrete_m3/, "#{M21} K36", K36_C],
  [/\AQTO3_ROW;pile_infill_concrete\|steel_t/, "#{M21} K36", K36_R],
  [/\AQTO3_ROW;head_beam\|concrete_m3/, "#{M21} K50", K50_C],
  [/\AQTO3_ROW;head_beam\|formwork_m2/, "#{M21} 08-R6", R6_F],
  [/\AQTO3_ROW;head_beam\|steel_t/, "#{M21} K50 (türev donatı)", K50_R],
  [/\AQTO3_TOTAL;steel_t/, "#{M21} K36 + K50", K36_R + K50_R],
  [/\AQTO3_TOTAL;concrete_m3/, "#{M21} K36 + K50", K36_C + K50_C],
  [/\AQTO3_TOTAL;formwork_m2/, "#{M21} 08-R6", R6_F],
  [/\AQTO3_CLASS;C30\/37/, "#{M21} K36 + K50", K36_C + K50_C],
  [/\APILE_GROUP;PILE_INFILL\|C30\/37/, "#{M21} K36", K36_C],
  [/\AELEM;head_beam\|BK1\|concrete_m3/, "#{M21} K50", K50_C],
  [/\AELEM;head_beam\|BK1\|(steel_t|rebar_t)/, "#{M21} K50 (türev donatı)", K50_R],
  [/\AELEM;head_beam\|BK1\|rebar_kg/, "#{M21} K50 (türev donatı)", K50_R * 1000],
  [/\AELEM;head_beam\|BK1\|pile_embed_m3/, "#{M21} K50", -K50_C],
  [/\AELEM;head_beam\|BK2\|formwork_m2/, "#{M21} 08-R6", R6_F],
  [/\AELEM;head_beam\|BK2\|pile_opening_m2/, "#{M21} 08-R6", -R6_F],
  [/\AELEM;steel_pipe_pile\|P2\|(pile_qto_concrete|bim_concrete_m3)/, "#{M21} K36", K36_C],
  [/\AELEM;steel_pipe_pile\|P2\|pile_rebar_t/, "#{M21} K36", K36_R],
  [/\AQTO_SUMMARY;total_concrete/, "#{M21} K36 + K50", K36_C + K50_C],
  [/\AQTO_SUMMARY;total_formwork/, "#{M21} 08-R6", R6_F],
  [/\AQTO_SUMMARY;concrete_breakdown\|BK\z/, "#{M21} K50", K50_C],
  [/\AQTO_SUMMARY;concrete_breakdown\|ÇBK\z/, "#{M21} K36", K36_C],
  [/\AQTO_SUMMARY;concrete_breakdown\|DOSP\z/, 'GÖSTERİM §2.4 K08 (kaplama ayrı satır)', -TOP],
  [/\AQTO_SUMMARY;concrete_breakdown\|DİĞER\z/, 'GÖSTERİM §2.4 K08 (−kaplama dengeleme kalemi kalktı)', :text],
  [/\AQTO_SUMMARY_ROW;Beton\|Kazık İçi Beton/, "#{M21} K36 (pano satırı)", :text],
  [/\AQTO_SUMMARY_ROW;Betonarme\|Başlık Kirişi/, "#{M21} K50 + 08-R6 (pano satırı)", :text],
  [/\AQTO_SUMMARY_ROW;Betonarme\|(Döşeme|Kaplama)/, 'GÖSTERİM §2.4 K08 (kaplama ayrı satır)', :text],
  [/\ABOQ_INFO;INFO:UNMAPPED_CONCRETE/, 'BİLGİ §2.2 K33 (toplam dışı)', :text],
  [/\ABOQ_INFO;INFO:PILE_PLUG/, 'BİLGİ §2.2 K39 (toplam dışı)', :text],
  [/\ABOQ_INFO;\*\z/, 'BİLGİ §2.2 (0.51.4\'te işlev yok)', :text]
].freeze

# Parti G-b (taban 7e2e9c7): fikstur sabitleri — bordurler C1 1.2 + C2 0.6 + C3 0.3 m³; kaplama D1 50×0.12 + D2 (20 − 5×0.3)×0.10
CURB_V = 1.2 + 0.6 + 0.3
GB_TOP = 6.0 + (20.0 - 5.0 * 0.3) * 0.10
RULES_GB = [
  [/\ABOQ_(QTY|ROW);(ÖBF-\d+\|)?REBAR/, "#{M21} G4 (bordür donatısı Keşif'te)", CURB_V * rate.('deck') / 1000.0],
  [/\AREBAR_BREAKDOWN;curb\z/, "#{M21} G4 (Bordür / Tretuvar satırı)", CURB_V * rate.('deck')],
  [/\AREBAR_TRACE;count\z/, "#{M21} G4 (REBAR izlemesine 3 bordür)", 3.0],
  [/\AREBAR_TRACE;sum_t\z/, "#{M21} G4 (REBAR izlemesine bordür donatısı)", CURB_V * rate.('deck') / 1000.0],
  [/\AHAKEDIS;REBAR\|approved\z/, "#{M21} G4 (önceden onaylı bordür C1 donatısı bu dönem artışı)", 1.2 * rate.('deck') / 1000.0],
  [/\AHAKEDIS;REBAR\|warning\z/, "#{M21} G4 (K34 notu: bordür eleman ilerlemesiyle ödenir)", :text],
  [/\AQTO_SUMMARY;total_concrete\z/, "#{M21} G6 (Toplam Beton + kaplama)", GB_TOP],
  [/\AQTO_SUMMARY;concrete_breakdown\|KAPLAMA\z/, "#{M21} G6 (KAPLAMA kırılımı)", GB_TOP],
  [/\AQTO_SUMMARY_ROW;Betonarme\|Kaplama/, "#{M21} G6 (kaplama satırı açıklaması)", :text],
  [/\AEXCEL_SUMMARY;Toplam Beton\z/, "#{M21} G6 (Excel Özet Toplam Beton + kaplama)", GB_TOP],
  [/\AEXCEL_SUMMARY;Beton Kaplama \(C30\/37\)\z/, "#{M21} G6 (Beton Kaplama satırı, D1)", 6.0],
  [/\AEXCEL_SUMMARY;Beton Kaplama \(C35\/45\)\z/, "#{M21} G6 (Beton Kaplama satırı, D2 sınıfsız → C35/45)", GB_TOP - 6.0],
  [/\ACSV(_TOTAL)?;/, "#{M21} G5 (CSV = Keşif; g5_csv_boq ile sayısal kabul)", :text]
].freeze
rules = profile == 'Gb' ? RULES_GB : RULES

out = []
bad = 0
(o.keys | n.keys).sort.each do |k|
  next if o[k] == n[k]
  ov = o[k] || '(yok)'
  nv = n[k] || '(yok)'
  rule = rules.find { |re, _, _| k =~ re }
  cat = rule ? rule[1] : 'BEKLENMEYEN'
  check = ''
  if rule && rule[2].is_a?(Numeric)
    oz = num.(ov) || (profile == 'Gb' && o[k].nil? ? 0.0 : nil)   # Gb: tabanda olmayan yeni anahtar 0'dan sayılır
    d = num.(nv) && oz ? num.(nv) - oz : nil
    if d && (d - rule[2]).abs <= 1e-6
      check = format('fark %+.6f = beklenen %+.6f', d, rule[2])
    else
      check = format('fark %s ≠ beklenen %+.6f', d ? format('%+.6f', d) : '?', rule[2])
      cat = "BEKLENMEYEN (sayı tutmuyor; aday #{rule[1]})"
    end
  end
  bad += 1 if cat.start_with?('BEKLENMEYEN')
  out << [k.split(';', 2), ov, nv, cat, check].flatten
end
File.open(out_f, 'w:UTF-8') do |f|
  f.puts 'bolum;anahtar;eski_0514;yeni_0515;esleme;kontrol'
  out.each { |r| f.puts r.join(';') }
end
same = (o.keys & n.keys).count { |k| o[k] == n[k] }
puts "anahtar eski=#{o.size} yeni=#{n.size} aynı=#{same} farklı=#{out.size} beklenmeyen=#{bad}"
out.group_by { |r| r[4] }.each { |c, rs| puts "  #{rs.size}× #{c}" }
exit(bad.zero? ? 0 : 1)
