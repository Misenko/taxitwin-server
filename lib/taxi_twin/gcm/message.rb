require 'json'

require 'em-xmpp/context'

module TaxiTwin
  module Gcm
    class Message < EM::Xmpp::Context::Bit
      include EM::Xmpp::Context::Contexts::IncomingStanza

      def data_node
        xpath('//xmlns:gcm', {'xmlns' => "google:mobile:data"}).first
      end

      def data
        node = data_node
        JSON.parse(node.text) if node
      end

      def message_id_field
        data["message_id"] if data.has_key? "message_id"
      end
    end
  end
end

