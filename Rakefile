require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/gempackagetask'
require 'rake/clean'

GEM_VERSION = "0.1"

Rake::RDocTask.new do |task|
  task.rdoc_files.add [ 'lib/**/*.rb' ]
end

task :clobber => [ :clean ]

Rake::TestTask.new do |task|
  task.ruby_opts << '-rrubygems'
  task.libs << 'lib'
  task.libs << 'test'
  task.test_files = [ "test/test_all.rb" ]
  task.verbose = true
end

gemspec = Gem::Specification.new do |gemspec|
  gemspec.name = "deltared"
  gemspec.version = GEM_VERSION
  gemspec.author = "MenTaLguY <mental@rydia.net>"
  gemspec.summary = "A multi-way constraint solver for Ruby"
  gemspec.test_file = 'test/test_all.rb'
  gemspec.files = FileList[ 'Rakefile', 'test/*.rb', 'lib/**/*.rb' ]
  gemspec.require_paths = [ 'lib' ]
  gemspec.has_rdoc = true
  gemspec.platform = Gem::Platform::RUBY
end

task :package => [ :clean, :test ]
Rake::GemPackageTask.new( gemspec ) do |task|
  task.gem_spec = gemspec
  task.need_tar = true
end

task :default => [ :clean, :test ]

