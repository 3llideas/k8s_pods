namespace :k8s_pods do
    desc "Generate PODs and execute delayed jobs"
    task delayed_to_pod: :environment do
      # K8sDelayedPod.clean_succeeded
      K8sPods::Definition.active.each do |definition|
        delayed_jobs = Delayed::Job.where(locked_at: nil, locked_by: nil, queue: definition.queue_name, last_error: nil)
        delayed_jobs.each do |job|
          definition.deploy_and_run(job)
        end
      end
      K8sPods::Definition.clean_succeeded
    end
  
    task :execute_delayed, [:delayed_job_id] => :environment do |t, args|
      job = Delayed::Job.find(args[:delayed_job_id])
  
      return unless job.present?
  
      worker = Delayed::Worker.new
      worker.run(job)
    end
  
    desc "Remove Succeeded K8S pods"
    task remove_succeeded_k8s_pods: :environment do
      K8sPods::Defitinion.clean_succeeded
    end
  end
  