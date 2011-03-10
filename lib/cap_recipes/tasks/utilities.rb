require 'fileutils'
 
module Utilities 
  # utilities.config_gsub('/etc/example', /(.*)/im, "\\1")
  def config_gsub(file, find, replace)
    tmp="/tmp/#{File.basename(file)}"
    get file, tmp
    content=File.open(tmp).read
    content.gsub!(find,replace)
    put content, tmp
    sudo "mv #{tmp} #{file}"
  end
  
  # utilities.ask('What is your name?', 'John')
  def ask(question, default='')
    question = "\n" + question.join("\n") if question.respond_to?(:uniq)
    answer = Capistrano::CLI.ui.ask(space(question)).strip
    answer.empty? ? default : answer
  end

  # utilities.yes?('Proceed with install?')
  def yes?(question)
    question = "\n" + question.join("\n") if question.respond_to?(:uniq)
    question += ' (y/n)'
    ask(question).downcase.include? 'y'
  end

  # Uses the base ruby path to install gem(s), avoids installing the gem if it's already installed.
  # Installs the gems detailed in +package+, selecting version +version+ if
  # specified.
  def gem_install(package, version=nil)
    tries = 3
    begin
      cmd = "#{sudo} #{base_ruby_path}/bin/gem install -y --no-rdoc --no-ri #{version ? '-v '+version.to_s : ''} #{package}"
      wrapped_cmd = "if ! #{base_ruby_path}/bin/gem list | grep --silent -e '#{package}.*#{version}'; then #{cmd}; fi"
      run wrapped_cmd
      #send(run_method,wrapped_cmd)
    rescue Capistrano::Error
      tries -= 1
      retry if tries > 0
    end
  end

  # Installs the gems detailed in +package+, selecting version +version+ if
  # specified, after uninstalling all versions of previous gems of +package+
  def gem_install_only(package, version=nil)
    tries = 3
    begin
      run "if ! #{base_ruby_path}/bin/gem list | grep --silent -e '#{package}.*#{version}'; then #{sudo} #{base_ruby_path}/bin/gem uninstall --ignore-dependencies --executables --all #{package}; #{sudo} #{base_ruby_path}/bin/gem install -y --no-rdoc --no-ri #{version ? '-v '+version.to_s : ''} #{package}; fi"
    rescue Capistrano::Error
      tries -= 1
      retry if tries > 0
    end
  end

  # uninstalls the gems detailed in +package+, selecting version +version+ if
  # specified, otherwise all.
  def gem_uninstall(package, version=nil)
    cmd = "#{sudo} #{base_ruby_path}/bin/gem uninstall --ignore-dependencies --executables #{version ? '-v '+version.to_s  : '--all'} #{package}"
    run "if #{base_ruby_path}/bin/gem list | grep --silent -e '#{package}.*#{version}'; then #{cmd}; fi"
  end
  
  # utilities.apt_install %w[package1 package2]
  # utilities.apt_install "package1 package2"
  def apt_install(packages)
    packages = packages.split(/\s+/) if packages.respond_to?(:split)
    packages = Array(packages)
    sudo "#{apt_get} -qyu --force-yes install #{packages.join(" ")}"
  end
  
  def apt_update
    sudo "#{apt_get} -qy update"
  end

  def apt_upgrade
    sudo "#{apt_get} -qy update"
    sudo "#{apt_get} -qyu --force-yes upgrade"
  end

  def apt_get
    "DEBCONF_TERSE='yes' DEBIAN_PRIORITY='critical' DEBIAN_FRONTEND=noninteractive apt-get"
  end
  
  # utilities.sudo_upload('/local/path/to/file', '/remote/path/to/destination', options)
  def sudo_upload(from, to, options={}, &block)
    top.upload from, "/tmp/#{File.basename(to)}", options, &block
    sudo "mv /tmp/#{File.basename(to)} #{to}"
    sudo "chmod #{options[:mode]} #{to}" if options[:mode]
    sudo "chown #{options[:owner]} #{to}" if options[:owner]
  end

  # Upload a file, running it through ERB
  # utilities.sudo_upload_template('/local/path/to/file','remote/path/to/destination', options)
  def sudo_upload_template(src,dst,options = {})
    raise Capistrano::Error, "sudo_upload_template requires Source and Destination" if src.nil? or dst.nil?
    put ERB.new(File.read(src)).result(binding), "/tmp/#{File.basename(dst)}"
    sudo "mv /tmp/#{File.basename(dst)} #{dst}"
    sudo "chmod #{options[:mode]} #{dst}" if options[:mode]
    sudo "chown #{options[:owner]} #{dst}" if options[:owner]
  end
  
  # Upload a file relative to utilities.rb, running it through ERB
  def upload_template(src,dst,options = {})
    raise Capistrano::Error, "put_template requires Source and Destination" if src.nil? or dst.nil?
    put ERB.new(File.read(src)).result(binding), dst, options
  end
  
  # utilities.adduser('deploy')
  def adduser(user, options={})
    options[:shell] ||= '/bin/bash' # new accounts on ubuntu 6.06.1 have been getting /bin/sh
    switches = '--disabled-password --gecos ""'
    switches += " --disabled-login" if options[:disabled_login]
    switches += " --system" if options[:system]
    switches += " --shell=#{options[:shell]} " if options[:shell]
    switches += ' --no-create-home ' if options[:nohome]
    switches += " --ingroup #{options[:group]} " unless options[:group].nil?
    invoke_command "grep '^#{user}:' /etc/passwd || sudo /usr/sbin/adduser #{user} #{switches}",
    :via => run_method
  end

  #utilities.addgroup('deploy')
  def addgroup(group,options={})
    switches = ''
    switches += " --system" if options[:system]
    invoke_command "/usr/sbin/addgroup #{group} #{switches}", :via => run_method
  end
  
  # role = :app
  def with_role(role, &block)
    original, ENV['HOSTS'] = ENV['HOSTS'], find_servers(:roles => role).map{|d| d.host}.join(",")
    begin
      yield
    ensure
      ENV['HOSTS'] = original
    end
  end

  # utilities.with_credentials(:user => 'xxxx', :password => 'secret')
  # options = { :user => 'xxxxx', :password => 'xxxxx' }
  def with_credentials(options={}, &block)
    original_username, original_password = user, password
    begin
      set :user,     options[:user] || original_username
      set :password, options[:password] || original_password
      yield
    ensure
      set :user,     original_username
      set :password, original_password
    end
  end
  
  def space(str)
    "\n#{'=' * 80}\n#{str}"
  end
  
  ##
  # Run a command and ask for input when input_query is seen.
  # Sends the response back to the server.
  #
  # +input_query+ is a regular expression that defaults to /^Password/.
  # Can be used where +run+ would otherwise be used.
  # run_with_input 'ssh-keygen ...', /^Are you sure you want to overwrite\?/
  def run_with_input(shell_command, input_query=/^Password/, response=nil)
    handle_command_with_input(:run, shell_command, input_query, response)
  end
 
  ##
  # Run a command using sudo and ask for input when a regular expression is seen.
  # Sends the response back to the server.
  #
  # See also +run_with_input+
  # +input_query+ is a regular expression
  def sudo_with_input(shell_command, input_query=/^Password/, response=nil)
    handle_command_with_input(:sudo, shell_command, input_query, response)
  end
 
  def invoke_with_input(shell_command, input_query=/^Password/, response=nil)
    handle_command_with_input(run_method, shell_command, input_query, response)
  end
  
  private
  
  ##
  # Does the actual capturing of the input and streaming of the output.
  #
  # local_run_method: run or sudo
  # shell_command: The command to run
  # input_query: A regular expression matching a request for input: /^Please enter your password/
  def handle_command_with_input(local_run_method, shell_command, input_query, response=nil)
    send(local_run_method, shell_command, {:pty => true}) do |channel, stream, data|
      
      if data =~ input_query
        if response
          logger.info "#{data} #{"*"*(rand(10)+5)}", channel[:host]
          channel.send_data "#{response}\n"
        else
          logger.info data, channel[:host]
          response = ::Capistrano::CLI.password_prompt "#{data}"
          channel.send_data "#{response}\n"
        end
      else
        logger.info data, channel[:host]
      end
    end
  end
  
  
end
 
Capistrano.plugin :utilities, Utilities