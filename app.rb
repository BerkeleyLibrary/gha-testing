require 'date'
require 'octokit'
require 'sinatra'
require 'sinatra/json'

configure :development do
  set :logging, Logger::DEBUG
  set :server_settings, timeout: 60
end

def has_permatag?(version, permatags)
  (version['metadata']['container']['tags'] & permatags).any?
end

def younger_than?(version, days_old)
  cutoff = Time.now - 60*60*24*days_old
  version['created_at'] > cutoff
end

github = Octokit::Client.new(per_page: 100, auto_paginate: true)

get '/' do
  'Hello, world!'
end

get '/prunables' do
  packages = github.get('orgs/BerkeleyLibrary/packages', {package_type: :container})
  logger.info "Scanning #{packages.size} packages for prunable images: #{packages.collect(&:name).sort}"

  packages.each do |pkg|
    logger.info "Determining prunable images for #{pkg.name}"

    next unless pkg.repository

    permatags = %w(latest edge)
    permatags += github.branches(pkg.repository.full_name).collect(&:name)
    permatags += github.tags(pkg.repository.full_name).collect(&:name)

    images = github.get("orgs/#{pkg.owner.login}/packages/#{pkg.package_type}/#{pkg.name}/versions").collect do |image|
      if has_permatag? image, permatags
        verdict = :permatagged
      elsif younger_than? image, 7
        verdict = :recent
      else
        verdict = :prunable
      end
      # { image:, verdict: }
    end

    json({
      repo: pkg.repository.full_name,
      package: pkg.name,
      images:,
    })
  end
end
