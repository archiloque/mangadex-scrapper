source 'https://rubygems.org'
ruby '3.1.2'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://github.com/#{repo_name}.git"
end

gem 'curb', '~> 0.9.3'
gem 'rubyzip', '~> 2.3', '>= 2.3.2'
gem 'asciidoctor', '~> 2.0', '>= 2.0.17'
gem 'asciidoctor-epub3', '~> 1.5', '>= 1.5.1'
