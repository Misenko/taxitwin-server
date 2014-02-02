require 'singleton'
require 'thread'

module TaxiTwin
  module Gcm
    class Queue
      include Singleton
      
      QUOTA = 1000

      def initialize
        @nonacked_messages = {}
      end

      def free_space
        count = 0
        @nonacked_messages.each{ |x| count += x.size}
        QUOTA - count
      end

      def add_nonacked_message(data)
        unless @nonacked_messages.has_key? data['to']
          @nonacked_messages[data['to']] = {}
        end

          @nonacked_messages[data['to']][data['message_id']] = data
          TaxiTwin::Log.debug "added message to queue: to: #{data['to']}, message_id: #{data['message_id']}, whole: #{data}"
      end

      def remove_nonacked_message(reg_id, message_id)
        unless @nonacked_messages.has_key? reg_id and @nonacked_messages[reg_id].has_key? message_id
          TaxiTwin::Log.info("not my message... reg_id: #{reg_id}, message_id: #{message_id}")
          TaxiTwin::Log.debug("queue: #{@nonacked_messages}")
          return
        end

        @nonacked_messages[reg_id].delete message_id
        @nonacked_messages.delete reg_id if @nonacked_messages[reg_id].empty?
        TaxiTwin::Log.debug "removed message from queue: reg_id:  #{reg_id}, message_id: #{message_id}"
      end
    end
  end
end

