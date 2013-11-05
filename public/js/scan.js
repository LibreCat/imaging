/* goto tab */
// Javascript to enable link to tab
if(window.location.hash && window.location.hash != ""){
  $('.nav-tabs a[href='+window.location.hash+']').tab('show') ;
}

// Change hash for page-reload
$('.nav-tabs a').on('shown', function (e) {
    window.location.hash = e.target.hash;
});

//submit-on-enter
$('input').keydown(function(e){
  if(e.which == 13){
    e.preventDefault();
    $(this).closest("form").submit();
  }
});

$(document).ready(function(){

  //controleer aanwezigheid in grep   
  $('.metadata_archive').each(function(){

    var $t = $(this);
    $.ajax({
      dataType: "json",
      url: base_url+"/archive?query=identifier~"+$t.attr("data-id"),
      success: function(data){
        //in grep: 'rood' (want controle is nodig!)
        //niet in grep: 'groen'
        var addClass = data.hits.length == 1 ? "label-important":"label-success";
        $t.removeClass(addClass).addClass(addClass);
        $t.html("in archief: "+data.hits.length);
      }
    });     

  });
  
  //controleer of er nog jobs bezig zijn
  var mm_check_jobs_timeout = 1000*30;
  var job_progress = $("#job_progress");
  if(job_progress.size() > 0){
    var func = function(){
    
      var asset_id = job_progress.attr("data-id");
      $.ajax({
        dataType: "json",
        url: base_url+"/jobs/"+asset_id,
        success: function(data){            

          if(data.errors.length > 0){

            //asset is reeds verwijderd door MediaMosa (waarschijnlijk)
            var str = "The asset with ID '"+asset_id+"' was not found in the database";
            var re = new RegExp(str);
            if(re.test(data.errors[0]))return;

          }else{
            //geef aan hoeveel jobs nog bezig zijn
            var done = 0;
            for(var i = 0;i < data["hits"].length;i++){
              var job = data["hits"][i];
              if(job["status"] == "FINISHED"){
                done++;
              }
            }
            var progress = Math.floor((done / data["hits"].length) * 100);            
            job_progress.find(".bar").css("width",progress+"%");

            if(progress >= 100){
              //niet zomaar pagina opnieuw laden, want cron-status.pl heeft mogelijks "busy" nog niet verwijderd
              //op die manier vermijdt je dat de pagina zich voortdurend herlaadt..
              clearInterval(x);
              //TODO: job_progress vervangen door link die pagina herlaadt?
            }

          }
        }
      });

    };
    //start func now, and then at regular intervals
    func();
    var x;
    x = setInterval(func,mm_check_jobs_timeout);
  }

});

