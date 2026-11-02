# 17 ADR-0515 ek H — Parti H karar kaydı (mst-mimar, 02.11.2026)
Kapsam: yalnız mst_tb1 0.51.5 hattı (kaynak eaaa858). SketchUp'ta kurulu MST v0.52.6 AUDIT CANDIDATE ayrı hattır; bu kararlar ona aktarılamaz. Durum: Önerildi (kullanıcı "Evet, Parti H yap"). Yeni attribute anahtarı yok. Uyarı türü kararlar metrajı değiştirmez; golden beklenen fark 0.

## H1 — K43 aks organizasyonu / elle aks
project_ano_axis_manager iki kez tanımlı (main.rb:9307 v0.20, 13073 v0.34.28; sonraki geçerli) → project_organize/project_manual_axis callback'leri yalnız eski HTML'de; auto_organize_project (9199) ve assign_manual_axis_to_selection (9278) erişilemez. Model Kontrolü metinleri (8398-8412) olmayan yolu gösteriyor. Veri riski: auto_organize_project ano/zone/project/active_ano/project_structure_revision'ı serbest metinle ezer; yeni yapı üyeliği (mst_pile_in_structure? 11558) ano'ya dayanıyor.
Öneri B + C (kullanıcı kararı — yeni yazma yolu): Uzantılar → "Tüm araçlar (eski menü)" → "Seçili Elemana Elle Aks Ata…" (UI.inputbox); yalnız axis ve axis_assignment='manual' yazar, project yalnız boşsa; ano/zone/active_ano yazılmaz; auto_organize_project bağlanmaz; 8412 metni bu maddeye yönlendirir. Undo: normal 'MST Elle Aks Ataması'; doğrulamalar start_operation öncesi (bugün 9283-9287 raise → işlem açılmadan abort; aynı kusur 9202-9203/9274). axis REVISION_PARAMETER_KEYS'te → revizyonda "değişti" (gerçek değişiklik). Metraj yok.

## H2 — K32 yedek CSS (ui.html:325)
Yalnız kazık özel ayarları kipi: inset öncesi top/right/bottom/left:0; min() öncesi width:96vw;max-width:720px; .pile-ov-grid grid-gap:10px. Flex gap için margin yedeği eklenmez (onaylı görünüm). Tarayıcı sürüm tablosu belge gerekli (ajan belleği: inset Chrome 87, min() 79, flex gap 84, grid gap 66). check_chromium64.rb CSS desenlerini taramıyor → test-paketleme ekler (inset:, min(, max(, clamp().

## H3 — Parti B ayrı önerileri
(a) mst_v50_beams.rb:488 rescue nil → ortak yardımcı mst_bk_set_net_formwork!(hb) (219-224 ve 488), hatada formwork_net_error (Model Kontrolü 8241 okur). 'MST VK/BBK' işlemi içinde.
(b) boq_pro.rb:371-377 send_boq: puts → warn + oturumda bir kez UI.messagebox("Keşif ekranı güncellenemedi: …").
(c) mst_schedule.rb:274 sp_last_json: yalnız değer farklıysa normal işlem 'MST İş Programı Kaydı'.
(d) mst_kd_last_json (mst_v50_piles.rb:459), mst_af_last_json (154), mst_vk_last_json (mst_v50_beams.rb:483): model özniteliği kalır; VK yazımı 484 işlemine alınır; kazık yazımı generate_layout'tan sonra yalnız made>0 ise transparent işlemle (hata olsa da commit). Önceye konmaz.
(e) U6: mst_active_ano_context (10908-10914) ve mst_active_structure_zone (10971-10977) yalnız değer farklıysa yazar. Ayrı risk (kullanıcı kararı, değiştirilmez): 10912 yöneticinin yazdığı yapı adını "ANO-01" ile ezebilir.
(f) Kaplama "PID-n" gösterimi: genel element_visible_id değişmez; yeni gösterim yardımcısı mst_display_id(e) (deck_topping → topping_id) yalnız önizleme/listelemede.

## H4 — A2 açıkları
K35 performansı: ölçmeden optimizasyon yok; ölçüm testi (n=50/500/2000, 1 ve 4 kaynak, kayıtlı/kayıtsız; çağrı sayısı + süre, çıktı birebir). Eşik kullanıcı kararı (öneri: Keşif yenilemesi >1 s).
Kazık yönelimi değişince BK açıklığı (doğrulandı): apply_selected_pile_orientations (602-639) BK pile_opening_area_m2 ve formwork_net_area_m2'yi güncellemiyor. Karar: aynı işlemde bağlı BK'lar için açıklık 1454/1520 formülüyle yeniden yazılır + H3a yardımcısıyla net kalıp; commit_with_dependencies. METRAJI DEĞİŞTİRİR (daire → elips 0,810732 → 0,821915 m²); golden fikstürüne yönelim değişimi eylemi.

## H5 — mstLoadCommonPileForm boş değer (ui.html:1705-1715)
Anahtar payload'da varsa ve '' / null ise alan boşaltılır; yoksa dokunulmaz. Yükleme öncesi driving_length_m.readOnly=false, sonrası updateDrivingAuto(). Ruby payload boş kotu anahtar olarak göndermiyorsa '' eklenir. Metrajı etkiler (yanlış çakım önlenir); SketchUp kabulü zorunlu.

## H6 — DXF birimi tanımsızken
Üç yol: kazık dispozisyonu sessiz "varsayılan (m)"; paftadan donatı "L=" soru ön seçimi m; 3B pafta soru ön seçimi cm. MST_DXF_INSUNITS altı değeri Autodesk $INSUNITS ile uyumlu (ajan belleği; belge ile doğrulanmalı); eksik kodlar soruya düşer.
Öneri C (kullanıcı kararı): ön seçimsiz "— seçin —", seçilmezse iptal; kazık yolunda son çare de soru. "L=" yazı birimi ↔ $INSUNITS kuralı: belge gerekli, değişmez. Soru işlemden önce.

## H7 — Menfez–gömülme kesişimi
mst_audit_v0515 K50 döngüsüne UYARI: kazık zarfı ile menfez kutusu planda ve düşeyde örtüşüyorsa "menfez ile kazık gömülmesi kesişiyor; kesişim hacmi BK betonundan iki kez düşülmüş olabilir". Hacim düzeltmesi yok (belge gerekli). Component BK/farklı kap denetlenmez. z referansı fikstürle doğrulanır.

## H8 — Triage dışı 08 maddeleri
R7: tanım yalnız satır numarası; iki aday (rockfill_boq_source.rb:80 başlık ↔ tablo; 42 sabit kesit '13') — belge gerekli, kod yok.
Sarmalayıcı Component ×N (doğrulandı): Keşif ×N, iz/hakediş .uniq ile 1 → Model Kontrolü UYARISI "Keşif N kez, hakediş 1 kez sayar; sarmalayıcıyı patlatın veya benzersiz yapın".
v034 tretuvar köşe bindirmesi (doğrulandı; yalnız eski modeller, ofset 0'da 4·w²·h): kayıtlı değer düzeltilmez (kullanıcı kararı); Model Kontrolü UYARISI tahmini bindirme hacmiyle.

## H9 — Metraj riskleri
Pursantajlı BK'da sehpa düşümü: kodla doğrulanmadı (mst_v50_chair_kg BIM değilse 0). İsteğe bağlı BİLGİ: rebar_mode≠bim_detail ve rebar_schedule_json'da CHAIR/SEHPA.
Döşeme + kaplama hasırı: DS3 BIM'de kaplama hasırı yok; drawing_detail/auto_detail döşeme + topping_enabled → BİLGİ "çizelge kaplama hasırını içeriyorsa kaplama donatısı ayrıca sayılıyor olabilir". Kural belge gerekli.

## H10 — K59 #3
Hata yolunda rebar_mode/rebar_t silinir (main.rb:12638-12639); revizyon imzası yalnız kaynak değişiminde değişir, tekrar eden hata idempotent; yanlış "değişti" üretilmez. Karar: ADR 02 §6 metni düzeltilir, kod değişmez. Önerilen metin: "hata durumunda pile_rebar_error yazılır, pile_cage_rebar_kg/_bar_count silinir; iç beton grubundan rebar_mode ve rebar_t silinir (yeni oluşturulmuş iç betonla aynı durum; add_pile_infill rebar_t yazmaz). Tonaj mst_pile_rebar_t ile pursantajdan hesaplanır; revizyon imzası yalnız kaynak değişiminde değişir." Test: başarı → hata → hata → başarı imzaları değişir/değişmez/değişir.

## İş bölümü
uygulayıcı (main.rb tek yazar): H1, H3a-f, H4b, H6, H7, H8, H9. arayüz (ui.html): H2, H5. dokümantasyon: H10 (02 §6 sapma kaydı), 07 §4.1. test-paketleme: H4a ölçümü, check_chromium64 CSS desenleri. Arayüz ve uygulayıcı paralel olabilir.
Golden: H4b; H5/H6 SketchUp CSV karşılaştırması. Diğerleri fark 0.
Kullanıcı kararı: H1 (B+C), H2 genel flex gap yedeği, H4a eşiği, H6 (C), H8 tretuvar kayıtlı değer, U6 active_ano çatışması.
Belge gerekli: H8 R7, H6 pafta birim standardı, H7 kesişim hacmi, H9 kaplama hasırı, H2 tarayıcı sürüm tablosu.
