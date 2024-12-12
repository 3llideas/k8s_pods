module K8sPods
    class Record < ApplicationRecord
        belongs_to :cron, class_name: 'K8sPods::Cron', foreign_key: 'cron_id'
        belongs_to :owner, polymorphic: true
    end
end