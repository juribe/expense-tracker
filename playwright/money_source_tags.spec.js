const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('MoneySource tags', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  async function createMoneySource(page, name, tags = []) {
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_active').check();

    for (let i = 0; i < tags.length; i++) {
      if (i > 0) {
        await page.locator('#addTag').click();
      }
      await page.locator('#tags .tag-row input').nth(i).fill(tags[i]);
    }

    await page.locator('form input[type="submit"]').click();
    await expect(page).toHaveURL(/\/money_sources$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();
  }

  async function editHrefFor(page, name) {
    const card = page.locator('.card', { hasText: name }).first();
    return card.locator('a[href$="/edit"]').getAttribute('href');
  }

  test('user can create a money source with tags and sees them as badges', async ({ page }) => {
    const name = `Tarjeta Baloto-${Date.now()}`;
    await createMoneySource(page, name, ['tarjeta clásica', '1234']);

    await expect(page.getByText('tarjeta clásica', { exact: true })).toBeVisible();
    await expect(page.getByText('1234', { exact: true })).toBeVisible();
  });

  test('tags are normalized (trimmed + lowercase) before display', async ({ page }) => {
    const name = `Ahorros Leo-${Date.now()}`;
    await createMoneySource(page, name, ['  Tarjeta Clásica  ']);

    await expect(page.getByText('tarjeta clásica', { exact: true })).toBeVisible();
    await expect(page.getByText('Tarjeta Clásica', { exact: true })).toHaveCount(0);
  });

  test('money source show page displays its tags', async ({ page }) => {
    const name = `Billetera Móvil-${Date.now()}`;
    await createMoneySource(page, name, ['tarjeta clásica', '9999']);

    const editHref = await editHrefFor(page, name);
    await page.goto(editHref.replace(/\/edit$/, ''));

    await expect(page.getByRole('heading', { name })).toBeVisible();
    await expect(page.getByText('Etiquetas de coincidencia')).toBeVisible();
    await expect(page.getByText('tarjeta clásica', { exact: true })).toBeVisible();
    await expect(page.getByText('9999', { exact: true })).toBeVisible();
  });

  test('user can add a tag to an existing money source', async ({ page }) => {
    const name = `TDC Falabella-${Date.now()}`;
    await createMoneySource(page, name, ['1111']);

    const editHref = await editHrefFor(page, name);
    await page.goto(editHref);

    await page.locator('#addTag').click();
    await page.locator('#tags .tag-row input').nth(1).fill('2222');
    await page.locator('form input[type="submit"]').click();

    await expect(page.getByText('La fuente de dinero se actualizó correctamente.')).toBeVisible();
    await expect(page.getByText('1111', { exact: true })).toBeVisible();
    await expect(page.getByText('2222', { exact: true })).toBeVisible();
  });

  test('user can remove a tag from a money source', async ({ page }) => {
    const name = `TDC Avianca-${Date.now()}`;
    await createMoneySource(page, name, ['1111', '2222']);

    const editHref = await editHrefFor(page, name);
    await page.goto(editHref);
    await expect(page.locator('#tags .tag-row')).toHaveCount(2);

    await page.locator('#tags .tag-row').first().locator('.remove-tag').click();
    await expect(page.locator('#tags .tag-row')).toHaveCount(1);
    await page.locator('form input[type="submit"]').click();

    await expect(page.getByText('2222', { exact: true })).toBeVisible();
    await expect(page.getByText('1111', { exact: true })).toHaveCount(0);
  });

  test('submitting the same normalized tag twice on create is rejected', async ({ page }) => {
    const name = `Cuenta Nu-${Date.now()}`;
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_active').check();

    await page.locator('#tags .tag-row input').first().fill('Tarjeta Clásica');
    await page.locator('#addTag').click();
    await page.locator('#tags .tag-row input').nth(1).fill('tarjeta clásica');
    await page.locator('form input[type="submit"]').click();

    await expect(page.getByRole('heading', { name: 'Nueva Fuente de Dinero' })).toBeVisible();
    await expect(page.getByText(/impidió guardar la fuente de dinero/)).toBeVisible();
  });

  test('duplicate normalized tags entered on edit collapse into a single tag', async ({ page }) => {
    const name = `Cuenta Nu-${Date.now()}`;
    await createMoneySource(page, name, ['1111']);

    const editHref = await editHrefFor(page, name);
    await page.goto(editHref);

    await page.locator('#addTag').click();
    await page.locator('#tags .tag-row input').nth(1).fill('1111');
    await page.locator('form input[type="submit"]').click();

    await expect(page.getByText('La fuente de dinero se actualizó correctamente.')).toBeVisible();
    await expect(page.getByText('1111', { exact: true })).toHaveCount(1);
  });

  test('money source without tags shows no tag badges', async ({ page }) => {
    const name = `Caja Menor-${Date.now()}`;
    await createMoneySource(page, name);

    const card = page.locator('.card', { hasText: name }).first();
    await expect(card.locator('.badge')).toHaveCount(0);
  });

  test('the same tag is allowed on different money sources', async ({ page }) => {
    const first = `Daviplata A-${Date.now()}`;
    const second = `Daviplata B-${Date.now()}`;
    await createMoneySource(page, first, ['daviplata']);
    await createMoneySource(page, second, ['daviplata']);

    await expect(page.getByText('daviplata', { exact: true })).toHaveCount(2);
  });
});