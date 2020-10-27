# frozen_string_literal: true

module WheneverSystemd
  module Formatters
    factory = proc { |tpl, args| tpl % args }.curry(2).freeze

    ParamPair = factory["%s=%s"].freeze

    capitalize = -> (part) do
      part.match?(/\A[a-z][a-z0-9]+\z/) ? part.capitalize : part
    end

    ParamKey = -> (key) do
      key.to_s.split('_').map(&capitalize).join
    end

    hash_join_params = -> (hash) do
      hash.transform_keys(&ParamKey).map(&ParamPair) * "\n"
    end

    ParamsHash = -> (hash) do
      hash.transform_values(&hash_join_params)
    end

    IntervalMinutes = factory["*:0/%{minutes}"]
    IntervalHours   = factory["0/%{hours}:0/%{minutes}"] >> proc { |v| v.chomp("/0") }
    IntervalSeconds = factory["0:0:0/%d"]

    NormalizeInterval = {
      "daily" => "*-*-*"
    }

    Duration = -> (freq) do
      case freq
      when 0...3600;     IntervalMinutes[freq.parts]  # 1 second to hour
      when 3600...86400; IntervalHours[freq.parts]    # 1 hour to day
      else               IntervalSeconds[freq.to_i]
      end
    end

    Freq = -> (freq) do
      ActiveSupport::Duration === freq ? Duration[freq] : freq
    end

    Service = ParamsHash >> factory[<<~INI]
      [Unit]
      %{unit}

      [Service]
      %{service}
    INI

    Timer = ParamsHash >> factory[<<~INI]
      [Unit]
      %{unit}

      [Timer]
      %{timer}

      [Install]
      %{install}
    INI

    Target = ParamsHash >> factory[<<~INI]
      [Unit]
      %{unit}

      [Install]
      WantedBy=timers.target
    INI

    MaterializeUnit = factory[<<~BASH]
      cat > %{path}/%{filename} <<'EOF'
      %{content}
      EOF
    BASH

    MaterializeUnits = proc { |list| list.map(&MaterializeUnit) * "\n" }

    DryUnit = factory[<<~EOF]
      # filepath: %{path}/%{filename}
      %{content}

    EOF

    DryUnits = proc { |list| list.map(&DryUnit) * "\n" }
  end
end
