class Feeder


  def initialize (ticker, logger=nil)
    @ticker = ticker    
    @logger = logger
    @today = Time.now.strftime "%Y:%m:%d"
    @ticks = {}
    @bars = {}
  end

  def start
    EventMachine.run do
      @ticker.ws = Faye::WebSocket::Client.new(@ticker.socket_url)

      @ticker.ws.on :open do |event|
        @logger.info "Subscribed succesfully to 260105" if @ticker.subscribe(260105)
        @logger.info "Mode set to FULL" if @ticker.set_mode("full", 260105)
      end

      @ticker.ws.on :message do |event|
        socket_feed = @ticker.make_sense( event.data )
        self.fetch socket_feed if event.data.size > 2
      end

      @ticker.ws.on :close do |event|
        @logger.info [:close, event.code, event.reason]
        @ticker.ws = nil
        EventMachine::stop_event_loop
      end
    end
  end

  def fetch tick
    #if 15 minute data, maintain in memory
    time_h = tick.first[:timestamp][0..1]
    time_m = tick.first[:timestamp][3..4].to_i / 15
    time = "#{time_h}:#{time_m*15}"
    last_price = tick.first[:last_price]
    
    if @ticks[time]
      @ticks[time] << last_price
    else
      self.persist
      @ticks[time] = [last_price]
    end
  end

  private

  def persist
    @logger.info @ticks.keys
    @ticks.each do |k,v|
      d = {
        date: @today,
        time: k,
        open: v.first,
        high: v.max,
        low: v.min,
        close: v.last,
      }
      add_bar d
    end
    @ticks = {}
  end

  def add_bar hash
    time = hash[:time]
    @bars[time] ||= Bar.new @today
    @bars[time].add_bar_data 260105,hash
    @logger.info @bars
    emit bar: @bars[time]
  end

  # def add_bar symbol, hash
  #   date = hash[:date]
  #   @bars[date] ||= Bar.new date
  #   @bars[date].add_bar_data symbol, hash
  # end

  # def on_complete response
  #   if response.success?
  #     request = response.request
  #     begin
  #       stock_symbol = request.options[:params][:s].to_s.downcase.to_sym
  #     rescue
  #       return stock_symbol
  #     end
  #     CSV.parse(response.body, headers: true, header_converters: :symbol) do |row|
  #       row = row.to_hash
  #       next if row[:date].blank?
  #       add_bar stock_symbol, row
  #     end
  #   elsif response.timed_out?
  #     # aw hell no
  #     puts '[ERROR] got a time out'
  #   elsif response.code == 0
  #     # Could not get an http response, something's wrong.
  #     puts "[ERROR] response.return_message"
  #   else
  #     # Received a non-successful http response.
  #     puts "[ERROR] HTTP request failed: " + response.code.to_s
  #   end
  # end
end
