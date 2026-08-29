const { test, expect } = require('@playwright/test');
const { signUp, signIn } = require('./helpers/auth');

test.describe('auth pages are working', () => {
  test('signup page loads', async ({ page }) => {
    const response = await page.goto('/users/sign_up');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByRole('heading', { name: 'Crear cuenta' })).toBeVisible();
    await expect(page.locator('#user_email')).toBeVisible();
  });

  test('login page loads', async ({ page }) => {
    const response = await page.goto('/users/sign_in');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByRole('heading', { name: 'Iniciar sesión' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Iniciar sesión' })).toBeVisible();
  });

  test('user can sign up and then sign in', async ({ page }) => {
    const { email, password } = await signUp(page);
    await expect(page.getByText(email)).toBeVisible();

    await page.getByRole('link', { name: /Cerrar sesión/ }).click();
    await signIn(page, email, password);
    await expect(page.getByText(email)).toBeVisible();
  });
});
