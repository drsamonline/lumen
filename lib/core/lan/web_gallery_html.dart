/// A single self-contained page served to any browser on the local network.
/// No CDN, no fonts, no telemetry — it works with the router's WAN port
/// unplugged, which is the whole point.
const String kGalleryHtmlTemplate = r"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<title>__NAME__ — Lumen</title>
<style>
  :root {
    --bg: #0d0f11;
    --panel: #16191d;
    --ink: #e8eaed;
    --muted: #9aa0a6;
    --accent: #7fd1c8;
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; background: var(--bg); color: var(--ink);
    font: 15px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  header {
    position: sticky; top: 0; z-index: 5;
    display: flex; align-items: center; gap: 12px;
    padding: 14px 18px; background: rgba(13,15,17,.88);
    backdrop-filter: blur(12px); border-bottom: 1px solid #22262b;
  }
  header h1 { font-size: 15px; font-weight: 600; margin: 0; letter-spacing: .02em; }
  header .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--accent); }
  header .count { margin-left: auto; color: var(--muted); font-size: 13px; }
  .wrap { padding: 10px 10px 80px; }
  .grid {
    display: grid; gap: 4px;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  }
  @media (max-width: 520px) {
    .grid { grid-template-columns: repeat(auto-fill, minmax(110px, 1fr)); gap: 3px; }
  }
  .tile {
    position: relative; aspect-ratio: 1; overflow: hidden;
    background: var(--panel); border-radius: 6px; cursor: pointer;
    contain: content;
  }
  .tile img {
    width: 100%; height: 100%; object-fit: cover; display: block;
    opacity: 0; transition: opacity .28s ease;
  }
  .tile img.loaded { opacity: 1; }
  .tile .fav {
    position: absolute; top: 5px; right: 6px; font-size: 13px;
    color: #ffd166; text-shadow: 0 1px 3px #000;
  }
  .empty { color: var(--muted); text-align: center; padding: 80px 20px; }
  /* lightbox */
  #lb {
    position: fixed; inset: 0; z-index: 20; display: none;
    background: #000; flex-direction: column;
  }
  #lb.on { display: flex; }
  #lb .bar {
    display: flex; align-items: center; gap: 14px; padding: 12px 16px;
    color: var(--muted); font-size: 13px;
  }
  #lb .bar button {
    background: #1e2227; color: var(--ink); border: 0; border-radius: 8px;
    padding: 7px 13px; font-size: 14px; cursor: pointer;
  }
  #lb .stage { flex: 1; display: grid; place-items: center; overflow: hidden; }
  #lb img { max-width: 100%; max-height: 100%; object-fit: contain; }
  #lb .meta { padding: 10px 16px 20px; color: var(--muted); font-size: 12px;
    text-align: center; }
  .sentinel { height: 1px; }
</style>
</head>
<body>
<header>
  <span class="dot"></span>
  <h1>__NAME__</h1>
  <span class="count" id="count"></span>
</header>
<div class="wrap">
  <div class="grid" id="grid"></div>
  <div class="sentinel" id="sentinel"></div>
  <div class="empty" id="empty" style="display:none">
    Nothing here yet. Scan a folder in the Lumen app.
  </div>
</div>

<div id="lb">
  <div class="bar">
    <button id="close">Close</button>
    <span id="lbname"></span>
  </div>
  <div class="stage"><img id="lbimg" alt=""></div>
  <div class="meta" id="lbmeta"></div>
</div>

<script>
(function () {
  var grid = document.getElementById('grid');
  var sentinel = document.getElementById('sentinel');
  var emptyEl = document.getElementById('empty');
  var countEl = document.getElementById('count');

  var offset = 0;
  var limit = 60;
  var total = null;
  var loading = false;
  var exhausted = false;

  function el(tag, cls) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    return n;
  }

  function openLightbox(photo) {
    var lb = document.getElementById('lb');
    document.getElementById('lbimg').src = '/photo/' + photo.id;
    document.getElementById('lbname').textContent = photo.file_name;
    var bits = [];
    if (photo.camera_model) bits.push(photo.camera_model);
    if (photo.taken_label) bits.push(photo.taken_label);
    if (photo.width && photo.height) bits.push(photo.width + ' x ' + photo.height);
    document.getElementById('lbmeta').textContent = bits.join('  ·  ');
    lb.classList.add('on');
  }

  document.getElementById('close').addEventListener('click', function () {
    document.getElementById('lb').classList.remove('on');
    document.getElementById('lbimg').src = '';
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') document.getElementById('close').click();
  });

  function addTiles(photos) {
    var frag = document.createDocumentFragment();
    photos.forEach(function (p) {
      var tile = el('div', 'tile');
      var img = el('img');
      img.loading = 'lazy';
      img.decoding = 'async';
      img.alt = p.file_name;
      img.src = '/thumb/' + p.id;
      img.addEventListener('load', function () { img.classList.add('loaded'); });
      tile.appendChild(img);
      if (p.is_favorite) {
        var star = el('span', 'fav');
        star.textContent = '\u2605';
        tile.appendChild(star);
      }
      tile.addEventListener('click', function () { openLightbox(p); });
      frag.appendChild(tile);
    });
    grid.appendChild(frag);
  }

  function loadMore() {
    if (loading || exhausted) return;
    loading = true;
    fetch('/api/photos?offset=' + offset + '&limit=' + limit)
      .then(function (r) { return r.json(); })
      .then(function (data) {
        total = data.total;
        countEl.textContent = data.total + ' photos';
        addTiles(data.photos);
        offset += data.photos.length;
        if (data.photos.length < limit) exhausted = true;
        if (data.total === 0) emptyEl.style.display = 'block';
        loading = false;
        if (!exhausted) maybeFill();
      })
      .catch(function () { loading = false; });
  }

  function maybeFill() {
    // Keep pulling until the page is taller than the viewport.
    if (document.body.scrollHeight < window.innerHeight + 200 && !exhausted) {
      loadMore();
    }
  }

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) { if (e.isIntersecting) loadMore(); });
  }, { rootMargin: '600px' });
  io.observe(sentinel);

  loadMore();
})();
</script>
</body>
</html>
""";

String buildGalleryHtml({required String libraryName, required int port}) {
  return kGalleryHtmlTemplate
      .replaceAll('__NAME__', libraryName)
      .replaceAll('__PORT__', port.toString());
}
