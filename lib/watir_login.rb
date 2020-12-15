require 'watir'
require 'yaml'

configs_file='./../config/login.yaml'
CLIENTS=YAML.load_file configs_file
browser = Watir::Browser.new :firefox, headless: true

CLIENTS.each do |record|
  url=record[:login_url]
  client=record[:client]
  password=record[:password]
  otp=record[:otp]
  record[:access_token] = nil
  record[:request_token] = "API-ERROR"

  begin
    browser.goto url
  rescue
    record[:access_token] = nil
    record[:request_token] = "API-ERROR"
    next
  end

  browser.input(id: "userid").send_keys client
  browser.input(id: "password").send_keys password

  browser.button(:visible_text => "Login").click
  
  browser.input(id: "pin").send_keys otp 
  
  begin
    browser.button(:visible_text => "Continue").click
  rescue
  end

  sleep 1
  puts browser.url
  request_token=browser.url.split("request_token=")[1].split("&")[0]

  record[:access_token] = nil 
  record[:request_token] = request_token
end

File.open(configs_file, 'w') {|f| f.write CLIENTS.to_yaml }
