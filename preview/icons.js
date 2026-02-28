// preview/icons.js — Monochrome SF Symbol approximations as inline SVGs
// All icons use viewBox="0 0 24 24" and currentColor for theming.

(function() {
  'use strict';

  // Each icon is the innerHTML of an <svg viewBox="0 0 24 24"> element.
  // Icons use fill="currentColor" and/or stroke="currentColor" as appropriate.
  var icons = {

    // ── Settings Tab Icons ──────────────────────────────────

    'gear': '<path fill="currentColor" d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 00.12-.61l-1.92-3.32a.49.49 0 00-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54A.48.48 0 0013.92 2h-3.84c-.24 0-.44.17-.48.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.72 8.47c-.12.2-.07.47.12.61l2.03 1.58c-.05.3-.07.62-.07.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.48-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>',

    'gearshape': '<path fill="currentColor" d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 00.12-.61l-1.92-3.32a.49.49 0 00-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54A.48.48 0 0013.92 2h-3.84c-.24 0-.44.17-.48.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.72 8.47c-.12.2-.07.47.12.61l2.03 1.58c-.05.3-.07.62-.07.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.48-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>',

    'mic.fill': '<path fill="currentColor" d="M12 2a3 3 0 00-3 3v6a3 3 0 006 0V5a3 3 0 00-3-3zm7 9a1 1 0 10-2 0 5 5 0 01-10 0 1 1 0 10-2 0 7 7 0 006 6.92V20H8.5a1 1 0 100 2h7a1 1 0 100-2H13v-2.08A7 7 0 0019 11z"/>',

    'mic.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><path fill="currentColor" d="M12 7a2 2 0 00-2 2v3a2 2 0 004 0V9a2 2 0 00-2-2zm3.5 5a3.5 3.5 0 01-7 0H7.25a4.75 4.75 0 004.25 4.72V18h1v-1.28A4.75 4.75 0 0016.75 12H15.5z"/>',

    'mic.circle.fill': '<circle cx="12" cy="12" r="11" fill="currentColor"/><path fill="var(--color-bg, #1e1e1e)" d="M12 7a2 2 0 00-2 2v3a2 2 0 004 0V9a2 2 0 00-2-2zm3.5 5a3.5 3.5 0 01-7 0H7.25a4.75 4.75 0 004.25 4.72V18h1v-1.28A4.75 4.75 0 0016.75 12H15.5z"/>',

    'text.book.closed': '<path fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="M4 19.5A2.5 2.5 0 016.5 17H20M4 4.5A2.5 2.5 0 016.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15z"/><line x1="8" y1="6" x2="16" y2="6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="10" x2="13" y2="10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'cpu': '<rect x="4" y="4" width="16" height="16" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="9" y="9" width="6" height="6" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="9" y1="1" x2="9" y2="4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="15" y1="1" x2="15" y2="4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="9" y1="20" x2="9" y2="23" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="15" y1="20" x2="15" y2="23" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="1" y1="9" x2="4" y2="9" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="1" y1="15" x2="4" y2="15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="20" y1="9" x2="23" y2="9" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="20" y1="15" x2="23" y2="15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'lock.shield': '<path fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="M12 2L3 7v5c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-9-5z"/><rect x="9" y="10" width="6" height="5" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M10 10V8a2 2 0 014 0v2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'lock.shield.fill': '<path fill="currentColor" d="M12 1L2 6.5v5.5c0 6.08 4.22 11.78 10 13 5.78-1.22 10-6.92 10-13V6.5L12 1zm3 13a1 1 0 01-1 1h-4a1 1 0 01-1-1v-3a1 1 0 011-1v-1a2 2 0 114 0v1a1 1 0 011 1v3z"/><path fill="var(--color-bg, #1e1e1e)" d="M10.5 10v-1a1.5 1.5 0 013 0v1h-3z"/>',

    'ant.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><ellipse cx="12" cy="13.5" rx="3" ry="2.5" fill="none" stroke="currentColor" stroke-width="1.2"/><circle cx="12" cy="9.5" r="1.8" fill="none" stroke="currentColor" stroke-width="1.2"/><line x1="9.5" y1="12" x2="7" y2="10" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><line x1="14.5" y1="12" x2="17" y2="10" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><line x1="9.5" y1="14" x2="7" y2="15.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><line x1="14.5" y1="14" x2="17" y2="15.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><line x1="10.5" y1="8" x2="9" y2="6" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><line x1="13.5" y1="8" x2="15" y2="6" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>',

    'info.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="12" y1="16" x2="12" y2="12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="12" cy="8" r="0.5" fill="currentColor" stroke="currentColor" stroke-width="1"/>',

    // ── Meeting Type Icons ──────────────────────────────────

    'figure.stand': '<circle cx="12" cy="4" r="2" fill="currentColor"/><path fill="currentColor" d="M15 22h-2v-7h-2v7H9v-9H7v-4a2 2 0 012-2h6a2 2 0 012 2v4h-2v9z"/>',

    'person.2': '<circle cx="9" cy="5" r="2.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M3 20c0-3.31 2.69-6 6-6h0c3.31 0 6 2.69 6 6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="17" cy="7" r="2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M21 20c0-2.76-2.24-5-5-5-.97 0-1.88.28-2.65.76" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'person.2.fill': '<circle cx="9" cy="5" r="2.5" fill="currentColor"/><path fill="currentColor" d="M3 20.5c0-3.59 2.91-6.5 6-6.5s6 2.91 6 6.5H3z"/><circle cx="17" cy="7" r="2" fill="currentColor"/><path fill="currentColor" d="M14.2 14.55A5.4 5.4 0 0117 14c2.76 0 5 2.24 5 5v1.5h-6.5c-.27-2.4-1.35-4.56-1.3-5.95z"/>',

    'person.3': '<circle cx="12" cy="4" r="2.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M6 20c0-3.31 2.69-6 6-6s6 2.69 6 6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="5" cy="7" r="1.8" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M1 19c0-2.21 1.79-4 4-4 .9 0 1.73.3 2.4.8" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/><circle cx="19" cy="7" r="1.8" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M23 19c0-2.21-1.79-4-4-4-.9 0-1.73.3-2.4.8" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>',

    'phone': '<path fill="currentColor" d="M6.62 10.79a15.91 15.91 0 006.59 6.59l2.2-2.2a1 1 0 011.01-.24c1.12.37 2.33.57 3.58.57a1 1 0 011 1V20a1 1 0 01-1 1A17 17 0 013 4a1 1 0 011-1h3.5a1 1 0 011 1c0 1.25.2 2.46.57 3.58a1 1 0 01-.25 1.01l-2.2 2.2z"/>',

    'play.rectangle': '<rect x="2" y="4" width="20" height="16" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><polygon points="10,8 16,12 10,16" fill="currentColor"/>',

    'doc.text': '<path fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6z"/><polyline points="14,2 14,8 20,8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><line x1="8" y1="13" x2="16" y2="13" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="17" x2="14" y2="17" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'slider.horizontal.3': '<line x1="4" y1="6" x2="20" y2="6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="4" y1="12" x2="20" y2="12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="4" y1="18" x2="20" y2="18" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><circle cx="8" cy="6" r="2" fill="var(--color-bg, #1e1e1e)" stroke="currentColor" stroke-width="1.5"/><circle cx="16" cy="12" r="2" fill="var(--color-bg, #1e1e1e)" stroke="currentColor" stroke-width="1.5"/><circle cx="10" cy="18" r="2" fill="var(--color-bg, #1e1e1e)" stroke="currentColor" stroke-width="1.5"/>',

    // ── Menu Bar Icons ──────────────────────────────────────

    'keyboard': '<rect x="2" y="5" width="20" height="14" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="6" y1="9" x2="6" y2="9.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="10" y1="9" x2="10" y2="9.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="14" y1="9" x2="14" y2="9.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="18" y1="9" x2="18" y2="9.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="6" y1="13" x2="6" y2="13.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="18" y1="13" x2="18" y2="13.01" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="9" y1="16" x2="15" y2="16" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'arrow.down.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><polyline points="8,11 12,15 16,11" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><line x1="12" y1="7" x2="12" y2="15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'arrow.circlepath': '<path d="M1 4v6h6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M3.51 15a9 9 0 105.64-11.36L1 10" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'power': '<path d="M18.36 6.64a9 9 0 11-12.73 0" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="12" y1="2" x2="12" y2="12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    // ── Onboarding Icons ────────────────────────────────────

    'bolt.fill': '<path fill="currentColor" d="M13 2L3 14h7l-1 8 10-12h-7l1-8z"/>',

    'lock.fill': '<path fill="currentColor" d="M18 10h-1V7A5 5 0 007 7v3H6a2 2 0 00-2 2v8a2 2 0 002 2h12a2 2 0 002-2v-8a2 2 0 00-2-2zM9 7a3 3 0 016 0v3H9V7z"/>',

    'waveform': '<line x1="4" y1="8" x2="4" y2="16" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="5" x2="8" y2="19" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="12" y1="2" x2="12" y2="22" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="16" y1="6" x2="16" y2="18" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="20" y1="9" x2="20" y2="15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'waveform.circle.fill': '<circle cx="12" cy="12" r="11" fill="currentColor"/><line x1="7" y1="10" x2="7" y2="14" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.3" stroke-linecap="round"/><line x1="9.5" y1="8" x2="9.5" y2="16" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.3" stroke-linecap="round"/><line x1="12" y1="6" x2="12" y2="18" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.3" stroke-linecap="round"/><line x1="14.5" y1="8.5" x2="14.5" y2="15.5" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.3" stroke-linecap="round"/><line x1="17" y1="10" x2="17" y2="14" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.3" stroke-linecap="round"/>',

    'brain.head.profile': '<path fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="M12 2C6.48 2 2 6.48 2 12c0 3.17 1.47 5.99 3.77 7.83A3.98 3.98 0 009 22h3v-2"/><path fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" d="M9 8c1.5-1 3-1 4.5 0M8 11c2-1.5 4-1.5 6 0M9 14c1.5 1 3 1 4.5 0"/><circle cx="17" cy="8" r="2.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M19.5 8c1 1 1.5 3 1.5 4 0 2-1 4-3 5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'accessibility': '<circle cx="12" cy="4" r="2" fill="currentColor"/><path d="M12 8c-3 0-6 .5-6 .5l.5 2s2-.5 4.5-.5v4l-2.5 7h2.5l2-5.5 2 5.5h2.5L15 14v-4c2.5 0 4.5.5 4.5.5l.5-2S15 8 12 8z" fill="currentColor"/>',

    'checkmark': '<polyline points="4,12 9,17 20,6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',

    'checkmark.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><polyline points="8,12.5 11,15.5 16.5,9" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'checkmark.circle.fill': '<circle cx="12" cy="12" r="11" fill="currentColor"/><polyline points="7.5,12 10.5,15.5 16.5,8.5" fill="none" stroke="var(--color-bg, #1e1e1e)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',

    'arrow.clockwise.circle.fill': '<circle cx="12" cy="12" r="11" fill="currentColor"/><path d="M16 8h-3.5" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.5" stroke-linecap="round"/><path d="M16 8v3.5" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.5" stroke-linecap="round"/><path d="M16 8c-1.5-1.5-3.5-2.5-5.5-2 -3 .7-5 3.5-4.4 6.5.6 3 3.4 5 6.4 4.5 2.5-.4 4.3-2.3 4.8-4.5" stroke="var(--color-bg, #1e1e1e)" stroke-width="1.5" stroke-linecap="round" fill="none"/>',

    // ── Analyze & Library Icons ─────────────────────────────

    'sparkles': '<path fill="currentColor" d="M10 2l1.5 4.5L16 8l-4.5 1.5L10 14l-1.5-4.5L4 8l4.5-1.5L10 2zM18 10l1 3 3 1-3 1-1 3-1-3-3-1 3-1 1-3zM7 16l.75 2.25L10 19l-2.25.75L7 22l-.75-2.25L4 19l2.25-.75L7 16z"/>',

    'doc.text.magnifyingglass': '<path fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6z"/><polyline points="14,2 14,8 20,8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="11.5" cy="14.5" r="2.5" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="13.3" y1="16.3" x2="15" y2="18" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'tray': '<path d="M2 17v3a2 2 0 002 2h16a2 2 0 002-2v-3M2 17l3-7h14l3 7" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'tray.full': '<path d="M2 17v3a2 2 0 002 2h16a2 2 0 002-2v-3M2 17l3-7h14l3 7" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><line x1="7" y1="7" x2="17" y2="7" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="4" x2="16" y2="4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'trash': '<polyline points="3,6 5,6 21,6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'pencil.line': '<path d="M17 3a2.83 2.83 0 114 4L7.5 20.5 2 22l1.5-5.5L17 3z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'books.vertical': '<rect x="3" y="2" width="5" height="20" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="10" y="4" width="4.5" height="18" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="16.5" y="6" width="4.5" height="16" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/>',

    'square.and.arrow.down': '<path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><polyline points="7,10 12,15 17,10" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><line x1="12" y1="15" x2="12" y2="3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'magnifyingglass': '<circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="16.5" y1="16.5" x2="21" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    // ── Utility Icons ───────────────────────────────────────

    'chevron.down': '<polyline points="6,9 12,15 18,9" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'chevron.right': '<polyline points="9,6 15,12 9,18" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'plus': '<line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'xmark': '<line x1="18" y1="6" x2="6" y2="18" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="6" y1="6" x2="18" y2="18" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'xmark.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="15" y1="9" x2="9" y2="15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="9" y1="9" x2="15" y2="15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'doc.on.clipboard': '<rect x="8" y="2" width="8" height="4" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="4" y="4" width="16" height="18" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="8" y1="12" x2="16" y2="12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="16" x2="13" y2="16" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'square.and.arrow.up': '<path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><polyline points="17,8 12,3 7,8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><line x1="12" y1="3" x2="12" y2="15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',

    'stop.fill': '<rect x="5" y="5" width="14" height="14" rx="2" fill="currentColor"/>',

    'record.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="12" cy="12" r="5" fill="currentColor"/>',

    'arrow.clockwise': '<path d="M1 4v6h6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M3.51 15a9 9 0 105.64-11.36L1 10" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',

    'ellipsis.circle': '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="16" cy="12" r="1" fill="currentColor"/>'
  };

  /**
   * Render an SF Symbol-like SVG icon.
   * @param {string} name - Icon name (e.g. 'gear', 'mic.fill')
   * @param {number} [size=16] - Icon size in pixels
   * @param {string} [extraStyle] - Additional inline CSS
   * @returns {string} HTML string with <span class="sf-icon"><svg>...</svg></span>
   */
  window.sfIcon = function(name, size, extraStyle) {
    size = size || 16;
    var svg = icons[name];
    if (!svg) return '<span class="sf-icon" style="width:'+size+'px;height:'+size+'px;display:inline-flex"></span>';
    var style = 'width:'+size+'px;height:'+size+'px';
    if (extraStyle) style += ';' + extraStyle;
    return '<span class="sf-icon" style="'+style+'">' +
      '<svg viewBox="0 0 24 24" width="'+size+'" height="'+size+'">' + svg + '</svg></span>';
  };

  /**
   * Auto-replace elements with data-icon attribute.
   * Usage: <span data-icon="gear" data-size="18" data-icon-style="color:red"></span>
   */
  window.initIcons = function() {
    var els = document.querySelectorAll('[data-icon]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var name = el.getAttribute('data-icon');
      var size = parseInt(el.getAttribute('data-size')) || 16;
      var style = el.getAttribute('data-icon-style') || '';
      el.innerHTML = sfIcon(name, size, style);
    }
  };

  // Auto-init on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initIcons);
  } else {
    setTimeout(initIcons, 0);
  }

})();
