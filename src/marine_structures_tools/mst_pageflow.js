/* v0.38 UI7 — sayfa içi iş akışı: her sayfa kendi adımlarına bölünür (1 · 2 · 3 …).
   Bölümler TAŞINMAZ; yalnız o adımda görünmeyenler gizlenir. Eşleşmeyen bölüm her zaman görünür kalır.
   "Tümü" ile eski tek sayfa görünüm geri gelir. */
(function(){
'use strict';
function $(s,r){return (r||document).querySelector(s);}
function $$(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s));}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
var SEL='section,.card,.pd-panel,.panel,.channel-card,.side-card,.qto-panel,.mst-flow-card';

/* Her sayfanın adımları: başlık metninde geçen ifadelerle bölümler eşlenir.
   pin  = her adımda görünen bölümler (mod seçimi, eylem kutusu)
   note = varsayılan kapalı bilgi kartları (başlığa tıklayınca açılır) */
var FLOWS={
 pile:{pin:['Çelik Boru Kazık Yönetimi'],note:['Mühendislik Notları'],steps:[
  {t:'Kesit ve Malzeme',h:'Çap, et kalınlığı, boy, üst kot, çelik sınıfı, iç beton',m:['Kazık Tanımı','Mevcut Kazık — İmalat']},
  {t:'Detaylar ve Donatı',h:'Çember, tapa, ek, PE kaplama, foraj, kazık içi donatı',m:['Kazık Detayları']},
  {t:'Yerleşim ve Kotlar',h:'Aktif grid, noktalar, düşük BK bölgeleri, kesit',m:['Kazık Yerleşimi','Kazık Üst Kotları','Uygulama Kapsamı','Şematik Kesit']}]},
 beam:{pin:['Başlık Kirişi Yönetimi'],note:['Notlar','Mühendislik Mantığı'],steps:[
  {t:'BK Tipi',h:'Genişlik, yükseklik, alt kot, taşmalar, beton',m:['Başlık Kirişi Tipleri','Şematik Görünüş']},
  {t:'Diş ve Kanal Cebi',h:'Usturmaça dişi, alt kot düşümü, kanal prekastı cebi',m:['Usturmaça Dişi','Kanal Prekastı']},
  {t:'Yerleşim',h:'Oluşturma yöntemi, akslara tip atama / seçili BK güncelleme',m:['Oluşturma Yöntemi','Akslara BK Tipi Ata',"Seçili BK'yi Güncelle"]},
  {t:'Donatı BIM',h:'Boyuna, etriye, gönye — çizilen donatı metraja girer',m:['Donatı BIM']}]},
 precast:{tab:'pd',pin:[],note:['Notlar','Mühendislik Mantığı'],steps:[
  {t:'Prekast Tipleri',h:'PD / PDÖ / PV / PK tip kütüphanesi',m:['Prekast Tip Kütüphanesi']},
  {t:'Yerleşim',h:'BK aralığı, Y yönünde dizilim, parametreler, genişlik kontrolü',m:['PD Yerleşim Düzeni','Parametreler','Genişlik Kontrolü']},
  {t:'Kalıp Yüzleri',h:'Hangi yüzler kalıp sayılır',m:['PD Kalıp Yüzleri']},
  {t:'Önizleme',h:'Kesit, boyuna, plan ve 3B',m:[]}]},
 deck:{pin:[],note:['Mühendislik Notları'],steps:[
  {t:'Döşeme',h:'ID, toplam kalınlık, beton, oturma payı',m:['Döşeme Tanımı','Yerleşim Mantığı']},
  {t:'Tretuvar ve Baba',h:'Taraflar, ölçüler, baba kaidesi aksları',m:['Bordür / Tretuvar','Baba Kaideleri']},
  {t:'Kaplama',h:'Kaplama betonu kalınlığı ve sınıfı',m:['Kaplama']},
  {t:'Donatı BIM',h:'Üst / alt hasır, BK üstü dolgu, tretuvar, baba',m:['Döşeme Donatı BIM']}]},
 crown:{pin:[],note:['Revizyon Standardı'],steps:[
  {t:'Kesit Tipleri',h:'Tip A ve Tip B geometrisi',m:['Tip A Geometrisi','Tip B Geometrisi']},
  {t:'Aks ve İstasyonlar',h:'Proje / aks, istasyon aralıkları',m:['Proje / Aks','İstasyon Aralıkları']},
  {t:'Kalıp ve Renk',h:'Kalıp kapsamı, renkler',m:['Kalıp Kapsamı']}]},
 rockfill:{pin:[],note:[],steps:[
  {t:'Malzemeler',h:'Dolgu / taş malzeme kütüphanesi',m:['Dolgu Malzeme Kütüphanesi']},
  {t:'Kesitler',h:'Kesit kütüphanesi ve istasyon zinciri',m:['Kesit Kütüphanesi']},
  {t:'Kübaj',h:'Ortalama uç alan metrajı ve toplamlar',m:['Ortalama Uç Alan','Malzeme Genel Toplamları']}]},
 rockfill_live:{pin:[],note:[],steps:[
  {t:'Aks ve Taban',h:'Hesap aksı, taban yüzeyi / TIN',m:['Hesap aksı ve taban']},
  {t:'Tip Kesitler',h:'Tip kesit ve geçerli olduğu bölge',m:['Tip kesit ve geçerli']},
  {t:'Hesap',h:'Kübaj ve Metraj / Keşif bağlantısı',m:['Hesap ve miktar']}]},
 editor:{pin:[],note:['BIM Prensibi'],steps:[
  {t:'Seçim',h:'Modelde eleman seçip oku',m:['Seçili BIM Elemanı']},
  {t:'Bilgiler',h:'Kimlik, organizasyon, geometri',m:['BIM Kimliği','Kazık Geometrisi','Parametrik Geometri']},
  {t:'Etki ve Güncelle',h:'Bağlı elemanlar, kontrollü güncelleme',m:['Bağımlılık','Kontrollü Güncelleme']}]},
 qto:{plain:true,pin:[],note:['Metraj Kapsamı'],steps:[
  {t:'Özet',h:'Ana metraj ve eleman bazında',m:['Ana Metraj Özeti','Eleman Bazında Metraj']},
  {t:'Kazık',h:'Kesit / yapı / sistem toplamları',m:['Kazık Metrajı']},
  {t:'Dolgu / Taş',h:'Malzeme hacim ve tonajı',m:['Dolgu / Taş Metrajı']},
  {t:'Detay Raporları',h:'Disiplin bazında ayrıntılı tablolar',m:['Metraj Detayı']}]},
 boq:{plain:true,pin:[],note:[],steps:[
  {t:'Poz Listesi',h:'Poz no, tanım, birim, miktar kaynağı',m:['Poz Listesi']},
  {t:'Keşif',h:'Model miktarı × birim fiyat, Excel',m:['ÖBF Keşif Özeti']},
  {t:'Para Birimi',h:'Sözleşme para birimi, kur, beton sınıfı',m:['Para Birimi ve Keşif Ayarları']}]},
 progress:{plain:true,pin:[],note:[],steps:[
  {t:'İlerleme Girişi',h:'Eleman × iş kalemi: yüzde, onay, tarih',m:['İş Kalemi İlerlemesi','BIM İmalat Durumu','Modelde İlerleme Görünümü']},
  {t:'Hakediş Cetveli',h:'Sözleşme / önceki / bu dönem / kümülatif',m:['Hakediş Özeti']},
  {t:'İcmal ve Kesintiler',h:'Fiyat farkı, KDV, kesintiler, ödenecek',m:['Dönem ve İcmal','Sözleşme ve Kesintiler']}]},
 settings:{plain:true,pin:[],note:['Çalışma Prensibi','Önemli'],steps:[
  {t:'Donatı Pursantajları',h:'BIM çizilmeyen elemanlar için kg/m³',m:['Donatı Pursantajları']},
  {t:'Harici Eleman Tanıt',h:'Eklenti dışı Group / Component',m:['Mevcut Elemanı Tanıt','Desteklenen Elemanlar','Model Entegrasyonu']}]}
};
FLOWS.rockfill_alt2={pin:[],note:[],steps:[{t:'Referans Kesitler',h:'Kesit dosyası, kübaj, kaynak',m:['Referans kesitlerinden']},{t:'Aks ve İstasyonlar',h:'Seçili aks, istasyon hazırlığı',m:['Aks ve istasyonlar']}]};

var previewPages=['pile','beam','deck','crown','rockfill','rockfill_live','rockfill_alt2'];
previewPages.forEach(function(id){
 FLOWS[id].steps.push({t:'Önizleme',h:'Tam sayfa çizim ve metraj',m:[],preview:true});
});
function topSections(pg){
 return $$(SEL,pg).filter(function(e){
  if(e.closest('.mst-std-head,.mst-pf,.mst-embed-page,.mstpv-full'))return false;
  for(var x=e.parentElement;x&&x!==pg;x=x.parentElement){if(x.matches(SEL))return false;}
  return true;});
}
function headOf(sec){var h=sec.querySelector('h3,h2,h4');return h?h.textContent.replace(/\s+/g,' ').trim():'';}
function match(text,list){for(var i=0;i<(list||[]).length;i++){if(text.indexOf(list[i])>=0)return true;}return false;}
function store(k,v){try{if(v===undefined)return localStorage.getItem('mstpf_'+k);localStorage.setItem('mstpf_'+k,v);}catch(e){return null;}}

var STATE={};
function build(pg){
 var cfg=FLOWS[pg.id];if(!cfg||pg.getAttribute('data-pf'))return;
 pg.setAttribute('data-pf','1');
 var secs=topSections(pg),map=[];
 secs.forEach(function(s){
  var t=headOf(s),step=-1;
  if(match(t,cfg.note)){collapse(s);return;}
  if(match(t,cfg.pin)){s.classList.add('mst-pf-pin');return;}
  if(s.closest('aside'))return;                       /* yan panel: önizleme / bilgi — her adımda görünür */
  cfg.steps.forEach(function(st,i){if(step<0&&match(t,st.m))step=i;});
  if(step>=0){s.setAttribute('data-pf-step',step);map.push(s);}
  else s.classList.add('mst-pf-pin');               /* eşleşmeyen bölüm asla kaybolmaz */
 });
 /* adım çubuğu */
 var bar=document.createElement('div');bar.className='mst-pf'+(cfg.plain?' plain':'');
 var html='<div class="mst-pf-steps" role="tablist">';
 cfg.steps.forEach(function(st,i){html+='<button type="button" class="mst-pf-step" data-i="'+i+'" role="tab"><i>'+(cfg.plain?'':(i+1))+'</i><span><b>'+esc(st.t)+'</b><small>'+esc(st.h)+'</small></span></button>';});
 html+='<button type="button" class="mst-pf-step all" data-i="all" title="Bütün bölümleri tek sayfada göster"><i>☰</i><span><b>Tümü</b><small>Tek sayfa görünüm</small></span></button></div>';
 bar.innerHTML=html;
 $$('.mst-pf-step',bar).forEach(function(b){b.onclick=function(){go(pg,b.getAttribute('data-i'),true);};});
 /* adım sonu gezinme */
 var foot=document.createElement('div');foot.className='mst-pf-foot';
 foot.innerHTML='<button type="button" class="secondary prev">‹ Önceki</button><span class="where"></span><button type="button" class="action next">Sonraki ›</button>';
 foot.querySelector('.prev').onclick=function(){var c=STATE[pg.id];if(c>0)go(pg,c-1,true);};
 foot.querySelector('.next').onclick=function(){var c=STATE[pg.id];if(c<cfg.steps.length-1)go(pg,c+1,true);};
 var head=pg.querySelector(':scope > .mst-std-head');
 var anchor=head?head.nextSibling:pg.firstChild;
 if(cfg.tab){var tabs=pg.querySelector('.mst-sub-tabs');if(tabs)anchor=tabs.nextSibling;(tabs?tabs.parentNode:pg).insertBefore(bar,anchor);}
 else pg.insertBefore(bar,anchor);
 /* son adım bölümünün ardına */
 var last=map.length?map[map.length-1]:null;
 var host=last?last.parentNode:pg;
 if(last&&last.parentNode.classList.contains('card-grid'))host=last.parentNode.parentNode;
 host.appendChild(foot);
 pg._pf={cfg:cfg,bar:bar,foot:foot,secs:map};
 var saved=store(pg.id);
 go(pg,saved==='all'?'all':(saved!=null&&+saved<cfg.steps.length?+saved:0),false);
 if(cfg.tab)watchTab(pg);
}
function go(pg,i,scroll){
 var f=pg._pf;if(!f)return;
 var all=(i==='all');STATE[pg.id]=all?'all':+i;store(pg.id,all?'all':String(i));
 if(previewPages.indexOf(pg.id)>=0){
  var preview=!all&&!!(f.cfg.steps[+i]&&f.cfg.steps[+i].preview);
  if(!preview)f.previousStep=all?'all':+i;
  pg.setAttribute('data-mst-full-preview',String(preview));
 }
 if(pg.id==='precast')pg.setAttribute('data-pf-preview',String(!all&&+i===3));
 f.secs.forEach(function(s){s.classList.toggle('mst-pf-off',!all&&+s.getAttribute('data-pf-step')!==+i);});
 /* tamamen boşalan ızgara kapları da gizlenir */
 $$('.card-grid',pg).forEach(function(g){var kids=Array.prototype.slice.call(g.children);if(!kids.length)return;
  var vis=kids.filter(function(k){return !k.classList.contains('mst-pf-off')&&!k.classList.contains('mst-hidden-dup');}).length;
  g.classList.toggle('mst-pf-off',vis===0);
  /* adımda kalan kartlar satırı doldurur (tek kart = tam genişlik) */
  g.style.gridTemplateColumns=(!all&&vis>0&&vis<3)?'repeat('+vis+',minmax(0,1fr))':'';});
 $$('.mst-pf-step',f.bar).forEach(function(b){var d=b.getAttribute('data-i');b.classList.toggle('on',all?d==='all':d===String(i));b.classList.toggle('done',!all&&d!=='all'&&+d<+i);});
 f.foot.style.display=all?'none':'';
 if(!all){var n=f.cfg.steps.length;f.foot.querySelector('.prev').style.visibility=i>0?'visible':'hidden';
  var nx=f.foot.querySelector('.next');nx.style.visibility=i<n-1?'visible':'hidden';if(i<n-1)nx.textContent='Sonraki: '+(+i+2)+' · '+f.cfg.steps[+i+1].t+' ›';
  f.foot.querySelector('.where').textContent=(f.cfg.plain?'':'Bölüm '+(+i+1)+' / '+n+' · ')+f.cfg.steps[+i].t;}
 if(window.mstSyncBar)setTimeout(window.mstSyncBar,0);
 if(scroll){try{f.bar.scrollIntoView({block:'nearest'});var top=f.bar.getBoundingClientRect().top;if(top<150)window.scrollBy(0,top-150);}catch(e){}}
}
window.mstPreviewBack=function(page){
 var pg=document.getElementById(page),flow=pg&&pg._pf;
 if(flow)go(pg,flow.previousStep==null?0:flow.previousStep,true);
};
window.mstPageStep=function(page,i){var pg=document.getElementById(page);if(pg){build(pg);go(pg,i,true);}};
function watchTab(pg){
 var upd=function(){var on=(pg.getAttribute('data-pctab')||'pd')===pg._pf.cfg.tab;pg._pf.bar.style.display=on?'':'none';pg._pf.foot.style.display=on&&STATE[pg.id]!=='all'?'':'none';};
 if(window.MutationObserver)new MutationObserver(upd).observe(pg,{attributes:true,attributeFilter:['data-pctab']});upd();
}
function collapse(sec){
 if(sec.classList.contains('mst-note'))return;
 var h=sec.querySelector('h3,h2,h4');if(!h)return;
 var top=h;while(top.parentElement&&top.parentElement!==sec)top=top.parentElement;
 top.classList.add('mst-note-head');sec.classList.add('mst-note','mst-collapsed');
 h.setAttribute('title','Aç / kapat');
 top.addEventListener('click',function(){sec.classList.toggle('mst-collapsed');});
}
/* rapor/donatı sayfasından bir bölüme gitmek: önce o bölümün adımını aç */
window.mstGoSection=function(page,text){
 if(window.mstShowPage)mstShowPage(page);
 setTimeout(function(){var pg=document.getElementById(page);if(!pg)return;build(pg);
  var hs=$$('h3,h4',pg).filter(function(h){return h.textContent.indexOf(text)>=0&&!h.closest('.mst-pf,.mst-std-head');});
  var h=hs[0];if(!h)return;
  var sec=h.closest('[data-pf-step]');if(sec)go(pg,+sec.getAttribute('data-pf-step'),false);
  setTimeout(function(){h.scrollIntoView({block:'start',behavior:'smooth'});window.scrollBy(0,-150);},60);},90);
};
function wrap(){
 if(!window.T||window.T._mstpf)return false;var prev=window.T;
 var w=function(id,b){var r=prev.apply(this,arguments);var pg=document.getElementById(id);if(pg)build(pg);return r;};
 w._mst=true;w._mstpf=true;window.T=w;try{T=w;}catch(e){}return true;
}
function init(){
 if(!window.T||!window.T._mst){setTimeout(init,40);return;}   /* önce iş akışı katmanı */
 try{wrap();Object.keys(FLOWS).forEach(function(id){var pg=document.getElementById(id);if(pg)build(pg);});}
 catch(e){console.error('MST sayfa akışı:',e);}
}
window.MST_PAGEFLOWS=FLOWS;
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){setTimeout(init,30);});else setTimeout(init,30);
})();
