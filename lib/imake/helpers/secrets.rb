%w(tmpdir yaml base64 deep_merge aws-sdk).each { |gem| require gem }


class Secrets
  @@cache_file="#{Dir::tmpdir}/imake/secrets.yaml"


  def initialize(context, binding)
    @binding            = binding
    @stackname          = caller[0].split('/').last.split('.')[0]
    @context            = context
    @params             = (File.exists?(@@cache_file)) ? YAML::load_file(@@cache_file) : {}
    @params[@stackname] = {} unless @params.key? @stackname
    @count              = 0
  end


  def hide_parameter(var)
    var  = self.encrypt(var, @binding.local_variable_get('region'))
    name = @stackname + 'HiddenParameter' + @count.to_s.rjust(3, "0")
    @context.Parameter(name) do
      Type 'String'
      NoEcho 'True'
    end
    @params[@stackname][name] = var
    File.open(@@cache_file, 'w') { |f| f.write YAML::dump(@params) }
    @count += 1
    @context.Ref(name)
  end


  def hide_file(filename)
    var = Secrets.encrypt_file(filename, @binding.local_variable_get('region'))
    self.hide_parameter(var)
  end


  def self.as_params(region)
    secrets = []
    Secrets.all_secrets.each do |stk, secs|
      secs.each do |k, v|
        secrets.push({parameter_key: k, parameter_value: Secrets.decrypt(v, region)})
      end
    end
    secrets
  end


  def self.all_secrets
    if File.exists?(@@cache_file)
      return YAML::load_file(@@cache_file)
    end
    return {}
  end


  def self.purge
    File.delete @@cache_file if File.exists?(@@cache_file)
  end


  def encrypt(text, region)
    if text.is_a?(String) && text.include?("ENCRYPT[")
      final = Secrets.encrypt(text, region)
      # Now replace in yaml file. We have no easy way of knowing which file it came from, so speed up development and search them all :(
      # Also, there is a scalability problem with reading the whole file into memory. Though this will likely never be an issue,
      # if someone is looking into finding a huge memory hog in this program, this might be it. Stop reading the whole file into
      # memory and use C-style file pointers and locks to overwrite the string in place.
      # TODO: This was lazy, but performance is not an issue (...yet). Make it smarter if needed.
      Dir.glob(@binding.local_variable_get('config_folder') + "/**/*.yaml") do |file|
        if File.foreach(file).any? { |l| l[text] }
          filetext     = File.read(file)
          new_contents = filetext.gsub(text, final)
          File.open(file, "w") { |f| f.puts new_contents }
        end
      end if @binding.local_variables.include? 'config_folder'.to_sym
      final
    else
      text
    end
  end


  def self.encrypt_file(filename, region)
    text = File.read(filename)
    if text.include?("ENCRYPT[")
      kms = Aws::KMS::Client.new(region: region)
      text.scan(/ENCRYPT\[([\w]+)\|\|([^\|\[\]]+)\]/).each do |key, secret|
        awskeyid = "arn:aws:kms:us-east-1:#{$config.accounts[$config.primary_account]['account_number']}:alias/#{key}"
        encrypted_secret = Base64.strict_encode64(kms.encrypt(key_id: awskeyid, plaintext: secret).ciphertext_blob)
        text.gsub!("ENCRYPT[#{key}||#{secret}]", "DECRYPT[#{key}||#{encrypted_secret}]")
      end
      File.write(filename, text)
    end
    text
  end


  def self.encrypt(text, region)
    if text.is_a?(String) && text.include?("ENCRYPT[")
      key_alias, txt = text.match(/\[(.*)\]/m)[1].split("||")
      awskeyid       = "arn:aws:kms:#{region}:#{$config.accounts[$config.primary_account]['account_number']}:alias/#{key_alias}"
      kms            = Aws::KMS::Client.new(region: region)
      encrypted_text = Base64.strict_encode64(kms.encrypt(key_id: awskeyid, plaintext: txt).ciphertext_blob)
      "DECRYPT[" + key_alias +"||"+ encrypted_text + "]"
    else
      text
    end
  end


  def self.decrypt(text, region)
    if text.is_a?(String) && text.include?("DECRYPT[")
      base64_text     = text.split("||")[-1].chop
      ciphertext_blob = Base64.decode64(base64_text)
      Aws::KMS::Client.new(region: region).decrypt({ciphertext_blob: ciphertext_blob}).plaintext
    else
      text
    end
  end

end
