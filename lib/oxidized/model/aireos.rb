class Aireos < Oxidized::Model
  # AireOS (at least I think that is what it's called, hard to find data)
  # Used in Cisco WLC 5500

  comment "! "
  prompt(/^\([^)]+\)\s>/)

  cmd :all do |cfg|
    cfg.cut_both
  end

  # show sysinfo?
  # show switchconfig?

  cmd "show udi" do |cfg|
    cfg = comment clean cfg
    cfg << "\n"
  end

  cmd "show boot" do |cfg|
    cfg = comment clean cfg
    cfg << "\n"
  end

  cmd "show run-config startup-commands" do |cfg|
    clean cfg
  end

  cfg :telnet, :ssh do
    username(/^User:\s*/)
    password(/^Password:\s*/)
    post_login "config paging disable"
  end

  cfg :telnet, :ssh do
    pre_logout do
      send "logout\n"
      send "n"
    end
  end

  def clean(cfg)
    out = []
    cfg = cfg.gsub(/\s{20,}/, "\n")
    cfg.each_line do |line|
      raise StandardError if /.*There is another transfer activity going on.*$/.match?(line)
      next if /^\s*$/.match?(line)
      next if /rogue (adhoc|client) (alert|Unknown) [\da-f]{2}:/.match?(line)
      next if /Config generation may take some time.*$/.match?(line)
      next if /Cannot execute command.*$/.match?(line)
      next if /Please ignore messages.*$/.match?(line)
      next if /transfer (upload|download).*$/.match?(line)
      next if /.*WLC Config (Begin|End).*$/.match?(line)
      next if /.*Blocked: Configuration is blocked.*$/.match?(line)
      next if line[0] == "#"
      next if line[0] == "!"

      line = line[1..-1] if line[0] == "\r"
      out << line.strip
    end
    out = out.join "\n"
    out << "\n"
  end
end
