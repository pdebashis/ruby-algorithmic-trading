require 'net/https'
require 'uri'
require 'json'

class ExtractCandles
  attr_reader :url

  def initialize()
    @from_date="2021-01-23"
    @to_date="2021-01-31"
    @user="YD7348"
    @authorizaton="enctoken zAuvBHLOoKFSJvIDO0dyQsSaI9/mxhw9IqkdIJgiGxfbPxHk5b3TyMLbCJUC9I6u6BgeZLhJ64gQwkZpX+7nu09ZZ1i3xA=="
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
  	uri = URI("https://kite.zerodha.com/oms/instruments/historical/121345/15minute?user_id=#{@user}&oi=1&from=#{@from_date}&to=#{@to_date}")

	response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
	  request = Net::HTTP::Get.new(uri)
	  request["authorization"] = @authorizaton
	  http.request(request) 
	end

    response.body
  end

end

puts ExtractCandles.new().any?
