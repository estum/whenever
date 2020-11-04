# frozen_string_literal: true

require "whenever_systemd/formatters"
require "active_support/duration"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/object/deep_dup"

module WheneverSystemd
  class JobList
    attr_reader :roles

    def initialize(options)
      @jobs, @env, @set_variables, @pre_set_variables = [], {}, {}, {}

      if options.is_a? String
        options = { :string => options }
      end
      @temp_path = options[:temp_path]
      pre_set(options[:set])
      @roles = options[:roles] || []

      setup_file = File.expand_path('../setup.rb', __FILE__)
      setup = File.read(setup_file)
      schedule = if options[:string]
        options[:string]
      elsif options[:file]
        File.read(options[:file])
      end

      instance_eval(setup, setup_file)
      instance_eval(schedule, options[:file] || '<eval>')
    end

    def set(variable, value)
      variable = variable.to_sym
      return if @pre_set_variables[variable]

      instance_variable_set("@#{variable}".to_sym, value)
      @set_variables[variable] = value
    end

    def method_missing(name, *args, &block)
      @set_variables.has_key?(name) ? @set_variables[name] : super
    end

    def self.respond_to?(name, include_private = false)
      @set_variables.has_key?(name) || super
    end

    def env(variable, value)
      @env[variable.to_s] = value
    end

    def every(frequency, at: nil, **timer)
      @options_was = @options
      @options = @options.to_h.merge(interval: Formatters::Freq[frequency], timer: timer, at: at)
      yield
    ensure
      @options, @options_was = @options_was, nil
    end

    def daily(at: "00:00:00", **options, &block)
      every("*-*-*", at: at, **options, &block)
    end

    %w(minutely hourly monthly yearly quarterly semiannually).each do |k|
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def #{k}(**options, &block)
          every(:#{k}, **options, &block)
        end
      RUBY
    end

    def weekly(*on_days, **options, &block)
      if on_days.size > 0
        every("#{on_days * ?,} *-*-*", **options, &block)
      else
        every(:weekly, **options, &block)
      end
    end

    def at(time)
      @options_was, @options = @options, @options.to_h.merge(at: time)
      yield
    ensure
      @options, @options_was = @options_was, nil
    end

    attr_reader :jobs

    def job_type(name, template)
      singleton_class.class_eval do
        define_method(name) do |job_name, task, *args|
          options = { :task => task, :template => template }
          options.merge!(args[0]) if args[0].is_a? Hash
          options[:description] ||= options.delete("?") { "WheneverSystemd-generated Job" }

          @jobs ||= []
          @jobs << Job.new("#{@prefix}-#{job_name}", @set_variables.deep_merge(@options).deep_merge(options).deep_dup)
        end
      end
    end

    def generate_units_script(path)
      Formatters::MaterializeUnits[systemd_units(path)]
    end

    def generate_update_script(path)
      [
        make_backup_dir,
        backup_previous_units_from(path, all: true),
        systemctl_timers('disable', '--now', all: true),
        generate_units_script(@temp_path),
        copy_updated_units_to(path),
        Shellwords.join(["/usr/bin/systemctl", "daemon-reload"]),
        systemctl_timers('enable', '--now')
      ].join("\n\n")
    end

    def generate_clear_script(path)
      [
        make_backup_dir,
        backup_previous_units_from(path, all: true),
        systemctl_timers('disable', '--now', all: true),
        format(%(/usr/bin/rm -rfI %{target}/%{expansion}), target: Shellwords.escape(path), expansion: units_expansion(all: true))
      ].join("\n\n")
    end

    def backup_previous_units_from(path, **opts)
      format(%(/usr/bin/cp -rvf %{source}/%{expansion} -t %{target}),
        source: Shellwords.escape(path),
        expansion: units_expansion(**opts),
        target: Shellwords.escape("#{@temp_path}/backup")
      )
    end

    def copy_updated_units_to(path)
      format(%(/usr/bin/cp -rvf %{source}/*.{service,timer} -t %{target}),
        source: Shellwords.escape(@temp_path),
        target: Shellwords.escape(path)
      )
    end

    def make_backup_dir
      Shellwords.join(["mkdir", "-p", "#{@temp_path}/backup"])
    end

    def systemctl_timers(*args, **opts)
      case args[0]
      when "enable", "disable"
        format(%(for timer in %s; do %s $timer; done),
          units_expansion('timer', sub: true, **opts),
          Shellwords.join(["/usr/bin/systemctl", *args])
        )
      else
        Shellwords.join(["/usr/bin/systemctl", *args, units_expansion('timer', **opts)])
      end
    end

    def timers
      @jobs.map(&:timer_name)
    end

    def unit_files(path)
      Dir.glob("#{path}/#{units_expansion}")
    end

    def units_expansion(ext = "{service,timer}", all: false, sub: false)
      suffixes = all ? "*" : format("{%s}", @jobs.map { |j| Shellwords.escape(j.unprefixed_name) }.join(?,))
      pattern = "#{@prefix}-#{suffixes}.#{ext}"
      return pattern unless sub
      if all
        format(%($(/usr/bin/systemctl list-unit-files '%s' | /usr/bin/cut -d ' ' -f 1 | /usr/bin/head -n -2 | /usr/bin/tail -n +2)), pattern)
      else
        format(%($(/usr/bin/echo %s)), pattern)
      end
    end

    def dry_units(path)
      Formatters::DryUnits[systemd_units(path)]
    end

    def systemd_units(path, include_target = true)
      wanted_by = @set_variables.dig(:install, :wanted_by)
      if include_target && wanted_by != "timers.target"
        [timers_target(path), *systemd_units("#{path}/#{wanted_by}.wants", false)]
      else
        @jobs.flat_map { |job| job.systemd_units(path) }
      end
    end

    def timers_target(path)
      {
        path: path,
        filename: @set_variables.dig(:install, :wanted_by),
        content: Formatters::Target[unit: { description: "Timers target" }]
      }
    end

    private

    #
    # Takes a string like: "variable1=something&variable2=somethingelse"
    # and breaks it into variable/value pairs. Used for setting variables at runtime from the command line.
    # Only works for setting values as strings.
    #
    def pre_set(variable_string = nil)
      return if variable_string.nil? || variable_string == ""

      pairs = variable_string.split('&')
      pairs.each do |pair|
        next unless pair.index('=')
        variable, value = *pair.split('=')
        unless variable.nil? || variable == "" || value.nil? || value == ""
          variable = variable.strip.to_sym
          set(variable, value.strip)
          @pre_set_variables[variable] = value
        end
      end
    end

    def environment_variables
      return if @env.empty?

      output = []
      @env.each do |key, val|
        output << "#{key}=#{val.nil? || val == "" ? '""' : val}\n"
      end
      output << "\n"

      output.join
    end
  end
end
