#
# Cookbook Name:: resque
# Recipe:: default
#
if ['solo', 'util'].include?(node[:instance_role])
  
  execute "install resque gem" do
    command "gem install resque redis redis-namespace yajl-ruby -r"
    not_if { "gem list | grep resque" }
  end

  workers = %w{ab ab email email analytics crm signals}
  num_workers = workers.length
  
  node[:applications].each do |app, data|
    template "/etc/monit.d/resque_#{app}.monitrc" do 
    owner 'root' 
    group 'root' 
    mode 0644 
    source "monitrc.conf.erb" 
    variables({ 
    :num_workers => num_workers,
    :app_name => app, 
    :rails_env => node[:environment][:framework_env] 
    }) 
    end
    
    count = 0
    workers.each do |worker_queue|
      template "/data/#{app}/shared/config/resque_#{count}.conf" do
        owner node[:owner_name]
        group node[:owner_name]
        mode 0644
        source "resque.conf.erb"
        variables({
          :queue => worker_queue
        })
      end
      count = count + 1
    end

    execute "ensure-resque-is-setup-with-monit" do 
      command %Q{ 
      monit reload 
      } 
    end

    execute "restart-resque" do 
      command %Q{ 
        echo "sleep 20 && monit -g #{app}_resque restart all" | at now 
      }
    end
  end 
end

node[:applications].each do |app, data|
  if ['solo', 'app', 'app_master', 'util'].include?(node[:instance_role])
    template "/data/#{app}/shared/config/resque.yml" do
      owner node[:owner_name]
      group node[:owner_name]
      mode 0644
      source "resque.yml.erb"    
      variables({
          :server_name => node[:utility_instances].first[:hostname]
      })    
    end  
  end
end