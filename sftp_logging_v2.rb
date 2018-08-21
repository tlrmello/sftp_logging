#!/usr/local/bin/env ruby

require 'rubygems'
require 'httparty'
require 'json'
require 'pp'
require 'launchy'

#Receive API Key, Endpoint name, Serivce ID, and Version # as ARGS
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
end

op.parse!

#Bow out if missing any values
abort("You must pass in --api-key, --name --service and --version") unless options[:api_key] &&
                                                                           options[:name] &&
                                                                           options[:service_id] &&
                                                                           options[:version]
#Assign global variables
$key = options[:api_key]
$service_id = options[:service_id]
$name = options[:name]
$service_version = options[:version]
$base_uri = "https://api.fastly.com"

#"Requestor" holds the methods of the various HTTP Requests we're making to the Fastly API
class Requestor
  include HTTParty
  base_uri $base_uri
  #below line is used to debug requests at the class level
  #debug_output $stdout

  #GET Version: Retrieve the attributes of the specified version
  def get_version
    response = self.class.get("/service/#{$service_id}/version/#{$service_version}", {
    headers: {"Fastly-Key" => $key}
    })
  end

  #GET Verify_name: Verify the name of the endpoint provided
  def get_name
    response = self.class.get("/service/#{$service_id}/version/#{$service_version}/logging/sftp/#{$name}", {
    headers: {"Fastly-Key" => $key} 
    })
  end

  #PUT Clone: Clone specififed version to a new development version
  def put_clone
    response = self.class.put("/service/#{$service_id}/version/#{$service_version}/clone", { 
    headers: {"Fastly-Key" => $key} 
    })
  end

  #POST Create: Create a new SFTP logging endpoint
  def post_create
    response = self.class.post("/service/#{$service_id}/version/#{$service_version}/logging/sftp", 
        headers: { "Fastly-Key" => $key},
        body: { "name" => "#{$name}",
                "address" => "#{$address}",
                "port" => "22",
                "format" => "#{$log_format}",
                "user" => "#{$user}",
                "secret_key" => "#{$secret_key}",
                "public_key" => "#{$public_key}" })
  end

  #POST Create on cloned version: Create a new SFTP logging endpoint on a cloned version
  def post_create_clone
    response = self.class.post("/service/#{$service_id}/version/#{$new_dev_version}/logging/sftp", 
        headers: { "Fastly-Key" => $key},
        body: { "name" => "#{$name}",
                "address" => "#{$address}",
                "port" => "22",
                "format" => "#{$log_format}",
                "user" => "#{$user}",
                "secret_key" => "#{$secret_key}",
                "public_key" => "#{$public_key}" })
  end

  #PUT Update: Update an existing SFTP logging endpoint
  def put_update
    response = self.class.put("/service/#{$service_id}/version/#{$service_version}/logging/sftp/#{$name}", 
        headers: { "Fastly-Key" => $key }, 
        body: $put_form_data )
  end

end

#Verify version supplied
get_version = Requestor.new.get_version
if get_version.success?
    get_version = JSON.parse(get_version.body)
    active_version = get_version["active"]
    locked_version = get_version["locked"]
    if active_version.to_s == "true"
        #Offer clone
        puts "The version provided is the current active version of the service. Clone the current active version to create an SFTP logging endpoint on? [Y/N]"
        clone = gets.strip.upcase
        if clone == "Y"
            #Clone current active version
            put_clone = Requestor.new.put_clone
            if put_clone.success? 
                $new_dev_version = put_clone["number"]
                puts "Version cloned. Creating SFTP logging enpoint on version #{$new_dev_version}..."
                puts "Checking required fields..."
                puts "Please enter a log format to be used. If none entered, will default too '%h %l %u %t %r %>s'."
                $log_format = gets.chomp
                    if $log_format == ""
                        $log_format = "%h %l %u %t %r %>s"
                    end
                puts "Please enter an address to be used:"
                $address = gets.chomp
                puts "Please enter a user to be used:"
                $user = gets.chomp
                puts "Please enter a file path to save the files too. If none entered, will default too '/'."
                $path = gets.chomp
                    if $path == ""
                        $path = "/"
                    end
                puts "Secret key is empty. Please enter the path in which the private key is saved too:"
                secret_key_location = gets.chomp
                $secret_key = File.read(secret_key_location)
                puts "Public key is empty. Please enter a known_hosts entry to be used in the public_key field:"
                public_key_location = gets.chomp
                $public_key = File.read(public_key_location)   
                
                #Issue POST to create logging endpoint with supplied variables
                post_create_clone = Requestor.new.post_create_clone
                if post_create_clone.success? 
                    #successful post
                    endpoint_url = "https://manage.fastly.com/configure/services/#{$service_id}/versions/#{$new_dev_version}/logging/#{$name}/edit"
                    puts "Endpoint created successfully. Please review the SFTP configuration before activating. Would you like to open the configuration in your browser? [Y/N]"
                    launch = gets.strip.upcase
                    if launch == "Y" 
                        Launchy.open(endpoint_url)
                    else
                        puts "Setup complete. Goodbye!"
                    end
                else
                    #failed post
                    puts "There was an issue creating the logging endpoint. Please see error messaging below, and try again."
                    puts post_create_clone.code
                    puts post_create_clone.message
                    puts post_create_clone.body
                end
            else 
                puts "There was an issue cloning the service. Please see error information below."
                puts "#{put_clone.code} #{put_clone.message}"
                puts "#{put_clone.body}"
            end
        else 
            puts "Please retry and provide a development version to create or update an SFTP endpoint on."
        end
    elsif locked_version.to_s == "true"
    puts "This is a locked version. Please try again and provide an active or in-development version to use."
    else 
    #Modify dev service
    puts "The version provided is a development version, ok to modify service."
    puts "Verifying provided endpoint name..."
    #check name supplied already exists, if not, offer post 
    get_name = Requestor.new.get_name
    if get_name.success?
        get_name = JSON.parse(get_name.body)    
        secret_key = get_name["secret_key"]
        public_key = get_name["public_key"]
        endpoint_name = get_name["name"]
        puts "An SFTP logging endpoint with this name has been found. Update existing endpoint? [Y/N]"
        #check for keys, offer update on both secret and public keys
        update = gets.strip.upcase
        if update == "Y"
          puts "Checking for Secret and Public keys..."
          if secret_key == nil || secret_key == "" 
            puts "No secret key found. Please enter the path in which the private key is saved too:"
            secret_key = gets.chomp
            $secret_key = File.read(secret_key)
          else 
            puts "A secret key has been found. Would you like to provide a new private key to be used? [Y/N]"
            update_secret_key = gets.strip.upcase
            if update_secret_key == "Y"
              puts "Please enter the path in which the private key is saved too:"
              secret_key = gets.chomp
              $secret_key = File.read(secret_key)
            else
              secret_key = nil
            end 
          end 
          if public_key == nil || public_key == "" 
            puts "No public key found. Please enter the path in which the known_hosts entry is saved too:"
            public_key = gets.chomp
            $public_key = File.read(public_key)
          else 
            puts "A public key has been found. Would you like to provide a new known_hosts entry to be used? [Y/N]"
            update_public_key = gets.strip.upcase
            if update_public_key == "Y"
              puts "Please enter the path in which the new known_hosts entry is saved too:"
              public_key = gets.chomp
              $public_key = File.read(public_key)
            else 
              public_key = nil
            end 
          end
          
          #check for what needs updating depending on what user sumitted
          if $secret_key != nil && $public_key == nil
            #send put request with just secret key update
            $put_form_data = {"secret_key" => "#{$secret_key}"}
          elsif $secret_key != nil && $public_key != nil
            #send put request with both secret key and public key updates
            $put_form_data = {"secret_key" => "#{$secret_key}", "public_key" => "#{$public_key}"}
          elsif $secret_key == nil && $public_key != nil
            #send put request with just public key update 
            $put_form_data = {"public_key" => "#{$public_key}"}
          else 
            puts "No updates recognized. Please start over and try again."
          end

          #Issue PUT to update existing SFTP logging endpoint
          put_update = Requestor.new.put_update
          if put_update.success? 
            endpoint_url = "https://manage.fastly.com/configure/services/#{$service_id}/versions/#{$service_version}/logging/#{$name}/edit"
            puts "Endpoint updated successfully. Please review the SFTP configuration before activating. Would you like to open the configuration in your browser? [Y/N]"
            launch = gets.strip.upcase
            if launch == "Y" 
              Launchy.open(endpoint_url)
            else
            puts "Setup complete. Goodbye!"
            end
        else 
          puts "There was an issue creating the SFTP logging endpoint. Please see error information below."
          puts "#{put_update.code} #{put_update.message}"
          puts "#{put_update.body}" 
        end
    else 
        #end script
        puts "Please retry and provide a development version to create or update an SFTP endpoint on."
    end
    else 
        puts "An SFTP logging endpoint with this name has not been found. Create a new endpoint with this name? [Y/N]"
        create = gets.strip.upcase
        if create == "Y"
            #create new endpoint with Args
            puts "Checking required fields..."
            #ask for required attributes
            puts "Please enter a log format to be used. If none entered, will default too '%h %l %u %t %r %>s'."
                $log_format = gets.chomp
                    if $log_format == ""
                        $log_format = "%h %l %u %t %r %>s"
                    end
                puts "Please enter an address to be used:"
                $address = gets.chomp
                puts "Please enter a user to be used:"
                $user = gets.chomp
                puts "Please enter a file path to save the files too. If none entered, will default too '/'."
                $path = gets.chomp
                    if $path == ""
                        $path = "/"
                    end
                puts "Secret key is empty. Please enter the path in which the private key is saved too:"
                secret_key_location = gets.chomp
                $secret_key = File.read(secret_key_location)
                puts "Public key is empty. Please enter a known_hosts entry to be used in the public_key field:"
                public_key_location = gets.chomp
                $public_key = File.read(public_key_location)   
                
                #Issue POST to create logging endpoint with supplied variables
                post_create = Requestor.new.post_create
                if post_create.success? 
                    #successful post
                    endpoint_url = "https://manage.fastly.com/configure/services/#{$service_id}/versions/#{$service_version}/logging/#{$name}/edit"
                    puts "Endpoint created successfully. Please review the SFTP configuration before activating. Would you like to open the configuration in your browser? [Y/N]"
                    launch = gets.strip.upcase
                    if launch == "Y" 
                        Launchy.open(endpoint_url)
                    else
                        puts "Setup complete. Goodbye!"
                    end
                else
                    #failed post
                    puts post_create.code
                    puts post_create.message
                    puts post_create.body
                end
        else
            #end script
            puts "Please try again and provide a new service version number in which to create or update an SFTP endpoint on."
        end
    end
    end
else 
    puts "There was an error verifying the supplied information. Please see error messaging below and try again."
    puts "#{get_version.code} #{get_version.message}" 
    puts "#{get_version.body}"
end