class Feeder

  def initialize (ticker, logger=nil, instrument=nil)
    @ticker = ticker    
    @logger = logger
    @today = Time.now.getlocal("+05:30").strftime "%Y:%m:%d"
    @ticks = {}      
    #@ticks = {"14:15"=>[21591,21400,21600,21592]}
    @bars = {}
    @d1=Time.strptime("09:13 +05:30","%H:%M %Z")
    @d2=Time.strptime("15:16 +05:30","%H:%M %Z")
    @instrument=instrument
  end

  def start
    EventMachine.run do
      @ticker.ws = Faye::WebSocket::Client.new(@ticker.socket_url)

      @ticker.ws.on :open do |event|
        self.subscribe (@instrument)
      end

      @ticker.ws.on :message do |event|
        socket_feed = @ticker.make_sense( event.data )
        self.fetch socket_feed if event.data.kind_of?(Array) and event.data.size > 2
        
        @logger.info socket_feed if event.data.kind_of?(String)
      end

      @ticker.ws.on :close do |event|
        @logger.info [:close, event.code, event.reason]
        @ticker.ws = nil
        EventMachine::stop_event_loop
      end
    end
  end

  def subscribe (token)
    @logger.info "Subscribed succesfully to #{token}" if @ticker.subscribe(token)
    @logger.info "Mode set to FULL" if @ticker.set_mode("full", token)
  end

  def unsubscribe (token)
    @logger.info "Unsubscribed succesfully to #{token}" if @ticker.unsubscribe(token)
  end

  def fetch tick
    @logger.info tick
    tick.each do |hash_of_tick|
      unless hash_of_tick[:instrument_token].equal? @instrument
        fetch_strike_tick hash_of_tick 
        next
      end 
      epoch = hash_of_tick[:timestamp]
      
      time_now=Time.at(epoch).getlocal("+05:30")
      
      close_ws if time_now > @d2 
      return unless time_now.between?(@d1,@d2)

      time_h = time_now.hour
      time_m = time_now.min
      time_c = time_m/15
      time = "#{time_h}:#{time_c*15}"
      last_price = hash_of_tick[:last_price]
 
      if @ticks[time]
        emit tick: last_price
        @ticks[time] << last_price
      else
        persist_bar unless @ticks.empty?
        @ticks = {}
        @ticks[time] = [last_price]
        @logger.info "signal:new time frame received"
        emit tick: last_price
      end
    end
  end

  private

  def persist_bar
    @logger.debug "Number of ticks captured in last time frame:#{@ticks.values.first.size}"
    return if @ticks.values.first.size < 600
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
  end

  def add_bar hash
    time = hash[:time]
    @bars[time] ||= Bar.new @today
    @bars[time].add_bar_data @instrument,hash
    @logger.info "Emitted Bar"
    emit bar: @bars[time]
  end

  def fetch_strike_tick hash
    emit strike: hash[:last_price]
  end


  def close_ws
    @logger.info "signal:close received"
    @logger.info @bars
    @ticker.ws.close
  end
end
