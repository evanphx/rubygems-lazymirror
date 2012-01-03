require 'rubygems'

require 'net/http'
require 'rack'
require 'json'
require 'fileutils'

module Rubygems
  class Lazymirror
    VERSION = '1.0.0'

    def initialize
      reset_counts
    end

    attr_reader :counts

    def reset_counts
      c = @counts
      @counts = Hash.new(0)
      return c
    end

    def fetch(uri)
      redirections = 0

      begin
        Net::HTTP.start(uri.host, uri.port) do |http|
          rep = http.get(uri.path, { "User-Agent" => "rubygems-lazymirror" })

          case rep
          when Net::HTTPOK
            return rep
          when Net::HTTPFound
            uri = URI.parse rep['Location']
            return nil if redirections == 10
            redirections += 1
            retry
          else
            return nil
          end
        end

        true
      end
    end

    def download(file)
      rep = fetch URI.parse("http://rubygems.org#{file}")

      return nil unless rep

      dest = File.join(Dir.pwd, file)

      FileUtils.mkdir_p File.dirname(dest)

      File.open(dest, "w") do |f|
        f << rep.body
      end

      dest
    end

    def run(host, port)
      handler = Rack::Handler.get("mongrel")
      handler.run self, :Host => host, :Port => port
    end

    def serve(pi, env)
      unless File.exists?(pi)
        unless file = download(pi)
          return [404, {}, "File '#{pi}' not available\n"]
        end
      end

      rf = Rack::File.new nil
      rf.path = file

      return rf.serving(env)
    end

    def call(env)
      pi = env['PATH_INFO']

      case pi
      when %r!\.\./!
        [404, {}, "Stop trying to go where you don't belong"]

      when %r!^/gems/!
        @counts[pi] += 1
        serve pi, env

      when %r!^/quick/!
        serve pi, env

      when "/stats"
        [200, {}, @counts.to_json]
      when "/reset-stats"
        [200, {}, reset_counts.to_json]
      else
        [302, { 'Location' => "http://rubygems.org#{pi}" }, ""]
      end
    end
  end
end

