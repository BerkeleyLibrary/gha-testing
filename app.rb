require 'date'
require 'octokit'
require 'faraday'
require 'sinatra'
require 'sinatra/json'

configure :development do
  set :logging, Logger::DEBUG
  set :server_settings, timeout: 60
end

stack = Faraday::RackBuilder.new do |builder|
  builder.use Octokit::Middleware::FollowRedirects
  builder.use Octokit::Response::RaiseError
  builder.use Octokit::Response::FeedParser
  builder.response :logger, nil, { headers: true, bodies: true, errors: true } do |logger|
    logger.filter(/(Authorization: "(token|Bearer) )(\w+)/, '\1[REMOVED]')
  end
  builder.adapter Faraday.default_adapter
end
Octokit.middleware = stack

module Logging
  def logger
    Logging.logger
  end

  def self.logger
    @logger ||= Logger.new(STDOUT)
  end
end

class RegistryPruner
  include Logging

  attr_reader :github, :org

  def initialize(github: nil, org: 'BerkeleyLibrary')
    @github = github || Octokit::Client.new(per_page: 100, auto_paginate: true)
    @org = org
    @inventory = nil
  end

  def inventory
    @inventory ||= [].then { refresh_inventory! }
  end

  def prune!(days_old = 7)
    cutoff = Time.now - (60*60*24 * days_old)

    inventory.each do |image|
      if image[:created_at] > cutoff
        logger.debug "SKIPPING: Image #{image[:package]}/#{image[:version]} created recently: #{image[:created_at]}"
        next
      end

      permatags = image[:tags] & image[:repo_permatags]
      if permatags.any?
        logger.debug "SKIPPING: Image #{image[:package]}/#{image[:version]} has permatags: #{permatags.sort.join(', ')}"
        next
      end

      begin
        logger.debug("Deleting image: #{image[:url]}")
        github.delete image[:url], nil
      rescue Octokit::BadRequest => e
        logger.error(e)
        if e.message =~ /cannot be deleted/
          next
        else
          raise
        end
      end
    end
  end

  def refresh_inventory!
    @inventory = [].tap do |images|
      github.get("orgs/#{org}/packages", { package_type: :container }).each do |pkg|
        next unless pkg.repository

        repo = pkg.repository.full_name
        repo_permatags = permatags_for(pkg)
        next_page = "orgs/#{org}/packages/container/#{pkg.name}/versions"

        loop do
          github.get(next_page).each do |image|
            images << {
              url: "orgs/#{org}/packages/container/#{pkg.name}/versions/#{image.id}",
              package: pkg.name,
              version: image.id,
              created_at: image['created_at'],
              tags: image['metadata']['container']['tags'],
              repo:,
              repo_permatags:,
            }
          end
          next_page = github.last_response.rels[:next]&.href
          break if next_page.nil?
        end
      end
    end
  end

  def permatags_for(pkg)
    %w(latest edge).tap do |permatags|
      permatags.concat github.branches(pkg.repository.full_name).collect(&:name)
      permatags.concat github.tags(pkg.repository.full_name).collect(&:name)
      permatags.sort!
    end
  end
end

get '/images' do
  pruner = RegistryPruner.new
  inventory = pruner.inventory
  json({ inventory: })
end
