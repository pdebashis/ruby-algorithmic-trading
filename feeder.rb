class Feeder


  def initialize (ticker, logger=nil)
    @ticker = ticker    
    @logger = logger
    @today = Time.now.getlocal("+05:30").strftime "%Y:%m:%d"
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
    epoch = tick.first[:timestamp]
    time_h = Time.at(epoch).getlocal("+05:30").hour
    time_m = Time.at(epoch).getlocal("+05:30").hour/ 15
    time = "#{time_h}:#{time_m*15}"
    last_price = tick.first[:last_price]
    
    if @ticks[time]
      emit tick: last_price
      @ticks[time] << last_price
    else
      persist_bar
      @ticks[time] = [last_price]
      emit tick: last_price
    end
    @logger.info @ticks
  end

  private

  def persist_bar
    @ticks.each do |k,v|
      d = {
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
    emit bar: @bars[time]
  end
end
