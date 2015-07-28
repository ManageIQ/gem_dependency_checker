# Polisher gem2update cli util
#
# Licensed under the MIT license
# Copyright (C) 2015 Red Hat, Inc.
###########################################################

require 'optparse'

def gems2update_conf
  conf.merge!(default_conf)
      .merge!(targets_conf)
      .merge!(sources_conf)
end

def gems2update_parser
  OptionParser.new do |opts|
    default_options opts
    targets_options opts
    sources_options opts
  end
end

def check_missing(deps, alts)
  deps.each { |name, gdeps|
    versions = Polisher::Gem.remote_versions_for(name)
    matching = versions.select { |v| gdeps.all? { |dep| dep.match?(name, v)} }

    print "#{name} #{gdeps.collect { |dep| dep.requirement.to_s }}: ".blue.bold

    if matching.empty?
      puts "No matching upstream versions".red.bold

    else
      latest    = alts[name].max
      updatable = latest.nil? ? matching : matching.select { |m| m > latest }

      if updatable.empty?
        puts "No matching upstream version > #{latest} (downstream)".red.bold

      else
        puts "Update to #{updatable.max}".green.bold

      end

    end
  }
end

def check_gems2update(source)
  deps = {}
  alts = {}

  # TODO optimize speed
  source.dependency_tree(:recursive => true,
                         :dev_deps  => conf[:devel_deps]) do |source, dep, resolved_dep|
    name     = dep.name
    versions = Polisher::VersionChecker.matching_versions(dep)
    missing_downstream    = versions.empty?
    other_version_missing = deps.key?(name)

    if missing_downstream || other_version_missing
      deps[name] ||= []
      has_dep = other_version_missing && deps[name].any? { |gdep| gdep == dep }
      deps[name] << dep unless has_dep

      alts[name] = Polisher::VersionChecker.versions_for(name).values.flatten unless alts.key?(name)
    end

  end

  check_missing(deps, alts)
end

def check_gems(conf)
  check_gems2update(conf_source) if conf_gem? || conf_gemfile?
end
