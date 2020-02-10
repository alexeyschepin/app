require 'fileutils'

module Compats
  class Check < Services::Base
    REPO   = 'git@github.com:manuelmeurer/railsbump-checker.git'
    REMOTE = 'origin'
    TMP    = Rails.root.join('tmp')

    def call(compat)
      check_uniqueness

      if compat.checked?
        raise Error, 'Compat is already checked.'
      end

      unless Rails.env.production?
        @compat = compat

        check
      end

      compat.checked!
    end

    private

      def check
        gemmy_name    = @compat.gemmy.name
        gemmy_version = @compat.version
        rails_version = @compat.rails_release.version
        branch_name   = [gemmy_name, gemmy_version, 'rails', rails_version].join('_')
        dir           = TMP.join("railsbump_checker_#{branch_name}")
        ssh_key_file  = TMP.join('ssh_key')

        ssh_key = ENV['SSH_KEY']&.dup
        if ssh_key.present?
          unless ssh_key_file.exist?
            unless ssh_key[-1] == "\n"
              ssh_key << "\n"
            end
            File.write ssh_key_file, ssh_key
          end
          ENV['GIT_SSH_COMMAND']="ssh -o StrictHostKeyChecking=no -i #{ssh_key_file}"
        end

        git = Git.clone(REPO, dir)

        git.config 'user.name',  'RailsBump Checker'
        git.config 'user.email', 'hello@railsbump.org'

        git.checkout

        git.branches.select { |branch| branch.name == branch_name }.each do |branch|
          if branch.remote
            git.push REMOTE, branch.name, delete: true
          else
            branch.delete
          end
        end

        git.branch(branch_name).checkout

        files = {
          '.travis.yml' => <<~CONTENT,
                             language: ruby
                             rvm:
                               - 2.6
                             notifications:
                               webhooks: #{api_travis_notifications_url}
                           CONTENT
          'Gemfile'     => <<~CONTENT,
                             source 'https://rubygems.org'

                             gem 'rails', '#{rails_version}'
                             gem '#{gemmy_name}', '#{gemmy_version}'
                           CONTENT
          'Rakefile'    => 'task :default'
        }

        files.each do |filename, content|
          File.write dir.join(filename), content
          git.add filename
        end

        git.commit "Test compatibility of #{gemmy_name} #{gemmy_version} with Rails #{rails_version}"

        git.push REMOTE, branch_name
      ensure
        if dir&.exist?
          FileUtils.rm_rf dir
        end
      end
  end
end