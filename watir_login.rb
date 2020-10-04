require 'watir'
require 'yaml'

CONFIG=OpenStruct.new YAML.load_file 'config/config.yaml'
url=CONFIG.login_url
client=CONFIG.client
password=CONFIG.password
otp=CONFIG.otp

browser = Watir::Browser.new :firefox, headless: true
browser.goto url
sleep(2)
browser.input(id: "userid").send_keys client
browser.input(id: "password").send_keys password

browser.button(:visible_text => "Login").click
sleep(2)

browser.input(id: "pin").send_keys otp 
browser.button(:visible_text => "Continue").click
sleep(2)

puts browser.url

request_token=browser.url.split("request_token=")[1].split("&")[0]

CONFIG[:access_token] = nil 
CONFIG[:request_token] = request_token

File.open('config/config.yaml', 'w') {|f| f.write CONFIG.to_yaml }
