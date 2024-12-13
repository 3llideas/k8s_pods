# K8sPods
Allow to manage pods definition, create pods and run delayed jobs on them

## Usage
If we use the jobs:work or jobs:workoff tasks from Delayed::Job, we have to indicate the queues that we want to be executed in a standard way, excluding the queues that we want to be executed in a new pod.

```
QUEUES='import,fast' rake jobs:work
```

## Installation
Add this line to your application's Gemfile:

```ruby
gem 'k8s_pods'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install k8s_pods
```

Execute this to copy the initializer. Update it with your configuration.
```ruby
rails generate k8s_pods:install
```

Then, run the migrations
```ruby
rails k8s_pods:install:migrations
rake db:migrate
```

By default, the application rakes are available. If we want to execute other functions, we need to decorate/override the record model to add our own functions:
```ruby
K8sPods::Record.class_eval do
    def self.test
        puts 'test'
    end
end
```

The instances of the models which will be "owners" of a K8sPods::Cron should respond to the k8s_pod_owner_name
```ruby
class MyModel < ActiveRecord::Base
    def k8s_pod_owner_name
        self.name
    end
end

```




We should create some K8sDelayedPod definitions, as for example:

```ruby
queue_name: 'k8s-pod'
pod_namespace: 'pod_namespace'
pod_image: 'pod_image'
pod_cpu: '100m'
pod_memory: '128Mi'
pod_yaml: //valid yaml
```

After that, we can use this K8sDelayedPod definition. The pod parameters will be merged on the yaml before the pod request

```ruby
OurModel.delay(queue: 'k8s-pod').action
```

Also we can overwrite the pod_namespace, pod_image, pod_cpu and pod_memory parameters as we want:

```ruby
OurModel.delay(queue: 'k8s-pod', pod_image: 'another-image-for-this-job', pod_cpu:'200m').action
```

## License
All rights reserved.
