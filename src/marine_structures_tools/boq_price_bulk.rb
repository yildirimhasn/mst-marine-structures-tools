# frozen_string_literal: true
# encoding: utf-8
# ADAY10 — Keşif Kütüphanesi toplu fiyat güncelleme (saf mantık; SketchUp API'si kullanmaz).
# Önizleme → hatasızsa TEK kayıt işlemi; herhangi bir hata varsa HİÇBİRİ yazılmaz. Eşleşme kayıt KİMLİĞİNE (id) göre.
# Boş fiyat hücresi = "dokunma" (silme değil). Ondalık: nokta ve virgül; "1.234,56" Türkçe biçimi kabul.
module MAG
  module MarineStructuresTools
    module BOQPriceBulk
      extend self
      LIMIT = 5000
      BOM = "﻿"

      # rows: kütüphane kayıtları; changes: [{'id'=>..., 'unit_price'=>...}]
      # → {ok: [{id,code,old,new}], errors: [{row,id,message}], unchanged: Integer}
      def preview(rows, changes)
        by_id = {}
        Array(rows).each { |r| by_id[r['id'].to_s] = r }
        ok = []; errors = []; unchanged = 0; seen = {}
        Array(changes).each_with_index do |c, i|
          n = i + 1
          id = c['id'].to_s.strip
          if id.empty? then errors << {row: n, id: id, message: 'Kayıt kimliği boş.'}; next end
          dup = seen[id]; seen[id] = true
          if dup then errors << {row: n, id: id, message: 'Aynı kimlik tekrar ediyor.'}; next end
          rec = by_id[id]
          if rec.nil? then errors << {row: n, id: id, message: 'Kimlik kütüphanede bulunamadı.'}; next end
          raw = c['unit_price']
          if raw.nil? || raw.to_s.strip.empty? then unchanged += 1; next end
          if rec['currency'].to_s != 'USD' then errors << {row: n, id: id, message: 'Kaydın para birimi USD olmalı (fiyat güncellemesi yalnız USD kayıtlara).'}; next end
          pr = parse_price_result(raw)
          price = pr[:value]
          if price.nil? then errors << {row: n, id: id, message: "#{pr[:error]}: #{raw}"}; next end
          old = rec['unit_price'].nil? ? nil : rec['unit_price'].to_f
          if !old.nil? && old == price then unchanged += 1; next end
          ok << {id: id, code: rec['code'], old: old, new: price}
        end
        {ok: ok, errors: errors, unchanged: unchanged}
      end

      # Hatasız ise yeni kayıt dizisini saver'a verir (tek yazım) ve değişen adedi döner; hata varsa ArgumentError (hiçbiri yazılmaz).
      def apply(rows, changes, saver:, today: Time.now.strftime('%Y-%m-%d'))
        pv = preview(rows, changes)
        unless pv[:errors].empty?
          raise ArgumentError, "#{pv[:errors].size} satırda hata var; hiçbir fiyat yazılmadı. İlk hata: satır #{pv[:errors].first[:row]}: #{pv[:errors].first[:message]}"
        end
        return 0 if pv[:ok].empty?
        newp = {}
        pv[:ok].each { |x| newp[x[:id]] = x[:new] }
        saver.call(Array(rows).map { |r| newp.key?(r['id'].to_s) ? r.merge('unit_price' => newp[r['id'].to_s], 'date' => today) : r })   # fiyat güncellendi = fiyat tarihi bugün (çakışmada en yeni sayılır)
        pv[:ok].size
      end

      def parse_price(raw)
        parse_price_result(raw)[:value]
      end

      # Sıkı ayrıştırma (sessiz yanlış okuma yok): rakam + . , dışında karakter reddedilir; iki ayırıcı varsa SON ayırıcı ondalıktır
      # (diğeri 3'lü binlik grubu olmalı); tek ayırıcı + tam 3 hane ve tam kısım 1-3 haneli, 0'sız (1.234 / 12,500) BELİRSİZDİR → reddedilir.
      def parse_price_result(raw)
        s = raw.to_s.strip.delete(' ').delete("\u00A0")
        return {value: nil, error: 'Fiyat boş'} if s.empty?
        return {value: nil, error: 'Geçerli bir sayı değil (yalnız rakam, nokta, virgül)'} unless s.match?(/\A\d[\d.,]*\z/)
        seps = s.scan(/[.,]/)
        v = nil
        if seps.empty?
          v = s.to_f
        elsif s.include?('.') && s.include?(',')
          i = s.rindex(/[.,]/)
          dec = s[i]; grp = dec == '.' ? ',' : '.'
          int = s[0...i]; frac = s[(i + 1)..-1]
          return {value: nil, error: 'Geçerli bir sayı değil (binlik/ondalık ayırıcı tutarsız)'} unless frac.match?(/\A\d+\z/) && int.match?(/\A\d{1,3}(?:#{Regexp.escape(grp)}\d{3})+\z/)
          v = "#{int.delete(grp)}.#{frac}".to_f
        else
          c = seps.first
          if seps.size > 1
            return {value: nil, error: 'Geçerli bir sayı değil (binlik grupları 3 haneli olmalı)'} unless s.match?(/\A\d{1,3}(?:#{Regexp.escape(c)}\d{3})+\z/)
            v = s.delete(c).to_f
          else
            int, frac = s.split(c, -1)
            return {value: nil, error: 'Geçerli bir sayı değil (ondalık kısım boş)'} unless int.match?(/\A\d+\z/) && frac.to_s.match?(/\A\d+\z/)
            if frac.length == 3 && int.length <= 3 && !int.start_with?('0')
              return {value: nil, error: 'Belirsiz sayı biçimi (binlik mi ondalık mı?); 1234,5 veya 1234.5 biçiminde yazın'}
            end
            v = "#{int}.#{frac}".to_f
          end
        end
        return {value: nil, error: 'Fiyat sonlu bir sayı olmalı'} unless v.finite?
        {value: v, error: nil}
      end

      # Metin (Excel yapıştırması / CSV) → [{'id'=>,'unit_price'=>}] ; başlık satırı zorunlu (id ve fiyat sütunları)
      def parse_text(text)
        t = text.to_s.sub(BOM, '').gsub("\r\n", "\n").tr("\r", "\n")
        lines = t.split("\n").reject { |l| l.strip.empty? }
        raise ArgumentError, 'İçe aktarılacak veri boş.' if lines.empty?
        delim = detect_delim(lines.first)
        head = split_line(lines.first, delim).map { |h| fold(h) }
        ic = head.index { |h| %w[id kimlik kayit\ kimligi].include?(h) }
        pc = head.index { |h| ['fiyat', 'unit_price', 'unit price', 'birim fiyat', 'price'].include?(h) }
        raise ArgumentError, 'Başlık satırında "id" sütunu bulunamadı (dışa aktarılan dosyanın başlığını koruyun).' if ic.nil?
        raise ArgumentError, 'Başlık satırında "fiyat" sütunu bulunamadı.' if pc.nil?
        body = lines[1..-1] || []
        raise ArgumentError, "En fazla #{LIMIT} satır içe aktarılabilir." if body.size > LIMIT
        body.map { |l| c = split_line(l, delim); {'id' => c[ic].to_s.strip, 'unit_price' => c[pc].to_s.strip} }
      end

      # rows: kütüphane kayıtları → UTF-8 BOM'lu, ; ayraçlı CSV (Türkçe Excel'de doğrudan açılır; ondalık virgül)
      def export_csv(rows)
        out = [%w[id kayıt\ no ad birim para\ birimi fiyat].join(';')]
        Array(rows).each do |r|
          price = r['unit_price'].nil? ? '' : r['unit_price'].to_s.tr('.', ',')
          out << [r['id'], r['code'], r['name'], r['unit'], r['currency'], price].map { |x| csv_cell(x) }.join(';')
        end
        BOM + out.join("\r\n") + "\r\n"
      end

      def csv_cell(v)
        s = v.to_s
        (s.include?(';') || s.include?('"') || s.include?("\n")) ? '"' + s.gsub('"', '""') + '"' : s
      end

      def detect_delim(line)
        [["\t", line.count("\t")], [';', line.count(';')], [',', line.count(',')]].max_by { |_, n| n }.first
      end

      # Tırnaklı alan destekli basit ayrıştırıcı
      def split_line(line, delim)
        out = []; cur = +''; q = false; i = 0
        while i < line.length
          ch = line[i]
          if q
            if ch == '"' && line[i + 1] == '"' then cur << '"'; i += 1
            elsif ch == '"' then q = false
            else cur << ch end
          elsif ch == '"' then q = true
          elsif ch == delim then out << cur; cur = +''
          else cur << ch end
          i += 1
        end
        out << cur
        out
      end

      def fold(s)
        s.to_s.strip.tr('İIıÇçĞğÖöŞşÜü', 'iiiccggoossuu').downcase
      end
    end
  end
end
