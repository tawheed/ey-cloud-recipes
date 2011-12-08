#
# Cookbook Name:: tout
# Recipe:: default
#

if node[:name] == 'ResqueAndRedis' or node[:instance_role] == 'solo'
  cron "Enqueue Scheduled Tout Pitches" do
    command "cd /data/Tout/current; RAILS_ENV=production bundle exec rake tout:scheduler"
    minute "*/5"
    user "deploy"
  end

  cron "Remind Customers About Trials Ending" do
    command "cd /data/Tout/current; RAILS_ENV=production bundle exec rake trials:remind"
    hour "12"
    user "deploy"
  end
  
end

if node[:name] == 'ResqueAndRedis' or node[:instance_role] == 'solo'
  cron "Run metrics" do
    command "cd /data/Tout/current; RAILS_ENV=production bundle exec rake metrics:process"
    hour "3"
    user "deploy"
  end
end

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

if ['app', 'app_master'].include?(node[:instance_role])
  node.engineyard.apps.each do |app|
    nginx_ssl_config_filename = "/etc/nginx/servers/#{app.name}.ssl.conf"
    ssl_param_modified_output = File.read(nginx_ssl_config_filename).gsub(/^ssl_ciphers (.*);/, "ssl_ciphers HIGH:!ADH;")
    File.open(nginx_ssl_config_filename, "w") do |out|
      out << ssl_param_modified_output
    end
  end
end