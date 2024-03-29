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
    @decision_map_green={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :target_value => 0, :ltp_at_buy => 0, :strike => nil, :instrument => nil}
    @decision_map_red={:trigger_price => 0, :wait_buy => true, :wait_sell => false, :stop_loss=>0, :target_value => 0, :ltp_at_buy => 0, :strike => nil, :instrument => nil}
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
          telegram "#{time} matches basic conditions"
          if @candle_color == "GREEN"
            @decision_map_green[:trigger_price] = closing
            @decision_map_green[:stop_loss] = low
            @decision_map_green[:target_value] = [@levels[1],closing + 250].min
            buy_ce
          else
            @decision_map_red[:trigger_price] = closing
            @decision_map_red[:stop_loss] = high
            @decision_map_green[:target_value] = [@levels[0],closing - 250].max
            buy_pe
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


  def book_pl_strike(strike,color)
    buy_price = color == "GREEN" ? @decision_map_green[:ltp_at_buy] : @decision_map_red[:ltp_at_buy]
    profit = strike - buy_price
    if profit > @trade_target or profit < @trade_exit
      sell_position color
      @net_bnf+=profit
      telegram "TRADE CAP REACHED(#{profit}), SELLING POSITION NET_BNF:#{@net_bnf}"
      reset_counters color
    end
  end

  def on_strike strike 
    if @decision_map_green[:wait_sell]
      book_pl_strike(strike,"GREEN")
    end

    if @decision_map_red[:wait_sell]
      book_pl_strike(strike,"RED")
    end
  end

  def on_tick tick
    if @decision_map_green[:wait_sell]
      sell_position "GREEN" if tick < @decision_map_green[:stop_loss] 
      sell_position "GREEN" if tick > @decision_map_green[:target_price]
    end

    if @decision_map_red[:wait_sell]
      sell_position "RED" if tick > @decision_map_red[:stop_loss]
      sell_position "RED" if tick < @decision_map_red[:target_price]
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

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.empty? ? 0 : ltp.values.first["last_price"]
    @decision_map_green[:ltp_at_buy]=ltp_value || 0
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit
    lot_size_sym="lot_size_" + @whichnifty

    @users.each do |usr|
      api_usr = usr[:fyer_api] ? usr[:fyer_api] : usr[:kite_api]
      lot_size = usr[lot_size_sym.to_sym] * @quantity
      api_usr.place_cnc_order(@strike, "BUY", lot_size, nil, "MARKET") if @trade_flag
      reporting "#{self.to_s},#{usr[:client_id]},#{@quantity},#{lot_size},#{@strike},BUY,#{ltp_value}"
    end

    telegram "ORDER PLACED FOR #{strike} quantity #{@quantity} at #{ltp_value}; TARGET: #{target_value}; SL: #{sl_value}"
    @feeder.subscribe(@instrument)
    @decision_map_green[:wait_buy]=false
    @decision_map_green[:wait_sell]=true
    @logger.info "DECISION MAP : #{@decision_map_green}"

  end

  def buy_pe
    config=OpenStruct.new YAML.load_file 'config/config.yaml'
    @instrument = config[@index][:instrument_pe].to_s
    @quantity = config[@index][:quantity]
    @strike = config[@index][:strike_pe]

    ltp = @user.ltp(@instrument)
    ltp_value = ltp.values.empty? ? 0 : ltp.values.first["last_price"]
    @decision_map_red[:ltp_at_buy]=ltp_value || 0
    target_value = ltp_value + @trade_target
    sl_value = ltp_value + @trade_exit
    lot_size_sym="lot_size_" + @whichnifty

    @users.each do |usr|
      api_usr = usr[:fyer_api] ? usr[:fyer_api] : usr[:kite_api]
      lot_size = usr[lot_size_sym.to_sym] * @quantity
      api_usr.place_cnc_order(@strike, "BUY", lot_size, nil, "MARKET") if @trade_flag
      reporting "#{self.to_s},#{usr[:client_id]},#{@quantity},#{lot_size},#{@strike},BUY,#{ltp_value}"
    end

    telegram "ORDER PLACED FOR #{@strike} quantity #{@quantity} at #{ltp_value}; TARGET: #{target_value}; SL: #{sl_value}"
    @feeder.subscribe(@instrument)
    @decision_map_red[:wait_buy]=false
    @decision_map_red[:wait_sell]=true
    @logger.info "DECISION MAP : #{@decision_map_red}"
  end


  def sell_position color=nil
    instrument = color == "GREEN" ? decision_map_green[:instrument] : decision_map_red[:instrument]

    @feeder.unsubscribe(instrument)
    ltp = @user.ltp(instrument)
    ltp_value = ltp.values.empty? ? 0 : ltp.values.first["last_price"]
    lot_size_sym="lot_size_" + @whichnifty
    
    @users.each do |usr|
      api_usr=  usr[:fyer_api] ? usr[:fyer_api] : usr[:kite_api]
      lot_size=usr[lot_size_sym.to_sym]*@quantity
      api_usr.place_cnc_order(@strike, "SELL", lot_size, nil, "MARKET") if @trade_flag
      reporting "#{self.to_s},#{usr[:client_id]},#{@quantity},#{lot_size},#{@strike},SELL,#{ltp_value}"
    end

    if color == "GREEN"
      @decision_map_green[:wait_sell]=false
      difference = ltp_value - @decision_map_green[:ltp_at_buy]
      @net_day+=difference
      telegram "SELLING #{@decision_map_green[:strike]} at #{ltp_value}; POINTS: #{difference}"
    else
      @decision_map_red[:wait_sell]=false
      difference = ltp_value - @decision_map_red[:ltp_at_buy]
      @net_day+=difference
      telegram "SELLING #{@decision_map_red[:strike]} at #{ltp_value}; POINTS: #{difference}"
    end
  end

  def reset_counters(color=nil)
    if color == "GREEN"
      @decision_map_green[:wait_buy]= false
      @decision_map_green[:wait_sell]=false
      @decision_map_green[:stop_loss]=nil
      @decision_map_green[:trigger_price] = nil
    else
      @decision_map_red[:wait_buy]= false
      @decision_map_red[:wait_sell]=false
      @decision_map_red[:stop_loss]=nil
      @decision_map_red[:trigger_price] = nil
    end
  end

  def close_day close
    if @decision_map_green[:wait_sell]
      sell_position "GREEN" 
      telegram "END TRADE, SELLING POSITION GREEN NET_BNF:#{@net_day}"
      reset_counters "GREEN"
    end

    if @decision_map_red[:wait_sell]
      sell_position "RED" 
      telegram "END TRADE, SELLING POSITION RED NET_BNF:#{@net_day}"
      reset_counters "RED"
    end 
  end
end
