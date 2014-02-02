module TaxiTwin
  module Gcm
    class Response
      attr_reader :data

      def initialize(data)
        @data = data
      end

      def update_queue
        Queue.instance.remove_nonacked_message(data['from'], data['message_id'])
      end
    end
  end
end

