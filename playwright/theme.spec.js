const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

function luminance(rgb) {
  return rgb
    .map((value) => {
      const channel = value / 255;
      return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
    })
    .reduce((acc, channel, index) => acc + [0.2126, 0.7152, 0.0722][index] * channel, 0);
}

function contrastRatio(fg, bg) {
  const parse = (color) => color.match(/\d+/g).slice(0, 3).map(Number);
  const [high, low] = [luminance(parse(fg)), luminance(parse(bg))].sort((a, b) => b - a);
  return (high + 0.05) / (low + 0.05);
}

test.describe('theme stylesheet loading', () => {
  test('loads each stylesheet once with the theme after the base theme', async ({ page }) => {
    await signUp(page);
    await page.goto('/dashboard');

    const hrefs = await page.evaluate(() =>
      Array.from(document.querySelectorAll('head link[rel="stylesheet"]')).map((link) => link.getAttribute('href'))
    );

    const themeIndex = hrefs.findIndex((href) => href.startsWith('/assets/theme-'));
    const spikeIndex = hrefs.findIndex((href) => href.startsWith('/assets/themes/spike-'));

    expect(hrefs.filter((href) => href.startsWith('/assets/theme-')).length).toBe(1);
    expect(hrefs.filter((href) => href.startsWith('/assets/themes/spike-')).length).toBe(1);
    expect(new Set(hrefs).size).toBe(hrefs.length);
    expect(themeIndex).toBeGreaterThan(spikeIndex);
  });
});

test.describe('recognition page dark mode', () => {
  test('recognition headings and bank cards adapt to dark mode', async ({ page }) => {
    await signUp(page);

    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(`Banco ${Date.now()}`);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_active').check();
    await page.locator('.card button[type="submit"], .card input[type="submit"]').first().click();
    await expect(page).toHaveURL(/\/money_sources\/credit_cards$/);

    await page.goto('/money_sources/recognition');
    await page.locator('[data-theme-toggle]').click();
    await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'dark');

    const bankToggle = page.locator('[data-testid="recognition-bank-toggle"]').first();
    if ((await bankToggle.getAttribute('aria-expanded')) === 'false') {
      await bankToggle.click();
    }

    const readColors = () =>
      page.evaluate(() => {
        const background = (el) => getComputedStyle(el).backgroundColor;
        let pageBg = background(document.body);
        if (pageBg === 'rgba(0, 0, 0, 0)') pageBg = background(document.documentElement);
        return {
          pageBg,
          title: getComputedStyle(document.querySelector('.recognition-title')).color,
          cardBg: getComputedStyle(document.querySelector('.recognition-table-card')).backgroundColor,
          rowName: getComputedStyle(document.querySelector('.recognition-row-name')).color
        };
      });

    await expect
      .poll(async () => {
        const { title, pageBg } = await readColors();
        return contrastRatio(title, pageBg);
      })
      .toBeGreaterThan(3);
    await expect.poll(async () => contrastRatio((await readColors()).cardBg, 'rgb(255, 255, 255)')).toBeGreaterThan(3);
    await expect
      .poll(async () => {
        const { rowName, cardBg } = await readColors();
        return contrastRatio(rowName, cardBg);
      })
      .toBeGreaterThan(3);
  });
});

test.describe('topbar theme contrast', () => {
  test('topbar nav actions stay visible in dark mode', async ({ page }) => {
    await signUp(page);
    await page.goto('/dashboard');

    await page.locator('[data-theme-toggle]').click();
    await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'dark');

    await expect
      .poll(async () => {
        const { link, background } = await page.evaluate(() => ({
          link: getComputedStyle(document.querySelector('.topbar .nav .nav-link')).color,
          background: getComputedStyle(document.querySelector('.topbar')).backgroundColor
        }));
        return contrastRatio(link, background);
      })
      .toBeGreaterThan(3);
  });
});
