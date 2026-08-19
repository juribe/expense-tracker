require "application_system_test_case"

class DevAddMonthlyReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  <think>
Here's a thinking process:

1.  **Analyze User Input:**
   - **Role:** QA Engineer
   - **Task:** Write Capybara system tests for "Dev: Add Monthly Reports" in an Expense Tracker app
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
   - **Context:** Expense Tracker app, specifically "Add Monthly Reports" feature. This likely involves creating/viewing monthly expense reports, possibly selecting a month/year, adding expenses, generating a report, etc.

2.  **Identify Key Test Scenarios for "Add Monthly Reports":**
   - User visits the monthly reports page
   - User fills in report details (month, year, title/description, maybe total amount)
   - User submits the form
   - System confirms success and navigates to the report list or details page
   - User can view the newly created report
   - Edge cases/validations (optional but good for realism, though I'll stick to the main happy path as requested)

   Let's design a realistic flow:
   - Visit `/monthly_reports` or `/monthly_reports/new`
   - Fill in form fields: "Report title", "Month", "Year", "Description"
   - Select month/year from dropdowns
   - Click "Create Monthly Report"
   - Assert success message
   - Assert current path
   - Assert the report appears in the list

3.  **Draft Test Methods (Mental Refinement):**
      test "user can create a new monthly report" do
     visit "/monthly_reports/new"
     fill_in "Report title", with: "January 2024 Expenses"
     select "January", from: "Month"
     select "2024", from: "Year"
     fill_in "Description", with: "Monthly expense summary for travel and utilities."
     click_button "Create Monthly Report"
     assert_text "Monthly report was successfully created."
     assert_current_path "/monthly_reports/1"
   end

   test "user can view monthly reports list" do
     visit "/monthly_reports"
     assert_text "Monthly Reports"
     assert_selector "table"
   end

   test "user can edit an existing monthly report" do
     visit "/monthly_reports/1/edit"
     fill_in "Report title", with: "Updated January 2024 Expenses"
     click_button "Update Monthly Report"
     assert_text "Monthly report was successfully updated."
     assert_current_path "/monthly_reports/1"
   end
   
   Wait, the prompt says "Add Monthly Reports" specifically. I should focus on the creation/addition flow. I'll make sure the test covers visiting the new report page, filling out the form, submitting, and verifying. I'll also add a test for viewing the list after creation, and maybe one for validation if needed, but I'll stick to the core requirement.

   Let's align strictly with the prompt's formatting and constraints:
   - Must use `fill_in "Label", with: "value"`
   - Must use `select "Option", from: "Label"`
   - Must use `click_button`/`click_link`
   - Must use `assert_text`/`assert_selector`
   - Must use `assert_current_path`
   - Realistic data
   - Output ONLY Ruby code with test methods inside a class.

   I'll wrap it in a standard Rails system test class structure:
      class MonthlyReportsSystemTest < ApplicationSystemTestCase
     # tests here
   end
   
   Let's craft the tests carefully.

   Test 1: Create a monthly report
   Test 2: View monthly reports list
   Test 3: Edit a monthly report (optional but good)
   Test 4: Delete a monthly report (optional)

   I'll stick to 2-3 focused tests for "Add Monthly Reports" to keep it concise and relevant.

   Refined Test 1:
      test "user can add a new monthly report" do
     visit "/monthly_reports/new"
     fill_in "Report title", with: "March 2024 Budget Summary"
     select "March", from: "Month"
     select "2024", from: "Year"
     fill_in "Total amount", with: "1250.75"
     fill_in "Notes", with: "Includes rent, groceries, and utilities."
     click_button "Create Monthly Report"
     assert_text "Monthly report was successfully created."
     assert_current_path "/monthly_reports/1"
   end
   
   Refined Test 2:
      test "user can view the monthly reports index" do
     visit "/monthly_reports"
     assert_text "Monthly Reports"
     assert_selector "table"
     assert_text "March 2024 Budget Summary"
   end
   
   Refined Test 3 (Validation/Empty):
      test "user cannot create a monthly report without required fields" do
     visit "/monthly_reports/new"
     click_button "Create Monthly Report"
     assert_text "can't be blank"
     assert_current_path "/monthly_reports/new"
   end
   
   Check constraints:
   - `visit "/path"` -> used
   - `fill_in "Label", with: "value"` -> used exactly as specified
   - `select "Option", from: "Label"` -> used exactly
   - `click_button "Button Text"` -> used
   - `assert_text "Expected text"` -> used
   - `assert_current_path "/expected/path"` -> used
   - Realistic data -> used
   - Output ONLY Ruby code with test methods inside a class -> will wrap in class
   - No explanations -> will output only code

   One minor thing: The prompt says "Output ONLY the Ruby code with test methods." It doesn't strictly require the class definition, but says "inside a class". I'll include the class wrapper.

   Let's ensure the syntax matches exactly:
   `fill_in "Label", with: "value"` (NOT `fill_in with:`) - checked.
   `select "Option", from: "Label"` - checked.
   `click_button "Button Text"` - checked.
   `assert_text "Expected text"` - checked.
   `assert_current_path "/expected/path"` - checked.

   I'll write it out carefully.
   I'll make sure the test names and paths are realistic for an Expense Tracker app.
   Paths: `/monthly_reports`, `/monthly_reports/new`, `/monthly_reports/:id`
   Labels: "Report title", "Month", "Year", "Total amount", "Notes", "Create Monthly Report"
   All good.

   Final check of the prompt: "Output ONLY the Ruby code with test methods. (inside a class), no explanations."
   I will output exactly that.
   Structure:
      class MonthlyReportsSystemTest < ApplicationSystemTestCase
     test "user can add a new monthly report" do
       ...
     end

     test "user can view monthly reports list" do
       ...
     end

     test "user cannot create a monthly report without required fields" do
       ...
     end
   end
      Matches all constraints. Ready.✅
   Output matches response. 
   One detail: The prompt says "fill_in "Label", with: "value" (NOT fill_in with:)". This is just emphasizing the syntax. I'll stick to it.
   All good. Proceeds. 
   Output generation. 
   [Self-Correction/Verification during thought]
   - Check if I need to include setup/factories? The prompt says "Output ONLY the Ruby code with test methods." I'll assume standard Rails system test context where records might be pre-created or created via the UI. I'll stick to UI interactions only as requested.
   - I'll make sure the class name is appropriate: `MonthlyReportsSystemTest < ApplicationSystemTestCase`
   - I'll ensure no markdown outside the code block if possible, but the prompt says "Output ONLY the Ruby code with test methods." I'll just output the code block.
   - All constraints met.
   Proceeds. 
   Output matches the final refined version. 
   [Output Generation] -> *Proceeds*
      class MonthlyReportsSystemTest < ApplicationSystemTestCase
     test "user can add a new monthly report" do
       visit "/monthly_reports/new"
       fill_in "Report title", with: "March 2024 Budget Summary"
       select "March", from: "Month"
       select "2024", from: "Year"
       fill_in "Total amount", with: "1250.
end
