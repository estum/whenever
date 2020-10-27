# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module WheneverSystemd
  class CommandLine
    def self.execute(options={})
      new(options).run
    end

    def initialize(options={})
      @options = options

      @options[:install_path]    ||= WheneverSystemd::DEFAULT_INSTALL_PATH
      @options[:temp_path]       ||= "#{ENV['HOME']}/tmp/whenever-#{Time.now.to_i}"
      @options[:file]            ||= "config/schedule.rb"
      @options[:cut]             ||= 0
      @options[:identifier]      ||= default_identifier

      if !File.exist?(@options[:file]) && @options[:clear].nil?
        warn("[fail] Can't find file: #{@options[:file]}")
        exit(1)
      end
    end

    def run
      if @options[:dry]
        dry_run
      elsif @options[:clear]
        clear_units
      elsif @options[:update]
        update_units
      else
        show_units
        exit(0)
      end
    end

    def show_units
      puts job_list.dry_units(@options[:install_path])
      puts "## [message] Above is your schedule file converted to systemd units."
      puts "## [message] Your active units was not updated."
      puts "## [message] Run `whenever --help' for more options."
    end

    def dry_run
      if @options[:clear]
        puts job_list.generate_clear_script(@options[:install_path])
      elsif @options[:update]
        puts job_list.generate_update_script(@options[:install_path])
      else
        show_units
      end
      exit(0)
    end

    def update_units
      script_path = make_script("update_units") { job_list.generate_update_script(@options[:install_path]) }
      pid = spawn(sudo_if_need(script_path))
      Process.wait pid
    end

    def clear_units
      script_path = make_script("clear_units") { job_list.generate_clear_script(@options[:install_path]) }
      pid = spawn(sudo_if_need(script_path))
      Process.wait pid
    end

    def job_list
      @job_list ||= JobList.new(@options)
    end

    private

    def sudo_if_need(*cmd)
      Shellwords.join(@options[:sudo] ? ["sudo", "bash", *cmd] : ["bash", *cmd])
    end

    def make_script(name)
      FileUtils.mkdir_p(@options[:temp_path])
      script_file = Pathname(@options[:temp_path])/"#{name}.sh"
      script_file.write(yield)
      # script_file.chmod(0755)
      script_file.to_path
    end

    protected

    def default_identifier
      File.expand_path(@options[:file])
    end
  end
end
