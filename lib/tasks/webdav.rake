namespace :webdav do
  desc "Reset webdav fs mirror and anthentication"
  task :reset => :environment do
    # Make sure we start from a clean slate so deleted users are removed
    WebdavLoader.full_reset!
  end
end
