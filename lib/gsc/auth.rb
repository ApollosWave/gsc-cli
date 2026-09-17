# frozen_string_literal: true

module GSC
  class Auth
    OAUTH_TOKEN_URI = URI('https://oauth2.googleapis.com/token')

    SCOPES = [
      'https://www.googleapis.com/auth/indexing',
      'https://www.googleapis.com/auth/webmasters',
      'https://www.googleapis.com/auth/webmasters.readonly',
      'https://www.googleapis.com/auth/analytics.readonly'
    ].freeze

    def self.find_key(custom_path = nil)
      candidates = [
        custom_path,
        Config.key_path,
        ENV['GSC_KEY_PATH'],
        ENV['GOOGLE_APPLICATION_CREDENTIALS'],
        File.expand_path('gsc-service-account.json', Dir.pwd),
        File.expand_path('service-account.json', Dir.pwd),
        File.expand_path('config/gsc-service-account.json', Dir.pwd),
        File.expand_path('config/service-account.json', Dir.pwd),
        File.expand_path('../gsc-service-account.json', Dir.pwd),
        File.expand_path('../service-account.json', Dir.pwd),
        File.expand_path('~/.config/gsc/service-account.json'),
        File.expand_path('~/.gsc-service-account.json')
      ].compact

      found = candidates.find do |path|
        next false unless File.file?(path)

        begin
          json = JSON.parse(File.read(path))
          json['client_email'] && json['private_key']
        rescue StandardError
          false
        end
      end

      if found
        dir = File.dirname(File.expand_path(found))
        is_git = File.exist?(File.join(dir, '.git')) || File.exist?(File.join(File.dirname(dir), '.git'))
        if is_git && !found.start_with?(Config::CONFIG_DIR)
          warn Color.c("⚠️  Security Warning: Service account key is stored in a Git repository (#{found}).", Color::YELLOW)
          warn Color.c("   Run 'gsc connect' or move key to ~/.config/gsc/ to avoid accidental credential commits.\n", Color::YELLOW)
        end
      end

      found
    end

    def self.find_service_account(custom_path = nil, domain = nil)
      # 1. Check custom path first if provided
      if custom_path && File.file?(File.expand_path(custom_path))
        json = JSON.parse(File.read(File.expand_path(custom_path))) rescue nil
        return { data: json, source: custom_path, type: 'file' } if json && json['client_email']
      end

      # 2. Check Agency Vault for domain or active domain
      target_dom = domain || Config.default_domain
      if target_dom
        vault_key = Vault.key_for_domain(target_dom)
        if vault_key && vault_key['client_email']
          return { data: vault_key, source: "vault:#{target_dom}", type: 'vault' }
        end
      end

      # 3. Check filesystem key candidates
      key_file = find_key(custom_path)
      if key_file
        json = JSON.parse(File.read(key_file)) rescue nil
        return { data: json, source: key_file, type: 'file' } if json && json['client_email']
      end

      nil
    end

    def self.fetch_access_token(service_account)
      now = Time.now.to_i
      header = { alg: 'RS256', typ: 'JWT' }
      claims = {
        iss: service_account['client_email'],
        scope: SCOPES.join(' '),
        aud: OAUTH_TOKEN_URI.to_s,
        exp: now + 3600,
        iat: now
      }

      encoded_header = base64_url_encode(JSON.generate(header))
      encoded_claims = base64_url_encode(JSON.generate(claims))
      unsigned_jwt   = "#{encoded_header}.#{encoded_claims}"

      private_key = OpenSSL::PKey::RSA.new(service_account['private_key'])
      signature   = private_key.sign(OpenSSL::Digest::SHA256.new, unsigned_jwt)
      encoded_sig = base64_url_encode(signature)
      signed_jwt  = "#{unsigned_jwt}.#{encoded_sig}"

      res = Net::HTTP.post_form(
        OAUTH_TOKEN_URI,
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion'  => signed_jwt
      )

      data = JSON.parse(res.body)
      unless res.is_a?(Net::HTTPSuccess)
        error_msg = data['error_description'] || data['error'] || res.body
        raise "OAuth token request failed: #{error_msg}"
      end

      data['access_token']
    end

    def self.base64_url_encode(str)
      Base64.urlsafe_encode64(str).delete('=')
    end
  end
end
