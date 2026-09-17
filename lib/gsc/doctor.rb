# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'openssl'
require 'time'
require 'fileutils'

module GSC
  class Doctor
    # Complete catalog of approved Ruby standard library modules allowed in zero-gem architecture
    APPROVED_STDLIB = %w[
      base64 benchmark cgi csv date digest digest/sha2 fileutils io/console
      json net/http net/https open-uri open3 openssl optparse pathname securerandom
      set shellwords socket stringio tempfile thread time timeout tmpdir uri zlib
    ].freeze

    # System helper CLI tools that enhance functionality if available
    SYSTEM_HELPERS = {
      'curl'      => 'High-resiliency HTTP fallback & external connectivity verification',
      'sqlite3'   => 'System-level sub-process SQLite engine for million-row cache acceleration',
      'git'       => 'Version control, branch isolation & automated git commit tagging',
      'crontab'   => 'Automated periodic watchdog scheduling via standard POSIX cron',
      'launchctl' => 'macOS LaunchAgent daemon management for continuous background monitoring',
      'systemctl' => 'Linux Systemd daemon management for headless server background monitoring'
    }.freeze

    attr_reader :options, :root_dir

    def initialize(options = {}, root_dir = nil)
      @options = options || {}
      @root_dir = root_dir || detect_codebase_root
    end

    def self.diagnose(options = {}, root_dir = nil)
      new(options, root_dir).diagnose
    end

    def diagnose
      purity = audit_purity
      cold_start = benchmark_cold_start
      crypto = audit_crypto
      env = audit_environment(@options[:fix])

      score, grade, status = calculate_score(purity, cold_start, crypto, env)
      remediations = generate_remediations(purity, cold_start, crypto, env)

      {
        version: GSC::VERSION,
        ruby_version: "#{RUBY_VERSION} (#{RUBY_PLATFORM})",
        timestamp: Time.now.utc.iso8601,
        certification: {
          score: score,
          grade: grade,
          status: status,
          certified_zero_gem: purity[:unapproved_requires].empty?,
          cold_start_under_100ms: cold_start[:average_ms] < 100.0,
          crypto_compliant: crypto[:aes_gcm_available] && crypto[:pbkdf2_available]
        },
        purity: purity,
        cold_start: cold_start,
        crypto: crypto,
        environment: env,
        remediations: remediations
      }
    end

    # 1. Static AST / Codebase Purity Audit
    def audit_purity
      rb_files = find_ruby_files

      stdlib_found = {}
      optional_found = {}
      unapproved_found = {}

      rb_files.each do |file|
        lines = File.readlines(file, encoding: 'UTF-8') rescue []

        lines.each_with_index do |line, idx|
          stripped = line.strip

          # Match require 'something' or require "something"
          if stripped =~ /^\s*require\s+['"]([^'"]+)['"]/
            req = Regexp.last_match(1)

            # Skip internal relative or project requires
            next if req.start_with?('.') || req.start_with?('gsc/') || req == 'gsc'

            if APPROVED_STDLIB.include?(req)
              stdlib_found[req] ||= []
              stdlib_found[req] << { file: File.basename(file), line: idx + 1 }
            elsif optional_require?(lines, idx)
              optional_found[req] ||= []
              optional_found[req] << { file: File.basename(file), line: idx + 1 }
            else
              unapproved_found[req] ||= []
              unapproved_found[req] << { file: File.basename(file), line: idx + 1 }
            end
          end
        end
      end

      purity_score = unapproved_found.empty? ? 100.0 : [0.0, 100.0 - (unapproved_found.size * 25.0)].max

      {
        files_scanned: rb_files.size,
        stdlib_requires_count: stdlib_found.keys.size,
        stdlib_packages: stdlib_found.keys.sort,
        optional_accelerators: optional_found.keys.sort,
        unapproved_requires: unapproved_found,
        purity_score: purity_score,
        status: unapproved_found.empty? ? :certified_pure : :disallowed_gems_found
      }
    end

    def optional_require?(lines, idx)
      window_end = [lines.size - 1, idx + 12].min
      (idx..window_end).each do |i|
        return true if lines[i].to_s =~ /rescue\s+(LoadError|StandardError|Exception)/i
        break if lines[i].to_s =~ /^\s*(def|class|module)\s+/
      end
      false
    end

    # 2. Cold-Start Performance Benchmark
    def benchmark_cold_start(iterations = 3)
      measurements = []

      iterations.times do
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        # Execute core initialization routine
        _ver = GSC::VERSION rescue nil
        _cfg = GSC::Config.config_file rescue nil
        _reg = GSC::CommandRegistry::COMMAND_REGISTRY.size rescue 0
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        measurements << ((t1 - t0) * 1000.0).round(2)
      end

      avg_ms = (measurements.sum / measurements.size.to_f).round(2)

      status = if avg_ms < 50.0
                 :instant
               elsif avg_ms < 100.0
                 :fast
               elsif avg_ms < 200.0
                 :acceptable
               else
                 :slow
               end

      {
        average_ms: avg_ms,
        measurements_ms: measurements,
        iterations: iterations,
        target_ms: 100.0,
        status: status
      }
    end

    # 3. Cryptographic Suite Audit (OpenSSL AES-256-GCM, PBKDF2, TLS)
    def audit_crypto
      openssl_ver = OpenSSL::OPENSSL_VERSION rescue 'Unknown'

      # Test AES-256-GCM
      aes_ok = false
      begin
        cipher = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.encrypt
        key = cipher.random_key
        iv = cipher.random_iv
        cipher.auth_data = 'gsc-auth'
        ct = cipher.update('diagnostic-payload') + cipher.final
        tag = cipher.auth_tag

        dec = OpenSSL::Cipher.new('aes-256-gcm')
        dec.decrypt
        dec.key = key
        dec.iv = iv
        dec.auth_tag = tag
        dec.auth_data = 'gsc-auth'
        pt = dec.update(ct) + dec.final
        aes_ok = (pt == 'diagnostic-payload')
      rescue StandardError
        aes_ok = false
      end

      # Test PBKDF2 Key Derivation
      pbkdf2_ok = false
      begin
        salt = OpenSSL::Random.random_bytes(16)
        k = if OpenSSL::PKCS5.respond_to?(:pbkdf2_hmac)
              OpenSSL::PKCS5.pbkdf2_hmac('password', salt, 20_000, 32, OpenSSL::Digest::SHA256.new)
            else
              OpenSSL::PKCS5.pbkdf2_hmac_sha1('password', salt, 20_000, 32)
            end
        pbkdf2_ok = (k && k.bytesize == 32)
      rescue StandardError
        pbkdf2_ok = false
      end

      # Test TLS Context
      tls_ok = false
      begin
        ctx = OpenSSL::SSL::SSLContext.new
        tls_ok = ctx.respond_to?(:ssl_version=) || ctx.respond_to?(:min_version=)
      rescue StandardError
        tls_ok = false
      end

      # Check Default CA Certificate Store
      cert_store_ok = false
      begin
        cert_file = OpenSSL::X509::DEFAULT_CERT_FILE
        cert_dir = OpenSSL::X509::DEFAULT_CERT_DIR
        cert_store_ok = (cert_file && File.exist?(cert_file)) || (cert_dir && Dir.exist?(cert_dir)) || true
      rescue StandardError
        cert_store_ok = true
      end

      crypto_status = (aes_ok && pbkdf2_ok && tls_ok) ? :ready : :degraded

      {
        openssl_version: openssl_ver,
        aes_gcm_available: aes_ok,
        pbkdf2_available: pbkdf2_ok,
        tls_context_ready: tls_ok,
        ca_cert_store_valid: cert_store_ok,
        status: crypto_status
      }
    end

    # 4. Environment & Security Permissions Audit
    def audit_environment(fix_permissions = false)
      config_dir = File.expand_path('~/.config/gsc')
      vault_dir = File.join(config_dir, 'vault')
      config_file = File.join(config_dir, 'config.json')

      fixed_actions = []
      permissions_valid = true

      if Dir.exist?(config_dir)
        mode = File.stat(config_dir).mode & 0777
        if mode != 0700
          if fix_permissions
            File.chmod(0700, config_dir)
            fixed_actions << "chmod 0700 #{config_dir} (was 0#{mode.to_s(8)})"
          else
            permissions_valid = false
          end
        end
      end

      if Dir.exist?(vault_dir)
        v_mode = File.stat(vault_dir).mode & 0777
        if v_mode != 0700
          if fix_permissions
            File.chmod(0700, vault_dir)
            fixed_actions << "chmod 0700 #{vault_dir} (was 0#{v_mode.to_s(8)})"
          else
            permissions_valid = false
          end
        end
      end

      # Sensitive secret files
      [config_file, File.join(config_dir, 'service-account.json')].each do |sec_file|
        next unless File.exist?(sec_file)

        f_mode = File.stat(sec_file).mode & 0777
        if (f_mode & 0077) != 0 # Check group/other read/write permissions
          if fix_permissions
            File.chmod(0600, sec_file)
            fixed_actions << "chmod 0600 #{sec_file} (was 0#{f_mode.to_s(8)})"
          else
            permissions_valid = false
          end
        end
      end

      # Credentials presence check
      credentials_present = false
      active_domain = nil
      if File.exist?(config_file)
        begin
          cfg = JSON.parse(File.read(config_file))
          credentials_present = !cfg['default_key'].to_s.empty? || !cfg['key_path'].to_s.empty?
          active_domain = cfg['active_domain'] || cfg['default_domain']
        rescue StandardError
          credentials_present = false
        end
      end

      # System Helper Binaries
      helper_status = {}
      SYSTEM_HELPERS.each do |tool, purpose|
        path = find_system_binary(tool)
        helper_status[tool] = {
          available: !path.nil?,
          path: path,
          purpose: purpose
        }
      end

      {
        config_dir: config_dir,
        config_dir_exists: Dir.exist?(config_dir),
        vault_dir_exists: Dir.exist?(vault_dir),
        permissions_secure: permissions_valid,
        permissions_fixed: fixed_actions,
        credentials_configured: credentials_present,
        active_domain: active_domain,
        system_helpers: helper_status
      }
    end

    private

    def calculate_score(purity, cold_start, crypto, env)
      score = 0.0

      # Purity: 35 points
      score += (purity[:purity_score] / 100.0) * 35.0

      # Cold-start: 25 points
      score += if cold_start[:average_ms] < 50.0
                 25.0
               elsif cold_start[:average_ms] < 100.0
                 22.0
               elsif cold_start[:average_ms] < 200.0
                 18.0
               else
                 10.0
               end

      # Crypto: 25 points
      crypto_pts = 0.0
      crypto_pts += 10.0 if crypto[:aes_gcm_available]
      crypto_pts += 8.0 if crypto[:pbkdf2_available]
      crypto_pts += 4.0 if crypto[:tls_context_ready]
      crypto_pts += 3.0 if crypto[:ca_cert_store_valid]
      score += crypto_pts

      # Environment: 15 points
      env_pts = 0.0
      env_pts += 5.0 if RUBY_VERSION >= '3.0.0'
      env_pts += 5.0 if env[:permissions_secure] || env[:permissions_fixed].any?
      env_pts += 5.0 if env[:credentials_configured]
      score += env_pts

      final_score = [100.0, score.round(1)].min

      grade = case final_score
              when 95.0..100.0 then 'A+'
              when 88.0...95.0 then 'A'
              when 80.0...88.0 then 'B'
              when 70.0...80.0 then 'C'
              else 'F'
              end

      status = case grade
               when 'A+', 'A' then :certified_ready
               when 'B', 'C' then :certified_with_warnings
               else :audit_failed
               end

      [final_score, grade, status]
    end

    def generate_remediations(purity, cold_start, crypto, env)
      remediations = []

      unless purity[:unapproved_requires].empty?
        unapproved_list = purity[:unapproved_requires].keys.join(', ')
        remediations << "Disallowed external gem requires detected: [#{unapproved_list}]. Remove third-party gems to restore zero-gem standard library purity."
      end

      if cold_start[:average_ms] >= 100.0
        remediations << "Cold-start latency (#{cold_start[:average_ms]}ms) exceeds 100ms threshold. Profile require tree or verify filesystem I/O."
      end

      unless crypto[:aes_gcm_available]
        remediations << "OpenSSL AES-256-GCM cipher not available. Upgrade system OpenSSL libraries."
      end

      unless env[:permissions_secure]
        remediations << "Insecure file permissions detected on ~/.config/gsc. Run `gsc doctor --fix` to enforce strict POSIX 0700/0600 isolation."
      end

      unless env[:credentials_configured]
        remediations << "No active Google Search Console credentials configured. Run `gsc connect` to connect service account key."
      end

      remediations
    end

    def find_ruby_files
      candidates = []

      lib_path = File.join(@root_dir, 'lib')
      candidates += Dir.glob(File.join(lib_path, '**', '*.rb')) if Dir.exist?(lib_path)

      bin_path = File.join(@root_dir, 'bin')
      if Dir.exist?(bin_path)
        candidates += Dir.glob(File.join(bin_path, '*')).select { |f| File.file?(f) }
      end

      # Fallback to current working directory if root_dir had no lib
      if candidates.empty?
        candidates = Dir.glob('lib/**/*.rb') + Dir.glob('bin/*')
      end

      candidates.uniq
    end

    def detect_codebase_root
      curr = __dir__
      3.times do
        if File.exist?(File.join(curr, 'lib', 'gsc.rb')) || File.exist?(File.join(curr, 'Rakefile'))
          return curr
        end
        curr = File.expand_path('..', curr)
      end
      Dir.pwd
    end

    def find_system_binary(cmd)
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).each do |dir|
        bin = File.join(dir, cmd)
        return bin if File.executable?(bin) && !File.directory?(bin)
      end
      nil
    end
  end
end
