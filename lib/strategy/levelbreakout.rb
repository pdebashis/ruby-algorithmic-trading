class StrategyLevelBreakout
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
    @trade_target = config[@index][:target_per_trade]
    @trade_exit = config[@index][:exit_per_trade]
    @day_target = config[@index][:target_per_day]
    @report_name=Dir.pwd+"/reports/trades.dat"

    @levels = []
    @candle=[]
    @candle_color = nil
    @candle_body_min_perc=0.07
    @candle_shadow_max_perc=0.25
    @candle_max_dist_from_lev=0.10
    @decision_map_green={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :target_value => 0}
    @decision_map_red={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :target_value => 0}
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
        @levels=get_levels(closing)
        if matches_basic_conditions(opening,high,low,closing)
          telegram "#{time} matches basic conditions"
          if @candle_color == "GREEN"
            @decision_map_green[:trigger_price] = closing
            @decision_map_green[:stop_loss] = low
          else
            @decision_map_red[:trigger_price] = closing
            @decision_map_red[:stop_loss] = high
          end
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


  def book_pl_strike strike
    profit= strike - @candle[2]
    if profit > @trade_target or profit < @trade_exit
      sell_position
      @net_bnf+=profit
      telegram "TRADE CAP REACHED(#{profit}), SELLING POSITION NET_BNF:#{@net_bnf}"
      reset_counters
    end
  end

  def on_strike strike 
    unless @candle.empty?
      book_pl_strike(strike) if @candle[4].eql? "BUY" or @candle[4].eql? "SELL"
    end
  end

  def on_tick tick
    unless @candle.empty?
      do_action(tick) if @candle[4].eql? "GREEN" or @candle[4].eql? "RED"
      book_pl(tick) if @candle[4].eql? "BUY" or @candle[4].eql? "SELL"  
    end
  end


  private 

  def telegram msg
    @logger.info msg
    @telegram_bot.send_message "[#{@whichnifty}] #{msg}" 
  end

  def buy_ce
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_ce].to_s
    @strike = config[@index][:strike_ce]
    @quantity = config[@index][:quantity]
    @trade_target = config.target_per_trade.to_i
    @trade_exit = config.exit_per_trade.to_i 
    @day_target = config.target_per_day.to_i 
   
    if @trade_flag 
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        kite_usr.place_cnc_order(@strike, "BUY", @quantity, nil, "MARKET") unless @strike.empty?
      end
    end

    @feeder.subscribe(@instrument)
    ltp = @user.ltp(@instrument)
    ltp.values.first["last_price"] unless ltp.values.empty?
  end

  def buy_pe
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_pe].to_s
    @strike = config[@index][:strike_pe]
    @quantity = config[@index][:quantity]
    @trade_target = config.target_per_trade.to_i
    @trade_exit = config.exit_per_trade.to_i
    @day_target = config.target_per_day.to_i  
    
    if @trade_flag
      @users.each do |usr|
       kite_usr=usr[:kite_api]
       kite_usr.place_cnc_order(@strike, "BUY", @quantity, nil, "MARKET") unless @strike.empty? 
      end
    end
 
    @feeder.subscribe(@instrument)
    ltp = @user.ltp(@instrument)
    ltp.values.first["last_price"] unless ltp.values.empty?
  end

  def sell_position
    
    if @trade_flag
      @users.each do |usr|
        kite_usr=usr[:kite_api]
        kite_usr.place_cnc_order(@strike, "SELL", @quantity, nil, "MARKET") unless @strike.empty?
      end
    end
    
    @feeder.unsubscribe(@instrument)
    ltp = @user.ltp(@instrument)
    @instument = 0
    @strike = ""
    ltp.values.first["last_price"] unless ltp.values.empty? 
  end

  def reset_counters(color=nil)
    if @net_bnf > @day_target and @trade_flag
      @logger.info "DAY TARGET ACHIEVED(#{@day_target})"
      @trade_flag=false
    end

    if color == "GREEN"
      @decision_map_green[:wait_buy]= false
      @decision_map_green[:wait_sell]=false
      @decision_map_green[:green] = nil 
      @decision_map_green[:stop_loss]=nil
      @decision_map_green[:trigger_price] = nil
    else
      @decision_map_red[:wait_buy]= false
      @decision_map_red[:wait_sell]=false
      @decision_map_red[:green] = nil 
      @decision_map_red[:stop_loss]=nil
      @decision_map_red[:trigger_price] = nil
    end

  end

  def book_pl tick
  end

  def close_day close
    # differen=0
    # diffe2=0
    # if @candle[4] == "SELL"
    #   differen = @candle[3] - close
    #   ltp=sell_position
    #   diffe2 = ltp - @candle[2]
    #   telegram "END TRADE:#{differen};strike:#{ltp};BNF_POINTS:#{diffe2}"
    # elsif @candle[4] == "BUY"
    #   differen = close - @candle[3]
    #   ltp=sell_position
    #   diffe2 = ltp - @candle[2]
    #   telegram "END TRADE:#{differen};strike:#{ltp};BNF_POINTS:#{diffe2}"
    # end
    # @net_day+=differen
    # @net_bnf+=diffe2
    # @logger.info "NET:#{@net_day};NET_BNF:#{@net_bnf}"
    # reset_counters
  end
end
