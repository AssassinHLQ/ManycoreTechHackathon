(function () {
  const touchCapable = (navigator.maxTouchPoints || 0) > 0 || 'ontouchstart' in window;
  if (!touchCapable) return;

  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  const viewport = document.querySelector('meta[name="viewport"]');
  if (viewport) {
    viewport.setAttribute('content', 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover');
  }

  const style = document.createElement('style');
  style.textContent = [
    'html.mobile-immersive, html.mobile-immersive body { margin:0; padding:0; overflow:hidden; background:#000; overscroll-behavior:none; }',
    '#mobile-immersive-btn { position:fixed; z-index:99999; top:calc(10px + env(safe-area-inset-top)); left:calc(10px + env(safe-area-inset-left)); padding:9px 14px; border-radius:999px; border:1px solid rgba(130,220,210,.8); background:rgba(8,24,30,.84); color:#dff7f2; font:14px/1.2 "Microsoft YaHei",system-ui,sans-serif; letter-spacing:.06em; box-shadow:0 4px 18px rgba(0,0,0,.45); -webkit-tap-highlight-color:transparent; }',
    '#mobile-immersive-btn:active { background:rgba(26,78,78,.94); }',
    '#mobile-immersive-btn.hidden { display:none; }',
    '#mobile-immersive-rotate { position:fixed; inset:0; z-index:99998; display:none; align-items:center; justify-content:center; background:rgba(2,6,12,.94); color:#dff7f2; font:18px/1.7 "Microsoft YaHei",system-ui,sans-serif; letter-spacing:.06em; text-align:center; padding:24px; }',
    '#mobile-immersive-rotate.show { display:flex; }'
  ].join('\n');
  document.head.appendChild(style);
  document.documentElement.classList.add('mobile-immersive');

  const button = document.createElement('button');
  button.id = 'mobile-immersive-btn';
  button.type = 'button';
  button.textContent = isIOS ? '请旋转手机' : '横屏全屏';
  button.title = isIOS ? 'iOS 不支持网页强制横屏，请手动旋转手机' : '进入全屏并锁定横屏';
  document.body.appendChild(button);

  const rotate = document.createElement('div');
  rotate.id = 'mobile-immersive-rotate';
  rotate.textContent = '请把手机横过来';
  document.body.appendChild(rotate);

  function updateRotate() {
    const portrait = window.innerHeight > window.innerWidth;
    rotate.classList.toggle('show', portrait);
  }
  window.addEventListener('resize', updateRotate);
  if (screen.orientation && screen.orientation.addEventListener) {
    screen.orientation.addEventListener('change', updateRotate);
  }
  updateRotate();

  function fullscreenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
  }

  function refresh() {
    const active = !!fullscreenElement();
    button.classList.toggle('hidden', active);
    button.style.display = active ? 'none' : '';
  }

  async function lockLandscape() {
    try {
      if (screen.orientation && screen.orientation.lock) {
        await screen.orientation.lock('landscape');
        updateRotate();
      }
    } catch (error) {
      console.warn('[immersive] orientation lock unavailable', error);
    }
  }

  async function enterImmersive() {
    const el = document.documentElement;
    try {
      if (!fullscreenElement()) {
        const request = el.requestFullscreen || el.webkitRequestFullscreen;
        if (request) await request.call(el, { navigationUI: 'hide' });
      }
    } catch (error) {
      console.warn('[immersive] fullscreen unavailable', error);
    }
    await lockLandscape();
    setTimeout(() => {
      refresh();
      window.dispatchEvent(new Event('resize'));
    }, 350);
  }

  button.addEventListener('click', enterImmersive);

  let autoTried = false;
  function autoImmersive() {
    if (autoTried) return;
    autoTried = true;
    enterImmersive();
  }
  window.addEventListener('pointerup', autoImmersive, { capture: true, once: true });
  window.addEventListener('touchend', autoImmersive, { capture: true, once: true });

  document.addEventListener('fullscreenchange', function () {
    if (fullscreenElement()) lockLandscape();
    refresh();
  });
  document.addEventListener('webkitfullscreenchange', refresh);
  setInterval(refresh, 800);
  window.addEventListener('orientationchange', function () {
    if (fullscreenElement()) lockLandscape();
    updateRotate();
    refresh();
  });

  refresh();
})();
