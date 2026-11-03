# 30 Kod incelemesi — ee18c79 tapa + prekast sınıf pozu (mst-kod-inceleme, 04.11.2026; salt okuma, test çalıştırmadı)
İncelenmeyen (ajan beyanı): Excel çıktı kodu, revizyon arşivi satır anahtarları, v4 testi, golden CSV. Sorunsuz bulunan: yükleme sırası (boq2_class_of çalışma anında), frozen_string_literal, Undo (yeni kod modele yazmıyor; save_boq_mapping işlem yapısı aynı), Model Kontrolü central listesi, progress_entity_quantity.

| No | Önem | Bulgu | Durum |
|---|---|---|---|
| 1 | yüksek | Ad eşleşmeli satırlar `automatic_mapping:true` → boq_mapping.html "Uygula" kilitli; "ÖBF Eşleştirme'den seçin" denip seçilemiyordu | **düzeltildi 2cc5c29**: bayrak `auto_library`; kilit yalnız foraj (`automatic_mapping`); v4 R1 + P6 |
| 2 | orta | PRECAST_C35_45 izlemesi daraltıldı: eski sürümde C30/37 prekasta PRECAST_C35_45 altında girilmiş ilerleme hiçbir satıra bağlanmıyordu | **düzeltildi 2cc5c29**: `prog2_raw_rec` — PRECAST_CONCRETE kaydı yoksa eski PRECAST_C35_45 kaydı okunur; eski kayıt silinmez; temizlemede boş PRECAST_CONCRETE kaydı (v4 R3). **Açık:** hakediş geçmişi olan modelde PRECAST_C35_45 satırının önceki dönemde ödenen miktarı (eskiden C30/37 dahil) modelde azalabilir → "önceki hakedişte ödenen miktar azaldı" uyarısı; aynı miktar yeni sınıf satırında görünür. Kullanıcı bilgisine (07 §2.9) |
| 3 | orta | Yeni eşleştirme anahtarları (`PILE_PLUG`, `PRECAST_CONCRETE#…`) eski sürümde `boq_project_mapping` doğrulamasından geçmez → model eski sürümde açılırsa Keşif/hakediş/eşleştirme ekranı hata verir (çıkarım; eski kod okunmadı) | uyumluluk notu 07 §2.9 / §3 |
| 4 | orta | Sınıfı değişen prekastın eski eşleştirmesi listeden çıkıyor, sıfırlanamıyor, poz yeniden bağlanamıyordu | **düzeltildi 2cc5c29**: kayıtlı `PRECAST_CONCRETE#` anahtarları listelenir ve sıfırlanır (v4 R4) |
| 5 | düşük | Başka kaynağa elle bağlı poz ad eşleşmesiyle ikinci satıra da gidiyordu | **düzeltildi 2cc5c29** (v4 R5) |
| 6 | düşük | save_boq_mapping / send_boq_mapping boq_quantities'i birden fazla kez hesaplıyor (performans) | açık; ölçülmedi |
| 7 | düşük | ui.html:2003 mapping_reason iki kez yazılıyor (foraj satırında da var); yeni satırlar proje poz listesinden pasif yapılamıyor | açık; davranış sorusu kullanıcıya |
