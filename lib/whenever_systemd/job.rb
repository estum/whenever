require 'shellwords'
require "whenever_systemd/formatters"

module WheneverSystemd
  class Job
    attr_reader :at, :roles, :mailto, :name

    def initialize(name, options = {})
      @name = name
      @options = options
      @at = options.delete(:at)
      @template = options.delete(:template)
      @mailto                           = options.fetch(:mailto, :default_mailto)
      @job_template                     = options.delete(:job_template) || ":job"
      @roles                            = Array(options.delete(:roles))
      @options[:output]                 = options.has_key?(:output) ? Output::Redirection.new(options[:output]).to_s : ''
      @options[:environment_variable] ||= "RAILS_ENV"
      @options[:environment]          ||= :production
      @options[:path]                   = Shellwords.shellescape(@options[:path] || WheneverSystemd.path)

      description = options.delete(:description)
      install = options.delete(:install) { { wanted_by: "timers.target" } }

      timer = options.delete(:timer).to_h
      timer[:on_calendar] ||= compose_on_calendar(options.delete(:interval), @at)

      unit = options.delete(:unit).to_h
      unit[:description] = description

      service = options.delete(:service).to_h
      service[:type] ||= "oneshot"
      service[:exec_start] = output

      @service_options = { unit: unit, service: service }
      @timer_options = { unit: { description: description }, timer: timer, install: install }
    end

    def compose_on_calendar(*args)
      args.compact!
      if args.size > 1 && Formatters::NormalizeInterval.key?(args[0])
        args[0] = Formatters::NormalizeInterval[args[0]]
      end
      args.join(" ")
    end

    def output
      job = process_template(@template, @options)
      out = process_template(@job_template, @options.merge(:job => job))
      out.gsub(/%/, '\%')
    end

    def unprefixed_name(prefix = nil)
      prefix ||= @options[:prefix]
      if @name.rindex(prefix) == 0
        prefix_end = prefix.size.next
        @name[prefix_end, @name.size - prefix_end]
      else
        @name
      end
    end

    def service_name
      "#{@name}.service"
    end

    def timer_name
      "#{@name}.timer"
    end

    def unit_expansion
      "#{@name}.{service,timer}"
    end

    def systemd_units(path)
      [
        { path: path, filename: service_name, content: systemd_service },
        { path: path, filename: timer_name,   content: systemd_timer }
      ]
    end

    def systemd_service
      Formatters::Service[@service_options]
    end

    def systemd_timer
      Formatters::Timer[@timer_options]
    end

    def has_role?(role)
      roles.empty? || roles.include?(role)
    end

  protected

    def process_template(template, options)
      template.gsub(/:\w+/) do |key|
        before_and_after = [$`[-1..-1], $'[0..0]]
        option = options[key.sub(':', '').to_sym] || key

        if before_and_after.all? { |c| c == "'" }
          escape_single_quotes(option)
        elsif before_and_after.all? { |c| c == '"' }
          escape_double_quotes(option)
        else
          option
        end
      end.gsub(/\s+/m, " ").strip
    end

    def escape_single_quotes(str)
      str.gsub(/'/) { "'\\''" }
    end

    def escape_double_quotes(str)
      str.gsub(/"/) { '\"' }
    end
  end
end
