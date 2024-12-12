K8sPods.setup do |config|

    # A list of environment variables that will be available in the config_map, secret_map and pod
    # Those will be available in the pod as ENV['VARIABLE_NAME']
    # config.environment_variables = [
    #     "VARIABLE_1_NAME", 
    #     "VARIABLE_2_NAME"
    # ]
    config.environment_variables = [

    ]

    # AWS configuration
    config.aws_access_key = ENV['AWS_ACCESS_KEY']
    config.aws_secret_key = ENV['AWS_SECRET_KEY']
    config.aws_region = ENV['AWS_REGION']
    config.aws_cluster_name = ENV['AWS_CLUSTER_NAME']
    config.aws_cluster_url = ENV['AWS_CLUSTER_URL']

    # Kubernetes configuration
    config.namespace = "default"
    config.config_map_name = "k8s-pods-config-#{Rails.env}"
    config.secret_map_name = "k8s-pods-secret-#{Rails.env}"

    # List of models which instance methods will be invoked in the pod
    config.instance_models = []

end