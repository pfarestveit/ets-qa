require_relative '../../util/spec_helper'

describe 'BOA' do

  before(:all) do
    dept = BOACDepartments::L_AND_S
    @other_dept = BOACDepartments::DEPARTMENTS.find { |d| ![dept, BOACDepartments::ADMIN].include? d }
    authorized_users = BOACUtils.get_authorized_users
    @test = BOACTestConfig.new
    @test.drop_in_appts(authorized_users, dept)

    @drop_in_advisors = authorized_users.select do |a|
      a.advisor_roles.find { |r| r.dept == @test.dept && r.is_drop_in_advisor }
    end

    @student = @test.students.shuffle.first

    @appts = []
    @appt_0 = Appointment.new(student: @student, topics: [Topic::COURSE_ADD, Topic::COURSE_DROP], detail: "Drop-in advisor appointment creation #{@test.id}")
    @appt_1 = Appointment.new(student: @student, topics: [Topic::RETROACTIVE_ADD, Topic::RETROACTIVE_DROP], detail: "Drop-in appointment details #{@test.id}")
    @appt_2 = Appointment.new(student: @student, topics: [Topic::PROBATION], detail: "Scheduler check-in 1 #{@test.id}")
    @appt_3 = Appointment.new(student: @student, topics: [Topic::OTHER], detail: "Scheduler check-in 2 #{@test.id}")
    @appt_4 = Appointment.new(student: @student, topics: [Topic::PROBATION], detail: "Drop-in advisor waiting list check-in 1 #{@test.id}")
    @appt_5 = Appointment.new(student: @student, topics: [Topic::OTHER], detail: "Drop-in advisor waiting list check-in 2 #{@test.id}")
    @appt_6 = Appointment.new(student: @student, topics: [Topic::EXCESS_UNITS], detail: "Drop-in advisor student page check-in 1 #{@test.id}" )
    @appt_7 = Appointment.new(student: @student, topics: [Topic::READMISSION], detail: "Scheduler cancel #{@test.id}")
    @appt_8 = Appointment.new(student: @student, topics: [Topic::WITHDRAWAL], detail: "Drop-in advisor waiting list cancel #{@test.id}")
    @appt_9 = Appointment.new(student: @student, topics: [Topic::OTHER], detail: "Drop-in advisor student page cancel #{@test.id}")

    @driver_scheduler = Utils.launch_browser
    @scheduler_homepage = BOACHomePage.new @driver_scheduler
    @scheduler_intake_desk = BOACApptIntakeDeskPage.new @driver_scheduler

    @driver_advisor = Utils.launch_browser
    @advisor_homepage = BOACHomePage.new @driver_advisor
    @advisor_appt_desk = BOACApptIntakeDeskPage.new @driver_advisor
    @advisor_student_page = BOACStudentPage.new @driver_advisor
  end

  after(:all) do
    Utils.quit_browser @driver_scheduler
    Utils.quit_browser @driver_advisor
  end

  ### PERMISSIONS - SCHEDULER

  context 'when the user is a scheduler' do

    before(:all) { @scheduler_homepage.dev_auth @test.drop_in_scheduler }

    it 'drops the user onto the drop-in intake desk at login' do
      expect(@scheduler_homepage.title).to include('Drop-in Appointments Desk')
      @scheduler_intake_desk.new_appt_button_element.when_visible Utils.short_wait
    end

    # The following should direct to a 404, but atm directs to a blank page
    it 'prevents the user from accessing a drop-in intake desk belonging to another department' do
      @scheduler_intake_desk.load_page @other_dept
      sleep 3
      expect(@scheduler_intake_desk.new_appt_button?).to be false
      # TODO @appt_desk.wait_for_title 'Page not found'
    end

    it 'prevents the user from accessing a page other than the drop-in intake desk' do
      @scheduler_intake_desk.navigate_to "#{BOACUtils.base_url}/student/#{@student.uid}"
      @scheduler_intake_desk.wait_for_title 'Not Found'
    end

    # TODO user cannot get to any boa API endpoints other than drop-in endpoints
  end

  ### PERMISSIONS - DROP-IN ADVISOR

  context 'when the user is a drop-in advisor' do

    before(:all) { @advisor_homepage.dev_auth @test.drop_in_advisor }
    after(:all) { @advisor_homepage.log_out }

    it 'drops the user onto the homepage at login with a waiting list' do
      expect(@advisor_homepage.title).to include('Home')
      @advisor_homepage.new_appt_button_element.when_visible Utils.short_wait
    end

    it 'prevents the user from accessing the department drop-in intake desk' do
      @advisor_appt_desk.load_page @test.dept
      @advisor_appt_desk.wait_for_title 'Page not found'
    end

    it 'prevents the user from accessing a drop-in intake desk belonging to another department' do
      @advisor_appt_desk.load_page @other_dept
      @advisor_appt_desk.wait_for_title 'Page not found'
    end
  end

  ### PERMISSIONS - NON-DROP-IN ADVISOR

  context 'when the user is a non-drop-in advisor' do

    before(:all) { @advisor_homepage.dev_auth @test.advisor }
    after(:all) { @advisor_appt_desk.log_out }

    it 'drops the user onto the homepage at login with no waiting list' do
      expect(@advisor_appt_desk.title).to include('Home')
      sleep 2
      expect(@advisor_appt_desk.new_appt_button?).to be false
    end

    it 'prevents the user from accessing the department drop-in intake desk' do
      @advisor_appt_desk.load_page @test.dept
      @advisor_appt_desk.wait_for_title 'Page not found'
    end
  end

  ### PERMISSIONS - ADMIN

  context 'when the user is an admin' do

    before(:all) { @advisor_homepage.dev_auth }
    after(:all) { @advisor_homepage.log_out }

    it 'drops the user onto the homepage at login with no waiting list' do
      expect(@advisor_homepage.title).to include('Home')
      sleep 2
      expect(@advisor_homepage.new_appt_button?).to be false
    end

    it 'allows the user to access any department\'s drop-in intake desk' do
      @advisor_appt_desk.load_page @test.dept
      @advisor_appt_desk.new_appt_button_element.when_visible Utils.short_wait
      @advisor_appt_desk.load_page @other_dept
      @advisor_appt_desk.new_appt_button_element.when_visible Utils.short_wait
    end
  end

  ### DROP-IN APPOINTMENT CREATION

  describe 'drop-in appointment creation' do

    # Scheduler

    context 'on the intake desk' do

      before(:all) do
        @scheduler_intake_desk.load_page @test.dept
        existing_appts = BOACUtils.get_today_drop_in_appts(@test.dept, @test.students).select { |a| !a.deleted_date }
        BOACUtils.delete_appts existing_appts
      end

      it 'shows a No Appointments message when there are no appointments' do
        @scheduler_intake_desk.empty_wait_list_msg_element.when_visible Utils.medium_wait
        expect(@scheduler_intake_desk.empty_wait_list_msg.strip).to eql('No appointments yet')
      end

      it 'allows a scheduler to create but cancel a new appointment' do
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.click_cancel_new_appt
      end

      it 'requires a scheduler to select a student for a new appointment' do
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.choose_reasons [Topic::CAREER_PLANNING]
        @scheduler_intake_desk.enter_detail 'Some detail'
        expect(@scheduler_intake_desk.make_appt_button_element.disabled?).to be true
        @scheduler_intake_desk.choose_student @test.students.first
        expect(@scheduler_intake_desk.make_appt_button_element.disabled?).to be false
      end

      it 'requires a scheduler to select a reason for a new appointment' do
        @scheduler_intake_desk.hit_escape
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.choose_student @test.students.first
        @scheduler_intake_desk.enter_detail 'Some detail'
        expect(@scheduler_intake_desk.make_appt_button_element.disabled?).to be true
        @scheduler_intake_desk.choose_reasons [Topic::CAREER_PLANNING]
        expect(@scheduler_intake_desk.make_appt_button_element.disabled?).to be false
      end

      it 'shows a scheduler the right reasons for a new appointment' do
        @scheduler_intake_desk.hit_escape
        @scheduler_intake_desk.click_new_appt
        expected_topics = Topic::TOPICS.select(&:for_appts).map &:name
        @scheduler_intake_desk.wait_until(1, "Expected #{expected_topics}, got #{@scheduler_intake_desk.new_appt_reasons}") do
          @scheduler_intake_desk.new_appt_reasons == expected_topics
        end
      end

      it 'requires a scheduler to enter details for a new appointment' do
        @scheduler_intake_desk.hit_escape
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.choose_student @test.students.first
        @scheduler_intake_desk.choose_reasons [Topic::CAREER_PLANNING]
        expect(@scheduler_intake_desk.make_appt_button_element.disabled?).to be true
        @scheduler_intake_desk.enter_detail 'Some detail'
        expect(@scheduler_intake_desk.make_appt_button_element.disabled?).to be false
      end

      it 'allows a scheduler to create a new appointment' do
        appt = Appointment.new(student: @student,
                               topics: [Topic::COURSE_ADD, Topic::COURSE_DROP],
                               detail: "Scheduler appointment creation #{@test.id} detail")
        @scheduler_intake_desk.hit_escape
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.create_appt appt
        expect(appt.id).not_to be_nil
      end
    end

    # Drop-in Advisor

    context 'on the waiting list' do

      before(:all) do
        existing_appts = BOACUtils.get_today_drop_in_appts(@test.dept, @test.students)
        BOACUtils.delete_appts existing_appts
        @advisor_homepage.dev_auth @test.drop_in_advisor
      end

      it 'shows a No Appointments message when there are no appointments' do
        @advisor_homepage.empty_wait_list_msg_element.when_visible Utils.medium_wait
        expect(@advisor_homepage.empty_wait_list_msg.strip).to eql('No appointments yet')
      end

      it 'updates the scheduler appointment desk with a No Appointments message when there are no appointments' do
        @scheduler_intake_desk.wait_for_poller { @scheduler_intake_desk.empty_wait_list_msg? }
      end

      it 'allows a drop-in advisor to create but cancel a new appointment' do
        @advisor_homepage.click_new_appt
        @advisor_homepage.click_cancel_new_appt
      end

      it 'requires a drop-in advisor to select a student for a new appointment' do
        @advisor_homepage.click_new_appt
        @advisor_homepage.choose_reasons [Topic::CAREER_PLANNING]
        @advisor_homepage.enter_detail 'Some detail'
        expect(@advisor_homepage.make_appt_button_element.disabled?).to be true
        @advisor_homepage.choose_student @test.students.first
        expect(@advisor_homepage.make_appt_button_element.disabled?).to be false
      end

      it 'requires a drop-in advisor to select a reason for a new appointment' do
        @advisor_homepage.hit_escape
        @advisor_homepage.click_new_appt
        @advisor_homepage.choose_student @test.students.first
        @advisor_homepage.enter_detail 'Some detail'
        expect(@advisor_homepage.make_appt_button_element.disabled?).to be true
        @advisor_homepage.choose_reasons [Topic::CAREER_PLANNING]
        expect(@advisor_homepage.make_appt_button_element.disabled?).to be false
      end

      it 'shows a drop-in advisor the right reasons for a new appointment' do
        @advisor_homepage.hit_escape
        @advisor_homepage.click_new_appt
        expected_topics = Topic::TOPICS.select(&:for_appts).map &:name
        @advisor_homepage.wait_until(1, "Expected #{expected_topics}, got #{@advisor_homepage.new_appt_reasons}") do
          @advisor_homepage.new_appt_reasons == expected_topics
        end
      end

      it 'requires a drop-in advisor to enter details for a new appointment' do
        @advisor_homepage.hit_escape
        @advisor_homepage.click_new_appt
        @advisor_homepage.choose_student @test.students.first
        @advisor_homepage.choose_reasons [Topic::CAREER_PLANNING]
        expect(@advisor_homepage.make_appt_button_element.disabled?).to be true
        @advisor_homepage.enter_detail 'Some detail'
        expect(@advisor_homepage.make_appt_button_element.disabled?).to be false
      end

      it 'allows a drop-in advisor to create a new appointment' do
        @advisor_homepage.hit_escape
        @advisor_homepage.click_new_appt
        @advisor_homepage.create_appt @appt_0
        expect(@appt_0.id).not_to be_nil
        @appts << @appt_0
      end

      it 'updates the scheduler appointment desk when a new appointment is created' do
        @scheduler_intake_desk.wait_for_poller { @scheduler_intake_desk.visible_appt_ids.include? @appt_0.id }
      end
    end
  end

  ### DROP-IN APPOINTMENT DETAILS

  describe '"waiting" drop-in appointment details' do

    # Scheduler

    context 'on the appointment intake desk' do

      before(:all) do
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.create_appt @appt_1
        @appts << @appt_1
        @scheduler_intake_desk.wait_until(Utils.short_wait) { @scheduler_intake_desk.visible_appt_ids.include? @appt_1.id }
        @visible_list_view_appt_data = @scheduler_intake_desk.visible_list_view_appt_data @appt_1
      end

      after(:all) { @scheduler_intake_desk.hit_escape }

      it('show the arrival time') { expect(@visible_list_view_appt_data[:created_date]).to eql(@scheduler_intake_desk.appt_time_created_format(@appt_1.created_date).strip) }
      it('show the student name') { expect(@visible_list_view_appt_data[:student_non_link_name]).to eql(@appt_1.student.full_name) }
      it('show no link to the student page') { expect(@visible_list_view_appt_data[:student_link_name]).to be_nil }
      it('show the student SID') { expect(@visible_list_view_appt_data[:student_sid]).to eql(@appt_1.student.sis_id) }
      it('show the appointment reason(s)') { expect(@visible_list_view_appt_data[:topics]).to eql(@appt_1.topics.map(&:name).sort) }

      it('allow the scheduler to expand an appointment\'s details') { @scheduler_intake_desk.view_appt_details @appt_1 }
      it('show the student name') { expect(@scheduler_intake_desk.details_student_name).to eql(@appt_1.student.full_name) }
      it('show the appointment reason(s)') { expect(@scheduler_intake_desk.topics_from_string @scheduler_intake_desk.modal_topics).to eql(@appt_1.topics.map(&:name).sort) }
      it('show the arrival time') { expect(@scheduler_intake_desk.modal_created_at).to eql(@scheduler_intake_desk.appt_time_created_format(@appt_1.created_date).strip) }
      it('show the appointment detail') { expect(@scheduler_intake_desk.modal_details).to eql(@appt_1.detail) }
    end

    # Drop-in Advisor

    context 'on the waiting list' do

      before(:all) do
        @advisor_homepage.refresh
        @advisor_homepage.wait_until(Utils.short_wait) { @scheduler_homepage.visible_appt_ids.any? }
        @visible_list_view_appt_data = @advisor_homepage.visible_list_view_appt_data @appt_1
      end

      after(:all) { @advisor_homepage.hit_escape }

      it('show the arrival time') { expect(@visible_list_view_appt_data[:created_date]).to eql(@advisor_homepage.appt_time_created_format(@appt_1.created_date).strip) }
      it('show the student name') { expect(@visible_list_view_appt_data[:student_link_name]).to eql(@appt_1.student.full_name) }
      it('show the student SID') { expect(@visible_list_view_appt_data[:student_sid]).to eql(@appt_1.student.sis_id) }
      it('show the appointment reason(s)') { expect(@visible_list_view_appt_data[:topics]).to eql(@appt_1.topics.map(&:name).sort) }

      it('allow the drop-in advisor to expand an appointment\'s details') { @advisor_homepage.view_appt_details @appt_1 }
      it('show the student name') { expect(@advisor_homepage.details_student_name).to eql(@appt_1.student.full_name) }
      it('show the appointment reason(s)') { expect(@advisor_homepage.topics_from_string @advisor_homepage.modal_topics).to eql(@appt_1.topics.map(&:name).sort) }
      it('show the arrival time') { expect(@advisor_homepage.modal_created_at).to eql(@advisor_homepage.appt_time_created_format(@appt_1.created_date).strip) }
      it('show the appointment detail') { expect(@advisor_homepage.modal_details).to eql(@appt_1.detail) }
    end

    context 'on the student page' do

      before(:all) do
        @advisor_homepage.click_student_link @appt_1
        @advisor_student_page.show_appts
        @advisor_student_page.wait_until(1) { @advisor_student_page.visible_message_ids.include? @appt_1.id }
      end

      context 'when collapsed' do

        before(:all) { @visible_collapsed_date = @advisor_student_page.visible_collapsed_appt_data @appt_1 }

        it('show the appointment detail') { expect(@visible_collapsed_date[:detail]).to eql(@appt_1.detail) }
        it('show the appointment status') { expect(@visible_collapsed_date[:status]).to eql('WAITING') }
        it('show the appointment date') { expect(@visible_collapsed_date[:created_date]).to eql(@advisor_student_page.expected_item_short_date_format @appt_1.created_date) }
      end

      context 'when expanded' do

        before(:all) do
          @advisor_student_page.expand_item @appt_1
          @visible_expanded_data = @advisor_student_page.visible_expanded_appt_data @appt_1
        end

        it('show the appointment detail') { expect(@visible_expanded_data[:detail]).to eql(@appt_1.detail) }
        it('show the appointment date') { expect(@visible_expanded_data[:created_date]).to eql(@advisor_student_page.expected_item_short_date_format @appt_1.created_date) }
        it('show the appointment check-in button') { expect(@advisor_student_page.check_in_button(@appt_1).exists?).to be true }
        it('show no appointment check-in time') { expect(@visible_expanded_data[:check_in_time]).to be_nil }
        it('show no appointment cancel reason') { expect(@visible_expanded_data[:cancel_reason]).to be_nil }
        it('show no appointment cancel additional info') { expect(@visible_expanded_data[:cancel_addl_info]).to be_nil }
        it('show no appointment advisor') { expect(@visible_expanded_data[:advisor_name]).to be_nil }
        it('show the appointment type') { expect(@visible_expanded_data[:type]).to eql('Drop-in') }
        it('show the appointment reasons') { expect(@visible_expanded_data[:topics]).to eql(@appt_1.topics.map { |t| t.name.upcase }.sort) }
      end
    end
  end

  ### DROP-IN APPOINTMENT CHECK-IN

  describe 'drop-in appointment checkin' do

    # Scheduler

    context 'on the intake desk' do

      before(:all) do
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.create_appt @appt_2
        @appts << @appt_2
        @scheduler_intake_desk.click_new_appt
        @scheduler_intake_desk.create_appt @appt_3
        @appts << @appt_3
      end

      it 'requires that a scheduler select a drop-in advisor for the appointment' do
        @scheduler_intake_desk.click_appt_check_in_button @appt_2
        expect(@scheduler_intake_desk.modal_check_in_button_element.disabled?).to be false
        @scheduler_intake_desk.select_check_in_advisor @test.drop_in_advisor
        expect(@scheduler_intake_desk.modal_check_in_button_element.disabled?).to be false
      end

      it 'offers only drop-in advisors as advisor for the appointment' do
        expect(@scheduler_intake_desk.check_in_advisors.sort).to eql(@drop_in_advisors.map(&:uid).sort)
      end

      it 'can be done from the intake desk view' do
        @scheduler_intake_desk.click_modal_check_in_button
        @appt_2.checked_in_date = Time.now
        @appt_2.advisor = @test.drop_in_advisor
      end

      it 'removes the appointment from the intake desk list' do
        @scheduler_intake_desk.wait_until(Utils.short_wait) { !@scheduler_intake_desk.visible_appt_ids.include? @appt_2.id }
      end

      it 'can be done from the appointment details' do
        @scheduler_intake_desk.view_appt_details @appt_3
        @scheduler_intake_desk.click_details_check_in_button
        @scheduler_intake_desk.select_check_in_advisor @test.drop_in_advisor
        @scheduler_intake_desk.click_modal_check_in_button
        @appt_3.checked_in_date = Time.now
        @appt_3.advisor = @test.drop_in_advisor
      end

      it('removes the appointment from the intake desk list') do
        @scheduler_intake_desk.wait_for_poller { !@scheduler_intake_desk.visible_appt_ids.include? @appt_3.id }
      end
    end

    # Drop-in Advisor

    context 'on the waiting list' do

      before(:all) do
        @advisor_student_page.click_home
        @advisor_homepage.click_new_appt
        @advisor_homepage.create_appt @appt_4
        @appts << @appt_4
        @advisor_homepage.click_new_appt
        @advisor_homepage.create_appt @appt_5
        @appts << @appt_5
      end

      it 'can be done from the list view' do
        @advisor_homepage.click_appt_check_in_button @appt_4
        @appt_4.checked_in_date = Time.now
        @appt_4.advisor = @test.drop_in_advisor
      end

      it 'updates the status of the appointment on the waiting list' do
        @advisor_homepage.wait_until(Utils.short_wait) do
          visible_data = @advisor_homepage.visible_list_view_appt_data(@appt_4)
          visible_data[:checked_in_status] && visible_data[:checked_in_status].include?('CHECKED IN')
        end
      end

      it 'can be done from the appointment details' do
        @advisor_homepage.view_appt_details @appt_5
        @advisor_homepage.click_details_check_in_button
        @appt_5.checked_in_date = Time.now
        @appt_5.advisor = @test.drop_in_advisor
      end

      it 'updates the status of the appointment on the waiting list' do
        @advisor_homepage.wait_until(Utils.short_wait) do
          visible_data = @advisor_homepage.visible_list_view_appt_data(@appt_5)
          visible_data[:checked_in_status] && visible_data[:checked_in_status].include?('CHECKED IN')
        end
      end

      it 'updates the scheduler appointment desk view dynamically' do
        @scheduler_intake_desk.wait_for_poller { (@scheduler_intake_desk.visible_appt_ids & [@appt_4.id, @appt_5.id]).empty? }
      end
    end

    context 'on the student page' do

      before(:all) do
        @advisor_homepage.click_new_appt
        @advisor_homepage.create_appt @appt_6
        @appts << @appt_6
      end

      context 'when the advisor is not a drop-in advisor' do

        before(:all) do
          @advisor_homepage.log_out
          @advisor_homepage.dev_auth @test.advisor
          @advisor_student_page.load_page @student
        end

        after(:all) { @advisor_student_page.log_out }

        it 'cannot be done' do
          @advisor_student_page.show_appts
          @advisor_student_page.expand_item @appt_6
          expect(@advisor_student_page.check_in_button(@appt_6).exists?).to be false
        end
      end

      context 'when the advisor is a drop-in advisor' do

        before(:all) do
          @advisor_homepage.dev_auth @test.drop_in_advisor
          @advisor_student_page.click_student_link @appt_6
          @advisor_student_page.show_appts
          @advisor_student_page.expand_item @appt_6
        end

        it 'can be done' do
          @advisor_student_page.click_check_in_button @appt_6
          @advisor_student_page.wait_until(Utils.short_wait) { @advisor_student_page.visible_expanded_appt_data(@appt_6)[:check_in_time] }
          @appt_6.checked_in_date = Time.now
          @appt_6.advisor = @test.drop_in_advisor
        end

        it 'updates the scheduler appointment desk view dynamically' do
          @scheduler_intake_desk.wait_for_poller { !@scheduler_intake_desk.visible_appt_ids.include? @appt_6.id }
        end
      end
    end
  end

  ### DROP-IN APPOINTMENT CANCELLATION

  describe 'drop-in appointment cancellation' do

    before(:all) do
      @advisor_student_page.click_home
      [@appt_7, @appt_8, @appt_9].each do |appt|
        @advisor_homepage.click_new_appt
        @advisor_homepage.create_appt appt
        @appts << appt
      end
    end

    # Scheduler

    context 'on the appointment intake desk' do

      before(:all) { @scheduler_intake_desk.wait_for_poller { @scheduler_intake_desk.visible_appt_ids.include? @appt_7.id } }

      it 'requires a reason' do
        @scheduler_intake_desk.click_appt_dropdown_button @appt_7
        @scheduler_intake_desk.click_cancel_appt_button @appt_7
        expect(@scheduler_intake_desk.cancel_confirm_button_element.disabled?).to be true
        @appt_7.cancel_reason = 'Canceled by student'
        @scheduler_intake_desk.select_cancel_reason @appt_7
        expect(@scheduler_intake_desk.cancel_confirm_button_element.disabled?).to be false
      end

      it 'accepts additional info' do
        @appt_7.cancel_detail = "Some 'splainin' to do #{@test.id}"
        @scheduler_intake_desk.enter_cancel_explanation @appt_7
      end

      it 'can be done' do
        @scheduler_intake_desk.click_cancel_confirm_button
        @appt_7.canceled_date = Time.now
      end

      it 'removes the appointment from the list' do
        @scheduler_intake_desk.wait_until(Utils.short_wait) { !@scheduler_intake_desk.visible_appt_ids.include? @appt_7.id }
      end
    end

    # Drop-in Advisor

    context 'on the waiting list' do

      it 'requires a reason' do
        @advisor_homepage.click_appt_dropdown_button @appt_8
        @advisor_homepage.click_cancel_appt_button @appt_8
        expect(@advisor_homepage.cancel_confirm_button_element.disabled?).to be true
        @appt_8.cancel_reason = 'Canceled by department/advisor'
        @advisor_homepage.select_cancel_reason @appt_8
        expect(@advisor_homepage.cancel_confirm_button_element.disabled?).to be false
      end

      it 'accepts additional info' do
        @appt_8.cancel_detail = "Even more 'splainin' to do #{@test.id}"
        @advisor_homepage.enter_cancel_explanation @appt_8
      end

      it 'can be done' do
        @advisor_homepage.click_cancel_confirm_button
        @appt_8.canceled_date = Time.now
      end

      it 'updates the appointment status on the waiting list' do
        @advisor_homepage.wait_until(Utils.short_wait) do
          visible_data = @advisor_homepage.visible_list_view_appt_data(@appt_8)
          visible_data[:canceled_status] && visible_data[:canceled_status].include?('CANCELED')
        end
      end

      it 'updates the scheduler appointment desk view dynamically' do
        @scheduler_intake_desk.wait_for_poller { !@scheduler_intake_desk.visible_appt_ids.include? @appt_7.id }
      end
    end

    context 'on the student page' do

      before(:all) do
        @advisor_homepage.click_student_link @appt_9
        @advisor_student_page.show_appts
        @advisor_student_page.expand_item @appt_9
      end

      it 'requires a reason' do
        @advisor_student_page.click_appt_dropdown_button @appt_9
        @advisor_student_page.click_cancel_appt_button @appt_9
        expect(@advisor_student_page.cancel_confirm_button_element.disabled?).to be true
        @appt_9.cancel_reason = 'Canceled by student'
        @advisor_student_page.select_cancel_reason @appt_9
        expect(@advisor_student_page.cancel_confirm_button_element.disabled?).to be false
      end

      it 'accepts additional info' do
        @appt_9.cancel_detail = "Too much 'splainin' to do #{@test.id}"
        @advisor_student_page.enter_cancel_explanation @appt_9
      end

      it 'can be done' do
        @advisor_student_page.click_cancel_confirm_button
        @advisor_student_page.wait_until(Utils.short_wait) do
          visible_data = @advisor_student_page.visible_expanded_appt_data @appt_9
          visible_data[:cancel_reason] == @appt_9.cancel_reason
          visible_data[:cancel_addl_info] == @appt_9.cancel_detail
        end
        @appt_9.canceled_date = Time.now
      end

      it 'updates the scheduler appointment desk view dynamically' do
        @scheduler_intake_desk.wait_for_poller { !@scheduler_intake_desk.visible_appt_ids.include? @appt_9.id }
      end
    end
  end

  describe 'intake desk appointments' do

    it 'shows today\'s pending appointments sorted by creation time' do
      pending_appts = @appts.select { |a| !a.checked_in_date && !a.canceled_date }.sort_by(&:created_date).reverse.map(&:id)
      expect(@scheduler_intake_desk.visible_appt_ids).to eql(pending_appts)
    end
  end

  describe 'drop-in advisor waiting list' do

    before(:all) do
      @advisor_student_page.click_home
      @advisor_homepage.wait_until(Utils.short_wait) { @advisor_homepage.visible_appt_ids.any? }
    end

    it 'shows all today\'s appointments sorted by creation time, with canceled segregated at the bottom' do
      canceled_appts = @appts.select(&:canceled_date).sort_by(&:created_date).reverse
      non_canceled_appts = (@appts - canceled_appts).sort_by(&:created_date).reverse
      expect(@advisor_homepage.visible_appt_ids).to eql((non_canceled_appts + canceled_appts).map(&:id))
    end
  end

  describe 'student appointment timeline' do

    before(:all) do
      @advisor_homepage.click_student_link @appt_0
      @advisor_student_page.show_appts
      @student_appts = BOACUtils.get_student_appts(@student).reject &:deleted_date
    end

    it 'shows all non-deleted appointments sorted by creation time' do
      expect(@advisor_student_page.visible_collapsed_item_ids('appointment')).to eql(@student_appts.sort_by(&:created_date).reverse.map(&:id))
    end
  end
end