/*
  See http://suan.github.io/jquery-keycombinator/
      http://keithcirkel.co.uk/jwerty/
*/
jwerty.key('ctrl+s',function(ev){
  ev.preventDefault();
  $('form.edit-baginfo').submit();
});
jwerty.key('esc',function(evt){
  evt.preventDefault();
  var url = base_url+"/scans";
  window.location.href = url;
});

//tab switch
$(document).keydown(function(e){
  if(e.which != 9)return;
  e.preventDefault();
  var tab_scan = $("#tab_scan");
  var tabs = tab_scan.find("li");
  for(var i = 0;i < tabs.length;i++){
    if($(tabs[i]).hasClass("active")){
      var new_i = i == tabs.length - 1 ? 0:i+1;
      $(tabs[new_i]).find("a").tab('show');
      break;
    }
  }
});
