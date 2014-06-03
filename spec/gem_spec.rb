# Polisher Gem Specs
#
# Licensed under the MIT license
# Copyright (C) 2013-2014 Red Hat, Inc.

require 'spec_helper'

require 'polisher/gem'

module Polisher
  describe Gem do
    describe "#file_name" do
      it "returns name-version.gem" do
        expected = 'rails-4.0.0.gem'
        Polisher::Gem.new(:name => 'rails', :version => '4.0.0')
                     .file_name.should == expected
      end
    end

    describe "#initialize" do
      it "sets gem attributes" do
        gem = Polisher::Gem.new :name => 'rails',
                                :version => '4.0.0',
                                :deps => ['activesupport', 'activerecord'],
                                :dev_deps => ['rake']
        gem.name.should == 'rails'
        gem.version.should == '4.0.0'
        gem.deps.should == ['activesupport', 'activerecord']
        gem.dev_deps.should == ['rake']
      end
    end

    describe "#ignorable_file?" do
      context "args matches an ignorable file" do
        it "returns true" do
          Polisher::Gem.ignorable_file?('foo.gemspec').should be_true
          Polisher::Gem.ignorable_file?('Gemfile').should be_true
        end
      end

      context "args does not match an ignorable file" do
        it "returns false" do
          Polisher::Gem.ignorable_file?('.rvmra').should be_false
          Polisher::Gem.ignorable_file?('foo.gemspoc').should be_false
        end
      end
    end

    describe "#doc_file?" do
      context "file is on doc files list" do
        it "returns true" do
          Polisher::Gem.doc_file?("CHANGELOG").should be_true
          Polisher::Gem.doc_file?("CHANGELOG.md").should be_true
        end
      end

      context "file is not on doc files list" do
        it "returns false" do
          Polisher::Gem.doc_file?("lib").should be_false
          Polisher::Gem.doc_file?(".yardopts").should be_false
        end
      end
    end

    describe "#has_file_satisfied_by?" do
      context "specified spec file satisfies at least one gem file" do
        it "returns true" do
          spec_file = 'spec_file'
          gem_file  = 'gem_file'
          RPM::Spec.should_receive(:file_satisfies?)
                   .with(spec_file, gem_file)
                   .and_return(true)

          gem = Polisher::Gem.new
          gem.should_receive(:file_paths).and_return([gem_file])
          gem.has_file_satisfied_by?(spec_file).should be_true
        end
      end

      context "specified spec file does not satisfy any gem files" do
        it "returns false" do
          spec_file = 'spec_file'
          gem_file  = 'gem_file'
          RPM::Spec.should_receive(:file_satisfies?)
                   .with(spec_file, gem_file)
                   .and_return(false)

          gem = Polisher::Gem.new
          gem.should_receive(:file_paths).and_return([gem_file])
          gem.has_file_satisfied_by?(spec_file).should be_false
        end
      end
    end

    describe "#local_versions_for" do
      it "returns versions of specified gem in local db"
      it "invokes cb with versions retrieved"
    end

    describe "#parse" do
      it "returns new gem" do
        gem = Polisher::Gem.parse
        gem.should be_an_instance_of(Polisher::Gem)
      end

      it "parses gem from gem spec" do
        spec = Polisher::Test::GEM_SPEC
        gem  = Polisher::Gem.parse(:gemspec => spec[:path])
        gem.name.should     == spec[:name]
        gem.version.should  == spec[:version]
        gem.deps.should     == spec[:deps]
        gem.dev_deps.should == spec[:dev_deps]
      end

      it "parses gem from gem at path"

      it "parses gem from metadata hash" do
        gemj = Polisher::Test::GEM_JSON
        gem = Polisher::Gem.parse gemj[:json]
        gem.name.should     == gemj[:name]
        gem.version.should  == gemj[:version]
        gem.deps.should     == gemj[:deps]
        gem.dev_deps.should == gemj[:dev_deps]
      end
    end

    describe "#remote_versions_for" do
      it "retrieves versions from rubygems.org" do
        curl = Curl::Easy.new
        described_class.should_receive(:client)
                       .at_least(:once).and_return(curl)
        curl.should_receive(:http_get)

        # actual output too verbose, just including bits we need
        curl.should_receive(:body_str)
            .and_return([{'number' => 1.1}, {'number' => 2.2}].to_json)
        described_class.remote_versions_for('polisher').should == [1.1, 2.2]
        curl.url.should == "https://rubygems.org/api/v1/versions/polisher.json"
      end
    end

    describe "#lastest_version_of" do
      it "retrieves latests version of gem available on rubygems.org" do
        described_class.should_receive(:remote_versions_for)
                       .with('polisher')
                       .and_return([2.2, 1.1])
        described_class.latest_version_of('polisher').should == 2.2
      end
    end

    describe "#download_gem" do
      context "gem in GemCache" do
        it "returns GemCache gem" do
          gem = described_class.new
          GemCache.should_receive(:get).with('polisher', '1.1')
                                       .and_return(gem)
          described_class.download_gem('polisher', '1.1').should == gem
        end
      end

      it "uses curl to download gem" do
        GemCache.should_receive(:get).and_return(nil)
        curl = Curl::Easy.new
        described_class.should_receive(:client)
                       .at_least(:once).and_return(curl)
        curl.should_receive(:http_get)
        curl.should_receive(:body_str).and_return('') # stub out body_str

        described_class.download_gem 'polisher', '2.2'
        curl.url.should == "https://rubygems.org/gems/polisher-2.2.gem"
      end

      it "sets gem in gem cache" do
        GemCache.should_receive(:get).and_return(nil)
        curl = Curl::Easy.new
        described_class.should_receive(:client)
                       .at_least(:once).and_return(curl)
        curl.stub(:http_get) # stub out http_get
        curl.should_receive(:body_str).and_return('gem')
        GemCache.should_receive(:set)
                .with('polisher', '1.1', 'gem')
        described_class.download_gem 'polisher', '1.1'
      end

      it "returns downloaded gem binary contents" do
        GemCache.should_receive(:get).and_return(nil)
        curl = Curl::Easy.new
        described_class.should_receive(:client)
                       .at_least(:once).and_return(curl)
        curl.stub(:http_get) # stub out http_get
        curl.should_receive(:body_str).and_return('gem')
        described_class.download_gem('polisher', '1.1').should == 'gem'
      end
    end

    describe "#download_gem_path" do
      it "downloads gem" do
        gem = Polisher::Gem.new
        Polisher::Gem.should_receive(:download_gem)
        gem.downloaded_gem_path
      end

      it "returns gem cache path for gem" do
        # stub out d/l
        gem = Polisher::Gem.new :name => 'rails', :version => '1.0'
        Polisher::Gem.should_receive(:download_gem)
        Polisher::GemCache.should_receive(:path_for).
                           with('rails', '1.0').
                           at_least(:once).
                           and_return('rails_path')
        gem.downloaded_gem_path.should == 'rails_path'
      end
    end

    describe "#gem_path" do
      it "returns specified path" do
        gem = Polisher::Gem.new :path => 'gem_path'
        gem.gem_path.should == 'gem_path'
      end

      context "specified path is null" do
        it "returns downloaded gem path" do
          gem = Polisher::Gem.new
          gem.should_receive(:downloaded_gem_path).and_return('gem_path')
          gem.gem_path.should == 'gem_path'
        end
      end
    end

    describe "#unpack" do
      it "unpacks gem at gem_path into temp dir"
      it "returns tmp dir"
      context "block specified" do
        it "invokes block with tmp dir"
        it "removes tmp dir"
        it "returns nil"
      end
    end

    describe "#file_paths" do
      it "returns list of file paths in gem"
    end

    describe "#retrieve" do
      before(:each) do
        @local_gem = Polisher::Test::LOCAL_GEM
      end

      it "returns gem retrieved from rubygems" do
        gem = Polisher::Gem.retrieve(@local_gem[:name])
        gem.should be_an_instance_of(Polisher::Gem)
        gem.name.should     == @local_gem[:name]
        gem.version.should  == @local_gem[:version]
        gem.deps.should     == @local_gem[:deps]
        gem.dev_deps.should == @local_gem[:dev_deps]
      end
    end

    describe "#versions" do
      it "looks up and returns versions for gemname in polisher version checker"

      context "recursive is true" do
        it "appends versions of gem dependencies to versions list"
        context "dev_deps is true" do
          it "appends versions of gem dev dependencies to versions list"
        end
      end
    end

    describe "#diff" do
      before(:each) do
        @gem1 = Polisher::Gem.new
        @gem2 = Polisher::Gem.new

        @result = AwesomeSpawn::CommandResult.new '', 'diff_out', '', 0
      end

      it "runs diff against unpacked local and other gems and returns output" do
        @gem1.should_receive(:unpack).and_return('dir1')
        @gem2.should_receive(:unpack).and_return('dir2')
        AwesomeSpawn.should_receive(:run).
          with("#{Polisher::Gem::DIFF_CMD} -r dir1 dir2").
          and_return(@result)
        @gem1.diff(@gem2).should == @result.output
      end

      it "removes unpacked gem dirs" do
        @gem1.should_receive(:unpack).and_return('dir1')
        @gem2.should_receive(:unpack).and_return('dir2')
        AwesomeSpawn.should_receive(:run).and_return(@result)
        FileUtils.should_receive(:rm_rf).with('dir1')
        FileUtils.should_receive(:rm_rf).with('dir2')
        # XXX for the GemCache dir cleaning:
        FileUtils.should_receive(:rm_rf).at_least(:once)
        @gem1.diff(@gem2)
      end

      context "error during operations" do
        it "removes unpacked gem dirs" do
          @gem1.should_receive(:unpack).and_return('dir1')
          @gem2.should_receive(:unpack).and_return('dir2')
          AwesomeSpawn.should_receive(:run).
            and_raise(AwesomeSpawn::CommandResultError.new('', ''))
          FileUtils.should_receive(:rm_rf).with('dir1')
          FileUtils.should_receive(:rm_rf).with('dir2')
          FileUtils.should_receive(:rm_rf).at_least(:once)
          @gem1.diff(@gem2)
        end
      end
    end

  end # describe Gem
end # module Polisher
