$('#add-comment').submit(function(evt) {
  evt.preventDefault();
  var f = $(this),
  textInput = f.find(':input[name="text"]'),
  text = textInput.val();
  textInput.val("");
  $.post(f.attr('action'), {text: text},function(res) {
    if(!res.status === 'ok')return;
    var comment = $(
      '<blockquote>'+
      res.data.text+
      '<small>posted by '+
      res.data.user_login + 
      ' at '+res.data.datetime+
      '</small></blockquote>'
    );
    comment.hide();
    $("#comments").prepend(comment);
    comment.slideDown();
  },'json');
});
