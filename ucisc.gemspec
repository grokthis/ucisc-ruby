require_relative 'lib/micro_cisc/version'

Gem::Specification.new do |spec|
  spec.name          = "ucisc"
  spec.version       = MicroCisc::VERSION
  spec.authors       = ["Robert Butler"]
  spec.email         = ["robert at grokthiscommunity.net"]

  spec.summary       = %q{Micro instruction set vm & compiler for hobbyist computing}
  spec.homepage      = "https://github.com/grokthis/ucisc-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  #spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/grokthis/ucisc-ruby"
  #spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "byebug"
  spec.add_runtime_dependency "tty-screen"
  spec.add_runtime_dependency "gtk2"
  spec.add_runtime_dependency "chunky_png"
  spec.add_runtime_dependency "bundler"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
end
