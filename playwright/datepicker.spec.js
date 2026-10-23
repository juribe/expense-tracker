const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');

// Flatpickr replaces the native browser date widget: the calendar must speak
// Spanish and display dd/MM/yyyy, while the hidden original input keeps the
// ISO value (Y-m-d) the server parses.
test.describe('date pickers render in Spanish', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
    await createCategory(page, `Food-${Date.now()}`);
    await createMoneySource(page, `Efectivo-${Date.now()}`);
  });

  test('the expense form calendar shows Spanish months and weekdays', async ({ page }) => {
    await page.goto('/expenses/new');

    const dateInput = page.locator('#expense_date');
    await dateInput.click();

    const calendar = page.locator('.flatpickr-calendar');
    await expect(calendar).toBeVisible();

    // es locale: month names lowercase and weekdays starting Monday ("Lun"),
    // never the browser-locale English defaults ("October", "Mo").
    await expect(calendar.locator('.flatpickr-current-month')).toContainText(/octubre|noviembre|diciembre/i);
    await expect(calendar.locator('.flatpickr-weekday').first()).toHaveText(/lun|mar|mi|jue/i);
    await expect(calendar.locator('.flatpickr-weekdays')).not.toContainText('Mo');
  });

  test('picking a date shows dd/MM/yyyy and submits the ISO value Rails expects', async ({ page }) => {
    await page.goto('/expenses/new');

    const dateInput = page.locator('#expense_date');
    const hiddenIso = page.locator('input[name="expense[date]"]');
    await dateInput.click();
    await page.locator('.flatpickr-day:not(.prevMonthDay):not(.nextMonthDay)').first().click();

    await expect(dateInput).toHaveValue(/^0?\d\d\/0?\d\d\/\d{4}$/);
    await expect(hiddenIso).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);

    await page.locator('#expense_amount').fill('120.00');
    await page.locator('#expense_description').fill('Paseo');
    await page.locator('#expense_money_source_id').selectOption({ index: 1 });
    await page.getByRole('button', { name: 'Guardar' }).click();

    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.getByText('El gasto se creó correctamente.')).toBeVisible();
  });

  test('filling a dd/MM/yyyy value programmatically still works (regression)', async ({ page }) => {
    await page.goto('/expenses/new');

    await page.locator('#expense_amount').fill('45.20');
    await page.locator('#expense_date').fill('15/11/2023');
    await page.locator('#expense_description').fill('Regression dd/MM');
    await page.locator('#expense_money_source_id').selectOption({ index: 1 });
    await page.getByRole('button', { name: 'Guardar' }).click();

    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.getByText('El gasto se creó correctamente.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Regression dd/MM');
  });

  test('the calendar adapts to dark mode', async ({ page }) => {
    await page.goto('/expenses/new');

    await page.locator('[data-theme-toggle]').click();
    await expect(page.locator('html')).toHaveAttribute('data-bs-theme', 'dark');

    await page.locator('#expense_date').click();
    const calendar = page.locator('.flatpickr-calendar');
    await expect(calendar).toBeVisible();

    const background = await calendar.evaluate((node) => getComputedStyle(node).backgroundColor);
    expect(background).not.toBe('rgb(255, 255, 255)');
    expect(background).not.toBe('rgb(249, 249, 249)');

    const dayText = await page
      .locator('.flatpickr-day:not(.prevMonthDay):not(.nextMonthDay):not(.flatpickr-disabled)')
      .first()
      .evaluate((node) => getComputedStyle(node).color);
    expect(dayText).not.toBe('rgb(0, 0, 0)');
  });
});
