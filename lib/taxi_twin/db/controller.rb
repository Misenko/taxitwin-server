require 'pg'

module TaxiTwin
  module Db
    class Controller
      attr_accessor :connection

      def connect
        @connection = PG.connect(
          :dbname => ENV['DB_NAME'],
          :user => ENV['DB_USER'],
          :password => ENV['DB_PASS'])
      end

      def disconnect
        connection.close
      end

      def create_tables
        self.connect
        run_sql_from_file 'create.sql'
        create_indexes
        self.disconnect
      end

      def drop_tables
        self.connect
        run_sql_from_file 'drop.sql'
        self.disconnect
      end

      def create_indexes
        connection.prepare("check_index", "SELECT * FROM pg_class WHERE relname = $1")
        f = open_sql_file('index.sql')
        f.each_line do |line|
          split = line.split '$'
          unless connection.exec_prepared("check_index", split.take(1)).any?
            connection.exec(split.last)
          end
        end
        f.close
      end

      def run_sql_from_file(filename)
        f = open_sql_file(filename)
        f.each_line do |line|
          connection.exec(line)
        end
        f.close
      end

      def open_sql_file(filename)
        File.open(File.join(File.dirname(__FILE__), 'sql', filename), 'r')
      end

      def load_data_on_subscribe(start_long, start_lat, end_long, end_lat, radius)
        self.connect

        start_point = "SRID=4326;POINT(#{start_long} #{start_lat})"
        end_point = "SRID=4326;POINT(#{end_long} #{end_lat})"

        params = [start_point, end_point, radius]

        f = open_sql_file 'subscribe.sql'
        f.each_line do |line|
          if radius.class == String
            line.gsub!(/\$3::real/, radius) 
            params = params.reverse.drop(1).reverse
          end
          connection.prepare('subscription', line)
        end

        connection.exec_prepared('subscription', params).each {|x| yield x if block_given?}
        self.disconnect
      end

      def load_taxitwin(device_id)
        self.connect
        f = open_sql_file 'load_taxitwin.sql'
        f.each_line do |line|
          connection.prepare('load_taxitwin', line)
        end

        connection.exec_prepared('load_taxitwin', [device_id]).each {|x| yield x if block_given?}
        self.disconnect
      end

      def exists?(table, values)
        where = ''
        values.keys.each_with_index do |key, i|
          where += "#{key} = $#{i+1} AND "
        end
        where.slice!(-5..-1)
        self.connect
        connection.prepare('exist', "SELECT id FROM #{table} WHERE #{where}")
        res = connection.exec_prepared('exist', values.values) 
        self.disconnect
        res.any? ? res.values.flatten[0] : nil
      end

      def fetch_data(table, columns, condition)
        where = ''
        condition.keys.each_with_index do |key, i|
          where += "#{key} = $#{i+1} AND "
        end
        where.slice!(-5..-1)

        self.connect
        connection.prepare('fetch', "SELECT #{columns.join ','} FROM #{table} WHERE #{where}")
        res = connection.exec_prepared('fetch', condition.values)
        self.disconnect
        res.any? ? res.values.flatten : nil
      end

      def update_data(table, values, condition)
        columns = ''
        offset = 0
        values.keys.each_with_index do |key, i|
          columns += "#{key} = $#{i+1},"
          offset += 1
        end
        columns = "#{columns.chop}"

        where = ''
        condition.keys.each_with_index do |key, i|
          where += "#{key} = $#{i+1+offset} AND "
        end
        where.slice!(-5..-1)

        self.connect
        connection.prepare('update', "UPDATE #{table} SET #{columns} WHERE #{where}")
        connection.exec_prepared('update', values.merge(condition).values) 
        self.disconnect
      end

      def store_data(table, values)
        columns = '('
        placeholders = '('
        values.keys.each_with_index do |key, i|
          columns += "#{key},"
          placeholders += "$#{i+1},"
        end
        columns = "#{columns.chop})"
        placeholders = "#{placeholders.chop})"

        self.connect
        if table.to_sym == :point
          columns = "#{columns.chop}, geom)"
          placeholders = "#{placeholders.chop}, ST_SetSRID(ST_MakePoint($#{values.keys.index('longitude')+1},$#{values.keys.index('latitude')+1}),4326))"
        end
        if ["participants", "pending_offer", "pending_response"].include? table
          connection.prepare('insert', "INSERT INTO #{table} #{columns} VALUES #{placeholders}")
        else
          connection.prepare('insert', "INSERT INTO #{table} #{columns} VALUES #{placeholders} RETURNING id")
        end
        res = connection.exec_prepared('insert', values.values)
        self.disconnect
        res.any? ? res.values.flatten[0] : nil
      end

      def remove_data(table, condition)
        where = ''
        condition.keys.each_with_index do |key, i|
          where += "#{key} = $#{i+1} AND "
        end
        where.slice!(-5..-1)

        self.connect
        connection.prepare('delete', "DELETE FROM #{table} WHERE #{where}")
        connection.exec_prepared('delete', condition.values) 
        self.disconnect
      end
    end
  end
end

