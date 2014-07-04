require 'net/http/persistent'
require 'json'
require 'fileutils'

require 'npm/mirror/version'
require 'npm/mirror/config'

module Npm
  module Mirror
    autoload :Pool, 'npm/mirror/pool'

    class Error < StandardError; end

    class Mirror
      attr_reader :from, :to, :server, :parallelism

      def initialize(from = DEFAULT_FROM, to = DEFAULT_TO,
                     server = DEFAULT_SERVER, parallelism = 10,
                     recheck = false)
        @from, @to, @server = from, to, server
        parallelism ||= 10
        recheck ||= false
        @pool = Pool.new parallelism
        @http = Net::HTTP::Persistent.new self.class.name
        @recheck = recheck

        puts "Mirroring  : #{from}"
        puts "Datadir    : #{to}"
        puts "Server     : #{server}"
        puts "Parallelism: #{parallelism}"
        puts "Recheck    : #{recheck}"
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
        uri = URI url
        etag = etag_for path

        req = Net::HTTP::Get.new uri.path
        req.add_field 'If-None-Match', etag if etag

        begin
          resp = @http.request uri, req
          fail Error, '503' if resp.code == '503'  # 503 backend read error
        rescue => e
          puts "[#{id}] Error fetching #{uri.path}: #{e.inspect}"
          sleep 10
          retry
        end

        puts "[#{id}] Fetched(#{resp.code}): #{uri}"
        case resp.code.to_i
        when 301  # Moved
          return fetch resp['location'], path
        when 302  # Found
          return fetch resp['location'], path
        when 200
          return resp
        when 304  # Not modified
          return resp if @recheck
          return nil
        when 403
          return nil
        when 404  # couchdb returns json even it's 404
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

        if resp.code == '304'
          if File.exist? path
            json = JSON.load(File.open(path, 'rb').read)
          else
            json = {}
          end
        else
          json = JSON.load resp.body
        end

        @pool.run

        packages = json.keys
        packages.each_slice(@pool.size * 10) do |slice|
          slice.each do |package|
            next if package.start_with? '_'
            @pool.enqueue_job(package, &method(:fetch_package))
          end
          sleep 0.5
        end

        @pool.enqueue_job do
          write_file path, resp.body, resp['etag']
        end unless resp.code == '304'
      end

      def fetch_package(package)
        url = from package
        path = to package, 'index.json'
        resp = fetch url, path
        return if resp.nil?

        if resp.code == '304'
          json = JSON.load(File.open(path, 'rb').read)
          tarball_links json
        else
          json = JSON.load resp.body
          deal_with_removals_for json
          tarball_links json
          write_file path, json.to_json, resp['etag']
          write_package_versions(package, json)
        end
      end

      def write_package_versions(package, json)
        return unless json['versions']
        json['versions'].each do |k, v|
          path = to package, k, 'index.json'
          write_file path, v.to_json, nil
        end
      end

      def fetch_tarball(tarball_uri)
        url = from tarball_uri
        path = to tarball_uri
        resp = fetch url, path
        return if resp.nil? || resp.code == '304' || resp.body.size.zero?
        write_file path, resp.body, resp['etag']
      end

      def write_file(path, bytes, etag = nil)
        FileUtils.mkdir_p File.dirname(path)
        File.open(path, 'wb') { |f| f << bytes }
        File.open(path_for_etag(path), 'wb') { |f| f << etag } if etag
      end

      def tarball_links(json)
        json.each do |_, v|
          if v.is_a? Hash
            if v['shasum'] && v['tarball']
              if v['tarball'].start_with?(@from)
                tarball = v['tarball'].split(/^#{@from}/, 2).last
                v['tarball'] = link tarball
              elsif v['tarball'].start_with?(@server)
                tarball = v['tarball'].split(/^#{@server}/, 2).last
              end
              @pool.enqueue_job(tarball, &method(:fetch_tarball))
            else
              tarball_links v
            end
          end
        end
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

      def correct_tarball_url
        Dir.glob("#{to}/*/index.json").each do |filename|
          json = JSON.load(File.open(filename, 'rb').read)
          next unless json['versions']
          versions = json['versions'].keys
          versions.each do |version|
            next unless json['versions'][version]['dist']
            tarball = URI json['versions'][version]['dist']['tarball']
            tarball = link tarball.path
            json['versions'][version]['dist']['tarball'] = tarball
          end
          File.open(filename, 'wb') { |f| f << json.to_json }
          write_package_versions json['name'], json
          puts filename
        end
      end

      def deal_with_removals_for(package_json)
        return unless package_json['versions']

        package = package_json['name']
        theirs = package_json['versions'].keys
        ours = Dir.glob("#{to}/#{package}/*").map { |x| File.basename x }
        removals = ours - theirs
        removals.each do |version|
          FileUtils.rm_rf "#{to}/#{package}/#{version}"
        end
      end
    end
  end
end
