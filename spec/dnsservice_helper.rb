MockDNS = Struct.new(
  # https://rubydoc.info/gems/google-cloud-dns/0.35.1/Google/Cloud/Dns
  :change, :credentials, :project, :record, :zone,
  keyword_init: true
) do
  def zone(zone)
    self.zone = zone
  end
end