(function() {
  // 尝试多种可能的轮播项选择器
  var itemSelectors = ['.header-image__item', '.swiper-slide', '[class*="carousel"] [class*="item"]', '[class*="banner"] [class*="item"]', '[class*="slider"] [class*="item"]'];
  var items = null;
  for (var i = 0; i < itemSelectors.length; i++) {
    items = document.querySelectorAll(itemSelectors[i]);
    if (items.length > 1) break;
    items = null;
  }
  if (!items || items.length <= 1) return 'no_items';
  // 常见的懒加载图片属性，按优先级尝试
  var attrList = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-image', 'data-bg', 'data-background', 'data-thumb', 'data-lazy'];
  var loaded = 0;
  var imgCount = 0;
  var bgCount = 0;
  // 读取元素（含 CSS 类定义）的 background-image，返回 url(...) 内的地址
  function bgOf(el) {
    try {
      var cs = getComputedStyle(el);
      var m = (cs.backgroundImage || '').match(/url\(["']?([^"'\)]+)["']?\)/);
      return m && m[1] ? m[1] : '';
    } catch (e) { return ''; }
  }
  for (var i = 0; i < items.length; i++) {
    items[i].style.display = 'block';
    items[i].style.visibility = 'visible';
    items[i].style.opacity = '1';
    items[i].style.transform = 'translateX(0)';
    items[i].style.position = 'static';
    var imgs = items[i].querySelectorAll('img');
    imgCount += imgs.length;
    // 轮播项自身或其后代可能是 background-image（无 img 标签）
    var bgs = [];
    var selfBg = bgOf(items[i]);
    if (selfBg && selfBg.indexOf('data:') !== 0) bgs.push(selfBg);
    var bgEls = items[i].querySelectorAll('*');
    for (var bi = 0; bi < bgEls.length; bi++) {
      var b = bgOf(bgEls[bi]);
      if (b && b.indexOf('data:') !== 0 && b.indexOf('blob:') !== 0) bgs.push(b);
    }
    if (bgs.length && imgs.length === 0) {
      // 无 img 标签但 CSS 有背景图：用第一个背景图填充占位 img
      var phImg = document.createElement('img');
      phImg.setAttribute('src', bgs[0]);
      phImg.setAttribute('data-real-bg', bgs.join(','));
      items[i].appendChild(phImg);
      loaded++;
    }
    bgCount += bgs.length;
    for (var j = 0; j < imgs.length; j++) {
      var realSrc = '';
      for (var k = 0; k < attrList.length; k++) {
        var v = imgs[j].getAttribute(attrList[k]);
        if (v && v.indexOf('data:') !== 0 && v.indexOf('blob:') !== 0) { realSrc = v; break; }
      }
      if (!realSrc) realSrc = imgs[j].getAttribute('src') || '';
      if (!realSrc) {
        var b2 = bgOf(imgs[j]);
        if (!b2 && imgs[j].parentNode) b2 = bgOf(imgs[j].parentNode);
        if (b2 && b2.indexOf('data:') !== 0) realSrc = b2;
      }
      if (realSrc) {
        imgs[j].setAttribute('src', realSrc);
        loaded++;
      }
    }
  }
  return 'dom_ok:' + items.length + '_imgs:' + imgCount + '_bg:' + bgCount + '_loaded:' + loaded + '_sample:' + items[0].outerHTML.replace(/\s+/g, ' ').substring(0, 200);
})()
