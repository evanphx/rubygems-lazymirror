require 'rubygems'

require 'net/http'
require 'rack'
require 'json'
require 'fileutils'

module Gem
  class Lazymirror
    VERSION = '1.0.0'

    def initialize(root, token=nil)
      @root = root
      @token = /token=#{token}\b/ if token
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

    def download(file, dest)
      rep = fetch URI.parse("http://rubygems.org#{file}")

      return nil unless rep

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
      file = File.join(@root, pi)

      unless File.exists?(file)
        unless file = download(pi, file)
          return [404, {}, "File '#{pi}' not available\n"]
        end
      end

      rf = Rack::File.new nil
      rf.path = file

      return rf.serving(env)
    end

    OneKBlob = ["x" * 1024]
    TenKBlob = ["x" * 10240]

    def call(env)
      pi = env['PATH_INFO']

      case pi
      when %r!\.\./!
        [404, {}, ["Stop trying to go where you don't belong"]]

      when %r!^/gems/!
        @counts[pi] += 1
        serve pi, env

      when %r!^/quick/!
        serve pi, env

      when "/stats"
        if @token and env['QUERY_STRING'] !~ @token
          [403, {}, ["Invalid token"]]
        else
          [200, {}, [@counts.to_json]]
        end
      when "/reset-stats"
        if @token and env['QUERY_STRING'] !~ @token
          [403, {}, ["Invalid token"]]
        else
          [200, {}, [reset_counts.to_json]]
        end
      when "/measure/1k"
        [200, {}, OneKBlob]
      when "/measure/10k"
        [200, {}, TenKBlob]
      else
        [302, { 'Location' => "http://rubygems.org#{pi}" }, [""]]
      end
    end
  end
end

