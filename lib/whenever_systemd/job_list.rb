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

    %w(minutely hourly daily monthly yearly quarterly semiannually).each do |k|
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
          @jobs << Job.new("#{@prefix}-#{job_name}", @options.merge(@set_variables).merge(options).deep_dup)
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
        stop_timers(all: true),
        disable_timers(all: true),
        generate_units_script(@temp_path),
        copy_updated_units_to(path),
        Shellwords.join(["systemctl", "daemon-reload"]),
        format(%(systemctl enable --now %s), units_expansion('timer'))
      ].join("\n\n")
    end

    def generate_clear_script(path)
      [
        make_backup_dir,
        backup_previous_units_from(path, all: true),
        stop_timers(all: true),
        disable_timers(all: true),
        format(%(rm -rfI %{target}/%{expansion}), target: Shellwords.escape(path), expansion: units_expansion(all: true))
      ].join("\n\n")
    end

    def backup_previous_units_from(path, **opts)
      format(%(cp -bfruv %{source}/%{expansion} %{target}),
        source: Shellwords.escape(path),
        expansion: units_expansion(**opts),
        target: Shellwords.escape("#{@temp_path}/backup")
      )
    end

    def copy_updated_units_to(path)
      format(%(cp -bfruv %{source}/*.{service,timer} %{target}/),
        source: Shellwords.escape(@temp_path),
        target: Shellwords.escape(path)
      )
    end

    def make_backup_dir
      Shellwords.join(["mkdir", "-p", "#{@temp_path}/backup"])
    end

    def stop_timers(**opts)
      format(%(systemctl stop %s), units_expansion('timer', **opts))
    end

    def disable_timers(**opts)
      format(%(systemctl disable %s), units_expansion('timer', **opts))
    end

    def timers
      @jobs.map(&:timer_name)
    end

    def unit_files(path)
      Dir.glob("#{path}/#{units_expansion}")
    end

    def units_expansion(ext = "{service,timer}", all: false)
      suffixes = all ? "*" : format("{%s}", @jobs.map { |j| Shellwords.escape(j.unprefixed_name) }.join(?,))
      "#{@prefix}-#{suffixes}.#{ext}"
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
