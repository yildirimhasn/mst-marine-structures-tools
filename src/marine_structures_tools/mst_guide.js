/* v0.47.2 — Kullanma Kılavuzu: bütün sistem adım adım. Ana pencerede "Araçlar → Kullanma Kılavuzu" sayfası
   ve Ayarlar sayfasının başında bağlantı. Yalnız metin; modele hiçbir şey yazmaz. */
(function(){
'use strict';
function $(s,r){return (r||document).querySelector(s);}
function $$(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s));}

/* Bölümler: id · başlık · grup · açılacak adım (mstOpenStep anahtarı) · içerik */
var G=[
{id:'g-start',grp:'Başlarken',t:'Eklentiyi açmak ve ekran düzeni',body:
'<p><b>Açmak:</b> SketchUp menüsünde <b>Extensions → Deniz Yapıları Araçları (MST) → MST Aç</b> ya da <b>Marine Structures</b> adlı araç çubuğundaki <b>MST Aç</b> düğmesi. Bütün sayfalar <b>tek pencerede</b> açılır.</p>'+
'<ol><li><b>Soldaki menü</b> iki bölümdür: <b>İŞ AKIŞI</b> (1–10 numaralı adımlar, çalışma sırası) ve <b>ARAÇLAR</b> (Eleman Düzenle, Aksesuarlar, Model Bakımı, Ayarlar, bu kılavuz). Alt sayfalar (Fore Kazık, Jet Grout, Dolgu / Taş, Revizyonlar, Hakediş) ilgili adımın altında girintili durur.</li>'+
'<li><b>Sayfa başlığı</b> her sayfada aynıdır: adım numarası, sayfanın ne işe yaradığı, adımın durumu ve <b>Sonraki adım →</b> düğmesi.</li>'+
'<li><b>Sayfa içi adımlar:</b> uzun sayfaların üstünde numaralı sekmeler vardır (ör. Kazık: Kesit ve Malzeme → Detaylar ve Donatı → Yerleşim ve Kotlar). <b>Tümü</b> sekmesi bütün paneli birlikte gösterir.</li>'+
'<li><b>İşlemler çubuğu</b> (sayfanın altında sabit): <b>↻ Seçiliyi Oku</b> (modelde seçili elemanı forma yükler) · <b>👁 Önizle</b> (değiştirmeden gösterir) · <b>✓ Oluştur / Güncelle</b> (modeli değiştirir) · <b>⋯ Diğer işlemler</b> (sayfaya özel ek araçlar).</li></ol>'+
'<p><b>Durum işaretleri:</b> <span class="gd-ok">✓ tamam</span> · <span class="gd-warn">⚠ güncel değil / eksik var</span> · <span class="gd-bad">✗ yapılmamış</span>. Durumlar her sayfa açılışında modelden yeniden okunur.</p>'},
{id:'g-rules',grp:'Başlarken',t:'Temel kurallar',body:
'<ul><li><b>Kotlar mutlak kottur</b> (ör. BK alt kotu +4.20). Göreli değer girilmez.</li>'+
'<li><b>Her işlem tek Geri Al:</b> bir Oluştur / Güncelle / Uygula işlemi SketchUp\'ta tek adımda <b>Ctrl+Z</b> ile geri alınır.</li>'+
'<li><b>Önce önizle, sonra uygula:</b> modeli değiştiren toplu işlemler önce neyin değişeceğini gösterir, onay ister.</li>'+
'<li><b>Elemanlar BIM kimliği taşır:</b> kazık, BK, prekast, döşeme… her biri kendi tipini, yapısını (ANO), aksını ve metraj bilgisini üzerinde tutar. Grupları elle patlatmayın (Explode); bilgi kaybolur.</li>'+
'<li><b>Büyük değişiklik öncesi model kopyası</b> alın. Test menüleri (MST | … TESTİ) yalnız kopyada çalıştırılır.</li>'+
'<li><b>Tag\'ler</b> otomatik verilir (MST | KAZIK, MST | DONATI | YD-02 …). Görünürlüğü Tags panelinden açıp kapatın.</li></ul>'},
{id:'g-quick',grp:'Başlarken',t:'Hızlı başlangıç — sıfırdan bir yapı',body:
'<ol class="gd-steps"><li><b>Proje / Aks:</b> proje adı, sistem, yapı (ANO) ve X/Y aksları → <i>Aks Sistemini Kaydet</i>.</li>'+
'<li><b>Kazık:</b> kesit + detaylar → <i>Aktif Sistem / Yapı Gridini Yükle</i> → grid noktalarını seç → <i>Seçili Grid Kazıklarını Oluştur</i>.</li>'+
'<li><b>Başlık Kirişi:</b> BK tipi tanımla → <i>Akslara BK Tipi Ata</i> → <i>Aktif ANO Başlık Kirişlerini Oluştur</i>.</li>'+
'<li><b>Prekast:</b> iki komşu BK seç → tip ve dizilim → <i>Oluştur</i>.</li>'+
'<li><b>Döşeme:</b> kalınlık, tretuvar, baba kaideleri → <i>Oluştur</i>.</li>'+
'<li><b>Kronman / Dolgu</b> (gerekiyorsa).</li>'+
'<li><b>Donatı BIM:</b> BK ve döşemelerde donatıyı çiz; çizilmeyenler pursantajla hesaplanır.</li>'+
'<li><b>Model Kontrolü:</b> hata 0 olana kadar düzelt.</li>'+
'<li><b>Metraj:</b> kontrol et, Excel\'e al.</li>'+
'<li><b>Keşif / Hakediş:</b> poz listesi ve fiyatlar → keşif → ilerleme girişi → hakediş dönemi.</li></ol>'},

{id:'g-1',grp:'İş Akışı',step:'project',t:'1 · Proje / Aks',body:
'<p>Bütün elemanlar konumunu bu gridden alır. Pencere <b>Proje / Sistem / Yapı — Aks Yöneticisi</b> olarak açılır.</p>'+
'<ol><li><b>Proje Adı</b> ve <b>Sistem</b> (Dolfen / İskele / Rıhtım) seçilir → <i>Projeyi Kaydet</i>.</li>'+
'<li><b>Aktif Yapı:</b> <i>+ Yeni Yapı</i> ile yapı (ANO, ör. YD-02) eklenir; <i>Yapıyı Kopyala</i> / <i>Yapıyı Sil</i> buradadır.</li>'+
'<li><b>Yapı Yerleşim Zinciri:</b> yapının X ve Y konumu başka bir yapının aksına bağlanabilir (Referans Yapı, Referans Aks, Mesafe / Yön) → <i>X + Y Konumunu Kaydet</i>.</li>'+
'<li><b>Aks Sistemi:</b> X ve Y aksları tek tek (<i>+ X Aksı Ekle</i>) ya da düzenli (Önek, Adet, Aralık → <i>Düzenli Oluştur</i>) girilir → <i>Aks Sistemini Kaydet</i> → <i>Aksları Modelde Göster / Güncelle</i>.</li></ol>'+
'<p class="gd-note">Aks taşınırsa, kaydetmeden önce o aksa bağlı elemanlar listelenir ve onay istenir; iptal ederseniz hiçbir şey değişmez.</p>'},

{id:'g-2',grp:'İş Akışı',step:'pile',t:'2 · Kazık (çelik boru)',body:
'<p>Sayfanın üstünde iki mod vardır: <b>＋ Yeni Kazık Oluştur</b> ve <b>✎ Mevcut Kazığı Düzenle / Güncelle</b>.</p>'+
'<h4>Yeni kazık</h4><ol><li><b>Kesit ve Malzeme:</b> çap, et kalınlığı, boy, üst kot (mutlak), çelik sınıfı, kazık içi beton.</li>'+
'<li><b>Detaylar ve Donatı:</b> çember, tapa, ek, PE kaplama, foraj, kazık içi donatı.</li>'+
'<li><b>Yerleşim ve Kotlar:</b> <i>↳ Aktif Sistem / Yapı Gridini Yükle</i> → plan üzerinde noktaları seç → gerekiyorsa <b>Kazık Üst Kotları — Düşük BK Bölgeleri</b> → <i>▶ Seçili Grid Kazıklarını Oluştur</i>.</li></ol>'+
'<h4>Mevcut kazığı değiştirmek</h4><ol><li>Modelde kazık(lar)ı seç → <i>↻ Modelden Seçili Kazığı Yükle</i>.</li><li>Değeri değiştir → <i>👁 Hedefleri Önizle</i> (hangi kazık, ne değişecek).</li><li><i>✓ Mevcut Kazığı Güncelle</i>. Geometri, kot, detaylar, iç beton, tip ve metraj birlikte güncellenir; kazıkla taşınan BK cebi de düzeltilir.</li></ol>'+
'<p class="gd-note"><b>Kazık BK\'ya gömülüyorsa</b> üst kotu BK altının üstünde verin (ör. BK altı +4.20, kazık üstü +4.30). BK içinde kalan kazık hacmi BK betonundan kendiliğinden düşülür; kazık BK üstünü geçerse Model Kontrolü hata verir.</p>'},
{id:'g-2a',grp:'İş Akışı',step:'pile',sub:'Fore Kazık',t:'2a · Fore Kazık',body:
'<ol><li><b>Kazık tipi ve kesit:</b> çap, boy, beton sınıfı, muhafaza borusu (geçici / kalıcı).</li><li><b>Donatı ve imalat kapsamı:</b> donatı BIM ya da pursantaj.</li><li><b>Proje ve yerleşim:</b> grid noktalarına yerleştir.</li><li><b>Model metrajı</b> tip / ölçü ve çap / beton sınıfı bazında listelenir.</li></ol>'+
'<p class="gd-note">Fore kazığı Ölçekle (Scale) aracıyla ya da elle taşırsanız metraj kendiliğinden güncellenmez; değişikliği teknik formdan yapın.</p>'},
{id:'g-2b',grp:'İş Akışı',step:'pile',sub:'Jet Grout',t:'2b · Jet Grout',body:
'<ol><li><b>Kolon tanımı:</b> çap, uzunluk / kotlar, sarf değerleri (çimento, su vb.).</li><li>Modele yerleştir.</li><li><b>Modeldeki tipler ve miktarlar:</b> nominal zemin hacmi ve sarf, keşif satırları.</li></ol>'+
'<p class="gd-note">Hacim nominal silindir hacmidir; birbirine giren kolonların ortak hacmi düşülmez.</p>'},
{id:'g-3',grp:'İş Akışı',step:'beam',t:'3 · Başlık Kirişi (BK)',body:
'<ol><li><b>Başlık Kirişi Tipleri:</b> genişlik, yükseklik, alt kot, başlangıç / son taşması, beton sınıfı → <i>＋ Yeni BK Tipi Ekle</i>.</li>'+
'<li><b>Usturmaça Dişi / Alt Kot Düşümü</b> ve <b>Kanal Prekastı</b> cebi tipe eklenir.</li>'+
'<li><b>Akslara BK Tipi Ata:</b> her aksın tipini seç → <i>▣ Aktif ANO Başlık Kirişlerini Oluştur</i>. BK, aksın kazıklarına oturur.</li>'+
'<li><b>Seçili BK\'yi Güncelle:</b> modelde BK seç → <i>↻ Modelden Seçili BK\'yi Ortak Forma Yükle</i> → değiştir → <i>▤ Seçili BK\'lara Uygula (önizleme)</i> → <i>✓ Seçili Fiziksel BK\'yi Güncelle</i>.</li>'+
'<li><b>Donatı BIM:</b> BK seç → <i>▦ Seçili BK için Donatı BIM Oluştur / Yenile</i>. Çizilen donatı metraja tonaj olarak girer. Detaylı donatı <b>yalnız eklentinin çizdiği BK\'larda</b> çizilir; <b>Mevcut Elemanı Tanıt</b> ile tanıtılan (kanallı, boşluklu, özel biçimli) BK\'larda motor boşlukları bilemediği için çizilmez, donatı pursantajla hesaplanır.</li><li><b>Otomatik Donatı (tanıtılan BK, proje çizimi gerekmez):</b> BK\'yı seçin → <b>Extensions → Deniz Yapıları Araçları (MST) → Otomatik Donatı (seçili BK)…</b> (Model Bakımı → Donatı). Önce çap / aralık / pas payı ekranı gelir (her BK için; son değerler hatırlanır). Eklenti BK\'nın yüzeylerinden 5 cm ızgaralı kot haritası çıkarır; kanal tabanlarını, geniş blokları, ince duvarları ve başlıklarını, kanal kenarı yüzlerini ve dış yüzleri kendisi tanır. Kurallar: alt ağ + enine kapalı etriye çifti, ara ağ, her açık üst yüzeyde iki yönlü ağ (yüksek betona kenetlenir, kenarda U bacak), kanal kenarlarında C + yatay, dış yüzlerde C + gövde, duvarlarda etriye + yatay + filiz; 12 m stok, 50Ø bindirme (Donatı Ayarları\'ndan), komşu çubuklarda şaşırtmalı; bükümler oval (etriye 4Ø, Ø≤16 6Ø, Ø>16 7Ø); tonaj açınım boyundan. Pas payı varsayılanı Donatı Ayarları → BK. Üstü düz (kanalsız) BK\'da <b>iç içe etriye</b> kol sayısıyla (4 kol = dış + 1 iç). Çakışan çubuk ≤ 9 cm kaydırılır, betona sığmayan çizilmez. Önizlemede bölge bölge çubuk / tonaj yazar; onaylayınca bölge grupları hâlinde çizilir (tek Geri Al). Tonaj çizilen çubuklardandır. BK-9 ile sınama: otomatik %92.5 (Ø14 %101, Ø32 %92); projenin ek pozları (uç yatay U, ek kancalar) kurallarda yok.</li><li><b>Çizimden Donatı (tanıtılan BK):</b> projenin donatı çizimi pakete işlenmişse (şu an <b>BK-9</b>) BK\'yı seçin → <b>Extensions → Deniz Yapıları Araçları (MST) → Çizimden Donatı (seçili BK)…</b> (Model Bakımı → Donatı\'da da var). Eklenti önce BK\'nın ölçüsünü ve kanallarını çizimle karşılaştırır, BK\'nın hangi yönde durduğunu bulur, her çubuğun betonun içinde kaldığını (kanala girmediğini) denetler ve poz poz tabloyu gösterir (model değişmez). Onaylayınca pozlar tek tek 3B çizilir (poz başına ayrı grup, tek Geri Al). Metraj <b>donatı tablosunun satırlarından</b> gelir, pursantaj kullanılmaz. Parapet donatısı ayrı çizimde olduğundan BK katısında parapet yoksa parapet payı düşülür (BK-9: 76.935 − 0.868 = <b>76.067 t</b>); parapet BK katısında varsa dahil kalır. Silmek: <i>Çizimden Donatıyı Sil</i> (pursantaja döner).</li></ol>'+
'<p class="gd-note"><b>Kalıp:</b> kazıkların BK altına girdiği daire alanları kalıptan düşülür (brüt / kazık kesintisi / net). <b>Beton:</b> kazık BK içine giriyorsa gömülü hacim düşülür; raporda "BK Betonu — Kazık Gömülme Düşümü" tablosu çıkar.</p>'},
{id:'g-4',grp:'İş Akışı',step:'precast',t:'4 · Prekast',body:
'<p>Sekmeler: <b>PD</b> (normal döşeme prekastı) · <b>PDÖ</b> (dişli / değişken) · <b>PV</b> (vinç) · <b>PK</b> (kanal).</p>'+
'<ol><li><b>Prekast Tipleri:</b> tip kütüphanesinden seç ya da yeni tip ekle.</li>'+
'<li><b>Yerleşim:</b> modelde iki komşu BK seç → Y yönünde dizilim, parametreler → <b>Genişlik Kontrolü</b> uyumu → <i>✓ Oluştur</i>.</li>'+
'<li><b>Kanal prekastı (PK):</b> BK seç → <i>↻ Seçili BK\'yı Oku</i> → kanal hattı → oluştur. BK\'da kanal cebi yoksa <i>⋯ Diğer işlemler</i> içinden kanaldan BK cebi açılır.</li>'+
'<li><b>Kalıp Yüzleri:</b> hangi yüzlerin kalıp sayılacağı.</li></ol>'},
{id:'g-5',grp:'İş Akışı',step:'deck',t:'5 · Döşeme',body:
'<ol><li><b>Döşeme Tanımı:</b> ID, toplam kalınlık, beton sınıfı, prekast oturma payı.</li><li><b>Bordür / Tretuvar</b> ve <b>Baba Kaideleri</b> (taraf ve akslar).</li><li><b>Kaplama</b> (topping) kalınlığı ve sınıfı.</li><li><i>👁 Önizle</i> → <i>✓ Oluştur</i>.</li><li><b>Döşeme Donatı BIM:</b> üst / alt hasır, BK üstü dolgu, tretuvar, baba.</li></ol>'+
'<p class="gd-note">BK değişince döşeme kendini yeniler. Elle güncellemek için döşemeyi seçip <i>🔄 Seçili Döşemeyi Güncelle</i>.</p>'},
{id:'g-6',grp:'İş Akışı',step:'crown',t:'6 · Kronman / Dolgu (isteğe bağlı)',body:
'<h4>Kronman</h4><ol><li><b>Kesit Tipleri:</b> Tip A / Tip B geometrisi.</li><li><b>Aks ve İstasyonlar:</b> proje / aks ve istasyon aralıkları.</li><li><b>Kalıp ve Renk</b> → <i>✓ Oluştur</i>. Değiştirmek için seç → <i>↻ Seçiliyi Oku</i>.</li></ol>'+
'<h4>Dolgu / Taş</h4><p>Önce hesap yöntemi seçilir:</p><ul><li><b>Alternatif-01:</b> kesit alanlarından ortalama uç alan (AEA) kübajı — malzeme kütüphanesi, kesit kütüphanesi, istasyon zinciri.</li><li><b>Alternatif-02:</b> aks + batimetri (taban yüzeyi) + tip kesit; kübaj modelden hesaplanır.</li><li><b>Alternatif-02 · Özel Katı:</b> net kapalı katıları malzemeye bağla, hacim katıdan okunur.</li></ul><p>Seçilen yöntemin hacim / tonajı Metraj ve Keşif\'e geçer.</p>'},
{id:'g-7',grp:'İş Akışı',step:'rebar',t:'7 · Donatı BIM',body:
'<ul><li>Donatının <b>tek kaynağı</b> vardır: eleman için donatı çizildiyse (BIM) modellenen tonaj, çizilmediyse <b>beton × pursantaj</b> (Ayarlar → Donatı Pursantajları).</li>'+
'<li>Bu sayfa hangi elemanda BIM, hangisinde pursantaj kullanıldığını gösterir. Metraj, keşif ve hakediş aynı değeri kullanır.</li>'+
'<li><b>Renkler:</b> her çap kendi rengindedir (Ø12, Ø16, Ø20 …). Eski donatıyı renklendirmek: BK sayfasında <i>🎨 Mevcut Donatıları Çapa Göre Renklendir</i>.</li>'+
'<li><b>Tag\'ler:</b> donatı grupları yapıya göre <b>MST | DONATI | &lt;ANO&gt;</b> Tag\'indedir. Eski donatı için <i>Donatı Tag\'lerini Güncelle</i> ya da araç çubuğunda <i>MST Tag\'lerini Güncelle</i>.</li></ul>'},
{id:'g-8',grp:'İş Akışı',step:'audit',t:'8 · Model Kontrolü',body:
'<ol><li>Kontrolü çalıştır: hatalar (✗) ve uyarılar (⚠) listelenir.</li><li>Satır seçince ilgili elemanlar modelde seçilir ve gösterilir.</li><li>Otomatik düzeltilebilenler için <b>Güvenli Onarım</b> (Model Bakımı).</li><li>Sonuç iş akışındaki 8. adımın durumuna yazılır.</li></ol>'+
'<p class="gd-note">Teslimden ve hakediş kaydından önce <b>hata 0</b> olmalı. Uyarılar bilgi amaçlıdır, tek tek okuyun.</p>'},
{id:'g-9',grp:'İş Akışı',step:'qto',t:'9 · Metraj',body:
'<ol><li><i>↻ Metrajı Yenile</i>: beton, kalıp, donatı, çelik ve dolgu tek hesap motorundan okunur.</li><li>Sekmeler: <b>Özet</b> · <b>Kazık</b> · <b>Dolgu / Taş</b> · <b>Detay Raporları</b>.</li><li><i>▦ Detaylı Metraj Raporu</i>: disiplin bazında bütün tablolar.</li><li><i>⇩ Excel\'e Aktar</i>: aynı rapor çok sayfalı Excel olarak.</li></ol>'},
{id:'g-10',grp:'İş Akışı',step:'boq',t:'10 · Keşif / Hakediş',body:
'<p>Sayfa adımları: <b>Poz Listesi → Keşif → Para Birimi</b>.</p>'+
'<h4>Poz Listesi</h4><ol><li>Her satır: Etkin · Poz No · İşin Tanımı · Birim · Varsayılan Fiyat · <b>Miktar Kaynağı</b> (modelden hangi miktar) · Elle Miktar.</li>'+
'<li><i>＋ Poz</i> modelden miktarlı poz; <i>＋ Elle Miktarlı Poz</i> modelde karşılığı olmayan iş (şantiye tesisi vb.).</li>'+
'<li>Pozu silmek yerine <b>Etkin</b> işaretini kaldırabilirsiniz. Aynı miktar kaynağı iki pozda kullanılamaz.</li>'+
'<li><b>Fiyat boş = FİYAT YOK</b> (0 sayılmaz). Kütüphane fiyatlı pozlarda (foraj, kaplama, kronman, eşleştirilen pozlar) fiyat listeden girilmez.</li>'+
'<li><i>Poz Listesini Kaydet</i> (tek Geri Al). <i>⇩ Dışa Aktar</i> / <i>⇪ İçe Aktar</i> ile JSON olarak başka projeye taşınır.</li></ol>'+
'<h4>Keşif</h4><ul><li><i>↻ Modelden Yenile</i>: model miktarı × birim fiyat.</li><li><i>⇩ Keşif Cetveli (Excel)</i>: formüllü keşif cetveli + poz metrajları (eleman bazında) + bilgi sayfası.</li><li><i>⋯ Diğer işlemler</i>: <b>Keşif Kütüphanesi</b> (birim fiyat arşivi) ve <b>ÖBF – Model Miktarı Eşleştirme</b>.</li><li>Kazık pozları çapa / kesite göre <b>ayrı poz</b> olarak gösterilebilir (kazık poz gruplaması).</li></ul>'+
'<h4>Para Birimi ve Keşif Ayarları</h4><ul><li>Sözleşme para birimi (USD / EUR / TRY), <b>1 USD / 1 EUR = … TL</b> kurları, fiyat tarihi. Kütüphane (USD) fiyatları kurla çevrilir.</li><li><b>Betonu sınıfa göre ayrı pozlarda göster:</b> ÖBF-005/C30/37, ÖBF-005/C35/45 …; toplam değişmez.</li></ul>'+
'<p class="gd-note">Kaydedilmiş hakediş varsa beton sınıf ayrımı ve kazık poz gruplaması değiştirilemez (önceki ödenen miktarlar poz bazında eşleşmez).</p>'},
{id:'g-10a',grp:'İş Akışı',step:'boq',sub:'Revizyonlar',t:'10a · Revizyonlar',body:
'<ol><li><i>Anlık Kayıt Oluştur</i>: modelin o anki BIM / metraj durumu ve keşfi kaydedilir (Rev.01, Rev.02 …).</li><li>Sonraki her açılışta güncel model son anlık kayıt ile karşılaştırılır: <b>yeni / değişen / silinen</b> elemanlar, beton / donatı / kalıp / çelik farkı.</li><li><b>Keşif Farkı</b> kartı poz bazında miktar ve tutar değişimini gösterir.</li></ol>'},
{id:'g-10b',grp:'İş Akışı',step:'boq',sub:'Hakediş / İlerleme',t:'10b · Hakediş / İlerleme',body:
'<p>Sayfa adımları: <b>İlerleme Girişi → Hakediş Cetveli → İcmal ve Kesintiler</b>.</p>'+
'<h4>Bir kez: sözleşme</h4><ol><li><b>Sözleşme ve Kesintiler:</b> tip (Özel / Kamu), KDV %, kesinti listesi (ad, taban: iş tutarı ya da KDV, oran). <i>Seçili tipin şablonunu yükle</i> örnek oranları getirir — sözleşmenizle kontrol edin → <i>Sözleşmeyi Kaydet</i>.</li></ol>'+
'<h4>Her dönem: ilerleme girişi</h4><ol><li>Modelde imal edilen elemanları seç (ör. çakılan kazıklar). Numarasını biliyorsanız <i>⌕ Numarayla Bul</i> (ör. P-56) kazığı bulup seçer.</li><li><i>↻ Seçimi Oku</i>: seçili elemanların girdiği iş kalemleri listelenir (onaylı % ve beyan %).</li><li>İş kalemlerini işaretle → <b>İlerleme %</b> → <b>Onaylı</b> (hakedişe girer) → <b>Tarih</b> → <i>Seçili Kalemlere Uygula</i> (tek Geri Al).</li><li>Onaysız giriş <b>beyan</b>dır; ödenmez ve verilmiş onayı düşürmez. Onay geçmişi tarihle saklanır.</li><li>Modelde karşılığı olmayan pozlar (mobilizasyon, elle pozlar) alttaki tabloda % ve onayla girilir.</li><li><i>Kaydı Sil</i> seçili elemanların o kalemdeki kaydını kaldırır.</li></ol>'+
'<h4>Modelde İlerleme Görünümü</h4><p>İş kalemi seç → <i>● Onaylıları Seç</i> / <i>● Kısmi / Beyan</i> / <i>● Başlanmamış</i> → <i>Yalnız Seçilileri Göster</i>; bitince <i>Hepsini Göster</i>.</p>'+
'<h4>Hakediş dönemi</h4><ol><li><b>Dönem sonu</b> tarihi: bu tarihe kadar onaylanan işler döneme girer.</li><li><b>Bu dönem fiyat farkı</b> (tutar) ve not.</li><li>Cetvel: sözleşme / önceki / bu dönem / kümülatif miktar ve tutar. İcmal: A iş tutarı · B fiyat farkı · C toplam · D KDV · E kesintiler · F ödenecek.</li><li><i>✓ Hakedişi Kaydet</i>. Önceki hakedişte ödenen bir miktar modelde azaldıysa (eleman silindi, poz pasif yapıldı) satır <b>eksi (alacak)</b> olarak gösterilir ve kaydetmeden önce sorulur.</li><li>Kayıtlı dönemler <b>Hakediş:</b> listesinden açılır (arşiv, değişmez); gerekirse <i>Hakedişi Sil</i>.</li><li><i>⇩ Hakediş Raporu (Excel)</i>: İcmal · Hakediş Cetveli · Onaylı Metraj (eleman bazında) · Bilgi.</li></ol>'},

{id:'g-t1',grp:'Araçlar',step:'editor',t:'Eleman Düzenle',body:'<ol><li>Modelde bir BIM elemanı seç → <i>↻ Seçiliyi Oku</i>.</li><li>Kimlik, organizasyon (proje / yapı / aks), geometri görünür.</li><li><b>Bağımlılık:</b> bu elemana bağlı elemanlar (ör. kazık → BK → döşeme).</li><li><b>Kontrollü Güncelleme</b> ile değiştir.</li></ol>'},
{id:'g-t2',grp:'Araçlar',step:'accessories',t:'Aksesuarlar',body:'<p>Baba, usturmaça, merdiven vb. ekipman çizelgesi; adetler keşfe aksesuar satırı olarak geçer.</p>'},
{id:'g-t3',grp:'Araçlar',step:'maint',t:'Model Bakımı',body:'<p>Eski menüdeki bütün araçlar tek sayfada, gruplu:</p><ul><li><b>Kontrol:</b> Model Kontrolü, Bağımlılık Motoru / Etki Analizi, BIM Veri Çekirdeği Raporu.</li><li><b>Onarım:</b> Güvenli Onarım, Döşeme BIM İlişkileri, BIM Kimlik Onarımı, Kazık Tip Kütüphanesi, Çember Et Kalınlığı kuralı, Kazık Boru Ağırlıkları, Kazık Organizasyonu, MST Tag\'leri.</li><li><b>Kütüphane:</b> Eleman Kütüphanesi, Keşif Kütüphanesi, ÖBF eşleştirme.</li><li><b>Kazık:</b> tekli düzenleyici, toplu kazık detay güncelleme.</li><li><b>Dışa Aktarım:</b> Detaylı Metraj Raporu, Excel, CSV.</li></ul><p class="gd-note">Onarımlar tek Geri Al\'dır; yine de önce model kopyası alın.</p>'},
{id:'g-t4',grp:'Araçlar',step:'settings',t:'Ayarlar',body:'<ul><li><b>Donatı Pursantajları (kg/m³):</b> donatısı çizilmeyen elemanlar için (kazık içi, BK, döşeme, prekastlar, kaplama, kronman …) → <i>Pursantajları Kaydet</i>.</li><li><b>Mevcut Elemanı Tanıt:</b> eklenti dışında çizilmiş bir Group / Component\'i seç → tip ve bilgilerini gir → <i>＋ Seçili Elemanı Tanıt</i>. Artık metraja girer. <i>✎ Eleman Bilgisini Düzenle</i> / <i>× Tanımı Kaldır</i>.</li></ul>'},

{id:'g-t5',grp:'Araçlar',t:'Kazık numaraları ve Numarayla Bul',body:
'<h4>Kazık numaralarını modelde göstermek</h4><ol><li>Araç çubuğunda <b>Kazık Numaraları</b> düğmesi ya da <b>Extensions → Deniz Yapıları Araçları (MST) → Kazık Numaralarını Göster / Güncelle</b> (Model Bakımı → Görünüm\'de de var).</li>'+
'<li>Her kazığın numarası (P-001, P-056 …) kazığın tam plan konumunda, yapının üstüne <b>yatay, sabit boyda</b> yazılır (BK / döşeme üst kotunun 5 cm üstü). <b>Üstten (plan) bakınca</b> bütün numaralar okunur; yaklaşınca büyür, uzaklaşınca küçülür, döndürünce yerinden kaymaz. Yazı boyu kazık aralığına göre 0.25–0.80 m seçilir.</li>'+
'<li>Aynı numara iki yapıda varsa yapı adı da yazılır (ör. <b>BD-01 · P-001</b>).</li>'+
'<li>Yazılar <b>MST | ETİKET | KAZIK</b> Tag\'indedir: Tags panelinden gizle / göster.</li>'+
'<li>Numaralar açıkken eklentiyle kazık oluşturup güncelleyince ve Proje / Aks\'ta aks ya da yapı taşıyınca <b>kendiliğinden yenilenir</b>. Kazığı elle (SketchUp araçlarıyla) silip taşıdıysanız <i>Göster / Güncelle</i>\'ye bir kez basın. Tamamen silmek için <i>Kazık Numaralarını Kaldır</i>.</li></ol>'+
'<p class="gd-note">Numaralar ayrı bir <b>MST Kazık Numaraları</b> grubundadır; hiçbir elemanın içine girmez ve eleman sayılmaz: beton, kalıp, çelik ve hiçbir metraj değişmez. Ekleme ve kaldırma tek Geri Al\'dır.</p>'+
'<h4>Numarayla Bul</h4><ol><li>Araç çubuğunda <b>Numarayla Bul</b> ya da menüde <b>Numarayla Bul…</b>.</li><li>Numarayı yazın: <b>P-56</b>, <b>p56</b> ya da <b>P-056</b> aynıdır. BK, prekast, döşeme numaraları da aranır.</li><li>Eleman modelde <b>seçilir ve ekrana getirilir</b>. Birden fazla bulunursa hepsi seçilir ve listelenir.</li></ol>'+
'<p>Hakediş sayfasında <i>⌕ Numarayla Bul</i>: bulunan eleman seçilir ve iş kalemleri doğrudan listeye okunur.</p>'},
{id:'g-t6',grp:'Araçlar',t:'PE kaplama görünümü',body:
'<ol><li>Kazıkta PE kaplama <b>Kazık → Detaylar ve Donatı → Polietilen Kaplama = Var</b> ve <b>PE Kaplama Boyu / Kazık (m)</b> ile tanımlanır.</li>'+
'<li>Araç çubuğunda <b>PE Kaplama Görünümü</b> ya da <b>Extensions → Deniz Yapıları Araçları (MST) → PE Kaplama Görünümünü Göster / Güncelle</b> (Model Bakımı → Görünüm\'de de var).</li>'+
'<li>PE kaplamalı bölüm, <b>PE üst kotundan aşağı PE boyu kadar</b> farklı renkte (koyu yeşil) görünür. PE üst kotu tanımlı değilse kazık başından başlar. Eğik kazıkta eğim boyunca.</li>'+'<li><b>PE üst kotu:</b> <b>Extensions → Deniz Yapıları Araçları (MST) → PE Üst Kotunu Ayarla…</b> (Model Bakımı → Görünüm). Seçili kazıklara ya da PE\'li bütün kazıklara <i>Kazık başı</i> veya <i>Belirli kot</i> (mutlak, ör. +2.50) verilir. Kot kazık başının üstünde ya da kazık ucunun altında olamaz.</li>'+
'<li>Rengi değiştirmek: SketchUp <b>Materials</b> (malzemeler) panelinde <b>MST PE Kaplama</b> malzemesini düzenleyin.</li>'+
'<li>Görünüm açıkken kazık oluşturup güncelleyince ve aks / yapı taşıyınca kendiliğinden yenilenir. Kazığı elle silip taşıdıysanız yeniden <i>Göster / Güncelle</i>. Gizlemek: Tags → <b>MST | GÖRÜNÜM | PE KAPLAMA</b>; silmek: <i>PE Kaplama Görünümünü Kaldır</i>.</li></ol>'+
'<p class="gd-note">Renkli kılıf yalnız görünümdür: ayrı bir <b>MST PE Kaplama Görünümü</b> grubundadır, kazığın içine girmez, eleman sayılmaz. Kazık geometrisi ve hiçbir metraj (PE m² dahil, π·D·L) değişmez; PE üst kotu yalnız renkli bölümün yerini belirler.</p>'},
{id:'g-t7',grp:'Araçlar',step:'rebar',sub:'Donatı araçları',t:'Donatı ayarları, bükme listesi, kesit, revizyon, çakışma',body:
'<ul><li><b>Donatı Ayarları (proje):</b> pas payı BK / döşeme / prekast ayrı ayrı (50 veya 75 mm, başka değer de girilebilir), bindirme boyu (varsayılan 50Ø) ve <b>şaşırtma</b> (komşu çubuklarda ekler 1.3 × bindirme kaydırılır; bir kesitte en çok yarısı eklenir). Donatı sayfası → <i>⚙ Donatı Ayarları</i>.</li>'+
'<li><b>Donatıyı Göster / Gizle:</b> bütün 3B donatı <b>MST | DONATI | …</b> tag\'lerindedir ve <b>varsayılan gizlidir</b> (model hafif kalsın). Tek düğmeyle açılır / kapanır; metraj ve hakediş etkilenmez.</li>'+
'<li><b>Donatı metrajı çap çap:</b> Donatı sayfasında her çap ayrı satır (Ø14 … t, Ø32 … t); hakediş (Keşif ÖBF-004) <b>tek poz</b> kalır. Pursantajlı elemanlar “Ø ayrımsız” satırındadır.</li>'+
'<li><b>Bükme Listesi + Kesim Planı:</b> seçili (yoksa bütün) 3B donatılı elemanlardan Excel (Bükme Listesi, Çap Özeti, Kesim Planı) ve krokili HTML. Kesim planı 12 m stoktan en iyi uyumla kesimi, sipariş tonajını ve fire yüzdesini verir.</li>'+
'<li><b>Donatı Kesiti:</b> BK seç → BK boyunca konum gir → 2B kesit (beton çizgisi, kesilen çubuklar çapa göre renkli, düzlemdeki etriye / C\'ler).</li>'+
'<li><b>Revizyon Karşılaştırması:</b> donatı her yeniden çizildiğinde (veya silindiğinde) öncekisi saklanır (son 10). Elemanı seç → hangi önceki donatıyla karşılaştırılacağını seç → poz poz ve çap çap fark.</li>'+
'<li><b>Elemanlar Arası Çakışma:</b> farklı elemanların 3B donatıları birbirine giriyor mu (ör. prekast ucu BK donatısına). İstenirse çakışanlar kırmızı boyanır; <i>Çakışma Renklerini Temizle</i> geri alır.</li>'+
'<li><b>Sehpa:</b> döşeme donatı BIM\'inde ve dolfen başlığında (Π: alt hasıra oturur, üst hasırı taşır; Ø14 / 100 cm varsayılan). İskele / rıhtım BK\'larında sehpa yoktur.</li></ul>'},
{id:'g-t8',grp:'Araçlar',t:'İş programı',body:
'<ol><li>Model Bakımı → <b>İş Programı → İş Programı Oluştur</b> (ya da Extensions menüsü). Faaliyetler modelden: kazık çakımı, kazık içi, BK, prekast üretimi ve montajı, döşeme, tretuvar / kronman / kaplama; miktarlar metrajdan.</li>'+
'<li>Süre = miktar / verim. Sıra: kazık → kazık içi → BK → bekleme → prekast → döşeme → bitiş işleri; ekip / platform / vinç sayısıyla kaynak kısıtlı. Takvim: haftalık çalışma günü ve hava / deniz kaybı (%).</li>'+
'<li><b>İş Programı Ayarları:</b> verimlerin hepsi değiştirilebilir; her değerin yanında kaynağı yazar (tahmin / proje / yayın). Kendi saha verinizle güncelleyin.</li>'+
'<li>Çıktı: Gantt (HTML), Excel (Faaliyetler, Haftalık İhtiyaç, Aylık Hakediş, Parametreler); haftalık beton / donatı / kazık / prekast / ekip ve kişi; keşif birim fiyatlarıyla aylık hakediş tahmini.</li>'+
'<li><b>4D Görünüm:</b> elemanları bittiği aya göre renklendirir ya da seçilen haftadaki durumu gösterir (biten yeşil, süren sarı, başlamamış gizli). <i>4D Temizle</i> eski hâline döndürür.</li></ol>'},
{id:'g-t9',grp:'Araçlar',t:'Proje paftaları',body:
'<p>Model Bakımı → <b>Proje</b> grubu ve Extensions → Deniz Yapıları Araçları (MST) → <b>Proje Paftaları</b>. Hepsi önizleme gösterir, tek Geri Al\'dır.</p><ul>'+
'<li><b>A-Çerçeve Eğik Kazık Çiftleri:</b> aks, çift aralığı, kafa aralığı, eğim (ör. 1/6), enine / boyuna düzlem, A (uçlar açılır) / V (uçlar birleşir). Kazıklar arası en küçük açıklık ve çakışma önizlemede yazılır. Kazık özellikleri son kazık formundan gelir.</li>'+
'<li><b>Kazık Dispozisyonu — DXF:</b> paftadaki kazık daireleri (katman adında "kazık" / "pile"), çap katman adından (ör. 1066.8), kazık no yazısı, eğik kazık açısı yazısı. Birim kendiliğinden (cm / mm / m). Başlangıç: sol alt kazık / en küçük nolu kazık / çizim orijini, sonra kaydır ve döndür. Eğim paftada yoksa tek bir oran girilir; ok yönü (alt uç / kafa) çakışmaya bakılarak seçilir. Elle yerleşim eskisi gibi Kazık sayfasında.</li>'+
'<li><b>Kazık Filizini BK\'ya Göre Ayarla:</b> donatı kafesi filizi = BK üstü − BK pas payı − üst ağ payı.</li>'+
'<li><b>Vinç / Boylama Kirişi:</b> iki BK seç; VK / BBK BK\'lara dik, BK yüzünde biter. Alın kalıbı yok; BK\'nın o yüzündeki kalıp temas alanı kadar düşülür. Donatıyı BK donatı panelinden çiz: boyuna çubuklar BK\'ya bindirme boyu (×Ø) kadar girer. VK\'da ray tipi (A45 … A150, MRS, QU) ve klips aralığı → keşifte ray kg ve klips adedi (ÖBF eşleştirilir).</li>'+
'<li><b>Menfez Sac Kutusu:</b> seçili BK\'da kutu (konum, boy, en, alt kot, yükseklik, sac t). Boşluk BK betonundan, delinen yüzlerin kalıbından düşülür; sac ağırlığı keşfe. BK donatısı yeniden çizilince menfezden geçen çubuklar kesilir, altında / üstünde takviye, iki yanında takviye etriyesi.</li>'+
'<li><b>BK Taban Bölgesi:</b> BK boyunca aralıkta alçak taban (uç dişlerine ek; geçiş eğimli). Beton, kalıp, donatı (bölge alt donatısı, etriye bölge tabanına iner).</li>'+
'<li><b>Kademeli Döküm:</b> BK / dolfen başlığında 1. kademe yüksekliği; beton ve kalıp iki kademeye bölünür (toplam aynı), iş programında iki adım + bekleme. <i>Kademeli Döküm Metrajı</i> HTML döker.</li>'+
'<li><b>BK donatı panelinde yeni:</b> etriye düzeni (iç içe / yan yana dar), çiroz, bant (2. kademe) üst donatısı + şapka etriye (BK üst donatısı ara katman), pas payı eleman tipine göre (Donatı Ayarları), VK ankrajı, dolfen yan yüz gönyeli, menfez takviyesi, alçak taban donatısı.</li>'+
'<li><b>Prekast Donatısı (PD / PK):</b> alt boyuna BK\'ya giriş boyu kadar taşar (varsayılan 90 cm), üst boyuna uçları Ü, enine alt / üst U, 2. kademeye taşan etriye şeritleri, kaldırma kancaları; kanal prekastında dış + iç sarma U, taban enine, duvar boyuna, duvar şapkası. Component prekastta aynı tipteki bütün parçalar aynı donatıyı taşır; boy değişince yeniden çizilir.</li>'+
'<li><b>Paftadan Donatı Metrajı (DXF):</b> donatı paftasının bükme krokilerinden (poz balonu + "adet Ø" + "L =") poz tablosu; seçili elemanın metrajı paftadan ya da yalnız karşılaştırma (Ø bazında pafta ↔ model). 3B yerleşim parametrik araçlarla.</li>'+
'<li><b>Kaplama Eğimi:</b> en ince kalınlık + eğim % → ortalama kalınlık (tek yöne / sırttan iki yana).</li>'+
'<li><b>Malzeme Sınıfları:</b> proje donatı çeliği (B420C / B500C …) ve seçili elemanlara beton sınıfı / çelik; çap metrajında çelik sınıfı yazılır.</li>'+
'<li>Sehpa metrajda ayrı satır (Donatı Ayarları; toplam değişmez). Aksesuar çizelgesinde baba / halka / kanca / merdiven / kedi yolu için <i>ankraj donatısı (kg)</i> → döşeme donatısına eklenir.</li></ul>'},
{id:'g-faq',grp:'Sorun Giderme',t:'Sık sorulanlar',body:
'<dl class="gd-faq"><dt>Yanlış bir işlem yaptım.</dt><dd>SketchUp\'ta <b>Ctrl+Z</b>: her MST işlemi tek adımda geri alınır.</dd>'+
'<dt>Metraj / Keşif eski değeri gösteriyor.</dt><dd>Sayfadaki <i>↻ Yenile</i> düğmesine basın; değerler modelden yeniden okunur.</dd>'+
'<dt>Sayfa başlığında "durum okunuyor…" kaldı.</dt><dd>Sayfayı soldaki menüden yeniden açın. Sürmesi hâlinde Window → Ruby Console\'daki mesajı not edin.</dd>'+
'<dt>Bir elemanı Model Kontrolü hata gösteriyor.</dt><dd>Satırı seçin, eleman modelde seçilir. Çoğu sorun Model Bakımı → Güvenli Onarım ile düzelir.</dd>'+
'<dt>Tanıttığım BK\'da donatı kanalların içine / elemanın yanına oluştu.</dt><dd>Eski sürümde tanıtılan BK\'lara da detaylı donatı çiziliyordu; motor elemanı düz kutu sandığı için boşlukları doldurur ve yanlış yere koyardı. <b>Model Bakımı → Eklenti Dışı BK Donatısını Temizle</b> yanlış donatıyı siler ve pursantaja döndürür (tek Geri Al). Model Kontrolü bu durumu hata olarak gösterir.</dd>'+
'<dt>Proje donatı çizimi olmayan kanallı bir BK\'ya donatı.</dt><dd><b>Otomatik Donatı (seçili BK)</b>: kanalları ve duvarları kendisi tanır, çap ve aralıkları sorar. Proje çizimi eklentiye işlenmişse (BK-9 gibi) <b>Çizimden Donatı</b> daha doğrudur; ikisi birbirinin yerine geçer (tek donatı grubu).</dd>'+
'<dt>Tanıttığım BK\'nın donatısını proje çizimine göre istiyorum.</dt><dd>Çizim pakete işlenmişse (BK-9) <b>Çizimden Donatı (seçili BK)</b>. Ölçü ya da kanallar çizimle uyuşmazsa ya da tek bir çubuk bile kanala taşarsa çizmez, nedenini yazar. Tonaj donatı tablosundandır; tablonun alt toplamı satırlarla uyuşmuyorsa satırlar esas alınır. Pozlar paketler hâlinde eklenir: 1. paket alt donatı planı (poz 1–10), 2. paket üst donatı planı ve uç bölgeler, 3. paket duvar etriyeleri ve filizler: BK-9\'un 42 pozu tam. Parapet (+3.20) donatısı kendi çiziminde olduğu için 3B çizilmez (poz 43–47 ve poz 20 / 22 / 23\'ün 9\'ar çubuğu); önizlemede \"parapet çizimi\" yazar. Sorun yalnız bir paketteyse eklenti sorunsuz paketleri çizmeyi önerir ve BK geometrisini bir dosyaya kaydeder (incelemek için gönderin). Sonraki paket gelince aynı komut hepsini yeniden çizer.</dd>'+
'<dt>Bazı çubuklar çizimdeki yerinden birkaç cm kaymış.</dt><dd>Çizim iki boyutludur; aynı noktadan geçen çubuklar 3B\'de çakışır. Eklenti çakışan çubuğu kendi dağıtım ekseninde en çok 7.5 cm kaydırır (adet ve boy değişmez); kaç çubuğun kaydığı önizlemede yazar.</dd>'+
'<dt>Donatı görünmüyor.</dt><dd>Tags panelinde ilgili <b>MST | DONATI | &lt;yapı&gt;</b> Tag\'inin gözü açık mı bakın.</dd>'+
'<dt>Eski menüdeki bir aracı arıyorum.</dt><dd>Model Bakımı sayfasında ya da <b>Extensions → Deniz Yapıları Araçları (MST) → Tüm araçlar (eski menü)</b>.</dd>'+
'<dt>Hata bildirmek.</dt><dd>Window → Ruby Console\'daki mesajı ve mümkünse model kopyasını / dışa aktarılan dosyayı gönderin. Sürüm: konsolda <code>puts MAG::MarineStructuresTools::MST_BUILD</code>.</dd></dl>'},
{id:'g-terms',grp:'Sorun Giderme',t:'Kısaltmalar',body:
'<table class="gd-terms"><tr><td>ANO</td><td>Yapı (ör. YD-02, BD-01)</td></tr><tr><td>BK</td><td>Başlık kirişi</td></tr><tr><td>PD / PDÖ / PV / PK</td><td>Döşeme / dişli-değişken / vinç / kanal prekastı</td></tr><tr><td>KN</td><td>Kanal (kanal prekastı hattı ve BK cebi)</td></tr><tr><td>BIM</td><td>Eleman üzerinde kimlik ve metraj bilgisi taşıyan model</td></tr><tr><td>Metraj (eski adı QTO)</td><td>Model miktarları</td></tr><tr><td>Keşif (eski adı BOQ) / ÖBF</td><td>Keşif / birim fiyat pozları</td></tr><tr><td>AEA</td><td>Ortalama uç alan (dolgu kübajı)</td></tr><tr><td>Pursantaj</td><td>Beton m³ başına donatı kg</td></tr><tr><td>Beyan / Onay</td><td>Yüklenicinin bildirdiği ilerleme / hakedişe giren onaylı ilerleme</td></tr><tr><td>İcmal</td><td>Hakediş özeti: tutar, fiyat farkı, KDV, kesintiler, ödenecek</td></tr></table>'}
];

function navGuideBtn(){return $('.tabs button[data-flow="guide"]');}
function open(){var b=navGuideBtn();if(window.T&&b){T('guide',b);}else{$$('.page').forEach(function(p){p.classList.remove('on');});$('#guide').classList.add('on');}try{window.scrollTo(0,0);}catch(e){}}
window.mstOpenGuide=function(id){open();if(id){var s=document.getElementById(id);if(s){openSec(s,true);s.scrollIntoView({block:'start'});}}};

function openSec(s,on){s.classList.toggle('open',on);}
function build(){
 if($('#guide'))return;
 var ref=$('#settings')||$('.page');if(!ref)return;
 var groups=[];G.forEach(function(x){if(groups.indexOf(x.grp)<0)groups.push(x.grp);});
 var toc=groups.map(function(g){return '<div class="gd-tgrp">'+g+'</div>'+G.filter(function(x){return x.grp===g;}).map(function(x){return '<a href="#" data-gd="'+x.id+'">'+x.t+'</a>';}).join('');}).join('');
 var secs=G.map(function(x){
  var go=x.step?'<button type="button" class="secondary gd-go" data-step="'+x.step+'">Bu sayfayı aç →</button>':'';
  return '<section class="gd-sec" id="'+x.id+'" data-grp="'+x.grp+'"><h3 class="gd-h"><span>'+x.t+'</span><i>▸</i></h3><div class="gd-body">'+x.body+go+'</div></section>';}).join('');
 var d=document.createElement('div');d.id='guide';d.className='page';
 d.innerHTML='<div class="gd-wrap"><aside class="gd-toc"><input id="gdFind" type="search" placeholder="Kılavuzda ara…" autocomplete="off">'+toc+
  '<div class="gd-tbtns"><button type="button" class="secondary" id="gdAll">Hepsini aç</button><button type="button" class="secondary" id="gdNone">Hepsini kapat</button><button type="button" class="secondary" id="gdPrint">🖨 Yazdır</button></div></aside>'+
  '<div class="gd-main"><div class="gd-intro"><b>Kullanma Kılavuzu</b> — eklentiyi çalışma sırasıyla, adım adım anlatır. Soldan bir başlık seçin ya da arayın; <i>Bu sayfayı aç →</i> ilgili sayfaya götürür.</div>'+secs+
  '<div id="gdEmpty" class="gd-empty" style="display:none">Aramaya uyan bölüm yok.</div></div></div>';
 ref.parentNode.insertBefore(d,ref.nextSibling);
 $$('.gd-h',d).forEach(function(h){h.onclick=function(){var s=h.parentNode;openSec(s,!s.classList.contains('open'));};});
 $$('.gd-toc a',d).forEach(function(a){a.onclick=function(e){e.preventDefault();var s=document.getElementById(a.getAttribute('data-gd'));openSec(s,true);s.scrollIntoView({block:'start'});$$('.gd-toc a').forEach(function(x){x.classList.toggle('on',x===a);});};});
 $$('.gd-go',d).forEach(function(b){b.onclick=function(){if(window.mstOpenStep)mstOpenStep(b.getAttribute('data-step'));};});
 $('#gdAll',d).onclick=function(){$$('.gd-sec',d).forEach(function(s){openSec(s,true);});};
 $('#gdNone',d).onclick=function(){$$('.gd-sec',d).forEach(function(s){openSec(s,false);});};
 $('#gdPrint',d).onclick=function(){$$('.gd-sec',d).forEach(function(s){openSec(s,true);});document.body.classList.add('gd-printing');try{window.print();}catch(e){}setTimeout(function(){document.body.classList.remove('gd-printing');},500);};
 $('#gdFind',d).oninput=function(){
  var q=this.value.trim().toLocaleLowerCase('tr-TR'),n=0;
  $$('.gd-sec',d).forEach(function(s){var hit=!q||s.textContent.toLocaleLowerCase('tr-TR').indexOf(q)>=0;s.style.display=hit?'':'none';if(hit)n++;if(q&&hit)openSec(s,true);});
  $$('.gd-toc a',d).forEach(function(a){var s=document.getElementById(a.getAttribute('data-gd'));a.style.display=s.style.display;});
  $('#gdEmpty',d).style.display=n?'none':'';
 };
 /* ilk açılışta başlangıç bölümleri açık */
 ['g-start','g-quick'].forEach(function(id){openSec(document.getElementById(id),true);});
 /* Ayarlar sayfasının başına bağlantı */
 var st=$('#settings');
 if(st&&!$('#gdLink')){var c=document.createElement('section');c.id='gdLink';c.className='gd-link';
  c.innerHTML='<div><b>📘 Kullanma Kılavuzu</b><small>Bütün sistem, çalışma sırasıyla adım adım: proje ve akslardan hakedişe kadar.</small></div><button type="button" class="action" onclick="mstOpenGuide()">Kılavuzu Aç</button>';
  st.insertBefore(c,st.firstChild);}
}
window.MST_GUIDE=G;
build();
})();
