#
# Cookbook Name:: resque
# Recipe:: default
#
if ['solo', 'util'].include?(node[:instance_role])
  
  execute "install resque gem" do
    command "gem install resque redis redis-namespace yajl-ruby -r"
    not_if { "gem list | grep resque" }
  end

  workers = %w{emailp1 emailp1,emailp3 fileprocessingp2,emailp1,emailp3 fileprocessingp2,emailp1,emailp3 emailp3,emailp1 backgroundp4,backgroundp5 backgroundp5,backgroundp6 longjobsp7}
  num_workers = workers.length
  
  node[:applications].each do |app, data|
    # Only set it up for the Tout app (not ToutAdmin which occupies the same environment)
    if app == 'Tout' then
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

      # Don't set up workers in the Redis instance, set it up in the rest of them
      if(!node[:name].match(/ResqueAndRedis/) or node[:instance_role] == "solo")
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
  end
end

resque_and_redis_instances = @node["utility_instances"].select { |ui| ui["name"].match(/ResqueAndRedis/) }
resque_and_redis_instance = resque_and_redis_instances.last

node[:applications].each do |app, data|
  if ['solo', 'app', 'app_master', 'util'].include?(node[:instance_role])
    template "/data/#{app}/shared/config/resque.yml" do
      owner node[:owner_name]
      group node[:owner_name]
      mode 0644
      source "resque.yml.erb"    
      variables({
          :server_name => resque_and_redis_instance[:hostname]
      })    
    end  
  end
end