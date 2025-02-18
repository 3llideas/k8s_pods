module K8sPods
  class Definition < ApplicationRecord
    has_many :crons, class_name: 'K8sPods::Cron', foreign_key: 'cron_id'
    validates :queue_name, presence: true, uniqueness: true
    scope :active, -> { where(active: true) }

     # The name should be equal as the returned by the method config_map_name
    CONFIG_MAP = "
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: \"#{K8sPods.config_map_name}\"
      namespace: \"#{K8sPods.namespace}\"
    data:"

    # The name should be equal as the returned by the method secrets_name
    SECRET = "
      apiVersion: v1
      kind: Secret
      metadata:
        name: \"#{K8sPods.secret_map_name}\"
        namespace: \"#{K8sPods.namespace}\"
        labels:
      type: Opaque
      data:"
      
    def self.clean_succeeded
      client = K8sPods::Definition.get_client
      all_entities = client.all_entities(namespace: K8sPods.namespace)
      all_entities["pod"].each do |entity|
        if entity.metadata.labels.app_name == ENV["APP_NAME"] && entity.metadata.labels.ecr_tag == ENV["APP_ECR_TAG"] && entity.status.phase == "Succeeded"
          client.delete_pod(entity.metadata.name, K8sPods.namespace)
        end
      end
    end

    def deploy_and_run(job)
      begin
        K8sPods::Definition.create_and_update_config_map?(true)
        client = K8sPods::Definition.get_client
        yaml = YAML.safe_load(pod_yaml)
        cron = job.payload_object.object.class.to_s == "K8sPods::Cron" ? job.payload_object.object : job.payload_object.object.cron
        job_name = "#{cron.name}"
        name = "#{K8sPods.k8s_app_name}-#{K8sPods.ecr_tag}-#{queue_name}-#{job.id}-#{job_name}".gsub(/[^0-9A-Za-z-]/, "-").downcase.gsub("--", "-").truncate(62, omission: "") + "0"
        yaml["metadata"]["name"] = name
        yaml["spec"]["containers"][0]["name"] = name
        yaml["spec"]["containers"][0]["args"][0] = yaml["spec"]["containers"][0]["args"][0].gsub("%job_id%", job.id.to_s)
        yaml["spec"]["containers"][0]["envFrom"][0]["configMapRef"]["name"] = K8sPods.config_map_name

        yaml["spec"]["containers"][0]["env"].each_with_index do |variable, index|
          next unless yaml["spec"]["containers"][0]["env"][index]["valueFrom"].present? && yaml["spec"]["containers"][0]["env"][index]["valueFrom"]["secretKeyRef"]
          yaml["spec"]["containers"][0]["env"][index]["valueFrom"]["secretKeyRef"]["name"] = K8sPods.secret_map_name
        end

        yaml["metadata"]["namespace"] = if job.pod_namespace.to_s.empty?
          pod_namespace
        else
          job.pod_namespace
        end

        yaml["metadata"]["labels"] = {} if yaml["metadata"]["labels"].nil?
        K8sPods.labels.each do |key, value|
          yaml["metadata"]["labels"][key] = value
        end

        yaml["spec"]["containers"][0]["image"] = if job.pod_image.to_s.empty?
          pod_image.to_s.empty? ? "#{K8sPods.ecr_url}:#{K8sPods.ecr_tag}" : pod_image
        else
          job.pod_image
        end

        yaml["spec"]["containers"][0]["resources"]["requests"]["cpu"] = if job.pod_cpu.to_s.empty?
          pod_cpu
        else
          job.pod_cpu
        end

        yaml["spec"]["containers"][0]["resources"]["requests"]["memory"] = if job.pod_memory.to_s.empty?
          pod_memory
        else
          job.pod_memory
        end

        service = Kubeclient::Resource.new(yaml)

        client.create_pod(service)
      rescue => e
        yaml = YAML.load(job.handler)
        if yaml.present? && yaml.class == Delayed::PerformableMethod && yaml.object.class.to_s == K8sPods.record_class
          record = yaml.object
          record.update_column(:status, "erronea")
          record.update_column(:log, e.message) 
        elsif job.payload_object.args[0].class.to_s == K8sPods.record_class
          record = job.payload_object.args[0]
          record.update_column(:status, "erronea")
          record.update_column(:log, e.message)
        end   
        return e.message
      end
      I18n.t("k8s_pods.flash.execute-now-ok")
    end

    def self.get_client
      require 'aws-sdk-core'
      require 'kubeclient'

      credentials = Aws::Credentials.new(K8sPods.aws_access_key, K8sPods.aws_secret_key)
      auth_options = {
        bearer_token: Kubeclient::AmazonEksCredentials.token(credentials, K8sPods.aws_cluster_name)
      }
      # ssl_options must be declared empty to work
      Kubeclient::Client.new(
        K8sPods.aws_cluster_url, "v1", auth_options: auth_options, ssl_options: {}
      )
    end

    def self.create_and_update_config_map?(force_update)
      client = K8sPods::Definition.get_client
      yaml_config_map = YAML.safe_load(K8sPods::Definition::CONFIG_MAP).deep_symbolize_keys

      yaml_config_map[:data] = {}
      K8sPods.environment_variables.each{|env| yaml_config_map[:data][env] = ENV[env]}

      begin
        config_map = client.get_config_map(yaml_config_map[:metadata][:name], yaml_config_map[:metadata][:namespace])
        config_map = client.update_config_map(yaml_config_map) if force_update
        puts "Config_map #{yaml_config_map[:metadata][:name]} updated"
      rescue Kubeclient::ResourceNotFoundError => e
        config_map = client.create_config_map(yaml_config_map)
        puts "Config_map #{yaml_config_map[:metadata][:name]} created"
      rescue Exception => e
        puts "Error: #{e.message}"
        return false
      end

      yaml_secrets = YAML.safe_load(K8sPods::Definition::SECRET).deep_symbolize_keys
      yaml_secrets[:data] = {}
      K8sPods.environment_variables.each{|env| yaml_secrets[:data][env] = Base64.strict_encode64(ENV[env].to_s)}

      begin
        secret = client.get_secret(yaml_secrets[:metadata][:name], yaml_secrets[:metadata][:namespace])
        secret = client.update_secret(yaml_secrets) if force_update
        puts "Secret #{yaml_secrets[:metadata][:name]} updated"
      rescue Kubeclient::HttpError => e
        secret = client.create_secret(yaml_secrets)
        puts "Secret #{yaml_secrets[:metadata][:name]} created"
      rescue Exception => e
        puts "Error: #{e.message}"
        return false
      end

      true
    end

    def self.create_default_k8s_pod
      k8spod = K8sPods::Definition.find_or_initialize_by(queue_name: "k8s-pod")

      k8spod.active = true
      k8spod.queue_name = "k8s-pod"
      k8spod.pod_namespace = K8sPods.namespace
      k8spod.pod_image = ""
      k8spod.pod_cpu = "100m"
      k8spod.pod_memory = "128Mi"
      yaml = <<~EOS
        apiVersion: v1
        kind: Pod
        metadata:
          name: job-name
          namespace: '%pod_namespace%'
          annotations:
              karpenter.sh/do-not-disrupt: 'true'
          labels:
            app_name: ''
            ecr_tag: ''
        spec:
          containers:
            - name: job-name
              image: '%pod_image%'
              imagePullPolicy: Always
              command: ['/bin/bash', '-l', '-c']
              args: ['RAILS_ENV=production bundle exec rake k8s_pods:execute_delayed[%job_id%]']
              resources:
                  requests:
                    cpu: '100m'
                    memory: '128Mi'
              volumeMounts:
                - name: kube-api-access-vwd29
                  readOnly: true
                  mountPath: /var/run/secrets/kubernetes.io/serviceaccount
              envFrom:
                - configMapRef:
                    name: #{K8sPods.config_map_name}
              env:
                - name: CURRENTLY_IN_A_POD
                  value: 'true'
          restartPolicy: Never
          volumes:
            - name: kube-api-access-vwd29
              readOnly: true
              mountPath: /var/run/secrets/kubernetes.io/serviceaccount
      EOS


      yaml_pod = YAML.safe_load(yaml)

      K8sPods.environment_variables.each do |env| 
       hash_env = {
        "name": env,
        "valueFrom":{
          "secretKeyRef":{
            "name": K8sPods.secret_map_name,
            "key": env
            }
          }
        }.deep_stringify_keys
        yaml_pod["spec"]["containers"][0]["env"] << hash_env
      end

      k8spod.pod_yaml = yaml_pod.to_yaml
      k8spod.save
      k8spod
    end
  end
end
