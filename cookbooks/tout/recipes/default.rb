#
# Cookbook Name:: tout
# Recipe:: default
#

# Set up CRON Jobs

if node[:name] == 'ResqueAndRedis' or node[:instance_role] == 'solo'
  cron "Enqueue Scheduled Tout Pitches" do
    command "cd /data/Tout/current; RAILS_ENV=production bundle exec rake tout:scheduler"
    minute "*/5"
    user "deploy"
  end

  cron "Run the Statsd Processor" do
    command "cd /data/Tout/current; RAILS_ENV=production bundle exec rake tout:statsd"
    user "deploy"
  end
end

if node[:name] == 'ResqueAndRedis' or node[:instance_role] == 'solo'
  cron "Run metrics" do
    command "cd /data/Tout/current; RAILS_ENV=production bundle exec rake metrics:process"
    hour "3"
    minute "0"
    user "deploy"
  end
end

# Set up Database configuration for Tout Admin

if ['solo', 'app', 'app_master', 'util'].include?(node[:instance_role])
  # We want to make sure that each database.yml file uses the same database in this environment
  node.engineyard.apps.each do |app|
    template "/data/#{app.name}/shared/config/database.yml" do
      # adapter: postgres   => datamapper
      # adapter: postgresql => active record
      dbtype = case node.engineyard.environment.db_stack
               when DNApi::DbStack::Mysql     then node.engineyard.environment.ruby_component.mysql_adapter
               when DNApi::DbStack::Postgres  then 'postgresql'
               when DNApi::DbStack::Postgres9 then 'postgresql'
               end

      owner node.engineyard.environment.ssh_username
      group node.engineyard.environment.ssh_username
      mode 0655
      source "database.yml.erb"
      variables({
        :dbuser => node.engineyard.environment.ssh_username,
        :dbpass => node.engineyard.environment.ssh_password,
        :dbname => "Tout",
        :dbhost => node.engineyard.environment.db_host,
        :dbtype => dbtype,
        :slaves => node.engineyard.environment.db_slaves_hostnames
      })
    end
  end
end

# Set up Custom SSL config for security purposes
if ['app', 'app_master'].include?(node[:instance_role])
  node.engineyard.apps.each do |app|
    nginx_ssl_config_filename = "/etc/nginx/servers/#{app.name}.ssl.conf"
    if File.exists?(nginx_ssl_config_filename) then
      ssl_param_modified_output = File.read(nginx_ssl_config_filename).gsub(/ssl_ciphers (.*);/, "ssl_ciphers HIGH:!ADH;")
      File.open(nginx_ssl_config_filename, "w") do |out|
        out << ssl_param_modified_output
      end
    end
  end
end

# Set up SSL forced redirect for Tout
if ['solo', 'app', 'app_master'].include?(node[:instance_role])
  template "/etc/nginx/servers/Tout/custom.conf" do
    owner node[:owner_name]
    group node[:owner_name]
    mode 0644
    source "custom.conf.erb"    
  end  
end

# Set up SSL subdomain handling
if ['solo', 'app', 'app_master'].include?(node[:instance_role])
  template "/etc/nginx/servers/Tout/custom.ssl.conf" do
    owner node[:owner_name]
    group node[:owner_name]
    mode 0644
    source "custom.ssl.conf.erb"    
  end  
end


# Set up remote_syslog
# execute "install remote_syslog gem" do
#   command "gem install remote_syslog"
# end

# # Install the remote_syslog start/stop script.
# template '/etc/init.d/remote_syslog' do
#   owner 'root'
#   group 'root'
#   mode 0755
#   source 'init.d-remote_syslog.erb'
# end

if ['solo', 'util'].include?(node[:instance_role])
  # Install the script for forcefully shutting down non-essential workers
  # and for gracefully shutting down essential workers 
  # so that deployment can proceed
  template "/data/Tout/shutdown_workers" do 
    owner 'deploy'
    group 'deploy'
    mode 0755
    source 'shutdown_workers.erb'
  end
end

# Set up the configuration file
template "/etc/log_files.yml" do
  @log_files = ["/var/log/nginx/*", "/var/log/chef.main.log", "/var/log/chef.custom.log", "/var/log/mysql/*", "/db/mysql/log/slow_query.log"]
  node.engineyard.apps.each do |app|
    @log_files << "/data/#{app.name}/current/log/production.log"
    @log_files << "/data/#{app.name}/current/log/resque.log"    
    @log_files << "/data/#{app.name}/current/log/unicorn.log"    
  end
  
  owner node[:owner_name]
  group node[:owner_name]
  mode 0644
  source "log_files.yml.erb"    
  variables({
      :hostname => node[:hostname],
      :log_files => @log_files
  })
end  

# execute "ensure-remote-syslog-is-running" do
#     command "/etc/init.d/remote_syslog restart"
# end

# Set up DocSplit dependencies
if['solo', 'util'].include?(node[:instance_role])
  package_list = [
    'poppler',
    'poppler-data',
    'poppler-bindings',
    'ghostscript',
    'corefonts',
    'openoffice-bin'
  ]
  for package_name in package_list do
    package package_name do
      action [:install]
    end
  end  

  # Set up GraphicsMagick for DocSplit
  bash "install_graphics_magick" do |variable|
    user "root"
    cwd "/tmp"
    code <<-EOH
    sudo wget -O GraphicsMagick-1.3.17.tar.gz http://downloads.sourceforge.net/project/graphicsmagick/graphicsmagick/1.3.17/GraphicsMagick-1.3.17.tar.gz
    tar -xvf GraphicsMagick-1.3.17.tar.gz
    cd GraphicsMagick-1.3.17
    ./configure
    make
    sudo make install
    EOH
    not_if do
      File.exists?("/usr/local/bin/gm")
    end
  end
end