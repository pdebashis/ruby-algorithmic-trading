# ruby-algorithmic-trading
A simple ruby algorithmic trading framework capable of automated buying or selling using predefined set of rules
Supports Kite/Fyer API

###### Features
- Buy and Sell using existing strategies
- Formulate trading strategy using the framework
- Back-testing and Live-testing
- Measure and optimize with the help of reports

###### Setup
- rvm install 2.5.5
- git clone <git-url>
- Create config.yaml,	Kite.yaml, Fyer.yaml
- Add geckodriver to $PATH
- yum install firefox
- gem install watir
- gem install telegram-bot-ruby
- gem install selenium-webdriver
- gem install frappuccino
- gem install eventmachine
- gem install websocket
- gem install faye-websocket
- gem install ffi

###### AWS Deployment
1. Setup a VPC(65000 IPs) and have a subnet (251 IPs). VPC requires a region and IP range
2. Setup a sbnet in suitable availability zone.
3. Enable public IPv4 address on subnet
4. VPS is associated with an IGW (Internet Gateway)
5. Route Table is created with a route for internet and linked with IGW. Route table is attached with subnet
10.10.0.0/16	local	active	No
0.0.0.0/0	igw-02e8fcae3e93820c8	active	No
6. Create ad launch an instance using this VPC and subnet.
7. sudo yum install -y git curl gpg gcc gcc-c++ make
