# frozen_string_literal: true

require "digest"
require "fileutils"

module RSX
  # Caches the Ruby produced from .rsx files on disk, keyed by a digest of the
  # source. A warm cache turns loading a template into reading a .rb file, so
  # booting a large application does no transformation work at all.
  class CompileCache
    attr_reader :directory

    def initialize(directory)
      @directory = directory
      @enabled = !directory.nil?
      @memory = {}
      @lock = Mutex.new
    end

    def enabled?
      @enabled
    end

    def digest(source)
      Digest::SHA256.hexdigest("#{COMPILER_VERSION}\0#{source}")[0, 32]
    end

    # Returns the compiled Ruby for source, compiling only on a cache miss.
    def fetch(path, source)
      key = digest(source)
      cached = @lock.synchronize { @memory[key] }
      return cached if cached

      ruby = read(path, key) || begin
        compiled = yield
        write(path, key, compiled)
        compiled
      end

      @lock.synchronize { @memory[key] = ruby }
      ruby
    end

    def path_for(source_path, key)
      return nil unless enabled?

      basename = File.basename(source_path.to_s, ".*")
      basename = "template" if basename.empty?
      File.join(@directory, "#{basename}-#{key}.rb")
    end

    def read(source_path, key)
      target = path_for(source_path, key)
      return nil unless target && File.file?(target)

      File.read(target)
    rescue SystemCallError
      nil
    end

    def write(source_path, key, ruby)
      target = path_for(source_path, key)
      return ruby unless target

      FileUtils.mkdir_p(File.dirname(target))
      temporary = "#{target}.#{Process.pid}.#{rand(1 << 24)}.tmp"
      File.binwrite(temporary, ruby)
      File.rename(temporary, target)
      ruby
    rescue SystemCallError
      # A read-only or missing cache directory must never break rendering.
      @enabled = false
      ruby
    end

    def clear
      @lock.synchronize { @memory.clear }
      return unless enabled? && File.directory?(@directory)

      Dir.glob(File.join(@directory, "*.rb")).each { |file| File.delete(file) }
      Dir.glob(File.join(@directory, "*.tmp")).each { |file| File.delete(file) }
    end
  end
end
