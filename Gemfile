# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "minitest", ">= 5.0"
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.60", require: false
end

# RSX has no runtime dependencies and its Rails integration activates only when
# Rails is already loaded, so the suite has to pass both with and without it.
# RAILS_VERSION picks which ActionView to test against; "none" leaves it out.
rails_version = ENV.fetch("RAILS_VERSION", "8.1")

unless rails_version == "none"
  group :test do
    gem "actionview", "~> #{rails_version}.0"
    gem "railties", "~> #{rails_version}.0"
  end
end
