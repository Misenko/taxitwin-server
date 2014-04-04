require 'json'
require 'nokogiri'
#require 'gcoder'
require 'set'

require 'em-xmpp/connection'

module TaxiTwin
  module Gcm
    class Request
      attr_reader :client, :data, :type, :tt_data

      def initialize(client, data)
        @client = client
        @data = data
        @tt_data = data['data'].clone
        @type = tt_data['type'].to_sym if tt_data.has_key? 'type'
      end

      def respond
        case type
        when :subscribe
          subscribe
        when :modify
          modify
        when :unsubscribe
          unsubscribe(data['from'])
        when :accept_offer
          accept_offer
        else
          invalid_request_type
        end
      end

      def modify
        device_id = data['from']
        old_taxitwin = {}
        dc = TaxiTwin::Db::Controller.new
        dc.load_taxitwin(device_id) do |row|
          old_taxitwin = row
        end

        new_taxitwin = old_taxitwin.clone
        tt_data.each_pair do |key, value|
          new_taxitwin[key] = value
        end

        if tt_data.include?('radius')
          new_taxitwin['radius'] = new_taxitwin['radius'].to_f/100000
        end

        TaxiTwin::Log.debug "new_taxitwin: #{new_taxitwin}"
        TaxiTwin::Log.debug "old_taxitwin: #{old_taxitwin}"

        res = load_data_for_modify(old_taxitwin, new_taxitwin)

        TaxiTwin::Log.debug "first res: #{res}"

        res['old_matches'].each_key do |id|
          tmp = {}
          tmp['type'] = 'invalidate'
          tmp['id'] = id
          send_response tmp
        end

        res['new_matches'].each_pair do |id, row|
          row.delete 'google_id'
          row.delete 'radius'
          row['type'] = 'offer'
          send_response row
        end

        old_taxitwin['radius'] = 'taxitwin.radius'
        new_taxitwin['radius'] = 'taxitwin.radius'
        res = load_data_for_modify(old_taxitwin, new_taxitwin)

        TaxiTwin::Log.debug "second res: #{res}"

        res['old_matches'].each_value do |value|
          tmp = {}
          tmp['type'] = 'invalidate'
          tmp['id'] = old_taxitwin['id']
          data['from'] = value['google_id']
          send_response tmp
        end

        res['new_matches'].each_value do |value|
          tmp = new_taxitwin.clone
          tmp.delete 'radius'
          tmp.delete 'google_id'
          tmp['type'] = 'offer'
          data['from'] = value['google_id']
          send_response tmp
        end

        res['inter'].each_value do |value|
          tmp = tt_data.clone
          tmp.delete 'radius'
          tmp['id'] = new_taxitwin['id']
          data['from'] = value['google_id']
          send_response tmp unless tmp.size <= 2
        end

        to_change = tt_data
        to_change.delete 'type'
        if to_change.include? 'start_long' or to_change.include? 'start_lat'

          start_long = to_change['start_long']
          start_lat = to_change['start_lat']
          gcoder = GCoder.connect
          start_textual = gcoder[[start_lat, start_long]][0]['formatted_address']

          start_id = dc.exists?('point', {'longitude' => start_long, 'latitude' => start_lat})
          unless start_id
            tmp = {}
            tmp['longitude'] = start_long
            tmp['latitude'] = start_lat
            tmp['textual'] = start_textual
            start_id = dc.store_data('point', tmp)
          end
          to_change.delete 'start_long'
          to_change.delete 'start_lat'
          to_change['start_point_id'] = start_id
        end

        if to_change.include? 'end_long' or to_change.include? 'end_lat'

          end_long = to_change['end_long']
          end_lat = to_change['end_lat']
          gcoder = GCoder.connect
          end_textual = gcoder[[end_lat, end_long]][0]['formatted_address']

          end_id = dc.exists?('point', {'longitude' => end_long, 'latitude' => end_lat})
          unless end_id
            tmp = {}
            tmp['longitude'] = end_long
            tmp['latitude'] = end_lat
            tmp['textual'] = end_textual
            end_id = dc.store_data('point', tmp)
          end
          to_change.delete 'end_long'
          to_change.delete 'end_lat'
          to_change['end_point_id'] = end_id
        end

        if to_change.include? 'radius'
          to_change['radius'] = to_change['radius'].to_f/100000 
        end

        TaxiTwin::Log.debug("to_change: #{to_change}")

        dc.update_data('taxitwin', to_change, {'id' => new_taxitwin['id']})
      end

      def load_data_for_modify(old_taxitwin, new_taxitwin)
        old_matches = {}
        dc = TaxiTwin::Db::Controller.new
        dc.load_data_on_subscribe(old_taxitwin['start_long'], old_taxitwin['start_lat'],old_taxitwin['end_long'], old_taxitwin['end_lat'], old_taxitwin['radius']) do |row|
          old_matches[row['id']] = row unless row['id'] == new_taxitwin['id']
        end

        TaxiTwin::Log.debug "old_matches: #{old_matches.keys}"

        new_matches = {} 
        dc.load_data_on_subscribe(new_taxitwin['start_long'], new_taxitwin['start_lat'], new_taxitwin['end_long'], new_taxitwin['end_lat'], new_taxitwin['radius']) do |row|
          new_matches[row['id']] = row unless row['id'] == new_taxitwin['id']
        end

        TaxiTwin::Log.debug "new_matches: #{new_matches.keys}"

        inter = new_matches.keys.to_set.intersection old_matches.keys.to_set
        h = {}
        h['old_matches'] = old_matches.select {|k, v| !inter.include? k}
        h['new_matches'] = new_matches.select {|k, v| !inter.include? k}
        h['inter'] = old_matches.merge(new_matches).select {|k, v| inter.include? k}
        h
      end

      def unsubscribe(google_id)
        #TODO remove from all the other tables and send proper messages
        dc = TaxiTwin::Db::Controller.new
        device_id = dc.exists?('device', {'google_id' => google_id})
        if device_id
          dc.remove_data('taxitwin', {'device_id' => device_id})
        end
      end

      def accept_offer
        taxitwin_id = tt_data['taxitwin_id'].to_i
        google_id = data['from']

        dc = TaxiTwin::Db::Controller.new

        from_device_id = dc.exists?('device', {'google_id' => google_id})
        unless from_device_id
          TaxiTwin::Log.error "There is no device with google_id #{google_id} in database."
          return
        end

        to_device_id = dc.fetch_data('taxitwin', ['device_id'], {'id' => taxitwin_id})
        unless to_device_id
          TaxiTwin::Log.error "There is no device with taxitwin_id #{taxitwin_id} in database."
          return
        end
        to_device_id = to_device_id[0].to_i

        TaxiTwin::Log.debug "to_device_id: #{to_device_id}"

        pending_response = dc.fetch_data('pending_response', ['from_device_id', 'to_device_id'], {"from_device_id" => from_device_id, "to_device_id" => to_device_id[0].to_i})
        if pending_response
          TaxiTwin::Log.info "response already acknowledged - not sending again"
          return
        end

        dc.store_data('pending_response', {"from_device_id" => from_device_id, "to_device_id" => to_device_id})

        taxitwin = {}
        dc.load_taxitwin(google_id) do |row|
          TaxiTwin::Log.debug "row: #{row}"
          taxitwin = row
        end

        TaxiTwin::Log.debug "taxitwin: #{taxitwin}"

        taxitwin.delete 'google_id'
        taxitwin.delete 'passengers_total'
        taxitwin.delete 'passengers'
        taxitwin.delete 'radius'
        taxitwin['type'] = 'response'
        data['from'] = dc.fetch_data('device', ['google_id'], {"id" => to_device_id})[0]
        TaxiTwin::Log.debug "taxitwin response: #{taxitwin}"
        send_response taxitwin
      end

      def subscribe
        start_long = tt_data['start_long'].to_f
        start_lat = tt_data['start_lat'].to_f
        end_long = tt_data['end_long'].to_f
        end_lat = tt_data['end_lat'].to_f
        radius = tt_data['radius'].to_f/100000
        from = data['from']
        name = tt_data['name']
        passengers = tt_data['passengers']

        dc = TaxiTwin::Db::Controller.new

        device_id = dc.exists?('device', {'google_id' => from})
        unless device_id
          tmp = {}
          tmp['google_id'] = from
          tmp['name'] = name
          device_id = dc.store_data('device', tmp)
        end

        taxitwin_id = dc.exists?('taxitwin', {'device_id' => device_id})
        if taxitwin_id
          unsubscribe(from)
        end

        dc.load_data_on_subscribe(start_long, start_lat, end_long, end_lat, radius) do |row|
          row.delete 'google_id'
          row['type'] = 'offer'
          send_response row
        end

        gcoder = GCoder.connect
        start_textual = gcoder[[start_lat, start_long]][0]['formatted_address']
        end_textual = gcoder[[end_lat, end_long]][0]['formatted_address']

        start_id = dc.exists?('point', {'longitude' => start_long, 'latitude' => start_lat})
        unless start_id
          tmp = {}
          tmp['longitude'] = start_long
          tmp['latitude'] = start_lat
          tmp['textual'] = start_textual
          start_id = dc.store_data('point', tmp)
        end

        end_id = dc.exists?('point', {'longitude' => end_long, 'latitude' => end_lat})
        unless end_id
          tmp = {}
          tmp['longitude'] = end_long
          tmp['latitude'] = end_lat
          tmp['textual'] = end_textual
          end_id = dc.store_data('point', tmp)
        end

        tmp = {}
        tmp['device_id'] = device_id
        tmp['start_point_id'] = start_id
        tmp['end_point_id'] = end_id
        tmp['radius'] = radius
        tmp['passengers'] = passengers
        tt_id = dc.store_data('taxitwin', tmp)

        tmp = tt_data
        tmp.delete 'type'
        tmp.delete 'radius'
        tmp['id'] = tt_id
        tmp['start_textual'] = start_textual
        tmp['end_textual'] = end_textual
        tmp['passengers_total'] = tt_data['passengers']
        tmp['passenegers'] = '0'
        tmp['name'] = name
        tmp['type'] = 'offer'
        dc.load_data_on_subscribe(start_long, start_lat, end_long, end_lat, "taxitwin.radius") do |row|
          data['from'] = row['google_id']
          send_response tmp unless row['id'] == tt_id
        end
      end

      def send_response(message_data)
        message = {}
        message['to'] = data['from']
        message['message_id'] = MessageIdHandler.instance.next_id
        message['time_to_live'] = 600
        message['data'] = message_data
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.message{
            xml.gcm(JSON.generate(message), 'xmlns' => 'google:mobile:data')
          }
        end
        if Queue.instance.free_space > 0
          Queue.instance.add_nonacked_message(message)
          client.send_raw builder.to_xml
        else
          TaxiTwin::Log.error "full queue, cannot send message: #{builder.to_xml}"
        end
      end

      def invalid_request_type
        TaxiTwin::Log.error "invalid request: #{data}"
      end

      def send_ack
        message = {}
        message['to'] = data['from']
        message['message_id'] = data['message_id']
        message['message_type'] = 'ack'
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.message{
            xml.gcm( JSON.generate(message), 'xmlns' => 'google:mobile:data')
          }
        end
        client.send_raw builder.to_xml
      end

      def dummy_response
        message = {}
        message['to'] = data['from']
        message['message_id'] = MessageIdHandler.instance.next_id
        message['time_to_live'] = 600
        message['data'] = {'ruby' => 'rocks!'}
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.message{
            xml.gcm(JSON.generate(message), 'xmlns' => 'google:mobile:data')
          }
        end
        Queue.instance.add_nonacked_message(message)
        builder.to_xml
      end
    end
  end
end
