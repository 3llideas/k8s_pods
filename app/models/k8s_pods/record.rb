module K8sPods
    class Record < ApplicationRecord
        belongs_to :cron, class_name: "K8sPods::Cron", foreign_key: 'cron_id'
        has_one :cron_exec, class_name: "K8sPods::Cron", inverse_of: :last_record_exec

        scope :cronified, -> { where.not(cron_id: nil) }

        def get_cron_and_execute(task, params)
            cron = K8sPods::Cron.where(record_task: task, active: false).destroy_all
            pod = K8sPods::Definition.find_by(queue_name: "k8s-pod")
            if pod.present?
              cron = K8sPods::Cron.create(name: "Auto-generated: #{task}",
                autogenerate: true,
                minute: "0",
                hour: "0",
                day: "1",
                month: "1",
                week_day: "*",
                record_task: task,
                active: false,
                arg1_type: (params.is_a?(Array) && !params[0].nil?) ? params[0].class : "",
                arg1_value: (params.is_a?(Array) && !params[0].nil?) ? params[0] : "",
                arg2_type: (params.is_a?(Array) && !params[1].nil?) ? params[1].class : "",
                arg2_value: (params.is_a?(Array) && !params[1].nil?) ? params[1] : "",
                arg3_type: (params.is_a?(Array) && !params[2].nil?) ? params[2].class : "",
                arg3_value: (params.is_a?(Array) && !params[2].nil?) ? params[2] : "",
                arg4_type: (params.is_a?(Array) && !params[3].nil?) ? params[3].class : "",
                arg4_value: (params.is_a?(Array) && !params[3].nil?) ? params[3] : "",
                arg5_type: (params.is_a?(Array) && !params[4].nil?) ? params[4].class : "",
                arg5_value: (params.is_a?(Array) && !params[4].nil?) ? params[4] : "",
                definition: pod)
              cron.run_task(self, true)
            else
              self.log ||= ""
              self.log += I18n.t("k8s_pods.error.k8s_not_found")
              save
            end
        end   
        
        def self.pod_methods
          K8sPods::Record.instance_methods - (K8sPods::Record.ancestors - [K8sPods::Record]).map(&:instance_methods).flatten - [:get_cron_and_execute,:autosave_associated_records_for_cron_exec,:autosave_associated_records_for_owner,:autosave_associated_records_for_cron]
        end
    end
end