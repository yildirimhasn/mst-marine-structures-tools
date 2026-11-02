/* MST workspace: read-only hierarchy, explicit selection and numeric inputs. */
'use strict';
function parseEngineeringNumber(value){
  if(typeof value==='number')return Number.isFinite(value)?value:NaN;
  var s=String(value==null?'':value).trim().replace(',','.');
  if(!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(s))return NaN;
  var n=Number(s);return Number.isFinite(n)?n:NaN;
}
function parseEngineeringRatio(value){
  var parts=String(value).split('/');
  if(parts.length===1)return parseEngineeringNumber(value);
  if(parts.length!==2)return NaN;
  var a=parseEngineeringNumber(parts[0]),b=parseEngineeringNumber(parts[1]);
  return Number.isFinite(a)&&Number.isFinite(b)&&a>=0&&b>0?a/b:NaN;
}
function mstClear(element){while(element.firstChild)element.removeChild(element.firstChild);}
function setWorkspaceVersion(version){
  document.querySelectorAll('[data-mst-version]').forEach(function(e){e.textContent='v'+version;});
}
var PILE_QTO_DATA=null, pileQTOCollapsed=new Set(), pileQTOInitialized=new Set();
var pileQTOColumns=[
  ['Sistem / Yapı / Kesit',null],['Ø (mm)',1],['Et (mm)',1],['Adet',0],
  ['Tapa (adet)',0],['Ek (adet)',0],['İmal boyu (m)',2],['Çakım boyu (m)',2],
  ['Tapa (t)',3],['Boru çeliği (t)',3],['Üst çember (kg)',2],['Alt çember (kg)',2],
  ['Manipülasyon (t)',3],['Beton (m³)',3],['PE (m²)',2],['Foraj (m)',2]
];
/* 02.11.2026 ADR 22: yapı satırında label = görünen ad, structure / key = kod (seçim ve kimlik kodla yapılır).
   Gösterim: "Ad (kod)"; görünen ad yoksa veya koda eşitse yalnız kod. */
function pileQTOStructureText(row){
  var code=row&&row.structure;if(code===null||code===undefined||code==='')return 'Tüm yapılar';
  var name=row.structure_label;code=String(code);
  return (typeof name==='string'&&name.trim()&&name!==code)?name+' ('+code+')':code;
}
function pileQTOVisibleRows(rows,query,collapsed){
  if(query){
    var keys=new Set();
    rows.filter(function(r){return r.level==='section';}).forEach(function(r){
      var hay=[r.zone,r.structure,r.structure_label||'',r.label].join(' ').toLocaleLowerCase('tr-TR');
      if(hay.includes(query)){
        keys.add(r.key);keys.add(r.parent);
        var parent=rows.find(function(p){return p.key===r.parent;});if(parent)keys.add(parent.parent);
      }
    });
    return rows.filter(function(r){return keys.has(r.key);});
  }
  var parents=new Map(rows.map(function(r){return [r.key,r.parent];}));
  return rows.filter(function(r){
    var parent=r.parent;
    while(parent){if(collapsed.has(parent))return false;parent=parents.get(parent);}
    return true;
  });
}
function pileQTOTotals(rows){
  var total=new Array(16).fill(0);
  rows.filter(function(r){return r.level==='section';}).forEach(function(r){for(var i=3;i<16;i++)total[i]+=Number(r.values[i])||0;});
  return total;
}
function setPileQTOData(data){
  PILE_QTO_DATA=data;
  (data.pile_qto_rows||[]).forEach(function(r){
    if(!pileQTOInitialized.has(r.key)){if(r.level==='structure')pileQTOCollapsed.add(r.key);pileQTOInitialized.add(r.key);}
  });
  renderPileQTO();
  var notes=document.getElementById('qtoWarnings');
  if(notes){
    mstClear(notes);
    var messages=(data.qto_status||{}).messages||[];
    notes.hidden=!messages.length;
    messages.forEach(function(message){var p=document.createElement('p');p.textContent=message;notes.appendChild(p);});
  }
  var status=data.qto_status||{}, missing=Number(status.incomplete_count)||0;
  var score=document.getElementById('qAuditScore');if(score)score.textContent=missing?'Kontrol gerekli':'Ön kontrol tamam';
  var text=document.getElementById('qAuditText');if(text)text.textContent=missing?
    missing+' elemanda temel kimlik, organizasyon veya kesit bilgisi eksik. Tam ilişki kontrolü için Model Kontrolü çalıştırın.':
    'Temel kimlik ve kesit alanları kontrol edildi. İlişkiler, mükerrer kimlikler ve geometri için Model Kontrolü çalıştırın.';
  var update=document.getElementById('qLastUpdate');if(update)update.textContent='Son okuma: '+new Date().toLocaleTimeString('tr-TR');
  if(data.version)setWorkspaceVersion(data.version);
}
function renderPileQTO(){
  var body=document.getElementById('qPileQTOBody'),head=document.getElementById('qPileQTOHead');
  if(!body||!head||!PILE_QTO_DATA)return;
  var search=document.getElementById('pileQTOSearch'),query=search?search.value.trim().toLocaleLowerCase('tr-TR'):'';
  var detail=document.getElementById('pileQTOFull'),full=detail&&detail.checked;
  var columns=full?pileQTOColumns.map(function(_,i){return i;}):[0,3,6,7,9,13,15];
  var rows=PILE_QTO_DATA.pile_qto_rows||[],visible=pileQTOVisibleRows(rows,query,pileQTOCollapsed);
  var matching= query?pileQTOVisibleRows(rows,query,new Set()):rows;
  var totals=query?pileQTOTotals(matching):(PILE_QTO_DATA.pile_qto_total||new Array(16).fill(0));
  var table=document.getElementById('pileQTOTable');if(table)table.classList.toggle('is-detailed',!!full);
  mstClear(head);mstClear(body);
  var hr=document.createElement('tr');
  columns.forEach(function(i){var th=document.createElement('th');th.scope='col';th.textContent=pileQTOColumns[i][0];hr.appendChild(th);});
  var actionHead=document.createElement('th');actionHead.textContent='Model';hr.appendChild(actionHead);head.appendChild(hr);
  function append(row,isTotal){
    var tr=document.createElement('tr');tr.className='pq-level-'+row.level;
    columns.forEach(function(i){
      var td=document.createElement('td');
      if(i===0){
        td.className='pq-tree-label';
        if(row.level==='system'||row.level==='structure'){
          var toggle=document.createElement('button');toggle.className='pq-tree-toggle secondary';
          toggle.textContent=query||!pileQTOCollapsed.has(row.key)?'−':'+';
          toggle.disabled=!!query;toggle.setAttribute('aria-expanded',String(!!query||!pileQTOCollapsed.has(row.key)));
          toggle.setAttribute('aria-label',row.label+' alt satırlarını aç / kapat');
          toggle.onclick=function(){if(pileQTOCollapsed.has(row.key))pileQTOCollapsed.delete(row.key);else pileQTOCollapsed.add(row.key);renderPileQTO();};
          td.appendChild(toggle);
        }
        var label=document.createElement('span');label.textContent=row.label;
        if(row.level==='structure'&&row.structure!==null&&row.structure!==undefined&&String(row.structure)!==String(row.label))label.title='Yapı kodu: '+row.structure;
        td.appendChild(label);
      }else{
        var value=i===1?row.diameter_mm:(i===2?row.thickness_mm:row.values[i]);
        td.textContent=value===null||value===undefined?'—':Number(value).toLocaleString('tr-TR',{minimumFractionDigits:pileQTOColumns[i][1],maximumFractionDigits:pileQTOColumns[i][1]});
      }
      tr.appendChild(td);
    });
    var td=document.createElement('td');
    if(!isTotal&&(!query||row.level==='section')){
      var select=document.createElement('button');select.className='secondary pq-select';select.textContent='Seç';
      select.title=row.level==='section'?(row.zone+' / '+pileQTOStructureText(row)+' / '+row.label+' elemanlarını seç'):((row.level==='structure'?row.zone+' / '+pileQTOStructureText(row):row.zone+' / Tüm yapılar')+' elemanlarını seç');
      select.onclick=function(){selectPileQTO(row.zone,row.diameter_mm,row.thickness_mm,row.structure);var status=document.getElementById('pileQTOSelection');if(status)status.textContent='Seçim kapsamı: '+row.zone+' / '+pileQTOStructureText(row)+' · '+row.values[3]+' kazık';};
      td.appendChild(select);
    }
    tr.appendChild(td);body.appendChild(tr);
  }
  visible.forEach(function(row){
    if(query&&row.level!=='section'){
      var leaves=matching.filter(function(r){return r.level==='section'&&r.zone===row.zone&&(row.level==='system'||r.structure===row.structure);});
      row=Object.assign({},row,{values:pileQTOTotals(leaves)});
    }
    append(row,false);
  });
  if(visible.length)append({level:'total',label:query?'FİLTRE TOPLAMI':'PROJE GENEL TOPLAMI',values:totals},true);
  else{var tr=document.createElement('tr'),td=document.createElement('td');td.colSpan=columns.length+1;td.textContent=rows.length?'Aramanıza uygun kazık bulunamadı.':'Modelde çelik boru kazık bulunamadı.';tr.appendChild(td);body.appendChild(tr);}
  [['pqFab',6,2,'m'],['pqDrive',7,2,'m'],['pqManip',12,3,'t'],['pqConc',13,3,'m³'],['pqPE',14,2,'m²'],['pqDrill',15,2,'m']].forEach(function(k){
    var e=document.getElementById(k[0]);if(e)e.textContent=Number(totals[k[1]]||0).toLocaleString('tr-TR',{minimumFractionDigits:k[2],maximumFractionDigits:k[2]})+' '+k[3];
  });
  var scope=document.getElementById('pileQTOScope');if(scope)scope.textContent=(query?'Arama kapsamı':'Tüm proje')+' · '+(totals[3]||0)+' kazık · '+matching.filter(function(r){return r.level==='section';}).length+' kesit grubu';
}
function expandPileQTO(open){
  if(!PILE_QTO_DATA)return;
  (PILE_QTO_DATA.pile_qto_rows||[]).forEach(function(r){if(r.level!=='section'){if(open)pileQTOCollapsed.delete(r.key);else pileQTOCollapsed.add(r.key);}});
  renderPileQTO();
}
function updatePileActionScope(){
  var count=typeof customAxes==='undefined'?0:customAxes.reduce(function(n,a){return n+(a.points||[]).filter(function(p){return p.selected;}).length;},0);
  document.querySelectorAll('#pile button[onclick="pile()"]').forEach(function(button){button.textContent=count+' Kazık Oluştur';button.disabled=count===0;});
  var e=document.getElementById('pileActionScope');if(e)e.textContent=(window.currentPileSystem||'Sistem seçilmedi')+' / '+(window.currentPileStructureLabel||window.currentPileStructure||'Yapı seçilmedi')+' · '+count+' seçili nokta';
}
function validatePileForm(){
  var creationFields=new Set(['diameter_mm','thickness_mm','length_m','top_elevation_m','seabed_elevation_m','driving_length_m','batter_ratio','azimuth_deg','splice_count_per_pile','plug_count_per_pile','plug_thickness_mm','plug_clearance_mm','upper_ring_width_mm','upper_ring_thickness_mm','upper_ring_count_per_pile','lower_ring_width_mm','lower_ring_thickness_mm','lower_ring_count_per_pile','pe_length_m','drilling_length_m','count_x','count_y','spacing_x_m','spacing_y_m','start_no','start_low_count','start_low_top_m','end_low_count','end_low_top_m','infill_bottom_normal_m','infill_bottom_start_m','infill_bottom_end_m']);
  var fields=document.querySelectorAll('#pile input');var first=null;
  fields.forEach(function(field){
    if(!creationFields.has(field.id))return;
    field.removeAttribute('aria-invalid');field.setCustomValidity('');
    if(!field.id||(!/(?:_mm|_m|_deg|_ratio|_count|_no)$/.test(field.id)&&field.type!=='number'))return;
    var raw=field.value.trim(),required=['diameter_mm','thickness_mm','length_m','top_elevation_m'].includes(field.id);
    if(!raw&&!required)return;
    var n=field.id==='batter_ratio'?parseEngineeringRatio(raw):parseEngineeringNumber(raw),error='';
    if(!Number.isFinite(n))error='Geçerli bir sayı girin. Ondalık için virgül veya nokta kullanabilirsiniz.';
    else if(['diameter_mm','thickness_mm','length_m'].includes(field.id)&&n<=0)error='Sıfırdan büyük bir değer girin.';
    else if((field.step==='1'||field.id.includes('count_per_pile')||field.id==='start_no')&&(!Number.isInteger(n)||n<Number(field.min||0)))error='Alan sınırlarına uygun tam sayı girin.';
    else if(field.id==='batter_ratio'&&n<0)error='Eğim negatif olamaz.';
    if(error){field.setCustomValidity(error);field.setAttribute('aria-invalid','true');if(!first&&field.type!=='hidden')first=field;}
  });
  var diameter=document.getElementById('diameter_mm'),thickness=document.getElementById('thickness_mm');
  if(parseEngineeringNumber(diameter.value)<=2*parseEngineeringNumber(thickness.value)){
    thickness.setCustomValidity('Et kalınlığının iki katı dış çaptan küçük olmalı.');thickness.setAttribute('aria-invalid','true');first=first||thickness;
  }
  if(first){first.scrollIntoView({block:'center'});first.reportValidity();return false;}
  return true;
}
document.addEventListener('DOMContentLoaded',function(){
  if(window.sketchup&&sketchup.workspace_ready)sketchup.workspace_ready();
  if(typeof togglePileDetailPanels==='function')togglePileDetailPanels();
  var cb=document.getElementById('infill_enabled'),sel=document.getElementById('infill_enabled_select');
  if(cb&&sel){sel.value=cb.checked?'1':'0';setInfillEnabledFromSelect(sel.value);}
  updatePileActionScope();
});
