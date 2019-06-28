require "bundler"

require "sinatra"
require "redis"
require "nokogiri"
require "httpclient"

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
  response.headers["Access-Control-Allow-Origin"] = "*"
end

options "*" do
  response.headers["Allow"] = "GET, POST, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token"
  response.headers["Access-Control-Allow-Origin"] = "*"
  200
end

get "/" do
  client = HTTPClient.new

  etag = client.head(BASE_URL).headers["ETag"]
  cached = REDIS.get(etag)

  status = "cached"

  if cached && !params["live"]
    data = JSON.parse(cached)
  else
    status = "live"

    doc = Nokogiri::HTML(client.get(BASE_URL).body)

    items = doc.css(".post").map do |item|
      number = item.css("span.pr-1.text-gray").text().gsub("#", "").to_i

      name = item.css("a.link-gray-dark").text().gsub(/[\n ]/, "")

      image = "#{BASE_URL}#{item.css("img.d-block.width-fit.height-auto.rounded-1")[0]["data-src"]}"

      link = "#{BASE_URL}#{item.css("a.link-gray-dark")[0]["href"]}"

      authors = item.css(".flex-nowrap a").map do |author|
        {
          link: author["href"],
          image: author.css("img")[0]["src"],
        }
      end

      data = {
        number: number,
        name: name,
        image: image,
        link: link,
        authors: authors,
      }
    end
    data = items

    REDIS.set(etag, data.to_json)
  end

  {status: status, data: data}.to_json
end
