require 'em-xmpp/helpers'

require 'taxi_twin/gcm/message'

module TaxiTwin
  module Gcm
    module Client
      attr_reader :roster

      $DEBUG = ENV['DEBUG']

      include EM::Xmpp::XmlParser::Nokogiri
      include EM::Xmpp::Helpers

      def ready
        super
        TaxiTwin::Log.debug 'READY'

        on_message do |ctx|
          message = ctx.bit(TaxiTwin::Gcm::Message)
          data = message.data
          if data
            TaxiTwin::Log.debug "incomming gcm message: #{data}"

            if data.has_key? "message_type"
              response = Response.new(data)
              response.update_queue
            else
              request = Request.new(self, data)
              request.send_ack
              request.respond
            end
          else
            TaxiTwin::Log.debug "incomming message: #{ctx}"
          end
          ctx
        end
      end
    end
  end
end

