module K8sPods
    class Cron < ApplicationRecord
        belongs_to :definition, class_name: 'K8sPods::Definition', foreign_key: 'definition_id'
        has_many :records, class_name: 'K8sPods::Record', foreign_key: 'cron_id'
        belongs_to :owner, polymorphic: true
    end
end