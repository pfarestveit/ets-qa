require_relative 'spec_helper'

class OecUtils

  include Logging

  @config = Utils.config

  def self.base_url(args = nil)
    (args && args.include?('qa')) ? 'https://course-evaluations-qa.berkeley.edu' : 'https://course-evaluations.berkeley.edu'
  end

  # Returns the name of the Blue project containing the evaluation forms being tested
  # @return [String]
  def self.blue_project_title
    @config['oec']['blue_project_title']
  end

  def self.create_results_file
    output_dir = File.join(ENV['HOME'], 'selenium-files')
    output_file = 'data_source_update_results.log'
    FileUtils.mkdir_p(output_dir) unless File.exists?(output_dir)
    file = File.join(output_dir, output_file)
    File.open(file, 'w') { |f| f.puts 'Results of OEC data source update script run:' }
    file
  end

  def self.log_results(file, result, e = nil)
    puts result
    puts "#{e.message}\n#{e.backtrace}" if e
    File.open(file, 'a') do |f|
      f.puts "\n => #{result}"
      f.puts "\n#{e.message}\n#{e.backtrace}" if e
    end
  end

  # Returns identifiers for a configured OEC test user
  # @return [Hash]
  def self.oec_user
    {
      first_name: @config['oec']['first_name'],
      last_name: @config['oec']['last_name'],
      uid: @config['oec']['uid'],
      sis_id: @config['oec']['sis_id'],
      email: @config['oec']['email']
    }
  end

  # Returns the expected location of the folder containing sub-dirs and CSVs for the configured term code
  # @return [String]
  def self.term_folder
    File.join(ENV['HOME'], "/OEC/#{@config['oec']['term']}")
  end

  def self.prepare_dept_confirmation(dept)
    file_name = File.join("#{term_folder}", "/Step 2 department confirmation/#{dept.dept_name} - Courses.csv")
    user = oec_user
    initial_csv = CSV.read(file_name, headers: true)
    CSV.open(file_name, 'wb') do |updated_csv|
      updated_csv << initial_csv.headers

      removed_row = initial_csv.find { |r| r['LDAP_UID'] }
      logger.info "Row where data will be removed: #{removed_row}"
      removed_row['START_DATE'] = nil
      removed_row['END_DATE'] = nil
      removed_row['EVALUATION_TYPE'] = nil
      removed_row['COURSE_NAME'] = nil
      removed_row['LDAP_UID'] = nil
      removed_row['FIRST_NAME'] = nil
      removed_row['LAST_NAME'] = nil
      removed_row['EMAIL_ADDRESS'] = nil

      changed_row = initial_csv.find { |r| r != removed_row }
      logger.info "Row where data will be changed: #{changed_row}"
      changed_row['LDAP_UID'] = user[:uid]
      changed_row['FIRST_NAME'] = user[:first_name]
      changed_row['LAST_NAME'] = user[:last_name]
      changed_row['EMAIL_ADDRESS'] = user[:email]
      changed_row['COURSE_ID'] = "#{changed_row['COURSE_ID']}_GSI"
      changed_row['START_DATE'] = (Date.today).strftime('%-m/%-d/%y')
      changed_row['END_DATE'] = (Date.today + 1).strftime('%-m/%-d/%y')
      changed_row['COURSE_NAME'] = "#{dept.dept_code} 999A LEC 001 INTRO TO SQUARE BIZ"
      changed_row['DEPT_FORM'] = "#{changed_row['DEPT_FORM']}_LECT"
      (changed_row['EVALUATION_TYPE'] == 'F') ? (changed_row['EVALUATION_TYPE'] = 'G') : (changed_row['EVALUATION_TYPE'] = 'F')
      (changed_row['CROSS_LISTED_FLAG'] == 'Y') ? (changed_row['CROSS_LISTED_FLAG'] = '') : (changed_row['CROSS_LISTED_FLAG'] = 'Y')

      initial_csv.each { |r| updated_csv << r.fields }
    end

    row_to_add = [nil, "#{dept.dept_code} 998AC LEC 001 IT MUST BE MAGIC", nil, nil, user[:uid], user[:first_name],
                  user[:last_name], user[:email], nil, "#{dept.dept_code}_OH_LA_LA", 'F', nil, nil, nil]
    Utils.add_csv_row(file_name, row_to_add)
  end

  # Edits data in the merged course confirmations file to maximize the number of rows where 'evaluate' can be set to 'yes' and pass
  # validation. Not intended to replicate edits by department admins, only to maximize the data that can reasonably be included in
  # validation and publishing.
  def self.prepare_merged_confirmations
    file_name = File.join("#{term_folder}", '/Step 3 preflight merge/Merged course confirmations.csv')

    # Read the existing file
    initial_csv = CSV.read(file_name, headers: true)

    # Create a new one to replace it
    CSV.open(file_name, 'wb') do |updated_csv|
      updated_csv << initial_csv.headers

      # Edit specific data on each row
      initial_csv.each do |r|
        logger.info "Checking a course instructor pairing for #{r['COURSE_ID']}-#{r['LDAP_UID']}"

        # Fill in missing instructors with the configured OEC user
        user = oec_user
        if r['LAST_NAME'].nil?
          r['LDAP_UID'] = user[:uid]
          r['SIS_ID'] = user[:sis_id]
          r['FIRST_NAME'] = user[:first_name]
          r['LAST_NAME'] = user[:last_name]
          r['EMAIL_ADDRESS'] = user[:email]
        end

        # Exclude instructors without email (adjusting the data is complicated) and one-day modular courses (not evaluated anyway)
        unless r['EMAIL_ADDRESS'].nil? || (r['START_DATE'] == r['END_DATE'])

          # Make sure the right department forms are set. FSSEM and BIOLOGY follow their own rules, so ignore them.
          unless r['DEPT_FORM'].nil? || r['DEPT_FORM'] == 'FSSEM' || r['DEPT_NAME'] == 'BIOLOGY' || r['DEPT_FORM'] == 'CALTEACH'
            dept = OECDepartments::DEPARTMENTS.find { |d| d.dept_code == r['DEPT_NAME'] }
            r['DEPT_FORM'] = dept.form_code
          end

          # Set empty evaluation types to 'WRIT' or 'F', though some Fs will cause validation errors
          if r['EVALUATION_TYPE'].nil?
            (r['DEPT_FORM'] == 'SPANISH') ? r['EVALUATION_TYPE'] = 'WRIT' : r['EVALUATION_TYPE'] = 'F'
          end

          # Set department forms for cross-listed courses
          if r['CROSS_LISTED_FLAG'] == 'Y'
            cross_listed_name = r['CROSS_LISTED_NAME']
            participating_listing_depts = OECDepartments::DEPARTMENTS.map { |d| d.form_code if cross_listed_name && cross_listed_name.include?(d.dept_code) }
            participating_listing_depts.compact!.sort!
            logger.debug "Cross-listed name is #{cross_listed_name}, and participating depts are #{participating_listing_depts}"
            r['DEPT_FORM'] = participating_listing_depts.first
          end

          # The data will probably pass validation, so set 'evaluate' to 'yes'
          r['EVALUATE'] = 'Y'

        end

        updated_csv << r.fields

      end
    end
  end

  # Selects the OEC departments whose evaluations are managed by ETS and returns a set of department form codes and evaluation types
  # @return [Array<Hash>]
  def self.get_forms
    participating_depts = OECDepartments::DEPARTMENTS.select { |d| d.ets_managed }
    forms_and_types = []
    participating_depts.each do |dept|
      if dept.eval_types
        # If both eval types and catalog IDs exist, then expect forms with only the eval types and forms with both the eval types and the catalog IDs.
        # Otherwise, just expect the eval types.
        forms_and_types << dept.eval_types.map { |eval| {:dept_code => dept.form_code, :eval_type => eval} }
        forms_and_types << dept.eval_types.map { |eval| {:dept_code => dept.form_code, :eval_type => eval, :catalog_ids => dept.catalog_ids} } if dept.catalog_ids
      else
        # If no eval types exist but catalog IDs exist, then expect forms with and without the catalog IDs
        forms_and_types << {:dept_code => dept.form_code}
        forms_and_types << {:dept_code => dept.form_code, :catalog_ids => dept.catalog_ids} if dept.catalog_ids
      end
    end
    forms = forms_and_types.flatten.uniq
    logger.debug "Forms are #{forms}"
    forms
  end

  # Parses the question bank file as a table. NB the CSV must be UTF-8 encoded.
  # @return [Array<Array>]
  def self.open_question_bank
    file = File.join(Utils.config_dir, 'oec-question-bank.csv')
    CSV.table file
  end

  # Compares the expected list of evaluation forms to the forms defined in the question bank.
  # @param csv [CSV::Table]
  # @return [boolean]
  def self.verify_all_forms_present(csv)
    expected_forms = get_forms.map { |f| get_form_code(f).gsub(/\W/, '').gsub('_', '').gsub('&', '') }
    expected_forms.each { |f| logger.info "Expecting a form for #{f}" }
    bank_forms = csv.headers[7..-1].map { |h| h.to_s.gsub(/\W/, '').gsub('_', '').upcase }
    expected_forms.each { |f| logger.info "Question bank has a form for #{f}" }
    logger.warn "Expected evaluation forms that are not in the question bank: #{expected_forms - bank_forms}"
    logger.warn "Evaluation forms in the question bank items that are unexpected: #{bank_forms - expected_forms}"
    bank_forms.sort == expected_forms.sort
  end

  # Converts a question bank row to a hash
  # @param row [Array<String>]
  # @return [Hash]
  def self.question_row_to_hash(row)
    {
      :category => row[:category],
      :question => row[:question],
      :type => row[:type],
      :options => row[:options] && (row[:options].split(' , ').map &:strip),
      :sub_question => row[:sub_question],
      :sub_type => row[:sub_type],
      :sub_options => row[:sub_options] && (row[:sub_options].split(' , '))
    }
  end

  # Returns the form code string that should be in the CSV header row
  # @param form [Hash]
  # @return [String]
  def self.get_form_code(form)
    "#{form[:dept_code]}#{'_' + form[:eval_type] if form[:eval_type]}#{'_' + form[:catalog_ids].first if form[:catalog_ids]}"
  end

  # Returns all the questions applicable to a given department form code and evaluation type
  # @param question_bank_csv [CSV]
  # @param form [Hash]
  # @return [Array<Hash>]
  def self.get_form_questions(question_bank_csv, form)
    # The form codes are headers in the question bank. When the CSV is read, the headers are converted to symbols.
    form_code_to_sym = get_form_code(form).downcase.gsub(' ', '_').gsub('&', '').delete(',').to_sym
    # Questions applicable to a form code have 'Y' under the header symbol
    questions = []
    question_bank_csv.each { |r| questions << OecUtils.question_row_to_hash(r) if r[form_code_to_sym] == 'Y' }
    questions
  end

end
