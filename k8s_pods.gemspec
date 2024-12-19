require_relative "lib/k8s_pods/version"

Gem::Specification.new do |spec|
  spec.name        = "k8s_pods"
  spec.version     = K8sPods::VERSION
  spec.authors     = [ "3LLIDEAS" ]
  spec.email       = [ "alaliena@3llideas.com" ]
  spec.homepage    = "https://3llideas.com"
  spec.summary     = "K8S delayed pods"
  spec.description = "Allow to manage pods definition, create pods and run delayed jobs on them "
  spec.license     = "MIT 2024 - 3LLIDEAS"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/3llideas/k8s_pods"
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 6.1.4"
  spec.add_dependency "delayed_job", "~> 4.1.9"
  spec.add_dependency "kubeclient", ">= 4.9.3"
  spec.add_dependency "aws-sdk-core"
  spec.add_dependency "fugit"

  spec.add_dependency "mutex_m"
  spec.add_dependency "bigdecimal"

  spec.add_development_dependency "sqlite3"
end
