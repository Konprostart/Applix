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

export const UI_KIT_VERSION = 1;

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

/** Transient message at the bottom of the screen. */
export function toast(message, { duration = 2200, action } = {}) {
  const node = el('div', 'ax-toast ax-toast--js');
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

export default {
  version: UI_KIT_VERSION,
  toast,
  openSheet,
  confirmDialog,
  mountTabs,
  mountBottomNav,
  mountSegmented,
  stagger,
};
