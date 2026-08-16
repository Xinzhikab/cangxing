(function() {
  var h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
  var y = 0;
  var step = Math.max(200, Math.floor(h / 10));
  var timer = setInterval(function() {
    y += step;
    if (y >= h) {
      clearInterval(timer);
      window.scrollTo(0, 0);
    } else {
      window.scrollTo(0, y);
    }
  }, 100);
})()
