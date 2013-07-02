require 'set'
require 'dav4rack/resources/git_resource'

class Webdav::GitlabResource < DAV4Rack::GitResource
  UnknownTime = Time.at(0)

  def children
    if is_namespace?
      user_namespaces[clean_path].map do |repo|
        child(repo)
      end
    elsif in_repo
      super
    end
  end

  def collection?
    is_namespace? or (super() if in_repo)
  end

  def exist?
    is_namespace? or (super() if in_repo)
  end

  def creation_date
    if in_repo then super() else UnknownTime end
  end

  def last_modified
    if in_repo then super() else UnknownTime end
  end

  def content_length
    if in_repo then super() else 0 end
  end

  private
  def authenticate(username, password)
    # Security warning: we cache the authentication globally for 2 minutes
    # Hashed as somewhat insecure MD5
    cache_key = "dav:user:#{Digest::MD5.hexdigest("#{username}:#{password}")}"
    self.user = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      user = User.where("username = :username OR email = :username", username: username).first
      user.try(:valid_password?, password) && user
    end
  end

  # A Hash of {namespace_path: [repo_paths]}
  def user_namespaces
    @user_namespaces ||= Rails.cache.fetch("dav:namespaces:user:#{self.user.id}", expires_in: 2.minutes) do
      namespaces = {"" => Set.new}
      self.user.projects.includes(:namespace).each do |project|
        if project.namespace
          namespaces[""] << project.namespace.path
          namespaces[project.namespace.path] ||= []
          namespaces[project.namespace.path] << project.path
        else
          namespaces[""] << project.path
        end
      end
      namespaces
    end
  end

  # An Array of repository paths with namespace
  def user_repos
    @user_repos ||= Rails.cache.fetch("dav:repos:user:#{self.user.id}", expires_in: 2.minutes) do
      self.user.projects.includes(:namespace).map(&:path_with_namespace)
    end
  end

  # Should be set to Gitlab's repos_path
  def root
    options[:root]
  end

  # Path without leading /
  def clean_path
    @clean_path ||= path.gsub(/^\//,'')
  end

  def in_repo
    # memoize even if it is false or nil
    return @in_repo if defined?(@in_repo)
    @in_repo = get_in_repo
  end

  # Returns the repository path of which path is a part of
  def get_in_repo
    parts = clean_path.split('/')
    base_path = parts.first
    namespaced_path = parts[0..1].join('/')
    user_repos.detect { |repo| repo == base_path || repo == namespaced_path }
  end

  # Is the path a namespace?
  def is_namespace?
    # memoize even if it is false or nil
    return @is_namespace if defined?(@is_namespace)
    @is_namespace = user_namespaces.keys.include?(clean_path)
  end

  # Overload git_dir with real git dir
  def git_dir
    @git_dir ||= File.join(root, "#{in_repo}.git")
  end

  # Overload relative_path with
  def relative_path
    @relative_path ||= path.gsub(/^\/#{in_repo}/,'')
  end
end
