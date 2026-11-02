const shim=require(process.argv[2]);
const s=shim('accessories'); const code=s.replace(/^<script>/,'').replace(/<\/script>$/,'');
new Function(code); // sözdizimi
let handler=null, scrolled=null, prevented=false;
const target={scrollIntoView(){scrolled='group-fender';}};
global.window={parent:{mstEmbedCall(){},mstEmbedUserClose(){}}};
global.document={addEventListener(t,f){if(t==='click')handler=f;},getElementById(id){return id==='group-fender'?target:null;}};
global.Proxy=Proxy;
new Function('window','document',code)(global.window,global.document);
const span={tagName:'SPAN'}; const a={tagName:'A',getAttribute(){return '#group-fender';}}; span.parentElement=a; a.parentElement=null;
handler({target:span,preventDefault(){prevented=true;}});
console.log('ic_baglanti: engellendi='+prevented+' kaydirildi='+scrolled);
prevented=false; const ext={tagName:'A',parentElement:null,getAttribute(){return 'https://example.com';}};
handler({target:ext,preventDefault(){prevented=true;}}); console.log('dis_baglanti: engellendi='+prevented);
prevented=false; handler({target:{tagName:'BUTTON',parentElement:null},preventDefault(){prevented=true;}}); console.log('dugme: engellendi='+prevented);
