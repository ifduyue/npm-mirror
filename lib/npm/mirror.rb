require 'net/http/persistent'
require 'json'

require 'npm/mirror/version'
require 'npm/mirror/config'

module Npm
  module Mirror
    autoload :Pool, 'npm/mirror/pool'

    class Error < StandardError; end

    class Mirror
      def initialize(from = DEFAULT_FROM, to = DEFAULT_TO,
                     server = DEFAULT_SERVER, parrellism = 10)
        @from, @to, @server = from, to, server
        @pool = Pool.new parrellism
        @http = Net::HTTP::Persistent.new self.class.name

        puts "Mirroring  : #{from}"
        puts "Datadir    : #{to}"
        puts "Server     : #{server}"
      end

      def from(*args)
        File.join @from, *args
      end

      def to(*args)
        File.join @to, *args
      end

      def link(*args)
        File.join @server, *args
      end

      def id
        l = @pool.size.to_s.size
        master = 'Master'.ljust(%w(Thread- Master).map(&:size).max + l)
        if Thread.current[:id]
          "Thread-#{Thread.current[:id].to_s.rjust(l, '0')}"
        else
          master
        end
      end

      def fetch(url, path = nil)
        puts "[#{id}] Fetching #{url}"
        uri = URI url
        mtime = File.exist?(path) ? File.stat(path).mtime.rfc822 : nil if path
        req = Net::HTTP::Get.new uri.path
        req.add_field 'If-Modified-Since', mtime if mtime

        begin
          resp = @http.request uri, req
        rescue => e
          puts "[#{id}] Error fetching #{uri.path}: #{e.inspect}"
          sleep 10
          retry
        end

        puts "[#{id}] Fetched(#{resp.code}): #{uri}"
        case resp.code.to_i
        when 304
        when 302
          return fetch resp['location'], path
        when 200
          return resp
        when 403
          puts "[#{id}] #{resp.code} on #{uri}"
          return nil
        when 404
          puts "[#{id}] #{resp.code} on #{uri}"
          return resp
        else
          fail Error, "unexpected response #{resp.inspect}"
        end
      end

      def fetch_index
        url = from '-/all'
        path = to '-/all/index.json'
        resp = fetch url, path
        fail Error, "Failed to fetch #{url}" if resp.nil?

        json = JSON.load resp.body
        json.each_key do |k|
          @pool.enqueue_job do
            resp = fetch from(k), to(k)
            json = JSON.load resp.body
            json = tarball_links json
            mtime = resp['last-modified'] || resp['date']
            write_file to(k, 'index.json'), json.to_json, mtime
          end unless k.start_with? '_'
        end
        write_file path, resp.body
      end

      def write_file(path, bytes, mtime = nil)
        FileUtils.mkdir_p File.dirname(path)
        File.open(path, 'wb') do |f|
          f << bytes
        end
        mtime = Time.rfc822 mtime if mtime
        File.utime(mtime, mtime, path) if mtime
      end

      def tarball_links(json)
        json.each do |k, v|
          if v.is_a? Hash
            if v['shasum'] && v['tarball'] && v['tarball'].start_with?(@from)
              tarball = v['tarball']
              path = tarball.split(/^#{@from}/, 2).last
              v['tarball'] = link path
              @pool.enqueue_job do
                resp = fetch from(path), to(path)
                mtime = resp['last-modified'] || resp['date']
                write_file to(path), resp.body, mtime
              end
            else
              json[k] = tarball_links v
            end
          end
        end
        json
      end

      def run
        fetch_index
        @pool.run_til_done
      end
    end
  end
end
