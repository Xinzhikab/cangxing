(function() {
  var dotSelectors = ['.swiper-pagination-bullet', '[class*="pagination"] [class*="dot"]', '[class*="pagination"] [class*="bullet"]', '[class*="indicator"] [class*="dot"]', '[class*="carousel"] [class*="dot"]', '.header-image [class*="dot"]', '[class*="banner"] [class*="dot"]'];
  var dots = null;
  for (var i = 0; i < dotSelectors.length; i++) {
    dots = document.querySelectorAll(dotSelectors[i]);
    if (dots.length > 1) break;
    dots = null;
  }
  if (!dots || dots.length <= 1) return 'no_dots';
  for (var i = 0; i < dots.length; i++) {
    dots[i].click();
  }
  return 'dots_ok:' + dots.length;
})()
