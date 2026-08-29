const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('category pages are working', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('user can create a category', async ({ page }) => {
    const name = `Food-${Date.now()}`;
    await page.goto('/categories');
    await page.getByRole('link', { name: /Nueva categoría/ }).first().click();
    await expect(page).toHaveURL(/\/categories\/new/);

    await page.locator('#category_name').fill(name);
    await page.locator('#category_description').fill('Expenses for meals and groceries');
    await page.locator('#category_category_type').selectOption({ label: 'Gasto' });
    await page.getByRole('button', { name: 'Guardar Categoría' }).click();

    await expect(page).toHaveURL(/\/categories\/\d+/);
    await expect(page.getByText('La categoría se creó correctamente.')).toBeVisible();
    await expect(page.getByRole('heading', { name })).toBeVisible();
  });

  test('user can edit a category', async ({ page }) => {
    const name = `Transport-${Date.now()}`;
    await createCategory(page, name, 'Travel expenses');

    await page.goto('/categories');
    await page.locator(`a[aria-label="Editar ${name}"]`).click();
    await expect(page).toHaveURL(/\/categories\/\d+\/edit/);

    await page.locator('#category_name').fill(`${name}-updated`);
    await page.locator('#category_description').fill('All travel related costs');
    await page.getByRole('button', { name: 'Guardar Categoría' }).click();

    await expect(page).toHaveURL(/\/categories\/\d+/);
    await expect(page.getByText('La categoría se actualizó correctamente.')).toBeVisible();
    await expect(page.getByRole('heading', { name: `${name}-updated` })).toBeVisible();
  });

  test('user can delete a category', async ({ page }) => {
    const name = `Entertainment-${Date.now()}`;
    await createCategory(page, name, 'Movies, concerts, etc.');

    await page.goto('/categories');
    await page.locator(`button[aria-label="Eliminar ${name}"]`).click();

    await expect(page.getByText('La categoría se eliminó correctamente.')).toBeVisible();
    await expect(page.getByText(name)).toHaveCount(0);
    await expect(page).toHaveURL(/\/categories/);
  });

  test('user sees validation errors on duplicate name', async ({ page }) => {
    const name = `Dup-${Date.now()}`;
    await createCategory(page, name);

    await page.goto('/categories/new');
    await page.locator('#category_name').fill(name);
    await page.locator('#category_category_type').selectOption({ label: 'Gasto' });
    await page.getByRole('button', { name: 'Guardar Categoría' }).click();

    await expect(page.getByText('Nombre ya está en uso', { exact: true })).toBeVisible();
    await expect(page.locator('#error-summary')).toBeVisible();
    await expect(page.locator('input.is-invalid')).toBeVisible();
  });
});
