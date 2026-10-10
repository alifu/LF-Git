class Lfgit < Formula
  desc "Merge tool and Git client for conflicts in files of any size, such as Xcode project.pbxproj"
  homepage "https://github.com/alifu/LF-Git"
  url "https://github.com/alifu/LF-Git/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/alifu/LF-Git.git", branch: "main"

  # Built on your own machine, so nothing is quarantined and no Apple Developer account is needed.
  depends_on macos: :sonoma

  def install
    # The command line tool needs only a Swift toolchain (Command Line Tools are enough).
    system "swift", "build", "--package-path", "LFCore", "--configuration", "release",
           "--disable-sandbox", "--product", "lfgit"
    bin.install "LFCore/.build/release/lfgit"

    if app_buildable?
      # Ad-hoc signed (CODE_SIGN_IDENTITY=-), which is enough for an app that was built on this Mac.
      system "xcodebuild", "-project", "LF-Git.xcodeproj", "-scheme", "LF-Git", "-configuration", "Release",
             "-derivedDataPath", buildpath/"build", "-enableCodeCoverage", "NO",
             "CODE_SIGN_IDENTITY=-", "ONLY_ACTIVE_ARCH=YES", "build"
      # `lfgit open` looks for LF-Git.app next to bin/, so the app lives in the keg's prefix.
      prefix.install "build/Build/Products/Release/LF-Git.app"
    else
      opoo "Full Xcode 26 or later was not found: only the `lfgit` command line tool was installed."
    end
  end

  def app_buildable?
    MacOS::Xcode.installed? && MacOS::Xcode.version >= "26.0"
  end

  def caveats
    <<~EOS
      Resolve conflicts from a terminal:
        lfgit install          # use lfgit as `git mergetool` in this repository (--global for all)
        git mergetool

      #{app_caveat}
    EOS
  end

  def app_caveat
    return "Only the command line tool was installed: reinstall with Xcode 26 or later for the app." unless (prefix/"LF-Git.app").exist?

    <<~EOS.chomp
      Open the app from a repository with `lfgit open`. To also find it in Launchpad or Spotlight:
        ln -sf #{opt_prefix}/LF-Git.app /Applications/LF-Git.app
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lfgit --version")

    # A real conflict, resolved from the command line.
    ENV["GIT_CONFIG_GLOBAL"] = testpath/"gitconfig"
    ENV["GIT_CONFIG_NOSYSTEM"] = "1"
    git = ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"]
    system(*git, "init", "-q", "-b", "main")
    (testpath/"a.txt").write "a\nb\nc\n"
    system(*git, "add", "a.txt")
    system(*git, "commit", "-q", "-m", "base")
    system(*git, "checkout", "-q", "-b", "feature")
    (testpath/"a.txt").write "a\nb-feature\nc\n"
    system(*git, "commit", "-q", "-am", "feature")
    system(*git, "checkout", "-q", "main")
    (testpath/"a.txt").write "a\nb-main\nc\n"
    system(*git, "commit", "-q", "-am", "main")
    assert_equal false, quiet_system(*git, "merge", "feature") # stops on the conflict
    assert_match "a.txt", shell_output("#{bin}/lfgit status")
    system bin/"lfgit", "resolve", "--all-incoming"
    assert_equal "a\nb-feature\nc\n", (testpath/"a.txt").read

    # The app, when it was built, is a complete bundle that `lfgit open` can find.
    app = prefix/"LF-Git.app"
    assert_path_exists app/"Contents/MacOS/LF-Git" if app.exist?
  end
end
