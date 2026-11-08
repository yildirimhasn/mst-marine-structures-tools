# 08 SketchUp kabul kontrol listesi — MST 0.51.5 TB1 FIX1 (02.11.2026; son durum: kaynak c8f9d70 — ön koşullar, 0.2 ve Parti H satırları mst-test-paketleme)

Hazırlayan: mst-dokumantasyon. Satırlar parti raporlarındaki "SketchUp kabul" maddelerinden (`03`–`06`, `09`, `10`, `14`, `15`; G arayüz partisi `c39c52c` için ana oturum bildirimi) ve `16_kabul_denetim.md` §"Boşluklar" listesinden birleştirildi; gruplar 16 §"SketchUp kabul önceliği" sırasındadır. Kesin liste ve sıra mst-test-paketleme'nindir.
Sonuç sütunları **kullanıcı dolduracak**. Ajan değerlendirmesi (mst-kabul-denetim) ayrı satırda "ajan değerlendirmesi" olarak yazılır; onay sayılmaz. Bu listedeki hiçbir satır henüz denenmedi.

Ön koşullar:
- Paket: `dist\MST_v0.51.5_TB1_FIX1_TEST.rbz`, 201 dosya, 1.181.367 bayt, SHA-256 `75c0ea66779cbe8d89fb193d07f847cfcdc9549450a272c03c5f79adf278c773` (kaynak commit `c8f9d70`, Parti H dahil; manifest `dist\MST_v0.51.5_TB1_FIX1_TEST.manifest.txt`). `dist\gecersiz_e1ad035f\` ve `dist\gecersiz_454daf8e\` içindeki eski paketler geçersizdir; kurulmaz.
- Runner: `dist\MST_TB1_Integration_TestRunner_v1.2.3_for_0.51.5.rbz`, 3 dosya, 17.384 bayt, SHA-256 `a02b4383ab28514c96f3f3f96dabeae896a98d646b84b71719a0e37805cb59ea` (beklenen MST `v0.51.5 TB1 FIX1` / `0.51.5`; dosya SHA listesi `c8f9d70` src'si = yukarıdaki paket, 201/201). Extension Manager → Eklenti Yükle ile kurulur; 1.1.0 kuruluysa aynı dosya adlarıyla yerine geçer. Kurulumdan sonra SketchUp yeniden açılır. Eklenti adı "MST 0.51.5 — Birleşim Testi (Salt Okunur)", sürüm 1.2.0; menü Extensions → "MST 0.51.5 | Birleşim Testi — Salt Okunur". 1.1.0 0.51.5 kabulünde kullanılmaz.
- SketchUp 2020; kurulu sürüm SHA-256 ile doğrulandı mı (MST 201 dosya ve runner 3 dosya, manifestlerle): ______.
- Tüm adımlar **model kopyası** üzerinde; asıl `.skp` açılmaz. Model kopyası adı her satıra yazılır.
- Karşılaştırma için aynı kopya 0.51.4 ile de açılıp Keşif CSV, Ayrıntılı Metraj (Excel) ve Özet alınır (golden-master).
- Ekran adları 0.51.5 Türkçe adlarıdır (Parti E); 0.51.4'teki İngilizce karşılığı parantezde.
- (03.11.2026) §10 satırları kaynak `930876a` sonrası üretilecek paketi gerektirir; yukarıdaki `c8f9d70` paketi bu değişiklikleri içermez. Paket adı ve SHA-256: **paketleme sonrası yazılacak** (07 §1). Her satırda hangi paketle denendiği yazılır. *(Yazıldı, 03.11.2026 mst-test-paketleme: §10 N-1 … N-23 için paket `MST_v0.51.5_TB1_FIX1_TEST.rbz`, src `831f0d0`, 201 dosya, SHA-256 `38d83120232e98e86ac95af02f670ee7c0b927cc34899bacc8f00c563914f50e`; runner `MST_TB1_Integration_TestRunner_v1.2.4_for_0.51.5.rbz` (sürüm 1.2.4), SHA-256 `c96075b570b1173851afbc3c27c87f2ad56d17810ce204f3ce824cdd54bd5c4d`. Teslim kopyası `OneDrive\Masaüstü\CLAUDE\MST_v0.51.5_TESLIM_5\`. Yukarıdaki `75c0ea66…` MST ve 1.2.3 runner paketleri bunun yerine geçmiştir; `dist\gecersiz_75c0ea66\`.)*

Sonuç: Geçti / Kaldı / Denenmedi. "Kullanıcının sözü" kullanıcının bildirdiği ifadedir.

## 1. Kurulum ve runner
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| 0.1 | Kurulum | RBZ kur, SketchUp'ı yeniden aç | Ana pencere başlığı "Deniz Yapıları Araçları (MST) v0.51.5"; Ruby Console'da yükleme hatası yok | | | | |
| 0.2 | Runner 1.2.0 | Menü "1 — Birleşim ve Saf Hesap Testlerini Çalıştır"; ardından model kopyası açıkken "2 — Aynı Testler + Aktif Modelden Miktar Oku"; "3 — Son Raporu TXT + JSON Kaydet" (test çıktıları klasörüne, proje klasörüne değil) | Tüm kontroller **geçmeli** (fail=0): "Yüklü sürüm ve yapı" 0.51.5 / v0.51.5 TB1 FIX1; "Kurulu dosyalar doğru birleşim paketine ait mi?" 201 dosya; "Aktarılan araçların giriş noktaları" 12 yöntem. Menü 2'de model okuma kaydı değiştirmez ("Okuma sırasında … değişti" hatası yok); eksik/geçersiz miktar uyarısı (warn) model verisine bağlıdır. Sahte nesne ön sonucu (SketchUp dışı, kanıt değil): menü 1 = 31 geçti / 0 hata. Kanıt: TXT + JSON rapor | | | | |
| E-1 | E / eklenti adı | Extension Manager'ı aç | Eklenti adı "Deniz Yapıları Araçları (MST)"; etkin/pasif durumu ve Extensions menüsüne atanmış kısayollar not edilir (sıfırlanabilir, 07 §2.7) | | | | |
| E-2 | E / menü | Extensions menüsünü ve alt menüleri gez | Menü öğeleri Türkçe (ör. Keşif Motoru, Metraj Motoru, Model Kontrolü, BIM Kimlik Onarımı, Ayrıntılı Metraj (Excel)); bilinçli istisnalar dışında İngilizce kalmaz | | | | |

## 2. Golden-master (0.51.4 ↔ 0.51.5: CSV, Ayrıntılı Metraj, Özet)
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| 0.3 | Golden-master | Aynı model kopyasında 0.51.4 ve 0.51.5 Keşif CSV + Ayrıntılı Metraj (Excel) + Özet al, karşılaştır | Farklar yalnız sürüm notu §2.1 kalemlerinde (ayrıca K08 pano ayrıştırması ve K33/K39 BİLGİ satırları; toplam dışı). Ek beklenen farklar: **G4** Keşif ÖBF-004 donatı = önceki + ayrı bordür hacmi × 150/1000 t (DS2 döşemede 0); **G5** CSV 9 sütun (sona `Donati_t`), ΣDonati_t = Keşif ÖBF-004, ΣCelik_t = boru çeliği (Keşif PILE_STEEL), BK Beton_m3 net, kazık iç betonu tek satır = ÖBF-010, "Keşif ek kalemi" satırları (0.51.4 CSV'si 8 sütundur; sütun eşlemesiyle karşılaştırılır); **G6** pano ve Excel Özet Toplam Beton = önceki + kaplama hacmi; **F1** Ayrıntılı Metraj'da tek "Kazık İçi Beton" satırı (0.51.4'te çift olabilir). Sahte fikstür ön sonucu (SketchUp dışı, kabul kanıtı değil): zincir parça parça beklenmeyen 0; uçtan uca 0.51.4 ↔ c8f9d70 fikstür karşılaştırmasında 110 farktan 95'i §2.1 / §2.4 / §2.5 kalemleriyle eşlendi, 15'i (Excel Ayrıntılı Metraj sayfası) karşılaştırılamadı (07 §6). Ek beklenen fark **H4b** (yalnız yönelim değiştirilen eğik kazığa bağlı BK'da kalıp; H-2) | | | | |
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
| H-2 | H4b (METRAJ) | BK'ya bağlı bir kazığı seç → Seçili Kazıklara Yönlendirme Uygula (Eğik, 1:6); öncesi ve sonrası Keşif / Metraj CSV al; Ctrl+Z | BK kazık açıklığı daire → elips (Ø1016 1:6: +0,011183 m²), BK net kalıbı aynı miktar azalır, aynı işlemde; CSV BK Kalip_m2 farkı yalnız bu; tek Ctrl+Z ile kazık yönelimi ve BK değerleri birlikte geri gelir; bağlı kazık listesi eşleşmeyen BK için uyarı iletisi | | | | |
| H-10 | H5 (METRAJ) | Kazık sayfasında "Modelden Seçili Kazığı Yükle": önce deniz tabanı kotu dolu kazık, sonra kotu boş kazık yükle | İkinci kazıkta kot alanı boş kalır (önceki kazığın kotu taşınmaz); çakım alanı ikinci kazığa göre hesaplanır/boş; kaydedilirse yanlış çakım yazılmaz | | | | |
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
| H-1 | H1 (K43) | Uzantılar → Deniz Yapıları Araçları (MST) → Tüm araçlar (eski menü) → "Seçili Elemana Elle Aks Ata…": (a) MST öğesi + MST dışı öğe karışık seçim, (b) giriş kutusunda Vazgeç, (c) geçerli aks; sonra Ctrl+Z | Yalnız MST öğelerine `axis` ve `axis_assignment=manual` yazılır; `project` yalnız boşsa; ano / zone / active_ano değişmez; Vazgeç'te işlem/Geri Al adımı yok; tek Ctrl+Z ("MST Elle Aks Ataması") tümünü geri alır; Model Kontrolü "Aks/Açıklık bilgisi eksik" metni bu menüyü gösterir | | | | |
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
| H-4 | H3d | A-çerçeve kazık yerleşimi, DXF'ten kazık dispozisyonu ve VK/BBK oluşturma; her birinden sonra Edit → Undo listesi ve tek Ctrl+Z | Son girdi kaydı (`mst_af_last_json`, `mst_kd_last_json`, `mst_vk_last_json`) ayrı Geri Al adımı oluşturmaz; tek Ctrl+Z oluşturulan öğeleri ve kaydı birlikte geri alır; kazık oluşturulmadıysa kayıt yazılmaz | | | | |
| H-5 | H3c | İş programını iki kez değiştirmeden kaydet; sonra bir değer değiştirip kaydet | İlk değişmeyen kayıt Geri Al adımı oluşturmaz; değişen kayıt tek adım "MST İş Programı Kaydı" | | | | |
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
| H-6 | H7 / H8 / H9 / H3a | Model Kontrolü: (a) menfezi kazık gömülme zarfıyla kesişen BK, (b) MST öğesi içeren çok kopyalı sarmalayıcı Component, (c) v0.34 tretuvarlı eski döşeme, (d) donatısı BIM olmayan, çizelgesinde CHAIR/SEHPA olan BK, (e) donatısı paftadan/otomatik ve kaplamalı döşeme, (f) VK temaslı BK'da net kalıp hatası | (a) UYARI "menfez ile kazık gömülmesi kesişiyor…"; (b) UYARI "Keşif N kez, hakediş 1 kez…"; (c) UYARI tahmini bindirme hacmiyle, kayıtlı değer değişmez; (d)(e) "Bilgi:" satırı (UYARI düzeyinde); (f) `formwork_net_error` → Hesap Hatası grubu. Metraj değişmez | | | | |
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
| H-7 | H3f | Kaplamalı döşemede bağımlılık / önizleme listesi | Kaplama "TOP-…" kimliğiyle görünür ("PID-n" değil); diğer öğelerin kimlik gösterimi değişmez | | | | |
| H-8 | H2 (K32) | Kazık sayfasında aks satırındaki ⚙ ile "Kazık Özel Ayarları" penceresini aç; pencereyi daralt/genişlet; ızgara alanlarına bak | Pencere ekranı kaplayan koyu arka planla ortada açılır, genişlik ≤ 720 px; alanlar iki/üç sütun ızgarada aralıklı; ekran görüntüsü (yalnız görünüşü kanıtlar) | | | | |
| C-11 | K37 | Toplu VAR/YOK önizleme | Önizleme = Kazık Metrajı | | | | |

## 9. DXF birimi ve performans
| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| B-8 | DXF birim | `$INSUNITS` olan/olmayan, mm/cm "L=" paftası | Birim sorusu (yoksa); tonaj birime uygun. Bilinen sınır: birim tanımsızken iki varsayılan (m / cm) — sonuç hangi yolla alındıysa yazılır *(Yerine geçti, Parti H H6: birim tanımsızken varsayılan yok — H-3)* | | | | |
| H-3 | H6 | `$INSUNITS` = 0 (tanımsız) paftayla üç yol: kazık dispozisyonu (DXF), paftadan donatı ("L="), 3B pafta | Üç yolda da işlemden önce ön seçimsiz "— seçin —" birim sorusu; seçilmezse iptal, model değişmez, Geri Al adımı yok; seçilen birimle tonaj/konum birime uygun | | | | |
| Gb-7 | G7 | Büyük modelde BIM Kimlik Onarımı ve Bağımlılık Motoru süresi (0.51.4 ile aynı kopya) | Süre ölçülür ve iki sürüm için yazılır; sonuç imzaları/öznitelikleri aynı (sahte nesne ölçümü, kanıt değil: stamp n=200 0,537 → 0,026 s; repair n=209 1,140 → 0,013 s) | | | | |
| H-9 | H4a (K35 / H4b performansı) | Büyük kazıklı model kopyasında (kazık sayısı ve AYRI POZ kaynak sayısı yazılır) Ruby Console: `require 'benchmark'; M=MAG::MarineStructuresTools; 3.times{ puts Benchmark.realtime{ M.boq_rows(true) } }` — `pile_boq_group_codes_json` kayıtlı ve kayıtsız (kayıtsız için ayrı kopya) durumda. Yönelim: kazık seç, `m=Sketchup.active_model; m.start_operation('ölçüm',true); t=Benchmark.realtime{ M.mst_pile_orientation_bk_openings!(m.selection.to_a,m) }; m.abort_operation; puts t` (3 kez; abort ile model değişmez) | Her ölçüm < 1 s (kullanıcı eşiği); aşılırsa yalnız raporlanır (kod değiştirilmez). Sahte nesne ölçümü (SketchUp süresi değil, kanıt değil): n=2000, 4 kaynak `boq_rows` 0,58–0,64 s; 1000 kazık / 200 BK yönelim 0,025 s (07 §6). Kanıt: konsol çıktısı + model kopyası adı, kazık/BK sayısı, sürüm | | | | |

## 10. İsimlendirme, Çalışma Alanı, Keşif ve prekast Kontrollü Düzenleme (kaynak `930876a`, 03.11.2026)
Kaynak: 07 §2.8, raporlar 23–28. Tüm adımlar **model kopyası** üzerinde. Bu satırlar SketchUp'ta denenmedi.

| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| N-1 | `b0a2592` / `930876a` hedef kod | Aks Yöneticisi'nde bir yapıyı silip kaydet; başka bir yapının kodunu silinen koda değiştirmeyi dene (bir kez aynı, bir kez farklı büyük/küçük harfle, ör. "ANO-02" / "ano-02") | İki durumda da Türkçe ret iletisi; kayıt yapılmaz, model değişmez | | | | |
| N-2 | `b0a2592` hedef kod | Bir yapının kodunu modelde kullanılan (başka yapıya ait) bir koda değiştirmeyi dene | Türkçe ret iletisi; model değişmez | | | | |
| N-3 | `b0a2592` kullanılan yapı silme | Elemanı / aks görseli olan bir yapıyı sil: (a) uyarıda onay verme, (b) onay ver; sonra Ctrl+Z | (a) silme reddedilir, model değişmez; (b) uyarı onayıyla silinir, tek Ctrl+Z ile geri gelir | | | | |
| N-4 | `b0a2592` kod karakter kümesi | Yeni yapı kodu ve yeni aks kodu olarak parantez ve virgül içeren değer yaz (ör. "A(1)", "A,1"); ardından yalnız harf, rakam, boşluk, `-` `_` `.` içeren değer yaz | Parantez/virgüllü kod reddedilir (Türkçe ileti); izinli karakterli kod kabul edilir. Modelde önceden kayıtlı eski kodlar için açılışta/kayıtta hata çıkmaz (eski kodlar denetlenmez) | | | | |
| N-5 | `b0a2592` görünen ad | Bir yapının Görünen Ad'ına parantez içeren ad yaz (ör. "Rıhtım (Kuzey)"), kaydet | Kabul edilir; gösterim "Ad (kod)" biçiminde, ad bozulmadan | | | | |
| N-6 | `b0a2592` Çalışma Alanı ağacı | İki farklı yapıya aynı Görünen Ad'ı ver; Proje Çalışma Alanı'nı aç | İki yapı ayrı düğüm olarak görünür (yapı koduyla ayrılır); elemanlar doğru düğümde | | | | |
| N-7 | `b0a2592` BK bekleyişi | Çalışma Alanı'nda bir BK için Elemanı Düzenle, ardından hemen başka bir eleman seç | BK sayfası kendiliğinden açılmaz; seçilen elemana göre davranılır | | | | |
| N-8 | `b0a2592` Keşif Motoru | Keşif Motoru'nu aç | Sayfa açılışta bir kez yenilenir (çift yükleme / ikinci yenileme yok) | | | | |
| N-9 | `0983966` NCR-003 A | Çalışma Alanı → normal prekast (PD) seç → Elemanı Düzenle | Kontrollü Düzenleme formu Prekast sayfasında açılır; alt sekme PD | | | | |
| N-10 | `0983966` NCR-003 A | Çalışma Alanı → kanal prekast (PK) seç → Elemanı Düzenle | Form Prekast sayfasında; alt sekme PK | | | | |
| N-11 | `0983966` / `930876a` tip adı | Aynı tipte en az iki PD olan kopyada birinin boyunu değiştir → önizle → uygula | Önizlemede "Prekast tipi" satırı (eski → yeni ad); uygulama sonrası tip adı: aynı tür + temel tip + ölçüde tip varsa o ad, yoksa "<temel>-B…". mm altı değişiklikte (ölçü anahtarı aynı) ad değişmez | | | | |
| N-12 | `0983966` | N-11 sonrası aynı tipteki diğer parçaları incele (Seçili Eleman Bilgisi) | Diğer parçaların geometrisi ve tip adı değişmez | | | | |
| N-13 | `0983966` METRAJ (28) | N-11 öncesi ve sonrası Metraj sayfası prekast PD/PK tablosu + Keşif / CSV / Ayrıntılı Metraj (Excel) al | Metraj sayfası toplamları eşit kalır (düzenlenen parçanın kendi boy değişikliği farkı dışında; tip adı kaynaklı fark yok); düzenlenen parçanın satırı ayrışır (ör. PD-01 / PD-01-B); Keşif, CSV, Excel'de tip adı kaynaklı fark yok | | | | |
| N-14 | `0983966` hakediş | Önceden onaylı ilerlemesi olan PD'de N-11 uygula, hakedişi aç | Onaylı miktar (`previous_*`) değişmez; ilerleme eşleşmesi kopmaz | | | | |
| N-15 | `0983966` Undo | N-11 uygulamasından sonra Ctrl+Z | Tek adımda geometri ve tip adı (`precast_type_id`, `precast_type`) birlikte geri döner | | | | |
| N-16 | `0983966` mesnetli PD | Üzerinde mesnet/bağlı eleman olan PD'de geometri değişikliği dene | Türkçe ret iletisi; model değişmez, Geri Al adımı yok | | | | |
| N-17 | `0983966` Component prekast | Component prekastı Çalışma Alanı → Elemanı Düzenle ile düzenlemeyi dene | Türkçe ret iletisi; model değişmez (bilinen sınır, 07 §4.1; alt gruplu kanal da formda düzenlenemez) | | | | |
| N-18 | 27/K4 performans | Büyük model kopyasında (yapı / eleman sayısı yazılır) Aks Yöneticisi'ni 3 kez aç; açılış süresini kronometreyle ölç | Süreler yazılır; değerlendirme kullanıcının (eşik belirlenmedi; aşırı gecikme yalnız raporlanır, kod değiştirilmez). Kanıt: süreler + model kopyası adı, sürüm | | | | |
| N-19 | `dd952bb` 25/5 | Yeni bir yapı ekleyip kaydet; Aks Yöneticisi'ni kapat-aç, hiçbir şeyi değiştirmeden "Projeyi Kaydet" | "Değişiklik yok — model değişmedi, Geri Al adımı oluşmadı."; Düzen menüsünde yeni Geri Al adımı yok | | | | |
| N-20 | `dd952bb` 25/7 | Bir yapıyı kazıklarıyla birlikte Aks Yöneticisi'nden onaylayarak sil ve kaydet; yeniden aç, "Yeni yapı kodu" önerisine bak; sonra aynı kodu elle yazıp ekle | Önerilen kod silinen kodu atlar; elle girilince "sahipsiz eleman" onayı sorulur; Vazgeç → eklenmez; onaylanırsa kazıklar yeni yapıda görünür | | | | |
| N-21 | `dd952bb` 25/8 | Çalışma Alanı'nda BK seç → Elemanı Düzenle | Başlık Kirişi sayfası açılır; Prekast / Kontrollü Düzenleme formu açılmaz | | | | |
| N-22 | `dd952bb` 26/1a | Keşif Excel'ini al; "Poz Metrajları" sayfasında ara toplam satırlarına bak | "Eleman toplamı · N eleman" (N = listelenen satır sayısı); "Yapı" sütunu boş; miktar toplamı önceki sürümle aynı | | | | |
| N-23 | `dd952bb` editor_payload | Yalnız gizli sayfa; menüden erişilmez — atlanabilir. Ruby Konsolu'nda MST hatası görülmemeli | Hata yok | | | | |

Toplam satır: 89 (1: 4, 2: 7, 3: 20, 4: 8, 5: 5, 6: 8, 7: 13, 8: 20, 9: 4). Parti H satırları (H-1 … H-10) `19_parti_H_uygulayici.md` "SketchUp kabul" listesi + H2 + H5 + H4a'dan; bu satırlar SketchUp'ta denenmedi.
Ek (03.11.2026): §10 18 satır (N-1 … N-18); yeni toplam 107.
Ek (03.11.2026, `dd952bb`): §10 5 satır (N-19 … N-23); yeni toplam 112.

Ajan değerlendirmesi (mst-kabul-denetim): ______ (onay sayılmaz)

## 11. Kazık tapası ve prekast beton sınıfı pozu (kaynak `2cc5c29`, 04.11.2026)
Kaynak: 07 §2.9, raporlar 29–30. Tüm adımlar **model kopyası** üzerinde. Bu satırlar SketchUp'ta denenmedi. Önce önceki sürümün Keşif Excel'ini aynı kopyada alın (karşılaştırma için).

| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| N-24 | tapa | Tapalı kazıkları olan kopyada Keşif'i aç; ÖBF-012 manipülasyon satırını önceki sürümle karşılaştır | Artış = tapa toplam ağırlığı / 1000 (Detaylı Metraj "Tapa (kg)" toplamı) | | | | |
| N-25 | tapa | Keşif'te "ÇEŞİTLİ DEMİR İMALATI VE YERİNE KONULMASI" (kg) satırına bak | Miktar = tapa toplamı (kg); poz kg birimli (ÖBF-017), ton pozu değil; "Kazık tapası (pozsuz)" bilgi satırı yok | | | | |
| N-26 | prekast | C30/37 prekastlı kopyada Keşif'e bak | "PREKAST BETONU (C30/37)" satırı (ÖBF-037), miktar = C30/37 prekast hacmi; "Poz eşlenmemiş beton … Prekast" bilgi satırı yok; C35/45 satırı miktarı önceki sürümle aynı | | | | |
| N-27 | prekast | Bir prekastın beton sınıfını boşalt (sınıf belirtilmemiş) → Keşif | "PREKAST BETONU" (ÖBF-071) satırı | | | | |
| N-28 | prekast | Bir prekasta kütüphanede pozu olmayan sınıf ver (ör. C50/60) → Keşif | Satır "UYGUN POZ EKSİK", fiyatsız, toplam tutara girmez; açıklamada "PREKAST BETONU (C50/60)" adı | | | | |
| N-29 | prekast | Poz Kütüphanesi'ne "PREKAST BETONU (C50/60)", birim m³, USD fiyatlı poz ekle → Keşif'i yenile | Satır o poza eşleşir, fiyat ve tutar görünür | | | | |
| N-30 | 30/1 | ÖBF Eşleştirme'de "Prekast betonu — C50/60" (veya tapa) kaynağını seç, başka bir m³ (tapa için kg) poz seç → Uygula; sonra Sıfırla | Uygula düğmesi açık; seçilen poz Keşif'e gelir; Sıfırla sonrası ad eşleşmesine döner; her adım tek Ctrl+Z | | | | |
| N-31 | fiyat | ÖBF-037 / ÖBF-071 / ÖBF-017 kütüphanede fiyatsızsa Keşif'e bak | Satır "KÜTÜPHANE FİYATI EKSİK"; fiyat kütüphanede girilince tutar oluşur | | | | |
| N-32 | 30/2 | Önceden C30/37 prekasta (eski sürümde) ilerleme girilmiş kopyada Hakediş'i aç | İlerleme "PREKAST BETONU (C30/37)" satırında görünür; C35/45 satırında yalnız C35/45 elemanlar; geçmiş varsa C35/45 satırında "ödenen miktar azaldı" uyarısı beklenebilir (bilinen sınır) | | | | |
| N-33 | genel | Keşif Excel'i ve Hakediş Excel'ini al | Yeni satırlar Excel'de; Ruby Konsolu'nda MST hatası yok | | | | |

Ek (04.11.2026, `2cc5c29`): §11 10 satır (N-24 … N-33); yeni toplam 122.

## 12. Yapıyı Kopyala (kaynak `96c194d`, 09.11.2026)
Kaynak: 07 §2.10, ADR 31, raporlar 32–33. Tüm adımlar **model kopyası** üzerinde. Bu satırlar SketchUp'ta denenmedi. Her senaryodan önce kaynak yapının Keşif Excel'ini alın. Üç sistemde (İSKELE, RIHTIM, DOLFEN) birer yapı ile yapın.

| No | Parti / bulgu | Adım | Beklenen | Tarih | Model kopyası | Sonuç | Kullanıcının sözü |
|---|---|---|---|---|---|---|---|
| N-34 | K1 | Aks Yöneticisi → aktif yapı → Yapıyı Kopyala; 2 kopya, dx = yapı boyu + 10 m, dy 0, önerilen kodlar → onay | Onay sorusunda eleman türleri / sayıları ve kopyalanmayanlar; sonuçta iki yeni yapı aks ağı ve elemanlarıyla doğru yerde; Ruby Konsolu'nda hata yok | 09.11.2026 | LİKİT ÇALIŞMA-4.skp kopyası (TESLIM_9 paketi) | Karşılandı (Detaylı Metraj): YD-02 → "YD-02copy", BD-03 → "BD-03 copy" (kullanıcı kodu); kopyalar ayrı yapı ara toplamlarıyla. Konum ve son ileti görseli gönderilmedi | "istediğin sonuçlar var" |
| N-35 | K1 metraj | Keşif'i aç (yapı sütunu) ve Excel al | Her kopya yapının satırları kaynakla aynı miktar; proje toplamı = kaynak × 3; kaynak yapının satırları önceki Excel ile aynı | 09.11.2026 | aynı | Kısmen (Detaylı Metraj, Keşif değil): her kopya ara toplamı kaynakla birebir (kazık 10 / 16 adet, boru 127,618 / 217,194 t, BK beton 202,176 / 56,658 / 49,122 / 48,564 / 49,68 m³, donatı aynı); proje toplamı ×2 (kazık 52, BK 812,4 m³, prekast 66 / 6, döşeme ×2). Kopya öncesi Excel aynı modelden (02:11). Keşif Excel gönderilmedi | — |
| N-36 | K1 Undo | Kopyadan hemen sonra tek Ctrl+Z; sonra Ctrl+Y | Ctrl+Z: iki kopya, yeni yapı kodları, aks ağları ve yerleşimler tümüyle kalkar, kaynak aynı; Ctrl+Y geri getirir | | | | |
| N-37 | K1 bağımsızlık | Kopya yapıda bir BK'nın boyunu / menfezini değiştir; bir kazığı düzenle | Yalnız o kopya değişir; kaynak ve diğer kopyanın BK / kazık / döşeme metrajı aynı; Component BK ise kaynak tanımı değişmez | | | | |
| N-38 | K1 kimlik | Model Kontrolü çalıştır | Mükerrer UID / fiziksel ID (BK, KR, kazık …) uyarısı yok; Kimlik Onarımı kopyaları "onarılacak" göstermez | 09.11.2026 | aynı | Kısmen: gönderilen Model Kontrolü metninde HATA satırı yok, yalnız 4 Kanal Cebi uyarısı (kaynak HB-YD-02-A2/A3 ile kopyaları BK-003/BK-004 aynı durum). Metin yalnız bulgu satırları, özet sayıları yok. Kopya kazıklar P-027…P-052, BK-001…BK-005, her BK kendi kopya kazıklarına bağlı; mükerrer kazık ID yok. Kimlik Onarımı denenmedi | — |
| N-39 | K1 kayıt | Modeli kaydet, SketchUp'ı kapatıp aç; Keşif ve Aks Yöneticisi'ni aç | Kopya yapılar, kodlar, görünen adlar ve yerleşimler duruyor; Keşif N-35 ile aynı | | | | |
| N-40 | 32/3 | Kopya yapıda kronmanı seç → Revize / yeniden çiz | Kronman kopyanın kendi yerinde kalır (kaynağın yerine çizilmez) | | | | |
| N-41 | 32/4, 33/2 | BK içinde ve kökte aksesuar (usturmaça) olan yapıyı kopyala | Aksesuarlar kopyaya geçmez; iletide "yerleştirilmiş N aksesuar kopyalanmadı" ve "Aksesuar çizelgesi ve aksesuar ankraj donatısı çoğalmaz"; Keşif aksesuar satırı değişmez | | | | |
| N-42 | karar 9 | Component prekastlı yapıyı kopyala; sonra kopyadaki bir Component prekasta donatı ekle | Onay ve sonuç iletisinde "Component prekast tipleri yapılar arasında ortak…" uyarısı; donatı aynı tipteki kaynak prekastta da görünür (bilinen, kararla kabul) | | | | |
| N-43 | 32/8 | Kopyadan sonra pencere yenilenmeden önceki Aks Yöneticisi'nde (yenilenmezse) Projeyi Kaydet'e bas | "pencerenin bilgileri eski … yeniden açın" uyarısı, kayıt yapılmaz; yeniden açınca kopya yapılar listede | | | | |
| N-44 | ret | (a) Aks Yöneticisi'nde aks ekleyip kaydetmeden Yapıyı Kopyala; (b) mevcut bir kodu yaz; (c) jet grout satırına elle ilerleme girilmiş yapıyı kopyala | Her birinde neden listesi, "işlem açılmadı, model değişmedi"; Ctrl+Z geçmişinde yeni işlem yok | | | | |
| N-45 | 32/7 | BK sayfası → Yeni Yapı: önce var olan kodla (ret), sonra yeni kodla; Ctrl+Z | Ret iletisi, model değişmez; yeni yapı tek Ctrl+Z ile kalkar | | | | |
| N-46 | perf | 10 kopya (gerçek boyutlu yapı) yap; süreyi not et | Tamamlanır; süre kaydedilir (eşik yok; sahte modelde 50 × 391 öğe ≈ 6 s) | | | | |

| N-47 | 34/1, 32/2 | İçinde iç içe Group'lar (BK donatı / menfez, kronman segmentleri) ve bir Component BK bulunan yapıyı kopyala; kopyada bir segmentin / donatının özelliğini aç | Kopya tamamlanır (konum uyuşmazlığı iptali yok); her iç öğenin özellikleri kaynaktaki karşılığıyla aynı (yer değiştirmemiş) | | | | |

Ek (09.11.2026, `96c194d`): §12 14 satır (N-34 … N-47); yeni toplam 136.
