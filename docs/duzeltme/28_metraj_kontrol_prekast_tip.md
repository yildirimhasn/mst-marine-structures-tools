# 28 Metraj kontrolü — Kontrollü Düzenleme prekast tip adı (mst-metraj-kontrol, 03.11.2026; 0983966; salt okuma)
Sonuç: toplamlar değişmez; değişen yalnız Metraj sayfası prekast tablolarında satır dağılımı / etiket (kod okuması). Golden kanıtı yok (fikstürde tip adı yok, golden Kontrollü Düzenleme yolunu çağırmıyor).

| Yer | Anahtar | Sonuç |
|---|---|---|
| Metraj sayfası PD (main.rb:4281) | precast_type + sınıf + genişlik + yükseklik | Satır ayrışır (ör. PD-01 / PD-01-B); toplam aynı (4284) |
| Metraj sayfası PK (main.rb:4287) | precast_type_id + iç ölçüler | Aynı |
| PV (main.rb:4294) | — | Kapsam dışı (crane_precast Kontrollü Düzenleme'de yok) |
| BOQ boq_quantities, CSV / Excel (library_type_id) | — | Girmez — uyuyor |
| boq_pro.rb, qto_workspace.rb | — | precast_type* yok — uyuyor |
| Revizyon imzası / RevisionLog | — | Tip adı yok — uyuyor |
| Katman (mst_assign_tag) | — | Değişir; QTO'da katmana göre gruplama yok |
| Hakediş / ilerleme (prog2_row_key, previous_*, progress_items_json, manual_progress_json, trace_pids) | — | Tip adı içermez; eşleşme kopmaz — uyuyor |

- Çift sayım / satır kaybı: bulunamadı (group_by; her eleman tek grupta).
- BK boyutlandırma yolu: `dims` verilmediğinde anahtar eskisiyle aynı; ölçü sırası ve mm yuvarlama birebir — uyuyor (statik).
- mst_code_usage (b0a2592): yalnız kilit / plan; metraj yolunda çağrı yok — uyuyor.
- Kayıt kapsamı farkı (ProjectWorkspace.entries ↔ collect_elements): ana oturum düzeltti, Kontrollü Düzenleme de collect_elements kullanır.

Açık (kabul bekliyor): önerilen golden senaryosu — aynı adlı 2 PD + 1 PK; birinin boyu Kontrollü Düzenleme ile değişir; öncesi / sonrası BOQ_QTY, CSV, Excel, hakediş (onaylı PD), Metraj sayfası prekast satırları ve tip alanları; beklenen: toplamlar eşit, PD satırı ikiye ayrılır, hakediş onaylı miktarı eşit; aynı senaryo BK aks taşıma yoluyla da aynı adı üretmeli. Golden aracı bu yolu desteklemediği için yapılmadı → SketchUp kabul listesinde.
