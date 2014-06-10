# NPM Mirror 

[![Gem Version](https://badge.fury.io/rb/npm-mirror.svg)](http://badge.fury.io/rb/npm-mirror)
[![Code Climate](https://codeclimate.com/github/ifduyue/npm-mirror.png)](https://codeclimate.com/github/ifduyue/npm-mirror)

A NPM Mirror that doesn't need couchdb.

## Installation

Add this line to your application's Gemfile:

    gem 'npm-mirror'

And then execute:

    $ bundle

## Usage

    $ bundle exec bin/npm-mirror [path/to/config.yml]

Or:

    $ npm-mirror [path/to/config.yml]

Here is an example of config.yml

    - from: http://registry.npmjs.org/
      to: /data/mirrors/npm
      server: http://mymirrors.com/npm/
      parallelism: 10
      recheck: false

Serving via Nginx

    server {
        listen 0.0.0.0:80;
        server_name mymirrors.com;
        root /data/mirrors/;
        location /npm/ {
            index index.json;

            location ~ \.etag$ {
                return 404;
            }

            location ~ /index\.json$ {
                default_type application/json;
            }

            # for npm search
            location = /npm/-/all/since {
                rewrite ^ /npm/-/all/;
            }
        }
    }

npm install from your mirror

    npm install -r http://mymirrors.com/npm/ package

## Contributing

1. Fork it ( https://github.com/ifduyue/npm-mirror/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
