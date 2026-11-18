/* v0.38 UI3 / UI4 / UI5 / UI6 — tek standart: iş akışı menüsü, sayfa başlığı, sabit işlem çubuğu.
   Var olan düğmeler TAŞINIR ya da gizlenir; hiçbir düğmenin işlevi değişmez (id / onclick korunur). */
(function(){
'use strict';
function $(s,r){return (r||document).querySelector(s);}
function $$(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s));}
function oc(b){return b.getAttribute('onclick')||'';}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}

/* ---- İş akışı: 10 adım. need = önce tamamlanması gereken adımlar ---- */
var FLOW=[
 {n:1, key:'project', title:'Proje / Aks', emb:'project_manager', desc:'Proje adı, sistem (Dolfen / İskele / Rıhtım), yapı ve aks gridi. Bütün elemanlar bu gridden konum alır.', need:[]},
 {n:2, key:'pile', title:'Kazık', page:'pile', desc:'Aktif yapının gridinden çelik boru kazıklar; fore kazık aynı adımın alt sayfasıdır.', need:['project'], subs:[{title:'Fore Kazık', emb:'bored_pile'},{title:'Jet Grout', emb:'jet_grout', desc:'Jet grout kolon tipleri, modele yerleşim ve metraj (zemin hacmi, sarf).'}]},
 {n:3, key:'beam', title:'Başlık Kirişi', page:'beam', desc:'Kazıklara oturan BK tipleri; diş, cep ve kanal prekastı cepleri; BK donatı BIM.', need:['pile']},
 {n:4, key:'precast', title:'Prekast', page:'precast', desc:'İki komşu BK arasına PD / kanal / vinç prekastları.', need:['beam']},
 {n:5, key:'deck', title:'Döşeme', page:'deck', desc:'Toplam kalınlık, tretuvar, baba kaideleri ve kaplama; BK ve prekasta göre otomatik güncellenir.', need:['beam']},
 {n:6, key:'crown', title:'Kronman / Dolgu', page:'crown', desc:'Kronman aralıkları ve dolgu / taş kübajı (isteğe bağlı).', need:['project'], subs:[{title:'Dolgu / Taş', page:'rockfill_choice', extra:"sketchup.rockfill_source('load')"},{title:'Dolgu / Taş · Özel Katı', emb:'special_solids', desc:'Alternatif-02: malzemeleri modellenmiş net kapalı katılara bağla, hacmi katıdan oku.'}]},
 {n:7, key:'rebar', title:'Donatı BIM', page:'rebar', desc:'Hangi elemanın donatısı modellendi (BIM), hangisi pursantajla hesaplanıyor.', need:['beam']},
 {n:8, key:'audit', title:'Model Kontrolü', emb:'model_audit', open:'model_audit', desc:'Hata ve uyarılar; listeden seçip modelde göster, güvenli onarım.', need:[]},
 {n:9, key:'qto', title:'Metraj', page:'qto', desc:'Tek hesap motorundan beton, kalıp, donatı, çelik ve dolgu metrajı.', need:[]},
 {n:10,key:'boq', title:'Keşif / Hakediş', page:'boq', desc:'ÖBF iş kalemleri, birim fiyat, revizyon ve hakediş.', need:['qto'], subs:[{title:'Revizyonlar', page:'revision', extra:'revisionMarkStale()'},{title:'Hakediş / İlerleme', page:'progress', extra:'progressRefresh()'}]}
];
var TOOLS=[
 /* 02.11.2026: eski "Eleman Düzenle / Eleman Düzenleyici" girişi kaldırıldı; yerine Çalışma Alanı. #editor sayfası DOM'da gizli kalır (Ruby setEditorSelection vb. çağrıları için).
    head:false — sayfanın kendi başlığı ve "Modeli Yenile" düğmesi korunur (std başlık .module-title'ı gizlerdi). */
 {key:'project_workspace', title:'Çalışma Alanı', page:'project_workspace', head:false, extra:'MSTProjectWorkspace.refresh()', desc:'Proje ağacı, seçimin özellikleri, modelde gösterme ve düzenleme.'},
 {key:'accessories', title:'Aksesuarlar', emb:'accessories', desc:'Baba, usturmaça, merdiven vb. ekipman çizelgesi.'},
 {key:'maint', title:'Model Bakımı', page:'maint', desc:'Onarım, senkronizasyon, kütüphane ve dışa aktarım araçlarının tamamı.'},
 {key:'settings', title:'Ayarlar', page:'settings', desc:'Donatı pursantajları ve harici elemanı modele tanıtma.'},
 {key:'guide', title:'Kullanma Kılavuzu', page:'guide', desc:'Bütün sistem, çalışma sırasıyla adım adım. Arama, başlık listesi ve ilgili sayfaya geçiş.'}
];
var STATUS={};
window.MST_FLOW=FLOW;

/* Sayfa → adım eşlemesi */
function stepOfPage(id){
 for(var i=0;i<FLOW.length;i++){var f=FLOW[i];if(f.page===id||('emb_'+f.emb)===id)return {f:f,sub:null};
  if(f.subs)for(var j=0;j<f.subs.length;j++){var s=f.subs[j];if(s.page===id||('emb_'+s.emb)===id||(id.indexOf('rockfill')===0&&s.page==='rockfill_choice'))return {f:f,sub:s};}}
 for(var k=0;k<TOOLS.length;k++){var t=TOOLS[k];if(t.page===id||('emb_'+t.emb)===id)return {f:t,sub:null,tool:true};}
 return null;
}
function nextStep(f){var i=FLOW.indexOf(f);return i>=0&&i<FLOW.length-1?FLOW[i+1]:null;}
function openItem(it){
 if(it.page){var b=navBtn(it.page)||document.createElement('button');T(it.page,b);if(it.extra){try{(0,eval)(it.extra)}catch(e){}}}
 else if(it.emb){var cb=it.open||it.emb;if(window.sketchup&&sketchup[cb])sketchup[cb]();}
 try{window.scrollTo(0,0)}catch(e){}
}
window.mstOpenStep=function(key){var it=FLOW.concat(TOOLS).filter(function(x){return x.key===key})[0];if(it)openItem(it);};

/* ---- UI4: menüyü iş akışı sırasına diz (var olan düğmeler taşınır) ---- */
var NAVMAP={};
function findNav(test){return $$('.tabs button').filter(function(b){return test(oc(b),b);})[0]||null;}
function navBtn(page){return NAVMAP[page]||null;}
function addIcon(b,icon){if(!b||b.querySelector('img'))return b;var im=document.createElement('img');im.className='mst-nav-thumb';im.src='icons/'+icon;im.alt='';im.setAttribute('aria-hidden','true');b.classList.add('mst-nav-photo');b.insertBefore(im,b.firstChild);return b;}
function makeBtn(title,sym,icon){var b=document.createElement('button');b.type='button';b.setAttribute('data-symbol',sym||'•');b.textContent=title;if(icon)addIcon(b,icon);return b;}
function decorate(b,it,isSub,n){
 b.classList.add(isSub?'mst-sub':(n?'mst-step':'mst-tool'));
 b.setAttribute('data-flow',it.key||it.page||it.emb);
 if(!isSub&&n){var no=document.createElement('i');no.className='mst-step-no';no.textContent=n;b.insertBefore(no,b.firstChild);}
 var st=document.createElement('em');st.className='mst-st';st.setAttribute('data-st','');b.appendChild(st);
 if(it.title){var img=b.querySelector('img');var t=document.createTextNode(it.title);Array.prototype.slice.call(b.childNodes).forEach(function(c){if(c.nodeType===3&&c.textContent.trim())b.removeChild(c);});b.insertBefore(t,img?img.nextSibling:(b.querySelector('.mst-step-no')?b.querySelector('.mst-step-no').nextSibling:b.firstChild));}
 return b;
}
function buildNav(){
 var tabs=$('.tabs');if(!tabs||tabs.classList.contains('mst-flow-nav'))return;
 var pick={
  project:findNav(function(o){return o.indexOf('sketchup.project_manager(')>=0;}),
  pile:findNav(function(o){return o.indexOf("T('pile'")>=0;}),
  jet:findNav(function(o){return o.indexOf('sketchup.jet_grout(')>=0;}),
  bored:findNav(function(o){return o.indexOf('sketchup.bored_pile(')>=0;}),
  beam:findNav(function(o){return o.indexOf("T('beam'")>=0;}),
  precast:findNav(function(o){return o.indexOf("T('precast'")>=0;}),
  deck:findNav(function(o){return o.indexOf("T('deck'")>=0;}),
  crown:findNav(function(o){return o.indexOf("T('crown'")>=0;}),
  rockfill:findNav(function(o){return o.indexOf("T('rockfill_choice'")>=0;}),
  workspace:$('#workspaceNav'),
  qto:findNav(function(o){return o.indexOf("T('qto'")>=0;}),
  boq:findNav(function(o){return o.indexOf("T('boq'")>=0;}),
  accessories:findNav(function(o){return o.indexOf('sketchup.accessories(')>=0;}),
  revision:findNav(function(o){return o.indexOf("T('revision'")>=0;}),
  progress:findNav(function(o){return o.indexOf("T('progress'")>=0;}),
  settings:findNav(function(o){return o.indexOf("T('settings'")>=0;})
 };
 /* yenileme T() sarmalayıcısında (wrapT) yapılır; onclick'te ikinci kez çağrılmaz */
 var rebar=makeBtn('Donatı BIM','▦','nav_rebar.png');rebar.setAttribute('onclick',"T('rebar',this)");
 var audit=makeBtn('Model Kontrolü','✓','nav_audit.png');audit.setAttribute('onclick','sketchup.model_audit()');
 var maint=makeBtn('Model Bakımı','⚒','nav_maint.png');maint.setAttribute('onclick',"T('maint',this)");
 if(!pick.settings){pick.settings=makeBtn('Ayarlar','⚙');pick.settings.setAttribute('onclick',"T('settings',this)");}
 var guide=$('#guide')?makeBtn('Kullanma Kılavuzu','📘'):null;if(guide)guide.setAttribute('onclick',"T('guide',this)");
 addIcon(pick.workspace,'nav_editor.png');addIcon(pick.settings,'nav_settings.png');if(pick.jet)addIcon(pick.jet,'nav_bored.png');
 var keep=[];
 function sec(t){var d=document.createElement('div');d.className='nav-section';d.textContent=t;keep.push(d);}
 function add(b,it,isSub,n){if(!b)return;decorate(b,it,isSub,n);keep.push(b);}
 sec('İŞ AKIŞI');
 add(pick.project,FLOW[0],false,1);
 add(pick.pile,FLOW[1],false,2);add(pick.bored,{key:'bored',title:'Fore Kazık'},true);add(pick.jet,{key:'jet_grout',title:'Jet Grout'},true);
 add(pick.beam,FLOW[2],false,3);add(pick.precast,FLOW[3],false,4);add(pick.deck,FLOW[4],false,5);
 add(pick.crown,FLOW[5],false,6);add(pick.rockfill,{key:'rockfill',title:'Dolgu / Taş'},true);
 add(rebar,FLOW[6],false,7);add(audit,FLOW[7],false,8);add(pick.qto,FLOW[8],false,9);
 add(pick.boq,FLOW[9],false,10);add(pick.revision,{key:'revision',title:'Revizyonlar'},true);add(pick.progress,{key:'progress',title:'Hakediş / İlerleme'},true);
 sec('ARAÇLAR');
 add(pick.workspace,TOOLS[0]);add(pick.accessories,TOOLS[1]);add(maint,TOOLS[2]);add(pick.settings,TOOLS[3]);add(guide,TOOLS[4]);
 /* menüde kalan diğer her şey (varsa) en sona — hiçbir giriş kaybolmaz */
 var rest=$$('.tabs > *').filter(function(x){return keep.indexOf(x)<0&&x.tagName==='BUTTON';});
 var olds=$$('.tabs > .nav-section').filter(function(x){return keep.indexOf(x)<0;});
 olds.forEach(function(x){x.parentNode.removeChild(x);});
 keep.forEach(function(x){tabs.appendChild(x);});
 rest.forEach(function(x){tabs.appendChild(x);});
 tabs.classList.add('mst-flow-nav');
 NAVMAP={pile:pick.pile,beam:pick.beam,precast:pick.precast,deck:pick.deck,crown:pick.crown,rockfill_choice:pick.rockfill,rebar:rebar,qto:pick.qto,boq:pick.boq,revision:pick.revision,progress:pick.progress,project_workspace:pick.workspace,maint:maint,settings:pick.settings,guide:guide,
  emb_project_manager:pick.project,emb_bored_pile:pick.bored,emb_jet_grout:pick.jet,emb_special_solids:pick.rockfill,emb_model_audit:audit,emb_accessories:pick.accessories};
 ['rockfill','rockfill_live','rockfill_alt2'].forEach(function(p){NAVMAP[p]=pick.rockfill;});
}

/* ---- UI3: her sayfanın başı aynı ---- */
function stdHead(pg){
 if(!pg||pg.querySelector(':scope > .mst-std-head'))return;
 var s=stepOfPage(pg.id);if(!s||(s.tool&&s.f.head===false))return;
 var f=s.f,it=s.sub||f;
 var desc=it.desc||f.desc||'';
 var eh=pg.querySelector(':scope > .mst-embed-head');if(eh)eh.style.display='none';
 var h=document.createElement('div');h.className='mst-std-head';
 var chip=s.tool?'Araç':('Adım '+f.n+' / '+FLOW.length+(s.sub?' · '+f.title:''));
 h.innerHTML='<div class="l"><span class="stepchip">'+esc(chip)+'</span><h2>'+esc(it.title)+'</h2><p>'+esc(desc)+'</p></div><div class="r"><span class="status" data-st="">—</span><span class="need" style="display:none"></span></div>';
 var nx=s.tool?null:nextStep(f);
 if(nx){var b=document.createElement('button');b.type='button';b.className='secondary next';b.textContent='Sonraki adım: '+nx.n+' · '+nx.title+' →';b.onclick=function(){openItem(nx);};h.querySelector('.r').appendChild(b);}
 pg.insertBefore(h,pg.firstChild);
 pg.classList.add('mst-std-page');
 paintHead(pg);
}
function paintHead(pg){
 var h=pg&&pg.querySelector(':scope > .mst-std-head');if(!h)return;
 var s=stepOfPage(pg.id);if(!s)return;
 var st=STATUS[s.f.key];var el=h.querySelector('.status');
 if(st){el.setAttribute('data-st',st.state);el.textContent=({ok:'✓ ',missing:'✗ ',stale:'⚠ ',optional:'',info:''}[st.state]||'')+st.text;}else{el.textContent=s.tool?'':'durum okunuyor…';}
 el.style.display=el.textContent?'':'none';
 var need=h.querySelector('.need'),miss=(s.f.need||[]).filter(function(k){return STATUS[k]&&STATUS[k].state==='missing';});
 if(miss.length){need.style.display='';need.innerHTML='⚠ Önce: '+miss.map(function(k){var f=FLOW.filter(function(x){return x.key===k})[0];return '<a data-k="'+k+'">'+f.n+' · '+esc(f.title)+'</a>';}).join(', ');
  $$('a',need).forEach(function(a){a.onclick=function(){mstOpenStep(a.getAttribute('data-k'));};});}
 else need.style.display='none';
}

/* ---- UI3: sabit işlem çubuğu (Seçiliyi Oku / Önizle / Oluştur-Güncelle / Diğer işlemler) ---- */
function vis(e){if(!e)return false;for(var x=e;x&&x!==document.body;x=x.parentElement){if(x.classList&&x.classList.contains('mst-hidden-dup'))continue;var cs=getComputedStyle(x);if(cs.display==='none'&&!(x.classList&&x.classList.contains('page')))return false;}return true;}
function byOc(pg,frag){return $$('button',pg).filter(function(b){return oc(b).indexOf(frag)>=0&&!b.closest('#mstMore');});}
function pcTab(){var p=$('#precast');return (p&&p.getAttribute('data-pctab'))||'pd';}
var ACT={
 pile:{read:{oc:'sketchup.pile_load_selected_for_edit()',label:'↻ Seçili Kazığı Oku'},
       preview:{oc:'mstPileTargetPreview()',label:'👁 Hedefleri Önizle',when:function(){return window.mstPileMode==='edit';}},
       create:[{oc:'mstApplyCommonPileForm()',when:function(){return window.mstPileMode==='edit';}},{oc:'pile()'}],
       more:['mstPileRingNormalizeAll()','mstPileBodyConvert()','mstPileBodyRevert()','pile_definitions_purge','mstReadTechnicalReport()','sketchup.element_info()']},
 beam:{read:{oc:'mstBKLoadEdit()',label:'↻ Seçili BK\'yi Oku'},
       create:[{oc:'mstBKApplyEdit()',when:function(){return window.mstBKMode==='edit';}},{oc:'createActiveAnoHeadBeams()'}],
       more:['beam()','sketchup.universal_formwork_face_tool()','sketchup.rebar_paint_all()','sketchup.element_info()']},
 precast:{read:{oc:'readChannelFromBK()',label:'↻ Seçili BK\'yı Oku',when:function(){return pcTab()==='pk';}},
       create:[{oc:'createPD()',when:function(){return pcTab()==='pd';}},{oc:'createChannelPrecast()',when:function(){return pcTab()==='pk';}},{oc:'createCranePrecast()',when:function(){return pcTab()==='pv';}}],
       more:['sketchup.sync_precast()','mstPkKnPlace()','sketchup.kn_pockets()','sketchup.precast_type_rename()','sketchup.precast_to_component()','sketchup.precast_to_group()','sketchup.precast_purge_defs()','sketchup.universal_formwork_face_tool()']},
 deck:{read:{oc:'sketchup.deck_refresh()',label:'🔄 Seçili Döşemeyi Güncelle'},preview:{oc:'previewDeck()'},create:[{oc:'createDeck()'}],
       more:['createExistingDeckTopping()','sketchup.universal_formwork_face_tool()']},
 crown:{read:{oc:'loadSelectedCrown()'},preview:{oc:'updateSelectedCrown()'},create:[{oc:'createCrownWall()'}],
       more:['loadCrownExample()','sketchup.universal_formwork_face_tool()']},
 editor:{read:{oc:'refreshEditor()'},create:[{oc:"applyEditor('selected')"}],more:['sketchup.element_info()','sketchup.element_library()']},
 qto:{read:{oc:'refreshQTO()',label:'↻ Metrajı Yenile'},preview:{oc:'sketchup.takeoff_excel()',label:'⇩ Excel\'e Aktar'},create:[{oc:'sketchup.takeoff()',label:'▦ Detaylı Metraj Raporu'}],
       more:['sketchup.export_professional_excel()','sketchup.export_boq_csv()','sketchup.element_library()','sketchup.element_info()','sketchup.model_audit()']},
 boq:{read:{oc:'refreshBOQ()',label:'↻ Modelden Yenile'},preview:{oc:'bq2KesifExcel()',label:'⇩ Keşif Cetveli (Excel)'},create:[{oc:'saveBOQPrices()'}],more:['sketchup.boq_mapping()','sketchup.boq_library()']},
 revision:{read:{oc:'revisionRefresh()'},create:[{oc:'revisionSnapshot()'}]},
 progress:{read:{oc:'progressRefresh()'},preview:{oc:'pg2Excel()',label:'⇩ Hakediş Raporu (Excel)'},create:[{oc:'progressSave()',label:'✓ Hakedişi Kaydet'}],more:['progressDelete()']},
 settings:{create:[{oc:'saveRebarRates()'}]}
};
/* aynı işi yapan ikinci/üçüncü düğmeler (UI6) */
var DUPS={pile:['pile()','sketchup.pile_load_selected_for_edit()',"document.getElementById('count_x').focus()","document.getElementById('diameter_select').focus()","document.getElementById('top_elevation_m').focus()"],
 qto:['refreshQTO()'],boq:['refreshBOQ()']};
var SLOTCACHE={};
function slotBtn(pg,spec){
 if(!spec)return null;var list=Array.isArray(spec)?spec:[spec];
 for(var i=0;i<list.length;i++){var s=list[i];if(s.when&&!s.when())continue;var bs=byOc(pg,s.oc);if(bs.length)return {btn:bs[0],spec:s};}
 return null;
}
function prepPage(pg){
 if(!pg||pg.getAttribute('data-mst-std'))return;
 pg.setAttribute('data-mst-std','1');
 var cfg=ACT[pg.id]||{};
 /* bar'a vekil olan düğmeler sayfada gizlenir (bar onları tıklar) */
 ['read','preview'].forEach(function(k){if(!cfg[k])return;byOc(pg,cfg[k].oc).forEach(function(b){b.classList.add('mst-hidden-dup');});});
 (cfg.create||[]).forEach(function(s){byOc(pg,s.oc).forEach(function(b){b.classList.add('mst-hidden-dup');});});
 /* tekrarlar */
 (DUPS[pg.id]||[]).forEach(function(f){byOc(pg,f).forEach(function(b){b.classList.add('mst-hidden-dup');});});
 /* ikincil işlemler 'Diğer işlemler' listesine taşınır */
 var more=document.createElement('div');more.className='grp';more.setAttribute('data-page',pg.id);
 var seen={};
 (cfg.more||[]).forEach(function(f){byOc(pg,f).forEach(function(b){var k=oc(b)+'|'+b.textContent.trim();if(seen[k]){b.classList.add('mst-hidden-dup');return;}seen[k]=1;b.classList.remove('mst-hidden-dup');b.style.display='';more.appendChild(b);});});
 if(more.children.length)$('#mstMore').appendChild(more);
 /* aynı işi yapan kalan görünür düğmelerden yalnız sonuncusu kalır (satır düğmeleri hariç) */
 var last={};if(['pile','beam','precast'].indexOf(pg.id)<0)$$('button',pg).forEach(function(b){var o=oc(b);if(!o||/this\.|event\.|\(\s*\d/.test(o)||b.classList.contains('mst-hidden-dup'))return;if(last[o])last[o].classList.add('mst-hidden-dup');last[o]=b;});
}
function syncBar(){
 var bar=$('#mstStdBar'),pg=$('.page.on');if(!bar||!pg)return;
 var cfg=ACT[pg.id];
 if(!cfg){bar.classList.remove('on');$('#mstMore').classList.remove('on');return;}
 prepPage(pg);
 [['read','↻ Seçiliyi Oku'],['preview','👁 Önizle'],['create','✓ Oluştur / Güncelle']].forEach(function(p){
  var k=p[0],b=bar.querySelector('[data-slot="'+k+'"]'),r=slotBtn(pg,cfg[k]);
  if(!r){b.style.display='none';b._t=null;return;}
  b.style.display='';b._t=r.btn;
  var lab=(r.spec.label||(cfg[k]&&!Array.isArray(cfg[k])&&cfg[k].label)||r.btn.textContent.replace(/\s+/g,' ').trim()||p[1]);
  b.textContent=lab;
 });
 var grp=$('#mstMore .grp[data-page="'+pg.id+'"]');
 $$('#mstMore .grp').forEach(function(g){g.style.display=(g===grp)?'':'none';});
 bar.querySelector('[data-slot="more"]').style.display=grp?'':'none';
 if(!grp)$('#mstMore').classList.remove('on');
 bar.classList.add('on');
}
window.mstSyncBar=syncBar;
function buildBar(){
 if($('#mstStdBar'))return;
 var bar=document.createElement('div');bar.id='mstStdBar';
 bar.innerHTML='<span class="lbl">İşlemler</span><button type="button" class="secondary" data-slot="read"></button><button type="button" class="secondary" data-slot="preview"></button><button type="button" class="action" data-slot="create"></button><span class="grow"></span><button type="button" class="secondary" data-slot="more">⋯ Diğer işlemler</button>';
 document.body.appendChild(bar);
 var more=document.createElement('div');more.id='mstMore';more.innerHTML='<h4>Diğer işlemler</h4>';document.body.appendChild(more);
 $$('button[data-slot]',bar).forEach(function(b){
  var k=b.getAttribute('data-slot');
  b.onclick=function(){if(k==='more'){$('#mstMore').classList.toggle('on');return;}syncBar();if(b._t)b._t.click();setTimeout(syncBar,60);};
 });
 more.addEventListener('click',function(e){if(e.target.closest('button'))setTimeout(function(){more.classList.remove('on');},50);});
}

/* ---- UI6: prekast alt sekmeleri gerçekten çalışır; süs/boş paneller kalkar ---- */
function precastTabs(){
 var pg=$('#precast');if(!pg||pg.querySelector('.mst-sub-tabs'))return;
 var pd=[$('.pd-grid',pg)],pk=$$('.channel-precast-panel:not(.crane-precast-panel)',pg),pv=$$('.crane-precast-panel',pg);
 $$('.channel-tabs',pg).forEach(function(t){t.style.display='none';});
 var bar=document.createElement('div');bar.className='mst-sub-tabs';
 [['pd','PD · Normal / Dişli'],['pk','PK · Kanal Prekastı'],['pv','PV · Vinç Prekastı']].forEach(function(x){var b=document.createElement('button');b.type='button';b.setAttribute('data-tab',x[0]);b.textContent=x[1];b.onclick=function(){setTab(x[0]);};bar.appendChild(b);});
 var main=$('.precast-main',pg)||pg;main.insertBefore(bar,main.firstChild);
 function setTab(t){pg.setAttribute('data-pctab',t);$$('button',bar).forEach(function(b){b.classList.toggle('on',b.getAttribute('data-tab')===t);});
  pd.forEach(function(e){if(e)e.style.display=t==='pd'?'':'none';});pk.forEach(function(e){e.style.display=t==='pk'?'':'none';});pv.forEach(function(e){e.style.display=t==='pv'?'':'none';});
  var side=$('.precast-workspace > aside',pg);if(side)side.style.display=t==='pd'?'':'none';
  syncBar();}
 window.mstPrecastTab=setTab;setTab('pd');
}
function trimPanels(){
 /* şematik "3D Önizleme" kutuları gerçek model değil — kaldırıldı (gizlendi) */
 $$('#pile .panel-head h3, #beam .side-card > h3').forEach(function(h){if(h.textContent.trim()==='3D Önizleme'){var box=h.closest('section')||h.closest('.panel')||h.parentElement.parentElement;if(box)box.classList.add('mst-hidden-dup');}});
 /* BK şematik görünüş kutusu (ölçüsüz çizim) — kaldırıldı */
 $$('#beam h3').forEach(function(h){if(h.textContent.trim()==='Şematik Görünüş ve Ölçüler'){var box=h.closest('section');if(box)box.classList.add('mst-hidden-dup');}});
 /* kazık sayfası "Hızlı Erişim" (yalnız alana odaklanan düğmeler) */
 $$('#pile h3').forEach(function(h){if(h.textContent.trim()==='Hızlı Erişim'){var box=h.closest('section')||h.parentElement;if(box)box.classList.add('mst-hidden-dup');}});
 /* boş "Kazık Yöneticisi" şerit adımları vb. modül başlıkları std başlık ile değişti (CSS) */
}

/* ---- yeni sayfalar: Donatı BIM (7) ve Model Bakımı ---- */
function newPage(id,html){if($('#'+id))return;var d=document.createElement('div');d.id=id;d.className='page';d.innerHTML=html;var ref=$('#settings')||$('.page');ref.parentNode.insertBefore(d,ref);}
function buildPages(){
 newPage('rebar','<section class="mst-flow-card"><h3>Donatı nereden geliyor?</h3><p class="small">Donatısı <b>BIM</b> olarak çizilen elemanlarda metraj, keşif, rapor ve hakediş modellenen çubukların tonajını kullanır. Çizilmeyenlerde beton hacmi × pursantaj kullanılır. Bir elemanın donatısını BIM yapmak için ilgili adımdaki “Donatı BIM” bölümünü kullanın.</p><div id="mstRebarTable" class="small">okunuyor…</div><h4 style="margin:14px 0 6px;color:#073f73">Donatı metrajı — çap çap</h4><p class="small">Hakediş (Keşif ÖBF-004) tek poz; bu tablo kontrol ve sipariş içindir.</p><div id="mstRebarDia" class="small">okunuyor…</div></section>'+
  '<section class="mst-flow-card"><h3>Donatı araçları</h3><p class="small" id="mstRebarSet">Ayarlar okunuyor…</p><div class="mst-flow-grid">'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'rebar_upgrade\')">⟳ Eski Donatıyı Yeniden Çiz<small>v0.48 donatısı → yeni kurallar (kayıtlı parametrelerle)</small></button>'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'rebar_settings\')">⚙ Donatı Ayarları<small>Pas payı BK / döşeme / prekast · bindirme ×Ø · şaşırtma</small></button>'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'rebar_toggle\')">👁 Donatıyı Göster / Gizle<small>Bütün MST | DONATI tag\'leri</small></button>'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'bending\')">📋 Bükme Listesi + Kesim Planı<small>Excel + krokili liste, 12 m stoktan fire</small></button>'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'section\')">✂ Donatı Kesiti<small>Seçili BK, istenen noktada</small></button>'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'revision\')">⇄ Revizyon Karşılaştırması<small>Seçili eleman: önce ↔ şimdi</small></button>'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'clash\')">⚠ Elemanlar Arası Çakışma<small>BK / döşeme / prekast donatıları</small></button>'+
  '<button type="button" class="secondary" onclick="mstRebarTool(\'clash_clear\')">🧽 Çakışma Renklerini Temizle<small>Çap rengine döner</small></button></div></section>'+
  '<section class="mst-flow-card"><h3>Donatı BIM oluştur</h3><div class="mst-flow-grid">'+
  '<button type="button" class="secondary" onclick="mstGoSection(\'beam\',\'Donatı BIM\')">▦ Başlık Kirişi Donatısı<small>Adım 3 · 5. Donatı BIM bölümü</small></button>'+
  '<button type="button" class="secondary" onclick="mstGoSection(\'deck\',\'Donatı BIM\')">▦ Döşeme Donatısı<small>Adım 5 · 5. Döşeme Donatı BIM bölümü</small></button>'+
  '<button type="button" class="secondary" onclick="mstGoSection(\'pile\',\'Donatı\')">▦ Kazık İçi Donatı Kafesi<small>Adım 2 · kazık donatısı bölümü</small></button>'+
  '<button type="button" class="secondary" onclick="if(window.sketchup&&sketchup.rebar_paint_all)sketchup.rebar_paint_all()">🎨 Donatıları Çapa Göre Renklendir<small>Mevcut bütün çubuklar</small></button>'+
  '<button type="button" class="secondary" onclick="if(window.sketchup&&sketchup.rebar_retag)sketchup.rebar_retag()">🏷 Donatı Tag\'lerini Güncelle<small>Yapıya (ANO) göre: MST | DONATI | YD-02 …</small></button>'+
  '<button type="button" class="secondary" onclick="mstShowPage(\'settings\')">⚙ Pursantajlar<small>Ayarlar sayfası</small></button></div></section>');
 newPage('maint','<section class="mst-flow-card"><h3>Bakım Araçları</h3><p class="small">Eskiden Eklentiler menüsünde duran bütün bakım araçları. Her işlem kendi önizlemesini / onayını gösterir ve tek Geri Al ile geri alınır.</p><div id="mstMaintBody">okunuyor…</div></section>');
}
window.mstGoSection=function(page,text){mstShowPage(page);setTimeout(function(){var hs=$$('#'+page+' h3');for(var i=0;i<hs.length;i++){if(hs[i].textContent.indexOf(text)>=0&&vis(hs[i])){hs[i].scrollIntoView({block:'start',behavior:'smooth'});break;}}},80);};
window.mstRebarRefresh=function(){if(window.sketchup&&sketchup.rebar_sources_get)sketchup.rebar_sources_get();};
window.mstRebarPage=function(d){var el=$('#mstRebarTable');if(!el)return;var rows=(d&&d.rows)||[];if(!rows.length){el.textContent='Modelde donatılı eleman yok.';return;}var tot=0,bim=0;
 var h='<table class="qto-table"><thead><tr><th>Eleman</th><th>Adet</th><th>Kaynak</th><th>Donatı (t)</th></tr></thead><tbody>';
 rows.forEach(function(r){var t=Number(r.t||0);tot+=t;if(String(r.label).indexOf('BIM')===0&&String(r.label).indexOf('+')<0)bim+=t;h+='<tr><td>'+esc(r.name)+'</td><td>'+(r.count||'-')+'</td><td>'+esc(r.label)+'</td><td>'+t.toFixed(3)+'</td></tr>';});
 h+='<tr class="total"><td>TOPLAM (Keşif ÖBF-004)</td><td></td><td>'+(tot>0?Math.round(bim/tot*100):0)+'% tamamen BIM</td><td>'+tot.toFixed(3)+'</td></tr></tbody></table>';el.innerHTML=h;
 var dd=$('#mstRebarDia');if(dd&&d&&d.dia){var t2='<table class="qto-table"><thead><tr><th>Çap</th><th>Donatı (t)</th></tr></thead><tbody>';(d.dia.rows||[]).forEach(function(r){t2+='<tr><td>'+esc(r.label)+'</td><td>'+(Number(r.kg||0)/1000).toFixed(3)+'</td></tr>';});t2+='<tr class="total"><td>TOPLAM (= Keşif ÖBF-004, tek poz)</td><td>'+(Number(d.dia.total_kg||0)/1000).toFixed(3)+'</td></tr></tbody></table>';dd.innerHTML=t2;}
 if(d&&d.settings&&window.mstApplyRebarSettings)mstApplyRebarSettings(d.settings);};
window.mstRebarTool=function(k){if(window.sketchup&&sketchup.rebar_tool)sketchup.rebar_tool(k);};
window.mstApplyRebarSettings=function(st){if(!st)return;var set=function(id,v){var e=document.getElementById(id);if(e&&v!=null)e.value=String(Math.round(Number(v)));};set('dr_cover_mm',st.cover_deck_mm);set('dr_lap_d',st.lap_d);set('hb_rebar_cover',st.cover_bk_mm);var g=document.getElementById('dr_stagger');if(g)g.value=String(Number(st.stagger)?1:0);
 var el=$('#mstRebarSet');if(el)el.innerHTML='Pas payı: BK <b>'+Math.round(st.cover_bk_mm)+' mm</b> · döşeme <b>'+Math.round(st.cover_deck_mm)+' mm</b> · prekast <b>'+Math.round(st.cover_precast_mm)+' mm</b> · bindirme <b>'+Math.round(st.lap_d)+'Ø</b> '+(Number(st.stagger)?'şaşırtmalı':'aynı kesitte')+' · donatı <b>'+(Number(st.rebar_visible)?'görünür':'gizli')+'</b>';};
window.mstMaintRefresh=function(){if(window.sketchup&&sketchup.maint_list)sketchup.maint_list();};
window.mstMaintRender=function(items){var el=$('#mstMaintBody');if(!el)return;var g={},order=[];(items||[]).forEach(function(it){if(!g[it.group]){g[it.group]=[];order.push(it.group);}g[it.group].push(it);});
 el.innerHTML=order.map(function(k){return '<h4 style="margin:14px 0 8px;color:#073f73">'+esc(k)+'</h4><div class="mst-flow-grid">'+g[k].map(function(it){return '<button type="button" class="secondary" data-k="'+esc(it.key)+'">'+esc(it.title)+'<small>'+esc(it.desc)+'</small></button>';}).join('')+'</div>';}).join('');
 $$('button[data-k]',el).forEach(function(b){b.onclick=function(){if(window.sketchup&&sketchup.maint_action)sketchup.maint_action(b.getAttribute('data-k'));};});};

/* ---- durum rozetleri (Ruby: workflow_status) ---- */
window.mstFlowStatus=function(st){STATUS=st||{};
 $$('.tabs button[data-flow]').forEach(function(b){var k=b.getAttribute('data-flow');var s=STATUS[k];var em=b.querySelector('.mst-st');if(em){em.setAttribute('data-st',s?s.state:'');em.title=s?s.text:'';}});
 $$('.page').forEach(paintHead);
};
var stTimer=null;
function askStatus(){clearTimeout(stTimer);stTimer=setTimeout(function(){if(window.sketchup&&sketchup.workflow_status){var pg=document.querySelector('.page.on');sketchup.workflow_status(pg?pg.id:'');}},150);}   /* G1: açık sayfa Ruby'ye bildirilir (Çalışma Alanı yalnız açıkken yenilenir) */
window.mstAskStatus=askStatus;

/* ---- T() sarmalayıcı: her sayfa açılışında aynı iskelet ---- */
function wrapT(){
 if(!window.T||window.T._mst)return;var orig=window.T;
 var w=function(id,b){
  if(!b){b=navBtn(id)||document.createElement('button');}
  var r=orig.apply(this,[id,b]);
  var nb=navBtn(id);if(nb&&nb!==b){$$('.tabs button').forEach(function(x){x.classList.remove('on');});nb.classList.add('on');}
  var pg=document.getElementById(id);stdHead(pg);syncBar();askStatus();
  if(id==='rebar')mstRebarRefresh();if(id==='maint')mstMaintRefresh();
  return r;};
 w._mst=true;window.T=w;
 try{T=w;}catch(e){}
}
function init(){
 try{buildPages();buildNav();buildBar();precastTabs();trimPanels();wrapT();
  $$('.page').forEach(stdHead);
  /* gömülü sayfalar oluşunca da aynı başlık */
  var host=$('#settings');if(host&&window.MutationObserver){new MutationObserver(function(ms){ms.forEach(function(m){Array.prototype.forEach.call(m.addedNodes,function(n){if(n.classList&&n.classList.contains('mst-embed-page')){stdHead(n);}});});}).observe(host.parentNode,{childList:true});}
  var on=$('.page.on');if(on){var nb=navBtn(on.id);if(nb){$$('.tabs button').forEach(function(x){x.classList.remove('on');});nb.classList.add('on');}}
  syncBar();askStatus();
  setInterval(function(){if(document.visibilityState!=='hidden')syncBar();},1500);
  window.addEventListener('focus',askStatus);
 }catch(e){console.error('MST iş akışı arayüzü:',e);}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){setTimeout(init,0);});else setTimeout(init,0);
})();
