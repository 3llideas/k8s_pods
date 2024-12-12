Rails.application.routes.draw do
  mount K8sPods::Engine => "/k8s_pods"
end
