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

  await page.locator('.card button[type="submit"], .card input[type="submit"]').first().click();
  const section = SECTION_BY_KIND[kind] || 'cash';
  await expect(page).toHaveURL(new RegExp(`/money_sources/${section}$`));
  return name;
}

async function createCreditCard(page, name, extra = {}) {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_name').fill(name);
  await page.locator('#money_source_kind').selectOption('credit_card');
  await page.locator('#money_source_credit_account_attributes_card_last_four')
            .fill(extra.lastFour || '1234');
  await page.locator('#money_source_credit_account_attributes_credit_limit')
            .fill(extra.creditLimit || '20000000');

  if (extra.fill) {
    await extra.fill(page);
  }

  await page.locator('.card button[type="submit"], .card input[type="submit"]').first().click();
  await expect(page).toHaveURL(/\/money_sources\/credit_cards$/);
  return name;
}

async function createLoan(page, name, extra = {}) {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_name').fill(name);
  await page.locator('#money_source_kind').selectOption('loan');

  if (extra.subKind) {
    await page.locator('#money_source_sub_kind').selectOption(extra.subKind);
  }

  await page.locator('#money_source_credit_account_attributes_principal_amount')
            .fill(extra.principal || '5000000');

  if (extra.fill) {
    await extra.fill(page);
  }

  await page.locator('.card button[type="submit"], .card input[type="submit"]').first().click();
  await expect(page).toHaveURL(/\/money_sources\/loans$/);
  return name;
}

module.exports = { createMoneySource, createCreditCard, createLoan };
