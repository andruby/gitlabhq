# Rackup Script
require 'dav4rack'
require 'dav4rack/resources/file_resource'
require 'bcrypt'
require 'yaml'
require 'digest/md5'
require 'thin'

root_path = "/home/git/webdav-mirror"

class Cache
  attr_accessor :data

  def initialize
    @data = {}
  end

  def fetch(key,&block)
    if data.has_key?(key)
      data[key]
    else
      data[key] = yield
    end
  end
end

class AuthenticatedResource < DAV4Rack::FileResource
  def setup
    Thread.current['cache'] ||= Cache.new
  end

  #
  # Read Only Implementation, so we forbid the following requests
  #
  def forbidden(*args)
    raise Forbidden
  end
  %w{put post delete copy move make_collection lock unlock last_modified=}.each { |method| alias_method method, :forbidden }


  private
  def authenticate(username, password)
    # TODO: check_password
    self.user = username
    Thread.current['cache'].fetch(Digest::MD5.hexdigest("#{user}:#{password}")) do
      valid_password?(password)
    end
  end

  # Verifies whether an password (ie from sign in) is the user password.
  # Adapted from Devise database_authenticable.rb
  def valid_password?(password)
    return false if (encrypted_password.nil? || encrypted_password.size == 0)
    bcrypt   = ::BCrypt::Password.new(encrypted_password)
    password = ::BCrypt::Engine.hash_secret(password, bcrypt.salt) # No Pepper used
    password == encrypted_password
  end

  # Gets the encrypted password
  def encrypted_password
    Thread.current['cache'].fetch("hashed_passwords") do
      # Decrypt acl.yaml
      decipher = OpenSSL::Cipher::AES.new(128, :CBC)
      decipher.decrypt
      decipher.key = "\x0F%\x88\x1AP\xC4p\x06JN\x86C\x14\xE5\xAA\xAD"
      decipher.iv = "&9>v,\xD0\xF3\x90I\xA5\xE6\a'\xCB\x05,"
      encrypted = File.read(File.join(options[:root], 'acl.yml'))
      YAML.load(decipher.update(encrypted) + decipher.final)
    end[self.user]
  end

  # Overload root to the authenticated user's path
  def root
    File.join(options[:root], self.user)
  end
end

use Rack::CommonLogger
run DAV4Rack::Handler.new(:root => root_path, :resource_class =>AuthenticatedResource)