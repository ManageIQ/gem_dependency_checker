# RPM Spec Parser Mixin
#
# Licensed under the MIT license
# Copyright (C) 2013-2014 Red Hat, Inc.

require 'polisher/rpm/macros'

module Polisher
  module RPM
    module SpecParser
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def default_metadata
          {:contents          => "",
           :requires          => [],
           :build_requires    => [],
           :pkg_excludes      => {},
           :pkg_files         => {},
           :changelog         => "",
           :changelog_entries => []}
        end

        # Parse the specified rpm spec and return new RPM::Spec instance from metadata
        #
        # @see [Polisher::RPM::SpecConstants::METADATA_IDS]
        # @param [String] string contents of spec to parse
        # @return [Polisher::RPM::Spec] spec instantiated from rpmspec metadata
        def parse(spec)
          in_subpackage = false
          in_changelog  = false
          in_files      = false
          subpkg_name   = nil
          meta          = default_metadata.merge(:contents => spec)
          macros        = {}
          spec.each_line do |l|
            if l =~ RPM::Spec::COMMENT_MATCHER

            elsif Macro.specifier?(l)
              macro = Macro.parse l
              macros[macro.label] = macro
              meta[:gem_name] = macro.value if macro.label == "gem_name"

            elsif l =~ RPM::Spec::SPEC_NAME_MATCHER
              meta[:name]      = $1.strip
              meta[:gem_name]  = $1.strip if l =~ RPM::Spec::SPEC_PREFIXED_NAME_MATCHER &&
                                             $1.strip != "%{gem_name}"
              meta[:full_name] = String.new(meta[:name])
              meta[:full_name] = Macro.replace_all(meta[:full_name], macros) if Macro.included_in?(meta[:full_name])

            elsif l =~ RPM::Spec::SPEC_VERSION_MATCHER
              meta[:version]      = $1.strip
              meta[:full_version] = String.new(meta[:version])
              meta[:full_version] = Macro.replace_all(meta[:version], macros) if Macro.included_in?(meta[:version])

            elsif l =~ RPM::Spec::SPEC_RELEASE_MATCHER
              meta[:release] = $1.strip

            elsif l =~ RPM::Spec::SPEC_SUBPACKAGE_MATCHER
              subpkg_name = $1.strip
              in_subpackage = true

            elsif l =~ RPM::Spec::SPEC_REQUIRES_MATCHER && !in_subpackage
              meta[:requires] << RPM::Requirement.parse($1.strip)

            elsif l =~ RPM::Spec::SPEC_BUILD_REQUIRES_MATCHER && !in_subpackage
              meta[:build_requires] << RPM::Requirement.parse($1.strip)

            elsif l =~ RPM::Spec::SPEC_CHANGELOG_MATCHER
              in_changelog = true

            elsif l =~ RPM::Spec::SPEC_FILES_MATCHER
              subpkg_name = nil
              in_files = true

            elsif l =~ RPM::Spec::SPEC_SUBPKG_FILES_MATCHER
              subpkg_name = $1.strip
              in_files = true

            elsif l =~ RPM::Spec::SPEC_CHECK_MATCHER
              meta[:has_check] = true

            elsif in_changelog
              meta[:changelog] << l

            elsif in_files
              tgt = subpkg_name.nil? ? meta[:full_name] : subpkg_name

              if l =~ RPM::Spec::SPEC_EXCLUDED_FILE_MATCHER
                sl = Regexp.last_match(1)
                meta[:pkg_excludes][tgt] ||= []
                meta[:pkg_excludes][tgt] << sl unless sl.blank?

              else
                sl = l.strip
                meta[:pkg_files][tgt] ||= []
                meta[:pkg_files][tgt] << sl unless sl.blank?

              end
            end
          end

          # Ensure pkg_files hash exists
          meta[:changelog_entries] = meta[:changelog].split("\n\n") if meta[:changelog]
          meta[:changelog_entries].collect! { |c| c.strip }.compact!

          new :metadata => meta,
              :macros   => macros
        end
      end # module ClassMethods
    end # module SpecParser
  end # module RPM
end # module Polisher
