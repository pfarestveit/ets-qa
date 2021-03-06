require_relative '../../util/spec_helper'

module Page
  module JunctionPages
    class CanvasMailingListPage

      include PageObject
      include Logging
      include Page
      include JunctionPages

      link(:mailing_list_link, text: 'Mailing List')
      div(:no_list_msg, xpath: '//div[contains(.,"No Mailing List has yet been created for this site.")]')
      button(:create_list_button, id: 'btn-create-mailing-list')
      div(:list_created_msg, xpath: '//div[contains(.,"A Mailing List has been created")]')
      div(:list_address, xpath: '//div[contains(.,"A Mailing List has been created")]/strong')
      div(:list_dupe_error_msg, xpath: '//div[contains(.,"A Mailing List cannot be created for the site")]')
      div(:list_dupe_email_msg, xpath: '//div[contains(.,"is already in use by another Mailing List.")]')

      # Loads the instructor Mailing List LTI tool in a course site
      # @param course [Course]
      def load_embedded_tool(course)
        logger.info "Loading embedded instructor Mailing List tool for course ID #{course.site_id}"
        load_tool_in_canvas"/courses/#{course.site_id}/external_tools/#{JunctionUtils.canvas_mailing_list_tool}"
      end

      # Loads the standalone version of the instructor Mailing List tool
      # @param course [Course]
      def load_standalone_tool(course)
        logger.info "Loading standalone instructor Mailing List tool for course ID #{course.site_id}"
        navigate_to "#{JunctionUtils.junction_base_url}/canvas/site_mailing_list/#{course.site_id}"
      end

      # Clicks the 'create list' button
      def create_list
        logger.info 'Clicking create-list button'
        wait_for_update_and_click create_list_button_element
        list_created_msg_element.when_present Utils.short_wait
      end

      # WELCOME EMAIL

      link(:welcome_email_link, id: 'link-to-httpsberkeleyservicenowcomkb_viewdosysparm_articleKB0013900')
      text_field(:email_subject_input, id: 'bc-page-site-mailing-list-subject-input')
      elements(:email_body_text_area, :text_area, xpath: '//div[@role="textbox"]')
      button(:email_save_button, id: 'btn-save-welcome-email')
      button(:email_activation_toggle, id: 'welcome-email-activation-toggle')
      div(:email_paused_msg, xpath: '//div[text()=" Sending welcome emails is paused until activation. "]')
      div(:email_activated_msg, xpath: '//div[text()=" Welcome email activated. "]')
      div(:email_subject, id: 'bc-page-site-mailing-list-subject')
      div(:email_body, id: 'bc-page-site-mailing-list-body')
      button(:email_edit_button, id: 'btn-edit-welcome-email')
      button(:email_edit_cancel_button, id: 'btn-cancel-welcome-email-edit')
      button(:email_log_download_button, id: 'btn-download-sent-message-log')

      def enter_email_subject(subject)
        logger.info "Entering subject '#{subject}'"
        wait_for_element_and_type(email_subject_input_element, subject)
      end

      def enter_email_body(body)
        logger.info "Entering body '#{body}'"
        wait_for_textbox_and_type(email_body_text_area_elements[1], body)
      end

      def click_save_email_button
        logger.info 'Clicking the save email button'
        wait_for_update_and_click email_save_button_element
        email_subject_element.when_visible Utils.short_wait
      end

      def click_edit_email_button
        logger.info 'Clicking the edit button'
        wait_for_update_and_click email_edit_button_element
      end

      def click_cancel_edit_button
        logger.info 'Clicking the cancel email edit button'
        wait_for_update_and_click email_edit_cancel_button_element
      end

      def click_activation_toggle
        logger.info 'Clicking email activation toggle'
        wait_for_update_and_click email_activation_toggle_element
      end

      def download_csv
        logger.info 'Downloading mail audit CSV'
        Utils.prepare_download_dir
        path = "#{Utils.download_dir}/embedded-welcome-messages-log*.csv"
        wait_for_update_and_click email_log_download_button_element
        wait_until(Utils.short_wait) { Dir[path].any? }
        CSV.table Dir[path].first
      end

    end
  end
end
