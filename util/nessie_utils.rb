require_relative 'spec_helper'

class NessieUtils < Utils

  @config = Utils.config['nessie']

  def self.nessie_db_credentials
    {
      :host => @config['db_host'],
      :port => @config['db_port'],
      :name => @config['db_name'],
      :user => @config['db_user'],
      :password => @config['db_password']
    }
  end

  # DATABASE - ASSIGNMENTS

  # Returns the assignments associated with a user in a course site
  # @param user [User]
  # @param course [Course]
  # @return [Array<Assignment>]
  def self.get_assignments(user, course)
    query = "SELECT assignment_id, due_at, submitted_at, assignment_status
              FROM boac_analytics.assignment_submissions_scores
              WHERE course_id = #{course.site_id}
                AND canvas_user_id = #{user.canvas_id}
              ORDER BY assignment_id;"
    results = query_redshift_db(nessie_db_credentials, query)
    results.map do |r|
      submitted = %w(on_time late submitted graded).include? r['assignment_status']
      Assignment.new({:id => r['assignment_id'], :due_date => r['due_at'], :submission_date => r['submitted_at'], :submitted => submitted})
    end
  end

  # DATABASE - ALL STUDENTS

  # Converts a students result object to an array of users
  # @param athletes [PG::Result]
  # @return [Array<User>]
  def self.student_result_to_users(student_result, dept)
    # If a user has multiple sports, they will be on multiple rows and should be merged. The 'status' refers to active or inactive athletes.
    students = student_result.group_by { |h1| h1['uid'] }.map do |k,v|
      # Athletes with two sports can be active in one and inactive in the other. Drop the inactive sport altogether.
      if v.length > 1 && (%w(t f) & (v.map { |i| i['active'] }) == %w(t f))
        v.delete_if { |r| r['active'] == 'f' }
      end
      # ASC status only applies to athletes
      active = if v[0]['active']
                 (v.map { |i| i['active'] }).include?('t')
               end
      {
        :uid => k,
        :sid => v[0]['sid'],
        :dept => dept,
        :active => active,
        :intensive => (v[0]['intensive'] == 't'),
        :first_name => v[0]['first_name'],
        :last_name => v[0]['last_name'],
        :group_code => v.map { |h2| h2['group_code'] }.join(' ')
      }
    end

    # Convert to Users
    students.map do |a|
      attributes = {
        :uid => a[:uid],
        :sis_id => a[:sid],
        :depts => [a[:dept]],
        :active_asc => a[:active],
        :intensive_asc => a[:intensive],
        :first_name => a[:first_name],
        :last_name => a[:last_name],
        :full_name => "#{a[:first_name]} #{a[:last_name]}",
        :sports => a[:group_code].split.uniq
      }
      BOACUser.new attributes
    end
  end

  # Returns all students
  # @return [Array<User>]
  def self.get_all_students
    # Get a separate set of student users for each department
    asc_students = student_result_to_users(query_all_asc_students, BOACDepartments::ASC)
    coe_students = student_result_to_users(query_all_coe_students, BOACDepartments::COE)

    # Find students served by more than one department and merge their attributes into a new user
    all_students = asc_students + coe_students
    logger.info "There are #{asc_students.length} ASC students and #{coe_students.length} CoE students, for a total of #{all_students.length}"
    merged_students = []
    all_students.group_by { |s| s.uid }.map do |k,v|
      if v.length > 1
        depts = (v.map &:depts).flatten
        athlete = v.find { |i| i.sports.any? }
        active_asc = athlete.active_asc
        intensive_asc = athlete.intensive_asc
        sports = athlete.sports

        attributes = {
            :uid => k,
            :sis_id => v[0].sis_id,
            :depts => (depts ? depts : v[0].depts),
            :active_asc => (active_asc ? active_asc : v[0].active_asc),
            :intensive_asc => (intensive_asc ? intensive_asc : v[0].intensive_asc),
            :sports => (sports ? sports : v[0].sports),
            :first_name => v[0].first_name,
            :last_name => v[0].last_name,
            :full_name => v[0].full_name
        }
        merged_students << BOACUser.new(attributes)
      end
    end

    # Replace the duplicates with the merged users
    merged_student_sids = merged_students.map &:sis_id
    all_students.delete_if { |s| merged_student_sids.include? s.sis_id }
    net = all_students + merged_students
    logger.info "There are #{merged_students.length} overlapping students, for a net total of #{net.length}"
    net
  end

  # DATABASE - ASC STUDENTS

  # Returns all ASC students
  # @return [PG::Result]
  def self.query_all_asc_students
    env = nessie_db_credentials[:name][7..-1]
    query = "SELECT students.sid AS sid,
                    students.intensive AS intensive,
                    students.active AS active,
                    students.group_code AS group_code,
                    persons.ldap_uid AS uid,
                    persons.first_name AS first_name,
                    persons.last_name AS last_name
             FROM boac_advising_asc.students
             JOIN calnet_ext_#{env}.persons ON calnet_ext_#{env}.persons.sid = boac_advising_asc.students.sid
             ORDER BY students.sid;"
    Utils.query_redshift_db(nessie_db_credentials, query)
  end

  # Returns all the distinct teams associated with team members
  # @return [Array<Team>]
  def self.get_asc_teams
    # Get the squads associated with ASC students
    query = 'SELECT DISTINCT group_code
              FROM boac_advising_asc.students;'
    results = Utils.query_redshift_db(nessie_db_credentials, query)
    results = results.map { |r| r['group_code'] }
    squads = Squad::SQUADS.select { |squad| results.include? squad.code }
    squads.sort_by { |s| s.name }

    # Get the teams associated with the squads
    teams = squads.map &:parent_team
    teams.uniq!
    logger.info "Teams are #{teams.map &:name}"
    teams.sort_by { |t| t.name }
  end

  # Returns all the users associated with a team. If the full set of athlete users is already available,
  # will use that. Otherwise, obtains the full set too.
  # @param team [Team]
  # @param all_athletes [Array<User>]
  # @return [Array<User>]
  def self.get_asc_team_members(team, all_athletes)
    team_squads = Squad::SQUADS.select { |s| s.parent_team == team }
    squad_codes = team_squads.map &:code
    team_members = all_athletes.select { |u| (u.sports & squad_codes).any? }
    team_members
  end

  # DATABASE - CoE STUDENTS

  # Returns all CoE students
  # @return [PG::Result]
  def self.query_all_coe_students
    env = nessie_db_credentials[:name][7..-1]
    query = "SELECT students.sid AS sid,
                    persons.ldap_uid AS uid,
                    persons.first_name AS first_name,
                    persons.last_name AS last_name
             FROM boac_advising_coe.students
             JOIN calnet_ext_#{env}.persons ON calnet_ext_#{env}.persons.sid = boac_advising_coe.students.sid
             ORDER BY students.sid;"
    Utils.query_redshift_db(nessie_db_credentials, query)
  end

  # Returns all the CoE students associated with a given advisor
  # @param advisor [User]
  # @param all_coe_students [Array<User>]
  # @return [Array<User>]
  def self.get_coe_advisor_students(advisor, all_coe_students)
    query = "SELECT students.sid
              FROM boac_advising_coe.students
              WHERE students.advisor_ldap_uid = '#{advisor.uid}'
              ORDER BY students.sid;"
    result = Utils.query_redshift_db(nessie_db_credentials, query)
    result = result.map { |r| r['sid'] }
    all_coe_students.select { |s| result.include? s.sis_id }
  end

end