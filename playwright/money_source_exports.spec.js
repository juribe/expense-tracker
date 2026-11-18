const fs = require('fs');
const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');
const { createMoneySource } = require('./helpers/money_sources');

test.describe('Money source statement exports', () => {
  let sourceName;
  let sourcePath;

  test.beforeEach(async ({ page }) => {
    await signUp(page);

    const category = `Export Cat-${Date.now()}`;
    sourceName = `Cuenta Export-${Date.now()}`;

    await createCategory(page, category);
    await createMoneySource(page, sourceName, 'account', { startingBalance: '2000000' });
    await createExpense(page, category, 'Mercado Central', '45000');
    await createExpense(page, category, 'Transporte', '95000');

    await page.goto('/money_sources/cash');
    const card = page.locator('[data-testid="account-card"]', { hasText: sourceName }).first();
    const href = await card.getByRole('link', { name: sourceName }).first().getAttribute('href');
    sourcePath = href.split('?')[0];
  });

  test('downloads CSV, XLSX and PDF files with the statement movements', async ({ page }) => {
    await openStatement(page);

    const csvDownload = await downloadExport(page, 'CSV');
    expect(csvDownload.suggestedFilename()).toMatch(/^extracto-.*\.csv$/);
    const csv = (await readDownload(csvDownload)).toString('utf8');
    expect(csv.split(/\r?\n/)[0]).toContain('Fecha');
    expect(csv.split(/\r?\n/)[0]).toContain('Descripción');
    expect(csv).toContain('Mercado Central');
    expect(csv).toContain('Transporte');

    const xlsxDownload = await downloadExport(page, 'Excel (XLSX)');
    expect(xlsxDownload.suggestedFilename()).toMatch(/^extracto-.*\.xlsx$/);
    const xlsx = await readDownload(xlsxDownload);
    expect(xlsx.subarray(0, 2).toString()).toBe('PK');
    expect(xlsx.length).toBeGreaterThan(1000);

    const pdfDownload = await downloadExport(page, 'PDF');
    expect(pdfDownload.suggestedFilename()).toMatch(/^extracto-.*\.pdf$/);
    const pdf = await readDownload(pdfDownload);
    expect(pdf.subarray(0, 4).toString()).toBe('%PDF');
    expect(pdf.length).toBeGreaterThan(1000);
  });

  test('CSV export keeps the active search filter', async ({ page }) => {
    await openStatement(page);

    await page.locator('input[name="q"]').fill('Mercado');
    await page.locator('button[aria-label="Buscar movimientos"]').click();

    await expect(page).toHaveURL(/q=Mercado/);
    await expect(page.locator('#movementRows')).toContainText('Mercado Central');
    await expect(page.locator('#movementRows')).not.toContainText('Transporte');

    const download = await downloadExport(page, 'CSV');
    const csv = (await readDownload(download)).toString('utf8');
    expect(csv).toContain('Mercado Central');
    expect(csv).not.toContain('Transporte');
  });

  async function openStatement(page) {
    await page.goto(`${sourcePath}/extractos`);
    await expect(page.locator('#movementRows')).toBeVisible();
    await expect(page.locator('#movementRows')).toContainText('Mercado Central');
    await expect(page.getByTestId('statement-export')).toBeVisible();
  }

  async function createExpense(page, category, description, amount) {
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill(amount);
    await page.locator('#expense_description').fill(description);
    await pickCategory(page, 'expense_category_id', category);
    await page.locator('#expense_money_source_id').selectOption({ label: sourceName });
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses/);
  }

  async function downloadExport(page, label) {
    await page.getByTestId('statement-export').click();
    const menu = page.locator('#statementExportMenu + .dropdown-menu');
    await expect(menu).toBeVisible();

    const [download] = await Promise.all([
      page.waitForEvent('download'),
      menu.getByRole('link', { name: label, exact: true }).click()
    ]);
    return download;
  }

  async function readDownload(download) {
    const path = await download.path();
    expect(path).toBeTruthy();
    return fs.readFileSync(path);
  }
});
