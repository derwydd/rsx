# frozen_string_literal: true

module RSX
  # Render caches. Any object responding to `fetch(key, expires_in:) { ... }`
  # and `clear` can be used as a store, so Rails.cache, Memcached or Redis need
  # no adapter beyond the thin wrapper below.
  module Cache
    # Thread-safe in-process LRU. This is the default store so caching works
    # with no configuration and no dependencies.
    class Memory
      DEFAULT_MAX_ENTRIES = 4096

      def initialize(max_entries: DEFAULT_MAX_ENTRIES)
        @max_entries = max_entries
        @entries = {}
        @lock = Mutex.new
      end

      def fetch(key, expires_in: nil)
        found = read(key)
        return found unless found.nil?

        write(key, yield, expires_in: expires_in)
      end

      def read(key)
        @lock.synchronize do
          value, expires_at = @entries[key]
          next nil if value.nil?

          if expires_at && expires_at < now
            @entries.delete(key)
            next nil
          end

          # Re-insert so the entry counts as most recently used.
          @entries.delete(key)
          @entries[key] = [value, expires_at]
          value
        end
      end

      def write(key, value, expires_in: nil)
        @lock.synchronize do
          @entries.delete(key)
          @entries[key] = [value, expires_in && (now + expires_in)]
          @entries.shift while @entries.size > @max_entries
        end
        value
      end

      def delete(key)
        @lock.synchronize { @entries.delete(key) }
      end

      def clear
        @lock.synchronize { @entries.clear }
        self
      end

      def size
        @lock.synchronize { @entries.size }
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    # Stores fragments in Rails.cache so they live alongside the rest of the
    # application's cache and are invalidated by the same tooling.
    class Rails
      def initialize(store = nil)
        @store = store
      end

      def store
        @store || ::Rails.cache
      end

      def fetch(key, expires_in: nil, &block)
        store.fetch(key, expires_in: expires_in, &block)
      end

      def read(key) = store.read(key)
      def write(key, value, expires_in: nil) = store.write(key, value, expires_in: expires_in)
      def delete(key) = store.delete(key)
      def clear = store.clear
    end

    # Never caches. Useful in tests and for disabling caching outright.
    class Null
      def fetch(_key, expires_in: nil) = yield
      def read(_key) = nil
      def write(_key, value, expires_in: nil) = value
      def delete(_key) = nil
      def clear = self
    end
  end
end
