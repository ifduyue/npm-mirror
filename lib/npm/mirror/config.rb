require 'tmpdir'

module Npm
  module Mirror
    DEFAULT_FROM = 'http://registry.npmjs.org/'
    DEFAULT_TO = Dir.mktmpdir 'npm-mirror-'
    DEFAULT_SERVER = 'http://localhost/'
  end
end
