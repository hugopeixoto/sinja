# frozen_string_literal: true
module Sinatra::JSONAPI::RelationshipRoutes
  module HasOne
    def self.registered(app)
      app.action_conflicts :graft=>true

      app.get '', :actions=>:pluck do
        serialize_model!(*pluck(resource))
      end

      app.patch '', :nullif=>proc(&:nil?), :actions=>:prune do
        _, opts = prune(resource)
        serialize_model?(nil, opts)
      end

      app.patch '', :actions=>:graft do
        serialize_model?(*graft(resource, data))
      end
    end
  end
end
