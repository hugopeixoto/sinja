# frozen_string_literal: true
require 'sinatra/base'
require 'sinatra/namespace'

require 'sinatra/jsonapi/helpers/relationships'
require 'sinatra/jsonapi/relationship_routes/has_many'
require 'sinatra/jsonapi/relationship_routes/has_one'
require 'sinatra/jsonapi/resource_routes'

module Sinatra::JSONAPI
  module Resource
    def def_action_helper(action)
      abort 'JSONAPI resource actions can\'t be HTTP verbs!' if Sinatra::Base.respond_to?(action)

      define_singleton_method(action) do |**opts, &block|
        can(action, opts[:roles]) if opts.key?(:roles)

        define_method(action) do |*args|
          result =
            begin
              instance_exec(*args.take(block.arity.abs), &block)
            rescue Exception=>e
              halt 409, e.message if settings.sinja_config.conflict?(action, e.class)
              #halt 422, resource.errors if settings.sinja_config.invalid?(action, e.class) # TODO
              #not_found if settings.sinja_config.not_found?(action, e.class) # TODO
              raise
            end

          # TODO: This is a nightmare.
          if action == :create
            raise ActionHelperError, "`#{action}' must return primary key and resource object" \
              unless result.is_a?(Array) && result.length >= 2 && !result[1].instance_of?(Hash)
            return result if result.length == 3
            return *result, {}
          else
            return result \
              if result.is_a?(Array) && result.length == 2 && result.last.instance_of?(Hash)
            return nil, result if result.instance_of?(Hash)
            return result, {}
          end
        end
      end
    end

    def def_action_helpers(actions)
      [*actions].each { |action| def_action_helper(action) }
    end

    def self.registered(app)
      app.helpers Helpers::Relationships do
        attr_accessor :resource

        def sanity_check!(id=nil)
          halt 409, 'Resource type in payload does not match endpoint' \
            if data[:type] != request.path.split('/').last # TODO

          halt 409, 'Resource ID in payload does not match endpoint' \
            if id && data[:id].to_s != id.to_s
        end
      end

      app.register ResourceRoutes
    end

    %i[has_one has_many].each do |rel_type|
      define_method(rel_type) do |rel, &block|
        namespace %r{/(?<resource_id>[^/]+)(?<r>/relationships)?/#{rel.to_s.tr('_', '-')}}, :actions=>:find do
          helpers do
            def setter_path?
              !params[:r].nil? # TODO: Can't mix named and positional capture groups?
            end

            def resource
              super || self.resource = find(params[:resource_id]).first
            end

            def sanity_check!
              super(params[:resource_id])
            end
          end

          before do
            not_found unless setter_path? ^ request.get?
            not_found unless resource
          end

          register RelationshipRoutes.const_get \
            rel_type.to_s.split('_').map(&:capitalize).join.to_sym

          if block
            instance_eval(&block)
          elsif rel_type == :has_one
            pluck { resource.send(rel) }
          elsif rel_type == :has_many
            fetch { resource.send(rel) }
          end
        end
      end
    end
  end
end
