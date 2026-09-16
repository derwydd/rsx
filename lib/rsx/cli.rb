# frozen_string_literal: true

require "optparse"

module RSX
  # `rsx` command line tool. Useful for seeing exactly what a template compiles
  # to, rendering a file outside of Rails, and warming the compile cache.
  class CLI
    BANNER = <<~TEXT
      Usage: rsx COMMAND [options] [files]

      Commands:
        compile FILE...     Print the Ruby a .rsx file compiles to
        render FILE         Render a .rsx file and print the HTML
        precompile DIR...   Compile every .rsx file under DIR and cache the result
        version             Print the RSX version

      Options:
    TEXT

    def self.start(argv)
      new.run(argv)
    end

    def run(argv)
      options = { props: {}, cache_dir: nil }

      parser = OptionParser.new do |opts|
        opts.banner = BANNER
        opts.on("-p", "--prop NAME=VALUE", "Pass a string prop when rendering") do |pair|
          name, value = pair.split("=", 2)
          options[:props][name.to_sym] = value
        end
        opts.on("-I", "--include PATH", "Add a directory to the RSX load path") do |path|
          RSX.config.paths |= [File.expand_path(path)]
        end
        opts.on("-c", "--cache-dir DIR", "Directory for compiled output") do |dir|
          options[:cache_dir] = dir
        end
        opts.on("-h", "--help", "Show this message") { puts opts; return 0 }
      end

      arguments = parser.parse(argv)
      command = arguments.shift

      RSX.config.cache_dir = options[:cache_dir]

      case command
      when "compile" then compile(arguments)
      when "render" then render(arguments, options[:props])
      when "precompile" then precompile(arguments, options[:cache_dir])
      when "version", "-v", "--version" then puts RSX::VERSION
      when nil then puts parser
      else
        warn "rsx: unknown command #{command.inspect}"
        puts parser
        return 1
      end

      0
    rescue RSX::Error, Errno::ENOENT => e
      warn "rsx: #{e.message}"
      1
    end

    private

    def compile(files)
      abort_missing(files)
      files.each do |file|
        puts "# #{file}" if files.length > 1
        puts RSX.compile(File.read(file), path: File.expand_path(file))
      end
    end

    def render(files, props)
      abort_missing(files)
      # Naming a file on the command line is as explicit as it gets, so add its
      # directory to the load path rather than have the loader refuse it.
      RSX.config.paths |= files.map { |file| File.dirname(File.expand_path(file)) }
      files.each { |file| puts RSX.render_file(File.expand_path(file), **props) }
    end

    def precompile(directories, cache_dir)
      directories = [Dir.pwd] if directories.empty?
      RSX.config.cache_dir = cache_dir || File.join(Dir.pwd, "tmp", "cache", "rsx")
      files = RSX.loader.files(directories)
      RSX.precompile!(directories)
      puts "rsx: precompiled #{files.length} file(s) into #{RSX.config.cache_dir}"
    end

    def abort_missing(files)
      raise Error, "no files given" if files.empty?

      missing = files.reject { |file| File.file?(file) }
      raise Error, "no such file: #{missing.join(", ")}" unless missing.empty?
    end
  end
end
