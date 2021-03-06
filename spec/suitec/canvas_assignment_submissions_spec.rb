require_relative '../../util/spec_helper'

include Logging

describe 'Canvas assignment submission', order: :defined do

  begin

    course_id = ENV['COURSE_ID']
    poller_retries = ENV['RETRIES'].to_i if ENV['RETRIES']
    test_id = Utils.get_test_id
    @course = Course.new({title: "Canvas Assignment Submissions #{test_id}"})
    @course.site_id = course_id

    # Load test data
    user_test_data = SuiteCUtils.load_suitec_test_data.select { |data| data['tests']['canvas_assignment_submissions'] }
    users = user_test_data.map { |user_data| User.new(user_data) }
    students = users.select { |user| user.role == 'Student' }
    @teacher = users.find { |user| user.role == 'Teacher' }

    @driver = Utils.launch_browser
    @canvas = Page::CanvasAssignmentsPage.new @driver
    @cal_net = Page::CalNetPage.new @driver
    @asset_library = Page::SuiteCPages::AssetLibraryDetailPage.new @driver
    @asset_library_manage = Page::SuiteCPages::AssetLibraryManageAssetsPage.new @driver
    @engagement_index = Page::SuiteCPages::EngagementIndexPage.new @driver

    # Create course site if necessary. If an existing site, then ensure Canvas sync is enabled.
    @canvas.log_in(@cal_net, Utils.super_admin_username, Utils.super_admin_password)
    @canvas.create_generic_course_site(Utils.canvas_qa_sub_account, @course, users, test_id, [LtiTools::ASSET_LIBRARY, LtiTools::ENGAGEMENT_INDEX])
    @asset_library_url = @canvas.click_tool_link(@driver, LtiTools::ASSET_LIBRARY)
    @engagement_index_url = @canvas.click_tool_link(@driver, LtiTools::ENGAGEMENT_INDEX)
    @asset_library.ensure_canvas_sync(@driver, @asset_library_url) unless course_id.nil?

    # Create assignment
    @assignment = Assignment.new({title: "Submission Assignment #{test_id}"})
    @canvas.masquerade_as(@teacher, @course)
    @canvas.create_assignment(@course, @assignment)

    # Enable Canvas assignment sync, then create another assignment. When the latter appears as a category, the former should have sync enabled.
    @asset_library_manage.wait_for_canvas_category(@driver, @asset_library_url, @assignment)
    @asset_library_manage.enable_assignment_sync @assignment
    poller_assignment = Assignment.new({title: "Throwaway Assignment #{test_id}"})
    @canvas.create_assignment(@course, poller_assignment)
    @asset_library_manage.wait_for_canvas_category(@driver, @asset_library_url, poller_assignment)
    @canvas.stop_masquerading

    # Submit assignment
    submissions = []
    expected_csv_rows = []
    students.each do |student|
      begin
        name = student.full_name
        @asset = Asset.new student.assets.first

        # Get user's score before submission
        @initial_score = @engagement_index.user_score(@driver, @engagement_index_url, student)

        # Submit assignment
        @canvas.masquerade_as(student, @course)
        @canvas.submit_assignment(@assignment, student, @asset)
        @canvas.stop_masquerading

        @asset.title = @asset_library.get_canvas_submission_title @asset
        asset_title = @asset.title
        submissions << [student, @asset, @initial_score]

      rescue => e
        logger.error "#{e.message + "\n"} #{e.backtrace.join("\n ")}"
        it("failed for #{name}'s submission '#{asset_title}'") { fail }
      end
    end

    # Verify assignment processed successfully in Asset Library and Engagement Index
    submissions.each do |submission|
      begin
        student = submission[0]
        student_full_name = student.full_name
        asset = submission[1]
        asset_title = asset.title
        asset.description = nil
        asset.category = @assignment.title

        # Check for updated Engagement Index score once submission is processed
        initial_score = submission[2]
        expected_score = initial_score.to_i + Activity::SUBMIT_ASSIGNMENT.points
        logger.debug "Checking submission for #{student_full_name} who uploaded #{asset_title} and should now have a score of #{expected_score}"

        score_updated = @engagement_index.user_score_updated?(@driver, @engagement_index_url, student, "#{expected_score}", poller_retries)

        it("earns 'Submit an Assignment' points on the Engagement Index for #{student_full_name}") { expect(score_updated).to be true }

        expected_csv_rows << "#{student_full_name}, submit_assignment, #{Activity::SUBMIT_ASSIGNMENT.points}, #{expected_score}"

        # Check that submission is added to Asset Library with right metadata
        @asset_library.load_page(@driver, @asset_library_url)
        @asset_library.advanced_search(nil, asset.category, student, asset.type, nil)
        @asset_library.wait_until(Utils.short_wait) { @asset_library.list_view_asset_elements.length == 1 }

        file_uploaded = @asset_library.verify_block { @asset_library.verify_first_asset(student, asset) }
        preview_generated = @asset_library.preview_generated?(@driver, @asset_library_url, asset, student)

        it("appears in the Asset Library for #{student_full_name}") { expect(file_uploaded).to be true }
        it("generate the expected asset preview for #{student_full_name} uploading #{asset_title}") { expect(preview_generated).to be true }

        if asset.type == 'File'
          asset_downloadable = @asset_library.verify_block { @asset_library.download_asset asset }
          it("can be downloaded by #{student_full_name} from the #{asset_title} asset detail page") { expect(asset_downloadable).to be true }
        else
          has_download_button = @asset_library.download_asset_link?
          it("cannot be downloaded by #{student_full_name} from the #{asset_title} detail page") { expect(has_download_button).to be false }
        end

      rescue => e
        logger.error "#{e.message + "\n"} #{e.backtrace.join("\n ")}"
        it("caused an unexpected error checking #{student_full_name}'s submission in SuiteC") { fail }
      end
    end

    # Check that all activity is included in CSV download
    scores = @engagement_index.download_csv(@driver, @course, @engagement_index_url)
    expected_csv_rows.each do |row|
      it("shows #{row} on the CSV export") { expect(scores).to include(row) }
    end




  rescue => e
    # Catch and report errors related to the whole test
    logger.error "#{e.message + "\n"} #{e.backtrace.join("\n ")}"
    it('caused an unexpected error handling the UI') { fail }
  ensure
    @driver.quit
  end

end
