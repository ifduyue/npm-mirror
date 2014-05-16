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
        if Thread.current[:id]
          "Thread-#{Thread.current[:id].to_s.rjust(l, '0')}"
        else
          'Master'.ljust(%w(Thread- Master).map(&:size).max + l)
        end
      end

      def fetch(url, path = nil)
        puts "[#{id}] Fetching #{url}"
        uri = URI url
        mtime = mtime_for path
        etag = etag_for path

        req = Net::HTTP::Get.new uri.path
        req.add_field 'If-Modified-Since', mtime if mtime
        req.add_field 'If-None-Match', etag if etag

        begin
          resp = @http.request uri, req
        rescue => e
          puts "[#{id}] Error fetching #{uri.path}: #{e.inspect}"
          sleep 10
          retry
        end

        puts "[#{id}] Fetched(#{resp.code}): #{uri}"
        case resp.code.to_i
        when 301  # Moved
        when 302  # Found
          return fetch resp['location'], path
        when 200
          return resp
        when 304  # Not modified
          return nil
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
          @pool.enqueue_job(k, &method(:fetch_package)) unless k.start_with? '_'
        end
        write_file path, resp.body, resp['last-modified'], resp['etag']
      end

      def fetch_package(package)
        url = from package
        path = to package, 'index.json'
        resp = fetch url, path
        return if resp.nil?
        json = JSON.load resp.body
        json = tarball_links json
        write_file path, json.to_json, resp['last-modified'], resp['etag']
      end

      def fetch_tarball(tarball_uri)
        url = from tarball_uri
        path = to tarball_uri
        resp = fetch url, path
        return if resp.nil?
        write_file path, json.to_json, resp['last-modified'], resp['etag']
      end

      def write_file(path, bytes, mtime = nil, etag = nil)
        FileUtils.mkdir_p File.dirname(path)
        File.open(path, 'wb') { |f| f << bytes }
        mtime = Time.rfc822 mtime if mtime
        File.utime(mtime, mtime, path) if mtime
        File.open(path_for_etag(path), 'wb') { |f| f << etag } if etag
      end

      def tarball_links(json)
        json.each do |k, v|
          if v.is_a? Hash
            if v['shasum'] && v['tarball'] && v['tarball'].start_with?(@from)
              tarball = v['tarball'].split(/^#{@from}/, 2).last
              v['tarball'] = link tarball
              @pool.enqueue_job(tarball, &method(:fetch_tarball))
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

      def path_for_etag(path)
        if path.nil?
          nil
        elsif File.directory? path
          File.join path, '.etag'
        else
          dirname, basename = File.split path
          File.join dirname, ".#{basename}.etag"
        end
      end

      def etag_for(path)
        etag_path = path_for_etag path
        if !etag_path
          nil
        elsif File.file?(etag_path) && File.readable?(etag_path)
          File.open(etag_path, 'rb') { |f| f.readline.strip }
        else
          nil
        end
      end

      def mtime_for(path)
        if path.nil?
          nil
        elsif File.exist?(path)
          File.stat(path).mtime.rfc822
        else
          nil
        end
      end
    end
  end
end
