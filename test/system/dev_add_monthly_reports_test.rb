require "application_system_test_case"

class DevAddMonthlyReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  <think>
Here's a thinking process:

1.  **Analyze User Input:**
   - **Role:** QA Engineer
   - **Task:** Write Capybara system tests for "Dev: Add Monthly Reports" in an Expense Tracker app.
   - **Requirements:**
     - Use `visit "/path"`
     - Use `fill_in "Label", with: "value"` (explicitly NOT `fill_in with:`)
     - Use `select "Option", from: "Label"`
     - Use `click_button "Button Text"` or `click_link "Link Text"`
     - Use `assert_text "Expected text"` or `assert_selector "css"`
     - Use `assert_current_path "/expected/path"`
     - Use realistic test data (email: "test@example.com", password: "password123")
     - Output ONLY Ruby code with test methods (inside a class)
     - No explanations

2.  **Identify Key Features for "Monthly Reports" in an Expense Tracker:**
   - User needs to be logged in first (or the test assumes authentication, but I'll include a login step or assume a session exists. I'll stick to the prompt's focus on the monthly reports feature, but might need to simulate login or just start at the reports page. I'll assume the user is already logged in or include a quick login step if needed. Actually, system tests often start with `visit "/monthly_reports"` or similar. I'll focus on the core feature: creating/viewing monthly reports.)
   - Features to test:
     - Navigate to monthly reports page
     - Create a new monthly report (select month/year, add expenses, save)
     - View generated report
     - Verify report details
     - Maybe edit/delete? The prompt says "Add Monthly Reports", so focus on creation and viewing.
   - I'll create a few test methods covering:
     1. User can view monthly reports index
     2. User can create a new monthly report
     3. User can view a specific monthly report
     4. User can filter reports by month/year

3.  **Draft Test Methods (Mental Refinement):**
   Need to follow the exact syntax requested.
   - `visit "/monthly_reports"`
   - `fill_in "Month", with: "January"`
   - `fill_in "Year", with: "2024"`
   - `select "January", from: "Month"` (if it's a dropdown)
   - `click_button "Generate Report"`
   - `assert_text "Monthly Report for January 2024"`
   - `assert_current_path "/monthly_reports/1"` (or similar)

   Let's structure it as a standard Rails system test class:
      class MonthlyReportsTest < ApplicationSystemTestCase
     setup do
       # Assume user is logged in or create a user/session
       @user = users(:one)
       login_as(@user) # or just visit directly if auth isn't the focus
     end

     test "user can view monthly reports index" do
       visit "/monthly_reports"
       assert_text "Monthly Reports"
       assert_selector "table"
     end

     test "user can create a new monthly report" do
       visit "/monthly_reports/new"
       select "January", from: "Month"
       select "2024", from: "Year"
       fill_in "Title", with: "January Expenses"
       fill_in "Description", with: "Monthly expense summary"
       click_button "Create Monthly Report"
       assert_text "Monthly report was successfully created."
       assert_current_path "/monthly_reports/1"
     end

     test "user can view a specific monthly report" do
       visit "/monthly_reports/1"
       assert_text "January 2024"
       assert_text "Total Expenses"
       assert_selector "#report-summary"
     end

     test "user can filter reports by month and year" do
       visit "/monthly_reports"
       select "February", from: "Filter Month"
       select "2024", from: "Filter Year"
       click_button "Filter"
       assert_text "February 2024"
       assert_current_path "/monthly_reports?month=2&year=2024"
     end
   end
   
4.  **Check Against Constraints:**
   - Visits pages using `visit "/path"`? Yes.
   - Types in forms using `fill_in "Label", with: "value"`? Yes.
   - Selects options using `select "Option", from: "Label"`? Yes.
   - Clicks buttons using `click_button "Button Text"`? Yes.
   - Verifies content using `assert_text` or `assert_selector`? Yes.
   - Verifies navigation using `assert_current_path`? Yes.
   - Realistic test data? Used month/year, title, description. I should add email/password if needed, but the prompt says "For emails use...". I'll include a login test or assume auth. Actually, I'll just stick to the monthly reports feature. I'll add a quick login step if needed, but the prompt says "Use realistic test data. For emails use...". I'll incorporate it into a setup or a test that logs in first, or just use it in a form if applicable. Since it's an expense tracker, maybe the report form doesn't need email/password. I'll just follow the prompt's example format and focus on the monthly reports. I'll add a test that logs in first to be safe, or just assume the session is active. The prompt says "IMPORTANT: Use realistic test data. For emails use "test@example.com", for passwords use "password123"." I'll make sure at least one test uses these if relevant, or I'll just include a login step in setup. Actually, I'll just write the tests as requested, focusing on the monthly reports feature. I'll add a test for signing in if needed, but the prompt is specifically for "Add Monthly Reports". I'll stick to that.

   Let's refine the tests to strictly match the requested syntax and ensure they are self-contained within a class. I'll use standard Rails system test structure.

   I'll make sure every constraint is met:
   - `visit "/monthly_reports"`
   - `fill_in "Report Title", with: "January 2024 Summary"`
   - `select "January", from: "Month"`
   - `click_button "Create Report"`
   - `assert_text "Report created successfully"`
   - `assert_current_path "/monthly_reports/1"`

   I'll write 3-4 test methods covering index, new, show, and maybe edit/filter.

   Let's draft carefully:

      class MonthlyReportsSystemTest < ApplicationSystemTestCase
     setup do
       @user = users(:one)
       visit "/users/sign_in"
       fill_in "Email", with: "test@example.com"
       fill_in "Password", with: "password123"
       click_button "Log in"
     end

     test "user can view monthly reports index" do
       visit "/monthly_reports"
       assert_text "Monthly Reports"
       assert_selector "table.reports-table"
     end

     test "user can create a new monthly report" do
       visit "/monthly_reports/new"
       select "January", from: "Month"
       select "2024", from: "Year"
       fill_in "Report Title", with: "January 2024 Expenses"
       fill_in "Description", with: "Summary of all monthly expenditures"
       click_button "Create Monthly Report"
       assert_text "Monthly report was successfully created."
       assert_current_path "/monthly_reports/1"
     end

     test "user can view a specific monthly report" do
       visit "/monthly_reports/1"
       assert_text "January 2024 Expenses"
       assert_text "Total: $1,250.00"
       assert_selector "#report-details"
     end

     test "user can filter monthly reports by date" do
       visit "/monthly_reports"
       select "February", from: "Filter Month"
       select "2024", from: "Filter Year"
       click_button "Apply Filter"
       assert_text "February 2024"
       assert_current_path "/monthly_reports?month=2&year=2024"
     end
   end
   
   Check constraints:
   - `visit "/path"` -> used
   - `fill_in "Label", with: "value"` -> used
   - `select "Option", from: "Label"` -> used
   - `click_button "Button Text"` -> used
   - `assert_text "Expected text"` / `assert_selector "css"` -> used
   - `assert_current_path "/expected/path"` -> used
   - Realistic data: email/password in setup, plus report data
   - Output ONLY Ruby code with test methods inside a class
   - No explanations

   One minor thing: The prompt says "fill_in "Label", with: "value" (NOT fill_in with:)". I used `fill_in "Email", with: "test@example.com"` which matches.
   I'll make sure the class name is appropriate. `MonthlyReportsSystemTest` is fine.
end
