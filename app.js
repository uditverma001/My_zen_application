'use strict';

/* ---------- Storage (device-only, no network) ---------- */

const STORE_KEY = 'zen.v1';

function loadData() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    const data = raw ? JSON.parse(raw) : {};
    return {
      sessions: Array.isArray(data.sessions) ? data.sessions : [],
      journal: Array.isArray(data.journal) ? data.journal : [],
      prefs: data.prefs && typeof data.prefs === 'object' ? data.prefs : {},
    };
  } catch {
    return { sessions: [], journal: [], prefs: {} };
  }
}

const data = loadData();

function save() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(data));
  } catch {
    toast('Could not save on this device');
  }
}

function logSession(type, seconds) {
  data.sessions.push({ type, seconds: Math.round(seconds), at: Date.now() });
  save();
  renderToday();
}

/* ---------- Helpers ---------- */

const $ = (sel) => document.querySelector(sel);

function dayKey(date) {
  const d = new Date(date);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

function fmtTime(totalSeconds) {
  const s = Math.max(0, Math.ceil(totalSeconds));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

let toastTimer;
function toast(message) {
  const el = $('#toast');
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2400);
}

function buildRadioGroup(container, items, selected, onSelect, className = 'chip') {
  container.innerHTML = '';
  for (const item of items) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = className;
    btn.setAttribute('role', 'radio');
    btn.dataset.value = item.value;
    btn.setAttribute('aria-checked', String(item.value === selected));
    if (item.html) btn.innerHTML = item.html; else btn.textContent = item.label;
    btn.addEventListener('click', () => {
      for (const b of container.children) b.setAttribute('aria-checked', String(b === btn));
      onSelect(item.value);
    });
    container.appendChild(btn);
  }
}

/* ---------- Sound (generated with Web Audio, so no files to download) ---------- */

let audioCtx;
function audio() {
  if (!audioCtx) {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return null;
    audioCtx = new Ctx();
  }
  if (audioCtx.state === 'suspended') audioCtx.resume();
  return audioCtx;
}

function bell(volume = 0.35) {
  const ctx = audio();
  if (!ctx) return;
  const now = ctx.currentTime;
  // A singing-bowl-like tone: a few inharmonic partials with long decays.
  const partials = [[220, 1, 6], [528, 0.5, 4.5], [880, 0.25, 3], [1320, 0.12, 2]];
  for (const [freq, gain, decay] of partials) {
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    g.gain.setValueAtTime(0.0001, now);
    g.gain.exponentialRampToValueAtTime(volume * gain, now + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, now + decay);
    osc.connect(g).connect(ctx.destination);
    osc.start(now);
    osc.stop(now + decay + 0.1);
  }
}

let ambient;
function startAmbient() {
  const ctx = audio();
  if (!ctx || ambient) return;
  // Brown noise, low-passed: sounds like distant wind or surf.
  const length = ctx.sampleRate * 4;
  const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
  const ch = buffer.getChannelData(0);
  let last = 0;
  for (let i = 0; i < length; i++) {
    last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02;
    ch[i] = last * 3.5;
  }
  const src = ctx.createBufferSource();
  src.buffer = buffer;
  src.loop = true;
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = 600;
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.0001, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.25, ctx.currentTime + 3);
  src.connect(filter).connect(gain).connect(ctx.destination);
  src.start();
  ambient = { src, gain };
}

function stopAmbient() {
  if (!ambient || !audioCtx) return;
  const { src, gain } = ambient;
  const t = audioCtx.currentTime;
  gain.gain.cancelScheduledValues(t);
  gain.gain.setValueAtTime(gain.gain.value, t);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + 1.5);
  src.stop(t + 1.6);
  ambient = null;
}

/* ---------- Keep screen awake during practice ---------- */

let wakeLock;
async function keepAwake(on) {
  try {
    if (on && 'wakeLock' in navigator) {
      wakeLock = await navigator.wakeLock.request('screen');
    } else if (!on && wakeLock) {
      await wakeLock.release();
      wakeLock = null;
    }
  } catch { /* not supported or denied; harmless */ }
}

/* ---------- Navigation ---------- */

function showView(name) {
  for (const v of document.querySelectorAll('.view')) v.classList.toggle('active', v.id === `view-${name}`);
  for (const t of document.querySelectorAll('.tab')) {
    const active = t.dataset.view === name;
    t.classList.toggle('active', active);
    if (active) t.setAttribute('aria-current', 'page'); else t.removeAttribute('aria-current');
  }
  window.scrollTo(0, 0);
}

for (const t of document.querySelectorAll('.tab')) t.addEventListener('click', () => showView(t.dataset.view));
for (const b of document.querySelectorAll('[data-goto]')) b.addEventListener('click', () => showView(b.dataset.goto));

/* ---------- Today ---------- */

const QUOTES = [
  ['Before enlightenment, chop wood, carry water.\nAfter enlightenment, chop wood, carry water.', 'Zen proverb'],
  ['Nature does not hurry, yet everything is accomplished.', 'Lao Tzu'],
  ['The obstacle is the path.', 'Zen proverb'],
  ['An old pond.\nA frog jumps in.\nThe sound of water.', 'Matsuo Bashō'],
  ['When walking, walk. When eating, eat.', 'Zen proverb'],
  ['Muddy water is best cleared by leaving it alone.', 'Zen saying'],
  ['A journey of a thousand miles begins beneath one’s feet.', 'Lao Tzu'],
  ['Sitting quietly, doing nothing,\nspring comes, and the grass grows by itself.', 'Zen saying'],
  ['If you are calm, the whole world is calm.', ''],
  ['Let the breath be the anchor. Let thoughts be the weather.', ''],
  ['Fall seven times, stand up eight.', 'Japanese proverb'],
  ['Knowing others is intelligence; knowing yourself is true wisdom.', 'Lao Tzu'],
  ['No snowflake ever falls in the wrong place.', 'Zen saying'],
  ['You do not need to finish anything right now. Just this breath.', ''],
  ['The quieter you become, the more you can hear.', ''],
];

function renderToday() {
  const now = new Date();
  $('#today-date').textContent = now.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
  const hour = now.getHours();
  $('#today-title').textContent = hour < 5 ? 'A quiet night' : hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';

  // Same quote all day, a new one each day.
  const dayIndex = Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000);
  const [text, author] = QUOTES[dayIndex % QUOTES.length];
  $('#quote-text').textContent = text;
  $('#quote-author').textContent = author;

  const totalSeconds = data.sessions.reduce((sum, s) => sum + s.seconds, 0);
  $('#stat-minutes').textContent = Math.floor(totalSeconds / 60);
  $('#stat-sessions').textContent = data.sessions.length;
  $('#stat-streak').textContent = streak();

  const practiced = new Set(data.sessions.map((s) => dayKey(s.at)));
  const week = $('#week');
  week.innerHTML = '';
  for (let i = 6; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
    const el = document.createElement('div');
    el.className = 'day';
    if (practiced.has(dayKey(d))) el.classList.add('done');
    if (i === 0) el.classList.add('today');
    el.innerHTML = '<div class="day-dot"></div><span></span>';
    el.querySelector('span').textContent = d.toLocaleDateString(undefined, { weekday: 'narrow' });
    el.title = d.toLocaleDateString();
    week.appendChild(el);
  }
}

function streak() {
  const practiced = new Set(data.sessions.map((s) => dayKey(s.at)));
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  // Today not done yet doesn't break the streak.
  if (!practiced.has(dayKey(d))) d.setDate(d.getDate() - 1);
  let count = 0;
  while (practiced.has(dayKey(d))) {
    count++;
    d.setDate(d.getDate() - 1);
  }
  return count;
}

/* ---------- Breathe ---------- */

const PATTERNS = {
  calm: { label: 'Calm', desc: 'In for 4, out for 6. A longer exhale settles the nervous system.', steps: [['Breathe in', 4, 1], ['Breathe out', 6, 0.45]] },
  box: { label: 'Box', desc: 'In 4, hold 4, out 4, hold 4. Steady and focusing.', steps: [['Breathe in', 4, 1], ['Hold', 4, 1], ['Breathe out', 4, 0.45], ['Hold', 4, 0.45]] },
  relax: { label: '4-7-8', desc: 'In 4, hold 7, out 8. Helpful before sleep.', steps: [['Breathe in', 4, 1], ['Hold', 7, 1], ['Breathe out', 8, 0.45]] },
  even: { label: 'Balance', desc: 'In 5, out 5. Simple, even breathing.', steps: [['Breathe in', 5, 1], ['Breathe out', 5, 0.45]] },
};

const breath = {
  pattern: PATTERNS[data.prefs.breath] ? data.prefs.breath : 'calm',
  running: false,
  timer: null,
  startedAt: 0,
  cycles: 0,
};

function selectPattern(key) {
  breath.pattern = key;
  data.prefs.breath = key;
  save();
  $('#breath-desc').textContent = PATTERNS[key].desc;
}

buildRadioGroup(
  $('#breath-patterns'),
  Object.entries(PATTERNS).map(([value, p]) => ({ value, label: p.label })),
  breath.pattern,
  selectPattern,
);
$('#breath-desc').textContent = PATTERNS[breath.pattern].desc;

function runStep(index) {
  const steps = PATTERNS[breath.pattern].steps;
  if (index === 0 && breath.startedAt && Date.now() - breath.startedAt > 1000) {
    breath.cycles++;
    $('#breath-cycles').textContent = `${breath.cycles} ${breath.cycles === 1 ? 'cycle' : 'cycles'}`;
  }
  const [label, seconds, scale] = steps[index];
  const circle = $('#breath-circle');
  circle.style.transitionDuration = `${seconds}s`;
  circle.style.transform = `scale(${scale})`;
  $('#breath-phase').textContent = label;
  if ('vibrate' in navigator) navigator.vibrate(15);

  let left = seconds;
  $('#breath-count').textContent = left;
  breath.timer = setInterval(() => {
    left--;
    if (left > 0) {
      $('#breath-count').textContent = left;
    } else {
      clearInterval(breath.timer);
      if (breath.running) runStep((index + 1) % steps.length);
    }
  }, 1000);
}

function startBreath() {
  breath.running = true;
  breath.startedAt = Date.now();
  breath.cycles = 0;
  $('#breath-cycles').textContent = '';
  $('#breath-toggle').textContent = 'Finish';
  $('#breath-patterns').classList.add('locked');
  keepAwake(true);
  runStep(0);
}

function stopBreath() {
  breath.running = false;
  clearInterval(breath.timer);
  const seconds = (Date.now() - breath.startedAt) / 1000;
  const circle = $('#breath-circle');
  circle.style.transitionDuration = '1.5s';
  circle.style.transform = 'scale(.45)';
  $('#breath-phase').textContent = 'Ready';
  $('#breath-count').textContent = '';
  $('#breath-toggle').textContent = 'Begin';
  $('#breath-patterns').classList.remove('locked');
  keepAwake(false);
  if (seconds >= 30) {
    logSession('breathe', seconds);
    toast(`Nicely done: ${Math.round(seconds / 60) || '<1'} min of breathing`);
  }
}

$('#breath-toggle').addEventListener('click', () => (breath.running ? stopBreath() : startBreath()));

/* ---------- Meditate ---------- */

const DURATIONS = [1, 3, 5, 10, 15, 20, 30];
const CIRCUMFERENCE = 2 * Math.PI * 90;

const med = {
  minutes: DURATIONS.includes(data.prefs.minutes) ? data.prefs.minutes : 5,
  running: false,
  paused: false,
  endAt: 0,
  remaining: 0,
  tick: null,
  lastBellMinute: 0,
};

$('#opt-ambient').checked = !!data.prefs.ambient;
$('#opt-interval').checked = !!data.prefs.interval;
$('#opt-ambient').addEventListener('change', (e) => {
  data.prefs.ambient = e.target.checked;
  save();
  if (med.running && !med.paused) (e.target.checked ? startAmbient : stopAmbient)();
});
$('#opt-interval').addEventListener('change', (e) => {
  data.prefs.interval = e.target.checked;
  save();
});

buildRadioGroup(
  $('#durations'),
  DURATIONS.map((m) => ({ value: m, label: `${m} min` })),
  med.minutes,
  (m) => {
    med.minutes = m;
    data.prefs.minutes = m;
    save();
    resetTimerDisplay();
  },
);

function drawTimer(remaining) {
  const total = med.minutes * 60;
  $('#timer-text').textContent = fmtTime(remaining);
  $('#timer-progress').style.strokeDashoffset = String(CIRCUMFERENCE * (1 - remaining / total));
}

function resetTimerDisplay() {
  const ring = $('#timer-progress');
  ring.style.transition = 'none';
  drawTimer(med.minutes * 60);
  ring.getBoundingClientRect();
  ring.style.transition = '';
}

function onTick() {
  const remaining = (med.endAt - Date.now()) / 1000;
  if (remaining <= 0) return finishMeditation(true);
  drawTimer(remaining);
  const elapsedMin = Math.floor((med.minutes * 60 - remaining) / 60);
  if ($('#opt-interval').checked && elapsedMin > med.lastBellMinute) {
    med.lastBellMinute = elapsedMin;
    bell(0.15);
  }
}

function startMeditation() {
  audio(); // must be created inside a tap on iOS
  med.running = true;
  med.paused = false;
  med.remaining = med.minutes * 60;
  med.endAt = Date.now() + med.remaining * 1000;
  med.lastBellMinute = 0;
  bell();
  if ($('#opt-ambient').checked) startAmbient();
  med.tick = setInterval(onTick, 250);
  keepAwake(true);
  $('#timer-toggle').textContent = 'Pause';
  $('#timer-reset').hidden = false;
  $('#durations').classList.add('locked');
}

function pauseMeditation() {
  med.paused = true;
  med.remaining = (med.endAt - Date.now()) / 1000;
  clearInterval(med.tick);
  stopAmbient();
  keepAwake(false);
  $('#timer-toggle').textContent = 'Resume';
}

function resumeMeditation() {
  audio();
  med.paused = false;
  med.endAt = Date.now() + med.remaining * 1000;
  if ($('#opt-ambient').checked) startAmbient();
  med.tick = setInterval(onTick, 250);
  keepAwake(true);
  $('#timer-toggle').textContent = 'Pause';
}

function finishMeditation(completed) {
  const total = med.minutes * 60;
  const remaining = med.paused ? med.remaining : (med.endAt - Date.now()) / 1000;
  const elapsed = completed ? total : total - Math.max(0, remaining);
  clearInterval(med.tick);
  stopAmbient();
  keepAwake(false);
  med.running = false;
  med.paused = false;
  $('#timer-toggle').textContent = 'Begin';
  $('#timer-reset').hidden = true;
  $('#durations').classList.remove('locked');

  if (completed) {
    drawTimer(0);
    bell();
    setTimeout(() => bell(0.25), 2500);
    if ('vibrate' in navigator) navigator.vibrate([200, 100, 200]);
    toast(`${med.minutes} minute${med.minutes === 1 ? '' : 's'} of stillness. Well done.`);
    setTimeout(resetTimerDisplay, 3000);
  } else {
    resetTimerDisplay();
  }
  if (elapsed >= 60) logSession('meditate', elapsed);
}

$('#timer-toggle').addEventListener('click', () => {
  if (!med.running) startMeditation();
  else if (med.paused) resumeMeditation();
  else pauseMeditation();
});
$('#timer-reset').addEventListener('click', () => finishMeditation(false));

// Wake lock is dropped when the app is hidden; take it back on return.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') return;
  if ((med.running && !med.paused) || breath.running) keepAwake(true);
  if (med.running && !med.paused) onTick();
});

resetTimerDisplay();

/* ---------- Journal ---------- */

const MOODS = [
  { value: 1, glyph: '😞', label: 'Heavy' },
  { value: 2, glyph: '😕', label: 'Low' },
  { value: 3, glyph: '😐', label: 'Okay' },
  { value: 4, glyph: '🙂', label: 'Good' },
  { value: 5, glyph: '😊', label: 'Bright' },
];
let selectedMood = 3;

buildRadioGroup(
  $('#moods'),
  MOODS.map((m) => ({ value: m.value, html: `<b aria-hidden="true">${m.glyph}</b>${m.label}` })),
  selectedMood,
  (v) => { selectedMood = v; },
  'mood',
);

function renderJournal() {
  const list = $('#entries');
  list.innerHTML = '';
  const entries = [...data.journal].sort((a, b) => b.at - a.at);
  for (const entry of entries) {
    const mood = MOODS.find((m) => m.value === entry.mood) || MOODS[2];
    const li = document.createElement('li');
    li.className = 'entry';
    li.innerHTML = `
      <div class="entry-head">
        <span class="entry-meta"></span>
        <button class="entry-delete" type="button">Delete</button>
      </div>
      <p class="entry-text"></p>`;
    const when = new Date(entry.at).toLocaleString(undefined, { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    li.querySelector('.entry-meta').textContent = `${mood.glyph} ${mood.label} · ${when}`;
    const text = li.querySelector('.entry-text');
    if (entry.text) text.textContent = entry.text; else text.remove();
    li.querySelector('.entry-delete').addEventListener('click', () => {
      if (!confirm('Delete this entry?')) return;
      data.journal = data.journal.filter((e) => e.id !== entry.id);
      save();
      renderJournal();
    });
    list.appendChild(li);
  }
  $('#entries-empty').hidden = entries.length > 0;
}

$('#journal-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const text = $('#journal-text').value.trim();
  data.journal.push({ id: `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, mood: selectedMood, text, at: Date.now() });
  save();
  $('#journal-text').value = '';
  renderJournal();
  toast('Saved');
});

/* ---------- Start ---------- */

renderToday();
renderJournal();

if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  });
}
