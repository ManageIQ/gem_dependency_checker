# Helpers to check versions
#
# Licensed under the MIT license
# Copyright (C) 2013-2014 Red Hat, Inc.

require 'polisher/gem'
require 'polisher/logger'

module Polisher
  class VersionChecker
    extend Logging

    GEM_TARGET    = :gem
    KOJI_TARGET   = :koji
    FEDORA_TARGET = :fedora
    GIT_TARGET    = :git
    YUM_TARGET    = :yum
    BODHI_TARGET  = :bodhi  # fedora dispatches to bodhi so not enabled by default
    ERRATA_TARGET = :errata # not enabled by default
    ALL_TARGETS   = [GEM_TARGET, KOJI_TARGET, FEDORA_TARGET,
                     GIT_TARGET, YUM_TARGET]

    # Enable the specified target(s) in the list of target to check
    def self.check(*target)
      @check_list ||= []
      target.flatten.each { |t| @check_list << t }
    end

    def self.should_check?(target)
      @check_list ||= Array.new(ALL_TARGETS)
      @check_list.include?(target)
    end

    # Retrieve all the versions of the specified package using
    # the configured targets.
    #
    # If not specified, all targets are checked
    # @param [String] name name of package to query
    # @param [Callable] bl optional block to invoke with versions retrieved
    # @returns [Hash<target,Array<String>>] returns a hash of target to versions
    # available for specified package
    def self.versions_for(name, &bl)
      versions = {}

      if should_check?(GEM_TARGET)
        logger.debug "versions_for<gem>(#{name})..."
        gem_versions = Gem.local_versions_for(name, &bl)
        logger.debug gem_versions
        versions.merge! :gem => gem_versions
      end

      if should_check?(FEDORA_TARGET)
        begin
          require 'polisher/fedora'
          logger.debug "versions_for<fedora>(#{name})..."
          fedora_versions = Fedora.versions_for(name, &bl)
          logger.debug fedora_versions
          versions.merge! :fedora => fedora_versions
        rescue
          logger.debug 'unknown'
          versions.merge! :fedora => unknown_version(:fedora, name, &bl)
        end
      end

      if should_check?(KOJI_TARGET)
        begin
          require 'polisher/koji'
          logger.debug "versions_for<koji>(#{name})..."
          koji_versions = Koji.versions_for(name, &bl)
          logger.debug koji_versions
          versions.merge! :koji => koji_versions
        rescue
          logger.debug 'unknown'
          versions.merge! :koji => unknown_version(:koji, name, &bl)
        end
      end

      if should_check?(GIT_TARGET)
        begin
          require 'polisher/git/pkg'
          logger.debug "versions_for<git>(#{name})..."
          git_versions = Git::Pkg.versions_for(name, &bl)
          logger.debug git_versions
          versions.merge! :git => git_versions
        rescue
          logger.debug 'unknown'
          versions.merge! :git => unknown_version(:git, name, &bl)
        end
      end

      if should_check?(YUM_TARGET)
        begin
          require 'polisher/yum'
          logger.debug "versions_for<yum>(#{name})..."
          yum_versions = [Yum.version_for(name, &bl)].compact
          versions.merge! :yum => yum_versions
          logger.debug yum_versions
        rescue
          logger.debug 'unknown'
          versions.merge! :yum => unknown_version(:yum, name, &bl)
        end
      end

      if should_check?(BODHI_TARGET)
        begin
          require 'polisher/bodhi'
          logger.debug "versions_for<bodhi>(#{name})..."
          bodhi_versions = Bodhi.versions_for(name, &bl)
          versions.merge! :bodhi => bodhi_versions
          logger.debug bodhi_versions
        rescue
          logger.debug 'unknown'
          versions.merge! :bodhi => unknown_version(:bodhi, name, &bl)
        end
      end

      if should_check?(ERRATA_TARGET)
        begin
          require 'polisher/errata'
          logger.debug "versions_for<errata>(#{name})..."
          errata_versions = Errata.versions_for(name, &bl)
          versions.merge! :errata => errata_versions
          logger.debug errata_versions
        rescue
          logger.debug 'unknown'
          versions.merge! :errata => unknown_version(:errata, name, &bl)
        end
      end

      versions
    end

    # Return version of package most frequent references in each
    # configured target.
    def self.version_for(name)
      Hash[versions_for(name).collect do |k, versions|
        most = versions.group_by { |v| v }.values.max_by(&:size).first
        [k, most]
      end]
    end

    # Return version of package most frequent reference in all
    # configured targets.
    def self.version_of(name)
      version_for(name).values.group_by { |v| v }.values.max_by(&:size).first
    end

    # Invoke block for specified target w/ an 'unknown' version
    def self.unknown_version(tgt, name)
      yield tgt, name, [:unknown] if block_given?
      [:unknown]
    end
  end

  # Helper module to be included in components
  # that contain lists of dependencies which include version information
  module VersionedDependencies

    # Return list of versions of dependencies of component.
    #
    # Requires module define 'deps' method which returns list
    # of gem names representing component dependencies. List
    # will be iterated over, versions will be looked up
    # recursively and returned
    def dependency_versions(args = {}, &bl)
      args = {:recursive => true, :dev_deps  => true}.merge(args)
      versions = {}
      deps.each do |dep|
        gem = Polisher::Gem.retrieve(dep.name)
        versions.merge!(gem.versions(args, &bl))
      end
      versions
    end

    # Return list of states which gem dependencies are in
    def dependency_states
      states = {}
      deps.each do |dep|
        gem = Polisher::Gem.new :name => dep.name
        states.merge! dep.name => gem.state(:check => dep)
      end
      states
    end
  end
end
