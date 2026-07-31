/* Enitor — поведение лендинга. Один файл на обе языковые версии: всё, что
   зависит от языка, приходит из разметки через data-атрибуты. */
(function () {
  'use strict';

  document.documentElement.classList.add('js');

  /* ── Каскадное появление блоков ──────────────────────────────────────────
     Тот же жест, что StaggerReveal в приложении. Всё под IntersectionObserver:
     без поддержки класс .in ставится сразу, и страница просто остаётся видимой
     (в CSS скрытие включается только классом .js, который выставлен выше). */
  var items = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e, i) {
        if (!e.isIntersecting) return;
        var el = e.target;
        setTimeout(function () { el.classList.add('in'); }, Math.min(i * 45, 360));
        io.unobserve(el);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    items.forEach(function (el) { io.observe(el); });
  } else {
    items.forEach(function (el) { el.classList.add('in'); });
  }

  /* ── Просмотр скриншота в полный размер ──────────────────────────────────
     На странице скриншот занимает ~380px, а файл лежит 706px — мелкий текст
     интерфейса иначе не прочитать. Используется <dialog>: он сам держит фокус
     внутри, сам закрывается по Esc и сам возвращает фокус на кнопку, с которой
     его открыли. Если <dialog> не поддерживается, кнопки просто прячутся и
     остаются обычные картинки — ничего не ломается. */
  var lb = document.getElementById('lightbox');
  var zooms = document.querySelectorAll('.zoom');

  if (lb && typeof lb.showModal === 'function') {
    var lbImg = lb.querySelector('img');
    var lbCap = lb.querySelector('figcaption');

    zooms.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var img = btn.querySelector('img');
        if (!img) return;
        // currentSrc — то, что браузер реально выбрал из <picture>: webp там,
        // где он поддерживается, и png в остальных случаях.
        lbImg.src = img.currentSrc || img.src;
        lbImg.alt = img.alt;
        lbCap.textContent = btn.dataset.caption || img.alt || '';
        lb.showModal();
      });
    });

    // Клик мимо картинки закрывает: событие на самом <dialog> приходит только
    // от подложки, потому что содержимое лежит во вложенном <figure>.
    lb.addEventListener('click', function (e) {
      if (e.target === lb) lb.close();
    });
    var closeBtn = lb.querySelector('.close');
    if (closeBtn) closeBtn.addEventListener('click', function () { lb.close(); });
  } else {
    // Без поддержки диалога незачем показывать курсор «лупа» и ловить клики.
    zooms.forEach(function (btn) { btn.style.cursor = 'default'; });
    if (lb) lb.remove();
  }

  /* ── Номер последней версии в «таблетке» ─────────────────────────────────
     Ничего не ломается, если GitHub не ответит или упрётся в лимит запросов:
     в разметке уже лежит осмысленный текст, и он просто останется на месте. */
  var pill = document.getElementById('release-pill');
  if (pill && window.fetch) {
    fetch('https://api.github.com/repos/alexskvo10/Enitor/releases/latest')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) {
        if (j && j.tag_name) {
          pill.textContent = j.tag_name + ' — ' + (pill.dataset.latest || 'latest');
        }
      })
      .catch(function () {});
  }
})();
