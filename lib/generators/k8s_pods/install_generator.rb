# frozen_string_literal: true

require 'rails/generators/base'
require 'securerandom'

module K8sPods
  module Generators
    MissingORMError = Class.new(Thor::Error)

    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("../../templates", __FILE__)

      desc "Creates a K8sPods initializer and copy locale files to your application."
      class_option :orm, required: true

      def copy_initializer
        unless options[:orm]
          raise MissingORMError, <<-ERROR.strip_heredoc
          An ORM must be set to install K8sPod in your application.
          ERROR
        end

        template "k8s_pods.rb", "config/initializers/k8s_pods.rb"
      end

    end
  end
end