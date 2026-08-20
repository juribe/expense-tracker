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
   - **Output:** ONLY Ruby code with test methods
   - **Context:** Dev: Build Dashboard for an Expense Tracker app
   - **Requirements:**
     - Use `visit "/path"`
     - Use `fill_in "Label", with: "value"` (explicitly NOT `fill_in with:`)
     - Use `select "Option", from: "Label"`
     - Use `click_button "Button Text"` or `click_link "Link Text"`
     - Use `assert_text "Expected text"` or `assert_selector "css"`
     - Use `assert_current_path "/expected/path"`
     - Use realistic test data (email: "test@example.com", password: "password123")
     - Format: Ruby test methods inside a class
     - Output ONLY the code, no explanations

2.  **Identify Key Features for an Expense Tracker Dashboard:**
   - User authentication (login)
   - Dashboard overview (total expenses, recent transactions, categories)
   - Adding a new expense
   - Filtering/Searching expenses
   - Navigating to different sections (e.g., categories, reports)
   - Since it's a "Build Dashboard" task, I'll focus on:
     - Logging in
     - Viewing the dashboard
     - Adding an expense
     - Verifying dashboard updates
     - Filtering expenses
     - Navigating to categories/reports

3.  **Draft Test Methods (Mental Refinement):**
   I'll create a test class `ExpenseTrackerSystemTest` with several test methods covering the dashboard functionality.

   *Test 1: User can log in and view dashboard*
      test "user can log in and view dashboard" do
     visit "/users/sign_in"
     fill_in "Email", with: "test@example.com"
     fill_in "Password", with: "password123"
     click_button "Log in"
     assert_current_path "/dashboard"
     assert_text "Welcome to your Expense Dashboard"
     assert_selector "h1", text: "Dashboard"
   end
   
   *Test 2: User can add a new expense from dashboard*
      test "user can add a new expense from dashboard" do
     visit "/users/sign_in"
     fill_in "Email", with: "test@example.com"
     fill_in "Password", with: "password123"
     click_button "Log in"
     click_link "Add Expense"
     fill_in "Amount", with: "45.50"
     fill_in "Description", with: "Grocery shopping"
     select "Food & Dining", from: "Category"
     click_button "Save Expense"
     assert_text "Expense created successfully"
     assert_current_path "/dashboard"
     assert_text "Grocery shopping"
     assert_text "$45.50"
   end
   
   *Test 3: User can filter expenses by category on dashboard*
      test "user can filter expenses by category on dashboard" do
     visit "/users/sign_in"
     fill_in "Email", with: "test@example.com"
     fill_in "Password", with: "password123"
     click_button "Log in"
     select "Transportation", from: "Filter by Category"
     click_button "Apply Filter"
     assert_selector "table.expenses-list"
     assert_text "Transportation"
     refute_text "Food & Dining"
   end
   
   *Test 4: User can navigate to reports from dashboard*
      test "user can navigate to reports from dashboard" do
     visit "/users/sign_in"
     fill_in "Email", with: "test@example.com"
     fill_in "Password", with: "password123"
     click_button "Log in"
     click_link "View Reports"
     assert_current_path "/reports"
     assert_text "Monthly Expense Report"
     assert_selector "canvas#expense-chart"
   end
   
   *Test 5: Dashboard displays summary statistics*
      test "dashboard displays summary statistics" do
     visit "/users/sign_in"
     fill_in "Email", with: "test@example.com"
     fill_in "Password", with: "password123"
     click_button "Log in"
     assert_selector ".summary-card", count: 3
     assert_text "Total Expenses"
     assert_text "This Month"
     assert_text "Remaining Budget"
   end
   
4.  **Check Against Requirements:**
   - Visits pages using `visit "/path"`? Yes.
   - Types in forms using `fill_in "Label", with: "value"`? Yes.
   - Selects options using `select "Option", from: "Label"`? Yes.
   - Clicks buttons using `click_button` or `click_link`? Yes.
   - Verifies content using `assert_text` or `assert_selector`? Yes.
   - Verifies navigation using `assert_current_path`? Yes.
   - Realistic test data? Used "test@example.com" and "password123".
   - Output ONLY Ruby code with test methods inside a class? Yes.
   - No explanations? Yes.

   I'll wrap them in a class `ExpenseTrackerDashboardTest < ApplicationSystemTestCase` (standard Rails naming) or just `class ExpenseTrackerSystemTest`. I'll stick to a simple class structure as requested.

   Let's refine the code to ensure it strictly matches the prompt's formatting and constraints. I'll make sure every test method follows the exact syntax requested.

   One minor adjustment: The prompt says "Output ONLY the Ruby code with test methods." I'll provide just the class and methods.

   Structure:
      class ExpenseTrackerDashboardTest < ApplicationSystemTestCase
     test "user can log in and view dashboard" do
       # ...
     end

     test "user can add a new expense from dashboard" do
       # ...
     end

     test "user can filter expenses by category on dashboard" do
       # ...
     end

     test "user can navigate to reports from dashboard" do
       # ...
     end

     test "dashboard displays summary statistics" do
       # ...
     end
   end
   
   Check constraints:
   - `fill_in "Label", with: "value"` -> Used correctly.
   - `select "Option", from: "Label"` -> Used correctly.
   - `click_button` / `click_link` -> Used correctly.
   - `assert_text` / `assert_selector` -> Used correctly.
   - `assert_current_path` -> Used correctly.
   - Realistic data -> Used.
   - Only Ruby code -> Yes.

   All good. I will generate the output now. I'll make sure the code is clean and directly matches the requirements. I'll add a few more realistic dashboard interactions like editing or deleting if needed, but the current set covers the main dashboard features well. I'll stick to 5 solid tests.

   One thing: The prompt says "Output ONLY the Ruby code with test methods." I will output exactly that. No markdown code blocks? The example shows markdown code blocks. I'll use markdown code blocks as in the example. Actually, the prompt says "Output ONLY the Ruby code with test methods." I'll wrap it in a ruby block as is standard.

   Let's draft it carefully. 
   I'll ensure the syntax exactly matches `fill_in "Label", with: "value"` (note the comma placement, which is standard Ruby keyword argument syntax, but the prompt explicitly says `fill_in "Label", with: "value"`). I'll follow that exactly.

   All set. Output matches response. 
   Proceeds. 
   Self-Correction/Verification during thought:
   - Check `fill_in` syntax: `fill_in "Email", with: "test@example.com"` is correct.
   - Check `select` syntax: `select "Food & Dining", from: "Category"` is correct.
   - Check `assert_current_path`: `assert_current_path "/dashboard"` is correct.
   - The prompt says "Output ONLY the Ruby code with test methods." I will output just the class containing the tests.
   - I'll make sure the class name is appropriate: `class ExpenseTrackerDashboardTest < ApplicationSystemTestCase`
   - I'll ensure no extra text is included.

   Ready.✅
   Output matches the final refined version. 
   Generating. 
   [Output Generation] -> *Proceeds*
   *(Self-Correction/Refinement during drafting)*: I should make sure the tests are self-contained and follow Rails system test conventions. I'll add `driven_by :rack_test` or similar if needed, but the prompt just wants the test methods. I'll stick to the exact format requested.

   Final code structure:
      class ExpenseTrackerDashboardTest < ApplicationSystemTestCase
     test "user can log in and view dashboard" do
       visit "/users/sign_in"
       fill_in "Email", with: "test@example.com"
       fill_in "Password", with: "password123"
       click
end
