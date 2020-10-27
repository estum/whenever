
WheneverSystemd is a fork of the gem [Whenever](https://github.com/javan/whenever), which generates & installs
[systemd timers](https://www.freedesktop.org/software/systemd/man/systemd.timer.html#) from a similar `schedule.rb` file.

Note: By some reasons there is no tests yet, if you want to add them, you are welcome.

### Installation

```sh
$ gem install whenever_systemd
```

Or with Bundler in your Gemfile.

```ruby
gem 'whenever_systemd', require: false
```

### Getting started

```sh
$ cd /apps/my-great-project
$ bundle exec wheneverize .
```

This will create an initial `config/schedule.rb` file for you (as long as the config folder is already present in your project).

### The `whenever_systemd` command

The `whenever_systemd` command will simply show you your `schedule.rb` file converted to cron syntax. It does not read or write your systemd units.

```sh
$ cd /apps/my-great-project
$ bundle exec whenever_systemd
```

To write unit files for your jobs, execute this command:

```sh
$ whenever_systemd --update-units
```

Other commonly used options include:
```sh
$ whenever_systemd --load-file config/my_schedule.rb # set the schedule file
$ whenever_systemd --install-path '/usr/lib/systemd/system/' # install units to specific dir
```

### Example schedule.rb file

**Note the difference with whenever schedule.rb:**

You should provide a name to your job in the first argument, i.e.:

```ruby
# instead of:
runner "MyModel.some_process"

# With whenever_systemd:
runner "mymodel-some_process", "MyModel.some_process"
```

So, here is an example:

```ruby
set :prefix,        "myproject"
set :timer,          { accuracy_sec: "1m" } # timer options
set :install,        { wanted_by: "timers.target" } # project timers target

every 3.hours do # 1.minute 1.day 1.week 1.month 1.year is also supported
  runner  "mymodel-some_process", "MyModel.some_process"
  rake    "myrake-task", "my:rake:task"
  command "my_great_command", "/usr/bin/my_great_command"
end

# Helpers: minutely, hourly, daily, monthly, yearly, quarterly, semiannually
# See: https://www.freedesktop.org/software/systemd/man/systemd.time.html#Calendar%20Events
minutely do
  runner "SomeModel.ladeeda"
end

# +every+ helper eats any calendar syntax described in the link above:
every '*:1/15' do # Every 15 minutes, starting from 01, i.e.: 01,16,31,46
  runner "mymode-task_to_run_in_15m", "Mymodel.task_to_run_in_15m"
end

# Folded blocks:
daily do
  at '00:00' do # run every day at 00:00
    runner "task-do_something_great", "Task.do_something_great"
    rake "app_server-task", "app_server:task"
  end
end

weekly 'Sun' do
  at '4:30' do # Run every Sunday at 04:30
    runner "mymodel-sunday_task", "Mymodel.sunday_task"
  end
end
```

### Define your own job types

Whenever ships with three pre-defined job types: command, runner, and rake. You can define your own with `job_type`.

For example:

```ruby
job_type :awesome, '/usr/local/bin/awesome :task :fun_level'

every 2.hours do
  awesome "awesome-party", "party", fun_level: "extreme"
end
```

Would run `/usr/local/bin/awesome party extreme` every two hours. `:task` is always replaced with the first argument, and any additional `:whatevers` are replaced with the options passed in or by variables that have been defined with `set`.

The default job types that ship with Whenever are defined like so:

```ruby
job_type :command, ":task :output"
job_type :rake,    "cd :path && :environment_variable=:environment bundle exec rake :task --silent :output"
job_type :runner,  "cd :path && bin/rails runner -e :environment ':task' :output"
job_type :script,  "cd :path && :environment_variable=:environment bundle exec script/:task :output"
```

If a `:path` is not set it will default to the directory in which `whenever` was executed. `:environment_variable` will default to 'RAILS_ENV'. `:environment` will default to 'production'. `:output` will be replaced with your output redirection settings which you can read more about here: <http://github.com/javan/whenever/wiki/Output-redirection-aka-logging-your-cron-jobs>

All jobs are by default run with `bash -l -c 'command...'`. Among other things, this allows your cron jobs to play nice with RVM by loading the entire environment instead of cron's somewhat limited environment. Read more: <http://blog.scoutapp.com/articles/2010/09/07/rvm-and-cron-in-production>

You can change this by setting your own `:job_template`.

```ruby
set :job_template, "bash -l -c ':job'"
```

Or set the job_template to nil to have your jobs execute normally.

```ruby
set :job_template, nil
```

### Credit

WheneverSystemd is forked from Whenever not by a glory seeker, so I just copy the original credits:

Whenever was created for use at Inkling (<http://inklingmarkets.com>). Their take on it: <http://blog.inklingmarkets.com/2009/02/whenever-easy-way-to-do-cron-jobs-from.html>

Thanks to all the contributors who have made it even better: <http://github.com/javan/whenever/contributors>

Copyright &copy; 2017 Javan Makhmali
