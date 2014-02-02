require 'singleton'

module TaxiTwin
  module Gcm
    class MessageIdHandler
      include Singleton

      def initialize
        @id_alpha = 'a'
        @id_num = 0
      end

      def next_id
        @id_num += 1
        if @id_num == 100000
          @id_num = 0
          @id_alpha.next!
        end
        "#{@id_alpha}#{"%05d" % @id_num}"
      end
    end
  end
end

