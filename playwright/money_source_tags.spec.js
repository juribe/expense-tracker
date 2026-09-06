const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('MoneySource recognition keywords', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  async function createMoneySource(page, name, kind = 'credit_card') {
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption(kind);
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();
    const url = kind === 'credit_card' ? /\/money_sources\/credit_cards$/ : /\/money_sources\/loans$/;
    await expect(page).toHaveURL(url);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();
  }

  async function showHrefFor(page, name) {
    await page.goto('/money_sources/credit_cards');
    const card = page.locator('[data-testid="credit-card-card"]', { hasText: name }).first();
    return card.locator('a[href^="/money_sources/"]').first().getAttribute('href');
  }

  async function addKeywords(page, sourceName, keywords) {
    await page.goto('/money_sources/recognition');
    const row = page.locator('[data-testid="recognition-row"]', { hasText: sourceName });
    await row.locator('[data-testid="edit-recognition"]').click();
    await expect(page.getByTestId('recognition-edit-panel')).toBeVisible();

    for (const keyword of keywords) {
      await page.locator('[data-recognition-chips="keywords"] [data-recognition-add]').click();
      const input = page.locator('[data-recognition-inline-add="keywords"]');
      await input.fill(keyword);
      await input.press('Enter');
    }

    await page.getByTestId('recognition-save').click();
    await expect(page.getByText('Configuración de reconocimiento guardada.')).toBeVisible();
  }

  test('user can configure recognition keywords and sees them as badges on the money source', async ({ page }) => {
    const name = `Tarjeta Baloto-${Date.now()}`;
    await createMoneySource(page, name);
    await addKeywords(page, name, ['tarjeta clásica', '1234']);

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);

    await expect(page.getByRole('heading', { name })).toBeVisible();
    await expect(page.getByText('tarjeta clásica', { exact: true })).toBeVisible();
    await expect(page.getByText('1234', { exact: true })).toBeVisible();
  });

  test('keywords are trimmed before display', async ({ page }) => {
    const name = `Ahorros Leo-${Date.now()}`;
    await createMoneySource(page, name);
    await addKeywords(page, name, ['  Tarjeta Clásica  ']);

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);

    await expect(page.getByText('Tarjeta Clásica', { exact: true })).toBeVisible();
    await expect(page.locator('.card', { hasText: 'Reconocimiento' }).locator('.badge')).toHaveText('Tarjeta Clásica');
  });

  test('money source show page displays its recognition keywords', async ({ page }) => {
    const name = `Billetera Móvil-${Date.now()}`;
    await createMoneySource(page, name);
    await addKeywords(page, name, ['tarjeta clásica', '9999']);

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);

    await expect(page.getByRole('heading', { name })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Reconocimiento' })).toBeVisible();
    await expect(page.getByText('tarjeta clásica', { exact: true })).toBeVisible();
    await expect(page.getByText('9999', { exact: true })).toBeVisible();
  });

  test('user can add an extra keyword to an existing money source', async ({ page }) => {
    const name = `TDC Falabella-${Date.now()}`;
    await createMoneySource(page, name);
    await addKeywords(page, name, ['1111']);
    await addKeywords(page, name, ['2222']);

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);
    await expect(page.getByText('1111', { exact: true })).toBeVisible();
    await expect(page.getByText('2222', { exact: true })).toBeVisible();
  });

  test('user can remove a keyword from a money source', async ({ page }) => {
    const name = `TDC Avianca-${Date.now()}`;
    await createMoneySource(page, name);
    await addKeywords(page, name, ['1111', '2222']);

    await page.goto('/money_sources/recognition');
    const row = page.locator('[data-testid="recognition-row"]', { hasText: name });
    await row.locator('[data-testid="edit-recognition"]').click();
    await expect(page.getByTestId('recognition-edit-panel')).toBeVisible();

    const section = page.locator('[data-recognition-chips="keywords"]');
    await expect(section.locator('.recognition-chip')).toHaveCount(2);
    await section.locator('.recognition-chip', { hasText: '1111' }).first().locator('[data-recognition-remove]').click();
    await expect(section.locator('.recognition-chip')).toHaveCount(1);
    await page.getByTestId('recognition-save').click();
    await expect(page.getByText('Configuración de reconocimiento guardada.')).toBeVisible();

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);
    await expect(page.getByText('2222', { exact: true })).toBeVisible();
    await expect(page.getByText('1111', { exact: true })).toHaveCount(0);
  });

  test('submitting the same keyword twice collapses into a single keyword', async ({ page }) => {
    const name = `Cuenta Nu-${Date.now()}`;
    await createMoneySource(page, name);
    await addKeywords(page, name, ['1111', '1111']);

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);
    await expect(page.getByText('1111', { exact: true })).toHaveCount(1);
  });

  test('keywords that differ in case are kept as distinct values', async ({ page }) => {
    const name = `Cuenta Nu-${Date.now()}`;
    await createMoneySource(page, name);
    await addKeywords(page, name, ['Tarjeta Clásica', 'tarjeta clásica']);

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);
    await expect(page.getByText('Tarjeta Clásica', { exact: true })).toBeVisible();
    await expect(page.getByText('tarjeta clásica', { exact: true })).toBeVisible();
    await expect(page.locator('.card', { hasText: 'Reconocimiento' }).locator('.badge')).toHaveCount(2);
  });

  test('money source without keywords shows no keyword badges', async ({ page }) => {
    const name = `Caja Menor-${Date.now()}`;
    await createMoneySource(page, name);

    const showHref = await showHrefFor(page, name);
    await page.goto(showHref);

    const recognitionCard = page.locator('.card', { hasText: 'Reconocimiento' });
    await expect(recognitionCard.locator('.badge')).toHaveCount(0);
    await expect(recognitionCard.getByText('Sin configurar')).toBeVisible();
  });

  test('the same keyword is allowed on different money sources', async ({ page }) => {
    const first = `Daviplata A-${Date.now()}`;
    const second = `Daviplata B-${Date.now()}`;
    await createMoneySource(page, first);
    await createMoneySource(page, second);
    await addKeywords(page, first, ['daviplata']);
    await addKeywords(page, second, ['daviplata']);

    await page.goto(await showHrefFor(page, first));
    await expect(page.getByText('daviplata', { exact: true })).toHaveCount(1);
    await page.goto(await showHrefFor(page, second));
    await expect(page.getByText('daviplata', { exact: true })).toHaveCount(1);
  });
});