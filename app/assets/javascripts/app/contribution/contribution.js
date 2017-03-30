App.addChild('Contribution', {
  el: '#new-contribution',

  events: {
    'click .radio' : 'clickReward',
    'click .submit-form' : 'submitForm',
    'keyup .user-reward-value' : 'submitOnReturnKey',
    'click .user-reward-value' : 'clearOnFocus',
    'input #contribution_value' : 'restrictChars'
  },

  restrictChars: function(event){
    var $target = $(event.target);
    $target.val($target.val().replace(/[^\d,]/, ''));
  },

  submitOnReturnKey: function(event) {
    event.preventDefault();
    if(event.keyCode === 13) {
      this.$('.submit-form').trigger('click');
    }
  },

  submitForm: function(event){
    var $target_row = $(event.target).parents('.back-reward-money'),
        user_value = this.$('.selected').find('.user-reward-value').val().replace(/\./g,''),
        minimumValue=this.minimumValue();
    if(user_value === ''){
      this.$value.val(minimumValue);
    }else{
      this.$value.val(user_value);
    }
    if(parseInt(user_value) < parseInt(minimumValue)){
      $target_row.find('.user-reward-value').addClass('error');
      $target_row.find('.text-error').slideDown();
    }else{
      CatarseAnalytics.event({cat:'contribution_create',act:'contribution_continue_click',lbl:minimumValue,val:minimumValue});
      this.$('form').submit();
    }

    return false;
  },

  activate: function(){
    this.$('.user-reward-value').mask('000.000.000', {reverse: true});
    this.$value = this.$('#contribution_value');
    this.$minimum = this.$('#minimum-value');
    if(this.$('input[type=radio]').length > 0) {
      this.clickReward({currentTarget: this.$('input[type=radio]:checked').parents('.radio')});
      this.isOnAutoScroll = false;
      this.activateFloattingHeader();
    }
    // copy default value from rendered contribution
    $('.user-reward-value:first').val($('#contribution_value').val());
    var stats=$('[data-stats]').data('stats');
    CatarseAnalytics.event({cat:'contribution_create',act:'contribution_started',lbl:stats && stats.id});
    if(stats && stats.id && _.contains([41679,40191,40271,38768,42815,43002,42129,41867,39655,29706], stats.id)) {
          (window.$zopim && window.$zopim.livechat)||(function(d,s){var z=window.$zopim=function(c){z._.push(c)},$=z.s=d.createElement(s),e=d.getElementsByTagName(s)[0];z.set=function(o){z.set._.push(o)};z._=[];z.set._=[];$.async=!0;$.setAttribute('charset','utf-8');$.src='//v2.zopim.com/?2qPtIfZX0Exh5Szx5JUoUxWKqrTQI5Tm';z.t=+new Date;$.type='text/javascript';e.parentNode.insertBefore($,e)})(document,'script');
          setTimeout(function t(){
            if(window.$zopim && window.$zopim.livechat)
              window.zE.hide();
            else
              setTimeout(t, 500);
          },500);
    }
  },

  activateFloattingHeader: function(){
    var that = this,
        top,
        top_title = $('#new-contribution'),
        faq_top = $("#faq-box").offset().top;
    $(window).scroll(function() {
        if(!that.isOnAutoScroll && !app.isMobile()){
            top = $(top_title).offset().top,
            $(window).scrollTop() > top ? $(".reward-floating").addClass("reward-floating-display") : $(".reward-floating").removeClass("reward-floating-display");
            var t = $("#faq-box");
            $(window).scrollTop() > faq_top-130 ? $(t).hasClass("faq-card-fixed") || $(t).addClass("faq-card-fixed") : $(t).hasClass("faq-card-fixed") && $(t).removeClass("faq-card-fixed");
        }
    });
  },

  clearOnFocus: function(event){
    this.$(event.target).val("");
    this.$('.error').removeClass('error');
    this.$('.text-error').slideUp();
    return false;
  },

  customValidation: function(event){
    if(parseInt(this.$value.val()) < this.minimumValue()){
      this.selectReward(this.$('.radio label'));
    }
  },

  minimumValue: function(){
    return this.$('.selected').find('label[data-minimum-value]').data('minimum-value');
  },

  resetSelected: function(){
    this.$('.w-radio').removeClass('selected');
  },

  selectReward: function(reward){
    this.resetSelected();
    reward.find('input[type=radio]').prop('checked', true);
    this.$('.back-reward-money').hide();
    reward.find('.back-reward-money').show();
    reward.parents('.back-reward-radio-reward').addClass('selected');
  },

  clickReward: function(event){
    var $el = $(event.currentTarget).find('label');
    if(!$el.parents('.back-reward-radio-reward').hasClass('selected')) {
      var elOffset = $el.offset().top;
      var elHeight = $el.height();
      var windowHeight = $(window).height();
      var isOnAutoScroll = this.isOnAutoScroll;
      var offset;
      if (elHeight < windowHeight) {
        offset = elOffset - ((windowHeight / 2) - ((elHeight * 2) / 3));
      } else {
        offset = elOffset;
      }
      $.smoothScroll({
        speed: 600,
        offset: -60,
        callback: function(){
          isOnAutoScroll = false;
        }
      }, offset);
      this.selectReward($el);
      var minimum = this.minimumValue();
      var reward_value = $el.find('.user-reward-value');
      if(reward_value.val() === ''){
        reward_value.val(minimum);
      }
      CatarseAnalytics.event({cat:"contribution_create",act:"contribution_reward_change",lbl:this.minimumValue()});
    }
  }
});

App.addChild('FaqBox', {
  el: '#faq-box',

  events: {
    'click li.list-question' : 'clickQuestion'
  },

  clickQuestion: function(event){
    var $question = $(event.currentTarget);
    var $answer = $question.next();
    $question.toggleClass('open').toggleClass('alt-link');
    $answer.slideToggle('slow');
    if($question.hasClass('open')) {
      CatarseAnalytics.event({cat:"contribution_create",act:"contribution_info_click",lbl:$.trim($question.text())});
    }
  },

  activate: function(){
    // Add class is necessary due to mithril - jquery compatibility
    this.$('li.list-answer').addClass('list-answer-opened').hide();
  }
});
