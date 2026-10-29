/* v0.47 BQ1 — BOQ ve Hakediş arayüzü: poz listesi, para birimi, iş kalemi ilerlemesi, icmal, kesintiler,
   modelde görünüm, Excel ve revizyon keşif farkı. Var olan tablolar ve düğmeler aynen kalır. */
(function(){
'use strict';
function $(s,r){return (r||document).querySelector(s);}
function $$(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s));}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
function num(v,d){var n=Number(v||0);return n.toLocaleString('tr-TR',{minimumFractionDigits:d==null?2:d,maximumFractionDigits:d==null?2:d});}
function call(name){var a=Array.prototype.slice.call(arguments,1);if(window.sketchup&&sketchup[name])sketchup[name].apply(sketchup,a);}
function today(){var d=new Date();return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');}
var BQ={items:[],sources:{},library:[],settings:{currency:'USD',fx:{USD:1,EUR:1},price_date:'',split_concrete:false},contract:null,custom:false};
var PG={rows:[],manual:[],selected:0,icmal:[],currency:'USD',history:[],period:0,data:null};
window.BQ2=BQ;window.PG2=PG;
/* Ruby tarafında hata → bekleyen "…" mesajları hata olarak kapanır */
window.bq2Error=function(msg){var any=false;$$('.bq2-msg').forEach(function(m){if(/…\s*$/.test(m.textContent)){m.className='small bq2-msg err';m.textContent='Hata: '+msg;any=true;}});var si=$('#pg2SelInfo');if(si&&/…\s*$/.test(si.textContent))si.textContent='Hata: '+msg;return any;};

function card(id,title,sub,body){var s=document.createElement('section');s.className='qto-panel bq2-card';s.id=id;s.innerHTML='<div class="qto-panel-head"><div><h3>'+title+'</h3><small>'+sub+'</small></div></div>'+body;return s;}

/* ============================== BOQ sayfası ============================== */
function buildBoq(){
 var pg=$('#boq');if(!pg||$('#bq2Items'))return;
 var main=$('#boq > section.qto-panel')||pg.lastElementChild;
 var items=card('bq2Items','Poz Listesi','Projenin pozları: poz no, tanım, birim, varsayılan fiyat ve miktarın modelden hangi kaynaktan geleceği. Model miktarı olmayan işler için elle miktarlı poz ekleyebilirsin.',
  '<div class="bq2-toolbar"><button type="button" class="secondary" onclick="bq2AddItem(false)">＋ Poz</button><button type="button" class="secondary" onclick="bq2AddItem(true)">＋ Elle Miktarlı Poz</button><span class="grow"></span><button type="button" class="secondary" onclick="bq2Call(\'boq2_items_import\')">⇪ İçe Aktar</button><button type="button" class="secondary" onclick="bq2Call(\'boq2_items_export\')">⇩ Dışa Aktar</button><button type="button" class="secondary" onclick="bq2ResetItems()">Varsayılana Dön</button><button type="button" class="action" onclick="bq2SaveItems()">Poz Listesini Kaydet</button></div>'+
  '<div class="boq-scroll"><table class="qto-table bq2-items"><thead><tr><th>Etkin</th><th>Poz No</th><th>İşin Tanımı</th><th>Birim</th><th>Varsayılan Fiyat</th><th>Miktar Kaynağı</th><th>Elle Miktar</th><th></th></tr></thead><tbody id="bq2ItemRows"><tr><td colspan="8">okunuyor…</td></tr></tbody></table></div>'+
  '<div id="bq2ItemsMsg" class="small bq2-msg"></div>');
 var set=card('bq2Settings','Para Birimi ve Keşif Ayarları','Bütün birim fiyatlar sözleşme para birimindedir. Kütüphane (USD) fiyatları kur ile çevrilir. Kurlar TL karşılığıdır.',
  '<div class="deck-grid bq2-grid"><label>Sözleşme para birimi<select id="bq2Cur"><option>USD</option><option>EUR</option><option>TRY</option></select></label>'+
  '<label>1 USD = … TL<input id="bq2FxUSD" type="number" step="0.0001" min="0"></label><label>1 EUR = … TL<input id="bq2FxEUR" type="number" step="0.0001" min="0"></label>'+
  '<label>Fiyat tarihi<input id="bq2PriceDate" type="date"></label>'+
  '<label class="bq2-check"><input id="bq2Split" type="checkbox"> Betonu sınıfa göre ayrı pozlarda göster<small>BK + döşeme ve kronman betonu: ÖBF-005/C30/37, ÖBF-005/C35/45 …</small></label></div>'+
  '<div class="bq2-toolbar"><span class="grow"></span><button type="button" class="action" onclick="bq2SaveSettings()">Ayarları Kaydet</button></div><div id="bq2SetMsg" class="small bq2-msg"></div>');
 pg.insertBefore(items,main);
 main.parentNode.insertBefore(set,main.nextSibling);
 /* keşif Excel düğmesi: özet panelinin başlığına */
 var head=main.querySelector('.qto-panel-head');
 if(head){var b=document.createElement('button');b.type='button';b.className='secondary';b.setAttribute('onclick','bq2KesifExcel()');b.textContent='⇩ Keşif Cetveli (Excel)';head.appendChild(b);}
}
function srcOptions(sel){
 var h='';var keys=Object.keys(BQ.sources);
 keys.forEach(function(k){h+='<option value="'+esc(k)+'"'+(k===sel?' selected':'')+'>'+esc(BQ.sources[k])+'</option>';});
 var manual=String(sel||'').indexOf('MANUAL:')===0;
 h+='<option value="__MANUAL"'+(manual?' selected':'')+'>Elle miktar (modelde karşılığı yok)</option>';
 return h;
}
var MSEQ=0;function newManualId(){MSEQ++;return 'MANUAL:'+Date.now().toString(36)+'-'+MSEQ+Math.random().toString(36).slice(2,6);}
function itemRow(it){
 var manual=String(it.source||'').indexOf('MANUAL:')===0,lib=!manual&&BQ.library.indexOf(it.source)>=0;
 var tr=document.createElement('tr');tr.className='bq2-item'+(it.active===false?' off':'');tr.setAttribute('data-manual-id',manual?it.source:'');
 tr.innerHTML='<td><input type="checkbox" class="i-act"'+(it.active===false?'':' checked')+'></td>'+
  '<td><input class="i-code" value="'+esc(it.code)+'"></td><td><input class="i-name" value="'+esc(it.name)+'"></td>'+
  '<td><input class="i-unit" value="'+esc(it.unit)+'"></td><td>'+(lib?'<input class="i-price" disabled placeholder="kütüphane" title="Bu pozun fiyatı BOQ kütüphanesinden gelir (USD → kur). Fiyatı BOQ sayfasındaki kütüphane eşleştirmesinden değiştir.">':'<input class="i-price" type="number" step="0.01" min="0" placeholder="fiyat yok" value="'+(it.price==null?'':it.price)+'">')+'</td>'+
  '<td><select class="i-src">'+srcOptions(it.source)+'</select></td><td><input class="i-qty" type="number" step="0.001" min="0" value="'+(manual?(it.qty||0):'')+'"'+(manual?'':' disabled')+'></td>'+
  '<td class="bq2-rowbtn"><button type="button" class="secondary" title="Yukarı" onclick="bq2Move(this,-1)">↑</button><button type="button" class="secondary" title="Aşağı" onclick="bq2Move(this,1)">↓</button><button type="button" class="secondary" title="Sil" onclick="bq2Del(this)">✕</button></td>';
 tr.querySelector('.i-src').onchange=function(){var m=this.value==='__MANUAL',q=tr.querySelector('.i-qty');q.disabled=!m;if(m&&!tr.getAttribute('data-manual-id'))tr.setAttribute('data-manual-id',newManualId());};
 tr.querySelector('.i-act').onchange=function(){tr.classList.toggle('off',!this.checked);};
 return tr;
}
function renderItems(){var b=$('#bq2ItemRows');if(!b)return;b.textContent='';BQ.items.forEach(function(it){b.appendChild(itemRow(it));});}
function readItems(){
 return $$('#bq2ItemRows tr.bq2-item').map(function(tr){
  var s=tr.querySelector('.i-src').value;var o={active:tr.querySelector('.i-act').checked,code:tr.querySelector('.i-code').value,name:tr.querySelector('.i-name').value,unit:tr.querySelector('.i-unit').value,price:(tr.querySelector('.i-price').disabled?'':tr.querySelector('.i-price').value)};
  if(s==='__MANUAL'){o.source=tr.getAttribute('data-manual-id')||newManualId();o.qty=tr.querySelector('.i-qty').value||'0';}else o.source=s;
  return o;});
}
window.bq2ReadItems=readItems;
function localCheck(items){
 var err=[],codes={},srcs={};
 items.forEach(function(h,i){var n='Satır '+(i+1)+': ';if(!String(h.code).trim())err.push(n+'poz no boş');if(!String(h.unit).trim())err.push(n+'birim boş');
  if(codes[h.code])err.push(n+'poz no tekrar');codes[h.code]=1;
  if(h.source.indexOf('MANUAL:')===0){if(srcs[h.source])err.push(n+'elle poz kimliği tekrar');srcs[h.source]=1;}
  else if(h.active){if(srcs[h.source])err.push(n+'aynı miktar kaynağı iki pozda');srcs[h.source]=1;}});
 return err;
}
window.bq2AddItem=function(manual){var it={active:true,code:'',name:'',unit:manual?'LS':'m³',price:'',source:manual?newManualId():Object.keys(BQ.sources)[0],qty:manual?1:''};$('#bq2ItemRows').appendChild(itemRow(it));};
window.bq2Move=function(btn,d){var tr=btn.closest('tr'),t=d<0?tr.previousElementSibling:tr.nextElementSibling;if(!t)return;if(d<0)tr.parentNode.insertBefore(tr,t);else tr.parentNode.insertBefore(t,tr);};
window.bq2Del=function(btn){btn.closest('tr').remove();};
window.bq2SaveItems=function(){var it=readItems(),e=localCheck(it),m=$('#bq2ItemsMsg');if(e.length){m.className='small bq2-msg err';m.textContent=e.slice(0,6).join(' · ');return;}m.className='small bq2-msg';m.textContent='Kaydediliyor…';call('boq2_save_items',JSON.stringify(it));};
window.bq2ResetItems=function(){if(confirm('Poz listesi şablona dönsün mü? Girdiğin birim fiyatlar silinmez.'))call('boq2_reset_items');};
window.bq2Call=function(n){call(n);};
window.bq2SaveSettings=function(){var d={currency:$('#bq2Cur').value,fx:{USD:$('#bq2FxUSD').value,EUR:$('#bq2FxEUR').value},price_date:$('#bq2PriceDate').value,split_concrete:$('#bq2Split').checked};$('#bq2SetMsg').textContent='Kaydediliyor…';call('boq2_save_settings',JSON.stringify(d));};
window.bq2KesifExcel=function(){call('boq2_kesif_excel');};
window.boq2Loaded=function(d){
 d=d||{};BQ.items=d.items||[];BQ.sources=d.sources||{};BQ.settings=d.settings||BQ.settings;BQ.contract=d.contract||null;BQ.custom=!!d.custom;BQ.library=d.library_sources||[];
 renderItems();var s=BQ.settings;
 if($('#bq2Cur')){$('#bq2Cur').value=s.currency||'USD';$('#bq2FxUSD').value=(s.fx||{}).USD||1;$('#bq2FxEUR').value=(s.fx||{}).EUR||1;$('#bq2PriceDate').value=s.price_date||'';$('#bq2Split').checked=!!s.split_concrete;$('#bq2Split').disabled=!!s.split_locked;$('#bq2Split').parentNode.title=s.split_locked?'Kaydedilmiş hakediş var: beton sınıf ayrımı değiştirilemez.':'';}
 var m=$('#bq2ItemsMsg');if(m){m.className='small bq2-msg';m.textContent=(BQ.custom?'Projeye özel poz listesi':'Şablon poz listesi (henüz değiştirilmedi)')+' · '+BQ.items.length+' poz';}
 var sm=$('#bq2SetMsg');if(sm)sm.textContent='Para birimi: '+(s.currency||'USD')+(s.price_date?' · fiyat tarihi '+s.price_date:'');
 relabel(s.currency||'USD');
};
/* "USD" etiketlerini sözleşme para birimine çevir (tablo başlıkları, KPI'lar) */
var LAST_CUR={};
function relabel(cur){
 ['boq','progress','revision'].forEach(function(id){
  var pg=document.getElementById(id);if(!pg)return;
  var w=document.createTreeWalker(pg,NodeFilter.SHOW_TEXT,null,false),n,list=[];
  while((n=w.nextNode())){if(n.parentNode&&/^(SCRIPT|STYLE|OPTION|TEXTAREA)$/.test(n.parentNode.nodeName))continue;if(n.parentNode&&n.parentNode.closest&&n.parentNode.closest('#bq2Settings,#bq2Items,.bq2-keep'))continue;if(/\b(USD|EUR|TRY)\b/.test(n.nodeValue))list.push(n);}
  list.forEach(function(t){t.nodeValue=t.nodeValue.replace(/\b(USD|EUR|TRY)\b/g,cur);});
 });
 PG.currency=cur;
}
window.bq2Relabel=relabel;

/* setBOQ'dan sonra para birimi */
function wrapSetBOQ(){if(!window.setBOQ||window.setBOQ._bq2)return;var o=window.setBOQ;var w=function(d){var r=o.apply(this,arguments);if(d&&d.currency)relabel(d.currency);return r;};w._bq2=true;window.setBOQ=w;try{setBOQ=w;}catch(e){}}

/* ============================== Hakediş sayfası ============================== */
function buildProgress(){
 var pg=$('#progress');if(!pg||$('#pg2Entry'))return;
 var summary=$('#progress > .qto-panel');
 var entry=card('pg2Entry','İş Kalemi İlerlemesi','Modelde eleman(lar) seç → Seçimi Oku → iş kalemlerini işaretle → yüzde, onay ve tarih ver → Uygula. Hakediş yalnız onaylı yüzdeyi öder; onaysız yüzde "beyan" olarak görünür.',
  '<div class="bq2-toolbar"><button type="button" class="action" onclick="pg2ReadSelection()">↻ Seçimi Oku</button><button type="button" class="secondary" onclick="pg2Find()" title="Kazık / eleman numarasını yaz (ör. P-56): modelde seçilir, gösterilir ve buraya okunur">⌕ Numarayla Bul</button><span id="pg2SelInfo" class="small">Seçim okunmadı.</span></div>'+
  '<div class="boq-scroll"><table class="qto-table"><thead><tr><th><input type="checkbox" id="pg2All" title="Hepsi"></th><th>Poz</th><th>İşin Tanımı</th><th>Eleman</th><th>Miktar</th><th>Onaylı</th><th>Beyan</th></tr></thead><tbody id="pg2Rows"><tr><td colspan="7">Modelde eleman seçip “Seçimi Oku”ya bas.</td></tr></tbody></table></div>'+
  '<div class="deck-grid bq2-grid"><label>İlerleme %<span class="bq2-pct"><select id="pg2PctSel"><option>0</option><option>25</option><option>50</option><option>75</option><option selected>100</option></select><input id="pg2Pct" type="number" min="0" max="100" step="1" value="100"></span></label>'+
  '<label class="bq2-check"><input id="pg2Ok" type="checkbox" checked> Onaylı (hakedişe girer)</label><label>Tarih<input id="pg2Date" type="date"></label></div>'+
  '<div class="bq2-toolbar"><span id="pg2Msg" class="small bq2-msg"></span><span class="grow"></span><button type="button" class="secondary" onclick="pg2Apply(true)">Kaydı Sil</button><button type="button" class="action" onclick="pg2Apply(false)">Seçili Kalemlere Uygula</button></div>'+
  '<h4 class="bq2-h4">Modelde karşılığı olmayan pozlar (elle ilerleme)</h4><div class="boq-scroll"><table class="qto-table"><thead><tr><th>Poz</th><th>İşin Tanımı</th><th>Miktar</th><th>İlerleme %</th><th>Onaylı</th><th>Tarih</th><th></th></tr></thead><tbody id="pg2Manual"><tr><td colspan="7">—</td></tr></tbody></table></div>');
 var view=card('pg2View','Modelde İlerleme Görünümü','Bir iş kaleminin onaylı, kısmi/beyan veya hiç başlanmamış elemanlarını modelde seç; istersen yalnız onları göster.',
  '<div class="deck-grid bq2-grid"><label>İş kalemi<select id="pg2ViewSrc"><option value="">Tüm kalemler (eleman durumu)</option></select></label></div>'+
  '<div class="bq2-toolbar"><button type="button" class="secondary bq2-ok" onclick="pg2Select(\'ok\')">● Onaylıları Seç</button><button type="button" class="secondary bq2-part" onclick="pg2Select(\'partial\')">● Kısmi / Beyan</button><button type="button" class="secondary bq2-none" onclick="pg2Select(\'none\')">● Başlanmamış</button><span class="grow"></span><button type="button" class="secondary" onclick="pg2Isolate(1)">Yalnız Seçilileri Göster</button><button type="button" class="secondary" onclick="pg2Isolate(0)">Hepsini Göster</button></div><div id="pg2ViewMsg" class="small bq2-msg"></div>');
 var ic=card('pg2Icmal','Dönem ve İcmal','Dönem sonu tarihine kadar onaylanan işler bu döneme girer. Önceki = son kaydedilen hakediş. Fiyat farkını bu dönem için tutar olarak gir.',
  '<div class="deck-grid bq2-grid"><label>Dönem sonu<input id="pg2PeriodDate" type="date"></label><label>Bu dönem fiyat farkı<input id="pg2PriceDiff" type="number" step="0.01" value="0"></label><label>Not<input id="pg2Note" placeholder="ör. Ekim 2026 hakedişi"></label></div>'+
  '<div class="boq-scroll"><table class="qto-table bq2-icmal"><thead><tr><th></th><th>Kalem</th><th>Kümülatif</th><th>Önceki</th><th>Bu Dönem</th></tr></thead><tbody id="pg2IcmalRows"><tr><td colspan="5">—</td></tr></tbody></table></div>'+
  '<div class="bq2-toolbar"><span id="pg2IcMsg" class="small bq2-msg"></span><span class="grow"></span><button type="button" class="secondary" onclick="pg2Excel()">⇩ Hakediş Raporu (Excel)</button></div>');
 var ct=card('pg2Contract','Sözleşme ve Kesintiler','KDV ve kesinti oranları icmalde kullanılır. Hazır şablonlar örnektir — oranları sözleşmene göre kontrol et.',
  '<div class="deck-grid bq2-grid"><label>Sözleşme tipi<select id="pg2Type"><option value="ozel">Özel / uluslararası</option><option value="kamu">Kamu (KİK)</option></select></label><label>KDV %<input id="pg2Vat" type="number" min="0" max="100" step="0.01"></label>'+
  '<label>Şablon<span class="bq2-pct"><button type="button" class="secondary" onclick="pg2Preset()">Seçili tipin şablonunu yükle</button></span></label></div>'+
  '<div class="boq-scroll"><table class="qto-table"><thead><tr><th>Kesinti</th><th>Taban</th><th>Oran %</th><th></th></tr></thead><tbody id="pg2Ded"></tbody></table></div>'+
  '<div class="bq2-toolbar"><button type="button" class="secondary" onclick="pg2AddDed()">＋ Kesinti</button><span class="grow"></span><button type="button" class="action" onclick="pg2SaveContract()">Sözleşmeyi Kaydet</button></div><div id="pg2CtMsg" class="small bq2-msg"></div>');
 pg.insertBefore(entry,summary);pg.insertBefore(view,summary);
 summary.parentNode.insertBefore(ic,summary.nextSibling);ic.parentNode.insertBefore(ct,ic.nextSibling);
 /* eski "BIM İmalat Durumu" paneli giriş adımının sonuna */
 var old=$$('#progress > .qto-panel').filter(function(p){var h=p.querySelector('h3');return h&&h.textContent.indexOf('BIM İmalat Durumu')>=0;})[0];
 if(old)entry.parentNode.insertBefore(old,view.nextSibling);
 $('#pg2Date').value=today();$('#pg2PeriodDate').value=today();
 $('#pg2PctSel').onchange=function(){$('#pg2Pct').value=this.value;};
 $('#pg2All').onchange=function(){var c=this.checked;$$('#pg2Rows input.pg2-src').forEach(function(x){x.checked=c;});};
 $('#pg2PeriodDate').onchange=pg2View;$('#pg2PriceDiff').onchange=pg2View;
}
function pg2View(){var a=$('#progressPeriodSelect');if(a&&Number(a.value||0)>0)return;call('prog2_view',JSON.stringify({date:$('#pg2PeriodDate').value,price_diff:$('#pg2PriceDiff').value}));}
window.pg2View=pg2View;
window.pg2Find=function(){$('#pg2SelInfo').textContent='aranıyor…';call('mst_find');};
window.pg2ReadSelection=function(){$('#pg2SelInfo').textContent='okunuyor…';call('prog2_selection');};
window.prog2SelectionLoaded=function(d){
 d=d||{};PG.rows=d.rows||[];PG.manual=d.manual||[];PG.selected=d.selected||0;
 $('#pg2SelInfo').textContent=PG.selected?PG.selected+' eleman seçili · '+PG.rows.length+' iş kalemi':'Modelde seçim yok.';
 var b=$('#pg2Rows');
 b.innerHTML=PG.rows.length?PG.rows.map(function(r){return '<tr><td><input type="checkbox" class="pg2-src" value="'+esc(r.key||r.source)+'"></td><td><b>'+esc(r.code)+'</b></td><td class="txt">'+esc(r.name)+'</td><td class="num">'+r.count+'</td><td class="num">'+num(r.quantity,3)+' '+esc(r.unit)+'</td><td class="num">'+bar(r.approved_pct,'ok')+'</td><td class="num">'+bar(r.claimed_pct,'part')+'</td></tr>';}).join(''):'<tr><td colspan="7">'+(PG.selected?'Seçili elemanlar hiçbir aktif poza girmiyor.':'Modelde eleman seçip “Seçimi Oku”ya bas.')+'</td></tr>';
 var m=$('#pg2Manual');
 m.innerHTML=PG.manual.length?PG.manual.map(function(r,i){return '<tr data-src="'+esc(r.key||r.source)+'"><td><b>'+esc(r.code)+'</b></td><td class="txt">'+esc(r.name)+'</td><td class="num">'+num(r.quantity,3)+' '+esc(r.unit)+'</td><td><input class="m-pct" type="number" min="0" max="100" value="'+(r.pct||0)+'"></td><td><input class="m-ok" type="checkbox"'+(r.ok?' checked':'')+' title="Onaylı: '+Number(r.approved_pct||0)+'%"></td><td><input class="m-date" type="date" value="'+esc(r.date||today())+'"></td><td><button type="button" class="secondary" onclick="pg2Manual(this)">Kaydet</button></td></tr>';}).join(''):'<tr><td colspan="7">Elle ilerleyen poz yok.</td></tr>';
};
function bar(p,cls){p=Number(p||0);return '<span class="pg2-bar '+cls+'"><i style="width:'+Math.max(0,Math.min(100,p))+'%"></i></span> '+p.toFixed(0)+'%';}
window.pg2Apply=function(clear){
 var srcs=$$('#pg2Rows input.pg2-src').filter(function(x){return x.checked;}).map(function(x){return x.value;}),m=$('#pg2Msg');
 if(!srcs.length){m.className='small bq2-msg err';m.textContent='En az bir iş kalemi işaretle.';return;}
 var p=Number($('#pg2Pct').value);if(!clear&&!(p>=0&&p<=100)){m.className='small bq2-msg err';m.textContent='Yüzde 0–100 olmalı.';return;}
 m.className='small bq2-msg';m.textContent='Uygulanıyor…';
 call('prog2_apply',JSON.stringify({sources:srcs,pct:p,ok:$('#pg2Ok').checked,date:$('#pg2Date').value,clear:!!clear}));
};
window.prog2Applied=function(d){$('#pg2Msg').textContent=(d&&d.count||0)+' eleman × kalem güncellendi (tek Geri Al).';};
window.pg2Manual=function(btn){var tr=btn.closest('tr');call('prog2_manual',JSON.stringify({source:tr.getAttribute('data-src'),pct:tr.querySelector('.m-pct').value,ok:tr.querySelector('.m-ok').checked,date:tr.querySelector('.m-date').value}));};
window.pg2Select=function(state){$('#pg2ViewMsg').textContent='seçiliyor…';call('prog2_select',JSON.stringify({source:$('#pg2ViewSrc').value,state:state}));};
window.prog2Selected=function(n){$('#pg2ViewMsg').textContent=n+' eleman seçildi.';};
window.pg2Isolate=function(on){call('prog2_isolate',String(on));};
window.prog2Isolated=function(d){$('#pg2ViewMsg').textContent=d.on?(d.count+' MST elemanı gizlendi; yalnız seçim görünüyor.'):(d.count+' eleman yeniden görünür.');};
window.pg2Excel=function(){var s=$('#progressPeriodSelect');call('prog2_excel',String(s?Number(s.value||0):0));};
window.progressSave=function(){
 var date=$('#pg2PeriodDate').value||today(),pd=$('#pg2PriceDiff').value||'0';
 if(!confirm('Hakediş dönemi '+date+' tarihiyle kaydedilsin mi?\nBu tarihe kadar onaylanan işler dönemi oluşturur.'))return;
 call('prog2_save',JSON.stringify({date:date,price_diff:pd,note:$('#pg2Note').value}));
};
function renderIcmal(d){
 var b=$('#pg2IcmalRows');if(!b)return;var cur=d.currency||PG.currency||'USD',ic=d.icmal||[];
 b.innerHTML=ic.length?ic.map(function(l){var cls=(l.key==='C'||l.key==='F')?' class="total"':(l.key==='E'?' class="subtotal"':'');return '<tr'+cls+'><td><b>'+esc(l.key)+'</b></td><td class="txt">'+esc(l.name)+'</td><td class="num">'+num(l.cum)+' '+cur+'</td><td class="num">'+num(l.prev)+' '+cur+'</td><td class="num"><b>'+num(l.cur)+' '+cur+'</b></td></tr>';}).join(''):'<tr><td colspan="5">—</td></tr>';
 var msg=$('#pg2IcMsg');if(msg)msg.textContent=(d.archived?'Arşiv: ':'Önizleme: ')+'dönem sonu '+(d.period_date||'—')+(d.last_date?' · son hakediş '+d.last_date:' · ilk hakediş');
 if(d.period_date&&!d.archived)$('#pg2PeriodDate').value=d.period_date;
 $('#pg2PriceDiff').value=Number(d.price_diff||0);
 $('#pg2PeriodDate').disabled=!!d.archived;$('#pg2PriceDiff').disabled=!!d.archived;
}
function renderContract(c){
 if(!c||!$('#pg2Type'))return;$('#pg2Type').value=c.type||'ozel';$('#pg2Vat').value=c.vat_pct;
 $('#pg2Ded').innerHTML='';(c.deductions||[]).forEach(function(x){addDed(x);});
}
function addDed(x){x=x||{name:'',base:'tutar',pct:0};var tr=document.createElement('tr');tr.innerHTML='<td><input class="d-name" value="'+esc(x.name)+'"></td><td><select class="d-base"><option value="tutar"'+(x.base==='tutar'?' selected':'')+'>İş tutarı (C)</option><option value="kdv"'+(x.base==='kdv'?' selected':'')+'>KDV (D)</option></select></td><td><input class="d-pct" type="number" min="0" max="100" step="0.001" value="'+x.pct+'"></td><td><button type="button" class="secondary" onclick="this.closest(\'tr\').remove()">✕</button></td>';$('#pg2Ded').appendChild(tr);}
window.pg2AddDed=function(){addDed();};
window.pg2Preset=function(){if(confirm('Seçili sözleşme tipinin örnek kesinti şablonu yüklensin mi? Mevcut kesinti listesi değişir.'))call('boq2_contract_preset',$('#pg2Type').value);};
window.pg2SaveContract=function(){var d={type:$('#pg2Type').value,vat_pct:$('#pg2Vat').value,deductions:$$('#pg2Ded tr').map(function(tr){return {name:tr.querySelector('.d-name').value,base:tr.querySelector('.d-base').value,pct:tr.querySelector('.d-pct').value};})};$('#pg2CtMsg').textContent='Kaydediliyor…';call('boq2_save_contract',JSON.stringify(d));};
function wrapProgress(){
 if(!window.progressLoaded||window.progressLoaded._bq2)return;var o=window.progressLoaded;
 var w=function(d){var r=o.apply(this,arguments);try{
  PG.data=d;var cur=(d&&d.currency)||'USD';
  /* eksilen (negatif) satırları işaretle */
  var trs=$$('#progressBody tr');((d&&d.rows)||[]).forEach(function(row,i){var tr=trs[i];if(!tr)return;if(row.warning||Number(row.current_period)<-1e-9){tr.classList.add('pg2-neg');tr.title=row.warning||'Önceki hakedişe göre azalma';}if(row.manual)tr.classList.add('pg2-manual');if(row.price_missing){tr.classList.add('pg2-noprice');tr.title=(tr.title?tr.title+' · ':'')+'Birim fiyat yok';}if(row.removed)tr.classList.add('pg2-removed');});
  renderIcmal(d||{});renderContract(d&&d.contract);
  var vs=$('#pg2ViewSrc');if(vs){var keep=vs.value;vs.innerHTML='<option value="">Tüm kalemler (eleman durumu)</option>'+((d&&d.rows)||[]).filter(function(r){return !r.manual&&!r.removed;}).map(function(r){return '<option value="'+esc(r.key||r.source)+'">'+esc(r.code)+' · '+esc(r.name)+'</option>';}).join('');vs.value=keep;}
  var sel=$('#progressPeriodSelect');if(sel&&d&&d.history){Array.prototype.forEach.call(sel.options,function(o){var h=d.history.filter(function(x){return String(x.no)===o.value;})[0];if(h&&h.date)o.textContent='Hakediş '+String(h.no).padStart(2,'0')+' · dönem sonu '+h.date;});}
  relabel(cur);
 }catch(e){console.error('BQ1 hakediş:',e);}return r;};
 w._bq2=true;window.progressLoaded=w;try{progressLoaded=w;}catch(e){}
}

/* ============================== Revizyon: keşif farkı ============================== */
function buildRevision(){
 var pg=$('#revision');if(!pg||$('#rv2Boq'))return;
 var c=card('rv2Boq','Keşif Farkı','Son snapshot ile güncel model arasında poz bazında miktar ve tutar değişimi (güncel birim fiyatlarla).',
  '<div id="rv2Note" class="small bq2-msg"></div><div class="boq-scroll"><table class="qto-table"><thead><tr><th>Poz</th><th>İşin Tanımı</th><th>Birim</th><th>Önceki</th><th>Güncel</th><th>Δ Miktar</th><th>Birim Fiyat</th><th>Δ Tutar</th></tr></thead><tbody id="rv2Rows"><tr><td colspan="8">—</td></tr></tbody></table></div>');
 var anchor=$('#revision > .qto-panel');(anchor&&anchor.parentNode===pg)?pg.insertBefore(c,anchor.nextSibling):pg.appendChild(c);
}
function wrapRevision(){
 if(!window.revisionLoaded||window.revisionLoaded._bq2)return;var o=window.revisionLoaded;
 var w=function(d){var r=o.apply(this,arguments);try{
  var cur=(d&&d.currency)||'USD',rows=(d&&d.boq_diff)||null,b=$('#rv2Rows');$('#rv2Note').textContent=(d&&d.boq_diff_note)||'';
  if(!rows){b.innerHTML='<tr><td colspan="8">'+esc((d&&d.boq_diff_note)||'—')+'</td></tr>';return r;}
  var tot=0;b.innerHTML=rows.length?rows.map(function(x){tot+=Number(x.delta_amount||0);var cls=x.delta<0?' class="pg2-neg"':'';return '<tr'+cls+'><td><b>'+esc(x.code)+'</b></td><td class="txt">'+esc(x.name)+'</td><td>'+esc(x.unit)+'</td><td class="num">'+num(x.prev,3)+'</td><td class="num">'+num(x.curr,3)+'</td><td class="num"><b>'+(x.delta>0?'+':'')+num(x.delta,3)+'</b></td><td class="num">'+num(x.unit_price)+' '+cur+'</td><td class="num"><b>'+(x.delta_amount>0?'+':'')+num(x.delta_amount)+' '+cur+'</b></td></tr>';}).join('')+'<tr class="total"><td colspan="7">TOPLAM KEŞİF FARKI</td><td class="num"><b>'+(tot>0?'+':'')+num(tot)+' '+cur+'</b></td></tr>':'<tr><td colspan="8">Keşifte değişiklik yok.</td></tr>';
 }catch(e){console.error('BQ1 revizyon:',e);}return r;};
 w._bq2=true;window.revisionLoaded=w;try{revisionLoaded=w;}catch(e){}
}

/* sayfa açılınca veri iste */
function hookT(){
 if(!window.T||window.T._bq2)return false;var o=window.T;
 var w=function(id){var r=o.apply(this,arguments);if(id==='boq')call('boq2_get');return r;};
 for(var k in o)if(Object.prototype.hasOwnProperty.call(o,k))w[k]=o[k];w._bq2=true;window.T=w;try{T=w;}catch(e){}return true;
}
function init(){
 try{buildBoq();buildProgress();buildRevision();wrapSetBOQ();wrapProgress();wrapRevision();}catch(e){console.error('BQ1 arayüz:',e);}
 (function wait(){if(window.T&&window.T._mstpf){hookT();}else setTimeout(wait,60);})();
}
/* DOM hazır: pageflow bölümleri sayabilsin diye kartlar hemen eklenir */
init();
})();
