# Polisher Config Helper Mixin
#
# Licensed under the MIT license
# Copyright (C) 2013-2014 Red Hat, Inc.

module ConfHelpers
  module ClassMethods
    attr_reader :conf_attrs

    def conf_attrs?
      conf_attrs.is_a?(Array)
    end

    # Defines a 'config attribute' or attribute on the class
    # which this is defined in. Accessors to the single shared
    # attribute will be added to the class as well as instances
    # of the class. Specify the default value with the attr name
    # or via an env variable
    #
    # @example
    #   class Custom
    #     extend ConfHelpers
    #     conf_attr :data_dir, :default => '/etc/'
    #   end
    #   Custom.data_dir # => '/etc/'
    #   ENV['POLISHER_DATA_DIR'] = '/usr/'
    #   Custom.data_dir # => '/usr/'
    #   Custom.data_dir == Custom.new.data_dir # => true
    #
    def conf_attr(name, opts = {})
      @conf_attrs ||= []
      @conf_attrs  << name
      default    = opts[:default]
      accumulate = opts[:accumulate]

      send(:define_singleton_method, name) do |*args|
        nvar = "@#{name}".intern
        current = instance_variable_get(nvar)
        envk    = "POLISHER_#{name.to_s.upcase}"
        if accumulate
          instance_variable_set(nvar, []) unless current
          current  = instance_variable_get(nvar)
          current << default
          current << ENV[envk]
          current += args

          current.uniq!
          current.compact!
          current.flatten!
          instance_variable_set(nvar, current)

        else
          instance_variable_set(nvar, default)    unless current
          instance_variable_set(nvar, ENV[envk])  if ENV.key?(envk)
          instance_variable_set(nvar, args.first) unless args.empty?
        end
        instance_variable_get(nvar)
      end

      send(:define_method, name) do
        self.class.send(name)
      end
    end

    def cmd_available?(cmd)
      File.exist?(cmd) && File.executable?(cmd)
    end

    def require_cmd!(cmd)
      raise "command #{cmd} not available" unless cmd_available?(cmd)
    end

    def require_dep!(dep, obj=nil)
      require dep
    rescue LoadError => e
      m  = e.backtrace[obj.nil? ? 3 : 4].split.last
      ms = obj.nil? ? m : "#{obj.class} #{m}"
      raise "dependency #{dep} is not available - cannot invoke #{ms}"
    end
  end # module ClassMethods

  def self.included(base)
    base.extend(ClassMethods)
  end

  def require_cmd!(cmd)
    self.class.require_cmd!(cmd)
  end

  def require_dep!(dep)
    self.class.require_dep!(dep, self)
  end
end
