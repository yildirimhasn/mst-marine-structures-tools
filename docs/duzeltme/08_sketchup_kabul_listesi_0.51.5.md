# 08 SketchUp kabul kontrol listesi — MST 0.51.5 TB1 FIX1 (iskelet, 02.11.2026)

Hazırlayan: mst-dokumantasyon (parti raporlarındaki "SketchUp testi bekliyor" maddeleri ve Parti C kabul adımlarından birleştirildi). Kesin liste ve sıra mst-test-paketleme'nindir.
Sonuç sütunları **kullanıcı dolduracak**. Ajan değerlendirmesi (mst-kabul-denetim) ayrı satırda "ajan değerlendirmesi" olarak yazılır; onay sayılmaz.

Ön koşullar:
- Paket: `MST_v0.51.5_TB1_FIX1_TEST.rbz`, SHA-256: ______ (paketleme sonrası).
- SketchUp 2020; kurulu sürüm SHA-256 ile doğrulandı mı: ______.
- Tüm adımlar **model kopyası** üzerinde; asıl `.skp` açılmaz. Model kopyası adı her satıra yazılır.
- Karşılaştırma için aynı kopya 0.51.4 ile de açılıp BOQ/QTO CSV alınır (golden-master).

Sonuç: Geçti / Kaldı / Denenmedi. "Kullanıcının sözü" kullanıcının bildirdiği ifadedir.

| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| 0.1 | Kurulum | RBZ kur, SketchUp'ı yeniden aç | Ana pencere başlığı "Marine Structures Tools v0.51.5"; Ruby Console'da yükleme hatası yok | | | | |
| 0.2 | Runner | TB1 entegrasyon test eklentisini çalıştır | Sürüm ve SHA kontrolleri **başarısız** (beklenen, 0.51.4'ü bekler); yöntem adı kontrolleri geçer | | | | |
| 0.3 | Golden-master | Aynı model kopyasında 0.51.4 ve 0.51.5 BOQ CSV + Detailed QTO | Farklar yalnız sürüm notu §2.1 kalemlerinde (ayrıca K08 pano ayrıştırması ve K33/K39 BİLGİ satırları; toplam dışı). Sahte fikstür ön sonucu (SketchUp dışı, kabul kanıtı değil): beklenmeyen 0, `docs\duzeltme\golden\` | | | | |
| A1-1 | K02/K03/K26 | 21+ revizyon kaydet; fark yokken kaydet; tek Ctrl+Z | Eski kayıt silinmez, numara tekrarlanmaz; fark yoksa kayıt oluşmaz; tek Ctrl+Z | | | | |
| A1-2 | K04/K05/K28 | Eleman Kütüphanesi'ni aç; Dependency stamp çalıştır | Açmak kayıt yazmaz; dolu alanlar ezilmez; tek işlem | | | | |
| A1-3 | K06 | Döşeme + tretuvarı Ctrl+Move ile kopyala; Model Kontrolü → BIM Identity Repair; revizyon/hakediş kaydı | "kopya olası"; kopyaya yeni UID + `copied_from_uid`; ilerleme devralınmış (onaysız); mükerrer UID sorusu | | | | |
| A1-4 | K19/K20/K27 | Bozuk kayıtlı kopyada kaydetme dene | Kaydetme reddi + Türkçe ileti; dosya/kayıt değişmez | | | | |
| A2-1 | K50 | Dişin/alçak bölgenin altında kazık olan BK | BK betonu gömülme düşümü kazık eksenindeki derinlikten | | | | |
| A2-2 | K36 | Component kazıkta iç beton YOK | İç beton ve donatısı metrajda 0 | | | | |
| A2-3 | K58 | İki donatılı Component PD'nin boylarını eşitle | Seçilmeyen parçaya donatı/tonaj sızmaz | | | | |
| A2-4 | K09 | Çok kopyalı Component BK'ya menfez EKLE / TEMİZLE | "Yalnız bu parçayı ayır / iptal" sorusu; diğer kopyalar değişmez; `element_uid` korunur | | | | |
| A2-5 | K57 | Seçim boşken "Donatıyı Sil" | Paftadan metrajı olan BK ve prekast donatısı silinmez; iletide sayı | | | | |
| A2-6 | K59 | Kafesli kazıkta hesap hatası oluştur | Donatı pursantaja döner; Model Kontrolü HATA | | | | |
| A2-7 | K35 | Kazık ayrı poz: kesit grubu ekle/çıkar, hakediş kaydet | Önceki dönem miktarı başka kesite kaymaz | | | | |
| A2-8 | K33/K39/K40 | BOQ bilgi satırları | "BİLGİ" satırları fiyatsız; toplam 0.51.4 ile aynı | | | | |
| B-1 | K07 | Döşemeyi taşı (kaplamalı) | Kaplama birlikte ötelenir | | | | |
| B-2 | K53 | Kaplama eğimi uygulandıktan sonra BK kotunu değiştir | Kaplama değerleri korunur; revizyon uyarısı | | | | |
| B-3 | K51 | Diş tabanını kalıptan çıkar, BK'yı revize et | Seçim yalnız o yüzde kalır | | | | |
| B-4 | K22 | Döndürülmüş BK'da prekast oluştur | Türkçe ileti, prekast oluşturulmaz, işlem açılmaz | | | | |
| B-5 | K11/K12/K15/K62 | İlgili araçlar sonrası Ctrl+Z; toplu prekastı yarıda kes | Tek Ctrl+Z; yarıda kalan toplu yerleşim tümüyle geri alınır | | | | |
| B-6 | K14 | Dolgu yükle (alternatif değişmeden) | Yazım/Undo adımı oluşmaz | | | | |
| B-7 | K45 | Araç çubuğunu kapat, SketchUp'ı yeniden aç | Kapatılan araç çubuğu geri gelmez | | | | |
| B-8 | DXF birim | `$INSUNITS` olan/olmayan, mm/cm "L=" paftası | Birim sorusu (yoksa); tonaj birime uygun | | | | |
| C-1 | K33/K39/K40 | BOQ bilgi satırları ve toplam | Toplam 0.51.4 ile aynı | | | | |
| C-2 | K34 | Hakediş REBAR notu | Not görünür; kırmızı yalnız negatif dönem | | | | |
| C-3 | K38 | İcmal '!' satırı, kayıt | Tek uyarı satırı; hesaba girmez | | | | |
| C-4 | K24/K25 | Kronman aks oku / oluştur / güncelle | Aks okunur, geri bildirim gelir | | | | |
| C-5 | K24 | Dolgu Alt-02 açılış | Alternatif korunur; Undo adımı oluşmaz | | | | |
| C-6 | K24 | Seçili Eleman Bilgisi, Element Library, Excel, CSV, Model Kontrolü düğmeleri | Hepsi açılır | | | | |
| C-7 | K01 | Eleman Düzenle | Yalnız önizleme + Proje Çalışma Alanı yönlendirmesi | | | | |
| C-8 | K31 | Eski menü Keşif / BOQ Engine | BOQ sayfası açılır | | | | |
| C-9 | K42/08-R1 | Kazık formunda kotu sil, boş/0 m kaydet | Çakım alanı temizlenir; onay sorusu | | | | |
| C-10 | K08/K41 | Pano Kaplama satırı; QTO sütunları | Ayrı Kaplama satırı; Detailed QTO 10 sütun | | | | |
| C-11 | K37 | Toplu VAR/YOK önizleme | Önizleme = Kazık QTO | | | | |

Ajan değerlendirmesi (mst-kabul-denetim): ______ (onay sayılmaz)
