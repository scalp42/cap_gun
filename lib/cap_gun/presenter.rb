require 'etc'

module CapGun
  class Presenter
    DEFAULT_SENDER = %("CapGun" <cap_gun@example.com>)
    DEFAULT_EMAIL_PREFIX = "[DEPLOY]"

    attr_accessor :capistrano

    def initialize(capistrano)
      self.capistrano = capistrano
    end

    def recipients
      capistrano[:cap_gun_email_envelope][:recipients]
    end

    def email_prefix
      capistrano[:cap_gun_email_envelope][:email_prefix] || DEFAULT_EMAIL_PREFIX
    end

    def from
      capistrano[:cap_gun_email_envelope][:from] || DEFAULT_SENDER
    end

    def current_user
      Etc.getlogin || ENV['LOGNAME'] || "Deploy"
    end

    def summary
      if capistrano[:rails_env] == "staging"
        %[<b>#{current_user}</b> #{deployed_to} (#{capistrano[:application]}, #{capistrano[:target_server]}) at #{release_time}.]
      else
        %[<b>#{current_user}</b> #{deployed_to} (#{capistrano[:application]}) at #{release_time}.]
      end
    end

    def deployed_to
      return "deployed to #{capistrano[:rails_env]}" if capistrano[:rails_env]
      "deployed"
    end

    def branch
      "Branch: #{capistrano[:branch]}" unless capistrano[:branch].nil? || capistrano[:branch].empty?
    end

    def scm_details
      return unless [:git,:subversion].include? capistrano[:scm].to_sym
      <<-EOL
#{branch}
#{scm_log}
      EOL
      rescue
        nil
    end

    def scm_log
      "\nCommits since last release\n=========================\n#{scm_log_messages}"
    end

    def scm_log_messages
      messages = case capistrano[:scm].to_sym
        when :git
          git_log.empty? ? "There were no commits between the current and previous revision." : git_log.gsub(/pull request #[\d]+/){|m| %Q{pull request <a href="#{capistrano[:pull_url]}/#{m.gsub('pull request #', '')}">#{m.gsub('pull request', '').strip}</a>} }.strip
        when :subversion
          `svn log -r #{previous_revision.to_i+1}:#{capistrano[:current_revision]}`
        else
          "No scm was used. Please look into git or subversion."
      end
    end

    def git_log
      @git_log ||= begin
        stdin, stdout, stderr = Open3.popen3("git log #{previous_revision}..#{capistrano[:latest_revision]} --pretty=format:%h:%s")
        error = stderr.read.chomp
        return "There was an error getting the commits log (please make sure you checkout the branch you're trying to deploy:)\n#{error}" unless error.blank?
        stdout.read.chomp
      end
    end

    def exit_code
      $?
    end

    # Gives you a prettier date/time for output from the standard Capistrano timestamped release directory.
    # This assumes Capistrano uses UTC for its date/timestamped directories, and converts to the local
    # machine timezone.
    def humanize_release_time(path)
      return unless path
      match = path.match(/(\d+)$/)
      return unless match
      local = convert_from_utc(match[1])
      local.strftime("%B #{local.day.ordinalize}, %Y %l:%M %p #{local_timezone}").gsub(/\s+/, ' ').strip
    end

    # Use some DateTime magicrey to convert UTC to the current time zone
    # When the whole world is on Rails 2.1 (and therefore new ActiveSupport) we can use the magic timezone support there.
    def convert_from_utc(timestamp)
      # we know Capistrano release timestamps are UTC, but Ruby doesn't, so make it explicit
      utc_time = timestamp << "UTC"
      datetime = DateTime.parse(utc_time)
      datetime.new_offset(local_datetime_zone_offset)
    end

    def local_datetime_zone_offset
      @local_datetime_zone_offset ||= DateTime.now.offset
    end

    def local_timezone
      @current_timezone ||= Time.now.zone
    end

    def release_time
      humanize_release_time(capistrano[:current_release])
    end

    def previous_revision
      capistrano.fetch(:previous_revision, "n/a")
    end

    def previous_release_time
      humanize_release_time(capistrano[:previous_release])
    end

    def subject
      if capistrano[:rails_env] == "staging"
        "#{email_prefix} #{current_user} #{deployed_to} (#{capistrano[:application]}, #{capistrano[:target_server]})"
      else
        "#{email_prefix} #{current_user} #{deployed_to} (#{capistrano[:application]})"
      end
    end

    def comment
      "Comment: #{capistrano[:comment]}.\n" if capistrano[:comment]
    end

    def repository
      capistrano[:repository_url] || capistrano[:repository]
    end

    def server_deployed
      if capistrano[:rails_env] == "staging"
        "#{capistrano[:target_server]}"
      else
        "production"
      end
    end

    def body
      body = "#{summary}\n"
      body << "#{scm_only_requests.join("\n")}\n"
      body << "#{comment}\n"
      body << "Deployment details\n"
      body << "====================\n"
      body << "\n"
      body << "Deployed to : <b>#{server_deployed}</b>\n"
      body << "\n"      
      body << "Release: #{capistrano[:current_release]}\n"
      body << "Release Time: #{release_time}\n"
      body << "Release Revision: #{capistrano[:latest_revision]}"
      body << "\n"
      body << "Previous Release: #{capistrano[:previous_release]}\n"
      body << "Previous Release Time: #{previous_release_time}\n"
      body << "Previous Release Revision: #{previous_revision}\n"
      body << "\n"
      body << "Repository: #{capistrano[:repository]}\n"
      body << "Deploy path: #{capistrano[:deploy_to]}\n"
      body << "Domain: #{capistrano[:domain]}\n" if capistrano[:domain]
      body << "#{scm_details}\n"
      body
    end

  end
end
