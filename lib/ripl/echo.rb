require 'ripl'

module Ripl
  module Echo
    module Commands
      def echo(str="")
        puts "-- #{str}"
      end
    end
  end
end


Ripl::Commands.send :include, Ripl::Echo::Commands
