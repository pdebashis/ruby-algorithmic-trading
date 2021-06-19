class StrategyLevelBreakoutGreen
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
    @net_day=0
    @trade_flag=false
    @index = @feeder.instrument.to_s
    @whichnifty = @feeder.instrument == 256265 ? "nifty" : "banknifty"
    @instrument = 0
    @strike = ""
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @trade_target = config[@index][:levelbreakout_target]
    @trade_exit = config[@index][:levelbreakout_exit]
    @day_target = config[@index][:target_per_day]
    @report_name=Dir.pwd+"/reports/trades.dat"

    @levels = []
    @candle=[]
    @candle_color = nil
    @candle_body_min_perc=0.07
    @candle_shadow_max_perc=0.25
    @candle_max_dist_from_lev=0.10
    @decision_map={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :target_value => 0, :ltp_at_buy => 0}
  end

  def on_bar bar
    bar.bar_data.each do |_symbol, data|
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
        @levels=get_levels(closing)
        if matches_basic_conditions(opening,high,low,closing)
          telegram "#{time} matches basic conditions candle"
          @decision_map[:trigger_price] = closing
          @decision_map[:stop_loss] = low
          @decision_map[:target_value] = [@levels[1],closing + 250].min
          buy_ce
        end
      end
    end
  end

  def get_levels(closing_value)
    level_config=OpenStruct.new YAML.load_file('config/levels.yaml') 
    targets = level_config.levels.sort
    raise "Targets not enclosing the data points" if targets.first > closing_value or targets.last < closing_value 
    targets.each_with_index { |t,n|
      return [targets[n-1],t] if t > closing_value
    }
  end

  def matches_basic_conditions(o,h,l,c)
    return false if h < @levels[1] and l > @levels[0]

    candle_body_size=(o-c).abs
    @candle_color = o < c ? "GREEN" : "RED"
    return false if color == "RED"
    levels_diff = @levels[1] - @levels[0]

    shodow_size =  @candle_color == "RED" ? c - l : h - c
    dist_from_lev =  @candle_color == "GREEN" ? c - @levels[0] : @levels[1] - c
    body_shadow_ratio = candle_body_size*2.5 > shodow_size
    @logger.info("BODY:#{candle_body_size} SHADOW:#{shodow_size} DISTFROMLVL:#{dist_from_lev} LEVELSIZE:#{levels_diff} COLOR:#{@candle_color}")
    return false unless body_shadow_ratio

    candle_body_size_matches = candle_body_size > @candle_body_min_perc * levels_diff
    candle_shadow_size_matches = shodow_size < @candle_shadow_max_perc * levels_diff
    candle_dist_from_level_matches = dist_from_lev < @candle_max_dist_from_lev * levels_diff
    dist_not_zero = dist_from_lev > 0
    shadow_not_zero = shodow_size > 0
    not_zero = dist_not_zero and shadow_not_zero
    @logger.info("BODY:#{candle_body_size_matches} SHADOW:#{candle_shadow_size_matches} DISTFROMLVL:#{candle_dist_from_level_matches} NOTZERO:#{not_zero}")
    return true if candle_body_size_matches and candle_shadow_size_matches and candle_dist_from_level_matches and not_zero
  end


  def book_pl_strike(strike,color)
    buy_price = @decision_map[:ltp_at_buy]
    profit = strike - buy_price
    if profit > @trade_target or profit < @trade_exit
      sell_position
      @net_bnf+=profit
      telegram "TRADE CAP REACHED(#{profit}), SELLING POSITION NET_BNF:#{@net_bnf}"
      reset_counters
    end
  end

  def on_strike strike 
    if @decision_map[:wait_sell]
      book_pl_strike(strike)
    end
  end

  def on_tick tick
    if @decision_map[:wait_sell]
      sell_position if tick < @decision_map[:stop_loss] 
      sell_position if tick > @decision_map[:target_price]
    end
  end


  private 

  def telegram msg
    @logger.info msg
    @telegram_bot.send_message "[#{@whichnifty}][GREEN LEVELBREAKOUT] #{msg}" 
  end

  def refresh_clients_from_yaml
    CLIENTS=YAML.load_file 'config/login.yaml'
    CLIENTS_FYER=YAML.load_file 'config/fyer.yaml'
    @users.each do |usr|
      CLIENTS.each do |client|
        if client[:client] == usr[:client_id]
          usr[:level_break_enable] = client[:level_break_enable]
        end
      end
      CLIENTS_FYER.each do |client|
        if client[:client] == usr[:client_id]
          usr[:level_break_enable] = client[:level_break_enable]
        end
      end
    end
  end

  def buy_ce
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_ce].to_s
    @strike = config[@index][:strike_ce]
    @quantity = config[@index][:quantity]

    refresh_clients_from_yaml

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.empty? ? 0 : ltp.values.first["last_price"]
    @decision_map[:ltp_at_buy]=ltp_value || 0
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit
    lot_size_sym="lot_size_" + @whichnifty

    @users.each do |usr|
      api_usr = usr[:fyer_api] ? usr[:fyer_api] : usr[:kite_api]
      lot_size = usr[lot_size_sym.to_sym] * @quantity
      api_usr.place_cnc_order(@strike, "BUY", lot_size, nil, "MARKET") if @trade_flag and usr[:level_break_enable]
      reporting "#{self.to_s},#{usr[:client_id]},#{@quantity},#{lot_size},#{@strike},BUY,#{ltp_value}" if usr[:level_break_enable]
    end

    telegram "ORDER PLACED FOR #{strike} quantity #{@quantity} at #{ltp_value}; TARGET: #{target_value}; SL: #{sl_value}"
    @feeder.subscribe(@instrument)
    @decision_map[:wait_buy]=false
    @decision_map[:wait_sell]=true
    @logger.info "DECISION MAP : #{@decision_map}"

  end

  def sell_position
    @instrument = @instrument

    @feeder.unsubscribe(@instrument)
    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.empty? ? 0 : ltp.values.first["last_price"]
    lot_size_sym="lot_size_" + @whichnifty
    
    @users.each do |usr|
      api_usr=  usr[:fyer_api] ? usr[:fyer_api] : usr[:kite_api]
      lot_size=usr[lot_size_sym.to_sym]*@quantity
      api_usr.place_cnc_order(@strike, "SELL", lot_size, nil, "MARKET") if @trade_flag and usr[:level_break_enable]
      reporting "#{self.to_s},#{usr[:client_id]},#{@quantity},#{lot_size},#{@strike},SELL,#{ltp_value}" if usr[:level_break_enable]
    end

    @decision_map[:wait_sell]=false
    difference = ltp_value - @decision_map[:ltp_at_buy]
    @net_day+=difference
    telegram "SELLING #{@decision_map[:strike]} at #{ltp_value}; POINTS: #{difference}"
  end

  def reset_counters(color=nil)
    @decision_map[:wait_buy]= false
    @decision_map[:wait_sell]=false
    @decision_map[:stop_loss]=nil
    @decision_map[:trigger_price] = nil
  end

  def close_day close
    if @decision_map[:wait_sell]
      sell_position
      telegram "END TRADE, SELLING POSITION NET_BNF:#{@net_day}"
      reset_counters
    end
  end
end
