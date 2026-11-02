(function(global){
 'use strict';
 var state={records:[],token:null,expanded:new Set(),focus:[],selected:[],scope:false,ready:false,query:'',filters:{type:'',structure:'',axis:'',status:'all'}};
 var viewCache=null,focusCache=null,searchTimer=null,page=0,revealKey=null,pendingBeam=null;
 var fields={project:'Proje',system:'Sistem',structure:'Yapı',axis:'Aks',library_type_id:'Tip kimliği',concrete_class:'Beton sınıfı',steel_grade:'Çelik kalitesi',diameter_mm:'Çap (mm)',thickness_mm:'Et kalınlığı (mm)',length_m:'Boy (m)',width_m:'Genişlik (m)',height_m:'Yükseklik (m)'};
 var metrics={concrete_m3:'Beton',steel_t:'Boru çeliği',rebar_t:'Donatı',formwork_m2:'Kalıp'};
 function el(id){return document.getElementById(id);}
 function clear(node){while(node.firstChild)node.removeChild(node.firstChild);}
 function text(tag,value,cls){var n=document.createElement(tag);n.textContent=value;if(cls)n.className=cls;return n;}
 function labels(r){var f=r.fields;return [f.project||'Proje atanmamış',f.system||'Sistem atanmamış',f.structure||'Yapı atanmamış',f.axis||'Aks atanmamış',r.label];}
 function searchable(r){return [r.id,r.uid,r.label,'Ø'+(r.fields.diameter_mm||''),'t'+(r.fields.thickness_mm||'')].concat(Object.keys(r.fields).map(function(k){return r.fields[k];})).join(' ').toLocaleLowerCase('tr-TR');}
 function unassigned(value){return value===null||value===undefined||String(value).trim()==='';}
 function visible(records,query,filters){var terms=(query||'').trim().toLocaleLowerCase('tr-TR').split(/\s+/).filter(Boolean);filters=filters||{};return records.filter(function(r){
  var haystack=searchable(r);if(!terms.every(function(term){return haystack.includes(term);}))return false;
  if(filters.type&&r.type!==filters.type)return false;
  if(filters.structure&&r.fields.structure!==filters.structure)return false;
  if(filters.axis&&r.fields.axis!==filters.axis)return false;
  var values=Object.keys(r.quantities||{}).map(function(k){return r.quantities[k];});
  if(filters.status==='issues'&&!(r.issues||[]).length)return false;
  if(filters.status==='incomplete'&&!Object.keys(metrics).some(function(k){var q=(r.quantities||{})[k];return !q||q.state==='missing'||q.state==='invalid';}))return false;
  if(filters.status==='estimated'&&!values.some(function(q){return q&&q.state==='estimated';}))return false;
  if(filters.status==='unassigned'&&!unassigned(r.fields.structure)&&!unassigned(r.fields.axis))return false;
  return true;
 });}
 function view(){var signature=JSON.stringify([state.query,state.filters]);if(!viewCache||viewCache.source!==state.records||viewCache.signature!==signature){var records=visible(state.records,state.query,state.filters);page=0;viewCache={rows:null,source:state.records,signature:signature,records:records,tree:build(records),keys:new Set(records.map(function(r){return r.key;}))};}return viewCache;}
 function filtered(){return view().records;}
 function cancelSearch(accept){if(searchTimer!==null)clearTimeout(searchTimer);searchTimer=null;if(accept)state.query=el('pwSearch').value;}
 function searchChanged(){cancelSearch(false);el('pwInspectResults').disabled=true;el('pwCount').textContent='Arama güncelleniyor…';searchTimer=setTimeout(function(){searchTimer=null;state.query=el('pwSearch').value;renderTree();},140);}
 function activeFilters(){return !!(state.query.trim()||state.filters.type||state.filters.structure||state.filters.axis||state.filters.status!=='all');}
 function fillFilter(id,key,label){var node=el(id),previous=node.value;clear(node);var option=text('option',label);option.value='';node.appendChild(option);var representatives=new Map();state.records.forEach(function(r){var value=key==='type'?r.type:r.fields[key];if(!unassigned(value)&&!representatives.has(value))representatives.set(value,r);});var values=Array.from(representatives.keys()).sort(function(a,b){return String(a).localeCompare(String(b),'tr',{numeric:true});});values.forEach(function(value){var row=representatives.get(value),item=text('option',key==='type'?row.label:String(value));item.value=value;node.appendChild(item)});node.value=values.includes(previous)?previous:'';state.filters[key]=node.value;}
 function updateFilters(){fillFilter('pwTypeFilter','type','Tüm türler');fillFilter('pwStructureFilter','structure','Tüm yapılar');fillFilter('pwAxisFilter','axis','Tüm akslar');}
 function resetFilters(){state.query='';state.filters={type:'',structure:'',axis:'',status:'all'};el('pwSearch').value='';['pwTypeFilter','pwStructureFilter','pwAxisFilter'].forEach(function(id){el(id).value=''});el('pwIssueFilter').value='all';}
 function build(records){
  var root={children:[],keys:[],index:{}};
  records.forEach(function(r){
   var node=root,path=[];
   labels(r).forEach(function(label){
    path.push(String(label));var key='g:'+JSON.stringify(path);
    if(!node.index[key]){node.index[key]={key:key,label:String(label),children:[],keys:[],index:{}};node.children.push(node.index[key]);}
    node=node.index[key];node.keys.push(r.key);
   });
   node.children.push({key:'e:'+r.key,label:r.id,record:r,keys:[r.key],children:[]});
  });
  function sort(n){n.children.sort(function(a,b){return a.label.localeCompare(b.label,'tr',{numeric:true});});n.children.forEach(sort);}
  sort(root);return root;
 }
 function quantitySummary(values,unit){
  var counts={calculated:0,estimated:0,missing:0,invalid:0,not_applicable:0},sums={calculated:0,estimated:0};
  values.forEach(function(q){var status=q&&typeof q==='object'?q.state:'missing';if(!Object.prototype.hasOwnProperty.call(counts,status))status='invalid';if(['calculated','estimated','not_applicable'].includes(status)&&(typeof q.value!=='number'||!Number.isFinite(q.value)||q.value<0||(status==='not_applicable'&&q.value!==0)))status='invalid';counts[status]++;if(status==='calculated'||status==='estimated')sums[status]+=q.value;});
  var total=sums.calculated+sums.estimated,overflow=!Number.isFinite(total),incomplete=counts.missing>0||counts.invalid>0||overflow;
  return {value:incomplete?null:total,unit:unit,incomplete:incomplete,estimated:counts.estimated>0,counts:counts,calculated_value:Number.isFinite(sums.calculated)?sums.calculated:null,estimated_value:Number.isFinite(sums.estimated)?sums.estimated:null,overflow:overflow};
 }
 function summarize(records){
  var common=Object.keys(fields).map(function(k){
   var values=records.map(function(r){return r.fields[k];}),mixed=values.length>0&&!values.every(function(v){return v===values[0];});
   return {key:k,label:fields[k],value:mixed?null:values[0],mixed:mixed};
  }),totals={};
  Object.keys(metrics).forEach(function(k){
   var values=records.map(function(r){return r.quantities[k];});
   totals[k]=quantitySummary(values,k==='concrete_m3'?'m³':k==='formwork_m2'?'m²':'t');
  });
  return {count:records.length,keys:records.map(function(r){return r.key;}),common:common,totals:totals,issues:Array.from(new Set(records.reduce(function(a,r){return a.concat(r.issues||[]);},[])))};
 }
 function focusRows(){if(!focusCache||focusCache.source!==state.records||focusCache.keys!==state.focus){var keys=new Set(state.focus);focusCache={source:state.records,keys:state.focus,rows:state.records.filter(function(r){return keys.has(r.key);})};}return focusCache.rows;}
 function renderProperties(summary){
  summary=summary||summarize(focusRows());var count=summary.count;
  el('pwTitle').textContent=state.scope?'Kapsam Özellikleri':'Eleman Özellikleri';
  el('pwSelection').textContent=count?(state.scope?'İncelenen kapsam: ':'Seçim: ')+count+' eleman'+(count>1?' · Ortak ve farklı değerler aşağıda gösterilir.':''):'Ağaçtan bir kapsam veya modelden bir eleman seçin.';
  el('pwModelSelection').textContent='Model: '+state.selected.length+' seçili';
  el('pwShow').disabled=!state.ready||!count;el('pwHealth').disabled=!state.ready||!count;var editable=focusRows().length===1&&['steel_pipe_pile','head_beam','flat_precast','channel_precast'].includes(focusRows()[0].type);el('pwEdit').disabled=!state.ready||!editable;el('pwEdit').textContent=editable?'Elemanı Düzenle':'Düzenleme Hazır Değil';el('pwEdit').title=!editable?'Tek bir kazık, BK, normal ya da kanal prekastı seçin.':focusRows()[0].type==='steel_pipe_pile'?'Kazık sayfasında ortak formda açılır.':focusRows()[0].type==='head_beam'?'Başlık Kirişi sayfasında ortak formda açılır.':'Kontrollü Düzenleme panelinde açılır (önizleme ve onay).';el('pwQTO').disabled=!state.ready;var concreteTypes=['head_beam','flat_precast','channel_precast','crane_precast','deck_slab','curb'];el('pwElevation').disabled=!state.ready||!focusRows().length||!focusRows().every(function(r){return ['head_beam','flat_precast','channel_precast','crane_precast','deck_slab'].includes(r.type)});el('pwMaterial').disabled=!state.ready||!focusRows().length||!focusRows().every(function(r){return concreteTypes.includes(r.type)});
  var container=el('pwMetrics');clear(container);
  Object.keys(metrics).forEach(function(k){
   var value=summary.totals[k],card=document.createElement('div');
   card.appendChild(text('small',metrics[k]));card.appendChild(text('b',!count?'—':value.overflow?'Sayısal sınır aşıldı':value.incomplete?'Toplam tamamlanmadı':value.counts&&value.counts.not_applicable===count?'Uygulanmaz':Number(value.value).toLocaleString('tr-TR',{maximumFractionDigits:3})+' '+value.unit+(value.estimated?' · Tahmini içerir':'')));if(count&&value.counts){var c=value.counts;function amount(n){return n===null?'Sayısal sınır aşıldı':Number(n).toLocaleString('tr-TR',{maximumFractionDigits:3})+' '+value.unit;}card.appendChild(text('small','Hesaplanmış: '+amount(value.calculated_value)+' · '+c.calculated+' eleman'));card.appendChild(text('small','Tahmini: '+amount(value.estimated_value)+' · '+c.estimated+' eleman'));if(c.missing||c.invalid)card.appendChild(text('small','Eksik: '+c.missing+' · Geçersiz: '+c.invalid+' eleman'));if(c.not_applicable)card.appendChild(text('small','Uygulanmaz: '+c.not_applicable+' eleman'));if(value.incomplete)card.appendChild(text('small',value.overflow?'Sayısal toplam sınırı aşıldı; toplam gösterilmiyor.':'Yalnız mevcut geçerli miktarlar gösteriliyor; kapsam toplamı tamamlanmadı.'));}container.appendChild(card);
  });
  container=el('pwIssues');clear(container);
  (summary.issues||[]).forEach(function(issue){container.appendChild(text('p',issue));});
  container=el('pwProperties');clear(container);
  (summary.common||[]).forEach(function(item){
   container.appendChild(text('dt',item.label));
   container.appendChild(text('dd',!count?'—':item.mixed?'Farklı değerler':item.value===null||item.value===undefined||item.value===''?'Atanmamış':String(item.value),item.mixed?'mixed':''));
  });
  container=el('pwElements');clear(container);
  focusRows().slice(0,300).forEach(function(r){var button=text('button',r.id+' · '+r.label);button.onclick=function(){setFocus([r.key],false);action(false,false);};container.appendChild(button);});
  if(count>300)container.appendChild(text('p','İlk 300 eleman gösteriliyor. Ağacı arayarak kapsamı daraltın.'));
  renderDeps();
 }
 /* 02.11.2026: Eleman başına bağımlılık listesi (eski Eleman Düzenleyici edDepList görünümü) Çalışma Alanı özellik panelinde.
    Mevcut salt okuma callback'i dependency_analysis kullanılır; Ruby setDependencyAnalysis(d) ile döner, ui.html'deki işlev buraya da iletir.
    Otomatik çağrı yok: hesap yalnız "Bağımlılıkları Göster" düğmesiyle başlar. */
 var depTypes={steel_pipe_pile:'Çelik boru kazık',head_beam:'Başlık kirişi',flat_precast:'Normal prekast',channel_precast:'Kanal prekastı',crane_precast:'Vinç prekastı',deck_slab:'Döşeme',curb:'Bordür / tretuvar',crown_wall:'Kronman',bored_pile:'Fore kazık',pile_infill_concrete:'Kazık içi beton',deck_topping:'Kaplama'};
 var dep={key:null,pending:false,timer:null,data:null,note:''},depIndex=null;
 function depTypeLabel(t){return depTypes[t]||t||'Tür bilinmiyor';}
 function depTarget(){var rows=focusRows();if(!state.ready||rows.length!==1)return null;if(state.selected.length!==1||state.selected[0]!==rows[0].key)return null;return rows[0];}
 function depStop(){if(dep.timer!==null)clearTimeout(dep.timer);dep.timer=null;dep.pending=false;}
 function depInvalidate(note){var had=!!dep.data||dep.pending;depStop();dep.data=null;dep.note=had?note:'';}
 function depRecord(item){
  if(!depIndex||depIndex.source!==state.records){var byUid={},byId={};state.records.forEach(function(r){if(r.uid)(byUid[r.uid]=byUid[r.uid]||[]).push(r);var k=r.id+'|'+r.type;(byId[k]=byId[k]||[]).push(r);});depIndex={source:state.records,byUid:byUid,byId:byId};}
  var list=item.uid?depIndex.byUid[item.uid]:null;if(list&&list.length===1)return list[0];
  list=depIndex.byId[item.id+'|'+item.type];return list&&list.length===1?list[0]:null;
 }
 function depRow(item,depth){
  var record=depRecord(item),label=(depth?'↳ ':'')+(item.id||'Kimliksiz')+' · '+depTypeLabel(item.type),node;
  if(record){node=text('button',label,'pw-dep-row');node.type='button';node.title='Çalışma Alanı\'nda seç ve modelde göster'+(item.uid?' · UID: '+item.uid:'');node.onclick=function(){if(!state.ready)return;reveal([record.key]);setFocus([record.key],false);action(false,false);};}
  else{node=text('div',label+' · Çalışma Alanı listesinde tekil eşleşme yok','pw-dep-row pw-dep-plain');if(item.uid)node.title='UID: '+item.uid;}
  if(depth>1)node.style.paddingLeft=(8+(depth-1)*14)+'px';
  return node;
 }
 function depList(container,title,items,depthKey,empty){
  container.appendChild(text('h5',title+': '+items.length+' eleman'));
  if(!items.length){container.appendChild(text('p',empty,'note'));return;}
  var box=text('div','','pw-dep-list');items.slice(0,300).forEach(function(x){box.appendChild(depRow(x,depthKey?Number(x.depth)||1:0));});container.appendChild(box);
  if(items.length>300)container.appendChild(text('p','İlk 300 satır gösteriliyor.','note'));
 }
 function renderDeps(){
  var section=el('pwDeps');if(!section)return;
  var target=depTarget(),key=target?target.key:null,rows=focusRows();
  if(dep.key!==key){depInvalidate('Seçim değişti; önceki bağımlılık sonucu temizlendi.');dep.key=key;}
  var button=el('pwDepRun'),status=el('pwDepStatus'),body=el('pwDepBody');clear(body);
  button.disabled=!target||dep.pending;button.textContent=dep.pending?'Hesaplanıyor…':'Bağımlılıkları Göster';
  if(!target){status.textContent=!state.ready?'Model okunuyor…':!rows.length?'Bağımlılıklar tek eleman için gösterilir. Bir eleman seçin.':rows.length>1?'Bağımlılıklar tek eleman için gösterilir. Kapsamda '+rows.length+' eleman var; tek bir eleman seçin.':'Eleman modelde seçili değil. Ağaçta elemana tıklayın, sonra düğmeye basın.';return;}
  if(dep.pending){status.textContent='Hesaplanıyor… ('+target.id+' için tüm model ilişkileri taranıyor)';return;}
  var d=dep.data;
  if(!d){status.textContent=(dep.note?dep.note+' ':'')+target.id+' için bağımlılıkları görmek üzere "Bağımlılıkları Göster" düğmesine basın.';return;}
  status.textContent=d.root_id+' · '+depTypeLabel(d.root_type)+': '+(d.parents||[]).length+' doğrudan üst eleman, '+(Number(d.affected_count)||0)+' etkilenen eleman (aşağı akış).';
  depList(body,'Bağlı olduğu (doğrudan üst)',d.parents||[],false,'Kayıtlı üst ilişki yok.');
  depList(body,'Etkilediği (aşağı akış, tüm kademeler)',d.items||[],true,'Kayıtlı aşağı akış bağımlılığı yok.');
  if(d.impacts&&d.impacts.length)body.appendChild(text('p','Etkilenebilecek metraj / işlemler (kural listesi, miktar hesabı değil): '+d.impacts.join(' · '),'note'));
  body.appendChild(text('p','Kaynak: kayıtlı ilişki bilgileri (BK bağlı kazık kimlikleri, prekast ve döşeme mesnet kayıtları, bordür üst eleman kaydı). Geometriden ölçülmez; kaydı eksik ilişki listede görünmez. Model değişirse sonuç temizlenir.','note pw-dep-source'));
 }
 function depRun(){
  var target=depTarget();if(!target||dep.pending)return;
  if(!(global.sketchup&&sketchup.dependency_analysis)){dep.note='SketchUp bağlantısı hazır değil.';renderDeps();return;}
  dep.data=null;dep.note='';dep.pending=true;renderDeps();
  dep.timer=setTimeout(function(){dep.timer=null;if(!dep.pending)return;dep.pending=false;dep.note='Yanıt gelmedi. Model büyükse biraz bekleyip yeniden deneyin.';renderDeps();},30000);
  sketchup.dependency_analysis();
 }
 function depReceived(d){
  var target=depTarget();if(!target||!el('pwDeps'))return;
  if(!d||!d.ok){if(dep.pending){depStop();dep.note=(d&&d.message)||'Bağımlılık analizi yapılamadı.';renderDeps();}return;}
  var same=d.root_id===target.id&&d.root_type===target.type&&(!d.root_uid||!target.uid||d.root_uid===target.uid);
  if(!same){if(dep.pending){depStop();dep.note='Gelen sonuç seçili elemana ait değil ('+d.root_id+'). Seçimi kontrol edip yeniden deneyin.';renderDeps();}return;}
  depStop();dep.data=d;dep.note='';renderDeps();
 }
 function setFocus(keys,scope){state.focus=keys;state.scope=scope;renderProperties();renderTree();}
 function treeRows(cached){if(!cached.rows){var result=[];function visit(node,depth,context){result.push({node:node,depth:depth,context:context});if(node.children.length&&(state.expanded.has(node.key)||state.query))node.children.forEach(function(child){visit(child,depth+1,context.concat(node.label));});}cached.tree.children.forEach(function(node){visit(node,0,[])});cached.rows=result;}return cached.rows;}
 function invalidateRows(){if(viewCache)viewCache.rows=null;}
 function renderTree(){
  var cached=view(),records=cached.records,root=cached.tree,selected=new Set(state.selected),container=el('pwTree');clear(container);
  el('pwInspectResults').disabled=!state.ready||!records.length||searchTimer!==null;var outside=state.focus.filter(function(key){return !cached.keys.has(key);}).length;el('pwCount').textContent=records.length+' / '+state.records.length+' eleman'+(activeFilters()?' · Filtre sonucu':'')+(outside?' · İncelenen seçimde '+outside+' eleman filtre dışında.':'');
  function add(node,parent,depth,context){
   var group=node.children.length>0,line=text('div','','pw-line'),toggle=text('button',group?(state.expanded.has(node.key)||state.query?'▾':'▸'):'·','pw-toggle');
   toggle.type='button';
   if(group){toggle.setAttribute('aria-label',node.label+' alt satırlarını aç veya kapat');toggle.setAttribute('aria-expanded',String(state.expanded.has(node.key)||!!state.query));toggle.onclick=function(){invalidateRows();if(state.expanded.has(node.key))state.expanded.delete(node.key);else state.expanded.add(node.key);renderTree();};}
   else{toggle.disabled=true;toggle.setAttribute('aria-hidden','true');}
   var button=text('button','','pw-node');button.type='button';button.appendChild(text('span',node.label||'Adsız eleman'));
   if(group)button.appendChild(text('small',String(node.keys.length)));
   else if(node.record.issues.length)button.appendChild(text('small','!'));
   button.title=node.record?context.concat([node.record.id,node.record.uid||'Kimlik eksik',node.record.nested?'İç içe yerleşim':'Ana düzey']).join(' · '):node.label+' · '+node.keys.length+' eleman';
   button.onclick=function(){setFocus(node.keys,group);if(!group)action(false,false);};
   if(!group&&selected.has(node.record.key)){line.classList.add('selected');button.setAttribute('aria-pressed','true');}
   line.style.marginLeft=(depth*13)+'px';line.appendChild(toggle);line.appendChild(button);parent.appendChild(line);
  }
  if(!records.length)container.appendChild(text('p',activeFilters()?'Bu arama ve filtrelere uygun eleman bulunamadı.':'Modelde desteklenen yapı elemanı bulunamadı.','note'));
  var rows=treeRows(cached),size=300;
  if(revealKey){var index=rows.findIndex(function(row){return row.node.record&&row.node.record.key===revealKey;});if(index>=0)page=Math.floor(index/size);revealKey=null;}
  page=Math.min(page,Math.max(0,Math.ceil(rows.length/size)-1));var start=page*size,end=Math.min(start+size,rows.length);
  if(rows.length>size){container.appendChild(text('p','Ağaç satırları: '+(start+1)+'–'+end+' / '+rows.length+'. Kapsam ve miktarlar bütün sonuçları kullanır.','note'));if(rows[start].context.length)container.appendChild(text('p','Sayfa başlangıcı: '+rows[start].context.join(' › '),'note'));}
  function pageControls(){var controls=text('div','','pw-toolbar'),previous=text('button','Önceki Satırlar'),next=text('button','Sonraki Satırlar');previous.disabled=page===0;next.disabled=end===rows.length;previous.onclick=function(){if(previous.disabled)return;page--;renderTree();container.scrollTop=0;};next.onclick=function(){if(next.disabled)return;page++;renderTree();container.scrollTop=0;};controls.appendChild(previous);controls.appendChild(next);container.appendChild(controls);}
  if(rows.length>size)pageControls();
  rows.slice(start,end).forEach(function(row){add(row.node,container,row.depth,row.context);});
  if(rows.length>size)pageControls();

 }
 function reveal(keys){
  invalidateRows();revealKey=keys[0]||null;var wanted=new Set(keys);state.records.filter(function(r){return wanted.has(r.key);}).forEach(function(r){
   var path=[];labels(r).forEach(function(label){path.push(String(label));state.expanded.add('g:'+JSON.stringify(path));});
  });
 }
 function refresh(){
  cancelSearch(true);state.ready=false;el('pwStatus').textContent='Model okunuyor…';renderProperties();renderTree();
  if(global.sketchup&&sketchup.project_workspace_refresh)sketchup.project_workspace_refresh();
  else error('SketchUp bağlantısı hazır değil.');
 }
 function action(zoom,edit){
  if(!state.ready||!state.focus.length)return;
  var request={model_token:state.token,keys:state.focus,zoom:!!zoom,edit:!!edit};
  if(global.sketchup&&sketchup.project_workspace_action)sketchup.project_workspace_action(JSON.stringify(request));
 }
 /* 02.11.2026 NCR-003: BK, Kontrollü Düzenleme yerine BK sayfasındaki ortak formda düzenlenir.
    Önce aynı select aksiyonu (edit:false) ile BK modelde seçilir; seçim geri gelince BK sayfası açılır ve "Seçili BK'yi Oku" yolu çalışır. */
 function editBeam(record){
  if(!state.ready)return;
  pendingBeam={key:record.key,at:Date.now()};
  el('pwStatus').textContent=record.id+' modelde seçiliyor; Başlık Kirişi sayfasında ortak forma yüklenecek…';
  action(false,false);
 }
 function consumeBeam(){
  if(!pendingBeam)return;
  if(Date.now()-pendingBeam.at>5000){pendingBeam=null;return;}
  if(state.selected.length!==1||state.selected[0]!==pendingBeam.key)return;
  pendingBeam=null;global.projectWorkspaceOpenBeamEditor();
 }
 function loaded(data){
  cancelSearch(true);viewCache=null;focusCache=null;page=0;revealKey=null;
  depInvalidate('Model güncellendi; önceki bağımlılık sonucu temizlendi.');
  if(state.token&&state.token!==data.model_token){state.focus=[];state.selected=[];state.expanded.clear();state.scope=false;resetFilters();}state.records=data.records||[];state.token=data.model_token;updateFilters();state.ready=true;state.selected=(data.selection&&data.selection.keys)||[];
  if(state.selected.length){state.focus=state.selected.slice();state.scope=false;reveal(state.selected);}
  else{var available=new Set(state.records.map(function(r){return r.key;}));state.focus=state.focus.filter(function(key){return available.has(key);});}
  if(!state.expanded.size)view().tree.children.forEach(function(n){state.expanded.add(n.key);});
  el('pwStatus').textContent=state.records.length+' yapı elemanı okundu.'+(data.duplicate_uid_count?' '+data.duplicate_uid_count+' kimlik birden fazla fiziksel yerleşimde kullanılıyor; kontrol gerekli.':'')+' Özellikler okunur; düzenleme için elemanı seçin.';
  renderTree();renderProperties();consumeBeam();
 }
 function selection(data,token){
  if(token!==state.token){error('Aktif model değişti. Modeli Yenile düğmesine basın.',true);return;}
  state.selected=data.keys||[];state.focus=state.selected.slice();state.scope=false;reveal(state.selected);renderTree();renderProperties(data);consumeBeam();
 }
 function error(message,stale){pendingBeam=null;if(stale){cancelSearch(true);state.ready=false;}el('pwStatus').textContent=message;renderProperties();renderTree();}
 function navigate(id){
  var buttons=document.querySelectorAll('.tabs button'),button=Array.from(buttons).find(function(b){return (b.getAttribute('onclick')||'').includes("T('"+id+"'");});
  if(button){T(id,button);if(id==='editor')refreshEditor();}
 }
 function init(){
  if(!el('project_workspace'))return;
  el('pwSearch').addEventListener('input',searchChanged);
  [['pwTypeFilter','type'],['pwStructureFilter','structure'],['pwAxisFilter','axis'],['pwIssueFilter','status']].forEach(function(pair){el(pair[0]).addEventListener('change',function(){cancelSearch(true);state.filters[pair[1]]=this.value;renderTree();});});
  el('pwClearFilters').onclick=function(){cancelSearch(false);resetFilters();renderTree();};
  el('pwInspectResults').onclick=function(){if(!state.ready||searchTimer!==null)return;var rows=filtered();if(rows.length)setFocus(rows.map(function(r){return r.key;}),true);};
  el('pwExpand').onclick=function(){cancelSearch(true);invalidateRows();page=0;function visit(n){if(n.children.length)state.expanded.add(n.key);n.children.forEach(visit);}visit(view().tree);renderTree();};
  el('pwCollapse').onclick=function(){cancelSearch(true);invalidateRows();page=0;state.expanded.clear();renderTree();};
  el('pwElevation').onclick=function(){if(state.ready&&state.focus.length)sketchup.elevation_sync(JSON.stringify({model_token:state.token,keys:state.focus}));};el('pwMaterial').onclick=function(){if(state.ready&&state.focus.length)sketchup.material_change(JSON.stringify({model_token:state.token,keys:state.focus}));};el('pwHealth').onclick=function(){if(!state.ready||!state.focus.length)return;sketchup.scoped_model_health(JSON.stringify({model_token:state.token,keys:state.focus}));};el('pwShow').onclick=function(){action(true,false);};el('pwEdit').onclick=function(){var rows=focusRows();if(rows.length===1&&rows[0].type==='head_beam'){editBeam(rows[0]);return;}action(false,true);};el('pwQTO').onclick=function(){navigate('qto');};if(el('pwDepRun'))el('pwDepRun').onclick=depRun;
  refresh();
 }
 global.MSTProjectWorkspace={refresh:refresh,build:build,visible:visible,summarize:summarize,quantitySummary:quantitySummary};
 global.projectWorkspaceLoaded=loaded;global.projectWorkspaceSelection=selection;global.projectWorkspaceError=error;global.projectWorkspaceDependency=depReceived;global.projectWorkspaceOpenPileEditor=function(){navigate('pile');if(global.sketchup&&sketchup.pile_load_selected_for_edit)sketchup.pile_load_selected_for_edit();var panel=document.getElementById('mstPileModePanel');if(panel)panel.scrollIntoView({block:'center'});};
 global.projectWorkspaceOpenBeamEditor=function(){navigate('beam');if(typeof global.mstBKSetMode==='function')global.mstBKSetMode('edit');if(global.mstPageStep)global.mstPageStep('beam',0);if(typeof global.mstBKLoadEdit==='function')global.mstBKLoadEdit();var status=document.getElementById('mstBKEditStatus');if(status)status.scrollIntoView({block:'center'});};
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})(window);
