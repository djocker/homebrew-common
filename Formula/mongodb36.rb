class Mongodb36 < Formula
  include Language::Python::Virtualenv
  desc "High-performance, schema-free, document-oriented database"
  homepage "https://www.mongodb.org/"
  url "https://fastdl.mongodb.org/src/mongodb-src-r3.6.17.tar.gz"
  sha256 "25981810f48fdae7ca43dffe0a797c8111a920975287813bf2f2a0e6f64f6b00"
  version "3.6.17"
  revision 2

#   bottle do
#     cellar :any
#     sha256 "17700a35d1ae69422747abea85cbc9a5cb6c162f75ca00e5e74512e412a15d23" => :mojave
#     sha256 "cd334cae4a0c939b7e39f3e0fc26c05e8f0807d406ec190d4140baeb1e084b38" => :high_sierra
#     sha256 "f3cc1d1f566dcf6a0fbd2b355496e2adb6bba2a98fafde11b345db407e0d3b1f" => :sierra
#   end

  keg_only :versioned_formula

  depends_on "gcc-9" => :build
  depends_on "go@1.11" => :build
  depends_on "pkg-config" => :build
  depends_on "scons30" => :build
#   if OS.mac?
#     depends_on :xcode => ["8.3.2", :build]
#   end

  depends_on "openssl@1.1"
  depends_on "libpcap"
  depends_on "python@2"

   resource "Cheetah" do
     url "https://files.pythonhosted.org/packages/cd/b0/c2d700252fc251e91c08639ff41a8a5203b627f4e0a2ae18a6b662ab32ea/Cheetah-2.4.4.tar.gz"
     sha256 "be308229f0c1e5e5af4f27d7ee06d90bb19e6af3059794e5fd536a6f29a9b550"
   end

   resource "PyYAML" do
     url "https://files.pythonhosted.org/packages/9e/a3/1d13970c3f36777c583f136c136f804d70f500168edc1edea6daa7200769/PyYAML-3.13.tar.gz"
     sha256 "3ef3092145e9b70e3ddd2c7ad59bdd0252a94dfe3949721633e41344de00a6bf"
   end

   resource "typing" do
     url "https://files.pythonhosted.org/packages/bf/9b/2bf84e841575b633d8d91ad923e198a415e3901f228715524689495b4317/typing-3.6.6.tar.gz"
     sha256 "4027c5f6127a6267a435201981ba156de91ad0d1d98e9ddc2aa173453453492d"
   end

  def install
    #ENV.libcxx
    #ENV.cxx11
    #ENV.append "CXXFLAGS", "-std=c++14"

    #ENV['CFLAGS'] = '-I$(brew --prefix libpam)/include'
    #ENV['LDFLAGS'] = '-L$(brew --prefix libpam)/lib'

    ["Cheetah", "PyYAML", "typing"].each do |r|
      resource(r).stage do
        system "python", *Language::Python.setup_install_args(buildpath/"vendor")
      end
    end
    if OS.mac?
        mkdir_p "#{buildpath}/.brew_home/Library/Python/2.7/lib/python/site-packages"
        (buildpath/".brew_home/Library/Python/2.7/lib/python/site-packages/vendor.pth").write <<~EOS
          import site; site.addsitedir("#{buildpath}/vendor/lib/python2.7/site-packages")
        EOS
    else
        mkdir_p "#{buildpath}/.brew_home/.local/lib/python2.7/site-packages"
        (buildpath/".brew_home/.local/lib/python2.7/site-packages/vendor.pth").write <<~EOS
          import site; site.addsitedir("#{buildpath}/vendor/lib/python2.7/site-packages")
        EOS
    end


    # New Go tools have their own build script but the server scons "install"
    # target is still responsible for installing them.

    cd "src/mongo/gotools/src/github.com/mongodb/mongo-tools" do
      inreplace "set_goenv.sh" do |s|
        s.gsub! "$(git describe)", version.to_s
        s.gsub! "$(git rev-parse HEAD)", "homebrew"
      end
      inreplace "build.sh", "#!/bin/sh", "#!/bin/bash"

      ENV["LIBRARY_PATH"] = [Formula["openssl@1.1"].opt_lib, Formula["libpcap"].opt_lib].join(':')
      ENV["CPATH"] = [Formula["openssl@1.1"].opt_include, Formula["libpcap"].opt_include].join(':')
      ENV["GOROOT"] = Formula["go@1.11"].opt_libexec

      system "./build.sh", "ssl"
    end

    (buildpath/"src/mongo-tools").install Dir["src/mongo/gotools/src/github.com/mongodb/mongo-tools/bin/*"]

    ENV["CC"] = "gcc-9"
    ENV["LD"] = "gcc-9"
    ENV["CXX"] = "g++-9"

    if OS.mac?
      args = %W[
        -j#{ENV.make_jobs}
        --build-mongoreplay=true
        --prefix=#{prefix}
        --ssl
        --use-new-tools
        CC=#{ENV.cc}
        CXX=#{ENV.cxx}
        CCFLAGS=-mmacosx-version-min=#{MacOS.version}
        LINKFLAGS=-mmacosx-version-min=#{MacOS.version}
        CCFLAGS=-I#{Formula["openssl@1.1"].opt_include}
        LINKFLAGS=-L#{Formula["openssl@1.1"].opt_lib}
        MONGO_VERSION=#{version}
      ]
    else
      args = %W[
          -j#{ENV.make_jobs}
          --build-mongoreplay=true
          --prefix=#{prefix}
          --ssl
          --use-new-tools
          CC=#{ENV.cc}
          CXX=#{ENV.cxx}
          CCFLAGS=-I#{Formula["openssl@1.1"].opt_include}
          LINKFLAGS=-L#{Formula["openssl@1.1"].opt_lib}
      ]
    end

    args << "--disable-warnings-as-errors"

    system "#{Formula["scons30"].prefix}/bin/scons", "install", *args

    (buildpath/"mongod.conf").write mongodb_conf
    etc.install "mongod.conf"
  end

  def post_install
    (var/"mongodb").mkpath
    (var/"log/mongodb").mkpath
  end

  def mongodb_conf; <<~EOS
    systemLog:
      destination: file
      path: #{var}/log/mongodb/mongo.log
      logAppend: true
    storage:
      dbPath: #{var}/mongodb
    net:
      bindIp: 127.0.0.1
  EOS
  end

  plist_options :manual => "#{HOMEBREW_PREFIX}/opt/mongodb@3.6/bin/mongod --config #{HOMEBREW_PREFIX}/etc/mongod.conf"

  def plist; <<~EOS
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>#{plist_name}</string>
      <key>ProgramArguments</key>
      <array>
        <string>#{opt_bin}/mongod</string>
        <string>--config</string>
        <string>#{etc}/mongod.conf</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <false/>
      <key>WorkingDirectory</key>
      <string>#{HOMEBREW_PREFIX}</string>
      <key>StandardErrorPath</key>
      <string>#{var}/log/mongodb/output.log</string>
      <key>StandardOutPath</key>
      <string>#{var}/log/mongodb/output.log</string>
      <key>HardResourceLimits</key>
      <dict>
        <key>NumberOfFiles</key>
        <integer>4096</integer>
      </dict>
      <key>SoftResourceLimits</key>
      <dict>
        <key>NumberOfFiles</key>
        <integer>4096</integer>
      </dict>
    </dict>
    </plist>
  EOS
  end

  test do
    system "#{bin}/mongod", "--sysinfo"
  end

  if OS.mac?
      patch :p1 do
         url "https://raw.githubusercontent.com/djocker/homebrew-common/master/Patches/mongodb36/macos.patch"
         sha256 "d38ba1a4b11edfc54a46cef9145c02aa027a9fc63afdfcb7f90626af629efeba"
      end
  end

#   def patches
#     "https://raw.githubusercontent.com/djocker/homebrew-common/master/Patches/mongodb36/macos.patch" if OS.mac?
#   end
end
