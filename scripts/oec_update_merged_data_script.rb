require_relative '../util/spec_helper'

# In order to publish a large number of course-instructor pairs to the OEC validate / publish tasks:
# - identifies departments that should be represented in the merged supervisors file but are missing, which will cause validation errors
# - edits merged course data row-by-row, setting as many as possible to 'evaluate = y' with data that will pass validation

begin

  OecUtils.prepare_dept_confirmation OECDepartments::THEATER
  OecUtils.prepare_merged_confirmations

end
