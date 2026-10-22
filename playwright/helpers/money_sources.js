const { expect } = require('@playwright/test');

const SECTION_BY_KIND = {
  account: 'cash',
  wallet: 'cash',
  cash: 'cash',
  pocket: 'pockets',
  debit_card: 'cash',
  credit_card: 'credit_cards',
  loan: 'loans'
};

// Expenses require a money source (Transaction#money_source_must_be_present),
// so specs that create expenses need a payment source first. Cash is the
// simplest kind: name is the only meaningful field and no bank/institution
// panel applies.
async function createMoneySource(page, name, kind = 'cash', extra = {}) {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_kind').selectOption(kind);
  await page.locator('#money_source_name').fill(name);

  // The kind panels duplicate the id; only the active panel's input is
  // enabled. Manual expenses are guarded against emptying the source
  // (Transaction#ensure_sufficient_balance_for_manual_expense), so a funded
  // source is needed to pay expenses from.
  const balanceInput = page.locator('#money_source_starting_balance:not([disabled])').first();
  await balanceInput.fill(extra.startingBalance || '1000000');

  if (extra.fill) {
    await extra.fill(page);
  }

  await page.locator('.card form button[type="submit"], .card form input[type="submit"]').first().click();
  const section = SECTION_BY_KIND[kind] || 'cash';
  await expect(page).toHaveURL(new RegExp(`/money_sources/${section}$`));
  return name;
}

module.exports = { createMoneySource };
