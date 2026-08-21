# frozen_string_literal: true

require_relative "lib/rsx/version"

Gem::Specification.new do |spec|
  spec.name = "rsx"
  spec.version = RSX::VERSION
  spec.authors = ["RSX contributors"]

  spec.summary = "JSX-style templates for Ruby and Rails."
  spec.description = <<~DESC
    RSX is a template language that brings React's JSX authoring model to Ruby.
    Write .rsx files where Ruby replaces JavaScript and markup is embedded directly
    in expression position, including fragments (<>), expression containers ({}),
    spread attributes and composable components. Templates compile ahead of time to
    plain Ruby string building, so rendering is fast and cacheable. Zero runtime
    dependencies; Rails integration is optional and loads automatically when present.
  DESC

  spec.homepage = "https://github.com/rsx-rb/rsx"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "lib/**/*.rake",
    "exe/*",
    "examples/**/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ]

  spec.bindir = "exe"
  spec.executables = ["rsx"]
  spec.require_paths = ["lib"]

  # No runtime dependencies. Rails/ActionView integration is activated only when
  # those libraries are already loaded by the host application.
end
