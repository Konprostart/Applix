// Applix UI Kit - shared, dependency-free components for generated apps.
//
// Ships in every built app next to index.html, so single-file and multi-file
// projects use the same widgets:
//
//   <script type="module">
//     import { toast, openSheet, confirmDialog, mountTabs, mountBottomNav,
//              mountSegmented, stagger } from './applix-ui.js';
//   </script>
//
// The styles live in applix-ui.css (already inlined by the shell). These
// helpers only build markup with .ax-* classes, so app CSS can still override
// everything. No bridge calls: the kit works before the native bridge is ready.

export const UI_KIT_VERSION = 2;

const el = (tag, className = '', text = '') => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
};

const button = (className, label) => {
  const b = el('button', className, label);
  b.type = 'button';
  return b;
};

/** Transient message at the bottom of the screen. `tone`: 'error' | 'success'. */
export function toast(message, { duration = 2200, action, tone } = {}) {
  const node = el('div', 'ax-toast ax-toast--js' + (tone ? ' ax-toast--' + tone : ''));
  node.setAttribute('role', 'status');
  node.appendChild(el('span', 'ax-toast__msg', message));
  if (action && action.label) {
    const act = button('ax-toast__action', action.label);
    act.addEventListener('click', () => {
      action.onClick?.();
      close();
    });
    node.appendChild(act);
  }
  document.body.appendChild(node);
  requestAnimationFrame(() => node.classList.add('ax-toast--show'));

  let closed = false;
  const timer = setTimeout(close, Math.max(800, duration));
  function close() {
    if (closed) return;
    closed = true;
    clearTimeout(timer);
    node.classList.remove('ax-toast--show');
    setTimeout(() => node.remove(), 240);
  }
  return { close };
}

/** Error message for failed actions. Never leave a failure silent. */
export function showError(message, { duration = 3800, action } = {}) {
  return toast(String(message || 'Something went wrong.'), { duration, action, tone: 'error' });
}

/**
 * Bottom sheet used for dialogs, pickers and details.
 * Returns { close, sheet }. `onClose` fires exactly once, also on backdrop
 * tap or Escape.
 */
export function openSheet({ title, content, actions = [], dismissible = true, onClose } = {}) {
  const backdrop = el('div', 'ax-sheet-backdrop ax-sheet-backdrop--js');
  const sheet = el('div', 'ax-sheet');
  sheet.setAttribute('role', 'dialog');
  sheet.setAttribute('aria-modal', 'true');
  sheet.appendChild(el('div', 'ax-sheet__handle'));
  if (title) {
    const heading = el('div', 'ax-sheet__title', title);
    sheet.appendChild(heading);
  }
  const body = el('div', 'ax-sheet__body');
  if (typeof content === 'string') body.textContent = content;
  else if (content) body.appendChild(content);
  sheet.appendChild(body);

  if (actions.length) {
    const row = el('div', 'ax-sheet__actions');
    for (const a of actions) {
      const kind = a.kind === 'ghost' ? ' ax-btn--ghost'
        : a.kind === 'danger' ? ' ax-btn--danger'
        : a.kind === 'secondary' ? ' ax-btn--secondary' : '';
      const b = button(`ax-btn ax-btn--block${kind}`, a.label || 'OK');
      b.addEventListener('click', () => {
        a.onClick?.();
        if (a.close !== false) close();
      });
      row.appendChild(b);
    }
    sheet.appendChild(row);
  }

  backdrop.appendChild(sheet);
  document.body.appendChild(backdrop);
  requestAnimationFrame(() => backdrop.classList.add('ax-sheet-backdrop--show'));

  let closed = false;
  function close() {
    if (closed) return;
    closed = true;
    document.removeEventListener('keydown', onKey);
    backdrop.classList.remove('ax-sheet-backdrop--show');
    setTimeout(() => backdrop.remove(), 240);
    onClose?.();
  }
  function onKey(event) {
    if (event.key === 'Escape' && dismissible) close();
  }
  if (dismissible) {
    backdrop.addEventListener('click', (event) => {
      if (event.target === backdrop) close();
    });
    document.addEventListener('keydown', onKey);
  }
  return { close, sheet };
}

/** Promise<boolean> confirmation built on the sheet. */
export function confirmDialog({
  title = 'Are you sure?',
  message = '',
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  danger = false,
} = {}) {
  return new Promise((resolve) => {
    let settled = false;
    const settle = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    openSheet({
      title,
      content: message,
      onClose: () => settle(false),
      actions: [
        { label: cancelLabel, kind: 'ghost', onClick: () => settle(false) },
        {
          label: confirmLabel,
          kind: danger ? 'danger' : 'primary',
          onClick: () => settle(true),
        },
      ],
    });
  });
}

/** Animated top tab bar. tabs: [{id, label}] */
export function mountTabs(container, { tabs = [], active = 0, onChange } = {}) {
  container.textContent = '';
  const bar = el('div', 'ax-tabs');
  bar.setAttribute('role', 'tablist');
  let current = active;
  const buttons = [];
  tabs.forEach((tab, index) => {
    const b = button('ax-tab', tab.label || tab.id || `Tab ${index + 1}`);
    b.setAttribute('role', 'tab');
    b.dataset.id = tab.id ?? String(index);
    b.addEventListener('click', () => select(index, true));
    bar.appendChild(b);
    buttons.push(b);
  });
  container.appendChild(bar);

  function select(index, notify) {
    current = index;
    buttons.forEach((b, i) => {
      const on = i === index;
      b.classList.toggle('ax-tab--active', on);
      b.setAttribute('aria-selected', String(on));
    });
    if (notify) onChange?.(tabs[index], index);
  }
  select(Math.max(0, Math.min(active, tabs.length - 1)), false);
  return { setActive: (index) => select(index, false), get active() { return current; } };
}

/** Fixed bottom navigation. items: [{id, label, icon}] (icon is a short text/emoji). */
export function mountBottomNav(container, { items = [], active = 0, onChange } = {}) {
  container.textContent = '';
  const nav = el('nav', 'ax-bottom-nav');
  let current = active;
  const buttons = [];
  items.forEach((item, index) => {
    const b = button('ax-bottom-nav__item');
    b.dataset.id = item.id ?? String(index);
    if (item.icon) b.appendChild(el('span', 'ax-bottom-nav__icon', item.icon));
    b.appendChild(el('span', 'ax-bottom-nav__label', item.label || item.id || ''));
    b.addEventListener('click', () => select(index, true));
    nav.appendChild(b);
    buttons.push(b);
  });
  container.appendChild(nav);

  function select(index, notify) {
    current = index;
    buttons.forEach((b, i) => {
      const on = i === index;
      b.classList.toggle('ax-bottom-nav__item--active', on);
      if (on) b.setAttribute('aria-current', 'page');
      else b.removeAttribute('aria-current');
    });
    if (notify) onChange?.(items[index], index);
  }
  select(Math.max(0, Math.min(active, items.length - 1)), false);
  return { setActive: (index) => select(index, false), get active() { return current; } };
}

/** iOS-style segmented control. options: [{id, label}] or string[]. */
export function mountSegmented(container, { options = [], active = 0, onChange } = {}) {
  container.textContent = '';
  const wrap = el('div', 'ax-segmented');
  const normalized = options.map((option, index) =>
    typeof option === 'string' ? { id: String(index), label: option } : option);
  let current = active;
  const buttons = [];
  normalized.forEach((option, index) => {
    const b = button('ax-segmented__item', option.label || option.id || '');
    b.addEventListener('click', () => select(index, true));
    wrap.appendChild(b);
    buttons.push(b);
  });
  container.appendChild(wrap);

  function select(index, notify) {
    current = index;
    buttons.forEach((b, i) => {
      const on = i === index;
      b.classList.toggle('ax-segmented__item--active', on);
      b.setAttribute('aria-checked', String(on));
    });
    if (notify) onChange?.(normalized[index], index);
  }
  select(Math.max(0, Math.min(active, normalized.length - 1)), false);
  return { setActive: (index) => select(index, false), get active() { return current; } };
}

/** Staggers the entrance animation of a list of elements. */
export function stagger(selector, root = document) {
  const nodes = typeof selector === 'string'
    ? Array.from(root.querySelectorAll(selector))
    : Array.from(selector);
  const step = 45;
  nodes.forEach((node, index) => {
    node.classList.add('ax-anim-in');
    node.style.animationDelay = `${Math.min(index * step, 360)}ms`;
  });
  return nodes;
}

const SVG_NS = 'http://www.w3.org/2000/svg';

const ICONS = {
  home: 'M3 10.5 12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z',
  list: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
  chart: 'M4 20V10M10 20V4M16 20v-6M2 20h20',
  plus: 'M12 5v14M5 12h14',
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.35-4.35',
  check: 'M20 6 9 17l-5-5',
  trash: 'M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6',
  back: 'M19 12H5M12 19l-7-7 7-7',
  chevron: 'm9 18 6-6-6-6',
  clock: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 6v6l4 2',
  calendar: 'M3 5h18v16H3zM8 3v4M16 3v4M3 10h18',
  bell: 'M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0',
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0',
  wallet: 'M3 7h18v13H3zM3 7l2-4h14l2 4M16 13h2',
  heart: 'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8z',
  close: 'M18 6 6 18M6 6l12 12',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
};

function svgEl(tag, attrs = {}) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value));
  return node;
}

/** Inline SVG icon (stroke style, currentColor). name: see ICONS. */
export function icon(name, { size = 22, className = 'ax-icon' } = {}) {
  const svg = svgEl('svg', {
    class: className,
    viewBox: '0 0 24 24',
    width: size,
    height: size,
    'aria-hidden': 'true',
    focusable: 'false',
  });
  const path = svgEl('path', { d: ICONS[name] || ICONS.chevron });
  svg.appendChild(path);
  return svg;
}

/** Replaces <span data-ax-icon="home"></span> with inline SVG icons. */
export function mountIcons(root = document) {
  const nodes = Array.from(root.querySelectorAll('[data-ax-icon]'));
  nodes.forEach((node) => {
    const svg = icon(node.dataset.axIcon, {
      size: Number(node.dataset.axSize) || 22,
      className: node.className ? `ax-icon ${node.className}` : 'ax-icon',
    });
    node.replaceWith(svg);
  });
  return nodes.length;
}

function numeric(values) {
  return (Array.isArray(values) ? values : []).map(Number).filter(Number.isFinite);
}

/** SVG sparkline for a series of numbers. */
export function sparkline(values, { width = 280, height = 64, stroke = 'var(--ax-primary)', fill = true } = {}) {
  const nums = numeric(values);
  const svg = svgEl('svg', {
    class: 'ax-sparkline',
    viewBox: `0 0 ${width} ${height}`,
    width,
    height,
    preserveAspectRatio: 'none',
    'aria-hidden': 'true',
  });
  if (nums.length < 2) return svg;
  const min = Math.min(...nums);
  const max = Math.max(...nums);
  const span = max - min || 1;
  const step = width / (nums.length - 1);
  const points = nums.map((value, index) => {
    const x = index * step;
    const y = height - ((value - min) / span) * (height - 10) - 5;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  });
  if (fill) {
    svg.appendChild(svgEl('polygon', {
      points: `0,${height} ${points.join(' ')} ${width},${height}`,
      fill: 'currentColor',
      opacity: '0.12',
      stroke: 'none',
    }));
  }
  svg.appendChild(svgEl('polyline', {
    points: points.join(' '),
    fill: 'none',
    stroke,
    'stroke-width': '2.5',
    'stroke-linecap': 'round',
    'stroke-linejoin': 'round',
  }));
  return svg;
}

/** Simple bar chart. values: numbers; labels: optional strings. */
export function barChart(values, { labels = [], height = 120, format } = {}) {
  const nums = numeric(values);
  const wrap = el('div', 'ax-chart');
  const bars = el('div', 'ax-chart__bars');
  bars.style.height = `${height}px`;
  const max = Math.max(...nums, 1);
  nums.forEach((value, index) => {
    const bar = el('div', 'ax-bar');
    const pct = Math.max(2, Math.round((value / max) * 100));
    bar.style.height = `${pct}%`;
    const shown = format ? format(value) : String(value);
    bar.title = labels[index] ? `${labels[index]}: ${shown}` : shown;
    if (labels[index]) bar.setAttribute('aria-label', bar.title);
    bars.appendChild(bar);
  });
  wrap.appendChild(bars);
  if (labels.length) {
    const row = el('div', 'ax-chart__labels');
    labels.forEach((label) => row.appendChild(el('span', 'ax-chart__label', label)));
    wrap.appendChild(row);
  }
  return wrap;
}

/** Donut progress 0..100 with a centered label. */
export function donut(value, { size = 96, strokeWidth = 10, label = '', tone = 'var(--ax-primary)' } = {}) {
  const pct = Math.max(0, Math.min(100, Number(value) || 0));
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const svg = svgEl('svg', {
    class: 'ax-donut',
    viewBox: `0 0 ${size} ${size}`,
    width: size,
    height: size,
    role: 'img',
    'aria-label': label || `${Math.round(pct)}%`,
  });
  svg.appendChild(svgEl('circle', {
    cx: size / 2, cy: size / 2, r: radius,
    fill: 'none', stroke: 'var(--ax-border)', 'stroke-width': strokeWidth,
  }));
  svg.appendChild(svgEl('circle', {
    cx: size / 2, cy: size / 2, r: radius,
    fill: 'none', stroke: tone, 'stroke-width': strokeWidth,
    'stroke-linecap': 'round',
    'stroke-dasharray': `${(circumference * pct) / 100} ${circumference}`,
    transform: `rotate(-90 ${size / 2} ${size / 2})`,
  }));
  if (label) {
    const text = svgEl('text', {
      x: '50%', y: '50%', 'text-anchor': 'middle', 'dominant-baseline': 'central',
      fill: 'var(--ax-text)', 'font-size': size * 0.2, 'font-weight': '700',
    });
    text.textContent = label;
    svg.appendChild(text);
  }
  return svg;
}

export default {
  version: UI_KIT_VERSION,
  toast,
  showError,
  openSheet,
  confirmDialog,
  mountTabs,
  mountBottomNav,
  mountSegmented,
  stagger,
  icon,
  mountIcons,
  sparkline,
  barChart,
  donut,
};
