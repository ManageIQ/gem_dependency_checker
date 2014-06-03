# Polisher Gem Represenation
#
# Licensed under the MIT license
# Copyright (C) 2013-2014 Red Hat, Inc.

require 'polisher/vendor'
require 'polisher/component'
require 'polisher/gem_cache'
require 'polisher/version_checker'

module Polisher
  deps = ['curb', 'json', 'yaml', 'tempfile', 'pathname', 'fileutils',
          'awesome_spawn', 'rubygems/installer', 'active_support', 'active_support/core_ext']
  Component.verify("Gem", *deps) do
    class Gem
      include HasVendoredDeps

      GEM_CMD      = '/usr/bin/gem'
      DIFF_CMD     = '/usr/bin/diff'

      # Common files shipped in gems that we should ignore
      IGNORE_FILES = ['.gemtest', '.gitignore', '.travis.yml',
                      /.*.gemspec/, /Gemfile.*/, 'Rakefile',
                      /rspec.*/, '.yardopts', '.rvmrc']

      # Common files shipped in gems that we should mark as doc
      DOC_FILES = [/\/?CHANGELOG.*/, /\/?CONTRIBUTING.*/, /\/?README.*/, /\/?.*LICENSE/]

      attr_accessor :spec
      attr_accessor :name
      attr_accessor :version
      attr_accessor :deps
      attr_accessor :dev_deps

      attr_accessor :path

      def file_name
        "#{name}-#{version}.gem"
      end

      def initialize(args={})
        @spec     = args[:spec]
        @name     = args[:name]
        @version  = args[:version]
        @path     = args[:path]
        @deps     = args[:deps]     || []
        @dev_deps = args[:dev_deps] || []
      end

      # Return bool indicating if the specified file is on the IGNORE_FILES list
      def self.ignorable_file?(file)
        IGNORE_FILES.any? do |ignore|
          ignore.is_a?(Regexp) ? ignore.match(file) : ignore == file
        end
      end

      # Return bool indicating if the specified file is on the DOC_FILES list
      def self.doc_file?(file)
        DOC_FILES.any? do |doc|
          doc.is_a?(Regexp) ? doc.match(file) : doc == file
        end
      end

      # Return bool indicating if spec file satisfies any file in gem
      def has_file_satisfied_by?(spec_file)
        file_paths.any? { |gem_file| RPM::Spec.file_satisfies?(spec_file, gem_file) }
      end

      # Retrieve list of the versions of the specified gem installed locally
      #
      # @param [String] name name of the gem to lookup
      # @param [Callable] bl optional block to invoke with versions retrieved
      # @return [Array<String>] list of versions of gem installed locally
      def self.local_versions_for(name, &bl)
        silence_warnings do
          @local_db ||= ::Gem::Specification.all
        end
        versions = @local_db.select { |s| s.name == name }.collect { |s| s.version }
        bl.call(:local_gem, name, versions) unless(bl.nil?)
        versions
      end

      # Return new instance of Gem from JSON Specification
      def self.from_json(json)
        specj     = JSON.parse(json)
        metadata           = {}
        metadata[:spec]    = specj
        metadata[:name]    = specj['name']
        metadata[:version] = specj['version']

        metadata[:deps] =
          specj['dependencies']['runtime'].collect { |d|
            ::Gem::Dependency.new d['name'], *d['requirements'].split(',')
          }

        metadata[:dev_deps] =
          specj['dependencies']['development'].collect { |d|
            ::Gem::Dependency.new d['name'], d['requirements'].split(',')
          }

        self.new metadata
      end

      # Retrieve all versions of gem available on rubygems
      def self.remote_versions_for(name)
        client.url = "https://rubygems.org/api/v1/versions/#{name}.json"
        client.follow_location = true
        client.http_get
        json = JSON.parse(client.body_str)
        json.collect { |version| version['number'] }
      end

      # Retieve latest version of gem available on rubygems
      def self.latest_version_of(name)
        remote_versions_for(name).first
      end

      # Return new instance of Gem from Gemspec
      def self.from_gemspec(gemspec)
        gemspec  =
          ::Gem::Specification.load(gemspec) if !gemspec.is_a?(::Gem::Specification) &&
                                                 File.exists?(gemspec)

        metadata           = {}
        metadata[:spec]    = gemspec
        metadata[:name]    = gemspec.name
        metadata[:version] = gemspec.version.to_s

        metadata[:deps] =
          gemspec.dependencies.select { |dep|
            dep.type == :runtime
          }.collect { |dep| dep }

        metadata[:dev_deps] =
          gemspec.dependencies.select { |dep|
            dep.type == :development
          }.collect { |dep| dep }

        self.new metadata
      end

      # Return new instance of Gem from rubygem
      def self.from_gem(gem_path)
        gem = self.parse :gemspec => ::Gem::Package.new(gem_path).spec
        gem.path = gem_path
        gem
      end

      # Parse the specified gemspec & return new Gem instance from metadata
      #
      # @param [String,Hash] args contents of actual gemspec of option hash
      # specifying location of gemspec to parse
      # @option args [String] :gemspec path to gemspec to load / parse
      # @return [Polisher::Gem] gem instantiated from gemspec metadata
      def self.parse(args={})
        if args.is_a?(String)
          return self.from_json args

        elsif args.has_key?(:gemspec)
          return self.from_gemspec args[:gemspec]

        elsif args.has_key?(:gem)
          return self.from_gem args[:gem]

        end

        self.new
      end

      # Return handler to internal curl helper
      def self.client
        @client ||= Curl::Easy.new
      end

      # Download the specified gem and return the binary file contents as a string
      #
      # @return [String] binary gem contents
      def self.download_gem(name, version)
        cached = GemCache.get(name, version)
        return cached unless cached.nil?

        client.url = "https://rubygems.org/gems/#{name}-#{version}.gem"
        client.follow_location = true
        client.http_get
        gemf = client.body_str

        GemCache.set(name, version, gemf)
        gemf
      end

      # Download the local gem and return it as a string
      def download_gem
        self.class.download_gem @name, @version
      end

      # Download the specified gem / version from rubygems and
      # return instance of Polisher::Gem class corresponding to it
      def self.from_rubygems(name, version)
        download_gem name, version
        self.from_gem downloaded_gem_path(name, version)
      end

      # Returns path to downloaded gem
      #
      # @return [String] path to downloaded gem
      def self.downloaded_gem_path(name, version)
        # ensure gem is downloaded
        self.download_gem(name, version)
        GemCache.path_for(name, version)
      end

      # Return path to downloaded gem
      def downloaded_gem_path
        self.class.downloaded_gem_path @name, @version
      end

      # Returns path to gem, either specified one of downloaded one
      def gem_path
        @path || downloaded_gem_path
      end

      # Unpack files & return unpacked directory
      #
      # If block is specified, it will be invoked
      # with directory after which directory will be removed
      def unpack(&bl)
        dir = nil
        pkg = ::Gem::Installer.new gem_path, :unpack => true

        if bl
          Dir.mktmpdir { |dir|
            pkg.unpack dir
            bl.call dir
          }
        else
          dir = Dir.mktmpdir
          pkg.unpack dir
        end

        dir
      end

      # Iterate over each file in gem invoking block with path
      def each_file(&bl)
        self.unpack do |dir|
          Pathname(dir).find do |path|
            next if path.to_s == dir.to_s
            pathstr = path.to_s.gsub("#{dir}/", '')
            bl.call pathstr unless pathstr.blank?
          end
        end
      end

      # Retrieve the list of paths to files in the gem
      #
      # @return [Array<String>] list of files in the gem
      def file_paths
        @file_paths ||= begin
          files = []
          self.each_file do |path|
            files << path
          end
          files
        end
      end

      # Retrieve gem metadata and contents from rubygems.org
      #
      # @param [String] name string name of gem to retrieve
      # @return [Polisher::Gem] representation of gem
      def self.retrieve(name)
        gem_json_path = "https://rubygems.org/api/v1/gems/#{name}.json"
        spec = Curl::Easy.http_get(gem_json_path).body_str
        gem  = self.parse spec
        gem
      end

      # Retreive versions of gem available in all configured targets (optionally recursively)
      #
      # @param [Hash] args hash of options to configure retrieval
      # @option args [Boolean] :recursive indicates if versions of dependencies
      # should also be retrieved
      # @option args [Boolean] :dev_deps indicates if versions of development
      # dependencies should also be retrieved
      # @return [Hash<name,versions>] hash of name to list of versions for gem
      # (and dependencies if specified)
      def versions(args={}, &bl)
        recursive = args[:recursive]
        dev_deps  = args[:dev_deps]
        versions  = args[:versions] || {}

        gem_versions = Polisher::VersionChecker.versions_for(self.name, &bl)
        versions.merge!({ self.name => gem_versions })
        args[:versions] = versions

        if recursive
          self.deps.each { |dep|
            unless versions.has_key?(dep.name)
              gem = Polisher::Gem.retrieve(dep.name)
              versions.merge! gem.versions(args, &bl)
            end
          }

          if dev_deps
            self.dev_deps.each { |dep|
              unless versions.has_key?(dep.name)
                gem = Polisher::Gem.retrieve(dep.name)
                versions.merge! gem.versions(args, &bl)
              end
            }
          end
        end
        versions
      end

      # Return diff of content in this gem against other
      def diff(other)
        out = nil

        begin
          this_dir  = self.unpack
          other_dir = other.is_a?(Polisher::Gem) ? other.unpack :
                     (other.is_a?(Polisher::Git::Repo) ? other.path : other)
          result = AwesomeSpawn.run("#{DIFF_CMD} -r #{this_dir} #{other_dir}")
          out = result.output.gsub("#{this_dir}", 'a').gsub("#{other_dir}", 'b')
        rescue
        ensure
          FileUtils.rm_rf this_dir  unless this_dir.nil?
          FileUtils.rm_rf other_dir unless  other_dir.nil? ||
                                           !other.is_a?(Polisher::Gem)
        end

        out
      end
    end # class Gem
  end # Component.verify("Gem")
end # module Polisher
