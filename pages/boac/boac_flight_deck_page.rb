require_relative '../../util/spec_helper'

class BOACFlightDeckPage

  include PageObject
  include Logging
  include Page
  include BOACPages

  h2(:my_profile_heading, xpath: '//h2[text()="My Profile"]')
  checkbox(:demo_mode_toggle, id: 'toggle-demo-mode')
  h2(:status_heading, id: 'system-status-header')

  # Loads the admin page
  def load_page
    navigate_to "#{BOACUtils.base_url}/admin"
  end

  def drop_in_advising_toggle_el(dept)
    button_element(xpath: "//button[@id='toggle-drop-in-advising-#{dept.code if dept}']")
  end

  def drop_in_advising_enabled?(dept)
    drop_in_advising_toggle_el(dept).when_visible Utils.short_wait
    span_element(xpath: "//button[@id='toggle-drop-in-advising-#{dept.code}']/span/span").text == 'YES'
  end

  def disable_drop_in_advising_role(dept_membership)
    if drop_in_advising_enabled? dept_membership.dept
      logger.info "Drop-in role is enabled in dept #{dept_membership.dept.code}, removing"
      wait_for_update_and_click drop_in_advising_toggle_el(dept_membership.dept)
    else
      logger.info "Drop-in role is already disabled in dept #{dept_membership.dept.code}"
    end
    dept_membership.is_drop_in_advisor = false
  end

  def enable_drop_in_advising_role(dept_membership = nil)
    if drop_in_advising_enabled?(dept_membership&.dept)
      logger.info "Drop-in role is already enabled#{ + ' in dept ' + dept_membership.dept.code if dept_membership}"
    else
      logger.info "Drop-in role is disabled#{ + 'in dept ' + dept_membership.dept.code if dept_membership}, adding"
      wait_for_update_and_click drop_in_advising_toggle_el(dept_membership&.dept)
    end
    dept_membership.is_drop_in_advisor = true
  end

  #### SERVICE ANNOUNCEMENTS ####

  checkbox(:post_service_announcement_checkbox, id: 'checkbox-publish-service-announcement')
  h2(:edit_service_announcement, id: 'edit-service-announcement')
  text_area(:update_service_announcement, xpath: '//div[@role="textbox"]')
  button(:update_service_announcement_button, id: 'button-update-service-announcement')
  span(:service_announcement_banner, id: 'service-announcement-banner')
  span(:service_announcement_checkbox_label, id: 'checkbox-service-announcement-label')

  # Updates service announcement without touching the 'Post' checkbox
  # @param announcement [String]
  def update_service_announcement(announcement)
    logger.info "Entering service announcement '#{announcement}'"
    wait_for_textbox_and_type(update_service_announcement_element, announcement)
    wait_for_update_and_click update_service_announcement_button_element
  end

  # Checks or un-checks the service announcement "Post" checkbox
  def toggle_service_announcement_checkbox
    logger.info 'Clicking the service announcement posting checkbox'
    (el = post_service_announcement_checkbox_element).when_present Utils.short_wait
    js_click el
  end

  # Posts service announcement
  def post_service_announcement
    logger.info 'Posting a service announcement'
    service_announcement_checkbox_label_element.when_visible Utils.short_wait
    tries ||= 2
    begin
      tries -= 1
      toggle_service_announcement_checkbox if service_announcement_checkbox_label == 'Post'
      wait_until(Utils.short_wait) { service_announcement_checkbox_label == 'Posted' }
    rescue
      if tries.zero?
        logger.error 'Failed to post service alert'
        fail
      else
        logger.warn 'Failed to post service alert, retrying'
        retry
      end
    end
  end

  # Unposts service announcement
  def unpost_service_announcement
    logger.info 'Un-posting a service announcement'
    service_announcement_checkbox_label_element.when_visible Utils.medium_wait
    tries ||= 2
    begin
      tries -= 1
      toggle_service_announcement_checkbox if service_announcement_checkbox_label == 'Posted'
      wait_until(Utils.short_wait) { service_announcement_checkbox_label_element.text == 'Post' }
    rescue
      if tries.zero?
        logger.error 'Failed to unpost a service alert'
        fail
      else
        logger.warn 'Failed to unpost a service alert, retrying'
        retry
      end

    end
  end

end
