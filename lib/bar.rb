# a bar is an abstraction of a time interval
# for instance, a bar encapsulates states for a day
# if data is EOD data
class Bar
  attr_reader :date, :bar_data

  def initialize date
    @date = date
    @bar_data = {}
  end

  def add_bar_data symbol, data
    @bar_data[symbol] = data
  end

  def get_symbol_ohlc
    return @bar_data
  end

end
