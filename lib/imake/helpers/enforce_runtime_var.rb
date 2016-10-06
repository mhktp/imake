def enforce_runtime_var *args
  args.each do |arg|
    raise "Variable '#{arg}' not specified at runtime. Please rerun using `imake -v #{arg}=<value>`." unless $config.vars.key? arg
  end
end
