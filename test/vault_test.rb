# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class VaultTest < Minitest::Test
  def setup
    @original_vault_dir = GSC::Vault::VAULT_DIR
    @test_vault_dir = File.expand_path('../tmp/test_vault', __dir__)
    FileUtils.rm_rf(@test_vault_dir)
    FileUtils.mkdir_p(@test_vault_dir)

    # Temporarily override constants
    GSC::Vault.send(:remove_const, :VAULT_DIR)
    GSC::Vault.send(:remove_const, :KEYS_DIR)
    GSC::Vault.send(:remove_const, :INDEX_FILE)
    GSC::Vault.send(:remove_const, :MASTER_FILE)

    GSC::Vault.const_set(:VAULT_DIR, @test_vault_dir)
    GSC::Vault.const_set(:KEYS_DIR, File.join(@test_vault_dir, 'keys'))
    GSC::Vault.const_set(:INDEX_FILE, File.join(@test_vault_dir, 'vault.json'))
    GSC::Vault.const_set(:MASTER_FILE, File.join(@test_vault_dir, '.master.key'))
  end

  def teardown
    FileUtils.rm_rf(@test_vault_dir)
    GSC::Vault.send(:remove_const, :VAULT_DIR)
    GSC::Vault.send(:remove_const, :KEYS_DIR)
    GSC::Vault.send(:remove_const, :INDEX_FILE)
    GSC::Vault.send(:remove_const, :MASTER_FILE)

    GSC::Vault.const_set(:VAULT_DIR, @original_vault_dir)
    GSC::Vault.const_set(:KEYS_DIR, File.join(@original_vault_dir, 'keys'))
    GSC::Vault.const_set(:INDEX_FILE, File.join(@original_vault_dir, 'vault.json'))
    GSC::Vault.const_set(:MASTER_FILE, File.join(@original_vault_dir, '.master.key'))
  end

  def test_encryption_and_decryption_aes_256_gcm
    secret = '{"client_email": "test@agency.iam.gserviceaccount.com", "private_key": "MOCK_KEY"}'
    envelope = GSC::Vault.encrypt(secret)

    refute_equal secret, envelope
    assert_includes envelope, 'AES-256-GCM'

    decrypted = GSC::Vault.decrypt(envelope)
    assert_equal secret, decrypted
  end

  def test_add_and_retrieve_key
    mock_key = {
      'client_email' => 'client1@agency.iam.gserviceaccount.com',
      'private_key' => '-----BEGIN RSA PRIVATE KEY-----MOCK-----END RSA PRIVATE KEY-----',
      'project_id' => 'agency-client-1'
    }
    tmp_file = File.join(@test_vault_dir, 'sample_key.json')
    File.write(tmp_file, JSON.generate(mock_key))

    entry = GSC::Vault.add_key(tmp_file, domain: 'clientone.com', alias_name: 'c1', ga4_id: '987654321')

    assert_equal 'clientone.com', entry['domain']
    assert_equal 'c1', entry['alias']
    assert_equal 'client1@agency.iam.gserviceaccount.com', entry['client_email']

    # Retrieve by domain
    retrieved = GSC::Vault.key_for_domain('clientone.com')
    assert_equal mock_key['client_email'], retrieved['client_email']

    # Retrieve by alias
    retrieved_alias = GSC::Vault.key_for_domain('c1')
    assert_equal mock_key['client_email'], retrieved_alias['client_email']

    # Vault status
    status = GSC::Vault.status
    assert_equal 1, status[:keys_stored]
    assert_equal 1, status[:domains_mapped]
    assert_equal 'AES-256-GCM', status[:encryption_algorithm]

    # Remove
    assert GSC::Vault.remove_entry('c1')
    assert_nil GSC::Vault.key_for_domain('clientone.com')
    assert_equal 0, GSC::Vault.status[:keys_stored]
  end
end
