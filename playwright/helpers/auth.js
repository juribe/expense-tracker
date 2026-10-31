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

  // Accounts must confirm their email before signing in. Specs cannot open the
  // confirmation email, so the test-only endpoint confirms the account.
  await confirmUser(page, email);
  // Internal tools (expense playground, AI evaluations) are admin-only, so
  // specs that exercise them opt into the role before signing in.
  if (overrides.admin) {
    await promoteAdmin(page, email);
  }
  await signIn(page, email, password);

  return { email, password, name };
}

async function confirmUser(page, email) {
  const response = await page.request.post('/test_support/confirm_user', {
    form: { email }
  });
  if (!response.ok()) {
    throw new Error(`Could not confirm ${email}: ${response.status()}`);
  }
}

async function promoteAdmin(page, email) {
  const response = await page.request.post('/test_support/promote_admin', {
    form: { email }
  });
  if (!response.ok()) {
    throw new Error(`Could not promote ${email} to admin: ${response.status()}`);
  }
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
  await expect(page).toHaveURL(/\/categories\/[0-9a-f-]{36}/);
}

module.exports = { uniqueEmail, signUp, signIn, createCategory };
