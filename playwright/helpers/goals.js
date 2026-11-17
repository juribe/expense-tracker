const { expect } = require('@playwright/test');

// A Goal is only a target: the saved amount is the pocket's balance and the
// reservations live in GoalAllocation, so creating one never moves money.
async function createGoal(page, { name, target, pocket, targetDate, category } = {}) {
  await page.goto('/goals/new');
  await page.locator('#goal_name').fill(name);
  await page.locator('#goal_target_amount').fill(String(target));

  if (pocket) {
    await page.locator('#goal_pocket_id').selectOption({ label: pocket });
  }
  if (category) {
    await page.locator('#goal_category').selectOption(category);
  }
  if (targetDate) {
    await page.locator('#goal_target_date').fill(targetDate);
  }

  await page.getByRole('button', { name: 'Crear meta' }).click();
  await expect(page).toHaveURL(/\/goals$/);
  await expect(page.getByText('Meta creada.')).toBeVisible();
  return name;
}

module.exports = { createGoal };
