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
        when :decline_response
          decline_response
        when :accept_response
          accept_response
        when :leave_taxitwin
          leave_taxitwin
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

        inter_tmp = tt_data.clone
        inter_tmp.delete 'radius'

        to_change = tt_data
        to_change.delete 'type'
        to_change.delete 'passengers' if to_change.include? 'passengers'
        if to_change.include? 'start_long' or to_change.include? 'start_lat'

          start_long = to_change['start_long']
          start_lat = to_change['start_lat']
          gcoder = GCoder.connect
          start_textual = gcoder[[start_lat, start_long]][0]['formatted_address']
          inter_tmp['start_text'] = start_textual

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
          inter_tmp['end_text'] = end_textual

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

        res['inter'].each_value do |value|
          inter_tmp['id'] = new_taxitwin['id']
          data['from'] = value['google_id']
          send_response inter_tmp unless inter_tmp.size <= 2
        end

        TaxiTwin::Log.debug("to_change: #{to_change}")

        dc.update_data('taxitwin', to_change, {'id' => new_taxitwin['id']}) unless to_change.empty?
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
        TaxiTwin::Log.debug "unsubscribe google_id: #{google_id}"

        dc = TaxiTwin::Db::Controller.new
        device_id = dc.exists?('device', {'google_id' => google_id})

        unless device_id
          TaxiTwin::Log.error "there is no device with google_id: #{google_id} in the db"
          return
        end

        taxitwin = nil
        dc.load_taxitwin(google_id) do |row|
          TaxiTwin::Log.debug "row: #{row}"
          taxitwin = row
        end

        unless taxitwin
          TaxiTwin::Log.error "there is no taxitwin with google_id: #{google_id} in the db"
          return
        end

        start_long = taxitwin['start_long']
        start_lat = taxitwin['start_lat']
        end_long = taxitwin['end_long']
        end_lat = taxitwin['end_lat']

        dc.load_data_on_subscribe(start_long, start_lat, end_long, end_lat, "taxitwin.radius") do |row|
          data['from'] = row['google_id'] 
          tmp = {}
          tmp['type'] = "invalidate"
          tmp['id'] = taxitwin['id']
          send_response tmp unless row['google_id'] == google_id
        end

        join_table = 'pending_response INNER JOIN device ON pending_response.to_device_id = device.id'
        responses = dc.fetch_data(join_table, ['google_id'], {'from_device_id' => device_id})
        if responses
          responses.each do |to_device_google_id|
            tmp = {}
            tmp['type'] = "invalidate"
            tmp['id'] = taxitwin['id']
            data['from'] = to_device_google_id
            send_response tmp
          end
        end

        if device_id
          #dc.remove_data('participants', {'device_id' => device_id})
          #dc.remove_data('share', {'owner_taxitwin_id' => taxitwin['id']})
          dc.remove_data('pending_response', {'from_device_id' => device_id})
          dc.remove_data('pending_response', {'to_device_id' => device_id})
          dc.remove_data('taxitwin', {'device_id' => device_id})
        end
      end

      def leave_taxitwin
        google_id = data['from']

        dc = TaxiTwin::Db::Controller.new
        join_table = 'taxitwin INNER JOIN device ON taxitwin.device_id = device.id'
        taxitwin_id = dc.fetch_data(join_table, ['taxitwin.id'], {'google_id' => google_id})
        unless taxitwin_id
          TaxiTwin::Log.error "There is no taxitwin with google_id #{google_id} in database."
          return
        end
        taxitwin_id = taxitwin_id[0].to_i
        owner_taxitwin_google_id = nil

        share_id = dc.exists?('share', {'owner_taxitwin_id' => taxitwin_id})
        if share_id
          join_table = 'participants INNER JOIN device ON participants.device_id = device.id'
          participants = dc.fetch_data(join_table, ['google_id'], {'share_id' => share_id})
          dc.remove_data('share', {'id' => share_id})
          participants.each do |participant|
            tmp = {}
            tmp['type'] = 'no_longer'
            data['from'] = participant
            send_response tmp

            participant_taxitwin = nil
            dc.load_taxitwin(participant) do |row|
              participant_taxitwin = row
            end
            unless participant_taxitwin
              TaxiTwin::Log.error "There is no taxitwin with google_id #{participant} in database."
              return
            end
            
            matches = []
            dc.load_data_on_subscribe(participant_taxitwin['start_long'], participant_taxitwin['start_lat'],participant_taxitwin['end_long'], participant_taxitwin['end_lat'], 'taxitwin.radius') do |row|
              matches << row
            end

            matches.each do |match|
            tmp = participant_taxitwin.clone
            tmp.delete 'google_id'
            tmp.delete 'radius'
            tmp['type'] = 'offer'
            data['from'] = match['google_id']
            send_response tmp unless (match['google_id'] == participant_taxitwin['google_id']) or (match['google_id'] == google_id)
            end
          end

          owner_taxitwin_google_id = google_id
        else
          join_table = 'participants INNER JOIN device ON participants.device_id = device.id'
          share_id = dc.fetch_data(join_table, ['share_id'], {'google_id' => google_id})
          unless share_id
            TaxiTwin::Log.error "There is no participant with google_id #{google_id} in database."
            return
          end
          share_id = share_id[0].to_i

          join_table = 'share INNER JOIN taxitwin ON share.owner_taxitwin_id = taxitwin.id INNER JOIN device ON taxitwin.device_id = device.id'
          owner_taxitwin_google_id = dc.fetch_data(join_table, ['google_id'], {'share.id' => share_id})
          unless owner_taxitwin_google_id
            TaxiTwin::Log.error "There is no google_id with share_id #{share_id} in database."
            return
          end
          owner_taxitwin_google_id = owner_taxitwin_google_id[0]

          device_id = dc.exists?('device', {'google_id' => google_id})
          unless device_id
            TaxiTwin::Log.error "There is no device with google_id #{google_id} in database."
            return
          end
          dc.remove_data('participants', {'device_id' => device_id})
        end

        owner_taxitwin = nil
        dc.load_taxitwin(owner_taxitwin_google_id) do |row|
          owner_taxitwin = row
        end

        unless owner_taxitwin
          TaxiTwin::Log.error "There is no taxitwin with google_id #{owner_taxitwin_google_id} in database."
          return
        end

        matches = []
        dc.load_data_on_subscribe(owner_taxitwin['start_long'], owner_taxitwin['start_lat'],owner_taxitwin['end_long'], owner_taxitwin['end_lat'], owner_taxitwin['radius']) do |row|
          matches << row['google_id']
        end
        if owner_taxitwin['passengers_total'].to_i == owner_taxitwin['passengers'].to_i + 1
          matches.each do |match|
            tmp = owner_taxitwin.clone
            tmp.delete 'radius'
            tmp.delete 'google_id'
            tmp['type'] = 'offer'
            data['from'] = match
            send_response tmp unless match == owner_taxitwin['google_id']
          end
        else
          matches.each do |match|
            tmp = {}
            tmp['type'] = 'modify'
            tmp['id'] = owner_taxitwin['id']
            tmp['passengers'] = owner_taxitwin['passengers'].to_i
            data['from'] = match
            send_response tmp unless match = owner_taxitwin['google_id']
          end
        end

        if owner_taxitwin['passengers'].to_i == 0
          tmp = {}
          tmp['type'] = 'no_longer'
          data['from'] = owner_taxitwin_google_id
          send_response tmp
          dc.remove_data('share', {'id' => share_id}) if dc.exists?('share', {'owner_taxitwin_id' => owner_taxitwin['id']})
        end
        #unsubscribe(google_id)
      end

      def decline_response
        taxitwin_id = tt_data['taxitwin_id'].to_i

        dc = TaxiTwin::Db::Controller.new

        device_id = dc.fetch_data('taxitwin', ['device_id'], {'id' => taxitwin_id})
        unless device_id
          TaxiTwin::Log.error "There is no device with taxitwin_id #{taxitwin_id} in database."
          return
        end
        device_id = device_id[0].to_i

        dc.remove_data('pending_response', {'from_device_id' => device_id})
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

      def accept_response
        taxitwin_id = tt_data['taxitwin_id'].to_i
        google_id = data['from']

        dc = TaxiTwin::Db::Controller.new

        to_device_id = dc.exists?('device', {'google_id' => google_id})
        unless to_device_id
          TaxiTwin::Log.error "There is no device with google_id #{google_id} in database."
          return
        end

        from_device_id = dc.fetch_data('taxitwin', ['device_id'], {'id' => taxitwin_id})
        unless from_device_id
          TaxiTwin::Log.error "There is no device with taxitwin_id #{taxitwin_id} in database."
          return
        end
        from_device_id = from_device_id[0].to_i

        TaxiTwin::Log.debug "to_device_id: #{to_device_id}"

        dc.remove_data('pending_response', {'to_device_id' => to_device_id, 'from_device_id' => from_device_id})

        owner_taxitwin_id = dc.fetch_data('taxitwin', ['id'], {'device_id' => to_device_id})
        unless owner_taxitwin_id
          TaxiTwin::Log.error "no taxitwin found with device_id: #{to_device_id}"
          return
        end
        owner_taxitwin_id = owner_taxitwin_id[0].to_i

        owner_taxitwin = nil
        dc.load_taxitwin(google_id) do |row|
          owner_taxitwin = row
        end

        share_id = dc.exists?('share', {'owner_taxitwin_id' => owner_taxitwin_id})
        unless share_id
          share_id = dc.store_data('share', {'owner_taxitwin_id' => owner_taxitwin_id})
          tmp = owner_taxitwin.clone
          tmp.delete 'radius'
          tmp.delete 'google_id'
          tmp['type'] = 'taxitwin'
          send_response tmp
        end

        matches = []
        dc.load_data_on_subscribe(owner_taxitwin['start_long'], owner_taxitwin['start_lat'],owner_taxitwin['end_long'], owner_taxitwin['end_lat'], owner_taxitwin['radius']) do |row|
          matches << row['google_id']
        end

        dc.store_data('participants', {'share_id' => share_id, 'device_id' => from_device_id})                
        join_table = 'participants INNER JOIN device ON participants.device_id = device.id'
        participants = dc.fetch_data(join_table, ['google_id'], {'share_id' => share_id})

        join_table = 'taxitwin INNER JOIN device ON taxitwin.device_id = device.id'
        new_participant_google_id = dc.fetch_data(join_table, ['google_id'], {'taxitwin.id' => taxitwin_id})
        unless new_participant_google_id
          TaxiTwin::Log.error "no google_id found for taxitwin: #{taxitwin_id}"
          return
        end
        new_participant_google_id = new_participant_google_id[0]
        tmp = {}
        tmp['type'] = 'taxitwin'
        tmp['id'] = owner_taxitwin_id
        data['from'] = new_participant_google_id
        send_response tmp

        if owner_taxitwin['passengers_total'].to_i == owner_taxitwin['passengers'].to_i + 1
          matches.each do |match|
            invalidate_tmp = {}
            invalidate_tmp['type'] = invalidate
            modify_tmp = {}
            modify_tmp['type'] = 'modify'
            modify_tmp['passengers'] = owner_taxitwin['passengers'].to_i + 1
            modify_tmp['id'] = owner_taxitwin_id
            data['from'] = match
            if (participants.include? match) or (match = google_id)
              send_response modify_tmp
            else
              send_response invalidate_tmp
            end
          end
        else
          matches.each do |match|
            tmp = {}
            tmp['type'] = 'modify'
            tmp['passengers'] = owner_taxitwin['passengers'].to_i + 1
            tmp['id'] = owner_taxitwin_id
            data['from'] = match
            send_response tmp
          end
        end

        tmp = {}
        tmp['type'] = 'modify'
        tmp['passengers'] = owner_taxitwin['passengers'].to_i + 1
        tmp['id'] = owner_taxitwin_id
        data['from'] = google_id
        send_response tmp
        #count  = participants.count
        #participants << google_id
        #participants.each do |participant|
        #  tmp = {}
        #  tmp['type'] = 'modify'
        #  tmp['passengers'] = count
        #  tmp['id'] = owner_taxitwin_id
        #  data['from'] = participant
        #  send_response tmp
        #end
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
        tmp['start_text'] = start_textual
        tmp['end_text'] = end_textual
        tmp['passengers_total'] = tt_data['passengers']
        tmp['passengers'] = '0'
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
