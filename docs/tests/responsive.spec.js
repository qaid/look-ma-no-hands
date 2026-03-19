const { test, expect } = require('@playwright/test');
const AxeBuilder = require('@axe-core/playwright').default;

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  // Disable reveal animations so elements are immediately visible
  await page.addStyleTag({
    content: '.reveal { opacity: 1 !important; transform: none !important; transition: none !important; }',
  });
});

// --- Accessibility ---

test.describe('Accessibility', () => {
  // TODO: Fix aria-prohibited-attr violations in index.html, then remove .fixme
  test.fixme('no critical accessibility violations', async ({ page }) => {
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .disableRules(['color-contrast'])
      .analyze();

    const serious = results.violations.filter(
      (v) => v.impact === 'critical' || v.impact === 'serious'
    );
    expect(
      serious,
      `Violations:\n${serious.map((v) => `  - ${v.id}: ${v.description} (${v.nodes.length} nodes)`).join('\n')}`
    ).toHaveLength(0);
  });

  // TODO: Fix light-mode color contrast in index.html, then remove .fixme
  test.fixme('color contrast meets WCAG AA', async ({ page }) => {
    const results = await new AxeBuilder({ page })
      .withRules(['color-contrast'])
      .analyze();

    expect(results.violations).toHaveLength(0);
  });
});

// --- Horizontal overflow ---

test.describe('No horizontal overflow', () => {
  test('page does not scroll horizontally', async ({ page }) => {
    const overflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth > document.documentElement.clientWidth;
    });
    expect(overflow).toBe(false);
  });

  test('no visible element exceeds viewport width', async ({ page }) => {
    const overflowing = await page.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      const bad = [];
      for (const el of document.querySelectorAll('*')) {
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') continue;
        if (style.position === 'fixed' || style.position === 'sticky') continue;

        const rect = el.getBoundingClientRect();
        if (rect.right > vw + 1 || rect.left < -1) {
          bad.push({
            tag: el.tagName,
            class: el.className.toString().slice(0, 60),
            width: Math.round(rect.width),
            right: Math.round(rect.right),
            vw,
          });
        }
      }
      return bad;
    });
    expect(
      overflowing,
      `Overflowing elements:\n${JSON.stringify(overflowing, null, 2)}`
    ).toHaveLength(0);
  });
});

// --- Key elements visible ---

test.describe('Key elements visible', () => {
  test('nav is visible', async ({ page }) => {
    await expect(page.locator('nav')).toBeVisible();
  });

  test('hero heading is visible', async ({ page }) => {
    await expect(page.locator('.hero h1')).toBeVisible();
  });

  test('all feature rows are visible', async ({ page }) => {
    const tracks = page.locator('.track');
    const count = await tracks.count();
    expect(count).toBeGreaterThanOrEqual(8);
    for (let i = 0; i < count; i++) {
      await expect(tracks.nth(i)).toBeVisible();
    }
  });

  test('footer is visible', async ({ page }) => {
    await expect(page.locator('footer')).toBeVisible();
  });
});

// --- Waveform SVG sizing ---

test.describe('Waveform SVG', () => {
  test('waveform does not exceed viewport', async ({ page, viewport }) => {
    if (!viewport) return;
    const svg = page.locator('#waveform');
    if ((await svg.count()) === 0) return;
    const svgWidth = await svg.evaluate((el) => el.getBoundingClientRect().width);
    expect(svgWidth).toBeLessThanOrEqual(viewport.width);
  });
});

// --- Screenshots grid ---

test.describe('Screenshots grid', () => {
  test('screenshot images fit within viewport', async ({ page, viewport }) => {
    if (!viewport) return;
    const images = page.locator('.screenshots-grid .screenshot img');
    const count = await images.count();
    for (let i = 0; i < count; i++) {
      const width = await images.nth(i).evaluate((el) => el.getBoundingClientRect().width);
      expect(width).toBeLessThanOrEqual(viewport.width);
    }
  });
});

// --- Code block overflow ---

test.describe('Code blocks', () => {
  test('code blocks do not cause horizontal overflow', async ({ page, viewport }) => {
    if (!viewport) return;
    const blocks = page.locator('.code-block');
    const count = await blocks.count();
    for (let i = 0; i < count; i++) {
      const right = await blocks.nth(i).evaluate((el) => el.getBoundingClientRect().right);
      expect(right).toBeLessThanOrEqual(viewport.width + 1);
    }
  });
});
