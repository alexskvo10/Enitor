// Веб-страница сервера (С2-web): одна страница на GET /, без внешних библиотек и шрифтов.
// Данные выводятся только через textContent — innerHTML не используется.
const kWebPage = r'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Enitor</title>
<style>
:root {
  --bg: #f5f6f8;
  --card: #ffffff;
  --text: #1d2026;
  --muted: #6b7280;
  --line: #e3e6ea;
  --accent: #3b6ef5;
  --accent-text: #ffffff;
  --danger: #d64541;
  --input-bg: #ffffff;
  --chip: #eef1f6;
  --p-none: #9aa1ab;
  --p-low: #2e9d5b;
  --p-medium: #d99a1e;
  --p-high: #d64541;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #121417;
    --card: #1c2026;
    --text: #e8eaee;
    --muted: #9aa3ae;
    --line: #2c323b;
    --accent: #6d93ff;
    --accent-text: #0b0d10;
    --danger: #ff6b67;
    --input-bg: #15181d;
    --chip: #262c35;
    --p-none: #6b727c;
    --p-low: #48c17d;
    --p-medium: #f0b043;
    --p-high: #ff6b67;
  }
}
[hidden] { display: none !important; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: var(--bg);
  color: var(--text);
  font: 15px/1.4 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
.wrap { max-width: 640px; margin: 0 auto; padding: 16px; }
h1 { font-size: 22px; margin: 8px 0; }
h2 { font-size: 17px; margin: 0 0 8px; }
.top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.card {
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 12px;
  margin: 12px 0;
}
.daynav { display: flex; align-items: center; gap: 8px; margin-top: 8px; }
.daylabel { flex: 1; text-align: center; font-weight: 600; min-width: 0; overflow-wrap: anywhere; }
.todaywrap { text-align: center; margin: 6px 0 0; }
.muted { color: var(--muted); }
.err { color: var(--danger); margin: 8px 0 0; overflow-wrap: anywhere; }
.list { list-style: none; margin: 0 0 8px; padding: 0; }
.row {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  gap: 8px;
  padding: 8px 0;
  border-top: 1px solid var(--line);
}
.row:first-child { border-top: none; }
.row > .grow { flex: 1 1 160px; min-width: 0; }
.row > input[type=checkbox] { width: 20px; height: 20px; margin: 4px 0 0; flex: 0 0 auto; }
.row.edit > .formrow { flex: 1 1 100%; }
.row.edit > .actions { flex: 1 1 100%; }
.title { overflow-wrap: anywhere; }
.done { text-decoration: line-through; color: var(--muted); }
.meta { font-size: 13px; color: var(--muted); display: flex; flex-wrap: wrap; gap: 2px 10px; margin-top: 2px; }
.prio::before { content: "\25CF\00a0"; }
.p1 { color: var(--p-low); }
.p2 { color: var(--p-medium); }
.p3 { color: var(--p-high); }
.empty { color: var(--muted); padding: 8px 0; list-style: none; }
.actions { display: flex; flex-wrap: wrap; gap: 6px; align-items: flex-start; }
.form { display: flex; flex-direction: column; gap: 8px; border-top: 1px solid var(--line); padding-top: 12px; margin-top: 8px; }
.formrow { display: flex; flex-wrap: wrap; gap: 8px; }
.formrow > * { flex: 1 1 130px; min-width: 0; }
.formrow > input[type=text] { flex-basis: 100%; }
.formrow label { display: flex; flex-direction: column; gap: 4px; font-size: 13px; color: var(--muted); }
input, select, button { font: inherit; }
input[type=text], input[type=time], input[type=number], input[type=password], select {
  width: 100%;
  min-width: 0;
  padding: 9px 10px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--input-bg);
  color: var(--text);
}
button {
  min-height: 36px;
  padding: 8px 12px;
  border-radius: 8px;
  border: 1px solid var(--line);
  background: var(--chip);
  color: var(--text);
  cursor: pointer;
}
button.primary { background: var(--accent); border-color: var(--accent); color: var(--accent-text); }
button.ghost { background: transparent; }
button.danger { color: var(--danger); }
</style>
</head>
<body>
<div class="wrap">

  <section id="auth" hidden>
    <h1>Enitor</h1>
    <p class="muted">Введите токен сервера. Он сохранится в этом браузере, пока вы не нажмёте «Выйти».</p>
    <form id="auth-form" class="card form">
      <input id="token-input" type="password" autocomplete="off" placeholder="Токен" aria-label="Токен" required>
      <button type="submit" class="primary">Войти</button>
      <p id="auth-msg" class="err"></p>
    </form>
  </section>

  <section id="app" hidden>
    <header class="top">
      <h1>Enitor</h1>
      <button type="button" id="logout" class="ghost">Выйти</button>
    </header>

    <nav class="daynav">
      <button type="button" id="prev" class="ghost" aria-label="Предыдущий день">←</button>
      <div id="day-label" class="daylabel"></div>
      <button type="button" id="next" class="ghost" aria-label="Следующий день">→</button>
    </nav>
    <div class="todaywrap"><button type="button" id="today" class="ghost">Сегодня</button></div>

    <p id="msg" class="err" role="alert" hidden></p>

    <section class="card">
      <h2>Задачи</h2>
      <ul id="task-list" class="list"></ul>
      <form id="task-form" class="form">
        <input id="task-title" type="text" required maxlength="200" placeholder="Новая задача" aria-label="Название задачи">
        <div class="formrow">
          <label>Начало <input id="task-start" type="time"></label>
          <label>Конец <input id="task-end" type="time"></label>
          <label>Важность <select id="task-priority"></select></label>
        </div>
        <button type="submit" class="primary">Добавить задачу</button>
      </form>
    </section>

    <section class="card">
      <h2>Расписание</h2>
      <ul id="sched-list" class="list"></ul>
      <form id="sched-form" class="form">
        <input id="sched-title" type="text" required maxlength="200" placeholder="Название" aria-label="Название пункта">
        <div class="formrow">
          <label>Начало <input id="sched-start" type="time" required></label>
          <label>Конец <input id="sched-end" type="time"></label>
        </div>
        <input id="sched-location" type="text" maxlength="200" placeholder="Место (необязательно)" aria-label="Место">
        <button type="submit" class="primary">Добавить в расписание</button>
      </form>
    </section>

    <section class="card">
      <h2>Цели периода</h2>
      <ul id="goal-list" class="list"></ul>
      <form id="goal-form" class="form">
        <input id="goal-title" type="text" required maxlength="200" placeholder="Новая цель" aria-label="Название цели">
        <div class="formrow">
          <label>Период <select id="goal-period"></select></label>
          <label>Цель, шт. <input id="goal-target" type="number" min="1" step="1" placeholder="без счётчика"></label>
        </div>
        <button type="submit" class="primary">Добавить цель</button>
      </form>
    </section>
  </section>

</div>
<script>
(function () {
  'use strict';

  var TOKEN_KEY = 'enitor-token';
  var PRIORITY = [
    { v: 'none', t: 'нет' },
    { v: 'low', t: 'низкая' },
    { v: 'medium', t: 'средняя' },
    { v: 'high', t: 'высокая' }
  ];
  var PERIODS = [
    { v: 'week', t: 'неделя' },
    { v: 'month', t: 'месяц' },
    { v: 'season', t: 'сезон' },
    { v: 'year', t: 'год' }
  ];
  var REPEAT = { weekly: 'каждую неделю', monthly: 'каждый месяц', interval: 'повтор по дням' };

  var state = { token: '', day: '', rev: null, data: null, editing: null, timer: null };

  class AuthError extends Error {}

  // ── Мелочи ────────────────────────────────────────────────────────────────

  function $(id) { return document.getElementById(id); }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function ymd(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function parts(s) { return s.split('-').map(Number); }
  function shiftDay(s, n) { var p = parts(s); return ymd(new Date(p[0], p[1] - 1, p[2] + n)); }
  function dayLabel(s) {
    var p = parts(s);
    return new Date(p[0], p[1] - 1, p[2]).toLocaleDateString('ru-RU', { weekday: 'long', day: 'numeric', month: 'long' });
  }
  function hm(min) { return pad(Math.floor(min / 60)) + ':' + pad(min % 60); }
  function span(s, e) {
    if (s === null || s === undefined) return '';
    return hm(s) + (e === null || e === undefined ? '' : '–' + hm(e));
  }
  function enc(s) { return encodeURIComponent(s); }
  function pick(o) {
    var r = {};
    Object.keys(o).forEach(function (k) { if (o[k] !== '' && o[k] !== undefined) r[k] = o[k]; });
    return r;
  }
  function periodLabel(v) {
    for (var i = 0; i < PERIODS.length; i++) if (PERIODS[i].v === v) return PERIODS[i].t;
    return v;
  }
  function sortByTime(list) {
    return list.slice().sort(function (a, b) {
      var sa = a.startMinutes == null ? 99999 : a.startMinutes;
      var sb = b.startMinutes == null ? 99999 : b.startMinutes;
      return (sa - sb) || ((a.order || 0) - (b.order || 0));
    });
  }

  function el(tag, props, kids) {
    var n = document.createElement(tag);
    props = props || {};
    Object.keys(props).forEach(function (k) {
      var v = props[k];
      if (v === null || v === undefined || v === false) return;
      if (k === 'text') n.textContent = String(v);
      else if (k === 'cls') n.className = v;
      else if (k === 'value') n.value = v;
      else if (k === 'checked') n.checked = !!v;
      else if (k === 'on') Object.keys(v).forEach(function (ev) { n.addEventListener(ev, v[ev]); });
      else n.setAttribute(k, v === true ? '' : String(v));
    });
    (kids || []).forEach(function (c) { if (c) n.appendChild(c); });
    return n;
  }
  function clear(n) {
    while (n.firstChild) n.removeChild(n.firstChild);
    return n;
  }
  function fillOptions(sel, list, def) {
    clear(sel);
    list.forEach(function (p) {
      sel.appendChild(el('option', { value: p.v, text: p.t, selected: p.v === def }));
    });
    return sel;
  }

  // ── Сообщения об ошибках ──────────────────────────────────────────────────

  function showError(msg) {
    var box = $('msg');
    box.textContent = msg;
    box.hidden = false;
  }
  function clearError() {
    $('msg').textContent = '';
    $('msg').hidden = true;
  }
  function handleErr(e) {
    if (e instanceof AuthError) { showAuth('Токен не подошёл. Введите его снова.', true); return; }
    showError(e && e.message ? e.message : 'Неизвестная ошибка');
  }

  // ── Сеть ──────────────────────────────────────────────────────────────────

  function api(method, path, body) {
    var headers = { Authorization: 'Bearer ' + state.token };
    var opts = { method: method, headers: headers };
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts).then(function (res) {
      return res.json().catch(function () { return null; }).then(function (j) {
        if (res.status === 401) throw new AuthError('unauthorized');
        if (!j || j.ok !== true) {
          var e = j && j.error;
          throw new Error(e && e.message ? e.message : 'Ошибка сервера (' + res.status + ')');
        }
        return j.result;
      });
    }, function () {
      throw new Error('Нет связи с сервером');
    });
  }

  // Выполнить действие: при ошибке показать сообщение, потом перечитать день
  // (чтобы галочки и списки совпали с сервером). Возвращает true при успехе.
  function run(p) {
    clearError();
    return p.then(function () { return true; }, function (e) { handleErr(e); return false; })
      .then(function (ok) {
        return state.token ? refresh().then(function () { return ok; }) : ok;
      });
  }

  function load() {
    var day = state.day;
    return api('GET', '/v1/ping').then(function (p) {
      state.rev = p.rev;
      return api('GET', '/v1/days/' + day);
    }).then(function (d) {
      if (day !== state.day) return;
      state.data = d;
      render();
    });
  }
  function refresh() { return load().catch(handleErr); }

  function poll() {
    if (!state.token) return;
    api('GET', '/v1/ping').then(function (p) {
      // Во время правки задачи не перерисовываем: введённое не должно пропасть.
      if (p.rev !== state.rev && !state.editing) return load();
    }).catch(handleErr);
  }
  function startPolling() {
    stopPolling();
    state.timer = setInterval(poll, 10000);
  }
  function stopPolling() {
    if (state.timer) clearInterval(state.timer);
    state.timer = null;
  }

  // ── Вход / выход ──────────────────────────────────────────────────────────

  function showAuth(msg, forget) {
    stopPolling();
    state.token = '';
    state.data = null;
    state.editing = null;
    if (forget) { try { localStorage.removeItem(TOKEN_KEY); } catch (e) {} }
    $('app').hidden = true;
    $('auth').hidden = false;
    $('auth-msg').textContent = msg || '';
    $('token-input').value = '';
    $('token-input').focus();
  }

  function enter(token) {
    state.token = token;
    return api('GET', '/v1/ping').then(function (p) {
      try { localStorage.setItem(TOKEN_KEY, token); } catch (e) {}
      state.rev = p.rev;
      $('auth').hidden = true;
      $('app').hidden = false;
      startPolling();
      return load();
    }).catch(function (e) {
      if (e instanceof AuthError) showAuth('Неверный токен', true);
      else showAuth(e.message, false);
    });
  }

  function goDay(day) {
    state.day = day;
    state.editing = null;
    clearError();
    refresh();
  }

  // ── Задачи ────────────────────────────────────────────────────────────────

  function renderTasks(list) {
    var ul = clear($('task-list'));
    if (!list.length) {
      ul.appendChild(el('li', { cls: 'empty', text: 'Задач на этот день нет' }));
      return;
    }
    sortByTime(list).forEach(function (t) { ul.appendChild(taskRow(t)); });
  }

  function taskRow(t) {
    if (state.editing === t.id) return taskEditRow(t);
    var prio = t.priority || 0;
    var cb = el('input', {
      type: 'checkbox',
      'aria-label': 'Отметить задачу',
      checked: !!t.completedAt,
      on: {
        change: function () {
          run(api('POST', '/v1/tasks/' + enc(t.id) + (cb.checked ? '/complete' : '/uncomplete')));
        }
      }
    });
    var info = el('div', { cls: 'grow' }, [
      el('div', { cls: 'title' + (t.completedAt ? ' done' : ''), text: t.title }),
      el('div', { cls: 'meta' }, [
        t.startMinutes == null ? null : el('span', { text: span(t.startMinutes, t.endMinutes) }),
        prio ? el('span', { cls: 'prio p' + prio, text: PRIORITY[prio].t }) : null,
        t.virtual ? el('span', { text: 'повтор' }) : null
      ])
    ]);
    var actions = el('div', { cls: 'actions' }, [
      el('button', { type: 'button', cls: 'ghost', text: 'Изменить', on: {
        click: function () { state.editing = t.id; render(); }
      } }),
      el('button', { type: 'button', cls: 'ghost danger', text: 'Удалить', on: {
        click: function () { run(api('DELETE', '/v1/tasks/' + enc(t.id))); }
      } })
    ]);
    return el('li', { cls: 'row' }, [cb, info, actions]);
  }

  function taskEditRow(t) {
    var title = el('input', { type: 'text', required: true, maxlength: 200, value: t.title, 'aria-label': 'Название' });
    var start = el('input', { type: 'time', value: t.startMinutes == null ? '' : hm(t.startMinutes), 'aria-label': 'Начало' });
    var end = el('input', { type: 'time', value: t.endMinutes == null ? '' : hm(t.endMinutes), 'aria-label': 'Конец' });
    var sel = fillOptions(el('select', { 'aria-label': 'Важность' }), PRIORITY, PRIORITY[t.priority || 0].v);
    var save = el('button', { type: 'button', cls: 'primary', text: 'Сохранить', on: {
      click: function () {
        if (!title.value.trim()) { showError('Введите название задачи'); return; }
        run(api('PATCH', '/v1/tasks/' + enc(t.id), {
          title: title.value.trim(),
          start: start.value || null,
          end: end.value || null,
          priority: sel.value
        })).then(function (ok) {
          if (ok) { state.editing = null; render(); }
        });
      }
    } });
    var cancel = el('button', { type: 'button', cls: 'ghost', text: 'Отмена', on: {
      click: function () { state.editing = null; render(); }
    } });
    return el('li', { cls: 'row edit' }, [
      el('div', { cls: 'formrow' }, [title, start, end, sel]),
      el('div', { cls: 'actions' }, [save, cancel])
    ]);
  }

  // ── Расписание ────────────────────────────────────────────────────────────

  function renderSchedule(list) {
    var ul = clear($('sched-list'));
    if (!list.length) {
      ul.appendChild(el('li', { cls: 'empty', text: 'На этот день пунктов нет' }));
      return;
    }
    sortByTime(list).forEach(function (s) { ul.appendChild(schedRow(s)); });
  }

  function schedRow(s) {
    var series = !!s.repeat;
    var info = el('div', { cls: 'grow' }, [
      el('div', { cls: 'title', text: s.title }),
      el('div', { cls: 'meta' }, [
        s.startMinutes == null ? null : el('span', { text: span(s.startMinutes, s.endMinutes) }),
        s.location ? el('span', { text: s.location }) : null,
        series ? el('span', { text: REPEAT[s.repeat] || 'повтор' }) : null
      ])
    ]);
    var btns;
    if (series) {
      btns = [
        el('button', { type: 'button', cls: 'ghost', text: 'Удалить только этот день', on: {
          click: function () { run(api('DELETE', '/v1/schedule/' + enc(s.id) + '?scope=day&date=' + state.day)); }
        } }),
        el('button', { type: 'button', cls: 'ghost danger', text: 'Удалить всю серию', on: {
          click: function () {
            if (confirm('Удалить всю серию «' + s.title + '»?')) run(api('DELETE', '/v1/schedule/' + enc(s.id)));
          }
        } })
      ];
    } else {
      btns = [
        el('button', { type: 'button', cls: 'ghost danger', text: 'Удалить', on: {
          click: function () { run(api('DELETE', '/v1/schedule/' + enc(s.id))); }
        } })
      ];
    }
    return el('li', { cls: 'row' }, [info, el('div', { cls: 'actions' }, btns)]);
  }

  // ── Цели ──────────────────────────────────────────────────────────────────

  function renderGoals(list) {
    var ul = clear($('goal-list'));
    if (!list.length) {
      ul.appendChild(el('li', { cls: 'empty', text: 'Целей на этот день нет' }));
      return;
    }
    list.forEach(function (g) { ul.appendChild(goalRow(g)); });
  }

  function goalRow(g) {
    // Прогресс цели = ручная часть + связанная с задачами (см. Goal.progressCount).
    var total = (g.manualProgress || 0) + (g.linkedProgress || 0);
    var cb = el('input', {
      type: 'checkbox',
      'aria-label': 'Отметить цель',
      checked: !!g.completed,
      on: {
        change: function () {
          run(api('POST', '/v1/goals/' + enc(g.id) + (cb.checked ? '/complete' : '/uncomplete')));
        }
      }
    });
    var info = el('div', { cls: 'grow' }, [
      el('div', { cls: 'title' + (g.completed ? ' done' : ''), text: g.title }),
      el('div', { cls: 'meta' }, [
        el('span', { text: periodLabel(g.period) }),
        el('span', { text: g.targetCount ? total + ' / ' + g.targetCount : 'прогресс: ' + total })
      ])
    ]);
    var actions = el('div', { cls: 'actions' }, [
      el('button', { type: 'button', cls: 'ghost', text: '+1', on: {
        click: function () { run(api('POST', '/v1/goals/' + enc(g.id) + '/progress', { value: total + 1 })); }
      } }),
      el('button', { type: 'button', cls: 'ghost danger', text: 'Удалить', on: {
        click: function () { run(api('DELETE', '/v1/goals/' + enc(g.id))); }
      } })
    ]);
    return el('li', { cls: 'row' }, [cb, info, actions]);
  }

  // ── Общая перерисовка ─────────────────────────────────────────────────────

  function render() {
    var d = state.data;
    if (!d) return;
    $('day-label').textContent = dayLabel(state.day);
    renderTasks(d.tasks || []);
    renderSchedule(d.schedule || []);
    renderGoals(d.goals || []);
  }

  // ── Формы ─────────────────────────────────────────────────────────────────

  function bindForms() {
    $('auth-form').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var t = $('token-input').value.trim();
      if (t) enter(t);
    });
    $('logout').addEventListener('click', function () { showAuth('', true); });
    $('prev').addEventListener('click', function () { goDay(shiftDay(state.day, -1)); });
    $('next').addEventListener('click', function () { goDay(shiftDay(state.day, 1)); });
    $('today').addEventListener('click', function () { goDay(ymd(new Date())); });

    $('task-form').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var f = ev.currentTarget;
      run(api('POST', '/v1/tasks', pick({
        title: $('task-title').value.trim(),
        date: state.day,
        start: $('task-start').value,
        end: $('task-end').value,
        priority: $('task-priority').value
      }))).then(function (ok) { if (ok) f.reset(); });
    });

    $('sched-form').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var f = ev.currentTarget;
      run(api('POST', '/v1/schedule', pick({
        title: $('sched-title').value.trim(),
        date: state.day,
        start: $('sched-start').value,
        end: $('sched-end').value,
        location: $('sched-location').value.trim()
      }))).then(function (ok) { if (ok) f.reset(); });
    });

    $('goal-form').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var f = ev.currentTarget;
      var target = $('goal-target').value;
      run(api('POST', '/v1/goals', pick({
        title: $('goal-title').value.trim(),
        period: $('goal-period').value,
        date: state.day,
        targetCount: target ? Number(target) : ''
      }))).then(function (ok) { if (ok) f.reset(); });
    });
  }

  function init() {
    fillOptions($('task-priority'), PRIORITY, 'none');
    fillOptions($('goal-period'), PERIODS, 'month');
    bindForms();
    state.day = ymd(new Date());
    var saved = '';
    try { saved = localStorage.getItem(TOKEN_KEY) || ''; } catch (e) {}
    if (saved) enter(saved);
    else showAuth('', false);
  }

  init();
})();
</script>
</body>
</html>''';
