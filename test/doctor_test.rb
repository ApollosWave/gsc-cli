# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/doctor'
require_relative '../lib/gsc/version'

class DoctorTest < Minitest::Test
  def setup
    @doctor = GSC::Doctor.new({}, File.expand_path('..', __dir__))
  end

  def test_audit_purity_certifies_zero_external_gems
    res = @doctor.audit_purity

    assert_operator res[:files_scanned], :>=, 90, "Expected at least 90 Ruby files scanned"
    assert_empty res[:unapproved_requires], "Expected zero unapproved external gem requires"
    assert_equal 100.0, res[:purity_score]
    assert_equal :certified_pure, res[:status]
    assert_includes res[:stdlib_packages], 'json'
    assert_includes res[:stdlib_packages], 'openssl'
    assert_includes res[:stdlib_packages], 'net/http'
  end

  def test_benchmark_cold_start_under_100ms
    res = @doctor.benchmark_cold_start(3)

    assert_operator res[:average_ms], :<, 100.0, "Cold start should be under 100ms"
    assert_equal 3, res[:iterations]
    assert_includes [:instant, :fast], res[:status]
  end

  def test_audit_crypto_verifies_aes_gcm_and_pbkdf2
    res = @doctor.audit_crypto

    assert res[:aes_gcm_available], "OpenSSL AES-256-GCM must be operational"
    assert res[:pbkdf2_available], "PBKDF2 key derivation must be operational"
    assert res[:tls_context_ready], "TLS context must be ready"
    assert_equal :ready, res[:status]
  end

  def test_full_diagnose_certification
    res = @doctor.diagnose

    assert_equal GSC::VERSION, res[:version]
    assert_operator res[:certification][:score], :>=, 90.0
    assert_includes ['A+', 'A'], res[:certification][:grade]
    assert_equal :certified_ready, res[:certification][:status]
    assert res[:certification][:certified_zero_gem]
    assert res[:certification][:cold_start_under_100ms]
    assert res[:certification][:crypto_compliant]
  end
end
