(function() {
  var el = /*__SELECTOR_CHAIN__*/;
  if (!el) return '0';
  var len = (el.innerText || el.textContent || '').trim().length;
  if (len > 50) return '1';
  if (len < 5) return '0';
  var carousel = document.querySelectorAll('.swiper-slide, .header-image__item, [class*="slider"] [class*="item"], [class*="carousel"] [class*="item"]').length;
  return carousel > 1 ? '1' : '0';
})()
