require "application_system_test_case"

class DevAddMonthlyReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  <think>
The user wants a Capybara system test for a feature called "Add Monthly Reports" in an Expense Tracker app.
I need to write a Ruby test method following specific conventions:
- Use `visit`, `fill_in`, `select`, `click_button`, `assert_text`, `assert_current_path`.
- Use realistic data (emails, passwords).
- Output only the Ruby code.

Let's imagine the flow for adding a monthly report:
1.  User logs in (or is already logged in). Since the prompt asks for the specific feature "Add Monthly Reports", I should probably start by visiting the reports page or the "New Report" page.
2.  Fill in details for the report (e.g., Month, Year, Total Expenses, Description).
3.  Submit the form.
4.  Verify success message and navigation.

Let's assume a standard Rails resource structure:
- Path: `/monthly_reports` (index) or `/monthly_reports/new` (new).
- Form fields: "Month", "Year", "Total amount", "Notes".
- Button: "Create Monthly report" or "Save".

Let's construct the test.

Test Name: `user can add a monthly report`

Steps:
1.  `visit "/monthly_reports/new"`
2.  `fill_in "Month", with: "October"` (or select from dropdown)
3.  `fill_in "Year", with: "2023"`
4.  `fill_in "Total amount", with: "1500.50"`
5.  `fill_in "Notes", with: "Rent and groceries"`
6.  `click_button "Create Monthly report"`
7.  `assert_text "Monthly report was successfully created."`
8.  `assert_current_path "/monthly_reports/1"` (assuming ID 1)

Wait, the prompt mentions "Dev: Add Monthly Reports". It might be a task management context or just the feature name. Given "Expense Tracker app", it's likely the feature to add a report.

Let's refine the fields to be generic but realistic for an expense tracker.
- Month (Select)
- Year (Select or Text)
- Total Expenses (Number)
- Description (Text)

Let's write the code.

test "user can add a monthly report" do
  visit "/monthly_reports/new"
  select "October", from: "Month"
  select "2023", from: "Year"
  fill_in "Total expenses", with: "2500.00"
  fill_in "Description", with: "Monthly household expenses"
  click_button "Create Monthly report"
  assert_text "Monthly report was successfully created."
  assert_current_path "/monthly_reports/1"
end

I should probably include a login step if it's a protected route, but usually, these snippets focus on the specific feature interaction. However, to be safe and "realistic", I'll stick to the specific interaction requested. If the prompt implies a full flow, I might add a login, but usually, "Generate a test for: [Feature]" implies testing that specific feature's UI.

Let's check the constraints again.
- `fill_in "Label", with: "value"`
- `select "Option", from: "Label"`
- `click_button "Button Text"`
- `assert_text`
- `assert_current_path`

I will provide a test that navigates to the new report page, fills it out, and submits it.

One detail: The prompt asks for "Dev: Add Monthly Reports". This sounds like a task title. The description is "Task for Expense Tracker app".
So the feature is adding a report.

Let's assume the user is already logged in or the test focuses on the form interaction.

test "user can add a monthly report" do
  visit "/monthly_reports/new"
  
  select "October", from: "Month"
  select "2023", from: "Year"
  fill_in "Total amount", with: "1250.75"
  fill_in "Notes", with: "Rent, utilities, and groceries"
  
  click_button "Create Monthly report"
  
  assert_text "Monthly report was successfully created."
  assert_current_path "/monthly_reports/1"
end

I will output just the code block.

Wait, looking at the example provided:
test "user can sign up" do
  visit "/users/sign_up"
  ...
end
It's a single test method.

I will write a test method named `test "user can add a monthly report"`.

Let's refine the field labels to be very standard.
- "Month"
- "Year"
- "Total amount"
- "Description"

And the button "Create Monthly report".

Final check of the prompt requirements:
- "Output ONLY the Ruby code with test methods."
- "Output ONLY the test methods (inside a class), no explanations." -> Actually, the prompt says "Output ONLY the Ruby code with test methods" in the first line, and "Output ONLY the test methods (inside a class), no explanations" at the end. It implies I should wrap it in a class or just provide the method? The example shows just the `test "..." do ... end` block. I will provide the method block.

Actually, looking at the example:
test "user can sign up" do
  ...
end
It's just the method.

Let's double check the prompt: "Output ONLY the test methods (inside a class)". This is slightly ambiguous. Does it mean `class MyTest < ApplicationSystemTestCase ... end` or just the method content? The example shows just the method. I will provide the method.

Wait, "Output ONLY the test methods (inside a class)" might mean the output should look like it belongs inside a class, but not necessarily include the class definition if the example doesn't. The example *doesn't* have the class definition. I will follow the example format.

Let's create a slightly more complex scenario if needed, but a simple happy path is usually best for these prompts.

Test:
1. Visit new report path.
2. Select Month.
3. Select Year.
4. Fill in Total.
5. Fill in Description.
6. Click Create.
7. Assert success.
8. Assert path.

test "user can add a monthly report" do
  visit "/monthly_reports/new"
  select "October", from: "Month"
  select "2023", from: "Year"
  fill_in "Total amount", with: "1500.50"
  fill_in "Description", with: "Monthly expenses for rent and food"
  click_button "Create Monthly report"
  assert_text "Monthly report was successfully created."
  assert_current_path "/monthly_reports/1"
end

I'll stick to this. It's clean and follows all rules.

One variation: Maybe the user needs to log in first? The prompt doesn't specify authentication, but "Expense Tracker" usually requires it. However, without a login test provided or requested, adding a login block might clutter the specific feature test. I'll stick to the feature logic.

Let's check if there are any other specific constraints. "Dev: Add Monthly Reports" is the title.
Maybe the path is `/reports`? `/monthly_reports` is more RESTful.
Maybe the button is "Save"? "Create Monthly report" is standard Rails.

I will use standard Rails conventions.

One more check: "Output ONLY the test methods (inside a class)".
If I output just the method, it is technically "inside a class" contextually, but syntactically it's just a method definition. If I output the class, it might violate the "Example format" which didn't show the class. I will follow the example format.

Wait, the prompt says "Output ONLY the test methods (inside a class)". This might be a directive to ensure the code is valid Ruby code that would go inside a class, but not necessarily to output the `class` keyword. The example is the strongest hint.

Let's refine the test data.
Email: test@example.com (not used here unless logging in)
Password: password123 (not used here)
Realistic data for report:
Month: November
Year: 2023
Amount: 3200.00
Description: Housing and transport costs.

test "user can add a monthly report" do
  visit "/monthly_reports/new"
  select "November", from: "Month"
  select "2023", from: "Year"
  fill_in "Total amount", with: "3200.00"
  fill_in "Description", with: "Housing and transport costs"
  click_button "Create Monthly report"
  assert_text "Monthly report was successfully created."
  assert_current_path "/monthly_reports/1"
end
This looks good.

One edge case: Maybe the form has a "Category" select?
"Expense Tracker" -> Categories are common.
But "Monthly Report" usually aggregates expenses.
I'll stick to the simpler fields to avoid guessing too much about the schema.

Final check on syntax:
`fill_in "Label", with: "value"`
end
