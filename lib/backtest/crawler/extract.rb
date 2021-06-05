require 'net/https'
require 'uri'
require 'json'

class ExtractCandles
  attr_reader :url

  def initialize()
    @from_date="2021-01-01"
    @to_date="2021-06-04"
    @user="NC7756"
    @authorizaton="enctoken naWkjqZ1OmRYqh6GYx1OnJZvDIpHadnHT2NrdsDXKhUXrRQw9BTLDFtddjMOe3PRxoiLqK9VU4bMyLF68toqHbH8XJgVuA=="
  end

  def any?
  	parsed_json = JSON.parse(response_body)
        parsed_json["data"]["candles"].each do |child|

      puts "#{child[0]},#{child[1]},#{child[2]},#{child[3]},#{child[4]},#{child[5]}"
  	end
  	""
  end

  private

  def response_body
  	uri = URI("https://kite.zerodha.com/oms/instruments/historical/260105/15minute?user_id=#{@user}&oi=1&from=#{@from_date}&to=#{@to_date}")

	response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
	  request = Net::HTTP::Get.new(uri)
	  request["authorization"] = @authorizaton
	  http.request(request) 
	end

    response.body
  end

end

puts ExtractCandles.new().any?

#Make sure the ordering of columns is as expected 
#cat 2020.csv | awk -F',' '{print $2","$3","$4","$5","$1}' > 2020.csv.fixed