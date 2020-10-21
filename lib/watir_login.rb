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

  browser.goto url
  sleep(1)
  browser.input(id: "userid").send_keys client
  browser.input(id: "password").send_keys password

  browser.button(:visible_text => "Login").click
  sleep(1)

  browser.input(id: "pin").send_keys otp 
  browser.button(:visible_text => "Continue").click
  sleep(1)

  puts browser.url

  request_token=browser.url.split("request_token=")[1].split("&")[0]

  record[:access_token] = nil 
  record[:request_token] = request_token
end

File.open(configs_file, 'w') {|f| f.write CLIENTS.to_yaml }
