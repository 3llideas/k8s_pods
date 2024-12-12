namespace :crons do
    desc "Background task that executes 'check_and_run' every 15 minutes"
    task worker: :environment do
      loop do
        if ENV["LOG_CRON_WORKER"] == "1"
          file_path = File.join(ENV["EFS_PATH"], ENV["APP_STOAM_SAAS_K8S_APP_NAME"], "worker_cron.log")
          begin
            log_file = File.open(file_path, "a")
            log_file.write("inicia cron worker #{Time.now}\n")
          rescue IOError => e
            puts "No se pudo escribir"
          ensure
            log_file.close unless log_file.nil?
          end
        end
        system("bundle exec rake crons:check_and_run")
        system("bundle exec rake k8s:delayed_to_pod")
        3.times do
          system("QUEUE=mailers bundle exec rake jobs:workoff")
          sleep(1.minutes)
        end
      end
    end
  
    desc "Check if there are cron definitions to be triggered"
    task check_and_run: :environment do
        StoamCarga::Cron.check_and_run
    end
  
    desc "Generates the default cron tasks"
    task generate_default_crons: :environment do
        StoamCarga::Cron.create(name: "Sitemap refresh",
        minute: "30",
        hour: "4",
        rake_task: "sitemap:refresh:no_ping",
        active: true,
        k8s_delayed_pod: K8sDelayedPod.find_by(queue_name: "k8s-pod"))
    end
  
    desc "Raises error"
    task raise: :environment do
      raise "BIG ERROR"
    end
  end
  