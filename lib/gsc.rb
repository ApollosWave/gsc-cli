# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'base64'
require 'optparse'
require 'time'
require 'date'
require 'fileutils'

module GSC
end

require_relative 'gsc/version'
require_relative 'gsc/color'
require_relative 'gsc/config'
require_relative 'gsc/auth'
require_relative 'gsc/client'
require_relative 'gsc/api'
require_relative 'gsc/sitemap_loader'
require_relative 'gsc/google_trends'
require_relative 'gsc/keyword_planner'
require_relative 'gsc/keywords_everywhere'
require_relative 'gsc/prompts'
require_relative 'gsc/page_analyzer'
require_relative 'gsc/site_crawler'
require_relative 'gsc/google_suggest'
require_relative 'gsc/open_page_rank'
require_relative 'gsc/page_speed'
require_relative 'gsc/page_comparator'
require_relative 'gsc/content_gap'
require_relative 'gsc/internal_links'
require_relative 'gsc/schema_validator'
require_relative 'gsc/llms_generator'
require_relative 'gsc/serp_preview'
require_relative 'gsc/network_tracer'
require_relative 'gsc/robots_checker'
require_relative 'gsc/backlinks_manager'
require_relative 'gsc/indexnow'
require_relative 'gsc/command_registry'
require_relative 'gsc/cli_advanced'
require_relative 'gsc/cli'

# Top-level aliases for compatibility
IndexNow           = GSC::IndexNow unless defined?(IndexNow)
GoogleTrends       = GSC::GoogleTrends unless defined?(GoogleTrends)
KeywordPlanner     = GSC::KeywordPlanner unless defined?(KeywordPlanner)
KeywordsEverywhere = GSC::KeywordsEverywhere unless defined?(KeywordsEverywhere)
Prompts            = GSC::Prompts unless defined?(Prompts)
PageAnalyzer       = GSC::PageAnalyzer unless defined?(PageAnalyzer)
SiteCrawler        = GSC::SiteCrawler unless defined?(SiteCrawler)

GoogleSuggest      = GSC::GoogleSuggest unless defined?(GoogleSuggest)
OpenPageRank       = GSC::OpenPageRank unless defined?(OpenPageRank)
PageSpeed          = GSC::PageSpeed unless defined?(PageSpeed)
PageComparator     = GSC::PageComparator unless defined?(PageComparator)
ContentGap         = GSC::ContentGap unless defined?(ContentGap)
InternalLinks      = GSC::InternalLinks unless defined?(InternalLinks)
SchemaValidator    = GSC::SchemaValidator unless defined?(SchemaValidator)
LlmsGenerator      = GSC::LlmsGenerator unless defined?(LlmsGenerator)
SerpPreview        = GSC::SerpPreview unless defined?(SerpPreview)
NetworkTracer      = GSC::NetworkTracer unless defined?(NetworkTracer)
RobotsChecker      = GSC::RobotsChecker unless defined?(RobotsChecker)
BacklinksManager   = GSC::BacklinksManager unless defined?(BacklinksManager)
