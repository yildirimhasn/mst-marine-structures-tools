# 08 SketchUp kabul kontrol listesi — MST 0.51.5 TB1 FIX1 (02.11.2026; son durum: kaynak eaaa858)

Hazırlayan: mst-dokumantasyon. Satırlar parti raporlarındaki "SketchUp kabul" maddelerinden (`03`–`06`, `09`, `10`, `14`, `15`; G arayüz partisi `c39c52c` için ana oturum bildirimi) ve `16_kabul_denetim.md` §"Boşluklar" listesinden birleştirildi; gruplar 16 §"SketchUp kabul önceliği" sırasındadır. Kesin liste ve sıra mst-test-paketleme'nindir.
Sonuç sütunları **kullanıcı dolduracak**. Ajan değerlendirmesi (mst-kabul-denetim) ayrı satırda "ajan değerlendirmesi" olarak yazılır; onay sayılmaz. Bu listedeki hiçbir satır henüz denenmedi.

Ön koşullar:
- Paket: `dist\MST_v0.51.5_TB1_FIX1_TEST.rbz`, 201 dosya, 1.177.336 bayt, SHA-256 `454daf8ed3d5298e694d55689268f451bd950e17111188b040dbaf1842167bbe` (kaynak commit `eaaa858`). `dist\gecersiz_e1ad035f\` içindeki eski paket geçersizdir; kurulmaz.
- SketchUp 2020; kurulu sürüm SHA-256 ile doğrulandı mı: ______.
- Tüm adımlar **model kopyası** üzerinde; asıl `.skp` açılmaz. Model kopyası adı her satıra yazılır.
- Karşılaştırma için aynı kopya 0.51.4 ile de açılıp Keşif CSV, Ayrıntılı Metraj (Excel) ve Özet alınır (golden-master).
- Ekran adları 0.51.5 Türkçe adlarıdır (Parti E); 0.51.4'teki İngilizce karşılığı parantezde.

Sonuç: Geçti / Kaldı / Denenmedi. "Kullanıcının sözü" kullanıcının bildirdiği ifadedir.

## 1. Kurulum ve runner
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| 0.1 | Kurulum | RBZ kur, SketchUp'ı yeniden aç | Ana pencere başlığı "Deniz Yapıları Araçları (MST) v0.51.5"; Ruby Console'da yükleme hatası yok | | | | |
| 0.2 | Runner | TB1 entegrasyon test eklentisini çalıştır | Sürüm ve SHA kontrolleri **başarısız** (beklenen, 0.51.4'ü bekler); yöntem adı kontrolleri geçer | | | | |
| E-1 | E / eklenti adı | Extension Manager'ı aç | Eklenti adı "Deniz Yapıları Araçları (MST)"; etkin/pasif durumu ve Extensions menüsüne atanmış kısayollar not edilir (sıfırlanabilir, 07 §2.7) | | | | |
| E-2 | E / menü | Extensions menüsünü ve alt menüleri gez | Menü öğeleri Türkçe (ör. Keşif Motoru, Metraj Motoru, Model Kontrolü, BIM Kimlik Onarımı, Ayrıntılı Metraj (Excel)); bilinçli istisnalar dışında İngilizce kalmaz | | | | |

## 2. Golden-master (0.51.4 ↔ 0.51.5: CSV, Ayrıntılı Metraj, Özet)
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| 0.3 | Golden-master | Aynı model kopyasında 0.51.4 ve 0.51.5 Keşif CSV + Ayrıntılı Metraj (Excel) + Özet al, karşılaştır | Farklar yalnız sürüm notu §2.1 kalemlerinde (ayrıca K08 pano ayrıştırması ve K33/K39 BİLGİ satırları; toplam dışı). Ek beklenen farklar: **G4** Keşif ÖBF-004 donatı = önceki + ayrı bordür hacmi × 150/1000 t (DS2 döşemede 0); **G5** CSV 9 sütun (sona `Donati_t`), ΣDonati_t = Keşif ÖBF-004, ΣCelik_t = boru çeliği (Keşif PILE_STEEL), BK Beton_m3 net, kazık iç betonu tek satır = ÖBF-010, "Keşif ek kalemi" satırları (0.51.4 CSV'si 8 sütundur; sütun eşlemesiyle karşılaştırılır); **G6** pano ve Excel Özet Toplam Beton = önceki + kaplama hacmi; **F1** Ayrıntılı Metraj'da tek "Kazık İçi Beton" satırı (0.51.4'te çift olabilir). Sahte fikstür ön sonucu (SketchUp dışı, kabul kanıtı değil): zincir parça parça beklenmeyen 0; uçtan uca 0.51.4 karşılaştırması yok (07 §6) | | | | |
| E-10 | E / metin işi | 0.51.4 ile 0.51.5 Keşif toplamını karşılaştır (0.3'teki metraj farkları ayıklanarak) | Türkçeleştirme kaynaklı fark yok | | | | |
| E-7 | E / Excel | Ayrıntılı Metraj (Excel) dışa aktar | Sayfa adları: Özet, Ayrıntılı Metraj, Eleman Kütüphanesi, Kazık Metrajı, Keşif USD, Fore Kazık, Taş Dolgu | | | | |
| E-8 | E / CSV | Keşif / Metraj CSV Dışa Aktar | Başlıklar: Kategori, Tip, Malzeme/Sinif, Adet, Boy_m, Beton_m3, Kalip_m2, Celik_t, Donati_t; Türkçe karakterler bozulmadan okunur | | | | |
| F-1 | F1 | Ayrıntılı Metraj (Excel) → Ayrıntılı Metraj sayfası | Tek "Kazık İçi Beton" satırı; hacmi = Keşif ÖBF-010 | | | | |
| Gb-4 | G5 | Keşif / Metraj CSV al, toplamları Keşif ile karşılaştır | 9 sütun; ΣDonati_t = ÖBF-004; ΣCelik_t = boru çeliği; BK betonu net; iç beton tek satır | | | | |
| Gb-5 | G6 | Pano ve Excel Özet "Toplam Beton" | Kaplama betonu dahil; pano alt yazısında KAPLAMA; Excel Özet'te "Beton Kaplama (sınıf)" satırları | | | | |

## 3. Kritik metraj
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| A2-1 | K50 | Dişin/alçak bölgenin altında kazık olan BK | BK betonu gömülme düşümü kazık eksenindeki derinlikten | | | | |
| A2-2 | K36 | Component kazıkta iç beton YOK | İç beton ve donatısı metrajda 0 | | | | |
| B-4 | K22 | Döndürülmüş BK'da prekast oluştur | Türkçe ileti, prekast oluşturulmaz, işlem açılmaz; mevcut prekastta Model Kontrolü UYARI | | | | |
| A2-3 | K58 | İki donatılı Component PD'nin boylarını eşitle | Seçilmeyen parçaya donatı/tonaj sızmaz | | | | |
| A2-5 | K57 | Seçim boşken "Çizimden / Otomatik Donatıyı Sil" | Paftadan metrajı olan BK ve prekast donatısı silinmez; iletide sayı | | | | |
| A2-6 | K59 | Kafesli kazıkta hesap hatası oluştur | Donatı pursantaja döner (0 t değil); Model Kontrolü HATA | | | | |
| A2-7 | K35 | Kazık ayrı poz: kesit grubu ekle/çıkar, hakediş kaydet | Önceki dönem miktarı başka kesite kaymaz | | | | |
| Ga-5 | G-a #7 | TEK POZ modunda hakediş kaydet | Kayıt engellenmez (bozuk kesit kodu kaydı yalnız AYRI POZ modunda engeller) | | | | |
| A2-8 | K33/K39/K40 | Keşif bilgi satırları | "BİLGİ" satırları fiyatsız; toplam 0.51.4 ile aynı | | | | |
| C-1 | K33/K39/K40 | Keşif bilgi satırları ve toplam | Toplam 0.51.4 ile aynı | | | | |
| Gb-1 | G4 | Ayrı bordür öğesi olan (eski tip) döşeme; Keşif ve hakediş | ÖBF-004 artışı = bordür hacmi × 150/1000 t; önceden onaylı bordür donatısı bu dönem artışı olarak görünür, `previous_*` değişmez | | | | |
| B-2 | K53 | Kaplama eğimi uygulandıktan sonra BK kotunu değiştir | Kaplama değerleri korunur (yenileme öncesi = sonrası); revizyon uyarısı | | | | |
| B-3 | K51 | Diş tabanını kalıptan çıkar, BK'yı revize et | Seçim yalnız o yüzde kalır | | | | |
| A2-9 | K55 | Dolguda bilinmeyen malzeme kodu | Alt-1 tonajı sessiz 0 yerine hata | | | | |
| B-9 | K56 | Aynı istasyonda iki kesitli dolgu | Alt-1 hacmi istasyon + özgün sıraya göre; kesit sırası karışmaz | | | | |
| A2-10 | 08-R3 | Hakediş yedek yolu (eleman bazında kısmi ilerleme) | İlerleme adet oranıyla değil miktar ağırlıklı hesaplanır | | | | |
| A2-11 | Eğik kazık elipsi | Eğik kazıklı BK oluştur / plan izle | Kalıp açıklığı daire değil elips alanıyla düşülür (fikstür örneği 0,810732 → 0,821915 m²) | | | | |
| A2-12 | 08-R6 | Alt yüzlerin hiçbiri kalıpta olmayan BK | Kazık açıklığı kalıptan düşülmez (kısmi kapalıda eski kural) | | | | |

## 4. Veri ve kimlik
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| A1-1 | K02/K03/K26 | 21+ revizyon kaydet; fark yokken kaydet; tek Ctrl+Z | Eski kayıt silinmez, numara tekrarlanmaz; fark yoksa kayıt oluşmaz; tek Ctrl+Z | | | | |
| Ga-1 | G1 | Öğe ilerlemesi Onaylandı → Ctrl+Move → BIM Kimlik Onarımı → ilerleme gir → Ctrl+Move → BIM Kimlik Onarımı; tek Ctrl+Z | Son kopya onaysız (çift sayım yok); devralma geçmişe eklenir, eski kayıt değişmez; tek Ctrl+Z | | | | |
| A1-2 | K04/K05/K28 | Eleman Kütüphanesi'ni aç; bağımlılık damgalama çalıştır | Açmak kayıt yazmaz; dolu alanlar ezilmez; tek işlem | | | | |
| A1-3 | K06 | Döşeme + tretuvarı Ctrl+Move ile kopyala; Model Kontrolü → BIM Kimlik Onarımı; revizyon/hakediş kaydı | "kopya olası"; kopyaya yeni UID + `copied_from_uid`; ilerleme devralınmış (onaysız); mükerrer UID sorusu | | | | |
| A1-4 | K19/K20/K27 | Bozuk kayıtlı kopyada kaydetme dene | Kaydetme reddi + Türkçe ileti; dosya/kayıt değişmez | | | | |
| Ga-4 | G-a #1 | Bozuk dolgu kesit zinciri kaydı olan kopya: dolgu sayfasını aç, kaydet / otomatik kayıt | Kayıt ezilmez; yüklemede uyarı | | | | |
| Ga-8 | G3-#12 | PID'siz eski revizyon kaydı olan modelde mükerrer UID'li öğelerle revizyon karşılaştırması | Kayıtlar anahtar çakışması olmadan eşlenir (önceki tarafta çok kayıt varsa `u~PID-n` / `u~REC-n`) | | | | |

## 5. Paylaşılan tanım ve bağımlılık
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| A2-4 | K09 | Çok kopyalı Component BK'ya menfez EKLE / TEMİZLE | "Yalnız bu parçayı ayır / iptal" sorusu; diğer kopyalar değişmez; `element_uid` korunur | | | | |
| Ga-2 | G3-#11 | Üç kopyalı Component BK'da çizimden donatı sil | Soru gelir; Hayır → değişiklik yok; Evet → diğer kopyalarda donatı kalır; tek Ctrl+Z | | | | |
| B-10 | K29 | Çok kopyalı Component BK'da BK yüz aracını kullan | Araç reddeder (paylaşılan tanım değişmez) | | | | |
| B-11 | K61 | Tek örnekli iç içe tanımlardaki öğede çakışma denetimi | Tam dönüşüm zinciri kullanılır; yanlış çakışma raporlanmaz | | | | |
| B-1 | K07 | Döşemeyi taşı (kaplamalı) | Kaplama birlikte ötelenir | | | | |

## 6. Geri alma (Undo)
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| B-5 | K11/K12/K15/K62 | İlgili araçlar sonrası Ctrl+Z; toplu prekastı yarıda kes | Tek Ctrl+Z; yarıda kalan toplu yerleşim tümüyle geri alınır | | | | |
| Ga-6 | G-a #10 | Toplu prekastta hata oluştur | Türkçe hata iletisi; işlem geri alınır | | | | |
| B-6 | K14 | Dolgu yükle (alternatif değişmeden) | Yazım/Undo adımı oluşmaz | | | | |
| C-5 | K24 | Dolgu Alt-02 açılış | Alternatif korunur; Undo adımı oluşmaz | | | | |
| F-2 | F2 | Kazık sayfasında "Modelden Seçili Kazığı Yükle" → foraj değiştir → "✓ Mevcut Kazığı Güncelle" → Ctrl+Z | Tanımsız işlev hatası yok; güncelleme tek Ctrl+Z ile geri alınır | | | | |
| Gb-6 | 'ALL' | Kazık hedefi "Projedeki tüm kazıklar" ile toplu işlem → Ctrl+Z | İşlenen kazık sayısı = modeldeki kazık sayısı; tek Ctrl+Z | | | | |

## 7. Model Kontrolü
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| A2-13 | G3 (A2) | Hata bayraklı öğeler (`pile_rebar_error`, `pc_rebar_error`, `rebar_restore_error`, `culvert_error`, `formwork_net_error`) olan kopyada Model Kontrolü | "Hesap Hatası" grubu görünür, bayraklı öğeler listelenir | | | | |
| Ga-3 | G3-#13 | BK gömülme hesabı hatalı / kazık orijini başlık merkezinde olmayan kopyada Model Kontrolü | HATA "BK gömülme düşümü hesaplanamadı (…); BK betonu brüt alındı."; derinlik hatasında UYARI; orijin UYARISI | | | | |
| Ga-7 | G-a #8 | Model Kontrolü sağlık kutuları | Tüm kontrol adları bir sağlık kutusuna bağlı ('Kanal Cebi' dahil) | | | | |
| E-5 | E | Model Kontrolü sağlık kutuları metinleri | Türkçe | | | | |
| B-12 | K10 | VK/BBK'nın bağlı olduğu BK'nın kotunu/konumunu değiştir veya BK'yı sil | Uyarı (otomatik yeniden kurma yok) | | | | |
| B-13 | K23 | Ölçekli / aynalı öğe | Model Kontrolü uyarısı; metraj değişmez | | | | |
| B-14 | K54 | PV diş / oturma uyumsuzluğu | Oluşturma iletisinde ve Model Kontrolü'nde uyarı | | | | |
| B-15 | K16 | Hata kaydı olan öğede kayıtları düzelt (adım ayrıntısı raporda yok; mst-test-paketleme belirleyecek) | Hata yalnız tüm kayıtlar geçerliyse silinir | | | | |
| B-16 | K17 | Bozuk menfez kaydı olan BK: menfez EKLE ve yeniden çizim | EKLE reddedilir; yeniden çizim menfezi silmez; `culvert_error` → Hesap Hatası | | | | |
| B-17 | K18 | Net kalıp hesaplanamayan öğe | `formwork_net_error` + uyarı | | | | |
| B-18 | K21 | S7/S8 hatası olan kopya; otomatik kayıt hatası | S7/S8 Model Kontrolü HATA; S9 otomatik kayıt hatası oturumda bir kez ileti kutusu | | | | |
| Gb-3 | G4 | Gövdesinde bordür betonu olan (DS2) döşemeye ayrı bordür öğesi bağlı kopya | Model Kontrolü çift sayım UYARISI | | | | |

## 8. Arayüz
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| E-3 | E | Ana pencere başlığı | "Deniz Yapıları Araçları (MST)" + 0.51.5 (0.1 ile birlikte gözlenebilir) | | | | |
| E-4 | E | Sayfa adım geçişleri | Adım adları Türkçe; geçişler çalışır | | | | |
| E-6 | E | Rozetler | 0.51.5 | | | | |
| E-9 | E | Geri Al (Edit → Undo) adları | Türkçe işlem adları (ör. "MST BIM Kimlik Onarımı") | | | | |
| B-7 | K45 | Araç çubuğunu kapat, SketchUp'ı yeniden aç | Kapatılan araç çubuğu geri gelmez | | | | |
| C-2 | K34 | Hakediş REBAR notu | Not görünür; kırmızı yalnız negatif dönem | | | | |
| GU-1 | K34 / metraj kontrolü D (`c39c52c`) | Hakediş REBAR satırındaki eşlenmemiş donatı notu | Nedenler arasında "kazık içi beton donatısı: parametreli / BIM kafes" yazar | | | | |
| Gb-2 | G4 / K34 | Aynı not | "Bordür / tretuvar donatısı eleman ilerlemesiyle ödenir" ifadesi görünür | | | | |
| GU-2 | Kazık İçi Beton (`c39c52c`) | Pano, Excel (Ayrıntılı Metraj, Eleman Kütüphanesi), katalog başlıkları | Her yerde "Kazık İçi Beton"; "Kazık İçi Betonu" yok | | | | |
| C-3 | K38 | İcmal '!' satırı, kayıt | Tek uyarı satırı; hesaba girmez | | | | |
| C-4 | K24/K25 | Kronman aks oku / oluştur / güncelle | Aks okunur, geri bildirim gelir | | | | |
| B-19 | K29 | Adında `<` / `</` olan aks | Ad bozulmadan görünür; dialog kırılmaz | | | | |
| C-6 | K24 | Seçili Eleman Bilgisi, Eleman Kütüphanesi, Ayrıntılı Metraj (Excel), CSV, Model Kontrolü düğmeleri | Hepsi açılır | | | | |
| C-7 | K01 | Eleman Düzenle | Yalnız önizleme + Proje Çalışma Alanı yönlendirmesi | | | | |
| C-8 | K31 | Eski menü Keşif Motoru (0.51.4: BOQ Engine) | Keşif sayfası açılır | | | | |
| C-9 | K42/08-R1 | Kazık formunda kotu sil, boş/0 m kaydet | Çakım alanı temizlenir; onay sorusu | | | | |
| C-10 | K08/K41 | Pano Kaplama satırı; Metraj sütunları | Ayrı Kaplama satırı; Ayrıntılı Metraj 10 sütun | | | | |
| C-11 | K37 | Toplu VAR/YOK önizleme | Önizleme = Kazık Metrajı | | | | |

## 9. DXF birimi ve performans
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| B-8 | DXF birim | `$INSUNITS` olan/olmayan, mm/cm "L=" paftası | Birim sorusu (yoksa); tonaj birime uygun. Bilinen sınır: birim tanımsızken iki varsayılan (m / cm) — sonuç hangi yolla alındıysa yazılır | | | | |
| Gb-7 | G7 | Büyük modelde BIM Kimlik Onarımı ve Bağımlılık Motoru süresi (0.51.4 ile aynı kopya) | Süre ölçülür ve iki sürüm için yazılır; sonuç imzaları/öznitelikleri aynı (sahte nesne ölçümü, kanıt değil: stamp n=200 0,537 → 0,026 s; repair n=209 1,140 → 0,013 s) | | | | |

Toplam satır: 79 (1: 4, 2: 7, 3: 18, 4: 7, 5: 5, 6: 6, 7: 12, 8: 18, 9: 2).

Ajan değerlendirmesi (mst-kabul-denetim): ______ (onay sayılmaz)
