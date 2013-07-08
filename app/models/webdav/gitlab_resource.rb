require 'digest/md5'
require 'dav4rack/resources/git_resource'

class Webdav::GitlabResource < DAV4Rack::FileResource
  UnknownTime = Time.at(0)

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
    Rails.logger.debug("** exist? with path: #{path.inspect}")
    Rails.logger.debug("** in_repo: #{in_repo.inspect}")
    (if in_repo then super() else is_namespace? end).tap { |x| Rails.logger.debug("** exist?: #{x.inspect}") }
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
    end.tap { |x| Rails.logger.debug("** NameSpace (from cache): #{x.inspect}") }
  end

  def user_namespace
    options[:user_namespace]
  end

  def generate_fs_structure_for_user(user)
    fs_structure = {}
    user.projects.includes(:namespace).each do |project|
      ensure_project_git_fs(project)
      if project.namespace
        fs_structure[project.namespace.path] ||= {}
        fs_structure[project.namespace.path][project.path] = project.path_with_namespace
      else
        fs_structure[project.path] = project.path_with_namespace
      end
    end
    fs_structure.tap { |x| Rails.logger.debug("** NameSpace: #{x.inspect}") }
  end

  def ensure_project_git_fs(project)
    project_path = File.join(repos_path, "#{project.path_with_namespace}.git")
    Rails.logger.debug("** Ensuring project_path: #{project_path}")
    spawn('git fs', chdir: project_path)
  end

  # FIXME: get fails with No Route matches [GET] #{path}

  # # A Hash of {namespace_path: [repo_paths]}
  # def user_namespaces
  #   @user_namespaces ||= Rails.cache.fetch("dav:namespaces:user:#{self.user.id}", expires_in: 2.minutes) do
  #     namespaces = {"" => Set.new}
  #     self.user.projects.includes(:namespace).each do |project|
  #       if project.namespace
  #         namespaces[""] << project.namespace.path
  #         namespaces[project.namespace.path] ||= []
  #         namespaces[project.namespace.path] << project.path
  #       else
  #         namespaces[""] << project.path
  #       end
  #     end
  #     namespaces
  #   end
  # end
  #
  # # An Array of repository paths with namespace
  # def user_repos
  #   @user_repos ||= Rails.cache.fetch("dav:repos:user:#{self.user.id}", expires_in: 2.minutes) do
  #     self.user.projects.includes(:namespace).map(&:path_with_namespace)
  #   end
  # end

  # Should be set to Gitlab's repos_path
  def root
    if in_repo
      # overload to this repo's root
      File.join(repos_path, "#{leaf}.git")
    else
      repos_path
    end.tap { |x| Rails.logger.debug("** root: #{x.inspect}") }
  end

  def repos_path
    options[:root]
  end

  # Path without leading /
  def clean_path
    @clean_path ||= path.gsub(/^\//,'')
  end

  # Returns the repository path of which path is a part of
  def in_repo
    return leaf.tap { |x| Rails.logger.debug("** in_repo: #{x.inspect}") } if leaf.is_a?(String)
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

  # Overload file_path for files inside a repo
  def file_path
    path_without_repo = clean_path.gsub(/^#{in_repo}/, '')
    Rails.logger.debug("** path_without_repo: #{path_without_repo.inspect}")
    File.join(root, "fs/HEAD/worktree", path_without_repo).tap { |x| Rails.logger.debug("** file_path: #{x.inspect}") }
  end

  # Overload relative_path with
  # def relative_path
  #   path.gsub(/^\/#{in_repo}/,'')
  # end
end
