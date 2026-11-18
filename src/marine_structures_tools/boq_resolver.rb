# frozen_string_literal: true
# encoding: utf-8
# ADAY10 — Keşif poz çözümleyici (saf mantık; SketchUp API'si kullanmaz).
# Kaynak anahtarı (ör. MOBILIZATION) → kütüphane kaydı ve fiyatı. Koda GÖRE eşleştirme yapılmaz
# (ÖBF numaraları katalog ile şablonda farklı işleri gösterir); ad + birim yalnız tek aday varsa.
module MAG
  module MarineStructuresTools
    module BOQResolver
      extend self

      # Aday: aynı kaynak + aynı birim + USD. Fiyatı olan adaylar arasında en yeni tarihli seçilir
      # (tarih yoksa yıl; eşitlikte sondaki kayıt). Fiyatı seçilenden farklı adaylar :conflict olur.
      def pick(records, source:, unit:)
        cands = Array(records).select { |r| r['source'].to_s == source.to_s && r['unit'].to_s == unit.to_s && r['currency'].to_s == 'USD' }
        if cands.empty?
          # Aday yok: nedenini söyle (aynı kaynakta kayıt var ama birim/para birimi uymuyor mu?)
          same = Array(records).select { |r| r['source'].to_s == source.to_s }
          st = if same.any? { |r| r['unit'].to_s == unit.to_s && r['currency'].to_s != 'USD' } then 'USD FİYAT GEREKLİ'
               elsif same.any? { |r| r['unit'].to_s != unit.to_s } then 'BİRİM UYUŞMUYOR'
               else 'KAYIT YOK'
               end
          return {record: nil, price: nil, conflict: [], status: st}
        end
        priced = cands.reject { |r| r['unit_price'].nil? }
        return {record: cands.last, price: nil, conflict: [], status: 'FİYAT YOK'} if priced.empty?
        chosen = priced.first
        priced.each { |r| chosen = r if (rank(r) <=> rank(chosen)) >= 0 }   # eşitlikte sondaki kayıt (Ruby 2.5 uyumlu)
        conflict = priced.reject { |r| r.equal?(chosen) || r['unit_price'].to_f == chosen['unit_price'].to_f }
        {record: chosen, price: chosen['unit_price'].to_f, conflict: conflict, status: conflict.empty? ? 'TAMAM' : 'ÇAKIŞAN FİYAT'}
      end

      # Normalleştirilmiş ad + birim ile TEK aday varsa döner, aksi halde nil.
      def by_name_unit(records, name:, unit:)
        key = norm(name)
        found = Array(records).select { |r| r['unit'].to_s == unit.to_s && norm(r['name']) == key }
        found.size == 1 ? found.first : nil
      end

      # ADAY13: çakışan fiyat notu için etiket — "KOD (40,25 USD/m²)"; fiyatsız kayıtta yalnız kod.
      def conflict_labels(conflict)
        Array(conflict).map do |r|
          code = r['code'].to_s
          r['unit_price'].nil? ? code : "#{code} (#{format('%.2f', r['unit_price'].to_f).tr('.', ',')}#{r['currency'].to_s.empty? ? '' : ' ' + r['currency'].to_s}/#{r['unit']})"
        end
      end

      # Çözüm havuzu: kullanıcı kütüphanesi + katalog (kullanıcı kaydı aynı id / catalog_key'li katalog kaydını gölgeler).
      def pool(library, seeds)
        lib = Array(library)
        ids = {}
        keys = {}
        lib.each { |r| ids[r['id']] = true; keys[r['catalog_key']] = true unless r['catalog_key'].to_s.empty? }
        lib + Array(seeds).reject { |s| ids[s['id']] || (!s['catalog_key'].to_s.empty? && keys[s['catalog_key']]) }
      end

      def norm(s)
        s.to_s.tr('İIıÇçĞğÖöŞşÜü', 'iiiccggoossuu').downcase.gsub(/[^a-z0-9]+/, ' ').strip
      end

      # [tarih metni, yıl] — ISO tarih metni sözlük sırasıyla karşılaştırılır; boş tarih en eski sayılır.
      def rank(r)
        [r['date'].to_s, r['year'].to_i]
      end
    end
  end
end
