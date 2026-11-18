const { expect } = require('@playwright/test');

// Drives the category picker's visible combobox. The picker keeps a hidden
// native select for form submission, so specs exercise the real control
// instead of calling selectOption() on the hidden element.
//
// Fails if typing does not actually filter the list, so a regression that
// leaves every option visible cannot pass silently.
async function pickCategory(page, fieldId, label) {
  const input = page.locator(`#${fieldId}_search`);
  const listbox = page.locator(`#${fieldId}_listbox`);

  await input.click();
  await input.fill(label);

  const total = await listbox.locator('[role="option"]').count();
  const option = listbox.getByRole('option', { name: label, exact: true });
  await expect(option).toBeVisible();
  if (total > 1) {
    // The query must hide at least one row; otherwise typing does nothing.
    await expect
      .poll(async () => listbox.locator('[role="option"]:not([hidden])').count())
      .toBeLessThan(total);
  }

  // Selecting with the keyboard avoids racing the picker's deferred blur
  // handler, which can close the listbox while Playwright is clicking.
  const visibleOptions = listbox.locator('[role="option"]:not([hidden])');
  const index = await visibleOptions.evaluateAll(
    (options, wanted) => options.findIndex((candidate) => candidate.textContent.trim() === wanted),
    label
  );
  expect(index).toBeGreaterThanOrEqual(0);
  for (let step = 0; step < index; step += 1) {
    await input.press('ArrowDown');
  }
  await input.press('Enter');

  await expect(input).toHaveValue(label);
  await expect(page.locator(`#${fieldId}`)).toHaveValue(/^[0-9a-f-]{36}$/);
}

module.exports = { pickCategory };
