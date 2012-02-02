require 'ripl'

module Ripl
  module SilenceRuby
    def print_result(result)
      if @error_raised || 
        @command_mode == :system ||
        @command_mode == :mixed ||
        (!result || result == '')
        # silence
      else
        #super
      end
    end
  end
end

Ripl::Shell.include Ripl::SilenceRuby
