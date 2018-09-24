require 'bundler'

require 'sinatra'
require 'nokogiri'
require 'httpclient'
require 'redis'

BASE_URL = "https://octodex.github.com/"

if ENV["REDISTOGO_URL"]
  uri = URI.parse(ENV["REDISTOGO_URL"])
  REDIS = Redis.new(host: uri.host, port: uri.port, password: uri.password)
else
  REDIS = Redis.new
end

configure do
  enable :cross_origin
end

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

options "*" do
  response.headers["Allow"] = "GET, POST, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token"
  response.headers["Access-Control-Allow-Origin"] = "*"
  200
end

get '/' do
  client = HTTPClient.new

  etag = client.head(BASE_URL).headers['ETag']
  cached = REDIS.get(etag)

  status = "cached"

  unless cached == etag
    status = "live"

    doc = Nokogiri::HTML(client.get(BASE_URL).body)

    items = doc.css('.item-shell').map do |item|
      number = item.css('.footer .number').text().gsub('#', '').to_i

      name = item.css('p.purchasable a').text()

      image = "#{BASE_URL}#{item.css('.preview-image img')[0]['data-src']}"

      link = "#{BASE_URL}#{item.css('p.purchasable a')[0]['href']}"

      authors = item.css('.footer > a').map do |author|
        {
          link: author['href'],
          image: author.css('img')[0]['src']
        }
      end

      data = {
        number: number,
        name: name,
        image: image,
        link: link,
        authors: authors
      }
    end
    data = items.to_json

    REDIS.set(etag, data)
  end

  { status: status, data: data }
end
