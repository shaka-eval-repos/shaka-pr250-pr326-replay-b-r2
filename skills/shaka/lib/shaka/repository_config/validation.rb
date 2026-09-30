# frozen_string_literal: true

require 'pathname'
require_relative '../error'

module Shaka
  class RepositoryConfig
    # Shared primitive validators for repository policy sections.
    module Validation
      private

      def positive_integer!(value, label)
        return if value.is_a?(Integer) && value.positive?

        raise Error, "#{label} must be a positive integer"
      end

      def string!(value, label)
        raise Error, "#{label} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?

        value
      end

      def prompt_path!(value, label)
        path = string!(value, label)
        inside = !Pathname.new(path).absolute? && !path.split('/').include?('..')
        raise Error, "#{label} must be a path inside the repository" unless inside
      end

      def mapping!(value, label)
        raise Error, "#{label} must be a mapping" unless value.is_a?(Hash) && value.keys.all?(String)

        value
      end

      def keys!(mapping, required, optional, label)
        unknown = mapping.keys - required - optional
        missing = required - mapping.keys
        raise Error, "unknown #{label} key: #{unknown.first}" unless unknown.empty?
        raise Error, "missing #{label} key: #{missing.first}" unless missing.empty?
      end

      def name_list!(names, label, noun)
        raise Error, "#{label} must be a list of #{noun}" unless names.is_a?(Array)
        raise Error, "#{label} must not be empty" if names.empty?

        names.each_with_index { |name, index| string!(name, "#{label}[#{index}]") }
        repeated = names.map(&:downcase).tally.find { |_, count| count > 1 }
        raise Error, "#{label} repeats #{repeated.first}" if repeated
      end

      def enum!(value, allowed, message)
        raise Error, message unless allowed.include?(value)
      end

      def file!(value, label)
        path = repository_path(value, label)
        raise Error, "#{label} does not exist: #{value}" unless File.file?(path)

        real_path = File.realpath(path)
        raise Error, "#{label} must resolve inside the repository" unless real_path.start_with?("#{@root}/")

        path
      end

      def executable!(value, label)
        path = file!(value, label)
        raise Error, "#{label} is not executable: #{value}" unless File.executable?(path)
      end

      def repository_path(value, label)
        relative = string!(value, label)
        expanded = File.expand_path(relative, @root)
        inside = !Pathname.new(relative).absolute? && expanded.start_with?("#{@root}/")
        raise Error, "#{label} must stay inside the repository" unless inside

        expanded
      end
    end
  end
end
