def certificate_arn(domain_name, region)
  acm_client = Aws::ACM::Client.new(region: region)
  acm_client.list_certificates.certificate_summary_list.select { |s| s.domain_name == domain_name }[0].certificate_arn
end
