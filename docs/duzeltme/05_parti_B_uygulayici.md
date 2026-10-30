# 05 Parti B — mst-uygulayici (commit 38a7946)
Ana oturum doğrulaması: A1 (4), A2 (9), B (4) testlerinin hepsi "N geçti, 0 kaldı"; ruby -c 0 hata; Ruby 2.5 dilbilgisi files=66 failures=0.
B testleri (yeni / 0.51.4): b_undo 23/0 – 2/21; b_k07_k53_topping 17/0 – 4/13; b_audit_k22_k23_k10_k54 15/0 – 1/11; b_misc 27/0 – 4/16.

| Bulgu | Değişiklik | Durum |
|---|---|---|
| K07 | mst_collect_toppings, mst_topping_parent_deck; dependency_graph kaplama döşeme çocuğu (parent_uid sahip tercihi, yoksa tek eşleşmeli parent_deck_id); mst_bk_dependents yalnız öteleme; mükerrer kaplama kontrolü | düzeltildi ve doğrulandı (mantık); SketchUp testi bekliyor |
| K53 | mst_deck_regenerate! güncel topping_* korunur; parent_deck_revision_no + uyarı (örnek 0.51.4: 0 → 50 m²/6,0 m³) | düzeltildi, SketchUp testi bekliyor |
| K52 | Model Kontrolü uyarısı | ara çözüm (kullanıcı kararı) |
| K22 aşama 1 | mst_bk_span_frame_error (90° katı değilse ve kutu fazlası >5 mm); 4 çağrı noktası + mevcut prekast uyarısı; döndürülmemiş yapıda 0.51.4 yolu aynı | düzeltildi (aşama 2 açık kaldı) |
| K23 | mst_tr_scale_info + tam zincir; ölçek/aynalama uyarısı | ara çözüm (uyarı; metraj değişmez) |
| K10 | link_support_state_json; BK revizyon/kot/konum değişince veya BK yoksa uyarı | ara çözüm (yeniden kurma kuralı belgesi yok) |
| K51 | bk_formwork_face_keys konumlu anahtar; önce konumlu sonra eski | düzeltildi, SketchUp testi bekliyor |
| K11 | ikinci commit kaldırıldı (2 araç) | düzeltildi, SketchUp testi bekliyor |
| K12 | transparent işlemde commit+ileti (mst_v50_piles, mst_deck_after_edit) | düzeltildi, SketchUp testi bekliyor |
| K13 | rescue'da abort (3 yer) | düzeltildi ve doğrulandı (mantık) |
| K15 (U8) | toplu prekast tek işlem; yarıda durursa tümü geri alınır | düzeltildi, SketchUp testi bekliyor |
| K14 | mst_rf_write! (değişmeyeni yazmaz, işlem içinde); yükleme yalnız alternatif değişince yazar | düzeltildi; skp: yolu C partisine bağlı |
| K62 | Malzeme Ata / Canlı QTO tek işlem; mst_pc_last_* ve çakışma görünürlüğü işlem içinde | düzeltildi, SketchUp testi bekliyor |
| K16 kalan | hata yalnız tüm kayıtlar geçerliyse silinir | düzeltildi ve doğrulandı (mantık) |
| K17 | mst_cv_specs_bad?: bozukta EKLE reddi, yeniden çizim menfezi silmez, culvert_error | düzeltildi ve doğrulandı (mantık) |
| K18 | formwork_net_error + uyarı | düzeltildi ve doğrulandı (mantık) |
| K21 S7/S8 | warn + Model Kontrolü HATA | düzeltildi ve doğrulandı (mantık) |
| K21 S9 | otomatik kayıt hatası oturumda bir kez messagebox | düzeltildi |
| K29 | Component BK yüz aracı mst_hb_ents (çok kopyalıda red); aks adı html_escape + `</`→`<\/`; 9 callback mst_cb_json; N8 Integer/Float | düzeltildi ve doğrulandı (mantık) |
| K45 | `tb.show unless defined?(TB_HIDDEN) && get_last_state==TB_HIDDEN` | düzeltildi, SketchUp testi bekliyor |
| K54 | mst_pv_tooth_seat_warnings (oluşturma iletisi + Model Kontrolü) | ara çözüm (uyarı) |
| K56 | istasyon + özgün sıra | düzeltildi ve doğrulandı (Ruby 3.1.2) |
| K61 | tek örnekli üst tanımlar boyunca tam zincir (yanlış çakışma 1→0) | düzeltildi ve doğrulandı (mantık) |
| DXF birim | mst_dxr_l_unit ($INSUNITS, yoksa soru, varsayılan m); regex (mm|cm|m); otomatik pafta ftol=0.006/u (cm = eski 0,6) | düzeltildi, SketchUp testi bekliyor |
| A2 aktarımları | pile_owned_concrete infill_enabled=0 önce; repair_bim_identity fiziksel ID mst_uid_owner | düzeltildi ve doğrulandı (mantık) |
| K28 kalıntı | bulunmadı | değişiklik yok |

Yeni anahtarlar: parent_deck_revision_no (Int), link_support_state_json (String), formwork_net_error (String).
Davranış değişiklikleri: K15 toplu yerleşim yarıda kalırsa tümü geri alınır; K62 Canlı QTO hatasında last_result kaydedilmez.
Metraj değiştirenler: K53, K56 (aynı istasyon), DXF "L=" birimsiz/mm, K17 bozuk kayıt.
Açık/bilinen sınırlar: K22 aşama 2; K51 konumsuz eski kayıt; K07 parent_uid dolu ama eşleşmiyorsa parent_deck_id'ye düşülmez; kaplama önizlemede "PID-n"; K23 çok örnekli tanımda zincir durur; otomatik paftada L= metre kabulü.
Ayrı öneriler (sonraki parti): mst_v50_beams ~470 VK temas BK formwork rescue nil; boq_pro.rb:376 send_boq hatası puts; mst_schedule.rb:274 sp_last_json işlem dışı; mst_v50_piles.rb:459 mst_kd_last_json işlem dışı; main.rb U6 okuma işlevleri yazma; element_visible_id kaplama.
diff: 21 dosya +1059/−75 (testler dahil).
