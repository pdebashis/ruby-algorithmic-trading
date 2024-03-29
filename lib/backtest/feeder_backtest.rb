require_relative '../bar'
require_relative 'levelbreakout'
require 'frappuccino'
require 'logger'
require 'yaml'
require 'ostruct'
require 'faye/websocket'
require 'eventmachine'
require 'time'

class Feeder

  def initialize 
    
    data_file_path="2021.csv"
    targets_file_path="./../../config/levels.yaml"

    raise "Source file not found" unless File.file? data_file_path
    raise "Levels file not found" unless File.file? targets_file_path

    result_filepath=File.dirname(data_file_path)
    result_filename="result_" + File.basename(data_file_path)

    @data_in_file=""
    @today=""    

    @new_date=""
    @old_date=""
    @target=0
    @stop_loss=0
    @tolerence=0
    @net_day=0

    File.open(data_file_path, "r") do |fp|
      until fp.eof? do @data_in_file << fp.gets end
    end

    @ticks = {}      
    @bars = {}
    @instrument = 260105
  end

  def start
    EventMachine.run do
    @data_in_file.lines.each do |line|

      opening,high,low,closing,timestamp=line.split(",")

      closing=closing.to_i
      high=high.to_i
      low=low.to_i
      opening=opening.to_i
      p timestamp
      new_date=timestamp.split("T")[0]
      next if Time.strptime(timestamp,"%Y-%m-%d").thursday?
      new_time=timestamp.split("T")[1][0..4]

      if timestamp.include? ("09:15") or @today != new_date
        @today=new_date
      end 

      emit tick: opening
      emit tick: high
      emit tick: low
      emit tick: closing

      d = {
        date: @today,
        time: new_time,
        open: opening,
        high: high,
        low: low,
        close: closing,
      }
      add_bar d
    end
    end
  end

  def add_bar hash
    time = hash[:time]
    @bars[time] ||= Bar.new @today
    @bars[time].add_bar_data @instrument,hash
    emit bar: @bars[time]
  end

end

LOG=Logger.new('results/levelsbreakout_backtest.log', 'daily', 30)
LOG.formatter = proc do |severity, datetime, progname, msg|
  "#{msg}\n"
end

a=Feeder.new 
#StrategyOrb.new(a, LOG)
StrategyLevelBreakout.new(a,LOG)
a.start
