require 'watir'
require 'yaml'

configs_file='./../config/fyer.yaml'
CLIENTS=YAML.load_file configs_file
browser = Watir::Browser.new :firefox, headless: true

CLIENTS.each do |record|
  url=record[:login_url] + "&response_type=code&state=ruby"
  client=record[:client]
  password=record[:password]
  dob=record[:otp]
  record[:access_token] = nil
  record[:request_token] = "API-ERROR"

  begin
    browser.goto url
  rescue
    record[:access_token] = nil
    record[:request_token] = "API-ERROR"
    next
  end

  browser.input(id: "fyers_id").send_keys client
  browser.input(id: "password").send_keys password

  sleep 1

  radio=browser.radio(:id=>"Dobcheck")
  browser.execute_script("arguments[0].click();",radio)
  browser.input(id: "dob").send_keys dob
  
  sleep 1

  checkbox=browser.checkbox
  browser.execute_script("arguments[0].click();",checkbox)

  begin
    browser.button(:id => "btn_id").click
  rescue
  end
  
  sleep 3
  puts browser.url
  ok=browser.url.split("code=")[1].split("&")[0]
  continue unless ok == "200"
  request_token=browser.url.split("auth_code=")[1].split("&")[0]

  record[:access_token] = nil 
  record[:request_token] = request_token
end

File.open(configs_file, 'w') {|f| f.write CLIENTS.to_yaml }
