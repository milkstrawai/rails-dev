# frozen_string_literal: true

module RailsDev
  class Hooks
    def initialize(config, context)
      @callbacks = config.hooks
      @context = context
    end

    def call(name)
      @callbacks.fetch(name).each { |callback| invoke(name, callback) }
    end

    def around(index = 0, &)
      callback = @callbacks.fetch(:around_run)[index]
      return yield unless callback

      invoke(:around_run, callback, -> { around(index + 1, &) })
    end

    def after_stop(failure = nil)
      @callbacks.fetch(:after_stop).reverse_each do |callback|
        invoke(:after_stop, callback)
      rescue StandardError => error
        @context.say(error.message) if failure
        failure ||= error
      end
      raise failure if failure
    end

    private

    def invoke(name, callback, *)
      @context.check_for_interrupt
      callback.call(@context, *)
      @context.check_for_interrupt
    rescue Error
      raise
    rescue StandardError => error
      raise Error, "#{name} hook failed: #{error.message}"
    end
  end
end
