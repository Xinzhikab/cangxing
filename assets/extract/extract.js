(function() {
  // 过滤头像/图标/表情等与正文无关的图片
  function relevant(img) {
    var cls = ((img.className || '') + ' ' + (img.id || '')).toLowerCase();
    var banned = /*__BANNED_CLASSES__*/;
    for (var i = 0; i < banned.length; i++) {
      if (cls.indexOf(banned[i]) !== -1) return false;
    }
    var w = parseInt(img.getAttribute('width'), 10);
    if (w && w < 40) return false;
    return true;
  }
  // 过滤 URL 命中站点规则排除路径的图片（如 /avatar/、/emoji/）
  function bannedUrl(src) {
    var s = src.toLowerCase();
    var banned = /*__BANNED_URLS__*/;
    for (var i = 0; i < banned.length; i++) {
      if (s.indexOf(banned[i]) !== -1) return true;
    }
    return false;
  }
  var el = /*__SELECTOR_CHAIN__*/;
  if (!el) return JSON.stringify({text:'', images:[]});
  // 在同一个克隆副本上生成正文与图片列表，保证 [图N] 占位符和 images 一一对应：
  // 先移除评论区/导航等容器，它们的图片不会进入任何一方，避免数量错位
  var c = el.cloneNode(true);
  var tags = ['script','style','noscript','iframe','svg','nav','header','footer','aside'];
  c.querySelectorAll(tags.join(',')).forEach(function(n){ n.remove(); });
  c.querySelectorAll('[class*="comment"],[id*="comment"]').forEach(function(n){ n.remove(); });
  var images = [];
  var seen = {};
  var idx = 0;
  function pushImg(img) {
    // 支持多种懒加载属性：data-src, data-original, data-lazy-src, data-url, data-image, data-bg 等
    var attrList = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-image', 'data-bg', 'data-background', 'data-thumb', 'data-lazy'];
    var src = '';
    for (var k = 0; k < attrList.length; k++) {
      var v = img.getAttribute(attrList[k]);
      if (v && v.indexOf('data:') !== 0 && v.indexOf('blob:') !== 0) { src = v; break; }
    }
    if (!src) src = img.getAttribute('src') || '';
    if (!src) {
      // 兜底：用 getComputedStyle 从 img 或其父元素读取 CSS 定义的 background-image
      try {
        var cs = getComputedStyle(img);
        var m = (cs.backgroundImage || '').match(/url\(["']?([^"'\)]+)["']?\)/);
        if (m && m[1] && m[1].indexOf('data:') !== 0) { src = m[1]; }
        if (!src && img.parentNode) {
          var cs2 = getComputedStyle(img.parentNode);
          var m2 = (cs2.backgroundImage || '').match(/url\(["']?([^"'\)]+)["']?\)/);
          if (m2 && m2[1] && m2[1].indexOf('data:') !== 0) { src = m2[1]; }
        }
      } catch (e) {}
    }
    if (!src || src.indexOf('data:') === 0 || src.indexOf('blob:') === 0) return false;
    if (!relevant(img) || bannedUrl(src) || seen[src]) return false;
    seen[src] = 1;
    idx++;
    images.push(src);
    return true;
  }
  // 首图轮播（.header-image__item / .swiper-slide 等）先入图列表，并把 [图N] 占位符插到正文开头
  // 轮播项 class 因站点而异（小黑盒为 .swiper-slide + .bbs-link-img-slider-slide），
  // 用多重选择器匹配，与 _triggerLazyImages 的 DOM 策略保持一致
  var headerSelectors = ['.header-image__item', '.swiper-slide', '[class*="carousel"] [class*="item"]', '[class*="banner"] [class*="item"]', '[class*="slider"] [class*="item"]'];
  var headerItems = null;
  for (var hs = 0; hs < headerSelectors.length; hs++) {
    var hq = document.querySelectorAll(headerSelectors[hs]);
    if (hq.length > 1) { headerItems = hq; break; }
  }
  var headerPhs = [];
  if (headerItems) {
    for (var hi = 0; hi < headerItems.length; hi++) {
    var itemImgs = headerItems[hi].querySelectorAll('img');
    if (itemImgs.length) {
      for (var ii = 0; ii < itemImgs.length; ii++) {
        if (pushImg(itemImgs[ii])) headerPhs.push(document.createTextNode('[图' + idx + ']'));
      }
    } else {
      // 轮播项无 img 标签时，用 getComputedStyle 读取 CSS 类/内联 background-image
      var bgSrc = '';
      try {
        var cs0 = getComputedStyle(headerItems[hi]);
        var m0 = (cs0.backgroundImage || '').match(/url\(["']?([^"'\)]+)["']?\)/);
        if (m0 && m0[1]) bgSrc = m0[1];
        if (!bgSrc) {
          var bgEls2 = headerItems[hi].querySelectorAll('*');
          for (var bi2 = 0; bi2 < bgEls2.length && !bgSrc; bi2++) {
            var cs2 = getComputedStyle(bgEls2[bi2]);
            var m2 = (cs2.backgroundImage || '').match(/url\(["']?([^"'\)]+)["']?\)/);
            if (m2 && m2[1] && m2[1].indexOf('data:') !== 0) bgSrc = m2[1];
          }
        }
      } catch (e) {}
      if (bgSrc && bgSrc.indexOf('data:') !== 0 &&
          !bannedUrl(bgSrc) && !seen[bgSrc]) {
        seen[bgSrc] = 1;
        idx++;
        images.push(bgSrc);
        headerPhs.push(document.createTextNode('[图' + idx + ']'));
      }
    }
    }
  }
  if (headerPhs.length && c.firstChild) {
    var frag = document.createDocumentFragment();
    for (var k = 0; k < headerPhs.length; k++) frag.appendChild(headerPhs[k]);
    c.insertBefore(frag, c.firstChild);
  }
  // 正文容器内的图片继续编号并原位替换为占位符
  var imgs = c.querySelectorAll('img');
  for (var j = 0; j < imgs.length; j++) {
    if (pushImg(imgs[j])) {
      var ph = document.createTextNode('[图' + idx + ']');
      if (imgs[j].parentNode) imgs[j].parentNode.replaceChild(ph, imgs[j]);
    }
  }
  // 提取正文并保留换行。注意：c 是 cloneNode 的副本，不在文档流
  // 中，innerText 对 detached 节点会回退为 textContent（纯拼接、
  // 无换行），所以必须自己按 DOM 遍历，在块级元素边界补换行
  var blockTags = ['p','div','section','article','header','footer','nav','aside','li','ul','ol','dl','dt','dd','h1','h2','h3','h4','h5','h6','pre','table','tr','figure','figcaption'];
  function blockText(node) {
    if (node.nodeType === 3) return node.textContent;
    if (node.nodeType !== 1) return '';
    var tag = node.tagName.toLowerCase();
    if (tag === 'br') return '\n';
    if (['script','style','noscript','iframe','svg'].indexOf(tag) >= 0) return '';
    // 行内粗体（b/strong）转 Markdown **粗体**
    if (tag === 'b' || tag === 'strong') {
      var bs = '';
      for (var bi = 0; bi < node.childNodes.length; bi++) {
        bs += blockText(node.childNodes[bi]);
      }
      bs = bs.trim();
      if (!bs) return '';
      return '**' + bs + '**';
    }
    var s = '';
    for (var i = 0; i < node.childNodes.length; i++) {
      s += blockText(node.childNodes[i]);
    }
    // blockquote 与正文区分：内部段落归一为行，逐行加 > 前缀，
    // 输出 Markdown 引用块（嵌套引用自然形成 > > 前缀）
    if (tag === 'blockquote') {
      var inner = s.replace(/[ \t\r]+/g, ' ')
        .replace(/ *\n */g, '\n')
        .replace(/\n+/g, '\n')
        .trim();
      if (!inner) return '\n';
      var quoted = inner.split('\n').map(function(l) { return '> ' + l; }).join('\n');
      return '\n' + quoted + '\n';
    }
    if (blockTags.indexOf(tag) >= 0) s = '\n' + s + '\n';
    return s;
  }
  var t = blockText(c).trim()
    .replace(/[ \t\r]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n+/g, '\n\n');
  // 标题/作者/发布时间：小黑盒详情页有精确元素，优先取；其余站点走兜底
  var title = '';
  var author = '';
  var publishedAt = '';
  // 标题多重兜底：精确选择器 → og:title → h1 → document.title
  var titleSels = ['.section-title__content', '[class*="bbs-link"] [class*="title"]', 'h1.title', 'h1', '[class*="article-title"]', '[class*="post-title"]'];
  for (var ts = 0; ts < titleSels.length && !title; ts++) {
    var tEl = document.querySelector(titleSels[ts]);
    if (tEl) {
      var tT = (tEl.innerText || '').trim();
      if (tT && tT.length <= 120) title = tT;
    }
  }
  if (!title) {
    var og = document.querySelector('meta[property="og:title"]') || document.querySelector('meta[name="og:title"]');
    if (og) title = (og.getAttribute('content') || '').trim();
  }
  if (!title) title = (document.title || '').trim();
  // 最后兜底：纯图轮播帖无标题元素时，用正文第一句（去掉图片占位符）当标题
  if (!title) {
    var textOnly = t.replace(/\[图\d+\]/g, '').trim();
    var m5 = textOnly.match(/^[^。！？!?~～]{4,40}/);
    if (m5) title = m5[0].trim();
  }
  // 去掉站点名后缀（如「xxx - 小黑盒」「xxx_小黑盒」）
  title = title.replace(/[\s\-_]+(小黑盒|酷安|哔哩哔哩|bilibili|微博|贴吧|抖音)\s*$/, '').trim();
  var authorEl = document.querySelector('.link-user__username');
  if (authorEl) author = (authorEl.innerText || '').trim();
  var dateEl = document.querySelector('.link-data__time');
  dateEl = dateEl || document.querySelector('.user-info__line-2');
  if (dateEl) {
    var dm = (dateEl.innerText || '').match(/(\d{4}-\d{2}-\d{2}|\d{2}-\d{2})/);
    if (dm) publishedAt = dm[1];
  }
  // 兜底：作者卡片/元信息容器（小黑盒为 .link-user__user-wrapper），优先取它
  var metaText = '';
  var metaSels = ['[class*="link-user__user-wrapper"]','[class*="user-wrapper"]','[class*="user-info"]','[class*="author-info"]','[class*="user-card"]','[class*="post-meta"]','[class*="article-meta"]'];
  for (var i = 0; i < metaSels.length; i++) {
    var mEl = document.querySelector(metaSels[i]);
    if (mEl) { var mT = (mEl.innerText || '').trim(); if (mT && mT.length < 80) { metaText = mT; break; } }
  }
  if (metaText) {
    var mline = metaText.split('\n').map(function(s){ return s.trim(); }).filter(function(s){ return s; });
    if (!author && mline.length && mline[0].length < 30 && !/^Lv\.?\s*\d/i.test(mline[0]) && mline[0].indexOf('关注') < 0) {
      author = mline[0];
    }
    if (!publishedAt) {
      var dm2 = metaText.match(/(\d{4}-\d{2}-\d{2}|\d{2}-\d{2})/);
      if (dm2) publishedAt = dm2[1];
    }
  }
  // 兜底：小黑盒作者名与 Lv.NN 分属两行，找到 Lv 行后向上回溯最近的单行昵称
  if (!author) {
    var lines = (document.body.innerText || '').split('\n').map(function(s){ return s.trim(); }).filter(function(s){ return s; });
    for (var i = 0; i < lines.length; i++) {
      if (/^Lv\.?\s*\d+/i.test(lines[i])) {
        for (var j = i - 1; j >= 0 && i - j <= 4; j--) {
          if (/^[A-Za-z0-9_\-\u4e00-\u9fa5]{1,30}$/.test(lines[j])) {
            author = lines[j];
            break;
          }
        }
        break;
      }
    }
  }
  if (!publishedAt) {
    var tm = (document.body.innerText || '').match(/Lv\.?\s*\d+\s*(\d{4}-\d{2}-\d{2}|\d{2}-\d{2})/);
    if (tm) publishedAt = tm[1];
  }
  return JSON.stringify({text: t, images: images, author: author, publishedAt: publishedAt, title: title});
})()
