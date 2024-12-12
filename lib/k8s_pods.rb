require "k8s_pods/version"
require "k8s_pods/engine"

module K8sPods

  mattr_accessor :environment_variables
  @@environment_variables = []

  mattr_accessor :aws_access_key
  @@aws_access_key = ""

  mattr_accessor :aws_secret_key
  @@aws_secret_key = ""

  mattr_accessor :aws_region
  @@aws_region = ""

  mattr_accessor :aws_cluster_name
  @@aws_cluster_name = ""

  mattr_accessor :aws_cluster_url
  @@aws_cluster_url = ""

  mattr_accessor :namespace
  @@namespace = ""

  mattr_accessor :config_map_name
  @@config_map_name = ""

  mattr_accessor :secret_map_name
  @@secret_map_name = ""

  mattr_accessor :instance_models
  @@instance_models = []
  
  def self.setup
    yield self
  end
end
