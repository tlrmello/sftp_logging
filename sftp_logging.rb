#!/usr/local/bin/env ruby

require 'net/http'
require 'json'
require 'optparse'
require 'pp'
require 'launchy'


options = {}
op = OptionParser.new do |opts|
  opts.on('-k', '--api-key=api_key',           'Your Fastly API key (required)') do |api_key|
    options[:api_key] = api_key
  end
  opts.on('-n', '--name=name',                 'The logging object name (required)') do |name|
    options[:name] = name
  end
  opts.on '-s', '--service=service_id',        'The Service ID (required)' do |service_id|
    options[:service_id] = service_id
  end
  opts.on '-v', '--version=version',           'The version number (required)' do |version|
    options[:version] = version
  end
  opts.on '-f', '--format[=format]',           'The logging format' do |fmt|
    options[:format] = fmt
  end
  opts.on '-a', '--address[=address]',         'The address of the host (with optional ":port" on the end)' do |address|
    options[:address], options[:port] = address.split(':')
    options[:port] ||= 22
  end
  opts.on '-d', '--directory[=directory]',     'The directory to stick log files in' do |directory|
    options[:path] = directory
  end
  opts.on '-u', '--user[=user]',               'The SSH username' do |user|
    options[:user] = user
  end
  opts.on '-p', '--password[=password]',       'The SSH password' do |password|
    options[:password] = password
  end
  opts.on '-s', '--secret-key[=secret_key]', 'The private SSH key (can be the key itself or a filename)' do |secret_key|
    secret_key=File.read(secret_key) if File.readable?(secret_key)
    options[:secret_key] = secret_key
  end
  opts.on '-h', '--known-host[=known_host]',   'The known_host file entry' do |known_host|
    options[:public_key] = known_host
  end
  opts.on '-g', '--gzip=[gzip]',               'The GZIP level' do |gzip|
    options[:gzip_level] = gzip
  end
  opts.on '-r', '--rotation[=rotation]', 'The log file rotation period in seconds' do |period|
    options[:period] = period
  end
  opts.on '-t', '--timestamp-format[=timestamp_format]', 'The format of the timestamp' do |timestamp_format|
    options[:timestamp_format] = timestamp_format
  end
  opts.on '-c', '--condition[=response_condition]', 'The name of a response condition to attach this logger to' do |condition|
    options[:response_condition] = condition
  end
end


op.parse!
#options.each {|key, value| puts "#{key} is #{value}" }

abort("You must pass in --api-key, --name --service and --version") unless options[:api_key] &&
                                                                           options[:name] &&
                                                                           options[:service_id] &&
                                                                           options[:version]




#check version provided is dev, if not, initiate cloning 
puts "Verifying provided version number..."
version_verification_url = "https://api.fastly.com" + "/service/" + options[:service_id] + "/version/" + options[:version] 
uri = URI(version_verification_url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
request = Net::HTTP::Get.new(uri.request_uri)
request['Fastly-Key'] = options[:api_key]
response = http.request(request)
response = JSON.parse(response.body)
active_version = response["active"]
locked_version = response["locked"]
if active_version.to_s == "true"
    #offer clone
    puts "The version provided is the current active version of the service. Clone the current active version to create an SFTP logging endpoint on? [Y/N]"
        clone = gets.strip.upcase
        if clone == "Y"
          #clone current active version
          clone_url = "https://api.fastly.com" + "/service/" + options[:service_id] + "/version/" + options[:version] + "/clone"
          uri = URI(clone_url)
          http = Net::HTTP.new(uri.host, uri.port)
          request = Net::HTTP::Put.new(uri.request_uri)
          http.use_ssl = true
          request['Fastly-Key'] = options[:api_key]
          request['Content-Type'] = "application/x-www-form-urlencoded"
          request['Accept'] = "application/json"
          response = http.request(request)
          response = JSON.parse(response.body)
          new_dev_version = response["number"]
          if Net::HTTPSuccess  
            puts "Version cloned. Creating SFTP logging enpoint on version #{new_dev_version}..."
            puts "Checking required fields..."
            #Verify ARGS supplied
            if options[:format] == nil || options[:format] == ""
                puts "Format is empty. Please enter a log format to be used. If none entered, will default too '%h %l %u %t %r %>s'."
                options[:format] = gets.chomp
                    if options[:format] == ""
                        options[:format] = "%h %l %u %t %r %>s"
                    end
            end

            if options[:address] == nil || options[:address] == ""
                puts "Address is empty. Please enter an address to be used:"
                options[:address] = gets.chomp
            end

            if options[:user] == nil || options[:user] == ""
                puts "User is empty. Please enter a user to be used:"
                options[:user] = gets.chomp
            end

            if options[:path] == nil || options[:path] == ""
                puts "Path is empty. Please enter a file path to save the files too. If none entered, will default too '/'."
                options[:path] = gets.chomp
                    if options[:format] == ""
                        options[:format] = "/"
                    end
            end

            if options[:secret_key] == nil || options[:secret_key] == ""
                puts "Secret key is empty. Please enter the path in which the private key is saved too:"
                secret_key = gets.chomp
                options[:secret_key] = File.read(secret_key)

            end

            if options[:public_key] == nil || options[:public_key] == ""
                puts "Public key is empty. Please enter a known_hosts entry to be used in the public_key field:"
                public_key = gets.chomp
                options[:public_key] = File.read(public_key)
            end
            
            #POST to create logging endpoint                                                                    
            post_url = "https://api.fastly.com" + "/service/" + options[:service_id] + "/version/#{new_dev_version}/logging/sftp"
            uri = URI(post_url)
            http = Net::HTTP.new(uri.host, uri.port)
            request = Net::HTTP::Post.new(uri.request_uri)
            http.use_ssl = true
            request['Content-Type'] = "application/json"
            request['Fastly-key'] = options[:api_key]
            request.set_form_data({"name" => "#{options[:name]}", "address" => "#{options[:address]}", "port" => "22", "format" => "#{options[:format]}", "user" => "#{options[:user]}", "secret_key" => "#{options[:secret_key]}", "public_key" => "#{options[:public_key]}"})
            response = http.request(request)
            if Net::HTTPSuccess
              endpoint_url = "https://manage.fastly.com/configure/services/#{options[:service_id]}/versions/#{new_dev_version}/logging/#{options[:name]}/edit"
              puts "Endpoint created successfully. Please review the SFTP configuration before activating. Would you like to open the configuration in your browser? [Y/N]"
              launch = gets.strip.upcase
                if launch == "Y" 
                  Launchy.open(endpoint_url)
                else
                puts "Setup complete. Goodbye!"
                end
            else 
              puts "There was an issue creating the SFTP logging endpoint. Please see error information below."
              puts "#{response.code} #{response.message}"
              puts "#{response.body}" 
            end
          else 
            puts "There was an issue cloning the service. Please see error information below."
            puts "#{response.code} #{response.message}"
            puts "#{response.body}" 
          end
        else 
            #end script
            puts "Please retry and provide a development version to create or update an SFTP endpoint on."
        end
elsif locked_version.to_s == "true"
  puts "This is a locked version. Please try again and provide an active or in-development version to use." 
else 
    puts "The version provided is a development version, ok to modify service."
    puts "Verifying provided endpoint name..."
    #check name supplied already exists, if not, offer post                                                                        
    url = "https://api.fastly.com" + "/service/" + options[:service_id] + "/version/" + options[:version] + "/logging/sftp/" + options[:name]
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri.request_uri)
    request['Fastly-Key'] = options[:api_key]
    response = http.request(request)
    response = JSON.parse(response.body)
    secret_key = response["secret_key"]
    public_key = response["public_key"]
    endpoint_name = response["name"]
    if endpoint_name.to_s == options[:name].to_s
      puts "An SFTP logging endpoint with this name has been found. Update existing endpoint? [Y/N]"
      #check for keys, offer update on both secret and public keys
      update = gets.strip.upcase
      if update == "Y"
        puts "Checking for Secret and Public keys..."
        if secret_key == nil || secret_key == "" 
          puts "No secret key found. Please enter the path in which the private key is saved too:"
          secret_key = gets.chomp
          options[:secret_key] = File.read(secret_key)
        else 
          puts "A secret key has been found. Would you like to provide a new private key to be used? [Y/N]"
          update_secret_key = gets.strip.upcase
          if update_secret_key == "Y"
            puts "Please enter the path in which the private key is saved too:"
            secret_key = gets.chomp
            options[:secret_key] = File.read(secret_key)
          else
            secret_key = nil
          end 
        end 
        if public_key == nil || public_key == "" 
          puts "No public key found. Please enter the path in which the known_hosts entry is saved too:"
          public_key = gets.chomp
          options[:public_key] = File.read(public_key)
        else 
          puts "A public key has been found. Would you like to provide a new known_hosts entry to be used? [Y/N]"
          update_public_key = gets.strip.upcase
          if update_public_key == "Y"
            puts "Please enter the path in which the new known_hosts entry is saved too:"
            public_key = gets.chomp
            options[:public_key] = File.read(public_key)
          else 
            public_key = nil 
          end 
        end

        #check for what needs updating depending on what user sumitted
        if secret_key != nil && public_key == nil
        #send put request with just secret key update
          put_form_data = ({"secret_key" => "#{options[:secret_key]}"})
        elsif secret_key != nil && public_key != nil
          #send put request with both secret key and public key updates
          put_form_data = ({"secret_key" => "#{options[:secret_key]}", "public_key" => "#{options[:public_key]}"})
        elsif secret_key == nil && public_key != nil
          #send put request with just public key update 
          put_form_data = ({"public_key" => "#{options[:public_key]}"})
        else 
          puts "No updates recognized. Please start over and try again."
        end

        put_url = "https://api.fastly.com/service/#{options[:service_id]}/version/#{options[:version]}/logging/sftp/#{options[:name]}"
        uri = URI(put_url)
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Put.new(uri.request_uri)
        http.use_ssl = true
        request['Content-Type'] = "application/json"
        request['Fastly-key'] = options[:api_key]
        request.set_form_data(put_form_data)
        response = http.request(request)
        if Net::HTTPSuccess
          endpoint_url = "https://manage.fastly.com/configure/services/#{options[:service_id]}/versions/#{options[:version]}/logging/#{options[:name]}/edit"
          puts "Endpoint created successfully. Please review the SFTP configuration before activating. Would you like to open the configuration in your browser? [Y/N]"
          launch = gets.strip.upcase
            if launch == "Y" 
              Launchy.open(endpoint_url)
            else
            puts "Setup complete. Goodbye!"
            end
        else 
          puts "There was an issue creating the SFTP logging endpoint. Please see error information below."
          puts "#{response.code} #{response.message}"
          puts "#{response.body}" 
        end
      else
        puts "Please start over and provide an endpoint name and version number in which you'd like to create or update an existing SFTP endoint on."
      end
    else 
      puts "An SFTP logging endpoint with this name has not been found. Create a new endpoint with this name? [Y/N]"
      create = gets.strip.upcase
      if create == "Y"
        #create new endpoint with Args
        puts "Checking required fields..."
            #Verify ARGS supplied
            if options[:format] == nil || options[:format] == ""
                puts "Format is empty. Please enter a log format to be used. If none entered, will default too '%h %l %u %t %r %>s'."
                options[:format] = gets.chomp
                    if options[:format] == ""
                        options[:format] = "%h %l %u %t %r %>s"
                    end
            end

            if options[:address] == nil || options[:address] == ""
                puts "Address is empty. Please enter an address to be used:"
                options[:address] = gets.chomp
            end

            if options[:user] == nil || options[:user] == ""
                puts "User is empty. Please enter a user to be used:"
                options[:user] = gets.chomp
            end

            if options[:path] == nil || options[:path] == ""
                puts "Path is empty. Please enter a file path to save the files too. If none entered, will default too '/'."
                options[:path] = gets.chomp
                    if options[:format] == ""
                        options[:format] = "/"
                    end
            end

            if options[:secret_key] == nil || options[:secret_key] == ""
                puts "Secret key is empty. Please enter the path in which the private key is saved too:"
                secret_key = gets.chomp
                options[:secret_key] = File.read(secret_key)

            end

            if options[:public_key] == nil || options[:public_key] == ""
                puts "Public key is empty. Please enter a known_hosts entry to be used in the public_key field:"
                public_key = gets.chomp
                options[:public_key] = File.read(public_key)
            end
            
            #POST to create logging endpoint                                                                    
            post_url = "https://api.fastly.com/service/#{options[:service_id]}/version/#{options[:version]}/logging/sftp"
            uri = URI(post_url)
            http = Net::HTTP.new(uri.host, uri.port)
            request = Net::HTTP::Post.new(uri.request_uri)
            http.use_ssl = true
            request['Content-Type'] = "application/json"
            request['Fastly-key'] = options[:api_key]
            request.set_form_data({"name" => "#{options[:name]}", "address" => "#{options[:address]}", "port" => "22", "format" => "#{options[:format]}", "user" => "#{options[:user]}", "secret_key" => "#{options[:secret_key]}", "public_key" => "#{options[:public_key]}"})
            response = http.request(request)
            if Net::HTTPSuccess
            endpoint_url = "https://manage.fastly.com/configure/services/#{options[:service_id]}/versions/#{options[:version]}/logging/#{options[:name]}/edit"
              puts "Endpoint created successfully. Please review the SFTP configuration before activating. Would you like to open the configuration in your browser? [Y/N]"
              launch = gets.strip.upcase
              if launch == "Y" 
                Launchy.open(endpoint_url)
              else
                puts "Setup complete. Goodbye!"
              end
            else 
              puts "There was an issue creating the SFTP logging endpoint. Please see error information below."
              puts "#{response.code} #{response.message}"
              puts "#{response.body}" 
            end
      else
        #end script
        puts "Please try again and provide a new service version number in which to create or update an SFTP endpoint on."
      end
    end
end
