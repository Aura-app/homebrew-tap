class DbTunnel < Formula
  desc "Aura database tunnel helper"
  homepage "https://github.com/aura-app/homebrew-tap"
  version "0.2.1"

  url "https://github.com/aura-app/homebrew-tap/releases/download/db-tunnel-v0.2.1/db-tunnel-v0.2.1.tar.gz"
  sha256 "5805ed4594d9de011e80ae936cc667dc5b26f8cb4eea8963e3f9be0d27188682"

  depends_on "awscli"
  depends_on "jq"

  def install
    bin.install "bin/db-tunnel"
    bin.install "bin/db-auth-token"
    pkgshare.install "share/db-tunnels.json"
    valentina_hook = buildpath/"share/valentina-pre-connect.py"
    pkgshare.install valentina_hook if valentina_hook.exist?
  end

  def caveats
    <<~EOS
      db-tunnel opens AWS SSM sessions and requires Amazon's Session Manager
      plugin. If it is missing, db-tunnel will offer to install it with:

        brew install --cask session-manager-plugin
    EOS
  end

  test do
    assert_match "Available database tunnels:", shell_output("#{bin}/db-tunnel list")
  end
end
