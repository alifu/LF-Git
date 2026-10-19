class Lfgit < Formula
  desc "Merge tool and Git client for conflicts in files of any size"
  homepage "https://github.com/alifu/LF-Git"
  url "https://github.com/alifu/LF-Git/archive/refs/tags/v0.2.3.tar.gz"
  sha256 "5b37230834f76c429a8c2e310f73afada1468278167cde95c0745934e72dd11c"
  license "MIT"
  head "https://github.com/alifu/LF-Git.git", branch: "main"

  # Built on your own machine, so nothing is quarantined and no Apple Developer account is needed.
  # The app needs Xcode 26 (Swift 6.2 language features); the command line tool needs only a Swift toolchain.
  depends_on xcode: ["26.0", :build]
  depends_on macos: :sonoma

  def install
    # The command line tool needs only a Swift toolchain (Command Line Tools are enough).
    system "swift", "build", "--package-path", "LFCore", "--configuration", "release",
           "--disable-sandbox", "--product", "lfgit"
    bin.install "LFCore/.build/release/lfgit"

    # Ad-hoc signed (CODE_SIGN_IDENTITY=-), which is enough for an app that was built on this Mac.
    xcodebuild "-project", "LF-Git.xcodeproj", "-scheme", "LF-Git", "-configuration", "Release",
               "-derivedDataPath", buildpath/"build", "CLANG_COVERAGE_MAPPING=NO", "ENABLE_CODE_COVERAGE=NO",
               # A sandbox cannot be nested: Homebrew already sandboxes this build, so SwiftPM's manifest
               # sandbox and the sandbox of the Swift macro helper (@Observable, #Preview) must be off.
               "-IDEPackageSupportDisableManifestSandbox=1", "OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox",
               "CODE_SIGN_IDENTITY=-", "ONLY_ACTIVE_ARCH=YES", "build"
    # `lfgit open` looks for LF-Git.app next to bin/, so the app lives in the keg's prefix.
    prefix.install "build/Build/Products/Release/LF-Git.app"
  end

  def caveats
    <<~EOS
      Resolve conflicts from a terminal:
        lfgit install          # use lfgit as `git mergetool` in this repository (--global for all)
        git mergetool

      Open the app from a repository with `lfgit open`. To also find it in Launchpad or Spotlight:
        ln -sf #{opt_prefix}/LF-Git.app /Applications/LF-Git.app
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lfgit --version")

    # A real conflict, resolved from the command line.
    ENV["GIT_CONFIG_GLOBAL"] = testpath/"gitconfig"
    ENV["GIT_CONFIG_NOSYSTEM"] = "1"
    git = %w[git -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false]
    system(*git, "init", "-q", "-b", "main")
    File.write(testpath/"a.txt", "a\nb\nc\n")
    system(*git, "add", "a.txt")
    system(*git, "commit", "-q", "-m", "base")
    system(*git, "checkout", "-q", "-b", "feature")
    File.write(testpath/"a.txt", "a\nb-feature\nc\n")
    system(*git, "commit", "-q", "-am", "feature")
    system(*git, "checkout", "-q", "main")
    File.write(testpath/"a.txt", "a\nb-main\nc\n")
    system(*git, "commit", "-q", "-am", "main")
    refute quiet_system(*git, "merge", "feature") # stops on the conflict
    assert_match "a.txt", shell_output("#{bin}/lfgit status")
    system bin/"lfgit", "resolve", "--all-incoming"
    assert_equal "a\nb-feature\nc\n", (testpath/"a.txt").read

    # The app is a complete bundle that `lfgit open` can find next to bin/.
    assert_path_exists prefix/"LF-Git.app/Contents/MacOS/LF-Git"
  end
end
