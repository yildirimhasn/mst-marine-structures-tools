(function(global){
 'use strict';
 var current=null,token=null,generation=0;
 function node(id){return document.getElementById(id);}
 function clear(e){while(e.firstChild)e.removeChild(e.firstChild);}
 function text(tag,value){var e=document.createElement(tag);e.textContent=value;return e;}
 function invalidate(){generation++;token=null;node('ceApply').disabled=true;clear(node('cePreview'));}
 function request(){var values={};current.fields.forEach(function(f){values[f.key]=node('ce_'+f.key).value;});values.concrete_class=node('ceConcrete').value;return {model_token:current.model_token,keys:current.keys,values:values};}
 global.controlledEditorReset=function(){invalidate();current=null;node('controlledEditor').hidden=true;};
 global.controlledEditorLoaded=function(data){
  /* 03.11.2026 NCR-003: form Prekast sayfasında; ilgili alt sekme (kanal → PK, diğer → PD) */
  if(global.mstShowPage)global.mstShowPage('precast');
  if(typeof global.mstPrecastTab==='function')global.mstPrecastTab(data.fields.some(function(f){return f.key==='inner_width_m';})?'pk':'pd');
  current=data;var panel=node('controlledEditor');panel.hidden=false;node('ceTitle').textContent=data.id+' · '+data.label;
  var fields=node('ceFields');clear(fields);
  data.fields.forEach(function(f){var label=text('label',f.label),input=document.createElement('input');input.id='ce_'+f.key;input.type='text';input.inputMode='decimal';input.value=f.value===null?'':f.value;input.addEventListener('input',invalidate);label.appendChild(input);fields.appendChild(label);});
  var label=text('label','Beton sınıfı'),select=document.createElement('select');select.id='ceConcrete';data.classes.forEach(function(c){var option=text('option',c);option.value=c;select.appendChild(option);});select.value=data.concrete_class;select.addEventListener('change',invalidate);label.appendChild(select);fields.appendChild(label);
  invalidate();node('ceCheck').disabled=false;node('ceStatus').textContent=data.note||'Ölçüleri değiştirdikten sonra önizleyin. Yalnız bu fiziksel eleman güncellenir.';
  node('ceCheck').onclick=function(){invalidate();node('ceStatus').textContent='Değişiklik kontrol ediliyor…';var data=request();data.request_id=generation;sketchup.controlled_editor_preview(JSON.stringify(data));};
  node('ceApply').onclick=function(){if(!token)return;var selectedToken=token;invalidate();node('ceStatus').textContent='Güncelleniyor…';sketchup.controlled_editor_apply(JSON.stringify({token:selectedToken}));};
  node('ceClose').onclick=function(){invalidate();panel.hidden=true;current=null;sketchup.controlled_editor_cancel();};
  panel.scrollIntoView({block:'center'});
 };
 global.controlledEditorPreview=function(data){
  if(!current||data.request_id!==generation)return;token=data.token;var preview=node('cePreview');clear(preview);
  data.changes.forEach(function(change){preview.appendChild(text('p',change.label+': '+change.before+' → '+change.after));});
  function amount(v){return Number(v).toLocaleString('tr-TR',{maximumFractionDigits:3});}
  preview.appendChild(text('p','Beton: '+amount(data.before_concrete)+' → '+amount(data.after_concrete)+' m³'));
  preview.appendChild(text('p','Kalıp: '+amount(data.before_formwork)+' → '+amount(data.after_formwork)+' m²'));
  node('ceStatus').textContent=data.dependencies?'Beton sınıfı değişir; bağlı eleman geometrisi korunur.':'Önizleme hazır. Tip kimliği yeni ölçü ve malzemeye göre eşleştirilecek.';
  node('ceApply').disabled=false;
 };
 /* 03.11.2026 (kullanıcı bildirimi): açılış reddedilirse (ör. Component prekast) de Prekast sayfasına gidilir; neden form alanında yazılır */
 global.controlledEditorError=function(message){invalidate();if(!current){
  if(global.mstShowPage)global.mstShowPage('precast');
  var panel=node('controlledEditor');panel.hidden=false;node('ceTitle').textContent='Seçili Prekastı Düzenle';clear(node('ceFields'));
  node('ceStatus').textContent=message+' — Bu prekast bu formda düzenlenemez. Component (bileşen) prekastlar ve alt gruplu kanallar için ölçü/tip değişikliğini yukarıdaki prekast tip ve yerleşim bölümlerinden yapın (yerleşimi yeniden oluşturun).';
  node('ceCheck').disabled=true;node('ceClose').onclick=function(){panel.hidden=true;};
  global.projectWorkspaceError(message);panel.scrollIntoView({block:'center'});return;}
  node('ceStatus').textContent=message;};
 global.controlledEditorDone=function(data){invalidate();node('ceStatus').textContent=data.message;node('ceCheck').disabled=true;};
})(window);
