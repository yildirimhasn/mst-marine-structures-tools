# 34 Kod incelemesi — Yapıyı Kopyala düzeltmesi (`cc50a60..96c194d -- src`) (mst-kod-inceleme, 09.11.2026; salt okuma, test çalıştırmadı; ana oturum kaydetti)
Genel: engelleyici bulgu yok. 32/1–8 ve 33/2, 4, 5, 6 kodda kapanmış; yeni hata yolları güvenli tarafta (abort / ret), sessiz yanlış yazım yok.
Okunan: structure_copy.rb tamamı; main.rb 2145-2182, 2939-2949, 6509, 7728-7739, 9695-9723, 10820-10845, 12081-12105, 13616-13621, 13942-13978, 14053-14057.

Denetlenenler: 32/4 aksesuar silme yalnız ayrılmış kopya içinde (mst_sc_separate! önce; paylaşım sürerse raise); 32/2 çocuk yerel dönüşümü bit düzeyinde kopyalanır, ölçek/aynalama kökte → yanlış ret beklenmez; 32/3 crown_build_v2 her zaman model.entities'e mutlak inçle kurar → +dx.m iç içe/kökte doğru; 32/6 önekler türe göre benzersiz, used yalnız büyür → ipucu ilk boş numarayla aynı, vtok ≡ eski :vid; 32/7 mst_plan_readonly ensure ile geri alınır, işlem içi yazım etkilenmez; 32/8 modele giden üç çağrı (axis_manager_v2_save / _show / structure_copy) mstStale'den geçer, diğerleri yalnız bellekte; Undo: tek start_operation, hata → abort + raise; yeni anahtar yok.

| No | Önem | Yer | Bulgu | Senaryo | Öneri | Ana oturum kararı |
|---|---|---|---|---|---|---|
| 1 | düşük | structure_copy.rb:362-365 | Konum denetimi aynı sınıf + aynı yerel konumdaki kardeşlerin yer değiştirmesini yakalamaz; SketchUp sırayı değiştirirse iç içe yapılar her seferinde iptal olur | Üst üste iki grup → öznitelik ters öğeye | SketchUp'ta iç içe Group + Component BK denemesi | 08 N-47 |
| 2 | düşük | :56, 259-261 | Paylaşılan tanımlı Component (prekast, kazık) içindeki aksesuar kopyayla gelir, sayılmaz | Prekast tanımı içinde usturmaça | Böyle model varsa sayılsın | 07 §2.10 bilinen sınır (6) |
| 3 | düşük | :565-571 | QuantityService geometriden iç içe öğeleri topluyorsa aksesuar silinen kopyada metraj farkı → iptal (güvenli) | BK içinde aksesuar | Doğrulanmalı | Geçersiz: BK kalıbı yalnız BK'nın kendi yüzleri (main.rb:2260), beton öznitelikten (2662) |
| 4 | bilgi (kapsam dışı) | main.rb:13975 | Kopya sonrası Ctrl+Z → yenilenmiş pencere modelde olmayan kodları kaydedebilir (önceden de vardı); taşıma yolunda kronman uçları ötelenmez | Ctrl+Z, sonra Projeyi Kaydet | Ayrı iş | 07 §2.10 bilinen sınır (7) |

Doğrulanamayan: SketchUp Group#copy / make_unique çocuk sırası; mst_show_grid_visual ve commit_with_dependencies işlem davranışı yeniden incelenmedi (rapor 32'ye dayanıldı); test dosyaları incelenmedi; SketchUp kabulü yok.
