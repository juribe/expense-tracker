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
   - **Context:** Expense Tracker app - Dashboard feature
   - **Requirements:**
     - Use `visit "/path"`
     - Use `fill_in "Label", with: "value"` (explicitly NOT `fill_in with:`)
     - Use `select "Option", from: "Label"`
     - Use `click_button "Button Text"` or `click_link "Link Text"`
     - Use `assert_text "Expected text"` or `assert_selector "css"`
     - Use `assert_current_path "/expected/path"`
     - Use realistic test data (email: "test@example.com", password: "password123")
     - Output ONLY test methods inside a class, no explanations
   - **Feature:** Dashboard for Expense Tracker

2.  **Identify Key Dashboard Features for an Expense Tracker:**
   - View dashboard after login
   - See summary stats (total expenses, balance, etc.)
   - Filter expenses by date/category
   - Add a new expense from dashboard
   - Navigate to expense list
   - Verify dashboard loads correctly with user data

3.  **Draft Test Methods (Mental Refinement):**
   I need to create a test class (e.g., `DashboardSystemTest < ApplicationSystemTestCase`) and write several test methods covering the dashboard functionality.

   *Test 1: User can view dashboard after login*
   - Visit sign in page
   - Fill in credentials
   - Click sign in
   - Assert current path is dashboard
   - Assert text like "Dashboard" or "Welcome"

   *Test 2: User can see expense summary on dashboard*
   - Assume logged in (or log in first)
   - Visit dashboard
   - Assert text for total expenses, income, balance
   - Assert selector for summary cards

   *Test 3: User can filter expenses by category on dashboard*
   - Visit dashboard
   - Select category from dropdown
   - Click filter button
   - Assert filtered results/text

   *Test 4: User can add a new expense from dashboard*
   - Visit dashboard
   - Click "Add Expense"
   - Fill in form (amount, category, date, description)
   - Click submit
   - Assert success message
   - Assert current path is dashboard
   - Assert new expense appears

   *Test 5: User can navigate to expense list from dashboard*
   - Visit dashboard
   - Click link "View All Expenses"
   - Assert current path "/expenses"
   - Assert text "Expenses"

   Let's structure these properly according to the constraints. I'll make sure to follow the exact syntax requested.

   Constraint check:
   - `visit "/path"` ✓
   - `fill_in "Label", with: "value"` ✓
   - `select "Option", from: "Label"` ✓
   - `click_button "Button Text"` / `click_link "Link Text"` ✓
   - `assert_text "Expected text"` / `assert_selector "css"` ✓
   - `assert_current_path "/expected/path"` ✓
   - Realistic data: email "test@example.com", password "password123" ✓
   - Output ONLY Ruby code with test methods inside a class ✓

   I'll write a cohesive set of tests inside a class. I'll assume standard Rails paths like `/users/sign_in`, `/dashboard`, `/expenses`. I'll make sure the syntax matches exactly.

   Let's draft:

      class DashboardSystemTest < ApplicationSystemTestCase
     test "user can access dashboard after signing in" do
       visit "/users/sign_in"
       fill_in "Email", with: "test@example.com"
       fill_in "Password", with: "password123"
       click_button "Sign in"
       assert_current_path "/dashboard"
       assert_text "Dashboard"
       assert_text "Welcome back, Test User"
     end

     test "user can view expense summary on dashboard" do
       visit "/users/sign_in"
       fill_in "Email", with: "test@example.com"
       fill_in "Password", with: "password123"
       click_button "Sign in"
       visit "/dashboard"
       assert_selector ".summary-card"
       assert_text "Total Expenses"
       assert_text "Total Income"
       assert_text "Current Balance"
     end

     test "user can filter dashboard expenses by category" do
       visit "/users/sign_in"
       fill_in "Email", with: "test@example.com"
       fill_in "Password", with: "password123"
       click_button "Sign in"
       visit "/dashboard"
       select "Food & Dining", from: "Category"
       click_button "Filter"
       assert_text "Filtered by Food & Dining"
       assert_selector ".expense-list"
     end

     test "user can add a new expense from dashboard" do
       visit "/users/sign_in"
       fill_in "Email", with: "test@example.com"
       fill_in "Password", with: "password123"
       click_button "Sign in"
       visit "/dashboard"
       click_button "Add Expense"
       fill_in "Amount", with: "45.50"
       select "Transportation", from: "Category"
       fill_in "Date", with: "2023-10-25"
       fill_in "Description", with: "Monthly bus pass"
       click_button "Save Expense"
       assert_text "Expense was successfully created."
       assert_current_path "/dashboard"
       assert_text "Monthly bus pass"
     end

     test "user can navigate to expense list from dashboard" do
       visit "/users/sign_in"
       fill_in "Email", with: "test@example.com"
       fill_in "Password", with: "password123"
       click_button "Sign in"
       visit "/dashboard"
       click_link "View All Expenses"
       assert_current_path "/expenses"
       assert_text "All Expenses"
     end
   end
   
   Check constraints:
   - `visit "/path"` -> used correctly
   - `fill_in "Label", with: "value"` -> used correctly (note: explicitly NOT `fill_in with:`)
   - `select "Option", from: "Label"` -> used correctly
   - `click_button` / `click_link` -> used correctly
   - `assert_text` / `assert_selector` -> used correctly
   - `assert_current_path` -> used correctly
   - Realistic data -> used
   - Output ONLY Ruby code with test methods inside a class -> yes
   - No explanations -> yes

   One minor thing: The prompt says "Output ONLY the Ruby code with test methods." I'll wrap it in a class as requested. I'll make sure the syntax strictly matches the examples. The example shows `test "user can sign up" do ... end`. I'll follow that.

   I should ensure that the test methods are self-contained or assume a logged-in state appropriately. Since it's a system test, logging in each time is fine, or I could use `setup` but the prompt says "Output ONLY the test methods (inside a class)". I'll keep the login steps inside each test for simplicity and robustness, or I could just focus on dashboard interactions assuming auth is handled. The prompt example includes login steps, so I'll keep them.

   Let's verify the exact syntax requested:
   `fill_in "Label", with: "value"` (NOT fill_in with:) -> I used this.
   `select "Option", from: "Label"` -> I used this.
   `click_button "Button Text"` -> I used this.
   `assert_text "Expected text"` -> I used this.
   `assert_current_path "/expected/path"` -> I used this.

   All good. I will output exactly the Ruby code block.
   One thing: I'll make sure the class name is standard like `DashboardSystemTest < ApplicationSystemTestCase`.
   I'll remove any extra comments or explanations.
   Ready.✅
   Output matches response. 
   Proceeds. 
   Self-Correction/Refinement during thought: 
   The prompt says "Output ONLY the Ruby code with test methods." I will provide just the class with the tests. I'll make sure the formatting is exact. I'll also ensure that the `fill_in` syntax strictly matches `fill_in "Label", with: "value"`. All good.
   I will generate the code now. 
   Output matches the drafted code.✅
   Proceeds. 
   [Output Generation] -> *Proceeds*
   *(Self-Correction/Verification during drafting)*: 
   Check `fill_in` syntax: The prompt explicitly says `fill_in "Label", with: "value"` (NOT fill_in with:). My code uses `fill_in "Email", with: "test@example.com"`. This matches.
   Check `select` syntax: `select "Food & Dining", from: "Category"`. Matches.
   Check `click_button`: `click_button "Sign in"`. Matches.
   Check `assert_text`: `assert_text "Dashboard"`. Matches.
   Check `assert_current
end
