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
require_relative 'gsc/heading_validator'
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
require_relative 'gsc/geo_auditor'
require_relative 'gsc/brand_segmenter'
require_relative 'gsc/ctr_curve'
require_relative 'gsc/indexing_queue'
require_relative 'gsc/cannibalization_analyzer'
require_relative 'gsc/entity_auditor'
require_relative 'gsc/decay_predictor'
require_relative 'gsc/vault'
require_relative 'gsc/questions_harvester'
require_relative 'gsc/striking_playbook'
require_relative 'gsc/answer_synthesizer'
require_relative 'gsc/serp_feature_detector'
require_relative 'gsc/speed_correlator'
require_relative 'gsc/firewall_scanner'
require_relative 'gsc/title_optimizer'
require_relative 'gsc/command_registry'
require_relative 'gsc/cache_manager'
require_relative 'gsc/seasonal_predictor'
require_relative 'gsc/canonical_chains'
require_relative 'gsc/low_ctr_rewriter'
require_relative 'gsc/security_scanner'
require_relative 'gsc/landing_roi'
require_relative 'gsc/schema_generator'
require_relative 'gsc/sitemap_tree'
require_relative 'gsc/zombie_purger'
require_relative 'gsc/citation_simulator'
require_relative 'gsc/sparkline'
require_relative 'gsc/image_seo'
require_relative 'gsc/hreflang_validator'
require_relative 'gsc/eeat_auditor'
require_relative 'gsc/report_generator'
require_relative 'gsc/intent_shift'
require_relative 'gsc/rich_results'
require_relative 'gsc/watchdog'
require_relative 'gsc/keyword_value'
require_relative 'gsc/mobile_parity'
require_relative 'gsc/skill_pack'
require_relative 'gsc/doctor'
require_relative 'gsc/aio_hunter'
require_relative 'gsc/soft_404_analyzer'
require_relative 'gsc/cli/base'
require_relative 'gsc/cli/dashboard'
require_relative 'gsc/cli/cache'
require_relative 'gsc/cli/analytics'
require_relative 'gsc/cli/ga4'
require_relative 'gsc/cli/indexing'
require_relative 'gsc/cli/keywords'
require_relative 'gsc/cli/growth'
require_relative 'gsc/cli/audit'
require_relative 'gsc/cli/setup'
require_relative 'gsc/cli/seasonal'
require_relative 'gsc/cli/canonical'
require_relative 'gsc/cli/low_ctr'
require_relative 'gsc/cli/security'
require_relative 'gsc/cli/landing_roi'
require_relative 'gsc/cli/schema_generate'
require_relative 'gsc/cli/sitemap_tree'
require_relative 'gsc/cli/zombie_purger'
require_relative 'gsc/cli/citation_simulator'
require_relative 'gsc/cli/sparkline'
require_relative 'gsc/cli/image_seo'
require_relative 'gsc/cli/hreflang'
require_relative 'gsc/cli/eeat'
require_relative 'gsc/cli/report'
require_relative 'gsc/cli/intent_shift'
require_relative 'gsc/cli/rich_results'
require_relative 'gsc/cli/watchdog'
require_relative 'gsc/cli/keyword_value'
require_relative 'gsc/cli/mobile_parity'
require_relative 'gsc/cli/skill_pack'
require_relative 'gsc/cli/doctor'
require_relative 'gsc/cli/aio_hunter'
require_relative 'gsc/cli/soft_404'
require_relative 'gsc/cli_advanced'
require_relative 'gsc/cli'

# Top-level aliases for compatibility
IndexNow           = GSC::IndexNow unless defined?(IndexNow)
GoogleTrends       = GSC::GoogleTrends unless defined?(GoogleTrends)
KeywordPlanner     = GSC::KeywordPlanner unless defined?(KeywordPlanner)
KeywordsEverywhere = GSC::KeywordsEverywhere unless defined?(KeywordsEverywhere)
Prompts            = GSC::Prompts unless defined?(Prompts)
HeadingValidator   = GSC::HeadingValidator unless defined?(HeadingValidator)
PageAnalyzer       = GSC::PageAnalyzer unless defined?(PageAnalyzer)
SiteCrawler        = GSC::SiteCrawler unless defined?(SiteCrawler)

GoogleSuggest      = GSC::GoogleSuggest unless defined?(GoogleSuggest)
OpenPageRank       = GSC::OpenPageRank unless defined?(OpenPageRank)
PageSpeed          = GSC::PageSpeed unless defined?(PageSpeed)
SpeedCorrelator    = GSC::SpeedCorrelator unless defined?(SpeedCorrelator)
FirewallScanner    = GSC::FirewallScanner unless defined?(FirewallScanner)
TitleOptimizer     = GSC::TitleOptimizer unless defined?(TitleOptimizer)
PageComparator     = GSC::PageComparator unless defined?(PageComparator)
ContentGap         = GSC::ContentGap unless defined?(ContentGap)
InternalLinks      = GSC::InternalLinks unless defined?(InternalLinks)
SchemaValidator    = GSC::SchemaValidator unless defined?(SchemaValidator)
LlmsGenerator      = GSC::LlmsGenerator unless defined?(LlmsGenerator)
SerpPreview        = GSC::SerpPreview unless defined?(SerpPreview)
SerpFeatureDetector = GSC::SerpFeatureDetector unless defined?(SerpFeatureDetector)
NetworkTracer      = GSC::NetworkTracer unless defined?(NetworkTracer)
RobotsChecker      = GSC::RobotsChecker unless defined?(RobotsChecker)
BacklinksManager   = GSC::BacklinksManager unless defined?(BacklinksManager)
GeoAuditor         = GSC::GeoAuditor unless defined?(GeoAuditor)
BrandSegmenter     = GSC::BrandSegmenter unless defined?(BrandSegmenter)
CtrCurve           = GSC::CtrCurve unless defined?(CtrCurve)
IndexingQueue      = GSC::IndexingQueue unless defined?(IndexingQueue)
CannibalizationAnalyzer = GSC::CannibalizationAnalyzer unless defined?(CannibalizationAnalyzer)
EntityAuditor      = GSC::EntityAuditor unless defined?(EntityAuditor)
DecayPredictor     = GSC::DecayPredictor unless defined?(DecayPredictor)
Vault              = GSC::Vault unless defined?(Vault)
QuestionsHarvester = GSC::QuestionsHarvester unless defined?(QuestionsHarvester)
StrikingPlaybook   = GSC::StrikingPlaybook unless defined?(StrikingPlaybook)
AnswerSynthesizer  = GSC::AnswerSynthesizer unless defined?(AnswerSynthesizer)
CacheManager       = GSC::CacheManager unless defined?(CacheManager)
SeasonalPredictor  = GSC::SeasonalPredictor unless defined?(SeasonalPredictor)
CanonicalChains    = GSC::CanonicalChains unless defined?(CanonicalChains)
LowCtrRewriter     = GSC::LowCtrRewriter unless defined?(LowCtrRewriter)
SecurityScanner    = GSC::SecurityScanner unless defined?(SecurityScanner)
LandingRoi         = GSC::LandingRoi unless defined?(LandingRoi)
SchemaGenerator    = GSC::SchemaGenerator unless defined?(SchemaGenerator)
SitemapTree        = GSC::SitemapTree unless defined?(SitemapTree)
ZombiePurger       = GSC::ZombiePurger unless defined?(ZombiePurger)
CitationSimulator  = GSC::CitationSimulator unless defined?(CitationSimulator)
Sparkline          = GSC::Sparkline unless defined?(Sparkline)
ImageSeo           = GSC::ImageSeo unless defined?(ImageSeo)
HreflangValidator  = GSC::HreflangValidator unless defined?(HreflangValidator)
EeatAuditor        = GSC::EeatAuditor unless defined?(EeatAuditor)
ReportGenerator    = GSC::ReportGenerator unless defined?(ReportGenerator)
IntentShift        = GSC::IntentShift unless defined?(IntentShift)
RichResults        = GSC::RichResults unless defined?(RichResults)
Watchdog           = GSC::Watchdog unless defined?(Watchdog)
KeywordValue       = GSC::KeywordValue unless defined?(KeywordValue)
MobileParity       = GSC::MobileParity unless defined?(MobileParity)
SkillPack          = GSC::SkillPack unless defined?(SkillPack)
Doctor             = GSC::Doctor unless defined?(Doctor)
AioHunter          = GSC::AioHunter unless defined?(AioHunter)
Soft404Analyzer    = GSC::Soft404Analyzer unless defined?(Soft404Analyzer)



