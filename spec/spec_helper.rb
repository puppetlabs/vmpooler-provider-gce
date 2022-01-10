# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end
require 'helpers'
require 'rspec'
require 'vmpooler'
require 'redis'
require 'vmpooler/metrics'
require 'computeservice_helper'
require 'dnsservice_helper'

def project_root_dir
  File.dirname(File.dirname(__FILE__))
end

def fixtures_dir
  File.join(project_root_dir, 'spec', 'fixtures')
end

def create_google_client_error(status_code, message, reason = 'notFound')
  Google::Apis::ClientError.new(Google::Apis::ClientError, status_code: status_code, body: '{
  "error": {
    "code": ' + status_code.to_s + ',
    "message": "' + message + '",
    "errors": [
      {
        "message": "' + message + '",
        "domain": "global",
        "reason": "' + reason + '"
      }
    ]
  }
  }
  ')
end
