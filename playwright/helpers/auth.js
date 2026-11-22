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
  await page.locator('#user_terms_accepted').check();
  await page.locator('#user_privacy_accepted').check();
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

  // E2E specs exercise the full account/card experience. New sign-ups start
  // in the simple flow by product design, so tests explicitly switch to the
  // advanced tracking mode before their first authenticated navigation.
  await setMoneyTrackingMode(page, email, overrides.moneyTrackingMode || 'detailed');

  await signIn(page, email, password);

  // Grant a free trial so membership gating does not block navigation in E2E specs.
  const trialResponse = await page.request.post('/test_support/grant_trial', { form: { email } });
  if (!trialResponse.ok()) {
    throw new Error(`Could not grant trial to ${email}: ${trialResponse.status()}`);
  }

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

async function setMoneyTrackingMode(page, email, mode) {
  const response = await page.request.post('/test_support/money_tracking', {
    form: { email, mode }
  });
  if (!response.ok()) {
    throw new Error(`Could not set money tracking mode for ${email}: ${response.status()}`);
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
  return createCategoryOfType(page, name, 'Gasto', description);
}

// Incomes and monthly incomes only accept income categories, so specs that
// exercise them need a category of that type.
async function createIncomeCategory(page, name, description = '') {
  return createCategoryOfType(page, name, 'Ingreso', description);
}

async function createCategoryOfType(page, name, type, description = '') {
  await page.goto('/categories/new');
  await page.locator('#category_name').fill(name);
  if (description) {
    await page.locator('#category_description').fill(description);
  }
  await page.locator('#category_category_type').selectOption({ label: type });
  await page.getByRole('button', { name: 'Guardar Categoría' }).click();
  await expect(page).toHaveURL(/\/categories\/[0-9a-f-]{36}/);
}

module.exports = { uniqueEmail, signUp, signIn, createCategory, createIncomeCategory };
