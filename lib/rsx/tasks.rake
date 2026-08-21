# frozen_string_literal: true

namespace :rsx do
  desc "Compile every .rsx file and warm the on-disk compile cache"
  task precompile: :environment do
    files = RSX.loader.files
    RSX.precompile!
    puts "rsx: precompiled #{files.length} file(s) into #{RSX.config.cache_dir || "memory"}"
  end

  desc "Delete compiled .rsx output and clear the render cache"
  task clear: :environment do
    RSX.config.compile_cache.clear
    RSX.cache.clear
    puts "rsx: cleared #{RSX.config.cache_dir || "memory"}"
  end

  desc "Load every .rsx file and report the components it defines"
  task components: :environment do
    RSX.load_all
    RSX.loader.entries.sort_by(&:path).each do |entry|
      names = entry.components.map { |component| component.name || "(anonymous)" }
      puts format("%-60s %s", entry.path.sub("#{Dir.pwd}/", ""), names.join(", "))
    end
  end
end
