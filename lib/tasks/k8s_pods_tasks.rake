namespace :k8s_pods do
    desc "Generate PODs and execute delayed jobs"
    task delayed_to_pod: :environment do
      # K8sDelayedPod.clean_succeeded
      K8sDelayedPod.active.each do |k8s_delayed_pod|
        delayed_jobs = Delayed::Job.where(locked_at: nil, locked_by: nil, queue: k8s_delayed_pod.queue_name, last_error: nil)
        delayed_jobs.each do |job|
          if defined?(StoamSaas)
            tenant = job.try(:tenant)
            return unless tenant.present?
            Apartment::Tenant.switch(tenant) do
              k8s_delayed_pod.deploy_and_run(job)
            end
          else
            k8s_delayed_pod.deploy_and_run(job)
          end
        end
      end
      # temporalmente podemos ejecuar aqui la limpieza
      # pero lo ideal seria lanzar la tarea remove_succeeded_k8s_pods
      # para poder controlar cada cuanto se lanza
      K8sDelayedPod.clean_succeeded
    end
  
    task :execute_delayed, [:delayed_job_id] => :environment do |t, args|
      job = Delayed::Job.find(args[:delayed_job_id])
  
      return unless job.present?
  
      if defined?(StoamSaas)
        tenant = job.try(:tenant)
        return unless tenant.present?
  
        Apartment::Tenant.switch(tenant) do
          # We need run the job through a worker to get job deleted on success
          worker = Delayed::Worker.new
          worker.run(job)
        end
      else
        worker = Delayed::Worker.new
        worker.run(job)
      end
    end
  
    desc "Remove Succeeded K8S pods"
    task remove_succeeded_k8s_pods: :environment do
      K8sDelayedPod.clean_succeeded
    end
  end
  