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

  /* ── Иконка в шапке поворачивается вслед за курсором ─────────────────────
     Наклон в трёх измерениях: грань «смотрит» туда, где указатель. Скрипт
     только считает углы и кладёт их в переменные — вся отрисовка в CSS.

     Включается лишь там, где есть настоящее наведение: на тач-экранах
     hover срабатывает по касанию и застревает, а смысла в наклоне нет.
     Просьбу системы убрать анимацию тоже уважаем. */
  var wrap = document.querySelector('.hero .mark-wrap');
  var mark = wrap && wrap.querySelector('.mark');
  var canHover = window.matchMedia
    && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  var calmDown = window.matchMedia
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  if (mark && canHover && !calmDown) {
    var MAX_TILT = 15; // градусов от центра к краю

    // Слушаем обёртку, а не саму картинку: её геометрия не меняется при
    // наклоне, поэтому курсор не выпадает из неё у края.
    wrap.addEventListener('pointermove', function (e) {
      var r = wrap.getBoundingClientRect();
      // -0.5 у левого/верхнего края, +0.5 у правого/нижнего.
      var dx = (e.clientX - r.left) / r.width - 0.5;
      var dy = (e.clientY - r.top) / r.height - 0.5;
      // Знак у rotateX обратный: ось X горизонтальная, и чтобы верх уходил
      // от зрителя при курсоре внизу, угол нужен отрицательный.
      mark.classList.remove('settle');
      mark.style.setProperty('--ry', (dx * 2 * MAX_TILT).toFixed(2) + 'deg');
      mark.style.setProperty('--rx', (-dy * 2 * MAX_TILT).toFixed(2) + 'deg');
    });

    wrap.addEventListener('pointerleave', function () {
      mark.classList.add('settle');
      mark.style.setProperty('--rx', '0deg');
      mark.style.setProperty('--ry', '0deg');
    });
  }

  /* ── Переключатель Windows / Android у галереи ───────────────────────────
     В разметке обе галереи видимы: без скрипта посетитель просто увидит
     подряд оба набора скриншотов, а не пустое место. Прячет лишнее уже JS. */
  var switcher = document.querySelector('.switch');
  if (switcher) {
    var buttons = Array.prototype.slice.call(switcher.querySelectorAll('button'));
    var panels = buttons.map(function (b) { return document.getElementById(b.dataset.shots); });

    if (panels.every(Boolean)) {
      // Таблетку двигаем по замеренным кнопкам, а не по долям ширины: подписи
      // разной длины, и «половина» с кнопкой не совпала бы.
      var movePill = function (btn) {
        switcher.style.setProperty('--pill-x', btn.offsetLeft + 'px');
        switcher.style.setProperty('--pill-w', btn.offsetWidth + 'px');
      };

      var show = function (active) {
        movePill(buttons[active]);
        buttons.forEach(function (b, i) {
          var on = i === active;
          b.classList.toggle('on', on);
          b.setAttribute('aria-pressed', on ? 'true' : 'false');
          panels[i].hidden = !on;
          // Скрытый блок не попадает в IntersectionObserver, поэтому его
          // карточки так и остались бы прозрачными после появления. Показывая
          // панель, доводим их до конечного состояния руками.
          if (on) {
            panels[i].querySelectorAll('.reveal').forEach(function (el) {
              el.classList.add('in');
            });
          }
        });
      };
      // Ставим таблетку на место без перехода, иначе при загрузке она бы
      // проехала из левого угла. Класс placing снимаем в следующем кадре,
      // когда стартовое положение уже применено.
      switcher.classList.add('sliding', 'placing');
      show(0);
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { switcher.classList.remove('placing'); });
      });

      buttons.forEach(function (b, i) {
        b.addEventListener('click', function () { show(i); });
      });

      // Ширина кнопок меняется вместе со шрифтом и раскладкой — на смену
      // размера окна пересчитываем, иначе таблетка уедет мимо.
      window.addEventListener('resize', function () {
        var current = buttons.filter(function (b) { return b.classList.contains('on'); })[0];
        if (current) movePill(current);
      });
    }
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

  /* ── Число звёзд на кнопке ───────────────────────────────────────────────
     Отдельный запрос: номер релиза и счётчик звёзд лежат в разных ответах
     API. Если он не придёт — на кнопке просто не появится счётчик, а сама
     кнопка работает как обычная ссылка. Точка-разделитель нарисована в CSS
     по :not(:empty), поэтому пустой счётчик не оставляет висячий разделитель. */
  var stars = document.getElementById('star-count');
  if (stars && window.fetch) {
    fetch('https://api.github.com/repos/alexskvo10/Enitor')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) {
        if (j && typeof j.stargazers_count === 'number') {
          stars.textContent = j.stargazers_count;
        }
      })
      .catch(function () {});
  }
})();
