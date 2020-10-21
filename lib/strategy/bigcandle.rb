class StrategyBigCandle
  def initialize traders, feeder, logger=nil
    @user = traders.first
    @users = traders
    @feeder = feeder
    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:bar) && !event[:bar].nil? }.
      map{ |event| event[:bar] }.
      on_value(&method(:on_bar))

    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:tick) && !event[:tick].nil? }.
      map{ |event| event[:tick] }.
      on_value(&method(:on_tick))
   
    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:strike) && !event[:strike].nil? }.
      map{ |event| event[:strike] }.
      on_value(&method(:on_strike))

    @telegram_bot=TelegramBot.new

    @logger = logger
    @quantity=0
    @levels=[]
    @decision_map={:big_candle => false, :trigger_price => 0, :wait_buy => false, :wait_sell => false}

    @net_day=0
   
    @instrument = 0
    @strike = ""
    @trade_target = 9999
    @trade_exit = -9999
    @day_target = 9999
    @trade_flag=false
  end

  def on_bar bar
    bar.bar_data.each do |symbol, data|
      @logger.info "NEW CANDLE #{data}"
      time = data[:time]
      opening = data[:open]
      high = data[:high]
      low = data[:low]
      closing = data[:close]

      if time.eql? "14:45"
        close_day(closing)
      elsif time.eql? "15:0"
        telegram "MARKET CLOSED :: NET:#{@net_day}"
      else
        check_inside_candle(opening,high,low,closing)
        check_big_candle(opening,high,low,closing)
      end
    end
  end

  def on_tick tick
    if @decision_map[:wait_buy]
      if @decision_map[:green]
        buy_ce if tick > @decision_map[:trigger_price]  
      else
        buy_pe if tick < @decision_map[:trigger_price]
      end 
    end
  end

  def on_strike strike
    return unless @decision_map[:wait_sell]
    book_pl_strike(strike) 
  end

  private

  def reset_counters
    @decision_map[:big_candle]=false
    @decision_map[:wait_buy]= false
    @decision_map[:green] = nil 
    @decision_map[:stop_loss]=nil
    @decision_map[:trigger_price] = nil
    @decision_map[:ltp_at_buy]=nil
    if @net_day > @day_target and @trade_flag
      @logger.info "DAY TARGET ACHIEVED(#{@day_target})"
      @trade_flag=false
    end
  end

  def telegram msg
    @logger.info msg
    @telegram_bot.send_message msg 
  end

  def is_big_candle?(o,h,l,c)
    return true if (o-c).abs > 50
  end

  def check_big_candle(o,h,l,c)
    @decision_map[:big_candle] = false
    return unless is_big_candle?(o,h,l,c)
    @decision_map[:big_candle]=true
    @decision_map[:green] = o < c ? true : false
    if @decision_map[:green]
      telegram "BIG GREEN CANDLE FORMED"
    else
      telegram "BIG RED CANDLE FORMED"
    end
    @decision_map[:trigger_price] = @decision_map[:green] ? h : l
    @decision_map[:stop_loss]= @decision_map[:green] ? l : h
    @decision_map[:big_candle_high]=h
    @decision_map[:big_candle_low]=l
  end

  def check_inside_candle(o,h,l,c)
    if @decision_map[:big_candle]
      if h < @decision_map[:big_candle_high] and l > @decision_map[:big_candle_low]
        telegram "INSIDE CANDLE FORMED"
        @logger.info "DECISION MAP : #{@decision_map}"
        @decision_map[:wait_buy]=true
      end
    else
      reset_counters
    end
  end

  def buy_ce
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config.instrument_ce.to_s
    @strike = config.strike_ce
    @quantity = config.quantity
    @trade_target = config.bigcandle_target_per_trade.to_i
    @trade_exit = config.bigcandle_exit_per_trade.to_i 
    @day_target = config.bigcandle_target_per_day.to_i 
   
    if @trade_flag 
      @users.each do |usr|
        usr.place_cnc_order(@strike, "BUY", @quantity, nil, "MARKET") unless @strike.empty?
      end
    end

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty?
    @decision_map[:ltp_at_buy]=ltp_value
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit

    telegram "ORDER PLACED FOR #{@strike} at #{ltp_value} ; TARGET: #{target_value} ; SL: #{sl_value}"
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
    @feeder.subscribe(@instrument)
  end

  def buy_pe
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config.instrument_pe.to_s
    @strike = config.strike_pe
    @quantity = config.quantity
    @trade_target = config.target_per_trade.to_i
    @trade_exit = config.exit_per_trade.to_i
    @day_target = config.target_per_day.to_i  
    
    if @trade_flag
      @users.each do |usr|
       usr.place_cnc_order(@strike, "BUY", @quantity, nil, "MARKET") unless @strike.empty? 
      end
    end

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty?
    @decision_map[:ltp_at_buy]=ltp_value
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit

    telegram "ORDER PLACED FOR #{@strike} at #{ltp_value}; TARGET: #{target_value} ; SL: #{sl_value}"
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
    @feeder.subscribe(@instrument)
  end

  def sell_position
    
    if @trade_flag
      @users.each do |usr|
        usr.place_cnc_order(@strike, "SELL", @quantity, nil, "MARKET") unless @strike.empty?
      end
    end
   
    @decision_map[:wait_sell]=false
    @feeder.unsubscribe(@instrument)
    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty? 
    difference = ltp_value - @decision_map[:ltp_at_buy]
    @net_day+=difference

    telegram "SOLD #{@strike} at #{ltp_value}"
    @instument = 0
    @strike = ""
  end

  def book_pl_strike strike
    profit= strike - @decision_map[:ltp_at_buy]
    if profit > @trade_target or profit < @trade_exit
      sell_position
      @net_day+=profit
      telegram "TRADE CAP REACHED(#{profit}), SELLING POSITION NET_BNF:#{@net_day}"
      reset_counters
    end
  end

  def close_day close
    profit= close - @decision_map[:ltp_at_buy]
    sell_position
    @net_day+=profit
    telegram "MARKET CLOSE REACHED, SELLING POSITION NET_BNF:#{@net_day}"
    reset_counters
  end
end
