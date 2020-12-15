class StrategyBigCandle
  def initialize traders, feeder, logger=nil
    @user = traders.first[:kite_api]
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
    @orb_decision_map={:wait_buy => false, :wait_sell => false}
    @net_day=0
  
    @index = @feeder.instrument.to_s 
    @instrument = 0
    @strike = ""
    @trade_target = 9999
    @trade_exit = -9999
    @day_target = 9999
    @trade_flag=true
    
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @hl_height = config[@index][:big_candle_size].to_i
    @oc_height = @hl_height/2 
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
        check_orb(high,low,time)
        return if @decision_map[:wait_sell] or @orb_decision_map[:wait_sell]
        if @decision_map[:big_candle]
          check_inside_candle(opening,high,low,closing)
        else
          check_big_candle(opening,high,low,closing)
        end
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

    if @decision_map[:wait_sell]
      if @decision_map[:green]
        sell_position if tick < @decision_map[:stop_loss] 
        sell_position if tick > @decision_map[:target_price]
      else
        sell_positon if tick > @decision_map[:stop_loss]
        sell_position if tick < @decision_map[:target_price]
      end
    end

    if @orb_decision_map[:wait_buy]
      if tick > @orb_decision_map[:high]
        @orb_decision_map[:trigger]=@orb_decision_map[:high]
        @orb_decision_map[:target]=@orb_decision_map[:trigger]+300
        @orb_decision_map[:buy]=true
        @orb_decision_map[:stoploss]=@orb_decision_map[:trigger]-80
        orb_buy_ce
      end
      if tick < @orb_decision_map[:low]
        @orb_decision_map[:trigger]=@orb_decision_map[:low]
        @orb_decision_map[:target]=@orb_decision_map[:trigger]-300
        @orb_decision_map[:buy]=false
        @orb_decision_map[:stoploss]=@orb_decision_map[:trigger]+80
        orb_buy_pe
      end
    end

    if @orb_decision_map[:wait_sell]
      if @orb_decision_map[:buy]
        sell_position if tick > @orb_decision_map[:target]
        sell_position if tick < @orb_decision_map[:stoploss]
      end

      if ! @orb_decision_map[:buy]
        sell_position if tick < @orb_decision_map[:target]
        sell_position if tick > @orb_decision_map[:stoploss]
      end
    end

  end

  def on_strike strike
    return unless @decision_map[:wait_sell] or @orb_decision_map[:wait_sell]
    book_pl_strike(strike) 
  end

  private

  def reset_counters
    @decision_map[:big_candle]=false
    @decision_map[:wait_buy]= false
    @decision_map[:wait_sell]=false
    @decision_map[:green] = nil 
    @decision_map[:stop_loss]=nil
    @decision_map[:trigger_price] = nil
    @decision_map[:target_price] = nil
    @decision_map[:ltp_at_buy]=nil
    @decision_map[:size]=0
    if @net_day > @day_target and @trade_flag
      @logger.info "DAY TARGET ACHIEVED(#{@day_target})"
      @trade_flag=false
    end
  end

  def telegram msg
    @logger.info msg
    @telegram_bot.send_message "[#{@index}] #{msg}"
  end

  def check_orb(high,low,time)
    return unless time.eql? "9:15"

    orb_size=(low-high).abs
    if orb_size <= 150
       telegram "ORB candle formed;length=#{orb_size}"
       @orb_decision_map[:high]=high
       @orb_decision_map[:low]=low
       @orb_decision_map[:wait_buy]=true
    else
       @orb_decision_map[:wait_buy]=false
       telegram "ORB candle notformed;length=#{orb_size}"
    end
  end

  def is_big_candle?(o,h,l,c)
    return true if (o-c).abs > @oc_height and (h-l).abs > @hl_height
  end

  def check_big_candle(o,h,l,c)
    return unless is_big_candle?(o,h,l,c)
    reset_counters
    @decision_map[:big_candle]=true
    @decision_map[:size]=(h-l).abs
    @decision_map[:green] = o < c ? true : false
    if @decision_map[:green]
      telegram "BIG GREEN CANDLE FORMED"
    else
      telegram "BIG RED CANDLE FORMED"
    end
    @decision_map[:trigger_price] = @decision_map[:green] ? h : l
    @decision_map[:target_price] = @decision_map[:green] ? h + 150 : l - 150
    @decision_map[:stop_loss]= @decision_map[:green] ? l : h
    @decision_map[:big_candle_high]=h
    @decision_map[:big_candle_low]=l
  end

  def check_inside_candle(o,h,l,c)
    if h < @decision_map[:big_candle_high] and l > @decision_map[:big_candle_low]
      telegram "INSIDE CANDLE FORMED"
      @decision_map[:wait_buy]=true
    else
      @logger.info "BREAKOUT OF RANGE"
      
      reset_counters
      check_big_candle(o,h,l,c)
    end
  end

  def buy_ce
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_ce].to_s
    @strike = config[@index][:strike_ce]
    @quantity = config[@index][:quantity]
    @trade_target = config.bigcandle_target_per_trade.to_i
    @trade_exit = config.bigcandle_exit_per_trade.to_i 
    @day_target = config.bigcandle_target_per_day.to_i 
   
    if @trade_flag 
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        lot_size=usr[:lot_size]
        kite_usr.place_cnc_order(@strike, "BUY", @quantity * lot_size, nil, "MARKET") unless @strike.empty?
      end
    end

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty?
    @decision_map[:ltp_at_buy]=ltp_value
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit

    telegram "ORDER PLACED FOR #{@strike} quantity #{@quantity} at #{ltp_value} ; TARGET: #{target_value} ; SL: #{sl_value}"
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
    @feeder.subscribe(@instrument)
    @logger.info "DECISION MAP : #{@decision_map}"
  end

  def buy_pe
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_pe].to_s
    @strike = config[@index][:strike_pe]
    @quantity = config[@index][:quantity]
    @trade_target = config.bigcandle_target_per_trade.to_i
    @trade_exit = config.bigcandle_exit_per_trade.to_i
    @day_target = config.bigcandle_target_per_day.to_i  
    
    if @trade_flag
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        lot_size=usr[:lot_size]
        kite_usr.place_cnc_order(@strike, "BUY", @quantity * lot_size, nil, "MARKET") unless @strike.empty? 
      end
    end

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty?
    @decision_map[:ltp_at_buy]=ltp_value
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit

    telegram "ORDER PLACED FOR #{@strike} quantity #{@quantity} at #{ltp_value}; TARGET: #{target_value} ; SL: #{sl_value}"
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
    @feeder.subscribe(@instrument)
    @logger.info "DECISION MAP : #{@decision_map}"
  end

  def orb_buy_ce
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_ce].to_s
    @strike = config[@index][:strike_ce]
    @quantity = config[@index][:quantity]
    @trade_target = config.orb_target_per_trade.to_i
    @trade_exit = config.orb_exit_per_trade.to_i
    @day_target = config.bigcandle_target_per_day.to_i

    if @trade_flag
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        lot_size=usr[:lot_size]
        kite_usr.place_cnc_order(@strike, "BUY", @quantity * lot_size, nil, "MARKET") unless @strike.empty?
      end
    end

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty?
    @decision_map[:ltp_at_buy]=ltp_value
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit

    telegram "ORDER PLACED FOR #{@strike} quantity #{@quantity} at #{ltp_value} ; TARGET: #{target_value} ; SL: #{sl_value}"
    @orb_decision_map[:wait_buy]=false
    @orb_decision_map[:wait_sell]=true
    @feeder.subscribe(@instrument)
    @logger.info "DECISION MAP : #{@orb_decision_map}"
  end

  def orb_buy_pe
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_pe].to_s
    @strike = config[@index][:strike_pe]
    @quantity = config[@index][:quantity]
    @trade_target = config.orb_target_per_trade.to_i
    @trade_exit = config.orb_exit_per_trade.to_i
    @day_target = config.bigcandle_target_per_day.to_i

    if @trade_flag
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        lot_size=usr[:lot_size]
        kite_usr.place_cnc_order(@strike, "BUY", @quantity * lot_size, nil, "MARKET") unless @strike.empty?
      end
    end

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty?
    @decision_map[:ltp_at_buy]=ltp_value
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit

    telegram "ORDER PLACED FOR #{@strike} quantity #{@quantity} at #{ltp_value}; TARGET: #{target_value} ; SL: #{sl_value}"
    @orb_decision_map[:wait_buy]=false
    @orb_decision_map[:wait_sell]=true
    @feeder.subscribe(@instrument)
    @logger.info "DECISION MAP : #{@orb_decision_map}"
  end

  def sell_position
    if @trade_flag
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        lot_size=usr[:lot_size]
        kite_usr.place_cnc_order(@strike, "SELL", @quantity * lot_size, nil, "MARKET") unless @strike.empty?
      end
    end

    @decision_map[:wait_sell]=false if @decision_map[:wait_sell]
    @orb_decision_map[:wait_sell]=false if @orb_decision_map[:wait_sell]

    @feeder.unsubscribe(@instrument)
    ltp = @user.ltp(@instrument)
    ltp_value = 0
    ltp_value = ltp.values.first["last_price"] unless ltp.values.empty? 
    difference = ltp_value - @decision_map[:ltp_at_buy]
    @net_day+=difference

    telegram "SELLING #{@strike} at #{ltp}; POINTS: #{difference}" 

    @instument = 0
    @strike = ""
  end

  def book_pl_strike strike
    profit= strike - @decision_map[:ltp_at_buy]
    if profit > @trade_target or profit < @trade_exit
      sell_position
      telegram "TRADE CAP REACHED(#{profit}); NET_BNF:#{@net_day}"
      reset_counters
    end
  end

  def close_day close
    return unless @decision_map[:wait_sell]
    sell_position
    telegram "MARKET CLOSE REACHED, SELLING POSITION NET_BNF:#{@net_day}"
    reset_counters
  end
end
