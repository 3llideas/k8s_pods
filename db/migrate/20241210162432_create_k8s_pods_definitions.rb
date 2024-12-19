class CreateK8sPodsDefinitions < ActiveRecord::Migration[6.1]
  def change
    create_table :k8s_pods_definitions do |t|
      t.boolean :active, default: true
      t.string :queue_name, default: "k8s-pod", unique: true
      t.string :pod_namespace, default: "pod_namespace"
      t.string :pod_image, default: "pod_image"
      t.string :pod_cpu, default: "100m"
      t.string :pod_memory, default: "128Mi"
      t.text :pod_yaml, default:"apiVersion: v1\nkind: Pod\nmetadata:\n  name: job-name\n  namespace: '%pod_namespace%'\nspec:\n  containers:\n    - name: job-name\n      image: '%pod_image%'\n      imagePullPolicy: Always\n      command: ['/bin/bash', '-l', '-c']\n      args: ['RAILS_ENV=production bundle exec rake k8s:execute_delayed[%job_id%]']\n      resources:\n         requests:\n            cpu: '%pod_cpu%'\n            memory: '%pod_memory%'\n      volumeMounts:\n        - name: myshared\n          mountPath: /efs\n          readOnly: false\n        - name: kube-api-access-vwd29\n          readOnly: true\n          mountPath: /var/run/secrets/kubernetes.io/serviceaccount\n      envFrom:\n        - configMapRef:\n            name:\n      env:\n        - name: APP_AWS_K_ACCESS_KEY\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_AWS_K_ACCESS_KEY\n        - name: APP_AWS_K_SECRET_KEY\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_AWS_K_SECRET_KEY\n        - name: APP_EMAIL_PASSWORD\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_EMAIL_PASSWORD\n        - name: APP_EMAIL_USERNAME\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_EMAIL_USERNAME\n        - name: APP_GOOGLE_API_KEY\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_GOOGLE_API_KEY\n        - name: APP_RECAPTCHA_KEY\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_RECAPTCHA_KEY\n        - name: APP_RECAPTCHA_SECRET\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_RECAPTCHA_SECRET\n        - name: APP_SECRET_KEY_BASE\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: APP_SECRET_KEY_BASE\n        - name: DATABASE_URL\n          valueFrom:\n            secretKeyRef:\n              name: app-env-var-secret\n              key: DATABASE_URL\n  restartPolicy: Never\n  volumes:\n    - name: sharedvolume\n      persistentVolumeClaim:\n        claimName: sharedstoam\n    - name: kube-api-access-vwd29\n      readOnly: true\n      mountPath: /var/run/secrets/kubernetes.io/serviceaccount"
      t.timestamps
    end

    create_table :k8s_pods_crons do |t|
      t.string :name, null: false

      t.references :owner, polymorphic: true
      t.references :definition
      t.references :last_record_exec

      t.string :minute, default: "*"
      t.string :hour, default: "*"
      t.string :day, default: "*"
      t.string :month, default: "*"
      t.string :week_day, default: "*"
      t.boolean :active, default: true

      t.string :pod_namespace, default: ""
      t.string :pod_image, default: ""
      t.string :pod_cpu, default: ""
      t.string :pod_memory, default: ""

      t.string :rake_task, default: ""
      t.string :record_task, default: ""

      t.string :rake_task_arg1, default: ""
      t.string :rake_task_arg2, default: ""
      t.string :rake_task_arg3, default: ""
      t.string :rake_task_arg4, default: ""
      t.string :rake_task_arg5, default: ""

      t.string :arg1_value, default: ""
      t.string :arg2_value, default: ""
      t.string :arg3_value, default: ""
      t.string :arg4_value, default: ""
      t.string :arg5_value, default: ""

      t.string :arg1_type, default: ""
      t.string :arg2_type, default: ""
      t.string :arg3_type, default: ""
      t.string :arg4_type, default: ""
      t.string :arg5_type, default: ""      

      t.string :frequency, default: ""
      t.boolean :autogenerate, default: false
      t.datetime :last_exec, default: -> { "CURRENT_TIMESTAMP" }, null: false

      t.timestamps
    end

    create_table :k8s_pods_records do |t|
      t.references :cron
      t.string :status
      t.text :log
      t.string :time
      t.timestamps
    end

    add_column :delayed_jobs, :pod_namespace, :string, null: true
    add_column :delayed_jobs, :pod_image, :string, null: true
    add_column :delayed_jobs, :pod_cpu, :string, null: true
    add_column :delayed_jobs, :pod_memory, :string, null: true
    
  end
end
