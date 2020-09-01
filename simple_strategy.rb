class SimpleStrategy
  def initialize feeder, logger=nil, starting_capital=0, commission_per_trade=0, limit=0
    @feeder = feeder
    Frappuccino::Stream.new(feeder).
      select{ |event| event.has_key?(:bar) && !event[:bar].nil? }.
      map{ |event| event[:bar] }.
      on_value(&method(:on_bar))
    @logger = logger
    #@portfolio = Portfolio::Base.new self, starting_capital, commission_per_trade
    #@limit = limit
    #@last_close = {}

    @targets=[]
    @result=""
    @levels=[]
    @candle1=[]
    @candle2=[]

    @new_date=""
    @old_date=""
    @target=0
    @stop_loss=0
    @tolerence=limit
    @net_day=0
  end

  def start
    @feeder.start
  end

  def on_bar bar
    bar.bar_data.each do |symbol, data|
      # holding_num_shares = @portfolio.holdings.num_shares_for_symbol symbol
      # current_close = data[:adj_close].to_f
      # last_close = @last_close[symbol].to_f
      # change = current_close - last_close

      # # TODO to refactor - violate tell don't ask
      # cheapest_holding_price = @portfolio.holdings.cheapest_price_for_symbol symbol
      # if cheapest_holding_price.blank?
      #   profit_estimate_pct = 0
      # else
      #   profit_estimate_pct = (current_close - cheapest_holding_price).to_f / cheapest_holding_price * 100
      # end

      # trade_type = if holding_num_shares == 0 && change < 0
      #                :buy
      #              elsif holding_num_shares > 0 && profit_estimate_pct > @limit
      #                :sell
      #              end

      # # keep current's adj_close so that on next bar we can
      # # refer to the last bar's adj_close
      # @last_close[symbol] = current_close

      # if trade_type.present?
      #   # TODO look-ahead bias here - should only place order on the next bar
      #   emit symbol: symbol, type: trade_type, price: current_close
      # end
      @logger.info "received #{data}"
    end
  end
end