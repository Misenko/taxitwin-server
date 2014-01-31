require 'eventmachine'

module EM::Xmpp
  class Connection < EM::Connection
    def post_init
      super
      initiate_tls
      prepare_parser!
      set_negotiation_handler!
    end
  end
end

