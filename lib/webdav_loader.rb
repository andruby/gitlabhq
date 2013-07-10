require 'fileutils'

class WebdavLoader
  attr_reader :user, :root
  REPOS_PATH = Gitlab.config.gitlab_shell.repos_path
  WEBDAV_ROOT = File.expand_path(File.join(REPOS_PATH,'..','webdav-mirror'))

  def initialize(user)
    @user = user
    @root = File.join(WEBDAV_ROOT, user.username)
  end

  def setup_fs
    ensure_directory_exists(root)
    user.projects.each do |project|
      setup_fs_for_project(project)
    end
  end

  # Clears all user fs mirrors
  def self.clear_webdav_root!
    FileUtils.remove_entry_secure(WEBDAV_ROOT) if File.exists?(WEBDAV_ROOT)
    FileUtils.mkdir_p(WEBDAV_ROOT)
  end

  def self.full_reset!
    all_users = User.includes(:projects => :namespace)
    self.clear_webdav_root!
    self.transfer_passwords!
    all_users.each do |user|
      Rails.logger.debug "creating webdav mirror for user: #{user.username}"
      self.new(user).setup_fs
    end
  end

  def self.transfer_passwords!
    # encrypt acl.yml
    cipher = OpenSSL::Cipher::AES.new(128, :CBC)
    cipher.encrypt
    cipher.key = "\x0F%\x88\x1AP\xC4p\x06JN\x86C\x14\xE5\xAA\xAD"
    cipher.iv = "&9>v,\xD0\xF3\x90I\xA5\xE6\a'\xCB\x05,"
    data = User.all.inject({}) { |h, u| h[u.username] = u.encrypted_password; h }
    encrypted = cipher.update(YAML.dump(data)) + cipher.final
    File.open(File.join(WEBDAV_ROOT, 'acl.yml'), 'wb', 0600) do |f|
      f.write(encrypted)
    end
  end

  private
  def ensure_directory_exists(dir)
    FileUtils.mkdir_p(dir) unless File.exists?(dir)
  end

  def setup_fs_for_project(project)
    git_path = File.join(REPOS_PATH, "#{project.path_with_namespace}.git")
    worktree_path = File.join(git_path, 'fs', 'HEAD', 'worktree')
    mirror_path = File.join(root, project.path_with_namespace)
    ensure_directory_exists(File.join(root, project.namespace.path)) if project.namespace
    spawn('git fs', chdir: git_path) unless File.exists?(worktree_path)
    FileUtils.ln_s(worktree_path, mirror_path) unless File.symlink?(mirror_path)
  end
end