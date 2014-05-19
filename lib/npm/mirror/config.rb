require 'tmpdir'

module Npm
  module Mirror
    DEFAULT_FROM = 'http://registry.npmjs.org/'
    DEFAULT_TO = File.join(Dir.tmpdir, 'npm-mirror')
    DEFAULT_SERVER = 'http://localhost/'
  end
end
