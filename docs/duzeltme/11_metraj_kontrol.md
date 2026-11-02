# 11 Bağımsız metraj kontrolü — mst-metraj-kontrol (02.11.2026, kaynak 98222c5, salt okuma)
Yöntem: golden fikstür girdilerinden (tools/golden/fixture.rb) koddan bağımsız elle hesap; ajan komut çalıştırmadı.

Sonuç: golden farkındaki 44 kalemin tamamı beklenen hesapla uyuyor (ÖBF-010 26,251196; BK1 gömülme 0,731896; HB_DECK 37,968105; FORMWORK_CAST 81,178536; REBAR 15,137058 t; toplam beton 95,919301; pano Kaplama 6,0 / DOSP 16,2; çakım 98,2869 değişmedi). Pursantaj ile ilerleme yüzdesi karışması yok. Eleman başına tek donatı sınıfı (BIM varsa BIM, yoksa hacim × kg/m³); iki sınıfın birlikte sayıldığı yol bulunmadı. F1 (Excel tek iç beton satırı) yalnız kodda doğrulandı.

0.51.4'ten gelen, 0.51.5'te değişmemiş tutarsızlıklar (karar/belge gerekli):
- (A) Bordür donatısı (fikstürde 180 kg) Keşif REBAR'da yok (quantity_service.rb:106 bilinçli), QTO3/Excel/hakediş elemanlarında var.
- (B) Ekran/Excel "Toplam Beton" kaplama betonunu (6,0 m³) içermiyor; Keşif'te kaplama ayrı poz (ÖBF-072).
- (C) Keşif/Metraj CSV (export_boq_csv, main.rb:8567-8575) ham attribute okuyor: BK brüt beton, yalnız fiziksel iç beton, donatı yok → Keşif ile tutmaz (fikstürde BK 23,7 ↔ 22,968; iç beton 9,126 ↔ 26,251; Celik_t 0).
- (D) Hakediş REBAR K34 notu farkın nedenine kazık iç beton donatısını (parametreli) yazmıyor.
Riskler (belge gerekli): döşeme BIM donatısı kaplama hasırını içeriyorsa kaplama pursantajı çift sayılır; sehpa düşümü pursantajlı BK'dan da düşüyor (golden kapsamaz); DXF birimi tanımsızken iki farklı varsayılan (m / cm).
Gerekli belgeler: REBAR_DEFAULTS pursantajları (kazık 250, BK 180, döşeme 150, kaplama 20, prekast 120, kronman 100 kg/m³), diş geometrisi paftası, tapa ve PD2 poz eşlemesi.
Golden kapsam önerisi: diş geçişindeki kazık, Component BK, pile_rebar_error/pc_rebar_error taşıyan öğeler, sehpa, rebar_rate_* ayarlı model, bordür donatısı; Excel Ayrıntılı Metraj ve CSV çıktıları.
SketchUp kabulünde ölçülecekler: rapordaki tablo (K50 geçiş, elips açıklık, K59 hata → REBAR +0,5 t, K53 yenileme öncesi = sonrası, F1 tek satır = ÖBF-010 vb.).
