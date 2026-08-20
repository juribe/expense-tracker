require "application_system_test_case"

class DevBuildDashboardTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  <think>
Here's a thinking process:

1.  **Analyze User Input:**
   - **Role:** QA Engineer
   - **Task:** Write Capybara system tests
   - **Output:** Only Ruby code with test methods
   - **Context:** Dev: Build Dashboard for an Expense Tracker app
   - **Requirements:**
     1. Use `visit "/path"`
     2. Use `fill_in "Label", with: "value"` (strictly this format)
     3. Use `select "Option", from: "Label"`
     4. Use `click_button "Button Text"` or `click_link "Link Text"`
     5. Use `assert_text "Expected text"` or `assert_selector "css"`
     6. Use `assert_current_path "/expected/path"`
     7. Use realistic test data (email: "test@example.com", password: "password123")
     8. Output ONLY the test methods inside a class, no explanations
     9. Follow the example format

2.  **Identify Key Features for an Expense Tracker Dashboard:**
   - Dashboard typically shows:
     - Summary of expenses (total, by category, recent transactions)
     - Navigation to add expenses, view reports, settings
     - Maybe a filter/date range selector
     - Charts or tables (we'll simulate with text/assertions)
   - I need to create tests that cover:
     - Visiting the dashboard
     - Verifying dashboard content (totals, recent expenses)
     - Filtering expenses (using select)
     - Adding an expense from the dashboard (or navigating to it)
     - Verifying navigation/paths
     - Maybe a test for viewing a specific category or date range

3.  **Draft Test Methods (Mental Refinement):**
   I'll create a class `DashboardSystemTest < ApplicationSystemTestCase` (standard Rails naming) and include several test methods covering the requirements.

   *Test 1: Visit dashboard and verify initial content*
      test "user can view dashboard with expense summary" do
     visit "/dashboard"
     assert_current_path "/dashboard"
     assert_text "Expense Summary"
     assert_text "Total Expenses: $0.00"
     assert_text "Recent Transactions"
   end
   
   *Test 2: Filter expenses by category*
      test "user can filter expenses by category" do
     visit "/dashboard"
     select "Food & Dining", from: "Category Filter"
     click_button "Apply Filter"
     assert_text "Filtered by: Food & Dining"
     assert_selector "table.expenses-table"
   end
   
   *Test 3: Add new expense from dashboard*
      test "user can add a new expense from dashboard" do
     visit "/dashboard"
     click_button "Add Expense"
     assert_current_path "/expenses/new"
     fill_in "Description", with: "Grocery shopping"
     fill_in "Amount", with: "45.50"
     select "Food & Dining", from: "Category"
     fill_in "Date", with: "2023-10-25"
     click_button "Save Expense"
     assert_text "Expense was successfully created."
     assert_current_path "/dashboard"
     assert_text "Grocery shopping"
   end
   
   *Test 4: Navigate to reports from dashboard*
      test "user can navigate to reports from dashboard" do
     visit "/dashboard"
     click_link "View Reports"
     assert_current_path "/reports"
     assert_text "Expense Reports"
   end
   
   *Test 5: Verify dashboard updates after adding expense*
   (Maybe combine with Test 3 or make it separate. I'll keep it simple and focused on the requirements.)

   Let's ensure all constraints are met:
   - `visit "/path"` ✓
   - `fill_in "Label", with: "value"` ✓
   - `select "Option", from: "Label"` ✓
   - `click_button` / `click_link` ✓
   - `assert_text` / `assert_selector` ✓
   - `assert_current_path` ✓
   - Realistic data ✓
   - Only Ruby code with test methods inside a class ✓
   - No explanations ✓

   I'll structure it properly as a Rails system test class. I'll make sure the syntax matches exactly what's requested. I'll add a few more realistic dashboard interactions like date range filtering or verifying chart/summary updates.

   Let's draft it carefully:

      class DashboardSystemTest < ApplicationSystemTestCase
     test "user can view dashboard with expense summary" do
       visit "/dashboard"
       assert_current_path "/dashboard"
       assert_text "Expense Summary"
       assert_text "Total Expenses: $0.00"
       assert_text "Recent Transactions"
       assert_selector "div.dashboard-summary"
     end

     test "user can filter dashboard expenses by category" do
       visit "/dashboard"
       select "Food & Dining", from: "Category Filter"
       click_button "Apply Filter"
       assert_text "Showing expenses for: Food & Dining"
       assert_selector "table.expenses-list"
     end

     test "user can add a new expense from the dashboard" do
       visit "/dashboard"
       click_button "Add Expense"
       assert_current_path "/expenses/new"
       fill_in "Description", with: "Weekly groceries"
       fill_in "Amount", with: "67.85"
       select "Food & Dining", from: "Category"
       fill_in "Date", with: "2023-11-15"
       click_button "Save Expense"
       assert_text "Expense was successfully created."
       assert_current_path "/dashboard"
       assert_text "Weekly groceries"
       assert_text "Total Expenses: $67.85"
     end

     test "user can navigate to monthly reports from dashboard" do
       visit "/dashboard"
       click_link "View Reports"
       assert_current_path "/reports"
       assert_text "Monthly Expense Reports"
     end

     test "user can filter expenses by date range on dashboard" do
       visit "/dashboard"
       fill_in "Start Date", with: "2023-10-01"
       fill_in "End Date", with: "2023-10-31"
       click_button "Filter by Date"
       assert_text "Filtered: Oct 1 - Oct 31, 2023"
       assert_selector "div.date-filtered-results"
     end
   end
   
   Check constraints:
   - `visit "/path"` -> used correctly
   - `fill_in "Label", with: "value"` -> used correctly (note: the prompt says `fill_in "Label", with: "value"` (NOT fill_in with:), which is standard Capybara syntax anyway)
   - `select "Option", from: "Label"` -> used correctly
   - `click_button` / `click_link` -> used correctly
   - `assert_text` / `assert_selector` -> used correctly
   - `assert_current_path` -> used correctly
   - Realistic data -> used dates, amounts, descriptions
   - Output ONLY Ruby code with test methods inside a class -> yes
   - No explanations -> yes

   One minor thing: The prompt says "Output ONLY the Ruby code with test methods." I'll wrap it in a class as requested. I'll make sure the formatting matches exactly. I'll remove any markdown if needed, but the prompt says "Output ONLY the Ruby code with test methods." I'll provide just the code block.

   All constraints met. Ready.✅
   I will generate the response now. 
   Self-Correction/Verification during thought:
   - Check `fill_in` syntax: The prompt explicitly says `fill_in "Label", with: "value"` (NOT fill_in with:). This is standard. I used it correctly.
   - Check `select` syntax: `select "Option", from: "Label"` - used correctly.
   - Check `assert_current_path` - used correctly.
   - Check realistic data - used realistic expense data.
   - The prompt says "Output ONLY the Ruby code with test methods." I will output just the class with the tests.
   - I'll make sure there's no extra text.

   All good. Proceeds. 
   Output matches the drafted code.✅
   One thing: I'll make sure the class name is standard like `DashboardSystemTest < ApplicationSystemTestCase`. The prompt says "inside a class", so that's fine.
   I'll output exactly the code block.✅
   Done. 
   Generating. 
   [Output Generation] -> *Proceeds*
   *(Self-Correction/Refinement during drafting)*: 
   I should ensure the test methods are self-contained and follow Rails system test conventions. The prompt example shows `test "user can sign up" do ... end`. I'll stick to that.
   I'll verify the exact syntax requested: `fill_in "Label", with: "value"` (NOT fill_in with:). This is just emphasizing the keyword argument syntax. I used it correctly.
   All good.✅
end
