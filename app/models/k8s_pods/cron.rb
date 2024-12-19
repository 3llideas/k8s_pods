require "fugit"
require "open3"

module K8sPods
    class Cron < ApplicationRecord
        belongs_to :definition, class_name: 'K8sPods::Definition', foreign_key: 'definition_id'
        has_many :records, class_name: K8sPods.record_class, foreign_key: 'cron_id'
        belongs_to :last_record_exec, optional: true, class_name: K8sPods.record_class, inverse_of: :cron_exec
        belongs_to :owner, polymorphic: true, optional: true

        validate :correct_time_definition
        validate :only_rake_or_instance_method
        validate :check_args
        validate :rake_task_args
      
        validates :name, presence: true
        validates :minute, presence: true
        validates :hour, presence: true
        validates :day, presence: true
        validates :month, presence: true
        validates :week_day, presence: true

        scope :active, -> { where(active: true).order("day,hour,minute") }
      
        FREQUENCIES = ["dia", "hora", "cuarto_hora", "dia_5"]
        VALID_ARGUMENT_TYPES = ["String", "FalseClass", "TrueClass", "Integer", "Decimal", "Array", "Hash"]

        def task
          if self.record_task.to_s.empty?
            self.rake_task
          else
            self.record_task
          end
        end

        def call_rake(record)
            time = Time.now
            options = []
        
            options << "RAILS_ENV=#{Rails.env}"
            options << rake_task_arg1 unless rake_task_arg1.empty?
            options << rake_task_arg2 unless rake_task_arg2.empty?
            options << rake_task_arg3 unless rake_task_arg3.empty?
            options << rake_task_arg4 unless rake_task_arg4.empty?
            options << rake_task_arg5 unless rake_task_arg5.empty?
        
            log_folder = K8sPods.log_folder
            dir = ""
            
            if self.owner.present?
                owner_name = self.owner.k8s_pod_owner_name
                dir1 = "#{log_folder}/#{owner_name}"
                dir = "#{log_folder}/#{owner_name}/#{rake_task.parameterize}"
                Dir.mkdir(dir1) unless File.exist?(dir1)
                Dir.mkdir(dir) unless File.exist?(dir)
            else
                dir = "#{log_folder}/#{rake_task.parameterize}"
                Dir.mkdir(dir) unless File.exist?(dir)
            end

            stdout, stderr, status = Open3.capture3("bundle exec rake #{rake_task} #{options.join(" ")} >> #{dir}/#{Time.now.strftime("%Y%m%d%H%M")}.log")
        
            record.log = status.success? ? stdout.first(10000) : stderr.first(10000)
            record.time = Time.at(Time.now - time).utc.strftime("%H:%M:%S")
            record.status = status.success? ? "finalizada" : "erronea"
            record.save
        end

        def get_next_run
            ActiveSupport::TimeWithZone.new(fugit_cron.next_time.to_t, Time.zone)
        rescue
            nil
        end

        def fugit_cron
            Fugit.parse("#{minute} #{hour} #{day} #{month} #{week_day}")
        end
                
        def run_task(record = nil, execute_now = false, auto_executed = false)
          record = (record.class.to_s == K8sPods.record_class) ? record : records.new
          record.status = "en-cola"
          task = record_task.present? ? record_task : rake_task
          record.cron = self
          record.log ||= ""

          if last_record_exec.present? &&
              ["en-cola", "iniciada"].include?(last_record_exec.estado.try(:parameterize))
      
              record.status = "erronea"
              record.log += "\n La tarea sigue ejecutándose \n"
              record.save
              if Time.now > (last_record_exec.created_at + 0.5 * fugit_cron.rough_frequency)
                  record.log += "\n Tarea autodesbloqueada \n"
                  record.status = "en-cola"
                  record.save
                  last_record_exec.estado = "erronea"
                  last_record_exec.save
              else
              return
              end
          else
              record.save
              if auto_executed
                  update_columns(last_record_exec_id: record.id, last_exec: Time.now)
              end
          end
      
          arguments = []
          arguments << K8sPods::Cron.convert_to_data_type(arg1_type, arg1_value) unless arg1_type.empty?
          arguments << K8sPods::Cron.convert_to_data_type(arg2_type, arg2_value) unless arg2_type.empty?
          arguments << K8sPods::Cron.convert_to_data_type(arg3_type, arg3_value) unless arg3_type.empty?
          arguments << K8sPods::Cron.convert_to_data_type(arg4_type, arg4_value) unless arg4_type.empty?
          arguments << K8sPods::Cron.convert_to_data_type(arg5_type, arg5_value) unless arg5_type.empty?
      
          begin
              if !rake_task.to_s.empty?
                  if definition.present? && !Rails.env.development?
                      delayed_job = delay(queue: definition.queue_name, pod_cpu: pod_cpu, pod_memory: pod_memory, pod_namespace: pod_namespace, pod_image: pod_image).call_rake(record)
                      if execute_now
                          definition = K8sPods::Definition.find_by(queue_name: delayed_job.queue)
                          definition.deploy_and_run(delayed_job)
                      end
                  else
                    call_rake(record)
                  end
              elsif !record_task.to_s.empty?
                  if self.definition.present? && !Rails.env.development?
                      delayed_job = record.delay(queue: self.definition.queue_name, pod_cpu: pod_cpu, pod_memory: pod_memory, pod_namespace: pod_namespace, pod_image: pod_image).__send__(record_task, *arguments)
                      if execute_now
                          definition = K8sPods::Definition.find_by(queue_name: delayed_job.queue)
                          definition.deploy_and_run(delayed_job)
                      end
                  else
                    record.__send__(record_task, *arguments)
                  end
              end
          rescue Exception => e
              record.update_column(:log, "#{record.log}\n#{e.message}")
              return "#{I18n.t("k8s_pods.error.error_executing")} --> #{e.message}"
          end
          I18n.t("k8s_pods.flash.executing")
        end
        

        def self.check_and_run
            time_now = Time.now
            K8sPods::Cron.active.each do |cron|
                fugit_carga_cron = cron.fugit_cron
                next_time = ActiveSupport::TimeWithZone.new(fugit_carga_cron.next_time(time_now - 6.minute).to_t, Time.zone)
                frequency = fugit_carga_cron.rough_frequency
                next_time_frec = (cron.last_exec + frequency)
                # si ya paso el tiempo de ejecuccion y paso +- de la mitad de la frecuencia
                if time_now >= next_time and (time_now >= next_time_frec - frequency / 2)
                    cron.run_task(nil, nil, true)
                end
            end
        end
                
        def correct_time_definition
            if get_next_run.to_s.empty?
                errors.add(:hour, I18n.t("k8s_pods.error.review_time"))
            end
        end


        def self.convert_to_data_type(arg_type, arg_value)
            case arg_type
            when "FalseClass"
              false
            when "TrueClass"
              true
            when "String"
              arg_value.to_s
            when "Integer"
              arg_value.to_i
            when "Decimal"
              arg_value.to_d
            when "Array"
              (eval(arg_value).class == Array) ? eval(arg_value) : []
            when "Hash"
              (eval(arg_value).class == Hash) ? eval(arg_value) : {}
            end
        end

        private

        def check_args
          unless record_task.empty?
            if arg1_value.to_s.empty? || arg1_type.to_s.empty?
              errors.add(:arg1_value, I18n.t("k8s_pods.error.args")) if !arg1_value.to_s.empty? || !arg1_type.to_s.empty?
            end
            if arg2_value.to_s.empty? || arg2_type.to_s.empty?
              errors.add(:arg2_value, I18n.t("k8s_pods.error.args")) if !arg2_value.to_s.empty? || !arg2_type.to_s.empty?
            end
            if arg3_value.to_s.empty? || arg3_type.to_s.empty?
              errors.add(:arg3_value, I18n.t("k8s_pods.error.args")) if !arg3_value.to_s.empty? || !arg3_type.to_s.empty?
            end
            if arg4_value.to_s.empty? || arg4_type.to_s.empty?
              errors.add(:arg4_value, I18n.t("k8s_pods.error.args")) if !arg4_value.to_s.empty? || !arg4_type.to_s.empty?
            end
            if arg5_value.to_s.empty? || arg5_type.to_s.empty?
              errors.add(:arg5_value, I18n.t("k8s_pods.error.args")) if !arg5_value.to_s.empty? || !arg5_type.to_s.empty?
            end
          end
        end
      
        def rake_task_args
          unless rake_task.empty?
            unless rake_task_arg1.to_s.empty?
              errors.add(:rake_task_arg1, I18n.t("k8s_pods.error.rake_task_args")) if rake_task_arg1.split("=")[0].nil? || rake_task_arg1.split("=")[1].nil?
            end
            unless rake_task_arg2.to_s.empty?
              errors.add(:rake_task_arg2, I18n.t("k8s_pods.error.rake_task_args")) if rake_task_arg2.split("=")[0].nil? || rake_task_arg2.split("=")[1].nil?
            end
            unless rake_task_arg3.to_s.empty?
              errors.add(:rake_task_arg3, I18n.t("k8s_pods.error.rake_task_args")) if rake_task_arg3.split("=")[0].nil? || rake_task_arg3.split("=")[1].nil?
            end
            unless rake_task_arg4.to_s.empty?
              errors.add(:rake_task_arg4, I18n.t("k8s_pods.error.rake_task_args")) if rake_task_arg4.split("=")[0].nil? || rake_task_arg4.split("=")[1].nil?
            end
            unless rake_task_arg5.to_s.empty?
              errors.add(:rake_task_arg5, I18n.t("k8s_pods.error.rake_task_args")) if rake_task_arg5.split("=")[0].nil? || rake_task_arg5.split("=")[1].nil?
            end
          end
        end
      
        def correct_time_definition
          if get_next_run.to_s.empty?
            errors.add(:hour, I18n.t("k8s_pods.error.review_time"))
          end
        end
      
        def only_rake_or_instance_method
          if rake_task.to_s.empty? && record_task.to_s.empty?
            errors.add(:rake_task, I18n.t("k8s_pods.error.missing_task"))
          elsif !rake_task.to_s.empty? && !record_task.to_s.empty?
            errors.add(:rake_task, I18n.t("k8s_pods.error.double_task"))
          end
        end        
    end
end