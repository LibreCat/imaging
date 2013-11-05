jwerty.key('arrow-left',function(evt){
  evt.preventDefault();
  var href = $(".link_prev").first().attr('href');
  if(href == undefined)return;
  window.location.href = href;
});
jwerty.key('arrow-right',function(evt){
  evt.preventDefault();
  var href = $(".link_next").first().attr('href');
  if(href == undefined)return;
  window.location.href = href;
});
