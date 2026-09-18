# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module GSC
  class Config
    CONFIG_DIR  = File.expand_path('~/.config/gsc')
    CONFIG_FILE = File.join(CONFIG_DIR, 'config.json')

    def self.ensure_gsc_symlink!
      gsc_dir = File.expand_path('~/.gsc')
      return if File.exist?(gsc_dir) || File.symlink?(gsc_dir)
      File.symlink(CONFIG_DIR, gsc_dir) rescue nil
    end

    def self.get(key)
  load[key.to_s]
end

def self.set(key, value)
  save(key.to_s => value)
  value
end

    def self.load
      return {} unless File.exist?(CONFIG_FILE)
      JSON.parse(File.read(CONFIG_FILE))
    rescue StandardError
      {}
    end

    def self.save(data)
      FileUtils.mkdir_p(CONFIG_DIR)
      File.chmod(0700, CONFIG_DIR) rescue nil
      existing = load
      updated = existing.merge(data)
      File.write(CONFIG_FILE, JSON.pretty_generate(updated))
      File.chmod(0600, CONFIG_FILE) rescue nil
      updated
    end

    def self.default_domain
      load['default_domain']
    end

    def self.set_default_domain(domain)
      clean = domain.to_s.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')
      save('default_domain' => clean)
      clean
    end

    def self.key_path
      load['key_path']
    end

    def self.set_key_path(path)
      resolved = File.expand_path(path)
      save('key_path' => resolved)
      resolved
    end

    def self.ga4_properties
      load['ga4_properties'] || {}
    end

    def self.ga4_property_id(domain = nil)
      dom = domain || default_domain
      return load['ga4_property_id'] unless dom
      clean = dom.to_s.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')
      ga4_properties[clean] || load['ga4_property_id']
    end

    def self.set_ga4_property_id(property_id, domain = nil)
      dom = domain || default_domain
      clean = dom ? dom.to_s.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/') : nil
      clean_id = property_id.to_s.strip.sub(%r{^properties/}, '')

      if clean
        props = ga4_properties.dup
        props[clean] = clean_id
        save('ga4_properties' => props)
      else
        save('ga4_property_id' => clean_id)
      end
      clean_id
    end

    def self.unlink_ga4_property(domain = nil)
      dom = domain || default_domain
      return unless dom
      clean = dom.to_s.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')
      props = ga4_properties.dup
      removed = props.delete(clean)
      save('ga4_properties' => props)
      removed
    end
def self.keywords_everywhere_api_key
  ENV['KEYWORDSEVERYWHERE_API_KEY'] || load['keywords_everywhere_api_key'] || load['ke_api_key']
end

def self.set_keywords_everywhere_api_key(key)
  clean = key.to_s.strip
  save('keywords_everywhere_api_key' => clean)
  clean
end

def self.domain_keywords_dir(domain = nil)
  dom = domain || default_domain || 'global'
  clean = dom.to_s.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/').gsub(/[^a-zA-Z0-9.-]/, '_')
  dir = File.join(CONFIG_DIR, 'domains', clean, 'keywords')
  FileUtils.mkdir_p(dir)
  File.chmod(0700, dir) rescue nil
  dir
end

def self.save_keyword_research(domain, name_or_seed, data, source: 'planner')
  dir = domain_keywords_dir(domain)
  date_str = Time.now.strftime('%Y-%m-%d')
  clean_name = name_or_seed.to_s.downcase.gsub(/[^a-z0-9]+/, '-').sub(/^-+/, '').sub(/-+$/, '')
  clean_name = 'research' if clean_name.empty?
  filename = "#{date_str}-#{clean_name}.json"
  filepath = File.join(dir, filename)

  payload = {
    'domain' => domain || default_domain,
    'seed' => name_or_seed,
    'source' => source,
    'savedAt' => Time.now.utc.iso8601,
    'totalKeywords' => data.size,
    'keywords' => data
  }

  File.write(filepath, JSON.pretty_generate(payload))
  filepath
end

def self.list_saved_keywords(domain = nil)
  dir = domain_keywords_dir(domain)
  files = Dir.glob(File.join(dir, '*.json')).sort_by { |f| File.mtime(f) }.reverse
  files.map do |f|
    parsed = JSON.parse(File.read(f)) rescue {}
    {
      'file' => File.basename(f),
      'path' => f,
      'seed' => parsed['seed'] || File.basename(f, '.json'),
      'source' => parsed['source'] || 'unknown',
      'savedAt' => parsed['savedAt'] || File.mtime(f).utc.iso8601,
      'totalKeywords' => parsed['totalKeywords'] || (parsed['keywords'] ? parsed['keywords'].size : 0),
      'domain' => parsed['domain']
    }
  end
end

def self.load_saved_keywords(domain, identifier)
  list = list_saved_keywords(domain)
  return nil if list.empty?

  target_file = if identifier.to_s =~ /^\d+$/
                  idx = identifier.to_i - 1
                  idx >= 0 ? list[idx]&.fetch('path', nil) : nil
                else
                  found = list.find { |item| item['file'] == identifier || item['seed'] == identifier || item['file'].include?(identifier.to_s) }
                  found ? found['path'] : nil
                end

  return nil unless target_file && File.exist?(target_file)
  JSON.parse(File.read(target_file))
rescue StandardError
  nil
end

def self.delete_saved_keywords(domain, identifier)
  list = list_saved_keywords(domain)
  return false if list.empty?

  target_file = if identifier.to_s =~ /^\d+$/
                  idx = identifier.to_i - 1
                  idx >= 0 ? list[idx]&.fetch('path', nil) : nil
                else
                  found = list.find { |item| item['file'] == identifier || item['file'].include?(identifier.to_s) }
                  found ? found['path'] : nil
                end

  return false unless target_file && File.exist?(target_file)
  File.delete(target_file)
  true
end

  end
end

