# frozen_string_literal: true

require "monitor"

module RSX
  # Finds, compiles, evaluates and reloads .rsx files.
  class Loader
    EXTENSIONS = [".rsx", ".html.rsx"].freeze

    Entry = Struct.new(:path, :digest, :mtime, :components, :default, :template, :statics_prefix,
                       keyword_init: true) do
      # Markup files render through a template; component files render their
      # default export.
      def renderable
        default || components.first
      end
    end

    def initialize(config)
      @config = config
      @entries = {}
      @stack = []
      @monitor = Monitor.new
    end

    def entries
      @entries.values
    end

    def loaded?(path)
      @entries.key?(File.expand_path(path))
    end

    # The file currently being evaluated, used to attribute components to it.
    def current_entry
      @stack.last
    end

    def compile_cache
      @config.compile_cache
    end

    # Compiles and evaluates a .rsx file exactly once per digest.
    def load(path, force: false)
      absolute = File.expand_path(path)
      raise FileNotFoundError, "no such RSX file: #{absolute}" unless File.file?(absolute)

      @monitor.synchronize do
        source = File.read(absolute)
        digest = compile_cache.digest(source)
        existing = @entries[absolute]
        return existing if existing && existing.digest == digest && !force

        unload(existing) if existing

        entry = Entry.new(path: absolute, digest: digest, mtime: mtime(absolute), components: [],
                          default: nil, statics_prefix: Transformer.static_prefix(source))
        @entries[absolute] = entry
        @stack.push(entry)

        begin
          ruby = compile_cache.fetch_or_compile(absolute, source) do
            Transformer.transform(source, path: absolute)
          end

          if Transformer.defines_components?(ruby)
            # Component files are evaluated at the top level so that `class`,
            # `def` and constants behave exactly as they do in a .rb file.
            eval(ruby, TOPLEVEL_BINDING, absolute, 1) # rubocop:disable Security/Eval
          else
            entry.template = Template.from_ruby(ruby, path: absolute, digest: digest)
          end
        rescue Exception # rubocop:disable Lint/RescueException
          @entries.delete(absolute)
          raise
        ensure
          @stack.pop
        end

        entry
      end
    end

    # Loads every .rsx file under the configured paths. Called at boot in
    # production so no request pays for compilation.
    def load_all(paths = @config.paths)
      files(paths).each { |file| load(file) }
    end

    def files(paths = @config.paths)
      Array(paths).flat_map do |root|
        next [] unless File.directory?(root)

        Dir.glob(File.join(root, "**", "*.rsx")).sort
      end
    end

    # Reloads only the files whose contents changed. Used by the Rails reloader.
    def reload!
      @monitor.synchronize do
        # values takes a snapshot, which each_value would not: the body reloads
        # and deletes entries while iterating.
        @entries.values.each do |entry| # rubocop:disable Style/HashEachMethods
          if !File.file?(entry.path)
            unload(entry)
            @entries.delete(entry.path)
          elsif mtime(entry.path) != entry.mtime
            load(entry.path, force: true)
          end
        end
      end
    end

    def clear
      @monitor.synchronize do
        @entries.each_value { |entry| unload(entry) }
        @entries.clear
      end
    end

    # Resolves an import specifier or template path to a file on disk.
    def resolve(spec, from: nil)
      spec = spec.to_s
      candidates = []

      if spec.start_with?("/")
        candidates << spec
      else
        candidates << File.expand_path(spec, File.dirname(from)) if from && !from.empty?
        Array(@config.paths).each { |root| candidates << File.join(root, spec) }
        candidates << File.expand_path(spec, Dir.pwd)
      end

      candidates.each do |candidate|
        found = rsx_file_at(candidate)
        return found if found && within_roots?(found)
      end

      nil
    end

    def resolve!(spec, from: nil)
      resolved = resolve(spec, from: from)
      return resolved if resolved

      raise FileNotFoundError, unresolvable(spec, from)
    end

    def import(spec, as: nil, from: nil)
      entry = load(resolve!(spec, from: from))
      Array(as).each { |name| alias_constant(name, entry) }
      entry.default || entry.components.first
    end

    # Records a component defined by the file currently being loaded.
    def track(component)
      entry = current_entry
      return component unless entry

      entry.components << component
      entry.default ||= component
      component.rsx_source_path = entry.path
      component.rsx_source_digest = entry.digest
      component
    end

    def default_export(path)
      entry = load(path)
      entry.default || entry.components.first
    end

    private

    def rsx_file_at(candidate)
      return candidate if candidate.end_with?(".rsx") && File.file?(candidate)

      EXTENSIONS.each do |extension|
        with_extension = "#{candidate}#{extension}"
        return with_extension if File.file?(with_extension)
      end

      nil
    end

    # Loading a template evaluates it, so resolution stays inside the configured
    # paths (plus the working directory, which is what scripts and the CLI point
    # at). Without this a spec that came from a request could name any file on
    # disk. Paths are compared after expansion, so `../` cannot climb out.
    def within_roots?(path)
      target = File.expand_path(path)
      roots.any? { |root| target == root || target.start_with?("#{root}#{File::SEPARATOR}") }
    end

    def roots
      Array(@config.paths).map { |root| File.expand_path(root.to_s) }.push(File.expand_path(Dir.pwd)).uniq
    end

    def unresolvable(spec, from)
      searched = Array(@config.paths).join(", ")
      if rsx_file_at(File.expand_path(spec.to_s, Dir.pwd)) || rsx_file_at(spec.to_s)
        "`#{spec}` is outside the configured RSX paths, so it will not be loaded. " \
          "Add its directory to RSX.config.paths. Configured: #{searched}"
      else
        "could not find `#{spec}`#{" imported from #{from}" if from}. Looked in: #{searched}"
      end
    end

    def mtime(path)
      File.mtime(path)
    rescue SystemCallError
      nil
    end

    def alias_constant(name, entry)
      name = name.to_s
      target = entry.default || entry.components.first
      return if target.nil?
      return if RSX.const_defined_at?(name)

      RSX.assign_constant(name, target)
    end

    def unload(entry)
      entry.components.each { |component| RSX.remove_constant(component) }
      entry.components.clear
      entry.default = nil
      RSX.discard_statics(entry.statics_prefix)
    end
  end
end
