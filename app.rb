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

# Returns all container packages along with their pruning status, i.e. whether they can/can't be pruned and why
get '/images' do
  packages = github.get('orgs/BerkeleyLibrary/packages', {package_type: :container})
  logger.info "Scanning #{packages.size} packages for prunable images: #{packages.collect(&:name).sort}"

  prunables = [].tap do |sofar|
    packages.each do |pkg|
      logger.info "Determining prunable images for #{pkg.name}"

      next unless pkg.repository

      permatags = %w(latest edge)
      permatags += github.branches(pkg.repository.full_name).collect(&:name)
      permatags += github.tags(pkg.repository.full_name).collect(&:name)

      github.get("orgs/#{pkg.owner.login}/packages/#{pkg.package_type}/#{pkg.name}/versions").each do |image|
        if has_permatag? image, permatags
          pruning_status = :permatagged
        elsif younger_than? image, 7
          pruning_status = :recent
        else
          pruning_status = :prunable
        end

        sofar << {
          image: image.to_attrs,
          pruning_status: pruning_status,
          can_be_pruned: pruning_status == :prunable,
        }
      end
    end
  end

  json prunables
end
