require 'em-xmpp/helpers'

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
          TaxiTwin::Log.debug "incomming: #{ctx}"
          ctx
        end
      end
    end
  end
end
