/* Presentation-only enhancements. No model data or SketchUp callbacks. */
(function(){
  'use strict';
  function init(){
    var nav=document.querySelector('.tabs');
    if(nav){
      document.body.classList.add('mst-workspace');
      nav.setAttribute('role','navigation');nav.setAttribute('aria-label','Çalışma modülleri');
      var symbols=['◉','⊙','▰','▱','▦','◿','◩','✎','⌁','▤','≡','⚙'];
      nav.querySelectorAll('button').forEach(function(button,i){
        if(!button.dataset.symbol)button.dataset.symbol=symbols[i]||'·';
        button.title=button.textContent.trim();
      });
      function updateNav(){nav.querySelectorAll('button').forEach(function(b){
        if(b.classList.contains('on'))b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');
      });}
      new MutationObserver(updateNav).observe(nav,{attributes:true,attributeFilter:['class'],subtree:true});updateNav();
    }else document.body.classList.add('mst-report');
    document.querySelectorAll('label').forEach(function(label){
      var field=label.querySelector('input,select,textarea');
      if(field&&field.id&&!label.htmlFor)label.htmlFor=field.id;
    });
    document.querySelectorAll('button').forEach(function(b){if(!b.hasAttribute('title'))b.title=b.textContent.trim();});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
