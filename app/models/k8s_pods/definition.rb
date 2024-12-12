module K8sPods
  class Definition < ApplicationRecord
    has_many :crons, class_name: 'K8sPods::Cron', foreign_key: 'cron_id'

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
      
    # def self.config_map_name
    #   "k8s-stoamsaas-#{ENV["APP_NAME"]}-#{ENV["APP_ECR_TAG"]}-envapp"
    # end

    # def self.secrets_name
    #   "k8s-stoamsaas-#{ENV["APP_NAME"]}-#{ENV["APP_ECR_TAG"]}-env-var-secret"
    # end

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
        cron = job.payload_object.object.cron
        job_name = "#{cron.history_task}#{cron.s3_data_transfer_task}#{cron.rake_task}"
        name = "#{ENV["APP_NAME"]}-#{ENV["APP_ECR_TAG"]}-#{queue_name}-#{job.id}-#{job_name}".gsub(/[^0-9A-Za-z-]/, "-").gsub("--", "-").truncate(62, omission: "") + "0"
        yaml["metadata"]["name"] = name
        yaml["spec"]["containers"][0]["name"] = name
        yaml["spec"]["containers"][0]["args"][0] = yaml["spec"]["containers"][0]["args"][0].gsub("%job_id%", job.id.to_s)
        yaml["spec"]["containers"][0]["envFrom"][0]["configMapRef"]["name"] = K8sPods.config_map_name

        yaml["spec"]["containers"][0]["env"].each_with_index do |variable, index|
          next unless yaml["spec"]["containers"][0]["env"][index]["valueFrom"].present? && yaml["spec"]["containers"][0]["env"][index]["valueFrom"]["secretKeyRef"]
          yaml["spec"]["containers"][0]["env"][index]["valueFrom"]["secretKeyRef"]["name"] = K8sPods.secrets_name
        end

        yaml["metadata"]["namespace"] = if job.pod_namespace.to_s.empty?
          pod_namespace
        else
          job.pod_namespace
        end
        yaml["metadata"]["labels"] = {} if yaml["metadata"]["labels"].nil?
        yaml["metadata"]["labels"]["app_name"] = ENV["APP_NAME"]
        yaml["metadata"]["labels"]["ecr_tag"] = ENV["APP_ECR_TAG"]

        yaml["spec"]["containers"][0]["image"] = if job.pod_image.to_s.empty?
          pod_image.to_s.empty? ? "#{ENV["APP_ECR_URL"]}:#{ENV["APP_ECR_TAG"]}" : pod_image
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
        byebug
        # service = Kubeclient::Resource.new(yaml)

        # client.create_pod(service)
      rescue => e
        return e.message
      end
      I18n.t(".execute-now-ok")
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
      K8sPods.environment_variables.each{|env| yaml_secrets[:data][env] = ENV[env]}

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
      k8spod.pod_yaml = <<~EOS
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
              args: ['RAILS_ENV=production bundle exec rake k8s:execute_delayed[%job_id%]']
              resources:
                  requests:
                    cpu: '100m'
                    memory: '128Mi'
              volumeMounts:
                - name: sharedstoamsaas
                  mountPath: /efs-stoam
                  readOnly: false
                - name: kube-api-access-vwd29
                  readOnly: true
                  mountPath: /var/run/secrets/kubernetes.io/serviceaccount
              envFrom:
                - configMapRef:
                    name: k8s-stoamsaas-app-envapp
              env:
                - name: CURRENTLY_IN_A_POD
                  value: 'true'
                - name: APP_AWS_K_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_AWS_K_ACCESS_KEY
                - name: APP_AWS_K_SECRET_KEY
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_AWS_K_SECRET_KEY
                - name: APP_EMAIL_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_EMAIL_PASSWORD
                - name: APP_EMAIL_USERNAME
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_EMAIL_USERNAME
                - name: APP_GOOGLE_API_KEY
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_GOOGLE_API_KEY
                - name: APP_RECAPTCHA_KEY
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_RECAPTCHA_KEY
                - name: APP_RECAPTCHA_SECRET
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_RECAPTCHA_SECRET
                - name: APP_SECRET_KEY_BASE
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_SECRET_KEY_BASE
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: DATABASE_URL
                - name: ESB_PROJECT_NAME
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: ESB_PROJECT_NAME
                - name: ESB_STREAM2_NAME
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: ESB_STREAM2_NAME
                - name: ESB_BUCKET_SHARED
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: ESB_BUCKET_SHARED
                - name: ESB_BUCKET_PREFIX
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: ESB_BUCKET_PREFIX
                - name: ESB_COMMON_FILE_NAME
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: ESB_COMMON_FILE_NAME
                - name: APP_AWS_REGION
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: APP_AWS_REGION
                - name: STOAM_MASTER_KEY
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: STOAM_MASTER_KEY
                - name: LOCKBOX_MASTER_KEY
                  valueFrom:
                    secretKeyRef:
                      name: k8s-stoamsaas-app-env-var-secret
                      key: LOCKBOX_MASTER_KEY
                - name: STOAM_BC_EXTENSION_NAME
                valueFrom:
                  secretKeyRef:
                    name: k8s-stoamsaas-app-env-var-secret
                    key: STOAM_BC_EXTENSION_NAME
                - name: STRIPE_PUBLISHABLE_KEY
                valueFrom:
                  secretKeyRef:
                    name: k8s-stoamsaas-app-env-var-secret
                    key: STRIPE_PUBLISHABLE_KEY
                - name: STRIPE_SECRET_KEY
                valueFrom:
                  secretKeyRef:
                    name: k8s-stoamsaas-app-env-var-secret
                    key: STRIPE_SECRET_KEY
                - name: BASECAMP_URL
                valueFrom:
                  secretKeyRef:
                    name: k8s-stoamsaas-app-env-var-secret
                    key: BASECAMP_URL
          restartPolicy: Never
          volumes:
            - name: sharedstoamsaas
              persistentVolumeClaim:
                claimName: pvcsharedstoamsaas
            - name: kube-api-access-vwd29
              readOnly: true
              mountPath: /var/run/secrets/kubernetes.io/serviceaccount"
      EOS

      k8spod.save

      k8spod
    end
  end
end
