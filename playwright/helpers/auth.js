const { expect } = require('@playwright/test');

function uniqueEmail() {
  return `user-${Date.now()}-${Math.random().toString(16).slice(2)}@example.com`;
}

async function signUp(page, overrides = {}) {
  const email = overrides.email || uniqueEmail();
  const password = overrides.password || 'password123';
  const name = overrides.name || 'Test User';

  await page.goto('/users/sign_up');
  await page.locator('#user_name').fill(name);
  await page.locator('#user_email').fill(email);
  await page.locator('#user_password').fill(password);
  await page.locator('#user_password_confirmation').fill(password);
  await page.getByRole('button', { name: 'Crear cuenta' }).click();
  await expect(page.locator('body')).toBeVisible();
  await expect(page).not.toHaveURL(/sign_up/);

  return { email, password, name };
}

async function signIn(page, email, password) {
  await page.goto('/users/sign_in');
  await page.locator('#user_email').fill(email);
  await page.locator('#user_password').fill(password);
  await page.getByRole('button', { name: 'Iniciar sesión' }).click();
  await expect(page).not.toHaveURL(/sign_in/);
}

async function createCategory(page, name, description = '') {
  await page.goto('/categories/new');
  await page.locator('#category_name').fill(name);
  if (description) {
    await page.locator('#category_description').fill(description);
  }
  await page.locator('#category_category_type').selectOption({ label: 'Gasto' });
  await page.getByRole('button', { name: 'Guardar Categoría' }).click();
  await expect(page).toHaveURL(/\/categories\/\d+/);
}

module.exports = { uniqueEmail, signUp, signIn, createCategory };
