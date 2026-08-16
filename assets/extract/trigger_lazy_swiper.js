(function() {
  // 尝试多个可能的轮播选择器
  var selectors = ['.swiper-initialized', '.swiper', '.swiper-container', '[class*="swiper"]', '[class*="carousel"]', '[class*="banner"]', '[class*="slider"]', '.header-image'];
  var swiperEl = null;
  for (var i = 0; i < selectors.length; i++) {
    swiperEl = document.querySelector(selectors[i]);
    if (swiperEl && swiperEl.swiper) break;
    swiperEl = null;
  }
  if (!swiperEl || !swiperEl.swiper) return 'no_swiper';
  var sw = swiperEl.swiper;
  var count = sw.slides ? sw.slides.length : 0;
  if (count <= 1) return 'single_slide';
  var i = 0;
  var timer = setInterval(function() {
    i++;
    if (i >= count) {
      clearInterval(timer);
      sw.slideTo(0, 0);
    } else {
      sw.slideTo(i, 300);
    }
  }, 600);
  return 'swiper_ok:' + count;
})()
