module Miniloader
  # In-process, thread-safe rate + concurrency limiter. Single-process/multi-thread
  # deployment (Puma) is assumed, so in-memory state is sufficient here.
  class RateLimiter
    Result = Struct.new(:allowed?, :reason)

    def initialize(rate_limit_per_minute:, max_concurrent:, max_concurrent_per_caller:)
      @rate_limit_per_minute = rate_limit_per_minute
      @max_concurrent = max_concurrent
      @max_concurrent_per_caller = max_concurrent_per_caller
      @mutex = Mutex.new
      @request_times = Hash.new { |h, k| h[k] = [] }
      @in_flight_total = 0
      @in_flight_per_caller = Hash.new(0)
    end

    # Attempts to reserve a request slot for `caller`. Returns a Result; when
    # allowed, the caller MUST call #release(caller) once the request finishes.
    def try_acquire(caller)
      @mutex.synchronize do
        prune(caller)

        return Result.new(false, "rate limit exceeded (#{@rate_limit_per_minute}/min)") if
          @request_times[caller].size >= @rate_limit_per_minute

        return Result.new(false, "too many concurrent uploads in progress") if
          @in_flight_total >= @max_concurrent

        return Result.new(false, "too many concurrent uploads for this caller") if
          @in_flight_per_caller[caller] >= @max_concurrent_per_caller

        @request_times[caller] << Time.now
        @in_flight_total += 1
        @in_flight_per_caller[caller] += 1
        Result.new(true, nil)
      end
    end

    def release(caller)
      @mutex.synchronize do
        @in_flight_total -= 1
        @in_flight_per_caller[caller] -= 1
      end
    end

    private

    def prune(caller)
      cutoff = Time.now - 60
      @request_times[caller].reject! { |t| t < cutoff }
    end
  end
end
