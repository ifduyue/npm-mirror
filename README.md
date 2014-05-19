# NPM Mirror 

A NPM Mirror that doesn't need couchdb.

## Installation

Add this line to your application's Gemfile:

    gem 'npm-mirror'

And then execute:

    $ bundle

## Usage

    $ bundle exec bin/mirror

Or:

    $ bundle exec bin/mirror path/to/config.yml

Here is an example of config.yml

    - from: http://registry.npmjs.org/
      to: /tmp/npm/
      server: http://localhost/
      parallelism: 10

## Contributing

1. Fork it ( https://github.com/ifduyue/npm-mirror/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
