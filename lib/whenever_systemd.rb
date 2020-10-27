# frozen_string_literal: true

require 'whenever_systemd/job_list'
require 'whenever_systemd/job'
require 'whenever_systemd/command_line'
require 'whenever_systemd/output_redirection'
require 'whenever_systemd/os'

module WheneverSystemd
  DEFAULT_INSTALL_PATH = "/etc/systemd/system"

  def self.cron(options)
    JobList.new(options).dry_units(options[:install_path])
  end

  def self.path
    Dir.pwd
  end

  def self.bin_rails?
    File.exist?(File.join(path, 'bin', 'rails'))
  end

  def self.script_rails?
    File.exist?(File.join(path, 'script', 'rails'))
  end

  def self.bundler?
    File.exist?(File.join(path, 'Gemfile'))
  end
end