# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'openssl'
require 'base64'
require 'time'

module GSC
  class Vault
    VAULT_DIR   = File.join(Config::CONFIG_DIR, 'vault')
    KEYS_DIR    = File.join(VAULT_DIR, 'keys')
    INDEX_FILE  = File.join(VAULT_DIR, 'vault.json')
    MASTER_FILE = File.join(VAULT_DIR, '.master.key')
    AUTH_DATA   = 'gsc-vault-v1'

    def self.ensure_directories!
      FileUtils.mkdir_p(KEYS_DIR)
      File.chmod(0700, VAULT_DIR) rescue nil
      File.chmod(0700, KEYS_DIR) rescue nil
    end

    def self.master_key
      ensure_directories!
      if File.exist?(MASTER_FILE)
        File.chmod(0600, MASTER_FILE) rescue nil
        raw = File.binread(MASTER_FILE)
        return raw if raw.bytesize == 32
      end

      # Generate new 256-bit AES master key
      new_key = OpenSSL::Random.random_bytes(32)
      File.binwrite(MASTER_FILE, new_key)
      File.chmod(0600, MASTER_FILE) rescue nil
      new_key
    end

    def self.encrypt(plaintext)
      cipher = OpenSSL::Cipher.new('aes-256-gcm').encrypt
      cipher.key = master_key
      iv = cipher.random_iv
      cipher.auth_data = AUTH_DATA
      encrypted = cipher.update(plaintext) + cipher.final
      tag = cipher.auth_tag

      JSON.generate({
        'alg'  => 'AES-256-GCM',
        'iv'   => Base64.strict_encode64(iv),
        'tag'  => Base64.strict_encode64(tag),
        'data' => Base64.strict_encode64(encrypted)
      })
    end

    def self.decrypt(envelope_json)
      payload = JSON.parse(envelope_json)
      decipher = OpenSSL::Cipher.new('aes-256-gcm').decrypt
      decipher.key = master_key
      decipher.iv = Base64.strict_decode64(payload['iv'])
      decipher.auth_tag = Base64.strict_decode64(payload['tag'])
      decipher.auth_data = AUTH_DATA
      decipher.update(Base64.strict_decode64(payload['data'])) + decipher.final
    rescue StandardError => e
      raise "Vault Decryption Failed: #{e.message}"
    end

    def self.load_index
      ensure_directories!
      return { 'domains' => {}, 'aliases' => {} } unless File.exist?(INDEX_FILE)
      JSON.parse(File.read(INDEX_FILE))
    rescue StandardError
      { 'domains' => {}, 'aliases' => {} }
    end

    def self.save_index(data)
      ensure_directories!
      File.write(INDEX_FILE, JSON.pretty_generate(data))
      File.chmod(0600, INDEX_FILE) rescue nil
      data
    end

    def self.normalize_domain(dom)
      dom.to_s.strip.downcase.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')
    end

    def self.add_key(raw_path, domain: nil, alias_name: nil, ga4_id: nil)
      path = File.expand_path(raw_path)
      raise "File not found: #{path}" unless File.file?(path)

      raw_content = File.read(path)
      json = JSON.parse(raw_content)
      client_email = json['client_email']
      private_key  = json['private_key']
      project_id   = json['project_id']

      raise 'Invalid Google Service Account JSON: missing client_email or private_key' unless client_email && private_key

      target_domain = domain ? normalize_domain(domain) : nil
      clean_alias = alias_name ? alias_name.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, '') : nil

      # If no domain given, default to project_id or sanitize client_email
      safe_stem = target_domain || clean_alias || (project_id ? "#{project_id}.vault" : "key_#{Time.now.to_i}")
      sanitized_stem = safe_stem.gsub(/[^a-zA-Z0-9.-]/, '_').gsub(/\.{2,}/, '_')
      safe_filename = File.basename("#{sanitized_stem}.enc")
      key_store_path = File.join(KEYS_DIR, safe_filename)

      encrypted_blob = encrypt(raw_content)
      File.write(key_store_path, encrypted_blob)
      File.chmod(0600, key_store_path) rescue nil

      idx = load_index
      entry = {
        'domain'        => target_domain,
        'alias'         => clean_alias,
        'key_file'      => safe_filename,
        'client_email'  => client_email,
        'project_id'    => project_id,
        'ga4_id'        => ga4_id,
        'created_at'    => Time.now.utc.iso8601,
        'last_used_at'  => nil
      }

      idx['domains'][target_domain] = entry if target_domain
      idx['aliases'][clean_alias] = entry if clean_alias
      idx['keys'] ||= {}
      idx['keys'][safe_filename] = entry

      save_index(idx)
      entry
    end

    def self.find_entry(query)
      return nil if query.nil? || query.to_s.strip.empty?
      clean = normalize_domain(query)
      idx = load_index

      # 1. Exact domain match
      return idx['domains'][clean] if idx['domains'] && idx['domains'][clean]

      # 2. Exact alias match
      return idx['aliases'][clean] if idx['aliases'] && idx['aliases'][clean]

      # 3. Partial domain match
      match = (idx['domains'] || {}).find { |d, _| d.include?(clean) }
      return match[1] if match

      # 4. Partial alias or key match
      alias_match = (idx['aliases'] || {}).find { |a, _| a.include?(clean) }
      return alias_match[1] if alias_match

      # 5. Check by number (1-indexed based on sorted domains)
      if clean =~ /^\d+$/
        num = clean.to_i
        domains_list = (idx['domains'] || {}).keys.sort
        if num >= 1 && num <= domains_list.size
          return idx['domains'][domains_list[num - 1]]
        end
      end

      nil
    end

    def self.get_decrypted_key(entry)
      return nil unless entry && entry['key_file']
      clean_filename = File.basename(entry['key_file'].to_s)
      key_file = File.join(KEYS_DIR, clean_filename)
      return nil unless File.file?(key_file)
      return nil unless File.expand_path(key_file).start_with?(File.expand_path(KEYS_DIR))

      raw = File.read(key_file)
      decrypted = decrypt(raw)

      # Update last used
      idx = load_index
      if idx['keys'] && idx['keys'][entry['key_file']]
        idx['keys'][entry['key_file']]['last_used_at'] = Time.now.utc.iso8601
        save_index(idx)
      end

      JSON.parse(decrypted)
    rescue StandardError => e
      warn "Vault Decryption Warning: #{e.message}"
      nil
    end

    def self.key_for_domain(domain)
      entry = find_entry(domain)
      return nil unless entry
      get_decrypted_key(entry)
    end

    def self.remove_entry(query)
      entry = find_entry(query)
      return false unless entry

      idx = load_index
      idx['domains'].delete(entry['domain']) if entry['domain']
      idx['aliases'].delete(entry['alias']) if entry['alias']
      idx['keys'].delete(entry['key_file']) if entry['key_file']

      if entry['key_file']
        file_path = File.join(KEYS_DIR, entry['key_file'])
        FileUtils.rm_f(file_path)
      end

      save_index(idx)
      true
    end

    def self.switch_to(target_query)
      entry = find_entry(target_query)
      target_domain = entry ? (entry['domain'] || target_query) : normalize_domain(target_query)

      # Set default domain in config
      Config.set_default_domain(target_domain)

      # If GA4 ID is mapped in entry, set it
      if entry && entry['ga4_id']
        Config.set_ga4_property_id(entry['ga4_id'], target_domain)
      end

      {
        domain: target_domain,
        entry: entry,
        has_vault_key: !entry.nil?
      }
    end

    def self.list_entries
      idx = load_index
      active = Config.default_domain

      entries = []
      (idx['keys'] || {}).each do |_k, entry|
        is_active = (entry['domain'] == active)
        entries << entry.merge('active' => is_active)
      end

      entries.sort_by { |e| [e['active'] ? 0 : 1, e['domain'].to_s] }
    end

    def self.status
      ensure_directories!
      idx = load_index
      keys_count = (idx['keys'] || {}).size
      domains_count = (idx['domains'] || {}).size
      has_master = File.exist?(MASTER_FILE)
      perm_ok = (File.stat(VAULT_DIR).mode & 0777 == 0700) rescue false

      {
        vault_dir: VAULT_DIR,
        master_key_present: has_master,
        encryption_algorithm: 'AES-256-GCM',
        keys_stored: keys_count,
        domains_mapped: domains_count,
        permissions_secure: perm_ok,
        active_domain: Config.default_domain
      }
    end
  end
end
