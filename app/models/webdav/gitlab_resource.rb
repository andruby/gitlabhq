require 'digest/md5'
require 'fileutils'
require 'dav4rack/resources/git_resource'

class Webdav::GitlabResource < DAV4Rack::FileResource
  UnknownTime = Time.at(0)

  def setup
    ensure_directory_exists(root)
  end

  def children
    if is_namespace?
      leaf.keys.map do |repo|
        child("#{repo}/")
      end
    elsif in_repo
      super
    end
  end

  def collection?
    if in_repo then super() else is_namespace? end
  end

  def exist?
    if in_repo then super() else is_namespace? end
  end

  def creation_date
    if in_repo then super() else UnknownTime end
  end

  def last_modified
    if in_repo then super() else UnknownTime end
  end

  def etag
    (Digest::MD5.hexdigest(path) if is_namespace?) or (super() if in_repo)
  end

  def content_type
    ("text/directory" if is_namespace?) or (super() if in_repo)
  end

  def content_length
    if in_repo then super() else 0 end
  end

  #
  # Read Only Implementation, so we dissallow the following requests
  #
  def forbidden(*args)
    raise HTTPStatus::Forbidden
  end

  %w{put post delete copy move make_collection lock unlock last_modified=}.each { |method| alias_method method, :forbidden }

  private
  def authenticate(username, password)
    # Security warning: we cache the authentication globally for 2 minutes
    # Hashed as somewhat insecure MD5
    cache_key = "dav:user:#{Digest::MD5.hexdigest("#{username}:#{password}")}"
    options[:user_namespace] = Rails.cache.fetch(cache_key, expires_in: 1.minutes) do
      Rails.logger.debug("** Cache mis, fetching user namespace **")
      user = User.where("username = :username OR email = :username", username: username).first
      generate_fs_structure_for_user(user) if user.try(:valid_password?, password)
    end
  end

  def user_namespace
    options[:user_namespace]
  end

  def generate_fs_structure_for_user(user)
    fs_structure = {}
    user.projects.includes(:namespace).each do |project|
      ensure_project_fs(project)
      if project.namespace
        fs_structure[project.namespace.path] ||= {}
        fs_structure[project.namespace.path][project.path] = project.path_with_namespace
      else
        fs_structure[project.path] = project.path_with_namespace
      end
    end
    fs_structure
  end

  def ensure_project_fs(project)
    git_path = File.join(repos_path, "#{project.path_with_namespace}.git")
    worktree_path = File.join(git_path, 'fs', 'HEAD', 'worktree')
    mirror_path = File.join(root, project.path_with_namespace)
    ensure_directory_exists(File.join(root, project.namespace.path)) if project.namespace
    spawn('git fs', chdir: git_path) unless File.exists?(worktree_path)
    FileUtils.ln_s(worktree_path, mirror_path) unless File.symlink?(mirror_path)
  end

  def ensure_directory_exists(dir)
    FileUtils.mkdir_p(dir) unless File.exists?(dir)
  end

  # Should be set to Gitlab's repos_path
  def root
    options[:root]
  end

  def repos_path
    options[:repos_path]
  end

  # Path without leading /
  def clean_path
    @clean_path ||= path.gsub(/^\//,'')
  end

  # Returns the repository path of which path is a part of
  def in_repo
    return leaf if leaf.is_a?(String)
  end

  def leaf
    # memoize even if it is false or nil
    return @leaf if defined?(@leaf)
    @leaf = get_leaf
  end

  # Returns the leaf of the tree
  def get_leaf
    parts = path_parts[0..1]
    base = user_namespace.dup
    parts.each { |part| base = base[part] if base.is_a?(Hash) }
    base
  end

  # Is the path a namespace?
  def is_namespace?
    path_parts.length == 0 || (path_parts.length == 1 && leaf.is_a?(Hash))
  end

  def path_parts
    @path_parts ||= clean_path.split('/')
  end

  # Overload relative_path with
  def path_without_repo
    clean_path.gsub(/^#{in_repo}/, '')
  end
end
